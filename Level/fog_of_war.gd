class_name FogOfWar
extends RefCounted
## What the player has seen (Stage 3b). The data is WorldGrid.explored, saved
## with the level; this class decides when tiles get explored and tells the
## renderer and the points of interest about it.
##
## Units reveal a disc around themselves only when they CROSS INTO A NEW TILE,
## never every tick: a unit standing still, or walking inside ground that is
## already known, costs one integer compare. Only walking units are checked at
## all -- a unit that is not moving cannot see anything new.
##
## Exploration is two-state (seen / never seen). Nothing is re-hidden when a
## unit walks away; "currently in sight" can be added for enemies in Stage 4
## as a second layer without touching this one.

## Tiles just explored (their indices). Emitted once per reveal that uncovered
## anything, never for a reveal of already-known ground.
signal revealed(indices: PackedInt32Array)

## Tiles every worker reveals around itself as it walks.
var worker_radius := 2
## Tiles the explorer reveals around itself as it walks.
var explorer_radius := 6

var level: LevelGenerator
## Per unit id: the tile it last revealed from, or -1. Unit ids are pooled; a
## recycled id at worst costs one extra (harmless) reveal.
var _last := PackedInt32Array()
## World position of tile (0, 0)'s top-left corner, and the tile size: world to
## cell in plain arithmetic, because world_to_cell goes through the TileMapLayer
## (two engine calls) and this runs for every walking unit every tick.
var _origin := Vector2.ZERO
var _tile := 32.0


func setup(p_level: LevelGenerator) -> void:
	level = p_level
	# Methods, not lambdas (see WorkerRoster.attach).
	level.level_generated.connect(_on_level_generated)
	level.construction_completed.connect(_on_construction_completed)
	level.building_placed.connect(_on_building_placed)


func _on_level_generated() -> void:
	_last.fill(-1)
	_tile = float(level.ground_layer.tile_set.tile_size.x)
	_origin = level.cell_to_world(Vector2i.ZERO) - Vector2(_tile, _tile) / 2.0


func is_explored(cell: Vector2i) -> bool:
	return level.grid.in_bounds(cell) and level.grid.is_explored(cell)


## Explores a disc. Returns how many tiles were new.
func reveal_circle(cell: Vector2i, radius: int) -> int:
	var fresh := level.grid.reveal_circle(cell, radius)
	if not fresh.is_empty():
		revealed.emit(fresh)
	return fresh.size()


## Dev shortcut: the whole map at once.
func reveal_all() -> void:
	var g := level.grid
	var fresh := PackedInt32Array()
	for i in g.tile_count():
		if g.explored[i] == WorldGrid.UNEXPLORED:
			fresh.append(i)
	if fresh.is_empty():
		return
	g.explored.fill(WorldGrid.EXPLORED)
	revealed.emit(fresh)


## True while any tile is still hidden (the renderer skips drawing otherwise).
func any_hidden() -> bool:
	return level.grid.explored.find(WorldGrid.UNEXPLORED) != -1


## One simulation tick: walking units that entered a new tile look around.
func step_units(store: UnitStore) -> void:
	var n := store.size()
	if _last.size() < n:
		var old := _last.size()
		_last.resize(n)
		for i in range(old, n):
			_last[i] = -1
	var g := level.grid
	var w := g.size.x
	var inv := 1.0 / _tile
	for id in n:
		if store.state[id] != UnitStore.State.WALKING or not store.is_alive(id):
			continue
		var p := (store.pos[id] - _origin) * inv
		var cx := floori(p.x)
		var cy := floori(p.y)
		if cx < 0 or cy < 0 or cx >= w or cy >= g.size.y:
			continue
		var i := cy * w + cx
		if i == _last[id]:
			continue
		_last[id] = i
		var r := explorer_radius if store.kind[id] == WorkerRoster.Kind.EXPLORER else worker_radius
		reveal_circle(Vector2i(cx, cy), r)


## A building placed already finished (no build work) looks around at once.
func _on_building_placed(_type: String, cell: Vector2i) -> void:
	var id := level.grid.get_occupant(cell)
	if level.store.is_alive(id) and level.store.is_complete(id):
		_on_construction_completed(id)


## A finished building with a reveal radius (the watchtower) clears the fog
## around it, once.
func _on_construction_completed(id: int) -> void:
	var data := level.get_building_data(level.store.get_type(id))
	if data == null or data.reveal_radius <= 0:
		return
	# The footprint's middle tile (rounded down for even sizes, on purpose).
	@warning_ignore("integer_division")
	var middle := level.store.get_size(id) / 2
	reveal_circle(level.store.get_cell(id) + middle, data.reveal_radius)
