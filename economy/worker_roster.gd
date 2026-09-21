class_name WorkerRoster
extends RefCounted
## How many workers of each kind the player owns.
##
## Miners and builders are separate by design: miners are sent to resources,
## builders idle at the base and build or repair on their own. In Stage 1 this
## is only a count; Stage 2 turns each one into a unit at the base.

signal changed(kind: int, count: int)

## APPEND-ONLY: shop items store their worker kind as this integer.
enum Kind {
	MINER,
	BUILDER,
	COUNT,
}

const _KEYS := ["miner", "builder"]
const _DISPLAY := ["Miner", "Builder"]
const _ICONS := ["res://assets/ui/worker_icon.png", "res://assets/ui/builder_icon.png"]

var _counts := PackedInt32Array()


func _init() -> void:
	_counts.resize(Kind.COUNT)
	_counts.fill(0)


static func key_of(kind: int) -> String:
	return _KEYS[kind]


static func display_of(kind: int) -> String:
	return _DISPLAY[kind]


static func icon_path_of(kind: int) -> String:
	return _ICONS[kind]


func count(kind: int) -> int:
	return _counts[kind]


func add(kind: int, value: int = 1) -> void:
	if value <= 0:
		return
	_counts[kind] += value
	changed.emit(kind, _counts[kind])


func remove(kind: int, value: int = 1) -> void:
	if value <= 0:
		return
	_counts[kind] = maxi(_counts[kind] - value, 0)
	changed.emit(kind, _counts[kind])


func clear() -> void:
	for kind in Kind.COUNT:
		_counts[kind] = 0
		changed.emit(kind, 0)


func get_save_data() -> Dictionary:
	var out := {}
	for kind in Kind.COUNT:
		out[_KEYS[kind]] = _counts[kind]
	return {"counts": out}


func load_save_data(data: Dictionary) -> bool:
	var saved: Dictionary = data.get("counts", {})
	for key in saved:
		if not _KEYS.has(key):
			push_error("WorkerRoster: save names an unknown worker kind '%s'." % key)
			return false
	for kind in Kind.COUNT:
		_counts[kind] = maxi(int(saved.get(_KEYS[kind], 0)), 0)
		changed.emit(kind, _counts[kind])
	return true
