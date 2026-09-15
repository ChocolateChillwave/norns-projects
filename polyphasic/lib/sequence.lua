local MusicUtil = require "musicutil"

local Sequence = {}

function Sequence:new(args)
  local m = setmetatable({}, {__index=Sequence})
  local args = args == nil and {} or args
  for k, v in pairs(args) do m[k] = v end
  m:init()
  return m
end

function Sequence:init()
  self.sequence_max = 16 * 4 -- 16 steps, 4 measures
  self.note_max = 7 * 6 -- 7-note scale across 6 octaves
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
          for i = 1, self.sequence_max do
            for j = util.round(self.note_max * 1 / 4), util.round(self.note_max * 3 / 4) do
              if math.random() > density then matrix[i][j] = 1 end
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
      max=4,
      exp=false,
      div=1,
      default=4,
      formatter=function(param)
        local directions = {"backward", "ping pong", "random", "forward"}
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
      default=self.id, -- tracks default to channel 1-4 respectively rather than all colliding on ch 1
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
  if self:get_param("direction") == 4 then
    movement = 1
    step = step + 1
    while step > self:get_param("limit") do step = step - self:get_param("limit") end
  elseif self:get_param("direction") == 1 then
    movement = -1
    step = step - 1
    while step < 1 do step = step + self:get_param("limit") end
  elseif self:get_param("direction") == 2 then
    step = step + movement
    if step > self:get_param("limit") then
      step = self:get_param("limit") - 1
      movement = -1
    end
    if step < 1 then
      step = 2
      movement = 1
    end
  elseif self:get_param("direction") == 3 then
    step = math.random(1, self:get_param("limit"))
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

-- note_data is {note, note_index}
function Sequence:note_off(note_data)
  local note = note_data[1]
  if self.midi_out_device then
    self.midi_out_device:note_off(note, 0, self:get_param("midi_out_channel"))
  end
end

function Sequence:update(division, beat)
  if division ~= self.divisions[self:get_param("division")] then do return end end
  -- if generating then remove a random note and replace with a new note
  if self:get_param("evolve") == 1 and math.random() > 0.9 then
    -- find all the steps
    local steps = {}
    for i = 1, self.sequence_max do
      for j = 1, self.note_max do if self.matrix[i][j] > 0 then table.insert(steps, {i, j}) end end
    end
    if #steps > 0 then
      local random_step = steps[math.random(1, #steps)]
      self:clear_note(random_step[1], random_step[2])
      local random_i = math.random(1, self.sequence_max)
      local random_j = math.random(1, self.note_max)
      self.matrix[random_i][random_j] = 1
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
  -- check which notes are activated
  local notes = {}
  local notes_sustained = {}
  local notes_on = {}
  local can_tie = step_previous == self:left_step(self.step_last)
  for _, note_data in ipairs(self.notes_on) do
    if note_data[2] ~= nil then notes_on[note_data[2]] = note_data end
  end
  for i = 1, self.note_limit do
    if self.matrix[self.step_last][i] == 1 then
      table.insert(notes, i)
    elseif self.matrix[self.step_last][i] == 2 and can_tie and notes_on[i] ~= nil and self:get_param("mute") == 0 then
      notes_sustained[i] = true
    end
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

-- velocity is drawn from self.get_velocity() (injected at construction —
-- shared global lo/hi range in the main script). self.on_note(note_index,
-- velocity), also injected, drives the orb display.
function Sequence:note_on(note_index)
  if self:get_param("mute") == 1 then do return end end
  if self:get_param("probability") < math.random() then do return end end
  local note = self.scale_full[note_index]
  local velocity = self.get_velocity and self.get_velocity() or 100
  table.insert(self.notes_on, {note, note_index})
  if self.midi_out_device then
    self.midi_out_device:note_on(note, velocity, self:get_param("midi_out_channel"))
  end
  if self.on_note then self.on_note(note_index, velocity) end
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

function Sequence:toggle_note(note_index)
  local step = self.step
  local note_index = self:get_note_index(note_index)
  self:toggle_cell(step, note_index)
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