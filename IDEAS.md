# ideas — candidate future scripts

A brainstorm backlog for **new** scripts and shared infrastructure. Ideas
for features in an existing script live in that script's `NOTES.md` (and
are indexed under ROADMAP's "Ideas, not commitments"). Nothing in this file
is a commitment. When an idea gets picked up, it becomes a folder, gets a
`NOTES.md`, and moves onto the ROADMAP.

Each idea is judged by how much it can **reuse** of what's already built
and tested here, and by how much of it can be **proven at a desk**. Right
now the repo's bottleneck is time on the device, not a shortage of ideas
(see ROADMAP). An idea that adds a lot of new hardware assumptions costs
more than it looks.

Size: **S** is about one session, **M** is a few, **L** is a project in
its own right.

Brainstormed 2026-09-21.

---

## New scripts

### relay — follow actions for melodic clips · M
segue's idea applied to pitched material. Each lane holds melodic or bass
phrases for the Summit, and the phrases hand off to each other with
follow actions and legato transitions. The Summit has two parts, so two
lanes on two channels gives you a bass part and a lead part that develop
on their own.
- **Reuses:** segue's lane, pattern and follow engine (`lib/lane.lua`,
  `lib/pattern.lua`) and its tests, cascade's `musicutil` scale handling,
  garc.
- **New:** pitch in the patterns, key and scale as params, a phrase
  library.
- **Wait for:** segue's first real listening pass. If legato hand-off
  doesn't sound continuous on drums, it won't on melodies either. relay
  is only worth building once segue proves the idea.

### keel — a chord progression that runs itself · M
A progression sequencer. Chords live in slots, and the progression moves
between them with follow actions ("usually go to V, one time in four go to
vi"), so it varies every time around instead of looping one fixed cycle.
It sends the chords out as MIDI (to the Summit) or through JF, and
optionally sends the root to a second channel as a bass line. This is
polyphasic's parked "progression banks" idea, built on segue's engine
instead.
- **Reuses:** cascade's `lib/chords.lua` (voicings, stacking by degree,
  voice leading, chord naming, all tested), segue's follow engine,
  cascade's `lib/output.lua` for MIDI/JF.
- **New:** the progression model, and a grid layout for slots and weights.
- **Why it's a strong fit:** almost all of it is logic that already has
  tests. The part that needs hardware (how it sounds) is small.

### switchboard — a MIDI hub for the whole rig · S
norns as the router between the Rytm, the Summit, Ableton and a
controller. It merges, splits, remaps channels, forces notes into a scale,
applies velocity curves, turns single notes into chords, and blocks
feedback loops. Each routing is a row of params, and the whole routing
saves as a pset per setup ("jam", "record", "Rytm drives Summit").
- **Reuses:** polyphasic's velocity curves, `musicutil`, summitpatch's
  "don't echo a device's own input" logic, the MIDI side of the test stub.
- **New:** the routing table, and a screen that shows what goes where.
- **Why:** it's useful every day, small, and nearly all of it can be
  tested at a desk (MIDI in, MIDI out, check what came out). It needs
  almost no device time before you can trust it.

### turing — shift-register melodies for crow and JF · M
A Turing Machine-style looping random sequence. A knob sets how likely each
step is to change, from "locked" to "always new". The sequence goes out on
crow's CV outputs (pitch, gate, and an envelope via ASL) and/or JF. The
grid locks individual bits, and the arc controls change probability,
length and range.
- **Reuses:** patchcore's **tame-the-dice** approach (windows plus bias)
  applied to pitch instead of CC, `musicutil` scale quantizing, cascade's
  guarded crow output, garc.
- **New:** crow's own CV outputs (cascade's NOTES already parks "crow CV
  for the bass split" as waiting on this), and ASL envelopes.
- **Unknowns:** crow CV hasn't been used anywhere in this repo yet. Do
  cascade's JF hardware pass first so crow itself is known to work.

### bow — the arc as a string instrument · M
Four rings, four strings. Speed of rotation sets density and velocity, the
direction you turn sets up or down strokes, and stopping lets the string
ring out. Plays JF's six voices or MIDI. This is cascade's parked "arc
plectrum" as its own instrument, where the arc is the whole interface
rather than a mode inside a grid instrument.
- **Reuses:** cascade's `lib/output.lua` and `lib/chords.lua`, and the idea
  behind the strum engine.
- **New:** turning a physical gesture into notes. That lives or dies on
  feel.
- **Unknowns:** almost all of it. Feel can't be tested at a desk, so this
  is the most hardware-dependent idea here. Do it as a prototype
  (hard-code things, play it, then decide) before writing it properly.
- **Decide first:** do this *or* cascade's plectrum mode. Both would be
  the same work twice.

### loop — a MIDI phrase looper · M-L
Record what you play on the Summit's keys, loop it, overdub, undo, and
quantize after the fact. Loops sit in grid slots and can follow-action
into each other, like segue's lanes but made of your own playing.
- **Reuses:** segue's pattern format and follow engine, lattice timing,
  patchcore's undo model.
- **New:** recording and overdubbing, quantizing in time, loops of
  different lengths lining up. The timing is fiddly, but the virtual clock
  in cascade's stub was built for exactly this kind of problem.
- **Unknowns:** how accurate MIDI input timing is on the Pi. Measure that
  before designing quantize around it.

### geode — JF's rhythm modes, sequenced · S-M
Just Friends has a rhythmic mode (Geode) that cascade doesn't touch. This
would be a small script that clocks and shapes it from norns, synced to
the transport, with the arc controlling its run and shape.
- **Reuses:** cascade's guarded crow/ii output and JF handover.
- **Unknowns:** **the Geode ii commands haven't been checked.** They need
  confirming against the JF/crow ii docs before designing anything. Don't
  build from memory (the lesson from summitpatch's STRUCT page).

### halide — the rig, visualized · S
A script that only draws. It listens to MIDI from the Rytm and Summit and
turns it into polyphasic's glowing-orb Halide style, one orb per channel,
lit by velocity and fading off. Makes no sound. Useful for performing or
filming.
- **Reuses:** polyphasic's `lib/display.lua` Halide renderer, MIDI input
  handling.
- **Why it's low priority:** it's pleasant, but it doesn't make music.
  Worth doing only when the renderer is being reworked for polyphasic
  anyway.

---

## Shared infrastructure (not scripts)

These make every script after them cheaper. As PM, I'd weigh them against
new scripts rather than treat them as chores.

- **One canonical `norns_stub.lua`.** Three different copies exist now.
  Merge cascade's (the richest one) with segue's additions into one, then
  copy that everywhere. Do it **before** the next new script, or that
  script picks up whichever copy it happens to find. *Already on the
  ROADMAP.*
- **A shared output lib.** cascade's `lib/output.lua` makes MIDI and JF
  look the same to the engine. Adding crow CV and gates would make it the
  one output layer for keel, turing, bow and geode. Keep it as identical
  copies, the same way `garc.lua` works.
- **A shared tame lib.** Right now patchcore's windows-plus-bias
  randomizer only works on CC values. Pulled out into its own lib, it's
  the dice for turing's pitches, keel's chord choices and polyphasic's
  evolve.
- **Use norns' own `lib/lfo`** for cascade's parked "shared slow-modulation
  lib". It already ships with norns: clocked or free-running, six shapes,
  depth, phase and `add_params()`. That turns a planned lib into a
  call-site change (see CONVENTIONS §6).

---

## My pick, if you asked me today

1. **Clear the device backlog first.** segue, rytmpatch, summitpatch and
   cascade's JF work all need time on the device. A new script now would
   add a fourth thing nobody has tested. The stub merge is the one piece
   of desk work worth doing before that.
2. **Then switchboard.** It's small, useful every day, and can be tested
   end to end at a desk. It's the one new script here that won't join the
   hardware queue.
3. **Then keel**, once segue's listening pass says follow actions sound
   right. It gets the most out of what's already built: cascade's chord
   engine plus segue's follow engine, both tested, pointed at something
   neither does alone.

relay and turing are strong follow-ups to those. bow and loop need the
most time on the device, so they come last.
