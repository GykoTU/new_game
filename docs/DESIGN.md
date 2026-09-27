# Game design

The designer's decisions about **what** the game is, collected in one place.
ARCHITECTURE.md covers **how** it is built; `mechanics-coverage.md` checks the
proposed combat mechanics against the architecture. When a decision here
changes, update it here first.

Status markers: **decided** · **proposed** (awaiting the designer) · **open**.

---

## Resources

Gold, quartz, copper, diamond, fruit — and **wood** (decided, not yet built).

Terrain gates what can be reached. Water, void and lava block movement, and the
generator places copper in water, quartz in void and gold in lava. At the start
of a run only **diamond mines (on ice), fruit trees and plain trees** are
reachable.

## The progression chain (decided)

1. **Builders chop trees** for wood. Plain trees (`tree`) spawn on regular
   grass. The player **marks** trees by clicking them; builders chop only
   marked trees, when nothing more urgent needs doing. Fruit trees can't be
   chopped.
2. Wood crafts a **bucket** — a one-off, there to teach crafting and that the
   world needs workarounds.
3. The player clicks the bucket in the item bar and clicks a water tile, the
   same way a building is placed; a builder then goes there and fills it
   **once**. It becomes a permanent **water
   bucket**, available to every builder. From then on, turning lava into
   cobble costs **builder time only** — no water trips, no resources. The
   bucket is a tutorial item: it teaches crafting and that the world needs
   workarounds.
4. Builders turn lava into **cobble**, a walkable ground type. To mark lava,
   the player takes the **water bucket** from the item bar (top left) and
   drags over lava with it in hand; starting a stroke on a marked tile unmarks
   instead. Builders cobble marked tiles they can reach, working inward from
   the edge.
5. Cobble opens the way to **gold mines**.

**Trees:** a chopped tree leaves a stump, the stump disappears after a while,
and a new tree grows later on a random grass tile. **Fruit is left out for
now** — fruit trees are scenery, and may return as a special-fruit point of
interest.

Later traversal unlocks follow the same pattern — find the blueprint, reshape
the map, reach the resource: **bridges** over water (to copper) and **void
crossings** (which cost copper, to quartz), both findable blueprints.

## Starting state of a run (decided)

- 100 gold (tunable).
- A **builder house** with a builder and a **carrier house** with a carrier,
  next to the base, free.
- **One miner, with no house.** It waits in the base. Sent to a mine, it
  walks out and mines outside it — visible and unprotected. When the first
  miner house is built it moves in; it also moves into any miner house it is
  sent to that has a free bed. If its house is destroyed, it flees to the
  base and commutes again. At night it walks home to the base and goes back
  to the same mine at dawn.
- Blueprints known: **bucket**, **depot**, **builder house**, **carrier
  house**, **miner house**.

## Units (decided)

| Unit | Bought with | Does |
|---|---|---|
| Miner | gold | Sent to a mine that has a miner house with a free bed; gathers while stationed in it. |
| Builder | gold | Builds, repairs, chops wood, fetches water for cobble. Never carries resources. |
| Carrier | gold | The only unit that carries resources: picks them up and brings them home (base, later a depot). |
| Explorer | gold | Sent out to explore the map. *(new, not yet designed in detail)* |

Workers are fragile in transit and safe once stationed. If a worker house is
destroyed, its miners flee to the base.

**Units are only seen when busy.** An idle unit stays inside its building (its
house, or the base for unsent miners) and comes out when it gets a task.

**Mining drops resources.** Each resource a miner produces bounces out of the
mine onto the ground nearby. Carriers walk over, pick drops up and carry them
to the base. A mine with 20 drops lying around pauses until some are picked
up. Player-set builder priorities are planned.

## Houses (decided)

- **Homes and workers are separate purchases.** Workers are bought with gold
  (Buy); homes cost resources (Craft, from 2b).
- **Miner house: crafted, one per mine.** Bought in the Craft tab (5 wood)
  for each mine, and placed from the building bar touching a mine that has
  none. It holds **3 miners** and is built by a builder. Bought miners can
  only be sent to a mine with a miner house that has a free bed.
- **Builder houses** and **carrier houses** hold **3** each. The starting ones
  are free; more are crafted.
- **No bed, no purchase:** while every builder, carrier or miner bed is taken,
  the shop greys out buying another, and says why. Miner beds are in finished
  miner houses, and the first miner counts against them too (even while it
  commutes), so miners never outnumber miner beds.
- Future upgrades raise occupancy, and the building visibly expands.

## Shop: Buy, Craft and Upgrades (decided)

The shop has three tabs:

- **Buy** — paid in **gold**: workers.
- **Craft** — paid in **resources**, two sub-tabs: **Utility** (houses,
  depot, watchtower, city hall, bucket, shovel) and **Weapons**.
- **Upgrades** — two sub-tabs, **Weapons** and **Workers**.

Crafted buildings and **every upgrade** need a **blueprint**; one blueprint
unlocks every level of an upgrade. Blueprints come from blueprint caches and
from enemies. They are **common** or **rare**: the one-off weapon upgrades are
rare, everything else is common. A weapon's upgrades only turn up once the
weapon is known. What isn't known is **hidden**. The shop scrolls, at most
three rows tall.

An enemy that drops a blueprint leaves a **cache** where it fell, glowing
**grey** (common) or **blue** (rare). The explorer brings it in by day; it
stays until then.

The **shovel** (an item, like the bucket): mark buildings, and a builder digs
each one out; half of what it cost to craft comes back. Not the base.
Sales work in both sections (a SHOP_PRICE modifier, already built).

## Buildings (decided)

- Crafted buildings go to the **building bar** on the left: one slot per
  building type with a count, in the order each type was first crafted. It
  always shows 5 slots; with more types, hovering it and holding Shift opens
  more columns to the right, partly transparent. Buildings are placed from
  there; builders then construct them.
- **City hall** (a blueprint to be found): gives the player control over task
  priorities — how many builders, miners and carriers prefer which jobs, like
  Palworld's monitoring stand. More control unlocks over the course of a run.
  Until then, priorities are fixed: build > repair > cobble > chop.
- **Depot** is the first craftable building: carriers deliver to the nearest
  depot instead of walking all the way to the base.

## Day and night (decided)

- A run is measured in **days**. **120 seconds of day, 60 seconds of night**
  (simulation time, so the cycle pauses and speeds up with the game). The run
  starts at dawn of day 1; the day number goes up at each dawn.
- **The world darkens at night**, easing in at dusk and out at dawn. The UI
  does not darken. Finished player buildings carry a **faint warm glow** so
  they stay readable in the dark; trees and mines do not.
- **At night everyone goes home** — except **builders, who still repair**.
  Repairing means leaving the house while enemies are out, which is the point:
  it is a risk the player chooses to take. Carriers leave dropped resources
  where they lie until morning, and **mines stand idle** — a miner sent to a
  mine after dusk moves in and sleeps, and produces nothing until dawn.
- **Waves come at night** and get stronger with the day number (Stage 4).
- The game **autosaves at dawn**.

## Enemies and nights (decided)

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
  second. Weapon buildings do the real work (below).
- **Dawn burns** every enemy still alive within a few seconds.
- A killed enemy sometimes drops a **blueprint** the run doesn't know yet.

## Weapons (decided)

- **Seven weapon buildings**, built like any other building (crafted, then
  placed and built by a builder):
  - **Arrow tower** — fast arrows that pierce one enemy. Every run knows it.
  - **Cannon** — slow shells that explode where they land and fling enemies
    back. Aims at the enemy closest to what it is attacking.
  - **Frost tower** — bolts that slow what they hit.
  - **Flame tower** — short-range flames that set enemies alight; some leave
    the ground burning for a few seconds.
  - **Hook tower** — hooks the strongest enemy in range and drags it in.
  - **Chain cannon** — fires two chained cannonballs at an enemy. They fly
    their full range, past the target, hurt nothing, but catch the enemies
    in their path (up to 6), drag them along stunned and drop them stunned
    for 2 s where the flight ends.
  - **Whirl tower** — blades circling it while enemies are near.
- The other six are **found**: blueprint caches and enemy drops teach them in
  a random order, so every run's arsenal differs.
- **Upgrades** are in the shop's Upgrades tab once their blueprint is found
  and the weapon is known: number upgrades (more pierce, bigger blasts, more
  enemies caught...) and rare **behaviour upgrades** that change what the
  shots do: split arrows (they split at the first enemy they hit), seeking
  arrows, bouncing shells, volatile foes (enemies the cannon kills explode),
  a chilling chain for frost, cinders (enemies that burn to death explode),
  and a paying-out chain for the chain cannon (the chain lengthens as it
  flies, sweeping a wider path).
- **Target mode per building**: click a weapon to see its range and choose
  what it shoots: nearest, strongest, or first (closest to the building it is
  attacking). The whirl tower doesn't aim.
- **Friendly fire**: shots, blasts and burning ground hurt workers who are
  outside. Where weapons stand, and where workers walk at night, matters.
- **Walls** (Stage 6) will stop shots and shield from blasts; a flung enemy
  that hits a wall is hurt.

## Walls, gates and roads (decided)

- **Walls** and **roads** are known from the start; **bridges** (over water)
  and **void crossings** are found. All four are tools in a bar in the
  bottom-right corner: drag to paint, each tile is paid at once, and builders
  build them. Start a stroke on something not yet built to take it back.
- **Walls** stop enemies, workers and shots. Enemies never target a wall, but
  break through one when it's in their way.
- **Gates** (hold Shift while painting walls) let your workers through, day
  and night. By day they are open; at night they close and enemies must break
  them. A gate is the **weak point**: half a wall's health, and enemies go a
  few tiles out of their way to attack it rather than a wall.
- **You may seal your base in completely.** Without a gate, your workers
  can't get out either.
- **Roads** make your workers walk faster (1.6x). Enemies ignore them.

## Progression: levels and augments (decided)

- You earn **XP** once your base stands: from **kills** (tougher enemies are
  worth more), from **exploring** (revealing the map, opening points of
  interest) and from **surviving** (a slow trickle, and a bonus at every
  dawn that grows with the night number).
- Each **level** pauses the game and offers **three augments**. Pick one,
  **reroll** once for three new ones, or **skip** for gold.
- **Commons** stack up to 5 times: weapon stats, worker and economy boosts,
  building and defence health. **Rares** can be taken once and change a
  rule (enemies explode on death, fires spread, shots spare your workers...).
- Offers **lean toward what you already have**: an augment sharing a tag with
  ones you own is more likely. Some rares only appear once you own enough of
  their tag (Wildfire needs two fire augments).
- Several level-ups at once queue up and are picked one after another.

## Relic tree (decided)

- **Relics** are spent between runs on the **relic tree**, from the title
  screen. You earn them from **relic caches** and when your base falls:
  **one per night survived** plus **one per three levels** reached.
- The tree grows from **the Hearth** in four branches: **Arms** (weapons),
  **Hands** (workers and economy), **Walls** (defence) and **Paths**
  (exploration and level-ups). A node can be bought once a neighbour is
  owned; a **synergy node** between two branches needs both.
- Nodes can make you stronger (more damage, more base health), start runs
  better (gold, a second builder, knowing the cannon), **unlock content**
  (the whirl tower and the Wildfire augment only appear once bought) and
  change rules (an extra reroll, four augment cards, more relics per cache).
- **Refunds are free and total**: one button gives every relic back.
- A run keeps the tree it started with; changes apply to the next run.

## The end of a run (decided)

- The run ends when **the base is destroyed**. Nothing else ends it.
- Time stops, the run save is deleted, and a **summary** appears over the
  frozen world: days survived, time, workers, resources, and the best day
  reached across all runs. One button: **Return to title**.
- The permanent profile keeps `runs_started`, `runs_ended`, `best_day` and
  total time played. Meta currency joins it later (Stage 8).

## Exploration (decided)

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
  - a **blueprint cache** teaches a blueprint the run doesn't know yet, at
    random: the **watchtower**, the **city hall** or one of the six findable
    **weapons**; once all are known it holds relics instead;
  - a **relic cache** holds 1–3 **relics**;
  - an **NPC living in a house** and a **special fruit tree** are placeholders
    for now: visited once, they only show a message. *Their effects are open.*
- **Relics** are the meta currency. They are kept across runs in the profile
  (spent on the relic tree) and count once the run is saved — at dawn, on quitting,
  or when the base falls.
- **Watchtower**: a crafted building that clears the fog far around it (12
  tiles) once built. **City hall**: found and placeable; its priorities
  screen comes later.

---

## Future ideas (not yet scheduled)

- Assignable builder tasks.
- House occupancy upgrades, with the building growing.
- Fruit as a special-fruit point of interest.

## Open questions

None at the moment.
