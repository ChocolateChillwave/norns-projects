# roadmap — what's next, across all scripts

The cross-script view: where each script stands, what the next move is, and
what's waiting on a norns being in front of you.

**This file does not hold the detail.** Per-script decisions, rationale and
the full open-questions list live in each script's own `NOTES.md`, and that
stays the source of truth (see `CLAUDE.md`). What's here is the layer above:
status, ordering, and the things that belong to no single script. Each entry
links to the `NOTES.md` section with the reasoning.

Last reconciled against the code: **2026-09-21**.

## Status

| Script | On hardware? | Tests | Manual | Shape it's in |
|---|---|---|---|---|
| [cascade](cascade/NOTES.md) | partly — 2026-09-16, "working fairly well" | 238 | yes | Six batches have landed since that pass, including the whole crow/JF backend. Most-developed script here, and the one whose tested-vs-shipped gap is widest. |
| [polyphasic](polyphasic/NOTES.md) | yes — 2026-09-15 | **none** | no | Works and has been played. The arc changes of 2026-09-19 are untested and it has no suite to catch regressions. |
| [segue](segue/NOTES.md) | yes — v0.8 played 2026-09-21, "good" | 2147 | yes | In regular play. v0.8 added eight genre banks, global→lane→pattern setting inheritance and a redesigned FX grid, and its first session went well. Still unjudged specifically: whether the banks' kits interplay, and CPU at 96 PPQN. |
| [rytmpatch](rytmpatch/NOTES.md) | no | 1283 | no | Complete but unproven, and its MIDI channel defaults are known-suspect. |
| [summitpatch](summitpatch/NOTES.md) | no | 541 | no | Complete but unproven; a whole page (STRUCT) rests on unverified NRPN ranges. |

4,225 checks total, all passing — `lua run-tests.lua` from the repo root.

**The headline:** three of five scripts have never run on the device, and
the two that have are both now ahead of their last hardware pass. Test
coverage is good and buys real confidence in the logic, but nothing here
has verified a screen layout, a grid brightness, MIDI timing, or CPU load.
Desk testing has gone about as far as it usefully can on segue, rytmpatch
and summitpatch — the next real progress on those three is device time,
not more code.

## Next move per script

One thing each, in the order I'd do them:

1. **rytmpatch — confirm the MIDI channels.** Cheapest high-value item in
   the repo and it unblocks others. Its defaults (FX on 13, tracks on 1-12)
   were assumed, and segue's hardware session established that at least the
   track-channel part doesn't match your Rytm. Read the Rytm's MIDI CONFIG >
   CHANNELS once and both scripts get correct defaults. Also settles whether
   segue's "notes 0-11" layout is a deliberate config. → *rytmpatch Open
   items; segue Open items.*
2. **segue — hear the transitions.** MIDI is confirmed and the library is
   rebuilt, so the one thing the script exists for is now the only thing
   blocking it: does a legato hand-off landing mid-bar actually sound
   continuous? Unprovable at a desk. It ships in `focus` mode with the
   performance layer hidden precisely so this is what you judge. Watch CPU
   while you're there — the 96 PPQN master clock ticking eight lanes is the
   busiest thing in the repo and has never been measured on a Pi.
   → *segue Plan, phase 1.*
3. **cascade — hardware pass on crow/JF and on round 2.** Two cheap-to-change
   guesses are waiting on your ears: level 0 as sustain's note-off, and
   1-10V as the level range. Same session covers the round-2 playability
   questions and the string view's CPU cost. → *cascade Crow / Just Friends;
   Open items.*
4. **polyphasic — give it a test suite.** The only script without one, and
   its arc module just changed underneath it untested. Copying
   `cascade/test/test_arc.lua` alone covers the module that moved, for
   almost no effort. → *below, and polyphasic Added (2026-09-19).*
5. **summitpatch — verify the STRUCT page.** Its NRPN ranges come from
   memory of the Peak manual, not a document. Everything on the page is
   locked by default, so the risk is contained, but the page is either
   correct or it should go. → *summitpatch Open items.*

## Waiting on a norns

Gathered from the five NOTES files so there's one list to work from when
the hardware's in front of you. Detail and reasoning in each script's notes.

**rytmpatch** — MIDI CONFIG channels; whether audition's note 60 on the
track channel does what's assumed; tame windows worth re-hearing (LFO
DEPTH, SAMPLE START/END, FILTER FREQ's floor of 45); screen layout in 62px
cells.

**segue** — do the transitions sound like transitions; screen layout; grid
brightness choices; CPU at 96 PPQN (raised 2026-09-20, 4x the wakeups);
Ableton Link; whether finer swing actually improves the breaks.

**cascade** — crow/JF's two guesses; does a merged strum read clearly with
2-3 chords held; is 300ms the right default release; do morph/every feel
musical at tempo; is humanize too subtle at the low end; string view CPU;
how the chord banks actually sound (written in-key and well-formed, never
heard).

**summitpatch** — STRUCT NRPN encoding and ranges; the three guessed CC
labels (77 / 78 / 76); fine-detune and cutoff windows; whether `perc` and
`drone` still read as themselves post-taming.

**polyphasic** — the 2026-09-19 arc work (`poll()` and the new styles) has
never been seen on a real arc.

**Any script** — open segue's SELECT preview and see whether its ~36-character
header lines fit the screen. The preview doesn't wrap, and CONVENTIONS §2
sets the house width on that number without it having been measured.

## Cross-cutting

- **Three norns_stub.lua copies have diverged.** rytmpatch's and
  summitpatch's are byte-identical; cascade's and segue's are each their
  own. cascade's is the richest — a virtual clock, musicutil, several
  params gaps, `midi.to_msg` — and its own notes flag that the generic
  parts belong back in segue's copy. Worth one consolidation pass, ideally
  before a sixth script copies whichever one it happens to find first.
- **Shared files are in sync as of 2026-09-19** (checked, not assumed):
  `garc.lua` is identical across cascade, polyphasic and segue apart from
  its header comment, and `patchcore.lua` + `pageview.lua` are byte-identical
  between rytmpatch and summitpatch. These are kept in step by hand, so
  re-check after editing any of them — `md5sum */lib/garc.lua` is enough.
- **rytmpatch × segue integration** — patch randomization running while
  patterns play, with a patch morph triggered *by* a follow action. Both
  halves exist and `patchcore.lua` was deliberately built to be copied. Do
  the channel verification above first, then this is mostly a UI-placement
  question. → *segue Open items.*
- **No manual for polyphasic, rytmpatch or summitpatch.** Only cascade and
  segue have one. Least urgent thing on this page, but rytmpatch and
  summitpatch both have non-obvious taming behaviour that a manual is the
  natural home for.
- **`polyphasic` arc pages want reorganizing** around live performance
  rather than params-menu category, and there's now a backlog to do it
  around: `vel_curve` and `link_track` were left off the arc deliberately,
  and the new `bipolar` style suits the RANGE page's signed values.

- **Conventions drift found 2026-09-21** (see `CONVENTIONS.md`):
  polyphasic loads its modules as globals (`Sequence`, `GridLib`, `Display`,
  `GArc`, `lattice`), and polyphasic's and rytmpatch's header lines run to
  ~70 characters, past the SELECT preview's edge. Neither is a bug. Fix
  them the next time each script is open for other work, not as a
  standalone pass.
- **cascade's planned "shared slow-modulation lib" should use norns' own
  `lib/lfo`**, which already covers clocked/free LFOs, six shapes, depth,
  phase and `add_params()`. That makes the plan a call-site change instead
  of a lib. Update cascade's NOTES when that work starts.

## Ideas, not commitments

Candidate *new* scripts and shared infrastructure are brainstormed in
[IDEAS.md](IDEAS.md), with a recommended order. Below are feature ideas for
existing scripts, parked in their NOTES files: cascade's arc plectrum,
shared slow-modulation lib, and grid-right-half sequencer; polyphasic's
per-track progression banks and the shelved "Vanishing" visual; segue's per-pattern transition override, labelled scenes, per-lane
beat repeat, and non-16 pattern lengths; summitpatch's patch scenes with
an E3 crossfade, "breed", and a MOD MX page; rytmpatch's unmapped trig /
euclidean / performance-macro CCs, and arc support for both patch editors.
