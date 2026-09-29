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

## APPEND-ONLY (D8): saves store one byte per tile, and BuildingData's
## allowed_grounds is one bit per entry.
## APPEND-ONLY (D8): saves store these numbers per tile.
## Stage 10: ICE became SNOW (same number), MOUNTAIN was appended.
enum Ground { GRASS_1, GRASS_2, GRASS_3, FLOWERS, SNOW, LAVA, WATER, SAND, VOID, COBBLE, MOUNTAIN }

## Tiles whose ground or occupancy changed at runtime. Pathing, and later fog
## of war and enemy flow fields, update only these instead of rescanning the
## map. Silent while `notify` is false, i.e. during generation and loading,
## after which listeners rebuild from scratch once.
signal tiles_changed(indices: PackedInt32Array)

## Bit flags in `blocking`.
const BLOCKS_UNIT := 1 << 0
const BLOCKS_PROJECTILE := 1 << 1
const IS_ROAD := 1 << 2

## Values in `explored`.
const UNEXPLORED := 0
const EXPLORED := 255

## Value in `occupancy` meaning "no building here".
const NO_OCCUPANT := -1

## Movement costs, kept as whole numbers so roads can undercut open ground
## without fractions. 255 means impassable, never merely expensive -- pathing
## must treat it as a wall rather than as a route worth considering.
const COST_IMPASSABLE := 255
const COST_OPEN := 10
const COST_ROUGH := 14
## Roads (Stage 6): workers walk ROAD_SPEED times faster on them, so pathing
## weighs a road tile at COST_OPEN / ROAD_SPEED.
const COST_ROAD := 6
const ROAD_SPEED := 1.6
## Snow (Stage 10): everyone walks SNOW_SPEED times as fast in it, and
## pathing weighs it at COST_OPEN / SNOW_SPEED.
const SNOW_SPEED := 0.6
const COST_SNOW := 17

## Region layer (Stage 10): which region of the map a tile belongs to (an
## index into LevelGenerator.regions), or NO_REGION for mountains.
const NO_REGION := 255

## What is built on top of the ground (Stage 6). One per tile. Enemies ignore
## roads; bridges and crossings make water and void walkable for everyone.
enum Overlay { NONE, ROAD, BRIDGE, CROSSING }

## Terrain rules. Water, void and lava block movement: reaching the copper,
## quartz and gold mines is meant to require boats, bridges and (eventually)
## hauling water to cool lava. That gate is the point, not an obstacle to it.
const GROUND_BLOCKING := {
	Ground.GRASS_1: 0,
	Ground.GRASS_2: 0,
	Ground.GRASS_3: 0,
	Ground.FLOWERS: 0,
	Ground.SAND: 0,
	Ground.SNOW: 0,
	Ground.LAVA: BLOCKS_UNIT,
	Ground.WATER: BLOCKS_UNIT,
	Ground.VOID: BLOCKS_UNIT,
	Ground.COBBLE: 0,
	# Stage 10: nothing walks through a mountain and no shot passes it; it
	# also casts a shadow for sight (reveal_circle). Fliers cross it.
	Ground.MOUNTAIN: BLOCKS_UNIT | BLOCKS_PROJECTILE,
}

const GROUND_COST := {
	Ground.GRASS_1: COST_OPEN,
	Ground.GRASS_2: COST_OPEN,
	Ground.GRASS_3: COST_OPEN,
	Ground.FLOWERS: COST_OPEN,
	Ground.SAND: COST_ROUGH,
	Ground.SNOW: COST_SNOW,
	Ground.LAVA: COST_IMPASSABLE,
	Ground.WATER: COST_IMPASSABLE,
	Ground.VOID: COST_IMPASSABLE,
	Ground.COBBLE: COST_OPEN,   # cooled lava: made by builders, walkable
	Ground.MOUNTAIN: COST_IMPASSABLE,
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
## Fog of war (Stage 3b): EXPLORED or UNEXPLORED per tile. Stored as 0 / 255
## rather than 0 / 1 so FogRenderer can hand the array to an L8 image as it is,
## with no per-pixel loop. A fresh grid is fully explored: only
## LevelGenerator.generate() fogs a map, so hand-built maps (tests, and any
## future authored map) are visible unless they ask otherwise.
var explored := PackedByteArray()
## Overlay per tile (Overlay enum). Saved with the level.
var overlay := PackedByteArray()
## Region per tile (Stage 10), or NO_REGION. Saved with the level.
var region := PackedByteArray()

## The occupant's own contribution, stored rather than recomputed so that
## changing terrain under a building, or a building over terrain, gives the same
## answer in either order. Two bytes per tile buys order-independence, which is
## worth more than the memory once several systems write to the grid.
var _occupant_blocking := PackedByteArray()
var _occupant_cost := PackedByteArray()

## Off during bulk generation and loading; LevelGenerator turns it on when the
## map is complete. See tiles_changed.
var notify := false


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
	explored.resize(n); explored.fill(EXPLORED)
	overlay.resize(n); overlay.fill(Overlay.NONE)
	region.resize(n); region.fill(NO_REGION)


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
	_announce(i)


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
	_announce(i)


func release(i: int) -> void:
	occupancy[i] = NO_OCCUPANT
	_occupant_blocking[i] = 0
	_occupant_cost[i] = 0
	_derive(i)
	_announce(i)


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


# --- Fog of war ---------------------------------------------------------------

func is_explored(cell: Vector2i) -> bool:
	return explored[cell.y * size.x + cell.x] != UNEXPLORED


func is_explored_at(i: int) -> bool:
	return explored[i] != UNEXPLORED


## Explores every tile within `radius` of `center` (a disc, not a square)
## that `center` can see: since Stage 10 mountains cast shadows, so a tile is
## only explored if the line to it crosses no mountain (the first mountain
## on the line is seen). Returns the indices that were unexplored until now
## -- empty when the disc was already known, the common case for a unit
## walking home, which then costs no line tests at all.
func reveal_circle(center: Vector2i, radius: int) -> PackedInt32Array:
	var fresh := PackedInt32Array()
	var r2 := radius * radius + radius   # the +radius rounds the rim off nicely
	for y in range(maxi(center.y - radius, 0), mini(center.y + radius, size.y - 1) + 1):
		var dy := y - center.y
		var row := y * size.x
		for x in range(maxi(center.x - radius, 0), mini(center.x + radius, size.x - 1) + 1):
			var dx := x - center.x
			if dx * dx + dy * dy > r2:
				continue
			var i := row + x
			if explored[i] == UNEXPLORED and sees(center, Vector2i(x, y)):
				explored[i] = EXPLORED
				fresh.append(i)
	return fresh


## Every tile within `radius` that `center` can see (mountain shadows), as
## indices. For live sight (the snowstorm) and watchtower cones.
func visible_disc(center: Vector2i, radius: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius + radius
	for y in range(maxi(center.y - radius, 0), mini(center.y + radius, size.y - 1) + 1):
		var dy := y - center.y
		for x in range(maxi(center.x - radius, 0), mini(center.x + radius, size.x - 1) + 1):
			var dx := x - center.x
			if dx * dx + dy * dy <= r2 and sees(center, Vector2i(x, y)):
				out.append(y * size.x + x)
	return out


## True if nothing but the target itself may be a mountain on the line from
## `a` to `b` (Bresenham; the viewer's own tile never blocks).
func sees(a: Vector2i, b: Vector2i) -> bool:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var x := a.x
	var y := a.y
	while true:
		if x == b.x and y == b.y:
			return true
		if (x != a.x or y != a.y) and ground[y * size.x + x] == Ground.MOUNTAIN:
			return false
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true


func region_of(cell: Vector2i) -> int:
	return region[cell.y * size.x + cell.x]


# --- Derivation ---------------------------------------------------------------

## The ground's own flags, as the overlay changes them: a bridge or crossing
## makes its tile walkable, a road marks it IS_ROAD.
func ground_blocking_at(i: int) -> int:
	var flags := int(GROUND_BLOCKING[ground[i]])
	match overlay[i]:
		Overlay.BRIDGE, Overlay.CROSSING:
			flags &= ~BLOCKS_UNIT
		Overlay.ROAD:
			flags |= IS_ROAD
	return flags


## The ground's walking cost, as the overlay changes it.
func ground_cost_at(i: int) -> int:
	match overlay[i]:
		Overlay.ROAD:
			return COST_ROAD
		Overlay.BRIDGE, Overlay.CROSSING:
			return COST_OPEN
	return int(GROUND_COST[ground[i]])


func get_overlay(cell: Vector2i) -> int:
	return overlay[cell.y * size.x + cell.x]


func set_overlay_at(i: int, value: int) -> void:
	overlay[i] = value
	_derive(i)
	_announce(i)


## Tells every listener these tiles changed although no layer here did (a
## gate opening changes what enemies make of it).
func touch(indices: PackedInt32Array) -> void:
	if notify and not indices.is_empty():
		tiles_changed.emit(indices)


## Recomputes the derived layers for one tile from its inputs.
func _derive(i: int) -> void:
	blocking[i] = ground_blocking_at(i) | _occupant_blocking[i]
	var occ_cost := _occupant_cost[i]
	if occ_cost > 0:
		cost[i] = occ_cost
	else:
		cost[i] = ground_cost_at(i)
	# A tile nothing can walk onto is impassable regardless of its cost number.
	if (blocking[i] & BLOCKS_UNIT) != 0:
		cost[i] = COST_IMPASSABLE


func _announce(i: int) -> void:
	if notify:
		tiles_changed.emit(PackedInt32Array([i]))


## Rebuilds every derived tile. Used after bulk-loading a ground array.
func rebuild_derived() -> void:
	for i in ground.size():
		_derive(i)
