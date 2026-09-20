class_name LevelGenerator
extends Node2D
## Procedural level generator using individual placeholder PNGs (Godot 4.3+).
##
## Attach this to a Node2D. Ground tiles are drawn on a TileMapLayer created at
## runtime, and buildings (mines, trees) are Sprite2D children so they're easy
## to find and interact with later (e.g. sending workers to them).

signal level_generated
## Emitted when the player places a building (not for generated mines/trees).
signal building_placed(type: String, cell: Vector2i)

enum Ground { GRASS_1, GRASS_2, GRASS_3, FLOWERS, ICE, LAVA, WATER, SAND, VOID }

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

var ground_layer: TileMapLayer
## Where the player's base is. INVALID_CELL until the player places it.
var base_cell := INVALID_CELL
var buildings_root: Node2D
## "mine_gold" -> Array of cells. Useful for sending workers to mines.
var mines := {}
## Vector2i cell -> building type string ("mine_gold", "tree_fruit", ...).
var buildings := {}

## The seed the current map was generated with (saved for reference).
var used_seed := 0

var _ground := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _source_ids := {}
var _building_textures := {}
var _environments: Array[Dictionary] = []
## Every tile covered by a building -> that building's origin (top-left) cell.
var _occupied := {}


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
	level_generated.emit()


# --- Saving and loading -------------------------------------------------------

## Everything needed to rebuild this exact map. Only contains plain data
## (ints, Vector2i, Dictionary, PackedInt32Array), so it's safe with store_var.
func get_save_data() -> Dictionary:
	return {
		"version": 1,
		"seed": used_seed,
		"map_size": map_size,
		"ground": _ground,
		"buildings": buildings.duplicate(),
	}


## Rebuilds a saved map without running the generator.
func load_save_data(data: Dictionary) -> void:
	map_size = data["map_size"]
	_clear()
	if not _load_assets():
		return
	used_seed = data["seed"]
	_ground = data["ground"]
	var saved_buildings: Dictionary = data["buildings"]
	for cell in saved_buildings:
		_add_building(cell, saved_buildings[cell])
	_draw_ground()
	level_generated.emit()


## Removes a building. `cell` can be any tile the building covers.
## Call this when a mine is depleted, a tree is cut down, a building is demolished...
func remove_building(cell: Vector2i) -> void:
	if not _occupied.has(cell):
		return
	var origin: Vector2i = _occupied[cell]
	var type: String = buildings[origin]
	buildings.erase(origin)
	for c in _occupied.keys():
		if _occupied[c] == origin:
			_occupied.erase(c)
	if type == "base":
		base_cell = INVALID_CELL
	if mines.has(type):
		mines[type].erase(origin)
	var sprite := buildings_root.get_node_or_null("%s_%d_%d" % [type, origin.x, origin.y])
	if sprite:
		sprite.queue_free()


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
	if data.unique and buildings.values().has(type):
		return false
	for y in data.size.y:
		for x in data.size.x:
			var c := cell + Vector2i(x, y)
			if not _in_bounds(c) or _occupied.has(c):
				return false
			if (data.allowed_grounds & (1 << get_ground(c))) == 0:
				return false
	return true


## Places a player building if allowed. Returns true on success.
func place_building(type: String, cell: Vector2i) -> bool:
	if not can_place(type, cell):
		return false
	_add_building(cell, type)
	building_placed.emit(type, cell)
	return true


## Pixel offset from a building's origin tile center to the center of its footprint.
func get_footprint_offset(size: Vector2i) -> Vector2:
	return Vector2(size - Vector2i.ONE) * Vector2(ground_layer.tile_set.tile_size) / 2.0


# --- Public helpers -----------------------------------------------------------

func get_ground(cell: Vector2i) -> int:
	return _ground[cell.y * map_size.x + cell.x]


func get_mines(type: String) -> Array:
	return mines.get(type, [])


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

	mines.clear()
	buildings.clear()
	base_cell = INVALID_CELL
	_occupied.clear()
	_environments.clear()
	_source_ids.clear()
	_ground.resize(map_size.x * map_size.y)
	_ground.fill(Ground.GRASS_1)


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
			_set_ground(Vector2i(x, y), g)


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
			if not _in_bounds(c):
				continue
			# Noise wobbles the edge so patches look organic rather than circular.
			var edge := radius * (1.0 + 0.35 * noise.get_noise_2d(x, y))
			if Vector2(c - center).length() > edge:
				continue
			if not _is_grass(get_ground(c)):
				continue
			if _near_other_environment(c, type):
				continue
			_set_ground(c, type)
			cells.append(c)
	return cells


## True if a different environment is closer than the required grass gap.
func _near_other_environment(cell: Vector2i, type: int) -> bool:
	var check := grass_gap + sand_width
	for dy in range(-check, check + 1):
		for dx in range(-check, check + 1):
			var n := cell + Vector2i(dx, dy)
			if not _in_bounds(n):
				continue
			var g := get_ground(n)
			if _is_grass(g) or g == type or g == Ground.SAND:
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
		if _occupied.has(c):
			continue
		var interior := true
		for n in _neighbors(c):
			if get_ground(n) != type:
				interior = false
				break
		if interior:
			candidates.append(c)
	if candidates.is_empty():
		return env["center"]
	return candidates[_rng.randi() % candidates.size()]


func _surround(cell: Vector2i, type: int) -> void:
	_set_ground(cell, type)
	for n in _neighbors(cell):
		var g := get_ground(n)
		if _is_grass(g) or g == Ground.SAND or g == type:
			_set_ground(n, type)


## Rule 3: water is bordered by sand.
func _surround_water_with_sand() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			if get_ground(c) != Ground.WATER:
				continue
			for dy in range(-sand_width, sand_width + 1):
				for dx in range(-sand_width, sand_width + 1):
					var n := c + Vector2i(dx, dy)
					if _in_bounds(n) and _is_grass(get_ground(n)):
						_set_ground(n, Ground.SAND)


## Rules 8 and 9: trees are rare on grass, common on flowers.
func _place_trees() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			if _occupied.has(c):
				continue
			var g := get_ground(c)
			var chance := 0.0
			if g == Ground.FLOWERS:
				chance = tree_chance_flowers
			elif _is_grass(g):
				chance = tree_chance_grass
			if chance > 0.0 and _rng.randf() < chance:
				_add_building(c, "tree_fruit")


func _draw_ground() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			ground_layer.set_cell(c, _source_ids[get_ground(c)], Vector2i.ZERO)


func _add_building(cell: Vector2i, type: String) -> void:
	# Generated buildings (mines, trees) use BUILDING_FILES and are 1x1.
	# Player buildings come from BuildingData and can be bigger.
	var texture: Texture2D = _building_textures.get(type)
	var size := Vector2i.ONE
	var data := get_building_data(type)
	if data != null:
		texture = data.texture
		size = data.size
	if texture == null:
		push_warning("LevelGenerator: unknown building type '%s', skipped." % type)
		return

	buildings[cell] = type
	for y in size.y:
		for x in size.x:
			_occupied[cell + Vector2i(x, y)] = cell
	if type == "base":
		base_cell = cell # also runs when loading a save, so base_cell is restored
	if type.begins_with("mine_"):
		if not mines.has(type):
			mines[type] = []
		mines[type].append(cell)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = ground_layer.map_to_local(cell) + get_footprint_offset(size)
	sprite.name = "%s_%d_%d" % [type, cell.x, cell.y]
	sprite.set_meta("cell", cell)
	sprite.set_meta("type", type)
	buildings_root.add_child(sprite)


# --- Small utilities ----------------------------------------------------------

func _set_ground(cell: Vector2i, g: int) -> void:
	_ground[cell.y * map_size.x + cell.x] = g


func _is_grass(g: int) -> bool:
	return g == Ground.GRASS_1 or g == Ground.GRASS_2 or g == Ground.GRASS_3


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_size.x and c.y < map_size.y


func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := cell + Vector2i(dx, dy)
			if _in_bounds(n):
				result.append(n)
	return result


## Seeded shuffle so the same level_seed always produces the same map.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
