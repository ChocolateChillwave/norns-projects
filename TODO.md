# todo — what needs doing, and who it's waiting on

The working checklist for every script in the repo. When you ask "where am
I at?", this is the file we go through.

**Last reviewed: 2026-09-24, against commit `5540e53`.** At the next
progress check, anything committed after that commit gets reconciled
against this list first.

## How this works

Every item has an ID, so you can answer by ID ("SEG-1: sounds great",
"RYT-1: tracks are 1-12, FX is 16"). Every item also has one of three
tags:

| tag | means | waiting on |
|---|---|---|
| `device` | needs you at the norns with the gear: ears, eyes, hands | **you** |
| `decide` | needs your opinion or a choice, no hardware | **you** |
| `desk` | I can do it without hardware | me (items marked *go* just need your OK) |

When you give feedback on an item:
1. Your answer goes into that script's `NOTES.md`. The NOTES stay the
   record of *why*; this file only tracks *whether*.
2. The item gets ticked and moved to the **Done** log at the bottom, with
   the date and your answer in one line.
3. Anything your answer unblocks moves up.

This file doesn't repeat the reasoning behind an item. Each one points to
the section of the script's NOTES that explains it.
[ROADMAP.md](ROADMAP.md) holds status and priorities, and
[IDEAS.md](IDEAS.md) holds possible new scripts. Neither of those is a
checklist.

---

## Where things stand

- **Waiting on you at the device: 41**
- **Waiting on your decision: 11**
- **My desk queue: 8** (3 ready now once you say *go*, 3 blocked on an item above, 2 saved for the next time that script is open)

The first five, in order:

1. **SEG-23** `device` One minute, and it decides whether every other
   segue answer means anything: is segue addressing the Rytm on the right
   channels? RYT-1 says tracks are on 1-12; segue defaults to channel 1.
2. **SEG-1** `device` Does a legato switch mid-bar sound continuous? This
   is the question segue exists to answer.
3. **X-3** `decide` Should segue's encoder-lag fix become the rule for
   every script? One sentence from you settles it.
4. **X-2** `desk` Merge the three test stubs into one. Ready now, just
   needs a *go*.
5. **CAS-1 / CAS-2** `device` The two guesses about Just Friends that
   cascade is built on.

## Suggested device sessions

The `device` items grouped by what needs to be plugged in, so each sitting
at the norns covers as much as it can.

- **Session A: norns + Rytm.** SEG-23 first, because if segue is on the
  wrong channels nothing else you hear means what it seems to. Then all of
  segue's phase 1 and 2 items (SEG-1 to SEG-9). With the grids and arc
  plugged in, SEG-19 to SEG-21 too. Then RYT-2 to RYT-5 if you have energy.
  This is the most valuable session on the list.
- **Session B: norns + Summit.** SUM-1 to SUM-6.
- **Session C: norns + grid + crow/JF.** CAS-1 to CAS-10.
- **Session D: norns + arc.** POL-1, and polyphasic's arc questions.
- **Any session:** X-1 takes a few seconds.

---

## rytmpatch
*Never run on hardware, but its MIDI channels are now verified against the
Rytm (2026-09-24). → [NOTES](rytmpatch/NOTES.md), Open items / unverified*

- [ ] **RYT-2** `device` First load: does it run at all, and are the 62px
      cells and the window ticks readable on the real screen? (Receive is
      confirmed on, so nothing should be silent for a menu reason.)
- [ ] **RYT-3** `device` With audition on, does note 60 on a track's
      channel actually play that track? The channel half is confirmed
      now; note 60 is the part still guessed.
- [ ] **RYT-4** `device` Listen to the tame windows most likely to be
      wrong: LFO DEPTH (54-74 may be too timid), SAMPLE START/END, and
      FILTER FREQ's floor of 45.
- [ ] **RYT-5** `device` Outliers default to 10%. Is that a nice surprise,
      or too often?
- [ ] **RYT-6** `decide` Sending machine type (CC 15) was left out because
      the CSV's list looks wrong and changing machines wipes the sound. Do
      you want an explicit "send machine" trigger, or leave it out?

## summitpatch
*Never run on hardware. → [NOTES](summitpatch/NOTES.md), Open items / unverified*

- [ ] **SUM-1** `device` First load: does it run, and is the screen
      readable?
- [ ] **SUM-2** `device` STRUCT page: do the NRPNs work, and are the ranges
      right (wave 0-4, slope 0-1, shape 0-2)? The answer is either keep the
      page or drop it.
- [ ] **SUM-3** `device` CCs 77, 78 and 76 are labelled E1>FL, E2>FL and
      O3>FL. Are those really env→filter and osc3→filter?
- [ ] **SUM-4** `device` Is the fine-detune window (58-70) audible at all?
      Is the cutoff floor of 45 right? Do the `perc` and `drone` recipes
      still sound like themselves?
- [ ] **SUM-5** `device` Outliers default to 10%. Right amount?
- [ ] **SUM-6** `device` Play some AFX per-key overlays. Do they feel good,
      and do they work better in mono or legato voice mode as expected?
- [ ] **SUM-7** `decide` Right now it only addresses one Summit part. Do
      you need part B or Multi mode?

## segue
*Being played since 2026-09-20. The v0.8 session on 2026-09-21 went well,
but it was general play, so none of the items below are settled yet. →
[NOTES](segue/NOTES.md), Plan (items by phase) and Open items*

- [ ] **SEG-23** `device` **Before anything else on this list.** The Rytm
      reads tracks 1-12 (RYT-1), but segue defaults to one channel, notes
      0-11 — on which channel 1 is the kick alone. Play anything, then
      switch PARAMETERS > GLOBAL > note layout to "track channels 1-12"
      and say which of the two gives twelve distinct drums. Everything
      else you judge in a session depends on the right one being set.
      **Blocks:** honest answers to SEG-1 onward. → NOTES, Open items.

Phase 1: follow logic

- [ ] **SEG-1** `device` **Does a legato switch in the middle of a bar
      sound continuous?** This is the central question.
- [ ] **SEG-2** `device` Do `xfade` and `handover` sound like anything, or
      just like notes dropping out?
- [ ] **SEG-3** `device` Are the follow times the useful ones? (Even
      divisions plus dotted, nothing odd.)
- [ ] **SEG-4** `decide` Is "chance" (an A/B split) the right control, or
      should each pattern have weights across several destinations?
      Easiest to answer after SEG-1 to SEG-3.

Phase 2: beats

- [ ] **SEG-5** `device` Do the breaks sound like the breaks? They were
      transcribed from memory.
- [ ] **SEG-6** `device` Do the kits within a bank fit together? The
      "everything at once" recipe in FOLLOW.md §11 is the quickest test.
- [ ] **SEG-7** `device` Are the two variety banks the right picks?
- [ ] **SEG-8** `device` Does the finer swing actually improve the breaks,
      and is 75% the right maximum?
- [ ] **SEG-9** `device` Keep an eye on the CPU figure while it plays. The
      clock now runs at 96 PPQN, four times the wakeups it had before, and
      nobody has measured it.

Phase 3: interface

- [ ] **SEG-10** `device` The bank view is 8x8 cells, each 6x3 pixels. Can
      you read it?
- [ ] **SEG-11** `device` Can you follow the fading playhead on the grid,
      or does it just look like flicker?
- [ ] **SEG-12** `device` Can you read the three-letter bank code in the
      header (GEN/HSE/TEC)?
- [ ] **SEG-13** `device` You called the FX grid layout a work in
      progress. What's your verdict once you've played it?
- [ ] **SEG-14** `device` Ableton Link and transport start/stop. Neither
      has been tested.

Phase 4: performance (v0.9 and v0.10, desk-tested only, needs the FX grid)

- [ ] **SEG-19** `device` Beat repeat now loops what you just heard, ending
      on the last hit. Does a short repeat on a sparse lane (the snare)
      come out as the roll you meant?
- [ ] **SEG-20** `device` Is 1/16 the right starting division for a lane
      repeat (FX row 6)?
- [ ] **SEG-21** `device` The repeat ramp: does a swell into a drop, or a
      fade, sound played rather than mechanical? Is 1 bar the right
      default ramp time?
- [ ] **SEG-22** `decide` Latching solo/repeat, so a roll doesn't tie up a
      hand. Pick a gesture: double-tap, a LATCH key taking row 7 col 7
      (copy → user moves to PARAMS only), a param, or none. The trade-offs
      are in NOTES, Key decisions, "Latch is not built".

Decisions deferred until after phases 1 and 2 are heard

- [ ] **SEG-15** `decide` Lane layout: the four toms currently share one
      lane. Go to 12 lanes with a paged grid, or regroup the 8 lanes?
      *Waiting on SEG-1 to SEG-7.*
- [ ] **SEG-16** `decide` Hybrid library (4 kit rows plus 4 variation
      rows): take it or not? *Waiting on SEG-5 to SEG-7.*

My work

- [ ] **SEG-18** `desk` Cache the strings `redraw()` builds on every frame.
      Best done together with SEG-9's CPU reading. *Blocked on SEG-9.*

## cascade
*Hardware pass 2026-09-16. Six batches since then are untested. →
[NOTES](cascade/NOTES.md), Crow / Just Friends and Open items*

- [ ] **CAS-1** `device` JF in sustain mode: does ending a note with level
      0 work cleanly, with no stuck notes and no clicks?
- [ ] **CAS-2** `device` JF level: is 1-10V a sensible range, and is 5V a
      good default?
- [ ] **CAS-3** `device` With 2-3 chords held, does the merged strum still
      sound clear?
- [ ] **CAS-4** `device` Is 300ms the right default release?
- [ ] **CAS-5** `device` Is "strum now" the right default when you add a
      chord?
- [ ] **CAS-6** `device` Do morph and every feel musical at real tempos?
- [ ] **CAS-7** `device` Humanize: is the low end too subtle to hear?
- [ ] **CAS-8** `device` String view: CPU cost. If it's too high, the fix
      is lowering `SAMPLES` to 12.
- [ ] **CAS-9** `device` How do the chord banks actually sound? They've
      been checked for correctness but never heard.
- [ ] **CAS-10** `device` Pressing two chords at almost the same moment
      gives a brief strum of the first one. Can you hear it?
- [ ] **CAS-11** `decide` An arc strumming instrument: a plectrum *mode*
      inside cascade, or **bow** as its own script (IDEAS.md)? It's one or
      the other, not both.
- [ ] **CAS-12** `desk` Slow modulation using norns' built-in `lib/lfo`.
      Say when you want it. *go*
- [ ] **CAS-13** `desk` Drive the bass split from crow's CV outputs.
      *Blocked on CAS-1 and CAS-2, which confirm crow works.*

## polyphasic
*Played 2026-09-15. No tests. → [NOTES](polyphasic/NOTES.md), Open items
and Added (2026-09-19)*

- [ ] **POL-1** `device` Arc: do the rings now follow values that evolve
      or randomize change, without you touching the arc?
- [ ] **POL-2** `device` The arc always comes back on page 1 after a
      reload. Does that annoy you?
- [ ] **POL-3** `device` The track number no longer shows mute state. Do
      you miss it?
- [ ] **POL-4** `decide` Arc page reorganization: which controls do you
      actually reach for while playing? I'll lay the pages out around your
      answer. Tip: notice this during Session D.
- [ ] **POL-5** `desk` Add a test suite. Copying `test_arc.lua` covers the
      arc module that changed. *go*
- [ ] **POL-6** `desk` Clean up where it breaks CONVENTIONS: load modules
      as locals, and shorten header lines to about 36 characters. Planned
      for the next time polyphasic is open for other work.

## Across the repo

- [ ] **X-1** `device` Open segue in SELECT and check whether its header
      lines, about 36 characters each, fit on the screen. CONVENTIONS §2
      sets the house width based on that number.
- [ ] **X-2** `desk` Merge the three `norns_stub.lua` copies into one
      canonical stub. Do it before any new script starts. *go*
- [ ] **X-3** `decide` segue found that the "set a dirty flag, redraw at
      15fps" rule made encoders feel sluggish, and you approved the fix on
      the device: redraw straight from input handlers, capped at 30fps.
      Should that become the rule for all scripts (I'd update CONVENTIONS
      §8), or stay a segue-only exception?
- [ ] **X-4** `decide` IDEAS.md recommends switchboard first, then keel.
      Do you agree, and when do you want the first new script started?
- [ ] **X-5** `decide` Manuals for polyphasic, rytmpatch and summitpatch:
      do you want them, and when?
- [ ] **X-6** `desk` rytmpatch × segue: patch drift triggered by follow
      actions. *Blocked on segue phase 1* (RYT-1 cleared 2026-09-24).
- [ ] **X-7** `desk` rytmpatch's header lines run to about 70 characters.
      Shorten them the next time it's open for other work.

---

## Done

Newest first. Each line gives the date, the item, and the outcome.

- 2026-09-24 · RYT-1: Rytm MIDI CONFIG > CHANNELS read — tracks 1-12 in
  order, FX 13, auto channel 14, perf channel 15; note and parameter
  receive both enabled. rytmpatch's assumed defaults were right.
- 2026-09-24 · RYT-7: nothing to change — the defaults already matched and
  the tests read the params. Closed by RYT-1 rather than by code.
- 2026-09-22 · SEG-17: segue's Open items reconciled with its Plan (hardware
  status, 96 PPQN, swing, scenes → kits, inheritance). Done alongside v0.10.
- 2026-09-21 · segue v0.8 first play session: "went well, understanding more
  of the structure of the interface." General play, so no SEG item closes.
  The FX grid redesign was built around what you actually used.
- 2026-09-21 · Wrote CONVENTIONS.md (checked against the norns source) and
  IDEAS.md. Corrected two wrong API claims in CLAUDE.md.
- 2026-09-21 · Fixed the SMB "multiple connections" error on `\\10.0.0.39\dust`
  by clearing a stale anonymous session.
- 2026-09-20 · Confirmed `norns.local` resolves over mDNS. It had only been
  failing because the norns was off.
- 2026-09-20 · segue: MIDI mapping confirmed on the Rytm. The encoder
  redraw fix was felt on the device and approved.
- 2026-09-19 · Found `gitignore` had never been active (missing dot) and
  fixed it. Added ROADMAP.md and `run-tests.lua`, and reconciled the stale
  docs.
