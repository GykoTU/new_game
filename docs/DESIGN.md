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
   grass. Idle builders chop on their own.
2. Wood crafts a **bucket** — a one-off, there to teach crafting and that the
   world needs workarounds.
3. A builder fills it **once** at water. It becomes a permanent **water
   bucket**, available to every builder. From then on, turning lava into
   cobble costs **builder time only** — no water trips, no resources. The
   bucket is a tutorial item: it teaches crafting and that the world needs
   workarounds.
4. Builders turn lava into **cobble**, a walkable ground type.
5. Cobble opens the way to **gold mines**.

**Trees:** a chopped tree leaves a stump, the stump disappears after a while,
and a new tree grows later on a random grass tile. **Fruit is left out for
now** — fruit trees are scenery, and may return as a special-fruit point of
interest.

Later traversal unlocks — boats over water, bridges over void — follow the same
pattern: craft the tool, reshape the map, reach the resource.

## Starting state of a run (decided)

- 100 gold (tunable).
- Three houses next to the base, each with one worker inside: a **builder
  house** with a builder, a **carrier house** with a carrier, and a **miner
  home** with a miner.
- The starting miner **commutes**: sent to a mine, it walks out and mines
  outside it — visible and unprotected, and it costs nothing. It moves into
  a mine's miner home when sent to one with a free bed. If that home is
  destroyed, it goes back to its house by the base. (Later, with day/night,
  it walks home at night.)
- Blueprints known: **bucket**, **depot**, **builder house**, **carrier house**.

## Units (decided)

| Unit | Bought with | Does |
|---|---|---|
| Miner | gold | Sent to a mine; gathers while stationed in that mine's miner home. |
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
- **One miner home per mine**, holding **3 miners**, built by a builder. It is
  paid for when a bought miner is assigned to a mine that has none (for now
  5 diamonds, a placeholder until wood exists). Can't afford it: the miner
  isn't sent, and the reason is shown.
- **Builder houses** and **carrier houses** hold **3** each. The starting ones
  are free; more are crafted (2b).
- **No bed, no purchase:** while every builder (or carrier) bed is taken, the
  shop greys out buying another, and says why.
- Future upgrades raise occupancy, and the building visibly expands.

## Shop: Buy and Craft (decided)

The shop has two sections:

- **Buy** — paid in **gold**: NPCs and upgrades.
- **Craft** — paid in **resources**: buildings (depot, roads, walls, weapons)
  and items (bucket).

Crafting needs a **blueprint**. Enemies and points of interest award
blueprints. Sales work in both sections (a SHOP_PRICE modifier, already built).

## Buildings (decided)

- Crafted buildings go to the **building bar**, in the order they were crafted,
  and are placed from there. Builders then construct them.
- **Depot** is the first craftable building: carriers deliver to the nearest
  depot instead of walking all the way to the base.

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
