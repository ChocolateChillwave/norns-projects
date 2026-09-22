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

-- lane 1 starts on the generic bank's first kit, 16 steps of 1/16: one bar.
-- two positions eight beats apart are two whole loops apart, so they land
-- on the same step; one beat apart must not.
ok(start_at(4.0, 3) == start_at(12.0, 3),
   "shared clock: two bars apart gives the same step")
ok(start_at(4.0, 3) ~= start_at(5.0, 3),
   "shared clock: one beat apart gives a different step")
-- and the step it lands on is the phase-correct one for the tick it fired
-- on, not merely a repeatable one. (starting exactly at beat 0 lands on
-- step 2, not step 1: clock.sync waits for the next subdivision, so the
-- boundary at tick 0 is already in the past. that is right -- the first
-- 16th after the downbeat *is* step 2.)
-- the lane's RESOLVED step length: lane_1_div itself is 0 ("global") now
-- that lanes inherit their division, so it cannot be read directly
local dtv = SL[1]:div_ticks()
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
local SL = S.get_lanes()
local Pattern = S.upvalue(redraw, "Pattern")
local fx_level = S.upvalue(init, "fx_level")
local function cur_bank() return (S.deep(fx_level, "current_bank")) end
local function tgt_bank() return (S.deep(fx_level, "bank_target")) end
local function playing_now() return S.upvalue(redraw, "playing") end

-- stop, and put the lanes on bank b straight away (a stopped bank change
-- loads at once rather than queueing a hand-off)
local function stop() if playing_now() then key(3, 1) key(3, 0) end end
local function park_bank(b)
  stop()
  params:set("bank", b)
end

-- FX row 7 col 6 is the step-editor toggle; drive it to a known state
local function set_edit(want)
  if S.upvalue(redraw, "edit_mode") ~= want then
    S.grid_key(1, 14, 7, 1) S.grid_key(1, 14, 7, 0)
  end
end

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
ok(#S.grid_leds > 0, "the grid refresh lit something (" .. #S.grid_leds .. " leds)")

try("pressing every LAUNCH cell", function()
  for x = 1, 8 do
    for y = 1, 8 do S.grid_key(1, x, y, 1) S.grid_key(1, x, y, 0) end
  end
end)

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

-- the sweep walked over everything: the mute row, follow-all, the step
-- editor toggle, and all eight bank buttons (ending on the empty user
-- bank). put it back to a known, audible state.
set_edit(false)
park_bank(1)
for i = 1, 8 do
  params:set("lane_" .. i .. "_mute", 0)
  params:set("lane_" .. i .. "_follow", 1)
end
ok(cur_bank() == 1, "back on the generic bank after the sweep")

local function notes_on()
  local out = {}
  for _, m in ipairs(S.midi_sent) do
    if m.t == "on" then out[#out + 1] = m.ch .. "/" .. m.note .. "/" .. m.vel end
  end
  return out
end

-- FOCUS mode (the default) dims the performance rows
params:set("mode", 1)
ok(type(fx_level) == "function", "the fx level function is reachable")
local dark = true
for _, row in ipairs({1, 4, 6}) do
  for c = 1, 8 do if fx_level(c, row) ~= 0 then dark = false end end
end
ok(dark, "focus mode leaves rows 1, 4 and 6 dark")
local lit = false
for _, row in ipairs({2, 3, 5, 7, 8}) do
  for c = 1, 8 do if fx_level(c, row) > 0 then lit = true end end
end
ok(lit, "focus mode keeps the rows it does show lit")
local rep_before = S.upvalue(redraw, "rep_col")
S.grid_key(1, 10, 1, 1)
ok(S.upvalue(redraw, "rep_col") == rep_before, "a press on a hidden row is inert")
S.grid_key(1, 10, 1, 0)

params:set("mode", 2) -- full
local row1 = false
for c = 1, 8 do if fx_level(c, 1) > 0 then row1 = true end end
ok(row1, "full mode lights row 1 again")

-- beat repeat: the first pass records, every pass after replays it
clock_id = transport()
S.grid_key(1, 10, 1, 1) -- FX row 1 col 2 = 1/4 repeat
S.midi_sent = {}
try("first repeat window (records)", function() S.advance(clock_id, QUARTER) end)
local win_a = notes_on()
S.midi_sent = {}
try("second repeat window (replays)", function() S.advance(clock_id, QUARTER) end)
local win_b = notes_on()
S.grid_key(1, 10, 1, 0)
ok(#win_a > 0, "the repeat window captured something (" .. #win_a .. " notes)")
local same = #win_a == #win_b
for i = 1, math.min(#win_a, #win_b) do if win_a[i] ~= win_b[i] then same = false end end
ok(same, "the replayed window is note-for-note the captured one")
S.midi_sent = {}
try("a beat after releasing it", function() S.advance(clock_id, QUARTER) end)
ok(#notes_on() > 0, "the lanes resume playing live after the release")

S.grid_key(1, 9, 4, 1) -- solo lane 1
try("a few steps with a lane soloed", function() S.advance(transport(), QUARTER) end)
S.grid_key(1, 9, 4, 0)

-- row 2 launches one kit on every lane
park_bank(2)
S.grid_key(1, 13, 2, 1) S.grid_key(1, 13, 2, 0) -- kit 5, stopped: lands at once
local all5 = true
for i = 1, 8 do if SL[i].active ~= 5 then all5 = false end end
ok(all5, "FX row 2 col 5 put every lane on kit 5")

-- row 7 cols 1-4 set the GLOBAL transition; lanes inherit it
for i = 1, 8 do params:set("lane_" .. i .. "_trans", 0) end
S.grid_key(1, 9, 7, 1) S.grid_key(1, 9, 7, 0) -- cut
ok(params:get("transition") == 1, "FX row 7 col 1 set the global transition to cut")
ok(SL[3]:setting("trans") == 1, "an inheriting lane now switches on cut")
S.grid_key(1, 10, 7, 1) S.grid_key(1, 10, 7, 0) -- back to legato

---------------------------------------------------------------- banks
section("banks")
park_bank(1)
ok(SL[1].bank[1].name == "basic", "generic bank: kit 1 is 'basic'")
params:set("bank", 2)
ok(cur_bank() == 2, "a bank change while stopped lands at once")
ok(SL[1].bank[1].name == "classic", "...and the lanes hold house kits")

-- while playing it hands off on the launch-quantize boundary
clock_id = transport()
S.advance(clock_id, 1)
params:set("bank", 3)
ok(cur_bank() == 2, "the current bank does not change when a switch is asked for")
ok(tgt_bank() == 3, "...it is pending")
ok(SL[1].bank[1].name == "classic", "...and the lanes are still on house")
local landed = false
for _ = 1, BAR * 2 do
  S.advance(clock_id, 1)
  if cur_bank() == 3 then landed = true break end
end
ok(landed, "the switch landed within a bar")
ok(tgt_bank() == nil, "...and is no longer pending")
ok(SL[1].bank[1].name == "four four", "the lanes are now on techno")

-- choosing the bank you are on cancels a pending switch
params:set("bank", 4)
ok(tgt_bank() == 4, "a switch to electro is pending")
params:set("bank", 3)
ok(tgt_bank() == nil, "choosing techno again cancelled it")
local none_pending = true
for i = 1, 8 do if SL[i].pending_bank then none_pending = false end end
ok(none_pending, "...and no lane is still waiting to swap")

-- FX row 8 is the bank row
S.grid_key(1, 13, 8, 1) S.grid_key(1, 13, 8, 0) -- bank 5
ok(tgt_bank() == 5, "FX row 8 col 5 queued the breakbeats bank")
ok(fx_level(5, 8) > 0 and fx_level(3, 8) > 0,
   "both the pending bank and the one still playing are lit")

-- factory banks are read-only: an edit is gone once you leave the bank
park_bank(2)
local fp = SL[1].bank[1]
ok(Pattern.get(fp, 1, 2) == nil, "house kit 1 kick step 2 is a rest")
Pattern.set(fp, 1, 2, Pattern.ACCENT)
params:set("bank", 3)
params:set("bank", 2)
ok(Pattern.get(SL[1].bank[1], 1, 2) == nil,
   "the edit to a factory kit did not survive leaving the bank")

-- the user bank keeps its edits
params:lookup_param("clear_user").action()
params:set("bank", 8)
ok(cur_bank() == 8, "on the user bank")
Pattern.set(SL[1].bank[4], 1, 3, Pattern.ACCENT)
params:set("bank", 2)
params:set("bank", 8)
ok(Pattern.get(SL[1].bank[4], 1, 3) == Pattern.ACCENT,
   "an edit on the user bank survived leaving and coming back")

-- copy to user captures what is PLAYING into the first empty user slot
params:lookup_param("clear_user").action()
park_bank(2)
for i = 1, 8 do SL[i].active = 3 end        -- house kit 3, 'garage'
SL[1].active = 1                            -- but the kick from 'classic'
S.grid_key(1, 15, 7, 1) S.grid_key(1, 15, 7, 0) -- FX row 7 col 7
params:set("bank", 8)
ok(SL[1].bank[1].name == "classic" and SL[2].bank[1].name == "garage",
   "copy to user kept the exact mix that was playing, in user slot 1")
ok(not Pattern.is_empty(SL[1].bank[1]), "...with the notes, not just the name")
params:set("bank", 2)
for i = 1, 8 do SL[i].active = 2 end
params:lookup_param("copy_user").action()
params:set("bank", 8)
ok(SL[1].bank[2].name == "deep", "a second copy went into the next empty slot")

---------------------------------------------------------------- step editor
section("step editor")
park_bank(1)
params:set("sel_lane", 1)
set_edit(false)
S.grid_key(1, 1, 3, 1) S.grid_key(1, 1, 3, 0) -- lane 1 kit 3
set_edit(true)
ok(S.upvalue(redraw, "edit_mode") == true, "the editor turned on")

local p = SL[1].bank[3]
local before = p.trigs[1][2]
S.grid_key(1, 2, 1, 1) S.grid_key(1, 2, 1, 0)
ok(p.trigs[1][2] ~= before, "a grid press changed step 2")
local start = p.trigs[1][5]
for _ = 1, 4 do S.grid_key(1, 5, 1, 1) S.grid_key(1, 5, 1, 0) end
ok(p.trigs[1][5] == start, "four presses cycle a step back to its start")
S.grid_key(1, 2, 7, 1) S.grid_key(1, 2, 7, 0) -- page 2
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

S.grid_key(1, 2, 8, 1) S.grid_key(1, 2, 8, 0)
ok(Pattern.is_empty(p), "editor row 8 col 2 cleared the pattern")
S.grid_key(1, 1, 8, 1) S.grid_key(1, 1, 8, 0)
ok(S.upvalue(redraw, "edit_mode") == false, "editor row 8 col 1 left the editor")
S.grid_key(1, 4, 2, 1) S.grid_key(1, 4, 2, 0)
ok(SL[4].queued == 2 or SL[4].active == 2, "after leaving it a press launches again")

---------------------------------------------------------------- edit levels
section("edit levels")
stop()
park_bank(1)
params:set("mode", 2)
local cur_field = S.upvalue(redraw, "cur_field")
local field_list = S.deep(cur_field, "field_list") -- via field_index
ok(type(cur_field) == "function" and type(field_list) == "function",
   "the field functions are reachable")

local function goto_field(want)
  for _ = 1, 20 do key(1, 1) enc(3, -1) key(1, 0) end
  for _ = 1, 20 do
    if cur_field().name == want then return true end
    key(1, 1) enc(3, 1) key(1, 0)
  end
  return false
end
local function set_level(n)
  ok(goto_field("level"), "reached the level field")
  for _ = 1, 6 do enc(3, -1) end
  for _ = 1, n - 1 do enc(3, 1) end
end
local function level() return S.upvalue(redraw, "edit_level_") end

ok(level() == 1, "edits land at GLOBAL by default")

-- a GLOBAL edit flows to everything that inherits, and leaves every
-- override alone -- the property the whole model exists for
set_level(1)
ok(goto_field("chance"), "reached chance")
params:set("follow_chance", 100)
for _ = 1, 4 do enc(3, -1) end
ok(params:get("follow_chance") == 80, "a global edit moved the global param to 80")
ok(SL[1]:setting("follow_chance") == 80, "KICK, inheriting, now resolves to 80")
ok(SL[5]:setting("follow_chance") == 40,
   "CHH kept its own lane value (40): a global edit does not touch an override")

-- LANE level: from "global", the first click MATERIALISES the value already
-- in force, so the marker changes and the sound does not
params:set("sel_lane", 1)
set_level(2)
ok(goto_field("chance"), "back on chance at lane level")
enc(3, 1)
ok(params:get("lane_1_fchance") == 80,
   "turning up from 'global' took the inherited 80, not the bottom of the range")
enc(3, 1)
ok(params:get("lane_1_fchance") == 85, "...and the next click moved it")
ok(params:get("lane_2_fchance") == -5, "another lane still inherits")
for _ = 1, 30 do enc(3, -1) end
ok(params:get("lane_1_fchance") == -5, "turning down past 0 returned to 'global'")
ok(SL[1]:setting("follow_chance") == 80, "...and KICK inherits the global again")

-- PATTERN level touches exactly one pattern
local slot = S.upvalue(redraw, "sel_slot")
set_level(4)
ok(goto_field("chance"), "back on chance at pattern level")
local pp = SL[1].bank[slot]
pp.ov.follow_chance = nil
enc(3, 1)
ok(pp.ov.follow_chance == 80, "a pattern override materialised the inherited 80")
enc(3, 1)
ok(pp.ov.follow_chance == 85, "...then moved")
local strays = 0
for i = 1, 8 do
  for s = 1, 8 do
    if not (i == 1 and s == slot) and SL[i].bank[s].ov.follow_chance ~= nil then
      strays = strays + 1
    end
  end
end
ok(strays == 0, "a pattern-level edit touched only that one pattern (" ..
   strays .. " strays)")
for _ = 1, 30 do enc(3, -1) end
ok(pp.ov.follow_chance == nil, "turning down past 0 cleared the override")

-- KIT level writes one value to that slot on every lane, but never over an
-- empty slot's 'none' -- that guard is what keeps a sat-out voice silent
for _ = 1, 10 do enc(2, -1) end -- slot 1: 'basic', where most lanes sit out
set_level(3)
ok(goto_field("action A"), "reached action A at kit level")
enc(3, 1)
local v0 = SL[1].bank[1].ov.follow_a
local kit_same, guard_kept = true, true
for i = 1, 8 do
  local pat = SL[i].bank[1]
  if Pattern.is_empty(pat) then
    if pat.ov.follow_a ~= Pattern.ACTION_NONE then guard_kept = false end
  elseif pat.ov.follow_a ~= v0 then
    kit_same = false
  end
end
ok(v0 ~= nil and kit_same, "a kit-level edit wrote one value across the row")
ok(guard_kept, "...and left every empty slot's 'none' alone")
local other_slots = 0
for i = 1, 8 do
  for s = 2, 8 do
    local pat = SL[i].bank[s]
    if not Pattern.is_empty(pat) and pat.ov.follow_a ~= nil then
      other_slots = other_slots + 1
    end
  end
end
ok(other_slots == 0, "the other kit slots were untouched")

-- each level offers only what means something there
local function fields_at(n)
  set_level(n)
  local set = {}
  for _, k in ipairs(field_list()) do set[k] = true end
  return set
end
local g, ln, pt = fields_at(1), fields_at(2), fields_at(4)
ok(g.div and g.quant, "GLOBAL offers division and quantize")
ok(not ln.quant, "LANE hides quantize, which has no lane level")
ok(not pt.div and not pt.swing, "PATTERN hides division and swing")
ok(pt.length, "PATTERN offers the pattern's length")

-- an inherited value reports itself as inherited, so it is drawn dim
set_level(4)
ok(goto_field("transition"), "reached transition at pattern level")
SL[1].bank[1].ov.trans = nil
params:set("sel_lane", 1)
local _, inh = cur_field().show()
ok(inh == true, "an inherited value is reported as inherited")
enc(3, 1)
local _, inh2 = cur_field().show()
ok(inh2 == false, "once set here it is reported as set")
SL[1].bank[1].ov.trans = nil

-- division: a global edit re-resolves every inheriting lane at once
set_level(1)
ok(goto_field("division"), "reached division at global level")
params:set("division", 5)
for i = 1, 8 do params:set("lane_" .. i .. "_div", 0) end
enc(3, 1)
ok(params:get("division") == 6, "global division moved to 6")
local all6 = true
for i = 1, 8 do if SL[i].div ~= 6 then all6 = false end end
ok(all6, "every inheriting lane re-resolved to 6")
params:set("lane_2_div", 3)
enc(3, 1)
ok(SL[2].div == 3, "a lane with its own division kept it through a global edit")
ok(SL[1].div == 7, "an inheriting lane followed to 7")
params:set("division", 5)
params:set("lane_2_div", 0)
params:set("follow_chance", 100)
set_level(1)

---------------------------------------------------------------- arc broadcast
section("arc broadcast")
local arc_obj = S.arc_obj
local garc_ = S.upvalue(redraw, "garc_")
while garc_.page ~= 1 do arc_obj.key(1, 1) end -- PLAY, where ring 4 is vel
for i = 1, 8 do params:set("lane_" .. i .. "_level", 0.5) end
params:set("sel_lane", 2)
for _ = 1, 20 do arc_obj.delta(4, 5) end
ok(params:get("lane_2_level") > 0.5, "an arc turn moved the selected lane")
ok(params:get("lane_7_level") == 0.5, "...and left the others alone with K1 up")
for i = 1, 8 do params:set("lane_" .. i .. "_level", 0.5) end
key(1, 1)
for _ = 1, 20 do arc_obj.delta(4, 5) end
key(1, 0)
ok(params:get("lane_7_level") > 0.5, "holding K1 broadcast the turn to every lane")
ok(params:get("lane_2_level") == params:get("lane_7_level"),
   "every lane moved by the same amount")
ok(params:get("lane_2_level") <= 1.0, "velocity never goes past 100%")
for i = 1, 8 do params:set("lane_" .. i .. "_level", 1.0) end

-- the arc follows the edit level: at global a ring turns the global param
while garc_.page ~= 1 do arc_obj.key(1, 1) end
set_level(1)
params:set("division", 5)
for _ = 1, 20 do arc_obj.delta(1, 5) end
ok(params:get("division") ~= 5, "at global level ring 1 turned the global division")
ok(params:get("lane_2_div") == 0, "...not a lane's")
params:set("division", 5)

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
try("every field at every level driven to both limits", function()
  for lv = 1, 4 do
    set_level(lv)
    for f = 1, 14 do
      key(1, 1) enc(3, 1) key(1, 0)
      for _ = 1, 30 do enc(3, 1) end
      redraw()
      for _ = 1, 60 do enc(3, -1) end
      redraw()
    end
  end
end)
try("K2 and K3, shifted and not", function()
  for _, sh in ipairs({false, true}) do
    key(1, sh and 1 or 0)
    key(2, 1) key(2, 0) redraw()
    key(3, 1) key(3, 0) redraw()
  end
  key(1, 0)
end)
set_level(1)

---------------------------------------------------------------- footer
section("what-next footer")
local next_text = S.upvalue(redraw, "next_text")
local arc_fresh = S.upvalue(redraw, "arc_fresh")
ok(type(next_text) == "function", "next_text is reachable")
ok(type(arc_fresh) == "function", "arc_fresh is reachable")

stop()
park_bank(1)
params:set("sel_lane", 1)
params:set("transition", 2)
for i = 1, 8 do
  params:set("lane_" .. i .. "_follow", 0)
  params:set("lane_" .. i .. "_trans", 0)
end
SL[1].queued = nil
ok(next_text(SL[1]):find("legato") ~= nil, "idle footer names the inherited transition")

SL[1]:launch(5)
local qt = next_text(SL[1])
ok(qt:find(">") ~= nil and qt:find(SL[1].bank[5].name, 1, true) ~= nil,
   "a queued launch names where it is going (" .. qt .. ")")
SL[1].queued = nil

params:set("lane_1_follow", 1)
SL[1].bank[SL[1].active].ov.follow_time = 9
SL[1].bank[SL[1].active].ov.follow_a = 7
SL[1].step_count = 0
ok(next_text(SL[1]):find("other") ~= nil, "footer names the follow action")
SL[1].bank[SL[1].active].ov.follow_time = nil
SL[1].bank[SL[1].active].ov.follow_a = nil

-- a pending bank change says so
clock_id = transport()
S.advance(clock_id, 1)
params:set("bank", 3)
local bt = next_text(SL[1])
ok(bt:find("techno", 1, true) ~= nil, "a pending bank change names the bank (" .. bt .. ")")
stop()

local longest = 0
for i = 1, 8 do
  SL[i]:launch(8)
  longest = math.max(longest, #next_text(SL[i]))
  SL[i].queued = nil
  params:set("lane_" .. i .. "_trans", 4)
  longest = math.max(longest, #next_text(SL[i]))
end
ok(longest <= 26, "the footer stays inside a 128px line (" .. longest .. " chars)")
for i = 1, 8 do params:set("lane_" .. i .. "_trans", 0) end

S.now = 100
arc_obj.delta(1, 30)
ok(arc_fresh(), "the arc takes the line just after a ring moves")
S.now = 100.5
ok(arc_fresh(), "...and holds it briefly")
S.now = 105
ok(not arc_fresh(), "...then hands it back")
try("redraw with a stale arc footer", redraw)

---------------------------------------------------------------- arc
section("arc")
S.arc_leds = {}
ok(arc_obj ~= nil and arc_obj.delta ~= nil, "the script installed an arc delta handler")
try("arc page cycle + deltas on every ring", function()
  for page = 1, 3 do
    for ring = 1, 4 do
      for _ = 1, 30 do arc_obj.delta(ring, 5) end
      for _ = 1, 30 do arc_obj.delta(ring, -5) end
    end
    arc_obj.key(1, 1)
  end
end)
ok(#S.arc_leds > 0, "the arc lit some leds")
try("redraw with an arc footer", redraw)

section("arc follows values changed outside it")
try("a value moved from the PARAMS menu reaches the rings", function()
  local redraw_id = S.upvalue(init, "redraw_id")
  while garc_.page ~= 2 do arc_obj.key(1, 1) end -- MORPH: ring 3 is quant
  local qp = params:lookup_param("launch_quant")
  local before_q = qp.value
  S.advance(redraw_id, 1)
  S.arc_leds = {}
  S.advance(redraw_id, 3)
  ok(#S.arc_leds == 0, "a still arc lights nothing frame to frame")
  params:set("launch_quant", before_q == qp.controlspec.maxval and 1 or before_q + 1)
  S.advance(redraw_id, 1)
  ok(#S.arc_leds > 0, "the rings redrew after a value moved without the arc")
  params:set("launch_quant", before_q)
  S.advance(redraw_id, 1)
end)

---------------------------------------------------------------- psets
section("pset round trip")
-- a pset carries which bank and which kits; settings ride as params
stop()
park_bank(4)
for i = 1, 8 do SL[i].active = (i % 8) + 1 end
params:set("lane_1_div", 3)
try("action_write", function() params.action_write("x", "test", 7) end)
park_bank(2)
for i = 1, 8 do SL[i].active = 1 end
params:set("lane_1_div", 6)
try("action_read", function() params.action_read("x", false, 7) end)
ok(cur_bank() == 4, "the pset brought back the electro bank")
ok(SL[1].active == 2 and SL[8].active == 1, "...and which kit each lane was on")
ok(params:get("lane_1_div") == 6,
   "the data file did not override a lane param -- params own settings")
ok(SL[1].div == 6, "the lane followed the param, not the file")

-- the user bank lives in its own file and no pset load can touch it
params:lookup_param("clear_user").action()
park_bank(2)
for i = 1, 8 do SL[i].active = 4 end
params:lookup_param("copy_user").action()
ok(S.files[norns.state.data .. "segue-user.data"] ~= nil,
   "copying to user saved the user bank to its own file")
local ub = S.deep(cleanup, "user_bank")
local marker = ub[1][1]
params.action_read("x", false, 7)
ok(S.deep(cleanup, "user_bank")[1][1] == marker,
   "loading a pset did not replace the user bank")
try("action_delete", function() params.action_delete("x", "test", 7) end)

---------------------------------------------------------------- defaults
section("reset to factory")
park_bank(4)
for i = 1, 8 do SL[i].active = 6 end
params:set("division", 3)
params:set("transition", 4)
params:set("follow_a", 7)
params:set("lane_3_div", 2)
params:set("lane_4_mute", 1)
params:set("lane_5_fa", 0)
local user_before = S.deep(cleanup, "user_bank")[1][1]
try("reset to factory", function() params:lookup_param("reset_defaults").action() end)
ok(cur_bank() == 1, "back on the generic bank")
ok(params:get("division") == 5, "the global division is back to 1/16")
ok(params:get("transition") == 2, "the global transition is back to legato")
ok(params:get("follow_a") == 1, "the global follow action is back to 'none'")
ok(params:get("lane_3_div") == 0, "a lane's division is back to 'global'")
ok(params:get("lane_4_mute") == 0, "a muted lane was unmuted")
ok(params:get("lane_5_fa") == 7, "CHH's shipped 'other' override came back")
local all1 = true
for i = 1, 8 do if SL[i].active ~= 1 then all1 = false end end
ok(all1, "every lane is back on kit 1")
ok(SL[3].div == 5, "the lane object followed its param back")
ok(S.deep(cleanup, "user_bank")[1][1] == user_before,
   "reset left the user bank alone -- it is your work")
params:lookup_param("clear_user").action()
local ub2 = S.deep(cleanup, "user_bank")
local empty = true
for i = 1, 8 do
  for k = 1, 8 do if not Pattern.is_empty(ub2[i][k]) then empty = false end end
end
ok(empty, "'clear user bank' empties it")

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
