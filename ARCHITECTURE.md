# Architecture

Living design document for **Neues Spiel**. Updated as systems land.
Godot 4.6.stable. Status: pre-gameplay — only the level generator, build placer
and UI scaffolding exist.

---

## 1. What the game is

A top-down, tile-based, base-defence roguelike. There is no player avatar: the
player is the base. You place buildings on a generated map, send workers to
mines, and survive a day/night cycle in which waves grow stronger each day.

Three pillars, and the tension between them is the game:

- **Farming** — workers gather from mines and plants; carriers haul the goods home.
- **Base building** — walls, roads, houses and infrastructure expand outward
  across water and void toward richer resources.
- **Survivors-style combat** — auto-firing weapon *buildings* whose synergies
  carry the run. Weapons deal friendly fire, so your own defences threaten your
  own workers. Routing workers safely is a core design problem for the player.

A run ends on base death. The run save is destroyed; a separate permanent
profile keeps meta-currency for future runs. Runs are meant to get long.

---

## 2. Hard constraints

1. **Performance is the primary constraint.** Target: hundreds of enemies and
   projectiles on a low-spec machine, on maps larger than 100x100.
2. `assets/` is authored by hand and is never modified by tooling.
3. Git is never touched by tooling; the author backs up manually.
4. No addons or plugins without asking first. None are used today.

---

## 3. Decision log

Decisions that are expensive to reverse, with the reasoning, so future changes
are made deliberately.

### D1 — Walls occupy whole tiles, not tile edges
Edge-placed walls would need a second grid of ~2x the tile count (vertical and
horizontal edge sets), make every pathing neighbour test edge-aware, and make
projectile traversal a separate, slower algorithm. Tile walls keep a single
occupancy grid, a single flow field and a single traversal routine. Cost: a wall
consumes a buildable tile. Revisit only if the game demands it visually.

### D2 — Entities are data-oriented, not one Node per entity
Enemies, projectiles, workers and carriers live in struct-of-arrays inside
manager objects, not as `Node2D` per instance. A `Node2D` per enemy costs tree
overhead, per-node `_process` dispatch and separate draw calls; at the target
counts that is the difference between running and not running on the low end.
Buildings stay as real nodes — there are at most a few hundred, they are static,
and they need y-sorting and click-picking.

### D3 — Simulation time is our own, not `Engine.time_scale`
One root `_physics_process` computes `sim_delta = delta * speed` and passes it
down. Pause is `speed == 0`. This keeps UI animation, menus and the augment
choice screen running at real time while the world is frozen, and keeps the
simulation deterministic for a given seed and input sequence.

### D4 — Projectiles test the grid, not the physics server
A projectile walks the blocking grid with a supercover line traversal (a handful
of array reads per step) and queries a spatial hash for unit hits. No
`Area2D`/`RigidBody2D` per projectile, no physics server involvement.

### D5 — Enemy movement uses cached flow fields
An integer BFS over the cost grid produces one direction byte per tile. All
enemies sharing a target share one field. A small cache (~8 slots) covers the
handful of buildings actually under attack. Fields are recomputed only when the
blocking grid changes or a cached target dies — never per frame, never per enemy.

---

## 4. Runtime structure

    Main (Node2D)
      GameClock            # owns sim_delta, speed, pause
      RunDirector          # day/night, day counter, wave composition
      Level (LevelGenerator)
        Ground (TileMapLayer)
        Buildings (Node2D, y-sorted)   # Sprite2D per building
      Grids                # occupancy, blocking, cost, spatial hash
      Pathing              # flow field cache
      Units                # workers + carriers (SoA)
      Enemies              # SoA + MultiMeshInstance2D
      Projectiles          # SoA + MultiMeshInstance2D
      BuildPlacer
      Camera
      UI (CanvasLayers)    # shop, buildings, workers, options, augment choice

Autoloads stay thin and global: `EventBus` (signals only), `SaveManager`
(serialisation only), `Settings` (audio/video prefs only). Game state does not
live in autoloads — it lives in the systems above so a run can be torn down and
rebuilt cleanly.

`main.gd` currently instantiates every child by hand in `_ready`. This moves into
a `main.tscn` scene tree so the structure is visible and editable in the editor.

---

## 5. Grid layers

All grids are flat packed arrays indexed `y * map_size.x + x`. Never a
`Dictionary` keyed by `Vector2i` — at 65k cells that costs roughly two orders of
magnitude more memory and lookup time. (`LevelGenerator._occupied` is a
Dictionary today and gets converted.)

| Grid | Type | Meaning |
|---|---|---|
| `ground` | `PackedInt32Array` | terrain enum, exists today |
| `occupancy` | `PackedInt32Array` | building index at this tile, `-1` = free |
| `blocking` | `PackedByteArray` | bit flags: `BLOCKS_UNIT`, `BLOCKS_PROJECTILE`, `IS_ROAD` |
| `cost` | `PackedByteArray` | movement cost for pathing; roads cheap, rough terrain dear |
| `flow[slot]` | `PackedByteArray` | direction index 0-8 toward a cached target |

Walls set both blocking bits. Water and void set `BLOCKS_UNIT` until bridged.
Roads set `IS_ROAD` and lower `cost`.

**Open:** whether enemies may use roads. Exposed as a flag, default off, because
enemy-accessible roads turn a convenience into a liability and that needs play
testing before it becomes a rule.

---

## 6. Systems

### GameClock
Owns `speed` (0 = paused, 1 = normal, plus faster steps) and emits `sim_delta`.
Every gameplay system reads time from here, never from `_process(delta)`
directly. The augment screen and the options menu set speed to 0 rather than
using `get_tree().paused`, so UI stays live.

### RunDirector
Day counter, day/night phase, and wave composition per night. Waves scale by
**shape, not only by number**: later nights favour fewer, tougher enemies or
larger fragile swarms rather than simply multiplying the count, which keeps the
entity budget bounded as runs get long.

### Buildings
`BuildingData` (exists) gains: `max_health`, `threat_priority`, `build_cost`,
`build_work` (worker-seconds to complete), and category. Buildings have health;
at zero they are removed via `remove_building`.

Weapon buildings additionally carry a `WeaponData`: fire rate, damage, range,
projectile type, targeting rule.

### Workers and carriers
Two separate populations, bought in the shop, selected in the worker UI:

- **Mining workers** — clicked, then sent to a mine. They build a worker house
  there (capacity TBD), then gather automatically into a local stockpile. They
  are damaged in transit; once stationed they are safe. If their house is
  destroyed, they flee home and gathering at that site stops.
- **Building workers** — idle by default; automatically build and repair. The
  player sets a build-vs-repair priority. They are not sent manually.

**Carriers** ferry stockpiled goods from worker houses to the base. This is the
second convoy the player must protect, and it is what makes roads and wall
corridors worth designing.

All three are units in the same SoA store, so a single projectile hit test
covers them, which is what makes friendly fire cheap to implement.

### Enemies
Spawn at map edges. Their goal is the base, but they select targets by score:

    score = threat_priority / (distance + k)

so a cluster of mines and worker houses can outrank the base itself. They break
through walls when a wall blocks the path to their chosen target. Retargeting
happens on an interval and when a target dies, not every frame.

### Combat
Projectiles carry `friendly_fire: bool`, default **true**. They stop at walls
(D1/D4) and damage the first unit they overlap regardless of faction. Making
that a per-projectile flag rather than a global rule gives augments a lever —
"your projectiles pass through workers" is a meaningful late pick.

### Stats and modifiers
Every tunable value resolves through a stat block with explicit layers:

    final = (base + flat) * (1 + sum_of_increases) * product_of_multipliers

Shop upgrades and augments are modifier sources, never direct writes. This is
what makes synergies composable and debuggable instead of a pile of special
cases, and it is worth having in place before the first upgrade ships.

### Progression
Global XP from kills, exploration, and a slow survival drip that prevents
stagnation from stalling progress. On level-up the clock pauses and the player
picks **one of three** augments. Augments carry tags so synergy rules can be
expressed by tag rather than by naming individual augments. Shop purchases are
the small, frequent, resource-priced track; augments are the rare, loud one.

Per-building and per-worker XP is noted as a future direction and is not
designed for yet.

---

## 7. EventBus contract

Signals only; no state, no logic. Existing signals are kept; the set grows to:

    # run lifecycle
    run_started, run_ended(victory: bool), base_destroyed
    day_started(day: int), night_started(day: int)
    game_speed_changed(speed: float)

    # economy
    resource_changed(id: String, amount: int)

    # progression
    xp_gained(amount: int), level_up(new_level: int)
    augment_offered(choices: Array), augment_taken(id: String)

    # world
    building_placed(type: String, cell: Vector2i)
    building_destroyed(type: String, cell: Vector2i)
    worker_died(kind: int), carrier_died

High-frequency events (per-projectile, per-hit, per-enemy-death) do **not** go
through `EventBus`. Signal dispatch at hundreds of events per frame is a real
cost; those stay as direct calls inside the owning system.

---

## 8. Save format

Two files, deliberately separate.

**`user://run.save`** — the current run. Deleted on base death. Holds the map
seed and ground array, buildings with health and state, units, resources,
augments taken, XP, day number and clock state.

**`user://profile.save`** — permanent. Meta-currency, unlocks, statistics.
Survives death. Never written by run logic.

Both carry a `version: int` as the first key, and loading runs migrations
forward from older versions. Saves store plain data only — ints, floats,
strings, `Vector2i`, arrays, dictionaries — never objects, so `store_var` is
called with object support off.

The current `SaveManager` is debug scaffolding and is replaced by this.

---

## 9. Performance budget

Working targets, to be measured rather than assumed:

- 500+ enemies, 500+ projectiles, 100+ units, 16ms frame on a low-spec machine.
- Enemies and projectiles render through `MultiMeshInstance2D`, one draw call
  each. Note that MultiMesh does not y-sort per instance; instances are sorted
  by y into the buffer each frame, which is cheap at these counts.
- Buildings stay as `Sprite2D` under a y-sorted parent.
- Broadphase for hit tests is a spatial hash bucketed at a few tiles per cell,
  rebuilt each simulation step.
- Flow fields recompute only on structural change.
- Allocation in the hot loop is avoided: arrays are preallocated and entities
  are recycled through free lists rather than created and freed.

---

## 10. Known issues in existing code

- `LevelGenerator.remove_building` erases from `_occupied` while iterating its
  own keys, which can skip entries.
- `_occupied` and `buildings` are `Dictionary` keyed by `Vector2i`; both become
  flat arrays (section 5).
- `main.gd` builds its tree procedurally; moves into `main.tscn`.
- `project.godot` still defines `jump`, `left` and `right` input actions from an
  avatar that no longer exists.
