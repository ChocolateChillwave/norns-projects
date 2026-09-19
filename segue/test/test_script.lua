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
try("96 ticks (one bar) of transport", function() S.advance(clock_id, 96) end)
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
try("a bar with a hand-edited voice", function() S.advance(clock_id, 96) end)
params:set("note_layout", 1) -- restamping clears it, by design
ok(params:get("voice_3_note") == 2, "choosing a layout again overwrites it")

try("redraw while playing", redraw)

try("seven more bars", function() S.advance(clock_id, 96 * 7) end)

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
      S.advance(transport(), 3)
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

clock_id = transport()
S.grid_key(1, 10, 1, 1) -- FX row 1 col 2 = 1/4 repeat (24 ticks)
S.midi_sent = {}
try("first repeat window (records)", function() S.advance(clock_id, 24) end)
local win_a = notes_on()
S.midi_sent = {}
try("second repeat window (replays)", function() S.advance(clock_id, 24) end)
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
try("24 ticks after releasing it", function() S.advance(clock_id, 24) end)
ok(#notes_on() > 0, "the lanes resume playing live after the release (" ..
   #notes_on() .. " notes)")

-- solo, held then released
S.grid_key(1, 9, 4, 1) -- FX row 4 col 1 = solo lane 1
try("8 ticks with a lane soloed", function() S.advance(transport(), 8) end)
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
  S.advance(transport(), 24)
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
ok(params:get("lane_1_div") == 3,
   "a lane param was restored from the data file and pushed back to params" ..
   " (got " .. params:get("lane_1_div") .. ")")

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
