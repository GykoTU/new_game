class_name JobBoard
extends RefCounted
## Work for builders, in priority order.
##
## Idle builders take the highest-priority job they can reach, nearest first
## within a priority. Jobs are not stored here: each kind has a provider that
## lists the buildings needing that work right now, so the board can never
## drift out of step with the world. Assignable builder tasks (planned) will be
## per-builder filters over these same providers, not a second system.

enum Kind { BUILD, REPAIR, COBBLE, CHOP }

## Most urgent first. The designer's order: build > repair > cobble > chop.
const PRIORITY := [Kind.BUILD, Kind.REPAIR, Kind.COBBLE, Kind.CHOP]

## How many builders one job accepts at once. More builders build faster, but
## a whole crew on one hut leaves everything else waiting.
const MAX_WORKERS := 4

var _providers := {}   # Kind -> Callable() -> PackedInt32Array of building ids
var _positions: Callable   # building id -> Vector2 (world), for distance order


func set_provider(kind: int, provider: Callable) -> void:
	_providers[kind] = provider


func set_position_lookup(lookup: Callable) -> void:
	_positions = lookup


## Every open job as [kind, building id], most urgent first, nearest first
## within the same priority.
func candidates(from: Vector2) -> Array:
	var out := []
	for kind in PRIORITY:
		if not _providers.has(kind):
			continue
		var ids: PackedInt32Array = _providers[kind].call()
		var arr := Array(ids)
		if _positions.is_valid():
			arr.sort_custom(func(a, b):
				return from.distance_squared_to(_positions.call(a)) \
					< from.distance_squared_to(_positions.call(b)))
		for id in arr:
			out.append([kind, id])
	return out
