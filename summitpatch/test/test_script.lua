-- drives summitpatch.lua against the stubbed norns runtime: init, every
-- page/key/encoder combination, recipes, the AFX overlay path (notes in,
-- overlay CCs then the note out), pset round trip and cleanup.
-- run: lua summitpatch/test/test_script.lua
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")

math.randomseed(13)

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

dofile(S.DIR .. "summitpatch.lua")

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
  ok(pcall(function() return p:string() end), "formatter for " .. p.id)
end
ok(params:get("rnd_spread") == 0, "randomization starts fully tamed")
ok(params.by_id["afx_t8"] ~= nil, "8 AFX targets are params (so psets keep them)")

---------------------------------------------------------------- ui walk
section("ui walk")
try("every page, slot, value and mode", function()
  for _ = 1, 13 do
    enc(1, 1)
    for _ = 1, 8 do
      enc(2, 1)
      enc(3, 4) enc(3, -400) enc(3, 400)
      key(3, 1) key(3, 0)
    end
    key(2, 1) key(2, 0)
    redraw()
  end
  for _ = 1, 13 do enc(1, -1) redraw() end
end)
try("shift combos on an edit page", function()
  key(1, 1)
  enc(1, 1) enc(2, -20) enc(3, 2)
  key(2, 1) key(2, 0)
  key(3, 1) key(3, 0)
  key(1, 0)
  redraw()
end)

section("recipes")
try("every recipe randomizes the whole patch", function()
  for r = 1, #params.by_id["recipe"].options do
    params:set("recipe", r)
    key(1, 1) key(3, 1) key(3, 0) key(1, 0)
    redraw()
  end
end)
params:set("recipe", 1)

---------------------------------------------------------------- midi out
section("midi out")
params:set("morph", 1)
S.midi_sent = {}
key(2, 1) key(2, 0)
ok(#S.midi_sent > 0, "randomize sends CCs (" .. #S.midi_sent .. ")")
local ch_ok = true
for _, m in ipairs(S.midi_sent) do
  if m.ch ~= params:get("out_ch") then ch_ok = false end
end
ok(ch_ok, "everything goes out on the Summit channel")

---------------------------------------------------------------- afx
section("afx overlays")
-- separate input port, so note thru applies
params:set("in_port", 2)
params:set("afx_on", 2)
params:set("afx_release", 2)
-- give the current key slot some offsets, then play it
for _ = 1, 13 do enc(1, 1) end -- AFX page (last)
key(2, 1) key(2, 0)            -- randomize this key's offsets
S.midi_sent = {}
S.midi_in(2, {type = "note_on", note = 60, vel = 90, ch = 1})
local first_note, cc_before_note = nil, 0
for i, m in ipairs(S.midi_sent) do
  if m.t == "on" then first_note = first_note or i
  elseif m.t == "cc" and first_note == nil then cc_before_note = cc_before_note + 1 end
end
ok(first_note ~= nil, "the note is passed through to the Summit")
ok(cc_before_note > 0, "overlay CCs are sent before the note (" .. cc_before_note .. ")")

S.midi_sent = {}
S.midi_in(2, {type = "note_on", note = 60, vel = 90, ch = 1})
local repeats = 0
for _, m in ipairs(S.midi_sent) do if m.t == "cc" then repeats = repeats + 1 end end
ok(repeats == 0, "re-playing the same key resends nothing (values unchanged)")

S.midi_in(2, {type = "note_off", note = 60, vel = 0, ch = 1})
S.midi_sent = {}
S.midi_in(2, {type = "note_off", note = 60, vel = 0, ch = 1})
ok(true, "note off with nothing held is harmless")

-- same port for in and out: notes must NOT be echoed back at the Summit
section("afx with the summit as its own keyboard")
params:set("in_port", 1)
params:set("thru", 3) -- auto
key(1, 1) key(3, 1) key(3, 0) key(1, 0) -- offsets on every key, not just one
S.midi_sent = {}
S.midi_in(1, {type = "note_on", note = 62, vel = 90, ch = 1})
local echoed = false
for _, m in ipairs(S.midi_sent) do if m.t == "on" then echoed = true end end
ok(not echoed, "auto thru does not echo the Summit's own notes back to it")
local overlay = 0
for _, m in ipairs(S.midi_sent) do if m.t == "cc" then overlay = overlay + 1 end end
ok(overlay > 0, "overlay CCs still go out for that key (" .. overlay .. ")")
S.midi_in(1, {type = "note_off", note = 62, vel = 0, ch = 1})

section("midi in mirrors the summit")
params:set("sync_in", 2)
S.midi_in(1, {type = "cc", cc = 29, val = 33, ch = params:get("out_ch")})
local core = S.upvalue(redraw, "core")
ok(core.values["s.cutoff"] == 33, "a knob move on the Summit updates the script's value")

---------------------------------------------------------------- pset
section("pset round trip")
params.action_write("f", "n", 1)
local afx = S.upvalue(enc, "afx") -- enc() is where this local is referenced
local before = afx.offsets[afx.key][1]
key(1, 1) key(3, 1) key(3, 0) key(1, 0) -- randomize every key's offsets
params.action_read("f", false, 1)
afx = S.upvalue(enc, "afx")
ok(afx.offsets[afx.key][1] == before, "AFX offsets round trip through a pset")
ok(S.files["/home/we/dust/data/patchtest/summitpatch-01.data"] ~= nil, "pset data file written")

---------------------------------------------------------------- cleanup
section("cleanup")
try("cleanup() runs clean", cleanup)
ok(S.files["/home/we/dust/data/patchtest/summitpatch-last.data"] ~= nil,
   "cleanup autosaves the session")

S.real_print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
