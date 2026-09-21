class_name UnitPathing
extends RefCounted
## Paths for workers and carriers, using Godot's native AStarGrid2D.
##
## Kept in step with WorldGrid: rebuilt once when a map is generated or loaded,
## then updated only for the tiles WorldGrid announces through tiles_changed.
## Impassable tiles are solid; every other tile's weight is its movement cost,
## relative to open ground. Enemies do not use this: they use shared flow
## fields (D5), because hundreds of them would each need a path.

var astar := AStarGrid2D.new()
var _grid: WorldGrid


func rebuild(grid: WorldGrid) -> void:
	if _grid != null and _grid.tiles_changed.is_connected(_on_tiles_changed):
		_grid.tiles_changed.disconnect(_on_tiles_changed)
	_grid = grid
	astar.region = Rect2i(Vector2i.ZERO, grid.size)
	astar.cell_size = Vector2.ONE
	# No cutting corners past a blocked tile: a unit squeezing diagonally
	# between two buildings looks wrong and walks through walls' corners.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for i in grid.tile_count():
		_apply(i)
	grid.tiles_changed.connect(_on_tiles_changed)


func _on_tiles_changed(indices: PackedInt32Array) -> void:
	for i in indices:
		_apply(i)


func _apply(i: int) -> void:
	var cell := _grid.cell_at(i)
	if not _grid.is_passable_at(i):
		astar.set_point_solid(cell, true)
		return
	astar.set_point_solid(cell, false)
	astar.set_point_weight_scale(cell, float(_grid.get_cost_at(i)) / WorldGrid.COST_OPEN)


## Cells from `from` to `to`, both included. Empty if unreachable.
func cells_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not astar.is_in_boundsv(from) or not astar.is_in_boundsv(to):
		return out
	var restore := _open(from)
	var restore_to := _open(to)
	out.assign(astar.get_id_path(from, to))
	_close(from, restore)
	_close(to, restore_to)
	return out


## Cells from `from` to the nearest tile touching a building, stopping BEFORE
## the building itself. Empty if the building cannot be reached. A unit already
## standing next to it gets a one-cell path: [from].
func cells_to_building(from: Vector2i, origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not astar.is_in_boundsv(from) or not astar.is_in_boundsv(origin):
		return out
	var footprint := Rect2i(origin, size)
	# Open the footprint so A* can aim at it, then cut the path where it enters.
	var opened: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			if astar.is_in_boundsv(c) and astar.is_point_solid(c):
				astar.set_point_solid(c, false)
				opened.append(c)
	var restore := _open(from)
	var raw := astar.get_id_path(from, origin)
	_close(from, restore)
	for c in opened:
		astar.set_point_solid(c, true)
	for c in raw:
		if footprint.has_point(c):
			break
		out.append(c)
	return out


## A unit can be standing on a tile that has just become solid -- a house was
## built on it. Its own tile must not stop it from walking away.
func _open(cell: Vector2i) -> bool:
	if astar.is_point_solid(cell):
		astar.set_point_solid(cell, false)
		return true
	return false


func _close(cell: Vector2i, was_solid: bool) -> void:
	if was_solid:
		astar.set_point_solid(cell, true)
