-- covers lib/garc.lua, the arc module shared across the scripts in this
-- repo. it's worth its own file because every script depends on it and a
-- rendering mistake is invisible until you're holding the hardware.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")
package.path = HERE .. "/../lib/?.lua;" .. package.path

local GArc = require("garc")

local print = S.real_print
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end

---------------------------------------------------------------- harness
params:add_group("test", 8)
params:add{type = "control", id = "wide", name = "wide",
           controlspec = controlspec.new(0, 100, "lin", 1, 50, "", 1 / 100)}
params:add{type = "control", id = "signed", name = "signed",
           controlspec = controlspec.new(-100, 100, "lin", 1, 0, "", 1 / 200)}
params:add{type = "control", id = "few", name = "few",
           controlspec = controlspec.new(1, 4, "lin", 1, 1, "", 1 / 3)}
params:add{type = "control", id = "pair", name = "pair",
           controlspec = controlspec.new(1, 2, "lin", 1, 1, "", 1 / 1)}
params:add_number("arc_threshold", "sensitivity", 1, 64, 24)
params:add_number("arc_brightness", "brightness", 1, 15, 15)
params:add_number("arc_dim", "dim", 1, 15, 4)
params:add_number("arc_position", "position", 1, 4, 1)

local PAGES = {
  {name = "ONE", rings = {
    {label = "wide", id = "wide"},
    {label = "signed", id = "signed", style = "bipolar", track = true},
    {label = "few", id = "few"},
    {label = "pair", id = "pair"},
  }},
  {name = "TWO", rings = {
    {label = "comet", id = "wide", style = "comet"},
    {label = "dot", id = "wide", style = "dot"},
    {label = "tracked", id = "wide", track = true},
  }},
}

local a = GArc:new{pages = PAGES, threshold_id = "arc_threshold",
                   bright_id = "arc_brightness", dim_id = "arc_dim",
                   position_id = "arc_position"}

-- what got lit on a ring, as {led = level}
local function draw()
  S.arc_leds = {}
  a:redraw()
  local rings = {{}, {}, {}, {}}
  for _, l in ipairs(S.arc_leds) do rings[l[1]][l[2]] = l[3] end
  return rings
end
local function count(ring, min_level)
  local n = 0
  for _, level in pairs(ring) do
    if level >= (min_level or 1) then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------- fill
section("fill, the default")
params:set("wide", 50)
local r = draw()
local half = count(r[1])
ok(half > 25 and half < 39, "a mid value lights about half the ring (" .. half .. "/64)")

params:set("wide", 0)
r = draw()
ok(count(r[1]) == 1, "at minimum exactly one led stays lit, never mistaken for off")

params:set("wide", 100)
r = draw()
ok(count(r[1]) == 64, "at maximum the ring is completely full")

---------------------------------------------------------------- bipolar
section("bipolar")
params:set("signed", 0)
r = draw()
local bright = 15
local lit_bright = count(r[2], bright)
ok(lit_bright == 1, "centred: a single bright led at the origin (" .. lit_bright .. ")")
ok(count(r[2]) == 64, "with the track ring underneath it")

params:set("signed", 100)
r = draw()
local pos = {}
for led, level in pairs(r[2]) do if level >= bright then pos[#pos + 1] = led end end
table.sort(pos)
ok(#pos == 33, "full positive fills half the ring from the origin (" .. #pos .. ")")
ok(pos[1] == 1, "starting at the origin")

params:set("signed", -100)
r = draw()
local neg = {}
for led, level in pairs(r[2]) do if level >= bright then neg[#neg + 1] = led end end
ok(#neg == 33, "full negative fills the same amount the other way (" .. #neg .. ")")
local wraps_backwards = false
for _, led in ipairs(neg) do if led > 32 then wraps_backwards = true end end
ok(wraps_backwards, "and it runs anticlockwise from the origin, not clockwise")

params:set("signed", -50)
r = draw()
local partial = 0
for _, level in pairs(r[2]) do if level >= bright then partial = partial + 1 end end
ok(partial > 10 and partial < 25,
   "half negative reaches half as far (" .. partial .. ")")

---------------------------------------------------------------- discrete
section("discrete ticks")
params:set("few", 1)
r = draw()
ok(count(r[3]) == 4, "a 4-option param draws one tick per option")
ok(count(r[3], 15) == 1, "with exactly one of them bright")
params:set("few", 3)
r = draw()
ok(count(r[3], 15) == 1, "still one bright tick after moving")
r = draw()
ok(count(r[4]) == 2, "a 2-option param draws two ticks, not a half-lit ring")

---------------------------------------------------------------- styles
section("comet and dot")
a:cycle_page()
params:set("wide", 60)
r = draw()
local comet_levels, comet_max, comet_min = {}, 0, 99
for _, level in pairs(r[1]) do
  comet_levels[#comet_levels + 1] = level
  comet_max = math.max(comet_max, level)
  comet_min = math.min(comet_min, level)
end
ok(comet_max > comet_min, "a comet fades along its tail rather than being flat")
ok(comet_max == 15, "with a full-brightness head")
ok(count(r[2]) == 1, "a dot lights exactly one led")
ok(count(r[3]) == 64, "a tracked ring lights the whole circle")
ok(count(r[3], 15) > 1 and count(r[3], 15) < 64,
   "with the value drawn brighter on top of the track")
a:cycle_page()

---------------------------------------------------------------- rotation
section("rotation")
params:set("wide", 0)
params:set("arc_position", 1)
local at_1 = draw()
params:set("arc_position", 3)
local at_3 = draw()
local led_1, led_3
for led in pairs(at_1[1]) do led_1 = led end
for led in pairs(at_3[1]) do led_3 = led end
ok(led_1 ~= led_3, "rotating the arc moves where a ring starts (" .. led_1 .. " -> " .. led_3 .. ")")
ok(math.abs(led_3 - led_1) == 32, "by exactly half a turn for two quarter steps")
params:set("arc_position", 1)

---------------------------------------------------------------- live updates
section("poll: values that move without the arc being touched")
params:set("wide", 20)
a:redraw()
S.arc_leds = {}
a:poll()
ok(#S.arc_leds == 0, "nothing redraws when nothing has changed")

params:set("wide", 80)          -- as if from the PARAMS menu or a pset
S.arc_leds = {}
a:poll()
ok(#S.arc_leds > 0, "a value changed elsewhere redraws the ring")

S.arc_leds = {}
a:poll()
ok(#S.arc_leds == 0, "and then settles again")

-- a ring whose id is a resolver function must follow when it retargets
local which = "wide"
local resolver_page = {{name = "R", rings = {
  {label = "either", id = function() return which end},
}}}
local b = GArc:new{pages = resolver_page, threshold_id = "arc_threshold",
                   bright_id = "arc_brightness", dim_id = "arc_dim"}
b:redraw()
S.arc_leds = {}
b:poll()
ok(#S.arc_leds == 0, "resolver ring: quiet while its target is unchanged")
which = "signed"
S.arc_leds = {}
b:poll()
ok(#S.arc_leds > 0, "resolver ring: redraws when it retargets to another param")

---------------------------------------------------------------- turning
section("turning a ring")
params:set("wide", 50)
local before = params:get("wide")
for _ = 1, 30 do a.a.delta(1, 1) end   -- past the sensitivity threshold
ok(params:get("wide") > before, "turning a ring moves its param")
local footer = a:footer_text()
ok(footer and footer:find("ONE") and footer:find("wide"),
   "the footer names the page and ring: " .. tostring(footer))
ok(#footer <= 30, "and stays inside a screen line (" .. #footer .. " chars)")

---------------------------------------------------------------- no arc
section("no arc connected")
S.arc_connected = false
local c = GArc:new{pages = PAGES, threshold_id = "arc_threshold",
                   bright_id = "arc_brightness", dim_id = "arc_dim"}
local quiet = pcall(function()
  c:redraw()
  c:poll()
  c:cycle_page()
end)
ok(quiet, "redraw, poll and page cycling are all safe with no arc plugged in")
ok(c:footer_text() == nil, "and the footer reports nothing to draw")
S.arc_connected = true

---------------------------------------------------------------- done
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
