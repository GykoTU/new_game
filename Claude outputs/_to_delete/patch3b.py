import io

def patch(path, pairs):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path + " anchor not unique: " + old[:70])
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print("patched", path)

STAGE3B = """### Exploration: fog, the explorer, points of interest (implemented, Stage 3b)

**Diagram: [`docs/exploration.svg`](docs/exploration.svg)** — the start
clearing, how tiles get explored, the explorer's decision order, and what each
point of interest gives.

**Fog of war.** `WorldGrid.explored`, one byte per tile, saved with the level
(deflate-compressed: 10 000 tiles save as about 80 bytes). Two states only:
seen or never seen. Nothing is re-hidden when a unit walks away; a "currently
in sight" layer for enemies can come in Stage 4 as a second layer without
touching this one.

- **Stored as 0 / 255, not 0 / 1**, so `FogRenderer` hands the array to an L8
  image as it is: one native copy per rebuild, no per-pixel GDScript loop.
- **A fresh `WorldGrid` is fully explored.** Only `LevelGenerator.generate()`
  fogs a map, so hand-built maps (every test world) and a run saved before fog
  existed stay fully visible. Hiding a map the player has already seen would
  take something away.
- **The start clearing.** A new map is dark except a disc around the map
  centre (`start_reveal_radius` 10). The generator keeps `start_open_radius`
  (5) of plain grass there for the base, always places a small ice patch with a
  **diamond mine** just inside the disc (the one mine reachable from the
  start), and tops the disc up to `start_trees` (6) trees. The camera opens on
  it. The base has to go inside because **`can_place` refuses unexplored
  tiles**, for every building.
- **Nothing under fog can be used**: tree marking, sending a miner to a mine,
  lava marks, the bucket's water tile and every placement check `explored`.
- **Revealing.** `FogOfWar.step_units` runs after the units each tick. Only
  WALKING units are looked at, and only when they cross into a new tile
  (`_last` per unit id), so a unit standing still or walking known ground
  costs one compare. World-to-cell is plain arithmetic here, not
  `world_to_cell` (two engine calls through the TileMapLayer): 200 walking
  units cost about 0.2 ms per tick. Workers reveal 2 tiles, the explorer 6.
  A finished building with `BuildingData.reveal_radius` reveals once (the
  watchtower, 12).
- **Drawing.** One `Sprite2D` stretched over the map, one texture pixel per
  tile, linear filtering for a soft edge, and a shader that doubles the fog's
  slope so it is fully opaque by the *boundary* of the first hidden tile: a
  hidden tile is never partly visible, only the outer half of the last
  explored tile is shaded. `z_index` 2: over buildings, units and the night
  glow, under the placer's ghost. Rebuilt at most once a frame, only after a
  reveal; not drawn at all once nothing is hidden.

**The explorer** (`WorkerRoster.Kind.EXPLORER`, appended per D8). Bought with
gold; needs a bed in an **explorer house** (crafted, known from the start,
`BuildingData.beds` = 1 — a new field that sets a house type's base
HOUSE_CAPACITY). Click its worker-bar slot, then click anywhere, fog included.

- `UnitPathing.cells_toward` asks A* for a **partial path**: all the way if the
  spot is reachable, otherwise to the reachable tile closest to it. A click on
  a lake ends at the shore.
- `UnitStore.goal` holds the tile index it was sent toward. Its think order:
  a spotted point of interest (the detour), then the goal, then home. When a
  point of interest is spotted, explorers out exploring stop and re-think at
  once (`on_poi_spotted`), so the detour happens as it comes into view.
- **Night:** it turns back at dusk, *keeping* its goal, and sets out again at
  dawn, like the commuter. It can't be sent at night.
- Two explorers never go to the same point of interest; an unreachable one is
  left alone for 10 s (`POI_RETRY_TICKS`) rather than re-searched three times
  a second, because a failed A* search covers the whole reachable map.
- `ExploreFlags` draws a flag at each goal, over the fog, **only if**
  `assets/ui/explore_flag.png` exists: a grey placeholder square floating in
  the fog would read as a bug.

**Points of interest** (`Level/points_of_interest.gd`). The generator places
them as ordinary buildings of type `poi_*` on free grass, at least
`poi_min_distance` (16) from the centre and `poi_spacing` (8) apart; their
sprites load through `Art`, so an undrawn one shows the placeholder instead
of failing the level. **Spotted** means "its tile is explored" — not saved,
derived from the fog on load. **Opened** means the explorer stood beside it
for `open_seconds` (3; `UnitStore.State.OPENING`, finishing at `think_at`).

| Type | Gives | Afterwards |
|---|---|---|
| `poi_blueprint_cache` | the next `Unlocks.FINDABLE` blueprint (watchtower, then city hall); 2 relics once both are known | removed |
| `poi_relic_cache` | 1–3 relics | removed |
| `poi_npc_house` | a placeholder message | stays, visited once |
| `poi_fruit_tree` | a placeholder message | stays, visited once |

**Relics** are the meta currency, kept in the profile (`profile["relics"]`,
a new default key, so no migration). **They are written to the profile only
when the run is saved**: `save_run()` takes the pending relics and banks them
right after the run save that no longer holds their caches, and death banks
the rest. Writing them at once would let a player open a cache, quit without
saving, reload the dawn save and open it again. If the run save fails, the
relics go back to pending. The run summary lists relics found; the title
screen shows the total once there is one.

**Watchtower and city hall** are the findable blueprints. The watchtower is a
`reveal_radius` 12 building; the city hall is unique and does nothing yet.

"""

patch('ARCHITECTURE.md', [
 ("""| `cost` | `PackedByteArray` | derived | movement cost; `255` = impassable |
""",
  """| `cost` | `PackedByteArray` | derived | movement cost; `255` = impassable |
| `explored` | `PackedByteArray` | source | fog of war: `0` hidden, `255` explored (Stage 3b) |
"""),
 ("""### Planned: Stage 3b

**Fog of war (3b).** A `WorldGrid` layer, one byte per tile. Units reveal a
radius only when they cross into a new tile, never every frame. It is drawn as
one texture, one pixel per tile, updated per changed tile and laid over the
map by a shader: one draw call, no node per tile. Saved with the level. Things
under fog are neither drawn nor clickable.

**Points of interest (3b).** Placed by the generator, hidden by fog, and
interacted with by the explorer. Blueprints go to the run's unlock set; meta
currencies go to the permanent profile, which is why the profile migrates
rather than refuses (section 9).

""", STAGE3B),
 ("""stat, live), **Ctrl+T** skip to dusk or dawn, **Ctrl+K** destroy the base""",
  """stat, live), **Ctrl+T** skip to dusk or dawn, **Ctrl+F** reveal the whole
map, **Ctrl+K** destroy the base"""),
 ("""    unlocks, inventory, forest, lava, director
""", """    unlocks, inventory, forest, lava, director, poi
"""),
])

patch('TODO.md', [
 ("""## Stage 3b — Exploration

- [ ] Fog of war: the map is hidden until explored; explored tiles saved
- [ ] Explorer NPC (bought with gold), sent out to reveal the map
- [ ] Points of interest, hidden under fog, holding: blueprints, meta
      currency, an interactable NPC living in a house, a tree with special
      fruit
""", """## Stage 3b — Exploration

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
"""),
 ("""**2c**
- [x] `assets/ground/ground_cobble.png`
- [x] `assets/ui/bucket_empty.png` — before the one-time fill
- [x] `assets/ui/bucket_full.png` — the permanent water bucket
""", """**2c**
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
- [ ] `assets/buildings/poi/fruit_tree.png`
- [ ] `assets/ui/relic.png`
- [ ] `assets/ui/explore_flag.png` — optional; without it no marker is drawn
"""),
 ("""- [ ] Meta currencies found at points of interest feed Stage 8""",
  """- [ ] Relics (found at points of interest since 3b) feed Stage 8"""),
])

patch('docs/DESIGN.md', [
 ("""## Exploration (decided)

- **Fog of war**: the map is hidden until explored.
- An **explorer** NPC is sent out to reveal it.
- **Points of interest** hide under the fog. They can hold meta currencies,
  an interactable NPC living in a house, a tree with special fruit, and
  blueprints.
""", """## Exploration (decided)

- **Fog of war**: the map is hidden until explored. A run starts with a
  **clearing** around the map centre revealed; it always holds trees and an
  ice patch with a diamond mine, and the base must be placed inside it.
  Nothing under the fog can be clicked, marked or built on.
- Every worker reveals a little as it walks (2 tiles). The **explorer**
  reveals a lot (6).
- **Explorer**: bought with gold, lives in an **explorer house** (crafted
  from wood, 1 bed). Click its slot, then click anywhere, fog included: it
  walks as close to that spot as it can get, then comes home. It doesn't go
  out at night; sent out before dusk, it turns back and finishes the trip at
  dawn.
- **Points of interest** hide under the fog. When one comes into view the
  explorer detours to it on its own, spends 3 seconds, and:
  - a **blueprint cache** teaches the **watchtower**, then the **city hall**;
    once both are known it holds relics instead;
  - a **relic cache** holds 1–3 **relics**;
  - an **NPC living in a house** and a **special fruit tree** are placeholders
    for now: visited once, they only show a message. *Their effects are open.*
- **Relics** are the meta currency. They are kept across runs in the profile
  (spent in Stage 8) and count once the run is saved — at dawn, on quitting,
  or when the base falls.
- **Watchtower**: a crafted building that clears the fog far around it (12
  tiles) once built. **City hall**: found and placeable; its priorities
  screen comes later.
"""),
])
