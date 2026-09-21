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

-- derive every tick figure from the engine's own constants, so a change of
-- PPQN does not silently invalidate the whole suite
local STEP = Lane.TICKS_PER_16TH   -- ticks in one 16th-note step
local BAR  = Lane.TICKS_PER_BAR    -- ticks in one bar

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end

math.randomseed(12345)

---------------------------------------------------------------- library
section("library")
local lane_by_name = {}
for _, spec in ipairs(Library.LANES) do
  ok(#spec.voices >= 1, spec.name .. " has voices")
  lane_by_name[spec.name] = spec
end

local sounding = 0
for ki, kit in ipairs(Library.KITS) do
  ok(type(kit.name) == "string" and #kit.name > 0, "kit " .. ki .. " is named")
  ok(kit.length and kit.length >= 1 and kit.length <= 64,
     kit.name .. " has a legal length (" .. tostring(kit.length) .. ")")
  local voices_in_kit = 0
  for lane_name, rows in pairs(kit.parts) do
    local spec = lane_by_name[lane_name]
    ok(spec ~= nil, kit.name .. " names a real lane ('" .. lane_name .. "')")
    if spec then
      ok(#rows <= #spec.voices,
         kit.name .. "/" .. lane_name .. " has at most one row per voice (" ..
         #rows .. " rows, " .. #spec.voices .. " voices)")
      for ri, row in ipairs(rows) do
        ok(#row == kit.length,
           kit.name .. "/" .. lane_name .. " row " .. ri .. " is " ..
           kit.length .. " chars (got " .. #row .. ")")
        ok(row:match("^[Xxo%-]*$") ~= nil,
           kit.name .. "/" .. lane_name .. " row " .. ri .. " uses only Xxo-")
        if row:match("[Xxo]") then voices_in_kit = voices_in_kit + 1 end
      end
    end
  end
  ok(voices_in_kit >= 3, kit.name .. " sounds at least 3 voices (got " ..
     voices_in_kit .. ")")
  sounding = sounding + voices_in_kit
end
print("  " .. #Library.KITS .. " kits across " .. #Library.LANES ..
      " lanes, " .. sounding .. " sounding voice-parts")
ok(#Library.KITS == 8, "there are 8 kits, one per bank slot (got " ..
   #Library.KITS .. ")")

-- a kit is only worth the name if it is not just a division of the bar.
-- the first version failed exactly here, so it is worth an assertion:
-- at least one kit must place a kick somewhere other than on a beat.
local syncopated = false
for _, kit in ipairs(Library.KITS) do
  local k = kit.parts.KICK and kit.parts.KICK[1]
  if k then
    for step = 1, #k do
      if k:sub(step, step):match("[Xxo]") and ((step - 1) % 4) ~= 0 then
        syncopated = true
      end
    end
  end
end
ok(syncopated, "at least one kit has an off-beat kick")

-- and the library should not be all one length any more
local lengths = {}
for _, kit in ipairs(Library.KITS) do lengths[kit.length] = true end
local n_lengths = 0
for _ in pairs(lengths) do n_lengths = n_lengths + 1 end
ok(n_lengths >= 2, "kits come in more than one length (got " ..
   n_lengths .. ")")
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
for t = 0, BAR - 1 do
  if kick:tick(t, 0) >= 0 then end
end
-- count actual steps by watching pos change
kick:reset()
local steps = {}
for t = 0, BAR - 1 do
  local before = kick.pos
  kick:tick(t, 0)
  if t % STEP == 0 then steps[#steps + 1] = t end
end
ok(#steps == 16, "a 1/16 lane takes 16 steps per bar (got " .. #steps .. ")")

kick:reset()
kick.div = 3 -- 1/8 = 12 ticks
local n8 = 0
for t = 0, BAR - 1 do
  if kick:tick(t, 0) >= 0 and t % (STEP * 2) == 0 then n8 = n8 + 1 end
end
ok(n8 == 8, "a 1/8 lane takes 8 steps per bar (got " .. n8 .. ")")

-- every division divides a bar evenly, so a step always lands on a boundary
for i, dt in ipairs(Lane.DIV_TICKS) do
  ok(BAR % dt == 0, Lane.DIV_NAMES[i] .. " divides a bar evenly")
end

---------------------------------------------------------------- start phase
section("start phase")
-- a lane takes its opening playhead position from the tick it first fires
-- on, not from step 1. that is what lets a late join to a shared clock land
-- in the right part of the phrase instead of restarting the phrase.
local a0 = build_lane(1)
a0.follow_on = false
a0:reset()
a0:tick(0, 0)
ok(a0.pos == 1, "starting at tick 0 begins at step 1 (got " .. a0.pos .. ")")

local amid = build_lane(1)
amid.follow_on = false
amid:reset()
local adt = amid:div_ticks()
local alen = amid:pattern().length
amid:tick(10 * adt, 0)   -- step index 10 on the shared grid
ok(amid.pos == (10 % alen) + 1,
   "starting at step index 10 begins at step " .. ((10 % alen) + 1) ..
   " (got " .. amid.pos .. ")")

-- and it wraps by the pattern's own length, so a long run of ticks still
-- lands somewhere inside the pattern
local afar = build_lane(1)
afar.follow_on = false
afar:reset()
afar:tick(1000 * adt, 0)
ok(afar.pos >= 1 and afar.pos <= alen,
   "a far-future start still lands inside the pattern (got " ..
   afar.pos .. "/" .. alen .. ")")
ok(afar.pos == (1000 % alen) + 1, "...at the phase-correct step")

-- two lanes started at the same tick agree with each other
local s1, s2 = build_lane(1), build_lane(1)
s1.follow_on = false
s2.follow_on = false
s1:reset() s2:reset()
s1:tick(7 * adt, 0)
s2:tick(7 * adt, 0)
ok(s1.pos == s2.pos, "two lanes started at the same tick agree")

---------------------------------------------------------------- legato / cut
section("legato vs cut")
local l = build_lane(1)
l.follow_on = false
l:reset()
-- advance to step 5 (ticks 0,6,12,18,24 -> pos 1..5)
for t = 0, STEP * 4 do l:tick(t, 0) end
ok(l.pos == 5, "playhead reached step 5 (got " .. l.pos .. ")")

local legato = build_lane(1)
legato.follow_on = false
legato:reset()
for t = 0, STEP * 4 do legato:tick(t, 0) end
legato:commit(4, Lane.TRANS_LEGATO)
ok(legato.active == 4, "legato commit changed pattern")
ok(legato.pos == 5, "legato kept the playhead at step 5 (got " ..
   legato.pos .. ")")

local cut = build_lane(1)
cut.follow_on = false
cut:reset()
for t = 0, STEP * 4 do cut:tick(t, 0) end
cut:commit(4, Lane.TRANS_CUT)
ok(cut.pos == 1, "cut snapped the playhead back to step 1 (got " ..
   cut.pos .. ")")

-- legato into a shorter pattern wraps rather than running off the end
local short = build_lane(1)
short.follow_on = false
short.bank[4].length = 4
short:reset()
for t = 0, STEP * 4 do short:tick(t, 0) end -- pos 5
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
-- run one full pattern, then the follow should move us to pattern 2. the
-- length is read from the pattern rather than assumed: kits are not all
-- 16 steps any more (amen and halftime are 32).
local fl_len = fl.bank[1].length
for t = 0, fl_len * STEP do fl:tick(t, 0) end
ok(fl.active == 2, "follow 'end' + 'next' moved to pattern 2 after its " ..
   fl_len .. " steps (got " .. fl.active .. ")")

-- an absolute follow time fires mid-pattern
local mid = build_lane(1)
mid.transition = Lane.TRANS_LEGATO
for i = 1, 8 do
  mid.bank[i].follow.time = 4 -- 1/4 note = 4 sixteenths
  mid.bank[i].follow.a = 2
end
mid:reset()
mid.active = 1
for t = 0, 4 * STEP do mid:tick(t, 0) end
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

-- skip_empty keeps follow off silent slots. with a kit library most lanes
-- sit out some kits, so the expected count comes from the library rather
-- than a hardcoded number.
for li = 1, 8 do
  local spec = Library.LANES[li]
  local want = 0
  for _, kit in ipairs(Library.KITS) do
    local rows = kit.parts[spec.name]
    if rows then
      for _, r in ipairs(rows) do
        if r:match("[Xxo]") then want = want + 1 break end
      end
    end
  end
  local se = build_lane(li)
  se.skip_empty = true
  local cands = {}
  local n = se:_candidates(cands)
  ok(n == want, spec.name .. " has " .. want ..
     " non-empty kits (candidates: " .. n .. ")")
  se.skip_empty = false
  ok(se:_candidates(cands) == 8,
     spec.name .. ": with skip_empty off all 8 slots are candidates")
end

-- a lane sitting on a kit it has no part in must STAY silent -- an empty
-- slot is "this voice sits this one out", and a relative follow action
-- from a pattern that is not in its own candidate list would otherwise
-- jump the lane straight back in after one bar
local silent = nil
for li = 1, 8 do
  local spec = Library.LANES[li]
  for k = 1, 8 do
    local rows = Library.KITS[k].parts[spec.name]
    local sounds = false
    if rows then
      for _, r in ipairs(rows) do if r:match("[Xxo]") then sounds = true end end
    end
    if not sounds and silent == nil then silent = {li, k} end
  end
end
ok(silent ~= nil, "the library has at least one deliberately silent slot")
if silent then
  local sl = build_lane(silent[1])
  sl.active = silent[2]
  sl:reset()
  local heard = 0
  for t = 0, BAR * 4 do heard = heard + sl:tick(t, BAR) end
  ok(sl.active == silent[2], Library.LANES[silent[1]].name ..
     " stayed on its silent kit for four bars (ended on " .. sl.active .. ")")
  ok(heard == 0, "...and made no sound (" .. heard .. " hits)")
end

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

---------------------------------------------------------------- countdowns
section("countdowns")
-- what the screen reads to answer "when does this change?"
local cd = build_lane(1)
cd.follow_on = false
cd:reset()
ok(cd:steps_to_launch(0, BAR) == nil, "nothing queued, no launch countdown")

cd:launch(3)
ok(cd:steps_to_launch(0, 0) == 0, "instant quantize commits on the next step")
-- at a 1/16 division a bar is 16 steps, so from tick 0 the bar line is 16
-- steps off; from a third of the way in, proportionally fewer
ok(cd:steps_to_launch(0, BAR) == 16,
   "one-bar quantize from the bar line is 16 steps (got " ..
   tostring(cd:steps_to_launch(0, BAR)) .. ")")
ok(cd:steps_to_launch(STEP * 4, BAR) == 12,
   "...and 12 steps once four are gone (got " ..
   tostring(cd:steps_to_launch(STEP * 4, BAR)) .. ")")
ok(cd:steps_to_launch(STEP * 15, BAR) == 1, "...and 1 just before the line")

-- a coarser lane than the quantize setting still lands on its own step
local coarse = build_lane(1)
coarse.div = 1 -- 1/4
coarse:launch(3)
local cn = coarse:steps_to_launch(0, Lane.QUANT_TICKS[3]) -- 1/16 quantize
ok(cn == 1, "a 1/4 lane under 1/16 quantize commits at its next step (got " ..
   tostring(cn) .. ")")

-- pattern quantize counts out the rest of the loop
local pq = build_lane(1)
pq:launch(3)
pq.pos = 5
ok(pq:steps_to_launch(0, Lane.QUANT_PATTERN) ==
   pq:pattern().length - 4,
   "pattern quantize counts to the end of the loop")

-- follow countdown
local fc = build_lane(1)
fc.follow_on = true
fc.bank[fc.active].follow.time = 4
fc:reset()
ok(fc:steps_to_follow() == 4, "a fresh pattern is 4 steps from its follow")
fc:tick(0, 0)
fc:tick(STEP, 0)
ok(fc:steps_to_follow() == 2, "two steps in, two to go (got " ..
   tostring(fc:steps_to_follow()) .. ")")
fc.follow_on = false
ok(fc:steps_to_follow() == nil, "follow off means no countdown")
fc.follow_on = true
fc.bank[fc.active].follow.time = 0 -- off
ok(fc:steps_to_follow() == nil, "follow time 'off' means no countdown")

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
  if mo:tick(s * STEP, 0) > 0 then early = early + 1 end
end
for s = 9, 16 do
  if mo:tick(s * STEP, 0) > 0 then late = late + 1 end
end
ok(early > late, "xfade thins out across the window (early " .. early ..
   " vs late " .. late .. ")")
ok(mo.morph_left == 0, "morph window closed after morph_steps steps")
local after = 0
for s = 17, 24 do if mo:tick(s * STEP, 0) > 0 then after = after + 1 end end
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
for s = 1, 8 do counts[s] = ho:tick(s * STEP, 0) end
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
for s = 1, 16 do h1 = h1 + ho1:tick(s * STEP, 0) end
ok(h1 > 0 and h1 < 16, "single-slot handover blends rather than cutting (" ..
   h1 .. " hits over 16 steps)")

---------------------------------------------------------------- quantize
section("launch quantize")
local q = build_lane(1)
q.follow_on = false
q:reset()
for t = 0, BAR - 2 do q:tick(t, BAR) end -- one bar quantize
q:launch(5, Lane.TRANS_CUT)
ok(q.active == 1, "a queued launch does not take effect immediately")
for t = BAR - 1, BAR - 1 do q:tick(t, BAR) end
ok(q.active == 1, "still queued part way through the bar")
for t = BAR, BAR + STEP do q:tick(t, BAR) end
ok(q.active == 5, "queued launch committed on the bar line (got " ..
   q.active .. ")")

local qi = build_lane(1)
qi.follow_on = false
qi:reset()
for t = 0, STEP + 1 do qi:tick(t, 0) end
qi:launch(5, Lane.TRANS_LEGATO)
for t = STEP + 2, STEP * 3 do qi:tick(t, 0) end
ok(qi.active == 5, "instant quantize commits at the next step")

local qc = build_lane(1)
qc:launch(5)
qc:launch(5)
ok(qc.queued == nil, "pressing a queued pattern again cancels it")

---------------------------------------------------------------- swing
section("swing")
-- swing is a percentage of the lane's own step. collect the ticks a lane
-- actually fires on over two beats.
local function fire_ticks(pct, div)
  local sw = build_lane(1)
  sw.follow_on = false
  sw.swing = pct
  if div then sw.div = div end
  sw:reset()
  local out = {}
  for t = 0, BAR - 1 do
    local before = sw.pos
    sw:tick(t, 0)
    if sw.pos ~= before or t == 0 then out[#out + 1] = t end
  end
  return out
end

local straight = fire_ticks(0)
ok(straight[2] == STEP, "straight: second step one whole step later (got " ..
   tostring(straight[2]) .. ")")
ok(straight[3] == STEP * 2, "straight: third step on the grid")

local half = fire_ticks(50)
ok(half[1] == 0, "50%: first step on the beat")
ok(half[2] == STEP + STEP / 2,
   "50%: second step delayed half a step (want " .. (STEP + STEP / 2) ..
   ", got " .. tostring(half[2]) .. ")")
ok(half[3] == STEP * 2, "50%: third step back on the grid (got " ..
   tostring(half[3]) .. ")")

-- the point of moving to 96 PPQN: amounts between the old 0/17/33/50 are
-- now reachable. at a 1/16 division a step is 24 ticks, so ~4% resolution.
local seen = {}
local distinct = 0
for pct = 0, Lane.SWING_MAX do
  local l = build_lane(1)
  l.swing = pct
  local t = l:swing_ticks()
  if not seen[t] then seen[t] = true distinct = distinct + 1 end
end
ok(distinct >= 16, "at least 16 distinct swing amounts are reachable (got " ..
   distinct .. "; the 24 PPQN grid managed 4)")

local q = build_lane(1)
q.swing = 25
ok(q:swing_ticks() == STEP / 4,
   "25% is a quarter of a step (want " .. (STEP / 4) .. ", got " ..
   q:swing_ticks() .. ")")

-- the same percentage means the same feel at any division
for div = 1, #Lane.DIV_TICKS do
  local l = build_lane(1)
  l.swing = 50
  l.div = div
  local dt = Lane.DIV_TICKS[div]
  ok(l:swing_ticks() == math.floor(dt / 2),
     "50% is half a step at " .. Lane.DIV_NAMES[div] .. " (want " ..
     math.floor(dt / 2) .. ", got " .. l:swing_ticks() .. ")")
end

-- swing can never push a step onto or past the next one
for div = 1, #Lane.DIV_TICKS do
  local l = build_lane(1)
  l.div = div
  l.swing = Lane.SWING_MAX
  ok(l:swing_ticks() < Lane.DIV_TICKS[div],
     "max swing stays inside the step at " .. Lane.DIV_NAMES[div])
end

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

-- by default the settings are deliberately NOT restored: segue keeps them
-- in norns params, and a blob that also carried them gave every value two
-- homes -- which is why every lane setting used to survive a power cycle
-- with no way back to a known state.
local s2 = build_lane(3)
s2:deserialize(blob)
ok(s2.active == 4, "active pattern survived the round trip")
ok(Pattern.get(s2.bank[1], 2, 7) == Pattern.GHOST, "an edited trig survived")
ok(Pattern.get(s2.bank[2], 1, 5) == Pattern.get(s1.bank[2], 1, 5),
   "an untouched library pattern survived")
ok(s2.bank[1].follow.time == s1.bank[1].follow.time, "follow time survived")

ok(s2.div == Lane.DIV_16TH, "division did NOT come back (got " ..
   s2.div .. ", want the default " .. Lane.DIV_16TH .. ")")
ok(s2.swing == 0, "swing did NOT come back")
ok(s2.prob == 1.0, "probability did NOT come back")
ok(s2.transition == Lane.TRANS_LEGATO, "transition did NOT come back")

-- the blob still carries them, and the mechanism still works, for a caller
-- that wants it (and so this stays tested rather than rotting)
local s3 = build_lane(3)
s3:deserialize(blob, {settings = true})
ok(s3.div == 3, "with settings=true, division is restored")
ok(s3.swing == 2, "with settings=true, swing is restored")
ok(math.abs(s3.prob - 0.6) < 1e-9, "with settings=true, probability is restored")
ok(s3.transition == Lane.TRANS_XFADE, "with settings=true, transition is restored")

---------------------------------------------------------------- integration
section("8 lanes together")
local lanes = {}
for i = 1, 8 do lanes[i] = build_lane(i) end
local hit_total = 0
local by_voice = {}
for t = 0, BAR * 8 - 1 do          -- eight bars
  for i = 1, 8 do
    local n = lanes[i]:tick(t, BAR)
    for h = 1, n do
      local v = lanes[i].hits[h].voice
      by_voice[v] = (by_voice[v] or 0) + 1
      hit_total = hit_total + 1
      ok(lanes[i].hits[h].vel >= 1 and lanes[i].hits[h].vel <= 127,
         "velocity in range")
    end
  end
end
print("  " .. hit_total .. " hits over 8 bars of kit 1 (amen)")
ok(hit_total > 100, "eight bars produced a decent number of hits")

---------------------------------------------------------------- kits
section("kits as scenes")
-- launching a whole row is the headline gesture: every lane goes to kit k,
-- and what comes out should be exactly the voices that kit writes parts
-- for -- no more (a lane bleeding through from the last kit) and no fewer
-- (a part that never sounds).
local total_voices_used = {}
for k = 1, 8 do
  local kit = Library.KITS[k]
  local kl = {}
  for i = 1, 8 do
    kl[i] = build_lane(i)
    kl[i].follow_on = false     -- test the kit itself, not the drift
    kl[i]:commit(k, Lane.TRANS_CUT)
    kl[i]:reset()
    kl[i].active = k
  end

  local want = {}
  for li, spec in ipairs(Library.LANES) do
    local rows = kit.parts[spec.name]
    if rows then
      for s, r in ipairs(rows) do
        if r:match("[Xxo]") then want[spec.voices[s]] = true end
      end
    end
  end

  local got = {}
  local hits = 0
  for t = 0, BAR * 2 - 1 do        -- two bars, enough for a 32-step kit
    for i = 1, 8 do
      local n = kl[i]:tick(t, BAR)
      for h = 1, n do
        got[kl[i].hits[h].voice] = true
        total_voices_used[kl[i].hits[h].voice] = true
        hits = hits + 1
      end
    end
  end

  for v = 1, 12 do
    ok((want[v] or false) == (got[v] or false),
       kit.name .. ": voice " .. Voices.NAMES[v] .. " " ..
       (want[v] and "should sound" or "should stay silent") ..
       " (" .. (got[v] and "sounded" or "silent") .. ")")
  end
  ok(hits > 8, kit.name .. " is not nearly empty (" .. hits ..
     " hits over two bars)")
end

local covered = 0
for v = 1, 12 do if total_voices_used[v] then covered = covered + 1 end end
ok(covered == 12, "across the eight kits every Rytm voice gets used (" ..
   covered .. "/12)")

-- drift: with follow on, the hat lanes should move off kit 1 within a
-- reasonable stretch, and only ever onto a kit they have a part in
local dl = {}
for i = 1, 8 do dl[i] = build_lane(i) end
for t = 0, BAR * 16 - 1 do
  for i = 1, 8 do dl[i]:tick(t, BAR) end
end
ok(dl[5].active ~= 1 or dl[6].active ~= 1,
   "a hat lane drifted off kit 1 over sixteen bars (CHH " .. dl[5].active ..
   ", OHH " .. dl[6].active .. ")")
for i = 1, 8 do
  ok(not Pattern.is_empty(dl[i].bank[dl[i].active]) or
     Pattern.is_empty(dl[i].bank[1]),
     Library.LANES[i].name .. " did not drift into a silent kit")
end

---------------------------------------------------------------- results
print("")
print(string.rep("-", 46))
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
