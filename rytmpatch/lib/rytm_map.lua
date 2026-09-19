-- Analog Rytm MKII MIDI CC map (source: midi.guide / pencilresearch/midi
-- CSV, "Elektron/Analog Rytm MKII.csv").
--
-- track params go out on each track's own channel; FX params (delay,
-- reverb, distortion, compressor) reuse the same CC numbers but on the
-- Rytm's FX control channel -- that's how the Rytm tells them apart.
--
-- TAMING POLICY (the `w` windows and `b` biases below)
-- min/max is always the real CC range, so every value stays reachable by
-- hand. `w` is the slice randomize/wander are allowed to land in by
-- default, chosen so a fresh roll is a playable drum rather than a stunt:
--   * tunings stay within a few semitones of centre instead of ±2 octaves
--   * attacks bias short, decays avoid the "inaudible click" end
--   * anything that gets loud or ugly fast (overdrive, distortion,
--     comp makeup gain, delay feedback, bit reduction) is capped
--   * filter cutoff avoids the bottom of its range, where a track goes
--     silent, and resonance stays below self-oscillation
--   * levels/volumes are either locked or kept in a narrow band so a
--     random kit still balances
-- PARAMETERS > RANDOMIZE > "widen range" opens every window toward the
-- full range at once (100% = no taming at all), and K3 on a single param
-- cycles it tame -> wide -> locked.
--
-- desc fields: see patchcore.lua. `cc` added here.
-- compact machine specs: {name, min, max, flags, labels, w = {lo, hi},
-- b = "low"/"high"/"center"}; flags "c" = centered, "l" = locked, "d" =
-- discrete.

local Map = {}

local function d(name, cc, min, max, opts)
  local t = {name = name, cc = cc, min = min or 0, max = max or 127}
  if opts then for k, v in pairs(opts) do t[k] = v end end
  if t.labels then t.discrete = true end
  return t
end

---------------------------------------------------------------- synth machines

local SIN3 = {"SIN", "ASIN", "TRI"}
local WAVE12 = {"SIN.R", "SIN.F", "ASN.R", "ASN.F", "TRI.R", "TRI.F",
                "STH.R", "STH.F", "SAW.R", "SAW.F", "SQR.R", "SQR.F"}

-- shared windows, so one edit retunes every machine that uses them
local W_DECAY = {20, 110}       -- a decay of ~0 is an inaudible click
local W_NSDEC = {10, 90}
local W_HOLD = {0, 90}
local W_SWDEP = {0, 90}
local W_SWTIM = {10, 110}
local W_TRANS = {0, 70}         -- ticks/clicks/dust/impact: easily too loud
local W_NOISE = {0, 90}
local W_FM = {0, 90}
local W_TUNE = {48, 80}         -- ±16 of centre, not the full ±2 octaves
local W_DET = {58, 70}          -- 40-88 params: a few semitones either way

-- {name, min, max, flags, labels} + w/b. false = position unused by the machine
local LEV = {"LEV", 0, 127, "l"}
local TUNE = {"TUNE", 0, 127, "c", w = W_TUNE}
local DEC = {"DEC", w = W_DECAY}

local MACHINES = {
  {"BD HARD",     {LEV, TUNE, DEC, {"HOLD", w = W_HOLD}, {"SWTIM", w = W_SWTIM},
                   {"SWDEP", w = W_SWDEP}, {"WAVE", 0, 2, "", SIN3}, {"TICK", w = W_TRANS}}},
  {"BD CLASSIC",  {LEV, TUNE, DEC, {"HOLD", w = W_HOLD}, {"SWTIM", w = W_SWTIM},
                   {"SWDEP", w = W_SWDEP}, {"WAVE", 0, 2, "", SIN3}, {"TICK", 0, 55, "", nil, w = {0, 30}}}},
  {"BD FM",       {LEV, TUNE, DEC, {"FMAMT", w = W_FM}, {"SWTIM", w = W_SWTIM},
                   {"FMSWT", w = W_SWTIM}, {"FMDEC", w = W_DECAY}, {"FMTUN", w = {30, 100}}}},
  {"BD PLASTIC",  {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"SWTIM", w = W_SWTIM},
                   {"HOLD", w = W_HOLD}, {"CLICK", w = W_TRANS}, {"DUST", w = W_TRANS}}},
  {"BD SILKY",    {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"SWTIM", w = W_SWTIM},
                   {"HOLD", w = W_HOLD}, {"CLICK", w = W_TRANS}, {"DUST", w = W_TRANS}}},
  {"BD SHARP",    {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"SWTIM", w = W_SWTIM},
                   {"HOLD", w = W_HOLD}, {"TICK", w = W_TRANS}, {"WAVE", 0, 11, "", WAVE12}}},
  {"BD ACOUSTIC", {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"SWTIM", w = W_SWTIM},
                   {"HOLD", w = W_HOLD}, {"IMPCT", w = W_TRANS}, {"WAVE", 0, 11, "", WAVE12}}},
  {"SD HARD",     {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"TICK", w = W_TRANS},
                   {"NSDEC", w = W_NSDEC}, {"NSLEV", w = W_NOISE}, {"SWTIM", w = W_SWTIM}}},
  {"SD CLASSIC",  {LEV, TUNE, DEC, {"DETUN", w = {20, 100}}, {"SNAP", w = W_TRANS},
                   {"NSDEC", w = W_NSDEC}, {"NSLEV", w = W_NOISE}, {"BAL", w = {30, 100}}}},
  {"SD FM",       {LEV, TUNE, DEC, {"FMTUN", 0, 127, "c", nil, w = {40, 90}},
                   {"FMDEC", w = W_DECAY}, {"NSDEC", w = W_NSDEC}, {"NSLEV", w = W_NOISE},
                   {"FMAMT", w = W_FM}}},
  {"SD NATURAL",  {LEV, TUNE, {"BDDEC", w = W_DECAY}, {"NSDEC", w = W_NSDEC},
                   {"NSLPF", w = {40, 127}, b = "high"}, {"NSBAL", w = {30, 100}},
                   {"NSRES", w = {0, 90}}, {"NSHPF", w = {0, 80}}}},
  {"SD ACOUSTIC", {LEV, TUNE, {"BDDEC", w = W_DECAY}, {"NSDEC", w = W_NSDEC},
                   {"HOLD", w = W_HOLD}, {"NSLEV", w = W_NOISE}, {"IMPCT", w = W_TRANS},
                   {"SWDEP", w = W_SWDEP}}},
  {"RS HARD",     {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"TICK", w = W_TRANS},
                   {"NOISE", w = W_NOISE}, {"SYMM", w = {30, 100}}, {"SWTIM", w = W_SWTIM}}},
  {"RS CLASSIC",  {LEV, {"TUNE1", 0, 127, "c", nil, w = W_TUNE}, DEC,
                   {"BAL", 0, 127, "c", nil, w = {40, 90}}, {"TUNE2", 0, 127, "c", nil, w = W_TUNE},
                   {"SYMM", 0, 127, "c", nil, w = {40, 90}}, {"NOISE", w = W_NOISE},
                   {"TICK", w = W_TRANS}}},
  {"CP CLASSIC",  {LEV, {"TONE", w = {20, 110}}, {"NSDEC", w = W_NSDEC}, {"CLAPS", w = {0, 100}},
                   {"RATE", w = {20, 110}}, {"NOISE", w = W_NOISE}, {"RND", w = {0, 90}},
                   {"CPDEC", w = W_DECAY}}},
  {"BT CLASSIC",  {LEV, TUNE, DEC, false, {"NOISE", w = W_NOISE}, {"SNAP", 0, 3}, false, false}},
  {"XT CLASSIC",  {LEV, TUNE, DEC, {"SWDEP", w = W_SWDEP}, {"SWTIM", w = W_SWTIM},
                   {"NSDEC", w = W_NSDEC}, {"NSLEV", w = W_NOISE},
                   {"NTONE", 0, 127, "c", nil, w = {40, 90}}}},
  {"CH CLASSIC",  {LEV, TUNE, DEC, {"COLOR", w = {20, 110}}, false, false, false, false}},
  {"CH METALLIC", {LEV, TUNE, DEC, false, false, false, false, false}},
  {"OH CLASSIC",  {LEV, TUNE, DEC, {"COLOR", 0, 127, "c", nil, w = {40, 90}}, false, false, false, false}},
  {"OH METALLIC", {LEV, TUNE, DEC, false, false, false, false, false}},
  {"HH BASIC",    {LEV, TUNE, DEC, {"TONE", 0, 127, "c", nil, w = {40, 90}},
                   {"TRDEC", w = W_NSDEC}, {"RESET", 0, 1, "", {"OFF", "ON"}}, false, false}},
  {"HH LAB",      {LEV, {"TUNE1", 0, 127, "c", nil, w = W_TUNE}, DEC,
                   {"TUNE2", 0, 127, "c", nil, w = W_TUNE}, {"TUNE3", 0, 127, "c", nil, w = W_TUNE},
                   {"TUNE4", 0, 127, "c", nil, w = W_TUNE}, {"TUNE5", 0, 127, "c", nil, w = W_TUNE},
                   {"TUNE6", 0, 127, "c", nil, w = W_TUNE}}},
  {"CY CLASSIC",  {LEV, TUNE, DEC, {"COLOR", 0, 127, "c", nil, w = {40, 90}},
                   {"TONE", 0, 127, "c", nil, w = {40, 90}}, false, false, false}},
  {"CY METALLIC", {LEV, TUNE, DEC, {"TONE", 0, 127, "c", nil, w = {40, 90}},
                   {"TRDEC", w = W_NSDEC}, false, false, false}},
  {"CY RIDE",     {LEV, TUNE, {"TAIL", w = W_DECAY}, {"HIT", w = W_DECAY},
                   {"TYPE", 0, 3, "", {"A", "B", "C", "D"}}, {"CMP1", w = {0, 110}},
                   {"CMP2", w = {0, 110}}, {"CMP3", w = {0, 110}}}},
  {"CB CLASSIC",  {LEV, TUNE, DEC, {"DETUN", w = {20, 100}}, false, false, false, false}},
  {"CB METALLIC", {LEV, TUNE, DEC, {"DETUN", w = {20, 100}}, false, false, false, false}},
  {"SY DUAL VCO", {LEV, {"TUNE1", 0, 127, "c", nil, w = W_TUNE}, {"DEC1", w = W_DECAY},
                   {"BAL", 0, 127, "c", nil, w = {40, 90}}, {"DET2", 0, 127, "c", nil, w = {50, 80}},
                   {"CONF", 0, 79, "d"}, {"DEC2", w = W_DECAY},
                   {"BEND", 0, 127, "c", nil, w = {50, 80}}}},
  -- SY CHIP's waveform list runs real waveforms (0-28) then 99 pulse-width
  -- presets; the tame window keeps the dice out of the preset tail
  {"SY CHIP",     {LEV, TUNE, DEC, {"WAVE", 0, 127, "d", nil, w = {0, 28}}, {"SPEED", w = {20, 110}},
                   {"OFS2", 40, 88, "c", nil, w = W_DET}, {"OFS3", 40, 88, "c", nil, w = W_DET},
                   {"OFS4", 40, 88, "c", nil, w = W_DET}}},
  {"SY RAW",      {LEV, TUNE, {"DEC2", w = W_DECAY}, {"NOISE", w = W_NOISE},
                   {"DETUN", 40, 88, "c", nil, w = W_DET},
                   {"WAV1", 0, 6, "", {"SIN", "ASIN", "TRI", "SSAW", "ASAW", "SAW", "RING"}},
                   {"WAV2", 0, 1, "", {"SIN", "SSAW"}}, {"BAL", 0, 127, "c", nil, w = {40, 90}}}},
  {"UT NOISE",    {LEV, {"LPF", w = {40, 127}, b = "high"}, DEC,
                   {"SWDEP", 0, 127, "c", nil, w = {40, 90}}, {"SWTIM", w = W_SWTIM},
                   {"LPRES", w = {0, 90}}, {"HPF", w = {0, 80}}, {"ATK", w = {0, 40}, b = "low"}}},
  {"UT IMPULSE",  {LEV, {"ATK", w = {0, 40}, b = "low"}, DEC,
                   {"POLAR", 0, 1, "", {"POS", "NEG"}}, false, false, false, false}},
}

Map.machine_names = {}
Map.machine_pages = {}
for i, m in ipairs(MACHINES) do
  Map.machine_names[i] = m[1]
  local page = {}
  for p = 1, 8 do
    local spec = m[2][p]
    if spec then
      local flags = spec[4] or ""
      page[p] = d(spec[1], 15 + p, spec[2] or 0, spec[3] or 127, {
        centered = flags:find("c") ~= nil,
        lock = flags:find("l") ~= nil,
        discrete = flags:find("d") ~= nil or nil,
        labels = spec[5],
        rmin = spec.w and spec.w[1] or nil,
        rmax = spec.w and spec.w[2] or nil,
        bias = spec.b,
      })
    else
      page[p] = false
    end
  end
  Map.machine_pages[i] = page
end

function Map.machine_index(name)
  for i, n in ipairs(Map.machine_names) do if n == name then return i end end
  return 1
end

-- a guess at a typical kit layout, only used as the default label per
-- track -- set the real machines under PARAMETERS > MACHINES
Map.default_machines = {
  "BD HARD", "SD HARD", "RS HARD", "CP CLASSIC", "BT CLASSIC", "XT CLASSIC",
  "XT CLASSIC", "XT CLASSIC", "CH CLASSIC", "OH CLASSIC", "CY CLASSIC", "CB CLASSIC",
}

---------------------------------------------------------------- track pages

local FILTER_TYPES = {"LP2", "LP1", "BP", "HP1", "HP2", "BS", "PK"}
local LFO_WAVES = {"TRI", "SIN", "SQR", "SAW", "EXP", "RMP", "RND"}
local LFO_TRIG = {"FREE", "TRIG", "HOLD", "ONE", "HALF"}
local LFO_MULT = {"1", "2", "4", "8", "16", "32", "64", "128", "256", "512", "1K", "2K",
                  ".1", ".2", ".4", ".8", ".16", ".32", ".64", ".128", ".256", ".512", ".1K", ".2K"}

-- page 1 of the track pages (SYNTH) is machine-dependent: nil here
Map.track_pages = {
  {name = "SYNTH"},
  {name = "SAMPLE", slots = {
    d("TUNE", 24, 40, 88, {centered = true, rmin = 58, rmax = 70}),
    d("FINE", 25, 0, 127, {centered = true, rmin = 48, rmax = 80}),
    -- bit reduction turns nasty well before its ceiling
    d("BITRD", 26, 0, 127, {rmin = 0, rmax = 50, bias = "low"}),
    -- random sample slots swap samples out from under you: locked by default
    d("SLOT", 27, 0, 127, {lock = true, discrete = true}),
    -- start/end past a little trim can mute the sample entirely
    d("START", 28, 0, 120, {rmin = 0, rmax = 20, bias = "low"}),
    d("END", 29, 0, 120, {rmin = 100, rmax = 120, bias = "high"}),
    d("LOOP", 30, 0, 1, {labels = {"OFF", "ON"}}),
    d("LEVEL", 31, 0, 127, {rmin = 70, rmax = 115, default = 100}),
  }},
  {name = "FILTER", slots = {
    d("ATK", 70, 0, 127, {rmin = 0, rmax = 30, bias = "low"}),
    d("DEC", 71, 0, 127, {rmin = 20, rmax = 110}),
    d("SUS", 72, 0, 127, {rmin = 20, rmax = 110}),
    d("REL", 73, 0, 127, {rmin = 10, rmax = 90}),
    -- the bottom of the cutoff range is silence, so bias up and stop short
    d("FREQ", 74, 0, 127, {rmin = 45, rmax = 127, bias = "high"}),
    d("RESO", 75, 0, 127, {rmin = 0, rmax = 80, bias = "low"}),
    d("TYPE", 76, 0, 6, {labels = FILTER_TYPES}),
    d("ENV", 77, 0, 127, {centered = true, rmin = 54, rmax = 104}),
  }},
  {name = "AMP", slots = {
    d("ATK", 78, 0, 127, {rmin = 0, rmax = 20, bias = "low"}),
    d("HOLD", 79, 0, 127, {rmin = 0, rmax = 90}),
    d("DEC", 80, 0, 127, {rmin = 25, rmax = 120}),
    -- overdrive is the loudest knob on the track
    d("DRIVE", 81, 0, 127, {rmin = 0, rmax = 55, bias = "low"}),
    d("DELAY", 82, 0, 127, {rmin = 0, rmax = 55, bias = "low"}),
    d("REVRB", 83, 0, 127, {rmin = 0, rmax = 55, bias = "low"}),
    d("PAN", 10, 0, 127, {centered = true, rmin = 44, rmax = 84, bias = "center"}),
    d("VOL", 7, 0, 127, {lock = true, default = 100}),
  }},
  {name = "LFO", slots = {
    d("SPEED", 102, 0, 127, {centered = true, rmin = 44, rmax = 84}),
    d("MULT", 103, 0, 23, {labels = LFO_MULT, rmin = 0, rmax = 8}),
    d("FADE", 104, 0, 127, {centered = true, rmin = 54, rmax = 74}),
    d("DEST", 105, 0, 41, {discrete = true}),
    d("WAVE", 106, 0, 6, {labels = LFO_WAVES}),
    d("PHASE", 107),
    d("TRIG", 108, 0, 4, {labels = LFO_TRIG}),
    -- shallow by default: LFO destination is random, so depth is the thing
    -- standing between "movement" and "the track falls apart"
    d("DEPTH", 109, 0, 127, {centered = true, rmin = 54, rmax = 74}),
  }},
}

---------------------------------------------------------------- fx pages

Map.fx_pages = {
  {name = "DELAY", slots = {
    d("TIME", 16),
    d("PING", 17, 0, 1, {labels = {"OFF", "ON"}}),
    d("WIDTH", 18, 0, 127, {centered = true, rmin = 44, rmax = 84}),
    -- runaway feedback is the classic accident here
    d("FDBK", 19, 0, 127, {rmin = 20, rmax = 85}),
    d("HPF", 20, 0, 127, {rmin = 0, rmax = 50, bias = "low"}),
    d("LPF", 21, 0, 127, {rmin = 70, rmax = 127, bias = "high"}),
    d("REVRB", 22, 0, 127, {rmin = 0, rmax = 70}),
    d("MIX", 23, 0, 127, {rmin = 30, rmax = 100}),
  }},
  {name = "REVERB", slots = {
    d("PRE", 24, 0, 127, {rmin = 0, rmax = 60, bias = "low"}),
    d("DECAY", 25, 0, 127, {rmin = 30, rmax = 105}),
    d("SHLFF", 26, 0, 127, {rmin = 30, rmax = 110}),
    d("SHLFG", 27, 0, 127, {rmin = 30, rmax = 110}),
    d("HPF", 28, 0, 127, {rmin = 0, rmax = 50, bias = "low"}),
    d("LPF", 29, 0, 127, {rmin = 70, rmax = 127, bias = "high"}),
    false,
    d("MIX", 31, 0, 127, {rmin = 30, rmax = 100}),
  }},
  {name = "DIST", slots = {
    d("AMT", 70, 0, 127, {rmin = 0, rmax = 45, bias = "low"}),
    d("SYMM", 71, 0, 127, {rmin = 40, rmax = 90}),
    d("DRIVE", 72, 0, 127, {rmin = 0, rmax = 45, bias = "low"}),
    false,
    d("DLY", 76, 0, 1, {labels = {"PRE", "POST"}}),
    d("REV", 77, 0, 1, {labels = {"PRE", "POST"}}),
    false, false,
  }},
  {name = "COMP", slots = {
    d("THRS", 78, 0, 127, {rmin = 40, rmax = 110}),
    d("ATK", 79, 0, 6, {discrete = true}),
    d("REL", 80, 0, 7, {discrete = true}),
    -- makeup gain is a volume control wearing a disguise
    d("GAIN", 81, 0, 127, {rmin = 0, rmax = 40, bias = "low"}),
    d("RATIO", 82, 0, 3, {labels = {"1:2", "1:4", "1:8", "MAX"}}),
    d("SC EQ", 83, 0, 3, {labels = {"OFF", "LPF", "HPF", "HIT"}}),
    d("MIX", 84, 0, 127, {rmin = 0, rmax = 90}),
    d("VOL", 85, 0, 127, {lock = true, default = 100}),
  }},
}

return Map
