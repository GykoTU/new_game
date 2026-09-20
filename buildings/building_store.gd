class_name BuildingStore
extends RefCounted
## Every building on the map, as parallel arrays addressed by a stable integer id.
##
## Replaces the old `buildings` and `_occupied` dictionaries keyed by Vector2i.
## Two reasons. First, a dictionary keyed by Vector2i costs far more memory and
## lookup time than a flat array at 65k tiles. Second, buildings are about to
## grow state -- health, build progress, worker slots, cooldowns -- and a
## `Dictionary -> String` cannot carry that without becoming a dictionary of
## dictionaries.
##
## Ids are handed out from a free list and reused after removal, so an id is
## only meaningful while `is_alive(id)` is true. Never cache an id across a
## removal without checking.

const NONE := -1

## Default until BuildingData carries real values (Stage 1).
const DEFAULT_MAX_HEALTH := 100.0

var _type := PackedStringArray()
var _cell_x := PackedInt32Array()
var _cell_y := PackedInt32Array()
var _size_x := PackedInt32Array()
var _size_y := PackedInt32Array()
var _health := PackedFloat32Array()
var _max_health := PackedFloat32Array()
var _alive := PackedByteArray()
## Node references cannot live in a packed array. Parallel to the rest by index.
var _sprite: Array[Sprite2D] = []

var _free := PackedInt32Array()
## type -> PackedInt32Array of live ids, so "every gold mine" is not a full scan.
var _by_type := {}
var _live_count := 0


func clear() -> void:
	_type.clear(); _cell_x.clear(); _cell_y.clear()
	_size_x.clear(); _size_y.clear()
	_health.clear(); _max_health.clear(); _alive.clear()
	_sprite.clear(); _free.clear(); _by_type.clear()
	_live_count = 0


func add(type: String, cell: Vector2i, size: Vector2i, sprite: Sprite2D,
		max_health: float = DEFAULT_MAX_HEALTH) -> int:
	var id: int
	if _free.is_empty():
		id = _type.size()
		_type.append(type)
		_cell_x.append(cell.x); _cell_y.append(cell.y)
		_size_x.append(size.x); _size_y.append(size.y)
		_health.append(max_health); _max_health.append(max_health)
		_alive.append(1)
		_sprite.append(sprite)
	else:
		id = _free[_free.size() - 1]
		_free.remove_at(_free.size() - 1)
		_type[id] = type
		_cell_x[id] = cell.x; _cell_y[id] = cell.y
		_size_x[id] = size.x; _size_y[id] = size.y
		_health[id] = max_health; _max_health[id] = max_health
		_alive[id] = 1
		_sprite[id] = sprite

	if not _by_type.has(type):
		_by_type[type] = PackedInt32Array()
	var ids: PackedInt32Array = _by_type[type]
	ids.append(id)
	_by_type[type] = ids
	_live_count += 1
	return id


func remove(id: int) -> void:
	if not is_alive(id):
		return
	var type := _type[id]
	if _by_type.has(type):
		var ids: PackedInt32Array = _by_type[type]
		var at := ids.find(id)
		if at != -1:
			ids.remove_at(at)
		_by_type[type] = ids
	_alive[id] = 0
	_sprite[id] = null
	_free.append(id)
	_live_count -= 1


func is_alive(id: int) -> bool:
	return id >= 0 and id < _alive.size() and _alive[id] == 1


func count() -> int:
	return _live_count


# --- Field access -------------------------------------------------------------

func get_type(id: int) -> String:
	return _type[id]


func get_cell(id: int) -> Vector2i:
	return Vector2i(_cell_x[id], _cell_y[id])


func get_size(id: int) -> Vector2i:
	return Vector2i(_size_x[id], _size_y[id])


func get_sprite(id: int) -> Sprite2D:
	return _sprite[id]


func get_health(id: int) -> float:
	return _health[id]


func get_max_health(id: int) -> float:
	return _max_health[id]


## Returns the health remaining. Reaching 0 does not remove the building here --
## the caller decides, because removal also has to release grid tiles.
func damage(id: int, amount: float) -> float:
	if not is_alive(id):
		return 0.0
	_health[id] = maxf(_health[id] - amount, 0.0)
	return _health[id]


func heal(id: int, amount: float) -> float:
	if not is_alive(id):
		return 0.0
	_health[id] = minf(_health[id] + amount, _max_health[id])
	return _health[id]


# --- Queries ------------------------------------------------------------------

## Live ids of one type. The returned array is a copy; mutating it is harmless.
func ids_of_type(type: String) -> PackedInt32Array:
	if not _by_type.has(type):
		return PackedInt32Array()
	return PackedInt32Array(_by_type[type])


func has_type(type: String) -> bool:
	if not _by_type.has(type):
		return false
	var ids: PackedInt32Array = _by_type[type]
	return not ids.is_empty()


func cells_of_type(type: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in ids_of_type(type):
		out.append(get_cell(id))
	return out


func alive_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _alive.size():
		if _alive[id] == 1:
			out.append(id)
	return out


# --- Saving -------------------------------------------------------------------

## Plain data only, so store_var never needs object support. Ids are not saved:
## they are handed out again on load, because nothing outside a run refers to one.
func to_save_data() -> Dictionary:
	var types := PackedStringArray()
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var hp := PackedFloat32Array()
	for id in alive_ids():
		types.append(_type[id])
		xs.append(_cell_x[id])
		ys.append(_cell_y[id])
		hp.append(_health[id])
	return {"types": types, "cells_x": xs, "cells_y": ys, "health": hp}
