# norns-projects — CLAUDE.md

Context for Claude when working in this repo. norns scripts are Lua, run on a Raspberry Pi-based synth/sequencer platform (monome norns). No internet access on-device; scripts load via matron (script engine) and SuperCollider (audio engine) — MIDI-only scripts don't touch the audio engine.

**Before writing or changing script code, read `CONVENTIONS.md`** — the repo's script-writing standard, checked against the norns source. This file covers the repo's own reusable modules and context; where the two ever disagree, CONVENTIONS.md is the one verified against the API, so fix this file.

## Script structure (standard shape)

```lua
-- required globals: init(), redraw(), key(n,z), enc(n,d), cleanup()
-- engine.name = "..." -- only for a script that uses a SuperCollider engine.
-- MIDI-out-only scripts (every script here so far) leave it out entirely:
-- don't set it, not even to nil.

function init()
  -- set up params, clocks, midi devices, grid/arc connections here
end

function redraw()
  screen.clear()
  -- draw calls
  screen.update()
end

function key(n, z) end   -- n = key 1-3, z = 1 press / 0 release
function enc(n, d) end   -- n = encoder 1-3, d = delta
function cleanup() end   -- save state, stop clocks on script quit
```

## Core modules used across these scripts

- **clock** — coroutine-based timing. Use `clock.run(function() ... end)` for loops, not `metro` for anything tempo-synced. `clock.sync(beat_fraction)` to quantize to transport.
- **midi** — `midi.connect(n)` returns a virtual port; `dev:send(...)` or `dev:note_on(note, vel, ch)`. `connect` never returns nil for ports 1-16 — it hands back a virtual port that survives replugging and silently no-ops with nothing attached, so don't nil-check it; check `port.connected` only to show status. Pick the port with a param. See CONVENTIONS §7.
- **grid** — `grid.connect()`; `g.key = function(x,y,z) end`; redraw grid separately from screen via `g:led(x,y,val)` + `g:refresh()`.
- **arc** — same pattern as grid but `a:segment(ring, from, to, level)` (angles in **radians**, rings 1-based, 64 LEDs) for ring UI, or `a:led(ring, index, level)` per-LED. Arc dirty/refresh cycle is separate from screen redraw — don't conflate. For a paged multi-ring param editor (arc's own pushbutton cycles pages, one ring per param), start from `polyphasic/lib/garc.lua` rather than writing this from scratch (the copies in cascade and segue are identical to it apart from a header comment, so any of the three is a fine place to copy from) — it's a generic, reusable module (no polyphasic-specific state in it) covering the parts that are easy to get subtly wrong: smoothing a ring's fill by the param's actual `controlspec.quantum` (not a flat `1/range` guess — that reads fine for a coarse param but makes a fine-grained one like a 0-1 probability flicker/strobe as you turn it, since one detent's worth of motion is way less than a full ring's sweep), a floor/ceiling fixup so a value sitting at min/max still reads as "on" rather than indistinguishable from off, and a discrete-tick rendering mode (evenly-spaced dim ticks + one bright) for params with only a handful of selectable values, since a continuous fill makes a 2-3 option param look like a binary on/off switch rather than a selector. See `polyphasic/NOTES.md` for the fuller rationale/history.
  - **Call `GArc:poll()` from the script's screen-redraw loop.** Values move for reasons other than the arc — PARAMS menu, pset load, an encoder, a script's own automation — and without polling the rings show whatever they last drew until touched. It compares four values per frame and only redraws on a change, so it's cheap. Every arc script here does this (polyphasic, cascade, segue) — `segue/test/test_script.lua` has a small test you can copy that proves it: a value moved outside the arc redraws the rings, and a still arc redraws nothing.
  - **Rendering styles for continuous rings**, set per-ring alongside `label`/`id`: `style = "bipolar"` (fills out from the origin either way — use it for anything signed, where a plain fill shows "slightly negative" as most of a lit ring), `"comet"` (bright head, fading tail), `"dot"` (head only, for a position rather than an amount), and `track = true` for a dim underlay so a centred or empty value still reads as a dial. Default stays a plain fill, so existing pages look unchanged; opt in where the value's shape warrants it. `cascade/test/test_arc.lua` covers all of them and is worth copying alongside the module.
- **grid redraw** — rebuild the level buffer every frame so the grid follows anything that changes it, but compare against what's already on the hardware and skip `g:led`/`g:refresh` when nothing differs (see `cascade/lib/gridkeys.lua`). A grid sitting still then costs a comparison rather than 64 led writes 30x/sec. Reuse two buffers rather than allocating per frame.
- **Off-device testing** — norns APIs can be stubbed well enough to run a whole script in desktop Lua, which beats the copy-to-device-and-listen loop for anything with real state in it. `segue/test/norns_stub.lua` is a working stand-in (params with controlspecs/formatters/actions, clock coroutines you step by hand, screen/grid/arc/midi recorders that assert on out-of-range draws and notes) plus `S.upvalue()` for reaching a script's locals. `segue/test/test_script.lua` drives `init`/`redraw`/`key`/`enc`/grid/arc/psets/`cleanup` against it; `test_segue.lua` covers the pure-Lua libs directly. Copy the stub into a new script's `test/` and extend it rather than rebuilding it. Keeping libs free of norns APIs — with a lib's dependencies passed into its constructor rather than `include`d, the way the other scripts here already do it — is what makes this cheap.
- **MIDI CC patch editors** — for a script that randomizes/edits an external synth over CC/NRPN, start from `rytmpatch/lib/patchcore.lua` (randomize, morph over beats, undo/redo, wander, pset-side persistence) + `lib/pageview.lua` (8-slot page drawing); the device-specific part is just a map file like `rytmpatch/lib/rytm_map.lua`. Copies in each script's lib/ are kept identical.
  - **Tame the dice, not the knob.** A map entry's `min`/`max` is the real CC range and stays fully reachable by hand; `rmin`/`rmax` is the narrower window randomization may land in, with an optional `bias` ("low"/"high"/"center") shaping the draw inside it. Randomizing across a whole CC range sounds broken far more often than it sounds interesting — inaudible attacks, silent cutoffs, detuned oscillators, distortion pinned — and one bad param ruins an otherwise good roll. Per param, the lock key cycles tame → wide → locked; globally, a "widen range" 0-100% blends every window toward full (and fades bias out with it). Draw the window as ticks on the value bar so the constraint is visible rather than mysterious.
- **params** — use `params:add_number/option/control(...)` in `init()`, group related params with `params:add_group()`. This is how PARAMS menu + pset save/load work; don't hand-roll state persistence if params can hold it.
- **screen** — cairo subset. `screen.level(0-15)` before draw calls, `screen.aa(1)` for antialiasing on curves/circles (used for orb/glow visuals).
- **lib.musicutil** — scale/note utilities. Use `musicutil.generate_scale(root, scale_name, octaves)` instead of hand-building scale tables.
- **lib.sequins** — pattern sequencing container (`sequins{1,2,3}`), useful for per-track step patterns.
- **lib.util** — general helpers (`util.clamp`, `util.linlin` for range mapping — used constantly for velocity→brightness type mappings).

Full API index: https://monome.org/docs/norns/api/index.html

## Best practices for this repo

1. **Redraw sparingly.** `screen.update()` at 15–30fps via a dedicated `clock.run` loop (15 is plenty for most screens and is what polyphasic and the patch editors run; only go higher if something visibly needs it), not inside every event handler. Avoid calling redraw() from key/enc/midi callbacks directly if it causes rapid re-draws.
2. **Clock coroutines over metro** for anything musically timed. Reserve `metro` for UI polling (e.g. blink timers) unrelated to tempo.
3. **`cleanup()` is for what norns can't clean up itself** — note-offs to external synths (panic), returning hardware like Just Friends to its normal mode, saving data, stopping `lib/lfo` instances. norns' own `Script.clear()` already cancels every clock, frees metros, clears grid/arc/midi handlers and swaps out the global table after `cleanup()` runs, so coroutines do not outlive a script (verified against `lua/core/script.lua`; see CONVENTIONS §3).
4. **CPU budget** — norns is a Pi; avoid per-frame table allocation in redraw loops. Precompute what you can in init() or on state-change, not every frame.
5. **MIDI-out-only scripts**: don't set `engine.name`, don't load SuperCollider engine files. This alone meaningfully cuts CPU vs. scripts with an active synth engine.
6. **Params over globals** for anything user-adjustable — gives you the menu UI and pset save/load for free.
7. **Separate visual/logic concerns**: keep sequencing logic and redraw/visual code in different functions or files so visual changes (orb color, glow decay) don't risk touching timing logic.

## Don't

- Don't add `mx.samples` or internal sample-engine code to MIDI-out-only scripts.
- Don't hand-roll scale/chord math when `lib.musicutil` covers it.
- Don't use `os.clock()` or raw Lua timers for musical timing — use `clock`.

## Repo structure

This repo holds multiple standalone norns scripts, each in its own subfolder:

norns-projects/
├── CLAUDE.md          <- this file: repo context + its reusable modules (garc, patchcore, stubs)
├── README.md          <- index of the scripts (with links to their docs) + git command reference
├── CONVENTIONS.md     <- script-writing standard, verified against the norns API
├── ROADMAP.md         <- cross-script tracker: status, next moves, what needs hardware
├── IDEAS.md           <- brainstorm backlog of candidate new scripts + shared infrastructure
├── run-tests.lua      <- runs every script's test/ suite; exits non-zero on failure
├── cascade/           <- strummed-chord instrument:        lib/, test/, MANUAL.md, NOTES.md
├── polyphasic/        <- 4-track polymetric sequencer:     lib/, NOTES.md
├── rytmpatch/         <- Analog Rytm MKII patch editor:    lib/, test/, NOTES.md
├── segue/             <- Rytm follow-action drum sequencer: lib/, test/, MANUAL.md, NOTES.md
├── summitpatch/       <- Summit/Peak patch randomizer:     lib/, test/, NOTES.md
└── (future scripts follow the same pattern)

Every script has a `<script>.lua` entry point next to its `lib/`. `test/` dirs are desktop Lua suites (see Off-device testing above); norns ignores them. `NOTES.md` is the per-script status/decisions/open-questions file; `MANUAL.md` is a user manual, and only cascade and segue have one so far. `ROADMAP.md` at the root is the layer above those: cross-script status and ordering, plus the items that belong to no single script (diverged stubs, shared-copy sync, integrations). It deliberately holds no detail of its own — it links into the NOTES files, so the per-script convention above is unchanged. Update it when a script's status changes (first hardware pass, a suite added, a planned item shipped). `CONVENTIONS.md` is the standard every script is written and reviewed against; when a script teaches the repo a new lesson (a bug class, a norns API surprise), add it there with a pointer to where it happened. `IDEAS.md` holds candidate *new* scripts; an idea that gets picked up becomes a folder and moves onto the ROADMAP.

Each script folder is independent — mirrors its counterpart in dust/code/<name> on the norns device. Coding conventions, API notes, and best practices in this file apply to all of them. Project-specific decisions, current status, and open questions belong in each script's own NOTES.md, not here — keeps this file stable while individual scripts evolve.
