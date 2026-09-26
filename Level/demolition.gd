class_name Demolition
extends RefCounted
## The shovel (an item, like the bucket): the player marks buildings, and a
## builder digs each marked one out -- a DIG job (JobBoard), after repairs --
## and half of what it cost to craft comes back.
##
## Only the player's own buildings can be dug out: anything with BuildingData
## except the base. Trees, stumps, mines and points of interest cannot (trees
## are chopped instead). A construction site can be: it was crafted too.
## Marks are saved by cell.

signal marks_changed
## A building was dug out; `refund` is what came back, by resource.
signal dug(type: String, refund: Dictionary)

const ITEM := "item:shovel"
## Share of the craft price that comes back.
const REFUND_SHARE := 0.5

## Builder-seconds to dig a building out: this share of its build work, and
## at least MIN_WORK.
var work_share := 0.5
var min_work := 2.0

var level: LevelGenerator
var economy: Economy
var _refunds := {}   # building type -> {resource kind: amount}
var _marked := {}    # building id -> builder-seconds done


func setup(p_level: LevelGenerator, p_economy: Economy, catalogue: ShopCatalogue) -> void:
	level = p_level
	economy = p_economy
	for item in catalogue.items:
		if item != null and item.kind == ShopItemData.Kind.BUILDING and not _refunds.has(item.building_id):
			var back := {}
			for k in item.base_cost:
				var n := floori(int(item.base_cost[k]) * REFUND_SHARE)
				if n > 0:
					back[k] = n
			_refunds[item.building_id] = back
	# Methods, not lambdas (see WorkerRoster.attach).
	level.building_removed.connect(_on_building_removed)
	level.level_generated.connect(clear)


func clear() -> void:
	_marked.clear()
	marks_changed.emit()


func can_dig(id: int) -> bool:
	if not level.store.is_alive(id):
		return false
	var type := level.store.get_type(id)
	return type != "base" and level.get_building_data(type) != null


func is_marked(id: int) -> bool:
	return _marked.has(id)


## Marks or unmarks. Returns false if it cannot be dug out.
func set_mark(id: int, on: bool) -> bool:
	if not can_dig(id):
		return false
	if on == _marked.has(id):
		return true
	if on:
		_marked[id] = 0.0
	else:
		_marked.erase(id)
	marks_changed.emit()
	return true


func marked() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _marked:
		if level.store.is_alive(id):
			out.append(id)
	return out


## For buildings not crafted in the shop (walls and gates are painted).
func set_refund(type: String, back: Dictionary) -> void:
	_refunds[type] = back


func refund_of(type: String) -> Dictionary:
	return _refunds.get(type, {})


func work_needed(id: int) -> float:
	var data := level.get_building_data(level.store.get_type(id))
	return maxf(data.build_work * work_share if data != null else 0.0, min_work)


## Adds builder work. Returns true on the call that digs it out: it is gone,
## and the refund is in the economy.
func dig(id: int, work: float) -> bool:
	if not _marked.has(id) or not level.store.is_alive(id):
		return false
	var done: float = _marked[id] + work
	if done < work_needed(id):
		_marked[id] = done
		return false
	var type := level.store.get_type(id)
	var back := refund_of(type)
	for k in back:
		economy.add(k, back[k])
	level.remove_building(level.store.get_cell(id))   # -> _on_building_removed
	dug.emit(type, back)
	return true


func _on_building_removed(id: int, _type: String, _cell: Vector2i) -> void:
	if _marked.erase(id):
		marks_changed.emit()


func get_save_data() -> Dictionary:
	var cells := []
	for id in marked():
		var c := level.store.get_cell(id)
		cells.append([c.x, c.y, _marked[id]])
	return {"marked": cells}


## Call after the level has loaded.
func load_save_data(data: Dictionary) -> void:
	_marked.clear()
	for m in data.get("marked", []):
		var c := Vector2i(int(m[0]), int(m[1]))
		if level.grid.in_bounds(c):
			var id := level.grid.get_occupant(c)
			if can_dig(id):
				_marked[id] = float(m[2])
	marks_changed.emit()
