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

### D6 — Behaviours are effect hooks, not stat modifiers
The stat system moves numbers. It cannot express "shots split into two",
"shots bounce off walls" or "hook enemies". Those are *behaviours*, and they get
their own mechanism: an ordered set of effect hooks fired at points in a
projectile's life. Keeping the two systems separate is what lets a numeric
upgrade and a behavioural one compose without either knowing about the other.

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

## 5. Time and the update loop

Implemented. `game/game_clock.gd` and `game/main.gd`.
**Diagram: [`docs/frame-pipeline.svg`](docs/frame-pipeline.svg)** — the frame
pipeline and the sub-stepping rationale, drawn out. Keep it in step with this
section when either changes.

This is the most fragile part of the codebase to change, because nothing about
it is visible on screen and almost everything depends on it.

### Speed adds ticks; it never scales dt

`GameClock` holds a constant `TICK_DELTA` of 1/60s and an accumulator. Each
frame `advance(delta)` returns how many whole ticks to run: speed 2 returns
twice as many, speed 0.5 returns one every other frame, speed 0 returns none.

The tempting alternative — `dt = delta * speed` — is wrong for this game and
must not be reintroduced. Collision here is sampled, not swept: projectiles walk
the blocking grid (D4) and units test a spatial hash. Multiplying dt multiplies
the distance covered between two samples, so at 4x a fast projectile can have
one sample before a one-tile wall and the next beyond it, and passes through.
Sub-stepping keeps every sample the same distance apart at every speed, so
behaviour at 4x is identical to 1x, only more of it.

`MAX_TICKS_PER_FRAME` (8) caps the work one frame can request. Without it a slow
frame asks for more ticks next frame, which makes that frame slower still. When
the cap is hit, simulation time falls behind wall-clock time deliberately: the
game slows down rather than locking up.

### Main owns the order; the clock only owns time

`GameClock` has **no `_process` of its own**, on purpose. Godot calls `_process`
on a parent before its children, so a self-ticking clock would always be one
frame stale by the time `Main` read it. `Main._process` calls
`clock.advance(delta)` and then `_simulate(TICK_DELTA)` once per tick.

Systems are stepped by **explicit calls in `_simulate()`, never by connecting to
a signal.** Signal handlers run in connection order, which is invisible at the
call site and silently changes when connection code is reordered. Simulation
order is load-bearing — enemies move, then projectiles step, then hits resolve,
then damage applies — so it is written down in one readable list. The intended
order is in the diagram; systems join it as they are built.

High-frequency gameplay events stay out of `EventBus` for the same reason
(section 8): signal dispatch hundreds of times per tick is a real cost, and the
ordering is invisible.

### Pausing is a set of reasons, not a boolean

The options menu, the augment screen and the player's own pause key all stop
time. With a flag, closing the options menu would resume a run the player had
deliberately paused. So the clock holds a set of named reasons and runs only
when it is empty and `speed > 0`. Whoever pushes a reason pops it:

    clock.push_pause("options_menu")   # main.gd, on menu visibility
    clock.toggle_player_pause()        # the player's own pause key

`get_tree().paused` is deliberately **not** used. Freezing the tree would also
freeze menu animation and tweens; freezing only simulation keeps the UI alive
while the world stands still. Anything that pauses the world in future should
push a reason rather than reach for the tree.

On resume the accumulator is discarded, so time spent in a menu is never banked
and replayed as a burst of ticks.

### tick_count is the run's clock

`tick_count` advances only while the clock runs, so it is unaffected by frame
rate, pausing and speed. It — not wall-clock time — is what day length, wave
timing, the survival XP drip and the run save should be measured in. Using real
seconds anywhere in gameplay would make those depend on the player's frame rate
and pause habits.

### Input actions

`game_pause` (Space), `game_speed_1/2/3` (1, 2, 3 -> 1x, 2x, 4x), bound by
physical keycode so keyboard layout does not matter. The avatar-era `jump`,
`left` and `right` actions were removed.

### Scene ownership

`main.tscn` holds the run tree (section 4) instead of building it procedurally.
One consequence: children are readied before their parent, so `Level` would
generate a map before `main.gd` could decide a save should be loaded instead.
`generate_on_ready` is therefore false and `main.gd` calls `generate()` or
`load_save_data()` explicitly. Generation is never implicit.

Note for hand-edited scene files: a node property that references another node
needs `node_paths=PackedStringArray("prop")` in its `[node]` header, or the
stored `NodePath` is never resolved and the property is silently null at runtime.

---

## 6. Grid layers

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

## 7. Systems

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

Enemy position integration takes an **impulse channel** layered on top of
flow-field steering: a per-enemy velocity offset that decays over time. Knockback,
pulls and hook effects write to it rather than fighting the pathing. Without this
channel no weapon can ever physically move an enemy, and retrofitting it means
touching every movement path.

### Combat
Projectiles carry `friendly_fire: bool`, default **true**. They stop at walls
(D1/D4) and damage the first unit they overlap regardless of faction. Making
that a per-projectile flag rather than a global rule gives augments a lever —
"your projectiles pass through workers" is a meaningful late pick.

### Weapon behaviours and effect hooks

Behavioural upgrades are the interesting half of the weapon design, and they
need a mechanism the stat system cannot provide (D6).

Each projectile carries a `behaviour_set` id pointing at a shared, immutable,
pre-compiled list of behaviours. The set is shared by every projectile from that
weapon, so adding behaviours costs no per-projectile memory. Mutable per-shot
state — bounces left, splits left, hooked target — lives in a few generic scratch
slots in the projectile arrays.

Hooks, fired in priority order:

    on_spawn(p)                  # aim, spread, initial buffs
    on_step(p, dt)               # homing, acceleration, orbiting
    on_wall_hit(p, cell, normal) # bounce, pierce, stop, detonate
    on_unit_hit(p, unit)         # damage, split, hook, chain, pierce
    on_expire(p)                 # detonate, drop a field
    on_kill(p, unit)             # on-kill triggers, resource drops

Hooks fire on *events*, not per projectile per frame — `on_step` is the only
per-frame hook and most behaviours do not implement it. So a few hundred
projectiles cost a few hundred cheap array updates plus a handful of hook calls
where something actually happened.

Worked examples, to show the composition is real:

- **Bounce** — `on_wall_hit` reflects velocity about the tile normal and
  decrements a scratch counter; stops when it hits zero.
- **Split** — `on_unit_hit` spawns N children inheriting the behaviour set with
  a generation counter incremented.
- **Hook** — `on_unit_hit` stores the unit id and switches the projectile to a
  returning state; `on_step` applies an impulse to the hooked enemy each step.

Bounce and split compose without either knowing the other exists, which is the
whole point.

**Budget discipline.** Split, chain and bounce multiply entity counts, and
split-of-split is exponential. Every projectile carries a generation counter, sets
declare a max generation, and the projectile pool has a hard ceiling; when the
pool is full, new spawns are dropped rather than growing the arrays. An augment
combination must never be able to stall the game.

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

## 8. EventBus contract

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

## 9. Save format

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

## 10. Performance budget

Working targets, to be measured rather than assumed:

- 500+ enemies, 500+ projectiles, 100+ units, 16ms frame on a low-spec machine.
- Enemies and projectiles render through `MultiMeshInstance2D`, one draw call
  each. Note that MultiMesh does not y-sort per instance; instances are sorted
  by y into the buffer each frame, which is cheap at these counts.
- Buildings stay as `Sprite2D` under a y-sorted parent.
- Broadphase for hit tests is a spatial hash bucketed at a few tiles per cell,
  rebuilt each simulation step.
- Flow fields recompute only on structural change.
- Hard ceilings on the enemy and projectile pools; spawns are dropped when full,
  so no augment combination can grow the arrays without bound.
- Allocation in the hot loop is avoided: arrays are preallocated and entities
  are recycled through free lists rather than created and freed.

---

## 11. Known issues in existing code

- `LevelGenerator.remove_building` erases from `_occupied` while iterating its
  own keys, which can skip entries.
- `_occupied` and `buildings` are `Dictionary` keyed by `Vector2i`; both become
  flat arrays (section 5).
- ~~`main.gd` builds its tree procedurally~~ — done, now `main.tscn`.
- ~~`project.godot` defines dead avatar input actions~~ — done, removed.
