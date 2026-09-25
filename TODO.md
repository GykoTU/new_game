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
- [x] Run start: a builder house and a carrier house next to the base, one
      worker in each, plus one miner with no house (the commuter)
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
- [x] Miner house: crafted (5 wood), placed touching a mine that has none,
      3 miners, built by a builder; miners wait until it stands, then move in
- [x] Gathering while stationed; flee to the base if the house is destroyed
- [x] Fixes after first play:
  - [x] Units are drawn only while busy; idle ones wait inside their building
  - [x] Clicking the miner slot with no miners says so at once
  - [x] Mined resources bounce out of the mine as drops; carriers (only
        they carry) fetch them to the base; a mine pauses at 20 drops
  - [x] The starting miner commutes from the base: mines outside, moves into
        the first miner house built (or one it is sent to with a free bed)
  - [x] Miner houses are bought per mine in the Craft tab and placed next to
        a mine; bought miners need one to be sent
- [ ] Player-set builder priorities (build / repair / cobble / chop / fetch)
- [x] Reachable in 2a: diamond mines (ice). Gold arrives with cobble (2c).
- [x] Run saves hold units; `RUN_VERSION` 2 (older run saves are refused)

## Stage 2b — Wood, crafting, buildings

- [x] Plain trees (`tree`) generate on regular grass (`tree_chance_grass`
      0.02); fruit trees stay on flowers
- [x] Wood (new resource, appended). The player marks trees by clicking;
      builders chop marked trees only (priority below build and repair)
- [x] Chopped tree leaves a stump and 3 wood drops (carriers fetch them); the
      stump disappears after 60 s; trees regrow every 45 s up to the start count
- [x] Shop split into Buy (gold) and Craft (resources) tabs; Better Pickaxes
      lost its copper cost
- [x] Blueprints: crafting needs one; unknown items are hidden; the run starts
      knowing bucket, depot, builder house and carrier house
- [x] Craftable houses: builder house, carrier house (10 wood each); miner
      home paid on assignment, 5 wood
- [x] Building inventory and bar: one slot per type with a count, first-crafted
      order; always 5 slots on the left; hover + Shift opens more columns to
      the right (partly transparent); click to place as a construction site;
      cancel keeps it
- [x] Miners can only be bought while a finished miner house has a free bed
- [x] Depot (15 wood): carriers deliver to the nearest of base and depots

## Stage 2c — Cobble

- [x] Bucket: crafted from wood (5), one-off, leaves the shop once owned;
      shown in the item bar (top left)
- [x] Click the bucket in the item bar, then a water tile (placement-style
      ghost); a builder goes there and fills it once, and it becomes the
      permanent water bucket, usable by every builder
- [x] Click and drag to mark lava; builders cobble marked tiles for builder
      time only (3 builder-seconds each, faster with more builders and
      BUILD_SPEED); `Ground.COBBLE` appended per D8
- [x] Gold mines become reachable; miner houses, depots and houses can stand
      on cobble

## Stage 3 — Day/night and the run

- [x] `RunDirector`: day counter, 120 s day / 60 s night in ticks, phase
      signals (`day_started`, `phase_changed`), saved with the run
- [x] Autosave at dawn (calls `main.gd.save_run()`)
- [x] Day/night visual treatment: a `CanvasModulate` in the world (not over
      the UI), easing through dusk and dawn; both twilights belong to the
      night, so days are always fully lit
- [x] Day bar under the resource bar: day number, sun/moon, a bar that drains
      as the phase runs out
- [x] Night: everyone goes home; builders still take repair jobs, which means
      standing in the open; carriers leave drops until dawn
- [x] Mines stand idle at night, including a miner who moves into a house
      after dusk
- [x] A faint warm halo over finished player buildings at night (one MultiMesh,
      generated falloff texture, no art needed)
- [x] The commuting first miner walks home at night and returns to the same
      mine at dawn
- [x] Death: the base falling pauses the clock, deletes the run save, updates
      the profile (`runs_ended`, `best_day`, `total_ticks`)
- [x] Run summary over the frozen world, one "Return to title" button
- [x] Dev shortcuts: Ctrl+T skip to dusk/dawn, Ctrl+K destroy the base
- [ ] Art: `assets/ui/sun.png`, `assets/ui/moon.png` (32x32) — placeholder
      checker until they exist
- [ ] Balancing pass on day and night length once enemies exist (Stage 4)

## Stage 3b — Exploration

- [x] Fog of war: a grid layer, saved compressed with the level; one texture
      with a soft edge; nothing under it can be placed on, marked or clicked
- [x] Start clearing around the map centre, always with trees and an ice
      diamond mine; the base must go inside; the camera opens on it
- [x] Workers reveal 2 tiles as they walk, the explorer 6 (only on entering
      a new tile)
- [x] Explorer (gold) + explorer house (wood, 1 bed); click its slot, then
      anywhere, fog included; partial paths end as close as it gets; turns
      back at dusk and resumes at dawn
- [x] Points of interest, hidden under fog, spotted when explored, opened by
      the explorer on a detour (3 s): blueprint caches, relic caches, an NPC
      house and a special fruit tree (both placeholders)
- [x] Findable blueprints: watchtower (reveals 12 tiles), city hall (no
      function yet)
- [x] Relics: the meta currency, banked into the profile when the run is
      saved; shown in the run summary and on the title screen
- [x] Dev shortcut: Ctrl+F reveals the whole map
- [ ] Design: what the NPC in the house does
- [ ] Design: what the special fruit does
- [ ] City hall: the priorities UI (see Later)

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

- [ ] City hall (found as a blueprint): player-set task priorities for a
      number of builders, miners and carriers, unlocking more control over a
      run (like Palworld's monitoring stand). Replaces "assignable builder
      tasks" and the hard-coded build > repair > cobble > chop order
- [ ] Optional art: a mark sprite for trees marked for chopping (tint for now)
- [ ] House occupancy upgrades: houses hold more units, and the building
      visibly expands
- [ ] Fruit: gatherable again, possibly as a special-fruit point of interest
- [ ] Relics (found at points of interest since 3b) feed Stage 8

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

**3**
- [x] `assets/ui/sun.png`
- [x] `assets/ui/moon.png`

**3b**
- [ ] `assets/npcs/explorer.png` — or a horizontal strip of 32x32 frames
- [ ] `assets/npcs/explorer_walk.png` — optional walk strip, like `carrier_walk.png`
- [ ] `assets/ui/explorer_icon.png`
- [ ] `assets/buildings/explorer_house.png`
- [ ] `assets/buildings/watchtower.png`
- [ ] `assets/buildings/city_hall.png` — one tile; say if it should be 2x2 (64x64)
- [ ] `assets/buildings/poi/blueprint_cache.png`
- [ ] `assets/buildings/poi/relic_cache.png`
- [ ] `assets/buildings/poi/npc_house.png`
- [ ] `assets/buildings/poi/tree_fruit_special.png` — the special fruit tree
- [ ] `assets/ui/relic.png`
- [ ] `assets/ui/explore_flag.png` — optional; without it no marker is drawn

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
