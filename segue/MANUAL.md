# segue — user manual

**v0.7.0** · MIDI-out drum sequencer for monome norns, built for the Elektron
Analog Rytm. Grid and arc supported. No internal sound engine — segue plays
the Rytm.

Eight lanes of drum patterns, each with its own playhead and its own idea of
when to move on. Launch a pattern and the lane changes to it; leave it alone
and its **follow action** changes it for you — on its own clock, in the middle
of a bar if that is what you asked for, carrying the playhead across so the
beat continues instead of restarting.

---

## 1. Installing

1. Copy the `segue` folder to `dust/code/segue/` on the norns.
2. Load it: **SELECT > segue**.
3. **PARAMETERS > GLOBAL > midi out**: pick your Rytm from the device list.
4. **midi channel** and **note layout** just below it should already be right
   (channel 1, notes 0–11). If your Rytm is set up differently, see §8.
5. Optional, **PARAMETERS > CLOCK**: tempo source (internal, MIDI, Link).
   See §12 for how the pattern grid lines up with a shared clock.

A grid is strongly recommended. segue will use two 8×8 grids, one 16×8, or a
single 8×8, and works out which you have on its own — see §3.

## 2. Quick start

1. **K3** starts the transport. You should hear the amen break — every lane
   starts on kit 1 and the library is already filled in.
2. Tap **FX row 2** buttons to launch whole kits: 2 is a straight four-four,
   4 is electro, 7 halftime. The change lands at the next bar line.
3. Now press a single cell in the **left-hand 8×8** (the LAUNCH grid) —
   columns are lanes, rows are kits. Pressing column 2, row 6 puts the funky
   snare under whatever else is playing.
4. Listen to the hat lanes (columns 5 and 6) over a couple of bars — they
   have follow actions on by default and will move between kits on their own.
5. **E1** picks a lane, **E2** picks one of its patterns. The screen shows
   what that pattern's follow action is set to.
6. **E3** edits the value shown at the bottom of the screen. **Hold K1 and
   turn E3** to choose which value that is.
7. **K1 + K3** panics if anything gets stuck.

## 3. The grids

segue wants two 8×8 surfaces, LAUNCH and FX. It finds them like this:

| what is plugged in          | LAUNCH        | FX                    |
|-----------------------------|---------------|-----------------------|
| two grids (vports 1 and 2)  | port 1        | port 2                |
| one 16×8                    | left half     | right half            |
| one 8×8                     | the grid      | the grid, while holding **K1** |

The layout is printed to maiden on startup if you want to confirm it.

### LAUNCH

Columns are lanes 1–8. **Rows are kits** — slot N means the same beat on
every lane, so row 1 is the amen break right across the grid, row 2 is a
straight four-four, and so on:

| row | kit | steps | |
|-----|-----|-------|---|
| 1 | amen | 32 | the break — two bars, because bar two is what makes it |
| 2 | four four | 16 | straight techno, clap on the backbeat, no snare |
| 3 | think | 16 | the other break — busier kick, ghosted snares |
| 4 | electro | 16 | 808 syncopation, cowbell doing real work |
| 5 | rolling | 16 | driving techno, 16th hats with ghosts |
| 6 | funky | 16 | ghost notes are the whole point |
| 7 | halftime | 32 | sparse, with a descending tom fill in bar two |
| 8 | hypnotic | 16 | minimal — the useful one to drift *into* |

That gives you three ways to play the same material:

- **Launch a whole row** (FX row 2, the scene buttons) — the real,
  interlocking beat.
- **Launch a single cell** — borrow just that lane's part from another kit
  over whatever else is playing. A funky snare under a techno kick.
- **Leave it alone** — follow actions drift individual lanes between kits,
  so every destination is a coherent part rather than a bar count.

A dark cell means that kit has no part for that lane, on purpose: the amen
has no cowbell. Those slots stay silent and follow actions step over them.

This is the grid as it actually ships — the gaps are the kits that leave a
lane out:

```
             1      2      3      4      5      6      7      8
           KICK   SNARE  CLAP   TOMS   CHH    OHH    CYM    COW
         ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
1 amen   │ ███  │ ███  │ ███  │ ███  │ ███  │ ███  │ ███  │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
2 four   │  ▪   │  ·   │  ▪   │  ·   │  ▪   │  ▪   │  ·   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
3 think  │  ▪   │  ▪   │  ▪   │  ·   │  ▪   │  ▪   │  ▪   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
4 electro│  ▪   │  ▪   │  ▪   │  ▪   │  ▪   │  ·   │  ·   │  ▪   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
5 rolling│  ▪   │  ·   │  ▪   │  ·   │  ▫   │  ▪   │  ▪   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
6 funky  │  ▪   │  ▪   │  ▪   │  ·   │  ▪   │  ▪   │  ▪   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
7 half   │  ▪   │  ▪   │  ·   │  ▪   │  ▪   │  ▪   │  ▪   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
8 hypno  │  ▪   │  ·   │  ▪   │  ▪   │  ▪   │  ·   │  ·   │  ▪   │
         └──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

    ███  playing — and fading as its loop plays out
     ▫   queued  — blinking, waiting for the quantize boundary
     ▪   this kit has a part for this lane
     ·   this kit leaves this lane out (follow actions skip these)
```

Above: every lane is playing the amen, and the closed hat has the rolling
kit's hat queued — it will swap in while everything else stays put. Note the
COW column: only electro and hypnotic use the cowbell at all.

- **Press** a cell to launch that pattern on that lane. It takes effect at
  the next launch-quantize boundary (1 bar by default), and the cell blinks
  until it does.
- The **playing** cell is the bright one, and it **fades as its loop plays
  out** — that is the lane's progress through its pattern.
- A dim cell has a pattern in it; a dark cell is empty.
- Pressing a cell also selects that lane and slot for the screen.
- Pressing a cell that is already queued cancels the queue.

### FX

```
        1      2      3      4      5      6      7      8
    ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
 1  │ 1/2  │ 1/4  │ 1/4T │ 1/8  │ 1/8T │ 1/16 │1/16T │ 1/32 │  BEAT REPEAT
    │      │      │      │      │      │      │      │      │  hold
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 2  │ scn  │ scn  │ scn  │ scn  │ scn  │ scn  │ scn  │ scn  │  SCENES
    │  1   │  2   │  3   │  4   │  5   │  6   │  7   │  8   │  tap = launch
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 3  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  MUTE
    │      │      │      │      │      │      │      │      │  toggle
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 4  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  SOLO
    │      │      │      │      │      │      │      │      │  hold
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 5  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  FOLLOW
    │      │      │      │      │      │      │      │      │  toggle
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 6  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  ROLL
    │      │      │      │      │      │      │      │      │  hold
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 7  │ cut  │legato│xfade │hand- │quant │quant │morph │morph │  TRANSITION
    │      │      │      │ over │  −   │  +   │  −   │  +   │  + settings
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 8  │ play │reseed│follow│store │panic │ step │      │      │  TRANSPORT
    │ stop │      │ all  │scene │      │ edit │      │      │  + utility
    └──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘
                            ↑              ↑
                          hold          toggle
```

Row by row:

| row | what it does |
|-----|--------------|
| **1 · beat repeat** | **Hold** one. The next window of that length is captured and then looped for as long as you hold it. Let go and the lanes carry on where they would have been — the timeline keeps running underneath. |
| **2 · scenes** | Tap to launch a scene: every lane queues the pattern stored for it. To store, **hold row 8 col 4** and tap a scene. Scenes start out as "every lane on pattern N". |
| **3 · mute** | Toggle. A muted lane keeps its playhead running, it just makes no sound — so unmuting drops you back in on the beat. |
| **4 · solo** | **Hold**. Momentary, and several at once works. |
| **5 · follow** | Toggle that lane's follow action on/off. Lit = on, and **all eight are on by default** — the rhythm-section lanes just have their patterns set to action `none`, so nothing happens until you give them somewhere to go. Turning this off is the way to freeze a lane that *does* wander (TOMS, CHH, OHH) without editing its patterns. |
| **6 · roll** | **Hold** to play that lane at double speed. A fill you play by hand. |
| **7 · transition** | Cols 1–4 pick the transition for **all** lanes (the lit one is current). Cols 5–6 step launch quantize down/up, cols 7–8 the morph window length. |
| **8 · transport** | **play/stop** · **reseed** (every follow-enabled lane jumps somewhere new now) · **follow all** on/off · **store scene** (hold, then tap a scene) · **panic** · **step edit** (toggle — see §7). |

### Focus mode

**PARAMETERS > GLOBAL > mode** ships on **focus**, which dims three FX rows
— 1 (beat repeat), 4 (solo) and 6 (roll) — and trims the screen's editable
fields from eleven to eight. They are hidden, not removed: a press on a dark
row does nothing, and switching to **full** brings everything back.

The reason is ordering. The follow engine and the kit library are the parts
still being judged; the performance layer is a distraction until those two
sound right. Turn it to `full` whenever you want the rest.

## 4. Follow actions

This is the heart of it. Every pattern carries its own follow setting:

- **follow** — when the action fires, counted from the moment the pattern
  started: off, a musical interval from 1/16 up to 4 bars, or **end** (when
  the pattern loops). This is the setting that lets a change land mid-bar.
- **action A** and **action B** — where to go: `none`, `next`, `prev`,
  `first`, `last`, `any`, `other` (anything but this one), `rand2` (either
  neighbour).
- **chance** — the odds of taking A rather than B. At 100% it is always A;
  at 40% it takes A four times in ten and B the rest.

Empty pattern slots are skipped, so `next` means the next slot that actually
has something in it.

Follow actions **ignore launch quantize** — they fire on their own schedule.
That is deliberate, and it is what makes them feel different from pressing a
button.

Out of the box: kick, snare, clap, cymbal and cowbell hold their pattern;
toms step to the next fill each time round; the hats jump to another pattern
some of the time. Change any of it per pattern on the screen.

**→ [FOLLOW.md](FOLLOW.md) is the full reference** — exactly when the action
fires and why that matters, what each action does, what it is allowed to
land on, how the transitions interact with it, and a set of recipes worth
trying. Read it if you want to actually compose with this rather than just
let it run.

## 5. Transitions

What happens at the moment of the switch — set per lane (FX row 7, or the
screen, or the arc):

- **cut** — restart from step 1. An ordinary clip launch.
- **legato** *(default)* — leave the playhead where it is. Switch on the "and
  of 3" and the new pattern picks up on the "and of 3". This is the one that
  makes a mid-bar change sound like the beat carried on.
- **xfade** — blend. Over the **morph length** (in steps), each voice
  independently plays from the old or the new pattern, the odds shifting from
  one to the other across the window. The change arrives as a dissolve.
- **handover** — the voices change one at a time across the window, highest
  voice first, so the lane's anchor is the last thing to move. Most obvious
  on the TOMS lane, which has four voices. On a one-voice lane there is
  nothing to stagger, so it behaves as **xfade**.

**Launch quantize** (FX row 7 cols 5–6) sets when a *pressed* pattern takes
effect: instant, 1/32 up to 2 bars, or `pattern` (when that lane's own loop
comes round).

## 6. The screen

```
CHH   3 offbeat                   124
  ▄  ▄  ▄  █  ▄  ▄  ▄  ▄      <- the bank, lanes across,
  ─  ─  ─  ─  ─  ─  ─  ─         slots down. bright = playing
  ▁▁    ▁      ▁▁▁                 the row beneath = playheads
follow 1 bar
legato  q 1 bar
```

- Top left: the selected lane and pattern. Top right: tempo.
- The block is the whole bank — eight lanes across, eight slots down. The
  filled cell in each column is what that lane is playing; an outlined one is
  queued. The marks along the bottom are each lane's progress through its
  pattern.
- The bright mark above a column and beside a row show what E1 and E2 have
  selected.
- Second line from the bottom is the value **E3** edits.
- Bottom line is the arc's footer when an arc is connected, otherwise a
  summary of what the next switch will do. In step-edit mode it shows which
  steps are on screen instead.

### Controls

| control | does |
|---------|------|
| **E1** | select lane |
| **E2** | select pattern slot |
| **E3** | edit the value on the second-from-bottom line |
| **K1 + E3** | choose which value that is |
| **K1** | shift (and, on a single 8×8, shows the FX layer) |
| **K2** | launch the selected pattern |
| **K1 + K2** | follow on/off for the selected lane |
| **K3** | play / stop |
| **K1 + K3** | panic |

The editable fields, in order: follow time, action A, action B, chance,
pattern length, transition, division, swing, chance-per-trig, level, morph
steps, **scope**. The first five belong to the selected *pattern*; the next
six to the selected *lane*.

**scope** is the last one and it widens what a follow edit writes to —
`pattern`, `lane` (all 8 of the selected lane's), `kit` (the selected slot
on all 8 lanes) or `all`. While it is set to anything but `pattern` the
field line shows it in brackets, e.g. `[KIT] chance 40%`. Full details in
[FOLLOW.md §9](FOLLOW.md).

Holding **K1** while turning an arc ring applies it to every lane at once.

## 7. Step editing

**FX row 8 col 6** turns the LAUNCH grid into a step editor for the pattern
E1/E2 have selected. The lane keeps playing while you edit it.

Here is the TOMS lane (four voices) with steps 1–8 showing:

```
      step 1    2    3    4    5    6    7    8
        ┌────┬────┬────┬────┬────┬────┬────┬────┐
 BT  1  │ ▪  │    │    │    │ ▪  │    │    │    │  ← the lane's
        ├────┼────┼────┼────┼────┼────┼────┼────┤     voices, one
 LT  2  │    │    │ ▫  │    │    │    │ ▫  │    │     per row
        ├────┼────┼────┼────┼────┼────┼────┼────┤
 MT  3  │    │    │    │    │ █  │    │    │    │  ← █ = playhead
        ├────┼────┼────┼────┼────┼────┼────┼────┤       is here now
 HT  4  │    │    │    │    │    │    │    │ ▪  │
        ├────┼────┼────┼────┼────┼────┼────┼────┤
     5  │    │    │    │    │    │    │    │    │  unused on a
        ├────┼────┼────┼────┼────┼────┼────┼────┤  4-voice lane
     6  │    │    │    │    │    │    │    │    │
        ├────┼────┼────┼────┼────┼────┼────┼────┤
     7  │ p1 │ p2 │    │    │    │    │    │    │  PAGE: steps
        ├────┼────┼────┼────┼────┼────┼────┼────┤  1-8, 9-16, ...
     8  │exit│clr │    │    │    │    │    │    │
        └────┴────┴────┴────┴────┴────┴────┴────┘

    ▪  normal    ▫  ghost    (accent is brighter than normal)
    ·  faint marks sit on every 4th step so you can count
```

- Press a step repeatedly to cycle **rest → normal → accent → ghost → rest**.
  That reaches every velocity level the built-in patterns use, so there is no
  separate velocity mode to switch into.
- The step under the playhead lights up as it goes past, so you can hear and
  see where you are at the same time.
- **Row 7** pages through longer patterns, eight steps at a time. Only the
  pages the pattern is long enough to have are lit.
- **Row 8 col 1** leaves the editor; **col 2** clears the pattern.
- The screen's bottom line shows which steps are on the grid while you are
  in here.

Pattern length is on the screen (`length`, up to 64 steps). A lane whose
pattern is not 16 steps long will drift against the others, which is worth
doing on purpose.

## 8. The Rytm

A voice is just a **MIDI channel and a note number** — twelve of each, and
you can see and edit every one of them in **PARAMETERS > VOICE ROUTING**.
That is the only thing segue consults when it sends a trig.

**PARAMETERS > GLOBAL > note layout** and **midi channel** are *presets*
that fill those 24 values in for you:

| layout | what it writes |
|--------|----------------|
| **one ch, notes 0-11** *(default)* | every voice on **midi channel**, notes 0–11 in track order: BD 0, SD 1, RS 2, CP 3, BT 4, LT 5, MT 6, HT 7, CH 8, OH 9, CY 10, CB 11 |
| one ch, factory notes | every voice on **midi channel**, at the Rytm's factory trig notes: 36, 38, 40, 41, 43, 45, 47, 48, 50, 52, 53, 55 |
| track channels 1-12 | track N on channel N, all at note 60 (C4 — the sound's own pitch). **midi channel** is ignored here, since each track brings its own |

**midi channel** defaults to **1**, so out of the box: everything on channel
1, BD = note 0 counting up. That is the layout this was built against.

Picking a layout, or changing **midi channel**, overwrites all 24 values. So
edit a single voice in VOICE ROUTING *after* choosing a layout, not before —
choosing one again wipes hand edits, by design, because that is the only way
a preset can be a reliable "put it all back" button.

Check **MIDI CONFIG > CHANNELS** on the Rytm if you are unsure what it is
listening on, and make sure it is set to receive notes.

**closed hat chokes open** (PARAMETERS > GLOBAL, off by default) cuts the
open hat whenever a closed hat fires. The Rytm has no choke group across
tracks, so if you want that behaviour it has to come from here.

> **Note on an earlier version.** Up to v0.1.0 there was a "note scheme"
> control and a set of per-voice *overrides*. The overrides were always
> applied, so they permanently shadowed the scheme — both the scheme control
> and its channel control did nothing at all. v0.2.0 replaced that with the
> one-source-of-truth arrangement above. If either control seemed inert to
> you, that was why, and it is fixed.

## 9. The arc

The arc's own button cycles pages.

| page | rings |
|------|-------|
| **PLAY** | division · swing · chance-per-trig · level |
| **MORPH** | transition · morph steps · launch quantize · lane select |

**swing** is a percentage of the lane's own step, 0–75%, so it means the
same thing whatever division the lane runs at. The clock can land on about
every 4% at a 1/16 division, and the displayed value is what will actually
be played rather than what you asked for — so it may settle a percent or
two off where you turned it. 50% is a true triplet feel.

Rings act on the **selected lane** (except launch quantize, which is global,
and lane select, which changes what everything else points at). Holding
**K1** while turning applies the ring to *every* lane — see
[FOLLOW.md §9](FOLLOW.md).

**PARAMETERS > ARC** has sensitivity, brightness, tick level, and an
orientation setting that rotates every ring a quarter turn so the arc reads
right side up however it is sitting.

## 10. Saving, and getting back to the start

**What persists on its own:** segue saves your patterns on quit and reloads
them next time, so an evening's edits survive a power cycle without you
having to remember a pset. That covers pattern content, follow settings and
which kit each lane is on.

**What does not:** lane settings — division, swing, level, mute, follow
on/off, transition, morph — come back at their defaults every time. They
live in params, so a **pset** is how you keep a particular set of them.

**PARAMETERS > patterns > reset to factory kits** puts everything back: the
shipped eight kits, default scenes, every lane setting at its default. That
is the way out if you have edited yourself into a corner.

**PARAMETERS > PSET > save** stores the lot deliberately: every setting, plus
every pattern, follow setting and scene, in a `.data` file alongside the
pset. That is the one to use for something you want to come back to.

## 11. If something goes wrong

- **No sound** — check the MIDI port (PARAMETERS > GLOBAL > midi out), then
  the channel scheme (§8). The Rytm must be set to receive notes on the
  channels segue is sending to.
- **A note is stuck on** — **K1 + K3**, or PARAMETERS > GLOBAL > panic, or
  FX row 8 col 5.
- **Everything is silent but the playheads are moving** — check you have not
  left a lane soloed (FX row 4) or muted the lot (FX row 3).
- **Patterns are changing when you did not ask** — that is a follow action.
  FX row 8 col 3 turns them all off at once.
- **The grid is showing the wrong thing** — you may be in step-edit mode; FX
  row 8 col 6, or row 8 col 1 on the editor itself.

## 12. Syncing to other gear

**PARAMETERS > CLOCK > source** picks where tempo comes from — internal,
MIDI, Link or crow. segue reads its position from that clock rather than
counting from the moment you pressed play, which has one consequence worth
understanding:

- **On a shared clock (Link or MIDI):** the pattern grid is locked to the
  shared timeline, so every peer agrees where the bar is. You can press play
  whenever you like and it will land correctly — *including* landing in the
  middle of a pattern, because that is where the shared timeline says you
  are. Joining a session late drops you into the right part of the phrase
  rather than restarting it.
- **On the internal clock:** there is nobody to agree with, so pressing play
  starts the pattern at step 1 where you pressed it.

If a change is not landing when you expect, check the **launch quantize**
setting (FX row 7, cols 5–6) before suspecting the clock — at `1 bar` a
pressed pattern waits for the bar line, which is up to two seconds.

Note that **follow actions ignore launch quantize entirely** and fire on
their own schedule, which is deliberate — see [FOLLOW.md §7](FOLLOW.md).

segue also sends MIDI **start** and **stop** to every port enabled under
PARAMETERS > CLOCK > "midi out", so downstream gear follows its transport.
norns streams the clock ticks themselves; segue only adds the transport
messages.
