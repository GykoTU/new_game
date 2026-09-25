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

Later traversal unlocks — boats over water, bridges over void — follow the same
pattern: craft the tool, reshape the map, reach the resource.

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

## Shop: Buy and Craft (decided)

The shop has two sections:

- **Buy** — paid in **gold**: NPCs and upgrades.
- **Craft** — paid in **resources**: buildings (depot, roads, walls, weapons)
  and items (bucket).

Crafting needs a **blueprint**. Enemies and points of interest award
blueprints. Items without a known blueprint are **hidden** from the Craft tab.
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

## The end of a run (decided)

- The run ends when **the base is destroyed**. Nothing else ends it.
- Time stops, the run save is deleted, and a **summary** appears over the
  frozen world: days survived, time, workers, resources, and the best day
  reached across all runs. One button: **Return to title**.
- The permanent profile keeps `runs_started`, `runs_ended`, `best_day` and
  total time played. Meta currency joins it later (Stage 8).

## Exploration (decided)

- **Fog of war**: the map is hidden until explored.
- An **explorer** NPC is sent out to reveal it.
- **Points of interest** hide under the fog. They can hold meta currencies,
  an interactable NPC living in a house, a tree with special fruit, and
  blueprints.

---

## Future ideas (not yet scheduled)

- Assignable builder tasks.
- House occupancy upgrades, with the building growing.
- Fruit as a special-fruit point of interest.

## Open questions

None at the moment.
