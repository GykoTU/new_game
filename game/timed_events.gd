class_name TimedEvents
extends RefCounted
## Things that must happen at a later simulation tick: a stump rotting away, a
## tree growing back. Each event is a kind (a short string the owner
## understands) and a cell. Saved with the run, so a loaded run keeps its
## schedule.
##
## Ticks, never wall time: the schedule pauses with the game and runs faster
## at 2x/4x like everything else (section 5 of ARCHITECTURE.md).
##
## A plain list scanned on each pop. Dozens of events, not thousands; if that
## changes, swap in a heap without changing the interface.

var _due := PackedInt32Array()
var _kind := PackedStringArray()
var _cell: Array[Vector2i] = []


func schedule(due_tick: int, kind: String, cell := Vector2i.ZERO) -> void:
	_due.append(due_tick)
	_kind.append(kind)
	_cell.append(cell)


## Removes and returns every event due at or before `tick`, earliest first,
## as {tick, kind, cell}.
func pop_due(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < _due.size():
		if _due[i] <= tick:
			out.append({"tick": _due[i], "kind": _kind[i], "cell": _cell[i]})
			_due.remove_at(i)
			_kind.remove_at(i)
			_cell.remove_at(i)
		else:
			i += 1
	out.sort_custom(func(a, b): return a["tick"] < b["tick"])
	return out


func count(kind := "") -> int:
	if kind == "":
		return _due.size()
	var n := 0
	for k in _kind:
		if k == kind:
			n += 1
	return n


func clear() -> void:
	_due.clear()
	_kind.clear()
	_cell.clear()


func get_save_data() -> Dictionary:
	return {"due": _due, "kind": _kind, "cell": _cell.duplicate()}


func load_save_data(data: Dictionary) -> void:
	clear()
	var due: PackedInt32Array = data.get("due", PackedInt32Array())
	var kind: PackedStringArray = data.get("kind", PackedStringArray())
	var cell: Array = data.get("cell", [])
	for i in mini(due.size(), mini(kind.size(), cell.size())):
		schedule(due[i], kind[i], cell[i])
