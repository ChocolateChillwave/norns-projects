-- the taming tests: patchcore's windows/bias/modes, and the specific
-- promises rytm_map.lua makes about what a random roll can do.
-- run: lua rytmpatch/test/test_taming.lua
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")
local Core = dofile(S.DIR .. "lib/patchcore.lua")
local Map = dofile(S.DIR .. "lib/rytm_map.lua")

math.randomseed(7)

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1; S.real_print("  FAIL: " .. msg) end
end
local function section(s) S.real_print("\n== " .. s) end

local core = Core.new({send = function() end})
local function slot_of(desc, key) return {key = key or ("k." .. desc.name .. desc.cc), desc = desc} end

-- every desc in the map, with a stable key per (page, position)
local function all_descs()
  local out = {}
  for mi, page in ipairs(Map.machine_pages) do
    for i = 1, 8 do
      if page[i] then out[#out + 1] = {desc = page[i], key = "m" .. mi .. "." .. i,
                                       where = Map.machine_names[mi]} end
    end
  end
  for pi, pg in ipairs(Map.track_pages) do
    if pg.slots then
      for i = 1, 8 do
        if pg.slots[i] then out[#out + 1] = {desc = pg.slots[i], key = "t" .. pi .. "." .. i,
                                             where = pg.name} end
      end
    end
  end
  for pi, pg in ipairs(Map.fx_pages) do
    for i = 1, 8 do
      if pg.slots[i] then out[#out + 1] = {desc = pg.slots[i], key = "f" .. pi .. "." .. i,
                                           where = pg.name} end
    end
  end
  return out
end

local descs = all_descs()

---------------------------------------------------------------- map sanity
section("map sanity")
ok(#descs > 200, "map exposes a few hundred params (got " .. #descs .. ")")

for _, e in ipairs(descs) do
  local d = e.desc
  local id = e.where .. "/" .. d.name
  ok(d.min < d.max, id .. ": min < max")
  ok(d.cc >= 0 and d.cc <= 127, id .. ": cc in range")
  local lo, hi = d.rmin or d.min, d.rmax or d.max
  ok(lo >= d.min and hi <= d.max, id .. ": tame window inside the full range")
  ok(lo <= hi, id .. ": tame window is not inverted")
  if d.labels then
    ok(#d.labels == d.max - d.min + 1,
       id .. ": " .. #d.labels .. " labels for " .. (d.max - d.min + 1) .. " values")
    ok(d.discrete, id .. ": labelled params are discrete")
  end
  if d.bias then
    ok(d.bias == "low" or d.bias == "high" or d.bias == "center", id .. ": known bias")
  end
  if d.default then
    ok(d.default >= d.min and d.default <= d.max, id .. ": default inside range")
  end
end

---------------------------------------------------------------- windows hold
section("rolls stay inside the tame window")
local opts = {amount = 1, lo = 0, hi = 1, spread = 0}
local escaped = 0
for _, e in ipairs(descs) do
  local d = e.desc
  local s = slot_of(d, e.key)
  if not core:is_locked(s) then
    local lo, hi = d.rmin or d.min, d.rmax or d.max
    for _ = 1, 40 do
      local v = core:roll(s, opts)
      if v < lo or v > hi then escaped = escaped + 1 end
    end
  end
end
ok(escaped == 0, escaped .. " rolls landed outside their window")

-- and the full range is still reachable by hand
section("hand editing is not constrained")
local amp = Map.track_pages[4].slots
local drive = slot_of(amp[4], "hand.drive")
core:set(drive, 0)
for _ = 1, 200 do core:delta(drive, 1) end
ok(core:get(drive) == 127, "encoder reaches 127 on a param whose window caps at "
   .. (amp[4].rmax or 127) .. " (got " .. core:get(drive) .. ")")

---------------------------------------------------------------- modes
section("per-param modes")
local s = slot_of(Map.track_pages[3].slots[5], "mode.freq") -- FILTER FREQ
ok(core:mode(s) == "tame", "params start tame")
ok(core:cycle_mode(s) == "wide", "K3 once -> wide")
ok(core:cycle_mode(s) == "locked", "K3 twice -> locked")
ok(core:is_locked(s), "locked mode reads as locked")
ok(core:cycle_mode(s) == "tame", "K3 three times -> back to tame")

local locked_by_default = slot_of(Map.track_pages[2].slots[4], "mode.slot") -- SAMPLE SLOT
ok(core:mode(locked_by_default) == "locked", "desc.lock params start locked")
ok(core:cycle_mode(locked_by_default) == "tame", "cycling a locked param opens it")

-- a wide param ignores its window; a tame one does not
local freq = Map.track_pages[3].slots[5]
local wide = slot_of(freq, "wide.freq")
core:set_mode(wide, "wide")
local below = 0
for _ = 1, 300 do
  if core:roll(wide, opts) < freq.rmin then below = below + 1 end
end
ok(below > 0, "a wide param can land below its tame window (" .. below .. "/300)")

---------------------------------------------------------------- spread
section("widen range")
local tame_hits, open_hits = 0, 0
local t = slot_of(freq, "spread.freq")
for _ = 1, 300 do
  if core:roll(t, {amount = 1, lo = 0, hi = 1, spread = 0}) < freq.rmin then tame_hits = tame_hits + 1 end
  if core:roll(t, {amount = 1, lo = 0, hi = 1, spread = 1}) < freq.rmin then open_hits = open_hits + 1 end
end
ok(tame_hits == 0, "spread 0 keeps the window")
ok(open_hits > 50, "spread 100% reaches the whole range (" .. open_hits .. "/300)")

---------------------------------------------------------------- bias
section("bias")
local function mean_roll(desc, key, n, o)
  local sum = 0
  local sl = slot_of(desc, key)
  for _ = 1, n do sum = sum + core:roll(sl, o) end
  return sum / n
end

local atk = Map.track_pages[4].slots[1] -- AMP ATK, bias low
local mid = (atk.rmin + atk.rmax) / 2
local m = mean_roll(atk, "bias.atk", 400, opts)
ok(m < mid, "attack biases short: mean " .. string.format("%.1f", m) .. " < midpoint " .. mid)

local cut = Map.track_pages[3].slots[5] -- FILTER FREQ, bias high
local cmid = (cut.rmin + cut.rmax) / 2
local cm = mean_roll(cut, "bias.freq", 400, opts)
ok(cm > cmid, "cutoff biases open: mean " .. string.format("%.1f", cm) .. " > midpoint " .. cmid)

-- bias fades out as the window opens, so "full range" really is uniform
local wm = mean_roll(atk, "bias.atk2", 600, {amount = 1, lo = 0, hi = 1, spread = 1})
ok(math.abs(wm - 63.5) < 10, "at spread 100% the draw is ~uniform (mean "
   .. string.format("%.1f", wm) .. ")")

---------------------------------------------------------------- the promises
section("specific taming promises")
local function desc_on(page, i) return page.slots[i] end
local filt, ampp, lfo, samp = Map.track_pages[3], Map.track_pages[4], Map.track_pages[5], Map.track_pages[2]

ok(desc_on(ampp, 4).rmax <= 60, "amp overdrive cannot be rolled past 60")
ok(desc_on(ampp, 1).rmax <= 25 and desc_on(ampp, 1).bias == "low",
   "amp attack stays short and biases shorter")
ok(desc_on(filt, 5).rmin >= 40, "filter cutoff never rolls into silence")
ok(desc_on(filt, 6).rmax <= 85, "resonance stays below self-oscillation")
ok(desc_on(samp, 3).rmax <= 60, "bit reduction is capped")
ok(desc_on(samp, 4).lock, "sample slot is locked by default")
ok(desc_on(ampp, 8).lock, "track volume is locked by default")
ok(desc_on(lfo, 8).rmin > 40 and desc_on(lfo, 8).rmax < 90, "lfo depth stays shallow")

-- pitch: every centred tuning param stays within a few semitones of
-- centre. (a 0-based "DETUN" amount, like SD/CB Classic's, is a timbre
-- spread rather than a pitch offset, so it isn't held to this.)
local wide_tunings = {}
for _, e in ipairs(descs) do
  local d = e.desc
  if d.centered and (d.name:match("^TUNE") or d.name == "DETUN" or d.name:match("^OFS")) then
    local centre = (d.min + d.max) / 2
    local lo, hi = d.rmin or d.min, d.rmax or d.max
    local dev = math.max(centre - lo, hi - centre)
    if dev > (d.max - d.min) * 0.2 then
      wide_tunings[#wide_tunings + 1] = e.where .. "/" .. d.name
    end
  end
end
ok(#wide_tunings == 0, "tuning windows stay near centre: " .. table.concat(wide_tunings, ", "))

-- FX that can get loud or runaway
local fxd, fxr, fxdist, fxcomp = Map.fx_pages[1], Map.fx_pages[2], Map.fx_pages[3], Map.fx_pages[4]
ok(fxd.slots[4].rmax <= 90, "delay feedback cannot be rolled to runaway")
ok(fxdist.slots[1].rmax <= 50 and fxdist.slots[3].rmax <= 50, "distortion stays modest")
ok(fxcomp.slots[4].rmax <= 45, "compressor makeup gain is capped")
ok(fxcomp.slots[8].lock, "compressor output volume is locked")

---------------------------------------------------------------- wander
section("wander stays inside the window")
local wslots = {}
for i = 1, 8 do wslots[i] = ampp.slots[i] and slot_of(ampp.slots[i], "w." .. i) or false end
for _ = 1, 300 do core:wander_step(wslots, 8, 0.5, 0, 0) end
local out = 0
for i = 1, 8 do
  local sl = wslots[i]
  if sl and not core:is_locked(sl) then
    local d = sl.desc
    local v = core:get(sl)
    if v < (d.rmin or d.min) or v > (d.rmax or d.max) then out = out + 1 end
  end
end
ok(out == 0, "wander never walked a param out of its window")

---------------------------------------------------------------- persistence
section("modes persist")
local c2 = Core.new({send = function() end})
local keep = slot_of(freq, "persist.freq")
c2:set_mode(keep, "wide")
c2:set(keep, 99)
c2:save("/tmp/x.data")
local c3 = Core.new({send = function() end})
c3:load("/tmp/x.data")
ok(c3:mode(keep) == "wide", "mode survives save/load")
ok(c3:get(keep) == 99, "value survives save/load")

-- a file written before modes existed still loads
tab.save({values = {["old.key"] = 5}, locks = {["old.key"] = 1}}, "/tmp/old.data")
local c4 = Core.new({send = function() end})
c4:load("/tmp/old.data")
ok(c4:mode({key = "old.key", desc = freq}) == "locked", "old lock=1 files migrate to locked")

S.real_print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
