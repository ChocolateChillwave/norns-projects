# cascade — status notes

Strummed chord instrument, MIDI out only. Hold a grid cell (or an external
MIDI note) and the chord under it strums; hold several and they merge into
one strum over all their notes, arpeggiator-style. In cycle mode the strum
repeats for as long as you hold, with timing, velocity shape, pattern and
note probability all live-editable from the arc while it rings. Holding and
strumming is the point of the whole script — everything else serves that.

Renamed from `chordflow` 2026-09-16 (`git mv`, history kept).

**Status:** first hardware pass done 2026-09-16 ("working fairly well"); this
file's 2026-09-16 round 2 changes respond to that pass and are untested on
hardware. Chord, pattern and strum engines are covered by off-device tests
(see Verification).

`MANUAL.md` is the user-facing manual (what everything does, parameter
reference, recipes, version history). This file is the developer's log — why
things are built the way they are, what's unresolved. Keep changes to
behaviour reflected in both.

## Layout

- `test/` — off-device suites, see Verification. norns ignores the folder
- `cascade.lua` — params, grid/arc/screen wiring, strum settings
- `lib/display.lua` — the string view (and the older dots), kept out of the
  script so a visual change can't touch timing
- `lib/chords.lua` — voicing banks, degree stacking, inversion, chord naming
- `lib/patterns.lua` — strum patterns as timing slots, and the cycler that
  picks/blends them per repeat
- `lib/strum.lua` — the single strummer: shared note pool, release tails,
  repeat timing, humanize
- `lib/gridkeys.lua` — press/hold/release over a grid region, nothing else
- `lib/garc.lua` — copied unmodified from polyphasic (see its header)

## Key decisions

- **Grid: left 8x8, right half dark.** Columns = 8 scale steps up from the
  key root. Rows 5-8 are the lower octave, rows 1-4 the upper. Within each
  group of 4, the bottom row is the most compact voicing of the current bank
  and the top row the widest ("up = more"). Resting brightness is dim (2),
  accidentals brighter (6), held cells full (15). Right half reserved for a
  sequencer; nothing built there.
- **The two octave groups are exactly one octave apart in any scale** —
  `notes_per_octave` is measured off the generated scale, not assumed to be 7.
- **Chords are built by stacking scale degrees**, so they're in key by
  construction — no filtering, no substitution.
- **One strummer, shared pool.** Every held chord adds its notes to one pool
  and each pass strums the whole pool as one gesture (sorted by pitch, then
  timed by the pattern). Replaced one strummer per held chord, which was the
  cause of the "clashing" from the first hardware pass: separate strummers
  ran on separate timing so held chords fell out of step, and a pitch shared
  by two chords on the same MIDI channel could be cut by the *other* chord's
  note-off. There was never a mono restriction in cascade itself.
- **Soft chord changes.** Letting go of a chord doesn't cut its notes: they
  ring for `release` ms (default 300) and then stop — unless another held
  chord owns that pitch, or it's struck again first, in which case it just
  carries on. Same treatment for notes a held chord drops when bank/invert/
  transpose is changed mid-hold. `release` 0 = cut immediately, as before.
- **New chord timing (`new chord` param).** "strum now" (default): a newly
  pressed chord strums immediately — between repeats the wait is cancelled,
  mid-strum the current pass finishes and the next starts straight away.
  "next repeat": it waits and joins on the next scheduled repeat, keeping
  the existing rhythm untouched. One-shot mode always strums again, or the
  new chord would never sound.
- **Patterns are timing slots, not orders.** Each note gets a slot (when it
  lands, in units of the strum gap); equal slots strike together and slots
  can be fractional. That's what allows simultaneous strikes (pairs, pinch,
  thumb, block), shaped timing (accelerate, decelerate), and — the point —
  blending two patterns into a real in-between timing. 13 patterns: up, skip
  up, pairs, accelerate, decelerate, thumb, pinch, block, outside-in,
  inside-out, skip down, down, random. Listed by similarity so "advance"
  steps between neighbours.
- **Pattern cycling, gradually.** `cycle` = hold / advance / alternate
  (mirror the current pattern) / random; `every` = repeats between changes;
  `morph` = repeats spent blending into the new pattern (0 = instant). Morph
  is capped to fit inside `every`, so "every 1" still alternates each repeat.
  Turning the pattern knob also morphs rather than jumps. Blends are
  recomputed for whatever the pool size is on that pass, so chords being
  added or released mid-morph don't break it. Blending into or out of
  "random" is a partial scramble each repeat, since random reshuffles.
- **Humanize retuned.** Old model: every gap independently +-amount, which at
  25% drifted a 6-note strum up to 32ms from perfect. New model splits it: the
  whole strum varies a little (tempo, overall velocity, landing slightly
  late) and each note much less, and the knob is curved (amount^1.5). Measured
  worst drift over 120 repeats: 15% -> 2.8ms, 25% -> 5.9ms (was 32.4), 50% ->
  16.8ms, 100% -> 47.5ms. So the new full range covers roughly what 0-37% did
  before, with most of the knob spent on the subtle end. Depths are the
  constants at the top of `lib/strum.lua` if it needs another pass.
- **Tilt follows when a note lands**, not its pitch — so it tracks the
  pattern (a "down" strum with negative tilt still fades as it goes). A
  pattern with nothing to spread over (block) sits untilted.
- **12 banks, plain to colourful:** add nine, sixths, sevenths, ninths,
  elevenths, thirteenths, sus, quartal, fifths, spread, octave bass, clusters.
  4 voicings each, 4-6 notes, no plain triads. Tested in key across 4 scales x
  12 keys x every grid root. Default bank is sevenths (the old default sound).
  Contents are tables in `lib/chords.lua`; retuning them is the intended way
  to change the sound.
- **Range** at defaults: C3 to C7, 4.0 octaves, with the widest voicing
  reaching 14 scale steps above its root. MIDI-in roots are kept that far
  below the top of the pool (derived from the banks via `Chords.max_degree()`,
  not hardcoded) so they always come out whole.
- **Chromatic scale** gets a major-shaped stack on whatever root is played
  (degree-stacking over 12 semitones would make clusters). Can't produce
  minor chords in chromatic.
- **MIDI-in** snaps to the nearest scale note and uses whichever voicing row
  was last played on the grid.
- **Screen** shows the most recently pressed held chord's name, with "+N" when
  N more are merged into the strum, and one dot per pooled note lighting as
  it's struck. Names read off the actual pitch classes from the true root,
  slash bass when inverted.

## Engine batch (2026-09-17)

Five settings, all inside `lib/strum.lua`. Each defaults to the previous
behaviour except drift, so loading an old pset sounds the same.

- **note length** (ARTICULATION) — as a percentage of one repeat rather than
  ms, so it tracks tempo; chosen over ms for that reason. 0 = "let ring",
  the previous behaviour and still the default. Uses the same tail mechanism
  as release, with one rule added: an earlier stop already scheduled wins,
  so letting go of a key can't extend a note past the gate it was struck
  with. Repeat length comes from the cycle settings even in one-shot mode,
  so note length still means something there.
- **density** (FEEL) — thins the pool structurally, dropping from the middle
  and always keeping the lowest and highest note. Deliberately distinct from
  probability: density is the same every pass (a thinner voicing), while
  probability re-rolls per note per pass (a shimmer). Notes it drops are
  released rather than left ringing, which also fixed the general case of a
  sounding note no longer being in the play pool — the check is now "is this
  note in what we're playing" rather than "does some held chord own it".
- **fit to repeat** (STRUM) — `fit` on plus `strum span %` sizes the gap so
  the strum spans that fraction of each repeat, whatever the note count. 6
  notes and 12 notes both span 50%. Answers the "3 chords = an 18-note strum"
  open item. The arc's rate ring retargets to `strum span` when fit is on.
- **drift** (MOTION on arc, FEEL in params) — humanize's slow cousin: a random
  walk on tempo and velocity that wanders over tens of seconds instead of
  re-rolling each pass. Measured contrast at full depth: drift moves ~1ms
  between neighbouring passes across a 9.3ms range (a wander), where humanize
  moves 7.3ms between neighbours across 22ms (jumps). Default 10%, the only
  new default that isn't a no-op.
- **upstrokes** (ARTICULATION) — direction is *read off the pattern* rather
  than configured: if the lowest note lands after the highest, it's an
  upstroke. That works for every pattern including mirrored and mid-morph
  ones, and needs no new state. `upstroke level` plays them quieter,
  `upstroke notes` catches only the top N, like a real pick. Both default to
  100% (no change) since this one is on trial. Notes an upstroke skips keep
  ringing rather than being cut — the string is still there, the pick just
  missed it.

Decisions taken with these: note length as % of repeat (not ms); latch will
live in params when it's built; `invert` becomes an offset applied after
voice leading rather than being disabled by it.

## Batch 2 (2026-09-17): triads, latch, bass split, voice leading

- **triads bank**, added first in the list as the plainest. It's the only
  bank with three-note voicings — every other bank is 4-6 notes so a strum
  always has something to spread across. Adding it at index 1 shifted every
  other bank up by one, so **a saved pset from before this will load the
  neighbouring bank**; the default moved from 3 to 4 to keep sevenths.
- **latch** (STRUM group, params only as agreed). Tapping a chord leaves it
  playing; tapping the same cell again drops it. Latched cells stay lit on
  the grid at level 12, below the 15 of a key actually held. Turning latch
  off releases everything it was holding, since nothing is physically
  pressed any more. K2 (panic) also clears the lot.
- **bass split** (MIDI OUT group): `bass channel` (0 = off) sends the lowest
  note of the pool to its own channel, with `bass octave` to drop it. The
  pool merges every held chord, so there's one bass, not one per chord.
  Notes are tracked by their pool pitch but remembered with the pitch that
  actually went out, so a transposed bass still gets the right note-off.
- **voice leading** (CHORD group): picks the inversion and octave that move
  least from what's already sounding, falling back to the last chord played
  when nothing is. Measured over 2912 chord changes: never worse than root
  position, and 4.8 vs 11.1 semitones of movement on average. The placement
  is decided once per press and held for the life of that press -- deciding
  it every repeat would make a held chord wander. `invert` stays live as an
  offset on top, per the decision taken when this was scoped.

## String view (2026-09-17)

`lib/display.lua`, chosen as the visual over the old dots. The look is the
one phones give guitar strings: a rolling shutter exposes an image one column
at a time, so each column catches the string at a different point in its
cycle and a plain vibration reads as a travelling wave. That's faked head-on
-- a string is a sine along x whose phase advances with time, so it ripples
instead of flickering. It isn't how a string really moves, which is the point.

- Pitch sets both how many waves fit across the screen and how fast the
  ripple travels, so high notes shimmer tightly and low ones roll. Velocity
  sets the displacement, which decays back to a flat line over ~0.9s.
- Notes are drawn lowest at the bottom. More than 6 notes (two or three
  merged chords) are sampled evenly down to 6, so the outer ones always show.
- The chord name moved up to y=24 to make room for the string band at 30-56.
- **Cost**, measured off-device in screen ops per frame: 108 with all six
  strings ringing, 24 once they settle, against 20 for the old dots. At 15fps
  that's ~1620 ops/sec worst case -- more than polyphasic's Halide, and the
  thing most likely to need trimming on real hardware. `SAMPLES` in
  display.lua is the dial (16 points per rippling string); a resting string
  is a single line, which is why settling is so much cheaper.
- New `visual` param (DISPLAY group): strings / dots / off. The dots visual
  is kept as the cheap fallback and `off` as the escape hatch if the Pi
  struggles, rather than making people choose between a visual and CPU.

## Arc (the arc's own button cycles pages)

For an arc without a pushbutton (older models): hold K2 and turn E2, in
either direction. K2's panic therefore fires on release rather than press,
and is skipped if E2 was turned during the hold, so reaching for a page
never panics. K1 isn't usable for any of this — norns takes K1 for its
system menu before a script sees it (earlier versions of this file wrongly
said K1 cycled pages).

- STRUM — rate / pattern / cycle rate / mode
- MOTION — pattern cycle / every / morph / drift
- FEEL — tilt / humanize / probability / velocity
- VOICE — note length / release / density / upstroke level
- CHORD — bank / invert / octave / transpose

The rate rings retarget depending on their settings: the strum rate ring
edits `strum span` when fit is on, otherwise the division or ms param
depending on sync. `upstroke notes` is params-only — it's a set-once
character control rather than something to reach for mid-performance. Every arc-bound param is a `control` param with a
real `controlspec`, which garc.lua needs to render at all.

## Fixed

2026-09-17, after the first real playthrough (reported: occasional hanging
notes, plus `clock.lua:62: bad argument #1 to 'resume' (thread expected)`).
Three separate bugs, all found and fixed off-device:

- **Cancelling a clock that had a wake queued** (the crash, and some of the
  hangs). `clock.cancel` nils the thread, but a wake already scheduled for it
  still arrives and the scheduler resumes `nil`. Stopping a strum cancelled a
  coroutine sitting in `clock.sync`/`clock.sleep`, which is exactly the race;
  when it fired it crashed the clock and took any note-off timer queued behind
  it down too. **cascade now never calls `clock.cancel`.** A run carries a
  token; stopping clears it, and the run checks the token at every wake and
  before every strike, so a superseded run makes no sound and retires itself.
  Also removed the cancel of the screen redraw loop, which now exits on a flag.
  - Related correction: an earlier guard here defended against norns reusing
    clock ids. **It doesn't** — the id counter only increments. That guard was
    unnecessary and has gone; the real hazard was always the queued wake.
- **A note struck after its own chord was released.** A pass plans its strikes
  up front, so it could still name a chord let go mid-strum. Striking such a
  note replaced its sounding entry and dropped the release timer set when the
  key came up, so it rang forever. Ownership is now re-checked at the moment
  of the strike, not just when the pass was planned.
- **A stale note-off deadline.** Re-pressing a chord while one of its notes was
  still ringing out cleared that note's pending stop token but left `off_at`
  behind. The next release compared against that dead deadline, concluded a
  stop was already coming sooner, and scheduled nothing. `add()` now clears
  both, and `_tail` only defers to a deadline that still has a live token.
  Found by the soak test, not by reasoning — it needs a specific press /
  release / re-press / release-with-longer-tail sequence.

Testing added with these: a virtual clock that models norns properly
(sequential ids, and a cancelled clock leaving its queued wake so the crash
reproduces), plus a randomised soak — 25 seeds x 3 simulated minutes of
presses, releases, panics and setting changes, asserting no crash, no clock
cancels and nothing left sounding. A 200-seed run (~6.7 simulated hours) is
clean.

2026-09-16, round 2:
- **Chords clashing when held together or changed quickly** — see "One
  strummer, shared pool" above.
- **Pattern cycling jumped abruptly** — see "Pattern cycling, gradually".
- **Humanize too strong by ~25%** — see "Humanize retuned".
- **Pattern `every` didn't count from the first repeat** — "alternate every
  4" flipped after 1. Caught in testing, not on hardware.
- **Chord names**: sixth chords showed as plain triads (`C` for C6); 11th
  voicings without a third showed as `Cmaj9sus4`. Now `C6`, `C6/9`, `Cmaj11`,
  with 7sus4 still kept distinct from an 11.
- **"six-nine" voicing had no third** (it was really a sus chord). Fixed.

2026-09-16, round 1:
- **Chords hanging until K2** — one coroutine per note, so releasing mid-strum
  sent note-offs before still-sleeping coroutines sent their note-ons. Now one
  coroutine owns a strum and checks before every strike.
- **K2 stalling the script** — panic sent 2048 MIDI messages; now CC 123 per
  channel (16).
- **Cancelling a finished coroutine could kill an unrelated one** — norns
  reuses clock ids. Only cancel a coroutine still marked running. In the
  current engine the id is typically inherited by a release-tail timer, so
  without this guard a released note hangs; the test for it fails with the
  guard removed.
- **Screen stale while turning the arc** — screen now runs its own 15fps loop.
- **Inverted chords named after their bass note** — now named from the root.

## Removed

- Randomize and parameter locks (round 1, at your request).

## Open items

- **Sequencer on the grid's right half** — idea noted, nothing built.
- **String view needs a CPU check on hardware** (see above). If it bites,
  drop `SAMPLES` to 12 or fewer before reaching for anything cleverer.
- **`cascade/img/` is gone** -- 24 petal PNGs left over from the original
  flower visual, unused since the rewrite. Recoverable from git history at
  `chordflow/img/` if ever wanted. `polyphasic/img/rainy_city...png` is still
  there and still unused by its script; left alone because polyphasic's own
  NOTES deliberately keeps it in case "Vanishing" is revisited.
- **Needs a hardware pass** for round 2: does the merged strum read clearly
  with 2-3 chords held; is 300ms the right default release; is "strum now"
  the right default for new chords; do morph/every feel musical at real
  tempos; is humanize now in a useful range (worry is it's too subtle at the
  low end rather than too strong).
- **Chosen but not yet built**, in the agreed order: latch (in params), bass
  split, voice leading; then string view; then the crow/Just Friends output
  backend; then the arc plectrum and a shared slow-modulation lib. Design
  notes for each are in the session this batch came from.
- **crow/JF**: hardware is wired and norns needs nothing installed — crow is
  detected over USB. Relevant calls are `crow.ii.jf.mode(1)`,
  `crow.ii.jf.play_voice(channel 1-6, volts, level)`, and
  `crow.ii.jf.trigger(channel, state)` for gates. JF's 6 voices map naturally
  to 6 strings. Open question: plucks (JF's own envelope, so note length is
  JF's business) vs gates (cascade controls length).
- **Two chords pressed at almost the same instant** give a short strum of the
  first one before the merged strum starts (the second press arrives mid-pass
  and kicks the next pass). Probably inaudible at normal strum rates; flagging
  in case it isn't.
- **Bank contents are a first draft** — verified in key and well-formed, not
  yet heard. On minor degrees of a major key, "sixths" voicings land on a b6
  (diatonic), so they read as `Am` / `Amadd9` rather than `Am6`.
- **Chord symbol is best-effort** — some quartal/fifths stacks get valid but
  clunky names (`C6/9sus4`, `Cmaj13sus4`).
- **Chromatic can't make minor chords.**

## Verification

No norns in this dev environment, so testing is off-device against stubbed
norns APIs with the local `lua.exe`. The suites live in `cascade/test/` and
run with `lua test_libs.lua`, `lua test_strum.lua`, `lua test_script.lua`
from that folder (159 checks total).

`test/norns_stub.lua` started as a copy of `segue/test/norns_stub.lua` per
CLAUDE.md and was extended for cascade:

- **a virtual clock**, because cascade's behaviour is about timing rather
  than step counts -- gate lengths, release tails and strum spacing are
  asserted to the millisecond without waiting for any of it. It models norns
  properly: ids from a counter that only increments, and a cancelled clock
  keeping its queued wake so the hardware crash reproduces here.
- **musicutil**, enough scales to drive the script, including the real
  behaviour that generation stops at MIDI 127 so a pool can come back short.
- `params:add_option`/`add_number`/`add_binary`, `add_group`'s two-argument
  form, `controlspec`/`formatter` on the generic `params:add`, `midi.to_msg`
  and an incoming-MIDI helper, timestamps on recorded MIDI, and
  `screen.text_center`.

Worth folding the generic parts of that back into segue's copy if it's ever
touched again -- the param and midi gaps aren't cascade-specific.

- **`test_script.lua`**, 90 checks, drives cascade.lua itself: init, every
  param group's promised count, arc-bound params having controlspecs, the
  grid surface (including that C major shows no accidentals and A major
  shows three), latch, keys and encoders, K2+E2 paging without panicking,
  the bass split, voice leading across a progression, redraw and cleanup.
- **`test_libs.lua`**, 32 checks: banks, degree stacking, in-key across 4
  scales x 12 keys x 15 roots, chromatic fallback, inversion, chord naming,
  voice leading, patterns and the cycler's morphing.
- **`test_strum.lua`**, 37 checks including a randomised soak. Engine batch: let-ring vs gated note length, release
  not extending past a gate, density thinning and releasing what it drops,
  fit spanning the same fraction for 6 and 12 notes and following the repeat
  length, stroke direction read from the pattern, upstroke level and note
  count, skipped notes left ringing, drift wandering rather than jumping.
  Earlier checks: release mid-strum; release tail rings then stops;
  two chords merge into one evenly spaced ascending strum; shared pitch
  survives releasing the other chord; re-press cancels a pending tail;
  one-shot chord pressed mid-strum still sounds; "next repeat" waits and
  joins exactly on the repeat; "strum now" strikes at the press; synced
  repeats land on the beat grid; clock-id guard (fails without it — a note
  hangs); re-voicing mid-hold releases dropped notes; no pitch ever on twice;
  panic. Plus the humanize before/after measurement quoted above.
- **Patterns**, 17 checks: every pattern valid for 0-8 notes, mirrored or not;
  shapes (block, pinch, thumb, accelerate/decelerate); cycler hold, advance,
  alternate-with-morph sequence, morph cap at every=1, knob-turn morph,
  instant switch, random never repeats a pattern, pool size changing
  mid-morph.
- **Banks**: structure, no duplicates, in key across 4 scales x 12 keys x 15
  roots, no short chords from any grid position, range.
- **Chord naming**: 20 standard cases plus inversion slash names.
- All files load; every param group's declared count matches; every arc ring
  resolves to a registered control param.

None of this covers grid/arc/screen behavior on hardware or real MIDI timing.
