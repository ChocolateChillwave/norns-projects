local MusicUtil = require "musicutil"

local Sequence = {}

-- how often a generated note (randomize/evolve) comes out as a short
-- sustained/tied run instead of a lone single-step attack, and how long
-- that run can be
local SUSTAIN_CHANCE = 0.3
local SUSTAIN_MAX_STEPS = 3

-- when link_track is set: how often evolve's replacement note favors a
-- pitch already present in the linked track over a fully independent random
-- pick, and how much randomize's per-note density improves for those pitches
local LINK_EVOLVE_CHANCE = 0.7
local LINK_RANDOMIZE_BIAS = 0.25

function Sequence:new(args)
  local m = setmetatable({}, {__index=Sequence})
  local args = args == nil and {} or args
  for k, v in pairs(args) do m[k] = v end
  m:init()
  return m
end

function Sequence:init()
  self.sequence_max = 16 * 4 -- 16 steps, 4 measures
  -- 7-note scale across 7 octaves. note_lo/note_hi are indices into this pool
  -- (see NOTES.md). capped at 7 octaves rather than pushed further: MusicUtil
  -- silently stops generating once a note would exceed MIDI 127, so scale_full
  -- can end up SHORTER than note_max for a high root_note or a scale with
  -- fewer notes/octave than a 7-note one (a sparser scale needs more octaves,
  -- hence more semitones, to reach the same note count) -- 7 octaves keeps
  -- that from happening for any root_note this script allows (max 36) under a
  -- 7-note/octave scale; sparser scales can still fall short at a high root
  -- note, which is fine as long as nothing indexes scale_full past its real
  -- length (see the nil-guards below and in note_on/formatters).
  self.note_max = 7 * 7
  local scale_names = {}
  for i = 1, #MusicUtil.SCALES do table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name)) end

  self.scale_full = MusicUtil.generate_scale_of_length(24, 1, self.note_max)
  local matrix = {}
  for i = 1, self.sequence_max do
    matrix[i] = {}
    for j = 1, self.note_max do matrix[i][j] = 0 end
  end
  local matrices = {}
  for k = 1, 16 do
    matrices[k] = {}
    for i = 1, self.sequence_max do
      matrices[k][i] = {}
      for j = 1, self.note_max do matrices[k][i][j] = 0 end
    end
  end
  self.matrices = matrices
  self.matrix_sequence_m = {}
  for i = 1, 16 do self.matrix_sequence_m[i] = 0 end
  self.matrix_sequence_m[1] = 1
  self.matrix_sequence_cur = 1
  self.matrix_sequence_ind = 1
  self.matrix_sequence_step = 0

  self.matrix = matrix
  self.notes_to_ghost = {}
  self.step = 1
  self.state = 0 -- 0=sequence, 1=chain
  self.step_last = 1
  self.step_next = 1
  self.movement = 1
  self.note_limit = self.note_max
  self.note_offset = 21
  self.notes_on = {}
  -- live grid-keyboard holds (see note_on_live/note_off_live and the
  -- sustain check in update()) -- keyed by resolved matrix note_index
  self.held_notes = {}
  self.held_start_step = {}
  self.step_time_last = clock.get_beats()
  self.step_time_before_last = self.step_time_last
  self.midi_devices = {}
  self.beat = 1
  self.last_beat = 1
  for i = 1, #midi.vports do
    local long_name = midi.vports[i].name
    local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
    table.insert(self.midi_devices, i .. ": " .. short_name)
  end

  self.matrix_previous = 1

  -- scale_full can be shorter than note_max (see the comment on note_max
  -- above) -- guards note_lo/note_hi's formatters against indexing past its
  -- real end
  local function note_name_at(index)
    local note = self.scale_full[index]
    return note and MusicUtil.note_num_to_name(note, true) or "--"
  end

  -- setup parameters
  local params_menu = {
    {
      id="division",
      name="clock division",
      min=1,
      max=#self.divisions,
      exp=false,
      div=1,
      default=11, -- "1/16", matching pitter-patter's original musical default
      formatter=function(param)
        return self.divisions_strings[param:get()]
      end
    }, {
      id="sequence",
      name="sequence",
      min=1,
      max=7,
      exp=false,
      div=1,
      default=1,
      action=function(k)
        -- save current matrix 
        for i = 1, self.sequence_max do
          for j = 1, self.note_max do self.matrices[self.matrix_previous][i][j] = self.matrix[i][j] end
        end
        -- load new matrix
        for i = 1, self.sequence_max do
          for j = 1, self.note_max do self.matrix[i][j] = self.matrices[k][i][j] end
        end
        self.matrix_previous = k
      end
    }, {
      id="mute",
      name="mute",
      min=0,
      max=1,
      exp=false,
      div=1,
      default=0,
      formatter=function(param)
        return param:get() == 1 and "muted" or "unmuted"
      end
    }, {
      id="poly",
      name="polyphony",
      min=0,
      max=1,
      exp=false,
      div=1,
      default=0, -- mono
      formatter=function(param)
        return param:get() == 1 and "poly" or "mono"
      end
    }, {
      id="clear",
      name="clear",
      min=0,
      max=1,
      exp=false,
      div=1,
      default=0,
      formatter=function(param)
        return param:get() == 0 and "turn e3" or "cleared!"
      end,
      action=function(v)
        if v == 1 then self:clear() end
        clock.run(function()
          clock.sleep(1)
          self:set_param("clear", 0)
        end)
      end
    }, {
      id="randomize",
      name="randomize",
      min=0,
      max=1,
      exp=false,
      div=1,
      default=0,
      formatter=function(param)
        return param:get() == 0 and "turn e3" or "randomized!"
      end,
      action=function(v)
        if v == 1 then
          self:clear()
          local density = math.random(90, 95) / 100
          local note_lo, note_hi = self:get_param("note_lo"), self:get_param("note_hi")
          -- linked (opt-in, off by default): pitches the linked track is
          -- already using get a lower (easier-to-hit) density threshold, so
          -- the result leans toward "harmonizing" with it rather than every
          -- pitch in range being equally likely
          local linked = self:linked_note_set()
          for j = note_lo, note_hi do
            local j_density = density
            if linked and linked[j] then
              j_density = math.max(0.3, density - LINK_RANDOMIZE_BIAS)
            end
            -- a while-loop (not a plain for) so a step consumed by a
            -- sustained run's tail isn't immediately re-rolled as its own
            -- attack right after
            local i = 1
            while i <= self.sequence_max do
              if math.random() > j_density then
                self.matrix[i][j] = 1
                local run = 0
                if math.random() < SUSTAIN_CHANCE then run = math.random(1, SUSTAIN_MAX_STEPS) end
                for k = 1, run do
                  if i + k > self.sequence_max then break end
                  self.matrix[i + k][j] = 2
                end
                i = i + run + 1
              else
                i = i + 1
              end
            end
          end
        end
        clock.run(function()
          clock.sleep(1)
          self:set_param("randomize", 0)
        end)
      end
    }, {
      id="evolve",
      name="evolve",
      min=0,
      max=1,
      exp=false,
      div=1,
      default=0,
      formatter=function(param)
        return param:get() == 0 and "no" or "yes"
      end
    }, {
      id="link_track",
      name="link generation to",
      min=0,
      max=4,
      exp=false,
      div=1,
      default=0,
      formatter=function(param)
        local v = param:get()
        return v == 0 and "off" or ("track " .. v)
      end
    }, {
      id="scale",
      name="scale",
      min=1,
      max=#scale_names,
      exp=false,
      div=1,
      default=1,
      formatter=function(param)
        return scale_names[param:get()]
      end,
      action=function(v)
        self.scale_full = MusicUtil.generate_scale_of_length(self:get_param("root_note"), self:get_param("scale"),
                                                             self.note_max)
      end
    }, {
      id="root_note",
      name="root note",
      min=12,
      max=36,
      exp=false,
      div=1,
      default=24,
      formatter=function(param)
        return MusicUtil.note_num_to_name(param:get(), true)
      end,
      action=function(v)
        self.scale_full = MusicUtil.generate_scale_of_length(self:get_param("root_note"), self:get_param("scale"),
                                                             self.note_max)
      end
    }, {
      id="direction",
      name="direction",
      min=1,
      max=5,
      exp=false,
      div=1,
      default=1, -- forward
      formatter=function(param)
        local directions = {"forward", "backward", "ping pong", "random", "brownian"}
        return directions[param:get()]
      end
    }, {
      id="limit",
      name="limit",
      min=2,
      max=self.sequence_max,
      exp=false,
      div=1,
      default=16,
      formatter=function(param)
        return math.floor(param:get()) .. " steps"
      end
    }, {
      id="probability",
      name="probability",
      min=0,
      max=1,
      exp=false,
      div=0.01,
      default=1.0,
      formatter=function(param)
        return param:get() * 100 .. "%"
      end
    }, {
      id="note_lo",
      name="note range lo",
      min=1,
      max=self.note_max,
      exp=false,
      div=1,
      default=1,
      formatter=function(param) return note_name_at(param:get()) end,
      action=function(v) if v > self:get_param("note_hi") then self:set_param("note_hi", v) end end
    }, {
      id="note_hi",
      name="note range hi",
      min=1,
      max=self.note_max,
      exp=false,
      div=1,
      default=self.note_max,
      formatter=function(param) return note_name_at(param:get()) end,
      action=function(v) if v < self:get_param("note_lo") then self:set_param("note_lo", v) end end
    }, {
      id="midi_out_device",
      name="midi out device",
      min=1,
      max=#self.midi_devices,
      exp=false,
      div=1,
      default=1,
      formatter=function(param)
        return self.midi_devices[param:get()]
      end,
      action=function(value)
        local device = midi.connect(value)
        if device then
          print("midi device connected: " .. device.name)
          self.midi_out_device = device
        end
      end
    }, {
      id="midi_out_channel",
      name="midi out channel",
      min=1,
      max=16,
      exp=false,
      div=1,
      default=1, -- all tracks default to ch 1; set per-track from PARAMETERS/arc if you want them split out
      formatter=function(param)
        return "ch " .. math.floor(param:get())
      end
    }
  }

  params:add_group("TRACK " .. self.id, #params_menu)
  for _, pram in ipairs(params_menu) do
    pram.id = "sequence" .. self.id .. "_" .. pram.id
    params:add{
      type="control",
      id=pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min, pram.max, pram.exp and "exp" or "lin", pram.div, pram.default,
                                  pram.unit or "", pram.div / (pram.max - pram.min)),
      formatter=pram.formatter
    }
    if pram.action then params:set_action(pram.id, pram.action) end
    if pram.hide then params:hide(pram.id) end
  end
end

function Sequence:marshal()
  local data = {}
  data.matrix = self.matrix
  data.matrix_sequence_m = self.matrix_sequence_m
  data.matrix_sequence_cur = self.matrix_sequence_cur
  data.matrix_sequence_ind = self.matrix_sequence_ind
  data.matrices = self.matrices
  data.step = self.step
  data.movement = self.movement
  data.notes_to_ghost = self.notes_to_ghost
  data.note_offset = self.note_offset
  return data
end

function Sequence:unmarshal(data)
  self.matrix = data.matrix
  self.matrix_sequence_m = data.matrix_sequence_m
  self.matrix_sequence_cur = data.matrix_sequence_cur
  self.matrix_sequence_ind = data.matrix_sequence_ind
  self.matrices = data.matrices
  self.step = data.step
  self.movement = data.movement
  self.notes_to_ghost = data.notes_to_ghost
  self.note_offset = data.note_offset
end

function Sequence:reset_timer()
  self.step_time_last = clock.get_beats()
  self.step_time_before_last = self.step_time_last
  self.step = 1
end

function Sequence:delta_param(v, d)
  params:delta("sequence" .. self.id .. "_" .. v, d)
end

function Sequence:get_param(v)
  return params:get("sequence" .. self.id .. "_" .. v)
end

function Sequence:set_param(v, value)
  params:set("sequence" .. self.id .. "_" .. v, value)
end

function Sequence:get_param_str(v)
  return params:string("sequence" .. self.id .. "_" .. v)
end

function Sequence:step_peek(step, movement)
  if self:get_param("direction") == 1 then -- forward
    movement = 1
    step = step + 1
    while step > self:get_param("limit") do step = step - self:get_param("limit") end
  elseif self:get_param("direction") == 2 then -- backward
    movement = -1
    step = step - 1
    while step < 1 do step = step + self:get_param("limit") end
  elseif self:get_param("direction") == 3 then -- ping pong
    step = step + movement
    if step > self:get_param("limit") then
      step = self:get_param("limit") - 1
      movement = -1
    end
    if step < 1 then
      step = 2
      movement = 1
    end
  elseif self:get_param("direction") == 4 then -- random
    step = math.random(1, self:get_param("limit"))
  elseif self:get_param("direction") == 5 then -- brownian
    -- brownian: random walk of -1/0/+1, wrapped (not clamped) at the loop
    -- boundary so it doesn't pile up at the edges over time
    local limit = self:get_param("limit")
    step = step + math.random(0, 2) - 1
    while step > limit do step = step - limit end
    while step < 1 do step = step + limit end
  end
  return step, movement
end

function Sequence:left_step(step)
  local limit = self:get_param("limit")
  return step == 1 and limit or step - 1
end

function Sequence:right_step(step)
  local limit = self:get_param("limit")
  return step == limit and 1 or step + 1
end

function Sequence:promote_right_tie(step, note_index)
  local right_step = self:right_step(step)
  if self.matrix[right_step][note_index] == 2 then self.matrix[right_step][note_index] = 1 end
end

function Sequence:clear_note(step, note_index)
  self.matrix[step][note_index] = 0
  self:promote_right_tie(step, note_index)
end

function Sequence:toggle_cell(step, note_index)
  if self.matrix[step][note_index] == 0 then
    self.matrix[step][note_index] = 1
  elseif self.matrix[step][note_index] == 1 and self.matrix[self:left_step(step)][note_index] > 0 then
    self.matrix[step][note_index] = 2
  else
    self:clear_note(step, note_index)
  end
end

-- note_data is {note, note_index, device, channel} -- device/channel captured
-- at note-on time so a mid-note change to the track's midi out device or
-- channel (shift+E1, or the channel param) can't strand the note on the
-- device/channel it was actually sent to.
function Sequence:note_off(note_data)
  local note = note_data[1]
  local device = note_data[3]
  local channel = note_data[4]
  if device then device:note_off(note, 0, channel) end
end

-- returns the set of note_index values currently populated anywhere in the
-- linked track's matrix (whole buffer, not just the active loop -- a wider
-- "what pitches is that track using" read than just its current step), or
-- nil if not linked / the linked track has nothing in it. `sequencers` is
-- the global table polyphasic.lua builds all 4 tracks into -- read directly
-- rather than threading a lookup through the constructor, the same way
-- params/midi/clock are already used as ambient globals throughout this file.
-- randomize/evolve use this to bias generation toward "harmonizing" with
-- another track instead of picking uniformly at random -- opt-in via
-- link_track, off (nil) by default so it never changes existing behavior
-- unless asked for.
function Sequence:linked_note_set()
  local link = self:get_param("link_track")
  if link == 0 then return nil end
  local other = sequencers and sequencers[link]
  if other == nil or other == self then return nil end
  local set = nil
  for i = 1, other.sequence_max do
    for j = 1, other.note_max do
      if other.matrix[i][j] > 0 then
        set = set or {}
        set[j] = true
      end
    end
  end
  return set
end

function Sequence:update(division, beat)
  if division ~= self.divisions[self:get_param("division")] then do return end end
  -- if generating then remove a random note and replace with a new note.
  -- scoped to the currently active 1..limit steps, not the full sequence_max
  -- buffer -- evolve should only touch what's actually playing (mutating a
  -- banked/inactive step would be both inaudible and, for clear_note's tie
  -- promotion, out of range of what left_step/right_step expect).
  if self:get_param("evolve") == 1 and math.random() > 0.9 then
    local limit = self:get_param("limit")
    local note_lo, note_hi = self:get_param("note_lo"), self:get_param("note_hi")
    -- find all the steps
    local steps = {}
    for i = 1, limit do
      for j = note_lo, note_hi do if self.matrix[i][j] > 0 then table.insert(steps, {i, j}) end end
    end
    if #steps > 0 then
      local random_step = steps[math.random(1, #steps)]
      self:clear_note(random_step[1], random_step[2])
      local random_i = math.random(1, limit)

      -- linked (opt-in, off by default): favor a pitch the linked track is
      -- already using over a fully independent pick, when one's in range
      local random_j = nil
      local linked = self:linked_note_set()
      if linked and math.random() < LINK_EVOLVE_CHANCE then
        local candidates = {}
        for note_index in pairs(linked) do
          if note_index >= note_lo and note_index <= note_hi then
            table.insert(candidates, note_index)
          end
        end
        if #candidates > 0 then random_j = candidates[math.random(1, #candidates)] end
      end
      random_j = random_j or math.random(note_lo, note_hi)

      self.matrix[random_i][random_j] = 1
      if math.random() < SUSTAIN_CHANCE then
        local run = math.random(1, SUSTAIN_MAX_STEPS)
        for k = 1, run do
          if random_i + k > limit then break end
          self.matrix[random_i + k][random_j] = 2
        end
      end
    end
  end
  if self.step == self:get_param("limit") then
    self.matrix_sequence_step = self.matrix_sequence_step + 1
    local seq = {}
    for i = 1, 16 do if self.matrix_sequence_m[i] > 0 then table.insert(seq, {self.matrix_sequence_m[i], i}) end end
    if #seq == 0 then
      self.matrix_sequence_cur = 1
      self.matrix_sequence_ind = 1
    else
      local x = (self.matrix_sequence_step - 1) % #seq + 1
      self.matrix_sequence_cur = seq[x][1]
      self.matrix_sequence_ind = seq[x][2]
    end
    self:set_param("sequence", self.matrix_sequence_cur)
  end
  self.last_beat = self.beat
  self.beat = beat and beat or self.last_beat + 1
  self.step_time_before_last = self.step_time_last
  self.step_time_last = clock.get_beats()
  local step_previous = self.step_last
  self.step_last = self.step
  self.step, self.movement = self:step_peek(self.step, self.movement)

  -- live grid-keyboard hold: as long as a note is still held (see
  -- note_on_live), tie it through every new step the sequencer advances to
  -- -- skipping its own start step guards against a direction that can
  -- revisit it (ping-pong/random/brownian) turning the attack into a tie
  for note_index in pairs(self.held_notes) do
    if self.step ~= self.held_start_step[note_index] then
      self.matrix[self.step][note_index] = 2
    end
  end

  -- check which notes are activated
  local notes = {}
  local notes_sustained = {}
  local notes_on = {}
  local can_tie = step_previous == self:left_step(self.step_last)
  for _, note_data in ipairs(self.notes_on) do
    if note_data[2] ~= nil then notes_on[note_data[2]] = note_data end
  end
  local note_lo, note_hi = self:get_param("note_lo"), self:get_param("note_hi")
  for i = note_lo, note_hi do
    if self.matrix[self.step_last][i] == 1 then
      table.insert(notes, i)
    elseif self.matrix[self.step_last][i] == 2 and can_tie and notes_on[i] ~= nil and self:get_param("mute") == 0 then
      notes_sustained[i] = true
    end
  end

  -- mono: at most one note at a time. a stacked chord in the same step only
  -- keeps its first note, and any brand-new note chokes whatever's still
  -- held/tied rather than layering on top of it.
  if self:get_param("poly") == 0 then
    if #notes > 1 then notes = {notes[1]} end
    if #notes > 0 then notes_sustained = {} end
  end

  -- turn off previous notes
  local notes_held = {}
  for _, note_data in ipairs(self.notes_on) do
    if note_data[2] ~= nil and notes_sustained[note_data[2]] then
      table.insert(notes_held, note_data)
    else
      self:note_off(note_data)
    end
  end

  -- emit those notes
  self.notes_on = notes_held
  for i, note in pairs(notes) do self:note_on(note) end

  -- check if there are notes to ghost
  if #self.notes_to_ghost > 0 then
    local note_to_ghost = self.notes_to_ghost[math.random(1, #self.notes_to_ghost)]
    if self.matrix[note_to_ghost[1]][note_to_ghost[2]] > 0 then
      self:clear_note(note_to_ghost[1], note_to_ghost[2])
      for i, v in ipairs(self.notes_to_ghost) do
        if v[1] == note_to_ghost[1] and v[2] == note_to_ghost[2] then
          table.remove(self.notes_to_ghost, i)
          break
        end
      end
    end
  end
end

-- velocity is drawn from self.get_velocity(self) (injected at construction
-- -- shared global lo/hi range + curve shape in the main script; called
-- with self so a curve can read this track's own current step/limit).
-- self.on_note(note_index, velocity), also injected, drives the orb display.
function Sequence:note_on(note_index)
  if self:get_param("mute") == 1 then do return end end
  if self:get_param("probability") < math.random() then do return end end
  local note = self.scale_full[note_index]
  -- scale_full can be shorter than note_max (MusicUtil stops generating past
  -- MIDI 127 -- see note_max's comment in init()), so a high note_lo/note_hi
  -- or note_offset can point past its real end
  if note == nil then do return end end
  local velocity = self.get_velocity and self.get_velocity(self) or 100
  if self.midi_out_device then
    local channel = self:get_param("midi_out_channel")
    table.insert(self.notes_on, {note, note_index, self.midi_out_device, channel})
    self.midi_out_device:note_on(note, velocity, channel)
  end
  if self.on_note then self.on_note(note_index, velocity) end
end

-- send note_off for anything still sounding (device/channel it was actually
-- triggered on) and stop tracking it. call on script quit so a note that's
-- mid-decay or mid-tie doesn't ring forever.
function Sequence:panic()
  for _, note_data in ipairs(self.notes_on) do self:note_off(note_data) end
  self.notes_on = {}
end

function Sequence:clear_visible()
  for i = 1, self.sequence_max do
    for row = 1, 7 do
      local note_index = (row + self.note_offset - 1) % self.note_limit + 1
      self.matrix[i][note_index] = 0
    end
  end
end

function Sequence:clear()
  for i = 1, self.sequence_max do
    self.matrix[i] = {}
    for j = 1, self.note_max do self.matrix[i][j] = 0 end
  end
end

function Sequence:toggle_from_note(note)
  local closest_index = 1
  local closest_distance = 1000
  for i, v in ipairs(self.scale_full) do
    local distance = math.abs(v - note)
    if distance < closest_distance then
      closest_distance = distance
      closest_index = i
    end
  end
  self:toggle_cell(self.step, closest_index)
  self.note_offset = math.floor((closest_index) / 7) * 7
end

function Sequence:toggle_pos(step, row)
  local note_index = (row + self.note_offset - 1) % self.note_limit + 1
  self:toggle_cell(step, note_index)
end

-- sets a deterministic sustained note across [step_lo, step_hi] at
-- note_index: an attack at step_lo, tied continuation for every step after
-- it. unlike toggle_cell this isn't a toggle -- it overwrites whatever was
-- there, since the point is "make this whole span one held note."
function Sequence:sustain_range(step_lo, step_hi, note_index)
  self.matrix[step_lo][note_index] = 1
  for s = step_lo + 1, step_hi do self.matrix[s][note_index] = 2 end
end

function Sequence:sustain_pos(step_lo, step_hi, row)
  local note_index = (row + self.note_offset - 1) % self.note_limit + 1
  self:sustain_range(step_lo, step_hi, note_index)
end

-- live grid-keyboard entry (bottom row, "play it like a MIDI controller"):
-- press writes an attack at whatever step is current right now; holding it
-- down ties it through subsequent steps as the sequencer advances (see the
-- hold check in update()), so it sustains for as long as the key is held
-- instead of a single-step blip. release just stops future ties -- it
-- doesn't erase anything already written.
function Sequence:note_on_live(note_index)
  local resolved = self:get_note_index(note_index)
  self.held_notes[resolved] = true
  self.held_start_step[resolved] = self.step
  self.matrix[self.step][resolved] = 1
end

function Sequence:note_off_live(note_index)
  local resolved = self:get_note_index(note_index)
  self.held_notes[resolved] = nil
  self.held_start_step[resolved] = nil
end

function Sequence:get_note_index(note_index)
  return (note_index + self.note_offset - 1) % self.note_limit + 1
end

function Sequence:get_note_from_index(note_index)
  return self.scale_full[self:get_note_index(note_index)]
end

function Sequence:clear_all()
  for i = 1, self:get_param("limit") do for j = 1, self.note_limit do self.matrix[i][j] = 0 end end
end

function Sequence:ghost_section(step_start, step_end, note_start, note_end)
  for i = step_start, step_end do
    for j = note_start, note_end do
      if self.matrix[i][j] > 0 then
        local has_note = false
        for k, v in ipairs(self.notes_to_ghost) do
          if v[1] == i and v[2] == j then
            has_note = true
            break
          end
        end
        if not has_note then table.insert(self.notes_to_ghost, {i, j}) end
      end
    end
  end
end

return Sequence