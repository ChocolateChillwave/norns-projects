# summitpatch — status notes

Patch randomizer + AFX-mode-style per-key overlays for the Novation
Summit/Peak. MIDI-out only, no engine. Started 2026-09-16; not yet run on a
device or against a real Summit.

## Key decisions
- CC map from the pencilresearch/midi CSV behind midi.guide
  (`Novation/Summit and Peak.csv`). The CC pages use only plain 7-bit CCs.
- The CSV lists every NRPN as 0-16383 with no labels, so the STRUCT page
  (osc waves, filter slope/shape, saw density/detune, drift) uses ranges
  from memory of the Peak manual. **Unverified.** Every STRUCT param is
  locked by default, and NRPNs are sent as CC99/98 + value on CC6 (LSB
  CC38 = 0).
- **Taming (2026-09-19).** Randomize used to walk each CC's whole range,
  so a rolled patch was as likely to be a silent, detuned, distorted mess
  as a playable sound. Every param now carries a *tame window*
  (`rmin`/`rmax`) plus an optional `bias` ("low"/"high"/"center") shaping
  the draw inside it, and that's all randomize/wander reach by default.
  Sampled over 2000 rolls: amp attack mean 8/127 (was 63), sustain mean
  100 never below 50, cutoff mean 94 never below 45, resonance mean 24
  capped at 70, noise mix mean 14 capped at 40.
  - min/max stays the real CC range, so **nothing is unreachable by hand**.
  - Opening up: K3 cycles one param tame → wide → locked; "widen range"
    (0-100%) blends every window toward full at once; the chaos recipe
    forces 100%. Bias fades out as the window opens.
  - Windows show as ticks on each param's bar, and they follow the active
    recipe, so switching to `pad` visibly moves the windows.
- Tuning params (osc range/coarse, all pitch-mod depths), glide on, LFO
  sync, arp gate and animate holds are locked by default; osc fine is left
  free but with a narrow window, so patches detune musically without ever
  playing the wrong note.
- Recipes (bass/pad/lead/pluck/perc/drone) only override randomization
  *windows* per param id (`Map.recipes`); "any" uses the map's own windows;
  "chaos" uses full range everywhere. Locks always win.
- AFX overlays: 12 keys (by note name) or 24 (two octaves from "first
  key"). Each key stores offsets for 8 target params (targets are real params,
  so they persist in psets). On note-on the overlay (base + offset × depth)
  is sent, then the note passes through. CCs whose value hasn't changed are
  skipped. Release mode "return" restores base values once all notes are up.
  Base-patch edits/morph/wander send base values and temporarily override
  an overlay until the next note, which is acceptable for now.
- Note thru default "auto": passes notes only when input port ≠ Summit port.
  When they're the same port, the Summit's own keys would otherwise be
  echoed back and double every note. CCs arriving from the Summit's port
  are mirrored onto the screen, never echoed back.
- Sound data + AFX offsets saved beside each pset via action_write/read
  (same reasoning as rytmpatch); `summitpatch-last.data` autosaves.
- Shares `lib/patchcore.lua` + `lib/pageview.lua` with rytmpatch as
  identical copies.

## Open items / unverified
- Verify STRUCT NRPN encoding + ranges on hardware (wave 0-4, slope 0-1,
  shape 0-2). If they misbehave, drop the page or correct the ranges.
- Summit is bitimbral: this only addresses one channel ("summit channel").
  Layer B / Multi part B addressing isn't handled — likely just a second
  channel, not checked.
- Polyphony: CCs are patch-global, so an overlay affects every held voice.
  That's inherent to doing AFX over MIDI; it's most AFX-like with the Summit
  in mono/legato voice mode.
- CCs for "Amp filter" (77), "Mod 1 filter" (78), "Osc 3 filter" (76) are
  labeled E1>FL / E2>FL / O3>FL on the assumption they're env→filter
  depths and osc3→filter FM. Confirm by ear.
- Ideas not built: stored patch scenes A-D with an E3 crossfade, "breed"
  (random child of two stored patches), mod-matrix depth NRPNs
  (MSB 1-16 LSB 2) as a MOD MX page, arc support via garc.lua, grid as a
  key-slot picker for AFX.
- Tame windows are judgement calls made off-device. Worth checking by ear:
  the fine-detune window (58-70 may be too narrow to hear), cutoff's floor
  of 45, and whether `perc`/`drone` recipes still read as themselves now
  that the base windows are tighter.
- AFX offsets are deliberately *not* windowed — an overlay is a deviation
  from the base patch, and it's clamped to the param's range when applied.
  "random spread" (±127) is the control there. If per-key rolls turn out
  to need taming too, that's the knob to revisit.
- Tests: `test/` runs on desktop Lua, no norns needed (see CLAUDE.md).
  `lua summitpatch/test/test_taming.lua` covers the map, windows, bias,
  modes and recipes (~480 assertions); `lua summitpatch/test/test_script.lua`
  drives init/pages/keys/recipes/psets/cleanup plus the AFX path — that
  overlay CCs precede the note, that replaying a key resends nothing, and
  that auto-thru doesn't echo the Summit's own notes back at it.
  `test/norns_stub.lua` is byte-identical to rytmpatch's copy.
