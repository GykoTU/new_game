class_name EnemyStore
extends RefCounted
## Every enemy as parallel arrays addressed by a pooled id (D2), like UnitStore.
##
## EnemySystem EXTENDS this class rather than holding one, on purpose: GDScript
## reads a script's own member arrays about 2.7x faster than the same arrays
## through another object (`store.pos[e]`), and the enemy loop reads a dozen of
## them per enemy per tick. Measured: 16 reads for 500 enemies, 0.68 ms through
## an object, 0.26 ms as members. Method names here are chosen not to collide
## with EnemySystem's (alloc/release rather than spawn/despawn).
## Preallocated to CAP and never grown: a spawn beyond the cap is DROPPED, so
## no wave size or augment combination can make these arrays unbounded.
## Ids are reused after death, so an id means something only while is_alive.

const NONE := -1
## Hard ceiling on live enemies (ARCHITECTURE.md section 10).
const CAP := 600

enum State {
	MOVE,     ## following its flow field (or chasing a worker)
	ATTACK,   ## standing beside something, hitting it
}

var kind := PackedInt32Array()          # index into EnemySystem.kinds
var state := PackedInt32Array()
var pos := PackedVector2Array()
## Pushes from weapons (knockback, pulls). Added to steering, decays toward
## zero. Movement still respects the grid: see EnemySystem._move.
var impulse := PackedVector2Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
## Building id it is heading for, and the building it is hitting right now
## (the target, or whatever stands in the way).
var target := PackedInt32Array()
var hitting := PackedInt32Array()
## Worker (UnitStore id) it is chasing or hitting, or NONE.
var target_unit := PackedInt32Array()
## Ticks until it may hit again.
var attack_cd := PackedInt32Array()
## Tick at which it next reconsiders its target.
var retarget_at := PackedInt32Array()
## The tile it stands on, the tile it steps toward next, and the version of its
## flow field that choice was made with. The next step is only recomputed when
## one of those changes, so most ticks an enemy just walks.
var tile := PackedInt32Array()
var next_tile := PackedInt32Array()
var field_version := PackedInt32Array()
## Where it is walking right now: the next tile's centre (plus its lane), or
## the target itself while no field is ready. Set by planning, read every tick.
var waypoint := PackedVector2Array()
## Status slots (docs/mechanics-coverage.md): strongest wins, duration refreshes.
var slow_strength := PackedFloat32Array()
var slow_ticks := PackedInt32Array()
var burn_dps := PackedFloat32Array()
var burn_ticks := PackedInt32Array()
## Ticks left of the white hit flash.
var flash := PackedInt32Array()
var facing_left := PackedByteArray()
var anim_offset := PackedInt32Array()
## A small fixed offset inside each tile, so a crowd walking one route does
## not collapse into a single sprite. Cheaper than separation forces.
var lane := PackedVector2Array()

var _alive := PackedByteArray()
var _free := PackedInt32Array()
var _count := 0


func _init() -> void:
	# One by one: packed arrays are values in GDScript, so resizing them inside
	# a loop over [kind, state, ...] would resize copies and leave these empty.
	kind.resize(CAP); state.resize(CAP); target.resize(CAP); hitting.resize(CAP)
	target_unit.resize(CAP); attack_cd.resize(CAP); retarget_at.resize(CAP)
	tile.resize(CAP); next_tile.resize(CAP); field_version.resize(CAP)
	slow_ticks.resize(CAP); burn_ticks.resize(CAP); flash.resize(CAP); anim_offset.resize(CAP)
	hp.resize(CAP); max_hp.resize(CAP); slow_strength.resize(CAP); burn_dps.resize(CAP)
	pos.resize(CAP); impulse.resize(CAP); lane.resize(CAP); waypoint.resize(CAP)
	facing_left.resize(CAP)
	_alive.resize(CAP)
	reset_pool()


func reset_pool() -> void:
	_alive.fill(0)
	_free.resize(CAP)
	# Handed out lowest first: the free list is a stack.
	for i in CAP:
		_free[i] = CAP - 1 - i
	_count = 0


## Returns the new id, or NONE if the pool is full (the spawn is dropped).
func alloc(p_kind: int, p_pos: Vector2, p_hp: float, p_tick: int, p_lane: Vector2) -> int:
	if _free.is_empty():
		return NONE
	var id := _free[_free.size() - 1]
	_free.remove_at(_free.size() - 1)
	kind[id] = p_kind; state[id] = State.MOVE; pos[id] = p_pos
	impulse[id] = Vector2.ZERO; hp[id] = p_hp; max_hp[id] = p_hp
	target[id] = NONE; hitting[id] = NONE; target_unit[id] = NONE
	attack_cd[id] = 0; retarget_at[id] = p_tick
	tile[id] = -1; next_tile[id] = -1; field_version[id] = -1
	slow_strength[id] = 0.0; slow_ticks[id] = 0; burn_dps[id] = 0.0; burn_ticks[id] = 0
	flash[id] = 0; facing_left[id] = 0; anim_offset[id] = (id * 13) % 97
	lane[id] = p_lane
	waypoint[id] = p_pos
	_alive[id] = 1
	_count += 1
	return id


func release(id: int) -> void:
	if not is_alive(id):
		return
	_alive[id] = 0
	_free.append(id)
	_count -= 1


func is_alive(id: int) -> bool:
	return id >= 0 and id < CAP and _alive[id] == 1


func alive_count() -> int:
	return _count


func alive_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in CAP:
		if _alive[id] == 1:
			out.append(id)
	return out
