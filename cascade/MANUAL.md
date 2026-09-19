# cascade — user manual

**v0.5.0** · MIDI-out chord strumming instrument for monome norns
Grid and arc supported. No internal sound engine — cascade plays other things.

Hold a grid cell and the chord under it strums. Hold several and they merge
into one strum across all their notes. In cycle mode the strum repeats for as
long as you hold, and everything about it — timing, dynamics, pattern, note
count — can be changed while it rings.

---

## 1. Installing

1. Copy the `cascade` folder to `dust/code/cascade/` on the norns.
2. Load it: **SELECT > cascade**.
3. **PARAMETERS > MIDI OUT**: pick the device and channel your synth listens on.
4. Optional, **PARAMETERS > MIDI IN**: pick a keyboard to play chords from.
5. Optional, **PARAMETERS > CLOCK**: choose the tempo source — internal, MIDI,
   or Ableton Link. Anything cascade syncs follows this.

Nothing else to install. A grid is strongly recommended; an arc is optional
but is where the instrument really opens up.

## 2. Quick start

1. Hold any cell in the **bottom-left area** of the grid. You should hear a
   chord strum, and keep re-strumming while you hold.
2. Move up a row within the same group of four: the same chord, a wider
   voicing.
3. Move along a column: a different chord from the same key.
4. Hold two cells at once: their notes merge into one longer strum.
5. **K3** switches between repeating (cycle) and playing once (one-shot).
6. **K2** panics — stops all notes — if anything gets stuck.

## 3. The grid

cascade uses the **left 8×8** of the grid. The right half is dark and reserved
for a sequencer later.

```
        columns 1 - 8  =  8 scale steps up from the key root
      ┌─────────────────────────────┐
row 1 │  widest voicing             │
row 2 │                             │  upper octave
row 3 │                             │
row 4 │  tightest voicing           │
      ├─────────────────────────────┤
row 5 │  widest voicing             │
row 6 │                             │  lower octave
row 7 │                             │
row 8 │  tightest voicing           │
      └─────────────────────────────┘
```

- **Columns** are scale steps up from the key root, so column 1 is the root,
  column 8 the octave. Everything is in key — you cannot play a wrong note.
- **Rows 5–8** are the lower octave, **rows 1–4** the upper.
- **Within each group of four**, the bottom row is the tightest voicing of the
  current bank and the top row is the widest. Up means more open.

**Brightness:** dim cells are ordinary scale notes, brighter cells are
sharps/flats, so the row reads like a piano keyboard. Held cells light fully.

**Playing:** press to strum, hold to keep it ringing (or repeating), release
to let it fade over the release time. Several cells held at once merge into
a single strum.

## 4. Keys and encoders

| Control | Action |
|---|---|
| **K1** | norns system menu — cascade never sees this key |
| **K2** | Panic: stop all notes. Acts on release |
| **K3** | Switch one-shot / cycle |
| **K2 held + E2** | Change arc page, forwards or backwards |
| **E1** | Bank |
| **E2** | Key root |
| **E3** | Scale |

Turning any encoder while K2 is held cancels the panic, so reaching for a page
never silences you by accident.

## 5. The screen

| Area | Shows |
|---|---|
| Top left | Key and scale |
| Top right | one-shot or cycle |
| Centre | Chord name. `+2` means two more chords are merged in |
| Lower half | The strings — one per note, lowest at the bottom |
| Bottom | The last arc ring you touched, and its value |

**The strings** ripple when struck and settle back to flat lines. Higher
notes ripple tighter and faster, and a harder strike displaces them further.
The wobble is the effect you see filming a guitar with a phone: the camera
reads the picture one column at a time, so a vibrating string comes out as a
travelling wave rather than a blur.

Chords with more than six notes — two or three held together — are shown as
six strings spread across the range, so you always see the outer notes.

Chord names are read from the notes actually sounding, so an inverted chord
shows its bass after a slash, like `Cmaj7/E`.

## 6. The arc

Press the arc's own button to change page. If your arc has no button, hold
**K2 and turn E2**.

| Page | Ring 1 | Ring 2 | Ring 3 | Ring 4 |
|---|---|---|---|---|
| **STRUM** | rate | pattern | cycle rate | mode |
| **MOTION** | pattern cycle | every | morph | drift |
| **FEEL** | tilt | humanize | probability | velocity |
| **VOICE** | note length | release | density | upstroke level |
| **CHORD** | bank | invert | octave | transpose |

Two rings change what they edit depending on your settings:

- **rate** edits strum span when *fit to repeat* is on; otherwise the note
  division when strum sync is on, or milliseconds when it's off.
- **cycle rate** edits the note division when cycle sync is on, milliseconds
  when it's off.

Rings with only a few choices show as separate ticks; wider ones fill
gradually. **Tilt** and **transpose** fill outward from the top in whichever
direction the value sits, over a dim ring, since both run negative to
positive and a one-sided fill would misread.

The rings follow the values wherever they change — turn something in the
PARAMS menu or load a pset and the arc updates to match.

## 7. Parameter reference

### OUTPUT / MIDI IN
| Parameter | Range | Default | Notes |
|---|---|---|---|
| send to | midi / just friends / midi + jf | midi | Where notes go |
| midi device | — | 1 | Where chords are sent |
| midi channel | 1–16 | 1 | |
| bass channel | off, 1–16 | off | Sends the lowest note to its own MIDI channel |
| bass octave | −2 to +1 | 0 | Drops the bass note by octaves |
| jf note | pluck / sustain | pluck | Pluck lets JF's envelope end the note; sustain holds it until you let go |
| jf level | 1–10 V | 5 V | How hard full velocity hits JF |
| midi in device | — | 1 | Play chords from a keyboard |

### KEY
| Parameter | Range | Default | Notes |
|---|---|---|---|
| root | C–B | C | The key. Also **E2** |
| scale | all norns scales | major | Also **E3**. Chromatic lifts the in-key rule |
| octave | 1–6 | 3 | Register of the lowest grid row |
| transpose | −24 to +24 | 0 | Shifts output only; the key is unchanged |

### CHORD
| Parameter | Range | Default | Notes |
|---|---|---|---|
| bank | 13 banks | sevenths | The chord flavour. Also **E1** |
| invert | −4 to +4 | 0 | Positive rolls notes up an octave, negative down |
| velocity | 1–127 | 100 | Base velocity before tilt and humanize |
| voice lead | off / on | off | Each chord takes the placement closest to what's already sounding |

### STRUM
| Parameter | Range | Default | Notes |
|---|---|---|---|
| mode | one-shot / cycle | cycle | Cycle repeats while held. Also **K3** |
| latch | off / on | off | Chords keep playing after you let go |
| strum sync | off / on | off | Lock the gap between notes to the clock |
| strum rate | 0–200 ms | 25 ms | Gap between notes, when sync is off |
| strum div | 1/2–1/128 | 1/64 | Gap between notes, when sync is on. The slow end is more arpeggio than strum |
| fit to repeat | off / on | off | Size the strum to the repeat instead |
| strum span | 5–100% | 50% | How much of each repeat the strum fills |
| cycle sync | off / on | on | Lock the repeat to the clock |
| cycle rate | 50–2000 ms | 500 ms | Repeat time, when sync is off |
| cycle div | 1/1–1/16 | 1/4 | Repeat time, when sync is on |
| new chord | strum now / next repeat | strum now | What a newly pressed chord does |

### PATTERN
| Parameter | Range | Default | Notes |
|---|---|---|---|
| pattern | 13 patterns | up | The order and timing of the strum |
| cycle | hold / advance / alternate / random | hold | What happens between repeats |
| every | 1–16 repeats | 2 | How often the pattern changes |
| morph | 0–8 repeats | 1 | Repeats spent blending into the new pattern |

### FEEL
| Parameter | Range | Default | Notes |
|---|---|---|---|
| tilt | −100 to +100% | 0 | Velocity slope across the strum. Negative fades out |
| humanize | 0–100% | 15% | Small variation in timing and velocity, every strum |
| drift | 0–100% | 10% | Slow wander in tempo and loudness, over tens of seconds |
| density | 10–100% | 100% | Thins the chord, always keeping the lowest and highest note |
| probability | 0–100% | 100% | Chance each note sounds, re-rolled every strum |

### ARTICULATION
| Parameter | Range | Default | Notes |
|---|---|---|---|
| note length | let ring / 1–100% | let ring | How long notes sound, as a share of one repeat |
| release | 0–2000 ms | 300 ms | How long notes ring after you let go |
| upstroke level | 10–100% | 100% | How much quieter upstrokes are |
| upstroke notes | 10–100% | 100% | How many notes an upstroke catches, from the top |

### DISPLAY
| Parameter | Range | Default | Notes |
|---|---|---|---|
| visual | strings / dots / off | strings | Dots is cheaper to draw; off is cheapest |

### ARC
| Parameter | Range | Default | Notes |
|---|---|---|---|
| sensitivity | 1–64 | 24 | Lower is more sensitive |
| brightness | 1–15 | 15 | |
| dim level | 1–15 | 4 | Unselected ticks |
| position | 1–4 | 1 | Rotates rings a quarter turn, for how the arc sits |

## 7b. Crow and Just Friends

cascade can play Just Friends directly, over crow's ii bus.

**Wiring:** crow connects to the norns over USB and is detected
automatically — nothing to install. Run a 3-pin ii cable from crow's ii
header to Just Friends', lining up GND, SCL and SDA; on monome cables the
white stripe marks GND. Keep it short, and check the orientation against
JF's manual before powering up. Crow supplies the bus power, so a crow and
JF on their own need no powered bus board.

**Playing it:** set **OUTPUT > send to** to `just friends`, or `midi + jf`
to play a synth and JF together. Just Friends has six voices, so six notes
sound at once — the same six the screen draws as strings. A bigger chord
still plays; the oldest voice gets taken for the newest note.

- **jf note** — `pluck` hands the note's length to JF's own envelope, so
  its front panel decides how it decays. `sustain` holds each note until
  you let the chord go.
- **jf level** — how hard full velocity hits JF. Tilt, humanize and
  velocity all still apply on the way.

While JF is the target, cascade takes it over via ii; quitting the script
hands it back so its front panel works normally again.

## 8. Chord banks

Every bank holds four voicings — one per row within a group of four, tightest
at the bottom, widest at the top. Apart from the triads bank, they're all four
to six notes, so there's always something to strum.

| Bank | Character |
|---|---|
| triads | Plain three-note chords. The only bank without extra notes |
| add nine | Triads with a ninth added. Open, bright, unfussy |
| sixths | Sixth and six-nine chords. Warm, vintage |
| sevenths | Standard seventh chords. The default, works anywhere |
| ninths | Fuller sevenths with the ninth on top. Lush |
| elevenths | Suspended, floating, often no third |
| thirteenths | The richest tertian stacks. Dense and jazzy |
| sus | Suspended second and fourth. Unresolved, ambiguous |
| quartal | Stacked fourths. Modern, gospel, soul |
| fifths | Fifths and octaves. Hollow, open, good for power and ambient |
| spread | Triads spread wide across two octaves. Guitar-like |
| octave bass | Root doubled low, colour stacked high. Anchored |
| clusters | Adjacent notes. Shimmering, tense, good for texture |

Banks are defined in `lib/chords.lua` and are meant to be edited.

## 9. Strum patterns

A pattern sets *when* each note lands, not just the order — so some notes can
land together, and the spacing can speed up or slow down.

| Pattern | What it does |
|---|---|
| up | Lowest to highest, evenly |
| skip up | Odd notes first, then the evens. Broken, rolling |
| pairs | Two notes at a time |
| accelerate | Lowest to highest, gaps shrinking |
| decelerate | Lowest to highest, gaps growing |
| thumb | Bass note, a pause, then the rest |
| pinch | Lowest and highest together, then the middle |
| block | Everything at once. Not a strum at all |
| outside-in | Outer notes first, converging inward |
| inside-out | Middle notes first, spreading outward |
| skip down | Skip up, reversed |
| down | Highest to lowest |
| random | Shuffled each time |

**Pattern cycle** decides what happens between repeats: `hold` stays put,
`advance` steps to the next pattern, `alternate` flips the current one
backwards and forwards, `random` picks a new one. **every** sets how many
repeats pass between changes, and **morph** blends gradually into the new
pattern over that many repeats instead of switching abruptly. Turning the
pattern knob blends too.

## 10. How it behaves

Worth knowing, because it explains what you hear:

- **One strummer, shared notes.** Every held chord adds its notes to one pool,
  which is strummed as a single gesture. Two chords don't produce two strums;
  they produce one longer one, like an arpeggiator.
- **Chord changes are soft.** Letting go doesn't cut the notes — they ring for
  the release time. A note another held chord still uses keeps sounding.
- **Upstrokes are detected, not configured.** If the highest note lands first,
  cascade treats that repeat as an upstroke and can play it quieter and on
  fewer notes, like a real pick. Notes it skips keep ringing.
- **Density and probability differ.** Density is the same every repeat — a
  genuinely thinner voicing. Probability re-rolls per note per repeat — a
  shimmer. They stack.
- **Humanize and drift differ.** Humanize varies each strum independently.
  Drift wanders slowly over tens of seconds, like a player easing off and
  pushing again.
- **Live edits apply on the next repeat.** Bank, inversion, transpose,
  pattern, timing and feel are all re-read every repeat, so a held chord
  re-voices itself without being re-pressed.
- **Latch turns tapping into holding.** With latch on, tap a chord and it
  keeps playing; tap the same cell again to drop it. Latched cells stay lit
  on the grid, slightly dimmer than a key under your finger. K2 clears
  everything, and turning latch off releases whatever it was holding.
- **Voice leading keeps chords near each other.** With it off, every chord
  sits wherever its root falls, so moving along the grid jumps the whole
  chord around. With it on, each new chord picks the inversion and octave
  closest to what's already sounding — the notes shift a little instead of
  leaping. Invert still works on top of it as an offset.
- **The bass split takes the lowest note of everything held.** Held chords
  merge into one voicing, so there's a single bass note, not one per chord.

## 11. Recipes

**Acoustic strumming.** Cycle mode, cycle div 1/8, pattern cycle `alternate`,
every 1, morph 0, upstroke level 60%, upstroke notes 60%, humanize 25%,
drift 20%.

**Slow harp.** Pattern `decelerate`, fit to repeat on, span 90%, cycle div
1/1, note length let ring, density 100%, tilt −30%.

**Tight rhythm part.** Pattern `block` or `pairs`, note length 25%, cycle div
1/8, humanize 10%, probability 85%.

**Ambient wash.** Bank `clusters` or `fifths`, cycle div 1/1, fit on, span
100%, release 2000 ms, probability 60%, drift 40%.

**Two-chord arpeggio.** Hold two cells a step apart, pattern `up`, fit on,
span 100%, note length 30%.

## 12. Troubleshooting

| Problem | Try |
|---|---|
| No sound | Check MIDI OUT device and channel, and that the synth listens on that channel |
| A note is stuck | **K2**. If it keeps happening, note what you did — it's a bug |
| Chord keeps repeating | That's cycle mode. **K3** for one-shot |
| Nothing happens on the right half of the grid | Correct — cascade only uses the left 8×8 |
| Arc rings don't move | Check the arc's page; lower ARC sensitivity for finer control |
| Can't change arc page | Your arc may have no button — hold **K2** and turn **E2** |
| Strum too long with several chords | Turn on **fit to repeat**, or lower **density** |
| Feels mechanical | Raise **humanize** and **drift**; try pattern cycle `alternate` with morph |
| Feels sloppy | Lower **humanize**; most of its range is deliberately subtle |
| Screen feels sluggish | **PARAMETERS > DISPLAY > visual**: switch to dots, or off |
| Chords jump around as you move | Turn on **voice lead** |
| Want chords to keep playing hands-free | Turn on **latch**; tap again to drop one, K2 clears all |

## 13. Version history

**v0.9.0** — Crow and Just Friends output: a `send to` parameter picks MIDI,
Just Friends over crow's ii bus, or both. JF's six voices are allocated per
note, with pluck or sustain note behaviour and a level setting.

**v0.8.0** — Synced strum rates now reach down to 1/2, for arpeggio-slow
strums. The arc keeps up with values changed anywhere else, and tilt and
transpose draw outward from centre instead of as a one-sided fill.

**v0.7.0** — String view: the strum is drawn as vibrating strings with the
rolling-shutter wobble a phone camera gives guitar strings. A new `visual`
parameter switches to the older dots, or turns the visual off. Removed the
unused petal images left over from the original flower screen.

**v0.6.0** — Added a triads bank (first in the list, and the only one with
plain three-note chords), latch, a bass split to its own MIDI channel, and
voice leading. Note that adding triads shifted the other banks along by one,
so a pset saved before this loads the neighbouring bank.

**v0.5.1** — Fixed three bugs behind occasional hanging notes and a clock
crash: stopping a strum could cancel a clock that was about to fire, a note
could be struck just after its chord was released, and re-pressing a ringing
note could leave it with no note-off scheduled.

**v0.5.0** — Engine batch. Note length as a share of the repeat; density;
fit to repeat; slow drift; upstroke detection with level and note count. New
arc page VOICE.

**v0.4.0** — One shared strummer: held chords merge into a single strum
instead of separate ones, fixing clashes between them. Soft chord changes
with a release time. Patterns became timed slots, allowing simultaneous
strikes, shaped timing, and morphing between patterns. Banks 4 → 12, patterns
5 → 13. Humanize retuned to be far gentler. Arc paging moved to the arc's
button, with K2+E2 as a fallback.

**v0.3.0** — Rewritten as a single-note-in, chord-out instrument, modelled on
Ableton's Expressive Chords. Whole-grid note keyboard, degree-stacked
voicings, live MIDI-in, one-page arc. Fixed hanging notes and a panic that
stalled the script.

**v0.2.0** — First version under this design, renamed from `chordflow`.

## 14. Planned

Crow and Just Friends output, using its six voices as six strings; an arc
"plectrum" mode for strumming by hand; and slow modulation of any parameter.

The right half of the grid is reserved for a sequencer.
