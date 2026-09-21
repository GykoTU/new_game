# Mechanics coverage

A living check of the proposed mechanics against the architecture, so that gaps
are found on paper rather than in Stage 5.

**Source:** `docs/Proposed mechanics and interactions.txt` (owned by the
designer — this file reviews it, never edits it). Re-run this review whenever
that file changes or a stage lands.

**Last reviewed:** 2026-09-21, against Stage 0 complete (clock, grids, saves, stats).

Legend: **fits** — the architecture already supports it · **needs** — requires
something not yet designed · **ask** — ambiguous, needs a design decision.

---

## Every mechanic's *numbers* are already stats

Each mechanic is parameterised by a stat in `stats/stats.gd`, so any numeric
upgrade to it — "+1 bounce", "+30% blast radius", "burns last longer" — is an
ordinary modifier with no special code. Behaviours decide *what happens*; stats
decide *how much*. This part is done and tested.

| Mechanic | Stats it reads |
|---|---|
| hook enemies | `pull_strength` |
| slow enemies | `slow_strength` (capped at 0.9), `slow_duration` |
| fling enemies | `knockback` |
| incinerate | `burn_dps`, `burn_duration` |
| split into two | `split_count` |
| bounce off walls | `bounce_count` |
| explode / explode enemies | `area_radius` |
| whirl around | `orbit_radius`, `projectile_lifetime` |
| slinging projectiles | `orbit_radius` as chain length, `pierce_count` |

---

## Weapons can

**Hook enemies — fits, with one constraint.**
`on_unit_hit` stores the target and flips the projectile to a returning state;
`on_step` pushes the enemy through the impulse channel. Constraint: impulse
movement **must respect the blocking grid**. Otherwise hooking an enemy on the
far side of a wall drags it straight through, and walls stop meaning anything.

**Slow enemies — needs per-enemy status slots (Stage 4).**
Not modifiers: a StatBlock per enemy is ruled out (D7). Slow becomes a couple of
per-enemy array slots — strength and time remaining. Proposed stacking rule:
**strongest wins, duration refreshes.** Additive stacking would let several
weak slows freeze a horde; the 0.9 clamp guards the extreme, but the rule
should make stacking a choice rather than an accident.

**Shoot slinging projectiles — fits. Decided: a chained cannonball.**
A ball on a chain that swings rather than flying straight. It is an ordinary
projectile that **walls block like everything else** — no exception to the
wall rule, and **no bounce**. It **pierces enemies** and expires after hitting
`pierce_count` of them, so "+2 pierce" is an ordinary FLAT modifier on
`pierce_count` and needs no special code. Motion is `on_step`: the ball moves
along its swing while held within chain length of the weapon.
- **The weapon belongs outside walls.** The ball sweeps the space around its
  weapon; inside a walled area it would keep hitting its own walls.
- **Hitting a wall ends the shot.** *(Assumed from "no bounce" — confirm.)*
- **Friendly fire:** the swing arc is a standing hazard. Workers routed past a
  sling weapon get hit, which makes its placement a real decision.
- It is persistent, like *whirl around*, so it holds a pool slot continuously.

**Fling enemies — needs enemy movement events.**
`knockback` through the impulse channel fits. But the interesting part is what
a flung enemy *hits*: a wall, another enemy, a worker. The D6 hooks cover the
**projectile** lifecycle only; an enemy slamming into a wall is not a projectile
event. Needs an enemy-side event (`on_wall_impact`, possibly `on_unit_impact`)
so impact damage and knock-on effects have somewhere to live.

**Incinerate — fits as damage-over-time; needs zones if fire lingers.**
Burning an enemy is a status slot, like slow. If incinerate also leaves
**burning ground**, that is a new kind of entity — a persistent area effect —
which does not exist in the design yet (see *Effects are not projectiles*).

---

## Shots can

**Split into two — fits.** `on_unit_hit` spawns children that inherit the
behaviour set with the generation counter incremented. The generation cap and
pool ceiling already stop split-of-split running away.

**Bounce off walls — fits, one detail.** `on_wall_hit` reflects the velocity
about the crossed tile edge. The supercover grid walk knows which axis it
crossed, which gives the normal. Detail: a **corner** hit crosses both axes at
once and must reflect both components, or shots slide along corners.

**Explode — fits. Decided: walls block blasts.**
The blast is a radius query on the spatial hash, followed by a line-of-sight grid
walk from the blast centre to each victim; a wall in between shields it. Friendly
fire applies, so this is what keeps walls meaningful as worker protection. Cost:
one short grid walk per victim in range, which the budget absorbs.

**Explode enemies — needs effects in the budget scheme.** This is the most
important finding in the review. An enemy killed by a blast explodes, which
kills an enemy, which explodes. The generation cap is currently specified for
**projectiles**; a chain of explosions involves no projectiles at all, so
nothing stops it. Explosions must carry a chain depth under the same
discipline, and must be able to trigger `on_kill` themselves.

**Whirl around — fits.** Orbit motion in `on_step` around the weapon's
position. Note that long-lived orbiting shots occupy pool slots for a long time,
and orbiting close to their own weapon means they will hit that weapon's
neighbouring walls.

---

## Cross-cutting findings

These are what the review is really for. Each is a design gap that would have
been expensive to discover in code.

1. **Effects are not projectiles.** Explosions, burning ground and chain
   triggers need to be first-class entities alongside projectiles, sharing the
   same generation counter, pool ceiling and `on_kill` hook. The D6 seam as
   originally written was projectile-only. *(Stage 5)*

2. **Enemies need their own movement events.** Hook and fling move enemies
   with impulses; what happens when an impulse drives an enemy into a wall or
   into another unit needs an event on the enemy side. *(Stage 4)*

3. **Impulse movement must respect the blocking grid**, or hook and fling
   become ways to teleport enemies through walls. *(Stage 4)*

4. **Status slots, strongest-wins.** Slow and burn are per-enemy array slots,
   not modifiers. *(Stage 4)*

5. **Both open questions are decided** — see the bottom of this file.

---

## Synergies worth testing once these exist

Pairs from the list that stress the design, as acceptance tests for Stage 5:

- **hook + explode enemies** — pull a crowd together, then chain-detonate it.
  The showcase combination, and the hardest test of the chain-depth cap.
- **split + explode** — every child explodes; exercises the pool ceiling.
- **bounce + explode** — detonate on each bounce: `on_wall_hit` triggering an
  effect rather than just reflecting.
- **incinerate + explode enemies** — burning deaths set off explosions; a chain
  with a damage-over-time delay in it.
- **fling + walls** — impact damage; the first user of enemy movement events.
- **slow + whirl around** — slowed enemies stay in the orbit longer; a pure
  numbers synergy that should need no code at all.

---

## Decisions

1. **Slinging projectiles** are a chained cannonball: a swinging ball on a
   chain, blocked by walls like everything else. Its weapon is meant to stand
   outside walls. *(Decided 2026-09-21.)*
2. **Walls block explosions**, checked by line of sight from the blast centre.
   *(Decided 2026-09-21.)*

3. **Chained cannonball** does not bounce; it pierces up to `pierce_count`
   enemies, and pierce is upgradable. *(Decided 2026-09-21.)*

## Open questions for the designer

- Chained cannonball hitting a wall: assumed to end the shot. Confirm.
