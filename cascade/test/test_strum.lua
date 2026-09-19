-- drives lib/strum.lua against the stubbed norns clock and a recording MIDI
-- device. the engine is where every note-off lives, so most of this is about
-- one question: can a note ever be left ringing?
--
-- three bugs found on hardware are pinned here by name; each one fails this
-- file if the fix is reverted.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")
package.path = HERE .. "/../lib/?.lua;" .. package.path

local Patterns = require("patterns")
local Strum = require("strum")

local print = S.real_print
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end

---------------------------------------------------------------- harness
local dev = midi.connect(1)
local O

local function defaults()
  O = {
    device = dev, channel = 1, gap = 0.03,
    cycle = false, cycle_sync = false, cycle_sec = 0.4, cycle_beats = 1,
    retrigger_now = true, release_sec = 0, repeat_sec = 0.4, gate_sec = 0,
    fit = false, span = 0.5, velocity = 100, tilt = 0, humanize = 0, drift = 0,
    density = 1, probability = 1, upstroke_level = 1, upstroke_keep = 1,
    bass_channel = nil, bass_shift = 0,
    pattern = {pattern = 1, mode = 1, every = 1, morph = 0},
  }
end

local function reset()
  S.midi_sent = {}
  S.coros, S.wakes, S.now, S.cancels = {}, {}, 0, 0
  defaults()
end
local function engine()
  return Strum.new{opts = function() return O end, cycler = Patterns.cycler()}
end
local function chord(t) return function() return t end end
local function at(t) S.run_until(t) end

-- pitches with a note-on and no matching note-off: the thing that must
-- never happen
local function ringing()
  local on = {}
  for _, e in ipairs(S.midi_sent) do
    if e.t == "on" then on[e.note] = true elseif e.t == "off" then on[e.note] = nil end
  end
  local out = {}
  for n in pairs(on) do out[#out + 1] = n end
  table.sort(out)
  return out
end
local function note_ons(from, to)
  local out = {}
  for _, e in ipairs(S.midi_sent) do
    if e.t == "on" then out[#out + 1] = e end
  end
  return out
end

local C = {48, 52, 55, 59, 62, 67}

---------------------------------------------------------------- basics
section("holding and letting go")
reset()
local s = engine()
s:add("a", chord(C))
at(0.05)
local before = #note_ons()
s:remove("a")
at(2)
ok(#ringing() == 0, "letting go mid-strum leaves nothing ringing")
ok(#note_ons() == before, "and nothing sounds after the release")

reset(); O.release_sec = 0.3
s = engine()
s:add("a", chord(C))
at(0.5)
s:remove("a")
at(0.79)
ok(#ringing() == #C, "notes ring on through the release time")
at(0.81)
ok(#ringing() == 0, "then stop")

---------------------------------------------------------------- merging
section("chords merging into one strum")
reset(); O.cycle = true
s = engine()
s:add("a", chord({48, 52, 55}))
s:add("b", chord({50, 53, 57}))
at(0.4)
local all, start, seen = note_ons(), nil, 0
for i, e in ipairs(all) do
  if e.note == 48 then seen = seen + 1; if seen == 2 then start = i break end end
end
local merged, spacing_even = {}, true
for i = start, math.min(start + 5, #all) do
  merged[#merged + 1] = all[i].note
  if #merged > 1 and math.abs((all[i].time - all[i - 1].time) - 0.03) > 1e-6 then
    spacing_even = false
  end
end
ok(table.concat(merged, ",") == "48,50,52,53,55,57",
   "two held chords strum as one run of notes: " .. table.concat(merged, ","))
ok(spacing_even, "evenly spaced, not two strums overlapping")
s:panic(dev)

reset()
s = engine()
s:add("a", chord({48, 52, 55}))
s:add("b", chord({52, 55, 59}))
at(0.5)
local mark = #S.midi_sent
s:remove("a")
at(0.5)
local shared_cut = false
for i = mark + 1, #S.midi_sent do
  local e = S.midi_sent[i]
  if e.t == "off" and (e.note == 52 or e.note == 55) then shared_cut = true end
end
ok(not shared_cut, "a pitch two chords share survives releasing one of them")
s:remove("b")
ok(#ringing() == 0, "and stops once the last owner lets go")

---------------------------------------------------------------- timing
section("repeat timing")
reset(); O.cycle = true; O.retrigger_now = false; O.cycle_sec = 0.4
s = engine()
s:add("a", chord({48, 52}))
at(0.2)
s:add("b", chord({60, 64}))
at(0.39)
local joined_early = false
for _, e in ipairs(note_ons()) do
  if e.time > 0.2 and e.time < 0.39 then joined_early = true end
end
ok(not joined_early, "'next repeat': a new chord waits its turn")
at(0.45)
local first_after
for _, e in ipairs(note_ons()) do
  if e.time > 0.2 and not first_after then first_after = e.time end
end
ok(first_after and math.abs(first_after - 0.43) < 1e-6,
   "and joins exactly on the repeat")

reset(); O.cycle = true; O.retrigger_now = true; O.cycle_sec = 0.4
s = engine()
s:add("a", chord({48, 52}))
at(0.2)
s:add("b", chord({60, 64}))
local immediate = 0
for _, e in ipairs(note_ons()) do if math.abs(e.time - 0.2) < 1e-9 then immediate = immediate + 1 end end
ok(immediate >= 1, "'strum now': a new chord sounds at the moment of the press")
s:panic(dev)

reset(); O.cycle = true; O.cycle_sync = true; O.cycle_beats = 0.5
s = engine()
at(0.1)
s:add("a", chord({48, 52}))
at(1.1)
local on_grid, starts = true, 0
for _, e in ipairs(note_ons()) do
  if e.note == 48 and e.time > 0.11 then
    starts = starts + 1
    if math.abs(e.time / 0.25 - util.round(e.time / 0.25)) > 1e-6 then on_grid = false end
  end
end
ok(on_grid and starts >= 3, "synced repeats land on the beat grid")
s:panic(dev)

---------------------------------------------------------------- hardware bugs
section("the three bugs found on hardware")

-- 1. cancelling a clock that had a wake queued -> "bad argument #1 to
-- 'resume' (thread expected)", and note-off timers dying with it
reset(); O.cycle = true; O.cycle_sync = true; O.cycle_beats = 1
s = engine()
s:add("a", chord({48, 52}))
at(0.3)
local survived = pcall(function()
  s:add("b", chord({60, 64}))
  at(3)
end)
ok(survived and S.cancels == 0,
   "pressing a chord between repeats cancels no clock (" .. S.cancels .. " cancels)")
s:panic(dev)

-- 2. a note struck just after its own chord was released
reset(); O.cycle = true; O.cycle_sec = 2; O.repeat_sec = 2; O.gap = 0.05
O.release_sec = 0.3
s = engine()
s:add("a", chord({48, 52, 55}))
s:add("b", chord({60, 64, 67}))
at(0.02)
s:remove("a")
at(2.5)
local left = ringing()
ok(#left == 3 and left[1] == 60 and left[3] == 67,
   "releasing mid-strum doesn't strike its notes afterwards: " .. table.concat(left, ","))
s:panic(dev)

-- 3. a stale note-off deadline left behind by a re-press
reset(); O.release_sec = 0.2
s = engine()
s:add("a", chord({48, 52, 55}))
at(0.1)
s:remove("a")
at(0.3)
s:add("b", chord({48, 52, 55}))
at(0.6)
O.release_sec = 0.5
s:remove("b")
at(3)
ok(#ringing() == 0,
   "re-pressing a ringing note still leaves it stoppable: " .. table.concat(ringing(), ","))

---------------------------------------------------------------- feel
section("note length, density, fit, upstrokes, drift")
reset(); O.cycle = true; O.cycle_sec = 1; O.repeat_sec = 1
s = engine()
s:add("a", chord(C))
at(0.9)
ok(#ringing() == #C, "let ring: still sounding at the end of the repeat")
s:panic(dev)

reset(); O.cycle = true; O.cycle_sec = 1; O.repeat_sec = 1; O.gate_sec = 0.5
s = engine()
s:add("a", chord(C))
at(0.4)
ok(#ringing() == #C, "50% note length: sounding before the gate closes")
at(0.85)
ok(#ringing() == 0, "50% note length: silent before the next repeat")
s:panic(dev)

reset(); O.repeat_sec = 1; O.gate_sec = 0.3; O.release_sec = 2
s = engine()
s:add("a", chord({48}))
at(0.1)
s:remove("a")
at(0.45)
ok(#ringing() == 0, "letting go can't extend a note past its note length")

reset(); O.density = 0.5
s = engine()
s:add("a", chord(C))
at(1)
local played = {}
for _, e in ipairs(note_ons()) do played[#played + 1] = e.note end
table.sort(played)
ok(#played == 3 and played[1] == C[1] and played[3] == C[#C],
   "density thins from the middle, keeping the outer notes: " .. table.concat(played, ","))
s:panic(dev)

local function span_of(notes, repeat_sec)
  reset(); O.fit = true; O.span = 0.5; O.repeat_sec = repeat_sec; O.cycle_sec = repeat_sec
  local e = engine()
  e:add("a", chord(notes))
  at(repeat_sec * 2)
  local ons = note_ons()
  local first, last = ons[1].time, ons[#ons].time
  e:panic(dev)
  return last - first
end
ok(math.abs(span_of({48,52,55,59,62,67}, 1) - 0.5) < 1e-6, "fit: 6 notes span half the repeat")
ok(math.abs(span_of({48,50,52,53,55,57,59,60,62,64,65,67}, 1) - 0.5) < 1e-6,
   "fit: 12 notes span the same half")
ok(math.abs(span_of({48,52,55,59,62,67}, 0.5) - 0.25) < 1e-6, "fit: follows the repeat length")

local function stroke(pattern_idx)
  reset(); O.upstroke_level = 0.5; O.upstroke_keep = 0.5
  O.pattern = {pattern = pattern_idx, mode = 1, every = 1, morph = 0}
  local e = engine()
  e:add("a", chord(C))
  at(1)
  local notes, vels = {}, {}
  for _, ev in ipairs(note_ons()) do notes[#notes + 1] = ev.note; vels[#vels + 1] = ev.vel end
  e:panic(dev)
  table.sort(notes)
  return notes, vels
end
local down_notes, down_vels = stroke(1)
ok(#down_notes == #C and down_vels[1] == 100, "a downstroke plays every note at full velocity")
local up_notes, up_vels = stroke(#Patterns.NAMES - 1) -- "down" = highest note first
ok(#up_notes == 3 and up_notes[1] == C[4], "an upstroke catches only the top notes")
ok(up_vels[1] == 50, "and plays them quieter")

local function spans(drift, humanize)
  math.randomseed(11)
  reset(); O.cycle = true; O.cycle_sec = 0.6; O.repeat_sec = 0.6; O.gap = 0.03
  O.drift, O.humanize = drift, humanize
  local e = engine()
  e:add("a", chord(C))
  at(40)
  local out, first = {}, nil
  for _, ev in ipairs(note_ons()) do
    if ev.note == C[1] then first = ev.time
    elseif ev.note == C[#C] and first then out[#out + 1] = ev.time - first; first = nil end
  end
  e:panic(dev)
  local lo, hi, step = math.huge, -math.huge, 0
  for i, v in ipairs(out) do
    lo, hi = math.min(lo, v), math.max(hi, v)
    if i > 1 then step = step + math.abs(v - out[i - 1]) end
  end
  return hi - lo, step / math.max(#out - 1, 1)
end
local d_range, d_step = spans(1, 0)
ok(d_range > 0.005, "drift varies the strum length")
ok(d_step < d_range / 2, "drift wanders slowly rather than jumping each repeat")

---------------------------------------------------------------- bass split
section("bass split")
reset(); O.bass_channel = 2; O.bass_shift = -12
s = engine()
s:add("a", chord({48, 52, 55, 59}))
at(1)
local bass_on, chord_chans, bass_note = 0, {}, nil
for _, e in ipairs(S.midi_sent) do
  if e.t == "on" then
    if e.ch == 2 then bass_on = bass_on + 1; bass_note = e.note
    else chord_chans[e.ch] = true end
  end
end
ok(bass_on == 1, "exactly one note goes to the bass channel")
ok(bass_note == 36, "and it's the lowest note, moved down an octave: " .. tostring(bass_note))
ok(chord_chans[1] and not chord_chans[2], "the rest stay on the chord channel")
s:remove("a")
at(1)
ok(#ringing() == 0, "the transposed bass note gets its own note-off")

reset(); O.bass_channel = nil
s = engine()
s:add("a", chord({48, 52, 55}))
at(1)
local only_ch1 = true
for _, e in ipairs(S.midi_sent) do
  if e.t == "on" and e.ch ~= 1 then only_ch1 = false end
end
ok(only_ch1, "bass split off: everything on one channel")
s:panic(dev)

---------------------------------------------------------------- panic
section("panic")
reset(); O.cycle = true
s = engine()
for i = 1, 8 do s:add("k" .. i, chord({40 + i * 3, 47 + i * 3, 54 + i * 3})) end
at(1)
ok(s:count() == 8, "eight chords held at once")
s:panic(dev)
at(1)
local ccs = 0
for _, e in ipairs(S.midi_sent) do if e.t == "cc" then ccs = ccs + 1 end end
ok(#ringing() == 0, "panic silences everything")
ok(ccs == 16, "using 16 all-notes-off messages, not 2048 note-offs")

---------------------------------------------------------------- soak
section("soak: randomised playing")
local function soak(seed, seconds)
  math.randomseed(seed)
  reset()
  local st = engine()
  local held = {}
  local t = 0

  while t < seconds do
    local roll = math.random()
    if roll < 0.18 then
      local k = "k" .. math.random(8)
      local root = 40 + math.random(24)
      local notes = {}
      for i = 1, math.random(3, 6) do notes[i] = root + (i - 1) * math.random(2, 4) end
      local found = false
      for _, h in ipairs(held) do if h == k then found = true end end
      if not found then held[#held + 1] = k end
      st:add(k, chord(notes))
    elseif roll < 0.34 and #held > 0 then
      st:remove(table.remove(held, math.random(#held)))
    elseif roll < 0.40 then
      O.cycle = math.random() < 0.7
      O.cycle_sync = math.random() < 0.5
      O.cycle_sec = 0.15 + math.random() * 0.6
      O.cycle_beats = ({0.25, 0.5, 1})[math.random(3)]
      O.repeat_sec = O.cycle_sec
      O.retrigger_now = math.random() < 0.5
    elseif roll < 0.46 then
      O.gap = math.random() * 0.06
      O.humanize, O.drift = math.random(), math.random()
      O.probability = 0.5 + math.random() * 0.5
      O.density = 0.3 + math.random() * 0.7
      O.release_sec = math.random() * 0.8
      O.gate_sec = (math.random() < 0.5) and 0 or (math.random() * 0.5)
      O.upstroke_level = 0.3 + math.random() * 0.7
      O.upstroke_keep = 0.3 + math.random() * 0.7
      O.fit = math.random() < 0.4
      O.span = 0.2 + math.random() * 0.8
      O.bass_channel = (math.random() < 0.4) and 2 or nil
      O.bass_shift = ({-24, -12, 0})[math.random(3)]
    elseif roll < 0.50 then
      O.pattern = {pattern = math.random(#Patterns.NAMES), mode = math.random(4),
                   every = math.random(4), morph = math.random(0, 3)}
    elseif roll < 0.52 then
      held = {}
      st:panic(dev)
    end
    t = t + 0.05
    at(t)
  end

  for _, k in ipairs(held) do st:remove(k) end
  at(t + 5)
  return #ringing(), S.cancels
end

local soak_problems = 0
for i = 1, 25 do
  local okc, left, cancels = pcall(soak, i * 37, 120)
  if not okc then
    soak_problems = soak_problems + 1
    print("  seed " .. (i * 37) .. " crashed: " .. tostring(left))
  elseif left > 0 or cancels > 0 then
    soak_problems = soak_problems + 1
    print("  seed " .. (i * 37) .. ": " .. left .. " notes ringing, " .. cancels .. " cancels")
  end
end
ok(soak_problems == 0,
   "25 x 2 simulated minutes of random playing: no crash, nothing left ringing")

---------------------------------------------------------------- done
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
