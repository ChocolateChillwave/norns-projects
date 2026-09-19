-- Analog Rytm MKII MIDI CC map (source: midi.guide / pencilresearch/midi
-- CSV, "Elektron/Analog Rytm MKII.csv").
--
-- track params go out on each track's own channel; FX params (delay,
-- reverb, distortion, compressor) reuse the same CC numbers but on the
-- Rytm's FX control channel -- that's how the Rytm tells them apart.
--
-- desc fields: see patchcore.lua. `cc` added here.
-- flags in the compact machine tables: "c" = centered, "l" = locked by default

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

-- each entry: 8 positions = CC 16..23. false = unused by that machine.
-- position spec: {name, min, max, flags, labels}
local LEV = {"LEV", 0, 127, "l"}
local TUNE = {"TUNE", 0, 127, "c"}

local MACHINES = {
  {"BD HARD",     {LEV, TUNE, {"DEC"}, {"HOLD"}, {"SWTIM"}, {"SWDEP"}, {"WAVE", 0, 2, "", SIN3}, {"TICK"}}},
  {"BD CLASSIC",  {LEV, TUNE, {"DEC"}, {"HOLD"}, {"SWTIM"}, {"SWDEP"}, {"WAVE", 0, 2, "", SIN3}, {"TICK", 0, 55}}},
  {"BD FM",       {LEV, TUNE, {"DEC"}, {"FMAMT"}, {"SWTIM"}, {"FMSWT"}, {"FMDEC"}, {"FMTUN"}}},
  {"BD PLASTIC",  {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"SWTIM"}, {"HOLD"}, {"CLICK"}, {"DUST"}}},
  {"BD SILKY",    {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"SWTIM"}, {"HOLD"}, {"CLICK"}, {"DUST"}}},
  {"BD SHARP",    {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"SWTIM"}, {"HOLD"}, {"TICK"}, {"WAVE", 0, 11, "", WAVE12}}},
  {"BD ACOUSTIC", {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"SWTIM"}, {"HOLD"}, {"IMPCT"}, {"WAVE", 0, 11, "", WAVE12}}},
  {"SD HARD",     {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"TICK"}, {"NSDEC"}, {"NSLEV"}, {"SWTIM"}}},
  {"SD CLASSIC",  {LEV, TUNE, {"DEC"}, {"DETUN"}, {"SNAP"}, {"NSDEC"}, {"NSLEV"}, {"BAL"}}},
  {"SD FM",       {LEV, TUNE, {"DEC"}, {"FMTUN", 0, 127, "c"}, {"FMDEC"}, {"NSDEC"}, {"NSLEV"}, {"FMAMT"}}},
  {"SD NATURAL",  {LEV, TUNE, {"BDDEC"}, {"NSDEC"}, {"NSLPF"}, {"NSBAL"}, {"NSRES"}, {"NSHPF"}}},
  {"SD ACOUSTIC", {LEV, TUNE, {"BDDEC"}, {"NSDEC"}, {"HOLD"}, {"NSLEV"}, {"IMPCT"}, {"SWDEP"}}},
  {"RS HARD",     {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"TICK"}, {"NOISE"}, {"SYMM"}, {"SWTIM"}}},
  {"RS CLASSIC",  {LEV, {"TUNE1", 0, 127, "c"}, {"DEC"}, {"BAL", 0, 127, "c"}, {"TUNE2", 0, 127, "c"},
                   {"SYMM", 0, 127, "c"}, {"NOISE"}, {"TICK"}}},
  {"CP CLASSIC",  {LEV, {"TONE"}, {"NSDEC"}, {"CLAPS"}, {"RATE"}, {"NOISE"}, {"RND"}, {"CPDEC"}}},
  {"BT CLASSIC",  {LEV, TUNE, {"DEC"}, false, {"NOISE"}, {"SNAP", 0, 3}, false, false}},
  {"XT CLASSIC",  {LEV, TUNE, {"DEC"}, {"SWDEP"}, {"SWTIM"}, {"NSDEC"}, {"NSLEV"}, {"NTONE", 0, 127, "c"}}},
  {"CH CLASSIC",  {LEV, TUNE, {"DEC"}, {"COLOR"}, false, false, false, false}},
  {"CH METALLIC", {LEV, TUNE, {"DEC"}, false, false, false, false, false}},
  {"OH CLASSIC",  {LEV, TUNE, {"DEC"}, {"COLOR", 0, 127, "c"}, false, false, false, false}},
  {"OH METALLIC", {LEV, TUNE, {"DEC"}, false, false, false, false, false}},
  {"HH BASIC",    {LEV, TUNE, {"DEC"}, {"TONE", 0, 127, "c"}, {"TRDEC"}, {"RESET", 0, 1, "", {"OFF", "ON"}}, false, false}},
  {"HH LAB",      {LEV, {"TUNE1", 0, 127, "c"}, {"DEC"}, {"TUNE2", 0, 127, "c"}, {"TUNE3", 0, 127, "c"},
                   {"TUNE4", 0, 127, "c"}, {"TUNE5", 0, 127, "c"}, {"TUNE6", 0, 127, "c"}}},
  {"CY CLASSIC",  {LEV, TUNE, {"DEC"}, {"COLOR", 0, 127, "c"}, {"TONE", 0, 127, "c"}, false, false, false}},
  {"CY METALLIC", {LEV, TUNE, {"DEC"}, {"TONE", 0, 127, "c"}, {"TRDEC"}, false, false, false}},
  {"CY RIDE",     {LEV, TUNE, {"TAIL"}, {"HIT"}, {"TYPE", 0, 3, "", {"A", "B", "C", "D"}}, {"CMP1"}, {"CMP2"}, {"CMP3"}}},
  {"CB CLASSIC",  {LEV, TUNE, {"DEC"}, {"DETUN"}, false, false, false, false}},
  {"CB METALLIC", {LEV, TUNE, {"DEC"}, {"DETUN"}, false, false, false, false}},
  {"SY DUAL VCO", {LEV, {"TUNE1", 0, 127, "c"}, {"DEC1"}, {"BAL", 0, 127, "c"}, {"DET2", 0, 127, "c"},
                   {"CONF", 0, 79, "d"}, {"DEC2"}, {"BEND", 0, 127, "c"}}},
  {"SY CHIP",     {LEV, TUNE, {"DEC"}, {"WAVE", 0, 127, "d"}, {"SPEED"},
                   {"OFS2", 40, 88, "c"}, {"OFS3", 40, 88, "c"}, {"OFS4", 40, 88, "c"}}},
  {"SY RAW",      {LEV, TUNE, {"DEC2"}, {"NOISE"}, {"DETUN", 40, 88, "c"},
                   {"WAV1", 0, 6, "", {"SIN", "ASIN", "TRI", "SSAW", "ASAW", "SAW", "RING"}},
                   {"WAV2", 0, 1, "", {"SIN", "SSAW"}}, {"BAL", 0, 127, "c"}}},
  {"UT NOISE",    {LEV, {"LPF"}, {"DEC"}, {"SWDEP", 0, 127, "c"}, {"SWTIM"}, {"LPRES"}, {"HPF"}, {"ATK"}}},
  {"UT IMPULSE",  {LEV, {"ATK"}, {"DEC"}, {"POLAR", 0, 1, "", {"POS", "NEG"}}, false, false, false, false}},
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
    d("TUNE", 24, 40, 88, {centered = true}),
    d("FINE", 25, 0, 127, {centered = true}),
    d("BITRD", 26, 0, 127, {rmax = 90}),
    -- random sample slots swap samples out from under you: locked by default
    d("SLOT", 27, 0, 127, {lock = true, discrete = true}),
    d("START", 28, 0, 120),
    d("END", 29, 0, 120),
    d("LOOP", 30, 0, 1, {labels = {"OFF", "ON"}}),
    d("LEVEL", 31, 0, 127),
  }},
  {name = "FILTER", slots = {
    d("ATK", 70), d("DEC", 71), d("SUS", 72), d("REL", 73),
    d("FREQ", 74, 0, 127, {rmin = 20}),
    d("RESO", 75, 0, 127, {rmax = 110}),
    d("TYPE", 76, 0, 6, {labels = FILTER_TYPES}),
    d("ENV", 77, 0, 127, {centered = true}),
  }},
  {name = "AMP", slots = {
    d("ATK", 78, 0, 127, {rmax = 60}),
    d("HOLD", 79), d("DEC", 80),
    d("DRIVE", 81, 0, 127, {rmax = 90}),
    d("DELAY", 82, 0, 127, {rmax = 90}),
    d("REVRB", 83, 0, 127, {rmax = 90}),
    d("PAN", 10, 0, 127, {centered = true}),
    d("VOL", 7, 0, 127, {lock = true, default = 100}),
  }},
  {name = "LFO", slots = {
    d("SPEED", 102, 0, 127, {centered = true}),
    d("MULT", 103, 0, 23, {labels = LFO_MULT}),
    d("FADE", 104, 0, 127, {centered = true}),
    d("DEST", 105, 0, 41, {discrete = true}),
    d("WAVE", 106, 0, 6, {labels = LFO_WAVES}),
    d("PHASE", 107),
    d("TRIG", 108, 0, 4, {labels = LFO_TRIG}),
    d("DEPTH", 109, 0, 127, {centered = true}),
  }},
}

---------------------------------------------------------------- fx pages

Map.fx_pages = {
  {name = "DELAY", slots = {
    d("TIME", 16),
    d("PING", 17, 0, 1, {labels = {"OFF", "ON"}}),
    d("WIDTH", 18, 0, 127, {centered = true}),
    d("FDBK", 19, 0, 127, {rmax = 105}),
    d("HPF", 20, 0, 127, {rmax = 90}),
    d("LPF", 21, 0, 127, {rmin = 40}),
    d("REVRB", 22),
    d("MIX", 23),
  }},
  {name = "REVERB", slots = {
    d("PRE", 24), d("DECAY", 25), d("SHLFF", 26), d("SHLFG", 27),
    d("HPF", 28, 0, 127, {rmax = 90}),
    d("LPF", 29, 0, 127, {rmin = 40}),
    false,
    d("MIX", 31),
  }},
  {name = "DIST", slots = {
    d("AMT", 70, 0, 127, {rmax = 100}),
    d("SYMM", 71),
    d("DRIVE", 72, 0, 127, {rmax = 100}),
    false,
    d("DLY", 76, 0, 1, {labels = {"PRE", "POST"}}),
    d("REV", 77, 0, 1, {labels = {"PRE", "POST"}}),
    false, false,
  }},
  {name = "COMP", slots = {
    d("THRS", 78),
    d("ATK", 79, 0, 6, {discrete = true}),
    d("REL", 80, 0, 7, {discrete = true}),
    d("GAIN", 81, 0, 127, {rmax = 64}),
    d("RATIO", 82, 0, 3, {labels = {"1:2", "1:4", "1:8", "MAX"}}),
    d("SC EQ", 83, 0, 3, {labels = {"OFF", "LPF", "HPF", "HIT"}}),
    d("MIX", 84),
    d("VOL", 85, 0, 127, {lock = true, default = 100}),
  }},
}

return Map
