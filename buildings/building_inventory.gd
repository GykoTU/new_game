class_name BuildingInventory
extends RefCounted
## Crafted buildings waiting to be placed, by type, in the order each type was
## first crafted. The building bar shows one slot per type with a count.
##
## Types are BuildingData ids. A type whose count reaches zero leaves the list;
## crafting it again puts it at the end.

signal changed

var _order := PackedStringArray()
var _count := {}


func add(type: String, n := 1) -> void:
	if n <= 0:
		return
	if not _count.has(type):
		_order.append(type)
		_count[type] = 0
	_count[type] += n
	changed.emit()


## Takes one out, e.g. when it is placed. Returns false if there is none.
func take(type: String) -> bool:
	if int(_count.get(type, 0)) <= 0:
		return false
	_count[type] -= 1
	if _count[type] == 0:
		_count.erase(type)
		_order.remove_at(_order.find(type))
	changed.emit()
	return true


func count(type: String) -> int:
	return int(_count.get(type, 0))


## Types in the order they were first crafted.
func types() -> PackedStringArray:
	return _order.duplicate()


func clear() -> void:
	_order.clear()
	_count.clear()
	changed.emit()


func get_save_data() -> Dictionary:
	var counts := PackedInt32Array()
	for t in _order:
		counts.append(_count[t])
	return {"types": _order, "counts": counts}


func load_save_data(data: Dictionary) -> void:
	_order.clear()
	_count.clear()
	var types_saved: PackedStringArray = data.get("types", PackedStringArray())
	var counts: PackedInt32Array = data.get("counts", PackedInt32Array())
	for i in mini(types_saved.size(), counts.size()):
		if counts[i] > 0:
			_order.append(types_saved[i])
			_count[types_saved[i]] = counts[i]
	changed.emit()
