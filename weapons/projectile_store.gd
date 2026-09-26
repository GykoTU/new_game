class_name ProjectileStore
extends RefCounted
## Every shot in flight as parallel arrays addressed by a pooled id (D2), like
## EnemyStore. ProjectileSystem EXTENDS this class for the same reason
## EnemySystem extends EnemyStore (D10): its loop reads these arrays for every
## shot every tick, and member reads are much faster than `store.pos[p]`.
##
## Preallocated to CAP and never grown: a spawn beyond the cap is DROPPED, so
## no split, chain or upgrade combination can make these arrays unbounded
## (ARCHITECTURE.md, "Budget discipline"). Ids are reused after a shot ends.

const NONE := -1
## Hard ceiling on live shots (ARCHITECTURE.md section 10).
const CAP := 800

enum State {
	FLY,      ## straight (or homing) flight; hits things
	HOOKED,   ## a hook holding an enemy; follows it, hits nothing else
	RETURN,   ## a hook reeling back to its tower; hits nothing
	HELD,     ## a persistent shot (a whirl blade) moving round its weapon
}

## WeaponSystem type index: which weapon fired it, so which stats and
## behaviour set apply. The set is looked up per type, never copied per shot.
var type := PackedInt32Array()
## Building id of the weapon that fired it (NONE once that building is gone).
var owner := PackedInt32Array()
var state := PackedInt32Array()
## Split children and chained effects count up from 0; behaviours stop
## spawning more at the weapon's max_generation.
var gen := PackedInt32Array()
## Ticks left before on_expire.
var life := PackedInt32Array()
var born := PackedInt32Array()
var pos := PackedVector2Array()
var vel := PackedVector2Array()
## The weapon's centre: hooks reel back to it, blades and balls circle it.
var anchor := PackedVector2Array()
var dmg := PackedFloat32Array()
var radius := PackedFloat32Array()
var pierce_left := PackedInt32Array()
var bounce_left := PackedInt32Array()
## The last two enemies hit, so a piercing shot overlapping an enemy for a few
## ticks hits it once. Persistent shots may hit last_hit again after rehit_at.
var last_hit := PackedInt32Array()
var last_hit2 := PackedInt32Array()
var rehit_at := PackedInt32Array()
## Same, for workers (friendly fire).
var last_unit := PackedInt32Array()
var unit_rehit_at := PackedInt32Array()
## Generic scratch slots for behaviours (ARCHITECTURE.md, "Weapon behaviours"):
## the hooked enemy, a homing target, an orbit slot. Named for their users.
var hooked := PackedInt32Array()
var seek := PackedInt32Array()
var slot := PackedInt32Array()
## Drawn rotation for shots that do not face their flight (blades, balls).
var angle := PackedFloat32Array()
var friendly := PackedByteArray()

var _alive := PackedByteArray()
var _free := PackedInt32Array()
var _count := 0


func _init() -> void:
	# One by one: packed arrays are values (see EnemyStore._init).
	type.resize(CAP); owner.resize(CAP); state.resize(CAP); gen.resize(CAP)
	life.resize(CAP); born.resize(CAP); pierce_left.resize(CAP); bounce_left.resize(CAP)
	last_hit.resize(CAP); last_hit2.resize(CAP); rehit_at.resize(CAP)
	last_unit.resize(CAP); unit_rehit_at.resize(CAP)
	hooked.resize(CAP); seek.resize(CAP); slot.resize(CAP)
	pos.resize(CAP); vel.resize(CAP); anchor.resize(CAP)
	dmg.resize(CAP); radius.resize(CAP); angle.resize(CAP)
	friendly.resize(CAP)
	_alive.resize(CAP)
	reset_pool()


func reset_pool() -> void:
	_alive.fill(0)
	_free.resize(CAP)
	for i in CAP:
		_free[i] = CAP - 1 - i
	_count = 0


## Returns the new id, or NONE if the pool is full (the shot is dropped).
func alloc(p_type: int, p_owner: int, p_pos: Vector2, p_vel: Vector2, p_gen: int,
		p_tick: int) -> int:
	if _free.is_empty():
		return NONE
	var id := _free[_free.size() - 1]
	_free.remove_at(_free.size() - 1)
	type[id] = p_type; owner[id] = p_owner; state[id] = State.FLY; gen[id] = p_gen
	life[id] = 60; born[id] = p_tick
	pos[id] = p_pos; vel[id] = p_vel; anchor[id] = p_pos
	dmg[id] = 0.0; radius[id] = 4.0; pierce_left[id] = 0; bounce_left[id] = 0
	last_hit[id] = NONE; last_hit2[id] = NONE; rehit_at[id] = 0
	last_unit[id] = NONE; unit_rehit_at[id] = 0
	hooked[id] = NONE; seek[id] = NONE; slot[id] = -1
	angle[id] = 0.0; friendly[id] = 1
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
	if _count == 0:
		return out
	for id in CAP:
		if _alive[id] == 1:
			out.append(id)
	return out
