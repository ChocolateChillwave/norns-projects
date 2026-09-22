# segue — follow actions

**v0.8.0** · the reference for the one subsystem segue exists for.

A follow action is a pattern's answer to the question *"and then what?"* —
asked by the pattern itself, on its own clock, without you touching
anything.

This is the whole idea borrowed from Ableton's clip follow actions, with one
addition: segue also controls **how** the change happens, not just when and
where. That part is §6.

---

## 1. The four settings

A follow action is four numbers. Hold **K1 and turn E3** to reach each field
on the screen:

| field | means | values |
|---|---|---|
| **follow** | *when* the action fires, counted from the moment this pattern started playing | `off`, `1/16` … `4 bar`, `end` |
| **action A** | *where* it goes | see §3 |
| **action B** | the other place it might go | see §3 |
| **chance** | the odds of taking **A** rather than **B** | 0–100% |

`chance` at 100% means A always. At 50% it is a coin flip between A and B.
At 0% it is always B — which is a roundabout way of writing B, but it's
there so you can sweep the knob without the setting jumping.

A very common pair is **A = something, B = none**: "sometimes move, otherwise
stay." That is what the hat lanes ship with.

**These four are not stored 64 times.** They have a **global** value, and any
lane or single pattern can set its own — see §9. Out of the box one global
"at the end, stay put" covers nearly everything, and only the lanes that move
say otherwise. Which level an edit lands on is the **level** field (the last
one on the screen), and it starts on `global`.

## 2. Follow time

| value | fires after |
|---|---|
| `off` | never — the pattern plays forever |
| `1/16` `1/8` `1/8.` `1/4` `1/4.` | 1, 2, 3, 4, 6 sixteenths |
| `1/2` `1/2.` | 8, 12 sixteenths |
| `1 bar` `1.5 bar` `2 bar` `4 bar` | 16, 24, 32, 64 sixteenths |
| `end` | when the pattern loops — its own length, whatever that is |

**`end` is the Ableton-default behaviour** and the one to reach for first: a
pattern plays all the way through and then hands off. Everything shorter is
where it gets interesting, because the hand-off lands *inside* the phrase.

**Times are stored in sixteenths, not steps.** A lane running at 1/8 needs
only 8 steps to cover a bar, so `1 bar` means 8 steps there and 16 steps on
a 1/16 lane. Change a lane's division and its follow times keep the same
musical length. (`end` is the exception — it tracks the pattern's step
count, so at 1/8 a 16-step pattern takes two bars and `end` follows it out
there.)

One rounding caveat: a time that doesn't divide evenly into the lane's
division gets rounded to the nearest step, minimum 1. `1/8.` (3 sixteenths)
on a 1/8 lane is 1.5 steps and becomes 2.

## 3. The actions

Eight of them. "The bank" below means **the patterns this action is allowed
to land on** — which is not always all eight slots, see §5.

| action | goes to |
|---|---|
| `none` | nowhere. Stays put. |
| `next` | the next pattern in the bank, wrapping from the last back to the first |
| `prev` | the previous one, wrapping the other way |
| `first` | the lowest-numbered usable pattern |
| `last` | the highest |
| `any` | a random one — **including the one already playing** |
| `other` | a random one, never the one already playing |
| `rand2` | a coin flip between `prev` and `next` |

The difference between `any` and `other` matters more than it looks. `any`
re-picking the current pattern is not a no-op: under a `cut` transition it
restarts the loop from step 1, which is a real musical event. Under
`legato` it genuinely does nothing. Use `other` when you want guaranteed
movement, `any` when you want the pattern to sometimes hold.

`rand2` is the gentle one. It wanders up and down the bank a slot at a time
rather than jumping across it, so if you order a bank from sparse to busy it
behaves like a density random-walk.

## 4. Exactly when it fires

This is worth being precise about, because being one step out is the
difference between a switch that lands and one that stumbles.

The follow check runs **at the top of a step, after the playhead has moved
off the step it just played**. So:

> *follow at 1/4* means: play four steps, advance to step 5, change pattern,
> then play **step 5 of the new pattern**.

Traced, with `follow = 1/4` and `legato`, on a 16-step pattern:

```
step    1    2    3    4    5    6    7    8 ...
        ────────────────────┤
        pattern A           │  pattern B from step 5 onward
                            │
                     follow fires here, between step 4 and step 5.
                     the playhead does not reset — B picks up at 5.
```

And with `follow = end` on the same pattern, the hand-off lands exactly on
the loop point, which is what makes it feel like an ordinary clip change:

```
step  ... 14   15   16  │  1    2    3 ...
          pattern A     │  pattern B
                        └─ follow fires as the loop wraps
```

**The timer restarts on every change**, however the change happened — a
follow action, a button press, a kit launch, a bank change. And the timer that matters is
always the **newly arrived** pattern's own `follow` setting. Each pattern
decides how long it gets.

Because the timer is read fresh every step, editing a pattern's follow
settings while it is playing takes effect immediately. You do not have to
relaunch it.

## 5. What it is allowed to land on

Each lane has a **skip empty** setting, on by default. With it on, the bank
an action navigates is only the patterns that would actually make a sound.

This matters because segue's library is organised as **kits** — a row is one
beat across all eight lanes — and most kits leave some lanes out. The amen
has no cowbell. How many kits a lane can actually move between depends on
the bank: COW has a part in several electro kits, and in none of the
breakbeat ones. Its `next` steps between whichever kits it has a part in and
skips the rest.

An empty pattern is not a destination, and it is also not a trap:

> **A lane sitting on an empty slot stays there.** Empty slots ship with
> their follow forced to `none`, because "this voice sits this kit out" has
> to survive longer than one bar. Without that, a relative action like
> `next` would resolve to the first non-empty kit and drag the lane back in.

If an action resolves to nowhere — `none`, or `other` on a bank with only
one usable pattern — nothing happens and the timer simply re-arms. It will
ask again next time round, which is why changing the action later works
without a relaunch.

## 6. What the switch sounds like

Where the pattern goes is only half of it. The lane's **transition** decides
what the change sounds like, and it applies to follow actions and button
presses alike:

| transition | at the moment of the change |
|---|---|
| `cut` | playhead snaps to step 1. An ordinary clip launch. |
| `legato` | playhead carries straight over. **This is the one the whole script is for.** |
| `xfade` | over the next *morph* steps, each voice independently plays from the old or new pattern, the odds sliding from one to the other |
| `handover` | the voices change one at a time across the morph window, highest voice first, so the lane's anchor moves last |

`legato` is why a mid-phrase follow action can sound intentional rather than
like a mistake. Switching on the "and of 3" means the new pattern is heard
from *its* "and of 3" — the phrase continues, the material underneath it
changed.

The two morph transitions go further than Ableton does and blend the
patterns rather than swapping them. On a one-voice lane `handover` has
nothing to stagger and behaves as `xfade`.

Transition inherits like the follow settings (§9): **FX row 7 cols 1–4** set
the global one, and any lane, kit or pattern can have its own. The one used
is the **arriving** pattern's — give a fill its own `cut` and it always cuts
in, while the rest of the lane stays legato. The morph window length is a
screen field and an arc ring.

## 7. Follow actions ignore launch quantize

Deliberately, and it is the most important asymmetry in the script:

- **You press a pattern** → it waits for the next launch-quantize boundary
  (1 bar by default). A button press wants to land on the grid.
- **A follow action fires** → immediately, at its own time. That is the
  entire point. A follow action quantized to the bar could never land
  mid-phrase, and mid-phrase is the effect being chased.

So `launch quant` never delays a follow action, and shortening a follow
time is the only way to get a change to land off the bar line.

## 8. Turning it off

Three levels, coarsest first:

- **FX row 7 col 8** — flips follow on/off for all eight lanes at once.
- **FX row 5** — one button per lane. Lit means that lane's follow is live.
  This is how you freeze a wandering lane without editing its patterns.
  *All eight lanes ship with follow on* — the quiet lanes are quiet because
  they inherit a global `none`, not because the lane is disabled.
- **`follow = off`** at any level — globally, for a lane, or for one pattern.

There is also **PARAMETERS > patterns > reseed**: every follow-enabled lane re-rolls
where it is, as if all of them had hit an `any` at once. A manual shove when
the drift has settled. Two things it is not: it goes through the normal
launch path, so it **waits for the launch-quantize boundary** rather than
landing instantly, and because it rolls `any` rather than `other`, a lane
can perfectly well re-pick the pattern it is already on.

## 9. Global, lane, pattern

The four follow settings — and transition — are not stored per pattern. They
**inherit**: every one has a global value, and a lane or a single pattern can
set its own.

```
GLOBAL      follow end · none · none · 100%
  |
  +- KICK   (inherits)                -> end · none
  +- CHH    follow 1 bar · other · 40%   <- its own
  |           +- kit 7  follow 1/2       <- its own
  +- SNARE  (inherits)                -> end · none
```

Change the global and everything that hasn't been given its own value moves;
anything that has keeps it. That is the Ableton idiom — a clip's launch
quantize reads *Global* until you change it.

The **level** field (the last one; hold **K1**, turn **E3** to reach it)
chooses where an edit lands:

| level | an edit changes |
|---|---|
| `global` *(default)* | the value everything falls back to |
| `lane` | the selected lane — *"make the hats drift, whatever kit they're on"* |
| `kit` | the selected kit slot on every lane — so a kit carries its own behaviour as well as its notes |
| `pattern` | just the one pattern on screen |

The field line shows the level: `[lane] chance 40%`. A value drawn **dim** is
inherited; **bright** means it is set at this level.

- From an inherited value, the first click up **adopts the value you're
  already hearing** — the marker changes, the sound doesn't. The next click
  changes it.
- Turn a value **down past its lowest setting** to clear it back to inheriting.
- At the `kit` level an **empty slot is skipped**, so its `none` — the thing
  that keeps a sat-out voice silent — is never overwritten.

This replaced a v0.4 **scope** field that *copied* a value into many patterns
at once. Copying was the problem: once written everywhere, a deliberate
setting and a copy looked identical, and the next wide edit flattened both.

### On the arc

Holding **K1** while turning an arc ring applies it to every lane, nudging
each from where it is — lanes set differently stay different. The arc reaches
params only, so it can turn the global and lane follow values but not a single
pattern's. See MANUAL §11.

## 10. What ships, and why

| where | follow | action | chance | what it does |
|---|---|---|---|---|
| **global** | `end` | `none` / `none` | 100% | the default everything inherits: stay put |
| KICK, SNARE, CLAP, CYM, COW | — | — | — | inherit it, so they hold |
| TOMS (lane) | — | `next` | — | steps to the next fill every time round |
| CHH (lane) | `1 bar` | `other` | 40% | every bar, a 40% chance of grabbing another kit's hat |
| OHH (lane) | `2 bar` | `other` | 50% | same, slower and less often |

So the shipped behaviour is one global value and three lane overrides, not
64 copies of a setting. Change the global and the five quiet lanes follow;
the hats and toms keep their own.

The reasoning: the rhythm section is the floor and a kick that wanders on
its own is just noise. The movement goes to the parts where it is musical —
fills, and the top end. So it does something generative from the moment it
starts without the ground shifting under you, and nothing about it is fixed.

## 11. Things to try

**Let a single lane wander.** At the `lane` level, set CHH's follow to `1/2`
and `other` at 100%.
The hat changes kit twice a bar while everything else holds. This is the
quickest way to hear what legato is doing, because the hat is busy enough
that a switch is obvious and harmless enough that a bad one doesn't matter.

**A two-pattern flip-flop.** Two patterns, both `follow = end`, both
`next`. They alternate forever. Make one of them a variation of the other
and you have a 2-bar phrase out of two 1-bar patterns.

**A cycle with an escape hatch.** `A = next` at 85%, `B = first`. It walks
the bank and occasionally snaps home. Order the bank sparse-to-busy and it
reads as a build that resets.

**Guaranteed movement, gentle.** `A = rand2` at 100%. A random walk one slot
at a time — drifts without ever leaping.

**Fills that arrive on their own.** Put a fill in the last slot of the TOMS
lane and, at the `pattern` level, set the slot before it to `A = next` at
20%, `B = none`. The fill turns up roughly every five times round,
unpredictably. Give the fill its own `cut` transition and it always lands
hard, whatever the rest of the lane is doing.

**Everything at once.** At the `global` level set `other` on `1 bar`, and
make sure no lane overrides it. Chaos, but instructive — it tells you fast
whether a bank's kits are coherent enough that any mix of their parts works.
Try it on house, then on variety 2.

## 12. Gotchas

- **A change resets the timer.** Launching a pattern by hand restarts its
  follow countdown from zero, so a manual launch can delay the next
  automatic change.
- **`end` on a 32-step pattern takes twice as long.** The amen and halftime
  kits are two bars. A lane on either of them hands off half as often as a
  lane on a 16-step kit, even with identical settings.
- **Holding *roll* speeds `end` up** (FX row 6, and so *full* mode only —
  focus hides that row). Roll halves the lane's step length, so a pattern
  with `follow = end` loops — and hands off — twice as fast while held.
  Absolute times like `1 bar` come out unchanged, because they are measured
  in sixteenths: the step count doubles and the steps arrive twice as fast,
  which cancels.
- **`other` needs two usable patterns.** On a lane with only one non-empty
  slot it resolves to nothing and the lane sits still. That is not a bug,
  but it can look like one if you have not noticed how few kits that lane
  has a part in.
- **`any` can pick what is already playing.** Under `cut` that restarts the
  loop; under `legato` nothing audible happens at all. If you wanted
  guaranteed change, use `other`.
- **A global edit doesn't reach a lane with its own value.** That's the
  point of inheritance, but it can look like a setting is being ignored.
  Check the level, and look for a bright (set-here) value further down.
- **Beat repeat hides follow actions, it does not stop them.** The lanes
  keep running and keep handing off underneath a held repeat — you just
  aren't hearing them. Let go and you may be somewhere new.

---

Timing details, the tick order and the reasoning behind these choices are in
[NOTES.md](NOTES.md); the rest of the interface is in [MANUAL.md](MANUAL.md).
