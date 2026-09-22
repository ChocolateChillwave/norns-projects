-- off-device smoke test for segue's pure-Lua core: the pattern structure,
-- the lane/follow-action engine with its setting inheritance, the bank
-- library and the MIDI voice layer. none of these touch a norns API, so
-- plain desktop Lua runs them.
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

-- banks by name, so a test says which it means
local BANK = {}
for i, b in ipairs(Library.BANKS) do BANK[b.name] = i end

-- follow-time indices, named, so a test reads as music rather than numbers
local FT_OFF, FT_QUARTER, FT_BAR, FT_END = 1, 5, 9, Pattern.FOLLOW_IDX_END
local Q_INSTANT, Q_16TH, Q_QUARTER, Q_BAR, Q_PATTERN = 1, 3, 5, 7, 9

---------------------------------------------------------------- library
section("library")
local lane_by_name = {}
for _, spec in ipairs(Library.LANES) do
  ok(#spec.voices >= 1, spec.name .. " has voices")
  lane_by_name[spec.name] = spec
end

local voice_seen = {}
for _, spec in ipairs(Library.LANES) do
  for _, v in ipairs(spec.voices) do
    ok(voice_seen[v] == nil, "voice " .. v .. " assigned only once")
    voice_seen[v] = true
  end
end
for v = 1, 12 do ok(voice_seen[v], "Rytm voice " .. v .. " is covered") end

ok(#Library.BANKS == 8, "there are 8 banks (got " .. #Library.BANKS .. ")")
ok(Library.BANKS[Library.USER].user, "the last bank is the user bank")
ok(Library.kits(Library.USER) == nil, "the user bank has no factory kits")

local factory_kits = 0
for b, bank in ipairs(Library.BANKS) do
  ok(type(bank.short) == "string" and #bank.short <= 3,
     bank.name .. " has a short name for the header")
  if not bank.user then
    local kits = Library.kits(b)
    ok(kits and #kits == 8, bank.name .. " has 8 kits")
    for k = 1, 8 do
      local kit = kits and kits[k]
      ok(kit ~= nil, bank.name .. " kit " .. k .. " resolves")
      if kit then
        factory_kits = factory_kits + 1
        ok(kit.length >= 1 and kit.length <= 64,
           kit.name .. " has a legal length")
        local voices_in_kit = 0
        for lname, rows in pairs(kit.parts) do
          local spec = lane_by_name[lname]
          ok(spec ~= nil, kit.name .. " names a real lane ('" .. lname .. "')")
          if spec then
            ok(#rows <= #spec.voices, kit.name .. "/" .. lname ..
               " has at most one row per voice")
            for ri, row in ipairs(rows) do
              ok(#row == kit.length, bank.name .. "/" .. kit.name .. "/" ..
                 lname .. " row " .. ri .. " is " .. kit.length ..
                 " chars (got " .. #row .. ")")
              ok(row:match("^[Xxo%-]*$") ~= nil,
                 kit.name .. "/" .. lname .. " uses only Xxo-")
              if row:match("[Xxo]") then voices_in_kit = voices_in_kit + 1 end
            end
          end
        end
        ok(voices_in_kit >= 3, bank.name .. "/" .. kit.name ..
           " sounds at least 3 voices (got " .. voices_in_kit .. ")")
      end
    end
  end
end
print("  " .. factory_kits .. " factory kits across " ..
      (#Library.BANKS - 1) .. " factory banks")

-- the first version of the library was all divisions of the bar; a bank
-- is only worth having if some of its kicks are off the beat
local function has_syncopated_kick(b)
  for _, kit in ipairs(Library.kits(b)) do
    local k = kit.parts.KICK and kit.parts.KICK[1]
    if k then
      for step = 1, #k do
        if k:sub(step, step):match("[Xxo]") and ((step - 1) % 4) ~= 0 then
          return true
        end
      end
    end
  end
  return false
end
for _, name in ipairs({"generic", "electro", "breakbeats", "variety 2"}) do
  ok(has_syncopated_kick(BANK[name]), name .. " has an off-beat kick somewhere")
end

-- house is four-to-the-floor: that is what makes its kits interplay
local four_floor = 0
for _, kit in ipairs(Library.kits(BANK.house)) do
  if kit.parts.KICK and kit.parts.KICK[1]:sub(1, 16) == "X---X---X---X---" then
    four_floor = four_floor + 1
  end
end
ok(four_floor >= 6, "most house kits are four-to-the-floor (" ..
   four_floor .. "/8) -- the bank's interplay depends on it")

-- the variety banks are picks, resolved by bank name and kit number
local v1 = Library.kits(BANK.variety)
ok(v1[1] == Library.kits(BANK.house)[1],
   "variety slot 1 is literally house kit 1, not a copy that can drift")
local v2 = Library.kits(BANK["variety 2"])
ok(v2[1] == Library.kits(BANK.breakbeats)[1], "variety 2 slot 1 is the amen")

---------------------------------------------------------------- pattern
section("pattern")
local p = Pattern.from_rows({"X---x---X---x---"}, "four", 16)
ok(Pattern.get(p, 1, 1) == Pattern.ACCENT, "step 1 is an accent")
ok(Pattern.get(p, 1, 5) == Pattern.NORMAL, "step 5 is normal")
ok(Pattern.get(p, 1, 2) == nil, "step 2 is a rest")
ok(Pattern.get(p, 1, 17) == Pattern.ACCENT, "get wraps past the length")
ok(not Pattern.is_empty(p), "a written pattern is not empty")
ok(Pattern.is_empty(Pattern.new(1, 16)), "a fresh pattern is empty")
ok(next(Pattern.new(1, 16).ov) == nil, "a fresh pattern overrides nothing")

local c = Pattern.new(1, 16)
ok(Pattern.cycle(c, 1, 3) == Pattern.NORMAL, "cycle: rest -> normal")
ok(Pattern.cycle(c, 1, 3) == Pattern.ACCENT, "cycle: normal -> accent")
ok(Pattern.cycle(c, 1, 3) == Pattern.GHOST, "cycle: accent -> ghost")
ok(Pattern.cycle(c, 1, 3) == nil, "cycle: ghost -> rest")

local cp = Pattern.copy(p)
Pattern.set(cp, 1, 1, nil)
ok(Pattern.get(p, 1, 1) == Pattern.ACCENT, "copy is independent of original")
p.ov.trans = Lane.TRANS_CUT
local cp2 = Pattern.copy(p)
ok(cp2.ov.trans == Lane.TRANS_CUT, "copy carries the overrides")
cp2.ov.trans = nil
ok(p.ov.trans == Lane.TRANS_CUT, "...as its own table, not a shared one")

---------------------------------------------------------------- helpers

-- the shipped lane-level follow overrides, applied over the global
-- defaults: in the script these are params; here they are this function.
local function lane_parent(spec)
  local fo = spec.follow or {}
  return function(key)
    if fo[key] ~= nil then return fo[key] end
    return Lane.DEFAULTS[key]
  end
end

local function build_lane(spec_index, bank, parent)
  local spec = Library.LANES[spec_index]
  local l = Lane:new{pattern_lib = Pattern, id = spec_index,
                     name = spec.name, voices = spec.voices,
                     parent = parent or lane_parent(spec)}
  l.bank = Library.column(bank or BANK.generic, spec, #spec.voices, Pattern)
  return l
end

---------------------------------------------------------------- timing
section("timing")
local kick = build_lane(1)
kick.follow_on = false
kick:reset()
local steps = {}
for t = 0, BAR - 1 do
  kick:tick(t, 0)
  if t % STEP == 0 then steps[#steps + 1] = t end
end
ok(#steps == 16, "a 1/16 lane takes 16 steps per bar (got " .. #steps .. ")")

kick:reset()
kick.div = 3 -- 1/8
local n8 = 0
for t = 0, BAR - 1 do
  if kick:tick(t, 0) >= 0 and t % (STEP * 2) == 0 then n8 = n8 + 1 end
end
ok(n8 == 8, "a 1/8 lane takes 8 steps per bar (got " .. n8 .. ")")

for i, dt in ipairs(Lane.DIV_TICKS) do
  ok(BAR % dt == 0, Lane.DIV_NAMES[i] .. " divides a bar evenly")
end

---------------------------------------------------------------- start phase
section("start phase")
-- a lane takes its opening playhead from the tick it first fires on, which
-- is what lets a late join to a shared clock land in the right place
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
amid:tick(10 * adt, 0)
ok(amid.pos == (10 % alen) + 1, "starting at step index 10 begins at step " ..
   ((10 % alen) + 1) .. " (got " .. amid.pos .. ")")

local afar = build_lane(1)
afar.follow_on = false
afar:reset()
afar:tick(1000 * adt, 0)
ok(afar.pos == (1000 % alen) + 1, "a far-future start lands phase-correct")

local s1, s2 = build_lane(1), build_lane(1)
s1.follow_on, s2.follow_on = false, false
s1:reset() s2:reset()
s1:tick(7 * adt, 0)
s2:tick(7 * adt, 0)
ok(s1.pos == s2.pos, "two lanes started at the same tick agree")

---------------------------------------------------------------- legato / cut
section("legato vs cut")
local l = build_lane(1)
l.follow_on = false
l:reset()
for t = 0, STEP * 4 do l:tick(t, 0) end
ok(l.pos == 5, "playhead reached step 5 (got " .. l.pos .. ")")

local legato = build_lane(1)
legato.follow_on = false
legato:reset()
for t = 0, STEP * 4 do legato:tick(t, 0) end
legato:commit(4, Lane.TRANS_LEGATO)
ok(legato.active == 4, "legato commit changed pattern")
ok(legato.pos == 5, "legato kept the playhead at step 5 (got " .. legato.pos .. ")")

local cut = build_lane(1)
cut.follow_on = false
cut:reset()
for t = 0, STEP * 4 do cut:tick(t, 0) end
cut:commit(4, Lane.TRANS_CUT)
ok(cut.pos == 1, "cut snapped the playhead back to step 1 (got " .. cut.pos .. ")")

local short = build_lane(1)
short.follow_on = false
short.bank[4].length = 4
short:reset()
for t = 0, STEP * 4 do short:tick(t, 0) end
short:commit(4, Lane.TRANS_LEGATO)
ok(short.pos == 1, "legato into a 4-step pattern wrapped 5 -> 1 (got " ..
   short.pos .. ")")

---------------------------------------------------------------- follow
section("follow actions")
local fl = build_lane(1)
fl.follow_on = true
for i = 1, 8 do fl.bank[i].ov.follow_time = FT_END end
fl.bank[1].ov.follow_a = Pattern.ACTION_NEXT
fl:reset()
fl.active = 1
local fl_len = fl.bank[1].length
for t = 0, fl_len * STEP do fl:tick(t, 0) end
ok(fl.active == 2, "follow 'end' + 'next' moved to pattern 2 after its " ..
   fl_len .. " steps (got " .. fl.active .. ")")

local mid = build_lane(1)
for i = 1, 8 do
  mid.bank[i].ov.follow_time = FT_QUARTER
  mid.bank[i].ov.follow_a = Pattern.ACTION_NEXT
end
mid:reset()
mid.active = 1
for t = 0, 4 * STEP do mid:tick(t, 0) end
ok(mid.active == 2, "follow at 1/4 fired after 4 steps (got pattern " ..
   mid.active .. ")")
ok(mid.pos == 5, "...and legato carried the playhead into step 5 (got " ..
   mid.pos .. ")")

local dv = build_lane(1)
dv.div = 3 -- 1/8
dv.bank[1].ov.follow_time = FT_BAR
ok(dv:follow_steps() == 8, "one bar is 8 steps on a 1/8 lane (got " ..
   tostring(dv:follow_steps()) .. ")")
dv.div = Lane.DIV_16TH
ok(dv:follow_steps() == 16, "one bar is 16 steps on a 1/16 lane")

-- skip_empty keeps follow off silent slots; the count comes from the data
for li = 1, 8 do
  local spec = Library.LANES[li]
  local want = 0
  for _, kit in ipairs(Library.kits(BANK.breakbeats)) do
    local rows = kit.parts[spec.name]
    if rows then
      for _, r in ipairs(rows) do
        if r:match("[Xxo]") then want = want + 1 break end
      end
    end
  end
  local se = build_lane(li, BANK.breakbeats)
  local cands = {}
  ok(se:_candidates(cands) == want, spec.name .. " has " .. want ..
     " non-empty breakbeat kits")
  se.skip_empty = false
  ok(se:_candidates(cands) == 8, spec.name .. ": skip_empty off -> 8")
end

-- a lane sitting on a kit it has no part in must STAY silent. COW sits out
-- every breakbeat kit, so it is the clean case.
local cow = build_lane(8, BANK.breakbeats)
ok(Pattern.is_empty(cow.bank[1]), "COW has no part in the amen")
ok(cow.bank[1].ov.follow_a == Pattern.ACTION_NONE,
   "an empty slot carries its own 'none', so it holds")
cow:reset()
local heard = 0
for t = 0, BAR * 4 do heard = heard + cow:tick(t, BAR) end
ok(cow.active == 1, "COW stayed on its silent kit for four bars")
ok(heard == 0, "...and made no sound (" .. heard .. " hits)")

local oth = build_lane(1)
local self_hits = 0
for i = 1, 300 do
  oth.active = math.random(8)
  if oth:_resolve(Pattern.ACTION_OTHER) == oth.active then self_hits = self_hits + 1 end
end
ok(self_hits == 0, "'other' never picks the active pattern")

local nx = build_lane(1)
nx.active = 8
ok(nx:_resolve(Pattern.ACTION_NEXT) == 1, "'next' wraps 8 -> 1")
nx.active = 1
ok(nx:_resolve(3) == 8, "'prev' wraps 1 -> 8")

---------------------------------------------------------------- inheritance
section("inheritance")
-- a pattern's own value beats the lane/global chain; nothing set means the
-- chain decides. the parent here stands in for the script's params.
local chain = {follow_time = FT_END, follow_a = 1, follow_b = 1,
               follow_chance = 100, trans = Lane.TRANS_CUT, quant = Q_BAR}
local ih = build_lane(1, BANK.generic, function(key) return chain[key] end)
ok(ih:setting("trans") == Lane.TRANS_CUT,
   "no override: the pattern inherits the parent's transition")
ok(ih:setting_source("trans") == "parent", "...and says so")
ih:pattern().ov.trans = Lane.TRANS_XFADE
ok(ih:setting("trans") == Lane.TRANS_XFADE, "a pattern override beats the parent")
ok(ih:setting_source("trans") == "pattern", "...and says so")
ih:pattern().ov.trans = nil
ok(ih:setting("trans") == Lane.TRANS_CUT, "clearing it falls back to the parent")

-- changing the PARENT moves every pattern that inherits, and leaves an
-- override alone -- the whole point of the model
ih.bank[2].ov.trans = Lane.TRANS_HANDOVER
chain.trans = Lane.TRANS_LEGATO
ok(ih:setting("trans", ih.bank[1]) == Lane.TRANS_LEGATO,
   "an inheriting pattern follows a parent change")
ok(ih:setting("trans", ih.bank[2]) == Lane.TRANS_HANDOVER,
   "an overriding pattern ignores it")

-- behaviour, not just lookup: the ARRIVING pattern's own transition is the
-- one used, so a fill with "cut" always cuts in while the lane is legato
local arrive = build_lane(1)
for i = 1, 8 do
  arrive.bank[i].ov.follow_time = FT_QUARTER
  arrive.bank[i].ov.follow_a = Pattern.ACTION_NEXT
end
arrive.bank[2].ov.trans = Lane.TRANS_CUT
arrive:reset()
arrive.active = 1
for t = 0, 4 * STEP do arrive:tick(t, 0) end
ok(arrive.active == 2, "the follow moved to pattern 2")
ok(arrive.pos == 1, "pattern 2's own 'cut' cut the playhead to step 1, " ..
   "though the lane inherits legato (got pos " .. arrive.pos .. ")")

-- follow settings resolve through the chain too
local fr = build_lane(5) -- CHH, whose lane level overrides follow
ok(fr:setting("follow_a") == Pattern.ACTION_OTHER,
   "CHH inherits 'other' from its lane level")
ok(fr:setting("follow_time") == FT_BAR, "...and a one-bar follow time")
ok(build_lane(1):setting("follow_a") == Pattern.ACTION_NONE,
   "KICK has no lane override and inherits the global 'none'")

-- and a pattern's quantize override times its own launch
local qo = build_lane(1)
qo.follow_on = false
qo:reset()
qo.bank[5].ov.quant = Q_INSTANT
for t = 0, STEP + 1 do qo:tick(t, 0) end
qo:launch(5)
for t = STEP + 2, STEP * 3 do qo:tick(t, 0) end
ok(qo.active == 5, "a pattern's own 'instant' lands at the next step " ..
   "despite the one-bar global")

---------------------------------------------------------------- banks
section("banks")
-- a factory column is a fresh copy each time, so editing what a lane holds
-- can never reach back into the library: the factory banks are read-only
local c1 = Library.column(BANK.house, Library.LANES[1], 1, Pattern)
ok(Pattern.get(c1[1], 1, 2) == nil, "house kit 1 kick step 2 starts as a rest")
Pattern.set(c1[1], 1, 2, Pattern.ACCENT)
local c2 = Library.column(BANK.house, Library.LANES[1], 1, Pattern)
ok(Pattern.get(c2[1], 1, 2) == nil,
   "editing one column did not touch the next one built from the bank")
ok(c1[1] ~= c2[1], "two columns never share a pattern table")

-- every empty slot in every bank carries the sit-out guard
local guarded, empties = 0, 0
for b = 1, Library.USER - 1 do
  for _, spec in ipairs(Library.LANES) do
    for _, pat in ipairs(Library.column(b, spec, #spec.voices, Pattern)) do
      if Pattern.is_empty(pat) then
        empties = empties + 1
        if pat.ov.follow_a == Pattern.ACTION_NONE then guarded = guarded + 1 end
      end
    end
  end
end
ok(empties > 0 and guarded == empties,
   "every empty factory slot holds (" .. guarded .. "/" .. empties .. ")")

-- the hand-off: a queued bank waits for its boundary, then swaps with the
-- lane's transition. legato carries the playhead across.
local bs = build_lane(1, BANK.house)
bs.follow_on = false
bs:reset()
local techno = Library.column(BANK.techno, Library.LANES[1], 1, Pattern)
for t = 0, STEP * 2 do bs:tick(t, 0) end -- pos 3
bs:queue_bank(techno, Q_QUARTER)
ok(bs.bank ~= techno, "a queued bank waits for its boundary")
for t = STEP * 2 + 1, STEP * 4 - 1 do bs:tick(t, 0) end
ok(bs.bank ~= techno, "...still waiting just before the beat")
bs:tick(STEP * 4, 0)
ok(bs.bank == techno, "...and swaps on the beat")
ok(bs.pos == 5, "legato carried the playhead into the new bank at step 5 " ..
   "(got " .. bs.pos .. ")")
ok(bs.active == 1, "the lane stayed on the same kit slot")
ok(bs.pending_bank == nil, "the pending bank is cleared once it lands")

-- under xfade the blend has to start from the pattern that was PLAYING.
-- the swap replaces the bank before committing, so commit() has to be told
-- the old pattern; without that it blended the new pattern with itself and
-- the window was silent.
local bx = build_lane(1, BANK.house)
bx.follow_on = false
bx.bank[1] = Pattern.from_rows({"xxxxxxxxxxxxxxxx"}, "all", 16)
local silentcol = {}
for k = 1, 8 do silentcol[k] = Pattern.from_rows({"----------------"}, "none", 16) end
silentcol[1].ov.trans = Lane.TRANS_XFADE
bx.morph_steps = 16
bx:reset()
bx:tick(0, 0)
bx:queue_bank(silentcol, Q_INSTANT)
local bh = 0
for s = 1, 16 do bh = bh + bx:tick(s * STEP, 0) end
ok(bh > 0 and bh < 16, "a bank change under xfade blends out of the old " ..
   "pattern (" .. bh .. " hits over the window)")

-- a launch queued alongside a bank change lands in the NEW bank
local bl = build_lane(1, BANK.house)
bl.follow_on = false
bl:reset()
bl.bank[3].ov.quant = Q_INSTANT
bl:tick(0, 0)
local tc = Library.column(BANK.techno, Library.LANES[1], 1, Pattern)
bl:queue_bank(tc, Q_INSTANT)
bl:launch(3)
bl:tick(STEP, 0)
ok(bl.bank == tc and bl.active == 3, "bank swap then launch: kit 3 of the new bank")

---------------------------------------------------------------- countdowns
section("countdowns")
-- what the screen reads to answer "when does this change?". a launch
-- carries the quantize it resolved to, so each case sets it on the pattern.
local function queued(quant_idx, div)
  local q = build_lane(1)
  q.follow_on = false
  if div then q.div = div end
  q:reset()
  q.bank[3].ov.quant = quant_idx
  q:launch(3)
  return q
end
ok(build_lane(1):steps_to_launch(0) == nil, "nothing queued, no countdown")
ok(queued(Q_INSTANT):steps_to_launch(0) == 0, "instant: the next step")
local qb = queued(Q_BAR)
ok(qb:steps_to_launch(0) == 16, "one bar from the bar line is 16 steps (got " ..
   tostring(qb:steps_to_launch(0)) .. ")")
ok(qb:steps_to_launch(STEP * 4) == 12, "...12 once four are gone")
ok(qb:steps_to_launch(STEP * 15) == 1, "...1 just before the line")
ok(queued(Q_16TH, 1):steps_to_launch(0) == 1,
   "a 1/4 lane under 1/16 quantize commits at its own next step")
local qp = queued(Q_PATTERN)
qp.pos = 5
ok(qp:steps_to_launch(0) == qp:pattern().length - 4,
   "pattern quantize counts out the loop")

local bq = build_lane(1, BANK.house)
bq:queue_bank(Library.column(BANK.techno, Library.LANES[1], 1, Pattern), Q_BAR)
ok(bq:steps_to_launch(0) == 16, "a pending bank change counts down too")

local fc = build_lane(1)
fc.follow_on = true
fc.bank[fc.active].ov.follow_time = FT_QUARTER
fc:reset()
ok(fc:steps_to_follow() == 4, "a fresh pattern is 4 steps from its follow")
fc:tick(0, 0)
fc:tick(STEP, 0)
ok(fc:steps_to_follow() == 2, "two steps in, two to go")
fc.follow_on = false
ok(fc:steps_to_follow() == nil, "follow off means no countdown")
fc.follow_on = true
fc.bank[fc.active].ov.follow_time = FT_OFF
ok(fc:steps_to_follow() == nil, "follow time 'off' means no countdown")

---------------------------------------------------------------- morph
section("morph")
local mo = build_lane(1)
mo.follow_on = false
mo.bank[1] = Pattern.from_rows({"xxxxxxxxxxxxxxxx"}, "all", 16)
mo.bank[2] = Pattern.from_rows({"----------------"}, "none", 16)
mo.morph_steps = 16
mo:reset()
mo:tick(0, 0)
mo:commit(2, Lane.TRANS_XFADE)
local early, late = 0, 0
for s = 1, 8 do if mo:tick(s * STEP, 0) > 0 then early = early + 1 end end
for s = 9, 16 do if mo:tick(s * STEP, 0) > 0 then late = late + 1 end end
ok(early > late, "xfade thins out across the window (" .. early .. " vs " .. late .. ")")
ok(mo.morph_left == 0, "morph window closed after morph_steps steps")
local after = 0
for s = 17, 24 do if mo:tick(s * STEP, 0) > 0 then after = after + 1 end end
ok(after == 0, "after the morph, only the new pattern plays")

local ho = build_lane(4) -- TOMS, 4 slots
ho.follow_on = false
ho.bank[1] = Pattern.from_rows({"xxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxx",
                                "xxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxx"}, "all", 16)
ho.bank[2] = Pattern.from_rows({"----------------", "----------------",
                                "----------------", "----------------"}, "none", 16)
ho.morph_steps = 8
ho:reset()
ho:tick(0, 0)
ho:commit(2, Lane.TRANS_HANDOVER)
local counts = {}
for s = 1, 8 do counts[s] = ho:tick(s * STEP, 0) end
local monotonic = true
for s = 2, 8 do if counts[s] > counts[s - 1] then monotonic = false end end
ok(monotonic, "handover drops voices monotonically (" .. table.concat(counts, ",") .. ")")
ok(counts[8] == 0, "handover has fully changed over by the end")

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
ok(h1 > 0 and h1 < 16, "single-slot handover blends rather than cutting")

---------------------------------------------------------------- quantize
section("launch quantize")
local q = build_lane(1)
q.follow_on = false
q:reset()
for t = 0, BAR - 2 do q:tick(t, BAR) end
q:launch(5, Lane.TRANS_CUT) -- inherits the one-bar global
ok(q.active == 1, "a queued launch does not take effect immediately")
q:tick(BAR - 1, BAR)
ok(q.active == 1, "still queued just before the bar")
for t = BAR, BAR + STEP do q:tick(t, BAR) end
ok(q.active == 5, "queued launch committed on the bar line")

local qc = build_lane(1)
qc:launch(5)
qc:launch(5)
ok(qc.queued == nil, "pressing a queued pattern again cancels it")

---------------------------------------------------------------- swing
section("swing")
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
ok(straight[2] == STEP, "straight: second step one whole step later")
ok(straight[3] == STEP * 2, "straight: third step on the grid")
local half = fire_ticks(50)
ok(half[1] == 0, "50%: first step on the beat")
ok(half[2] == STEP + STEP / 2, "50%: second step delayed half a step")
ok(half[3] == STEP * 2, "50%: third step back on the grid")

local seen, distinct = {}, 0
for pct = 0, Lane.SWING_MAX do
  local sl = build_lane(1)
  sl.swing = pct
  local t = sl:swing_ticks()
  if not seen[t] then seen[t] = true distinct = distinct + 1 end
end
ok(distinct >= 16, "at least 16 distinct swing amounts (got " .. distinct .. ")")

local sq = build_lane(1)
sq.swing = 25
ok(sq:swing_ticks() == STEP / 4, "25% is a quarter of a step")

for div = 1, #Lane.DIV_TICKS do
  local sl = build_lane(1)
  sl.swing = 50
  sl.div = div
  ok(sl:swing_ticks() == math.floor(Lane.DIV_TICKS[div] / 2),
     "50% is half a step at " .. Lane.DIV_NAMES[div])
  sl.swing = Lane.SWING_MAX
  ok(sl:swing_ticks() < Lane.DIV_TICKS[div],
     "max swing stays inside the step at " .. Lane.DIV_NAMES[div])
end

---------------------------------------------------------------- voices
section("voices / midi")
local sent = {}
local stub = {
  note_on = function(_, n, v, ch) sent[#sent + 1] = {"on", n, v, ch} end,
  note_off = function(_, n, v, ch) sent[#sent + 1] = {"off", n, v, ch} end,
}
local V = Voices:new{dev = stub}
V:trig(1, 100)
ok(sent[1][1] == "on" and sent[1][2] == 0 and sent[1][4] == 1,
   "default layout: BD -> note 0 ch 1")
V:trig(2, 100)
ok(sent[2][2] == 1, "SD -> note 1")
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

sent = {}
local V0 = Voices:new{dev = stub}
V0:trig(1, 100)
V0:trig(1, 100)
ok(sent[2][1] == "off" and sent[2][2] == 0, "a note-0 retrig closes note 0 first")
V0:panic()
ok(next(V0.sounding) == nil, "panic clears everything sounding")

sent = {}
local Vf = Voices:new{dev = stub, layout = Voices.LAYOUT_FACTORY, base_channel = 10}
Vf:trig(1, 100)
ok(sent[1][2] == 36 and sent[1][4] == 10, "factory layout: BD -> note 36 ch 10")
Vf:trig(12, 100)
ok(sent[2][2] == 55, "factory layout: CB -> note 55")

sent = {}
local Vt = Voices:new{dev = stub, layout = Voices.LAYOUT_TRACK}
Vt:trig(1, 100)
ok(sent[1][2] == 60 and sent[1][4] == 1, "track layout: BD -> note 60 ch 1")
Vt:trig(9, 100)
ok(sent[2][4] == 9 and sent[2][2] == 60, "track layout: CH -> note 60 ch 9")

for _, layout in ipairs({Voices.LAYOUT_SEQ, Voices.LAYOUT_FACTORY}) do
  ok(Voices.layout_address(layout, 1, 7) == 7,
     "layout " .. layout .. " honours the base channel")
end
ok(Voices.layout_address(Voices.LAYOUT_TRACK, 5, 7) == 5,
   "the track layout ignores the base channel")

sent = {}
local Vo = Voices:new{dev = stub}
Vo:set_address(1, 5, 42)
Vo:trig(1, 90)
ok(sent[1][2] == 42 and sent[1][4] == 5, "set_address wins for that voice")
Vo:trig(2, 90)
ok(sent[2][2] == 1 and sent[2][4] == 1, "...and leaves the others alone")

---------------------------------------------------------------- persistence
section("persistence")
-- a column packs and unpacks with its trigs and overrides intact
local col = Library.column(BANK.breakbeats, Library.LANES[3], 2, Pattern)
Pattern.set(col[1], 2, 7, Pattern.GHOST)
col[1].ov.follow_a = Pattern.ACTION_OTHER
col[1].ov.trans = Lane.TRANS_CUT
col[4].length = 12
local back = Lane.unpack_column(Lane.pack_column(col), Pattern, 2)
ok(Pattern.get(back[1], 2, 7) == Pattern.GHOST, "an edited trig survived")
ok(back[1].ov.follow_a == Pattern.ACTION_OTHER, "a follow override survived")
ok(back[1].ov.trans == Lane.TRANS_CUT, "a transition override survived")
ok(back[4].length == 12, "an edited length survived")
ok(back[2].ov.trans == nil, "an inheriting pattern still inherits after the trip")
ok(Pattern.get(back[2], 1, 5) == Pattern.get(col[2], 1, 5),
   "an untouched pattern survived")

-- the lane round trip deliberately leaves settings to the params
local ls = build_lane(3)
ls.active = 4
ls.div = 3
ls.swing = 2
ls.prob = 0.6
local blob = ls:serialize()
local lr = build_lane(3)
lr:deserialize(blob)
ok(lr.active == 4, "active pattern survived the round trip")
ok(lr.div == Lane.DIV_16TH, "division did NOT come back (params own it)")
ok(lr.swing == 0, "swing did NOT come back")
local lt = build_lane(3)
lt:deserialize(blob, {settings = true})
ok(lt.div == 3 and lt.swing == 2 and math.abs(lt.prob - 0.6) < 1e-9,
   "with settings=true the mechanism still restores them")

---------------------------------------------------------------- kits as rows
section("every kit, as a row")
-- launching a whole row is the headline gesture: every lane goes to kit k,
-- and what comes out must be exactly the voices that kit writes parts for
-- -- no bleed-through from the last kit, no part that never fires.
local total_voices = {}
local rows_checked = 0
for b = 1, Library.USER - 1 do
  local kits = Library.kits(b)
  for k = 1, 8 do
    local kit = kits[k]
    local kl = {}
    for i = 1, 8 do
      kl[i] = build_lane(i, b)
      kl[i].follow_on = false
      kl[i]:reset()
      kl[i].active = k
    end
    local want = {}
    for _, spec in ipairs(Library.LANES) do
      local rows = kit.parts[spec.name]
      if rows then
        for s, r in ipairs(rows) do
          if r:match("[Xxo]") then want[spec.voices[s]] = true end
        end
      end
    end
    local got = {}
    for t = 0, BAR * 2 - 1 do
      for i = 1, 8 do
        local n = kl[i]:tick(t, BAR)
        for h = 1, n do
          got[kl[i].hits[h].voice] = true
          total_voices[kl[i].hits[h].voice] = true
        end
      end
    end
    local match = true
    for v = 1, 12 do
      if (want[v] or false) ~= (got[v] or false) then
        match = false
        ok(false, Library.BANKS[b].name .. "/" .. kit.name .. ": " ..
           Voices.NAMES[v] .. (want[v] and " should sound" or " should be silent"))
      end
    end
    if match then pass = pass + 1 end
    rows_checked = rows_checked + 1
  end
end
print("  " .. rows_checked .. " kits launched as rows")
local covered = 0
for v = 1, 12 do if total_voices[v] then covered = covered + 1 end end
ok(covered == 12, "across the banks every Rytm voice gets used (" .. covered .. "/12)")

---------------------------------------------------------------- drift
section("drift")
-- with the shipped lane overrides, the closed hat drifts between kits and
-- never lands on one it has no part in
local dl = {}
for i = 1, 8 do dl[i] = build_lane(i, BANK.generic) end
local hits_total = 0
for t = 0, BAR * 16 - 1 do
  for i = 1, 8 do
    local n = dl[i]:tick(t, BAR)
    for h = 1, n do
      hits_total = hits_total + 1
      ok(dl[i].hits[h].vel >= 1 and dl[i].hits[h].vel <= 127, "velocity in range")
    end
  end
end
ok(hits_total > 100, "sixteen bars produced plenty of hits (" .. hits_total .. ")")
ok(dl[5].active ~= 1, "CHH drifted off kit 1 over sixteen bars (on " ..
   dl[5].active .. ")")
ok(dl[1].active == 1, "KICK, inheriting the global 'none', held kit 1")
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
