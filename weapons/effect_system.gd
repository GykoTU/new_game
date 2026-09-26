class_name EffectSystem
extends RefCounted
## Explosions and burning ground: first-class entities beside the shots
## (docs/mechanics-coverage.md, "Effects are not projectiles"). They carry the
## same generation counter, have their own hard pool ceiling, and route their
## kills through WeaponSystem.hit_enemy, so on-kill behaviours see them.
##
##   blast    delay 0 goes off at once. A delayed blast (an enemy exploding
##            on death) waits in the pool; at most MAX_BLASTS_PER_TICK go off
##            per tick, the rest wait for the next -- a packed crowd
##            detonating is spread over ticks instead of stalling one.
##   ground   burns enemies standing in it and hurts workers, every PULSE
##            ticks, until it runs out.
##
## Victims behind a wall are shielded: a line-of-sight walk from the centre.
## Arrays are plain members, not a separate store class: the pool is small
## (CAP) and only touched on events and pulses, never in a hot loop.

const NONE := -1
const CAP := 256
const MAX_BLASTS_PER_TICK := 48
const PULSE := 10
## Enemies are points; this is how far past the edge of a blast still counts.
const ENEMY_RADIUS := 10.0

enum Kind { BLAST, GROUND }

## What just went off, for the renderer: [centre, radius, tick]. Drained by
## WeaponEffects each frame.
var blasts: Array = []

var w: WeaponSystem
var kind := PackedInt32Array()
var type := PackedInt32Array()
var gen := PackedInt32Array()
var pos := PackedVector2Array()
var radius := PackedFloat32Array()
## Blast: damage. Ground: damage per second.
var amount := PackedFloat32Array()
var knockback := PackedFloat32Array()
## Ticks until a blast goes off / a patch burns out.
var ticks := PackedInt32Array()
var total := PackedInt32Array()
var born := PackedInt32Array()

var _alive := PackedByteArray()
var _free := PackedInt32Array()
var _count := 0
var _blasts_this_tick := 0


func _init() -> void:
	kind.resize(CAP); type.resize(CAP); gen.resize(CAP); ticks.resize(CAP)
	total.resize(CAP); born.resize(CAP)
	pos.resize(CAP); radius.resize(CAP); amount.resize(CAP); knockback.resize(CAP)
	_alive.resize(CAP)
	reset_pool()


func reset_pool() -> void:
	_alive.fill(0)
	_free.resize(CAP)
	for i in CAP:
		_free[i] = CAP - 1 - i
	_count = 0
	blasts.clear()


func is_alive(id: int) -> bool:
	return id >= 0 and id < CAP and _alive[id] == 1


func alive_count() -> int:
	return _count


func _alloc(k: int, at: Vector2, r: float, amt: float, t: int, g: int, kb: float, n: int) -> int:
	if _free.is_empty():
		return NONE   # full: dropped, like every pool here
	var id := _free[_free.size() - 1]
	_free.remove_at(_free.size() - 1)
	kind[id] = k; pos[id] = at; radius[id] = r; amount[id] = amt; type[id] = t
	gen[id] = g; knockback[id] = kb; ticks[id] = n; total[id] = n; born[id] = w.tick
	_alive[id] = 1
	_count += 1
	return id


func _release(id: int) -> void:
	if is_alive(id):
		_alive[id] = 0
		_free.append(id)
		_count -= 1


## An explosion of `r` px at `at`: `damage` to every enemy (and, friendly
## fire, worker) in reach and in sight, pushed outward by `kb`.
## `delay` ticks > 0 queues it (dropped if the pool is full).
func blast(at: Vector2, r: float, damage: float, t: int, g: int, kb: float, delay: int) -> void:
	if r <= 0.0:
		return
	if delay <= 0 and _blasts_this_tick < MAX_BLASTS_PER_TICK:
		_detonate(at, r, damage, t, g, kb)
	else:
		_alloc(Kind.BLAST, at, r, damage, t, g, kb, maxi(delay, 1))


## A burning patch: `dps` to what stands in it, for `seconds`.
func ground(at: Vector2, r: float, dps: float, seconds: float, t: int, g: int) -> void:
	if r <= 0.0 or seconds <= 0.0:
		return
	_alloc(Kind.GROUND, at, r, dps, t, g, 0.0, maxi(int(round(seconds / GameClock.TICK_DELTA)), 1))


## One simulation tick, after the shots.
func step() -> void:
	_blasts_this_tick = 0
	if _count == 0:
		return
	for id in CAP:
		if _alive[id] == 0:
			continue
		if kind[id] == Kind.BLAST:
			if ticks[id] > 0:
				ticks[id] -= 1
			if ticks[id] <= 0 and _blasts_this_tick < MAX_BLASTS_PER_TICK:
				_release(id)   # first: the blast may queue more into this slot
				_detonate(pos[id], radius[id], amount[id], type[id], gen[id], knockback[id])
		else:
			ticks[id] -= 1
			if (w.tick - born[id]) % PULSE == 0:
				_burn(id)
			if ticks[id] <= 0:
				_release(id)


func _detonate(at: Vector2, r: float, damage: float, t: int, g: int, kb: float) -> void:
	_blasts_this_tick += 1
	if blasts.size() < 256:   # visuals only; drained by the renderer
		blasts.append([at, r, w.tick])
	var en := w.enemies
	var reach := r + ENEMY_RADIUS
	for e in en.nearby.query(at, reach):
		if not en.is_alive(e):
			continue
		var d := en.pos[e].distance_to(at)
		if d > reach or not w.in_sight(at, en.pos[e]):
			continue
		var push := Vector2.ZERO
		if kb > 0.0:
			var dir := (en.pos[e] - at).normalized() if d > 0.5 else Vector2.from_angle(w.rng.randf() * TAU)
			push = dir * kb * (1.0 - 0.5 * clampf(d / reach, 0.0, 1.0))
		if not w.hit_enemy(t, g, e, damage) and push != Vector2.ZERO:
			en.apply_impulse(e, push)
	if w.types[t].friendly_fire:
		for u in w.exposed_units_near(at, r):
			w.units.damage_unit(u, damage)


func _burn(id: int) -> void:
	var at := pos[id]
	var r := radius[id]
	var en := w.enemies
	var reach := r + ENEMY_RADIUS
	for e in en.nearby.query(at, reach):
		if en.is_alive(e) and en.pos[e].distance_squared_to(at) <= reach * reach:
			# A short burn, topped up every pulse while it stands here.
			en.apply_burn(e, amount[id], PULSE * GameClock.TICK_DELTA * 3.0, type[id], gen[id])
	if w.types[type[id]].friendly_fire:
		for u in w.exposed_units_near(at, r):
			w.units.damage_unit(u, amount[id] * PULSE * GameClock.TICK_DELTA)
