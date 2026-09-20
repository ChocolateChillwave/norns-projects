# polyphasic — status notes

4-track polymetric/polyphasic MIDI sequencer, adapted from open-source "pitter-patter." MIDI-out only, no internal sound engine.

## Key decisions
- Kept pitter-patter's grid-position-equals-note approach; note pool is scale-aware/quantized to a chosen scale
- `note_lo`/`note_hi` (per-track note range) are indices into `scale_full`
  (1..note_max, currently 49), not absolute pitches — so the ceiling/floor's displayed
  note name is scale-dependent, not fixed. `scale_full` walks the chosen scale until it
  collects `note_max` entries; a scale with fewer notes/octave (e.g. major pentatonic, 5)
  needs more octaves to reach that count than one with more (a diatonic scale, 7), so
  switching scale can noticeably raise or lower what note_hi=note_max actually sounds
  like without note_hi's own value changing at all. This is intentional/liked
  (2026-09-15). Important wrinkle found the same day: MusicUtil silently *stops*
  generating past MIDI note 127, so `scale_full` can end up shorter than `note_max` —
  see Fixed below. `note_max`'s own comment in `sequence.lua` explains the current
  7-octave cap and why it isn't higher.
- `direction`'s value order is forward/backward/ping-pong/random/brownian (1-5) as of
  2026-09-15, reordered from the original backward/ping-pong/random/forward for a more
  intuitive menu order. See Open items for the old-pset compatibility wrinkle this
  creates.
- Division list extended with odd/triplet divisions
- Removed mx.samples / sample-engine integration (was ~22% CPU on one track) since this build is MIDI-out only
- Visual: "Halide" — glowing per-track orbs over a faint dot-matrix field (x =
  track lane, y = pitch just played). Reinstated 2026-09-15 after a same-day
  round trip through "Vanishing" (a streetlamp-per-track night-road scene,
  baked background image + live glow) — Vanishing shipped, worked, but felt
  convoluted in practice and was reverted back to Halide. See Fixed/Added
  entries below for what Vanishing involved, in case it's worth another look
  later (its background image was deleted 2026-09-17 in a repo tidy-up —
  recoverable from commit 5e20ca0 at polyphasic/img/).
- Interface kept minimal, visual style inspired by Torso Electronic S4

## Open items
- Multiple sequences *per track* — flagged 2026-09-15 for future reference, no design
  decided yet. Worth knowing before designing it: pitter-patter's original pattern-bank
  system is already in here, just not something we've used/discussed yet — each track
  already has 7 selectable pattern banks (the `sequence` param, matrix stored per-bank
  in `self.matrices`) plus a rudimentary "chain mode" (grid's alternate state, toggled
  via the bottom-right grid button) that steps through a programmable order of banks
  automatically. Might already cover part of what "multiple sequences per track" means,
  might not — evaluate that existing mechanism first before building something new.
  2026-09-15: confirmed as a "circle back later" idea specifically as progression
  banks — each bank labeled/used as a chord slot, chain mode auto-stepping the
  progression. Not started.
- Arc page reorganization — flagged 2026-09-15, not started. Current pages
  (PLAY/MIX/RANGE/PERFORMANCE) were laid out by params-menu category, not by
  what's actually reached for while jamming/performing; worth rethinking the
  grouping around live performance use once there's a backlog of candidates
  worth reorganizing around (this session added vel_curve and link_track as
  PARAMETERS-only, deliberately not placed on arc yet, partly for this reason).
- Vanishing, if it's ever revisited: reverted 2026-09-15 for feeling convoluted
  next to Halide, not because it was broken. Unresolved when it was pulled: the
  lamp head/base coordinates in what was `Display.lamp_pos` were read off the
  background image by eye (pixel-grid overlay + cropped zooms, done outside the
  script) and weren't confirmed pixel-accurate on a real screen before the
  revert, and it was still an open question whether 4 lamps read as 4 distinct
  tracks without an extra differentiator (line weight, height, label). The
  background image (rainy_city_128x64_pixel_art.png) was deleted 2026-09-17
  along with the rest of the repo's unused images — nothing loaded it once
  Vanishing was reverted. Restore it from commit 5e20ca0 if this is ever
  picked back up:
  `git checkout 5e20ca0 -- polyphasic/img/`
- Odd (non-triplet) divisions — scrapped for now (2026-09-15), may revisit later.
- Euclidean pattern mode per track — skipped for now (2026-09-15).
- Arc: no page-cycle fallback for an arc without its own pushbutton (K1 is already the
  shift modifier here, unlike chordflow which had it free). Revisit if that turns out
  to matter on real hardware.
- Arc pset save/load for `arc_page`/`main_sequence` selection isn't persisted — arc
  always comes back on page 1 after a script reload. Minor; revisit if it's annoying
  in practice.
- `direction`'s numeric values were reordered 2026-09-15 (see Fixed) — an **old saved
  pset** that stored a specific `direction` value will now mean something different
  under the new order (e.g. old value 4 meant "forward", now means "random"). Not
  worth a migration for a script still this early in testing, but worth remembering
  if an old pset starts playing a track in a direction that looks wrong.
- MIDI device/channel routing was pulled off the arc 2026-09-15 at your request
  (set once via PARAMETERS or a pset instead). clear/evolve, which were on the same
  page, moved to a new PERFORMANCE page alongside randomize and track select —
  arc is now PLAY/MIX/RANGE/PERFORMANCE (4 pages).
- Track number's glowing badge (circle + knockout digit) was Halide-specific
  chrome that outlived Halide's own redesign without being reconsidered —
  simplified 2026-09-15 to plain text ("1", not "track 1"), same style as
  bpm/cpu, top-left mirroring bpm/cpu's top-right. Moved out of `display.lua`
  entirely (was `draw_badge`) into `polyphasic.lua`'s `redraw()`, gated by the
  same `show_header` toggle as bpm/cpu. No longer shows mute state (the badge
  used to dim on mute) — not asked for back; say so if it's missed.
- Dropped "(triplet)" from the division names shown in the menu/arc/footer
  (2/3, 1/3, 1/6, 1/12, 1/24) — redundant once you can see the fraction itself.
  Only `divisions_strings` in polyphasic.lua changed; the code comment above it
  explaining *why* ppqn=96 suits the triplet-family divisions is unrelated
  (about the underlying clock math, not display text) and stays as-is.

## Added (2026-09-15)
- Split the single `show_header` toggle into three independent DISPLAY params
  (`show_track`, `show_bpm`, `show_cpu`) — hiding bpm/cpu was also hiding the
  track number, which wasn't wanted. `redraw()` now checks each separately;
  bpm and cpu still share one line/one `screen.text_right` call when both are
  on (unchanged look), but the string is only built from whichever of the two
  is actually enabled.
- Arc footer no longer runs off-screen (was noticed on "randomize": "PERFORMANCE
  randomize: randomized!" is 35 characters, well past what a 128px line holds).
  `GArc:footer_text()` (garc.lua) now hard-truncates to a `FOOTER_MAX_CHARS`
  budget (22 initially, raised to 30 after that cut scale names down to
  nothing useful in practice — still an estimate, no exact on-device
  character-width measurement, may need another pass) with a plain "..." (not
  a single
  ellipsis glyph — not dependent on the active font having that character), so
  *any* verbose formatted value is bounded, not just today's known case.
  First pass dropped the page name entirely to make room; felt too stripped
  in practice, so page name + ring label + the `[ALL]` broadcast tag (if
  present) are back and always shown in full — only the formatted *value* at
  the end ever gets trimmed, since that's both the likeliest-to-be-long part
  and the one you can already read off the arc's own ring. Also shortened the
  PERFORMANCE page's own name to "PERF" (footer-only; nothing else displayed
  the full name) since at 11 characters it alone was eating half the budget.
- Velocity curve, global (`vel_curve` param, "polyphasic" group, alongside
  vel_lo/vel_hi): random (original behavior), ramp up, ramp down, triangle,
  sine (a smoothed triangle). Curve *type* is global but curve *position* is
  per-track — each track ramps/cycles across its own `limit` and current step,
  not a shared phase, since tracks can have different loop lengths. Required
  changing `get_velocity`'s call signature from `self.get_velocity()` to
  `self.get_velocity(self)` (in `Sequence:note_on`) so the curve function can
  read the calling track's own step/limit — `curve_velocity` in polyphasic.lua
  replaces the old `random_velocity`. Other curve shapes considered but not
  built (say if any are wanted): accent/pulse (peak on step 1 or every Nth
  step), alternating strong/weak (swing-like), random walk (smoothed random —
  each pick a small step from the last, instead of fully independent draws).
- Per-track `link_track` param (0 = off, 1-4 = which other track): when set,
  `randomize` and `evolve` bias their generation toward pitches already
  present in the linked track, instead of picking uniformly at random —
  opt-in, off by default, existing unlinked behavior is unchanged either way.
  `randomize` lowers the density threshold for linked pitches (more likely to
  land, not guaranteed); `evolve` has a 70% chance (`LINK_EVOLVE_CHANCE`) of
  picking its replacement note from the linked track's current pitches when
  any are in range, else falls back to a fully independent pick. New
  `Sequence:linked_note_set()` reads the linked track via the global
  `sequencers` table (same ambient-global pattern already used for
  params/midi/clock in this file, not threaded through the constructor) and
  scans that track's *entire* matrix, not just its active loop — "what
  pitches is that track using" in general, not just this instant.
- Display redesign, round 2: "Vanishing" implemented, superseding Halide the same
  day it shipped. A user-generated pixel-art image (a rainy night road with 4
  streetlamps, grayscale, prompted from the coordinate/composition spec built
  earlier this session) turned out to already be exactly 128x64 8-bit grayscale —
  checked with `magick identify` after installing ImageMagick (winget) for this,
  same reasoning as installing local Lua earlier: cheaper to verify than to
  guess. Quantizing it to norns' actual 16 gray levels (`magick ... -posterize 16`)
  barely changed it, since the pixel-art style already used fairly flat tones
  close to what 16 levels can hold — the fine-detail-loss risk flagged when this
  was still a hypothetical didn't really materialize.
    - `display.lua` rewritten around it: the image (`polyphasic/img/
      rainy_city_128x64_pixel_art.png`) loads once in `Display.init` via
      `screen.load_png` (pcall-guarded, same defensive pattern chordflow uses for
      its petal images) and blits with `screen.display_image` once per frame —
      one draw call regardless of how detailed the art is. Only the glow/pool/
      indicator are still procedural, drawn on top at each lamp's fixed
      (hx,hy)/(bx,by) position from `Display.lamp_pos`.
    - Behavior: a lamp is fully dark between hits (no idle "rest" glow, unlike
      the orb/Halide concepts before it). A muted track's lamp sits at a flat dim
      level (`MUTED_DIM`) that ignores note triggers entirely, rather than
      reacting and just capping lower. The current track gets a small dot above
      its lamp (`draw_indicator`) instead of Halide's corner badge — no track
      number shown on screen anywhere now.
    - `Display.draw`'s signature changed again: `muted` is now `muted_by_track`
      (a table, one entry per track — every lamp needs its own mute state now,
      not just the selected track's, since all 4 are visible at once).
      `polyphasic.lua`'s `redraw()` builds this into a module-level table reused
      every frame (`muted_by_track`, declared once near the top of the file) —
      not a fresh table allocated inside `redraw()` itself, which runs at 15fps.
    - `row` (pitch) is still accepted by `Display.trigger` for call-site
      compatibility with `sequence.lua`'s `on_note` callback, but Vanishing
      doesn't use it — lamps sit at fixed positions rather than a pitch-mapped
      row the way the orb concepts worked.
- Display redesign, round 1: "Halide" concept adopted (picked from 3 mockups compared live — (picked from 3 mockups compared live —
  see the artifact from this session for Rack/Scanned/Halide side by side). Real
  implementation in `display.lua` differs from the browser mockup in one important
  way: the mockup's dot-matrix field was dense (~700 dots, cheap in a browser) but
  that's far too many `screen.pixel` calls to redraw at 15fps on a Pi (CLAUDE.md's
  CPU-budget rule), so the on-device version uses much sparser spacing (every 12px
  for the full field, every 8px along the 4 lanes — a few dozen draws, not hundreds).
  Also added:
    - Track number + mute state as a small glowing corner badge (`draw_badge` in
      display.lua) — filled circle, digit knocked out of it in black
      (`screen.level(0)` over the fill, confirmed this actually paints black rather
      than skipping the draw), dims when muted instead of a second "muted" text
      label. Replaces the old plain "track N ...muted" text line.
    - `PARAMETERS > DISPLAY > "show bpm/cpu"` — the header line is now optional
      (defaults on).
    - Bottom line now shows the arc's footer when one's connected (it already
      covers play/direction/division-equivalent info for whatever ring you're on)
      and only falls back to the old play/direction/division text when no arc is
      present — no longer both at once, and no longer permanent regardless of arc.
  `Display.draw` signature changed: now `Display.draw(num_tracks, current_track,
  muted)` — the last two are optional (omit to skip the badge).
- Arc lights up on script startup instead of staying dark until first touched —
  `garc_:redraw()` now runs once right after `params:bang()` in `init()`.
- Arc broadcast: holding K1 while turning a ring applies that change to all 4
  tracks at once instead of just the selected one (footer shows `[ALL]` while
  held, so it's clear when a turn is about to go wide). Generic support added to
  `garc.lua` — a ring can carry an optional `all_ids` (a function returning every
  id it should apply to) alongside its normal `id`; `shift_fn` (passed once to
  `GArc:new`) is a function saying whether the modifier is currently held. Only
  polyphasic's per-track rings got `all_ids` (via a new `all_track_fields(name)`
  helper, sibling to `track_field`) — global rings (velocity, track select) don't
  have anything sensible to broadcast to, so K1 does nothing extra there.
  `is_shift` had to move earlier in polyphasic.lua (was declared after `init()`,
  which needs it as an upvalue when constructing `garc_`).
- Grid keyboard row (bottom row, "play it like a MIDI controller" entry) now
  sustains while held instead of writing a single-step blip. Press writes an
  attack at the current step; each further sequencer step reached while still
  held gets tied to it (`Sequence:note_on_live`/`note_off_live`, plus a
  hold-tracking check added right after `step_peek` in `Sequence:update`) —
  release just stops future ties, it doesn't erase what's already there. Only
  actually sustains while the sequencer is playing (`update()`, hence the step
  advance, only runs then) — holding a key while stopped still just marks the
  one fixed current step, same as before. Guards against re-tying its own start
  step, since ping-pong/random/brownian can revisit it while still held (would
  otherwise turn the attack back into a tie). Replaces the old `toggle_note`
  (was a toggle; a real keyboard doesn't have a "tap twice to erase" gesture,
  and the matrix area still supports full toggle-based editing regardless).
- BPM shown next to CPU% (top-right, screen redraw) — reads the global `clock_tempo`
  param, same as norns' own CLOCK menu shows.
- Default changes: `arc_brightness` 15 -> 10; every track's `midi_out_channel` now
  defaults to 1 (was `self.id`, i.e. tracks 1-4 defaulting to channels 1-4
  respectively specifically to avoid collision — that reasoning's overridden now per
  your ask, so if you want tracks split across channels again it's no longer the
  default, just set it per-track); `poly` now defaults to mono (was poly).
- MIDI clock out. Turns out norns already does the actual clock-tick streaming at
  the system level (`PARAMETERS > CLOCK > "midi out"`, per-port toggle,
  `clock_midi_out_1..16`) with zero script code needed — no reason to reinvent that.
  What was missing: this script's own play/stop didn't tell those ports anything, so
  an external arpeggiator would free-run on the clock ticks without actually
  starting/stopping with the sequencer. Added `send_transport(msg_type)` in
  polyphasic.lua, called from the `main_play` param's action (`"start"`/`"stop"` to
  every port with `clock_midi_out_N` enabled) — this fires both from the K3
  play/stop key and from `clock.transport.start/stop` (Link), so either source now
  propagates outward too.
- Grid: holding one step and tapping another now sustains the note across that whole
  span (one attack + tied continuation through every step in between) instead of the
  old behavior of toggling on a separate attack at every step along the line between
  them (removed along with its Bresenham-line helper, `get_line_coordinates`/`gcd` in
  ggrid.lua — nothing else used them). Uses the *pitch of whichever key is currently
  being pressed* (not the first one) for the whole span; a genuinely diagonal
  hold-and-tap (different pitches) collapses to that one row rather than attempting
  some kind of pitch glide, since a "sustain" only makes sense at a single pitch.
  New `Sequence:sustain_range`/`:sustain_pos` (sequence.lua) do the deterministic
  attack+tie write (unlike `toggle_cell`, these aren't a toggle — they overwrite
  whatever was in that span, since the point is "make this one held note"). The
  existing double-tap-a-step-to-tie-it-to-the-previous-step gesture is unchanged.
- `randomize` and `evolve` now occasionally generate a short sustained/tied run
  (1-3 steps, `SUSTAIN_CHANCE`/`SUSTAIN_MAX_STEPS` in sequence.lua) instead of always
  a lone single-step attack, using the same attack+tie shape the grid gesture above
  produces. `evolve`'s tie-run stays within `limit` (matching its existing scoping —
  see Fixed, the freeze bug), `randomize`'s within `sequence_max`.
- Arc controller, factored into `lib/garc.lua` (a reusable, polyphasic-agnostic
  module — see CLAUDE.md's arc entry). `polyphasic.lua` just supplies the page/ring
  layout — 4 pages: PLAY (division/direction/limit/probability), MIX (mute/poly/
  velocity lo+hi), RANGE (note lo/hi, scale, root), PERFORMANCE (track select,
  clear, randomize, evolve) — MIDI device/channel routing was dropped from arc, see
  Open items. PERFORMANCE's "track" ring is `main_sequence` itself (global, not
  per-track) — changing it changes which track *every other page's* rings act on,
  the same as turning E1; it's a 4-option param so it renders as discrete ticks like
  the others there. Each per-track ring's `id` is a resolver
  *function* (`track_field(name)`) rather than a fixed string, so it always targets
  whichever track is currently selected (`main_sequence`) — `garc.lua` itself has no
  idea "tracks" exist, it just calls `id()` when `id` is a function. `enc()` now also
  calls `garc_:redraw()` when `main_sequence` changes, since switching tracks changes
  what every per-track ring means without the arc itself being touched.
  Params: `arc_threshold` (sensitivity), `arc_brightness` (lit level), `arc_dim`
  (unselected-tick level), `arc_position` (1-4, rotates every ring a quarter turn so
  the arc reads right-side up regardless of physical orientation).
  Screen footer moved to its own line (was sharing a line with the existing
  direction/division text and could collide with it) and now shows the param's
  actual formatted string (`params:string(id)`) instead of a raw number.
- `note_max` (the note_lo/note_hi pool size) is 7 octaves (49 notes) — up from the
  original 6 (42), but dialed back from an initial 9-octave attempt that turned out
  to push a diatonic scale's ceiling past MIDI's valid range at the default root note
  (see Fixed: musicutil crash). Matrix storage grows accordingly (more columns per
  step, across all 16 pattern banks x 4 tracks) — fine for the Pi at rest, but worth
  knowing if pset save/load ever feels slow.
- Per-track `clear` param (sequence.lua, same on/turn-e3-to-arm pattern as
  `randomize`/`evolve`) — clears that track's matrix without needing K1+K2/K1+K3.
- Per-track `poly` param (mono/poly). Mono chokes: a stacked chord in one step keeps
  only its first note, and any new note-on cuts whatever's currently
  held/tied rather than layering — see the block right after the note-scan loop in
  `Sequence:update`.
- 5th `direction` mode, "brownian" — random walk (-1/0/+1 per step) wrapped at the
  `limit` boundary (not clamped, so it doesn't pile up at the edges over time).
  Existing ping-pong/random modes were already there from before.
- Per-track `note_lo`/`note_hi` params (formatted as note names, cross-clamped like
  the existing global `vel_lo`/`vel_hi`) constraining which rows of the scale a
  track can use. Applied in three places: the live playback note-scan in
  `Sequence:update`, `evolve`'s scan+replacement range, and `randomize`'s note
  range. Note: this *replaces* `randomize`'s old hardcoded middle 1/4..3/4 slice of
  `note_max` — since `note_lo`/`note_hi` default to the full 1..note_max range,
  `randomize`'s default spread is now wider (full range) than before (was always
  centered). Narrow the range per-track if you want the old centered-ish feel back.

## Added (2026-09-19)
- **`lib/garc.lua` gained `poll()` and per-ring rendering styles**, and
  `redraw()`'s loop now calls `garc_:poll()` every frame. polyphasic is the
  script garc was written in, so this is the source copy — cascade's and
  segue's are the same file with a one-line header comment. Before this, a
  value moved from the PARAMETERS menu, a pset load, an encoder or the
  script's own evolve/randomize left the rings showing whatever they last
  drew until you touched them; generative changes are exactly the case that
  matters here. `poll()` compares four values a frame and only redraws on a
  change, so a still arc costs the comparison and nothing else.
- The new `style` options (`bipolar`, `comet`, `dot`, and a `track`
  underlay) are available but **no polyphasic ring sets one yet**, so the
  arc looks exactly as it did. Worth a pass when the arc pages get
  reorganized (see Open items): the RANGE page's signed values are the
  obvious candidates for `bipolar`, which draws outward from centre instead
  of showing "slightly negative" as a nearly-full ring.
- Untested on hardware — the change landed after the last norns session.
  cascade has 31 checks covering this module (`cascade/test/test_arc.lua`)
  and polyphasic has no suite of its own to run them from yet.

## Fixed
- Grid LED crash when manually entering notes with evolve + chained link_track
  on (2026-09-15, traceback: `ggrid.lua:178: attempt to perform arithmetic on
  a nil value`). Same root cause as the earlier musicutil crash — `scale_full`
  can be shorter than `note_max` (MusicUtil stops generating past MIDI 127) —
  but in a spot that fix didn't reach: `GGrid:get_visual()` indexes
  `scale_full[note_index]` twice (the main step grid's LED level, and the
  bottom keyboard row's LED level) with no nil-guard. Evolve pushing notes
  toward the edges of a track's range, especially compounded by link_track
  biasing several tracks toward each other, made an out-of-range note_index
  much easier to hit than in ordinary play. Both spots now skip drawing (or
  fall back to unlit) when `scale_full[note_index]` is nil instead of
  crashing, matching the guard pattern already used in sequence.lua.
- Arc ring rendering, three issues from the first hardware test (2026-09-15):
    - Fine-grained params (probability: 0-1 by 0.01) flashed/strobed while turning —
      the ring-fill smoothing used a flat `1/range` as "how much of the ring one
      detent moves," which is only correct for a step size of 1. For a 0.01-step
      param that's 100x too much per detent, so a single click swept the *entire*
      ring. Fixed by using the param's own `controlspec.quantum` (how much its raw
      0-1 phase actually moves per `params:delta` call) instead — now correct for
      any step size without needing to special-case it per param.
    - A value sitting at its minimum or maximum drew a completely dark ring
      (indistinguishable from "no arc connected"/off) — an initial fix using
      `a:segment()` with a floor/ceiling fraction snap didn't actually resolve it on
      hardware (the segment's angle handling didn't reliably render a truly full or
      truly empty ring at the extremes). Replaced with `a:led()` calls lighting each
      LED individually instead, so the lit count is exact: 1 at minimum, all 64 at
      maximum, no reliance on how `:segment()` handles the edges of its range.
    - A 2-3 option param (mute, poly, direction) rendered as a thin sliver or a
      half-lit ring depending on its value, reading like a binary on/off toggle
      rather than a selector. Added a second rendering mode: for params with a
      small number of selectable values (auto-detected from the param's own
      min/max/step, currently <=16 options), draw one dim tick per option evenly
      spaced around the *whole* ring with the selected one lit bright, instead of a
      continuous fill.
- Crash on every note played, right after Vanishing shipped (traceback:
  `polyphasic.lua:95: attempt to perform arithmetic on a nil value (field
  'rows')`). `make_on_note` still computed a pitch row via `Display.rows` for
  the display's `on_note` callback, but the new `display.lua` doesn't define
  `Display.rows` at all (Vanishing's lamps sit at fixed positions, no pitch
  row to map to) — dropped that computation entirely rather than re-adding an
  unused field just to satisfy it.
- Crash turning the arc for `note_hi` after raising `note_lo` (2026-09-15, traceback:
  `musicutil.lua:618: attempt to perform arithmetic on a nil value (local 'note_num')`,
  entered via `clock.lua:68: core/clock.resume` — i.e. inside the screen redraw
  coroutine, which is why the symptom was "arc keeps working but the screen text
  froze": that coroutine died on the error and never ran `redraw()` again, while the
  arc's own event handling and the sequencer's clock are separate coroutines and kept
  going). Root cause: `MusicUtil.generate_scale_of_length` silently stops generating
  once a note would exceed MIDI 127, so `scale_full` can end up *shorter* than
  `note_max` — raising `note_lo` pushed `note_hi` up (their cross-clamp) to a pool
  index that didn't actually exist, and `note_hi`'s formatter indexed `scale_full`
  with it, landing on `nil` and crashing `MusicUtil.note_num_to_name`. Fixed two ways:
  `note_max` dialed back to 7 octaves (see Added — safe for any root_note this script
  allows under a 7-note/octave scale) and, more importantly, defensive nil-checks
  added wherever `scale_full` is indexed by a note_lo/note_hi/note_offset-derived
  value (`Sequence:note_on` and the note_lo/note_hi formatters, via a shared
  `note_name_at` helper) — so a sparse scale outrunning the MIDI ceiling at a high
  root note now just quietly has less range, instead of crashing.
- Freeze + stuck note with evolve on (2026-09-15, confirmed via traceback:
  `sequence.lua:341: attempt to index a nil value`). `evolve` scanned and mutated
  the *entire* 64-step buffer (`sequence_max`), not just the currently active
  `1..limit` steps that are actually playing. When it picked a step beyond `limit`
  to clear, `clear_note` -> `promote_right_tie` -> `right_step` computed a
  neighboring step index assuming wraparound happens at `limit`, producing an
  index past the matrix's bounds (e.g. step 65 of a 64-row matrix) and crashing
  that clock division's coroutine. Because a crashed division stops ticking for
  every track sharing it, this also explains the original "froze + stuck note"
  report from the very first test — the division that died never ran its
  note-off logic again. Fixed by scoping evolve's scan/replacement to
  `1..limit`, matching what's actually playing.
- `randomize` cleared the sequence but then wrote its random refill into a stale
  table reference (a closure upvalue left pointing at the pre-`clear()` matrix,
  not `self.matrix`), so triggering it produced a silently empty pattern instead
  of a random one. Fixed to write through `self.matrix`. Independent bug from the
  evolve crash above, found during the same freeze investigation.
- Script failed to load entirely (`module 'cjson' not found`) — pitter-patter's pattern
  save/load used cjson, which needs an ARM-compiled `.so` that was never actually present
  on-device. Replaced with norns' built-in `tab.save`/`tab.load` (table serialization,
  no external binary dependency) in `params.action_write`/`params.action_read`. Pset
  files now save as `<name>.data` instead of `<name>.json`.
- Stuck/continuously-sounding MIDI notes: `note_off` was reading the track's midi out
  device/channel live, but `note_on` didn't capture them — so changing a track's MIDI
  out device or channel (shift+E1, or the channel param) mid-note sent the note-off to
  the *new* device/channel, stranding the note on the old one forever. Fixed by
  capturing device+channel on the note itself at note-on time and using those captured
  values at note-off. Also added `Sequence:panic()`, called from `cleanup()`, to force
  note-off on anything still held when the script quits.
- Ableton Link: play moved the transport but Link's stop didn't stop norns playback.
  No `clock.transport.start`/`clock.transport.stop` hooks were defined (norns'
  standard mechanism for reacting to Link/global transport), so Link's stop message
  never reached `main_play`. Added both hooks in polyphasic.lua — needs on-device
  confirmation with Link now that they're wired up.
