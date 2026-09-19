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
- Tuning params (osc range/coarse/fine, all pitch-mod depths), glide on,
  LFO sync, arp gate and animate holds are locked by default, so the first
  "randomize whole patch" stays playable and in tune.
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
- Smoke-tested on desktop Lua with stubbed norns APIs only.
