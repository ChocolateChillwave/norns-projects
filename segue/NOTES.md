# segue — status notes

Follow-action drum sequencer for the Elektron Analog Rytm MKII, modelled on
Ableton Live's clip follow actions. MIDI-out only, no engine.
Started 2026-09-17; **not yet run on a device or against a real Rytm.**

The idea, from the reference video: in Live a clip can hand off to another
clip on its own schedule, and if the hand-off is *legato* the new clip picks
up at the position the old one had reached rather than restarting — so a
pattern change can land in the middle of a bar and still sound continuous.
That switch behaviour is the whole point of this script; everything else is
built around making it playable.

## What this is for

One sentence: **a drum machine you steer rather than program**, where the
interesting musical decision is *when and how one pattern becomes another*.

Everything else is in service of that. The Rytm already sequences drums
perfectly well; what it can't do is hand a part off to a different part
mid-bar and have it sound like the beat carried on. If segue only ever
achieves one thing, that is the thing.

Three claims it is trying to make good on, in order:

1. **A pattern change can land anywhere and still sound intentional.** Not
   just at the bar line. `legato` carries the playhead; `xfade` and
   `handover` blend. If a mid-phrase switch sounds like a mistake, the
   project has failed at its one job.
2. **Eight lanes drifting against each other beats one pattern changing.**
   Independent follow actions mean the beat is never quite the same twice
   without anyone randomising anything.
3. **It should sound like music the moment it starts.** Which is what the
   kit library is for, and what the first version got wrong.

Non-goals, so the scope stays honest: it is not a Rytm editor (that's
rytmpatch), not a sampler, not a general sequencer, and it does not try to
replace the Rytm's own sequencer for writing a fixed arrangement.

## Plan

Four subsystems, worked in this order (agreed 2026-09-20). The ordering is
the point: each one is only worth building once the one before it is known
to be good, because each later layer assumes the earlier one sounds right.

Everything not in the current phase is *hidden, not removed* — the `mode`
param (GLOBAL, defaults to **focus**) dims FX rows 1/4/6 and trims the
screen's field list. Switching it to **full** brings the lot back.

### 1 · Clip follow logic — *built, unproven*

The engine: playheads, follow actions, the four transitions, launch
quantize. Desk-tested hard (628 assertions) and never heard.

- [ ] **Does a legato mid-bar switch actually sound continuous?** The
      central question, unanswerable at a desk.
- [ ] Do `xfade` and `handover` sound like anything, or just like dropped
      notes? `handover` especially — it only has one 4-voice lane to work
      with while the toms stay grouped.
- [ ] Are the follow *times* the useful ones? The list is even divisions
      plus dotted; nothing odd or polymetric.
- [ ] Is "chance" the right knob, or does it want a per-pattern weight
      across several destinations rather than an A/B split?

### 2 · Beat generation — *first pass done 2026-09-20*

The kit library, now organised so a row is a whole beat (amen, four four,
think, electro, rolling, funky, halftime, hypnotic) rather than eight
unrelated per-voice patterns.

- [ ] Do the breaks read as the breaks? The transcriptions are from memory
      at 16th resolution — see the header of `library.lua`.
- [ ] Eight kits enough, or does it want 16+ and a bank switch?
- [x] ~~Swing is limited to 0/17/33/50% by the tick grid.~~ Done
      2026-09-20: PPQN 24 → 96, and swing is now a percentage of the step
      rather than a tick count. ~4% resolution, 19 settings instead of 4.
      **Needs ears** — and needs a CPU check, since it quadrupled the
      clock rate.
- [ ] Does swing at these finer amounts actually improve the breaks, and is
      75% the right cap?
- [ ] Generation proper — euclidean, density-driven fills, humanise — is
      *deliberately not started*. A curated library first; algorithms only
      once it is clear what they would be improving on.

### 3 · Interface — *started 2026-09-20*

Screen, launch grid, step editor, arc.

- [x] ~~No `GArc:poll()` call.~~ Added; rings now follow values changed from
      the PARAMS menu, an encoder or a pset.
- [x] ~~The screen never answered "when does this change?"~~ — which is the
      question the whole script poses. The bottom line now carries a
      standing **what-next**: a queued launch shows `> kitname N` counting
      that lane's steps to the boundary, otherwise the transition plus the
      follow action and its countdown. `Lane:steps_to_launch` walks forward
      rather than dividing, because the commit lands on the lane's next
      *step* that sits on a boundary — not the next boundary, which differs
      whenever the lane's division is coarser than the quantize setting.
- [x] ~~The arc footer squatted on the bottom line permanently~~, showing a
      stale ring value long after the arc was touched. It now borrows the
      line for 1.5s after a ring moves. garc keeps no timestamp and is a
      byte-identical shared copy, so rather than change it: *the footer
      string changing is the touch*.
- [ ] The bank view is eight columns of eight 6×3 cells on a 128×64 screen.
      Legible, or mush? **Needs eyes.**
- [ ] Is the fading-active-cell playhead readable on the grid, or does it
      just look like flicker? **Needs eyes.**
- [ ] Twelve editable fields behind shift+E3 is a lot. `focus` trims it to
      nine; the right answer may be fewer still, or a page structure. Not
      touched yet — worth deciding once the screen has been looked at.
- [ ] Nothing shows which kit a lane is on except the selected one. Eight
      names will not fit; an abbreviation row might.

### 4 · Performance — *built, hidden*

Beat repeat, roll, solo, scenes.

- [ ] Beat repeat is global and captures forwards. Per-lane, and capturing
      backwards, are both plausible and both more work.
- [ ] Scenes now mean "launch a whole kit", which makes the row the primary
      gesture. They are still unlabelled and unviewable until launched.
- [ ] Nothing here gets judged until 1–3 are good.

### Not in any phase yet

rytmpatch integration (patch drift tied to follow actions), per-pattern
transition override, hybrid kits + variations, lane/voice resplit. All in
Open items below.

## Key decisions

- **Eight lanes, not one kit.** Chosen 2026-09-17 over a single 64-slot bank
  of whole-kit patterns. Each grid column is an independent lane with its own
  8-pattern bank, playhead, length, division and follow action, and the
  Rytm's 12 voices are split across them (KICK / SNARE / CLAP / TOMS / CHH /
  OHH / CYM / COW — every voice covered exactly once, asserted in the tests).
  This is the direct analogue of a Live session-view column, and it is where
  the generative behaviour comes from: a hat lane drifting every bar against
  a kick lane that holds gives you variation without anything having to
  "randomize" a whole beat at once.
- **One master clock at 96 PPQN**, not a coroutine per lane. Every division
  is a whole number of ticks (1/4 = 96, 1/8 = 48, 1/16 = 24, 1/32 = 12,
  triplets 64/32/16/8) *and* every one divides a bar (384 ticks) evenly.
  That last part matters: it guarantees a lane always has a step landing
  exactly on any launch-quantize boundary whatever division it runs at, so
  boundary checks are integer equality with no floating-point epsilon
  anywhere. Per-lane coroutines were the other option and were dropped —
  polyphasic's NOTES record a crashed division coroutine silently stopping
  every track sharing it, and one loop is both cheaper and easier to reason
  about.
  - **Raised from 24 to 96 on 2026-09-20** for swing resolution. 24 was the
    *smallest* rate satisfying the integer constraints, but it made a 16th
    six ticks, so the only reachable swing amounts were 0 / 17 / 33 / 50% —
    and the breaks this library is built around live in between those.
    At 96 a 16th is 24 ticks, giving ~4% resolution and 19 distinct
    settings instead of 4.
  - The cost is 4× the clock wakeups (192/sec at 120bpm). polyphasic runs a
    96 PPQN lattice on this same hardware and has been played, so there is
    direct precedent a Pi copes. To keep the extra ticks cheap, `Lane:tick`
    now opens with the cheapest possible rejection — one modulo and two
    compares — for the overwhelmingly common "not this lane's step" case,
    before computing anything. **Still unmeasured on hardware.**
  - The tests derive every tick figure from `TICKS_PER_16TH` /
    `TICKS_PER_BAR` rather than restating them, so this cannot silently
    invalidate the suite again.
- **Four transitions**, two of them beyond what Live does:
  - `cut` — snap to step 1, an ordinary clip launch.
  - `legato` (default) — leave the playhead alone. This is the one the video
    is about.
  - `xfade` — over a window of N steps, each voice independently picks from
    the old or new pattern with the odds ramping across the window.
  - `handover` — voices change one at a time, highest slot first, so the
    lane's anchor (slot 1: the kick, the downbeat tom) is the last thing to
    move. On a single-slot lane there is nothing to stagger, so it falls
    back to `xfade` rather than degenerating into an instant switch.
- **Follow actions ignore launch quantize, manual launches respect it.**
  That is Live's behaviour and it is deliberate: a follow action firing at
  its own time, mid-bar, is exactly the effect being chased, whereas a
  button press wants to land on the grid.
- **The follow check runs at the top of a tick**, after the playhead has
  advanced off the step it just played. "Follow at 1/4" therefore means:
  play four steps, advance to step 5, change pattern, play step 5 *of the
  new pattern*. Getting this order wrong is the easy way to be one step off,
  so there are explicit tests pinning it.
- **Follow defaults are part of the curated library**, not neutral. Kick,
  snare, clap, cymbal and cowbell ship as "end / none" (stay put); toms step
  to the next fill each time round; the two hat lanes take an "other" jump
  40%/50% of the time and otherwise hold. So it does something the moment it
  starts without the floor moving under you — and every bit is editable.
- **The library is organised as kits** (2026-09-20), replacing eight
  independent per-voice banks. Bank slot N is the same beat on every lane,
  so launching a row gives the real interlocking pattern, launching a cell
  borrows one lane's part from another kit, and a follow action drifts a
  lane *between* kits. The previous arrangement could not express a named
  beat at all — an amen break is not four unrelated voice patterns, and with
  nothing holding the whole, every pattern ended up a division of the bar.
  That was the actual cause of "stale and uninspired", not weak
  pattern-writing.
  - A kit that names no part for a lane leaves it **empty on purpose** (the
    amen has no cowbell). Those slots are forced to follow `none`: with
    `skip_empty` on, the active pattern isn't in its own candidate list, so
    a relative action like `next` would resolve to the first *non*-empty kit
    and pull the lane back in after one bar. Silence you asked for has to
    stay silent.
  - Kits are 16 or 32 steps. The two-bar ones (amen, halftime) exist because
    their whole character is bar two differing from bar one — and they are
    also the first thing in the library to exercise mixed lengths, which
    means lanes now genuinely phase against each other.
  - Tested by reconstructing each kit's intended voice set from the source
    and asserting that launching it sounds exactly those voices — no lane
    bleeding through from the previous kit, no part that never fires.
- **Bulk follow editing via an `scope` field** (2026-09-20). Follow settings
  are per pattern, which is 64 × 4 values, and there was no way to set more
  than one at a time — the gap that prompted this. Scope is `pattern` /
  `lane` (the selected lane's 8) / `kit` (the selected slot on all 8 lanes,
  which only means something now rows are kits) / `all`, and it shows as a
  bracketed badge on the field line whenever it is armed.
  - A bulk edit **assigns** rather than deltas: the value is computed from
    the pattern on screen and written to everything in scope, so they end up
    identical and the displayed number is the truth. Delta-ing each
    independently would preserve differences but leave the screen lying
    about what just happened.
  - Deliberately excluded: `length`. It changes what a pattern *is* rather
    than how it behaves, and the kits are different lengths on purpose.
  - Lane settings (division, swing, transition…) are already one-per-lane,
    so they ignore `lane` and `kit` and only widen at `all`. The badge reads
    `[ALL LANES]` for those so the distinction is visible rather than a
    thing you have to remember.
- **Arc broadcast wired up** (2026-09-20). `garc` has had an `all_ids` hook
  since polyphasic — hold the shift key and a ring applies to every track —
  and segue was passing `shift_fn` while no ring ever declared `all_ids`, so
  holding K1 on the arc did nothing at all. Fixed by giving every per-lane
  ring an `all_ids`. Note it deltas each lane independently rather than
  assigning (that is garc's behaviour, and the module stays byte-identical
  across the three scripts that share it) — so the arc keeps lanes'
  differences and the screen's scope flattens them. Different on purpose:
  one is a performance nudge, the other is settings work.
  - The arc still cannot reach follow settings, because it binds to param
    ids and follow settings live in the pattern data blob, not in params.
    Making them params would mean 256 of them; not worth it.
- **Scaled back behind a `mode` param** (2026-09-20, defaults to `focus`).
  Rather than deleting the performance layer while the engine is still
  unproven, focus dims FX rows 1 (beat repeat), 4 (solo) and 6 (roll) and
  trims the screen's eleven editable fields to eight. Hidden rows are inert,
  and switching modes releases anything they had latched. Nothing is removed
  — `full` restores it. See the Plan above for why that ordering.
- **`skip_empty` (per lane, default on)** keeps follow actions off empty
  bank slots. A part-filled bank is the normal case and silently jumping to
  silence is almost never what was meant. It also means an empty slot is a
  free space to write into without disarming anything first — CYM and COW
  ship with slot 8 empty deliberately.
- **Swing is a percentage of the lane's own step** (0-75), not a tick count
  — changed 2026-09-20 alongside the PPQN raise. Storing ticks meant the
  same setting produced a different feel at a different division; a
  percentage means the same thing everywhere, and the lane converts to
  ticks on the fly. The formatter shows the *achieved* percentage rather
  than the requested one, since the tick grid can only land on so many
  (about 4% apart at 1/16) and a knob that claims precision the clock does
  not have is worse than a coarse one that is honest. 75% is the cap: past
  that the swung step is nearer the following downbeat than its own.
- **A voice is a (channel, note) pair and nothing else.** Those 24 numbers
  live in params (VOICE ROUTING) and are the only thing consulted when a
  trig is sent; "note layout" and "midi channel" are *presets that stamp
  them*, not a mode read at send time. See Fixed — the first version had a
  scheme consulted per-trig plus optional overrides, and the overrides won
  unconditionally, which made two controls silently dead. One set of values
  with presets writing into it makes that class of bug impossible rather
  than just fixing this instance of it.
  - Default layout is **one channel, notes 0-11** (BD 0, SD 1 ... CB 11) on
    channel 1 — confirmed 2026-09-17 as what this Rytm is actually set to,
    replacing the track-channels-1-12 guess inherited from rytmpatch. The
    factory-note and track-channel layouts are still there as presets.
  - Note 0 is a legal MIDI note but an easy off-by-one to write; there is a
    test pinning that the sounding-key bookkeeping handles it (the key is
    `ch * 1000 + note`, so note 0 is not falsy anywhere).
  - Trade-off accepted: re-picking a layout wipes hand-edited per-voice
    values. That is what makes a preset a reliable "put it all back", and
    the alternative (a "custom" state that sticks) reintroduces two places
    for the answer to live.
- **Settings live in params; only content rides in the data blob.**
  Tightened 2026-09-20 after every lane setting turned out to survive a
  power cycle with no way back. The autosave (`segue-last.data`, written on
  quit and read on init, following rytmpatch) was restoring division,
  swing, level, mute, follow, transition and morph *as well as* the
  patterns — and `push_lane_to_params` then wrote them over whatever the
  params said. So the blob silently won, and there was no defined boot
  state at all.
  - `Lane:deserialize` now skips those fields unless asked
    (`{settings = true}`, which only the round-trip test uses), and the
    script calls `sync_lane_from_params` after loading instead. Params are
    the single source of truth, the same shape as the MIDI-routing fix.
  - Pattern content, follow settings and which slot is playing still
    persist, because losing an evening's edits to a power cycle is worse
    than the surprise. **PARAMETERS > patterns > reset to factory kits**
    is the way back to the shipped state.
  - Psets are unaffected: they carry settings as params, which is exactly
    where they now come from.
- **Params vs data blob**, the same split rytmpatch uses. Settings are real
  norns params (and therefore reach the arc, which binds to param ids, and
  save with psets). Pattern content, follow settings and scenes are a table
  saved alongside the pset via `params.action_write/read` and
  `tab.save`/`tab.load` — no cjson, which needs an ARM binary that isn't on
  the device. 8 lanes x 8 patterns of trig data would bury the PARAMS menu.
  `apply_data` pushes the restored lane values back into the params
  afterwards, so the two never disagree.
- **Grid layout is detected, not configured.** Two grids on vports 1+2 →
  LAUNCH and FX. One 16-wide grid → left/right halves, matching the
  convention cascade already set. One 8x8 → LAUNCH, with FX under held K1.
  The rest of the script only ever sees `on_launch` / `on_fx`.
- **Beat repeat captures forwards.** On press it records the next window of
  output and passes it through, then loops that capture for as long as the
  button is held. The lanes keep ticking underneath with their output
  discarded, so the timeline is still correct on release. Capturing
  *backwards* (the last N ticks) would need a rolling buffer of every tick;
  forwards needs one window and sounds the same in use.
- **The step editor takes over the LAUNCH surface** (FX row 8 col 6) rather
  than asking for a third 8x8: rows are the lane's voices, columns are eight
  steps, row 7 pages through longer patterns. Pressing a step cycles rest →
  normal → accent → ghost, which reaches every velocity level the library
  itself is written in without a separate velocity mode.
- **Tests live in the repo** (`segue/test/`). This was the first script here
  to have them; cascade, rytmpatch and summitpatch have since followed, all
  from copies of this stub. This one has enough state — 8 playheads, a
  follow engine, transition blending, a capture buffer — that the round trip
  of "guess, copy to the norns, listen, guess again" is too slow to be the
  only check. `test_segue.lua` covers the pure-Lua engine; `test_script.lua`
  drives the whole script against `norns_stub.lua`, a stand-in runtime with
  steppable clock coroutines. norns ignores the folder.
- **`lib/garc.lua` is the shared arc module, kept in step with the other
  scripts' copies.** It started as an older copy without `poll()` or the
  per-ring `style`/`track` options and was brought up to date (2026-09-19)
  so the repo-wide advice in `CLAUDE.md` holds here too. The redraw loop
  now calls `garc_:poll()` every frame, so a lane/quant/lane-select value
  that moves from the PARAMS menu, a pset load or an encoder shows on the
  rings without touching them. No ring here sets `style`, so the arc looks
  exactly as it did; the options are available if a page ever gets a signed
  or position-style value that a plain fill would misrepresent.
  `test_script.lua`'s "arc follows values changed outside it" covers the
  wiring — remove the `poll()` call and it fails.

## Open items / unverified

- **Nothing has touched real hardware.** Everything below the line is desk
  testing only (828 assertions across the two suites). In particular the
  screen layout, the grid brightness choices and how the transitions
  actually *sound* are all unconfirmed.
- **CPU is unmeasured.** The master clock is the busiest thing here: 24 PPQN
  is 48 wakeups a second at 120bpm, each one calling `tick()` on all eight
  lanes. Almost all of those calls return immediately on a modulo test, and
  the hit buffers and the repeat buffer are preallocated so the tick path
  does not allocate — but none of that has been watched on an actual Pi. If
  it turns out to matter, the cheap fix is to skip lanes whose division
  cannot possibly fire on this tick rather than calling into them at all.
- **Why this Rytm is on notes 0-11 is unexplained.** Reported 2026-09-17 and
  taken at face value — it is the default now. Worth knowing that it is not
  the factory layout (which is 36/38/40/...), so it is presumably set that
  way in the Rytm's own MIDI CONFIG. Nothing depends on the reason; noted
  only so a future "that looks wrong" doesn't get silently "corrected".
- **rytmpatch's own channel assumption is now known to be suspect.** Its
  NOTES flag "FX channel 13, track channels 1-12" as unverified; this
  session establishes that at least the track-channel part does not match
  this device. Worth re-checking rytmpatch against the same MIDI CONFIG
  before trusting its defaults, and worth doing before the integration
  below rather than after.
- **rytmpatch integration** — your idea from the kickoff, and the reason
  `patchcore.lua` was left out of this pass rather than forgotten: patch
  randomization running while patterns play, ideally with the drift tied to
  the same clock the follow actions use (a patch morph triggered *by* a
  follow action would be the interesting version). `patchcore.lua` +
  `pageview.lua` + `rytm_map.lua` are already self-contained and designed to
  be copied, so this is mostly a question of where it goes in the UI — it
  wants a screen page of its own, and the arc pages are the natural home for
  the randomize/morph/undo controls. Not started.
- **Per-pattern transition override.** Transition is currently per lane. In
  Live the launch mode belongs to the clip, so a pattern could carry its own
  — worth it for "this one fill always cuts, everything else is legato".
- **Scenes are launch-only and unlabelled.** Eight of them, stored/recalled
  from FX row 2, defaulting to "every lane at pattern N". No way to see what
  a scene holds without launching it, and no scene follow actions (a scene
  chain would be a whole second layer of the same idea).
- **`handover` voice order is fixed** (highest slot first). Only really
  meaningful on the 4-slot TOMS lane at the moment. If lanes end up with
  more voices, a per-lane order might be worth it.
- **Lane voice assignment is not editable** from the script — it comes from
  `Library.LANES` and survives a pset (it is in the serialized data), but
  nothing changes it at runtime. Deliberate for now; the split covers all 12
  voices sensibly. Worth exposing if the fixed split starts to chafe.
- **Beat repeat is global**, not per lane. Per-lane repeat would need the
  capture buffer split per lane; probably worth it, but global is the
  classic behaviour and it is one button.
- **Lane layout: the four toms still share one lane.** Raised 2026-09-20
  ("all the tom drums on the same midi channel") and deliberately deferred.
  To be clear about what is and isn't true: BT/LT/MT/HT are four separate
  voices on the wire (channel 1, notes 4/5/6/7 under the default layout) —
  the MIDI is correct. What they share is a *lane*: one pattern bank, one
  playhead, one follow action between the four, because 12 voices had to
  fit 8 grid columns. Two ways out when it matters: 12 lanes with a paged
  grid, or keep 8 and improve the grouping (a proposed split that separates
  CH/OH, gives BT its own lane as techno's second kick, keeps LT/MT/HT as a
  fill unit and pairs CY+CB). Deferred until the follow engine and the kits
  have been heard, on the grounds that lane layout is easier to judge then.
- **The hybrid library shape was preferred but not taken** (2026-09-20):
  rows 1-4 coherent kits, rows 5-8 neutral per-lane variations for follow
  actions to wander into. Held back so the pure kit arrangement can be
  judged first; revisit once there is an opinion on whether eight kits is
  enough to drift between.
- **Swing only reaches 50%** and only in 1/6 steps on a 1/16 lane (see Key
  decisions). If finer swing turns out to matter, it needs a sub-tick delay
  — a short `clock.sleep` on the swung step — rather than a bigger PPQN.
- **`morph_steps` and `transition` exist both globally and per lane.** The
  global ones are "set them all" conveniences whose action writes to every
  lane. Restore order makes this safe for psets (the global is added before
  the lane groups, so per-lane values are applied last and win), but it is
  the kind of thing that breaks quietly if params get reordered later.
- **Ableton Link / transport**: `clock.transport.start`/`stop` hooks are
  wired and MIDI start/stop is sent to every port with `clock_midi_out_N`
  enabled, copying what polyphasic ended up with. Unverified with Link.

## Fixed

- **The pattern grid was measured from the keypress, not from the clock**
  (reported 2026-09-20 as "I often have to try a couple of times to lock in
  the tempo" with Link). `tick` started at 0 when you pressed play and then
  incremented, so every bar line, launch-quantize boundary and swing parity
  was relative to *when you happened to start*. Under Link that meant the
  right tempo at an arbitrary phase — the only way to land on the beat was
  to hit play at exactly the right instant, hence retrying.
  - `tick` now comes from `clock.get_beats() * PPQN` each wakeup, so the
    grid is a property of the clock rather than of the keypress. It is also
    self-correcting: a late or missed wakeup cannot accumulate drift the
    way an incrementing counter can. A monotonic guard stops a wakeup that
    lands a hair early from rounding back and firing a tick twice.
  - A lane now takes its opening playhead position from the tick it first
    fires on rather than always starting at step 1, which is what makes a
    late join land in the right part of the phrase.
  - **Behaviour change worth knowing:** on a *shared* clock (Link or MIDI,
    i.e. `clock_source > 1`) the origin is the shared timeline's zero, so
    pressing play mid-phrase drops you into the middle of the pattern
    rather than restarting it — correct for playing with others, and
    different from before. On the **internal** clock there is nobody to
    agree with, so the origin moves to the first tick after the keypress
    and the pattern still starts at step 1. If that automatic rule turns
    out to be wrong for either case it wants a param.
  - The origin for the internal case has to be taken on the first tick that
    actually *runs*, not in `all_reset` — `clock.sync` waits for the next
    subdivision, so the moment of the keypress is already past by then, and
    setting it earlier put the pattern one step out.
  - Starting exactly on beat 0 of a shared clock lands on step **2**, not
    step 1, for the same reason: the tick-0 boundary is in the past. That
    is correct, and there is a test pinning it so it does not get "fixed".
- **The screen lagged input by up to 66ms.** Reported as division still
  feeling sluggish after the encoder fix above. Measured: the *value* moved
  one step per click correctly, so this was purely display — the redraw
  loop runs at 15fps, which is fine for the playheads but means a turn can
  sit invisible long enough that you turn again before seeing the first
  change, and then it jumps two. Input now redraws straight from the
  handler (`touch()`), rate-limited to 30fps so a fast spin cannot flood
  the screen. CLAUDE.md's rule is against handler redraws *that cause rapid
  re-draws*, which the limiter prevents; the animation loop is unchanged at
  15fps.

- **Every discrete control took a dozen or more encoder clicks to move one
  step** (reported on hardware 2026-09-20 as "it's almost like the norns is
  waiting for a full turn"). norns' `Control:delta` is `set_raw(raw + d/100)`
  — it moves 1/100 of the *range* and ignores the param's step entirely. So
  a 0-1 control took **50 clicks to toggle**, a 4-option one 17, division 8,
  launch quant 7. Measured, not estimated.
  - Why everything is a `control` in the first place: garc only renders a
    ring for a param carrying a controlspec, so `number` and `option` were
    never available for anything the arc should reach.
  - Fixed with `add_ctl`, which overrides the param's own `delta` so one
    click is one step for any control with ≤100 steps. Wider ones (level,
    at 200) keep norns' behaviour, which is already reasonable for them.
  - **This also repairs the arc**, in a way that wasn't obvious: garc
    smooths a ring's fill by `controlspec.quantum` (step / range), i.e. it
    was already written assuming one delta equals one step — which norns
    does not do. Those rings had been under-filling for exactly these
    params all along.
  - **The stub was complicit.** `params:delta` in `norns_stub.lua` moved by
    one step, i.e. it implemented the *desired* behaviour rather than the
    real one, so all 2978 checks passed while the hardware was unusable.
    It now models norns properly, including keeping `raw` as separate
    accumulating state (a first attempt recomputed raw from the quantized
    value, which never crosses a step boundary at all — wrong in the other
    direction). A regression test now walks every control and asserts one
    click moves one step.

- **The note scheme and note-map channel controls did nothing** (found on
  hardware 2026-09-17, first session with a real Rytm attached; reported as
  "works the same whichever scheme is chosen, and the channel doesn't change
  anything"). `Voices:address()` computed a channel/note from the scheme and
  then let `channel_override[v]` / `note_override[v]` replace both. Those
  overrides were meant as an opt-in escape hatch, but they were ordinary
  params *with defaults*, and `params:bang()` fires every action at startup
  — so all 24 were populated on every boot and unconditionally shadowed the
  scheme. Both controls were inert from the first run; no test caught it
  because the unit tests exercised `Voices` directly (where the overrides
  are genuinely optional) and the script-level test only asserted that
  channels landed in 1-12, which the override defaults happened to satisfy.
  Fixed by removing the scheme/override split entirely — see Key decisions.
  The script test now asserts the layout controls actually change what goes
  out, which is the assertion that was missing.

## Layout reference

Lane → Rytm voice assignment (`Library.LANES`):

| lane | name  | voices          |
|------|-------|-----------------|
| 1    | KICK  | BD              |
| 2    | SNARE | SD              |
| 3    | CLAP  | CP, RS          |
| 4    | TOMS  | BT, LT, MT, HT  |
| 5    | CHH   | CH              |
| 6    | OHH   | OH              |
| 7    | CYM   | CY              |
| 8    | COW   | CB              |

62 patterns ship across the eight banks (CYM and COW leave slot 8 empty).

## Running the tests

```
lua segue/test/test_segue.lua     # engine, pure Lua
lua segue/test/test_script.lua    # whole script vs. a stubbed norns
```

Both exit non-zero on failure. `test_script.lua` reaches the script's locals
through `debug.getupvalue` (`S.get_lanes()`, `S.upvalue(redraw, name)`), so
renaming a local in `segue.lua` can quietly break a test's *assertion*
without breaking the script — if a test starts failing on something that
looks unrelated, check that first.
