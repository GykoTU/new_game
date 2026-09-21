class_name DropStore
extends RefCounted
## Resources lying on the ground, waiting to be picked up: parallel arrays
## addressed by a stable id (D2), like UnitStore.
##
## A drop is born at its mine and bounces to where it lands. The bounce is only
## drawn: the simulation just remembers where it started, where it lands and
## on which tick, and a drop cannot be picked up until it has landed.
##
## `mine` is a building id, so it is only meaningful while that mine exists;
## saves store the mine's cell instead (see UnitSystem.get_save_data).

const NONE := -1
## Ticks a bounce takes (0.4 s at 60 ticks/s).
const BOUNCE_TICKS := 24

var kind := PackedInt32Array()      ## ResourceKind.Id
var pos := PackedVector2Array()     ## where it lands (world)
var from := PackedVector2Array()    ## where the bounce starts (world)
var born := PackedInt32Array()      ## tick the bounce started
var mine := PackedInt32Array()      ## building id of the mine it came from, or NONE
var claimed_by := PackedInt32Array()   ## unit id on its way to fetch it, or NONE

var _alive := PackedByteArray()
var _free := PackedInt32Array()
var _count := 0


func spawn(p_kind: int, p_from: Vector2, p_to: Vector2, p_mine: int, tick: int) -> int:
	var id: int
	if _free.is_empty():
		id = kind.size()
		kind.append(p_kind); pos.append(p_to); from.append(p_from); born.append(tick)
		mine.append(p_mine); claimed_by.append(NONE); _alive.append(1)
	else:
		id = _free[_free.size() - 1]
		_free.remove_at(_free.size() - 1)
		kind[id] = p_kind; pos[id] = p_to; from[id] = p_from; born[id] = tick
		mine[id] = p_mine; claimed_by[id] = NONE; _alive[id] = 1
	_count += 1
	return id


func despawn(id: int) -> void:
	if not is_alive(id):
		return
	_alive[id] = 0
	claimed_by[id] = NONE
	_free.append(id)
	_count -= 1


func clear() -> void:
	for id in _alive.size():
		if _alive[id] == 1:
			despawn(id)


func is_alive(id: int) -> bool:
	return id >= 0 and id < _alive.size() and _alive[id] == 1


func size() -> int:
	return _alive.size()


func count() -> int:
	return _count


func has_landed(id: int, tick: int) -> bool:
	return tick - born[id] >= BOUNCE_TICKS


## Drops still lying around that came from this mine, claimed or not.
func count_from(p_mine: int) -> int:
	var n := 0
	for id in _alive.size():
		if _alive[id] == 1 and mine[id] == p_mine:
			n += 1
	return n


## Where a drop is drawn this frame: along its bounce arc, then at rest.
func draw_pos(id: int, tick: int) -> Vector2:
	var t := clampf(float(tick - born[id]) / BOUNCE_TICKS, 0.0, 1.0)
	return from[id].lerp(pos[id], t) + Vector2(0.0, -sin(t * PI) * 14.0)
