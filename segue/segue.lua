-- segue
-- v0.7.0
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
--
-- the last field is `scope`: it widens
-- a follow edit to the whole lane, the
-- whole kit (that slot on every lane)
-- or everything. shown in brackets on
-- the field line while it is armed.
-- holding K1 over an arc ring applies
-- the turn to every lane.

local Pattern = include("segue/lib/pattern")
local Lane = include("segue/lib/lane")
local Library = include("segue/lib/library")
local Voices = include("segue/lib/voices")
local GridUI = include("segue/lib/gridui")
local GArc = include("segue/lib/garc")

local NUM_LANES = 8
local FPS = 15

-- beat repeat divisions, in ticks (96 PPQN). capped at half a bar: past
-- that a "repeat" stops being a stutter and starts being a loop.
local REPEAT_TICKS = {192, 96, 64, 48, 32, 24, 16, 12}
local REPEAT_NAMES = {"1/2", "1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32"}
local REPEAT_MAX = 192

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

-- input deserves an answer now, not on the next animation frame. the redraw
-- loop runs at 15fps, which is plenty for the playheads but means a turn of
-- an encoder can sit invisible for 66ms -- and that reads as the encoder
-- being sluggish even when the value moved instantly, because you turn
-- again before the first change appears and then it jumps two.
--
-- so input redraws straight from the handler, rate-limited to 30fps so a
-- fast spin cannot flood the screen. CLAUDE.md's rule is against redraws
-- from handlers *that cause rapid re-draws*, which the limiter prevents.
local INPUT_FPS = 30
local last_input_draw = 0

local function touch()
  screen_dirty = true
  local now = util.time()
  if now - last_input_draw >= 1 / INPUT_FPS then
    last_input_draw = now
    redraw()
    screen_dirty = false
  end
end

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

-- TICKS COME FROM THE SHARED TIMELINE, not from a counter of our own.
--
-- the first version set tick = 0 at the moment you pressed play and then
-- incremented. that meant every bar line, every launch-quantize boundary
-- and every swing parity was measured from *when you happened to start* --
-- so under Link the script ran at the right tempo while sitting at an
-- arbitrary phase against everyone else, and the only way to land on the
-- beat was to press play at exactly the right instant. hence "I have to
-- try a couple of times."
--
-- deriving the tick from clock.get_beats() instead makes the grid a
-- property of the clock rather than of the keypress, so it lands right
-- however late you hit it. it is also self-correcting: a missed or late
-- wakeup cannot accumulate drift the way an incrementing counter can.
local tick_origin = 0

-- the shared timeline's tick, before any origin is subtracted
local function raw_tick()
  return math.floor(clock.get_beats() * Lane.PPQN + 0.5)
end

local function global_tick() return raw_tick() - tick_origin end

-- whether the clock is ours alone or shared with something else. when it is
-- shared, the pattern grid locks to the shared timeline (origin 0) so all
-- peers agree where the bar is. on the internal clock there is nobody to
-- agree with, and starting a pattern from step 1 where you pressed play is
-- what you would expect, so the origin moves to now.
local function clock_is_shared()
  local okc, src = pcall(function() return params:get("clock_source") end)
  return okc and src ~= nil and src > 1
end

-- on the internal clock the origin cannot be set here: clock.sync waits for
-- the *next* subdivision, so by the time the first tick is processed the
-- moment of the keypress has already gone by. setting the origin from the
-- first tick that actually runs is what makes "press play, hear step 1"
-- exact rather than one step out.
local pending_origin = false

local function all_reset()
  if clock_is_shared() then
    tick_origin = 0
    pending_origin = false
  else
    pending_origin = true
  end
  tick = global_tick() - 1
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
      if pending_origin then
        tick_origin = raw_tick()
        pending_origin = false
        tick = -1
      end
      local t = global_tick()
      -- never repeat or run backwards: a wakeup landing a hair early would
      -- otherwise round down to the tick just played and fire it twice
      if t <= tick then t = tick + 1 end
      tick = t
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

-- one bucket per tick of the capture window. at 96 PPQN a half-bar window
-- is 192 buckets, so the per-bucket hit tables are created only when a tick
-- actually records something -- preallocating 192 x 24 of them up front
-- would be several thousand tables for a buffer that is mostly silence.
-- once created they are reused, so the steady state still allocates
-- nothing.
local function rep_slot(offset)
  local s = rep_buf[offset]
  if s == nil then
    s = {n = 0}
    rep_buf[offset] = s
  end
  return s
end

local function rep_put(s, i, voice, vel)
  local h = s[i]
  if h == nil then
    h = {voice = 0, vel = 0}
    s[i] = h
  end
  h.voice = voice
  h.vel = vel
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
          rep_put(s, i, out_buf[i].voice, out_buf[i].vel)
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

  -- `tick` is set by the clock loop from the shared timeline, not counted
  -- here -- see the note above all_reset()
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

local LANE_SETTINGS = {"div", "swing", "prob", "level", "mute", "follow",
                       "trans", "morph"}

-- back to the shipped state: the factory kits, default scenes, and every
-- lane setting at its param default. the autosave means pattern edits
-- otherwise survive a power cycle indefinitely, which is usually what you
-- want and occasionally exactly what you don't.
local function reset_to_defaults()
  for i = 1, NUM_LANES do
    Library.populate(lanes[i], Library.LANES[i], Pattern)
    lanes[i].active = 1
    lanes[i]:reset()
    for _, f in ipairs(LANE_SETTINGS) do
      local id = lane_param(i, f)
      params:set(id, params:lookup_param(id).controlspec.default)
    end
  end
  scenes = {}
  for i = 1, 8 do
    local s = {}
    for j = 1, NUM_LANES do s[j] = i end
    scenes[i] = s
  end
  screen_dirty = true
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
  touch()
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
  touch()
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

-- FOCUS mode hides the performance layer so the parts still being proven --
-- the follow engine and the kit library -- are what you are actually
-- playing with. nothing is removed, just made dark and inert: rows 1 (beat
-- repeat), 4 (solo) and 6 (roll) are the three that are pure performance
-- and answer no question about whether a switch sounds right.
local FOCUS_HIDDEN_ROWS = {[1] = true, [4] = true, [6] = true}

local function row_hidden(row)
  return pround("mode") == 1 and FOCUS_HIDDEN_ROWS[row]
end

local function fx_press(col, row, z)
  if row_hidden(row) then return end
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
  touch()
end

local function fx_level(col, row)
  if row_hidden(row) then return 0 end
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

-- EDIT SCOPE. follow settings live per pattern, which means 64 of them, and
-- setting up a scheme one at a time is 4 fields x 64 trips. scope widens
-- what a follow edit writes to. it is shown on the field line whenever it is
-- set to anything but `pattern`, because a silent mass edit would be a
-- nasty surprise.
--
-- a bulk edit ASSIGNS rather than nudges: the new value is worked out from
-- the pattern on screen and then written to everything in scope, so they all
-- end up the same and the displayed value is the truth. (the arc's K1
-- broadcast is the other way round -- it deltas each lane independently,
-- keeping their differences. that is garc's behaviour and it is the right
-- one for a performance nudge; this is a settings edit.)
local SCOPE_PATTERN, SCOPE_LANE, SCOPE_KIT, SCOPE_ALL = 1, 2, 3, 4
local SCOPE_NAMES = {"pattern", "lane", "kit", "all"}
local scope = SCOPE_PATTERN

local _scope_buf = {}

-- the patterns a follow edit touches right now
local function scoped_patterns()
  local n = 0
  if scope == SCOPE_PATTERN then
    n = 1
    _scope_buf[1] = sel_pattern()
  elseif scope == SCOPE_LANE then
    for s = 1, Lane.PATTERN_COUNT do
      n = n + 1
      _scope_buf[n] = lanes[sel_lane].bank[s]
    end
  elseif scope == SCOPE_KIT then
    for i = 1, NUM_LANES do
      n = n + 1
      _scope_buf[n] = lanes[i].bank[sel_slot]
    end
  else
    for i = 1, NUM_LANES do
      for s = 1, Lane.PATTERN_COUNT do
        n = n + 1
        _scope_buf[n] = lanes[i].bank[s]
      end
    end
  end
  return n
end

-- write one follow field across the current scope
local function set_follow(key, value)
  local n = scoped_patterns()
  for i = 1, n do _scope_buf[i].follow[key] = value end
end

local function follow_time_index(v)
  for i, t in ipairs(Pattern.FOLLOW_TIMES) do if t == v then return i end end
  return #Pattern.FOLLOW_TIMES
end

-- the four follow fields honour the edit scope above
FIELDS[1] = {
  name = "follow", bulk = true,
  show = function()
    return Pattern.FOLLOW_NAMES[follow_time_index(sel_pattern().follow.time)]
  end,
  delta = function(d)
    local i = util.clamp(follow_time_index(sel_pattern().follow.time) + d,
                         1, #Pattern.FOLLOW_TIMES)
    set_follow("time", Pattern.FOLLOW_TIMES[i])
  end}

FIELDS[2] = {
  name = "action A", bulk = true,
  show = function() return Pattern.ACTIONS[sel_pattern().follow.a] end,
  delta = function(d)
    set_follow("a", util.clamp(sel_pattern().follow.a + d, 1, #Pattern.ACTIONS))
  end}

FIELDS[3] = {
  name = "action B", bulk = true,
  show = function() return Pattern.ACTIONS[sel_pattern().follow.b] end,
  delta = function(d)
    set_follow("b", util.clamp(sel_pattern().follow.b + d, 1, #Pattern.ACTIONS))
  end}

FIELDS[4] = {
  name = "chance", bulk = true,
  show = function() return sel_pattern().follow.chance .. "%" end,
  delta = function(d)
    set_follow("chance", util.clamp(sel_pattern().follow.chance + d * 5, 0, 100))
  end}

FIELDS[5] = {
  name = "length",
  show = function() return sel_pattern().length .. " st" end,
  delta = function(d)
    local p = sel_pattern()
    p.length = util.clamp(p.length + d, 1, 64)
  end}

-- lane settings are already one-per-lane, so `lane` and `kit` scope mean
-- nothing here -- only `all` widens them, to every lane at once.
local function lane_field(name, id)
  return {name = name, lane_wide = true,
          show = function() return params:string(lane_param(sel_lane, id)) end,
          delta = function(d)
            params:delta(lane_param(sel_lane, id), d)
            if scope == SCOPE_ALL then
              local v = params:get(lane_param(sel_lane, id))
              for i = 1, NUM_LANES do
                if i ~= sel_lane then params:set(lane_param(i, id), v) end
              end
            end
          end}
end

FIELDS[6] = lane_field("transition", "trans")
FIELDS[7] = lane_field("division", "div")
FIELDS[8] = lane_field("swing", "swing")
FIELDS[9] = lane_field("chance/trig", "prob")
FIELDS[10] = lane_field("level", "level")
FIELDS[11] = lane_field("morph", "morph")

FIELDS[12] = {
  name = "scope",
  show = function() return SCOPE_NAMES[scope] end,
  delta = function(d) scope = util.clamp(scope + d, 1, #SCOPE_NAMES) end}

-- FOCUS drops length (the kit sets it), and the per-lane mix controls
-- (chance/trig, level) -- neither answers a question about the follow
-- engine, and eleven fields behind one encoder is too many to hold.
-- `scope` sits last in both lists so the field E3 lands on by default is
-- still `follow`, not something that silently widens the next edit.
local FIELDS_FOCUS = {1, 2, 3, 4, 6, 7, 8, 11, 12}
local FIELDS_FULL = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}

-- what the field currently in front of you would actually write to, which
-- is not the same as `scope` -- a lane setting ignores `lane` and `kit`
local function scope_label(f)
  if scope == SCOPE_PATTERN then return nil end
  if f.bulk then return SCOPE_NAMES[scope]:upper() end
  if f.lane_wide and scope == SCOPE_ALL then return "ALL LANES" end
  return nil
end

local function field_list()
  return pround("mode") == 1 and FIELDS_FOCUS or FIELDS_FULL
end

local function cur_field()
  local list = field_list()
  return FIELDS[list[util.clamp(field, 1, #list)]]
end

---------------------------------------------------------------- params

-- VOICE ROUTING holds the real (channel, note) for each of the 12 voices;
-- "note layout" and "midi channel" are presets that write into it. nothing
-- reads the layout at send time, so the two can never disagree -- see the
-- header of voices.lua for why that matters.
-- norns' Control:delta moves the RAW 0-1 value by d/100 and ignores the
-- param's step entirely, so a control with only a handful of steps needs a
-- great deal of encoder to move one of them: 50 clicks to toggle a
-- two-option control, 17 for a four-option one, 8 for the division. That is
-- the "it's waiting for a full turn" feel, and it hits every discrete
-- setting in the script.
--
-- everything here has to be a `control` rather than a `number` or `option`
-- because garc only renders rings for params that carry a controlspec. so
-- the fix is to override the param's own delta: for any control with 100
-- steps or fewer, one click is one step.
--
-- this also repairs the arc, in a way that was not obvious. garc smooths a
-- ring's fill by `controlspec.quantum` (step / range) -- i.e. it was
-- already written assuming one delta equals one step, which norns does not
-- do. the rings were being under-filled for exactly these params.
local function add_ctl(id, name, cs, formatter)
  params:add_control(id, name, cs)
  local p = params:lookup_param(id)
  if formatter then p.formatter = formatter end
  if cs.step and cs.step > 0 and (cs.maxval - cs.minval) / cs.step <= 100 then
    p.delta = function(_, d)
      params:set(id, util.clamp(params:get(id) + d * cs.step,
                                cs.minval, cs.maxval))
    end
  end
  return p
end

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

  params:add_group("segue_global", "GLOBAL", 9)

  -- FOCUS is the default while the follow engine and the kit library are
  -- the things being judged: it dims the performance rows on the FX grid
  -- and trims the screen's field list. FULL turns everything back on --
  -- nothing is removed, only hidden.
  add_ctl("mode", "mode", controlspec.new(1, 2, "lin", 1, 1, ""))
  params:lookup_param("mode").formatter = function(p)
    return util.round(p:get()) == 1 and "focus" or "full"
  end
  params:set_action("mode", function()
    -- a hidden row must not leave state latched behind it
    if row_hidden(1) then rep_release() end
    if row_hidden(4) then solo = {} any_solo = false end
    if row_hidden(6) then
      for i = 1, NUM_LANES do if lanes[i] then lanes[i].boost = nil end end
    end
    field = 1
    screen_dirty = true
  end)

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

  add_ctl("launch_quant", "launch quant",
    controlspec.new(1, #Lane.QUANT_NAMES, "lin", 1, 7, ""))
  params:set_action("launch_quant", function() screen_dirty = true end)
  params:lookup_param("launch_quant").formatter = function(p)
    return Lane.QUANT_NAMES[util.round(p:get())]
  end

  add_ctl("transition", "transition",
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

  add_ctl("morph_steps", "morph steps",
    controlspec.new(1, 32, "lin", 1, 8, "st"))
  params:set_action("morph_steps", function(v)
    for i = 1, NUM_LANES do params:set(lane_param(i, "morph"), v) end
    screen_dirty = true
  end)

  add_ctl("hat_choke", "closed hat chokes open",
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

    add_ctl(lane_param(i, "div"), "division",
      controlspec.new(1, #Lane.DIV_NAMES, "lin", 1, Lane.DIV_16TH, ""))
    params:lookup_param(lane_param(i, "div")).formatter = function(p)
      return Lane.DIV_NAMES[util.round(p:get())]
    end

    add_ctl(lane_param(i, "swing"), "swing",
      controlspec.new(0, Lane.SWING_MAX, "lin", 1, 0, ""))
    params:lookup_param(lane_param(i, "swing")).formatter = function(p)
      -- a percentage of the lane's own step, so it means the same thing at
      -- any division. the tick grid can only land on so many of them (about
      -- 4% apart at a 1/16 division), so show what will actually be played
      -- rather than what was asked for -- otherwise the knob claims a
      -- precision the clock does not have.
      local want = util.round(p:get())
      if want == 0 then return "straight" end
      local dt = Lane.DIV_TICKS[pround(lane_param(i, "div"))]
      local ticks = math.floor(want / 100 * dt + 0.5)
      if ticks >= dt then ticks = dt - 1 end
      return math.floor(ticks / dt * 100 + 0.5) .. "%"
    end

    add_ctl(lane_param(i, "prob"), "chance / trig",
      controlspec.new(0, 1, "lin", 0.01, 1, ""))
    add_ctl(lane_param(i, "level"), "level",
      controlspec.new(0, 2, "lin", 0.01, 1, ""))

    add_ctl(lane_param(i, "mute"), "mute",
      controlspec.new(0, 1, "lin", 1, 0, ""))
    params:lookup_param(lane_param(i, "mute")).formatter = function(p)
      return p:get() > 0.5 and "muted" or "on"
    end

    add_ctl(lane_param(i, "follow"), "follow",
      controlspec.new(0, 1, "lin", 1, 1, ""))
    params:lookup_param(lane_param(i, "follow")).formatter = function(p)
      return p:get() > 0.5 and "on" or "off"
    end

    add_ctl(lane_param(i, "trans"), "transition",
      controlspec.new(1, #Lane.TRANS_NAMES, "lin", 1, Lane.TRANS_LEGATO, ""))
    params:lookup_param(lane_param(i, "trans")).formatter = function(p)
      return Lane.TRANS_NAMES[util.round(p:get())]
    end

    add_ctl(lane_param(i, "morph"), "morph steps",
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
  add_ctl("arc_threshold", "sensitivity",
    controlspec.new(1, 20, "lin", 1, 6, ""))
  add_ctl("arc_brightness", "brightness",
    controlspec.new(1, 15, "lin", 1, 10, ""))
  add_ctl("arc_dim", "tick level",
    controlspec.new(0, 15, "lin", 1, 2, ""))
  add_ctl("arc_position", "orientation",
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
        -- pattern content and which slot is playing, but NOT the lane's
        -- settings: those live in params, and a pset restores them that
        -- way. letting the blob restore them too meant every lane setting
        -- survived a power cycle whether you wanted it to or not, with no
        -- way back to a known state.
        lanes[i]:deserialize(d.lanes[i])
        sync_lane_from_params(i)
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
  -- `all_ids` is garc's broadcast hook: hold the shift key (K1, via the
  -- shift_fn below) and a turn applies to every lane instead of just the
  -- selected one. it was being passed shift_fn with no ring ever declaring
  -- all_ids, so holding K1 on the arc did nothing at all until now.
  --
  -- note this deltas each lane independently rather than assigning one
  -- value to all of them, so lanes that were set differently stay
  -- different. that is garc's own behaviour -- the module is a shared copy
  -- across three scripts and stays byte-identical -- and it is the right
  -- feel for a performance nudge. the screen's `scope` does the assigning
  -- kind for settings work.
  local function lane_ring(label, id)
    return {label = label,
            id = function() return lane_param(sel_lane, id) end,
            all_ids = function()
              local t = {}
              for i = 1, NUM_LANES do t[i] = lane_param(i, id) end
              return t
            end}
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
  add_ctl("sel_lane", "lane",
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
  params:add_trigger("reset_defaults", "reset to factory kits")
  params:set_action("reset_defaults", reset_to_defaults)

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
  -- the bucket headers are tiny and there are only 192 of them; the hit
  -- tables inside them are created on demand (see rep_put), since most
  -- ticks of a capture window record nothing at all
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
    touch()
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
  touch()
end

function enc(n, d)
  if n == 1 then
    params:set("sel_lane", util.clamp(sel_lane + d, 1, NUM_LANES))
  elseif n == 2 then
    sel_slot = util.clamp(sel_slot + d, 1, Lane.PATTERN_COUNT)
  elseif n == 3 then
    if shift then
      field = util.clamp(field + d, 1, #field_list())
    else
      cur_field().delta(d)
    end
  end
  touch()
end

---------------------------------------------------------------- screen

local MATRIX_X = 8
local MATRIX_Y = 13
local COL_W = 15
local ROW_H = 4

-- the arc's footer is worth reading for a moment after a ring moves and is
-- dead weight after that, so it borrows the bottom line rather than owning
-- it. garc keeps no timestamp and is a byte-identical shared copy, so
-- rather than change it: the footer string changing IS the touch.
local ARC_HOLD = 1.5
local last_footer, last_footer_at = nil, -math.huge

local function arc_fresh()
  local f = garc_ and garc_:footer_text()
  if f == nil then return false end
  if f ~= last_footer then
    last_footer = f
    last_footer_at = util.time()
  end
  return (util.time() - last_footer_at) < ARC_HOLD
end

-- "when does this change, and to what?" -- the question the whole script
-- poses, and the one thing the screen was not answering. a queued launch
-- outranks a follow action because you asked for it explicitly.
local function next_text(l)
  local quant = Lane.QUANT_TICKS[pround("launch_quant")]

  local n = l:steps_to_launch(tick, quant)
  if n then
    return "> " .. l.bank[l.queued].name .. (n > 0 and ("  " .. n) or "  now")
  end

  local trans = Lane.TRANS_NAMES[l.transition]
  if rep_col then return trans .. "  rpt " .. REPEAT_NAMES[rep_col] end

  local f = l:steps_to_follow()
  if f then
    local act = Pattern.ACTIONS[l:pattern().follow.a]
    return trans .. "  " .. act .. " " .. f
  end
  return trans .. "  q " .. Lane.QUANT_NAMES[pround("launch_quant")]
end

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
  local f = cur_field()
  local badge = scope_label(f)
  if badge then
    -- an armed bulk edit has to be impossible to miss: it goes in front of
    -- the field name, on the line where the edit happens
    screen.level(15)
    screen.text("[" .. badge .. "] ")
    screen.level(10)
    screen.text(f.name .. " " .. f.show())
  else
    screen.text(f.name .. " " .. f.show())
  end

  -- bottom line. three things want it, in this order of urgency:
  --   EDIT       the grid means something else entirely right now
  --   arc        but only just after a ring moved -- see arc_fresh()
  --   what next  the standing answer to "when does this change?"
  screen.level(4)
  screen.move(0, 62)
  if edit_mode then
    screen.level(15)
    screen.text("EDIT  steps " .. (edit_page * 8 + 1) .. "-" ..
                math.min(p.length, edit_page * 8 + 8) .. " of " .. p.length)
  elseif arc_fresh() then
    screen.text(garc_:footer_text())
  else
    screen.text(next_text(l))
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
