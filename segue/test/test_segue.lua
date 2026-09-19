-- off-device smoke test for segue's pure-Lua core: the pattern structure,
-- the lane/follow-action engine, the built-in library and the MIDI voice
-- layer. none of these touch a norns API, so plain desktop Lua runs them.
--
--   lua segue/test/test_segue.lua
--
-- see test_script.lua for the other half -- the whole script driven against
-- a stubbed norns runtime.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = HERE .. "/../lib/"

local Pattern = dofile(ROOT .. "pattern.lua")
local Lane    = dofile(ROOT .. "lane.lua")
local Library = dofile(ROOT .. "library.lua")
local Voices  = dofile(ROOT .. "voices.lua")

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end

math.randomseed(12345)

---------------------------------------------------------------- library
section("library")
local total_patterns = 0
for li, spec in ipairs(Library.LANES) do
  ok(#spec.voices >= 1, spec.name .. " has voices")
  for pi, entry in ipairs(spec.patterns) do
    local name, rows = entry[1], entry[2]
    ok(#rows == #spec.voices,
       spec.name .. "/" .. name .. " has one row per voice (got " ..
       #rows .. ", want " .. #spec.voices .. ")")
    for ri, row in ipairs(rows) do
      ok(#row == 16, spec.name .. "/" .. name .. " row " .. ri ..
         " is 16 chars (got " .. #row .. ")")
      ok(row:match("^[Xxo%-]+$") ~= nil,
         spec.name .. "/" .. name .. " row " .. ri .. " uses only Xxo-")
    end
    total_patterns = total_patterns + 1
  end
end
print("  " .. total_patterns .. " library patterns across " ..
      #Library.LANES .. " lanes")
local voice_seen = {}
for _, spec in ipairs(Library.LANES) do
  for _, v in ipairs(spec.voices) do
    ok(voice_seen[v] == nil, "voice " .. v .. " assigned only once")
    voice_seen[v] = true
  end
end
for v = 1, 12 do ok(voice_seen[v], "Rytm voice " .. v .. " is covered") end

---------------------------------------------------------------- pattern
section("pattern")
local p = Pattern.from_rows({"X---x---X---x---"}, "four", 16)
ok(Pattern.get(p, 1, 1) == Pattern.ACCENT, "step 1 is an accent")
ok(Pattern.get(p, 1, 5) == Pattern.NORMAL, "step 5 is normal")
ok(Pattern.get(p, 1, 2) == nil, "step 2 is a rest")
ok(Pattern.get(p, 1, 17) == Pattern.ACCENT, "get wraps past the length")
ok(not Pattern.is_empty(p), "a written pattern is not empty")
ok(Pattern.is_empty(Pattern.new(1, 16)), "a fresh pattern is empty")

local c = Pattern.new(1, 16)
ok(Pattern.cycle(c, 1, 3) == Pattern.NORMAL, "cycle: rest -> normal")
ok(Pattern.cycle(c, 1, 3) == Pattern.ACCENT, "cycle: normal -> accent")
ok(Pattern.cycle(c, 1, 3) == Pattern.GHOST, "cycle: accent -> ghost")
ok(Pattern.cycle(c, 1, 3) == nil, "cycle: ghost -> rest")

local cp = Pattern.copy(p)
Pattern.set(cp, 1, 1, nil)
ok(Pattern.get(p, 1, 1) == Pattern.ACCENT, "copy is independent of original")

---------------------------------------------------------------- lane helpers
local function build_lane(spec_index)
  local spec = Library.LANES[spec_index]
  local l = Lane:new{pattern_lib = Pattern, id = spec_index,
                     name = spec.name, voices = spec.voices}
  Library.populate(l, spec, Pattern)
  return l
end

-- run `ticks` master ticks, collecting (tick, pos, active, hits) per step
local function run(lane, ticks, quant, log)
  for t = 0, ticks - 1 do
    local pos_before = lane.pos
    local n = lane:tick(t, quant)
    if n > 0 or lane.fired then
      if log then
        log[#log + 1] = {t = t, pos = lane.pos, active = lane.active, n = n}
      end
    end
  end
end

---------------------------------------------------------------- timing
section("timing")
local kick = build_lane(1)
kick.follow_on = false
local fires = 0
for t = 0, 95 do
  if kick:tick(t, 0) >= 0 then end
end
-- count actual steps by watching pos change
kick:reset()
local steps = {}
for t = 0, 95 do
  local before = kick.pos
  kick:tick(t, 0)
  if t % 6 == 0 then steps[#steps + 1] = t end
end
ok(#steps == 16, "a 1/16 lane takes 16 steps per bar (got " .. #steps .. ")")

kick:reset()
kick.div = 3 -- 1/8 = 12 ticks
local n8 = 0
for t = 0, 95 do if kick:tick(t, 0) >= 0 and t % 12 == 0 then n8 = n8 + 1 end end
ok(n8 == 8, "a 1/8 lane takes 8 steps per bar (got " .. n8 .. ")")

-- every division divides a bar evenly, so a step always lands on a boundary
for i, dt in ipairs(Lane.DIV_TICKS) do
  ok(96 % dt == 0, Lane.DIV_NAMES[i] .. " divides a bar evenly")
end

---------------------------------------------------------------- legato / cut
section("legato vs cut")
local l = build_lane(1)
l.follow_on = false
l:reset()
-- advance to step 5 (ticks 0,6,12,18,24 -> pos 1..5)
for t = 0, 24 do l:tick(t, 0) end
ok(l.pos == 5, "playhead reached step 5 (got " .. l.pos .. ")")

local legato = build_lane(1)
legato.follow_on = false
legato:reset()
for t = 0, 24 do legato:tick(t, 0) end
legato:commit(4, Lane.TRANS_LEGATO)
ok(legato.active == 4, "legato commit changed pattern")
ok(legato.pos == 5, "legato kept the playhead at step 5 (got " ..
   legato.pos .. ")")

local cut = build_lane(1)
cut.follow_on = false
cut:reset()
for t = 0, 24 do cut:tick(t, 0) end
cut:commit(4, Lane.TRANS_CUT)
ok(cut.pos == 1, "cut snapped the playhead back to step 1 (got " ..
   cut.pos .. ")")

-- legato into a shorter pattern wraps rather than running off the end
local short = build_lane(1)
short.follow_on = false
short.bank[4].length = 4
short:reset()
for t = 0, 24 do short:tick(t, 0) end -- pos 5
short:commit(4, Lane.TRANS_LEGATO)
ok(short.pos == 1, "legato into a 4-step pattern wrapped 5 -> 1 (got " ..
   short.pos .. ")")

---------------------------------------------------------------- follow: end
section("follow actions")
local fl = build_lane(1)
fl.follow_on = true
fl.transition = Lane.TRANS_CUT
for i = 1, 8 do fl.bank[i].follow.time = Pattern.FOLLOW_END end
fl.bank[1].follow.a = 2 -- next
fl:reset()
fl.active = 1
-- 16 steps of pattern 1, then the follow should move us to pattern 2
for t = 0, 16 * 6 do fl:tick(t, 0) end
ok(fl.active == 2, "follow 'end' + 'next' moved to pattern 2 (got " ..
   fl.active .. ")")

-- an absolute follow time fires mid-pattern
local mid = build_lane(1)
mid.transition = Lane.TRANS_LEGATO
for i = 1, 8 do
  mid.bank[i].follow.time = 4 -- 1/4 note = 4 sixteenths
  mid.bank[i].follow.a = 2
end
mid:reset()
mid.active = 1
for t = 0, 4 * 6 do mid:tick(t, 0) end
ok(mid.active == 2, "follow at 1/4 fired after 4 steps (got pattern " ..
   mid.active .. ")")
ok(mid.pos == 5, "...and legato carried the playhead into step 5 (got " ..
   mid.pos .. ")")

-- follow time is expressed in 16ths and survives a division change
local dv = build_lane(1)
dv.div = 3 -- 1/8
dv.bank[1].follow.time = 16 -- one bar
ok(dv:follow_steps() == 8, "one bar is 8 steps on a 1/8 lane (got " ..
   tostring(dv:follow_steps()) .. ")")
dv.div = Lane.DIV_16TH
ok(dv:follow_steps() == 16, "one bar is 16 steps on a 1/16 lane (got " ..
   tostring(dv:follow_steps()) .. ")")

-- skip_empty keeps follow off silent slots
local se = build_lane(7) -- CYM: slot 8 is empty in the library
se.skip_empty = true
local cands = {}
local n = se:_candidates(cands)
ok(n == 7, "CYM has 7 non-empty patterns (got " .. n .. ")")
se.skip_empty = false
n = se:_candidates(cands)
ok(n == 8, "with skip_empty off all 8 slots are candidates (got " .. n .. ")")

-- 'other' never returns the pattern already playing
local oth = build_lane(1)
local self_hits = 0
for i = 1, 300 do
  oth.active = math.random(8)
  local got = oth:_resolve(7) -- other
  if got == oth.active then self_hits = self_hits + 1 end
end
ok(self_hits == 0, "'other' never picks the active pattern (got " ..
   self_hits .. " self-picks)")

-- 'next' wraps
local nx = build_lane(1)
nx.active = 8
ok(nx:_resolve(2) == 1, "'next' wraps 8 -> 1")
nx.active = 1
ok(nx:_resolve(3) == 8, "'prev' wraps 1 -> 8")

---------------------------------------------------------------- morph
section("morph")
-- pattern A: hits on every step. pattern B: no hits at all. during an
-- xfade, the number of hits should fall off across the window.
local mo = build_lane(1)
mo.follow_on = false
mo.bank[1] = Pattern.from_rows({"xxxxxxxxxxxxxxxx"}, "all", 16)
mo.bank[2] = Pattern.from_rows({"----------------"}, "none", 16)
mo.morph_steps = 16
mo.transition = Lane.TRANS_XFADE
mo:reset()
mo:tick(0, 0)
mo:commit(2, Lane.TRANS_XFADE)
local early, late = 0, 0
for s = 1, 8 do
  local t = s * 6
  if mo:tick(t, 0) > 0 then early = early + 1 end
end
for s = 9, 16 do
  local t = s * 6
  if mo:tick(t, 0) > 0 then late = late + 1 end
end
ok(early > late, "xfade thins out across the window (early " .. early ..
   " vs late " .. late .. ")")
ok(mo.morph_left == 0, "morph window closed after morph_steps steps")
local after = 0
for s = 17, 24 do if mo:tick(s * 6, 0) > 0 then after = after + 1 end end
ok(after == 0, "after the morph, only the new pattern plays (got " ..
   after .. " hits from the old one)")

-- handover: voices switch one at a time, anchor (slot 1) last
local ho = build_lane(4) -- TOMS, 4 slots
ho.follow_on = false
ho.bank[1] = Pattern.from_rows({"xxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxx",
                                "xxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxx"},
                               "all", 16)
ho.bank[2] = Pattern.from_rows({"----------------", "----------------",
                                "----------------", "----------------"},
                               "none", 16)
ho.morph_steps = 8
ho:reset()
ho:tick(0, 0)
ho:commit(2, Lane.TRANS_HANDOVER)
local counts = {}
for s = 1, 8 do counts[s] = ho:tick(s * 6, 0) end
local monotonic = true
for s = 2, 8 do if counts[s] > counts[s - 1] then monotonic = false end end
ok(monotonic, "handover drops voices monotonically (" ..
   table.concat(counts, ",") .. ")")
ok(counts[8] == 0, "handover has fully changed over by the end")

-- handover on a single-slot lane falls back to the probabilistic blend
local ho1 = build_lane(1)
ho1.follow_on = false
ho1.bank[1] = Pattern.from_rows({"xxxxxxxxxxxxxxxx"}, "all", 16)
ho1.bank[2] = Pattern.from_rows({"----------------"}, "none", 16)
ho1.morph_steps = 16
ho1:reset()
ho1:tick(0, 0)
ho1:commit(2, Lane.TRANS_HANDOVER)
local h1 = 0
for s = 1, 16 do h1 = h1 + ho1:tick(s * 6, 0) end
ok(h1 > 0 and h1 < 16, "single-slot handover blends rather than cutting (" ..
   h1 .. " hits over 16 steps)")

---------------------------------------------------------------- quantize
section("launch quantize")
local q = build_lane(1)
q.follow_on = false
q:reset()
for t = 0, 30 do q:tick(t, 96) end -- one bar quantize
q:launch(5, Lane.TRANS_CUT)
ok(q.active == 1, "a queued launch does not take effect immediately")
for t = 31, 95 do q:tick(t, 96) end
ok(q.active == 1, "still queued part way through the bar")
for t = 96, 102 do q:tick(t, 96) end
ok(q.active == 5, "queued launch committed on the bar line (got " ..
   q.active .. ")")

local qi = build_lane(1)
qi.follow_on = false
qi:reset()
for t = 0, 30 do qi:tick(t, 0) end
qi:launch(5, Lane.TRANS_LEGATO)
for t = 31, 36 do qi:tick(t, 0) end
ok(qi.active == 5, "instant quantize commits at the next step")

local qc = build_lane(1)
qc:launch(5)
qc:launch(5)
ok(qc.queued == nil, "pressing a queued pattern again cancels it")

---------------------------------------------------------------- swing
section("swing")
local sw = build_lane(1)
sw.follow_on = false
sw.swing = 2 -- 2 ticks of 6 = 33%
sw:reset()
local fired = {}
for t = 0, 47 do
  if sw:tick(t, 0) >= 0 then end
end
sw:reset()
for t = 0, 47 do
  local before = sw.pos
  sw:tick(t, 0)
  if sw.pos ~= before or (t == 0) then fired[#fired + 1] = t end
end
ok(fired[1] == 0, "first step on the beat")
ok(fired[2] == 8, "second step delayed by 2 ticks (6 + 2 = 8, got " ..
   tostring(fired[2]) .. ")")
ok(fired[3] == 12, "third step back on the grid (got " ..
   tostring(fired[3]) .. ")")

---------------------------------------------------------------- voices
section("voices / midi")
local sent = {}
local stub = {
  note_on = function(_, n, v, ch)
    sent[#sent + 1] = {"on", n, v, ch}
  end,
  note_off = function(_, n, v, ch)
    sent[#sent + 1] = {"off", n, v, ch}
  end,
}
-- the default layout: everything on one channel, notes counting from zero
local V = Voices:new{dev = stub}
V:trig(1, 100)
ok(sent[1][1] == "on" and sent[1][2] == 0 and sent[1][4] == 1,
   "default layout: BD -> note 0 ch 1 (got note " .. sent[1][2] ..
   " ch " .. sent[1][4] .. ")")
V:trig(2, 100)
ok(sent[2][2] == 1, "SD -> note 1 (got " .. sent[2][2] .. ")")
V:flush()
ok(sent[3][1] == "off" and sent[4][1] == "off", "flush released both notes")

sent = {}
local V12 = Voices:new{dev = stub}
for v = 1, 12 do V12:trig(v, 100) V12:flush() end
local seq_ok = true
for v = 1, 12 do
  local m = sent[(v - 1) * 2 + 1]
  if m[2] ~= v - 1 or m[4] ~= 1 then seq_ok = false end
end
ok(seq_ok, "all 12 voices land on channel 1, notes 0-11 in track order")

-- note 0 is a legal MIDI note and must survive the sounding-key bookkeeping
sent = {}
local V0 = Voices:new{dev = stub}
V0:trig(1, 100)
V0:trig(1, 100)
ok(sent[2][1] == "off" and sent[2][2] == 0,
   "a note-0 retrig closes the previous note 0 first")
V0:panic()
ok(next(V0.sounding) == nil, "panic clears everything sounding")

-- the other two layouts
sent = {}
local Vf = Voices:new{dev = stub, layout = Voices.LAYOUT_FACTORY,
                      base_channel = 10}
Vf:trig(1, 100)
ok(sent[1][2] == 36 and sent[1][4] == 10,
   "factory layout: BD -> note 36 ch 10")
Vf:trig(12, 100)
ok(sent[2][2] == 55, "factory layout: CB -> note 55")

sent = {}
local Vt = Voices:new{dev = stub, layout = Voices.LAYOUT_TRACK}
Vt:trig(1, 100)
ok(sent[1][2] == 60 and sent[1][4] == 1, "track layout: BD -> note 60 ch 1")
Vt:trig(9, 100)
ok(sent[2][4] == 9 and sent[2][2] == 60, "track layout: CH -> note 60 ch 9")

-- base channel actually moves things, on the layouts that use one
for _, layout in ipairs({Voices.LAYOUT_SEQ, Voices.LAYOUT_FACTORY}) do
  local ch = Voices.layout_address(layout, 1, 7)
  ok(ch == 7, "layout " .. layout .. " honours the base channel (got " ..
     ch .. ")")
end
local tch = Voices.layout_address(Voices.LAYOUT_TRACK, 5, 7)
ok(tch == 5, "the track layout ignores the base channel, as documented")

-- a per-voice address overrides whatever a layout put there, and is the
-- only thing consulted at send time
sent = {}
local Vo = Voices:new{dev = stub}
Vo:set_address(1, 5, 42)
Vo:trig(1, 90)
ok(sent[1][2] == 42 and sent[1][4] == 5, "set_address wins for that voice")
Vo:trig(2, 90)
ok(sent[2][2] == 1 and sent[2][4] == 1, "...and leaves the others alone")

---------------------------------------------------------------- persistence
section("persistence")
local s1 = build_lane(3) -- CLAP, 2 slots
s1.active = 4
s1.div = 3
s1.swing = 2
s1.prob = 0.6
s1.transition = Lane.TRANS_XFADE
Pattern.set(s1.bank[1], 2, 7, Pattern.GHOST)
local blob = s1:serialize()

local s2 = build_lane(3)
s2:deserialize(blob)
ok(s2.active == 4, "active pattern survived the round trip")
ok(s2.div == 3, "division survived")
ok(s2.swing == 2, "swing survived")
ok(math.abs(s2.prob - 0.6) < 1e-9, "probability survived")
ok(s2.transition == Lane.TRANS_XFADE, "transition survived")
ok(Pattern.get(s2.bank[1], 2, 7) == Pattern.GHOST, "an edited trig survived")
ok(Pattern.get(s2.bank[2], 1, 5) == Pattern.get(s1.bank[2], 1, 5),
   "an untouched library pattern survived")
ok(s2.bank[1].follow.time == s1.bank[1].follow.time, "follow time survived")

---------------------------------------------------------------- integration
section("8 lanes together")
local lanes = {}
for i = 1, 8 do lanes[i] = build_lane(i) end
local hit_total = 0
local by_voice = {}
for t = 0, 96 * 8 - 1 do          -- eight bars
  for i = 1, 8 do
    local n = lanes[i]:tick(t, 96)
    for h = 1, n do
      local v = lanes[i].hits[h].voice
      by_voice[v] = (by_voice[v] or 0) + 1
      hit_total = hit_total + 1
      ok(lanes[i].hits[h].vel >= 1 and lanes[i].hits[h].vel <= 127,
         "velocity in range")
    end
  end
end
print("  " .. hit_total .. " hits over 8 bars")
ok(hit_total > 200, "eight bars produced a decent number of hits")
local voices_used = 0
for v = 1, 12 do if by_voice[v] then voices_used = voices_used + 1 end end
ok(voices_used >= 10, "most Rytm voices got played (got " ..
   voices_used .. "/12)")
-- the drifting lanes should actually have drifted
ok(lanes[5].active ~= 1 or lanes[6].active ~= 1 or lanes[4].active ~= 1,
   "at least one follow-enabled lane moved off its first pattern")

---------------------------------------------------------------- results
print("")
print(string.rep("-", 46))
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
