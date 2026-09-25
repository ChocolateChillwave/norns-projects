# rytmpatch — status notes

MIDI CC patch randomizer/editor for the Elektron Analog Rytm MKII, modeled on
MDPatch (hanjo-synth, for the Machinedrum). MIDI-out only, no engine.
Started 2026-09-16; not yet run on a device or against a real Rytm.

## Key decisions
- CC map from the pencilresearch/midi CSV behind midi.guide
  (`Elektron/Analog Rytm MKII.csv`), not the rendered page — the page summary
  drops value ranges and labels.
- Pages: 5 per track (SYNTH SAMPLE FILTER AMP LFO) + 4 FX (DELAY REVERB DIST
  COMP). Every page is at most 8 params, like MDPatch's subpages, so the 2x4
  screen grid fits with no scrolling.
- FX params reuse CCs 16-31/70-85 and are told apart only by channel (the
  Rytm's FX control channel), so FX pages are one global scope, not per track.
- SYNTH page labels + ranges come from a per-track *label-only* machine param
  (PARAMETERS > MACHINES). Values are keyed by track+CC, not machine, so
  switching the label never loses values. Machine type is NOT sent to the
  Rytm (see open items).
- Sound data (≈500 values + locks) lives in a table saved via
  `params.action_write/read` next to each pset, not as norns params — 500
  params would bury the PARAMETERS menu. Settings (channels, amounts, morph,
  machines) are real params. Last session also autosaves to
  `rytmpatch-last.data` on cleanup and reloads on init *without* sending.
- **Taming (2026-09-19).** Randomize used to walk each CC's whole range,
  which made extreme sounds far too easy — sub-audible tunings, 4-second
  attacks, overdrive at 120, runaway delay feedback. Now every param in the
  map carries a *tame window* (`rmin`/`rmax`) plus an optional `bias`
  ("low"/"high"/"center") shaping the draw inside it, and that window is
  all randomize/wander can reach by default. Sampled over 2000 rolls: amp
  attack mean 6/127 (was 64), overdrive mean 18 max 55 (was 64/127),
  cutoff mean 100 never below 45 (was 62, often silent), BD tune stays
  within ±16 of centre (was ±64).
  - min/max stays the real CC range, so **nothing is unreachable by hand** —
    taming constrains the dice only.
  - **Outliers (2026-09-20).** A hard window edge made extremes
    unreachable by the dice rather than merely rare, which loses the
    occasional 4-second attack or slammed-shut filter that makes a roll
    interesting. "outliers" (default 10%) is the per-param chance of
    ignoring the window and drawing uniformly from outside it. 0% = the
    strict window.
  - `hard = "min"/"max"/"both"` exempts a param from outliers on the
    dangerous side: delay feedback and compressor makeup gain, both
    hard at the top. It blocks the dice only — "wide" mode and widen
    range still open those params fully, since both are deliberate.
  - Three opening-up routes, in increasing order of commitment: K3 cycles
    one param tame → wide → locked; PARAMETERS > RANDOMIZE > "widen range"
    (0-100%) blends every window toward its full range at once; and bias
    strength fades out as the window opens, so 100% really is uniform.
  - Windows are visible on screen as ticks on each param's bar, so what
    the dice can do is readable rather than a hidden table.
- Default locks keep a first randomize from silencing things or swapping
  samples: synth LEV, AMP VOL, COMP VOL, SAMPLE SLOT.
- `lib/patchcore.lua` + `lib/pageview.lua` are shared with summitpatch as
  identical copies (same convention as garc.lua): locks, drift-style random
  amount, range low/high, morph over beats, one-level undo/redo (press
  again = redo), wander, pset persistence. Edit one → copy to the other.
- Morph drops a param the moment something else moves it (encoder, wander,
  incoming CC), so morphs never fight the user.

## Open items / unverified
- **Channels verified on the device 2026-09-24** (MIDI CONFIG > CHANNELS):
  tracks on **1-12 in order**, FX on **13** — exactly what the script
  assumed, so `track ch` and `fx ch` keep their defaults. Note receive and
  parameter receive are both enabled on the Rytm, so the CCs will land.
- Also on that page: **auto channel 14**, **perf channel 15**. The auto
  channel addresses whichever track is currently selected on the Rytm
  rather than a fixed one, so it is the channel to use for a "follow the
  machine" feature, not for addressing a known track. The perf channel is
  where the performance macros listen — see the unmapped list below.
- Audition (off by default) sends note 60 on the track channel, assuming
  the Rytm plays the track chromatically from a note on its own channel.
  The channel half of that is confirmed now; note 60 itself is not.
- Sending machine type (CC 15) was left out: the CSV's value→machine
  list looks off (lists RS Hard twice), and changing machines remotely is
  destructive. Could come back as an explicit "send machine" trigger.
- Not mapped yet: trig page (CC 3-5, 11-14), euclidean (86-91, 117),
  performance macros (35-47), scenes (92), track mute/solo (93-95), LFO
  depth's 14-bit LSB (CC 118, only MSB is sent). The macros and scenes
  would go out on the perf channel (15 here), not a track channel — a
  third scope alongside track and FX, so they need their own param.
- Grid/arc: none yet. Arc via garc.lua would suit a page of 8 → 2 pages of 4.
- The tame windows are judgement calls made off-device, not measured
  against a Rytm — the ones worth re-checking by ear first are LFO DEPTH
  (54-74 may be too shy), SAMPLE START/END (deliberately near-full so a
  roll can't mute a sample) and FILTER FREQ's floor of 45.
- Tests: `test/` runs on desktop Lua, no norns needed (see CLAUDE.md).
  `lua rytmpatch/test/test_taming.lua` covers the map + windows/bias/modes
  (~1200 assertions, including "no roll ever escapes its window" and "the
  encoder still reaches both ends"); `lua rytmpatch/test/test_script.lua`
  drives init/pages/keys/encoders/morph/psets/cleanup. `test/norns_stub.lua`
  is byte-identical to summitpatch's copy.
- Screen layout (name/value widths in 62px cells, window ticks) still
  hasn't been checked on a real screen.
