-- covers the pure-Lua libs directly: chords (banks, degree stacking,
-- inversion, voice leading, naming) and patterns (slots, mirroring, the
-- cycler's morphing). no norns APIs involved, so these run as plain Lua.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = HERE .. "/../lib/?.lua;" .. package.path

local Chords = require("chords")
local Patterns = require("patterns")

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local SCALES = {
  major = {0, 2, 4, 5, 7, 9, 11},
  ["natural minor"] = {0, 2, 3, 5, 7, 8, 10},
  dorian = {0, 2, 3, 5, 7, 9, 10},
  ["harmonic minor"] = {0, 2, 3, 5, 7, 8, 11},
}
local function build_scale(steps, base, len)
  local s = {}
  for i = 0, len - 1 do
    s[i + 1] = base + math.floor(i / #steps) * 12 + steps[(i % #steps) + 1]
  end
  return s
end
local C_MAJOR = build_scale(SCALES.major, 48, 48)

---------------------------------------------------------------- banks
section("banks")
local shape_problems, dupes = 0, 0
for _, bank in ipairs(Chords.BANKS) do
  if #bank.voicings ~= 4 then
    shape_problems = shape_problems + 1
    print("  " .. bank.name .. " has " .. #bank.voicings .. " voicings, not 4")
  end
  local seen = {}
  for _, v in ipairs(bank.voicings) do
    local key = table.concat(v.deg, ",")
    if seen[key] then dupes = dupes + 1 end
    seen[key] = true
    if v.deg[1] ~= 0 or #v.deg < 3 or #v.deg > 6 then
      shape_problems = shape_problems + 1
      print("  odd shape: " .. bank.name .. " / " .. v.name .. " {" .. key .. "}")
    end
    for i = 2, #v.deg do
      if v.deg[i] <= v.deg[i - 1] then
        shape_problems = shape_problems + 1
        print("  not ascending: " .. bank.name .. " / " .. v.name)
      end
    end
  end
end
ok(shape_problems == 0, "every voicing is 3-6 ascending degrees from the root")
ok(dupes == 0, "no bank repeats a voicing")
ok(#Chords.BANKS >= 13, "at least 13 banks")
ok(Chords.BANKS[1].name == "triads", "triads is first, the plainest bank")
ok(#Chords.BANKS[1].voicings[1].deg == 3, "triads bank really does have a 3-note voicing")

-- the whole point of degree stacking: it cannot produce an out-of-key note
local out_of_key, short = 0, 0
for _, steps in pairs(SCALES) do
  for pc = 0, 11 do
    local scale = build_scale(steps, 48 + pc, 48)
    local in_key = {}
    for _, st in ipairs(steps) do in_key[(pc + st) % 12] = true end
    for _, bank in ipairs(Chords.BANKS) do
      for _, v in ipairs(bank.voicings) do
        for root = 1, 15 do
          local notes = Chords.build(scale, root, v.deg, false)
          if #notes ~= #v.deg then short = short + 1 end
          for _, n in ipairs(notes) do
            if not in_key[n % 12] then out_of_key = out_of_key + 1 end
          end
        end
      end
    end
  end
end
ok(out_of_key == 0, out_of_key .. " out-of-key notes (4 scales x 12 keys x 15 roots)")
ok(short == 0, short .. " chords came out short from a reachable grid position")

local lo, hi = 127, 0
for _, bank in ipairs(Chords.BANKS) do
  for _, v in ipairs(bank.voicings) do
    for root = 1, 15 do
      for _, n in ipairs(Chords.build(C_MAJOR, root, v.deg, false)) do
        lo, hi = math.min(lo, n), math.max(hi, n)
      end
    end
  end
end
ok((hi - lo) / 12 <= 5, string.format("range stays playable: %.1f octaves", (hi - lo) / 12))

---------------------------------------------------------------- chromatic
section("chromatic fallback")
-- degree stacking over 12 equal semitones would make every voicing a
-- cluster, so a chromatic root is built to a major shape instead. the test
-- is that it comes out identical to the same voicing on a major tonic,
-- just moved -- not that it avoids seconds, since the clusters bank is
-- meant to have them.
local chromatic = build_scale({0,1,2,3,4,5,6,7,8,9,10,11}, 48, 48)
local shape_matches = true
for _, bank in ipairs(Chords.BANKS) do
  for _, v in ipairs(bank.voicings) do
    local chrom = Chords.build(chromatic, 2, v.deg, true)   -- rooted on C#
    local major = Chords.build(C_MAJOR, 1, v.deg, false)    -- rooted on C
    if #chrom ~= #major then shape_matches = false end
    for i = 1, math.min(#chrom, #major) do
      if (chrom[i] - chrom[1]) ~= (major[i] - major[1]) then shape_matches = false end
    end
  end
end
ok(shape_matches, "a chromatic root builds the same shape a major key would")

---------------------------------------------------------------- inversion
section("inversion and naming")
local seventh = Chords.build(C_MAJOR, 1, {0, 2, 4, 6}, false)
ok(Chords.name(48, Chords.invert(seventh, 1), NOTE_NAMES) == "Cmaj7/E",
   "inverting names the bass, not a different chord")
ok(Chords.name(48, Chords.invert(seventh, -1), NOTE_NAMES) == "Cmaj7/B",
   "inverting downwards too")
ok(#Chords.invert(seventh, 3) == #seventh, "inversion never loses a note")

local naming = {
  {{48,52,55}, "C"}, {{48,51,55}, "Cm"}, {{48,53,55,58}, "C7sus4"},
  {{48,50,55}, "Csus2"}, {{48,53,55}, "Csus4"}, {{48,52,55,57}, "C6"},
  {{48,51,55,57}, "Cm6"}, {{48,52,55,57,62}, "C6/9"}, {{48,52,55,62}, "Cadd9"},
  {{48,52,55,59}, "Cmaj7"}, {{48,52,55,58}, "C7"}, {{48,51,55,58}, "Cm7"},
  {{48,52,55,59,62}, "Cmaj9"}, {{48,51,55,58,62,65}, "Cm11"},
  {{48,55,59,62,65}, "Cmaj11"}, {{48,52,58,62,69}, "C13"},
  {{48,51,54}, "Cdim"}, {{48,52,56}, "Caug"}, {{48,55,60}, "C5"},
}
local bad_names = 0
for _, case in ipairs(naming) do
  local got = Chords.name(48, case[1], NOTE_NAMES)
  if got ~= case[2] then
    bad_names = bad_names + 1
    print("  " .. case[2] .. " named as " .. got)
  end
end
ok(bad_names == 0, #naming .. " standard chord symbols name correctly")

---------------------------------------------------------------- voice leading
section("voice leading")
local function movement(from, to)
  local total = 0
  for _, n in ipairs(to) do
    local nearest = math.huge
    for _, r in ipairs(from) do nearest = math.min(nearest, math.abs(n - r)) end
    total = total + nearest
  end
  return total
end
local function led(notes, reference)
  local inv, oct = Chords.lead(notes, reference)
  local out = Chords.invert(notes, inv)
  if oct ~= 0 then for i, n in ipairs(out) do out[i] = n + oct * 12 end end
  return out
end

ok(select(1, Chords.lead(seventh, nil)) == 0, "no reference: chord is left alone")
ok(select(1, Chords.lead(seventh, {})) == 0, "empty reference: chord is left alone")
ok(select(1, Chords.lead({}, seventh)) == 0, "leading an empty chord is safe")
local inv_self, oct_self = Chords.lead(seventh, seventh)
ok(inv_self == 0 and oct_self == 0, "a chord already in place doesn't move")

local pitch_classes_kept = true
local f = Chords.build(C_MAJOR, 4, {0, 2, 4, 6}, false)
local f_led = led(f, seventh)
local present = {}
for _, n in ipairs(f_led) do present[n % 12] = true end
for _, n in ipairs(f) do if not present[n % 12] then pitch_classes_kept = false end end
ok(pitch_classes_kept, "leading changes placement, never which chord it is")

-- root position is one of the placements considered, so leading can never
-- be the worse choice
local worse, tested, plain_sum, led_sum = 0, 0, 0, 0
for _, bank in ipairs(Chords.BANKS) do
  for _, v in ipairs(bank.voicings) do
    for from = 1, 8 do
      local reference = Chords.build(C_MAJOR, from, v.deg, false)
      for to = 1, 8 do
        if to ~= from then
          local built = Chords.build(C_MAJOR, to, v.deg, false)
          local plain_move = movement(reference, built)
          local led_move = movement(reference, led(built, reference))
          if led_move > plain_move + 1e-9 then worse = worse + 1 end
          tested, plain_sum, led_sum = tested + 1, plain_sum + plain_move, led_sum + led_move
        end
      end
    end
  end
end
ok(worse == 0, "leading is never worse than root position (" .. tested .. " changes)")
ok(led_sum < plain_sum * 0.75,
   string.format("and much smoother: %.1f vs %.1f semitones per change",
                 led_sum / tested, plain_sum / tested))

---------------------------------------------------------------- patterns
section("patterns")
local bad_slots = 0
for idx = 1, #Patterns.NAMES do
  for n = 0, 8 do
    for _, mirrored in ipairs({false, true}) do
      local slots = Patterns.slots(idx, n, mirrored)
      if #slots ~= n then bad_slots = bad_slots + 1 end
      for i = 1, n do
        local s = slots[i]
        if type(s) ~= "number" or s ~= s or s < -1e-9 or s > 2 * n + 1 then
          bad_slots = bad_slots + 1
        end
      end
    end
  end
end
ok(bad_slots == 0, "every pattern gives one sane slot per note, 0-8 notes")

local function order_of(slots)
  local idx = {}
  for i = 1, #slots do idx[i] = i end
  table.sort(idx, function(a, b)
    if math.abs(slots[a] - slots[b]) < 1e-9 then return a < b end
    return slots[a] < slots[b]
  end)
  local groups, last = {}, nil
  for _, i in ipairs(idx) do
    if last and math.abs(slots[i] - last) < 1e-9 then
      groups[#groups] = groups[#groups] .. "+" .. i
    else groups[#groups + 1] = tostring(i) end
    last = slots[i]
  end
  return table.concat(groups, " ")
end
local function index_of(name)
  for i, n in ipairs(Patterns.NAMES) do if n == name then return i end end
end
ok(order_of(Patterns.slots(index_of("block"), 6, false)) == "1+2+3+4+5+6",
   "block strikes everything together")
ok(order_of(Patterns.slots(index_of("pinch"), 6, false)):sub(1, 3) == "1+6",
   "pinch takes the outer notes first")
ok(order_of(Patterns.slots(index_of("down"), 6, false)) ==
   order_of(Patterns.slots(index_of("up"), 6, true)),
   "mirroring 'up' gives 'down'")
local acc = Patterns.slots(index_of("accelerate"), 6, false)
local dec = Patterns.slots(index_of("decelerate"), 6, false)
ok((acc[2] - acc[1]) > (acc[6] - acc[5]), "accelerate closes up as it goes")
ok((dec[2] - dec[1]) < (dec[6] - dec[5]), "decelerate spreads out as it goes")

---------------------------------------------------------------- cycler
section("pattern cycling")
local function run(o, passes, n, tweak)
  local c = Patterns.cycler()
  local out = {}
  for p = 1, passes do
    if tweak then tweak(o, p) end
    out[p] = c:step(o, n or 4)
  end
  return out
end
local function same(a, b)
  for i = 1, #a do if math.abs(a[i] - b[i]) > 1e-9 then return false end end
  return true
end
local up = Patterns.slots(1, 4, false)
local down = Patterns.slots(1, 4, true)

local held = run({pattern = 1, mode = 1, every = 1, morph = 2}, 6)
local steady = true
for p = 2, 6 do if not same(held[p], held[1]) then steady = false end end
ok(steady, "hold: the pattern stays put")

local alt = run({pattern = 1, mode = 3, every = 4, morph = 2}, 12)
local shape = {}
for p = 1, 12 do
  shape[p] = same(alt[p], up) and "U" or (same(alt[p], down) and "D" or "~")
end
ok(table.concat(shape) == "UUUU~~DD~~UU",
   "alternate every 4 with morph 2 blends across, it doesn't jump: " .. table.concat(shape))
ok(alt[5][1] > up[1] and alt[5][1] < down[1], "a blended repeat really is in between")

local fast = run({pattern = 1, mode = 3, every = 1, morph = 4}, 6)
local fast_shape = {}
for p = 1, 6 do
  fast_shape[p] = same(fast[p], up) and "U" or (same(fast[p], down) and "D" or "~")
end
ok(table.concat(fast_shape) == "UDUDUD", "morph is capped so every=1 still alternates")

local knob = run({pattern = 1, mode = 1, every = 1, morph = 3}, 8, 4,
  function(o, p) if p == 3 then o.pattern = index_of("down") end end)
local knob_shape = {}
for p = 1, 8 do
  knob_shape[p] = same(knob[p], up) and "U" or (same(knob[p], down) and "D" or "~")
end
ok(table.concat(knob_shape) == "UU~~~DDD", "turning the pattern knob morphs too")

local sizes_ok = true
local c = Patterns.cycler()
for p = 1, 20 do
  local n = (p % 4) + 2
  if #c:step({pattern = 9, mode = 3, every = 2, morph = 1}, n) ~= n then sizes_ok = false end
end
ok(sizes_ok, "chords joining or leaving mid-morph doesn't break the blend")

---------------------------------------------------------------- done
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
