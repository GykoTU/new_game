# Roadmap

Staged so that each stage is playable or at least observable on its own, and so
that the expensive-to-retrofit decisions land early. See ARCHITECTURE.md for the
reasoning behind the structure.

Status: `[ ]` open · `[~]` in progress · `[x]` done

---

## Stage 0 — Foundations (no visible gameplay)

The load-bearing work. Nothing here is fun, and everything after it is cheaper
because of it.

- [ ] Move `main.gd`'s procedural tree into `main.tscn`
- [ ] `GameClock`: speed control, pause, `sim_delta` fan-out
- [ ] Convert `_occupied` / `buildings` from Dictionary to flat packed arrays
- [ ] Add `blocking` and `cost` grids alongside `ground`
- [ ] Fix `remove_building` iteration bug
- [ ] Spatial hash for unit broadphase
- [ ] Stat/modifier system (base, flat, increase, multiplier layers)
- [ ] Rewrite `SaveManager`: run save + profile save, versioned, migrations
- [ ] Expand `EventBus` to the contract in ARCHITECTURE.md section 7
- [ ] Remove the dead `jump` / `left` / `right` input actions

## Stage 1 — Economy skeleton

First loop the player can actually watch happen.

- [ ] Resource store + `resource_changed` events
- [ ] Resource counter UI (replaces the empty panel grids)
- [ ] Mines produce at a rate into a local stockpile
- [ ] Shop: buy workers, spend resources, real item data
- [ ] Extend `BuildingData` with health, priority, cost, build work

## Stage 2 — Workers and carriers

- [ ] Unit SoA store with pooling
- [ ] Click-a-worker-then-click-a-mine assignment
- [ ] Worker house: built on arrival, houses N workers, has health
- [ ] Gathering while stationed; flee home when the house dies
- [ ] Carriers: stockpile to base, vulnerable in transit
- [ ] Building workers: idle auto-build and auto-repair, with a build/repair
      priority toggle in the worker UI

## Stage 3 — Day/night and the run

- [ ] `RunDirector`: day counter, day/night phases, phase events
- [ ] Day/night visual treatment
- [ ] Run save/continue; run save destroyed on base death
- [ ] Death, run summary, return to title

## Stage 4 — Enemies

- [ ] Enemy SoA store + `MultiMeshInstance2D` rendering
- [ ] Edge spawning, wave composition per day
- [ ] Flow field cache and shared-target movement
- [ ] Target scoring by `threat_priority` and distance
- [ ] Enemies break walls when walls block their path
- [ ] Building damage and destruction

## Stage 5 — Weapons

- [ ] Weapon buildings with `WeaponData`
- [ ] Projectile SoA store, supercover grid traversal, wall blocking
- [ ] Friendly fire on units, as a per-projectile flag
- [ ] Targeting rules (nearest, strongest, first in range)
- [ ] Particles within the entity budget

## Stage 6 — Walls, roads, expansion

- [ ] Wall building: blocks units and projectiles, has health
- [ ] Placement rule preventing a fully sealed base
- [ ] Roads: cheaper movement cost for friendly units
- [ ] Bridges over water, crossings over void

## Stage 7 — Progression

- [ ] XP from kills, exploration, and the survival drip
- [ ] Level-up pauses the clock; choose one of three
- [ ] `AugmentData` with synergy tags
- [ ] Augment pool, weighting, and offer generation
- [ ] Shop upgrades routed through the modifier system

## Stage 8 — Meta progression

- [ ] Permanent currency earned per run
- [ ] Profile save, meta-upgrade screen on the title screen

---

## Continuous

- [ ] Keep ARCHITECTURE.md current as systems land
- [ ] Headless parse check before handing over any change
- [ ] Profile against the Stage-4/5 entity budget on the low-spec target

## Open questions

- Worker house capacity
- Day and night length
- Whether enemies may use roads (flag exists, default off)
- Per-building and per-worker XP — deferred, noted as a future direction
- Exact resource set beyond gold, quartz, copper, diamond, fruit
