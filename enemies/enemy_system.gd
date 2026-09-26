class_name EnemySystem
extends EnemyStore
## What every enemy does (Stage 4). Stepped once per simulation tick from
## main.gd._simulate(), after the units.
##
## Per tick: advance the flow fields, rebuild the spatial hash (`nearby`), let exposed
## workers draw nearby enemies onto them, then move, hit and burn each enemy.
##
##   targets   score = threat_priority / (distance_in_tiles + target_k), over
##             every player building; re-chosen every few seconds (staggered)
##             and when the target dies. A target without a flow field is only
##             chosen if a field slot is free.
##   moving    step to whichever neighbour tile the field says is closer. If
##             that tile holds a player building that is not the target, hit
##             it instead: that is how enemies break through.
##   workers   an exposed worker within aggro_range is chased and hit; it dies
##             at 0 health (UnitSystem.damage_unit).
##   impulse   a velocity offset from weapons that decays; the grid still
##             stops it, and hitting a wall (or a worker) fast is an event.
##   status    slow and burn: one slot each, strongest wins, duration refreshes.
##
## Positions are points; collision is "the tile this point would enter".

## A pushed enemy hit something solid at `speed` px/s (Stage 5 weapons listen).
signal wall_impact(id: int, speed: float)
## A pushed enemy ran into an exposed worker.
signal unit_impact(id: int, unit: int, speed: float)
## A kill taught the run a blueprint.
signal blueprint_dropped(blueprint: String)


## Seconds between target re-evaluations, per enemy (staggered).
var retarget_seconds := 3.0
## The "+ k" in the target score, in tiles: how strongly distance matters.
var target_k := 8.0
## Construction sites are worth this share of their building's threat.
var site_threat_share := 0.5
## Player buildings within this many tiles of a target add this share of their
## threat to its pull (a cluster draws enemies; see _rebuild_targets).
var cluster_radius := 3.0
var cluster_share := 0.5
## How far a hit reaches from an enemy to a worker, in pixels.
var unit_reach := 18.0
## Impulses halve in this many seconds.
var impulse_half_life := 0.15
## An impulse faster than this that runs into something is an impact.
var impact_speed := 60.0

var kinds: Array[EnemyData] = []
var fields := FlowFields.new()
var nearby := SpatialHash.new()
var level: LevelGenerator
var units: UnitSystem
var unlocks: Unlocks
var tick := 0
## Deaths since the renderer last looked: [position, kind, tick]. Drained by
## CombatEffects each frame (not a signal: hundreds a night).
var deaths: Array = []

var _unit_hash := SpatialHash.new()
var _rng := RandomNumberGenerator.new()
var _max_aggro := 0.0
var _tile := 32.0
var _inv_tile := 1.0 / 32.0
var _origin := Vector2.ZERO
var _w := 1
var _h := 1
## Per-kind numbers copied out of the EnemyData resources: reading a Resource
## property is far slower than an array index, and the hot loop reads these
## for every enemy every tick.
var _speed := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _aggro := PackedFloat32Array()
var _interval := PackedInt32Array()
var _flying := PackedByteArray()
var _targets_dirty := true
var _targets := PackedInt32Array()
var _target_pos := PackedVector2Array()
var _target_threat := PackedFloat32Array()


func setup(p_level: LevelGenerator, p_units: UnitSystem, p_unlocks: Unlocks,
		p_kinds: Array[EnemyData]) -> void:
	level = p_level
	units = p_units
	unlocks = p_unlocks
	kinds = p_kinds
	for k in kinds:
		_max_aggro = maxf(_max_aggro, k.aggro_range)
		_speed.append(k.move_speed)
		_damage.append(k.damage)
		_aggro.append(k.aggro_range)
		_interval.append(maxi(int(round(k.attack_interval / GameClock.TICK_DELTA)), 1))
		_flying.append(1 if k.flying else 0)
	fields.setup(level)
	# Methods, not lambdas (see WorkerRoster.attach).
	level.level_generated.connect(_on_level_generated)
	level.building_removed.connect(_on_building_removed)
	level.building_placed.connect(_on_building_placed)
	level.construction_completed.connect(_on_construction_completed)


func clear() -> void:
	reset_pool()
	deaths.clear()
	_targets_dirty = true


func _on_level_generated() -> void:
	reset_pool()
	_targets_dirty = true
	_tile = float(level.ground_layer.tile_set.tile_size.x)
	_inv_tile = 1.0 / _tile
	_origin = level.cell_to_world(Vector2i.ZERO) - Vector2(_tile, _tile) / 2.0
	_w = level.grid.size.x
	_h = level.grid.size.y
	var size := Vector2(level.grid.size) * _tile
	nearby.configure(_origin, size, _tile * 2.0)
	_unit_hash.configure(_origin, size, _tile * 2.0)
	_rng.seed = level.used_seed + 4


func kind_index(id: String) -> int:
	for n in kinds.size():
		if kinds[n].id == id:
			return n
	return -1


func count() -> int:
	return alive_count()


# --- Spawning and harm ------------------------------------------------------------

## Returns the new enemy, or NONE if the pool is full (the spawn is dropped).
func spawn(k: int, at: Vector2, hp_mult := 1.0) -> int:
	var d := kinds[k]
	var offset := Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 7.0))
	var id := alloc(k, at, d.max_health * hp_mult, tick, offset)
	if id != NONE:
		# Staggered, so a wave arriving together does not all retarget together.
		retarget_at[id] = tick + _rng.randi_range(0, 20)
	return id


## `by_player`: a kill by the player's defences (drops count); dawn does not.
func damage(e: int, amount: float, by_player := true) -> void:
	if not is_alive(e) or amount <= 0.0:
		return
	hp[e] -= amount
	flash[e] = 6
	if hp[e] <= 0.0:
		_kill(e, by_player)


## Knockback, pulls: added to the enemy's velocity, then decays.
func apply_impulse(e: int, velocity: Vector2) -> void:
	if is_alive(e):
		impulse[e] += velocity


## Strongest wins; an equal one refreshes the duration; a weaker one is ignored.
func apply_slow(e: int, strength: float, seconds: float) -> void:
	if not is_alive(e):
		return
	strength = clampf(strength, 0.0, 0.9)
	var ticks := int(round(seconds / GameClock.TICK_DELTA))
	if slow_ticks[e] <= 0 or strength > slow_strength[e]:
		slow_strength[e] = strength
		slow_ticks[e] = ticks
	elif is_equal_approx(strength, slow_strength[e]):
		slow_ticks[e] = maxi(slow_ticks[e], ticks)


## Same rule as slow, by damage per second.
func apply_burn(e: int, dps: float, seconds: float) -> void:
	if not is_alive(e):
		return
	var ticks := int(round(seconds / GameClock.TICK_DELTA))
	if burn_ticks[e] <= 0 or dps > burn_dps[e]:
		burn_dps[e] = dps
		burn_ticks[e] = ticks
	elif is_equal_approx(dps, burn_dps[e]):
		burn_ticks[e] = maxi(burn_ticks[e], ticks)


## Dawn: everything still out burns down within `seconds`.
func burn_all(seconds := 2.5) -> void:
	for e in alive_ids():
		apply_burn(e, max_hp[e] / seconds, seconds * 4.0)


func _kill(e: int, by_player: bool) -> void:
	deaths.append([pos[e], kind[e], tick])
	if by_player and unlocks != null and _rng.randf() < kinds[kind[e]].blueprint_drop_chance:
		var blueprint := unlocks.next_findable()
		if blueprint != "":
			unlocks.add(blueprint)
			blueprint_dropped.emit(blueprint)
	release(e)


# --- Simulation ---------------------------------------------------------------

func step(dt: float) -> void:
	fields.advance()
	if alive_count() == 0:
		return
	var ids := alive_ids()
	nearby.rebuild(ids, pos)
	_draw_to_workers()
	var decay := pow(0.5, dt / impulse_half_life)
	for e in ids:
		if is_alive(e):   # a kill earlier this tick frees an id; stay safe
			_step_one(e, dt, decay)


## Exposed workers pull the enemies near them off their building targets.
## Worker-centric on purpose: a handful of workers are out at night, against
## hundreds of enemies.
func _draw_to_workers() -> void:
	var us := units.store
	var exposed := PackedInt32Array()
	for u in us.size():
		if units.is_exposed(u):
			exposed.append(u)
	if exposed.is_empty():
		return
	_unit_hash.rebuild(exposed, us.pos)
	for u in exposed:
		var up: Vector2 = us.pos[u]
		for e in nearby.query(up, _max_aggro):
			var reach := _aggro[kind[e]]
			var d := pos[e].distance_squared_to(up)
			if d > reach * reach:
				continue
			var cur := target_unit[e]
			if cur == NONE or not units.is_exposed(cur) \
					or pos[e].distance_squared_to(us.pos[cur]) > d:
				target_unit[e] = u


## One enemy, one tick. The hot loop: kind numbers come from the per-kind
## arrays filled in setup (not the EnemyData resources), and anything costly --
## choosing a route, a target, the next tile -- happens only when something
## changed, not every tick.
func _step_one(e: int, dt: float, decay: float) -> void:
	var k := kind[e]
	# --- status
	if burn_ticks[e] > 0:
		burn_ticks[e] -= 1
		hp[e] -= burn_dps[e] * dt
		if hp[e] <= 0.0:
			_kill(e, false)
			return
	var slow := 0.0
	if slow_ticks[e] > 0:
		slow_ticks[e] -= 1
		slow = slow_strength[e]
	if flash[e] > 0:
		flash[e] -= 1
	if attack_cd[e] > 0:
		attack_cd[e] -= 1
	# --- target (a destroyed target resets retarget_at: _on_building_removed)
	if tick >= retarget_at[e]:
		_retarget(e)
	var p := pos[e]
	var steer := Vector2.ZERO
	var u := target_unit[e]
	if u != NONE:
		var reach := _aggro[k] * 1.5
		if not units.is_exposed(u) or units.store.pos[u].distance_squared_to(p) > reach * reach:
			target_unit[e] = NONE
			next_tile[e] = -1   # back to the buildings: re-plan
			u = NONE
	if u != NONE:
		# --- a worker first
		var up: Vector2 = units.store.pos[u]
		if p.distance_squared_to(up) <= unit_reach * unit_reach:
			state[e] = State.ATTACK
			if attack_cd[e] <= 0:
				attack_cd[e] = _interval[k]
				if units.damage_unit(u, _damage[k]):
					target_unit[e] = NONE
					next_tile[e] = -1
		else:
			state[e] = State.MOVE
			steer = (up - p).normalized()
	else:
		# --- the building route: re-plan only on a new tile or a new field
		var t := clampi(floori((p.y - _origin.y) * _inv_tile), 0, _h - 1) * _w \
			+ clampi(floori((p.x - _origin.x) * _inv_tile), 0, _w - 1)
		if t != tile[e] or next_tile[e] == -1 or field_version[e] != fields.generation:
			tile[e] = t
			_plan(e)
		var hit := hitting[e]
		if hit != NONE:
			state[e] = State.ATTACK
			if attack_cd[e] <= 0:
				attack_cd[e] = _interval[k]
				facing_left[e] = 1 if _building_center(hit).x < p.x else 0
				_hit_building(hit, _damage[k])
			# the hit may have destroyed it and cleared `hitting`; either way, stand
		else:
			state[e] = State.MOVE
			var to := waypoint[e] - p
			if to.length_squared() > 1.0:
				steer = to.normalized()
	# --- move
	var imp := impulse[e]
	var vel := steer * (_speed[k] * (1.0 - slow)) + imp
	if vel.x > 1.0 or vel.x < -1.0:
		facing_left[e] = 1 if vel.x < 0.0 else 0
	if vel == Vector2.ZERO:
		return
	if imp == Vector2.ZERO and u == NONE and next_tile[e] >= 0:
		# Walking its planned route: the next tile was chosen passable (and any
		# grid change since forces a re-plan), so there is nothing to collide
		# with. This is the common case, and it skips the collision test.
		pos[e] = p + vel * dt
		return
	_move(e, p, vel * dt, _flying[k] == 1, imp)
	if imp != Vector2.ZERO:
		impulse[e] = imp * decay if imp.length_squared() > 4.0 else Vector2.ZERO


## Moves by `delta` unless the tile it would enter is solid for it; slides along
## an axis if only one is blocked. A fast push into something solid is an impact.
func _move(e: int, p: Vector2, delta: Vector2, flying: bool, imp: Vector2) -> void:
	var costs := fields.cost_fly if flying else fields.cost_ground
	var np := p + delta
	if _solid(np, costs):
		var along_x := Vector2(np.x, p.y)
		var along_y := Vector2(p.x, np.y)
		if not _solid(along_x, costs):
			np = along_x
		elif not _solid(along_y, costs):
			np = along_y
		else:
			np = p
		next_tile[e] = -1   # something changed under it: re-plan
		var fast := imp.length()
		if fast > impact_speed:
			impulse[e] = Vector2.ZERO
			wall_impact.emit(e, fast)
	elif imp.length_squared() > impact_speed * impact_speed:
		var hit_unit := _unit_hash.nearest(np, 12.0, units.store.pos)
		if hit_unit != -1 and units.is_exposed(hit_unit):
			unit_impact.emit(e, hit_unit, imp.length())
	pos[e] = np


## Solid for this way of moving: impassable ground or any building at all.
## Read from the enemy cost layer, which already folds both in: 0 is
## impassable, BREAK_COST is a building (broken, never walked through).
func _solid(p: Vector2, costs: PackedByteArray) -> bool:
	var cx := floori((p.x - _origin.x) * _inv_tile)
	var cy := floori((p.y - _origin.y) * _inv_tile)
	if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
		return true
	var c := costs[cy * _w + cx]
	return c == 0 or c == FlowFields.BREAK_COST


## Chooses the next tile to step to (and the point to walk at), or the
## building to hit.
func _plan(e: int) -> void:
	hitting[e] = NONE
	next_tile[e] = -2   # -2: no field yet, head straight for the target
	field_version[e] = fields.generation
	var aim := target[e]
	if not level.store.is_alive(aim):
		waypoint[e] = pos[e]
		return
	var t := tile[e]
	var w := _w
	@warning_ignore("integer_division")
	var ty := t / w
	var tx := t - ty * w
	# Beside the target: hit it.
	var o := level.store.get_cell(aim)
	var sz := level.store.get_size(aim)
	if tx >= o.x - 1 and ty >= o.y - 1 and tx <= o.x + sz.x and ty <= o.y + sz.y:
		hitting[e] = aim
		next_tile[e] = t
		return
	var flying := _flying[kind[e]] == 1
	var f := fields.request(aim, flying, tick)
	if f == null or not f.is_ready():
		waypoint[e] = _building_center(aim)   # no field yet: straight at it
		return
	f.last_used = tick
	var costs := fields.cost_fly if flying else fields.cost_ground
	var dist := f.dist
	var best := t
	var best_d := dist[t]
	var up := ty > 0 and costs[t - w] != 0
	var down := ty < _h - 1 and costs[t + w] != 0
	var left := tx > 0 and costs[t - 1] != 0
	var right := tx < w - 1 and costs[t + 1] != 0
	if up and dist[t - w] < best_d: best = t - w; best_d = dist[best]
	if down and dist[t + w] < best_d: best = t + w; best_d = dist[best]
	if left and dist[t - 1] < best_d: best = t - 1; best_d = dist[best]
	if right and dist[t + 1] < best_d: best = t + 1; best_d = dist[best]
	if up and left and costs[t - w - 1] != 0 and dist[t - w - 1] < best_d: best = t - w - 1; best_d = dist[best]
	if up and right and costs[t - w + 1] != 0 and dist[t - w + 1] < best_d: best = t - w + 1; best_d = dist[best]
	if down and left and costs[t + w - 1] != 0 and dist[t + w - 1] < best_d: best = t + w - 1; best_d = dist[best]
	if down and right and costs[t + w + 1] != 0 and dist[t + w + 1] < best_d: best = t + w + 1; best_d = dist[best]
	if best == t:
		waypoint[e] = _building_center(aim)   # nowhere closer (cut off): straight at it
		return
	if costs[best] == FlowFields.BREAK_COST:
		var occ := level.grid.occupancy[best]
		if level.store.is_alive(occ):
			hitting[e] = occ   # a player building in the way: break through
			next_tile[e] = t
			return
	next_tile[e] = best
	waypoint[e] = _tile_center(best) + lane[e]


func _hit_building(b: int, amount: float) -> void:
	if level.store.damage(b, amount) <= 0.0:
		level.remove_building(level.store.get_cell(b))


# --- Targets ------------------------------------------------------------------

func _retarget(e: int) -> void:
	retarget_at[e] = tick + int(retarget_seconds / GameClock.TICK_DELTA) + _rng.randi_range(0, 30)
	if _targets_dirty:
		_rebuild_targets()
	if _targets.is_empty():
		target[e] = NONE
		return
	var flying := _flying[kind[e]] == 1
	var p := pos[e]
	var best := -1
	var best_score := -1.0
	var best_with_field := -1
	var best_with_field_score := -1.0
	for n in _targets.size():
		var tiles := p.distance_to(_target_pos[n]) * _inv_tile
		var score := _target_threat[n] / (tiles + target_k)
		if score > best_score:
			best_score = score
			best = n
		if score > best_with_field_score and fields.find(_targets[n], flying) != null:
			best_with_field_score = score
			best_with_field = n
	var choice := _targets[best]
	if fields.request(choice, flying, tick) == null and best_with_field != -1:
		choice = _targets[best_with_field]   # every field slot is busy: go where a field exists
	if choice != target[e]:
		target[e] = choice
		next_tile[e] = -1


## Every player building an enemy might go for, with its pull. A building's
## pull is its own threat plus half of what stands within cluster_radius of it:
## that is what lets a cluster of houses outrank a lone, distant base.
func _rebuild_targets() -> void:
	_targets_dirty = false
	_targets.clear()
	_target_pos.clear()
	_target_threat.clear()
	var own := PackedFloat32Array()
	for b in level.store.alive_ids():
		var data := level.get_building_data(level.store.get_type(b))
		if data == null or data.threat_priority <= 0.0:
			continue
		var threat := data.threat_priority
		if not level.store.is_complete(b):
			threat *= site_threat_share
		_targets.append(b)
		_target_pos.append(_building_center(b))
		own.append(threat)
	var r2 := (cluster_radius * _tile) * (cluster_radius * _tile)
	for n in _targets.size():
		var pull := own[n]
		for m in _targets.size():
			if m != n and _target_pos[n].distance_squared_to(_target_pos[m]) <= r2:
				pull += own[m] * cluster_share
		_target_threat.append(pull)


func _on_building_placed(_type: String, _cell: Vector2i) -> void:
	_targets_dirty = true


func _on_construction_completed(_id: int) -> void:
	_targets_dirty = true


func _on_building_removed(b: int, _type: String, _cell: Vector2i) -> void:
	_targets_dirty = true
	fields.drop_target(b)
	for e in alive_ids():
		if target[e] == b:
			target[e] = NONE
			retarget_at[e] = tick
			next_tile[e] = -1
		if hitting[e] == b:
			hitting[e] = NONE
			next_tile[e] = -1


# --- Geometry -----------------------------------------------------------------

func _tile_at(p: Vector2) -> int:
	var cx := clampi(floori((p.x - _origin.x) * _inv_tile), 0, _w - 1)
	var cy := clampi(floori((p.y - _origin.y) * _inv_tile), 0, _h - 1)
	return cy * _w + cx


func _tile_center(i: int) -> Vector2:
	@warning_ignore("integer_division")
	var y := i / _w
	return _origin + (Vector2(i - y * _w, y) + Vector2(0.5, 0.5)) * _tile


## Plain arithmetic, like _tile_center: cell_to_world goes through the
## TileMapLayer, which is two engine calls.
func _building_center(b: int) -> Vector2:
	return _origin + (Vector2(level.store.get_cell(b)) + Vector2(level.store.get_size(b)) * 0.5) * _tile


# --- Saving -------------------------------------------------------------------

## Kind by id, position, health and status. Targets and routes are not saved:
## they are recomputed on the first ticks after loading.
func get_save_data() -> Dictionary:
	var out := []
	for e in alive_ids():
		out.append({"kind": kinds[kind[e]].id, "pos": pos[e], "hp": hp[e],
			"max_hp": max_hp[e], "burn": [burn_dps[e], burn_ticks[e]],
			"slow": [slow_strength[e], slow_ticks[e]]})
	return {"enemies": out, "rng_state": _rng.state}


## Call after the level has loaded.
func load_save_data(data: Dictionary) -> void:
	reset_pool()
	for entry in data.get("enemies", []):
		var k := kind_index(String(entry.get("kind", "")))
		if k == -1:
			continue   # a kind this build no longer has
		var e := spawn(k, entry["pos"], 1.0)
		if e == NONE:
			break
		max_hp[e] = float(entry.get("max_hp", kinds[k].max_health))
		hp[e] = float(entry.get("hp", max_hp[e]))
		var burn: Array = entry.get("burn", [0.0, 0])
		burn_dps[e] = float(burn[0]); burn_ticks[e] = int(burn[1])
		var slow: Array = entry.get("slow", [0.0, 0])
		slow_strength[e] = float(slow[0]); slow_ticks[e] = int(slow[1])
	if data.has("rng_state"):
		_rng.state = int(data["rng_state"])
