class_name Economy
extends RefCounted
## How much of each resource the player holds in this run.
##
## Spending is all-or-nothing: a cost of 20 gold and 5 copper either takes both
## or takes neither, so a player can never end up having paid half a price.

## Emitted for every resource whose amount changed.
signal changed(kind: int, amount: int)

var _amounts := PackedInt64Array()


func _init() -> void:
	_amounts.resize(ResourceKind.count())
	_amounts.fill(0)


func amount(kind: int) -> int:
	return _amounts[kind]


func add(kind: int, value: int) -> void:
	if value <= 0:
		return
	_amounts[kind] += value
	changed.emit(kind, _amounts[kind])


## Replaces every amount. For starting resources and loading, not for gameplay.
func set_all(amounts: Dictionary) -> void:
	for kind in ResourceKind.count():
		_amounts[kind] = maxi(int(amounts.get(kind, 0)), 0)
		changed.emit(kind, _amounts[kind])


## `cost` maps ResourceKind.Id -> amount.
func can_afford(cost: Dictionary) -> bool:
	for kind in cost:
		if _amounts[kind] < int(cost[kind]):
			return false
	return true


## Takes the whole cost or nothing. Returns false and changes nothing if any
## part of it is unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for kind in cost:
		var value := int(cost[kind])
		if value <= 0:
			continue
		_amounts[kind] -= value
		changed.emit(kind, _amounts[kind])
	return true


# --- Saving -------------------------------------------------------------------

## Keyed by string ("gold"), not enum integer, so a save survives the registry
## changing. The shop's costs are the ones that depend on integer order.
func get_save_data() -> Dictionary:
	var out := {}
	for kind in ResourceKind.count():
		out[ResourceKind.key_of(kind)] = _amounts[kind]
	return {"amounts": out}


## Returns false if the save names a resource this build does not know: a run
## silently missing some of its resources is worse than not loading.
func load_save_data(data: Dictionary) -> bool:
	var saved: Dictionary = data.get("amounts", {})
	var loaded := {}
	var unknown := PackedStringArray()
	for key in saved:
		var kind := ResourceKind.id_from_key(key)
		if kind == -1:
			unknown.append(key)
			continue
		loaded[kind] = int(saved[key])
	if not unknown.is_empty():
		push_error("Economy: save names unknown resources: %s" % ", ".join(unknown))
		return false
	set_all(loaded)
	return true
