-- covers lib/output.lua: routing notes to MIDI, to Just Friends over crow's
-- ii bus, or both. the strum engine holds this object believing it's a midi
-- device, so the first thing to prove is that it behaves like one.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")
package.path = HERE .. "/../lib/?.lua;" .. package.path

local Output = require("output")

local print = S.real_print
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end

local dev = midi.connect(1)
local function reset()
  S.midi_sent, S.crow_sent = {}, {}
  S.crow_present = true
end
local function midi_notes(kind)
  local out = {}
  for _, e in ipairs(S.midi_sent) do
    if e.t == kind then out[#out + 1] = e.note end
  end
  return out
end
local function voices_played()
  local out = {}
  for _, a in ipairs(S.crow_calls("jf.play_voice")) do
    out[#out + 1] = {voice = a[1], volts = a[2], level = a[3]}
  end
  return out
end

---------------------------------------------------------------- routing
section("routing")
reset()
local o = Output.new()
o:configure{midi = true, jf = false, device = dev, jf_level = 5, jf_sustain = false}
o:note_on(60, 100, 1)
o:note_off(60, 0, 1)
ok(#midi_notes("on") == 1 and #midi_notes("off") == 1, "midi only: the note goes out over MIDI")
ok(#S.crow_sent == 0, "midi only: nothing is sent to crow")

reset()
o:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = false}
o:note_on(60, 100, 1)
ok(#S.midi_sent == 0, "just friends only: nothing goes out over MIDI")
ok(#voices_played() == 1, "just friends only: the note is played on a voice")
o:note_off(60, 0, 1)

reset()
o:configure{midi = true, jf = true, device = dev, jf_level = 5, jf_sustain = false}
o:note_on(60, 100, 1)
ok(#midi_notes("on") == 1 and #voices_played() == 1, "both: the note goes to each")
o:note_off(60, 0, 1)

---------------------------------------------------------------- handover
section("taking Just Friends over and giving it back")
reset()
local h = Output.new()
h:configure{midi = true, jf = false, device = dev, jf_level = 5, jf_sustain = false}
ok(#S.crow_calls("jf.mode") == 0, "no handover while JF isn't the target")

h:configure{midi = true, jf = true, device = dev, jf_level = 5, jf_sustain = false}
local modes = S.crow_calls("jf.mode")
ok(#modes == 1 and modes[1][1] == 1, "switching to JF hands it over with mode(1)")

h:configure{midi = true, jf = true, device = dev, jf_level = 6, jf_sustain = true}
ok(#S.crow_calls("jf.mode") == 1,
   "changing other settings doesn't repeat the handover (mode latches)")

h:configure{midi = true, jf = false, device = dev, jf_level = 5, jf_sustain = false}
modes = S.crow_calls("jf.mode")
ok(#modes == 2 and modes[2][1] == 0, "switching away gives JF back with mode(0)")

reset()
h:configure{midi = true, jf = true, device = dev, jf_level = 5, jf_sustain = false}
h:shutdown()
local after = S.crow_calls("jf.mode")
ok(after[#after][1] == 0, "shutdown gives JF back, so it isn't left ignoring its panel")

---------------------------------------------------------------- pitch, level
section("pitch and level")
reset()
o:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = false}
o:note_on(60, 127, 1)
local v = voices_played()[1]
ok(math.abs(v.volts) < 1e-9, "middle C is 0V")
ok(math.abs(v.level - 5) < 1e-9, "full velocity reaches the level setting")
o:note_off(60)

reset()
o:note_on(72, 127, 1)
ok(math.abs(voices_played()[1].volts - 1) < 1e-9, "an octave up is 1V")
o:note_off(72)
reset()
o:note_on(48, 127, 1)
ok(math.abs(voices_played()[1].volts + 1) < 1e-9, "an octave down is -1V")
o:note_off(48)

reset()
o:note_on(60, 64, 1)
local half = voices_played()[1].level
ok(half > 2 and half < 3, "half velocity is about half level (" .. string.format("%.2f", half) .. ")")
o:note_off(60)

reset()
o:configure{midi = false, jf = true, device = dev, jf_level = 10, jf_sustain = false}
o:note_on(60, 127, 1)
ok(math.abs(voices_played()[1].level - 10) < 1e-9, "the level setting scales the output")
o:note_off(60)
o:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = false}

---------------------------------------------------------------- voices
section("six voices")
reset()
local six = Output.new()
six:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = false}
for i = 0, 5 do six:note_on(60 + i, 100, 1) end
local used, seen = 0, {}
for _, p in ipairs(voices_played()) do
  if not seen[p.voice] then seen[p.voice] = true; used = used + 1 end
end
ok(used == 6, "six notes take six different voices (" .. used .. ")")

reset()
six:note_on(80, 100, 1)         -- a seventh, with none free
local stolen = voices_played()[1]
ok(stolen ~= nil, "a seventh note still sounds, by taking a voice")
local holding = six:jf_voices()
local holds_80, holds_60 = false, false
for _, note in pairs(holding) do
  if note == 80 then holds_80 = true end
  if note == 60 then holds_60 = true end
end
ok(holds_80, "the new note is holding a voice")
ok(not holds_60, "and it took the oldest one, not an arbitrary one")

reset()
six:note_off(80)
local free_after = 0
for v = 1, 6 do if six:jf_voices()[v] == nil then free_after = free_after + 1 end end
ok(free_after >= 1, "letting a note go frees its voice")

reset()
local re = Output.new()
re:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = false}
re:note_on(60, 100, 1)
re:note_on(60, 100, 1)          -- re-struck, as a cycling strum does
local distinct = {}
for _, p in ipairs(voices_played()) do distinct[p.voice] = true end
local n = 0
for _ in pairs(distinct) do n = n + 1 end
ok(n == 1, "re-striking the same pitch reuses its voice rather than taking another")

---------------------------------------------------------------- pluck/sustain
section("pluck and sustain")
reset()
local p = Output.new()
p:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = false}
p:note_on(60, 100, 1)
local before = #voices_played()
p:note_off(60)
ok(#voices_played() == before,
   "pluck: letting go sends nothing, JF's own envelope ends the note")

reset()
local sus = Output.new()
sus:configure{midi = false, jf = true, device = dev, jf_level = 5, jf_sustain = true}
sus:note_on(60, 100, 1)
sus:note_off(60)
local calls = voices_played()
ok(#calls == 2 and calls[2].level == 0, "sustain: letting go closes the voice with level 0")

---------------------------------------------------------------- panic
section("panic")
reset()
local pa = Output.new()
pa:configure{midi = true, jf = true, device = dev, jf_level = 5, jf_sustain = false}
for i = 0, 3 do pa:note_on(60 + i, 100, 1) end
reset()
for ch = 1, 16 do pa:cc(123, 0, ch) end
local silenced = 0
for _, c in ipairs(voices_played()) do if c.level == 0 then silenced = silenced + 1 end end
ok(silenced == 4, "panic releases every voice JF was holding (" .. silenced .. ")")
local still_held = 0
for v = 1, 6 do if pa:jf_voices()[v] ~= nil then still_held = still_held + 1 end end
ok(still_held == 0, "and forgets them all")
local ccs = 0
for _, e in ipairs(S.midi_sent) do if e.t == "cc" then ccs = ccs + 1 end end
ok(ccs == 16, "while MIDI still gets its 16 all-notes-off messages")

---------------------------------------------------------------- no crow
section("crow unplugged")
reset()
S.crow_present = false
local safe = pcall(function()
  local u = Output.new()
  u:configure{midi = true, jf = true, device = dev, jf_level = 5, jf_sustain = false}
  u:note_on(60, 100, 1)
  u:note_off(60)
  u:cc(123, 0, 1)
  u:shutdown()
end)
ok(safe, "everything still runs with no crow attached")
ok(#midi_notes("on") == 1, "and MIDI carries on regardless")
S.crow_present = true

---------------------------------------------------------------- no device
section("no midi device")
reset()
local nd = Output.new()
nd:configure{midi = true, jf = false, device = nil, jf_level = 5, jf_sustain = false}
local quiet = pcall(function()
  nd:note_on(60, 100, 1)
  nd:note_off(60)
  nd:cc(123, 0, 1)
end)
ok(quiet, "a missing MIDI device is survivable too")

---------------------------------------------------------------- done
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
