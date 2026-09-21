# segue — follow actions

**v0.7.0** · the reference for the one subsystem segue exists for.

A follow action is a pattern's answer to the question *"and then what?"* —
asked by the pattern itself, on its own clock, without you touching
anything. Every one of the 64 patterns carries its own answer.

This is the whole idea borrowed from Ableton's clip follow actions, with one
addition: segue also controls **how** the change happens, not just when and
where. That part is §6.

---

## 1. The four settings

Every pattern carries exactly four numbers. Select a lane with **E1** and a
pattern with **E2**, then hold **K1 and turn E3** to reach each field:

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
follow action, a button press, a scene launch. And the timer that matters is
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
has no cowbell. So the COW lane's bank is effectively two patterns long, and
its `next` steps between those two, skipping the six kits it has no part in.

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

Set the transition per lane (FX row 7 cols 1–4 sets all eight at once), and
the morph window length with FX row 7 cols 7–8.

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

- **FX row 8 col 3** — flips follow on/off for all eight lanes at once.
- **FX row 5** — one button per lane. Lit means that lane's follow is live.
  This is how you freeze a wandering lane without editing its patterns.
  *All eight lanes ship with follow on* — the quiet lanes are quiet because
  their patterns say `none`, not because the lane is disabled.
- **`follow = off`** on a single pattern — that one pattern never hands off,
  while the rest of the lane still does.

There is also **FX row 8 col 2, reseed**: every follow-enabled lane re-rolls
where it is, as if all of them had hit an `any` at once. A manual shove when
the drift has settled. Two things it is not: it goes through the normal
launch path, so it **waits for the launch-quantize boundary** rather than
landing instantly, and because it rolls `any` rather than `other`, a lane
can perfectly well re-pick the pattern it is already on.

## 9. Editing many at once

64 patterns × 4 settings is a lot of encoder trips, so the four follow
fields obey an **edit scope**. It is the last field in the list — hold
**K1 and turn E3** round to `scope`, then **E3** picks one of:

| scope | a follow edit writes to |
|---|---|
| `pattern` | just the one on screen. The default. |
| `lane` | all 8 patterns of the selected lane — *"make the hats drift, whatever kit they're on"* |
| `kit` | the selected slot on all 8 lanes — the whole row, so a kit carries its own behaviour as well as its notes |
| `all` | every pattern in the script |

While scope is anything but `pattern`, the field line shows it in brackets:

```
[LANE] chance 40%
```

That badge is the only warning you get, so it is deliberately in front of
the field name rather than tucked in a corner.

**A bulk edit assigns, it does not nudge.** The new value is worked out from
the pattern on screen and then written to everything in scope, so they all
end up identical and the number you can see is the truth. Turning `chance`
up one click at `all` scope does not add 5% to 64 different values — it sets
all 64 to whatever the selected one became.

Two limits worth knowing:

- **Only the four follow fields scope this way.** `length` deliberately does
  not: it changes what a pattern *is* rather than how it behaves, and the
  kits are not all the same length on purpose.
- **Lane settings ignore `lane` and `kit`.** Division, swing, transition and
  the rest are already one-per-lane, so those two scopes mean nothing to
  them; only `all` widens them, to every lane. The badge tells you which
  you are getting — it reads `[ALL LANES]` for those.

### On the arc

Holding **K1** while turning an arc ring applies it to every lane instead of
the selected one. This works differently on purpose: the arc **deltas each
lane independently**, so lanes that were set differently stay different —
the right feel for nudging everything mid-performance. The screen's `scope`
is the flatten-them-all kind, for settings work.

The arc cannot reach follow settings at all, only lane settings (division,
swing, chance/trig, level, transition, morph). Follow settings live in the
pattern data rather than in params, and the arc binds to params.

## 10. What ships, and why

| lane | follow | action | chance | what it does |
|---|---|---|---|---|
| KICK, SNARE, CLAP, CYM, COW | `end` | `none` | — | stays put |
| TOMS | `end` | `next` | 100% | steps to the next fill every time round |
| CHH | `1 bar` | `other` / `none` | 40% | every bar, a 40% chance of grabbing another kit's hat |
| OHH | `2 bar` | `other` / `none` | 50% | same, slower and less often |

The reasoning: the rhythm section is the floor and a kick that wanders on
its own is just noise. The movement goes to the parts where it is musical —
fills, and the top end. So it does something generative from the moment it
starts without the ground shifting under you, and nothing about it is fixed.

## 11. Things to try

**Let a single lane wander.** Set CHH's follow to `1/2` and `other` at 100%.
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
lane and set the slot before it to `A = next` at 20%, `B = none`. The fill
turns up roughly every five times round, unpredictably.

**Everything at once.** Set all eight lanes to `other` on `1 bar`. Chaos,
but instructive chaos — it tells you fast whether the kits are coherent
enough that any combination of their parts works.

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
- **Beat repeat hides follow actions, it does not stop them.** The lanes
  keep running and keep handing off underneath a held repeat — you just
  aren't hearing them. Let go and you may be somewhere new.

---

Timing details, the tick order and the reasoning behind these choices are in
[NOTES.md](NOTES.md); the rest of the interface is in [MANUAL.md](MANUAL.md).
