# conventions — how scripts in this repo are written

The standard for writing a norns script here. It comes from two places:
**the norns Lua API** (checked against the norns source, not remembered),
and **lessons these five scripts learned the hard way** (each linked to where
it happened).

- `CLAUDE.md` holds the repo's *own* reusable modules: `garc.lua`, the grid
  diff buffer, `patchcore.lua`, the test stubs. Use those; this file doesn't
  repeat them.
- A script's `NOTES.md` records its own decisions. If a script breaks a rule
  here on purpose, write down why in its NOTES.

Last checked against the norns source: **2026-09-21**. The API claims below
cite the file they come from (`lua/core/...` in
[monome/norns](https://github.com/monome/norns)). If norns updates change
one, fix it here and note the date.

---

## 1. Folder and files

```
<name>/                  == dust/code/<name>/ on the device
├── <name>.lua           entry point; norns lists it under SELECT
├── lib/                 everything that isn't wiring
├── test/                desktop Lua suites; norns ignores the folder
├── NOTES.md             status, decisions, open items (required)
└── MANUAL.md            user manual (once the script is played for real)
```

- The script's name is lowercase, one word, and the same as its folder name.
  `include()` paths depend on that.
- Put runtime state in `norns.state.data` (that's `dust/data/<name>/`).
  Never write inside the script's own folder, because the repo mirrors that
  folder and the repo's `.gitignore` leaves out `data/`.

## 2. The header comment

norns turns the script's opening comment into its SELECT preview
(`Script.metadata`, `lua/core/script.lua`):

- Every line starting with `--` counts, and norns strips the first three
  characters. **The first line that isn't a comment ends the header.** A
  blank line counts as not a comment, so use `--` on its own for spacing.
- The preview (`lua/core/menu/preview.lua`) shows **8 lines at a time**,
  scrolls with E2, and **doesn't wrap**. Long lines just run off the right
  edge of the screen.

House format:

```lua
-- segue
-- v0.7.0
-- follow-action drum sequencer
-- for the Elektron Analog Rytm
-- MIDI out only -- see MANUAL.md
--
-- (what it does, in a few short lines)
--
-- E1: ...  K2: ...   (controls last)
```

- Put the name on line 1 and the version on line 2. What the script is goes
  in lines 3-5, so the first screen of the preview answers "what is this".
- **Keep each line to about 36 characters** after the `-- `, the width
  cascade, segue and summitpatch use. polyphasic and rytmpatch run to about
  70 and get cut off. *The exact width that fits hasn't been measured yet.
  It's on the ROADMAP device checklist.*
- Change the version in the header and in the MANUAL's version history
  together.

## 3. Lifecycle: what norns cleans up, and what it doesn't

On unload (and before the next script loads), `Script.clear()` in
`lua/core/script.lua` does the following, in this order:

1. **Calls your `cleanup()`**, wrapped in `pcall`. An error there gets
   printed and ignored.
2. Clears grid, arc, midi, hid and osc handlers. Arc LEDs get blanked.
3. `metro.free_all()`, **`clock.cleanup()`** (cancels every coroutine and
   clears `clock.transport.start/stop` and `tempo_change_handler`),
   `poll.clear_all()`, and destroys the shared LFO lattice.
4. **Swaps out the global table**, so the last script's globals are gone.
5. `params:clear()` and resets the screen state (`aa(0)`, `level(15)`,
   `line_width(1)`, font 1 at size 8).

So a script **cannot** leak clocks, metros or device callbacks into the
next one, and `cleanup()` doesn't need to cancel clocks just to prevent
that. (That corrects earlier advice in this repo.) Cancelling your own
clocks is still fine and tidy. It just isn't what keeps things safe.

**`cleanup()` is for what norns can't know about:**

- **Note-offs.** norns sends none. Anything still sounding on an external
  synth keeps sounding. Call your panic, with an explicit note-off per held
  note (cascade `Strum:panic`, segue `voices_out:panic()`). Sending CC 123
  alone isn't enough, because not every synth listens for it.
- **External hardware state.** For example, Just Friends stays in ii mode
  and ignores its own panel until something sends `mode(0)`. The crow reset
  norns does at unload doesn't reach JF (cascade `Output:shutdown`).
- **Saving what the params don't hold** (`<name>-last.data`, see §5).
- **Stopping any `lib/lfo` instances** you started (`:stop()`).

Keep `cleanup()` safe when `init()` got only partway through: guard each
line (`if strum_ then ... end`), because a crash in `init()` still gets
you a `cleanup()` call.

## 4. Modules, locals, globals

- **Everything is `local`.** That includes modules:
  `local Lane = include("segue/lib/lane")`. polyphasic's global `Sequence`,
  `GridLib` and `lattice` are the thing to fix, not to copy. Globals don't
  leak between scripts (see §3), but they do leak between a script's own
  files. They can also silently overwrite a norns global.
- **Never shadow a norns global.** Don't reuse these names: `screen`,
  `params`, `clock`, `midi`, `grid`, `arc`, `crow`, `util`, `tab`,
  `metro`, `poll`, `engine`, `softcut`, `audio`, `norns`, `include`,
  `controlspec`, `hid`, `osc`, `keyboard`.
- Use `include("<name>/lib/<file>")` for the script's own libs and
  `require("<lib>")` for norns libs. Write norns libs as
  `local musicutil = require("musicutil")` (most scripts here already use
  that spelling).
- **Libs don't reach for norns APIs.** Pass what a lib needs (a MIDI port,
  a param getter, a clock) into its constructor. That's what lets `test/`
  run the lib in desktop Lua (see `CLAUDE.md`, Off-device testing).
- **Script-level globals** are only the callbacks norns calls: `init`,
  `redraw`, `key`, `enc`, `cleanup`, and `refresh` if you use it.
- MIDI-out scripts never set `engine.name`, and never set it to `nil`
  either (norns sets it to `nil` on unload anyway).

## 5. Params

Everything the player can change lives in params. That gives you the menu,
psets and MIDI mapping for free.

API (`lua/core/paramset.lua`):

```lua
params:add_group("strum", "STRUM", 6)          -- id, name, count; can't nest
params:add_separator("out_sep", "output")
params:add_number(id, name, min, max, default, formatter, wrap)
params:add_option(id, name, {"a", "b"}, default)
params:add_control(id, name, controlspec.new(min, max, warp, step, default, units, quantum), formatter)
params:add_binary(id, name, "toggle" | "momentary" | "trigger", default)
params:add_trigger(id, name)
params:set_action(id, function(v) ... end)
params:set(id, v, silent)                      -- silent: no action
```

Rules:

- **Ids are snake_case with no spaces, and they're permanent.** Psets store
  values by id, so renaming an id silently drops everyone's saved value.
- **Option order is part of the pset format.** A pset stores the option's
  *number*. Reordering options changes what old psets mean (polyphasic's
  `direction` reorder, 2026-09-15). Add new options **at the end**. If you
  really must reorder, say so in the MANUAL's version history.
- **Use `add_group`'s three-argument form** (`id, name, n`). The
  two-argument form still works but has no id. **`n` has to match** the
  number of params that follow. Get it wrong and params land outside the
  group or get swallowed into it. Test for it: cascade's `test_script.lua`
  checks every group's count.
- **Call `params:bang()` once, at the end of `init()`.** It runs every
  action except triggers. So **every action has to be safe to run at
  startup, and safe to run twice.** segue found out what a param with a
  default can do here: 24 "optional" overrides fired on every boot and
  silently beat the real setting (segue NOTES, Fixed).
- Actions run in the order params were added, and a "set them all" global
  depends on being added *before* the per-lane params it writes to. That's
  fragile, so leave a comment next to anything that depends on order.
- **Any param the arc shows needs a `controlspec` with a real `quantum`.**
  garc smooths the ring by that step (see `CLAUDE.md`).
- **Big data doesn't belong in params.** A few hundred sound values or a
  pattern library would bury the menu. Save them next to each pset
  instead:

  ```lua
  params.action_write  = function(filename, name, number) ... end
  params.action_read   = function(filename, silent, number) ... end
  params.action_delete = function(filename, name, number) ... end
  ```

  Use `tab.save`/`tab.load` into `norns.state.data`, named after the pset
  number. Also autosave `<name>-last.data` in `cleanup()` and load it in
  `init()` **without sending anything to the hardware** (rytmpatch,
  summitpatch, segue all do this).

## 6. Timing

API (`lua/core/clock.lua`):

```lua
local id = clock.run(fn, ...)      -- returns an id for clock.cancel
clock.sleep(seconds)                -- inside a clock.run only
clock.sync(beats, offset)           -- next multiple of `beats`, plus optional offset
clock.get_beats(); clock.get_tempo(); clock.get_beat_sec()
clock.transport.start = function() end   -- cleared on unload, so assign in init()
clock.transport.stop  = function() end
clock.tempo_change_handler = function(bpm) end
```

- **Anything musical goes through `clock`.** Use `clock.sync` for
  tempo-locked timing, and `clock.sleep` for time in seconds (gate lengths,
  release tails). Never use `os.clock()`, `os.time()` or a busy loop.
- **`metro` is for the UI only** (grid refresh, blink). Never use it for
  timing notes.
- If you have several rates or a master tick, use `lattice` instead of
  hand-rolling one coroutine per rate (polyphasic, segue). segue's master
  clock runs at 96 PPQN, so **each tick has to be cheap**: bail out early on
  a modulo test, and don't allocate anything.
- **Guard any clock that might have been superseded.** When a coroutine can
  be replaced (a re-pressed chord, a restarted strum), whatever it has
  scheduled needs to check that it's still the current one before it sends
  a note. Give it a token or generation number and compare before acting.
  Without that guard a stale wake either hangs a note or plays one that
  should never have sounded (cascade v0.5.1, `lib/strum.lua`).
- **Use the built-in `lib/lfo` for slow modulation** before writing your
  own. It's `require("lfo")`, with clocked or free-running modes, shapes
  sine/tri/square/random/up/down, depth, phase and baseline, plus
  `:add_params()` to get a menu for free. Call `:stop()` in cleanup.

## 7. MIDI

API (`lua/core/midi.lua`):

- **`midi.connect(n)` returns virtual port `n` (1-16), and it's never
  `nil`** for a valid `n`. The port object stays the same when devices are
  unplugged and replugged. With nothing attached, its methods quietly do
  nothing. So **don't nil-check what `connect` gives you.** Check
  `port.connected` if you want to *show* whether something's there.
- **Choose the port with a param**, and build its option list from
  `midi.vports[i].name`. Call `midi.connect` again in the param's action.
- **Channels, note maps and CC numbers are all params**, never assumed
  constants. Both rytmpatch's channel defaults and segue's note layout
  turned out not to match the real Rytm.
- **Incoming MIDI:** `port.event = function(data) local msg =
  midi.to_msg(data) ... end`. Branch on `msg.type`.
- **Don't send a device's own input back to it.** If the input and output
  are the same port, don't pass notes through (summitpatch's "auto" thru
  mode).
- **Every note-on needs a note-off that will definitely happen:** a
  scheduled one, one sent on release, or panic in `cleanup()`. Keep track
  of what's sounding so panic knows what to turn off.
- MIDI clock out is a norns system feature (PARAMETERS > CLOCK). Scripts
  only add start/stop in the `clock.transport` handlers.

## 8. Screen

Screen API: `screen.clear/level/move/line/text/text_right/text_center/
text_extents/rect/circle/fill/stroke/pixel/aa/line_width/font_face/
font_size/blend_mode/update`. The display is 128x64 with brightness levels
0-15.

- **Redraw from one `clock.run` loop at 15 fps**, and only when a `dirty`
  flag says something changed. `key`/`enc`/MIDI callbacks just set `dirty =
  true`. They never call `redraw()` themselves.
- **Every draw call comes after a `screen.level(...)`.** Set `aa`, font and
  line width on every frame you use them. Don't count on what the last
  frame left behind.
- **Don't allocate anything per frame.** Precompute layouts and strings
  when the state changes, not inside `redraw()`.
- **Keep visual code out of timing code** (`lib/display.lua` in cascade
  and polyphasic). A visual change should never be able to touch when a
  note fires.
- Test that drawing stays on screen: the stub asserts on draws outside
  128x64.

## 9. Grid, arc, crow

- **Grid:** `grid.connect(n)`, with `g.key = function(x, y, z)`. Read the
  size from `g.cols`/`g.rows`, never assume 16x8. Use the repo's diff
  buffer to redraw (see `CLAUDE.md`). If two grids are possible, detect
  them (segue's `gridui`) rather than making it a setting.
- **Arc:** use `garc.lua` (see `CLAUDE.md`). If you go below it:
  `a:segment(ring, from, to, level)` takes **radians**, rings and LEDs
  count from 1, each ring has 64 LEDs, and levels are 0-15. Call
  `garc:poll()` from the redraw loop.
- **crow / Just Friends:** crow is missing more often than it's plugged
  in. Guard every `crow.ii` call. Switch JF to `mode(1)` when it becomes
  the target and back to `mode(0)` when it stops, and in `cleanup()`
  (cascade `lib/output.lua`). Build the output as an object shaped like a
  MIDI port (`note_on`/`note_off`/`cc`), so the engine never needs to know
  where notes go.

## 10. Libraries to reach for first

| need | use | not |
|---|---|---|
| scales, note names, chords | `musicutil` (`generate_scale`, `note_num_to_name`) | hand-built tables |
| step patterns | `sequins` | index arithmetic |
| several rates on one clock | `lattice` | one coroutine per rate |
| slow modulation | `lfo` | a home-grown LFO |
| clamp / map / wrap | `util.clamp`, `util.linlin`, `util.wrap` | inline maths |
| saving tables | `tab.save` / `tab.load` | hand-written serializers |

Remember that `musicutil.generate_scale` **stops at MIDI 127**, so the
table can come back shorter than you asked for (polyphasic NOTES, Fixed).

## 11. Tests, docs, and shipping

- **`test/` exists from day one.** Copy the richest stub (see ROADMAP,
  Cross-cutting) and drive the whole script with it: `init`, every param
  group's count, keys, encoders, grid, arc, psets, `cleanup`.
- **Test that a setting changes what goes out.** "It lands in range"
  passes even when the setting does nothing (segue's inert-override bug).
- Run `lua run-tests.lua` before you commit.
- **Keep `NOTES.md` current** with status, key decisions, open items,
  what's been fixed, and how to verify. Say whether the latest changes have
  been on hardware, with a date.
- **Change the MANUAL** whenever behaviour changes. That includes moving
  "Planned" items to the version history when they ship.
- **Update `ROADMAP.md`** when the status changes: a first hardware pass, a
  suite added, a planned item shipped.

## 12. New-script checklist

- [ ] Folder name matches the script name, with `<name>.lua`, `lib/`, `test/`, `NOTES.md`
- [ ] Header: name, version, what it is, "MIDI out only", controls; lines ~36 chars
- [ ] Everything `local`; no norns global shadowed
- [ ] Every user-adjustable value is a param, with permanent snake_case ids
- [ ] Group counts checked by a test; options only ever added at the end
- [ ] `params:bang()` last in `init()`; every action safe to run at startup
- [ ] MIDI port, channels and notes are params; no nil-check on `midi.connect`
- [ ] Musical timing on `clock`; UI timing on `metro` or the redraw loop
- [ ] Redraw loop at 15 fps behind a dirty flag; nothing allocated per frame
- [ ] `cleanup()`: panic with explicit note-offs, return external hardware, save data, stop LFOs
- [ ] No `engine.name`
- [ ] Added to `README.md`, `ROADMAP.md`, and `CLAUDE.md`'s repo structure
