-- segue
-- v0.8.0
-- follow-action drum sequencer
-- for the Elektron Analog Rytm
-- MIDI out only -- see MANUAL.md
--
-- eight lanes, each a column of
-- eight kits. launch a kit and the
-- lane moves to it; leave it alone
-- and its follow action moves it,
-- on its own clock, mid-bar if you
-- asked for that.
--
-- eight banks of eight kits:
-- generic house techno electro
-- breakbeats variety variety-2 user
--
-- settings default to GLOBAL; any
-- lane or kit can override its own.
--
-- LAUNCH grid: lanes across, kits
-- down. FX grid: see MANUAL.md.
--
-- E1 lane   E2 kit   E3 edit
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
local shift = false

-- banks. `current_bank` is what the lanes hold; `bank_target` is a switch
-- waiting on its quantize boundary (nil when none is pending).
local current_bank = 1
local bank_target = nil
local user_bank = {}      -- [lane] = that lane's eight user patterns

local solo = {}
local any_solo = false

-- beat repeat
local rep_col = nil        -- which row-1 button is held
local rep_div = 0
local rep_t0 = 0
local rep_recording = false
local rep_buf = {}

local screen_dirty = true
local notice, notice_at = nil, -math.huge -- a one-off message for the footer

-- input deserves an answer now, not on the next animation frame. the redraw
-- loop runs at 15fps, which is plenty for the playheads but means a turn of
-- an encoder can sit invisible for 66ms -- and that reads as the encoder
-- being sluggish even when the value moved instantly, because you turn
-- again before the first change appears and then it jumps two.
--
-- so input redraws straight from the handler, rate-limited to 30fps so a
-- fast spin cannot flood the screen. CONVENTIONS §8 says handlers only set
-- a dirty flag; this is a deliberate exception, recorded in NOTES.md, made
-- after it was felt on hardware -- the rule's concern is rapid redraws,
-- which the limiter is there to prevent.
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

local function say(msg)
  notice = msg
  notice_at = util.time()
  screen_dirty = true
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
local function send_transport(msg)
  for i = 1, 16 do
    if params:get("clock_midi_out_" .. i) == 1 then
      midi.vports[i]:send({type = msg})
    end
  end
end

-- TICKS COME FROM THE SHARED TIMELINE, not from a counter of our own.
-- the first version set tick = 0 at the moment you pressed play and then
-- incremented, so every bar line and quantize boundary was measured from
-- *when you happened to start* -- under Link, the right tempo at an
-- arbitrary phase. deriving the tick from clock.get_beats() makes the grid
-- a property of the clock rather than of the keypress, and it is
-- self-correcting: a late wakeup cannot accumulate drift.
local tick_origin = 0

local function raw_tick()
  return math.floor(clock.get_beats() * Lane.PPQN + 0.5)
end

local function global_tick() return raw_tick() - tick_origin end

-- on a shared clock (Link, MIDI) the grid locks to the shared timeline so
-- every peer agrees where the bar is. on the internal clock there is nobody
-- to agree with, so the pattern starts at step 1 where you pressed play.
local function clock_is_shared()
  local okc, src = pcall(function() return params:get("clock_source") end)
  return okc and src ~= nil and src > 1
end

-- the internal-clock origin is taken from the first tick that actually
-- runs: clock.sync waits for the next subdivision, so by then the moment
-- of the keypress has passed, and setting it earlier lands one step out.
local pending_origin = false

local function all_reset()
  if clock_is_shared() then
    tick_origin = 0
    pending_origin = false
    tick = global_tick() - 1
  else
    -- -1, exactly what the first tick will set it to once it takes the
    -- origin. computing it from global_tick() here used the PREVIOUS run's
    -- origin, so anything that read `tick` between pressing play and the
    -- first tick -- a beat repeat pressed on the downbeat, say -- captured
    -- a number from the old timeline and ran misaligned for the whole hold.
    pending_origin = true
    tick = -1
  end
  for i = 1, NUM_LANES do lanes[i]:reset() end
  bank_target = nil
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

-- one bucket per tick of the capture window. the per-bucket hit tables are
-- created only when a tick actually records something -- at 96 PPQN a
-- half-bar window is 192 buckets, mostly silence -- and reused after that,
-- so the steady state allocates nothing.
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

  -- a bank switch has landed once every lane has swapped; only then does
  -- the current bank change (see select_bank)
  if bank_target then
    local waiting = false
    for i = 1, NUM_LANES do
      if lanes[i].pending_bank then waiting = true end
    end
    if not waiting then
      current_bank = bank_target
      bank_target = nil
      switched = true
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

  if switched or n_out > 0 then screen_dirty = true end
end

---------------------------------------------------------------- inheritance

local function lane_param(i, name) return "lane_" .. i .. "_" .. name end

-- EVERY INHERITABLE SETTING, and where each level of it lives.
--
--   global   a param everything falls back to
--   lane     a per-lane param, whose lowest value is the "inherit" sentinel
--   pattern  pattern.ov[key], absent meaning inherit (lane.lua)
--
-- the sentinel sits at the BOTTOM of each lane param's range, so turning a
-- lane value down past its lowest real setting lands on "global" -- the
-- same gesture as clearing a pattern override. `lane = nil` means there is
-- no lane level (quantize is global or per pattern, as in Ableton).
--
-- the global and lane levels are params, not data, because that is what
-- gets them the PARAMS menu, psets and the arc for free (CONVENTIONS §5).
-- the pattern level cannot be: 64 patterns x 6 keys would bury the menu.
local INHERIT = {
  follow_time   = {lane = "ftime",   global = "follow_time",   inherit = 0},
  follow_a      = {lane = "fa",      global = "follow_a",      inherit = 0},
  follow_b      = {lane = "fb",      global = "follow_b",      inherit = 0},
  follow_chance = {lane = "fchance", global = "follow_chance", inherit = -5},
  trans         = {lane = "trans",   global = "transition",    inherit = 0},
  quant         = {                  global = "launch_quant"},
  div           = {lane = "div",     global = "division",      inherit = 0},
  swing         = {lane = "swing",   global = "swing",         inherit = -1},
  morph         = {lane = "morph",   global = "morph_steps",   inherit = 0},
}

-- the lane's own value for `key`, or nil if the lane inherits
local function lane_value(i, key)
  local spec = INHERIT[key]
  if spec.lane == nil then return nil end
  local v = util.round(params:get(lane_param(i, spec.lane)))
  if v == spec.inherit then return nil end
  return v
end

local function global_value(key) return util.round(params:get(INHERIT[key].global)) end

-- what lane i resolves `key` to before any pattern override
local function parent_value(i, key)
  local v = lane_value(i, key)
  if v ~= nil then return v end
  return global_value(key)
end

-- division, swing and morph are read every tick, so they are resolved into
-- plain lane fields here -- whenever the lane or the global value moves --
-- rather than looked up on the 96 PPQN hot path. the pattern-level
-- settings resolve lazily through Lane:setting, since they are only read
-- when something actually changes.
local function sync_lane_from_params(i)
  local l = lanes[i]
  if l == nil then return end
  l.div = parent_value(i, "div")
  l.swing = parent_value(i, "swing")
  l.morph_steps = parent_value(i, "morph")
  l.prob = params:get(lane_param(i, "prob"))
  l.level = params:get(lane_param(i, "level"))
  l.mute = params:get(lane_param(i, "mute")) > 0.5
  l.follow_on = params:get(lane_param(i, "follow")) > 0.5
end

local function sync_all_lanes()
  for i = 1, NUM_LANES do sync_lane_from_params(i) end
end

---------------------------------------------------------------- banks

local function bank_is_user(b) return b == Library.USER end

-- lane i's column for bank b. a FACTORY column is a fresh copy every time,
-- which is what makes the factory banks read-only: edits land on the copy
-- and are gone when you leave the bank. the USER column is the saved table
-- itself, shared rather than copied, so edits made while on it are kept.
local function bank_column(b, i)
  if bank_is_user(b) then return user_bank[i] end
  local spec = Library.LANES[i]
  return Library.column(b, spec, #spec.voices, Pattern)
end

local function empty_user_column(i)
  local spec = Library.LANES[i]
  local col = {}
  for k = 1, Lane.PATTERN_COUNT do
    local p = Pattern.new(#spec.voices, 16, "--")
    p.ov.follow_a = Pattern.ACTION_NONE -- empty sits out, as in library.lua
    col[k] = p
  end
  return col
end

-- swap every lane's bank right now. used when stopped, and at init
local function load_bank_now(b)
  current_bank = b
  bank_target = nil
  for i = 1, NUM_LANES do
    local l = lanes[i]
    l.bank = bank_column(b, i)
    l.pending_bank = nil
    l.morph_left = 0
    l.morph_from = nil
  end
  screen_dirty = true
end

-- the switch you make while playing: every lane queues the new bank for
-- the next launch-quantize boundary and hands off on its own transition,
-- keeping its slot. under legato the playhead carries across, so changing
-- bank is just another of the script's smooth switches.
--
-- `current_bank` changes only when the swap LANDS (see do_tick), not when
-- it is asked for: until the boundary the lanes are still playing the old
-- bank, and the screen should say so rather than name a bank whose kits
-- are not on the grid yet.
local function cancel_bank_switch()
  bank_target = nil
  for i = 1, NUM_LANES do
    lanes[i].pending_bank = nil
    lanes[i].pending_bank_quant = nil
  end
  screen_dirty = true
end

local function select_bank(b)
  if not playing then
    load_bank_now(b)
    return
  end
  if b == current_bank then
    -- choosing the bank you are already on cancels a pending switch
    if bank_target ~= nil then cancel_bank_switch() end
    return
  end
  bank_target = b
  local q = pround("launch_quant")
  for i = 1, NUM_LANES do lanes[i]:queue_bank(bank_column(b, i), q) end
  screen_dirty = true
end

local function user_slot_empty(k)
  for i = 1, NUM_LANES do
    if not Pattern.is_empty(user_bank[i][k]) then return false end
  end
  return true
end

-- capture what is PLAYING -- each lane's current pattern, from whatever
-- bank and kit it is on -- into the first empty user slot. this does the
-- job "store scene" used to (keep a combination you like), except that it
-- is saved and becomes a real kit you can launch, edit and follow. it is
-- also the only way to keep an edit made on a factory bank.
local function copy_to_user()
  local slot = nil
  for k = 1, Lane.PATTERN_COUNT do
    if user_slot_empty(k) then slot = k break end
  end
  local overwrote = slot == nil
  slot = slot or sel_slot
  for i = 1, NUM_LANES do
    -- a copy, never the pattern itself: on a factory bank that pattern is a
    -- throwaway, and on the user bank the lane holds user_bank[i] directly,
    -- so this write also shows up on the grid straight away
    user_bank[i][slot] = Pattern.copy(lanes[i]:pattern())
  end
  say((overwrote and "replaced user " or "copied to user ") .. slot)
  return slot
end

---------------------------------------------------------------- lane ops

-- back to the shipped state: bank 1, every setting at its default. the
-- user bank is left alone -- it is your work, and "reset" is for getting
-- out of a corner, not for losing things (there is a separate trigger for
-- clearing it).
local function reset_to_defaults()
  local ids = {"division", "swing", "morph_steps", "transition",
               "launch_quant", "follow_time", "follow_a", "follow_b",
               "follow_chance"}
  for _, id in ipairs(ids) do
    params:set(id, params:lookup_param(id).controlspec.default)
  end
  for i = 1, NUM_LANES do
    for _, f in ipairs({"div", "swing", "prob", "level", "mute", "follow",
                        "trans", "morph", "ftime", "fa", "fb", "fchance"}) do
      local id = lane_param(i, f)
      params:set(id, params:lookup_param(id).controlspec.default)
    end
  end
  params:set("bank", 1, true) -- silent: load_bank_now below does the work
  load_bank_now(1)
  for i = 1, NUM_LANES do
    lanes[i].active = 1
    lanes[i]:reset()
  end
  say("reset to factory")
end

local function clear_user_bank()
  for i = 1, NUM_LANES do user_bank[i] = empty_user_column(i) end
  if bank_is_user(current_bank) then load_bank_now(current_bank) end
  say("user bank cleared")
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

-- launch kit k of the current bank on every lane: one press for a whole
-- row of the launch grid
local function kit_launch(k)
  for i = 1, NUM_LANES do
    if playing then lanes[i]:launch(k)
    else lanes[i]:commit(k, Lane.TRANS_CUT) end
  end
  screen_dirty = true
end

local function follow_all()
  local anyoff = false
  for i = 1, NUM_LANES do
    if params:get(lane_param(i, "follow")) < 0.5 then anyoff = true end
  end
  for i = 1, NUM_LANES do
    params:set(lane_param(i, "follow"), anyoff and 1 or 0)
  end
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
--
--   row 1  BEAT REPEAT  hold a division                     (focus: hidden)
--   row 2  KITS         launch kit N on every lane
--   row 3  MUTE         per lane, toggle
--   row 4  SOLO         per lane, hold                      (focus: hidden)
--   row 5  FOLLOW       per lane, toggle
--   row 6  ROLL         per lane, hold                      (focus: hidden)
--   row 7  cols 1-4 GLOBAL transition | 5 play | 6 step edit |
--          7 copy playing kit to user | 8 follow all on/off
--   row 8  BANKS        generic house techno electro breaks var var2 user
--
-- redesigned 2026-09-21. what left the grid, and why: quantize and morph
-- up/down buttons (no feedback -- you could not tell what you had set
-- without reading the screen; they are screen fields and arc rings now),
-- panic (K1+K3 and PARAMS), reseed (PARAMS), and "store scene", which
-- "copy to user" supersedes -- a stored combination that is saved and
-- becomes a real kit, instead of one that evaporated.

-- FOCUS mode hides the performance layer so the parts still being proven
-- are what you are playing with. nothing is removed, just dark and inert.
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

  elseif row == 2 then                          -- launch kit N
    if on then kit_launch(col) end

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
    if col <= 4 then
      -- the GLOBAL transition: every lane still set to inherit follows it,
      -- any lane or kit with its own override keeps that
      params:set("transition", col)
    elseif col == 5 then toggle_play()
    elseif col == 6 then
      edit_mode = not edit_mode
      edit_page = 0
    elseif col == 7 then copy_to_user()
    elseif col == 8 then follow_all() end

  elseif row == 8 then                          -- banks
    if on then params:set("bank", col) end
  end
  touch()
end

local function fx_level(col, row)
  if row_hidden(row) then return 0 end
  local blink = math.floor(tick / 4) % 2 == 0
  if row == 1 then
    return rep_col == col and 15 or 3
  elseif row == 2 then
    -- how many lanes are on this kit right now
    local on = 0
    for i = 1, NUM_LANES do
      if lanes[i].active == col then on = on + 1 end
    end
    if on == NUM_LANES then return 12 end
    if on > 0 then return 6 end
    if bank_is_user(current_bank) and user_slot_empty(col) then return 1 end
    return 2
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
    if col == 5 then return playing and (blink and 15 or 8) or 3 end
    if col == 6 then return edit_mode and 15 or 3 end
    if col == 7 then return 4 end
    if col == 8 then
      for i = 1, NUM_LANES do
        if params:get(lane_param(i, "follow")) < 0.5 then return 3 end
      end
      return 9
    end
  elseif row == 8 then
    if bank_target == col then return blink and 15 or 4 end
    if current_bank == col then return bank_target and 8 or 15 end
    return 3
  end
  return 0
end

---------------------------------------------------------------- edit levels

-- WHERE AN EDIT LANDS. the screen edits one level of the inheritance chain
-- at a time, and GLOBAL is the default -- change a setting there and every
-- lane and kit that has not been given its own value follows. step down a
-- level to give one lane, one kit (that slot on every lane) or one pattern
-- a value of its own. the lowest value at the lane and pattern levels is
-- "inherit", so clearing an override is the same gesture as turning it
-- down past its lowest setting.
local L_GLOBAL, L_LANE, L_KIT, L_PATTERN = 1, 2, 3, 4
local LEVEL_NAMES = {"global", "lane", "kit", "pattern"}
local LEVEL_TAGS = {"glb", "lane", "kit", "pat"}
local edit_level_ = L_GLOBAL

local function sel_pattern() return lanes[sel_lane].bank[sel_slot] end

-- the value range a pattern override may take, per key. the lane params
-- carry the same ranges plus their sentinel below.
local RANGE = {
  follow_time   = {1, #Pattern.FOLLOW_TIMES, 1},
  follow_a      = {1, #Pattern.ACTIONS, 1},
  follow_b      = {1, #Pattern.ACTIONS, 1},
  follow_chance = {0, 100, 5},
  trans         = {1, #Lane.TRANS_NAMES, 1},
  quant         = {1, #Lane.QUANT_NAMES, 1},
}

local FMT = {
  follow_time   = function(v) return Pattern.FOLLOW_NAMES[v] or "?" end,
  follow_a      = function(v) return Pattern.ACTIONS[v] or "?" end,
  follow_b      = function(v) return Pattern.ACTIONS[v] or "?" end,
  follow_chance = function(v) return v .. "%" end,
  trans         = function(v) return Lane.TRANS_NAMES[v] or "?" end,
  quant         = function(v) return Lane.QUANT_NAMES[v] or "?" end,
  div           = function(v) return Lane.DIV_NAMES[v] or "?" end,
  swing         = function(v) return v == 0 and "straight" or (v .. "%") end,
  morph         = function(v) return v .. " st" end,
}

-- the next override value for pattern p after a turn of d. from "inherit",
-- turning up MATERIALISES the value you are already hearing, so the first
-- click changes the marker (inherited -> set here) and not the sound;
-- turning down past the bottom of the range goes back to inherit.
local function next_override(p, key, d, lane_i)
  local r = RANGE[key]
  local cur = p.ov[key]
  if cur == nil then
    if d > 0 then return parent_value(lane_i, key) end
    return nil
  end
  local nxt = cur + d * r[3]
  if nxt < r[1] then return nil end
  if nxt > r[2] then nxt = r[2] end
  return nxt
end

-- an inheritable field: shows the value at the current edit level, and
-- whether that value is set here or inherited from further up
local function inh_field(name, key)
  return {name = name, key = key,
    show = function()
      local v, inherited
      if edit_level_ == L_GLOBAL then
        v, inherited = global_value(key), false
      elseif edit_level_ == L_LANE then
        local lv = lane_value(sel_lane, key)
        if lv ~= nil then v, inherited = lv, false
        else v, inherited = global_value(key), true end
      else
        local p = sel_pattern()
        if p.ov[key] ~= nil then v, inherited = p.ov[key], false
        else v, inherited = parent_value(sel_lane, key), true end
      end
      return FMT[key](v), inherited
    end,
    delta = function(d)
      local spec = INHERIT[key]
      if edit_level_ == L_GLOBAL then
        params:delta(spec.global, d)
      elseif edit_level_ == L_LANE then
        local id = lane_param(sel_lane, spec.lane)
        if util.round(params:get(id)) == spec.inherit and d > 0 then
          params:set(id, global_value(key)) -- materialise, as above
        else
          params:delta(id, d)
        end
      elseif edit_level_ == L_PATTERN then
        local p = sel_pattern()
        p.ov[key] = next_override(p, key, d, sel_lane)
      else -- L_KIT: the same value written to this slot on every lane
        local nv = next_override(sel_pattern(), key, d, sel_lane)
        for i = 1, NUM_LANES do
          local p = lanes[i].bank[sel_slot]
          -- an empty pattern's "none" is what keeps a sat-out voice
          -- silent; a kit-wide edit must not overwrite it
          if not Pattern.is_empty(p) then p.ov[key] = nv end
        end
      end
    end}
end

-- a plain per-lane param, not inherited
local function lane_plain(name, suffix)
  return {name = name,
    show = function() return params:string(lane_param(sel_lane, suffix)), false end,
    delta = function(d) params:delta(lane_param(sel_lane, suffix), d) end}
end

local FIELDS = {
  follow   = inh_field("follow", "follow_time"),
  action_a = inh_field("action A", "follow_a"),
  action_b = inh_field("action B", "follow_b"),
  chance   = inh_field("chance", "follow_chance"),
  trans    = inh_field("transition", "trans"),
  quant    = inh_field("quant", "quant"),
  div      = inh_field("division", "div"),
  swing    = inh_field("swing", "swing"),
  morph    = inh_field("morph", "morph"),
  velocity = lane_plain("velocity", "level"),
  prob     = lane_plain("chance/trig", "prob"),
  length   = {name = "length",
    show = function() return sel_pattern().length .. " st", false end,
    delta = function(d)
      local p = sel_pattern()
      p.length = util.clamp(p.length + d, 1, 64)
    end},
  level    = {name = "level",
    show = function() return LEVEL_NAMES[edit_level_], false end,
    delta = function(d) edit_level_ = util.clamp(edit_level_ + d, 1, 4) end},
}

-- which fields each level can edit. a setting with no lane level (quant)
-- or no pattern level (division, swing, morph) simply does not appear
-- where it would mean nothing. `level` is last in every list so the field
-- E3 lands on by default is a value, not the level selector.
local LEVEL_FIELDS = {
  [L_GLOBAL]  = {"follow", "action_a", "action_b", "chance", "trans", "quant",
                 "div", "swing", "morph", "level"},
  [L_LANE]    = {"follow", "action_a", "action_b", "chance", "trans",
                 "div", "swing", "morph", "velocity", "prob", "level"},
  [L_KIT]     = {"follow", "action_a", "action_b", "chance", "trans", "quant",
                 "level"},
  [L_PATTERN] = {"follow", "action_a", "action_b", "chance", "trans", "quant",
                 "length", "level"},
}
-- focus mode trims the fields that answer no question about the follow
-- engine: the per-lane mix and the pattern length (a kit sets it)
local FOCUS_DROP = {velocity = true, prob = true, length = true}

local field_key = "follow"

local function field_list()
  local base = LEVEL_FIELDS[edit_level_]
  if pround("mode") ~= 1 then return base end
  local out = {}
  for _, k in ipairs(base) do
    if not FOCUS_DROP[k] then out[#out + 1] = k end
  end
  return out
end

local function field_index()
  local list = field_list()
  for i, k in ipairs(list) do if k == field_key then return i, list end end
  return 1, list
end

local function cur_field()
  local i, list = field_index()
  field_key = list[i]
  return FIELDS[field_key]
end

local function move_field(d)
  local i, list = field_index()
  field_key = list[util.clamp(i + d, 1, #list)]
end

---------------------------------------------------------------- params

-- norns' Control:delta moves the RAW 0-1 value by d/100 and ignores the
-- param's step, so a control with only a handful of steps needs a great
-- deal of encoder to move one of them (50 clicks to toggle a two-option
-- control). everything here is a `control` because garc only renders rings
-- for params with a controlspec, so the fix is to override the param's own
-- delta: for anything with 100 steps or fewer, one click is one step. that
-- also makes garc's ring smoothing correct, since it already assumed it.
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

-- VOICE ROUTING holds the real (channel, note) for each of the 12 voices;
-- "note layout" and "midi channel" are presets that write into it. nothing
-- reads the layout at send time, so the two can never disagree.
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

-- a lane param with an "inherit" sentinel at the bottom of its range
local function add_inherit(id, name, hi, step, sentinel, default, fmt)
  add_ctl(id, name, controlspec.new(sentinel, hi, "lin", step, default, ""))
  params:lookup_param(id).formatter = function(p)
    local v = util.round(p:get())
    if v == sentinel then return "global" end
    return fmt(v)
  end
end

local function add_params()
  params:add_separator("segue_head", "segue")

  params:add_group("segue_global", "GLOBAL", 7)

  -- FOCUS is the default while the follow engine and the kit library are
  -- the things being judged: it dims the performance rows on the FX grid
  -- and trims the screen's field list. FULL turns everything back on.
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
    screen_dirty = true
  end)

  -- NEW BANKS GO AT THE END: psets store the option's number
  params:add_option("bank", "bank", Library.bank_names(), 1)
  params:set_action("bank", function(v) select_bank(v) end)

  -- the standard norns device picker: the vport number on its own tells you
  -- nothing about which box is on the other end
  local midi_devices = {}
  for i = 1, 16 do
    local name = midi.vports[i].name or "none"
    if name == nil or name == "" then name = "none" end
    if #name > 15 then name = util.acronym(name) end
    midi_devices[i] = i .. ": " .. name
  end
  params:add_option("midi_out", "midi out", midi_devices, 1)
  params:set_action("midi_out", function(v)
    midi_dev = midi.connect(v)
    if voices_out then voices_out.dev = midi_dev end
  end)

  params:add_number("midi_channel", "midi channel", 1, 16, 1)
  params:set_action("midi_channel", function() stamp_layout() end)

  params:add_option("note_layout", "note layout", Voices.LAYOUT_NAMES,
                    Voices.LAYOUT_SEQ)
  params:set_action("note_layout", function() stamp_layout() end)

  add_ctl("hat_choke", "closed hat chokes open",
    controlspec.new(0, 1, "lin", 1, 0, ""))
  params:lookup_param("hat_choke").formatter = function(p)
    return p:get() > 0.5 and "on" or "off"
  end

  params:add_trigger("panic", "panic")
  params:set_action("panic", function() if voices_out then voices_out:panic() end end)

  -------------------------------------------------------------- defaults
  -- the GLOBAL level of the inheritance chain. every lane and kit follows
  -- these unless it has been given a value of its own. division, swing and
  -- morph are resolved into the lanes on change (they are read every
  -- tick); the rest resolve when a switch happens, so their actions only
  -- need to repaint.
  params:add_group("segue_defaults", "DEFAULTS", 9)

  local function resync() sync_all_lanes() screen_dirty = true end
  local function repaint() screen_dirty = true end

  add_ctl("division", "division",
    controlspec.new(1, #Lane.DIV_NAMES, "lin", 1, Lane.DIV_16TH, ""),
    function(p) return Lane.DIV_NAMES[util.round(p:get())] end)
  params:set_action("division", resync)

  add_ctl("swing", "swing", controlspec.new(0, Lane.SWING_MAX, "lin", 1, 0, ""),
    function(p) return FMT.swing(util.round(p:get())) end)
  params:set_action("swing", resync)

  add_ctl("morph_steps", "morph steps", controlspec.new(1, 32, "lin", 1, 8, "st"))
  params:set_action("morph_steps", resync)

  add_ctl("transition", "transition",
    controlspec.new(1, #Lane.TRANS_NAMES, "lin", 1, Lane.TRANS_LEGATO, ""),
    function(p) return Lane.TRANS_NAMES[util.round(p:get())] end)
  params:set_action("transition", repaint)

  add_ctl("launch_quant", "launch quant",
    controlspec.new(1, #Lane.QUANT_NAMES, "lin", 1, Lane.DEFAULTS.quant, ""),
    function(p) return Lane.QUANT_NAMES[util.round(p:get())] end)
  params:set_action("launch_quant", repaint)

  add_ctl("follow_time", "follow time",
    controlspec.new(1, #Pattern.FOLLOW_TIMES, "lin", 1, Pattern.FOLLOW_IDX_END, ""),
    function(p) return Pattern.FOLLOW_NAMES[util.round(p:get())] end)
  params:set_action("follow_time", repaint)

  add_ctl("follow_a", "follow action A",
    controlspec.new(1, #Pattern.ACTIONS, "lin", 1, Pattern.ACTION_NONE, ""),
    function(p) return Pattern.ACTIONS[util.round(p:get())] end)
  params:set_action("follow_a", repaint)

  add_ctl("follow_b", "follow action B",
    controlspec.new(1, #Pattern.ACTIONS, "lin", 1, Pattern.ACTION_NONE, ""),
    function(p) return Pattern.ACTIONS[util.round(p:get())] end)
  params:set_action("follow_b", repaint)

  add_ctl("follow_chance", "follow chance",
    controlspec.new(0, 100, "lin", 5, 100, "%"),
    function(p) return util.round(p:get()) .. "%" end)
  params:set_action("follow_chance", repaint)

  -------------------------------------------------------------- per lane
  -- the LANE level. an inheritable setting's lowest value is "global".
  -- the library's per-lane follow behaviour (toms step on, hats drift) is
  -- written in as these params' defaults, so a fresh boot and "reset"
  -- both land on it.
  for i = 1, NUM_LANES do
    local spec = Library.LANES[i]
    local fo = spec.follow or {}
    params:add_group("segue_lane_" .. i, i .. " " .. spec.name, 12)

    add_inherit(lane_param(i, "div"), "division", #Lane.DIV_NAMES, 1, 0, 0,
      FMT.div)
    add_inherit(lane_param(i, "swing"), "swing", Lane.SWING_MAX, 1, -1, -1,
      FMT.swing)
    add_ctl(lane_param(i, "prob"), "chance / trig",
      controlspec.new(0, 1, "lin", 0.01, 1, ""))
    -- `level` is the id psets know it by (CONVENTIONS §5: ids are
    -- permanent), shown as "velocity" because that is what it is: a scale
    -- on every hit's velocity. capped at 1.0 so it can only turn things
    -- down -- above 1 it clipped accents and normals together at 127 and
    -- erased the dynamics the kits are written in.
    add_ctl(lane_param(i, "level"), "velocity",
      controlspec.new(0, 1, "lin", 0.01, 1, ""),
      function(p) return math.floor(p:get() * 100 + 0.5) .. "%" end)
    add_ctl(lane_param(i, "mute"), "mute",
      controlspec.new(0, 1, "lin", 1, 0, ""),
      function(p) return p:get() > 0.5 and "muted" or "on" end)
    add_ctl(lane_param(i, "follow"), "follow",
      controlspec.new(0, 1, "lin", 1, 1, ""),
      function(p) return p:get() > 0.5 and "on" or "off" end)
    add_inherit(lane_param(i, "trans"), "transition", #Lane.TRANS_NAMES, 1,
      0, 0, FMT.trans)
    add_inherit(lane_param(i, "morph"), "morph steps", 32, 1, 0, 0,
      FMT.morph)
    add_inherit(lane_param(i, "ftime"), "follow time", #Pattern.FOLLOW_TIMES,
      1, 0, fo.follow_time or 0, FMT.follow_time)
    add_inherit(lane_param(i, "fa"), "follow action A", #Pattern.ACTIONS, 1,
      0, fo.follow_a or 0, FMT.follow_a)
    add_inherit(lane_param(i, "fb"), "follow action B", #Pattern.ACTIONS, 1,
      0, fo.follow_b or 0, FMT.follow_b)
    add_inherit(lane_param(i, "fchance"), "follow chance", 100, 5, -5,
      fo.follow_chance or -5, FMT.follow_chance)

    for _, f in ipairs({"div", "swing", "prob", "level", "mute", "follow",
                        "trans", "morph", "ftime", "fa", "fb", "fchance"}) do
      params:set_action(lane_param(i, f), function()
        sync_lane_from_params(i)
        screen_dirty = true
      end)
    end
  end

  -------------------------------------------------------------- routing
  params:add_group("segue_routing", "VOICE ROUTING", Voices.COUNT * 2)
  for v = 1, Voices.COUNT do
    local def_ch, def_note = Voices.layout_address(Voices.LAYOUT_SEQ, v, 1)
    params:add_number("voice_" .. v .. "_chan", Voices.NAMES[v] .. " channel",
                      1, 16, def_ch)
    params:set_action("voice_" .. v .. "_chan", function(val)
      if voices_out then voices_out:set_address(v, val, nil) end
    end)
    params:add_number("voice_" .. v .. "_note", Voices.NAMES[v] .. " note",
                      0, 127, def_note)
    params:set_action("voice_" .. v .. "_note", function(val)
      if voices_out then voices_out:set_address(v, nil, val) end
    end)
  end
  -- from here on a layout change can write into the params above
  routing_ready = true

  -------------------------------------------------------------- arc
  params:add_group("segue_arc", "ARC", 4)
  add_ctl("arc_threshold", "sensitivity", controlspec.new(1, 20, "lin", 1, 6, ""))
  add_ctl("arc_brightness", "brightness", controlspec.new(1, 15, "lin", 1, 10, ""))
  add_ctl("arc_dim", "tick level", controlspec.new(0, 15, "lin", 1, 2, ""))
  add_ctl("arc_position", "orientation", controlspec.new(1, 4, "lin", 1, 1, ""))
end

---------------------------------------------------------------- persistence

-- two files, on purpose:
--
--   segue-user.data   the user bank. it is YOUR library, so it lives on
--                     its own and no pset load can overwrite it -- loading
--                     an old pset must not quietly throw away the kits you
--                     have built since.
--   segue-last.data   which bank you were on and which kit each lane was
--   segue-<n>.data    playing (the autosave, and one per pset). settings
--                     are params, so psets carry those themselves.
--
-- factory banks are never saved at all: they are read-only, and loading
-- them always gives exactly what shipped (see bank_column).
local function data_path(filename) return norns.state.data .. filename end

local function save_table(t, filename)
  local okw, err = pcall(function() tab.save(t, data_path(filename)) end)
  if not okw then print("segue: could not save " .. filename .. ": " .. tostring(err)) end
end

local function load_table(filename)
  local path = data_path(filename)
  if not util.file_exists(path) then return nil end
  local okr, d = pcall(function() return tab.load(path) end)
  if okr and type(d) == "table" then return d end
  print("segue: could not load " .. filename)
  return nil
end

local function save_user_bank()
  local d = {}
  for i = 1, NUM_LANES do d[i] = Lane.pack_column(user_bank[i]) end
  save_table({user = d}, "segue-user.data")
end

local function load_user_bank()
  local d = load_table("segue-user.data")
  for i = 1, NUM_LANES do
    local spec = Library.LANES[i]
    if d and d.user and d.user[i] then
      user_bank[i] = Lane.unpack_column(d.user[i], Pattern, #spec.voices)
    else
      user_bank[i] = empty_user_column(i)
    end
  end
end

local function collect_state()
  local d = {bank = current_bank, actives = {}}
  for i = 1, NUM_LANES do d.actives[i] = lanes[i].active end
  return d
end

local function apply_state(d)
  if type(d) ~= "table" then return end
  if d.bank and Library.BANKS[d.bank] then
    -- silent, then load directly: a restore lands at once rather than
    -- queueing a hand-off the way a live bank change does
    params:set("bank", d.bank, true)
    load_bank_now(d.bank)
  end
  if d.actives then
    for i = 1, NUM_LANES do
      local a = d.actives[i]
      if a and a >= 1 and a <= Lane.PATTERN_COUNT then lanes[i].active = a end
    end
  end
  sync_all_lanes()
  screen_dirty = true
end

---------------------------------------------------------------- init

local function build_lanes()
  for i = 1, NUM_LANES do
    local spec = Library.LANES[i]
    -- the lane's inheritance parent: its own param, else the global one
    lanes[i] = Lane:new{pattern_lib = Pattern, id = i, name = spec.name,
                        voices = spec.voices,
                        parent = function(key) return parent_value(i, key) end}
  end
end

local function build_arc()
  -- rings follow the EDIT LEVEL: at global they turn the global param, at
  -- any other level the selected lane's. the arc binds to params, and the
  -- pattern level is data, so kit/pattern fall back to the lane.
  --
  -- K1 held broadcasts a ring to every lane (garc's all_ids). at global
  -- level there is nothing to broadcast to, so all_ids returns just the
  -- global -- an empty list would make the turn do nothing at all.
  local function ring(label, key)
    local spec = INHERIT[key]
    return {label = label,
      id = function()
        if edit_level_ == L_GLOBAL or spec.lane == nil then return spec.global end
        return lane_param(sel_lane, spec.lane)
      end,
      all_ids = function()
        if edit_level_ == L_GLOBAL or spec.lane == nil then return {spec.global} end
        local t = {}
        for i = 1, NUM_LANES do t[i] = lane_param(i, spec.lane) end
        return t
      end}
  end
  local function lane_ring(label, suffix)
    return {label = label,
      id = function() return lane_param(sel_lane, suffix) end,
      all_ids = function()
        local t = {}
        for i = 1, NUM_LANES do t[i] = lane_param(i, suffix) end
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
        ring("div", "div"),
        ring("swing", "swing"),
        lane_ring("chance", "prob"),
        lane_ring("vel", "level"),
      }},
      {name = "MORPH", rings = {
        ring("trans", "trans"),
        ring("morph", "morph"),
        ring("quant", "quant"),
        {label = "lane", id = "sel_lane"},
      }},
    }}
end

function init()
  math.randomseed(util.time() * 1000)

  build_lanes()
  load_user_bank()
  add_params()

  -- a param purely so the arc has something to turn for lane select; it is
  -- the same value E1 moves, mirrored so both stay in step
  add_ctl("sel_lane", "lane", controlspec.new(1, NUM_LANES, "lin", 1, 1, ""),
    function(p)
      return util.round(p:get()) .. " " .. Library.LANES[util.round(p:get())].name
    end)
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
  params:add_trigger("copy_user", "copy playing kit to user")
  params:set_action("copy_user", function() copy_to_user() save_user_bank() end)
  params:add_trigger("reset_defaults", "reset to factory")
  params:set_action("reset_defaults", reset_to_defaults)
  params:add_trigger("clear_user", "clear user bank")
  params:set_action("clear_user", function() clear_user_bank() save_user_bank() end)

  params.action_write = function(filename, name, number)
    save_table(collect_state(), "segue-" .. number .. ".data")
  end
  params.action_read = function(filename, silent, number)
    apply_state(load_table("segue-" .. number .. ".data"))
  end
  params.action_delete = function(filename, name, number)
    local path = data_path("segue-" .. number .. ".data")
    if util.file_exists(path) then os.remove(path) end
  end

  -- norns clears these on unload, so they are assigned here (CONVENTIONS §6)
  clock.transport.start = function() if not playing then start_playing() end end
  clock.transport.stop = function() stop_playing() end

  -- the repeat buffer's bucket headers, built once rather than on the first
  -- press; the hit tables inside are created on demand (see rep_put)
  for o = 0, REPEAT_MAX - 1 do rep_slot(o) end

  load_bank_now(1)
  params:bang()
  sync_all_lanes()

  -- which bank and kits you were on come back without sending anything
  apply_state(load_table("segue-last.data"))

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
    if shift then move_field(d) else cur_field().delta(d) end
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
local NOTICE_HOLD = 1.5
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
-- poses. a pending bank switch and a queued launch outrank a follow action,
-- because you asked for those explicitly.
local function next_text(l)
  local quant = Lane.QUANT_TICKS[pround("launch_quant")]
  local n = l:steps_to_launch(tick, quant)
  if n then
    local dest
    if l.queued then dest = l.bank[l.queued].name
    else dest = Library.BANKS[bank_target or current_bank].name .. " bank" end
    return "> " .. dest .. (n > 0 and ("  " .. n) or "  now")
  end

  local trans = Lane.TRANS_NAMES[l:setting("trans")] or "?"
  if rep_col then return trans .. "  rpt " .. REPEAT_NAMES[rep_col] end

  local f = l:steps_to_follow()
  if f then
    local act = Pattern.ACTIONS[l:setting("follow_a")] or "?"
    return trans .. "  " .. act .. " " .. f
  end
  return trans .. "  q " .. Lane.QUANT_NAMES[pround("launch_quant")]
end

function redraw()
  screen.clear()
  screen.aa(0)

  local l = lanes[sel_lane]
  local p = l.bank[sel_slot]

  -- header: bank, then the lane and kit the encoders are pointed at
  screen.level(15)
  screen.move(0, 7)
  screen.text(Library.BANKS[current_bank].short or "?")
  screen.move(20, 7)
  screen.text(Library.LANES[sel_lane].name)
  screen.level(6)
  screen.move(46, 7)
  screen.text(p.name)
  screen.level(playing and 12 or 3)
  screen.move(128, 7)
  screen.text_right("" .. math.floor(clock.get_tempo() + 0.5))

  -- the bank: lanes across, kits down. this is the launch grid on screen.
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

  -- selection marker under the chosen lane / beside the chosen kit
  screen.level(15)
  local sx = MATRIX_X + (sel_lane - 1) * COL_W
  screen.rect(sx, MATRIX_Y - 3, 6, 1)
  screen.fill()
  screen.rect(MATRIX_X - 3, MATRIX_Y + (sel_slot - 1) * ROW_H, 1, 3)
  screen.fill()

  -- the field E3 is editing: which level it lands on, then its value --
  -- bright if set at this level, dim if it is inherited from further up
  local f = cur_field()
  local val, inherited = f.show()
  screen.move(0, 54)
  screen.level(15)
  screen.text("[" .. LEVEL_TAGS[edit_level_] .. "] ")
  screen.level(10)
  screen.text(f.name .. " ")
  screen.level(inherited and 4 or 15)
  screen.text(val)

  -- bottom line, in order of urgency: the step editor, a one-off notice, the
  -- arc just after a ring moved, and otherwise what happens next
  screen.level(4)
  screen.move(0, 62)
  if edit_mode then
    screen.level(15)
    screen.text("EDIT " .. (edit_page * 8 + 1) .. "-" ..
                math.min(p.length, edit_page * 8 + 8) .. "/" .. p.length ..
                (bank_is_user(current_bank) and "" or "  temp"))
  elseif notice and (util.time() - notice_at) < NOTICE_HOLD then
    screen.level(15)
    screen.text(notice)
  elseif arc_fresh() then
    screen.text(garc_:footer_text())
  else
    screen.text(next_text(l))
  end

  screen.update()
end

---------------------------------------------------------------- cleanup

-- what norns cannot do for us (CONVENTIONS §3): the note-offs, and saving
-- what the params do not hold. norns cancels the clocks itself.
function cleanup()
  if voices_out then voices_out:panic() end
  if gridui then gridui:cleanup() end
  if lanes[1] then
    save_table(collect_state(), "segue-last.data")
    save_user_bank()
  end
end
