class_name LevelGenerator
extends Node2D
## Procedural level generator.
##
## Generates terrain into a WorldGrid and registers buildings in a BuildingStore.
## Ground tiles are drawn on a TileMapLayer created at runtime; each building
## also gets a Sprite2D child so it can be seen and picked.
##
## This node fills the world. Once generation is done, gameplay systems should
## read `grid` and `store` rather than reaching back through here.

signal level_generated
## Emitted when the player places a building (not for generated mines/trees).
signal building_placed(type: String, cell: Vector2i)
## Emitted just before a building is removed, while its id is still valid.
## Units whose home or target it was must let go of it.
signal building_removed(id: int, type: String, cell: Vector2i)
## A construction site reached full progress.
signal construction_completed(id: int)

## How faded a construction site's sprite is drawn, until construction.png exists.
const CONSTRUCTION_ALPHA := 0.45

## Terrain lives on the grid now. Aliased so LevelGenerator.Ground keeps working.
const Ground := WorldGrid.Ground

## Bumped when the shape of get_save_data() changes. Version 1 stored buildings
## as a Dictionary keyed by Vector2i and ground as int32; both are gone.
const SAVE_VERSION := 2

const GROUND_DIR := "res://assets/ground/"

const GROUND_FILES := {
	Ground.GRASS_1: "ground_grass_1.png",
	Ground.GRASS_2: "ground_grass_2.png",
	Ground.GRASS_3: "ground_grass_3.png",
	Ground.FLOWERS: "ground_flowers.png",
	Ground.ICE: "ground_ice.png",
	Ground.LAVA: "ground_lava.png",
	Ground.WATER: "ground_water.png",
	Ground.SAND: "ground_sand.png",
	Ground.VOID: "ground_void.png",
}

const BUILDING_FILES := {
	"mine_gold": "res://assets/buildings/mines/mine_gold.png",
	"mine_quartz": "res://assets/buildings/mines/mine_quartz.png",
	"mine_copper": "res://assets/buildings/mines/mine_copper.png",
	"mine_diamond": "res://assets/buildings/mines/mine_diamond.png",
	"tree_fruit": "res://assets/buildings/plants/tree_fruit.png",
	"tree": "res://assets/buildings/plants/tree.png",
	"tree_stump": "res://assets/buildings/plants/tree_stump.png",
}

## Environment patches: size range and which mine (if any) belongs in them.
## Void only exists to hold quartz mines, so it's small and always gets one.
const ENVIRONMENTS := {
	Ground.FLOWERS: {"min_radius": 3, "max_radius": 7, "mine": ""},
	Ground.ICE: {"min_radius": 3, "max_radius": 6, "mine": "mine_diamond"},
	Ground.LAVA: {"min_radius": 3, "max_radius": 6, "mine": "mine_gold"},
	Ground.WATER: {"min_radius": 3, "max_radius": 7, "mine": "mine_copper"},
	Ground.VOID: {"min_radius": 1, "max_radius": 2, "mine": "mine_quartz"},
}

const INVALID_CELL := Vector2i(-1, -1)

@export var map_size := Vector2i(80, 60)
## 0 = random seed every time. Any other number always gives the same map.
@export var level_seed := 0
## 0 = use the width of ground_grass_1.png as the tile size.
@export var tile_size := 0
## Left false in main.tscn: main.gd decides whether to generate or load a save,
## and children are readied before their parent, so it must not self-start.
@export var generate_on_ready := true

@export_group("Environments")
## How many environment patches to try to place (flowers, ice, lava, water, void).
@export var environment_count := 16
## Minimum number of grass tiles between two different environments.
@export var grass_gap := 3
## Chance that an ice/lava/water patch gets a mine. Void patches always get one.
@export_range(0.0, 1.0) var mine_chance := 0.75
## How many tiles of sand surround water.
@export var sand_width := 1

@export_group("Trees")
@export_range(0.0, 1.0) var tree_chance_grass := 0.02
@export_range(0.0, 1.0) var tree_chance_flowers := 0.3

@export_group("Player buildings")
## Buildings the player can place. Create these as BuildingData resources.
@export var placeable_buildings: Array[BuildingData] = []

## Terrain, occupancy, blocking and movement cost. Read this from gameplay code.
var grid := WorldGrid.new()
## Every building on the map. Read this from gameplay code.
var store := BuildingStore.new()

var ground_layer: TileMapLayer
var buildings_root: Node2D
## Where the player's base is. INVALID_CELL until the player places it.
var base_cell := INVALID_CELL
## The seed the current map was generated with (saved for reference).
var used_seed := 0

var _rng := RandomNumberGenerator.new()
var _source_ids := {}
var _building_textures := {}
var _environments: Array[Dictionary] = []


func _ready() -> void:
	if generate_on_ready:
		generate()


func generate() -> void:
	_clear()
	# Remember the seed actually used, even when level_seed is 0 (random).
	used_seed = level_seed if level_seed != 0 else randi()
	_rng.seed = used_seed
	if not _load_assets():
		return
	_generate_grass()
	_place_environments()
	_place_mines()
	_surround_water_with_sand()
	_place_trees()
	_draw_ground()
	grid.notify = true
	level_generated.emit()


# --- Saving and loading -------------------------------------------------------

## Everything needed to rebuild this exact map, as plain data only (ints,
## Vector2i, packed arrays, Dictionary), so store_var never needs objects.
func get_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": used_seed,
		"map_size": map_size,
		"ground": grid.ground,
		"buildings": store.to_save_data(),
	}


## Rebuilds a saved map without running the generator.
## Returns false if the save is unreadable, in which case the caller should
## start a new level rather than continue with a half-built world.
func load_save_data(data: Dictionary) -> bool:
	var version: int = data.get("version", 0)
	if version != SAVE_VERSION:
		push_warning("LevelGenerator: save is version %d, this build reads %d. "
			% [version, SAVE_VERSION] + "Starting a new level instead.")
		return false

	map_size = data["map_size"]
	_clear()
	if not _load_assets():
		return false
	used_seed = data["seed"]
	grid.ground = PackedByteArray(data["ground"])
	grid.rebuild_derived()

	var saved: Dictionary = data["buildings"]
	var types: PackedStringArray = saved["types"]
	var xs: PackedInt32Array = saved["cells_x"]
	var ys: PackedInt32Array = saved["cells_y"]
	var hp: PackedFloat32Array = saved["health"]
	# Saves from before construction sites existed have no progress: complete.
	var progress: PackedFloat32Array = saved.get("progress", PackedFloat32Array())
	var skipped := 0
	for i in types.size():
		var p := progress[i] if i < progress.size() else 1.0
		var id := _add_building(Vector2i(xs[i], ys[i]), types[i], p)
		if id == BuildingStore.NONE:
			# The type no longer exists, or its BuildingData is missing from
			# placeable_buildings. Loading the rest would hand the player a world
			# quietly missing pieces, so the whole load fails instead.
			skipped += 1
			continue
		if i < hp.size():
			store.damage(id, store.get_max_health(id) - hp[i])
	if skipped > 0:
		push_error("LevelGenerator: save references %d building(s) this build " % skipped
			+ "cannot create. Refusing to load a partial world.")
		return false

	_draw_ground()
	grid.notify = true
	level_generated.emit()
	return true


## Removes a building. `cell` can be any tile the building covers.
## Call this when a mine is depleted, a tree is cut down, a building dies...
func remove_building(cell: Vector2i) -> void:
	if not grid.in_bounds(cell):
		return
	var id := grid.get_occupant(cell)
	if id == WorldGrid.NO_OCCUPANT or not store.is_alive(id):
		return

	# Release exactly the footprint this building claimed. The old version
	# scanned a dictionary and erased from it while iterating its own keys,
	# which could skip tiles; there is nothing to iterate over now.
	var origin := store.get_cell(id)
	var size := store.get_size(id)
	building_removed.emit(id, store.get_type(id), origin)
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			if grid.in_bounds(c):
				grid.release(grid.index(c))

	if store.get_type(id) == "base":
		base_cell = INVALID_CELL
	var sprite := store.get_sprite(id)
	if sprite != null:
		sprite.queue_free()
	store.remove(id)


# --- Player building placement ------------------------------------------------

func get_building_data(type: String) -> BuildingData:
	for data in placeable_buildings:
		if data != null and data.id == type:
			return data
	return null


## True if a building of this type may be placed with its top-left corner at `cell`.
func can_place(type: String, cell: Vector2i) -> bool:
	var data := get_building_data(type)
	if data == null:
		return false
	if data.unique and store.has_type(type):
		return false
	for y in data.size.y:
		for x in data.size.x:
			var c := cell + Vector2i(x, y)
			if not grid.in_bounds(c) or grid.is_occupied(c):
				return false
			if (data.allowed_grounds & (1 << grid.get_ground(c))) == 0:
				return false
	if data.must_touch_prefix != "":
		return _touches_free(type, cell, data)
	return true


## True if the footprint at `cell` touches a building whose type starts with
## data.must_touch_prefix -- and, with one_per_touched, one that no other
## building of this type touches yet.
func _touches_free(type: String, cell: Vector2i, data: BuildingData) -> bool:
	for target in _touching(cell, data.size):
		if not store.get_type(target).begins_with(data.must_touch_prefix):
			continue
		if not data.one_per_touched:
			return true
		var taken := false
		for other in _touching(store.get_cell(target), store.get_size(target)):
			if store.get_type(other) == type:
				taken = true
				break
		if not taken:
			return true
	return false


## Ids of the buildings touching a footprint (8 neighbours), each once.
func _touching(origin: Vector2i, size: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in range(origin.y - 1, origin.y + size.y + 1):
		for x in range(origin.x - 1, origin.x + size.x + 1):
			var c := Vector2i(x, y)
			if not grid.in_bounds(c):
				continue
			var id := grid.get_occupant(c)
			if id != WorldGrid.NO_OCCUPANT and store.is_alive(id) and not out.has(id):
				var inside := c.x >= origin.x and c.y >= origin.y and c.x < origin.x + size.x and c.y < origin.y + size.y
				if not inside:
					out.append(id)
	return out


## Places a player building if allowed. Returns true on success.
func place_building(type: String, cell: Vector2i) -> bool:
	if not can_place(type, cell):
		return false
	_add_building(cell, type)
	building_placed.emit(type, cell)
	return true


## Places a construction site: it claims its tiles now, and becomes the real
## building when builders have put in its BuildingData.build_work. A type with
## no build work is placed complete. Returns the id, or BuildingStore.NONE.
func place_construction(type: String, cell: Vector2i) -> int:
	if not can_place(type, cell):
		return BuildingStore.NONE
	var data := get_building_data(type)
	var start := 0.0 if data != null and data.build_work > 0.0 else 1.0
	var id := _add_building(cell, type, start)
	if id != BuildingStore.NONE:
		building_placed.emit(type, cell)
	return id


## Adds a generated 1x1 feature (tree, stump...) on a free tile at runtime.
## Returns the id, or BuildingStore.NONE if the tile is taken.
func add_feature(type: String, cell: Vector2i) -> int:
	if not grid.in_bounds(cell) or grid.is_occupied(cell) or not _building_textures.has(type):
		return BuildingStore.NONE
	return _add_building(cell, type)


## Adds builder work to a construction site. Returns true on the call that
## completes it. `work` is builder-seconds (build_speed * dt).
func add_construction_work(id: int, work: float) -> bool:
	if not store.is_alive(id) or store.is_complete(id):
		return false
	var data := get_building_data(store.get_type(id))
	var total := data.build_work if data != null and data.build_work > 0.0 else 1.0
	store.set_progress(id, store.get_progress(id) + work / total)
	if not store.is_complete(id):
		return false
	_refresh_sprite(id)
	construction_completed.emit(id)
	return true


## Cells where a building of `type` could go, touching the given building's
## footprint (8-neighbourhood), nearest to `prefer` first. Placement rules
## only; whether a unit can walk there is the pathing system's question.
func free_cells_around(building_id: int, type: String, prefer: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not store.is_alive(building_id):
		return out
	var origin := store.get_cell(building_id)
	var size := store.get_size(building_id)
	for y in range(origin.y - 1, origin.y + size.y + 1):
		for x in range(origin.x - 1, origin.x + size.x + 1):
			var c := Vector2i(x, y)
			if grid.in_bounds(c) and can_place(type, c):
				out.append(c)
	out.sort_custom(func(a, b): return (a - prefer).length_squared() < (b - prefer).length_squared())
	return out


## Pixel offset from a building's origin tile center to the center of its footprint.
func get_footprint_offset(size: Vector2i) -> Vector2:
	return Vector2(size - Vector2i.ONE) * Vector2(ground_layer.tile_set.tile_size) / 2.0


# --- Public helpers -----------------------------------------------------------

func get_ground(cell: Vector2i) -> int:
	return grid.get_ground(cell)


## Cells of every live mine of one type. Useful for sending workers to mines.
func get_mines(type: String) -> Array[Vector2i]:
	return store.cells_of_type(type)


## Global position of the base, e.g. where workers spawn and return.
func get_base_position() -> Vector2:
	var data := get_building_data("base")
	var size: Vector2i = data.size if data != null else Vector2i.ONE
	return cell_to_world(base_cell) + get_footprint_offset(size)


## Global position of a tile's center, e.g. for moving workers.
func cell_to_world(cell: Vector2i) -> Vector2:
	return ground_layer.to_global(ground_layer.map_to_local(cell))


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(world_pos))


# --- Setup --------------------------------------------------------------------

func _clear() -> void:
	for node in [ground_layer, buildings_root]:
		if node != null:
			remove_child(node)
			node.queue_free()

	ground_layer = TileMapLayer.new()
	ground_layer.name = "Ground"
	add_child(ground_layer)

	buildings_root = Node2D.new()
	buildings_root.name = "Buildings"
	buildings_root.y_sort_enabled = true
	add_child(buildings_root)

	# Silent while the map is rebuilt in bulk; listeners rebuild once on
	# level_generated instead of hearing about every one of thousands of tiles.
	grid.notify = false
	grid.resize(map_size)
	store.clear()
	base_cell = INVALID_CELL
	_environments.clear()
	_source_ids.clear()


func _load_assets() -> bool:
	var grass_tex: Texture2D = load(GROUND_DIR + GROUND_FILES[Ground.GRASS_1])
	if grass_tex == null:
		push_error("LevelGenerator: couldn't load grass texture, check the assets folder.")
		return false

	var size: int = tile_size if tile_size > 0 else grass_tex.get_width()
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(size, size)

	for g in GROUND_FILES:
		var tex: Texture2D = load(GROUND_DIR + GROUND_FILES[g])
		if tex == null:
			push_error("LevelGenerator: missing ground texture " + GROUND_FILES[g])
			return false
		var source := TileSetAtlasSource.new()
		source.texture = tex
		source.texture_region_size = Vector2i(size, size)
		source.create_tile(Vector2i.ZERO)
		_source_ids[g] = tile_set.add_source(source)

	ground_layer.tile_set = tile_set

	for type in BUILDING_FILES:
		var tex: Texture2D = load(BUILDING_FILES[type])
		if tex == null:
			push_error("LevelGenerator: missing building texture " + BUILDING_FILES[type])
			return false
		_building_textures[type] = tex

	return true


# --- Generation steps ---------------------------------------------------------

## Rule 1: the three grass variants form clusters instead of random noise.
func _generate_grass() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.08

	for y in map_size.y:
		for x in map_size.x:
			var n := noise.get_noise_2d(x, y)
			var g: int = Ground.GRASS_2
			if n < -0.15:
				g = Ground.GRASS_1
			elif n > 0.15:
				g = Ground.GRASS_3
			grid.set_ground(Vector2i(x, y), g)


## Rule 2: environments are blobs spaced apart, with grass between them.
func _place_environments() -> void:
	var types: Array = ENVIRONMENTS.keys()
	var order: Array = types.duplicate()
	_shuffle(order) # guarantees every environment type appears at least once
	while order.size() < environment_count:
		order.append(types[_rng.randi() % types.size()])

	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = _rng.randi()
	shape_noise.frequency = 0.25

	for type in order:
		var cfg: Dictionary = ENVIRONMENTS[type]
		var radius := _rng.randi_range(cfg["min_radius"], cfg["max_radius"])
		var center := _find_environment_spot(radius)
		if center == INVALID_CELL:
			continue
		var cells := _paint_environment(type, center, radius, shape_noise)
		if cells.is_empty():
			continue
		_environments.append({
			"type": type,
			"center": center,
			"radius": radius,
			"cells": cells,
		})


func _find_environment_spot(radius: int) -> Vector2i:
	var margin := radius + 1
	if map_size.x <= margin * 2 or map_size.y <= margin * 2:
		return INVALID_CELL

	for attempt in 60:
		var c := Vector2i(
			_rng.randi_range(margin, map_size.x - 1 - margin),
			_rng.randi_range(margin, map_size.y - 1 - margin)
		)
		var ok := true
		for env in _environments:
			var min_dist: float = (radius + env["radius"]) * 1.35 + grass_gap + sand_width
			if Vector2(c - env["center"]).length() < min_dist:
				ok = false
				break
		if ok:
			return c
	return INVALID_CELL


func _paint_environment(type: int, center: Vector2i, radius: int, noise: FastNoiseLite) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var reach := int(ceil(radius * 1.35)) + 1

	for y in range(center.y - reach, center.y + reach + 1):
		for x in range(center.x - reach, center.x + reach + 1):
			var c := Vector2i(x, y)
			if not grid.in_bounds(c):
				continue
			# Noise wobbles the edge so patches look organic rather than circular.
			var edge := radius * (1.0 + 0.35 * noise.get_noise_2d(x, y))
			if Vector2(c - center).length() > edge:
				continue
			if not grid.is_grass(grid.get_ground(c)):
				continue
			if _near_other_environment(c, type):
				continue
			grid.set_ground(c, type)
			cells.append(c)
	return cells


## True if a different environment is closer than the required grass gap.
func _near_other_environment(cell: Vector2i, type: int) -> bool:
	var check := grass_gap + sand_width
	for dy in range(-check, check + 1):
		for dx in range(-check, check + 1):
			var n := cell + Vector2i(dx, dy)
			if not grid.in_bounds(n):
				continue
			var g := grid.get_ground(n)
			if grid.is_grass(g) or g == type or g == Ground.SAND:
				continue
			var needed := grass_gap
			if g == Ground.WATER or type == Ground.WATER:
				needed += sand_width # leave room for the sand border
			if maxi(absi(dx), absi(dy)) <= needed:
				return true
	return false


## Rules 4-7 and 9: each mine sits on its environment and is fully surrounded by it.
func _place_mines() -> void:
	for env in _environments:
		var type: int = env["type"]
		var mine: String = ENVIRONMENTS[type]["mine"]
		if mine == "":
			continue
		if type != Ground.VOID and _rng.randf() > mine_chance:
			continue
		var cell := _pick_interior_cell(env)
		_surround(cell, type)
		_add_building(cell, mine)


## Prefers a cell whose 8 neighbors already match; falls back to the patch center.
func _pick_interior_cell(env: Dictionary) -> Vector2i:
	var type: int = env["type"]
	var candidates: Array[Vector2i] = []
	for c in env["cells"]:
		if grid.is_occupied(c):
			continue
		var interior := true
		for n in _neighbors(c):
			if grid.get_ground(n) != type:
				interior = false
				break
		if interior:
			candidates.append(c)
	if candidates.is_empty():
		return env["center"]
	return candidates[_rng.randi() % candidates.size()]


func _surround(cell: Vector2i, type: int) -> void:
	grid.set_ground(cell, type)
	for n in _neighbors(cell):
		var g := grid.get_ground(n)
		if grid.is_grass(g) or g == Ground.SAND or g == type:
			grid.set_ground(n, type)


## Rule 3: water is bordered by sand.
func _surround_water_with_sand() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			if grid.get_ground(c) != Ground.WATER:
				continue
			for dy in range(-sand_width, sand_width + 1):
				for dx in range(-sand_width, sand_width + 1):
					var n := c + Vector2i(dx, dy)
					if grid.in_bounds(n) and grid.is_grass(grid.get_ground(n)):
						grid.set_ground(n, Ground.SAND)


## Rules 8 and 9: plain trees are rare on grass (wood, Stage 2b); fruit trees
## are common on flowers.
func _place_trees() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			if grid.is_occupied(c):
				continue
			var g := grid.get_ground(c)
			if g == Ground.FLOWERS:
				if _rng.randf() < tree_chance_flowers:
					_add_building(c, "tree_fruit")
			elif grid.is_grass(g):
				if _rng.randf() < tree_chance_grass:
					_add_building(c, "tree")


func _draw_ground() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			ground_layer.set_cell(c, _source_ids[grid.get_ground(c)], Vector2i.ZERO)


## Registers a building, claims its tiles and creates its sprite.
## Returns the new building id, or BuildingStore.NONE if the type is unknown.
func _add_building(cell: Vector2i, type: String, progress: float = 1.0) -> int:
	# Generated buildings (mines, trees) use BUILDING_FILES and are 1x1.
	# Player buildings come from BuildingData and can be bigger.
	var texture: Texture2D = _building_textures.get(type)
	var size := Vector2i.ONE
	var block_flags := WorldGrid.BLOCKS_UNIT
	var max_health := BuildingStore.DEFAULT_MAX_HEALTH
	var data := get_building_data(type)
	if data != null:
		texture = data.get_texture()
		size = data.size
		max_health = data.max_health
		block_flags = 0
		if data.blocks_units:
			block_flags |= WorldGrid.BLOCKS_UNIT
		if data.blocks_projectiles:
			block_flags |= WorldGrid.BLOCKS_PROJECTILE
	if texture == null:
		push_warning("LevelGenerator: unknown building type '%s', skipped." % type)
		return BuildingStore.NONE

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = ground_layer.map_to_local(cell) + get_footprint_offset(size)
	sprite.name = "%s_%d_%d" % [type, cell.x, cell.y]
	buildings_root.add_child(sprite)

	var id := store.add(type, cell, size, sprite, max_health, progress)
	sprite.set_meta("building_id", id)
	_refresh_sprite(id)

	for y in size.y:
		for x in size.x:
			var c := cell + Vector2i(x, y)
			if grid.in_bounds(c):
				grid.claim(grid.index(c), id, block_flags)

	if type == "base":
		base_cell = cell # also runs when loading a save, so base_cell is restored
	return id


## Construction sites are drawn faded; complete buildings at full strength.
func _refresh_sprite(id: int) -> void:
	var sprite := store.get_sprite(id)
	if sprite != null:
		sprite.modulate.a = 1.0 if store.is_complete(id) else CONSTRUCTION_ALPHA


# --- Small utilities ----------------------------------------------------------

func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := cell + Vector2i(dx, dy)
			if grid.in_bounds(n):
				result.append(n)
	return result


## Seeded shuffle so the same level_seed always produces the same map.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
