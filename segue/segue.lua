-- segue
-- v0.2.0
-- follow-action drum sequencer
-- for the Elektron Analog Rytm
-- MIDI out only -- see MANUAL.md
--
-- eight lanes, each one a column of
-- eight patterns with its own
-- playhead, length and follow action.
-- launch a pattern and the lane moves
-- to it; leave it alone and its follow
-- action moves it for you, on its own
-- clock, in the middle of a bar if
-- that is what you asked for.
--
-- the point is the switch itself:
--   cut       restart from step 1
--   legato    carry the playhead over,
--             so the beat continues
--             rather than restarting
--   xfade     blend the two patterns
--             over a window
--   handover  voices change one at a
--             time, anchor voice last
--
-- LAUNCH grid (8x8):
--   columns are lanes, rows are the
--   eight pattern slots. press to
--   launch -- it lands on the next
--   quantize boundary. the lit cell
--   fades as its loop plays out.
--
-- FX grid (right half of a 128, a
-- second grid, or hold K1 on a 64):
--   1 beat repeat (hold)
--   2 scenes
--   3 lane mute
--   4 lane solo (hold)
--   5 lane follow on/off
--   6 lane roll (hold)
--   7 transition / quant / morph
--   8 play, reseed, follow all, store
--     scene (hold), panic, step edit
--
-- step edit (FX row 8 col 6) turns the
-- LAUNCH grid into a step editor for
-- the selected pattern: rows are that
-- lane's voices, columns eight steps,
-- row 7 pages, row 8 exits / clears.
-- press a step repeatedly to cycle
-- rest / normal / accent / ghost.
--
-- arc (its own button changes page):
--   PLAY   division / swing /
--          probability / level
--   MORPH  transition / morph steps /
--          launch quant / lane
--
-- E1 lane   E2 slot   E3 edit
-- K1 shift (+E3 picks the field)
-- K2 launch   K3 play/stop

local Pattern = include("segue/lib/pattern")
local Lane = include("segue/lib/lane")
local Library = include("segue/lib/library")
local Voices = include("segue/lib/voices")
local GridUI = include("segue/lib/gridui")
local GArc = include("segue/lib/garc")

local NUM_LANES = 8
local FPS = 15

-- beat repeat divisions, in ticks. capped at half a bar -- the capture
-- buffer is preallocated to the largest of these and a longer "repeat"
-- stops being a stutter and starts being a loop.
local REPEAT_TICKS = {48, 24, 16, 12, 8, 6, 4, 3}
local REPEAT_NAMES = {"1/2", "1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32"}
local REPEAT_MAX = 48

local lanes = {}
local voices_out
local gridui
local garc_
local midi_dev

local playing = false
local tick = 0
local clock_id
local redraw_id

local sel_lane = 1
local sel_slot = 1
local field = 1
local shift = false

local scenes = {}
local scene_arm = false
local solo = {}
local any_solo = false

-- beat repeat
local rep_col = nil        -- which row-1 button is held
local rep_div = 0
local rep_t0 = 0
local rep_recording = false
local rep_buf = {}

local screen_dirty = true

-- forward declaration: the transport starts the clock coroutine, which
-- calls the tick, which is defined further down once the lanes and the
-- repeat buffer it works on are in scope
local do_tick

local function pround(id) return util.round(params:get(id)) end

---------------------------------------------------------------- transport

-- norns streams the MIDI clock itself (PARAMETERS > CLOCK > "midi out",
-- per port) -- all a script has to add is start/stop, so an external box
-- follows this script's transport rather than free-running on the ticks.
-- same approach as polyphasic.
local function send_transport(msg)
  for i = 1, 16 do
    if params:get("clock_midi_out_" .. i) == 1 then
      midi.vports[i]:send({type = msg})
    end
  end
end

local function all_reset()
  tick = 0
  for i = 1, NUM_LANES do lanes[i]:reset() end
end

local function stop_playing()
  if not playing then return end
  playing = false
  if clock_id then clock.cancel(clock_id) clock_id = nil end
  if voices_out then voices_out:panic() end
  send_transport("stop")
  screen_dirty = true
end

local function start_playing()
  if playing then return end
  all_reset()
  playing = true
  send_transport("start")
  clock_id = clock.run(function()
    while true do
      clock.sync(1 / Lane.PPQN)
      do_tick()
    end
  end)
  screen_dirty = true
end

local function toggle_play()
  if playing then stop_playing() else start_playing() end
end

---------------------------------------------------------------- the tick

local out_buf = {}
for i = 1, 32 do out_buf[i] = {voice = 0, vel = 0} end

local function rep_slot(offset)
  local s = rep_buf[offset]
  if s == nil then
    s = {n = 0}
    for i = 1, 24 do s[i] = {voice = 0, vel = 0} end
    rep_buf[offset] = s
  end
  return s
end

local function rep_engage(col)
  rep_col = col
  rep_div = REPEAT_TICKS[col]
  rep_t0 = tick
  rep_recording = true
  for o = 0, rep_div - 1 do rep_slot(o).n = 0 end
end

local function rep_release()
  rep_col = nil
  rep_div = 0
  rep_recording = false
end

do_tick = function()
  -- release everything trigged on the previous tick before anything new
  voices_out:flush()

  local quant = Lane.QUANT_TICKS[pround("launch_quant")]
  local n_out = 0
  local switched = false

  for i = 1, NUM_LANES do
    local l = lanes[i]
    local n = l:tick(tick, quant)
    if l.switched then switched = true end
    if n > 0 and ((not any_solo) or solo[i]) then
      for h = 1, n do
        if n_out < 32 then
          n_out = n_out + 1
          out_buf[n_out].voice = l.hits[h].voice
          out_buf[n_out].vel = l.hits[h].vel
        end
      end
    end
  end

  -- beat repeat. the first pass through the window records what the lanes
  -- would have played and passes it through; after that the lanes keep
  -- running (so the timeline underneath is still correct when the button is
  -- let go) but their output is dropped in favour of the captured slice.
  if rep_col then
    local elapsed = tick - rep_t0
    if rep_recording and elapsed >= rep_div then rep_recording = false end
    local offset = elapsed % rep_div
    if rep_recording then
      local s = rep_slot(offset)
      s.n = 0
      for i = 1, n_out do
        if i <= 24 then
          s.n = i
          s[i].voice = out_buf[i].voice
          s[i].vel = out_buf[i].vel
        end
      end
    else
      local s = rep_slot(offset)
      n_out = 0
      for i = 1, s.n do
        n_out = n_out + 1
        out_buf[n_out].voice = s[i].voice
        out_buf[n_out].vel = s[i].vel
      end
    end
  end

  local choke = params:get("hat_choke") > 0.5
  for i = 1, n_out do
    local v = out_buf[i].voice
    -- a closed hat cuts an open one, if asked for. the Rytm has no choke
    -- group of its own across tracks, so it has to happen here.
    if choke and v == 9 then voices_out:release_voice(10) end
    voices_out:trig(v, out_buf[i].vel)
  end

  tick = tick + 1
  if switched or n_out > 0 then screen_dirty = true end
end

---------------------------------------------------------------- lanes

local function lane_param(i, name) return "lane_" .. i .. "_" .. name end

local function sync_lane_from_params(i)
  local l = lanes[i]
  l.div = pround(lane_param(i, "div"))
  l.swing = pround(lane_param(i, "swing"))
  l.prob = params:get(lane_param(i, "prob"))
  l.level = params:get(lane_param(i, "level"))
  l.mute = params:get(lane_param(i, "mute")) > 0.5
  l.follow_on = params:get(lane_param(i, "follow")) > 0.5
  l.transition = pround(lane_param(i, "trans"))
  l.morph_steps = pround(lane_param(i, "morph"))
end

-- the other direction, used after loading saved data: the lane object is
-- the thing that was restored, so the params have to be brought up to match
-- it or the next param touch would stomp the loaded value back.
local function push_lane_to_params(i)
  local l = lanes[i]
  params:set(lane_param(i, "div"), l.div)
  params:set(lane_param(i, "swing"), l.swing)
  params:set(lane_param(i, "prob"), l.prob)
  params:set(lane_param(i, "level"), l.level)
  params:set(lane_param(i, "mute"), l.mute and 1 or 0)
  params:set(lane_param(i, "follow"), l.follow_on and 1 or 0)
  params:set(lane_param(i, "trans"), l.transition)
  params:set(lane_param(i, "morph"), l.morph_steps)
end

local function reseed()
  for i = 1, NUM_LANES do
    local l = lanes[i]
    if l.follow_on then
      local target = l:_resolve(6) -- any
      if target then l:launch(target) end
    end
  end
  screen_dirty = true
end

local function scene_launch(n)
  local s = scenes[n]
  if s == nil then return end
  for i = 1, NUM_LANES do
    if s[i] then
      if playing then lanes[i]:launch(s[i])
      else lanes[i]:commit(s[i], Lane.TRANS_CUT) end
    end
  end
  screen_dirty = true
end

local function scene_store(n)
  local s = {}
  for i = 1, NUM_LANES do s[i] = lanes[i].active end
  scenes[n] = s
  screen_dirty = true
end

---------------------------------------------------------------- grid: edit

-- the step editor takes over the LAUNCH surface rather than asking for a
-- third 8x8: rows are the lane's voices, columns are eight steps of the
-- selected pattern, row 7 pages through longer patterns and row 8 exits.
-- the lane keeps playing underneath while you edit it.
local edit_mode = false
local edit_page = 0

local function edit_rows(l) return math.min(l.slots, 6) end

local function edit_press(x, y, z)
  if z ~= 1 then return end
  local l = lanes[sel_lane]
  local p = l.bank[sel_slot]
  local rows = edit_rows(l)
  if y <= rows then
    local step = edit_page * 8 + x
    if step <= p.length then Pattern.cycle(p, y, step) end
  elseif y == 7 then
    if x <= math.ceil(p.length / 8) then edit_page = x - 1 end
  elseif y == 8 then
    if x == 1 then edit_mode = false
    elseif x == 2 then Pattern.clear(p) end
  end
  screen_dirty = true
end

local function edit_level(x, y)
  local l = lanes[sel_lane]
  local p = l.bank[sel_slot]
  local rows = edit_rows(l)
  if y <= rows then
    local step = edit_page * 8 + x
    if step > p.length then return 0 end
    local v = Pattern.get(p, y, step)
    local under_head = (l.active == sel_slot) and (l.pos == step)
    if v == nil then
      if under_head then return 4 end
      -- a faint mark on every downbeat, so 16ths stay countable on a grid
      -- that has no numbers printed on it
      return (step % 4 == 1) and 2 or 0
    end
    if under_head then return 15 end
    if v >= Pattern.ACCENT then return 13 end
    if v >= Pattern.NORMAL then return 9 end
    return 5
  elseif y == 7 then
    if x > math.ceil(p.length / 8) then return 0 end
    return (x - 1) == edit_page and 12 or 3
  elseif y == 8 then
    if x == 1 then return 15 end
    if x == 2 then return 4 end
  end
  return 0
end

---------------------------------------------------------------- grid: launch

local function launch_press(lane, slot, z)
  if edit_mode then return edit_press(lane, slot, z) end
  if z ~= 1 then return end
  sel_lane = lane
  sel_slot = slot
  if playing then
    lanes[lane]:launch(slot)
  else
    lanes[lane]:commit(slot, Lane.TRANS_CUT)
  end
  screen_dirty = true
end

local function launch_level(lane, slot)
  if edit_mode then return edit_level(lane, slot) end
  local l = lanes[lane]
  local p = l.bank[slot]
  local blink = math.floor(tick / 4) % 2 == 0

  if l.active == slot then
    -- the active cell dims across the loop, so the grid shows how far
    -- through its pattern each lane is without needing a second row for it
    local frac = (l.pos - 1) / math.max(1, l:pattern().length)
    local lv = 15 - math.floor(frac * 7)
    if l.mute then lv = math.floor(lv / 3) end
    return lv
  end
  if l.queued == slot then return blink and 12 or 2 end
  if l.morph_left > 0 and l.morph_from == p then return 7 end
  if Pattern.is_empty(p) then return 0 end
  return l.mute and 1 or 3
end

---------------------------------------------------------------- grid: fx

local function fx_press(col, row, z)
  local on = z == 1

  if row == 1 then                              -- beat repeat (hold)
    if on then rep_engage(col)
    elseif rep_col == col then rep_release() end

  elseif row == 2 then                          -- scenes
    if on then
      if scene_arm then scene_store(col) else scene_launch(col) end
    end

  elseif row == 3 then                          -- lane mute
    if on then
      local id = lane_param(col, "mute")
      params:set(id, params:get(id) > 0.5 and 0 or 1)
    end

  elseif row == 4 then                          -- lane solo (hold)
    solo[col] = on or nil
    any_solo = next(solo) ~= nil

  elseif row == 5 then                          -- follow on/off
    if on then
      local id = lane_param(col, "follow")
      params:set(id, params:get(id) > 0.5 and 0 or 1)
    end

  elseif row == 6 then                          -- roll / fill (hold)
    lanes[col].boost = on or nil

  elseif row == 7 then
    if not on then return end
    if col <= 4 then                            -- transition, all lanes
      params:set("transition", col)
    elseif col == 5 then params:delta("launch_quant", -1)
    elseif col == 6 then params:delta("launch_quant", 1)
    elseif col == 7 then params:delta("morph_steps", -1)
    elseif col == 8 then params:delta("morph_steps", 1) end

  elseif row == 8 then
    if col == 4 then                            -- store-scene modifier
      scene_arm = on
      return
    end
    if not on then return end
    if col == 1 then toggle_play()
    elseif col == 2 then reseed()
    elseif col == 3 then
      -- flip every lane's follow at once
      local anyoff = false
      for i = 1, NUM_LANES do
        if params:get(lane_param(i, "follow")) < 0.5 then anyoff = true end
      end
      for i = 1, NUM_LANES do
        params:set(lane_param(i, "follow"), anyoff and 1 or 0)
      end
    elseif col == 5 then
      voices_out:panic()
    elseif col == 6 then
      edit_mode = not edit_mode
      edit_page = 0
    end
  end
  screen_dirty = true
end

local function fx_level(col, row)
  local blink = math.floor(tick / 4) % 2 == 0
  if row == 1 then
    if rep_col == col then return 15 end
    return 3
  elseif row == 2 then
    if scene_arm then return blink and 10 or 3 end
    return scenes[col] and 5 or 1
  elseif row == 3 then
    return params:get(lane_param(col, "mute")) > 0.5 and 12 or 2
  elseif row == 4 then
    return solo[col] and 15 or 2
  elseif row == 5 then
    return params:get(lane_param(col, "follow")) > 0.5 and 9 or 2
  elseif row == 6 then
    return lanes[col].boost and 15 or 2
  elseif row == 7 then
    if col <= 4 then return pround("transition") == col and 13 or 3 end
    return 4
  elseif row == 8 then
    if col == 1 then return playing and (blink and 15 or 8) or 3 end
    if col == 4 then return scene_arm and 15 or 3 end
    if col == 6 then return edit_mode and 15 or 3 end
    if col == 2 or col == 3 or col == 5 then return 3 end
    return 0
  end
  return 0
end

---------------------------------------------------------------- screen fields

-- the strip E3 edits, cycled with K1+E3. pattern-level fields act on the
-- selected slot; lane-level fields go through params, so the arc and psets
-- stay in step with them.
local FIELDS = {}

local function sel_pattern() return lanes[sel_lane].bank[sel_slot] end

local function follow_time_index(v)
  for i, t in ipairs(Pattern.FOLLOW_TIMES) do if t == v then return i end end
  return #Pattern.FOLLOW_TIMES
end

FIELDS[1] = {
  name = "follow",
  show = function()
    return Pattern.FOLLOW_NAMES[follow_time_index(sel_pattern().follow.time)]
  end,
  delta = function(d)
    local i = util.clamp(follow_time_index(sel_pattern().follow.time) + d,
                         1, #Pattern.FOLLOW_TIMES)
    sel_pattern().follow.time = Pattern.FOLLOW_TIMES[i]
  end}

FIELDS[2] = {
  name = "action A",
  show = function() return Pattern.ACTIONS[sel_pattern().follow.a] end,
  delta = function(d)
    local f = sel_pattern().follow
    f.a = util.clamp(f.a + d, 1, #Pattern.ACTIONS)
  end}

FIELDS[3] = {
  name = "action B",
  show = function() return Pattern.ACTIONS[sel_pattern().follow.b] end,
  delta = function(d)
    local f = sel_pattern().follow
    f.b = util.clamp(f.b + d, 1, #Pattern.ACTIONS)
  end}

FIELDS[4] = {
  name = "chance",
  show = function() return sel_pattern().follow.chance .. "%" end,
  delta = function(d)
    local f = sel_pattern().follow
    f.chance = util.clamp(f.chance + d * 5, 0, 100)
  end}

FIELDS[5] = {
  name = "length",
  show = function() return sel_pattern().length .. " st" end,
  delta = function(d)
    local p = sel_pattern()
    p.length = util.clamp(p.length + d, 1, 64)
  end}

local function lane_field(name, id)
  return {name = name,
          show = function() return params:string(lane_param(sel_lane, id)) end,
          delta = function(d) params:delta(lane_param(sel_lane, id), d) end}
end

FIELDS[6] = lane_field("transition", "trans")
FIELDS[7] = lane_field("division", "div")
FIELDS[8] = lane_field("swing", "swing")
FIELDS[9] = lane_field("chance/trig", "prob")
FIELDS[10] = lane_field("level", "level")
FIELDS[11] = lane_field("morph", "morph")

---------------------------------------------------------------- params

-- VOICE ROUTING holds the real (channel, note) for each of the 12 voices;
-- "note layout" and "midi channel" are presets that write into it. nothing
-- reads the layout at send time, so the two can never disagree -- see the
-- header of voices.lua for why that matters.
local routing_ready = false

local function stamp_layout()
  if not routing_ready then return end
  local layout = params:get("note_layout")
  local base = params:get("midi_channel")
  for v = 1, Voices.COUNT do
    local ch, note = Voices.layout_address(layout, v, base)
    params:set("voice_" .. v .. "_chan", ch)
    params:set("voice_" .. v .. "_note", note)
  end
end

local function add_params()
  params:add_separator("segue_head", "segue")

  params:add_group("segue_global", "GLOBAL", 8)

  -- the standard norns device picker: the vport number on its own tells you
  -- nothing about which box is on the other end
  local midi_devices = {}
  for i = 1, 16 do
    local name = midi.vports[i].name or "none"
    if name == nil or name == "" then name = "none" end
    if #name > 15 then name = util.acronym(name) end
    midi_devices[i] = i .. ": " .. name
  end
  params:add{type = "option", id = "midi_out", name = "midi out",
             options = midi_devices, default = 1,
             action = function(v)
               midi_dev = midi.connect(v)
               if voices_out then voices_out.dev = midi_dev end
             end}

  params:add{type = "number", id = "midi_channel", name = "midi channel",
             min = 1, max = 16, default = 1,
             action = function() stamp_layout() end}

  params:add{type = "option", id = "note_layout", name = "note layout",
             options = Voices.LAYOUT_NAMES, default = Voices.LAYOUT_SEQ,
             action = function() stamp_layout() end}

  params:add_control("launch_quant", "launch quant",
    controlspec.new(1, #Lane.QUANT_NAMES, "lin", 1, 7, ""))
  params:set_action("launch_quant", function() screen_dirty = true end)
  params:lookup_param("launch_quant").formatter = function(p)
    return Lane.QUANT_NAMES[util.round(p:get())]
  end

  params:add_control("transition", "transition",
    controlspec.new(1, #Lane.TRANS_NAMES, "lin", 1, Lane.TRANS_LEGATO, ""))
  params:lookup_param("transition").formatter = function(p)
    return Lane.TRANS_NAMES[util.round(p:get())]
  end
  params:set_action("transition", function(v)
    -- the global control is a "set them all" convenience; each lane keeps
    -- its own value, which the arc and the per-lane params still reach
    for i = 1, NUM_LANES do params:set(lane_param(i, "trans"), v) end
    screen_dirty = true
  end)

  params:add_control("morph_steps", "morph steps",
    controlspec.new(1, 32, "lin", 1, 8, "st"))
  params:set_action("morph_steps", function(v)
    for i = 1, NUM_LANES do params:set(lane_param(i, "morph"), v) end
    screen_dirty = true
  end)

  params:add_control("hat_choke", "closed hat chokes open",
    controlspec.new(0, 1, "lin", 1, 0, ""))
  params:lookup_param("hat_choke").formatter = function(p)
    return p:get() > 0.5 and "on" or "off"
  end

  params:add_trigger("panic", "panic")
  params:set_action("panic", function() if voices_out then voices_out:panic() end end)

  -------------------------------------------------------------- per lane
  for i = 1, NUM_LANES do
    local spec = Library.LANES[i]
    params:add_group("segue_lane_" .. i, i .. " " .. spec.name, 8)

    params:add_control(lane_param(i, "div"), "division",
      controlspec.new(1, #Lane.DIV_NAMES, "lin", 1, Lane.DIV_16TH, ""))
    params:lookup_param(lane_param(i, "div")).formatter = function(p)
      return Lane.DIV_NAMES[util.round(p:get())]
    end

    params:add_control(lane_param(i, "swing"), "swing",
      controlspec.new(0, 3, "lin", 1, 0, ""))
    params:lookup_param(lane_param(i, "swing")).formatter = function(p)
      -- swing is stored in whole ticks; what that is as a percentage
      -- depends on the lane's own step length, so it is worked out here
      -- rather than baked into the control
      local t = util.round(p:get())
      if t == 0 then return "straight" end
      local dt = Lane.DIV_TICKS[pround(lane_param(i, "div"))]
      return math.floor(t / dt * 100 + 0.5) .. "%"
    end

    params:add_control(lane_param(i, "prob"), "chance / trig",
      controlspec.new(0, 1, "lin", 0.01, 1, ""))
    params:add_control(lane_param(i, "level"), "level",
      controlspec.new(0, 2, "lin", 0.01, 1, ""))

    params:add_control(lane_param(i, "mute"), "mute",
      controlspec.new(0, 1, "lin", 1, 0, ""))
    params:lookup_param(lane_param(i, "mute")).formatter = function(p)
      return p:get() > 0.5 and "muted" or "on"
    end

    params:add_control(lane_param(i, "follow"), "follow",
      controlspec.new(0, 1, "lin", 1, 1, ""))
    params:lookup_param(lane_param(i, "follow")).formatter = function(p)
      return p:get() > 0.5 and "on" or "off"
    end

    params:add_control(lane_param(i, "trans"), "transition",
      controlspec.new(1, #Lane.TRANS_NAMES, "lin", 1, Lane.TRANS_LEGATO, ""))
    params:lookup_param(lane_param(i, "trans")).formatter = function(p)
      return Lane.TRANS_NAMES[util.round(p:get())]
    end

    params:add_control(lane_param(i, "morph"), "morph steps",
      controlspec.new(1, 32, "lin", 1, 8, "st"))

    for _, f in ipairs({"div", "swing", "prob", "level", "mute", "follow",
                        "trans", "morph"}) do
      params:set_action(lane_param(i, f), function()
        if lanes[i] then sync_lane_from_params(i) end
        screen_dirty = true
      end)
    end
  end

  -------------------------------------------------------------- routing
  params:add_group("segue_routing", "VOICE ROUTING", Voices.COUNT * 2)
  for v = 1, Voices.COUNT do
    local def_ch, def_note =
      Voices.layout_address(Voices.LAYOUT_SEQ, v, 1)
    params:add{type = "number", id = "voice_" .. v .. "_chan",
               name = Voices.NAMES[v] .. " channel", min = 1, max = 16,
               default = def_ch,
               action = function(val)
                 if voices_out then voices_out:set_address(v, val, nil) end
               end}
    params:add{type = "number", id = "voice_" .. v .. "_note",
               name = Voices.NAMES[v] .. " note", min = 0, max = 127,
               default = def_note,
               action = function(val)
                 if voices_out then voices_out:set_address(v, nil, val) end
               end}
  end
  -- from here on a layout change can write into the params above. adding
  -- the group before flipping this is what stops stamp_layout() running
  -- against params that do not exist yet.
  routing_ready = true

  -------------------------------------------------------------- arc
  params:add_group("segue_arc", "ARC", 4)
  params:add_control("arc_threshold", "sensitivity",
    controlspec.new(1, 20, "lin", 1, 6, ""))
  params:add_control("arc_brightness", "brightness",
    controlspec.new(1, 15, "lin", 1, 10, ""))
  params:add_control("arc_dim", "tick level",
    controlspec.new(0, 15, "lin", 1, 2, ""))
  params:add_control("arc_position", "orientation",
    controlspec.new(1, 4, "lin", 1, 1, ""))
end

---------------------------------------------------------------- persistence

-- the pattern/scene data is a table, not params: 8 lanes x 8 patterns x
-- (up to 4 rows x 64 steps) plus follow settings would be thousands of
-- entries and would bury the PARAMS menu. same split rytmpatch uses --
-- settings are params, sound data rides alongside the pset via
-- action_write/action_read and tab.save/tab.load (no cjson, which needs an
-- ARM binary that isn't on the device).
local function data_path(filename)
  return norns.state.data .. filename
end

local function collect_data()
  local d = {lanes = {}, scenes = {}}
  for i = 1, NUM_LANES do d.lanes[i] = lanes[i]:serialize() end
  for i = 1, 8 do
    if scenes[i] then
      local s = {}
      for j = 1, NUM_LANES do s[j] = scenes[i][j] end
      d.scenes[i] = s
    end
  end
  return d
end

local function apply_data(d)
  if type(d) ~= "table" then return end
  if d.lanes then
    for i = 1, NUM_LANES do
      if d.lanes[i] then
        lanes[i]:deserialize(d.lanes[i])
        push_lane_to_params(i)
      end
    end
  end
  scenes = {}
  if d.scenes then
    for i = 1, 8 do
      if d.scenes[i] then
        local s = {}
        for j = 1, NUM_LANES do s[j] = d.scenes[i][j] end
        scenes[i] = s
      end
    end
  end
  screen_dirty = true
end

local function write_data(filename)
  local okw, err = pcall(function()
    tab.save(collect_data(), data_path(filename))
  end)
  if not okw then print("segue: could not save " .. filename .. ": " .. tostring(err)) end
end

local function read_data(filename)
  local path = data_path(filename)
  if not util.file_exists(path) then return false end
  local okr, d = pcall(function() return tab.load(path) end)
  if okr and type(d) == "table" then
    apply_data(d)
    return true
  end
  print("segue: could not load " .. filename)
  return false
end

---------------------------------------------------------------- init

local function build_lanes()
  for i = 1, NUM_LANES do
    local spec = Library.LANES[i]
    lanes[i] = Lane:new{pattern_lib = Pattern, id = i, name = spec.name,
                        voices = spec.voices}
    Library.populate(lanes[i], spec, Pattern)
  end
  for i = 1, 8 do
    local s = {}
    for j = 1, NUM_LANES do s[j] = i end
    scenes[i] = s
  end
end

local function build_arc()
  local function lane_ring(label, id)
    return {label = label, id = function() return lane_param(sel_lane, id) end}
  end
  garc_ = GArc:new{
    threshold_id = "arc_threshold",
    bright_id = "arc_brightness",
    dim_id = "arc_dim",
    position_id = "arc_position",
    shift_fn = function() return shift end,
    pages = {
      {name = "PLAY", rings = {
        lane_ring("div", "div"),
        lane_ring("swing", "swing"),
        lane_ring("chance", "prob"),
        lane_ring("level", "level"),
      }},
      {name = "MORPH", rings = {
        lane_ring("trans", "trans"),
        lane_ring("morph", "morph"),
        {label = "quant", id = "launch_quant"},
        {label = "lane", id = "sel_lane"},
      }},
    }}
end

function init()
  math.randomseed(util.time() * 1000)

  build_lanes()
  add_params()

  -- a param purely so the arc has something to turn for lane select; it is
  -- the same value E1 moves, mirrored so both stay in step
  params:add_control("sel_lane", "lane",
    controlspec.new(1, NUM_LANES, "lin", 1, 1, ""))
  params:lookup_param("sel_lane").formatter = function(p)
    return util.round(p:get()) .. " " .. Library.LANES[util.round(p:get())].name
  end
  params:set_action("sel_lane", function(v)
    sel_lane = util.round(v)
    if garc_ then garc_:redraw() end
    screen_dirty = true
  end)

  midi_dev = midi.connect(params:get("midi_out"))
  voices_out = Voices:new{dev = midi_dev,
                          layout = params:get("note_layout"),
                          base_channel = params:get("midi_channel")}

  gridui = GridUI:new{
    on_launch = launch_press,
    on_fx = fx_press,
    level_launch = launch_level,
    level_fx = fx_level,
  }

  build_arc()

  params:add_separator("segue_data", "patterns")
  params:add_trigger("reseed", "reseed follow lanes")
  params:set_action("reseed", reseed)

  params.action_write = function(filename, name, number)
    write_data("segue-" .. number .. ".data")
  end
  params.action_read = function(filename, silent, number)
    read_data("segue-" .. number .. ".data")
  end
  params.action_delete = function(filename, name, number)
    local path = data_path("segue-" .. number .. ".data")
    if util.file_exists(path) then os.remove(path) end
  end

  -- the repeat buffer is built once here rather than on the first press:
  -- allocating 48 slots mid-performance is exactly the per-frame garbage
  -- CLAUDE.md's CPU rule warns about
  for o = 0, REPEAT_MAX - 1 do rep_slot(o) end

  params:bang()
  for i = 1, NUM_LANES do sync_lane_from_params(i) end

  -- last session's patterns come back without being sent anywhere, the same
  -- way rytmpatch reloads its last state on init
  read_data("segue-last.data")

  if garc_ then garc_:redraw() end

  redraw_id = clock.run(function()
    while true do
      clock.sleep(1 / FPS)
      -- rings follow values that moved without the arc (PARAMS menu, pset
      -- load, an encoder); cheap, redraws only when something changed
      if garc_ then garc_:poll() end
      if playing then screen_dirty = true end -- the playheads are moving
      if screen_dirty then
        redraw()
        screen_dirty = false
      end
    end
  end)
end

---------------------------------------------------------------- transport hooks

function clock.transport.start() if not playing then start_playing() end end
function clock.transport.stop() stop_playing() end

---------------------------------------------------------------- keys / encs

function key(n, z)
  if n == 1 then
    shift = z == 1
    -- on a single 8x8 the FX layer lives under the shift key, so it has to
    -- repaint the moment the key moves
    if gridui and gridui:set_alt(shift) then gridui:redraw() end
    screen_dirty = true
    return
  end
  if z ~= 1 then return end
  if n == 2 then
    if shift then
      local id = lane_param(sel_lane, "follow")
      params:set(id, params:get(id) > 0.5 and 0 or 1)
    else
      launch_press(sel_lane, sel_slot, 1)
    end
  elseif n == 3 then
    if shift then voices_out:panic() else toggle_play() end
  end
  screen_dirty = true
end

function enc(n, d)
  if n == 1 then
    params:set("sel_lane", util.clamp(sel_lane + d, 1, NUM_LANES))
  elseif n == 2 then
    sel_slot = util.clamp(sel_slot + d, 1, Lane.PATTERN_COUNT)
  elseif n == 3 then
    if shift then
      field = util.clamp(field + d, 1, #FIELDS)
    else
      FIELDS[field].delta(d)
    end
  end
  screen_dirty = true
end

---------------------------------------------------------------- screen

local MATRIX_X = 8
local MATRIX_Y = 13
local COL_W = 15
local ROW_H = 4

function redraw()
  screen.clear()
  screen.aa(0)

  local l = lanes[sel_lane]
  local p = l.bank[sel_slot]

  -- header: which lane and pattern the encoders are pointed at
  screen.level(15)
  screen.move(0, 7)
  screen.text(Library.LANES[sel_lane].name)
  screen.level(6)
  screen.move(34, 7)
  screen.text(sel_slot .. " " .. p.name)
  screen.level(playing and 12 or 3)
  screen.move(128, 7)
  screen.text_right("" .. math.floor(clock.get_tempo() + 0.5))

  -- the bank: lanes across, slots down. this is the launch grid on screen.
  for i = 1, NUM_LANES do
    local ln = lanes[i]
    local x = MATRIX_X + (i - 1) * COL_W
    for s = 1, Lane.PATTERN_COUNT do
      local y = MATRIX_Y + (s - 1) * ROW_H
      local cell = ln.bank[s]
      if ln.active == s then
        screen.level(ln.mute and 4 or 15)
        screen.rect(x, y, 6, 3)
        screen.fill()
      elseif ln.queued == s then
        screen.level(8)
        screen.rect(x + 0.5, y + 0.5, 5, 2)
        screen.stroke()
      elseif not Pattern.is_empty(cell) then
        screen.level(3)
        screen.rect(x, y + 1, 6, 1)
        screen.fill()
      end
    end
    -- playhead: how far through its pattern this lane is
    local frac = (ln.pos - 1) / math.max(1, ln:pattern().length)
    screen.level(ln.follow_on and 10 or 4)
    screen.rect(x, MATRIX_Y + Lane.PATTERN_COUNT * ROW_H + 1,
                math.max(1, math.floor(frac * 6 + 0.5)), 1)
    screen.fill()
  end

  -- selection marker under the chosen lane / beside the chosen slot
  screen.level(15)
  local sx = MATRIX_X + (sel_lane - 1) * COL_W
  screen.rect(sx, MATRIX_Y - 3, 6, 1)
  screen.fill()
  screen.rect(MATRIX_X - 3, MATRIX_Y + (sel_slot - 1) * ROW_H, 1, 3)
  screen.fill()

  -- the field E3 is editing
  screen.level(15)
  screen.move(0, 54)
  screen.text(FIELDS[field].name .. " " .. FIELDS[field].show())

  -- bottom line: the arc's own footer when there is one, otherwise a
  -- summary of what a switch is going to do right now
  screen.level(4)
  screen.move(0, 62)
  local footer = garc_ and garc_:footer_text()
  if edit_mode then
    -- edit mode owns this line: it changes what the grid does entirely, so
    -- it outranks the arc footer while it is on
    screen.level(15)
    screen.text("EDIT  steps " .. (edit_page * 8 + 1) .. "-" ..
                math.min(p.length, edit_page * 8 + 8) .. " of " .. p.length)
  elseif footer then
    screen.text(footer)
  else
    screen.text(Lane.TRANS_NAMES[l.transition] .. "  q " ..
                Lane.QUANT_NAMES[pround("launch_quant")] ..
                (rep_col and ("  rpt " .. REPEAT_NAMES[rep_col]) or ""))
  end

  screen.update()
end

---------------------------------------------------------------- cleanup

function cleanup()
  if clock_id then clock.cancel(clock_id) end
  if redraw_id then clock.cancel(redraw_id) end
  if voices_out then voices_out:panic() end
  if gridui then gridui:cleanup() end
  write_data("segue-last.data")
end
