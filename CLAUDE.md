# norns-projects — CLAUDE.md

Context for Claude when working in this repo. norns scripts are Lua, run on a Raspberry Pi-based synth/sequencer platform (monome norns). No internet access on-device; scripts load via matron (script engine) and SuperCollider (audio engine) — MIDI-only scripts don't touch the audio engine.

## Script structure (standard shape)

```lua
-- required globals: init(), redraw(), key(n,z), enc(n,d), cleanup()
engine.name = nil -- omit entirely if MIDI-out only, no synth engine needed

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
- **midi** — `midi.connect(n)` returns a device; `dev:send(...)` or `dev:note_on(note, vel, ch)`. Always null-check connected devices in `init()`.
- **grid** — `grid.connect()`; `g.key = function(x,y,z) end`; redraw grid separately from screen via `g:led(x,y,val)` + `g:refresh()`.
- **arc** — same pattern as grid but `a:segment(ring, from, to, level)` for ring UI, or `a:led(ring, index, level)` per-LED. Arc dirty/refresh cycle is separate from screen redraw — don't conflate. For a paged multi-ring param editor (arc's own pushbutton cycles pages, one ring per param), start from `polyphasic/lib/garc.lua` rather than writing this from scratch — it's a generic, reusable module (no polyphasic-specific state in it) covering the parts that are easy to get subtly wrong: smoothing a ring's fill by the param's actual `controlspec.quantum` (not a flat `1/range` guess — that reads fine for a coarse param but makes a fine-grained one like a 0-1 probability flicker/strobe as you turn it, since one detent's worth of motion is way less than a full ring's sweep), a floor/ceiling fixup so a value sitting at min/max still reads as "on" rather than indistinguishable from off, and a discrete-tick rendering mode (evenly-spaced dim ticks + one bright) for params with only a handful of selectable values, since a continuous fill makes a 2-3 option param look like a binary on/off switch rather than a selector. See `polyphasic/NOTES.md` for the fuller rationale/history.
- **Off-device testing** — norns APIs can be stubbed well enough to run a whole script in desktop Lua, which beats the copy-to-device-and-listen loop for anything with real state in it. `segue/test/norns_stub.lua` is a working stand-in (params with controlspecs/formatters/actions, clock coroutines you step by hand, screen/grid/arc/midi recorders that assert on out-of-range draws and notes) plus `S.upvalue()` for reaching a script's locals. `segue/test/test_script.lua` drives `init`/`redraw`/`key`/`enc`/grid/arc/psets/`cleanup` against it; `test_segue.lua` covers the pure-Lua libs directly. Copy the stub into a new script's `test/` and extend it rather than rebuilding it. Keeping libs free of norns APIs — with a lib's dependencies passed into its constructor rather than `include`d, the way the other scripts here already do it — is what makes this cheap.
- **MIDI CC patch editors** — for a script that randomizes/edits an external synth over CC/NRPN, start from `rytmpatch/lib/patchcore.lua` (locks, drift-style randomize, morph over beats, undo/redo, wander, pset-side persistence) + `lib/pageview.lua` (8-slot page drawing); the device-specific part is just a map file like `rytmpatch/lib/rytm_map.lua`. Copies in each script's lib/ are kept identical.
- **params** — use `params:add_number/option/control(...)` in `init()`, group related params with `params:add_group()`. This is how PARAMS menu + pset save/load work; don't hand-roll state persistence if params can hold it.
- **screen** — cairo subset. `screen.level(0-15)` before draw calls, `screen.aa(1)` for antialiasing on curves/circles (used for orb/glow visuals).
- **lib.musicutil** — scale/note utilities. Use `musicutil.generate_scale(root, scale_name, octaves)` instead of hand-building scale tables.
- **lib.sequins** — pattern sequencing container (`sequins{1,2,3}`), useful for per-track step patterns.
- **lib.util** — general helpers (`util.clamp`, `util.linlin` for range mapping — used constantly for velocity→brightness type mappings).

Full API index: https://monome.org/docs/norns/api/index.html

## Best practices for this repo

1. **Redraw sparingly.** `screen.update()` at ~30fps via a dedicated `clock.run` loop, not inside every event handler. Avoid calling redraw() from key/enc/midi callbacks directly if it causes rapid re-draws.
2. **Clock coroutines over metro** for anything musically timed. Reserve `metro` for UI polling (e.g. blink timers) unrelated to tempo.
3. **Always clean up in `cleanup()`** — stop clocks (`clock.cancel(id)`), release grid/arc devices, otherwise orphaned coroutines persist across script reloads.
4. **CPU budget** — norns is a Pi; avoid per-frame table allocation in redraw loops. Precompute what you can in init() or on state-change, not every frame.
5. **MIDI-out-only scripts**: don't set `engine.name`, don't load SuperCollider engine files. This alone meaningfully cuts CPU vs. scripts with an active synth engine.
6. **Params over globals** for anything user-adjustable — gives you the menu UI and pset save/load for free.
7. **Separate visual/logic concerns**: keep sequencing logic and redraw/visual code in different functions or files so visual changes (orb color, glow decay) don't risk touching timing logic.

## Don't

- Don't add `mx.samples` or internal sample-engine code to MIDI-out-only scripts.
- Don't hand-roll scale/chord math when `lib.musicutil` covers it.
- Don't use `os.clock()` or raw Lua timers for musical timing — use `clock`.

Repo structure

This repo holds multiple standalone norns scripts, each in its own subfolder:

norns-projects/
├── CLAUDE.md          <- this file: shared coding conventions, applies to all scripts below
├── README.md          <- git command reference
├── cascade/
│   ├── cascade.lua
│   ├── lib/
│   └── NOTES.md        <- cascade-specific status, decisions, open questions
├── polyphasic/
│   ├── polyphasic.lua
│   ├── lib/
│   └── NOTES.md        <- polyphasic-specific status, decisions, open questions
├── segue/
│   ├── segue.lua
│   ├── lib/
│   ├── test/           <- desktop Lua test suites (see below); norns ignores it
│   ├── MANUAL.md
│   └── NOTES.md
└── (future scripts follow the same pattern)

Each script folder is independent — mirrors its counterpart in dust/code/<name> on the norns device. Coding conventions, API notes, and best practices in this file apply to all of them. Project-specific decisions, current status, and open questions belong in each script's own NOTES.md, not here — keeps this file stable while individual scripts evolve.
