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
- Default locks keep a first randomize from silencing things or swapping
  samples: synth LEV, AMP VOL, COMP VOL, SAMPLE SLOT. Randomization windows
  (`rmin`/`rmax` in the map) tame feedback/reso/drive/comp gain.
- `lib/patchcore.lua` + `lib/pageview.lua` are shared with summitpatch as
  identical copies (same convention as garc.lua): locks, drift-style random
  amount, range low/high, morph over beats, one-level undo/redo (press
  again = redo), wander, pset persistence. Edit one → copy to the other.
- Morph drops a param the moment something else moves it (encoder, wander,
  incoming CC), so morphs never fight the user.

## Open items / unverified
- Rytm-side defaults: FX control channel assumed 13 and track channels 1-12
  — both are params, verify against the Rytm's MIDI CONFIG > CHANNELS.
- Audition (off by default) sends note 60 on the track channel, assuming
  the Rytm plays the track chromatically from a note on its own channel.
- Sending machine type (CC 15) was left out: the CSV's value→machine
  list looks off (lists RS Hard twice), and changing machines remotely is
  destructive. Could come back as an explicit "send machine" trigger.
- Not mapped yet: trig page (CC 3-5, 11-14), euclidean (86-91, 117),
  performance macros (35-47), scenes (92), track mute/solo (93-95), LFO
  depth's 14-bit LSB (CC 118, only MSB is sent).
- Grid/arc: none yet. Arc via garc.lua would suit a page of 8 → 2 pages of 4.
- Smoke-tested on desktop Lua with stubbed norns APIs only (every page/key
  combo, morph, wander, pset round trip, incoming CC). Screen layout
  (name/value widths in 62px cells) hasn't been checked on a real screen.
