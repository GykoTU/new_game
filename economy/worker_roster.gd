class_name WorkerRoster
extends RefCounted
## How many workers of each kind the player owns, and the kinds themselves.
##
## Since Stage 2a the units themselves are the truth: once attach()ed to the
## UnitSystem, count() asks it and add() spawns a real unit. Detached (as in the
## economy tests), it keeps plain counts, so the shop works without a world.

signal changed(kind: int, count: int)

## APPEND-ONLY: shop items store their worker kind as this integer.
enum Kind {
	MINER,
	BUILDER,
	CARRIER,
	COUNT,
}

const _KEYS := ["miner", "builder", "carrier"]
## Save key -> Kind, for loading.
const KEYS_INDEX := {"miner": Kind.MINER, "builder": Kind.BUILDER, "carrier": Kind.CARRIER}
const _DISPLAY := ["Miner", "Builder", "Carrier"]
const _ICONS := ["res://assets/ui/worker_icon.png", "res://assets/ui/builder_icon.png",
	"res://assets/ui/carrier_icon.png"]

var _counts := PackedInt32Array()
## The UnitSystem once attached. Untyped to avoid a class cycle with it.
var _units = null


func _init() -> void:
	_counts.resize(Kind.COUNT)
	_counts.fill(0)


static func key_of(kind: int) -> String:
	return _KEYS[kind]


static func display_of(kind: int) -> String:
	return _DISPLAY[kind]


static func icon_path_of(kind: int) -> String:
	return _ICONS[kind]


## Backs this roster with real units from now on.
##
## Connected to a METHOD, not a lambda: a lambda written in a RefCounted class
## holds a strong reference to it, and this roster holds the unit system, so a
## lambda here made a cycle that leaked the whole run on every return to title.
func attach(units) -> void:
	_units = units
	units.changed.connect(_on_units_changed)


func _on_units_changed(kind: int) -> void:
	changed.emit(kind, count(kind))


func count(kind: int) -> int:
	if _units != null:
		return _units.count(kind)
	return _counts[kind]


func add(kind: int, value: int = 1) -> void:
	if value <= 0:
		return
	if _units != null:
		for i in value:
			_units.spawn_bought(kind)
		return
	_counts[kind] += value
	changed.emit(kind, _counts[kind])


func remove(kind: int, value: int = 1) -> void:
	if value <= 0:
		return
	_counts[kind] = maxi(_counts[kind] - value, 0)
	changed.emit(kind, _counts[kind])


func clear() -> void:
	if _units != null:
		return   # the unit system is cleared by its owner
	for kind in Kind.COUNT:
		_counts[kind] = 0
		changed.emit(kind, 0)


func get_save_data() -> Dictionary:
	if _units != null:
		return {}   # units save themselves
	var out := {}
	for kind in Kind.COUNT:
		out[_KEYS[kind]] = _counts[kind]
	return {"counts": out}


func load_save_data(data: Dictionary) -> bool:
	if _units != null:
		return true
	var saved: Dictionary = data.get("counts", {})
	for key in saved:
		if not _KEYS.has(key):
			push_error("WorkerRoster: save names an unknown worker kind '%s'." % key)
			return false
	for kind in Kind.COUNT:
		_counts[kind] = maxi(int(saved.get(_KEYS[kind], 0)), 0)
		changed.emit(kind, _counts[kind])
	return true
