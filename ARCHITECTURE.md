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
5. **Art requests are a list of full paths**, e.g. `assets/npcs/builder.png`,
   with size and — for animations — layout. The artist draws to that list;
   code never invents a path the artist was not given.

**Animation sheets:** one horizontal strip per animation, every frame 32x32,
no trim, border, spacing or padding (Aseprite: Export Sprite Sheet, Layout
"Horizontal strip"). Drawn facing right; left is mirrored in code. Frame time
defaults to 100 ms (Aseprite's default) and is a per-animation setting. Units
are drawn in one batch per kind with a shader picking each unit's frame, which
is why the layout must be a fixed grid rather than Aseprite's packed layout.
Current sheets: `assets/npcs/carrier_walk.png` (8 frames).

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

### D7 — StatBlocks are per type, never per instance
One block for "goblin", one for "fire weapon", one for workers — never one per
enemy. Hundreds of enemies share a block, and its resolved values are copied
into each enemy's arrays at spawn. A block per instance would mean hundreds of
caches re-resolving on every modifier change, which is exactly the per-entity
overhead D2 exists to avoid. Short-lived per-instance effects (slowed, burning)
are **status slots** on the entity, not modifiers.

### D8 — Registries are append-only
`Stats.Id`, `ResourceKind.Id`, `WorkerRoster.Kind` and `WorldGrid.Ground` are
enums whose integers are stored inside `.tres` files or saves — the level save
stores ground as one byte per tile, and `BuildingData.allowed_grounds` is a bit
per ground type: a StatModifier stores `stat = 18`, a shop item
stores its cost as `{0: 40, 2: 5}`. Inserting or reordering an entry silently
retargets every saved reference — the pickaxe would quietly start modifying a
different stat. New entries go at the end, before `COUNT`; nothing is removed,
only retired. Save files are keyed by string ("gold", "miner") precisely so
they survive a mistake here; authored data cannot be.

### D9 — Prices resolve through the stat system
A shop price is `base * growth^purchases * SHOP_PRICE`, where `SHOP_PRICE` is an
ordinary stat resolved from a per-item StatBlock tagged with the item's
`price_tags()`. So a sale, a merchant augment, or a "workers cost less" upgrade
is a modifier source, not new code, and inherits tag targeting, saving and
rebalancing for free. Reversing this would mean a second, parallel discount
system for every future price effect.

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
      UI (CanvasLayers)    # options, shop, building bar, worker bar,
                           # resource bar, stat overlay; augment choice later

Planned nodes above not yet built: RunDirector (Stage 3), Enemies,
Projectiles (Stages 4, 5). Grids exist as `Level.grid` (WorldGrid). Units are
a `UnitSystem` object (below) plus one `UnitRenderer` node; unit pathing lives
inside the UnitSystem.

`main.gd` also owns the run's plain-object systems, which have no node: the
ModifierSet, Economy, WorkerRoster, Shop and UnitSystem. It passes them to the UI through
`bind()` calls in `_ready`, so the UI never reaches into `main.gd` on its own.

Autoloads stay thin and global: `EventBus` (signals only), `SaveManager`
(serialisation only), `Settings` (preferences: audio, video, key bindings).
Game state does not live in autoloads — it lives in the systems above so a run
can be torn down and rebuilt cleanly.

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

### Workers and carriers (implemented, Stage 2a)

**Diagram: [`docs/units.svg`](docs/units.svg)** — what each kind of worker
does, the states a unit moves through, and who owns which piece of data.

Three kinds, all in one store: **miners** (sent to a mine), **builders** and
**carriers** (work on their own). One store means
one projectile hit test will cover every unit, which is what makes friendly
fire cheap later.

| Piece | File | Job |
|---|---|---|
| `UnitStore` | `units/unit_store.gd` | Parallel arrays per unit (D2): kind, pos, path, state, task, home, target, inside, fetch, carry, hp. Stable ids from a free list. |
| `DropStore` | `units/drop_store.gd` | Resources lying on the ground: kind, landing spot, bounce start and tick, source mine, who is fetching it. |
| `UnitSystem` | `units/unit_system.gd` | All behaviour. Stepped once per tick from `main._simulate`. Owns the unit and drop stores, pathing, the job board, each mine's progress toward its next drop, and which miner is the commuter. |
| `UnitPathing` | `units/unit_pathing.gd` | `AStarGrid2D` over the map. Solid = impassable, weight = `cost / COST_OPEN`. Diagonals only past open corners. |
| `JobBoard` | `units/job_board.gd` | Builder work in priority order build > repair > cobble > chop, nearest first, at most 4 builders per job. |
| `UnitRenderer` | `units/unit_renderer.gd` | One `MultiMeshInstance2D` per (kind, animation), plus one per resource for drops (under the units). Drawn once per frame, after the simulation. |

**How it plays.**
- **Run start.** Placing the base places a finished builder house and carrier
  house near it, with a builder and a carrier inside, plus one miner with no
  house, waiting in the base: the **commuter** (`_commuter`).
- **Only busy units are drawn.** `UnitStore.inside` is 1 while a unit is in a
  building: new units spawn inside; `walk()` brings them out; arriving home
  (`GO_HOME`, `FLEE`), or standing beside home with nothing to do, puts them
  back in. The renderer skips inside and stationed units. When a house falls,
  anyone inside is exposed.
- **Beds.** Builder and carrier houses hold `HOUSE_CAPACITY` each (a stat,
  default 3, so occupancy upgrades are ordinary modifiers). The shop asks
  `main._purchase_check` before selling a worker and greys the slot out with
  the reason ("Needs a free bed…").
- **Sending miners.** Click the miner slot in the worker bar, then a mine.
  Shift keeps the mode open to send more; the cancel key or any refusal ends
  it, with the reason shown in a toast. A mine whose miner house has a free
  bed takes the nearest idle bought miner (or, with none idle, the commuter).
  A mine without one can only be worked by the commuter, who walks there
  (`TO_MINE`) and mines outside (`MINING`: visible, exposed); bought miners are
  refused with "Build a miner house next to this mine first." The first miner
  house to be built pulls the commuter in, wherever it is. If its house falls,
  it flees to the base and commutes again. A house placed on the tile a miner
  stands on still takes it in: `cells_to_building` returns `[from]` for a unit
  already inside the footprint.
- **Construction.** A site is a real building with `progress < 1`, drawn faded
  (`CONSTRUCTION_ALPHA`) until `construction.png` exists. Builders add work;
  more builders build faster. Miners wait beside the site, then move in.
- **Gathering drops resources.** Stationed miners are hidden and safe; the
  commuter mines outside. Each adds `GATHER_RATE` work per second to its
  mine's progress; every whole unit pops one
  drop out of the mine, bouncing (0.4 s, drawn only) onto a random free,
  walkable tile within 2 of it. At `drops_per_mine_cap` (20) drops from one
  mine, it pauses until some are picked up.
- **Fetching.** Carriers only: no other unit carries resources. A carrier
  claims the nearest landed, unclaimed drop, walks to it, takes it plus any
  landed drops of the same resource within 48 px, up to `CARRY_CAPACITY` (10),
  and carries them to the base (the nearest depot in 2b). The claim stops two
  carriers racing for one drop.
- **Losing a building.** Units working on it or walking to it drop the job. If
  a worker house falls, its miners flee to the base and gathering there stops.

**Pathing.** One path per trip, computed when the trip starts; nothing is
cached between trips. With dozens of workers this is cheap (200 walking units
measured at 0.75 ms per tick). A path to a building is found by temporarily
opening that building's own footprint, so a path can end on a solid tile. The
pathing grid is rebuilt once per map, then kept in step through
`WorldGrid.tiles_changed`, which carries only the changed indices. `notify` is
off while a level is being generated or loaded, so a new map does not announce
itself one tile at a time.

**Thinking is staggered.** An idle unit decides again every `THINK_INTERVAL`
ticks (20, a third of a second), not every tick. Walking and working run every
tick.

**Animation.** Each unit kind names an idle sheet and an optional walk sheet
in `UnitRenderer.LOOKS`. Sheets are horizontal strips, frames = width /
height. A shader picks the frame and mirrors it when the unit faces left
(sheets face right). Frames advance on `tick_count`, so animation pauses and
speeds up with the game. The quad is a hand-built 2D `ArrayMesh`: a
`QuadMesh` draws upside down in 2D.

### Rules for simulation code

Both learned from bugs; neither shows on screen until it breaks.

- **Save references as cells, never as ids.** Building and unit ids are handed
  out again when a run loads, so a saved id points at the wrong thing. A
  unit's home, a house's mine, a drop's mine, each mine's progress and the
  mine the commuter works are all saved by cell and looked up again after the
  level loads. Claims and trips are not saved:
  units decide again after loading. This is also why units load *after* the
  level.
- **No lambdas on signals inside `RefCounted` classes.** A lambda keeps a strong
  reference to `self`. Connected to another object's signal, it forms a cycle
  that never frees (roster ↔ units leaked this way). Connect a method instead:
  `units.changed.connect(_on_units_changed)`. `boot.sh` now fails on any
  "leaked" or "still in use" line at exit.

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

**Behaviours read their parameters from stats.** Bounce reads `bounce_count`,
explosions read `area_radius`, hook reads `pull_strength`. The behaviour decides
*what happens*; the weapon's StatBlock decides *how much*. So "+1 bounce" is an
ordinary modifier and needs no code, and the two systems meet at exactly one
point: a behaviour calling `get_value()` on its weapon's block.

**What the mechanics review added.** Checking the proposed mechanics
(`docs/mechanics-coverage.md`) against this seam found that it was
projectile-only, and three things are needed beyond it:

- **Effects are first-class, not projectiles.** Explosions, burning ground and
  chain triggers are entities in their own right. They share the projectiles'
  generation counter, pool ceiling and `on_kill` hook — otherwise "enemies
  explode on death" chains with nothing to stop it, because no projectile is
  involved. *(Stage 5)*
- **Enemies have movement events.** Hook and fling drive enemies with impulses;
  an enemy slammed into a wall or another unit needs an event on the enemy side
  (`on_wall_impact`, `on_unit_impact`) for impact damage to live in. *(Stage 4)*
- **Impulse movement respects the blocking grid.** Otherwise hook and fling are
  ways to teleport enemies through walls. *(Stage 4)*

Slow and burn are status slots on the enemy (D7), strongest-wins with a
refreshed duration, rather than additive stacks.

### Stats and modifiers

Implemented. `stats/`.
**Diagram: [`docs/stat-resolution.svg`](docs/stat-resolution.svg)** — a worked
example through tags, the formula, and per-stat caching.

Four pieces:

- **`Stats`** — the registry. Enum id, name, default and clamp range per stat.
  Adding a stat is one enum entry and one table row, checked for order at load.
- **`StatModifier`** — a `Resource`: stat, op, value, tags. Authorable in the
  inspector. Deliberately has **no source field**: a `.tres` is shared by
  everything referencing it, so two augments pointing at one modifier would
  fight over a source written onto it.
- **`ModifierSet`** — every active modifier in a run, grouped by **source**.
  Sources are the unit of change: an augment, an upgrade level, a timed buff.
  All of a source's modifiers arrive and leave together.
- **`StatBlock`** — base values plus tags, resolving and caching. One per type
  (D7).

**The formula, in one place.** `Stats.combine()` is the only place the order of
operations exists:

    final = clamp( (base + flat) * (1 + sum of increases) * product of multipliers )

Increases **add**; multipliers **multiply**. Two +50% increases give x2.00, two
x1.5 multipliers give x2.25. That gap is what lets a rare augment be worth more
than a common one — and it only means anything if the order never varies.

**Clamps are deliberate.** Stacking multipliers will eventually push fire rate
to zero or slow to 100%; the first symptom would be a division by zero or an
enemy frozen forever, far from its cause. `fire_rate` floors at 0.05,
`slow_strength` caps at 0.9, counts are capped. `FIRE_RATE` is shots per second
rather than a cooldown so that "+20%" is always good news.

**Tag targeting.** A modifier applies when the block carries **all** of its
tags; no tags means everything. `["weapon", "fire"]` reaches fire weapons and
nothing else. This is what makes synergies emerge instead of being hand-listed:
a modifier on a tag reaches every present and future thing carrying that tag.

**Caching is per stat.** `ModifierSet.stat_generation[stat]` moves only when a
change touches that stat; blocks compare per stat and re-resolve only what
moved. Measured: a cached read ~0.34 us; a change 0.25 ms across 50 blocks.
The first version re-resolved every stat on every change and cost **2.7 ms** —
enough that timed buffs expiring several times a second would show. Do not
simplify back to one counter without re-running the benchmark.

A replaced source must invalidate the stats it **used** to touch as well as the
ones it touches now, or a source moving from damage to range leaves damage
stale. There is a test for exactly this.

**Saving stores sources, not results.** The run save lists active source ids;
on load, `main.gd._resolve_modifier_source` rebuilds them from current data. A
rebalanced augment therefore reaches runs already in progress. An unknown
source refuses the load, for the same reason a missing building does. Runs saved
before modifiers existed have no `modifiers` key and load as an empty set, so
this was an additive change and `RUN_VERSION` did not move.

### Economy and shop

Implemented. `economy/`, `data/shop/`, `UI/shop_*.gd`, `UI/resource_bar.gd`.
**Diagram: [`docs/economy-flow.svg`](docs/economy-flow.svg)** — the buy path,
how a price is calculated, and why sales and saving need no special code.

- **`ResourceKind`** — registry: gold, quartz, copper, diamond, fruit. Each has
  a save key, a display name, an icon and the building that yields it. Append-
  only (D8). A new resource appears in the resource bar with no UI change.
- **`Economy`** — whole-number amounts. `spend(cost)` is **all or nothing**: a
  cost of 20 gold and 5 copper takes both or neither, so a player can never have
  paid half a price. New runs start with `starting_resources` (an export on the
  Main node).
- **`WorkerRoster`** — how many miners and builders the player owns. Separate
  kinds by design. A count only until Stage 2 turns each into a unit.
- **`ShopItemData`** / **`ShopCatalogue`** — one `.tres` per item in
  `data/shop/`, listed in `catalogue.tres` in display order. Items are WORKER or
  UPGRADE, carry a base cost per resource, a per-purchase growth factor, and an
  optional max level. Icons are **paths**, not textures, so a missing sprite
  shows the fallback instead of making the item fail to load.
- **`Shop`** — prices, affordability, and what a purchase does.

**Upgrades are levelled modifier sources.** Buying level N re-adds the source
`"upg:<id>"` with the item's modifiers scaled to N — FLAT and INCREASE by N,
MULTIPLIER to the power N — replacing level N-1. The level is stored once, as
the purchase count, never in the source id.

**Worker prices grow with purchases, not with workers alive**, so losing a
worker does not make the next one cheaper. Revisit once workers can die.

**Prices** follow D9: `round(base * growth^n * SHOP_PRICE)`, never below 1.
Two rounding details, both caught by rendering the real shop:
- Halves round **up**, after snapping to 0.001. `45 * 0.7` is
  `31.499999999999996` in binary floating point and otherwise shows 31.
- Stat storage is float64. Float32 turned 0.7 into 0.69999999, enough to flip a
  price by one; blocks are per type, so the memory never mattered.

Rounded, not ceiled: ceiling would make 30% off a 3-gold item still cost 3.

**Sales** exist as a mechanism, not as content. A sale is a modifier source with
`SHOP_PRICE` on tags such as `["shop", "upgrade"]`. When and how sales happen —
schedules, events, random — is undesigned; the shop already shows a struck-
through original price and the sale badge whenever one applies.

The shop does not pause the game; the player has a pause key.

### Key bindings

Implemented. `global/keybinds.gd`, `UI/controls_list.gd`, and the Controls
section of the options menu.

Every shortcut is a named InputMap action — including the ones that used to be
hard-coded (Ctrl+N, and the build placer's left/right click). `Keybinds.ACTIONS`
lists each with a label, category, whether it is rebindable, and whether it is
**dev-only**. Defaults live in `project.godot`; only bindings the player
changed are written to `settings.cfg`, so a changed default in a later build
still reaches everyone who never touched it.

- **Conflicts:** binding an input another action holds takes it from that
  action, which is left unbound and shown in red — never silently given a
  different key.
- **Escape is reserved.** The menu action cannot be rebound and its key cannot
  be taken, or a player could lock themselves out of the menu that fixes it.
- **Comparing inputs** uses `Keybinds.same_input`, not `InputEvent.is_match`.
  Godot's built-in `ui_*` actions define keys by *keycode*, this project's by
  *physical* keycode, and `is_match` treats those as different keys — which is
  how the first version let Escape be taken.
- **Capture** runs in `_input` and consumes every key and button while active,
  so pressing Space to bind it does not also pause; the shop toggles in
  `_unhandled_input` for the same reason.

**Dev-only actions in release builds** are hidden from the list *and* erased
from the InputMap at startup, before saved bindings are applied, so editing
`settings.cfg` cannot resurrect them. Debug handlers check the build first,
because asking about an erased action is an error, not a false. Exports made
with Godot's *debug* template still count as debug builds. Tested by
`Keybinds.simulate_release`, a test-only switch.

Dev shortcuts today: **Ctrl+N** new run, **Ctrl+G** grant resources (hold it
to keep granting: after 0.35 s, 10 times a second, in wall time so it works
while paused; each grant in one hold is 1.25x the last, capped at 1e9 per
grant, for stress tests), **F3** stat overlay (every modifier source and every resolved
stat, live).

### UI and input: rules that are easy to break

Three rules, each learned from a bug. None of them is visible on screen until
it is broken.

- **The world only reacts to input the UI did not use.** The camera starts pans
  and zooms in `_unhandled_input`, never by polling `Input.is_action_*` —
  polling sees every scroll, including one a menu already consumed, which made
  the camera zoom while scrolling the controls list. As a second line of
  defence it also ignores input whenever `gui_get_hovered_control()` is set.
- **Containers let mouse events through by default.** In Godot 4 a
  PanelContainer's `mouse_filter` defaults to PASS, so clicks in the gaps of a
  panel fall through to the build placer and scrolls to the camera. Every HUD
  panel sets STOP. Buttons *inside a ScrollContainer* are the exception: they
  use PASS so the scroll wheel reaches the list instead of dying on the button.
- **The options menu is modal, and must be the last child of `UI` in
  `main.tscn`.** Unhandled input runs in reverse tree order, so the last child
  sees it first; while open it consumes every key and mouse button, so nothing
  underneath reacts. It always opens with every section collapsed.

Verified by driving the real game with simulated input under a virtual display,
including a control experiment: the same click that is blocked by the open shop
places the base once the shop is closed.

### Art references

`Art.texture(path)` loads a sprite or returns a grey checker placeholder when
the file is missing or not yet imported — a PNG only becomes loadable after
the editor has imported it once. Debug builds print the list of missing
sprites at startup. Nothing ever writes into `assets/`: the artist names the
files, code references them by path.

### Wood, crafting and the building bar (implemented, Stage 2b)

**Diagram: [`docs/crafting-flow.svg`](docs/crafting-flow.svg)** — from a
marked tree to a placed, built building, and the timers in between.

| Piece | File | Job |
|---|---|---|
| `Forest` | `Level/forest.gd` | Marked trees, chop progress, stumps rotting, trees regrowing. |
| `TimedEvents` | `game/timed_events.gd` | Events due at a later tick (kind + cell), saved with the run. |
| `Unlocks` | `economy/unlocks.gd` | The run's known ids (`"blueprint:depot"`); starts with the four starter blueprints. |
| `BuildingInventory` | `buildings/building_inventory.gd` | Crafted buildings by type, in first-crafted order. |
| building bar | `UI/building_ui.gd` | One slot per type with a count. A column of 5 slots is always shown (the frame image at 3x, the building at 2x on top). Hover + hold `expand_building_bar` (Shift) opens further columns to the right, partly transparent. |

- **Trees and wood.** `WOOD` is appended to `ResourceKind` (D8). Plain trees
  (`tree`) generate on grass, fruit trees on flowers. Clicking a plain tree
  toggles its mark (`main._tree_click`, shown as a red tint until a mark
  sprite exists). JobBoard CHOP lists marked trees; a builder working one adds
  `BUILD_SPEED` per second to its chop progress, and at `chop_work` (4) the
  tree becomes a stump and `wood_per_tree` (3) wood drops bounce out.
  Carriers fetch them like mined resources. Unmarking mid-chop stops the
  builder; progress is kept.
- **Timers.** A stump schedules its own removal (`stump_seconds`, 60). A
  repeating regrow event (`regrow_seconds`, 45) grows one tree on a random
  free grass tile with nothing around it, while there are fewer trees than
  the map started with. Everything is in ticks and saved; regrowth spots come
  from the Forest's RNG, whose seed and state are saved too.
- **Buy and Craft.** `ShopItemData` gains `section` (BUY / CRAFT), the kind
  `BUILDING` (appended) with `building_id`, and `blueprint` (an unlock id;
  empty = always known). The shop hides unknown items and refuses them
  ("Needs a blueprint"). "Buy costs only gold, Craft costs no gold" is a data
  rule, checked by a test over the catalogue. An `ITEM` kind (bucket) is
  appended in 2c.
- **Placing.** Crafting adds one to the inventory. Clicking a bar slot starts
  `BuildPlacer` in construction mode (cancellable); a successful placement
  takes one from the inventory, and builders build the site. Houses add beds
  once complete.
- **Depots.** A carrier delivers to whichever is nearer in a straight line:
  the base or a finished depot (falling back to the base if the depot can't be
  reached). Resources count when they arrive.
- **Miner houses** (`worker_house`) are crafted and placed like any building.
  `BuildingData.must_touch_prefix = "mine_"` with `one_per_touched` makes
  `can_place` require a mine that no other miner house touches; placing one
  links it to that mine (`UnitSystem._on_building_placed`).

### Lava, cobble and the bucket (implemented, Stage 2c)

**Diagram: [`docs/cobble-flow.svg`](docs/cobble-flow.svg)** — the bucket's
stages, tile jobs, and how a painted line of lava becomes a road to gold.

| Piece | File | Job |
|---|---|---|
| `LavaWorks` | `Level/lava_works.gd` | Lava marks, cobble progress per tile, filling the bucket. |
| `TileMarks` | `Level/tile_marks.gd` | Draws the marked tiles (a see-through fill and outline); redrawn only when marks change. |
| item bar | `UI/item_bar.gd` | Owned items, top left: one slot per item, showing its best stage. Clicking one emits `item_pressed`. |

- **Cobble** is `Ground.COBBLE`, appended (D8): walkable at `COST_OPEN`, drawn
  with `ground_cobble.png`, and allowed under houses and depots
  (`allowed_grounds` bit 9). `LevelGenerator.set_ground_runtime` changes one
  tile and redraws it; the grid announces it, so pathing updates just that
  tile. The level save already stores ground per tile, so cobble persists
  with no save change.
- **The bucket** is a Craft item of the new shop kind `ITEM` (appended), a
  one-off (`max_level` 1) that leaves the shop once owned. Items are unlocks:
  crafting adds `"item:bucket"`, filling adds `"item:water_bucket"`.
- **Tile jobs.** `JobBoard` gains `FILL` (appended) and the priority
  build > repair > fill > cobble > chop. COBBLE and FILL list *grid tile
  indices*, not building ids (`JobBoard.is_tile_job`); `UnitStore.job` records
  which kind a builder's `target` is, so building removal never touches a
  tile job. A builder walks to a walkable tile next to the lava or water
  (`cells_to_building` with a 1x1 footprint), which is why cobbling works
  inward from the edge: a tile with no walkable neighbour waits.
- **Filling**: the player clicks the empty bucket in the item bar and then a
  water tile, exactly like placing a building — `BuildPlacer.start_tile` shows
  the same green/red ghost, cancels the same way, and emits `tile_picked`.
  That one tile is the FILL job (`LavaWorks.set_fill_target`, saved by cell);
  without it builders do not go looking for water. Only one builder takes it,
  and after `fill_work` (2) builder-seconds the water bucket exists for good.
- **Cobbling**: COBBLE lists marked lava only once the water bucket exists.
  `cobble_work` (3) builder-seconds per tile at `BUILD_SPEED`, up to 4
  builders per tile; a finished tile loses its mark.
- **Marking lava needs the bucket in hand.** Clicking the full bucket in the
  item bar starts `BuildPlacer.start_paint`: the ghost stays in hand and the
  placer reports each stroke (`paint_started`, `paint_moved`) until the player
  cancels. `main` marks every tile on the line between two mouse events, so a
  fast drag skips none; the first tile of a stroke decides whether that stroke
  marks or unmarks. Only free lava counts; clicking lava with empty hands does
  nothing.
- **Saved**: marks and progress by cell, and the fill progress; the bucket is
  in the unlocks.

### Planned: Stage 3b

**Fog of war (3b).** A `WorldGrid` layer, one byte per tile. Units reveal a
radius only when they cross into a new tile, never every frame. It is drawn as
one texture, one pixel per tile, updated per changed tile and laid over the
map by a shader: one draw call, no node per tile. Saved with the level. Things
under fog are neither drawn nor clickable.

**Points of interest (3b).** Placed by the generator, hidden by fog, and
interacted with by the explorer. Blueprints go to the run's unlock set; meta
currencies go to the permanent profile, which is why the profile migrates
rather than refuses (section 9).

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

Signals only; no state, no logic. **Implemented** so far:

    game_speed_changed(speed: float)
    resource_changed(kind: int, amount: int)      # ResourceKind.Id
    roster_changed(kind: int, count: int)         # WorkerRoster.Kind
    shop_purchased(item_id: String, purchases: int)

UI binds directly to the system objects main.gd hands it; these EventBus
mirrors exist for systems that should not hold a reference. **Planned:**

    # run lifecycle
    run_started, run_ended(victory: bool), base_destroyed
    day_started(day: int), night_started(day: int)

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

### What a run save holds, and load order

    level, clock, economy, roster, shop, modifiers, units

Load order is load-bearing: **shop purchases before modifiers**, because
rebuilding an upgrade's modifiers reads its level from the purchase count; and
**modifiers before the level**, because they are cheap to reject, so a run with
a missing upgrade is refused before the map is built. **Units after the
level**, because they refer to buildings by cell. On any failure `main.gd`
starts a new run, which resets everything that may have partly loaded.

Keys missing from older saves are additive where that is safe (a run from
before the economy gets the starting resources). Stage 2a moved `RUN_VERSION`
to 2: a run saved before units existed would load with miners on the roster but
no bodies, so older run saves are refused and a new run starts. The profile is
never refused.

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
