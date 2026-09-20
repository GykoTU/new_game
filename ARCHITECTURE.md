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

Implemented. `Level/world_grid.gd`, `buildings/building_store.gd`.
**Diagram: [`docs/grid-layers.svg`](docs/grid-layers.svg)** — the layers, the id
indirection, and the rules, drawn out. Keep it in step with this section.

`WorldGrid` owns every per-tile array. Systems that need to know what is where —
pathing, projectile traversal, placement, unit steering — read it directly;
`LevelGenerator` fills it and then steps back.

### The layers

All flat packed arrays, indexed `y * size.x + x`. **Never a `Dictionary` keyed
by `Vector2i`** — at 512x512 that is 262k tiles, where a dictionary costs orders
of magnitude more memory and lookup time than a flat array.

| Layer | Type | Kind | Meaning |
|---|---|---|---|
| `ground` | `PackedByteArray` | source | terrain enum; a byte, since nine values fit in one |
| `occupancy` | `PackedInt32Array` | source | building id, or `NO_OCCUPANT` (-1) |
| `blocking` | `PackedByteArray` | derived | `BLOCKS_UNIT`, `BLOCKS_PROJECTILE`, `IS_ROAD` |
| `cost` | `PackedByteArray` | derived | movement cost; `255` = impassable |

Plus two internal byte arrays holding the occupant's own contribution. Storing
it costs two bytes per tile and buys order-independence: changing terrain under
a building and adding a building over terrain give the same answer either way.
That matters once several systems write to the grid.

**Derived layers are outputs, never inputs.** Write `ground`, or `claim`/
`release` a tile, and `blocking` and `cost` follow. Setting them by hand
desynchronises them from the truth, and every later bug from that is invisible.

`255` in `cost` means impassable, not "very expensive". Pathing must treat it as
a wall; a cost-weighted search that merely disprefers it will happily route
units into water when the detour looks long enough.

### Terrain rules

Water, void and lava block movement. That is the expansion gate, not an obstacle
to it: copper sits in water, quartz in void, gold in lava, so reaching them needs
boats, bridges and eventually hauling water to cool lava. Ice and sand are
passable but cost more than open ground.

The table lives in `WorldGrid.GROUND_BLOCKING` and `GROUND_COST`, so changing
which terrain blocks what is a one-line edit rather than a refactor.

**Open:** whether enemies may use roads. Enemy-accessible roads turn a
convenience into a liability, which is interesting but needs play testing.

### Buildings

`BuildingStore` holds buildings as parallel arrays addressed by a stable integer
id, and `occupancy` stores that id. One indirection means a building's data
lives in one place however many tiles it covers, and that buildings can carry
state — health today; build progress, worker slots and cooldowns later — which a
`Dictionary -> String` could not without becoming a dictionary of dictionaries.

Ids come from a free list and are **reused after removal**, so an id is only
meaningful while `is_alive(id)` holds. Nothing should cache an id across a
removal without checking.

Removal clears the rectangle named by the record's `cell` and `size`. The old
`remove_building` scanned a dictionary and erased from it while iterating its own
keys, which could skip tiles and leave phantom occupancy behind. There is now
nothing to iterate, so the bug is gone structurally rather than patched.

### Accessors

Every getter has a `Vector2i` form for clarity and an `_at(index)` form for hot
loops. Code that already holds an index must use `_at` — building a `Vector2i`
per tile read is exactly the kind of cost that does not show up until there are
hundreds of entities doing it every tick.

### Measured

Generation, on the development machine, via the headless benchmark:

| Map | Tiles | Generate | Grid memory |
|---|---|---|---|
| 100x100 | 10,000 | ~130 ms | 88 KB |
| 256x256 | 65,536 | ~320 ms | 576 KB |
| 512x512 | 262,144 | ~860 ms | 2.3 MB |

Generation is one-time, so these are comfortable. Memory is the number that
matters for the flow fields landing on top of these grids in Stage 4.

Note: `environment_count` is a flat count, not a density, so larger maps are
currently emptier rather than bigger. It should scale with map area before map
size is tuned for real.

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

Implemented. `global/save_manager.gd`.
**Diagram: [`docs/save-flow.svg`](docs/save-flow.svg)** — the write path, the
crash windows and the load chain. Keep it in step with this section.

### Who decides what is saved

`SaveManager` does three things: file I/O, integrity, versioning. It does not
know what a level or a worker is. `main.gd` assembles the run dictionary from
the systems that own the data, and each system provides its own
`get_save_data()` / `load_save_data()`. Adding a system to the save means adding
one key in `main.gd.save_run()`, never touching the autoload.

    SaveManager.save_run(data) -> bool     load_run() -> Dictionary
    SaveManager.has_run() -> bool          delete_run()
    SaveManager.profile                    save_profile() -> bool

`settings.cfg` is not a save. It stays in `Settings` as a plain `ConfigFile`.

### Two files, two policies

**`user://run.save`** — one run. Deleted on death and on New Game. A version
mismatch is **refused**: runs are ephemeral, and carrying migration code for
every shape an in-development format passes through costs more than the
occasional lost run.

**`user://profile.save`** — permanent, never deleted by a run ending. A version
mismatch is **migrated**, never discarded, because meta progression is the one
thing a player would genuinely mourn. Keys added since a file was written take
their default on load, so additive changes need no migration step; only a change
in meaning needs one, and those go in `_migrate_profile` one version step at a time.

Today the profile holds statistics. Meta-currency and unlocks join it in Stage 8.

### Writing safely

A plain `FileAccess.open(WRITE)` truncates the existing file before the new
bytes exist, so a crash mid-write destroys the save outright. For a game aiming
at long runs that is the worst failure mode available, so writes go:

1. serialize, hash with SHA-256
2. write header and payload to `run.save.tmp`
3. **read it back and verify** — if that fails, stop; nothing has been rotated
4. `run.save` -> `run.save.bak`
5. `run.save.tmp` -> `run.save`

Godot cannot rename over an existing file portably, so step 4 opens a brief
window where `run.save` does not exist. That is survivable rather than ignored:
`.tmp` at that moment is a *complete newer* save and `.bak` is the previous run,
which is precisely why the load chain checks `.tmp` before `.bak`.

### Reading safely

The load chain is `run.save`, then `run.save.tmp`, then `run.save.bak`, taking
the first whose magic, container version, schema version and digest all verify.
Recovering from anything but the first logs a warning, so a degraded load is
visible rather than silent.

`has_run()` walks that same chain and verifies the payload rather than peeking
at the header. A header can be intact while the payload behind it is corrupt,
and a Continue button that silently drops the player into a brand new world is
worse than the milliseconds a full check costs on a title screen.

File layout, digest before payload so truncation is detected rather than
deserialised into nonsense:

    u32+bytes "NSPL" | u32 container ver | u32 schema ver
    u32+bytes sha256 hex | u64 payload length | payload bytes

Every length is bounded before it is trusted, so a corrupt length field cannot
make the loader allocate wildly. Payloads are `var_to_bytes` without object
support: saves carry plain data only, never objects.

### Autosave

Not implemented yet, deliberately. Saving mid-combat with hundreds of entities
is a frame hitch, and the natural checkpoint is a day boundary, which needs
`RunDirector` (Stage 3). `save_run()` is ready to be called from there.

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

- ~~`remove_building` erases from `_occupied` while iterating its own keys~~ —
  fixed; removal now clears the record's rectangle.
- ~~`_occupied` and `buildings` are `Dictionary` keyed by `Vector2i`~~ — done,
  now `WorldGrid.occupancy` and `BuildingStore`.
- ~~`main.gd` builds its tree procedurally~~ — done, now `main.tscn`.
- ~~`project.godot` defines dead avatar input actions~~ — done, removed.
