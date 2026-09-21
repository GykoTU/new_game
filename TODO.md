# Roadmap

Staged so that each stage is playable or at least observable on its own, and so
that the expensive-to-retrofit decisions land early. See ARCHITECTURE.md for the
reasoning behind the structure.

Status: `[ ]` open · `[~]` in progress · `[x]` done

---

## Stage 0 — Foundations (no visible gameplay)

The load-bearing work. Nothing here is fun, and everything after it is cheaper
because of it.

- [x] Move `main.gd`'s procedural tree into `main.tscn`
- [x] `GameClock`: fixed-tick sub-stepping, pause reasons, ordered update loop
- [x] Convert `_occupied` / `buildings` to `WorldGrid` + `BuildingStore`
- [x] Add `blocking` and `cost` grids alongside `ground`
- [x] Fix `remove_building` iteration bug
- [ ] Spatial hash for unit broadphase *(moved: lands with its first user, Stage 4)*
- [x] Stat/modifier system: registry, tag targeting, per-stat caching,
      source-based saving
- [x] Rewrite `SaveManager`: run + profile saves, atomic writes, checksums,
      backup recovery, versioned with migrations
- [~] Expand `EventBus` to the contract in ARCHITECTURE.md section 8
      (`game_speed_changed` added; the rest lands with its system)
- [x] Remove the dead `jump` / `left` / `right` input actions

## Stage 1 — Economy skeleton

First loop the player can actually watch happen.

- [x] Resource registry, `Economy` with all-or-nothing spending, starting
      resources, `resource_changed` events, saved with the run
- [x] Resource bar
- [x] Shop: data-driven items (`data/shop/`), workers and levelled upgrades,
      prices through `SHOP_PRICE` so sales are a modifier source
- [x] Worker roster (miners, builders) shown in the worker bar
- [x] Key bindings: every shortcut an action, Controls list in the options
      menu, rebinding with conflict handling, dev actions hidden and disabled
      in release builds
- [x] Debug tools: Ctrl+N new run, Ctrl+G grant resources, F3 stat overlay
- [x] Missing-art fallback and startup report
- [~] Extend `BuildingData`: health and grid flags done; threat_priority,
      build_cost and build_work still to come
- [ ] When sales happen (schedule, events, random) — undesigned

## Stage 2a — Units, housing, mining

- [x] Unit store: arrays, pooled, one batch per unit kind, animation shader
      picking each unit's frame and mirroring left/right
- [x] Pathfinding: `AStarGrid2D` weighted by the cost grid, kept in step
      through `WorldGrid.tiles_changed`. One path per trip; route caching was
      not needed (200 walking units: 0.75 ms per tick)
- [x] Run start: a builder house, carrier house and miner home next to the
      base, one worker in each
- [x] Housing: builder and carrier houses hold 3 each (`HOUSE_CAPACITY` stat);
      a builder or carrier can only be bought while a bed is free, and the
      shop shows why not
- [x] Builder job board: build > repair > cobble > chop, idle builders take
      the highest-priority reachable job (cobble and chop have no providers
      until 2b/2c)
- [x] Construction sites: placed buildings are built by builders over time;
      more builders build faster; sites drawn faded until `construction.png`
- [x] Sending miners: select the miner slot, click a mine; one idle miner per
      click, Shift to send several; refusals shown in a toast
- [x] Worker house: one per mine, 3 miners, built by a builder on a free tile
      next to the mine; miners wait until it stands, then move in
- [x] Gathering while stationed; flee to the base if the house is destroyed
- [x] Fixes after first play:
  - [x] Units are drawn only while busy; idle ones wait inside their building
  - [x] Clicking the miner slot with no miners says so at once
  - [x] Mined resources bounce out of the mine as drops; carriers (only
        they carry) fetch them to the base; a mine pauses at 20 drops
  - [x] The starting miner commutes: mines outside for free, moves into a
        mine's home when a bed is free, returns home if that home falls
  - [x] A bought miner sent to a mine without a home pays for the home then
        (placeholder: 5 diamonds, `BuildingData.cost`)
- [ ] Player-set builder priorities (build / repair / cobble / chop / fetch)
- [x] Reachable in 2a: diamond mines (ice). Gold arrives with cobble (2c).
- [x] Run saves hold units; `RUN_VERSION` 2 (older run saves are refused)

## Stage 2b — Wood, crafting, buildings

- [ ] Plain trees (`tree`) generate on regular grass
- [ ] Idle builders chop trees for wood (new resource, appended)
- [ ] Chopped tree leaves a stump; the stump disappears after a while; a new
      tree grows later on a random grass tile
- [ ] Shop split into Buy (gold: NPCs, upgrades) and Craft (resources:
      buildings, items); Better Pickaxes loses its copper cost
- [ ] Blueprints: crafting needs one; the run starts knowing bucket, depot,
      builder house and carrier house
- [ ] Craftable houses: builder house, carrier house (3 each), paid in
      resources; miner home cost moves to wood (it is paid on assignment,
      never placed from the bar)
- [ ] Owned-buildings inventory and the building bar: crafted buildings in
      the order they were crafted; hover extends it, partially transparent,
      to show the rest; click to place. Slot frame
      `assets/ui/building_slot.png` as a 9-slice.
- [ ] Depot: carriers deliver to the nearest depot instead of the base

## Stage 2c — Cobble

- [ ] Bucket: crafted from wood, one-off (`bucket_empty.png`)
- [ ] A builder fills it once at water; it becomes the permanent water bucket
      (`bucket_full.png`), usable by every builder
- [ ] Builders turn marked lava tiles into cobble for builder time only
      (new walkable ground type, appended to `Ground` per D8)
- [ ] Gold mines become reachable

## Stage 3 — Day/night and the run

- [ ] `RunDirector`: day counter, day/night phases, phase events
- [ ] Autosave at day boundaries (calls `main.gd.save_run()`)
- [ ] Day/night visual treatment
- [ ] The commuting first miner walks home at night
- [~] Run save/continue works; destroying it on base death waits for
      `RunDirector` (`SaveManager.delete_run()` is ready)
- [ ] Death, run summary, return to title

## Stage 3b — Exploration

- [ ] Fog of war: the map is hidden until explored; explored tiles saved
- [ ] Explorer NPC (bought with gold), sent out to reveal the map
- [ ] Points of interest, hidden under fog, holding: blueprints, meta
      currency, an interactable NPC living in a house, a tree with special
      fruit

## Stage 4 — Enemies

- [ ] Enemy SoA store + `MultiMeshInstance2D` rendering
- [ ] Spatial hash for unit/enemy broadphase (moved from 2a: its first real
      user is projectile and enemy hit tests)
- [ ] Edge spawning, wave composition per day
- [ ] Flow field cache and shared-target movement
- [ ] Target scoring by `threat_priority` and distance
- [ ] Enemies break walls when walls block their path
- [ ] Building damage and destruction
- [ ] Enemies drop blueprints
- [ ] Impulse channel on enemy movement (knockback, pulls, hooks),
      respecting the blocking grid so nothing is pushed through a wall
- [ ] Enemy movement events: `on_wall_impact`, `on_unit_impact`
- [ ] Status slots per enemy (slow, burn): strongest wins, duration refreshes

## Stage 5 — Weapons

- [ ] Weapon buildings with `WeaponData`
- [ ] Projectile SoA store, supercover grid traversal, wall blocking
- [ ] Friendly fire on units, as a per-projectile flag
- [ ] Targeting rules (nearest, strongest, first in range)
- [ ] Behaviour hook system: shared behaviour sets, per-shot scratch slots
- [ ] Behaviours: bounce, split, pierce, chain, homing, hook
- [ ] Generation counters and pool ceilings so split/chain cannot run away
- [ ] Effects as first-class entities (explosions, burning ground) sharing the
      projectiles' generation counter, pool ceiling and `on_kill`
- [ ] Bounce: corner hits reflect both velocity components
- [ ] Explosions: line-of-sight against walls (decided: walls block blasts)
- [ ] Chained cannonball: swinging tethered motion, blocked by walls,
      pierces up to `pierce_count` enemies, no bounce
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

## Later — noted so they are not lost

- [ ] Assignable builder tasks (idle builders choose on their own until then)
- [ ] House occupancy upgrades: houses hold more units, and the building
      visibly expands
- [ ] Fruit: gatherable again, possibly as a special-fruit point of interest
- [ ] Meta currencies found at points of interest feed Stage 8

## Continuous

- [ ] Keep ARCHITECTURE.md and the docs/*.svg diagrams current as systems land
- [ ] Re-run docs/mechanics-coverage.md whenever the proposed-mechanics file
      changes or a stage lands
- [ ] Headless parse check before handing over any change
- [ ] Profile against the Stage-4/5 entity budget on the low-spec target

## Art needed

Full paths, 32x32 unless stated. Ticked = the file exists.

**2a**
- [x] `assets/ui/carrier_icon.png`
- [x] `assets/buildings/builder_house.png`
- Drops on the ground reuse the resource's UI icon (`assets/ui/…`). Separate
  ground sprites are optional; say if you want them and I'll list the paths.
- [x] `assets/buildings/carrier_house.png`
- [ ] `assets/buildings/construction.png` — optional; without it the target
      building is drawn faded

**2b**
- [x] `assets/ui/wood.png`
- [x] `assets/buildings/plants/tree_stump.png`

**2c**
- [x] `assets/ground/ground_cobble.png`
- [x] `assets/ui/bucket_empty.png` — before the one-time fill
- [x] `assets/ui/bucket_full.png` — the permanent water bucket

## Open questions

- Chained cannonball hitting a wall: assumed to end the shot (no bounce).
- Worker price growth counts purchases, not workers alive. Revisit once
  workers can die.

- `environment_count` is a flat count, so bigger maps are emptier, not bigger.
  Scale it with map area before tuning map size.

- Day and night length
- Whether enemies may use roads (flag exists, default off)
- Per-building and per-worker XP — deferred, noted as a future direction
- Exact resource set beyond gold, quartz, copper, diamond, fruit
