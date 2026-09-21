-- drives segue.lua against the stubbed norns runtime: init, the transport
-- clock, every key/encoder combination, the grid surfaces, redraw, pset
-- round trip and cleanup.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1; S.real_print("  FAIL: " .. msg) end
end
local function section(s) S.real_print("\n== " .. s) end
local function try(what, fn)
  local okc, err = pcall(fn)
  ok(okc, what .. " -> " .. tostring(err))
  return okc
end

S.add_system_params()
dofile(S.SEGUE_DIR .. "segue.lua")

---------------------------------------------------------------- init
section("init")
ok(type(init) == "function", "init() is defined")
ok(type(redraw) == "function", "redraw() is defined")
ok(type(key) == "function", "key() is defined")
ok(type(enc) == "function", "enc() is defined")
ok(type(cleanup) == "function", "cleanup() is defined")
ok(rawget(_G, "engine") == nil, "no engine is set (MIDI-out only)")

try("init() runs clean", init)

local Lane = S.upvalue(redraw, "Lane")
ok(Lane ~= nil, "the Lane module is reachable for its timing constants")
local BAR = Lane.TICKS_PER_BAR      -- ticks in one bar
local QUARTER = BAR / 4             -- ticks in one beat

ok(params.by_id["lane_1_div"] ~= nil, "per-lane params exist")
ok(params.by_id["voice_12_note"] ~= nil, "voice routing params exist")
ok(params.by_id["launch_quant"] ~= nil, "launch quant param exists")
ok(params.by_id["arc_threshold"] ~= nil, "arc params exist")

-- every add_group promised a count; check each got exactly that many
for _, g in ipairs(params.groups) do
  ok(g.added == g.n, "group '" .. g.name .. "' declared " .. g.n ..
     " params and added " .. g.added)
end

-- every control param bound to the arc must have a controlspec, or the
-- ring silently never lights (garc skips params without one)
for _, id in ipairs({"lane_1_div", "lane_1_swing", "lane_1_prob",
                     "lane_1_level", "lane_1_trans", "lane_1_morph",
                     "launch_quant", "sel_lane"}) do
  ok(params.by_id[id] and params.by_id[id].controlspec ~= nil,
     id .. " has a controlspec so the arc can render it")
end

-- every param must format without blowing up
for _, p in ipairs(params.list) do
  local okf, err = pcall(function() return p:string() end)
  ok(okf, "formatter for " .. p.id .. " -> " .. tostring(err))
end

---------------------------------------------------------------- encoder feel
section("encoder response")
-- norns' Control:delta moves the raw 0-1 value by d/100 and ignores the
-- step, so a discrete control takes many clicks to move one step -- 50 to
-- toggle a two-option one. every control here is meant to override that.
-- (an earlier version of the stub moved by one step itself, which was
-- kinder than the hardware and hid this from the whole suite.)
local sluggish = {}
for _, p in ipairs(params.list) do
  local cs = p.controlspec
  if cs and cs.step and cs.step > 0 then
    local steps = (cs.maxval - cs.minval) / cs.step
    local restore = params:get(p.id)
    -- park at the bottom: a 0-1 step-1 control has nowhere above its
    -- midpoint to go, and half this script's controls are that shape
    params:set(p.id, cs.minval)
    params:delta(p.id, 1)
    local moved = params:get(p.id) - cs.minval
    -- wide controls keep norns' default; note `x and nil or y` cannot
    -- express that, since nil is falsy and the `or` branch always wins
    local want = cs.step
    if steps > 100 then want = nil end
    if want and math.abs(moved - want) > 1e-9 then
      sluggish[#sluggish + 1] = p.id .. " moved " .. moved ..
                                " (want " .. want .. ")"
    end
    params:delta(p.id, -1)
    if want and math.abs(params:get(p.id) - cs.minval) > 1e-9 then
      sluggish[#sluggish + 1] = p.id .. " did not come back down"
    end
    params:set(p.id, restore)
  end
end
ok(#sluggish == 0, "one encoder click moves one step on every control" ..
   (#sluggish > 0 and (" -- " .. table.concat(sluggish, "; ")) or ""))

-- spot-check the worst offenders by name, so a regression names itself
for _, id in ipairs({"mode", "transition", "lane_1_mute", "lane_1_swing",
                     "lane_1_div", "launch_quant"}) do
  local cs = params.by_id[id].controlspec
  local restore = params:get(id)
  params:set(id, cs.minval)
  params:delta(id, 1)
  ok(math.abs(params:get(id) - (cs.minval + cs.step)) < 1e-9,
     id .. ": one click moves one step (got " .. params:get(id) ..
     ", want " .. (cs.minval + cs.step) .. ")")
  params:set(id, restore)
end

---------------------------------------------------------------- redraw
section("redraw")
try("redraw() runs clean", redraw)
ok(S.draws > 0, "redraw drew some text")

---------------------------------------------------------------- transport
section("transport / clock")
S.midi_sent = {}
key(3, 1) -- play
key(3, 0)
ok(#S.midi_sent > 0 and S.midi_sent[1].t == "start", "play sent MIDI start")

-- the transport clock is the last coroutine started before the redraw one;
-- find it by walking what init left behind
-- make sure the transport is running and hand back its coroutine id. the
-- FX sweep below presses the script's own play/stop button, so this has to
-- be re-asked for rather than captured once.
local function transport()
  if not S.upvalue(redraw, "playing") then key(3, 1) key(3, 0) end
  local id
  for i = 1, #S.coros do
    if S.coros[i] and coroutine.status(S.coros[i]) == "suspended" then
      id = i -- the last one started is the transport
    end
  end
  return id
end

local clock_id = transport()
ok(clock_id ~= nil, "a transport clock coroutine is running")

S.midi_sent = {}
try("one bar of transport", function() S.advance(clock_id, BAR) end)
local notes = 0
for _, m in ipairs(S.midi_sent) do if m.t == "on" then notes = notes + 1 end end
S.real_print("  " .. notes .. " notes in the first bar")
ok(notes > 10, "the first bar actually played something")

-- every note-on is matched by a note-off on the same note+channel
local held = {}
for _, m in ipairs(S.midi_sent) do
  local k = m.ch .. ":" .. m.note
  if m.t == "on" then held[k] = (held[k] or 0) + 1
  elseif m.t == "off" then held[k] = (held[k] or 0) - 1 end
end
local stuck = 0
for _, v in pairs(held) do if v > 0 then stuck = stuck + 1 end end
ok(stuck <= 8, "no pile-up of unreleased notes (" .. stuck ..
   " outstanding at the bar line)")

-- the default layout puts every voice on channel 1 at notes 0-11
local bad_ch, bad_note = 0, 0
for _, m in ipairs(S.midi_sent) do
  if m.t == "on" then
    if m.ch ~= 1 then bad_ch = bad_ch + 1 end
    if m.note < 0 or m.note > 11 then bad_note = bad_note + 1 end
  end
end
ok(bad_ch == 0, "every note went to channel 1 (" .. bad_ch .. " did not)")
ok(bad_note == 0, "every note was in 0-11 (" .. bad_note .. " were not)")

-- and the controls that pick that layout actually do something -- the bug
-- this replaced was a dead scheme control shadowed by per-voice defaults
ok(params:get("midi_channel") == 1, "midi channel defaults to 1")
ok(params:get("voice_1_note") == 0, "BD defaults to note 0")
ok(params:get("voice_2_note") == 1, "SD defaults to note 1")
ok(params:get("voice_12_note") == 11, "CB defaults to note 11")

params:set("midi_channel", 7)
ok(params:get("voice_1_chan") == 7,
   "changing midi channel restamps the voices (got " ..
   params:get("voice_1_chan") .. ")")
params:set("note_layout", 3) -- track channels 1-12
ok(params:get("voice_9_chan") == 9 and params:get("voice_9_note") == 60,
   "the track-channel layout restamps to ch 9 / note 60 (got ch " ..
   params:get("voice_9_chan") .. " note " .. params:get("voice_9_note") .. ")")
params:set("note_layout", 2) -- factory notes
ok(params:get("voice_1_note") == 36, "the factory layout restamps to note 36")
params:set("note_layout", 1)
params:set("midi_channel", 1)
ok(params:get("voice_1_chan") == 1 and params:get("voice_1_note") == 0,
   "back to the default layout")

-- a hand-edited voice survives until a layout is chosen again
params:set("voice_3_note", 99)
ok(params:get("voice_3_note") == 99, "a per-voice note can be hand-edited")
S.midi_sent = {}
try("a bar with a hand-edited voice", function() S.advance(clock_id, BAR) end)
params:set("note_layout", 1) -- restamping clears it, by design
ok(params:get("voice_3_note") == 2, "choosing a layout again overwrites it")

try("redraw while playing", redraw)

try("seven more bars", function() S.advance(clock_id, BAR * 7) end)

---------------------------------------------------------------- clock sync
section("clock alignment")
-- the grid used to be measured from the moment you pressed play, so under
-- Link the script ran at the right tempo at an arbitrary phase and landing
-- on the beat was down to when you hit the key. it comes from
-- clock.get_beats() now, so the same musical position always gives the
-- same step.
local SL = S.get_lanes()

-- stop, move the shared clock to `beats`, start, and report where lane 1's
-- playhead landed on its very first step
local function start_at(beats, source)
  if S.upvalue(redraw, "playing") then key(3, 1) key(3, 0) end
  params:set("clock_source", source)
  S.beats = beats
  key(3, 1) key(3, 0)
  local id = transport()
  for _ = 1, 64 do
    S.advance(id, 1)
    if SL[1].started then break end
  end
  return SL[1].pos
end

-- lane 1 plays the amen: 32 steps of 1/16, so the pattern is exactly two
-- bars long. two positions eight beats apart are the same place in it.
ok(start_at(4.0, 3) == start_at(12.0, 3),
   "shared clock: two bars apart gives the same step")
ok(start_at(4.0, 3) ~= start_at(5.0, 3),
   "shared clock: one beat apart gives a different step")
-- and the step it lands on is the phase-correct one for the tick it fired
-- on, not merely a repeatable one. (starting exactly at beat 0 lands on
-- step 2, not step 1: clock.sync waits for the next subdivision, so the
-- boundary at tick 0 is already in the past. that is right -- the first
-- 16th after the downbeat *is* step 2.)
local dtv = Lane.DIV_TICKS[math.floor(params:get("lane_1_div"))]
for _, b in ipairs({0.0, 4.0, 13.75, 37.25}) do
  local pos = start_at(b, 3)
  local len = SL[1].bank[SL[1].active].length
  local k = math.floor(math.floor(S.beats * Lane.PPQN + 0.5) / dtv)
  ok(pos == (k % len) + 1,
     "shared clock at beat " .. b .. ": phase-correct step (want " ..
     ((k % len) + 1) .. ", got " .. pos .. ")")
end

-- on the internal clock there is nobody to agree with, so pressing play
-- begins the phrase where you pressed it
ok(start_at(4.0, 1) == 1, "internal clock: starts at step 1")
ok(start_at(37.25, 1) == 1, "internal clock: still step 1 from anywhere")

-- and the transport keeps running cleanly from a non-zero origin
params:set("clock_source", 3)
S.beats = 101.5
if S.upvalue(redraw, "playing") then key(3, 1) key(3, 0) end
key(3, 1) key(3, 0)
S.midi_sent = {}
try("a bar from a mid-bar shared-clock start", function()
  S.advance(transport(), BAR)
end)
local late_notes = 0
for _, m in ipairs(S.midi_sent) do
  if m.t == "on" then late_notes = late_notes + 1 end
end
ok(late_notes > 10, "a late join still plays a full bar (" ..
   late_notes .. " notes)")
params:set("clock_source", 1)

---------------------------------------------------------------- grid
section("grid")
ok(S.grid_leds ~= nil, "grid stub is wired")
local gridui_redrawn = false
for _, m in ipairs(S.metros) do
  if m.event then
    local okm, err = pcall(m.event)
    ok(okm, "grid refresh metro -> " .. tostring(err))
    gridui_redrawn = true
  end
end
ok(gridui_redrawn, "a grid refresh metro was registered")
ok(#S.grid_leds > 0, "the grid refresh lit something (" ..
   #S.grid_leds .. " leds)")

-- every launch cell, pressed and released
try("pressing every LAUNCH cell", function()
  for x = 1, 8 do
    for y = 1, 8 do
      S.grid_key(1, x, y, 1)
      S.grid_key(1, x, y, 0)
    end
  end
end)

-- every FX cell (right half of the 128), pressed and released
try("pressing every FX cell", function()
  for x = 9, 16 do
    for y = 1, 8 do
      S.grid_key(1, x, y, 1)
      S.advance(transport(), 12)
      S.grid_key(1, x, y, 0)
    end
  end
end)
try("redraw after the FX sweep", redraw)
try("grid redraw after the FX sweep", function()
  for _, m in ipairs(S.metros) do if m.event then m.event() end end
end)

-- the sweep above walked over the mute row, so put every lane back on
for i = 1, 8 do
  params:set("lane_" .. i .. "_mute", 0)
  params:set("lane_" .. i .. "_follow", 1)
end

-- beat repeat: the first pass through the window records, every pass after
-- that replays it, so two consecutive windows must be identical
local function notes_on()
  local out = {}
  for _, m in ipairs(S.midi_sent) do
    if m.t == "on" then out[#out + 1] = m.ch .. "/" .. m.note .. "/" .. m.vel end
  end
  return out
end

-- FOCUS mode (the default) dims the performance rows, so prove that first
-- and then switch to FULL for the beat-repeat check below
params:set("mode", 1)
-- init() closes over fx_level to hand it to GridUI, so that is where it can
-- be reached from (redraw() never mentions it)
local GridUI_L = S.upvalue(init, "fx_level")
ok(type(GridUI_L) == "function", "the fx level function is reachable")
if GridUI_L then
  local dark = true
  for _, row in ipairs({1, 4, 6}) do
    for c = 1, 8 do if GridUI_L(c, row) ~= 0 then dark = false end end
  end
  ok(dark, "focus mode leaves rows 1, 4 and 6 dark")
  local lit = false
  for _, row in ipairs({2, 3, 5, 7, 8}) do
    for c = 1, 8 do if GridUI_L(c, row) > 0 then lit = true end end
  end
  ok(lit, "focus mode keeps the rows it does show lit")
end
-- a press on a hidden row must do nothing at all
local rep_before = S.upvalue(redraw, "rep_col")
S.grid_key(1, 10, 1, 1)
ok(S.upvalue(redraw, "rep_col") == rep_before,
   "a press on a hidden row is inert")
S.grid_key(1, 10, 1, 0)

params:set("mode", 2) -- full
if GridUI_L then
  local lit = false
  for c = 1, 8 do if GridUI_L(c, 1) > 0 then lit = true end end
  ok(lit, "full mode lights row 1 again")
end

clock_id = transport()
S.grid_key(1, 10, 1, 1) -- FX row 1 col 2 = 1/4 repeat (24 ticks)
S.midi_sent = {}
try("first repeat window (records)", function() S.advance(clock_id, QUARTER) end)
local win_a = notes_on()
S.midi_sent = {}
try("second repeat window (replays)", function() S.advance(clock_id, QUARTER) end)
local win_b = notes_on()
S.grid_key(1, 10, 1, 0)

ok(#win_a > 0, "the repeat window captured something (" .. #win_a .. " notes)")
ok(#win_a == #win_b, "the replayed window has the same note count (" ..
   #win_a .. " vs " .. #win_b .. ")")
local same = #win_a == #win_b
for i = 1, math.min(#win_a, #win_b) do
  if win_a[i] ~= win_b[i] then same = false end
end
ok(same, "the replayed window is note-for-note the captured one")

S.midi_sent = {}
try("a beat after releasing it", function() S.advance(clock_id, QUARTER) end)
ok(#notes_on() > 0, "the lanes resume playing live after the release (" ..
   #notes_on() .. " notes)")

-- solo, held then released
S.grid_key(1, 9, 4, 1) -- FX row 4 col 1 = solo lane 1
try("a few steps with a lane soloed", function() S.advance(transport(), QUARTER) end)
S.grid_key(1, 9, 4, 0)

---------------------------------------------------------------- step editor
section("step editor")
local L = S.get_lanes()
-- point at a known lane/slot, then turn the editor on (FX row 8 col 6)
-- FX row 8 col 6 is a toggle and the blind sweep above already hit it, so
-- drive it to a known state rather than assuming which way it is facing
local function set_edit(want)
  if S.upvalue(redraw, "edit_mode") ~= want then
    S.grid_key(1, 14, 8, 1) S.grid_key(1, 14, 8, 0)
  end
end

params:set("sel_lane", 1)
set_edit(false)
S.grid_key(1, 1, 3, 1) S.grid_key(1, 1, 3, 0) -- launch lane 1 slot 3
set_edit(true)
ok(S.upvalue(redraw, "edit_mode") == true, "the editor turned on")

local p = L[1].bank[3]
local before = p.trigs[1][2]
S.grid_key(1, 2, 1, 1) S.grid_key(1, 2, 1, 0) -- step 2, slot 1
ok(p.trigs[1][2] ~= before, "a grid press changed step 2 (" ..
   tostring(before) .. " -> " .. tostring(p.trigs[1][2]) .. ")")

-- cycling all the way round returns the cell to where it started
local start = p.trigs[1][5]
for _ = 1, 4 do S.grid_key(1, 5, 1, 1) S.grid_key(1, 5, 1, 0) end
ok(p.trigs[1][5] == start, "four presses cycle a step back to its start")

-- page 2 edits steps 9-16, not steps 1-8 again
S.grid_key(1, 2, 7, 1) S.grid_key(1, 2, 7, 0) -- row 7 col 2 = page 2
local was9 = p.trigs[1][9]
S.grid_key(1, 1, 1, 1) S.grid_key(1, 1, 1, 0)
ok(p.trigs[1][9] ~= was9, "on page 2, column 1 edits step 9")

try("redraw in edit mode", redraw)
try("grid redraw in edit mode", function()
  for _, m in ipairs(S.metros) do if m.event then m.event() end end
end)
try("the transport keeps running while editing", function()
  S.advance(transport(), QUARTER)
end)

-- clear, then exit
S.grid_key(1, 2, 8, 1) S.grid_key(1, 2, 8, 0)
local function is_empty(pat)
  for s = 1, pat.slots do
    if next(pat.trigs[s]) ~= nil then return false end
  end
  return true
end
ok(is_empty(p), "row 8 col 2 cleared the pattern")
S.grid_key(1, 1, 8, 1) S.grid_key(1, 1, 8, 0)
ok(S.upvalue(redraw, "edit_mode") == false, "row 8 col 1 left the editor")

-- and a normal launch press works again
S.grid_key(1, 4, 2, 1) S.grid_key(1, 4, 2, 0)
ok(L[4].queued == 2 or L[4].active == 2,
   "after leaving the editor a press launches again")

---------------------------------------------------------------- edit scope
section("bulk follow edits")
local SL = S.get_lanes()

-- drive shift+E3 until the named field is in front of us
local function goto_field(want)
  for _ = 1, 20 do key(1, 1) enc(3, -1) key(1, 0) end  -- rewind to the first
  for _ = 1, 20 do
    if S.upvalue(redraw, "cur_field")().name == want then return true end
    key(1, 1) enc(3, 1) key(1, 0)
  end
  return false
end

local function set_scope(want)
  ok(goto_field("scope"), "reached the scope field")
  for _ = 1, 6 do enc(3, -1) end          -- back to "pattern"
  for _ = 1, want - 1 do enc(3, 1) end
end

local function all_chances()
  local out = {}
  for i = 1, 8 do
    for s = 1, 8 do out[#out + 1] = SL[i].bank[s].follow.chance end
  end
  return out
end

ok(type(S.upvalue(redraw, "cur_field")) == "function",
   "cur_field is reachable for the scope tests")

-- baseline: every pattern to a known value, one at a time is too slow, so
-- this is also the first real use of "all"
params:set("sel_lane", 1)
sel_slot_reset = nil
set_scope(4) -- all
ok(goto_field("chance"), "reached the chance field")
for _ = 1, 40 do enc(3, -1) end          -- everything to 0%
local zeroed = true
for _, c in ipairs(all_chances()) do if c ~= 0 then zeroed = false end end
ok(zeroed, "scope=all wrote chance to all 64 patterns")

-- pattern scope touches exactly one
set_scope(1)
ok(goto_field("chance"), "back on chance")
enc(3, 1)
local touched = 0
for _, c in ipairs(all_chances()) do if c ~= 0 then touched = touched + 1 end end
ok(touched == 1, "scope=pattern changed exactly one pattern (got " ..
   touched .. ")")

-- lane scope touches the selected lane's eight and nothing else
set_scope(4) ok(goto_field("chance")) for _ = 1, 40 do enc(3, -1) end
params:set("sel_lane", 3)
set_scope(2) -- lane
ok(goto_field("chance"), "back on chance for the lane test")
enc(3, 1)
local in_lane, out_lane = 0, 0
for i = 1, 8 do
  for s = 1, 8 do
    if SL[i].bank[s].follow.chance ~= 0 then
      if i == 3 then in_lane = in_lane + 1 else out_lane = out_lane + 1 end
    end
  end
end
ok(in_lane == 8, "scope=lane wrote all 8 patterns of lane 3 (got " ..
   in_lane .. ")")
ok(out_lane == 0, "scope=lane left every other lane alone (got " ..
   out_lane .. " strays)")

-- kit scope touches one slot across all lanes
set_scope(4) ok(goto_field("chance")) for _ = 1, 40 do enc(3, -1) end
set_scope(3) -- kit
ok(goto_field("chance"), "back on chance for the kit test")
local slot = S.upvalue(redraw, "sel_slot")
enc(3, 1)
local in_kit, out_kit = 0, 0
for i = 1, 8 do
  for s = 1, 8 do
    if SL[i].bank[s].follow.chance ~= 0 then
      if s == slot then in_kit = in_kit + 1 else out_kit = out_kit + 1 end
    end
  end
end
ok(in_kit == 8, "scope=kit wrote slot " .. slot .. " on all 8 lanes (got " ..
   in_kit .. ")")
ok(out_kit == 0, "scope=kit left the other slots alone (got " ..
   out_kit .. " strays)")

-- a bulk edit assigns rather than nudging: everything in scope ends equal
set_scope(1) ok(goto_field("chance"))
for _ = 1, 3 do enc(3, 1) end            -- make this one differ
set_scope(2) ok(goto_field("chance"))
enc(3, 1)
local first = SL[3].bank[1].follow.chance
local same = true
for s = 1, 8 do
  if SL[3].bank[s].follow.chance ~= first then same = false end
end
ok(same, "a bulk edit leaves everything in scope at the same value (" ..
   first .. "%)")

-- follow time and the two actions scope the same way
set_scope(4)
ok(goto_field("action A"), "reached action A")
enc(3, 1)
local a = SL[1].bank[1].follow.a
local a_same = true
for i = 1, 8 do
  for s = 1, 8 do if SL[i].bank[s].follow.a ~= a then a_same = false end end
end
ok(a_same, "scope=all applies to action A too")
ok(goto_field("follow"), "reached follow time")
enc(3, -1)
local t = SL[1].bank[1].follow.time
local t_same = true
for i = 1, 8 do
  for s = 1, 8 do if SL[i].bank[s].follow.time ~= t then t_same = false end end
end
ok(t_same, "scope=all applies to follow time too")

-- a lane setting ignores lane/kit scope and only widens at `all`
set_scope(2)
ok(goto_field("division"), "reached division")
params:set("sel_lane", 5)
for i = 1, 8 do params:set("lane_" .. i .. "_div", 5) end
enc(3, 1)
ok(params:get("lane_5_div") == 6, "lane 5's division moved")
ok(params:get("lane_2_div") == 5,
   "scope=lane did not widen a lane setting (lane 2 still " ..
   params:get("lane_2_div") .. ")")
set_scope(4)
ok(goto_field("division"), "back on division")
enc(3, 1)
local spread = true
for i = 1, 8 do
  if params:get("lane_" .. i .. "_div") ~= params:get("lane_5_div") then
    spread = false
  end
end
ok(spread, "scope=all set every lane's division to the same value")
set_scope(1)

---------------------------------------------------------------- arc broadcast
section("arc broadcast")
local arc_obj = S.arc_obj
for i = 1, 8 do params:set("lane_" .. i .. "_level", 1.0) end
-- page 1 ring 4 is level; without K1 held only the selected lane moves
params:set("sel_lane", 2)
local before = params:get("lane_7_level")
for _ = 1, 20 do arc_obj.delta(4, 5) end
ok(params:get("lane_2_level") ~= 1.0, "an arc turn moved the selected lane")
ok(params:get("lane_7_level") == before,
   "...and left the others alone with K1 up")
-- now with K1 held
for i = 1, 8 do params:set("lane_" .. i .. "_level", 1.0) end
key(1, 1)
for _ = 1, 20 do arc_obj.delta(4, 5) end
key(1, 0)
ok(params:get("lane_7_level") ~= 1.0,
   "holding K1 broadcast the arc turn to every lane (lane 7 now " ..
   params:get("lane_7_level") .. ")")
ok(params:get("lane_2_level") == params:get("lane_7_level"),
   "every lane moved by the same amount")

---------------------------------------------------------------- keys / encs
section("keys and encoders")
try("every encoder, both directions, shifted and not", function()
  for _, sh in ipairs({false, true}) do
    key(1, sh and 1 or 0)
    for n = 1, 3 do
      for _ = 1, 20 do enc(n, 1) end
      for _ = 1, 40 do enc(n, -1) end
      for _ = 1, 20 do enc(n, 1) end
    end
    redraw()
  end
  key(1, 0)
end)

-- walk every editable field and push it to both ends, redrawing each time
try("every field driven to both limits", function()
  for f = 1, 40 do
    key(1, 1) enc(3, 1) key(1, 0)   -- shift+E3 moves to the next field
    for _ = 1, 30 do enc(3, 1) end
    redraw()
    for _ = 1, 60 do enc(3, -1) end
    redraw()
  end
end)

try("K2 and K3, shifted and not", function()
  for _, sh in ipairs({false, true}) do
    key(1, sh and 1 or 0)
    key(2, 1) key(2, 0)
    redraw()
    key(3, 1) key(3, 0)
    redraw()
  end
  key(1, 0)
end)

---------------------------------------------------------------- footer
section("what-next footer")
local next_text = S.upvalue(redraw, "next_text")
local arc_fresh = S.upvalue(redraw, "arc_fresh")
ok(type(next_text) == "function", "next_text is reachable")
ok(type(arc_fresh) == "function", "arc_fresh is reachable")

params:set("sel_lane", 1)
local NL = S.get_lanes()
for i = 1, 8 do
  params:set("lane_" .. i .. "_follow", 0)
  params:set("lane_" .. i .. "_trans", 2) -- legato, whatever ran before
end
NL[1].queued = nil

-- with nothing pending it falls back to the lane's transition
local base = next_text(NL[1])
ok(base:find("legato") ~= nil, "idle footer names the transition (" .. base .. ")")

-- a queued launch names where it is going and how far off
NL[1]:launch(5)
local q = next_text(NL[1])
ok(q:find(">") ~= nil, "a queued launch is marked with > (" .. q .. ")")
ok(q:find(NL[1].bank[5].name, 1, true) ~= nil,
   "...and names the kit it is going to (" .. q .. ")")
NL[1].queued = nil

-- with follow armed it counts down to the action instead
params:set("lane_1_follow", 1)
NL[1].bank[NL[1].active].follow.time = 16
NL[1].bank[NL[1].active].follow.a = 7 -- other
NL[1].step_count = 0
local fl = next_text(NL[1])
ok(fl:find("other") ~= nil, "footer names the follow action (" .. fl .. ")")

-- nothing it can produce should overflow the screen
local longest = 0
for i = 1, 8 do
  params:set("sel_lane", i)
  NL[i]:launch(8)
  longest = math.max(longest, #next_text(NL[i]))
  NL[i].queued = nil
  params:set("lane_" .. i .. "_trans", 4) -- handover, the longest name
  longest = math.max(longest, #next_text(NL[i]))
end
ok(longest <= 26, "the footer stays inside a 128px line (" .. longest ..
   " chars at worst)")

-- the arc footer borrows the line briefly after a ring moves, then gives
-- it back. without the hold it squatted there permanently showing a stale
-- value long after the arc was last touched.
S.now = 100
S.arc_obj.delta(1, 30)
ok(arc_fresh(), "the arc takes the line just after a ring moves")
S.now = 100 + 0.5
ok(arc_fresh(), "...and holds it briefly")
S.now = 100 + 5
ok(not arc_fresh(), "...then hands it back (" .. tostring(S.now) .. ")")
try("redraw with a stale arc footer", redraw)

params:set("sel_lane", 1)
for i = 1, 8 do params:set("lane_" .. i .. "_trans", 2) end

---------------------------------------------------------------- arc
section("arc")
S.arc_leds = {}
local a = S.arc_obj
ok(a ~= nil and a.delta ~= nil, "the script installed an arc delta handler")
try("arc page cycle + deltas on every ring", function()
  for page = 1, 3 do
    for ring = 1, 4 do
      for _ = 1, 30 do a.delta(ring, 5) end
      for _ = 1, 30 do a.delta(ring, -5) end
    end
    a.key(1, 1) -- the arc's own button cycles pages
  end
end)
ok(#S.arc_leds > 0, "the arc lit some leds (" .. #S.arc_leds .. ")")
try("redraw with an arc footer", redraw)

section("arc follows values changed outside it")
try("a value moved from the PARAMS menu reaches the rings", function()
  local garc_ = S.upvalue(redraw, "garc_")
  local redraw_id = S.upvalue(cleanup, "redraw_id")
  -- pin the MORPH page, where ring 3 is the global launch_quant, so this
  -- doesn't depend on where the page-cycling test above happened to stop
  while garc_.page ~= 2 do a.key(1, 1) end
  local p = params:lookup_param("launch_quant")
  local cs = p.controlspec
  local before = p.value

  S.advance(redraw_id, 1)
  S.arc_leds = {}
  S.advance(redraw_id, 3)
  ok(#S.arc_leds == 0, "a still arc lights nothing frame to frame (poll only redraws on a change)")

  params:set("launch_quant", before == cs.maxval and cs.minval or before + cs.step)
  S.advance(redraw_id, 1)
  ok(#S.arc_leds > 0, "the rings redrew after a value moved without the arc being touched")

  params:set("launch_quant", before)
  S.advance(redraw_id, 1)
end)

---------------------------------------------------------------- psets
section("pset round trip")
-- edit something distinctive, save, change it, load, check it came back
params:set("lane_1_div", 3)
params:set("lane_3_prob", 0.42)
local L = S.get_lanes()
ok(L ~= nil, "lanes are reachable for the check")
L[2].bank[5].follow.chance = 35
L[2].bank[5].length = 12

try("action_write", function() params.action_write("x", "test", 7) end)
params:set("lane_1_div", 6)
L[2].bank[5].follow.chance = 100
L[2].bank[5].length = 16
try("action_read", function() params.action_read("x", false, 7) end)

ok(L[2].bank[5].follow.chance == 35, "follow chance came back (got " ..
   L[2].bank[5].follow.chance .. ")")
ok(L[2].bank[5].length == 12, "pattern length came back (got " ..
   L[2].bank[5].length .. ")")
-- lane settings live in params, so a pset restores them the ordinary way
-- and the data file must NOT also carry them back. that double home is why
-- every setting used to survive a power cycle: the autosave blob quietly
-- overrode whatever the params said.
ok(params:get("lane_1_div") == 6,
   "the data file did not override a lane param (got " ..
   params:get("lane_1_div") .. ", set to 6 before the read)")

-- and the lane object agrees with the param rather than the file
ok(L[1].div == 6, "the lane followed the param, not the blob (got " ..
   L[1].div .. ")")

---------------------------------------------------------------- defaults
section("reset to factory")
-- the autosave keeps pattern edits across power cycles, which is usually
-- wanted; this is the way back out of it
L[2].bank[5].follow.chance = 15
L[2].bank[5].length = 7
Pattern_edited = true
params:set("lane_3_div", 2)
params:set("lane_4_mute", 1)
L[1].active = 6

try("reset to factory kits", function()
  params:lookup_param("reset_defaults").action()
end)

ok(L[2].bank[5].follow.chance ~= 15, "an edited follow chance was reset")
ok(L[2].bank[5].length == 16 or L[2].bank[5].length == 32,
   "pattern length went back to the kit's own (got " ..
   L[2].bank[5].length .. ")")
ok(params:get("lane_3_div") == 5, "a lane setting went back to default (got " ..
   params:get("lane_3_div") .. ")")
ok(params:get("lane_4_mute") == 0, "a muted lane was unmuted")
ok(L[1].active == 1, "every lane went back to kit 1")
ok(L[3].div == 5, "the lane object followed its param back")

-- and the factory library really is back, not just cleared
local restored = 0
for i = 1, 8 do
  for s = 1, 8 do
    local pat = L[i].bank[s]
    for slot = 1, pat.slots do
      if next(pat.trigs[slot]) ~= nil then restored = restored + 1 break end
    end
  end
end
ok(restored > 30, "the factory kits are back, not an empty bank (" ..
   restored .. " non-empty patterns)")

try("action_delete", function() params.action_delete("x", "test", 7) end)

---------------------------------------------------------------- layouts
section("other grid layouts")
for _, cfg in ipairs({{8, 8, "dual"}, {8, 0, "single"}, {16, 0, "split"}}) do
  S.grid_cols = {cfg[1], cfg[2]}
  local GridUI = dofile(S.SEGUE_DIR .. "lib/gridui.lua")
  local seen = {}
  local ui = GridUI:new{
    on_launch = function(l, s, z) seen.launch = true end,
    on_fx = function(c, r, z) seen.fx = true end,
    level_launch = function() return 5 end,
    level_fx = function() return 5 end,
  }
  ok(ui.layout == cfg[3], "a " .. cfg[1] .. "/" .. cfg[2] ..
     " grid setup is '" .. cfg[3] .. "' (got '" .. ui.layout .. "')")
  try("redraw on the " .. cfg[3] .. " layout", function() ui:redraw() end)
  ui:_key(1, 1, 1, 1)
  ok(seen.launch, cfg[3] .. ": a top-left press reached LAUNCH")
  if cfg[3] == "single" then
    ui:set_alt(true)
    ui:_key(1, 1, 1, 1)
    ok(seen.fx, "single: the same press reaches FX with alt held")
  elseif cfg[3] == "split" then
    ui:_key(1, 9, 1, 1)
    ok(seen.fx, "split: a press on the right half reached FX")
  else
    ui:_key(2, 1, 1, 1)
    ok(seen.fx, "dual: a press on port 2 reached FX")
  end
end

---------------------------------------------------------------- cleanup
section("cleanup")
try("cleanup() runs clean", cleanup)

---------------------------------------------------------------- results
S.real_print("")
S.real_print(string.rep("-", 46))
S.real_print(("%d passed, %d failed"):format(pass, fail))
if #S.prints > 0 then
  S.real_print("script printed: " .. table.concat(S.prints, " | "))
end
os.exit(fail == 0 and 0 or 1)
