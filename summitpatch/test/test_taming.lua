-- the taming tests: patchcore's windows/bias/modes, plus the promises
-- summit_map.lua makes about what a random patch can do.
-- run: lua summitpatch/test/test_taming.lua
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")
local Core = dofile(S.DIR .. "lib/patchcore.lua")
local Map = dofile(S.DIR .. "lib/summit_map.lua")

math.randomseed(23)

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1; S.real_print("  FAIL: " .. msg) end
end
local function section(s) S.real_print("\n== " .. s) end

local core = Core.new({send = function() end})
local slots = {}
for _, pg in ipairs(Map.pages) do
  for i = 1, 8 do
    local d = pg.slots[i]
    if d then slots[d.id] = {key = "s." .. d.id, desc = d, page = pg.name} end
  end
end
local function slot(id) return assert(slots[id], "no slot " .. id) end

---------------------------------------------------------------- map sanity
section("map sanity")
local n = 0
for _ in pairs(slots) do n = n + 1 end
ok(n > 70, "map exposes the CC + NRPN params (got " .. n .. ")")

for id, s in pairs(slots) do
  local d = s.desc
  ok(d.min < d.max, id .. ": min < max")
  ok((d.cc ~= nil) ~= (d.nrpn ~= nil), id .. ": addressed by either CC or NRPN, not both")
  local lo, hi = d.rmin or d.min, d.rmax or d.max
  ok(lo >= d.min and hi <= d.max and lo <= hi, id .. ": tame window inside the range")
  if d.labels then
    ok(#d.labels == d.max - d.min + 1, id .. ": label count matches range")
  end
  if d.bias then
    ok(d.bias == "low" or d.bias == "high" or d.bias == "center", id .. ": known bias")
  end
end

-- AFX defaults and recipes can only name params that exist
for i, id in ipairs(Map.afx_defaults) do
  ok(slots[id] ~= nil, "afx default " .. i .. " (" .. id .. ") exists")
  ok(slots[id] and slots[id].desc.cc ~= nil, "afx default " .. id .. " is a plain CC")
end
for name, r in pairs(Map.recipes) do
  for id, win in pairs(r) do
    ok(slots[id] ~= nil, "recipe " .. name .. " names a real param: " .. id)
    if slots[id] then
      local d = slots[id].desc
      ok(win[1] >= d.min and win[2] <= d.max and win[1] <= win[2],
         "recipe " .. name .. "/" .. id .. ": window inside the range")
    end
  end
end
for _, name in ipairs(Map.recipe_names) do
  ok(name == "any" or name == "chaos" or Map.recipes[name] ~= nil,
     "recipe '" .. name .. "' has a table")
end

---------------------------------------------------------------- windows hold
section("rolls stay inside the tame window")
local opts = {amount = 1, lo = 0, hi = 1, spread = 0}
local escaped = {}
for id, s in pairs(slots) do
  if not core:is_locked(s) then
    local d = s.desc
    local lo, hi = d.rmin or d.min, d.rmax or d.max
    for _ = 1, 60 do
      local v = core:roll(s, opts)
      if v < lo or v > hi then escaped[#escaped + 1] = id end
    end
  end
end
ok(#escaped == 0, #escaped .. " rolls escaped their window")

section("hand editing is not constrained")
local dist = slot("dist")
core:set(dist, 0)
for _ = 1, 200 do core:delta(dist, 1) end
ok(core:get(dist) == 127, "the encoder still reaches 127 on a param capped at "
   .. dist.desc.rmax .. " (got " .. core:get(dist) .. ")")

---------------------------------------------------------------- pitch safety
section("a random patch stays in tune")
local pitch_ids = {"o1_coarse", "o2_coarse", "o3_coarse", "o1_range", "o2_range", "o3_range",
                   "o1_m2pitch", "o1_l2pitch", "o2_m2pitch", "o2_l2pitch",
                   "o3_m2pitch", "o3_l2pitch", "glide_on"}
for _, id in ipairs(pitch_ids) do
  ok(core:is_locked(slot(id)), id .. " is locked by default")
end
for _, id in ipairs({"o1_fine", "o2_fine", "o3_fine"}) do
  local d = slot(id).desc
  ok(not d.lock, id .. " is free to move (detune is musical)")
  ok(d.rmin >= 55 and d.rmax <= 73, id .. " only detunes slightly")
end

section("specific taming promises")
ok(slot("amp_a").desc.rmax <= 30 and slot("amp_a").desc.bias == "low",
   "amp attack stays short and biases shorter")
ok(slot("amp_s").desc.rmin >= 40, "amp sustain stays audible")
ok(slot("cutoff").desc.rmin >= 40 and slot("cutoff").desc.bias == "high",
   "cutoff never rolls into silence")
ok(slot("reso").desc.rmax <= 75, "resonance stays below self-oscillation")
ok(slot("dist").desc.rmax <= 45, "distortion stays modest")
ok(slot("f_drive").desc.rmax <= 55 and slot("f_post").desc.rmax <= 55, "filter drive is capped")
ok(slot("dly_fb").desc.rmax <= 75, "delay feedback cannot run away")
ok(slot("mix_noise").desc.rmax <= 45 and slot("mix_ring").desc.rmax <= 50,
   "noise and ring mod stay in the background")
ok(slot("mix_o1").desc.rmin >= 60, "osc 1 stays present in the mix")
for _, id in ipairs({"o1_wave", "f_shape", "drift"}) do
  ok(core:is_locked(slot(id)), "unverified NRPN param " .. id .. " is locked by default")
end

---------------------------------------------------------------- modes + spread
section("modes and widen range")
local s = slot("cutoff")
ok(core:mode(s) == "tame", "params start tame")
ok(core:cycle_mode(s) == "wide", "K3 -> wide")
ok(core:cycle_mode(s) == "locked", "K3 -> locked")
ok(core:cycle_mode(s) == "tame", "K3 -> tame")

local below = 0
for _ = 1, 300 do
  if core:roll(s, {amount = 1, lo = 0, hi = 1, spread = 1}) < s.desc.rmin then below = below + 1 end
end
ok(below > 50, "spread 100% reaches under the tame window (" .. below .. "/300)")

-- recipes replace the window; chaos is spread, not a recipe table
section("recipes")
local amp_d = slot("amp_d")
local hits = 0
for _ = 1, 300 do
  local v = core:roll(amp_d, opts, Map.recipes.perc.amp_d)
  if v >= Map.recipes.perc.amp_d[1] and v <= Map.recipes.perc.amp_d[2] then hits = hits + 1 end
end
ok(hits == 300, "a recipe window is respected exactly (" .. hits .. "/300)")

---------------------------------------------------------------- outliers
section("outliers")
local sus = slot("amp_s")
local topts = {amount = 1, lo = 0, hi = 1, spread = 0, tails = 0.1}
local outside, zeroish, minv, maxv = 0, 0, 999, -1
local N = 4000
for _ = 1, N do
  local v = core:roll(sus, topts)
  if v < sus.desc.rmin then outside = outside + 1 end
  if v <= 5 then zeroish = zeroish + 1 end
  minv, maxv = math.min(minv, v), math.max(maxv, v)
end
local pct = outside / N * 100
ok(pct > 5 and pct < 16, "about 10% of rolls land outside the window (got "
   .. string.format("%.1f", pct) .. "%)")
ok(zeroish > 0, "a sustain of ~0 is reachable again (" .. zeroish .. "/" .. N .. ")")
ok(minv >= sus.desc.min and maxv <= sus.desc.max, "outliers stay inside the real CC range")

local none = 0
for _ = 1, 500 do
  if core:roll(sus, {amount = 1, lo = 0, hi = 1, spread = 0, tails = 0}) < sus.desc.rmin then
    none = none + 1
  end
end
ok(none == 0, "outliers 0% is the old strict window")

-- hard caps: an outlier may go under the window but never over it
local fb = slot("dly_fb")
ok(fb.desc.hard == "max", "delay feedback is hard-capped at the top")
local over, under = 0, 0
for _ = 1, 2000 do
  local v = core:roll(fb, {amount = 1, lo = 0, hi = 1, spread = 0, tails = 1})
  if v > fb.desc.rmax then over = over + 1 end
  if v < fb.desc.rmin then under = under + 1 end
end
ok(over == 0, "no outlier ever exceeds a hard max (" .. over .. ")")
ok(under > 0, "the un-capped side still produces outliers (" .. under .. ")")

-- a param the user opened up ignores tails: it is already fully open
local w = slot("mix_noise")
core:set_mode(w, "wide")
local hi_hits = 0
for _ = 1, 500 do
  if core:roll(w, topts) > w.desc.rmax then hi_hits = hi_hits + 1 end
end
ok(hi_hits > 100, "a wide param is uniformly open, not window + tails")
core:set_mode(w, "tame")

---------------------------------------------------------------- bias
section("bias")
local function mean(id, o, count, override)
  local sum = 0
  for _ = 1, count do sum = sum + core:roll(slot(id), o, override) end
  return sum / count
end
local a = slot("amp_a").desc
ok(mean("amp_a", opts, 400) < (a.rmin + a.rmax) / 2, "attack biases short")
local c = slot("cutoff").desc
ok(mean("cutoff", opts, 400) > (c.rmin + c.rmax) / 2, "cutoff biases open")

S.real_print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
