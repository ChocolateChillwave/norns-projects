-- Novation Summit / Peak MIDI map (source: midi.guide / pencilresearch/midi
-- CSV, "Novation/Summit and Peak.csv").
--
-- everything on the CC pages is a plain 7-bit CC, which is reliable. the
-- STRUCT page uses NRPNs, whose value ranges the CSV doesn't document
-- (it lists every NRPN as 0-16383) -- the ranges there are from memory of
-- the Peak manual and are UNVERIFIED. that page is locked by default so
-- randomize-all never touches it until you unlock params on purpose.
--
-- env naming: Summit's Env 1 = amp env, Env 2 = "Mod 1", Env 3 = "Mod 2".
--
-- TAMING POLICY (rmin/rmax + bias)
-- min/max stays the real CC range so nothing is unreachable by hand;
-- rmin/rmax is the slice randomize/wander may land in by default:
--   * pitch stays put -- osc range/coarse and every pitch-mod depth start
--     locked, and fine detune gets a narrow window, so a random patch is
--     still in tune and still plays the note you asked for
--   * amp attack biases short and sustain high, so a roll is audible when
--     you press a key rather than a four-second swell you have to wait out
--   * cutoff avoids the bottom of its range (silence) and biases up;
--     resonance stays below self-oscillation
--   * anything that gets loud fast -- distortion, filter drive/post-drive,
--     noise and ring mod levels, delay feedback -- is capped low
-- PARAMETERS > RANDOMIZE > "widen range" opens every window toward the
-- full range at once, recipes replace the windows per param, and K3 on a
-- single param cycles it tame -> wide -> locked.

local Map = {}

local function cc(id, name, num, opts)
  local t = {id = id, name = name, cc = num, min = 0, max = 127}
  if opts then for k, v in pairs(opts) do t[k] = v end end
  if t.labels then t.discrete = true end
  return t
end

local function nrpn(id, name, msb, lsb, max, opts)
  local t = {id = id, name = name, nrpn = {msb, lsb}, min = 0, max = max, lock = true}
  if opts then for k, v in pairs(opts) do t[k] = v end end
  if t.labels then t.discrete = true end
  return t
end

-- shared windows
local W_DETUNE = {58, 70}   -- fine/detune: audible beating, still in tune
local W_PITCHMOD = {58, 70} -- only reached once these are unlocked
local W_MODDEPTH = {54, 84} -- shape/filter mod depths, from centre upward
local W_SHAPE = {40, 100}

Map.pages = {
  {name = "OSC 1", slots = {
    cc("o1_range", "RANGE", 3, {lock = true, rmin = 40, rmax = 90}),
    cc("o1_coarse", "COARS", 14, {centered = true, lock = true, rmin = 58, rmax = 70}),
    cc("o1_fine", "FINE", 15, {centered = true, rmin = W_DETUNE[1], rmax = W_DETUNE[2], bias = "center"}),
    cc("o1_shape", "SHAPE", 12, {centered = true, rmin = W_SHAPE[1], rmax = W_SHAPE[2]}),
    cc("o1_m1shape", "E2>SH", 119, {centered = true, rmin = W_MODDEPTH[1], rmax = W_MODDEPTH[2]}),
    cc("o1_l1shape", "L1>SH", 33, {centered = true, rmin = W_MODDEPTH[1], rmax = W_MODDEPTH[2]}),
    cc("o1_vsync", "VSYNC", 34, {rmin = 0, rmax = 40, bias = "low"}),
    false,
  }},
  {name = "OSC 2", slots = {
    cc("o2_range", "RANGE", 37, {lock = true, rmin = 40, rmax = 90}),
    cc("o2_coarse", "COARS", 17, {centered = true, lock = true, rmin = 58, rmax = 70}),
    cc("o2_fine", "FINE", 18, {centered = true, rmin = W_DETUNE[1], rmax = W_DETUNE[2], bias = "center"}),
    cc("o2_shape", "SHAPE", 39, {centered = true, rmin = W_SHAPE[1], rmax = W_SHAPE[2]}),
    cc("o2_m1shape", "E2>SH", 40, {centered = true, rmin = W_MODDEPTH[1], rmax = W_MODDEPTH[2]}),
    cc("o2_l1shape", "L1>SH", 41, {centered = true, rmin = W_MODDEPTH[1], rmax = W_MODDEPTH[2]}),
    cc("o2_vsync", "VSYNC", 42, {rmin = 0, rmax = 40, bias = "low"}),
    false,
  }},
  {name = "OSC 3", slots = {
    cc("o3_range", "RANGE", 65, {lock = true, rmin = 40, rmax = 90}),
    cc("o3_coarse", "COARS", 20, {centered = true, lock = true, rmin = 58, rmax = 70}),
    cc("o3_fine", "FINE", 21, {centered = true, rmin = W_DETUNE[1], rmax = W_DETUNE[2], bias = "center"}),
    cc("o3_shape", "SHAPE", 71, {centered = true, rmin = W_SHAPE[1], rmax = W_SHAPE[2]}),
    cc("o3_m1shape", "E2>SH", 72, {centered = true, rmin = W_MODDEPTH[1], rmax = W_MODDEPTH[2]}),
    cc("o3_l1shape", "L1>SH", 73, {centered = true, rmin = W_MODDEPTH[1], rmax = W_MODDEPTH[2]}),
    cc("o3_vsync", "VSYNC", 44, {rmin = 0, rmax = 40, bias = "low"}),
    cc("o3_filter", "O3>FL", 76, {rmin = 0, rmax = 50, bias = "low"}),
  }},
  -- every pitch-mod depth starts locked: these are what make a random
  -- patch wander off-key or sweep out of the audible range
  {name = "PITCH MOD", slots = {
    cc("o1_m2pitch", "1E3>P", 9, {centered = true, lock = true, rmin = W_PITCHMOD[1], rmax = W_PITCHMOD[2]}),
    cc("o1_l2pitch", "1L2>P", 16, {centered = true, lock = true, rmin = W_PITCHMOD[1], rmax = W_PITCHMOD[2]}),
    cc("o2_m2pitch", "2E3>P", 38, {centered = true, lock = true, rmin = W_PITCHMOD[1], rmax = W_PITCHMOD[2]}),
    cc("o2_l2pitch", "2L2>P", 19, {centered = true, lock = true, rmin = W_PITCHMOD[1], rmax = W_PITCHMOD[2]}),
    cc("o3_m2pitch", "3E3>P", 43, {centered = true, lock = true, rmin = W_PITCHMOD[1], rmax = W_PITCHMOD[2]}),
    cc("o3_l2pitch", "3L2>P", 22, {centered = true, lock = true, rmin = W_PITCHMOD[1], rmax = W_PITCHMOD[2]}),
    cc("glide_time", "GLIDE", 5, {rmin = 0, rmax = 40, bias = "low"}),
    cc("glide_on", "GL ON", 35, {lock = true}),
  }},
  {name = "MIX", slots = {
    cc("mix_o1", "OSC1", 23, {rmin = 70, rmax = 127, bias = "high"}),
    cc("mix_o2", "OSC2", 24, {rmin = 30, rmax = 127}),
    cc("mix_o3", "OSC3", 25, {rmin = 0, rmax = 110}),
    cc("mix_ring", "RING", 26, {rmin = 0, rmax = 45, bias = "low"}),
    cc("mix_noise", "NOISE", 27, {rmin = 0, rmax = 40, bias = "low"}),
    false,
    cc("dist", "DIST", 104, {rmin = 0, rmax = 40, bias = "low"}),
    cc("arp_gate", "ARPGT", 116, {lock = true}),
  }},
  {name = "FILTER", slots = {
    cc("cutoff", "FREQ", 29, {rmin = 45, rmax = 120, bias = "high"}),
    cc("reso", "RESO", 79, {rmin = 0, rmax = 70, bias = "low"}),
    cc("f_track", "TRACK", 75, {rmin = 30, rmax = 127}),
    cc("f_drive", "DRIVE", 80, {rmin = 0, rmax = 50, bias = "low"}),
    cc("f_post", "POST", 36, {rmin = 0, rmax = 50, bias = "low"}),
    cc("f_env2", "E2>FL", 78, {centered = true, rmin = 64, rmax = 104}),
    cc("f_lfo1", "L1>FL", 28, {centered = true, rmin = 54, rmax = 80}),
    cc("f_env1", "E1>FL", 77, {centered = true, rmin = 54, rmax = 90}),
  }},
  {name = "AMP ENV", slots = {
    cc("amp_a", "ATK", 86, {rmin = 0, rmax = 25, bias = "low"}),
    cc("amp_d", "DEC", 87, {rmin = 25, rmax = 110}),
    cc("amp_s", "SUS", 88, {rmin = 50, rmax = 127, bias = "high"}),
    cc("amp_r", "REL", 89, {rmin = 10, rmax = 70}),
    false, false,
    cc("anim1", "ANIM1", 114, {lock = true}),
    cc("anim2", "ANIM2", 115, {lock = true}),
  }},
  {name = "MOD ENVS", slots = {
    cc("m1_a", "E2 A", 90, {rmin = 0, rmax = 40, bias = "low"}),
    cc("m1_d", "E2 D", 91, {rmin = 20, rmax = 110}),
    cc("m1_s", "E2 S", 92, {rmin = 0, rmax = 110}),
    cc("m1_r", "E2 R", 93, {rmin = 0, rmax = 80}),
    cc("m2_a", "E3 A", 94, {rmin = 0, rmax = 40, bias = "low"}),
    cc("m2_d", "E3 D", 95, {rmin = 20, rmax = 110}),
    cc("m2_s", "E3 S", 117, {rmin = 0, rmax = 110}),
    cc("m2_r", "E3 R", 103, {rmin = 0, rmax = 80}),
  }},
  {name = "LFOS", slots = {
    cc("l1_rate", "L1 RT", 30, {rmin = 20, rmax = 100}),
    cc("l1_sync", "L1 SY", 81, {lock = true}),
    cc("l1_fade", "L1 FD", 82, {centered = true, rmin = 54, rmax = 74}),
    false,
    cc("l2_rate", "L2 RT", 31, {rmin = 20, rmax = 100}),
    cc("l2_sync", "L2 SY", 84, {lock = true}),
    cc("l2_fade", "L2 FD", 85, {centered = true, rmin = 54, rmax = 74}),
    cc("l2_range", "L2 RG", 83, {lock = true}),
  }},
  {name = "FX", slots = {
    cc("cho_lvl", "CHO", 105, {rmin = 0, rmax = 70}),
    cc("cho_rate", "CH RT", 118, {rmin = 20, rmax = 90}),
    cc("cho_fb", "CH FB", 107, {rmin = 0, rmax = 60, bias = "low"}),
    cc("rev_lvl", "REV", 112, {rmin = 0, rmax = 70}),
    cc("dly_lvl", "DLY", 108, {rmin = 0, rmax = 60}),
    cc("dly_time", "DL TM", 109),
    cc("dly_fb", "DL FB", 110, {rmin = 20, rmax = 70}),
    cc("rev_time", "REV T", 113, {rmin = 30, rmax = 100}),
  }},
  {name = "STRUCT", nrpn_page = true, slots = {
    nrpn("o1_wave", "O1 WV", 0, 14, 4, {labels = {"SIN", "TRI", "SAW", "PULS", "MORE"}, rmax = 3}),
    nrpn("o2_wave", "O2 WV", 0, 23, 4, {labels = {"SIN", "TRI", "SAW", "PULS", "MORE"}, rmax = 3}),
    nrpn("o3_wave", "O3 WV", 0, 32, 4, {labels = {"SIN", "TRI", "SAW", "PULS", "MORE"}, rmax = 3}),
    nrpn("f_slope", "SLOPE", 0, 45, 1, {labels = {"12dB", "24dB"}}),
    nrpn("f_shape", "SHAPE", 25, 9, 2, {labels = {"LP", "BP", "HP"}, rmax = 0}),
    nrpn("o1_dense", "DENSE", 0, 17, 127, {rmin = 0, rmax = 60}),
    nrpn("o1_detune", "DETUN", 0, 18, 127, {rmin = 0, rmax = 60}),
    nrpn("drift", "DRIFT", 0, 10, 127, {rmin = 0, rmax = 60, bias = "low"}),
  }},
}

-- id -> desc, cc -> desc
Map.by_id = {}
Map.by_cc = {}
Map.cc_ids = {} -- ordered list of CC-addressed ids, for AFX target selection
for _, pg in ipairs(Map.pages) do
  for i = 1, 8 do
    local desc = pg.slots[i]
    if desc then
      Map.by_id[desc.id] = desc
      if desc.cc then
        Map.by_cc[desc.cc] = desc
        Map.cc_ids[#Map.cc_ids + 1] = desc.id
      end
    end
  end
end

---------------------------------------------------------------- recipes
-- per-recipe randomization windows {lo, hi} replacing a desc's tame
-- window. params not listed keep their tame window. "chaos" ignores every
-- window and uses each param's full range (locks still apply).

Map.recipe_names = {"any", "bass", "pad", "lead", "pluck", "perc", "drone", "chaos"}

Map.recipes = {
  bass = {
    amp_a = {0, 8}, amp_d = {30, 90}, amp_s = {60, 127}, amp_r = {0, 30},
    cutoff = {10, 70}, reso = {0, 80}, f_drive = {0, 70},
    mix_o1 = {80, 127}, mix_ring = {0, 20}, mix_noise = {0, 15},
    cho_lvl = {0, 30}, dly_lvl = {0, 20}, rev_lvl = {0, 15},
    glide_time = {0, 40},
  },
  pad = {
    amp_a = {40, 110}, amp_d = {60, 127}, amp_s = {80, 127}, amp_r = {60, 127},
    m1_a = {30, 110}, m1_d = {60, 127},
    cutoff = {30, 100}, reso = {0, 60}, mix_noise = {0, 30},
    l1_rate = {0, 50}, l2_rate = {0, 50},
    cho_lvl = {50, 127}, dly_lvl = {20, 80}, rev_lvl = {50, 127}, rev_time = {60, 127},
  },
  lead = {
    amp_a = {0, 20}, amp_s = {70, 127}, amp_r = {10, 60},
    cutoff = {50, 127}, reso = {10, 90},
    glide_time = {0, 60}, dly_lvl = {20, 80}, rev_lvl = {10, 60},
  },
  pluck = {
    amp_a = {0, 4}, amp_d = {15, 60}, amp_s = {0, 15}, amp_r = {5, 50},
    m1_a = {0, 4}, m1_d = {10, 60}, m1_s = {0, 25},
    f_env2 = {84, 127}, cutoff = {0, 60}, reso = {10, 90},
    dly_lvl = {10, 70},
  },
  perc = {
    amp_a = {0, 2}, amp_d = {0, 40}, amp_s = {0, 0}, amp_r = {0, 30},
    m1_a = {0, 2}, m1_d = {0, 40}, m1_s = {0, 10},
    mix_noise = {20, 127}, mix_ring = {0, 127}, f_env2 = {64, 127},
    rev_lvl = {0, 60},
  },
  drone = {
    amp_a = {60, 127}, amp_s = {100, 127}, amp_r = {90, 127},
    l1_rate = {0, 40}, l2_rate = {0, 40},
    f_lfo1 = {40, 88}, o1_l1shape = {30, 98}, o2_l1shape = {30, 98},
    rev_lvl = {60, 127}, rev_time = {80, 127}, dly_fb = {40, 100}, cho_lvl = {30, 127},
  },
}

-- default AFX overlay targets: the 8 params that make the most obvious
-- per-key difference without detuning anything
Map.afx_defaults = {"cutoff", "reso", "o1_shape", "o2_shape", "mix_noise", "amp_d", "m1_d", "dist"}

return Map
