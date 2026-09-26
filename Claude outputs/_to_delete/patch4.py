import io

def patch(path, pairs):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path + " anchor not unique: " + old[:70])
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print("patched", path)

D10 = """### D10 — Hot-loop data are the system's own members
`EnemySystem` **extends** `EnemyStore` rather than holding one. GDScript reads a
script's own member arrays about 2.7x faster than the same arrays through
another object (`store.pos[e]`): measured, 16 reads for 500 enemies cost
0.68 ms through an object and 0.26 ms as members. The enemy loop reads a
dozen arrays per enemy per tick, so this alone took it from 2.05 ms to
0.75 ms for 500 enemies. The store's methods are named so they cannot collide
(`alloc`/`release`, `reset_pool`, `alive_count`). Use the same shape for the
projectile store in Stage 5. Units keep a separate store: their counts are
small enough that clarity wins.

---

## 4. Runtime structure"""

STAGE4 = """### Enemies, waves and the base's zap (implemented, Stage 4)

**Diagram: [`docs/enemies.svg`](docs/enemies.svg)** — a night from dusk to
dawn, how a flow field is built and read, and one enemy's tick.

Files: `enemies/` (`enemy_data.gd`, `enemy_store.gd`, `enemy_system.gd`,
`flow_field.gd`, `flow_fields.gd`, `waves.gd`, `base_defence.gd`,
`enemy_renderer.gd`, `combat_effects.gd`), `game/spatial_hash.gd`,
`game/health_bars.gd`, `data/enemies/*.tres`.

- **Kinds are data.** `EnemyData` resources (goblin, bee): health, speed,
  damage, attack interval, aggro range, flying, spawn cost, first night,
  blueprint drop chance, sprite paths. Saves refer to them by `id`.
- **Store.** Parallel arrays, preallocated to `EnemyStore.CAP` (600) and never
  grown: a spawn beyond the cap is dropped. `EnemySystem` extends it (D10).
- **Flow fields (D5).** `FlowFields` keeps two enemy cost layers, one byte per
  tile, in step with the grid: 0 = impassable (water, lava, void for walkers;
  trees, mines, stumps and points of interest for everyone), 10/14 = ground,
  `BREAK_COST` 250 = a player building. `dist[n]` is the cost to the target
  *counting n itself*, so an enemy compares neighbours directly and a building
  in the way costs what breaking it takes (about 24 tiles of walking). Built
  by Dijkstra with a bucket queue (Dial's algorithm) — buckets are linked
  lists in flat packed arrays, because a packed array stored in an Array is
  copied on every write. **Built in slices** (800 tiles a tick, ~1.5 ms)
  into a back buffer while enemies keep the old one. At most 8 fields (target
  × ground/flying); a field nobody planned with for 3 s is evicted when a
  slot is needed. A grid change rebuilds every field and bumps `generation`,
  which makes every enemy re-plan its next step at once.
- **Moving.** An enemy re-plans only when it enters a new tile or
  `generation` moved: it picks the cheapest neighbour (no cutting corners)
  and walks at its centre plus a fixed small `lane` offset, so a crowd does
  not collapse into one sprite. If that neighbour is a player building, it
  hits it instead — that is how enemies break through. Following its planned
  tile it skips the collision test; otherwise (pushed, chasing a worker, no
  field yet) the tile it would enter must not be solid, sliding along one
  axis if the other is blocked.
- **Targets.** `score = pull / (distance_in_tiles + target_k)` with
  `target_k` 8, where `pull` is the building's `threat_priority` plus half of
  what stands within 3 tiles of it — so a cluster of houses can outrank a
  lone, distant base. Base 10, miner house 4, houses and depot 3, watchtower
  2, city hall 5; construction sites count half. Re-chosen every 3 s
  (staggered) and at once when the target dies. A target without a field is
  only chosen while a slot is free.
- **Workers.** An exposed worker (outside, not stationed) within
  `aggro_range` is chased and hit; worker-centric search, because few workers
  are out at night against many enemies. At 0 health it dies for good
  (`UnitSystem.kill_unit`): what it carried is lost, its claims are
  released, its bed is free. Inside a building it is safe.
- **Buildings** take damage and are removed at 0 (`level.remove_building`),
  with all the usual consequences: miners flee, the base falling ends the
  run. Builders repair them, at night too. Health bars show over damaged
  player buildings and hurt workers.
- **Status slots**: `apply_slow` / `apply_burn`, one slot each, strongest
  wins, an equal one refreshes the duration, a weaker one is ignored; slow is
  capped at 0.9. **Impulses**: `apply_impulse` adds to a velocity offset that
  halves every 0.15 s; the grid still stops it. Running into something solid
  faster than 60 px/s emits `wall_impact(id, speed)`, into an exposed worker
  `unit_impact(id, unit, speed)` — the enemy-side movement events weapons need
  (docs/mechanics-coverage.md).
- **Waves** (`Waves`). At dusk the whole night is planned: budget 6 + 4 per
  night, from 1 edge (2 from night 3, 3 from night 6), in groups of 3–5 over
  the first 15 s. Bees from night 2. From night 3 a night is a *swarm* (x1.6
  count, x0.6 health, bee-heavy), *elite* (x0.55, x2.0) or plain *mixed*;
  health grows 15% a night. The plan is a queue saved with the run. A toast
  names the sides. Spawn points are free tiles at most 3 in from the edge.
- **Dawn** cancels whoever has not set out and sets every enemy burning
  (`burn_all`): all dead within 2.5 s. Burning is not a kill: no drops.
- **The base's zap** (`BaseDefence`): the nearest enemy within `RANGE`, every
  `1 / FIRE_RATE` s, for `DAMAGE` — ordinary stats on a StatBlock tagged
  `building`, `base`, `weapon` (12 damage, 1.25/s, 176 px), so modifiers
  reach it. It fires the moment something comes in range. The bolt is drawn
  with the night tint divided out, like the building glow: it is light.
- **Blueprint drops**: a kill by the player (not by dawn) teaches the next
  `Unlocks.FINDABLE` blueprint with the kind's `blueprint_drop_chance`
  (goblin 3%, bee 2%). Stage 5 adds weapon blueprints to that list.
- **Spatial hash** (`SpatialHash`): counting sort into 2-tile cells, rebuilt
  every tick (0.29 ms for 500). Used for the zap, worker aggro and impacts;
  Stage 5 projectiles will query it.
- **Order** in `_simulate`: director, waves, units, fog, enemies, defence,
  forest. The zap runs after the enemies, on the hash they just built.
- **Rendering.** One MultiMesh per (kind, animation), y-sorted; the shader
  shows the hit flash and the burn tint. Missing walk/attack sheets are
  skipped (never a placeholder). `CombatEffects` draws bolts, deaths and the
  optional burn overlay; every effect sprite is optional.
- **Measured**: 500 enemies, 0.75 ms per tick for their loop, about 1.4 ms per
  tick with the hash, units and zap. At 4x speed that is about 11 ms of
  simulation per frame; above that the clock's tick cap slows the game down
  rather than stalling it.
- **Saved**: enemies (kind by id, position, health, burn, slow) and tonight's
  queue. Targets and routes are recomputed after loading.

"""

patch('ARCHITECTURE.md', [
 ("""---

## 4. Runtime structure""", D10),
 ("""### Progression
Global XP from kills""", STAGE4 + """### Progression
Global XP from kills"""),
 ("""**Ctrl+F** reveal the whole
map, **Ctrl+K** destroy the base""", """**Ctrl+F** reveal the whole
map, **Ctrl+E** spawn 10 goblins at the map edge nearest the camera (they do
not burn by day), **Ctrl+K** destroy the base"""),
 ("""    unlocks, inventory, forest, lava, director, poi
""", """    unlocks, inventory, forest, lava, director, poi, enemies, waves
"""),
])

patch('TODO.md', [
 ("""## Stage 4 — Enemies

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
""", """## Stage 4 — Enemies

- [x] Enemy SoA store (cap 600, spawns dropped when full) +
      `MultiMeshInstance2D` rendering, hit flash, burn tint
- [x] Spatial hash for enemy/unit broadphase, rebuilt every tick
- [x] Edge spawning, wave composition per night (budget, sides, shapes:
      swarm / elite / mixed), toast at dusk
- [x] Flow field cache (8 slots, ground and flying), built in slices
- [x] Target scoring by `threat_priority`, cluster pull and distance
- [x] Enemies break through player buildings when they block the way
- [x] Building damage and destruction; health bars
- [x] Workers can be caught and killed; bed freed
- [x] The base fights back (zap: stats DAMAGE / FIRE_RATE / RANGE)
- [x] Dawn burns every enemy left
- [x] Enemies drop blueprints (findable pool; weapons join in Stage 5)
- [x] Impulse channel, respecting the grid
- [x] Enemy movement events: `wall_impact`, `unit_impact`
- [x] Status slots per enemy (slow, burn): strongest wins, duration refreshes
- [x] Dev shortcut: Ctrl+E spawns 10 goblins at the nearest edge
- [ ] Balancing after play-testing: night length vs travel time from the
      edges, wave budget, zap numbers, base health (500)
- [ ] Enemies are hard to see at night (the tint darkens them too); decide
      whether they should get a faint outline or glow
"""),
 ("""**3b**
- [x] `assets/npcs/explorer.png` — or a horizontal strip of 32x32 frames""", """**4** (all optional)
- [x] `assets/npcs/goblin.png`, `assets/npcs/bee.png` — already there
- [ ] `assets/npcs/goblin_walk.png`, `assets/npcs/goblin_attack.png` — strips
- [ ] `assets/npcs/bee_attack.png` — strip (`bee.png` can be the wing-flap strip)
- [ ] `assets/effects/zap_hit.png` — strip where a zap lands
- [ ] `assets/effects/enemy_death.png` — strip; without it, a fading ring
- [ ] `assets/effects/burn.png` — flame over burning enemies; without it, the tint

**3b**
- [x] `assets/npcs/explorer.png` — or a horizontal strip of 32x32 frames"""),
])

patch('docs/DESIGN.md', [
 ("""## The end of a run (decided)""", """## Enemies and nights (decided)

- **Enemies come at night**, from 1–3 map edges (more sides on later
  nights), announced at dusk: "Enemies approach from the north and east."
- **Goblins** walk; **bees** are fast and fragile and fly over water, lava
  and void. Buildings stop both — walls block everything.
- Nights grow stronger with the day and change **shape**: from night 3 a
  night is a swarm (many, fragile, bee-heavy), an elite night (few, tough) or
  a mix.
- Enemies choose what to attack by value and distance: the base is worth
  most, but a nearby **cluster** of houses can draw them away. A building
  standing in their way gets smashed; they go around if the detour is short.
- A worker out in the open (a builder repairing at night) gets chased and
  hit, and **dies** at 0 health — it is gone, and its bed is free again.
- **The base fights back**: it zaps the nearest enemy in range about once a
  second. Weapon buildings come in Stage 5.
- **Dawn burns** every enemy still alive within a few seconds.
- A killed enemy sometimes drops a **blueprint** the run doesn't know yet.

## The end of a run (decided)"""),
])

patch('ARCHITECTURE.md', [
 ("""Implemented in Stage 3: the day counter and the day/night phases (see "Day,
night and the end of a run" below). Still to come with enemies (Stage 4): wave
composition per night.""", """Implemented in Stage 3: the day counter and the day/night phases (see "Day,
night and the end of a run" below). Wave composition per night lives in
`Waves` (Stage 4, see "Enemies, waves and the base's zap")."""),
])
