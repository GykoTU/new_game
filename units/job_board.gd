class_name JobBoard
extends RefCounted
## Work for builders, in priority order.
##
## Idle builders take the highest-priority job they can reach, nearest first
## within a priority. Jobs are not stored here: each kind has a provider that
## lists what needs that work right now, so the board can never drift out of
## step with the world. Building jobs list building ids; tile jobs (cobble,
## fill the bucket) list grid tile indices -- see is_tile_job(). Assignable builder tasks (planned) will be
## per-builder filters over these same providers, not a second system.

enum Kind { BUILD, REPAIR, COBBLE, CHOP, FILL }

## Most urgent first. The designer's order: build > repair > cobble > chop;
## filling the bucket (a one-off) comes before cobble, which needs it.
const PRIORITY := [Kind.BUILD, Kind.REPAIR, Kind.FILL, Kind.COBBLE, Kind.CHOP]

## How many builders one job accepts at once. More builders build faster, but
## a whole crew on one hut leaves everything else waiting.
const MAX_WORKERS := 4
## Filling one bucket is one builder's job.
const MAX_WORKERS_BY_KIND := {Kind.FILL: 1}

var _providers := {}   # Kind -> Callable() -> PackedInt32Array of ids (building or tile)
var _positions := {}   # Kind -> Callable(id) -> Vector2 (world), for distance order
var _default_position: Callable


static func is_tile_job(kind: int) -> bool:
	return kind == Kind.COBBLE or kind == Kind.FILL


static func max_workers(kind: int) -> int:
	return int(MAX_WORKERS_BY_KIND.get(kind, MAX_WORKERS))


func set_provider(kind: int, provider: Callable) -> void:
	_providers[kind] = provider


## A lookup for one kind, or (kind -1) for every kind without its own.
func set_position_lookup(lookup: Callable, kind := -1) -> void:
	if kind == -1:
		_default_position = lookup
	else:
		_positions[kind] = lookup


## Every open job as [kind, id], most urgent first, nearest first within the
## same priority. `only` limits it to certain kinds (at night: repairs only).
func candidates(from: Vector2, only: Array = []) -> Array:
	var out := []
	for kind in PRIORITY:
		if not _providers.has(kind):
			continue
		if not only.is_empty() and not only.has(kind):
			continue
		var ids: PackedInt32Array = _providers[kind].call()
		var arr := Array(ids)
		var pos: Callable = _positions.get(kind, _default_position)
		if pos.is_valid():
			arr.sort_custom(func(a, b):
				return from.distance_squared_to(pos.call(a)) \
					< from.distance_squared_to(pos.call(b)))
		for id in arr:
			out.append([kind, id])
	return out
