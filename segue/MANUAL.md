# segue — user manual

**v0.8.0** · MIDI-out drum sequencer for monome norns, built for the Elektron
Analog Rytm. Grid and arc supported. No internal sound engine — segue plays
the Rytm.

Eight lanes of drum patterns, each with its own playhead and its own idea of
when to move on. Launch a kit and the lane changes to it; leave it alone and
its **follow action** changes it for you — on its own clock, in the middle of
a bar if that is what you asked for, carrying the playhead across so the beat
continues instead of restarting.

The follow actions have their own reference: **[FOLLOW.md](FOLLOW.md)**.

---

## 1. Installing

1. Copy the `segue` folder to `dust/code/segue/` on the norns.
2. Load it: **SELECT > segue**.
3. **PARAMETERS > GLOBAL > midi out**: pick your Rytm from the device list.
4. **midi channel** and **note layout** just below it should already be right
   (channel 1, notes 0–11). If your Rytm is set up differently, see §10.
5. Optional, **PARAMETERS > CLOCK**: tempo source (internal, MIDI, Link).
   See §14 for how the pattern grid lines up with a shared clock.

A grid is strongly recommended. segue uses two 8×8 grids, one 16×8, or a
single 8×8, and works out which you have on its own — see §4.

## 2. Quick start

1. **K3** starts the transport. You hear the **generic** bank's first kit.
2. Tap **FX row 8** to change bank — col 2 is house, col 5 breakbeats. The
   switch lands on the next bar line, carrying the beat across.
3. Tap **FX row 2** to launch a whole kit on every lane: col 4, col 7.
4. Press a single cell in the **left-hand 8×8** to borrow one lane's part from
   another kit — columns are lanes, rows are kits.
5. Listen to the closed hat (column 5) for a few bars. It follows on its own
   and drifts between kits while everything else holds.
6. **E3** edits the value on the second-from-bottom line. **Hold K1 and turn
   E3** to pick which value. Edits land on **global** unless you say
   otherwise — see §5.
7. **K1 + K3** panics if anything gets stuck.

## 3. Banks

Eight banks of eight kits. A kit is one beat written across the lanes, and
bank slot N is the same kit on every lane — so the launch grid's rows are
kits.

| # | bank | what's in it |
|---|---|---|
| 1 | **generic** | basic, backbeat, drive, half, threes, sparse, busy, fill — straight 4/4 building blocks |
| 2 | **house** | classic, deep, garage, disco, tribal, jackin, minimal, chicago |
| 3 | **techno** | four four, rolling, hypnotic, driving, industrial, peak, broken, dub |
| 4 | **electro** | electro, planet, 808, miami, breakdance, cowbell, detroit, sparse |
| 5 | **breakbeats** | amen, think, funky, halftime, apache, impeach, jungle, skeleton |
| 6 | **variety** | picks that lean four-to-the-floor |
| 7 | **variety 2** | picks that lean broken |
| 8 | **user** | yours — starts empty |

**Why they are grouped by genre.** Follow actions drift single lanes between
the kits of the loaded bank, so the kick might still be on kit 2 when the hat
lands on kit 5. That only sounds like a choice if kit 2 and kit 5 belong
together. So house is eight takes on four-to-the-floor, not house next to a
breakbeat, and the two variety banks are chosen to hang together as sets.

The named breaks (amen, think, apache, impeach) are written from memory at
16th resolution — recognisable, not transcriptions. Edit them by ear.

### Changing bank

**FX row 8**, or **PARAMETERS > GLOBAL > bank**.

- **Stopped:** it changes at once.
- **Playing:** every lane waits for the **launch-quantize boundary** (a bar,
  by default), then switches to the same kit slot in the new bank using its
  own transition. Under legato the playhead carries straight across, so a bank
  change is just another smooth switch. The target button blinks while it
  waits; the bottom line counts down.
- Pressing the bank you are **already on** while a switch is waiting cancels
  it.

### The user bank, and keeping things

The seven factory banks are **read-only**: you can edit any kit while it is
loaded, but the edit is gone when you leave the bank, and loading a factory
bank always gives exactly what shipped. The step editor says `temp` while you
are on one.

The **user** bank is yours. It keeps every edit, and it is saved on its own,
so no pset load can overwrite it.

**Copy to user** — **FX row 7 col 7**, or PARAMETERS > patterns — captures
**what is playing right now** into the first empty user slot: each lane's
current pattern, from whatever bank and kit it happens to be on. So a mix you
like — the classic house kick under a garage hat — becomes a real kit you can
launch, edit and follow later. It is also how you keep an edit made on a
factory bank. The bottom line says which slot it went into; if the bank is
full it replaces the slot E2 is on.

## 4. The grids

segue wants two 8×8 surfaces, LAUNCH and FX. It finds them like this:

| what is plugged in          | LAUNCH        | FX                    |
|-----------------------------|---------------|-----------------------|
| two grids (vports 1 and 2)  | port 1        | port 2                |
| one 16×8                    | left half     | right half            |
| one 8×8                     | the grid      | the grid, while holding **K1** |

### LAUNCH

Columns are lanes 1–8, rows are the loaded bank's eight kits.

```
             1      2      3      4      5      6      7      8
           KICK   SNARE  CLAP   TOMS   CHH    OHH    CYM    COW
         ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
kit 1    │ ███  │ ███  │  ·   │  ·   │ ███  │  ·   │  ·   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
kit 2    │  ▪   │  ▪   │  ·   │  ·   │  ▪   │  ▫   │  ·   │  ·   │
         ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
  ...    │  ▪   │  ▪   │  ▪   │  ▪   │  ▪   │  ▪   │  ▪   │  ▪   │
         └──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

    ███  playing — and fading as its loop plays out
     ▫   queued  — blinking, waiting for the quantize boundary
     ▪   this kit has a part for this lane
     ·   this kit leaves this lane out
```

- **Press** a cell to launch that kit on that lane. It lands on the next
  launch-quantize boundary, and blinks until it does.
- The **playing** cell is the bright one; it fades as its loop plays out.
- A dark cell means that kit has no part for that lane, on purpose — the
  amen has no cowbell. A lane parked on one stays silent, and follow actions
  step over it.
- Pressing a cell also selects that lane and kit for the screen.
- Pressing a cell that is already queued cancels the queue.

### FX

```
        1      2      3      4      5      6      7      8
    ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
 1  │ 1/2  │ 1/4  │ 1/4T │ 1/8  │ 1/8T │ 1/16 │1/16T │ 1/32 │  BEAT REPEAT
    │      │      │      │      │      │      │      │      │  hold · full
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 2  │ kit  │ kit  │ kit  │ kit  │ kit  │ kit  │ kit  │ kit  │  KITS
    │  1   │  2   │  3   │  4   │  5   │  6   │  7   │  8   │  every lane
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 3  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  MUTE
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 4  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  SOLO
    │      │      │      │      │      │      │      │      │  hold · full
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 5  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  FOLLOW
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 6  │ KICK │ SNR  │ CLAP │ TOMS │ CHH  │ OHH  │ CYM  │ COW  │  ROLL
    │      │      │      │      │      │      │      │      │  hold · full
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 7  │ cut  │legato│xfade │hand- │ play │ step │ copy │follow│  GLOBAL
    │      │      │      │ over │ stop │ edit │→user │ all  │  + utility
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
 8  │ gen  │house │techno│electr│break │ var  │ var2 │ user │  BANKS
    └──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘
```

| row | what it does |
|-----|--------------|
| **1 · beat repeat** | **Hold** one. The next window of that length is captured, then looped while you hold. Let go and the lanes carry on where they would have been. |
| **2 · kits** | Launch that kit on **every** lane at once. Bright when every lane is on it, dim when only some are. |
| **3 · mute** | Toggle. A muted lane keeps its playhead running, so unmuting drops back in on the beat. |
| **4 · solo** | **Hold**. Several at once works. |
| **5 · follow** | Toggle that lane's follow action. All eight are on by default; most lanes simply inherit "stay put", so turning one off only changes something on a lane that moves (the hats). |
| **6 · roll** | **Hold** to play that lane at double speed — a fill by hand. |
| **7 · global + utility** | Cols 1–4 set the **global** transition (every lane that has not been given its own follows it). Col 5 play/stop, col 6 step editor, col 7 copy what is playing to the user bank, col 8 follow on/off for all lanes. |
| **8 · banks** | Change bank (§3). The playing bank is bright; a pending one blinks. |

**What left the grid in v0.8, and where it went:** the quantize and morph
up/down buttons gave no feedback — you could not see what you had set without
reading the screen — so they are screen fields and arc rings now. Panic is on
**K1 + K3** and in PARAMETERS. Reseed is in PARAMETERS. "Store scene" is
replaced by **copy to user**, which does the same job but keeps the result.

### Focus mode

**PARAMETERS > GLOBAL > mode** ships on **focus**, which darkens FX rows 1, 4
and 6 (beat repeat, solo, roll) and trims the screen's field list. A press on
a dark row does nothing. **full** brings it all back.

## 5. Settings, and where they apply

Every setting has a **global** value, and anything can have its own.

```
GLOBAL        follow end · none        transition legato
  |
  +- KICK     (inherits)               -> end · none,  legato
  +- CHH      follow 1 bar · other     <- its own
  |             +- kit 7  transition cut  <- its own
  +- SNARE    (inherits)               -> end · none,  legato

change GLOBAL follow to 2 bar:
  KICK and SNARE move.  CHH keeps its 1 bar.
```

This is the Ableton idiom — a clip's launch quantize reads *Global* until you
change it. Change something at the top and everything that hasn't been given
its own value follows; anything that has keeps it.

### The four levels

The last field on the screen is **level**. It says where an edit lands:

| level | an edit changes |
|---|---|
| **global** *(default)* | the value everything falls back to |
| **lane** | just the selected lane |
| **kit** | the selected kit slot on every lane — so a kit carries its own behaviour, not just its notes |
| **pattern** | just the one pattern E1 and E2 are pointing at |

The field line always shows the level in brackets: `[glb] follow end`,
`[lane] chance 40%`.

### Inherited or set

- A value drawn **dim** is inherited from further up. A **bright** value is
  set at this level.
- From an inherited value, the first click up **takes the value you are
  already hearing** and makes it this level's own. The marker changes; the
  sound doesn't. The next click changes it.
- To **clear** an override, turn it down past its lowest setting — it goes
  back to `global` (at the lane level) or back to inheriting (at the pattern
  level).
- At the **kit** level an empty slot is skipped, so a voice that sits a kit
  out stays silent whatever you set.

### What lives at which level

| setting | global | lane | kit / pattern |
|---|:-:|:-:|:-:|
| follow time, action A, action B, chance | ✓ | ✓ | ✓ |
| transition | ✓ | ✓ | ✓ |
| launch quantize | ✓ | — | ✓ |
| division, swing, morph steps | ✓ | ✓ | — |
| velocity, chance / trig, mute, follow on/off | — | ✓ | — |

A level only lists the fields that mean something there. Quantize has no lane
level (as in Ableton, it belongs to the global setting or the clip), and
division, swing and morph are properties of a lane, not a pattern.

**Transition and quantize come from the pattern being launched**, not the one
being left. So give a fill its own `cut` and it always cuts in, while the rest
of the lane stays legato.

The global values are in **PARAMETERS > DEFAULTS**, and each lane's in its own
group. A lane setting at its lowest value reads `global`.

## 6. Follow actions

Each pattern's **follow** setting says when it hands off, **action A / B** and
**chance** say where to. They inherit like everything else (§5), so out of the
box one global "at the end of the pattern, stay put" covers most lanes, and
just three lane-level values make the toms step on and the hats drift.

Follow actions **ignore launch quantize** — they fire on their own schedule,
which is what lets a change land mid-bar.

**→ [FOLLOW.md](FOLLOW.md)** is the full reference: exactly when the action
fires, what each action does, what it can land on, and recipes worth trying.

## 7. Transitions

What happens at the moment of a switch:

- **cut** — restart from step 1. An ordinary clip launch.
- **legato** *(default)* — leave the playhead where it is. Switch on the "and
  of 3" and the new pattern picks up on the "and of 3". This is the one that
  makes a mid-bar change sound like the beat carried on.
- **xfade** — over the **morph** window (in steps), each voice independently
  plays from the old or the new pattern, the odds shifting across the window.
- **handover** — the voices change one at a time, highest first, so the
  lane's anchor moves last. Most obvious on TOMS. On a one-voice lane it
  behaves as xfade.

Set globally on FX row 7, or at any level on the screen (§5).

**Launch quantize** sets when a *pressed* kit takes effect: instant, 1/32 up
to 2 bars, or `pattern` (when that lane's own loop comes round).

## 8. The screen

```
HSE KICK classic                     124
  ▄  ▄  ▄  █  ▄  ▄  ▄  ▄      <- the bank: lanes across,
  ─  ─  ─  ─  ─  ─  ─  ─         kits down, bright = playing
  ▁▁    ▁      ▁▁▁                 the row beneath = playheads
[glb] follow end
legato  none 12
```

- **Top:** the bank (`GEN HSE TEC ELE BRK VR1 VR2 USR`), the selected lane
  and kit, and the tempo.
- **The block** is the loaded bank. The filled cell in each column is what
  that lane is playing; an outlined one is queued. The marks underneath are
  each lane's progress through its pattern.
- **Second from bottom:** the value E3 edits, with its level in brackets.
  Dim = inherited, bright = set here.
- **Bottom:** the answer to *"when does this change, and to what?"* — a queued
  kit or a pending bank change counts down (`> techno bank 12`), otherwise the
  transition and the follow action with its countdown. It briefly shows the
  arc's value just after a ring moves, a notice after copy or reset, and the
  step range in the editor.

### Controls

| control | does |
|---------|------|
| **E1** | select lane |
| **E2** | select kit |
| **E3** | edit the value on the field line |
| **K1 + E3** | choose which value (the last one is **level**) |
| **K1** | shift (and, on a single 8×8, shows the FX layer) |
| **K2** | launch the selected kit on the selected lane |
| **K1 + K2** | follow on/off for the selected lane |
| **K3** | play / stop |
| **K1 + K3** | panic |

## 9. Step editing

**FX row 7 col 6** turns the LAUNCH grid into a step editor for the pattern
E1 and E2 have selected. The lane keeps playing while you edit it.

```
      step 1    2    3    4    5    6    7    8
        ┌────┬────┬────┬────┬────┬────┬────┬────┐
 BT  1  │ ▪  │    │    │    │ ▪  │    │    │    │  <- the lane's
        ├────┼────┼────┼────┼────┼────┼────┼────┤     voices, one
 LT  2  │    │    │ ▫  │    │    │    │ ▫  │    │     per row
        ├────┼────┼────┼────┼────┼────┼────┼────┤
 MT  3  │    │    │    │    │ █  │    │    │    │  <- █ = playhead
        ├────┼────┼────┼────┼────┼────┼────┼────┤
 HT  4  │    │    │    │    │    │    │    │ ▪  │
        ├────┼────┼────┼────┼────┼────┼────┼────┤
     7  │ p1 │ p2 │    │    │    │    │    │    │  PAGE
        ├────┼────┼────┼────┼────┼────┼────┼────┤
     8  │exit│clr │    │    │    │    │    │    │
        └────┴────┴────┴────┴────┴────┴────┴────┘
```

- Press a step repeatedly to cycle **rest → normal → accent → ghost → rest**.
- The step under the playhead lights as it passes.
- **Row 7** pages through longer patterns, eight steps at a time.
- **Row 8 col 1** leaves the editor; **col 2** clears the pattern.
- On a **factory** bank the edit is temporary and the bottom line says
  `temp`. Copy to user (§3) to keep it, or edit on the user bank.

Pattern length is a screen field at the **pattern** level (up to 64 steps). A
lane whose pattern isn't 16 steps long drifts against the others, which is
worth doing on purpose.

## 10. The Rytm

A voice is a **MIDI channel and a note number** — twelve of each, in
**PARAMETERS > VOICE ROUTING**. That is the only thing segue consults when it
sends a trig.

**PARAMETERS > GLOBAL > note layout** and **midi channel** are presets that
fill those 24 values in:

| layout | what it writes |
|--------|----------------|
| **one ch, notes 0-11** *(default)* | every voice on **midi channel**, notes 0–11 in track order: BD 0, SD 1, RS 2, CP 3, BT 4, LT 5, MT 6, HT 7, CH 8, OH 9, CY 10, CB 11 |
| one ch, factory notes | every voice on **midi channel** at the Rytm's factory trig notes: 36, 38, 40, 41, 43, 45, 47, 48, 50, 52, 53, 55 |
| track channels 1-12 | track N on channel N, note 60. **midi channel** is ignored |

Picking a layout overwrites all 24, so hand-edit a single voice *after*
choosing one.

**closed hat chokes open** (PARAMETERS > GLOBAL, off by default) cuts the
open hat whenever the closed one fires. The Rytm has no choke group across
tracks, so it has to happen here.

## 11. The arc

The arc's own button cycles pages.

| page | rings |
|------|-------|
| **PLAY** | division · swing · chance / trig · velocity |
| **MORPH** | transition · morph steps · launch quantize · lane select |

The rings **follow the edit level** (§5). At **global** they turn the global
value; at any other level they turn the selected lane's. (The arc can only
reach params, and the kit and pattern levels are pattern data, so those fall
back to the lane.) Velocity and chance/trig are lane-only and always turn the
selected lane.

Holding **K1** while turning applies a ring to **every** lane at once. It
nudges each lane from where it is, so lanes that were set differently stay
different — the screen's kit and global levels are the way to set them all to
one value.

**velocity** scales every hit on the lane, 0–100%. It can only turn things
down: above 100% accents and normal hits both clipped to full and the kits'
dynamics flattened out. It only changes the sound if the Rytm's tracks respond
to velocity — if turning it does nothing, check that first.

**swing** is a percentage of the lane's own step (0–75%), so it means the same
thing at any division. The clock can land on about every 4% at 1/16, and the
display shows what will actually play.

**PARAMETERS > ARC** has sensitivity, brightness, tick level, and orientation.

## 12. Saving, and getting back to the start

Three things are kept, in three places:

| what | where | kept by |
|---|---|---|
| every setting (global and lane) | params | a **pset** |
| which bank, and which kit each lane is on | `segue-last.data`, and one file per pset | saved on quit; restored on load |
| the **user bank** | `segue-user.data` | saved on quit, after copy to user, and after clearing |

The user bank has a file of its own on purpose: **no pset load can overwrite
it**, so loading an old pset never throws away kits you've built since.

Factory banks are never saved — they always load exactly as shipped.

- **PARAMETERS > patterns > reset to factory** — bank 1, every global and lane
  setting back to its default, every lane on kit 1. It leaves the **user bank
  alone**; that's your work.
- **PARAMETERS > patterns > clear user bank** — empties it.

## 13. If something goes wrong

- **No sound** — check the MIDI port (PARAMETERS > GLOBAL > midi out), then the
  note layout (§10).
- **Silent after changing bank** — you may be on the user bank, which starts
  empty. FX row 8 col 1 goes back to generic.
- **A note is stuck on** — **K1 + K3**, or PARAMETERS > GLOBAL > panic.
- **Everything is silent but the playheads move** — check for a held solo (FX
  row 4) or mutes (FX row 3).
- **Patterns change when you didn't ask** — that's a follow action. FX row 7
  col 8 turns them all off.
- **A setting won't change when you edit it** — check the level. An edit at
  **global** doesn't reach a lane that has its own value; step down to
  **lane** or clear the override.
- **The grid shows the wrong thing** — you may be in the step editor. FX row 7
  col 6, or row 8 col 1 on the editor.

## 14. Syncing to other gear

**PARAMETERS > CLOCK > source** picks the tempo source. segue reads its
position from that clock rather than counting from when you pressed play:

- **Shared clock (Link or MIDI):** the grid locks to the shared timeline, so
  every peer agrees where the bar is. Press play whenever — you land in the
  right part of the phrase, including mid-pattern.
- **Internal clock:** the pattern starts at step 1 where you pressed play.

If a change isn't landing when you expect, check **launch quantize** before
suspecting the clock — at `1 bar` a pressed kit waits for the bar line.

segue sends MIDI **start** and **stop** to every port enabled under
PARAMETERS > CLOCK > "midi out".

## 15. Version history

**v0.8.0** — banks and inheritance.
- Eight banks of eight kits (generic, house, techno, electro, breakbeats,
  variety, variety 2, user), grouped by genre so follow drift stays coherent.
  Bank changes hand off on the launch-quantize boundary.
- Settings inherit: global → lane → pattern, with a **level** field choosing
  where an edit lands. Replaces the old **scope** field, which copied values
  and so couldn't tell a deliberate setting from a copy.
- FX grid redesigned (§4): kits on row 2, banks on row 8, global transition +
  play / step edit / copy to user / follow all on row 7.
- **Copy to user** replaces "store scene".
- Lane **level** renamed **velocity**, capped at 100%.
- *Pset compatibility:* a lane's `level` above 1.0 is clamped to 1.0. Lane
  division, swing, transition and morph gained a `global` value at the bottom
  of their range; older saved values keep their meaning.

**v0.7.0** — lane settings no longer survive a power cycle; reset to factory;
the "what happens next" footer; the arc footer only borrows the line briefly.

**v0.6.0** — the pattern grid follows the shared clock, so Link start lands
on the beat; the screen answers encoder turns immediately.

**v0.5.0** — one encoder click moves one step (it took up to 50); 96 PPQN, and
swing as a percentage with ~4% resolution.

**v0.4.0** — bulk follow edits (scope); holding K1 on the arc reaches every
lane.

**v0.3.0** — the kit library (rows are kits); focus mode.

**v0.2.0** — MIDI: the note layout controls, which had been doing nothing,
fixed; channel 1 / notes 0–11 default; named device picker.

**v0.1.0** — first version.
