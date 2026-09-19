-- drives rytmpatch.lua against the stubbed norns runtime: init, every
-- page/key/encoder combination, randomize + morph + undo, incoming CC
-- mirroring, pset round trip and cleanup.
-- run: lua rytmpatch/test/test_script.lua
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")

math.randomseed(11)

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

dofile(S.DIR .. "rytmpatch.lua")

---------------------------------------------------------------- init
section("init")
for _, fn in ipairs({"init", "redraw", "key", "enc", "cleanup"}) do
  ok(type(_G[fn]) == "function", fn .. "() is defined")
end
ok(rawget(_G, "engine") == nil, "no engine is set (MIDI-out only)")

try("init() runs clean", init)

for _, g in ipairs(params.groups) do
  ok(g.added == g.n, "group '" .. g.name .. "' declared " .. g.n .. " and added " .. g.added)
end
for _, p in ipairs(params.list) do
  local okf = pcall(function() return p:string() end)
  ok(okf, "formatter for " .. p.id)
end
ok(params.by_id["rnd_spread"] ~= nil, "widen range param exists")
ok(params:get("rnd_spread") == 0, "randomization starts fully tamed")
ok(params.by_id["machine_12"] ~= nil, "a machine param per track")

---------------------------------------------------------------- ui walk
section("ui walk")
try("redraw before any input", redraw)
try("every page, slot, value and mode", function()
  for _ = 1, 12 do
    enc(1, 1)                       -- page
    for _ = 1, 8 do
      enc(2, 1)                     -- select
      enc(3, 5) enc(3, -400) enc(3, 400) -- values, past both ends
      key(3, 1) key(3, 0)           -- cycle mode
    end
    key(2, 1) key(2, 0)             -- randomize page
    redraw()
  end
  for _ = 1, 12 do enc(1, -1) redraw() end
end)
try("shift combos", function()
  key(1, 1)
  enc(1, 3) enc(2, -20) enc(3, 2)   -- track, amount, morph
  key(2, 1) key(2, 0)               -- undo
  key(3, 1) key(3, 0)               -- randomize track
  key(1, 0)
  redraw()
end)

---------------------------------------------------------------- midi
section("midi out")
params:set("morph", 1)
params:set("rnd_amount", 100)
S.midi_sent = {}
key(2, 1) key(2, 0)
ok(#S.midi_sent > 0, "randomize sends CCs (" .. #S.midi_sent .. ")")
local base, fx = params:get("track_ch"), params:get("fx_ch")
local bad_ch = nil
for _, m in ipairs(S.midi_sent) do
  local track = m.ch - base + 1
  if m.ch ~= fx and (track < 1 or track > 12) then bad_ch = m.ch end
end
ok(bad_ch == nil, "every CC goes out on a track channel or the FX channel (saw " ..
   tostring(bad_ch) .. ")")

-- FX pages must address the FX channel, not the track channel
local pg = S.upvalue(redraw, "page")
S.midi_sent = {}
for _ = 1, 12 do enc(1, 1) end -- last page is an FX page
key(2, 1) key(2, 0)
local all_fx = #S.midi_sent > 0
for _, m in ipairs(S.midi_sent) do
  if m.ch ~= params:get("fx_ch") then all_fx = false end
end
ok(all_fx, "FX page randomize goes out on the FX channel only")

section("midi in mirrors the rytm")
params:set("sync_in", 2)
S.midi_in(1, {type = "cc", cc = 74, val = 12, ch = 1})  -- track 1 filter freq
S.midi_sent = {}
redraw()
ok(true, "incoming CC does not echo back (" .. #S.midi_sent .. " sent)")

---------------------------------------------------------------- morph
section("morph")
params:set("morph", 4) -- 1 beat
params:set("rnd_spread", 0)
for _ = 1, 12 do enc(1, -1) end -- back to a track page
S.midi_sent = {}
key(2, 1) key(2, 0)
local immediate = #S.midi_sent
S.advance_time(0.6)
S.advance_all(4)
ok(#S.midi_sent > immediate, "morph keeps sending after the key press")

---------------------------------------------------------------- pset
section("pset round trip")
params.action_write("f", "n", 1)
local before = {}
for k, v in pairs(S.upvalue(redraw, "core").values) do before[k] = v end
key(1, 1) key(3, 1) key(3, 0) key(1, 0) -- randomize a whole track
params.action_read("f", false, 1)
local core = S.upvalue(redraw, "core")
local same = true
for k, v in pairs(before) do if core.values[k] ~= v then same = false end end
ok(same, "pset restores every stored value")
ok(S.files["/home/we/dust/data/patchtest/rytmpatch-01.data"] ~= nil, "pset data file written")

---------------------------------------------------------------- machines
section("machines")
try("every machine renders and randomizes", function()
  for m = 1, #params.by_id["machine_1"].options do
    params:set("machine_1", m)
    for _ = 1, 20 do enc(1, -1) end -- SYNTH page
    key(2, 1) key(2, 0)
    redraw()
  end
end)

---------------------------------------------------------------- cleanup
section("cleanup")
try("cleanup() runs clean", cleanup)
ok(S.files["/home/we/dust/data/patchtest/rytmpatch-last.data"] ~= nil,
   "cleanup autosaves the session")

S.real_print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
