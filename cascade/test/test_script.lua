-- drives cascade.lua itself against the stubbed norns runtime: init, the
-- params it registers, the grid surface, latch, keys and encoders, MIDI in,
-- voice leading, the bass split, redraw and cleanup.
--
-- the libs are covered in test_libs.lua and test_strum.lua; this file is
-- about the wiring between them and the hardware.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local S = dofile(HERE .. "/norns_stub.lua")

local print = S.real_print
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function section(s) print("\n== " .. s) end
local function try(what, fn)
  local okc, err = pcall(fn)
  ok(okc, what .. " -> " .. tostring(err))
  return okc
end

dofile(S.SCRIPT_DIR .. "cascade.lua")

---------------------------------------------------------------- helpers
local function sounding()
  local on = {}
  for _, e in ipairs(S.midi_sent) do
    if e.t == "on" then on[e.note] = e.ch elseif e.t == "off" then on[e.note] = nil end
  end
  local out = {}
  for n in pairs(on) do out[#out + 1] = n end
  table.sort(out)
  return out, on
end
local function clear() S.midi_sent = {} end
local function press(x, y) S.grid_key(1, x, y, 1) end
local function lift(x, y) S.grid_key(1, x, y, 0) end
local function tap(x, y) press(x, y); lift(x, y) end
local function quiet()
  -- let every release tail and repeat finish
  params:set("latch", 1)
  key(2, 1); key(2, 0)          -- panic
  S.run_for(3)
  clear()
end

---------------------------------------------------------------- init
section("init")
ok(type(init) == "function", "init() is defined")
ok(type(redraw) == "function", "redraw() is defined")
ok(type(key) == "function", "key() is defined")
ok(type(enc) == "function", "enc() is defined")
ok(type(cleanup) == "function", "cleanup() is defined")
ok(rawget(_G, "engine") == nil, "no engine is set -- this is a MIDI-out script")

try("init() runs clean", init)

for _, g in ipairs(params.groups) do
  ok(g.added == g.n,
     "group '" .. g.name .. "' promised " .. g.n .. " params and added " .. g.added)
end

-- a param on an arc ring without a controlspec would silently never light
for _, id in ipairs({"tilt", "humanize", "drift", "density", "probability",
                     "note_length", "release", "upstroke_level", "bank",
                     "invert", "velocity", "voice_lead", "latch", "strum_span",
                     "bass_channel", "bass_octave", "pattern", "pattern_morph"}) do
  local p = params.by_id[id]
  ok(p ~= nil, id .. " exists")
  ok(p and p.controlspec ~= nil, id .. " has a controlspec")
end

local format_errors = 0
for _, p in ipairs(params.list) do
  local okf = pcall(function() return p:string() end)
  if not okf then format_errors = format_errors + 1; print("  " .. p.id .. " won't format") end
end
ok(format_errors == 0, "every param formats without erroring")

---------------------------------------------------------------- grid
section("grid")
clear()
press(1, 8)                     -- bottom-left: lowest root, tightest voicing
S.run_for(0.5)
local held_notes = sounding()
ok(#held_notes >= 3, "pressing a grid cell sounds a chord (" .. #held_notes .. " notes)")
lift(1, 8)
S.run_for(2)
ok(#sounding() == 0, "letting go stops it")

clear()
press(1, 8); S.run_for(0.4)
local low = sounding()
lift(1, 8); S.run_for(2); clear()
press(1, 4); S.run_for(0.4)     -- same column, upper octave group
local high = sounding()
lift(1, 4); S.run_for(2)
ok(high[1] and low[1] and high[1] > low[1],
   "the upper row group plays higher than the lower one")
quiet()

clear()
press(1, 8); press(3, 8)
S.run_for(0.5)
ok(#sounding() > #low, "two cells held merge into a bigger strum")
lift(1, 8); lift(3, 8)
S.run_for(2)
ok(#sounding() == 0, "and both let go cleanly")
quiet()

-- grid LEDs: the metro drives the redraw, so fire it by hand
local function led_counts()
  S.grid_leds = {}
  S.metros[1].event()
  local lit, bright = 0, 0
  for _, l in ipairs(S.grid_leds) do
    lit = lit + 1
    if l[3] >= 6 then bright = bright + 1 end
  end
  return lit, bright
end

params:set("key_root", 1)       -- C major has no black keys at all
local lit, bright = led_counts()
ok(lit >= 40, "the grid draws a resting keyboard (" .. lit .. " cells lit)")
ok(bright == 0, "C major: nothing is marked as an accidental, because there are none")

params:set("key_root", 10)      -- A major: C#, F#, G#
lit, bright = led_counts()
ok(bright > 0 and bright < lit,
   "A major: its three accidentals sit brighter than the rest (" .. bright .. " of " .. lit .. ")")
params:set("key_root", 1)

local off_region = false
for _, l in ipairs(S.grid_leds) do if l[1] > 8 then off_region = true end end
ok(not off_region, "and nothing is drawn in the right half")

-- the grid rebuilds its levels every frame so it follows anything that
-- changes them, but only writes to the hardware when they actually differ
S.metros[1].event()             -- let the previous key change settle first
S.grid_leds = {}
S.metros[1].event()
local idle_writes = #S.grid_leds
ok(idle_writes == 0, "an unchanged grid costs no led writes (" .. idle_writes .. ")")

press(2, 7)
S.grid_leds = {}
S.metros[1].event()
ok(#S.grid_leds > 0, "pressing a key makes the next refresh redraw")
lift(2, 7)
S.grid_leds = {}
S.metros[1].event()
ok(#S.grid_leds > 0, "and so does releasing it")
quiet()

params:set("key_root", 4)       -- changed from the PARAMS menu, not the grid
S.grid_leds = {}
S.metros[1].event()
ok(#S.grid_leds > 0, "changing the key from the menu redraws the grid too")
params:set("key_root", 1)
S.metros[1].event()

---------------------------------------------------------------- latch
section("latch")
quiet()
params:set("latch", 2)
clear()
tap(2, 8)                       -- press and release: should stay held
S.run_for(1)
ok(#sounding() > 0, "latched: a tapped chord keeps playing after the release")

S.grid_leds = {}
S.metros[1].event()
local latched_lit = false
for _, l in ipairs(S.grid_leds) do
  if l[1] == 2 and l[2] == 8 and l[3] >= 12 then latched_lit = true end
end
ok(latched_lit, "and its cell stays lit on the grid")

tap(2, 8)                       -- tapping again lets it go
S.run_for(3)
ok(#sounding() == 0, "latched: tapping the same cell again releases it")

tap(2, 8); tap(4, 8)
S.run_for(1)
ok(#sounding() > 0, "two chords latched")
params:set("latch", 1)          -- turning latch off must not strand them
S.run_for(3)
ok(#sounding() == 0, "turning latch off releases everything it was holding")
quiet()

---------------------------------------------------------------- keys / encoders
section("keys and encoders")
params:set("strum_mode", 2)
key(3, 1); key(3, 0)
ok(params:get("strum_mode") < 1.5, "K3 switches to one-shot")
key(3, 1); key(3, 0)
ok(params:get("strum_mode") > 1.5, "K3 switches back to cycle")

clear()
press(1, 8); S.run_for(0.5)
ok(#sounding() > 0, "something is ringing")
key(2, 1)
ok(#sounding() > 0, "K2 alone does nothing on the way down")
key(2, 0)
S.run_for(0.5)
ok(#sounding() == 0, "K2 panics on release")
lift(1, 8); quiet()

local bank_before = params:get("bank")
enc(1, 1)
ok(params:get("bank") ~= bank_before, "E1 changes bank")
local root_before = params:get("key_root")
enc(2, 1)
ok(params:get("key_root") ~= root_before, "E2 changes the key root")
local scale_before = params:get("scale_type")
enc(3, 1)
ok(params:get("scale_type") ~= scale_before, "E3 changes the scale")

-- hold K2 and turn E2: arc page, no panic, key root untouched
clear()
press(1, 8); S.run_for(0.4)
local root_held = params:get("key_root")
key(2, 1)
enc(2, 1)
ok(params:get("key_root") == root_held, "K2 + E2 pages the arc instead of changing key")
key(2, 0)
S.run_for(0.2)
ok(#sounding() > 0, "and skips the panic, because an encoder was turned")
lift(1, 8); quiet()

---------------------------------------------------------------- midi in
section("MIDI in")
local midi_dev = S.upvalue(init, "midi_in") or S.upvalue(redraw, "midi_in")
if midi_dev == nil then
  -- fall back: the script connected one, find it through the params action
  midi_dev = midi.connect(1)
end
ok(midi_dev ~= nil, "a MIDI in device is connected")

---------------------------------------------------------------- bass split
section("bass split")
quiet()
params:set("bass_channel", 2)
params:set("bass_octave", -1)
clear()
press(1, 8)
S.run_for(0.5)
local notes_now, chans = sounding()
local bass_count, chord_count = 0, 0
for _, ch in pairs(chans) do
  if ch == 2 then bass_count = bass_count + 1 else chord_count = chord_count + 1 end
end
ok(bass_count == 1, "exactly one note goes out on the bass channel")
ok(chord_count >= 2, "the rest stay on the chord channel")
lift(1, 8)
S.run_for(2)
ok(#sounding() == 0, "the bass note gets its own note-off")
params:set("bass_channel", 0)
quiet()

---------------------------------------------------------------- voice leading
section("voice leading")
local function spread_of(notes)
  local lo, hi = math.huge, -math.huge
  for _, n in ipairs(notes) do lo, hi = math.min(lo, n), math.max(hi, n) end
  return lo, hi
end
local function play_progression(lead_on)
  quiet()
  params:set("voice_lead", lead_on and 2 or 1)
  params:set("bank", 4)
  local jumps, prev = 0, nil
  for _, col in ipairs({1, 4, 5, 6, 2, 5, 1}) do
    clear()
    press(col, 8)
    S.run_for(0.4)
    local notes = sounding()
    if prev and #notes > 0 then
      local lo1, hi1 = spread_of(prev)
      local lo2, hi2 = spread_of(notes)
      jumps = jumps + math.abs(lo2 - lo1) + math.abs(hi2 - hi1)
    end
    if #notes > 0 then prev = notes end
    lift(col, 8)
    S.run_for(0.6)
  end
  return jumps
end
local without = play_progression(false)
local with = play_progression(true)
ok(with < without,
   string.format("voice leading moves the chord around less (%d vs %d semitones)",
                 with, without))
quiet()

---------------------------------------------------------------- redraw
section("redraw")
try("redraw() with nothing held", redraw)
press(1, 8)
S.run_for(0.3)
try("redraw() while playing", redraw)
params:set("latch", 2)
try("redraw() while latched", redraw)
params:set("latch", 1)
lift(1, 8)
quiet()
S.arc_leds = {}
local garc = S.upvalue(key, "garc_")
if garc then
  try("arc redraws on every page", function()
    for _ = 1, 6 do garc:cycle_page() end
  end)
  ok(#S.arc_leds > 0, "the arc lights up (" .. #S.arc_leds .. " led writes)")
end

---------------------------------------------------------------- string view
section("string view")
quiet()
params:set("visual", 1)
params:set("strum_mode", 1)     -- one-shot, so strings are left to settle

local function draw_and_count()
  S.lines, S.moves = 0, {}
  redraw()
  return S.lines, S.moves
end

clear()
press(1, 8)
S.run_for(0.2)
local ringing_lines = draw_and_count()
ok(ringing_lines > 20, "a ringing chord draws rippling strings (" .. ringing_lines .. " segments)")

S.run_for(2)                    -- past the decay: strings settle
local resting_lines = draw_and_count()
ok(resting_lines < ringing_lines,
   "settled strings cost far less to draw (" .. resting_lines .. " vs " .. ringing_lines .. ")")

-- strings start at x=0 within their band; the footer also moves to x=0 but
-- sits below it, so the band bounds keep it out of the count
local function string_starts(moves)
  local out = {}
  for _, m in ipairs(moves) do
    if m.x == 0 and m.y > 25 and m.y < 60 then out[#out + 1] = m.y end
  end
  return out
end

-- lowest note at the bottom, like strings on a chart. measured while they're
-- settled, so displacement can't blur the spacing.
local _, moves = draw_and_count()
local string_tops = string_starts(moves)
local descending = #string_tops >= 2
for i = 2, #string_tops do
  if string_tops[i] >= string_tops[i - 1] then descending = false end
end
ok(descending, "strings stack upward from the lowest note (" .. #string_tops .. " strings)")

-- a big merged pool must not draw more strings than there is room for
press(3, 8); press(5, 4)
S.run_for(0.3)
local _, big_moves = draw_and_count()
local big_strings = #string_starts(big_moves)
ok(big_strings <= 6 and big_strings > 0,
   "a large chord is capped at 6 strings (" .. big_strings .. ")")
lift(1, 8); lift(3, 8); lift(5, 4)
quiet()

params:set("visual", 2)
clear(); press(1, 8); S.run_for(0.2)
try("dots visual draws", redraw)
lift(1, 8); quiet()

params:set("visual", 3)
clear(); press(1, 8); S.run_for(0.2)
local off_lines = draw_and_count()
ok(off_lines == 0, "visual off draws no strings at all")
lift(1, 8)
params:set("visual", 1)
params:set("strum_mode", 2)
quiet()

---------------------------------------------------------------- output
section("output target")
quiet()
local function jf_plays()
  local n = 0
  for _, c in ipairs(S.crow_sent) do if c.fn == "jf.play_voice" then n = n + 1 end end
  return n
end

params:set("target", 1)         -- midi
clear(); S.crow_sent = {}
press(1, 8); S.run_for(0.4)
ok(#sounding() > 0 and jf_plays() == 0, "midi: notes go out over MIDI, crow is untouched")
lift(1, 8); quiet()

params:set("target", 2)         -- just friends
clear(); S.crow_sent = {}
press(1, 8); S.run_for(0.4)
local midi_on = 0
for _, e in ipairs(S.midi_sent) do if e.t == "on" then midi_on = midi_on + 1 end end
ok(jf_plays() > 0, "just friends: the chord is played on JF voices (" .. jf_plays() .. ")")
ok(midi_on == 0, "and nothing goes out over MIDI")
lift(1, 8); quiet()

params:set("target", 3)         -- both
clear(); S.crow_sent = {}
press(1, 8); S.run_for(0.4)
midi_on = 0
for _, e in ipairs(S.midi_sent) do if e.t == "on" then midi_on = midi_on + 1 end end
ok(jf_plays() > 0 and midi_on > 0, "midi + jf: the chord goes to both at once")
lift(1, 8); quiet()

-- a chord bigger than JF's six voices still plays
params:set("target", 2)
params:set("bank", 13)          -- clusters, and two cells for a big pool
clear(); S.crow_sent = {}
press(1, 8); press(4, 4)
S.run_for(0.5)
ok(jf_plays() > 0, "a pool larger than six voices still sounds")
lift(1, 8); lift(4, 4); quiet()
params:set("bank", 4)

params:set("target", 1)
S.crow_sent = {}
params:set("target", 2)
local handed_over = false
for _, c in ipairs(S.crow_sent) do
  if c.fn == "jf.mode" and c.args[1] == 1 then handed_over = true end
end
ok(handed_over, "selecting JF hands it over to ii control")
params:set("target", 3)         -- leave both on, so cleanup below sees MIDI too
quiet()

---------------------------------------------------------------- cleanup
section("cleanup")
clear()
press(1, 8); press(3, 8)
S.run_for(0.4)
ok(#sounding() > 0, "chords ringing before cleanup")
S.crow_sent = {}
try("cleanup() runs clean", cleanup)
S.run_for(1)
ok(#sounding() == 0, "cleanup silences everything")
local gave_back = false
for _, c in ipairs(S.crow_sent) do
  if c.fn == "jf.mode" and c.args[1] == 0 then gave_back = true end
end
ok(gave_back, "and hands Just Friends back, rather than leaving it in ii mode")

---------------------------------------------------------------- done
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
