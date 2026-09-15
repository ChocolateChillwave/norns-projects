-- chordflow
-- v0.1.0 (first pass, untested on hw)
-- a MIDI chord sequencer
--
-- sends chords out one MIDI channel
-- and an accompaniment (bass/lead)
-- voice out a second. clockable
-- internally, via MIDI, or Ableton
-- Link.
--
-- each flower's chord is built from
-- a named type (maj/min/dim/aug/sus/
-- 7ths/9ths/11ths...), not just a
-- stacked-thirds count — but only
-- types that are actually diatonic to
-- the current key/scale/degree are
-- selectable (unless scale is set to
-- chromatic), so randomizing chord
-- type can't land on something out
-- of key.
--
-- E2: move selection between flowers
-- E3: change degree of selected flower
-- K1: cycle arc page (also works on
--     the arc's own button, if it has one)
-- K2: play / stop
-- K3: tap = randomize progression only
--     hold ~0.5s = randomize everything
--
-- the screen shows a small flower: one
-- bitmap petal per flower 1-8, fanned
-- radially (current one ringed at the
-- tip, selected one ringed at the
-- base if different). rest flowers
-- show as a small hollow circle
-- instead of a petal. center dot is
-- filled/bright while playing, hollow
-- while stopped.
--
-- grid: cols 1-8, rows 1-7 = flower x
--   degree (vii at top, I just above
--   row 8). tap a cell to set that
--   flower's degree; tap the lit cell
--   again to clear it to rest.
--   row 8 = selection row: tap a
--   column to select that flower for
--   arc/E2/E3 editing. sequence length
--   is set separately, in PARAMETERS >
--   GROWTH > growth.
--
-- arc is a paged 4-knob editor for the
-- global dials (play/stop and randomize
-- live on K2/K3 only, not the grid).
-- page persists while you change which
-- flower is selected. labels are kept
-- plain/technical for now rather than
-- whimsical, so it's clear what's
-- actually changing:
--   CHORD (per-step): type/inv/oct/vel
--   STRUM: ms, sync, sync div, gate %
--   ACCOMP: pattern/density/oct/gate
--   SCALE: key/scale/oct/step div
-- (CHORD is per-step — it edits
-- whichever flower is selected; the
-- other three pages are still global)
--
-- arc sensitivity (PARAMETERS > ARC) is
-- a live-tunable threshold for how much
-- raw motion it takes to register one
-- step; the ring's on-screen position
-- still tracks your hand continuously
-- in between, so low-option params
-- (like a 4-choice list) feel just as
-- smooth as high-range ones.
--
-- RANDOMIZE menu page has an "amount %"
-- dial (how much of the unlocked pool
-- rerolls per press) plus lock-all /
-- unlock-all triggers, so taming the
-- randomizer doesn't require locking
-- every parameter by hand. scale_type's
-- random pool is a curated, consonant
-- shortlist; manual selection still
-- sees every MusicUtil scale.
--
-- all params (incl. clock source and
-- MIDI routing) live in the norns
-- PARAMETERS menu.

local MusicUtil = require "musicutil"

-- ============================================================
-- static data
-- ============================================================

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

local DEGREE_OPTIONS = {"I","ii","iii","IV","V","vi","vii\u{B0}","rest"}
local NUM_STEPS_MAX = 8

local SCALE_NAMES = {}
for i = 1, #MusicUtil.SCALES do
  table.insert(SCALE_NAMES, MusicUtil.SCALES[i].name)
end

-- shortlist of scales used specifically when *randomizing* scale_type,
-- so the randomizer doesn't land on obscure/dissonant modes. manual
-- selection (E-knob, arc, menu) still sees the full MusicUtil.SCALES
-- list — this only narrows the random pool.
local CONSONANT_SCALE_NAMES = {
  "major", "natural minor", "dorian", "mixolydian", "lydian",
  "harmonic minor", "major pentatonic", "minor pentatonic"
}
local CONSONANT_SCALE_INDICES = {}
for _, wanted in ipairs(CONSONANT_SCALE_NAMES) do
  for i, name in ipairs(SCALE_NAMES) do
    if string.lower(name) == wanted then
      table.insert(CONSONANT_SCALE_INDICES, i)
      break
    end
  end
end
-- fallback: if none of the curated names matched this MusicUtil
-- version's naming, don't leave the pool empty — just use everything.
if #CONSONANT_SCALE_INDICES == 0 then
  for i = 1, #SCALE_NAMES do table.insert(CONSONANT_SCALE_INDICES, i) end
end

-- named chord types, each defined by its actual interval structure
-- (semitones from root) rather than by stacking N thirds — this is
-- what makes diminished/sus/11ths etc. directly selectable instead
-- of being an incidental consequence of degree+extension-count.
local CHORD_TYPES = {
  {name = "maj",     ivl = {0, 4, 7}},
  {name = "min",     ivl = {0, 3, 7}},
  {name = "dim",     ivl = {0, 3, 6}},
  {name = "aug",     ivl = {0, 4, 8}},
  {name = "sus2",    ivl = {0, 2, 7}},
  {name = "sus4",    ivl = {0, 5, 7}},
  {name = "maj7",    ivl = {0, 4, 7, 11}},
  {name = "min7",    ivl = {0, 3, 7, 10}},
  {name = "dom7",    ivl = {0, 4, 7, 10}},
  {name = "dim7",    ivl = {0, 3, 6, 9}},
  {name = "hdim7",   ivl = {0, 3, 6, 10}},
  {name = "minmaj7", ivl = {0, 3, 7, 11}},
  {name = "maj9",    ivl = {0, 4, 7, 11, 14}},
  {name = "min9",    ivl = {0, 3, 7, 10, 14}},
  {name = "dom9",    ivl = {0, 4, 7, 10, 14}},
  {name = "dom11",   ivl = {0, 4, 7, 10, 14, 17}},
  {name = "maj11",   ivl = {0, 4, 7, 11, 14, 17}},
  {name = "min11",   ivl = {0, 3, 7, 10, 14, 17}},
}

-- given a key root (0-11), scale name, and scale degree (1-7), return
-- the CHORD_TYPES indices that are fully diatonic to the scale at that
-- degree — same constraint Tide uses, so randomizing chord type can't
-- land on something out of key. chromatic scale allows every type.
local function available_chord_types(key_root, scale_name, degree)
  if scale_name == "chromatic" then
    local all = {}
    for i = 1, #CHORD_TYPES do table.insert(all, i) end
    return all
  end

  local scale_notes = MusicUtil.generate_scale(key_root, scale_name, 2)
  if scale_notes == nil then
    local all = {}
    for i = 1, #CHORD_TYPES do table.insert(all, i) end
    return all
  end
  local in_scale = {}
  for _, n in ipairs(scale_notes) do in_scale[n % 12] = true end

  local degree_root = (scale_notes[degree] or key_root) % 12

  local available = {}
  for i, ct in ipairs(CHORD_TYPES) do
    local ok = true
    for _, ivl in ipairs(ct.ivl) do
      if not in_scale[(degree_root + ivl) % 12] then
        ok = false
        break
      end
    end
    if ok then table.insert(available, i) end
  end

  -- guard against an empty result on unusual scales
  if #available == 0 then table.insert(available, 1) end
  return available
end

-- step_div id -> length in "beats" (1 beat = 1 quarter note,
-- matching norns clock.sync() convention)
local DIVISION_NAMES = {"1/1", "1/2", "1/4", "1/8", "1/16"}
local DIVISION_BEATS = {4, 2, 1, 0.5, 0.25}

local ACCOMP_PATTERNS = {
  "root", "root+5th", "arp up", "arp down", "rand chord", "rand scale"
}

-- fine note divisions for clock-synced rustle (strum), separate from
-- DIVISION_NAMES since strumming a chord wants much finer spacing
-- than the step pulse itself.
local STRUM_DIVISION_NAMES = {"1/8", "1/16", "1/32", "1/64"}
local STRUM_DIVISION_BEATS = {0.5, 0.25, 0.125, 0.0625}

-- ============================================================
-- runtime state
-- ============================================================

local running = false
local seq_coro = nil
local current_step = 0        -- advances to 1 on first tick
local selected_step = 1       -- shared "editing target" for E2/E3, grid taps, arc
local current_chord_notes = {}
local current_scale_notes = {}
local last_chord_label = "--"

-- per-step overrides for chord arc page. nil = inherit global.
-- set to the current global value the first time the arc touches
-- a step, so the ring starts at the right position.
local step_inv  = {}   -- inversion  (0-3)
local step_gate = {}   -- gate %     (10-100)
local step_vel  = {}   -- velocity   (1-127)
local step_octave = {} -- octave override (1-6), nil = inherit global "height"
for i = 1, NUM_STEPS_MAX do
  step_inv[i]  = nil
  step_gate[i] = nil
  step_vel[i]  = nil
  step_octave[i] = nil
end

-- step_chord_type is always valued (no global "chord type" dial makes
-- sense, since availability depends on that step's own degree) — it's
-- an index into THAT step's avail_types list, not into CHORD_TYPES
-- directly. avail_types[i] is recomputed whenever key/scale/that
-- step's degree changes (see refresh_available_types below).
local step_chord_type = {}
local avail_types = {}
for i = 1, NUM_STEPS_MAX do
  step_chord_type[i] = 1
  avail_types[i] = {1}
end

-- convenience: read effective value for a step, falling back to global
local function eff_inv(i)  return step_inv[i]  or params:get("inversion") end
local function eff_gate(i) return step_gate[i] or params:get("chord_gate") end
local function eff_vel(i)  return step_vel[i]  or params:get("chord_velocity") end
local function eff_octave(i) return step_octave[i] or params:get("root_octave") end

-- recompute which chord types are available for a step, based on its
-- own degree (called on key/scale change for all steps, and on that
-- step's own degree change). clamps step_chord_type to stay valid.
local function refresh_available_types(step_i)
  local degree = params:get("step" .. step_i .. "_degree")
  if degree == 8 then
    avail_types[step_i] = {1}
    return
  end
  avail_types[step_i] = available_chord_types(
    params:get("root_note") - 1,
    SCALE_NAMES[params:get("scale_type")],
    degree)
  local ct = step_chord_type[step_i] or 1
  if ct > #avail_types[step_i] then ct = #avail_types[step_i] end
  step_chord_type[step_i] = ct
end

local function refresh_all_available_types()
  for i = 1, NUM_STEPS_MAX do refresh_available_types(i) end
end

local midi_out_devices = {}   -- filled at init from midi.vports
local chord_midi = nil
local accomp_midi = nil

local g = nil                 -- grid
local a = nil                 -- arc

-- ============================================================
-- randomizable-parameter registry
-- every param added through these two helpers gets a matching
-- "_lock" toggle right below it in the menu. randomize() skips
-- any param whose lock is on.
-- ============================================================

local rand_params = {}   -- ordered list of {id, kind, min, max, count}
local rand_lookup = {}   -- id -> same entry, for quick lookup (arc uses this)

local function add_rand_number(id, name, min, max, default, formatter)
  params:add_number(id, name, min, max, default, formatter)
  local entry = {id = id, kind = "number", min = min, max = max}
  table.insert(rand_params, entry)
  rand_lookup[id] = entry
  params:add_binary(id .. "_lock", "  anchor", "toggle", 0)
end

-- `candidates`, if given, restricts which option indices get chosen
-- during randomize (manual selection via E-knob/arc/menu still has
-- the full option list; only the random pool is narrowed).
local function add_rand_option(id, name, options, default, candidates)
  params:add_option(id, name, options, default)
  local entry = {id = id, kind = "option", count = #options, candidates = candidates}
  table.insert(rand_params, entry)
  rand_lookup[id] = entry
  params:add_binary(id .. "_lock", "  anchor", "toggle", 0)
end

local function randomize(filter_prefix)
  local amount = params:get("randomize_amount") / 100
  for _, p in ipairs(rand_params) do
    if params:get(p.id .. "_lock") == 0 then
      if filter_prefix == nil or string.find(p.id, filter_prefix) == 1 then
        if math.random() <= amount then
          if p.kind == "number" then
            params:set(p.id, math.random(p.min, p.max))
          elseif p.candidates then
            params:set(p.id, p.candidates[math.random(#p.candidates)])
          else
            params:set(p.id, math.random(1, p.count))
          end
        end
      end
    end
  end

  -- per-step overrides: gust randomizes them within valid range,
  -- gated by the matching global param's own lock.
  if filter_prefix == nil then
    local override_specs = {
      {tbl = step_inv,    lock_id = "inversion_lock",       min = 0,  max = 3},
      {tbl = step_gate,   lock_id = "chord_gate_lock",      min = 10, max = 100},
      {tbl = step_vel,    lock_id = "chord_velocity_lock",  min = 1,  max = 127},
      {tbl = step_octave, lock_id = "root_octave_lock",     min = 1,  max = 6},
    }
    for _, spec in ipairs(override_specs) do
      if params:get(spec.lock_id) == 0 then
        for i = 1, NUM_STEPS_MAX do
          if math.random() <= amount then
            spec.tbl[i] = math.random(spec.min, spec.max)
          end
        end
      end
    end

    -- chord type has a per-step dynamic range (however many types are
    -- diatonic to that step's own degree), so it can't use the fixed
    -- min/max spec above — handled separately, gated by its own lock.
    if params:get("chord_type_lock") == 0 then
      for i = 1, NUM_STEPS_MAX do
        if math.random() <= amount then
          local avail = avail_types[i] or {1}
          step_chord_type[i] = math.random(1, #avail)
        end
      end
    end
  end

  redraw()
  grid_redraw()
  arc_redraw()
end

-- ============================================================
-- music helpers
-- ============================================================

-- build absolute MIDI notes for a step's chord: degree gives the
-- scale root, that step's chord type (from its own filtered avail
-- list) gives the interval structure, octave sets the register.
local function build_chord(step_i, degree_idx, inversion)
  if degree_idx == 8 then return {} end -- "rest"

  local root_pc = params:get("root_note") - 1
  local octave = eff_octave(step_i)
  local base_midi = (octave + 1) * 12 + root_pc
  local scale_name = SCALE_NAMES[params:get("scale_type")]

  current_scale_notes = MusicUtil.generate_scale(base_midi, scale_name, 2)
  if current_scale_notes == nil then return {} end

  local degree_root = current_scale_notes[degree_idx]
  if degree_root == nil then return {} end

  local avail = avail_types[step_i] or {1}
  local ct_idx = avail[step_chord_type[step_i] or 1] or 1
  local ct = CHORD_TYPES[ct_idx]
  if ct == nil then return {} end

  local notes = {}
  for _, ivl in ipairs(ct.ivl) do
    table.insert(notes, degree_root + ivl)
  end

  for _ = 1, inversion do
    if #notes > 1 then
      local lowest = table.remove(notes, 1)
      table.insert(notes, lowest + 12)
    end
  end

  return notes
end

local function pick_accompaniment_note(sub)
  if #current_chord_notes == 0 then return nil end
  local pattern = ACCOMP_PATTERNS[params:get("accomp_pattern")]
  local octave_offset = params:get("accomp_octave") * 12
  local note

  if pattern == "root" then
    note = current_chord_notes[1]
  elseif pattern == "root+5th" then
    local fifth = current_chord_notes[3] or current_chord_notes[1]
    note = (sub % 2 == 1) and current_chord_notes[1] or fifth
  elseif pattern == "arp up" then
    note = current_chord_notes[((sub - 1) % #current_chord_notes) + 1]
  elseif pattern == "arp down" then
    local n = #current_chord_notes
    note = current_chord_notes[n - ((sub - 1) % n)]
  elseif pattern == "rand chord" then
    note = current_chord_notes[math.random(#current_chord_notes)]
  elseif pattern == "rand scale" then
    if #current_scale_notes > 0 then
      note = current_scale_notes[math.random(#current_scale_notes)]
    end
  end

  if note == nil then return nil end
  return util.clamp(note + octave_offset, 0, 127)
end

-- ============================================================
-- MIDI out
-- ============================================================

local function refresh_midi_connections()
  chord_midi = midi.connect(params:get("chord_out_device"))
  accomp_midi = midi.connect(params:get("accomp_out_device"))
end

local function send_chord(step_i, notes)
  if #notes == 0 or chord_midi == nil then return end
  local chan          = params:get("chord_out_channel")
  local vel           = util.clamp(eff_vel(step_i), 1, 127)
  local step_beats    = DIVISION_BEATS[params:get("step_div")]
  local gate          = util.clamp(eff_gate(step_i), 10, 100) / 100
  local sustain_beats = step_beats * gate

  local strum_sec
  if params:get("rustle_sync") == 2 then
    strum_sec = STRUM_DIVISION_BEATS[params:get("rustle_div")] * clock.get_beat_sec()
  else
    strum_sec = params:get("rustle") / 1000
  end

  for idx, n in ipairs(notes) do
    clock.run(function()
      if idx > 1 and strum_sec > 0 then
        clock.sleep(strum_sec * (idx - 1))
      end
      chord_midi:note_on(n, vel, chan)
      clock.sleep(clock.get_beat_sec() * sustain_beats)
      chord_midi:note_off(n, 0, chan)
    end)
  end
end

local function send_accompaniment_note(note, tick_beats)
  if note == nil or accomp_midi == nil then return end
  local chan = params:get("accomp_out_channel")
  local vel = params:get("accomp_velocity")
  local gate = params:get("accomp_gate") / 100
  accomp_midi:note_on(note, vel, chan)
  clock.run(function()
    clock.sleep(clock.get_beat_sec() * tick_beats * gate)
    accomp_midi:note_off(note, 0, chan)
  end)
end

local function all_notes_off()
  if chord_midi then
    for ch = 1, 16 do
      for n = 0, 127 do chord_midi:note_off(n, 0, ch) end
    end
  end
  if accomp_midi then
    for ch = 1, 16 do
      for n = 0, 127 do accomp_midi:note_off(n, 0, ch) end
    end
  end
end

-- ============================================================
-- sequencer
-- ============================================================

local function advance_step()
  current_step = (current_step % params:get("steps")) + 1

  local degree    = params:get("step" .. current_step .. "_degree")
  local inversion = eff_inv(current_step)

  current_chord_notes = build_chord(current_step, degree, inversion)

  local avail = avail_types[current_step] or {1}
  local ct = CHORD_TYPES[avail[step_chord_type[current_step] or 1] or 1]
  last_chord_label = DEGREE_OPTIONS[degree] .. " " .. (ct and ct.name or "?")

  if degree ~= 8 then
    send_chord(current_step, current_chord_notes)
  else
    current_chord_notes = {}
  end

  redraw()
  grid_redraw()
end

local function accompaniment_tick(sub, tick_beats)
  if params:get("accompaniment") == 1 then return end -- off
  local note = pick_accompaniment_note(sub)
  send_accompaniment_note(note, tick_beats)
end

local function sequencer_loop()
  while true do
    local step_beats = DIVISION_BEATS[params:get("step_div")]
    local ticks = params:get("accomp_division")
    local tick_beats = step_beats / ticks

    for sub = 1, ticks do
      clock.sync(tick_beats)
      if sub == 1 then advance_step() end
      accompaniment_tick(sub, tick_beats)
    end
  end
end

local function start_playback()
  if running then return end
  running = true
  seq_coro = clock.run(sequencer_loop)
  redraw()
end

local function stop_playback()
  if not running then return end
  running = false
  if seq_coro then clock.cancel(seq_coro) end
  all_notes_off()
  redraw()
end

local function toggle_playback()
  if running then stop_playback() else start_playback() end
end

-- respond to transport start/stop from an external clock source
clock.transport.start = function() start_playback() end
clock.transport.stop = function() stop_playback() end

-- ============================================================
-- params
-- ============================================================

local function build_device_options()
  midi_out_devices = {}
  for i = 1, #midi.vports do
    table.insert(midi_out_devices, i .. ": " .. (midi.vports[i].name or "none"))
  end
end

local function init_params()
  build_device_options()

  params:add_group("MIDI OUT", 4)
  params:add_option("chord_out_device", "chord device", midi_out_devices, 1)
  params:set_action("chord_out_device", function() refresh_midi_connections() end)
  params:add_number("chord_out_channel", "chord channel", 1, 16, 1)
  params:add_option("accomp_out_device", "roots device", midi_out_devices, 1)
  params:set_action("accomp_out_device", function() refresh_midi_connections() end)
  params:add_number("accomp_out_channel", "roots channel", 1, 16, 2)

  -- NOTE: no clock.add_params() call here on purpose — norns adds the
  -- whole CLOCK page (source, tempo, link, midi clock in/out, crow)
  -- automatically before a script's init() ever runs. clock_source /
  -- clock_tempo are already valid param ids by the time we get here.

  params:add_group("ARC", 2)
  params:add_number("arc_threshold", "arc sensitivity", 1, 64, 24)
  params:add_number("arc_brightness", "arc brightness", 1, 15, 15)

  params:add_group("GROWTH", 3)
  add_rand_option("step_div", "pace", DIVISION_NAMES, 3)
  params:add_number("steps", "growth", 1, NUM_STEPS_MAX, 4)

  params:add_group("SOIL & CLIMATE", 6)
  add_rand_option("root_note", "soil", NOTE_NAMES, 1)
  params:set_action("root_note", function() refresh_all_available_types() end)
  add_rand_option("scale_type", "climate", SCALE_NAMES, 1, CONSONANT_SCALE_INDICES)
  params:set_action("scale_type", function() refresh_all_available_types() end)
  add_rand_number("root_octave", "height", 1, 6, 3)

  params:add_group("BRANCHES", 13)
  add_rand_number("inversion", "lean", 0, 3, 0)
  add_rand_number("chord_gate", "bloom %", 10, 100, 80)
  add_rand_number("chord_velocity", "vigor", 1, 127, 100)
  add_rand_number("rustle", "rustle ms", 0, 150, 0)
  add_rand_option("rustle_sync", "rustle sync", {"off", "on"}, 1)
  add_rand_option("rustle_div", "rustle div", STRUM_DIVISION_NAMES, 2)
  params:add_binary("chord_type_lock", "  anchor chord type", "toggle", 0)

  params:add_group("FLOWERS", NUM_STEPS_MAX * 2)
  for i = 1, NUM_STEPS_MAX do
    add_rand_option("step" .. i .. "_degree", "flower " .. i,
      DEGREE_OPTIONS, ((i - 1) % 7) + 1)
    params:set_action("step" .. i .. "_degree", function() refresh_available_types(i) end)
  end

  params:add_group("ROOTS", 11)
  params:add_option("accompaniment", "roots", {"off", "on"}, 1)
  add_rand_option("accomp_pattern", "root pattern", ACCOMP_PATTERNS, 1)
  add_rand_number("accomp_division", "root density", 1, 4, 1)
  add_rand_number("accomp_octave", "root depth", -3, 2, -1)
  add_rand_number("accomp_gate", "root reach %", 10, 100, 70)
  add_rand_number("accomp_velocity", "root strength", 1, 127, 90)

  params:add_group("WIND", 5)
  params:add_number("randomize_amount", "wind %", 0, 100, 50)
  params:add_trigger("randomize_all", "gust")
  params:set_action("randomize_all", function() randomize(nil) end)
  params:add_trigger("randomize_progression", "breeze")
  params:set_action("randomize_progression", function() randomize("step") end)
  params:add_trigger("lock_all", "anchor all")
  params:set_action("lock_all", function()
    for _, p in ipairs(rand_params) do params:set(p.id .. "_lock", 1) end
  end)
  params:add_trigger("unlock_all", "release all")
  params:set_action("unlock_all", function()
    for _, p in ipairs(rand_params) do params:set(p.id .. "_lock", 0) end
  end)
end

-- ============================================================
-- grid
-- ============================================================

-- grid is a live piano-roll for the progression:
--   columns 1-8, rows 1-7 = step x degree. tap a cell to set that
--     step's degree (vii at top, I just above row 8). tap the lit
--     cell again to clear it to rest. this row never touches
--     selection, only the chord itself.
--   row 8 = selection row. tapping column x selects flower x for
--     arc/E2/E3 editing. sequence length is set separately in
--     PARAMETERS > GROWTH > growth. play/stop and randomize live
--     on K2/K3 only, not the grid.
local HOLD_SEC = 0.5

function grid_redraw()
  if g == nil or not g.device then return end
  g:all(0)
  local steps = params:get("steps")
  for x = 1, math.min(steps, 8) do
    local degree = params:get("step" .. x .. "_degree")
    if degree ~= 8 then
      local y = 8 - degree
      g:led(x, y, (x == current_step) and 15 or 8)
    end
  end
  for x = 1, 8 do
    if x <= steps then
      local level = 4
      if x == selected_step then level = 15
      elseif x == current_step then level = 10 end
      g:led(x, 8, level)
    end
  end
  g:refresh()
end

local function init_grid()
  g = grid.connect()
  g.key = function(x, y, z)
    if z ~= 1 then return end
    local steps = params:get("steps")
    if y >= 1 and y <= 7 and x <= math.min(steps, 8) then
      local degree = 8 - y
      local id = "step" .. x .. "_degree"
      if params:get(id) == degree then
        params:set(id, 8) -- toggle back to rest
      else
        params:set(id, degree)
      end
    elseif y == 8 then
      selected_step = x
    end
    grid_redraw()
    arc_redraw()
    redraw()
  end
end

-- ============================================================
-- arc
-- ============================================================

-- the arc is a paged global-parameter editor. page persists across
-- flower selection (selected_step still drives the tree's ring
-- marker and E2/E3, and will drive per-flower params later — for
-- now every arc page controls the shared, global dials so it's
-- immediately clear what's changing and by how much).
local arc_page = 1
local arc_accum = {0, 0, 0, 0}

-- rings with param_id are global. rings with step_tbl are per-step
-- overrides — they read/write the selected step's override table.
-- def/min/max are needed for ring display when param_id is absent.
local ARC_PAGES = {
  {
    name = "CHORD",
    per_step = true,
    rings = {
      {label = "type", kind = "chord_type"},
      {label = "inv",  step_tbl = step_inv,    min = 0, max = 3, def = "inversion"},
      {label = "oct",  step_tbl = step_octave, min = 1, max = 6, def = "root_octave"},
      {label = "vel",  step_tbl = step_vel,    min = 1, max = 127, def = "chord_velocity"},
    },
  },
  {
    name = "STRUM",
    rings = {
      {label = "ms",   param_id = "rustle",     unit = "ms"},
      {label = "sync", param_id = "rustle_sync"},
      {label = "div",  param_id = "rustle_div"},
      {label = "gate", step_tbl = step_gate, min = 10, max = 100, def = "chord_gate", unit = "%"},
    },
  },
  {
    name = "ACCOMP",
    rings = {
      {label = "pattern", param_id = "accomp_pattern"},
      {label = "density", param_id = "accomp_division"},
      {label = "oct",     param_id = "accomp_octave"},
      {label = "gate",    param_id = "accomp_gate", unit = "%"},
    },
  },
  {
    name = "SCALE",
    rings = {
      {label = "key",   param_id = "root_note"},
      {label = "scale", param_id = "scale_type"},
      {label = "oct",   param_id = "root_octave"},
      {label = "div",   param_id = "step_div"},
    },
  },
}

-- returns (base_fraction, fraction_per_step) for a ring,
-- regardless of whether it's a global param or a per-step override.
local function ring_span(ring)
  if ring.kind == "chord_type" then
    local avail = avail_types[selected_step] or {1}
    local count = math.max(#avail, 1)
    local val = step_chord_type[selected_step] or 1
    return (val - 1) / math.max(count - 1, 1), 1 / math.max(count - 1, 1)
  elseif ring.param_id then
    local entry = rand_lookup[ring.param_id]
    if entry == nil then return nil, nil end
    if entry.kind == "number" then
      local base = (params:get(ring.param_id) - entry.min) / (entry.max - entry.min)
      return base, 1 / math.max(entry.max - entry.min, 1)
    else
      local base = (params:get(ring.param_id) - 1) / math.max(entry.count - 1, 1)
      return base, 1 / math.max(entry.count - 1, 1)
    end
  elseif ring.step_tbl then
    -- read this step's override, falling back to the global default
    local val = ring.step_tbl[selected_step] or params:get(ring.def)
    local base = (val - ring.min) / (ring.max - ring.min)
    return base, 1 / math.max(ring.max - ring.min, 1)
  end
  return nil, nil
end

-- adds in-progress accumulator motion on top of current value so
-- low-option params (e.g. ext: 3 values) sweep as smoothly as
-- high-range ones (e.g. vel: 127 values).
local function ring_fraction(ring, n)
  if ring == nil then return nil end
  local base, step_frac = ring_span(ring)
  if base == nil then return nil end
  local threshold = params:get("arc_threshold")
  local smooth = ((arc_accum[n] or 0) / threshold) * step_frac
  return util.clamp(base + smooth, 0, 1)
end

local function ring_step(ring, dir)
  if ring.kind == "chord_type" then
    local avail = avail_types[selected_step] or {1}
    local count = math.max(#avail, 1)
    local cur = step_chord_type[selected_step] or 1
    step_chord_type[selected_step] = util.clamp(cur + dir, 1, count)
  elseif ring.param_id then
    params:delta(ring.param_id, dir)
  elseif ring.step_tbl then
    -- initialise from global on first touch so ring starts in place
    if ring.step_tbl[selected_step] == nil then
      ring.step_tbl[selected_step] = params:get(ring.def)
    end
    ring.step_tbl[selected_step] = util.clamp(
      ring.step_tbl[selected_step] + dir, ring.min, ring.max)
  end
end

function arc_redraw()
  if a == nil or not a.device then return end
  a:all(0)
  local page = ARC_PAGES[arc_page]
  for n = 1, 4 do
    local frac = ring_fraction(page.rings[n], n)
    if frac then
      a:segment(n, 0, math.pi * 2 * frac, params:get("arc_brightness"))
    end
  end
  a:refresh()
end

-- which ring was last touched on the arc — shown prominently in the footer
local arc_last_ring = 1

local function cycle_arc_page()
  arc_page = arc_page % #ARC_PAGES + 1
  arc_accum[1] = 0; arc_accum[2] = 0; arc_accum[3] = 0; arc_accum[4] = 0
  arc_redraw()
  redraw()
end

-- arc deltas arrive as many small raw units per physical detent, so
-- treating every event as a flat +-1 step made tiny jitter register
-- as a full step while fast spins didn't go any faster — read as
-- "inconsistent/oversensitive". instead we accumulate raw motion per
-- ring and only advance the underlying param once it crosses the
-- "arc sensitivity" param (PARAMETERS > ARC), carrying the remainder
-- — while the ring's on-screen position tracks the accumulator
-- continuously (see ring_fraction) so it always looks smooth even
-- between clicks. sensitivity is a live param specifically so it can
-- be tuned on the actual hardware without another round of code
-- changes.
local function init_arc()
  a = arc.connect()
  a.delta = function(n, d)
    local page = ARC_PAGES[arc_page]
    local ring = page.rings[n]
    if not ring then return end
    local threshold = params:get("arc_threshold")
    arc_accum[n] = arc_accum[n] + d
    arc_last_ring = n
    while arc_accum[n] >= threshold do
      ring_step(ring, 1)
      arc_accum[n] = arc_accum[n] - threshold
    end
    while arc_accum[n] <= -threshold do
      ring_step(ring, -1)
      arc_accum[n] = arc_accum[n] + threshold
    end
    arc_redraw()
    redraw()
  end
  -- not every arc model has a pushbutton; docs suggest falling back
  -- to a norns key when it doesn't. K1 (below) covers that case
  -- regardless, so this is just "use it if it's there".
  a.key = function(_, z)
    if z == 1 then cycle_arc_page() end
  end
end

-- ============================================================
-- screen — the flower
-- ============================================================

-- ============================================================
-- screen — the flower
-- ============================================================

-- 24 pre-baked petal rotations, one PNG per 15deg increment
-- (petal_00.png .. petal_23.png, file order). verified against
-- the petal-tester script — same asset pipeline, same math.
-- {true_pointing_angle, width, height, base_x, base_y}
local ROTATIONS = {
  {270, 14, 24,  7.00, 24.00}, -- petal_00.png
  {285, 20, 28,  6.89, 25.59}, -- petal_01.png
  {300, 26, 28,  7.00, 24.39}, -- petal_02.png
  {315, 28, 28,  5.51, 22.49}, -- petal_03.png
  {330, 28, 26,  3.61, 19.00}, -- petal_04.png
  {345, 28, 20,  2.41, 13.11}, -- petal_05.png
  {  0, 24, 14,  0.00,  7.00}, -- petal_06.png
  { 15, 28, 20,  2.41,  6.89}, -- petal_07.png
  { 30, 28, 26,  3.61,  7.00}, -- petal_08.png
  { 45, 28, 28,  5.51,  5.51}, -- petal_09.png
  { 60, 26, 28,  7.00,  3.61}, -- petal_10.png
  { 75, 20, 28,  6.89,  2.41}, -- petal_11.png
  { 90, 14, 24,  7.00,  0.00}, -- petal_12.png
  {105, 20, 28, 13.11,  2.41}, -- petal_13.png
  {120, 26, 28, 19.00,  3.61}, -- petal_14.png
  {135, 28, 28, 22.49,  5.51}, -- petal_15.png
  {150, 28, 26, 24.39,  7.00}, -- petal_16.png
  {165, 28, 20, 25.59,  6.89}, -- petal_17.png
  {180, 24, 14, 24.00,  7.00}, -- petal_18.png
  {195, 28, 20, 25.59, 13.11}, -- petal_19.png
  {210, 28, 26, 24.39, 19.00}, -- petal_20.png
  {225, 28, 28, 22.49, 22.49}, -- petal_21.png
  {240, 26, 28, 19.00, 24.39}, -- petal_22.png
  {255, 20, 28, 13.11, 25.59}, -- petal_23.png
}

local IMG_DIR = _path.code .. "chordflow/img/"
local petal_images = {}  -- indexed 1-24, matching ROTATIONS (file order)

-- file index i (0-based) has true_pointing_angle = (270 + i*15) % 360;
-- invert that to find the right file for a desired placement angle.
local function nearest_rotation_index(angle_deg)
  local offset = (angle_deg + 90) % 360
  local idx = util.round(offset / 15) % 24
  return idx + 1  -- lua 1-indexed
end

local FLOWER_CX   = 64
local FLOWER_CY   = 30
local PETAL_REACH = 8    -- distance from center to petal base
local CENTER_R    = 4
local REST_R      = 3    -- hollow-circle radius for rest (inactive) flowers

local sway_phase    = 0
local intro_progress = 0

local function petal_angle_deg(i, steps)
  local base = (360 * (i - 1) / steps) - 90
  local sway = math.sin(sway_phase) * 3
  return (base + sway) % 360
end

local function draw_flower()
  local steps = math.min(params:get("steps"), 8)
  local reach = PETAL_REACH * intro_progress

  for i = 1, steps do
    local degree      = params:get("step" .. i .. "_degree")
    local is_rest      = (degree == 8)
    local is_current   = (i == current_step)
    local is_selected  = (i == selected_step)

    local angle_deg = petal_angle_deg(i, steps)
    local rad = math.rad(angle_deg)
    local target_x = FLOWER_CX + math.cos(rad) * reach
    local target_y = FLOWER_CY + math.sin(rad) * reach

    if is_rest then
      screen.level(is_current and 10 or 3)
      screen.circle(target_x, target_y, REST_R * intro_progress)
      screen.stroke()
    else
      local rot_i = nearest_rotation_index(angle_deg)
      local rot   = ROTATIONS[rot_i]
      local img   = petal_images[rot_i]
      if img ~= nil then
        screen.display_image(img, target_x - rot[4], target_y - rot[5])
      end
    end

    -- current (playing) ring at the petal tip
    if is_current and intro_progress > 0.5 then
      local tip_x = FLOWER_CX + math.cos(rad) * (reach + (is_rest and REST_R or 12))
      local tip_y = FLOWER_CY + math.sin(rad) * (reach + (is_rest and REST_R or 12))
      screen.level(15)
      screen.circle(tip_x, tip_y, 2.5)
      screen.stroke()
    end

    -- selected (arc/E2 editing target) ring at the petal base, only
    -- drawn separately when it's a different step than current —
    -- keeps the two indicators from ever overlapping/ambiguous
    if is_selected and not is_current and intro_progress > 0.5 then
      screen.level(11)
      screen.circle(target_x, target_y, 3.5)
      screen.stroke()
    end
  end

  -- center dot: filled+bright while playing, hollow while stopped
  if running then
    screen.level(15)
    screen.circle(FLOWER_CX, FLOWER_CY, CENTER_R * intro_progress)
    screen.fill()
  else
    screen.level(6)
    screen.circle(FLOWER_CX, FLOWER_CY, CENTER_R * intro_progress)
    screen.stroke()
  end
end

function redraw()
  screen.clear()
  screen.font_size(8)

  -- header
  screen.level(15)
  screen.move(0, 7)
  screen.text(NOTE_NAMES[params:get("root_note")] .. " " ..
    SCALE_NAMES[params:get("scale_type")])
  screen.move(127, 7)
  screen.text_right(params:string("clock_source") .. " " ..
    string.format("%.0f", params:get("clock_tempo")))

  draw_flower()

  -- footer
  if a ~= nil and a.device then
    local page = ARC_PAGES[arc_page]
    local active = page.rings[arc_last_ring]

    -- page name + ring indicator, dim
    screen.level(4)
    screen.move(0, 55)
    local indicators = ""
    for n = 1, 4 do
      if page.rings[n] then
        indicators = indicators .. (n == arc_last_ring and "[" .. n .. "]" or " " .. n .. " ")
      end
    end
    local step_tag = page.per_step and ("S" .. selected_step .. " ") or ""
    screen.text(step_tag .. page.name .. "  " .. indicators)

    -- active ring: label and current value, bright and large
    if active then
      local val
      if active.kind == "chord_type" then
        local avail = avail_types[selected_step] or {1}
        local ct = CHORD_TYPES[avail[step_chord_type[selected_step] or 1] or 1]
        val = ct and ct.name or "?"
      elseif active.param_id then
        val = params:string(active.param_id)
      else
        val = tostring(active.step_tbl[selected_step] or params:get(active.def))
      end
      screen.font_size(12)
      screen.level(15)
      screen.move(0, 63)
      screen.text(active.label .. ":  " .. val .. (active.unit or ""))
      screen.font_size(8)
    end
  else
    screen.level(10)
    screen.move(0, 62)
    screen.text(running
      and ("step " .. current_step .. "  " .. last_chord_label)
      or  ("step " .. selected_step .. " = " ..
           DEGREE_OPTIONS[params:get("step" .. selected_step .. "_degree")]))
  end

  screen.update()
end

-- intro bloom: flower petals open from the center outward
local function boot_and_bloom()
  local duration, frames = 1.2, 24
  for i = 1, frames do
    intro_progress = i / frames
    redraw()
    clock.sleep(duration / frames)
  end
  intro_progress = 1
  while true do
    sway_phase = sway_phase + 0.04
    redraw()
    clock.sleep(1 / 20)
  end
end

-- ============================================================
-- encoders / keys
-- ============================================================

function enc(n, d)
  if n == 2 then
    selected_step = util.clamp(selected_step + d, 1, params:get("steps"))
    arc_redraw()
  elseif n == 3 then
    params:delta("step" .. selected_step .. "_degree", d)
  end
  redraw()
end

-- K3: quick tap = randomize progression only (mild, low-stakes —
-- safe against accidental presses); hold ~0.5s = randomize everything
-- (respecting locks/amount). mirrors the grid's randomize cell.
local k3_token = 0
local k3_fired = false

function key(n, z)
  if n == 1 then
    -- fallback page-cycle for arcs without a pushbutton (and works
    -- fine even if yours has one — either input cycles the same page)
    if z == 1 then cycle_arc_page() end
  elseif n == 2 then
    if z == 1 then toggle_playback() end
  elseif n == 3 then
    if z == 1 then
      k3_token = k3_token + 1
      local my_token = k3_token
      k3_fired = false
      clock.run(function()
        clock.sleep(HOLD_SEC)
        if k3_token == my_token then
          k3_fired = true
          randomize(nil)
        end
      end)
    elseif z == 0 then
      if not k3_fired then
        randomize("step")
      end
    end
  end
end

-- ============================================================
-- lifecycle
-- ============================================================

function init()
  math.randomseed(os.time())
  init_params()
  refresh_midi_connections()
  init_grid()
  init_arc()
  for i = 1, 24 do
    local filename = string.format("petal_%02d.png", i - 1)
    local ok, img = pcall(screen.load_png, IMG_DIR .. filename)
    if ok then
      petal_images[i] = img
    else
      print("failed to load " .. filename)
    end
  end
  params:bang()
  grid_redraw()
  arc_redraw()
  clock.run(boot_and_bloom)
end

function cleanup()
  stop_playback()
end