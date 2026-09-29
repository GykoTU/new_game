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
	Ground.SNOW: "ground_ice.png",   # ground_snow.png (SNOW_FILE) when it exists
	Ground.LAVA: "ground_lava.png",
	Ground.WATER: "ground_water.png",
	Ground.SAND: "ground_sand.png",
	Ground.VOID: "ground_void.png",
	Ground.COBBLE: "ground_cobble.png",
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

## Points of interest (Stage 3b). Loaded through Art, so a sprite that is not
## drawn yet shows the placeholder instead of stopping the level from loading.
## PointsOfInterest decides what each one does; the generator only places them.
const POI_FILES := {
	"poi_blueprint_cache": "res://assets/buildings/poi/blueprint_cache.png",
	"poi_relic_cache": "res://assets/buildings/poi/relic_cache.png",
	"poi_npc_house": "res://assets/buildings/poi/npc_house.png",
	"poi_fruit_tree": "res://assets/buildings/poi/tree_fruit_special.png",
	# Never generated: what an enemy leaves when it drops a blueprint. Falls
	# back to the blueprint cache's sprite until its own exists.
	"poi_blueprint_dropped": "res://assets/buildings/poi/blueprint_dropped.png",
}

## The iron mine's sprite. Not in BUILDING_FILES (whose files must exist):
## until it is drawn, the gold mine is shown in grey.
const IRON_MINE_FILE := "res://assets/buildings/mines/mine_iron.png"

## Stage 10: the map is a CHAIN OF REGIONS walled apart by mountains. The main
## chain runs valley -> lava fields -> lakes -> snowfield -> void, each
## joined to the next by one pass, and the pass INTO a region is sealed by
## that region's hazard (KIND_DATA.gate): lava needs cobble, water a bridge,
## the void a crossing; the snowfield's pass is open (the storm is its
## hazard). Side valleys branch off as dead ends, some behind a band of
## their parent's hazard. Every tile knows its region (WorldGrid.region).
enum RegionKind { VALLEY, LAVA, LAKE, SNOW, VOID }
const REGION_NAMES := ["the start valley", "the lava fields", "the lakes", "the snowfield", "the void"]
const MAIN_CHAIN := [RegionKind.VALLEY, RegionKind.LAVA, RegionKind.LAKE, RegionKind.SNOW, RegionKind.VOID]
## What a region's caches hold (ResourceKind.TIER).
const KIND_TIER := [1, 2, 3, 4, 4]
## Per kind: the hazard sealing the pass into it (-1: open), the hazard of
## its patches (-1: none), how many patches and how big, the mine inside
## each patch (or on the floor, for the snowfield), and the floor ground.
const KIND_DATA := {
	RegionKind.VALLEY: {"gate": -1, "patch": -1, "mine": "", "floor": -1},
	RegionKind.LAVA: {"gate": Ground.LAVA, "patch": Ground.LAVA, "patches": Vector2i(3, 5),
		"patch_r": Vector2i(3, 6), "mine": "mine_copper", "floor": -1},
	RegionKind.LAKE: {"gate": Ground.WATER, "patch": Ground.WATER, "patches": Vector2i(2, 4),
		"patch_r": Vector2i(3, 6), "mine": "mine_quartz", "floor": -1},
	RegionKind.SNOW: {"gate": -1, "patch": -1, "mine": "mine_diamond", "floor_mines": Vector2i(2, 3),
		"floor": Ground.SNOW},
	RegionKind.VOID: {"gate": Ground.VOID, "patch": Ground.VOID, "patches": Vector2i(2, 3),
		"patch_r": Vector2i(1, 2), "mine": "", "floor": -1},
}
## Cave mouths per main region: where enemies come out at night (Waves).
const CAVES := [2, 1, 2, 2, 2]
## How much a region's rim wobbles (share of its radius), and so its furthest
## reach: other regions and passes keep clear of that.
const REGION_WOBBLE := 0.22
const REGION_REACH := 1.22
const CAVE := "cave"
const CAVE_FILE := "res://assets/buildings/cave.png"
const MOUNTAIN_FILE := "ground_mountain.png"
const MOUNTAIN_SHEET := "mountain_sheet.png"
const SNOW_FILE := "ground_snow.png"
## Before Stage 10 a cache's tier came from the ground under it; saves from
## then have no regions, so that is still the fallback.
const REGION_TIER := {Ground.LAVA: 2, Ground.COBBLE: 2, Ground.WATER: 3, Ground.SNOW: 4, Ground.VOID: 4}
## Caches lie on the ground: everyone walks over them (workers and enemies;
## the explorer still stops beside one to open it). They occupy their tile,
## so nothing is built or painted on them.
const WALK_OVER := ["poi_blueprint_cache", "poi_relic_cache", "poi_blueprint_dropped"]

const INVALID_CELL := Vector2i(-1, -1)

@export var map_size := Vector2i(80, 60)
## 0 = random seed every time. Any other number always gives the same map.
@export var level_seed := 0
## 0 = use the width of ground_grass_1.png as the tile size.
@export var tile_size := 0
## Left false in main.tscn: main.gd decides whether to generate or load a save,
## and children are readied before their parent, so it must not self-start.
@export var generate_on_ready := true

@export_group("Regions")
## Radius of the main regions (random in range) and of the start valley.
@export var main_radius := Vector2i(13, 15)
@export var valley_radius := 16
## Radius of side valleys.
@export var side_radius := Vector2i(8, 10)
## Mountain between two joined regions, in tiles (random in range).
@export var ridge := Vector2i(8, 11)
## Chance that a main region gets a side valley, and that one is gated.
@export_range(0.0, 1.0) var side_valley_chance := 0.85
@export_range(0.0, 1.0) var side_gate_chance := 0.5
## Half-width of a pass, and how long its hazard band is, in tiles.
@export var pass_width := 1.6
@export var gate_band := 3.0
## Chance that a patch past the first gets a mine / a region cache. The first
## patch of each region always gets both (the lava and lake caches hold the
## next gate's blueprint).
@export_range(0.0, 1.0) var mine_chance := 0.75
@export_range(0.0, 1.0) var region_cache_chance := 0.5
## Plain trees on snow (wood in the storm is scarce).
@export_range(0.0, 1.0) var tree_chance_snow := 0.01
## How many tiles of sand surround water.
@export var sand_width := 1

@export_group("Trees")
@export_range(0.0, 1.0) var tree_chance_grass := 0.02
@export_range(0.0, 1.0) var tree_chance_flowers := 0.3

@export_group("Start clearing")
## Tiles around the map centre revealed when a run begins. The base has to go
## inside, because nothing can be placed under fog.
@export var start_reveal_radius := 10
## Plain grass kept free of environments around the centre: room for the base.
@export var start_open_radius := 5
## Trees guaranteed inside the clearing, since wood is the first thing a run needs.
@export var start_trees := 6

@export_group("Start valley mines")
## Stage 9: gold and iron sit on open grass, no gate. One of each is always
## inside the start clearing; these many more of each elsewhere in the valley.
@export var valley_mines: Dictionary[String, int] = {"mine_gold": 1, "mine_iron": 1}

@export_group("Points of interest")
## How many of each point of interest to try to place, by type.
@export var poi_counts: Dictionary[String, int] = {
	"poi_blueprint_cache": 2, "poi_relic_cache": 3, "poi_npc_house": 1, "poi_fruit_tree": 1,
}
## No point of interest closer than this to the start: they are found, not given.
@export var poi_min_distance := 12
## Minimum tiles between two points of interest.
@export var poi_spacing := 8

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
## Centre of the start clearing: where the camera opens a new run.
var start_cell := INVALID_CELL
## Gates (Stage 6) are open by day, closed at night. Closed, enemies must
## break them; open, they walk through. Workers always pass. Set through
## set_gates_open(), which tells the flow fields.
var gates_open := true

## Stage 10: every region, as plain data (saved): kind, main (on the chain),
## parent (index, -1 for the valley), center, radius, gated (its pass is
## sealed by a hazard).
var regions: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _source_ids := {}
var _building_textures := {}
## Hazard patches inside regions: {type, center, radius, cells, region}.
var _environments: Array[Dictionary] = []
var _mountain_sheet := false
## Generation only: per region its floor cells, and every pass tile (kept
## clear of patches).
var _region_cells: Array = []
var _pass_cells := {}
var _grass := PackedByteArray()


func _ready() -> void:
	if generate_on_ready:
		generate()


func generate() -> void:
	# Remember the seed actually used, even when level_seed is 0 (random).
	used_seed = level_seed if level_seed != 0 else randi()
	_rng.seed = used_seed
	# Stage 10: a layout that fails its checks (a leak between regions, a
	# chain that does not fit) is thrown away and drawn again from the same
	# random stream, so a seed still always gives the same map.
	for attempt in 24:
		_clear()
		if not _load_assets():
			return
		if _build_world():
			break
	_fog_all_but_start()
	_draw_ground()
	grid.notify = true
	level_generated.emit()


## One attempt at the whole map. False if it must be redone.
func _build_world() -> bool:
	_generate_grass()
	if not _layout_regions():
		return false
	start_cell = regions[0]["center"]
	_carve_regions()
	_carve_passes()
	_paint_patches()
	_place_start_lakes()
	_place_patch_contents()
	_surround_water_with_sand()
	_place_start_mines()
	_place_valley_mines()
	_place_snow_contents()
	_place_side_valley_contents()
	_place_trees()
	_ensure_start_trees()
	_place_caves()
	_place_points_of_interest()
	return _chain_sealed()


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
		# Mostly long runs of 0 and 255, so it compresses to almost nothing.
		"explored": grid.explored.compress(FileAccess.COMPRESSION_DEFLATE),
		# Roads, bridges, crossings (Stage 6): mostly zeros, like the fog.
		"overlay": grid.overlay.compress(FileAccess.COMPRESSION_DEFLATE),
		"start_cell": start_cell,
		# Stage 10: which region each tile is in, and the regions themselves.
		"region": grid.region.compress(FileAccess.COMPRESSION_DEFLATE),
		"regions": regions.duplicate(true),
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
	start_cell = data.get("start_cell", _map_centre())
	# A run saved before fog existed has no explored layer. It stays fully
	# explored (what resize left it as): hiding a map the player has already
	# seen would take something away rather than add anything.
	if data.has("explored"):
		var fog := PackedByteArray(data["explored"]).decompress(grid.tile_count(),
			FileAccess.COMPRESSION_DEFLATE)
		if fog.size() == grid.tile_count():
			grid.explored = fog
	# Stage 10: maps from before have no regions (caches fall back to the
	# ground for their tier, and nights to the map edges).
	regions.clear()
	if data.has("region"):
		var reg := PackedByteArray(data["region"]).decompress(grid.tile_count(),
			FileAccess.COMPRESSION_DEFLATE)
		if reg.size() == grid.tile_count():
			grid.region = reg
			for entry in data.get("regions", []):
				regions.append(Dictionary(entry))
	if data.has("overlay"):
		var over := PackedByteArray(data["overlay"]).decompress(grid.tile_count(),
			FileAccess.COMPRESSION_DEFLATE)
		if over.size() == grid.tile_count():
			grid.overlay = over
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
			if not grid.in_bounds(c):
				return false
			if grid.is_occupied(c) and not _cleared_for(data, grid.get_occupant(c)):
				return false
			if not grid.is_explored(c):
				return false   # nothing is placed where the player cannot see
			if (data.allowed_grounds & (1 << grid.get_ground(c))) == 0:
				return false
	if data.must_touch_prefix != "":
		return _touches_free(type, cell, data)
	return true


## What a new building may take the place of (tuned after Stage 10): a tree
## stump (it just disappears), and, for a weapon, a finished wall (the weapon
## is mounted on the wall line and replaces that tile).
func _cleared_for(data: BuildingData, occupant: int) -> bool:
	if not store.is_alive(occupant):
		return false
	var t := store.get_type(occupant)
	if t == "tree_stump":
		return true
	return data.weapon != null and t == "wall" and store.is_complete(occupant)


## Removes what `_cleared_for` lets a new building of `type` replace.
func _clear_footprint(type: String, cell: Vector2i) -> void:
	var data := get_building_data(type)
	if data == null:
		return
	for y in data.size.y:
		for x in data.size.x:
			var c := cell + Vector2i(x, y)
			if grid.in_bounds(c) and grid.is_occupied(c) and _cleared_for(data, grid.get_occupant(c)):
				remove_building(c)


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
	_clear_footprint(type, cell)
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
	_clear_footprint(type, cell)
	var id := _add_building(cell, type, start)
	if id != BuildingStore.NONE:
		building_placed.emit(type, cell)
	return id


## Changes one tile's ground at runtime (lava to cobble) and redraws just
## that tile. The grid announces the change, so pathing updates that tile.
func set_ground_runtime(cell: Vector2i, g: int) -> void:
	if not grid.in_bounds(cell):
		return
	grid.set_ground(cell, g)
	ground_layer.set_cell(cell, _source_ids[g], Vector2i.ZERO)


## Opens or closes every gate (dawn / dusk). The tiles are re-announced, so the
## enemy flow fields pick the change up.
func set_gates_open(open: bool) -> void:
	if open == gates_open:
		return
	gates_open = open
	var tiles := PackedInt32Array()
	for b in store.alive_ids():
		var data := get_building_data(store.get_type(b))
		if data != null and data.is_gate:
			tiles.append(grid.index(store.get_cell(b)))
	grid.touch(tiles)


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
	regions.clear()
	_region_cells.clear()
	_pass_cells.clear()
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
		var file: String = GROUND_FILES[g]
		if g == Ground.SNOW and Art.exists(GROUND_DIR + SNOW_FILE):
			file = SNOW_FILE
		var tex: Texture2D = load(GROUND_DIR + file)
		if tex == null:
			push_error("LevelGenerator: missing ground texture " + file)
			return false
		var source := TileSetAtlasSource.new()
		source.texture = tex
		source.texture_region_size = Vector2i(size, size)
		source.create_tile(Vector2i.ZERO)
		_source_ids[g] = tile_set.add_source(source)
	# Stage 10: mountains. A 16-frame connecting sheet (frame = neighbours that
	# are mountain, N=1 E=2 S=4 W=8), else one tile, else a drawn stand-in.
	var mountain := TileSetAtlasSource.new()
	_mountain_sheet = Art.exists(GROUND_DIR + MOUNTAIN_SHEET)
	if _mountain_sheet:
		mountain.texture = load(GROUND_DIR + MOUNTAIN_SHEET)
		mountain.texture_region_size = Vector2i(size, size)
		for f in 16:
			mountain.create_tile(Vector2i(f, 0))
	else:
		mountain.texture = load(GROUND_DIR + MOUNTAIN_FILE) if Art.exists(GROUND_DIR + MOUNTAIN_FILE) \
			else _stand_in_rock(size)
		mountain.texture_region_size = Vector2i(size, size)
		mountain.create_tile(Vector2i.ZERO)
	_source_ids[Ground.MOUNTAIN] = tile_set.add_source(mountain)

	ground_layer.tile_set = tile_set

	for type in BUILDING_FILES:
		var tex: Texture2D = load(BUILDING_FILES[type])
		if tex == null:
			push_error("LevelGenerator: missing building texture " + BUILDING_FILES[type])
			return false
		_building_textures[type] = tex
	_building_textures["mine_iron"] = Art.texture(IRON_MINE_FILE) if Art.exists(IRON_MINE_FILE) \
		else _grey(_building_textures["mine_gold"])
	_building_textures[CAVE] = Art.texture(CAVE_FILE) if Art.exists(CAVE_FILE) else _stand_in_cave(size)
	for type in POI_FILES:
		_building_textures[type] = Art.texture(POI_FILES[type])
	if not Art.exists(POI_FILES["poi_blueprint_dropped"]):
		_building_textures["poi_blueprint_dropped"] = Art.texture(POI_FILES["poi_blueprint_cache"])

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
	_grass = grid.ground.duplicate()


# --- Regions (Stage 10) --------------------------------------------------------

## Places the region centres: the main chain as a winding walk from the start
## valley, then side valleys off each main region. Tries many layouts (plain
## arithmetic, cheap); false only if none fits.
func _layout_regions() -> bool:
	for attempt in 200:
		if _try_layout():
			return true
	return false


func _try_layout() -> bool:
	regions.clear()
	var size_f := Vector2(map_size)
	var margin := float(valley_radius) * REGION_REACH + 3.0
	if size_f.x <= margin * 2.0 or size_f.y <= margin * 2.0:
		return false
	var start := Vector2i(Vector2(_rng.randf_range(margin, size_f.x - margin),
		_rng.randf_range(margin, size_f.y - margin)).round())
	regions.append(_region(RegionKind.VALLEY, true, -1, start, valley_radius, false))
	var heading := _rng.randf() * TAU
	for n in range(1, MAIN_CHAIN.size()):
		var kind: int = MAIN_CHAIN[n]
		var r := _rng.randi_range(main_radius.x, main_radius.y)
		var placed := false
		for attempt in 60:
			var ang := heading + _rng.randf_range(-1.3, 1.3)
			var c := _try_region_spot(n - 1, r, ang)
			if c == INVALID_CELL:
				continue
			regions.append(_region(kind, true, n - 1, c, r, KIND_DATA[kind]["gate"] != -1))
			heading = ang
			placed = true
			break
		if not placed:
			return false
	var mains := regions.size()
	for parent in mains:
		if _rng.randf() > side_valley_chance:
			continue
		var r := _rng.randi_range(side_radius.x, side_radius.y)
		for attempt in 40:
			var c := _try_region_spot(parent, r, _rng.randf() * TAU)
			if c == INVALID_CELL:
				continue
			var pk: int = regions[parent]["kind"]
			var gated: bool = KIND_DATA[pk]["patch"] != -1 and _rng.randf() < side_gate_chance
			regions.append(_region(pk, false, parent, c, r, gated))
			break
	return true


func _region(kind: int, main: bool, parent: int, center: Vector2i, radius: int, gated: bool) -> Dictionary:
	return {"kind": kind, "main": main, "parent": parent, "center": center, "radius": radius,
		"gated": gated}


## A centre for a region of radius `r` joined to region `from`, in direction
## `ang`, clear of every other region and pass. INVALID_CELL if it will not go.
func _try_region_spot(from: int, r: int, ang: float) -> Vector2i:
	var a: Dictionary = regions[from]
	var ra: int = a["radius"]
	var dist := float(ra + r) * REGION_REACH + float(_rng.randi_range(ridge.x, ridge.y))
	var c := Vector2i((Vector2(a["center"]) + Vector2.RIGHT.rotated(ang) * dist).round())
	var m := float(r) * REGION_REACH + 3.0
	if c.x < m or c.y < m or c.x > map_size.x - 1 - m or c.y > map_size.y - 1 - m:
		return INVALID_CELL
	for i in regions.size():
		var o: Dictionary = regions[i]
		var need := float(r + int(o["radius"])) * REGION_REACH + float(ridge.x)
		if Vector2(c - o["center"]).length() < need:
			return INVALID_CELL
		# The pass must not graze another region...
		if i != from and _segment_distance(Vector2(o["center"]), Vector2(a["center"]), Vector2(c)) \
				< float(o["radius"]) * REGION_REACH + 4.0:
			return INVALID_CELL
	# ...nor another pass.
	for i in range(1, regions.size()):
		var o: Dictionary = regions[i]
		var p: int = o["parent"]
		if p == from or i == from:
			continue
		if _segments_distance(Vector2(a["center"]), Vector2(c), Vector2(regions[p]["center"]),
				Vector2(o["center"])) < 6.0:
			return INVALID_CELL
	return c


## Every region's floor: a noisy disc, kept clear of every other region's
## furthest reach so a ridge always stands between them. Everything else is
## mountain.
func _carve_regions() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.09
	var floor_mask := PackedByteArray()
	floor_mask.resize(grid.tile_count())
	_region_cells.clear()
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		var cells: Array[Vector2i] = []
		var c: Vector2i = reg["center"]
		var r: int = reg["radius"]
		var reach := int(ceil(r * REGION_REACH)) + 1
		for y in range(maxi(c.y - reach, 2), mini(c.y + reach, map_size.y - 3) + 1):
			for x in range(maxi(c.x - reach, 2), mini(c.x + reach, map_size.x - 3) + 1):
				var cell := Vector2i(x, y)
				var d := Vector2(cell - c).length()
				if d > r * (1.0 + REGION_WOBBLE * noise.get_noise_2d(x, y)):
					continue
				var clear := true
				for oi in regions.size():
					if oi == ri:
						continue
					var o: Dictionary = regions[oi]
					if Vector2(cell - o["center"]).length() < float(o["radius"]) * REGION_REACH + 4.0:
						clear = false
						break
				if not clear or floor_mask[grid.index(cell)] != 0:
					continue
				floor_mask[grid.index(cell)] = 1
				grid.region[grid.index(cell)] = ri
				cells.append(cell)
		_region_cells.append(cells)
	for i in grid.tile_count():
		if floor_mask[i] == 0:
			grid.set_ground_at(i, Ground.MOUNTAIN)
		else:
			var f: int = KIND_DATA[regions[grid.region[i]]["kind"]]["floor"]
			if f != -1:
				grid.set_ground_at(i, f)


## The passes: a corridor from each region to its parent, and across its
## ridge (the tiles that were mountain) a band of the region's gate hazard.
func _carve_passes() -> void:
	_pass_cells.clear()
	for ri in range(1, regions.size()):
		var reg: Dictionary = regions[ri]
		var parent: int = reg["parent"]
		var a := Vector2(regions[parent]["center"])
		var b := Vector2(reg["center"])
		var length := a.distance_to(b)
		var ridge_cells: Array[Vector2i] = []
		var ridge_s := PackedFloat32Array()
		var lo := Vector2i((Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(3, 3)).floor())
		var hi := Vector2i((Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(3, 3)).ceil())
		for y in range(maxi(lo.y, 1), mini(hi.y, map_size.y - 2) + 1):
			for x in range(maxi(lo.x, 1), mini(hi.x, map_size.x - 2) + 1):
				var cell := Vector2i(x, y)
				var p := Vector2(cell)
				var t := clampf((p - a).dot(b - a) / (length * length), 0.0, 1.0)
				if p.distance_to(a.lerp(b, t)) > pass_width:
					continue
				var i := grid.index(cell)
				_pass_cells[i] = true
				if grid.ground[i] != Ground.MOUNTAIN:
					continue
				ridge_cells.append(cell)
				ridge_s.append(t * length)
		if ridge_cells.is_empty():
			continue
		var smin := INF
		var smax := -INF
		for sv in ridge_s:
			smin = minf(smin, sv)
			smax = maxf(smax, sv)
		var mid := (smin + smax) * 0.5
		# The ridge's tiles belong to the region on their side of its middle
		# (where a gate's band sits), so a region never starts before its gate.
		for k in ridge_cells.size():
			var side_of := ri if ridge_s[k] >= mid else parent
			var i := grid.index(ridge_cells[k])
			grid.region[i] = side_of
			var f: int = KIND_DATA[regions[side_of]["kind"]]["floor"]
			grid.set_ground_at(i, f if f != -1 else _grass_at(ridge_cells[k]))
		if not reg["gated"]:
			continue
		var kind: int = reg["kind"]
		var hazard: int = KIND_DATA[kind]["gate"] if reg["main"] else KIND_DATA[kind]["patch"]
		if hazard == -1:
			continue
		var half := minf(gate_band * 0.5, (smax - smin) * 0.5 + 0.01)
		for k in ridge_cells.size():
			if absf(ridge_s[k] - mid) <= half:
				grid.set_ground(ridge_cells[k], hazard)


## The grass variant the noise gave this tile before the mountains went in.
func _grass_at(cell: Vector2i) -> int:
	var v: int = _grass[grid.index(cell)]
	return v


## Hazard patches inside the lava fields, the lakes and the void, kept away
## from the passes. Each holds (maybe) a mine and a region cache.
func _paint_patches() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.25
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		var data: Dictionary = KIND_DATA[reg["kind"]]
		if data["patch"] == -1 or not reg["main"]:
			continue
		var count := _rng.randi_range(data["patches"].x, data["patches"].y)
		var cells: Array = _region_cells[ri]
		var made := 0
		for attempt in 300:
			if made >= count or cells.is_empty():
				break
			var r := _rng.randi_range(data["patch_r"].x, data["patch_r"].y)
			var c: Vector2i = cells[_rng.randi() % cells.size()]
			if not _patch_fits(c, r, ri):
				continue
			var painted: Array[Vector2i] = []
			var reach := int(ceil(r * 1.35)) + 1
			for y in range(c.y - reach, c.y + reach + 1):
				for x in range(c.x - reach, c.x + reach + 1):
					var cell := Vector2i(x, y)
					if not grid.in_bounds(cell) or grid.region_of(cell) != ri:
						continue
					if Vector2(cell - c).length() > r * (1.0 + 0.35 * noise.get_noise_2d(x, y)):
						continue
					if not grid.is_grass(grid.get_ground(cell)) or _near_pass(cell, 3):
						continue
					grid.set_ground(cell, data["patch"])
					painted.append(cell)
			if painted.size() < 3:
				continue
			_environments.append({"type": data["patch"], "center": c, "radius": r, "cells": painted,
				"region": ri})
			made += 1
	# Flowers (fruit trees) in the valley and the lakes, away from the start.
	for ri in regions.size():
		var kind: int = regions[ri]["kind"]
		if not regions[ri]["main"] or not (kind == RegionKind.VALLEY or kind == RegionKind.LAKE):
			continue
		var cells: Array = _region_cells[ri]
		for attempt in 30:
			var c: Vector2i = cells[_rng.randi() % cells.size()]
			if Vector2(c - start_cell).length() < start_reveal_radius + 4 or not _patch_fits(c, 3, ri):
				continue
			for y in range(c.y - 4, c.y + 5):
				for x in range(c.x - 4, c.x + 5):
					var cell := Vector2i(x, y)
					if grid.in_bounds(cell) and grid.region_of(cell) == ri and grid.is_grass(grid.get_ground(cell)) \
							and Vector2(cell - c).length() <= 3.5 * (1.0 + 0.3 * noise.get_noise_2d(x, y)) \
							and not _near_pass(cell, 2):
						grid.set_ground(cell, Ground.FLOWERS)
			break


## Two small lakes by the start (tuned after Stage 10), without mines: the
## bucket needs water, and the valley has no other. The first lies inside the
## revealed clearing, the second a little beyond it.
func _place_start_lakes() -> void:
	var cells: Array = _region_cells[0]
	var placed: Array[Vector2i] = []
	var rings := [Vector2(start_open_radius + 3, start_reveal_radius - 2),
		Vector2(start_reveal_radius, start_reveal_radius + 6)]
	for ring: Vector2 in rings:
		for attempt in 120:
			var c: Vector2i = cells[_rng.randi() % cells.size()]
			var d := Vector2(c - start_cell).length()
			if d < ring.x or d > ring.y or _near_pass(c, 4):
				continue
			var crowded := false
			for o in placed:
				if Vector2(c - o).length() < 8.0:
					crowded = true
			if crowded:
				continue
			var painted := 0
			for y in range(c.y - 2, c.y + 3):
				for x in range(c.x - 2, c.x + 3):
					var cell := Vector2i(x, y)
					if not grid.in_bounds(cell) or grid.region_of(cell) != 0 \
							or not grid.is_grass(grid.get_ground(cell)):
						continue
					if Vector2(cell - c).length() <= 1.6 + 0.6 * _rng.randf():
						grid.set_ground(cell, Ground.WATER)
						painted += 1
			if painted >= 4:
				placed.append(c)
				break


## Room for a patch of radius `r` at `c` in region `ri`: inside the region,
## off the passes, clear of the start clearing and of other patches.
func _patch_fits(c: Vector2i, r: int, ri: int) -> bool:
	if Vector2(c - start_cell).length() < start_open_radius + r + 3:
		return false
	if _near_pass(c, r + 1):
		return false
	for env in _environments:
		if Vector2(c - env["center"]).length() < r + int(env["radius"]) + 2:
			return false
	var h := int(ceil(r * 0.6))
	for dy in [-h, 0, h]:
		for dx in [-h, 0, h]:
			var n := c + Vector2i(dx, dy)
			if not grid.in_bounds(n) or grid.region_of(n) != ri:
				return false
	return true


func _near_pass(cell: Vector2i, dist: int) -> bool:
	for dy in range(-dist, dist + 1):
		for dx in range(-dist, dist + 1):
			var n := cell + Vector2i(dx, dy)
			if grid.in_bounds(n) and _pass_cells.has(grid.index(n)):
				return true
	return false


## Mines and region caches inside the hazard patches. The first patch of each
## region always gets both.
func _place_patch_contents() -> void:
	var first := {}
	var cached := {}
	for env in _environments:
		var ri: int = env["region"]
		var data: Dictionary = KIND_DATA[regions[ri]["kind"]]
		var is_first := not first.has(ri)
		first[ri] = true
		if data["mine"] != "" and (is_first or _rng.randf() < mine_chance):
			var cell := _pick_interior_cell(env)
			_surround(cell, env["type"])
			_add_building(cell, data["mine"])
		if is_first or _rng.randf() < region_cache_chance:
			var cell := _pick_interior_cell(env, 2)
			if cell == INVALID_CELL and is_first and not grid.is_occupied(env["center"]):
				cell = env["center"]   # a small patch: _surround grows it round the cache
			if cell == INVALID_CELL and is_first:
				cell = _pick_interior_cell(env, 1)
			if cell != INVALID_CELL:
				_surround(cell, env["type"])
				_add_building(cell, PointsOfInterest.BLUEPRINT_CACHE)
				cached[ri] = true
	# Every hazard region must hold a cache (the lava and lake ones hold the
	# next gate's key): if no patch had room, one goes on its floor.
	for ri in first:
		if not cached.has(ri):
			_place_on_floor(ri, PointsOfInterest.BLUEPRINT_CACHE, 2)


## The snowfield has no patches: its diamonds and caches lie on the snow.
func _place_snow_contents() -> void:
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		if reg["kind"] != RegionKind.SNOW or not reg["main"]:
			continue
		var data: Dictionary = KIND_DATA[RegionKind.SNOW]
		var mines := _rng.randi_range(data["floor_mines"].x, data["floor_mines"].y)
		for n in mines:
			_place_on_floor(ri, data["mine"], 3)
		_place_on_floor(ri, PointsOfInterest.BLUEPRINT_CACHE, 3)
		if _rng.randf() < region_cache_chance:
			_place_on_floor(ri, PointsOfInterest.BLUEPRINT_CACHE, 3)


## Each side valley holds a find: a cache of its region's tier or relics, and
## maybe one more mine of its parent's kind.
func _place_side_valley_contents() -> void:
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		if reg["main"]:
			continue
		var kind: int = reg["kind"]
		var poi := PointsOfInterest.BLUEPRINT_CACHE if _rng.randf() < 0.5 else PointsOfInterest.RELIC_CACHE
		_place_on_floor(ri, poi, 2)
		if _rng.randf() < 0.5:
			match kind:
				RegionKind.VALLEY:
					_place_on_floor(ri, "mine_gold" if _rng.randf() < 0.5 else "mine_iron", 2)
				RegionKind.SNOW:
					_place_on_floor(ri, "mine_diamond", 2)
				RegionKind.LAVA, RegionKind.LAKE:
					var cell := _place_on_floor(ri, KIND_DATA[kind]["mine"], 2)
					if cell != INVALID_CELL:
						_surround(cell, KIND_DATA[kind]["patch"])


## Puts `type` on a free floor tile of region `ri` (grass or snow, floor all
## round, nothing within `spacing`, off the passes). Returns the cell or
## INVALID_CELL.
func _place_on_floor(ri: int, type: String, spacing: int) -> Vector2i:
	var cells: Array = _region_cells[ri]
	if cells.is_empty():
		return INVALID_CELL
	for attempt in 60:
		var c: Vector2i = cells[_rng.randi() % cells.size()]
		if grid.region_of(c) != ri or not _is_floor(grid.get_ground(c)) or _near_pass(c, 1):
			continue
		if Vector2(c - start_cell).length() <= start_reveal_radius + 1 and type.begins_with("poi_"):
			continue
		var ok := true
		for n in _neighbors(c):
			if not grid.in_bounds(n) or not _is_floor(grid.get_ground(n)):
				ok = false
				break
		if not ok or _building_within(c, spacing):
			continue
		_add_building(c, type)
		return c
	return INVALID_CELL


func _is_floor(g: int) -> bool:
	return grid.is_grass(g) or g == Ground.SNOW or g == Ground.FLOWERS or g == Ground.SAND


## Cave mouths: mountain tiles on a region's rim with a walkable floor tile
## in front (the exit), spread apart, away from the start.
func _place_caves() -> void:
	var placed: Array[Vector2i] = []
	for ri in regions.size():
		var reg: Dictionary = regions[ri]
		if not reg["main"]:
			continue
		var want: int = CAVES[MAIN_CHAIN.find(reg["kind"])]
		var spots: Array[Vector2i] = []
		for c: Vector2i in _region_cells[ri]:
			if not _is_floor(grid.get_ground(c)) or _near_pass(c, 2):
				continue
			if Vector2(c - reg["center"]).length() < float(reg["radius"]) * 0.55:
				continue
			if Vector2(c - start_cell).length() < 12.0:
				continue
			for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var m: Vector2i = c + d
				if grid.in_bounds(m) and grid.get_ground(m) == Ground.MOUNTAIN and not grid.is_occupied(m):
					spots.append(m)
		_shuffle(spots)
		var made := 0
		for m in spots:
			if made >= want:
				break
			var crowded := false
			for o in placed:
				if Vector2(m - o).length() < 12.0:
					crowded = true
					break
			if crowded or cave_exit_of(m) == INVALID_CELL:
				continue
			_add_building(m, CAVE)
			placed.append(m)
			made += 1


## The walkable tile in front of a cave mouth, or INVALID_CELL.
func cave_exit_of(cell: Vector2i) -> Vector2i:
	for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var n: Vector2i = cell + d
		if grid.in_bounds(n) and not grid.is_occupied(n) and _is_floor(grid.get_ground(n)):
			return n
	return INVALID_CELL


## Every cave mouth on the map (building ids).
func caves() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in store.alive_ids():
		if store.get_type(id) == CAVE:
			out.append(id)
	return out


## The check that makes the chain a chain: walking on the ground alone (no
## bridges, no cobble), each group of regions joined by open passes is cut off
## from every other. A leak means the layout is redrawn.
func _chain_sealed() -> bool:
	var group := PackedInt32Array()
	group.resize(regions.size())
	for ri in regions.size():
		var g := ri
		while not regions[g]["gated"] and regions[g]["parent"] != -1:
			g = regions[g]["parent"]
		group[ri] = g
	var comp := _components()
	var seen := {}   # component -> group
	for ri in regions.size():
		for c: Vector2i in _region_cells[ri]:
			var k := comp[grid.index(c)]
			if k < 0:
				continue
			if seen.has(k) and seen[k] != group[ri]:
				return false
			seen[k] = group[ri]
	return true


## Walkable components of the bare ground (buildings ignored), -1 elsewhere.
func _components() -> PackedInt32Array:
	var comp := PackedInt32Array()
	comp.resize(grid.tile_count())
	comp.fill(-1)
	var w := map_size.x
	var next := 0
	for start in grid.tile_count():
		if comp[start] != -1 or (int(WorldGrid.GROUND_BLOCKING[grid.ground[start]]) & WorldGrid.BLOCKS_UNIT) != 0:
			continue
		var stack := PackedInt32Array([start])
		comp[start] = next
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			@warning_ignore("integer_division")
			var y := i / w
			var x := i % w
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= map_size.y:
					continue
				var j := ny * w + nx
				if comp[j] != -1 or (int(WorldGrid.GROUND_BLOCKING[grid.ground[j]]) & WorldGrid.BLOCKS_UNIT) != 0:
					continue
				comp[j] = next
				stack.append(j)
		next += 1
	return comp


## The tier of the region a cell lies in: what a cache there holds. Maps from
## before Stage 10 fall back to the ground under it.
func region_tier(cell: Vector2i) -> int:
	var ri := grid.region_of(cell)
	if ri != WorldGrid.NO_REGION and ri < regions.size():
		return KIND_TIER[regions[ri]["kind"]]
	return int(REGION_TIER.get(grid.get_ground(cell), 1))


## The region kind at a cell (RegionKind), or -1.
func region_kind(cell: Vector2i) -> int:
	var ri := grid.region_of(cell)
	return regions[ri]["kind"] if ri != WorldGrid.NO_REGION and ri < regions.size() else -1


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _segments_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(_segment_distance(a, c, d), _segment_distance(b, c, d)),
		minf(_segment_distance(c, a, b), _segment_distance(d, a, b)))


## Prefers a cell whose 8 neighbors already match; falls back to the patch
## center. With `spacing`, only cells at least that far (in tiles, Chebyshev)
## from any building, and INVALID_CELL if there is none.
func _pick_interior_cell(env: Dictionary, spacing := 0) -> Vector2i:
	var type: int = env["type"]
	var candidates: Array[Vector2i] = []
	for c in env["cells"]:
		if grid.is_occupied(c):
			continue
		if spacing > 0 and _building_within(c, spacing):
			continue
		var interior := true
		for n in _neighbors(c):
			if grid.get_ground(n) != type:
				interior = false
				break
		if interior:
			candidates.append(c)
	if candidates.is_empty():
		if spacing > 0:
			return INVALID_CELL
		return env["center"]
	return candidates[_rng.randi() % candidates.size()]


func _building_within(cell: Vector2i, spacing: int) -> bool:
	for dy in range(-spacing, spacing + 1):
		for dx in range(-spacing, spacing + 1):
			var n := cell + Vector2i(dx, dy)
			if grid.in_bounds(n) and grid.is_occupied(n):
				return true
	return false


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
			elif g == Ground.SNOW:
				if _rng.randf() < tree_chance_snow:
					_add_building(c, "tree")


## Stage 9: the start valley's metals. One gold and one iron mine sit on the
## open grass just inside the revealed clearing, on opposite sides, so a run
## can mine from the first minute; gold pays for workers, iron for the
## pickaxe, arrow upgrades and gates.
func _place_start_mines() -> void:
	var dist := float(start_reveal_radius - 2)
	var angle := _rng.randf() * TAU
	for type in ["mine_gold", "mine_iron"]:
		for attempt in 80:
			# First near the chosen side; then anywhere in the clearing.
			var a := angle + _rng.randf_range(-0.6, 0.6) if attempt < 24 else _rng.randf() * TAU
			var d := dist if attempt < 24 else _rng.randf_range(start_open_radius, start_reveal_radius - 1)
			var c := start_cell + Vector2i((Vector2.RIGHT.rotated(a) * d).round())
			if _free_grass(c, 1):
				_add_building(c, type)
				break
		angle += PI


## More gold and iron in the start valley, beyond the clearing.
func _place_valley_mines() -> void:
	for type in valley_mines:
		for n in valley_mines[type]:
			for attempt in 60:
				var cells: Array = _region_cells[0]
				var c: Vector2i = cells[_rng.randi() % cells.size()]
				if Vector2(c - start_cell).length() < start_reveal_radius + 2 or not _free_grass(c, 2) \
						or _near_pass(c, 1):
					continue
				_add_building(c, type)
				break


## Points of interest (Stage 10): each type in the regions it belongs to --
## tier-1 caches in the valley and its side valleys, relics in side valleys
## first, the NPC house by the lava or the lakes, the fruit tree by the lakes
## or in the snow. Never in the start clearing, spaced apart.
func _place_points_of_interest() -> void:
	var prefer := {
		PointsOfInterest.BLUEPRINT_CACHE: [RegionKind.VALLEY],
		PointsOfInterest.RELIC_CACHE: [RegionKind.LAVA, RegionKind.LAKE, RegionKind.SNOW, RegionKind.VOID],
		PointsOfInterest.NPC_HOUSE: [RegionKind.LAVA, RegionKind.LAKE],
		PointsOfInterest.FRUIT_TREE: [RegionKind.LAKE, RegionKind.SNOW],
	}
	var placed: Array[Vector2i] = []
	for id in store.alive_ids():
		if store.get_type(id).begins_with(PointsOfInterest.PREFIX):
			placed.append(store.get_cell(id))
	for type in poi_counts:
		if not POI_FILES.has(type):
			push_warning("LevelGenerator: unknown point of interest '%s'." % type)
			continue
		var kinds: Array = prefer.get(type, [])
		for n in poi_counts[type]:
			# Side valleys first for relics; then the preferred regions; then anywhere.
			var pools: Array = []
			if type == PointsOfInterest.RELIC_CACHE:
				pools.append(_regions_where(func(reg): return not reg["main"]))
			pools.append(_regions_where(func(reg): return kinds.has(reg["kind"])))
			pools.append(_regions_where(func(_reg): return true))
			for pool in pools:
				if _place_poi_in(type, pool, placed):
					break


func _regions_where(test: Callable) -> Array:
	var out := []
	for ri in regions.size():
		if test.call(regions[ri]):
			out.append(ri)
	return out


func _place_poi_in(type: String, pool: Array, placed: Array[Vector2i]) -> bool:
	if pool.is_empty():
		return false
	for attempt in 80:
		var ri: int = pool[_rng.randi() % pool.size()]
		var cells: Array = _region_cells[ri]
		if cells.is_empty():
			continue
		var c: Vector2i = cells[_rng.randi() % cells.size()]
		if grid.is_occupied(c) or not _is_floor(grid.get_ground(c)) or _near_pass(c, 1):
			continue
		if Vector2(c - start_cell).length() < poi_min_distance:
			continue
		var crowded := false
		for other in placed:
			if Vector2(c - other).length() < poi_spacing:
				crowded = true
				break
		if crowded:
			continue
		_add_building(c, type)
		placed.append(c)
		return true
	return false


## Grass, in bounds, with nothing built within `spacing` tiles and grass all
## round (a mine needs room for its miner house).
func _free_grass(cell: Vector2i, spacing: int) -> bool:
	if not grid.in_bounds(cell) or not grid.is_grass(grid.get_ground(cell)):
		return false
	for n in _neighbors(cell):
		if not grid.in_bounds(n) or not grid.is_grass(grid.get_ground(n)):
			return false
	return not _building_within(cell, spacing)


## A grey copy of a texture: the stand-in for a sprite not drawn yet.
static func _grey(tex: Texture2D) -> Texture2D:
	if tex == null:
		return Art.fallback()
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var v := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			img.set_pixel(x, y, Color(v * 0.95, v * 0.97, v * 1.05, c.a))
	return ImageTexture.create_from_image(img)


## Tops the clearing up to start_trees plain trees, between the base's open
## grass and the edge of the revealed area.
func _ensure_start_trees() -> void:
	var have := 0
	var spots: Array = []
	for y in range(start_cell.y - start_reveal_radius, start_cell.y + start_reveal_radius + 1):
		for x in range(start_cell.x - start_reveal_radius, start_cell.x + start_reveal_radius + 1):
			var c := Vector2i(x, y)
			if not grid.in_bounds(c):
				continue
			var d := Vector2(c - start_cell).length()
			if d > start_reveal_radius - 1:
				continue
			var id := grid.get_occupant(c)
			if id != WorldGrid.NO_OCCUPANT:
				if store.get_type(id) == "tree":
					have += 1
				continue
			if d >= 3.0 and grid.is_grass(grid.get_ground(c)):
				spots.append(c)
	_shuffle(spots)
	for c in spots:
		if have >= start_trees:
			break
		_add_building(c, "tree")
		have += 1


## The middle tile (rounded down on even sizes, on purpose).
func _map_centre() -> Vector2i:
	@warning_ignore("integer_division")
	return map_size / 2


## A new map is dark except the start clearing.
func _fog_all_but_start() -> void:
	grid.explored.fill(WorldGrid.UNEXPLORED)
	grid.reveal_circle(start_cell, start_reveal_radius)


func _draw_ground() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			var g := grid.get_ground(c)
			var frame := Vector2i.ZERO
			if g == Ground.MOUNTAIN and _mountain_sheet:
				frame = Vector2i(_mountain_mask(c), 0)
			ground_layer.set_cell(c, _source_ids[g], frame)


## Which neighbours are mountain too (N=1 E=2 S=4 W=8); off the map counts.
func _mountain_mask(c: Vector2i) -> int:
	var m := 0
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for k in 4:
		var n: Vector2i = c + dirs[k]
		if not grid.in_bounds(n) or grid.get_ground(n) == Ground.MOUNTAIN:
			m |= 1 << k
	return m


## A dark, speckled rock tile until ground_mountain.png exists.
static func _stand_in_rock(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in size:
		for x in size:
			var v := 0.26 + rng.randf() * 0.07 + (0.05 if (x + y) % 11 == 0 else 0.0)
			img.set_pixel(x, y, Color(v, v * 0.95, v * 0.9))
	return ImageTexture.create_from_image(img)


## A dark arch in the rock until cave.png exists.
static func _stand_in_cave(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size * 0.5, size * 0.85)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			if d.y < 0.0 and d.length() < size * 0.42 or (d.y >= 0.0 and absf(d.x) < size * 0.42 and y < size - 1):
				img.set_pixel(x, y, Color(0.05, 0.04, 0.05, 0.95))
			elif d.length() < size * 0.48 and d.y < 0.0:
				img.set_pixel(x, y, Color(0.18, 0.16, 0.15, 1.0))
	return ImageTexture.create_from_image(img)


## Registers a building, claims its tiles and creates its sprite.
## Returns the new building id, or BuildingStore.NONE if the type is unknown.
func _add_building(cell: Vector2i, type: String, progress: float = 1.0) -> int:
	# Generated buildings (mines, trees) use BUILDING_FILES and are 1x1.
	# Player buildings come from BuildingData and can be bigger.
	var texture: Texture2D = _building_textures.get(type)
	var size := Vector2i.ONE
	var block_flags := 0 if WALK_OVER.has(type) else WorldGrid.BLOCKS_UNIT
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
