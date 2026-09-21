class_name WorldGrid
extends RefCounted
## Every per-tile array for one map. Flat, indexed `y * size.x + x`.
##
## Systems that need to know what is where -- pathing, projectile traversal,
## placement checks, unit steering -- read this, not the generator that filled
## it. LevelGenerator writes the terrain; WorldGrid owns it afterwards.
##
## Every accessor comes in two forms: a Vector2i form for clarity, and a raw
## index form for hot loops that already hold the index. Hot code should use the
## index form and never build a Vector2i just to read one tile.

enum Ground { GRASS_1, GRASS_2, GRASS_3, FLOWERS, ICE, LAVA, WATER, SAND, VOID }

## Bit flags in `blocking`.
const BLOCKS_UNIT := 1 << 0
const BLOCKS_PROJECTILE := 1 << 1
const IS_ROAD := 1 << 2

## Value in `occupancy` meaning "no building here".
const NO_OCCUPANT := -1

## Movement costs, kept as whole numbers so roads can undercut open ground
## without fractions. 255 means impassable, never merely expensive -- pathing
## must treat it as a wall rather than as a route worth considering.
const COST_IMPASSABLE := 255
const COST_OPEN := 10
const COST_ROUGH := 14
const COST_ROAD := 4

## Terrain rules. Water, void and lava block movement: reaching the copper,
## quartz and gold mines is meant to require boats, bridges and (eventually)
## hauling water to cool lava. That gate is the point, not an obstacle to it.
const GROUND_BLOCKING := {
	Ground.GRASS_1: 0,
	Ground.GRASS_2: 0,
	Ground.GRASS_3: 0,
	Ground.FLOWERS: 0,
	Ground.SAND: 0,
	Ground.ICE: 0,
	Ground.LAVA: BLOCKS_UNIT,
	Ground.WATER: BLOCKS_UNIT,
	Ground.VOID: BLOCKS_UNIT,
}

const GROUND_COST := {
	Ground.GRASS_1: COST_OPEN,
	Ground.GRASS_2: COST_OPEN,
	Ground.GRASS_3: COST_OPEN,
	Ground.FLOWERS: COST_OPEN,
	Ground.SAND: COST_ROUGH,
	Ground.ICE: COST_ROUGH,
	Ground.LAVA: COST_IMPASSABLE,
	Ground.WATER: COST_IMPASSABLE,
	Ground.VOID: COST_IMPASSABLE,
}

var size := Vector2i.ZERO

## Terrain type per tile. A byte, not an int32: nine values fit in one, and at
## 256x256 that is 65 KB instead of 256 KB of cache traffic.
var ground := PackedByteArray()
## Building id per tile, or NO_OCCUPANT. Multi-tile buildings write their id to
## every tile they cover, so a lookup from any covered tile finds the building.
var occupancy := PackedInt32Array()
## Derived: ground flags OR the occupying building's flags.
var blocking := PackedByteArray()
## Derived: the occupant's cost if occupied, otherwise the terrain's.
var cost := PackedByteArray()

## The occupant's own contribution, stored rather than recomputed so that
## changing terrain under a building, or a building over terrain, gives the same
## answer in either order. Two bytes per tile buys order-independence, which is
## worth more than the memory once several systems write to the grid.
var _occupant_blocking := PackedByteArray()
var _occupant_cost := PackedByteArray()


func _init(map_size := Vector2i.ZERO) -> void:
	if map_size != Vector2i.ZERO:
		resize(map_size)


## Allocates every layer and resets the map to open grass.
func resize(map_size: Vector2i) -> void:
	size = map_size
	var n := size.x * size.y
	ground.resize(n); ground.fill(Ground.GRASS_1)
	occupancy.resize(n); occupancy.fill(NO_OCCUPANT)
	blocking.resize(n); blocking.fill(0)
	cost.resize(n); cost.fill(COST_OPEN)
	_occupant_blocking.resize(n); _occupant_blocking.fill(0)
	_occupant_cost.resize(n); _occupant_cost.fill(0)


func tile_count() -> int:
	return size.x * size.y


# --- Index maths --------------------------------------------------------------

func index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func cell_at(i: int) -> Vector2i:
	# Integer division is the point: the row is how many whole rows fit in i.
	@warning_ignore("integer_division")
	return Vector2i(i % size.x, i / size.x)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


# --- Terrain ------------------------------------------------------------------

func get_ground(cell: Vector2i) -> int:
	return ground[cell.y * size.x + cell.x]


func get_ground_at(i: int) -> int:
	return ground[i]


func set_ground(cell: Vector2i, g: int) -> void:
	set_ground_at(cell.y * size.x + cell.x, g)


func set_ground_at(i: int, g: int) -> void:
	ground[i] = g
	_derive(i)


func is_grass(g: int) -> bool:
	return g == Ground.GRASS_1 or g == Ground.GRASS_2 or g == Ground.GRASS_3


# --- Occupancy ----------------------------------------------------------------

func get_occupant(cell: Vector2i) -> int:
	return occupancy[cell.y * size.x + cell.x]


func get_occupant_at(i: int) -> int:
	return occupancy[i]


func is_occupied(cell: Vector2i) -> bool:
	return occupancy[cell.y * size.x + cell.x] != NO_OCCUPANT


## Marks one tile as covered by a building and folds its flags into the derived
## layers. `cost_value` of 0 means "leave the terrain's cost alone".
func claim(i: int, building_id: int, block_flags: int, cost_value: int = 0) -> void:
	occupancy[i] = building_id
	_occupant_blocking[i] = block_flags
	_occupant_cost[i] = cost_value
	_derive(i)


func release(i: int) -> void:
	occupancy[i] = NO_OCCUPANT
	_occupant_blocking[i] = 0
	_occupant_cost[i] = 0
	_derive(i)


# --- Queries for gameplay systems ---------------------------------------------

func blocks_unit(cell: Vector2i) -> bool:
	return (blocking[cell.y * size.x + cell.x] & BLOCKS_UNIT) != 0


func blocks_unit_at(i: int) -> bool:
	return (blocking[i] & BLOCKS_UNIT) != 0


func blocks_projectile(cell: Vector2i) -> bool:
	return (blocking[cell.y * size.x + cell.x] & BLOCKS_PROJECTILE) != 0


func blocks_projectile_at(i: int) -> bool:
	return (blocking[i] & BLOCKS_PROJECTILE) != 0


func get_cost(cell: Vector2i) -> int:
	return cost[cell.y * size.x + cell.x]


func get_cost_at(i: int) -> int:
	return cost[i]


func is_passable_at(i: int) -> bool:
	return cost[i] != COST_IMPASSABLE and (blocking[i] & BLOCKS_UNIT) == 0


# --- Derivation ---------------------------------------------------------------

## Recomputes the derived layers for one tile from its two inputs.
func _derive(i: int) -> void:
	var g: int = ground[i]
	blocking[i] = int(GROUND_BLOCKING[g]) | _occupant_blocking[i]
	var occ_cost := _occupant_cost[i]
	if occ_cost > 0:
		cost[i] = occ_cost
	else:
		cost[i] = int(GROUND_COST[g])
	# A tile nothing can walk onto is impassable regardless of its cost number.
	if (blocking[i] & BLOCKS_UNIT) != 0:
		cost[i] = COST_IMPASSABLE


## Rebuilds every derived tile. Used after bulk-loading a ground array.
func rebuild_derived() -> void:
	for i in ground.size():
		_derive(i)
