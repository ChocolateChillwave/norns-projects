-- cascade
-- v0.9.0
-- strummed chord instrument: MIDI,
-- or Just Friends via crow
-- see MANUAL.md for full documentation
--
-- hold a grid cell (or an external MIDI
-- note) and the chord under it strums.
-- hold several and they merge: one
-- strum runs over all their notes
-- together, like an arpeggiator. let
-- go and a chord's notes ring out for
-- the release time instead of cutting.
--
-- in cycle mode the strum repeats while
-- held. patterns can hold, advance,
-- alternate or randomize between
-- repeats, and morph blends one pattern
-- into the next over several repeats.
--
-- grid (left 8x8):
--   columns = 8 scale steps up from the
--     key root. accidentals (black keys)
--     sit at a brighter resting level.
--   rows 5-8 = lower octave,
--   rows 1-4 = upper octave.
--   within each group of 4, the bottom
--     row is the most compact voicing of
--     the current bank and the top row
--     the widest.
--   right half is dark -- reserved for a
--     sequencer later.
--
-- arc (its own button, or hold K2 and
--   turn E2, changes page):
--   STRUM   rate / pattern / cycle / mode
--   MOTION  pattern cycle / every /
--           morph / drift
--   FEEL    tilt / humanize / probability
--           / velocity
--   VOICE   note length / release /
--           density / upstroke
--   CHORD   bank / invert / octave /
--           transpose
--
-- strum rate and cycle rate each run
-- free (ms) or locked to the norns clock,
-- so both follow PARAMETERS > CLOCK,
-- Ableton Link included. "fit to repeat"
-- instead sizes the strum to span a set
-- fraction of each repeat, whatever the
-- note count.
--
-- upstrokes are detected from the pattern
-- itself (highest note first) and can be
-- played quieter and on fewer notes, like
-- a real pick. off by default.
--
-- in PARAMETERS: send to picks midi,
-- just friends (six voices over crow's
-- ii bus) or both; latch keeps chords
-- playing after you let go (tap again to
-- drop one, K2 clears all); voice lead
-- places each chord near the one before
-- it; bass channel splits the lowest note
-- out to its own MIDI channel; visual
-- picks strings / dots / off.
--
-- the screen draws the strum as vibrating
-- strings, with the rolling-shutter
-- wobble a phone camera gives real ones.
--
-- K2: panic (notes off), on release
-- K3: one-shot / cycle
-- hold K2 + turn E2: arc page
--   (panic is skipped if E2 was turned)
-- E1: bank  E2: key root  E3: scale

local MusicUtil = require "musicutil"
local Chords = include("cascade/lib/chords")
local Patterns = include("cascade/lib/patterns")
local Strum = include("cascade/lib/strum")
local Display = include("cascade/lib/display")
local Output = include("cascade/lib/output")
local GridKeys = include("cascade/lib/gridkeys")
local GArc = include("cascade/lib/garc")

-- ============================================================
-- static data
-- ============================================================

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local ACCIDENTALS = {[1] = true, [3] = true, [6] = true, [8] = true, [10] = true}

local SCALE_NAMES = {}
for i = 1, #MusicUtil.SCALES do
  table.insert(SCALE_NAMES, MusicUtil.SCALES[i].name)
end

local BANK_NAMES = Chords.bank_names()

local ONOFF_NAMES = {"off", "on"}
local MODE_NAMES = {"one-shot", "cycle"}
local RETRIGGER_NAMES = {"strum now", "next repeat"}
local VISUAL_NAMES = {"strings", "dots", "off"}
local TARGET_NAMES = {"midi", "just friends", "midi + jf"}
local JF_NOTE_NAMES = {"pluck", "sustain"}

-- strum spacing has its own division list, separate from the cycle repeat
-- rate below. it reaches well past a real strum at the slow end -- a 1/4
-- gap between notes is an arpeggio, not a strum -- because that turned out
-- to be a useful place to go, and the fast end is where an actual strum
-- lives.
local STRUM_DIV_NAMES = {"1/2", "1/4", "1/8", "1/16", "1/32", "1/64", "1/128"}
local STRUM_DIV_BEATS = {2, 1, 0.5, 0.25, 0.125, 0.0625, 0.03125}

local CYCLE_DIV_NAMES = {"1/1", "1/2", "1/4", "1/8", "1/16"}
local CYCLE_DIV_BEATS = {4, 2, 1, 0.5, 0.25}

local NOTE_POOL_SIZE = 48   -- roots reach ~2 octaves up, voicings another ~2
-- the widest voicing's reach above its root: an incoming MIDI note is kept
-- at least this far below the top of the pool so its chord comes out whole
local ROOT_INDEX_HEADROOM = Chords.max_degree()
local FPS = 15

-- ============================================================
-- runtime state
-- ============================================================

local scale_full = {}
local notes_per_octave = 7
local midi_device_options = {}
local chord_midi = nil
local midi_in = nil

local strum_ = nil
local output_ = nil
local gridkeys_ = nil
local garc_ = nil
local ui_running = false

local last_voicing = 1      -- MIDI-in follows whichever row you last played
local last_voiced = nil     -- notes of the last chord, for voice leading
local held_labels = {}      -- key -> {name, order}
local press_order = 0
local last_chord_label = "--"

-- ============================================================
-- scale / grid mapping
-- ============================================================

local function is_chromatic()
  return string.lower(SCALE_NAMES[util.round(params:get("scale_type"))] or "") == "chromatic"
end

local function refresh_scale()
  local pc = util.round(params:get("key_root")) - 1
  local octave = util.round(params:get("base_octave"))
  local base = (octave + 1) * 12 + pc
  scale_full = MusicUtil.generate_scale_of_length(
    base, util.round(params:get("scale_type")), NOTE_POOL_SIZE) or {}

  -- how far up the pool one octave actually is, so the grid's two row
  -- groups stay an octave apart in any scale (5 for pentatonic, 7 for a
  -- diatonic scale, 12 for chromatic) instead of assuming 7
  notes_per_octave = 7
  for i = 2, #scale_full do
    if scale_full[i] >= base + 12 then
      notes_per_octave = i - 1
      break
    end
  end
end

-- rows 1-4 are the upper octave group, 5-8 the lower. within a group the
-- bottom row is voicing 1 (most compact), counting up to 4 (widest).
local function cell_octave_group(y) return (y <= 4) and 1 or 0 end
local function cell_voicing(y) return (y <= 4) and (5 - y) or (9 - y) end

local function cell_root_index(x, y)
  return (x - 1) + cell_octave_group(y) * notes_per_octave + 1
end

local function nearest_scale_index(note)
  local best, best_dist = 1, math.huge
  for i, n in ipairs(scale_full) do
    local d = math.abs(n - note)
    if d < best_dist then best, best_dist = i, d end
  end
  return util.clamp(best, 1, math.max(#scale_full - ROOT_INDEX_HEADROOM, 1))
end

-- returns a function rather than a note list: the strummer calls it again
-- on every pass, so changing bank/inversion/transpose while holding a chord
-- re-voices it on the next pass instead of waiting for a re-press. second
-- return is the chord's true root, which inversion may have moved out of
-- the bass -- naming needs it, the strummer ignores it.
-- `lead` is the voice-leading placement decided once when the chord was
-- pressed, as {inv, oct}: an offset on top of the invert param, per the
-- decision that invert stays live rather than being disabled. keeping it
-- fixed for the life of the press means the chord doesn't re-lead itself
-- every repeat and wander.
local function chord_source(root_index, voicing_idx, lead)
  return function()
    local voicing = Chords.voicing(util.round(params:get("bank")), voicing_idx)
    local notes = Chords.build(scale_full, root_index, voicing.deg, is_chromatic())
    notes = Chords.invert(notes, util.round(params:get("invert")) + (lead and lead.inv or 0))

    local root = scale_full[root_index]
    local shift = util.round(params:get("transpose")) + (lead and lead.oct or 0) * 12
    if shift ~= 0 then
      for i, n in ipairs(notes) do notes[i] = util.clamp(n + shift, 0, 127) end
      if root then root = util.clamp(root + shift, 0, 127) end
    end
    return notes, root
  end
end

local function press(key, root_index, voicing_idx)
  -- latched: pressing a chord that's already held is how you let it go
  if params:get("latch") > 1.5 and held_labels[key] then
    held_labels[key] = nil
    strum_:remove(key)
    return
  end

  local lead = nil
  if params:get("voice_lead") > 1.5 then
    local plain = chord_source(root_index, voicing_idx, nil)()
    -- lead from what's actually ringing; if nothing is, from the last chord
    -- played, so a series of separate stabs still moves smoothly
    local reference = strum_:sounding_notes()
    if #reference == 0 then reference = last_voiced end
    if reference and #reference > 0 then
      local inv, oct = Chords.lead(plain, reference)
      lead = {inv = inv, oct = oct}
    end
  end

  local source = chord_source(root_index, voicing_idx, lead)
  local notes, root = source()
  if #notes == 0 then return end
  last_voiced = notes

  press_order = press_order + 1
  local name = Chords.name(root or notes[1], notes, NOTE_NAMES)
  held_labels[key] = {name = name, order = press_order}
  last_chord_label = name

  strum_:add(key, source)
end

local function release(key)
  -- when latched, letting go of the key changes nothing
  if params:get("latch") > 1.5 then return end
  held_labels[key] = nil
  strum_:remove(key)
end

local function release_all()
  for key in pairs(held_labels) do
    held_labels[key] = nil
    strum_:remove(key)
  end
end

-- ============================================================
-- strum settings, re-read at the start of every pass
-- ============================================================

local function strum_opts()
  local gap
  if params:get("strum_sync") > 1.5 then
    gap = STRUM_DIV_BEATS[util.round(params:get("strum_div"))] * clock.get_beat_sec()
  else
    gap = params:get("strum_ms") / 1000
  end

  -- how long one repeat lasts: note length is a percentage of this, and
  -- "fit" scales the strum to span a fraction of it. defined by the cycle
  -- settings even in one-shot, so note length still means something there.
  local repeat_sec
  if params:get("cycle_sync") > 1.5 then
    repeat_sec = CYCLE_DIV_BEATS[util.round(params:get("cycle_div"))] * clock.get_beat_sec()
  else
    repeat_sec = params:get("cycle_ms") / 1000
  end

  return {
    device = output_,
    channel = util.round(params:get("chord_out_channel")),
    gap = gap,
    cycle = params:get("strum_mode") > 1.5,
    cycle_sync = params:get("cycle_sync") > 1.5,
    cycle_beats = CYCLE_DIV_BEATS[util.round(params:get("cycle_div"))],
    cycle_sec = params:get("cycle_ms") / 1000,
    retrigger_now = params:get("retrigger") < 1.5,
    release_sec = params:get("release") / 1000,
    bass_channel = (params:get("bass_channel") >= 0.5)
      and util.round(params:get("bass_channel")) or nil,
    bass_shift = util.round(params:get("bass_octave")) * 12,
    repeat_sec = repeat_sec,
    gate_sec = (params:get("note_length") / 100) * repeat_sec,
    fit = params:get("strum_fit") > 1.5,
    span = params:get("strum_span") / 100,
    velocity = params:get("velocity"),
    tilt = params:get("tilt") / 100,
    humanize = params:get("humanize") / 100,
    drift = params:get("drift") / 100,
    density = params:get("density") / 100,
    probability = params:get("probability") / 100,
    upstroke_level = params:get("upstroke_level") / 100,
    upstroke_keep = params:get("upstroke_notes") / 100,
    pattern = {
      pattern = util.round(params:get("pattern")),
      mode = util.round(params:get("pattern_cycle")),
      every = util.round(params:get("pattern_every")),
      morph = util.round(params:get("pattern_morph")),
    },
  }
end

-- ============================================================
-- MIDI
-- ============================================================

local function build_device_options()
  midi_device_options = {}
  for i = 1, #midi.vports do
    table.insert(midi_device_options, i .. ": " .. (midi.vports[i].name or "none"))
  end
end

-- one object stands in for wherever notes go, so the strum engine only ever
-- holds "a device" -- see lib/output.lua
local function refresh_output()
  if output_ == nil then return end
  chord_midi = midi.connect(params:get("chord_out_device"))
  local target = util.round(params:get("target"))
  output_:configure{
    midi = (target == 1 or target == 3),
    jf = (target == 2 or target == 3),
    device = chord_midi,
    jf_sustain = params:get("jf_note") > 1.5,
    jf_level = params:get("jf_level"),
  }
end

local function refresh_midi_in()
  midi_in = midi.connect(params:get("midi_in_device"))
  midi_in.event = function(data)
    local msg = midi.to_msg(data)
    if msg.type == "note_on" and msg.vel and msg.vel > 0 then
      -- in chromatic the pool holds every semitone, so "nearest" lands on
      -- the played note exactly; in any other scale this is the snap
      press("midi:" .. msg.note, nearest_scale_index(msg.note), last_voicing)
    elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
      release("midi:" .. msg.note)
    end
  end
end

-- ============================================================
-- params
-- ============================================================

local function add_control(id, name, min, max, default, formatter, units)
  params:add{
    type = "control",
    id = id,
    name = name,
    controlspec = controlspec.new(min, max, "lin", 1, default, units or "",
                                  1 / math.max(max - min, 1)),
    formatter = formatter,
  }
end

local function name_formatter(names)
  return function(param) return names[util.round(param:get())] or "?" end
end

local function unit_formatter(suffix)
  return function(param) return string.format("%d%s", util.round(param:get()), suffix) end
end

local function init_params()
  build_device_options()

  params:add_group("OUTPUT", 7)
  add_control("target", "send to", 1, #TARGET_NAMES, 1, name_formatter(TARGET_NAMES))
  params:set_action("target", function() refresh_output() end)
  params:add_option("chord_out_device", "midi device", midi_device_options, 1)
  params:set_action("chord_out_device", function() refresh_output() end)
  params:add_number("chord_out_channel", "midi channel", 1, 16, 1)
  add_control("bass_channel", "bass channel", 0, 16, 0,
    function(param)
      local n = util.round(param:get())
      return n == 0 and "off" or ("ch " .. n)
    end)
  add_control("bass_octave", "bass octave", -2, 1, 0,
    function(param) return string.format("%+d", util.round(param:get())) end)
  -- Just Friends: pluck lets JF's own envelope end the note, sustain holds
  -- it until cascade says otherwise
  add_control("jf_note", "jf note", 1, 2, 1, name_formatter(JF_NOTE_NAMES))
  params:set_action("jf_note", function() refresh_output() end)
  add_control("jf_level", "jf level", 1, 10, 5,
    function(param) return string.format("%d V", util.round(param:get())) end)
  params:set_action("jf_level", function() refresh_output() end)

  params:add_group("MIDI IN", 1)
  params:add_option("midi_in_device", "device", midi_device_options, 1)
  params:set_action("midi_in_device", function() refresh_midi_in() end)

  params:add_group("DISPLAY", 1)
  add_control("visual", "visual", 1, 3, 1, name_formatter(VISUAL_NAMES))

  params:add_group("ARC", 4)
  params:add_number("arc_threshold", "sensitivity", 1, 64, 24)
  params:add_number("arc_brightness", "brightness", 1, 15, 15)
  params:add_number("arc_dim", "dim level", 1, 15, 4)
  params:add_number("arc_position", "position", 1, 4, 1)

  params:add_group("KEY", 4)
  add_control("key_root", "root", 1, 12, 1, name_formatter(NOTE_NAMES))
  params:set_action("key_root", function() refresh_scale() end)
  add_control("scale_type", "scale", 1, #SCALE_NAMES, 1, name_formatter(SCALE_NAMES))
  params:set_action("scale_type", function() refresh_scale() end)
  add_control("base_octave", "octave", 1, 6, 3)
  params:set_action("base_octave", function() refresh_scale() end)
  add_control("transpose", "transpose", -24, 24, 0,
    function(param) return string.format("%+d st", util.round(param:get())) end)

  params:add_group("CHORD", 4)
  add_control("bank", "bank", 1, #BANK_NAMES, 4, name_formatter(BANK_NAMES))
  add_control("invert", "invert", -4, 4, 0,
    function(param) return string.format("%d", util.round(param:get())) end)
  add_control("velocity", "velocity", 1, 127, 100)
  add_control("voice_lead", "voice lead", 1, 2, 1, name_formatter(ONOFF_NAMES))

  params:add_group("STRUM", 11)
  add_control("strum_mode", "mode", 1, 2, 2, name_formatter(MODE_NAMES))
  add_control("latch", "latch", 1, 2, 1, name_formatter(ONOFF_NAMES))
  -- turning latch off has to let go of whatever it was holding, since
  -- nothing is physically pressed any more
  params:set_action("latch", function(v) if v < 1.5 then release_all() end end)
  add_control("strum_sync", "strum sync", 1, 2, 1, name_formatter(ONOFF_NAMES))
  add_control("strum_ms", "strum rate", 0, 200, 25, unit_formatter(" ms"))
  add_control("strum_div", "strum div", 1, #STRUM_DIV_NAMES, 6,
    name_formatter(STRUM_DIV_NAMES))
  add_control("strum_fit", "fit to repeat", 1, 2, 1, name_formatter(ONOFF_NAMES))
  add_control("strum_span", "strum span", 5, 100, 50, unit_formatter("%"))
  add_control("cycle_sync", "cycle sync", 1, 2, 2, name_formatter(ONOFF_NAMES))
  add_control("cycle_ms", "cycle rate", 50, 2000, 500, unit_formatter(" ms"))
  add_control("cycle_div", "cycle div", 1, #CYCLE_DIV_NAMES, 3,
    name_formatter(CYCLE_DIV_NAMES))
  add_control("retrigger", "new chord", 1, 2, 1, name_formatter(RETRIGGER_NAMES))

  params:add_group("PATTERN", 4)
  add_control("pattern", "pattern", 1, #Patterns.NAMES, 1, name_formatter(Patterns.NAMES))
  add_control("pattern_cycle", "cycle", 1, #Patterns.CYCLE_NAMES, 1,
    name_formatter(Patterns.CYCLE_NAMES))
  add_control("pattern_every", "every", 1, 16, 2,
    function(param)
      local n = util.round(param:get())
      return n == 1 and "1 repeat" or (n .. " repeats")
    end)
  add_control("pattern_morph", "morph", 0, 8, 1,
    function(param)
      local n = util.round(param:get())
      return n == 0 and "instant" or (n .. " repeats")
    end)

  params:add_group("FEEL", 5)
  add_control("tilt", "tilt", -100, 100, 0, unit_formatter("%"))
  add_control("humanize", "humanize", 0, 100, 15, unit_formatter("%"))
  add_control("drift", "drift", 0, 100, 10, unit_formatter("%"))
  add_control("density", "density", 10, 100, 100, unit_formatter("%"))
  add_control("probability", "probability", 0, 100, 100, unit_formatter("%"))

  params:add_group("ARTICULATION", 4)
  add_control("note_length", "note length", 0, 100, 0,
    function(param)
      local n = util.round(param:get())
      return n == 0 and "let ring" or (n .. "% of repeat")
    end)
  add_control("release", "release", 0, 2000, 300, unit_formatter(" ms"))
  add_control("upstroke_level", "upstroke level", 10, 100, 100, unit_formatter("%"))
  add_control("upstroke_notes", "upstroke notes", 10, 100, 100, unit_formatter("%"))
end

-- ============================================================
-- arc
-- ============================================================

-- the rate rings retarget themselves depending on whether that rate is
-- currently synced, so one ring covers both the ms and the division param
-- without needing a page for each -- garc.lua resolves a ring's `id` every
-- time it touches it, which is what makes this work
local ARC_PAGES = {
  {
    name = "STRUM",
    rings = {
      -- one ring for "how wide is the strum", whichever way it's being set
      {label = "rate", id = function()
        if params:get("strum_fit") > 1.5 then return "strum_span" end
        return params:get("strum_sync") > 1.5 and "strum_div" or "strum_ms"
      end},
      {label = "pattern", id = "pattern"},
      {label = "cycle", id = function()
        return params:get("cycle_sync") > 1.5 and "cycle_div" or "cycle_ms"
      end},
      {label = "mode", id = "strum_mode"},
    },
  },
  {
    name = "MOTION",
    rings = {
      {label = "cycle", id = "pattern_cycle"},
      {label = "every", id = "pattern_every"},
      {label = "morph", id = "pattern_morph"},
      {label = "drift", id = "drift"},
    },
  },
  {
    name = "FEEL",
    rings = {
      -- tilt runs -100..100, so it gets the centred rendering: a plain fill
      -- would show "slightly negative" as most of a lit ring
      {label = "tilt", id = "tilt", style = "bipolar", track = true},
      {label = "human", id = "humanize"},
      {label = "prob", id = "probability"},
      {label = "vel", id = "velocity"},
    },
  },
  {
    name = "VOICE",
    rings = {
      {label = "length", id = "note_length"},
      {label = "release", id = "release"},
      {label = "density", id = "density"},
      {label = "upstroke", id = "upstroke_level"},
    },
  },
  {
    name = "CHORD",
    rings = {
      {label = "bank", id = "bank"},
      {label = "invert", id = "invert"},
      {label = "octave", id = "base_octave"},
      {label = "transp", id = "transpose", style = "bipolar", track = true},
    },
  },
}

-- ============================================================
-- screen
-- ============================================================

-- the most recently pressed held chord, plus how many others are merged
-- into the strum with it; the last chord played if nothing is held
local function chord_label()
  local latest, count = nil, 0
  for _, h in pairs(held_labels) do
    count = count + 1
    if latest == nil or h.order > latest.order then latest = h end
  end
  if latest == nil then return last_chord_label end
  if count > 1 then return latest.name .. " +" .. (count - 1) end
  return latest.name
end

function redraw()
  screen.clear()

  screen.level(15)
  screen.font_size(8)
  screen.move(0, 7)
  screen.text(NOTE_NAMES[util.round(params:get("key_root"))] .. " " ..
              SCALE_NAMES[util.round(params:get("scale_type"))])
  screen.move(127, 7)
  screen.text_right(params:string("strum_mode"))

  screen.font_size(16)
  screen.move(64, 24)
  screen.text_center(chord_label())
  screen.font_size(8)

  local visual = util.round(params:get("visual"))
  local pool = strum_ and strum_.last_pool or nil
  if visual == 1 then
    Display.draw(pool, util.time())
  elseif visual == 2 then
    Display.draw_dots(pool, util.time())
  end

  local footer = garc_ and garc_:footer_text()
  if footer then
    screen.level(8)
    screen.move(0, 62)
    screen.text(footer)
  end

  screen.update()
end

-- ============================================================
-- encoders / keys
-- ============================================================

-- no K1: norns takes K1 for its system menu, so a script never gets it.
-- arc pages are cycled by the arc's own button (wired inside garc.lua), or
-- by holding K2 and turning E2, for arcs without one.
--
-- K2's panic fires on RELEASE, and only if no encoder was turned during the
-- hold -- acting on press would panic every time you reached for a page.
local k2_down = false
local k2_turned = false

-- garc.lua only steps forward; going back one page is stepping forward
-- all the way round, which keeps garc.lua an unmodified copy
local function step_arc_page(d)
  local steps = (d > 0) and 1 or (#ARC_PAGES - 1)
  for _ = 1, steps do garc_:cycle_page() end
end

function enc(n, d)
  -- any turn during a K2 hold means it wasn't a tap, so no panic on release
  if k2_down then k2_turned = true end
  if n == 2 and k2_down then
    step_arc_page(d)
    return
  end

  if n == 1 then
    params:delta("bank", d)
  elseif n == 2 then
    params:delta("key_root", d)
  elseif n == 3 then
    params:delta("scale_type", d)
  end
  if garc_ then garc_:redraw() end
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      k2_down = true
      k2_turned = false
    else
      k2_down = false
      if not k2_turned then
        held_labels = {}
        strum_:panic(output_)
      end
    end
  elseif n == 3 and z == 1 then
    params:set("strum_mode", params:get("strum_mode") > 1.5 and 1 or 2)
    if garc_ then garc_:redraw() end
  end
end

-- ============================================================
-- lifecycle
-- ============================================================

function init()
  math.randomseed(os.time())
  init_params()
  output_ = Output.new()
  refresh_output()
  refresh_midi_in()
  refresh_scale()

  Display.init()

  strum_ = Strum.new{
    opts = strum_opts,
    cycler = Patterns.cycler(),
    on_strike = function(note, velocity) Display.strike(note, velocity) end,
  }

  gridkeys_ = GridKeys:new{
    cols = 8,
    rows = 8,
    on_press = function(x, y)
      last_voicing = cell_voicing(y)
      press("grid:" .. x .. "," .. y, cell_root_index(x, y), last_voicing)
    end,
    on_release = function(x, y)
      release("grid:" .. x .. "," .. y)
    end,
    level_fn = function(x, y)
      -- a latched chord stays lit even though nothing is pressed, just
      -- below the full brightness of a key actually under a finger
      if held_labels["grid:" .. x .. "," .. y] then return 12 end
      local note = scale_full[cell_root_index(x, y)]
      if note == nil then return 0 end
      return ACCIDENTALS[note % 12] and 6 or 2
    end,
  }

  garc_ = GArc:new{
    pages = ARC_PAGES,
    threshold_id = "arc_threshold",
    bright_id = "arc_brightness",
    dim_id = "arc_dim",
    position_id = "arc_position",
  }

  params:bang()
  garc_:redraw()

  -- screen refresh runs on its own clock rather than being poked by every
  -- event -- the arc's own handler only redraws the arc's LEDs, so without
  -- this the on-screen readout sat stale while a ring was being turned.
  -- it retires on a flag rather than being cancelled, for the same reason
  -- the strum engine does (see lib/strum.lua).
  ui_running = true
  clock.run(function()
    while ui_running do
      clock.sleep(1 / FPS)
      redraw()
      -- keeps the rings showing the real values when something else moves
      -- them (PARAMS menu, pset load, an encoder); only redraws on a change
      if garc_ then garc_:poll() end
    end
  end)
end

function cleanup()
  ui_running = false
  if strum_ then strum_:panic(output_) end
  if output_ then output_:shutdown() end
end
