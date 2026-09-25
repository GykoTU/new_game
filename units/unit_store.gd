class_name UnitStore
extends RefCounted
## Every unit -- miners, builders, carriers -- as parallel arrays addressed by a
## stable id (D2). No node per unit: the renderer draws each kind in one batch.
##
## Ids come from a free list and are reused after despawn, so an id is only
## meaningful while is_alive(id). References that must survive a save are
## stored as CELLS, never ids: building and unit ids are reassigned on load.

const NONE := -1

enum State {
	IDLE,       ## standing at home, available
	WALKING,    ## following `path`; `task` says what happens on arrival
	WAITING,    ## miner beside an unfinished worker house
	STATIONED,  ## miner inside its worker house: hidden, safe, gathering
	WORKING,    ## builder at a construction or repair job
	MINING,     ## the commuting miner, working outside its mine: visible, exposed
	OPENING,    ## explorer beside a point of interest; done at tick `think_at`
}

## Why a walking unit is walking. Decides what happens when it arrives.
enum Task {
	NONE,
	GO_HOME,
	TO_MINE_HOUSE,
	TO_JOB,
	TO_PICKUP,
	TO_DROPOFF,
	FLEE,
	TO_MINE,    ## the commuting miner, on its way to mine outside
	TO_EXPLORE, ## explorer, heading for the tile in `goal`
	TO_POI,     ## explorer, heading for the point of interest in `target`
}

var kind := PackedInt32Array()
var state := PackedInt32Array()
var task := PackedInt32Array()
var pos := PackedVector2Array()
## Building the unit lives in (or, for miners, is assigned to). NONE = homeless.
var home := PackedInt32Array()
## Building the current task is about (a site, a house to empty...). NONE if none.
var target := PackedInt32Array()
var carry := PackedInt32Array()
var carry_kind := PackedInt32Array()
var facing_left := PackedByteArray()
## 1 while the unit is inside a building (its house, or the base) and not drawn.
## Units come out when they get a task and go back in when they have none.
var inside := PackedByteArray()
## Drop (DropStore id) the unit is on its way to pick up, or NONE.
var fetch := PackedInt32Array()
## JobBoard.Kind of the builder job in `target`, or NONE. Tile jobs (cobble,
## fill the bucket) keep a grid tile index in `target`, not a building id.
var job := PackedInt32Array()
## Explorer: grid tile index it was sent toward, or NONE. It detours to points
## of interest on the way and resumes toward this afterwards.
var goal := PackedInt32Array()
## Per-unit offset so a crowd does not animate in lockstep.
var anim_offset := PackedInt32Array()
## Next tick at which the unit reconsiders what to do. Staggered, so idle units
## do not all run their (pathfinding) decisions on the same tick.
var think_at := PackedInt32Array()
var hp := PackedFloat32Array()
var path: Array[PackedVector2Array] = []
var path_i := PackedInt32Array()

var _alive := PackedByteArray()
var _free := PackedInt32Array()
var _count_by_kind := PackedInt32Array()


func _init() -> void:
	_count_by_kind.resize(WorkerRoster.Kind.COUNT)
	_count_by_kind.fill(0)


## A new unit starts inside the building it appears at (see `inside`).
func spawn(p_kind: int, p_pos: Vector2, p_home: int, max_hp: float, tick: int) -> int:
	var id: int
	if _free.is_empty():
		id = kind.size()
		kind.append(p_kind); state.append(State.IDLE); task.append(Task.NONE)
		pos.append(p_pos); home.append(p_home); target.append(NONE)
		carry.append(0); carry_kind.append(0); facing_left.append(0)
		inside.append(1); fetch.append(NONE); job.append(NONE); goal.append(NONE)
		anim_offset.append((id * 7) % 97); think_at.append(tick + id % 20)
		hp.append(max_hp); path.append(PackedVector2Array()); path_i.append(0)
		_alive.append(1)
	else:
		id = _free[_free.size() - 1]
		_free.remove_at(_free.size() - 1)
		kind[id] = p_kind; state[id] = State.IDLE; task[id] = Task.NONE
		pos[id] = p_pos; home[id] = p_home; target[id] = NONE
		carry[id] = 0; carry_kind[id] = 0; facing_left[id] = 0
		inside[id] = 1; fetch[id] = NONE; job[id] = NONE; goal[id] = NONE
		think_at[id] = tick + id % 20
		hp[id] = max_hp; path[id] = PackedVector2Array(); path_i[id] = 0
		_alive[id] = 1
	_count_by_kind[p_kind] += 1
	return id


func despawn(id: int) -> void:
	if not is_alive(id):
		return
	_alive[id] = 0
	_count_by_kind[kind[id]] -= 1
	path[id] = PackedVector2Array()
	_free.append(id)


func clear() -> void:
	for id in _alive.size():
		if _alive[id] == 1:
			despawn(id)


func is_alive(id: int) -> bool:
	return id >= 0 and id < _alive.size() and _alive[id] == 1


func count(p_kind: int) -> int:
	return _count_by_kind[p_kind]


func size() -> int:
	return _alive.size()


func ids_of_kind(p_kind: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _alive.size():
		if _alive[id] == 1 and kind[id] == p_kind:
			out.append(id)
	return out


func alive_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _alive.size():
		if _alive[id] == 1:
			out.append(id)
	return out


## Starts walking along `points` (world positions). An empty path means the
## unit is already where it needs to be; the caller handles arrival.
func walk(id: int, points: PackedVector2Array, p_task: int) -> void:
	path[id] = points
	path_i[id] = 0
	task[id] = p_task
	state[id] = State.WALKING
	inside[id] = 0
