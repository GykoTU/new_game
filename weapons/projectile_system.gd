class_name ProjectileSystem
extends ProjectileStore
## Moves every shot and finds what it hits (Stage 5). Stepped by
## WeaponSystem.step() after the weapons have fired.
##
## Per shot per tick:
##   1. on_step behaviours (only the few that have one: homing, hook, orbit,
##      the chain ball) steer it by setting its velocity.
##   2. move. The path is walked in steps of at most STEP_PX, so a fast shot
##      cannot skip a tile; entering a tile that stops shots (a wall; the map
##      edge) is on_wall_hit, with the side it crossed as the normal, both
##      axes at a corner. No behaviour keeping it: it ends there.
##   3. hits, while flying or held: enemies from EnemySystem's spatial hash,
##      then (friendly fire) exposed workers. Direct damage, then on_unit_hit;
##      pierce_left counts down, and a hit with none left is `final`.
##   4. life. At zero: on_expire, then it ends unless a behaviour kept it.
## Held shots (whirl blades) have no life: WeaponSystem ends them.

## Longest move before re-checking the grid: half a tile.
const STEP_PX := 16.0
## Held shots may hit the same enemy again after this many ticks.
const REHIT_TICKS := 24
const ENEMY_RADIUS := 10.0
const UNIT_RADIUS := 8.0

var w: WeaponSystem

var _tile := 32.0
var _inv_tile := 1.0 / 32.0
var _origin := Vector2.ZERO
var _cols := 1
var _rows := 1


func configure(level: LevelGenerator) -> void:
	reset_pool()
	_tile = float(level.ground_layer.tile_set.tile_size.x)
	_inv_tile = 1.0 / _tile
	_origin = level.cell_to_world(Vector2i.ZERO) - Vector2(_tile, _tile) / 2.0
	_cols = level.grid.size.x
	_rows = level.grid.size.y


func step(dt: float) -> void:
	if _count == 0:
		return
	# The grid's blocking layer, read once: nothing changes it during this step.
	var blocking := w.level.grid.blocking
	var en := w.enemies
	var enemies_out := en.alive_count() > 0
	var workers_out := w.exposed_count() > 0
	for p in alive_ids():
		if _alive[p] == 0:
			continue   # ended earlier this tick (a split parent, a hook's enemy...)
		var bs: BehaviourSet = w.sets[type[p]]
		for b in bs.step:
			b.on_step(w, p, dt)
		if _alive[p] == 0:
			continue
		var st := state[p]
		if st == State.HOOKED or st == State.RETURN:
			pos[p] += vel[p] * dt   # follows its enemy, or reels in: no walls
		elif not _move(p, vel[p] * dt, blocking, bs):
			continue
		st = state[p]
		if st == State.FLY or st == State.HELD:
			if enemies_out and _hit_enemies(p, bs, st == State.HELD):
				continue
			if workers_out and friendly[p] == 1 and _hit_workers(p, bs, st == State.HELD):
				continue
		if state[p] == State.HELD:
			continue
		life[p] -= 1
		if life[p] <= 0:
			_expire(p, bs)


## False if the shot ended against a wall.
func _move(p: int, delta: Vector2, blocking: PackedByteArray, bs: BehaviourSet) -> bool:
	var at := pos[p]
	var dist := delta.length()
	var steps := 1 if dist <= STEP_PX else ceili(dist / STEP_PX)
	var d := delta / steps
	for i in steps:
		var nxt := at + d
		var ox := floori((at.x - _origin.x) * _inv_tile)
		var oy := floori((at.y - _origin.y) * _inv_tile)
		var nx := floori((nxt.x - _origin.x) * _inv_tile)
		var ny := floori((nxt.y - _origin.y) * _inv_tile)
		if (nx != ox or ny != oy) and _solid(nx, ny, blocking):
			var normal := Vector2.ZERO
			if nx != ox and ny != oy:
				# A corner: which side did it really hit?
				var sx := _solid(nx, oy, blocking)
				var sy := _solid(ox, ny, blocking)
				normal = Vector2(1.0 if sx or not sy else 0.0, 1.0 if sy or not sx else 0.0)
			elif nx != ox:
				normal = Vector2(1.0, 0.0)
			else:
				normal = Vector2(0.0, 1.0)
			pos[p] = at
			var keep := false
			for b in bs.wall:
				if b.on_wall_hit(w, p, normal):
					keep = true
				if _alive[p] == 0:
					return false
			if not keep:
				w.end_shot(p)
				return false
			return true   # turned: the rest of this tick's move is dropped
		at = nxt
	pos[p] = at
	return true


func _solid(cx: int, cy: int, blocking: PackedByteArray) -> bool:
	if cx < 0 or cy < 0 or cx >= _cols or cy >= _rows:
		return true
	return blocking[cy * _cols + cx] & WorldGrid.BLOCKS_PROJECTILE != 0


## True if the shot ended.
func _hit_enemies(p: int, bs: BehaviourSet, held: bool) -> bool:
	var en := w.enemies
	var at := pos[p]
	var r := radius[p] + ENEMY_RADIUS
	var r2 := r * r
	for e in en.nearby.query(at, r):
		if not en.is_alive(e) or en.pos[e].distance_squared_to(at) > r2:
			continue
		if e == last_hit[p] or e == last_hit2[p]:
			if not held or w.tick < rehit_at[p]:
				continue
		last_hit2[p] = last_hit[p]
		last_hit[p] = e
		rehit_at[p] = w.tick + REHIT_TICKS
		var final := pierce_left[p] <= 0
		if not final:
			pierce_left[p] -= 1
		if bs.direct_damage:
			w.hit_enemy(type[p], gen[p], e, dmg[p])
		var keep := false
		for b in bs.hit:
			if b.on_unit_hit(w, p, e, final):
				keep = true
			if _alive[p] == 0:
				return true
		if state[p] != State.FLY and state[p] != State.HELD:
			return false   # hooked something: it stops hitting
		if final and not keep:
			w.end_shot(p)
			return true
	return false


## Friendly fire. A worker is not an enemy: no on_unit_hit, but the shot
## stops at it like at the end of its flight (a shell still explodes).
func _hit_workers(p: int, bs: BehaviourSet, held: bool) -> bool:
	var at := pos[p]
	var r := radius[p] + UNIT_RADIUS
	for u in w.exposed_units_near(at, r):
		if u == last_unit[p] and (not held or w.tick < unit_rehit_at[p]):
			continue
		last_unit[p] = u
		unit_rehit_at[p] = w.tick + REHIT_TICKS
		w.units.damage_unit(u, dmg[p])
		if pierce_left[p] > 0:
			pierce_left[p] -= 1
			continue
		if held:
			w.end_shot(p)
		else:
			_expire(p, bs)
		return true
	return false


func _expire(p: int, bs: BehaviourSet) -> void:
	var keep := false
	for b in bs.expire:
		if b.on_expire(w, p):
			keep = true
		if _alive[p] == 0:
			return
	if not keep:
		w.end_shot(p)
