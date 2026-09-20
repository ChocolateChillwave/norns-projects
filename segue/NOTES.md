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
- **One master clock at 24 PPQN**, not a coroutine per lane. 24 is the
  smallest resolution where every division we want is a whole number of
  ticks (1/4 = 24, 1/8 = 12, 1/16 = 6, 1/32 = 3, triplets 16/8/4/2) *and*
  every one of them divides a bar (96 ticks) evenly. That last part matters:
  it guarantees a lane always has a step landing exactly on any launch
  quantize boundary whatever division it runs at, so boundary checks are
  integer equality with no floating-point epsilon anywhere. Per-lane
  coroutines were the other option and were dropped — polyphasic's NOTES
  record a crashed division coroutine silently stopping every track sharing
  it, and one loop is both cheaper and easier to reason about.
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
- **`skip_empty` (per lane, default on)** keeps follow actions off empty
  bank slots. A part-filled bank is the normal case and silently jumping to
  silence is almost never what was meant. It also means an empty slot is a
  free space to write into without disarming anything first — CYM and COW
  ship with slot 8 empty deliberately.
- **Swing is stored in whole ticks**, not a percentage. At 24 PPQN a 16th is
  6 ticks, so a 1/16 lane can only swing 0 / 17% / 33% / 50%. Coarse, but
  those are the musically useful values, it keeps the entire timeline on
  integers, and 50% is a true triplet feel. The param formatter works the
  percentage out from the lane's own division, so the displayed number stays
  honest when the division changes.
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
- **Pattern lengths are all 16** in the library. The engine handles 1-64 and
  legato into a different-length pattern wraps correctly (tested), but no
  shipped pattern exercises it. A 12- or 24-step hat pattern against a
  16-step kick is one of the more interesting things this engine can do and
  nothing in the defaults shows it off yet.
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
