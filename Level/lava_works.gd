class_name LavaWorks
extends RefCounted
## Turning lava into cobble (Stage 2c), and the bucket that makes it possible.
##
## The player paints marks on lava tiles. Once the run owns the WATER bucket,
## builders cobble marked tiles they can reach, for builder time only. Before
## that, the player takes the empty bucket from the item bar and clicks a
## water tile, the same way a building is placed; that tile becomes the one
## FILL job. The bucket lives in the run's Unlocks ("item:bucket" once
## crafted, "item:water_bucket" once filled), so it is saved and never lost.
##
## Jobs are TILES, not buildings: JobBoard.COBBLE lists marked lava tile
## indices and JobBoard.FILL lists water tiles a builder can stand next to.

signal marks_changed
## The water tile chosen for filling changed (or was reached).
signal fill_target_changed

const ITEM_BUCKET := "item:bucket"
const ITEM_WATER_BUCKET := "item:water_bucket"
const Ground := WorldGrid.Ground
const NONE := -1

## Builder-seconds (BUILD_SPEED * dt) to turn one lava tile into cobble.
var cobble_work := 3.0
## Builder-seconds to fill the bucket at the water's edge.
var fill_work := 2.0

var level: LevelGenerator
var unlocks: Unlocks

var _marked := {}      # tile index -> true
var _progress := {}    # tile index -> builder-seconds so far
var _fill_progress := 0.0
## Tile the player sent the bucket to, or NONE.
var _fill_target := NONE


func setup(p_level: LevelGenerator, p_unlocks: Unlocks) -> void:
	level = p_level
	unlocks = p_unlocks
	level.level_generated.connect(_on_level_generated)


func clear() -> void:
	_marked.clear()
	_progress.clear()
	_fill_progress = 0.0
	_fill_target = NONE
	marks_changed.emit()
	fill_target_changed.emit()


func _on_level_generated() -> void:
	_fill_target = NONE


# --- The bucket ---------------------------------------------------------------

func has_bucket() -> bool:
	return unlocks.has(ITEM_BUCKET) or unlocks.has(ITEM_WATER_BUCKET)


func has_water_bucket() -> bool:
	return unlocks.has(ITEM_WATER_BUCKET)


## Water with walkable ground beside it: where the bucket can be sent.
func can_fill_at(i: int) -> bool:
	var g := level.grid
	if i < 0 or i >= g.ground.size() or g.ground[i] != Ground.WATER:
		return false
	var c := g.cell_at(i)
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var side: Vector2i = c + n
		if g.in_bounds(side) and g.is_passable_at(g.index(side)):
			return true
	return false


func fill_target() -> int:
	return _fill_target


## The player sends the empty bucket to a water tile. Returns false if that
## tile is no good (not water, or nothing walkable beside it).
func set_fill_target(i: int) -> bool:
	if has_water_bucket() or not has_bucket() or not can_fill_at(i):
		return false
	_fill_target = i
	_fill_progress = 0.0
	fill_target_changed.emit()
	return true


## JobBoard.FILL: the one water tile the player chose, while the bucket is
## empty. Nothing until then: builders do not go looking for water.
func fill_jobs() -> PackedInt32Array:
	if not has_bucket() or has_water_bucket() or not can_fill_at(_fill_target):
		return PackedInt32Array()
	return PackedInt32Array([_fill_target])


## Adds builder work to filling the bucket. Returns true on the call that
## fills it.
func fill(work: float) -> bool:
	if has_water_bucket() or not has_bucket():
		return false
	_fill_progress += work
	if _fill_progress < fill_work:
		return false
	_fill_target = NONE
	unlocks.add(ITEM_WATER_BUCKET)
	marks_changed.emit()   # cobble jobs may start now
	fill_target_changed.emit()
	return true


# --- Marks and cobble ------------------------------------------------------------

## Free lava: the only tiles that can be marked.
func is_markable(i: int) -> bool:
	return level.grid.ground[i] == Ground.LAVA and level.grid.get_occupant_at(i) == WorldGrid.NO_OCCUPANT


func is_marked(i: int) -> bool:
	return _marked.has(i)


## Marks or unmarks one tile. Returns true if anything changed.
func set_mark(i: int, on: bool) -> bool:
	if on == _marked.has(i):
		return false
	if on:
		if not is_markable(i):
			return false
		_marked[i] = true
	else:
		_marked.erase(i)
	marks_changed.emit()
	return true


func marked_tiles() -> PackedInt32Array:
	return PackedInt32Array(_marked.keys())


## JobBoard.COBBLE: marked lava, but only once there is water to cool it.
func cobble_jobs() -> PackedInt32Array:
	if not has_water_bucket():
		return PackedInt32Array()
	return marked_tiles()


## Adds builder work to a marked tile. Returns true on the call that turns it
## into cobble (it is unmarked then).
func cobble(i: int, work: float) -> bool:
	if not _marked.has(i) or not has_water_bucket() or level.grid.ground[i] != Ground.LAVA:
		return false
	var done: float = float(_progress.get(i, 0.0)) + work
	if done < cobble_work:
		_progress[i] = done
		return false
	_marked.erase(i)
	_progress.erase(i)
	level.set_ground_runtime(level.grid.cell_at(i), Ground.COBBLE)
	marks_changed.emit()
	return true


func tile_pos(i: int) -> Vector2:
	return level.cell_to_world(level.grid.cell_at(i))


# --- Saving -------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var marked: Array[Vector2i] = []
	for i in _marked:
		marked.append(level.grid.cell_at(i))
	var cells: Array[Vector2i] = []
	var work := PackedFloat32Array()
	for i in _progress:
		cells.append(level.grid.cell_at(i))
		work.append(_progress[i])
	var target = null
	if _fill_target != NONE and level.grid.in_bounds(level.grid.cell_at(_fill_target)):
		target = level.grid.cell_at(_fill_target)
	return {"marked": marked, "progress_cells": cells, "progress": work,
		"fill": _fill_progress, "fill_target": target}


## Call after the level has loaded.
func load_save_data(data: Dictionary) -> void:
	clear()
	for c in data.get("marked", []):
		if level.grid.in_bounds(c):
			set_mark(level.grid.index(c), true)
	var cells: Array = data.get("progress_cells", [])
	var work: PackedFloat32Array = data.get("progress", PackedFloat32Array())
	for n in mini(cells.size(), work.size()):
		if level.grid.in_bounds(cells[n]):
			_progress[level.grid.index(cells[n])] = work[n]
	_fill_progress = float(data.get("fill", 0.0))
	if data.get("fill_target") != null and level.grid.in_bounds(data["fill_target"]):
		_fill_target = level.grid.index(data["fill_target"])
	marks_changed.emit()
	fill_target_changed.emit()
