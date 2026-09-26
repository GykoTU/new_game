class_name WeaponSystem
extends RefCounted
## Every weapon building, the shots they fire and the effects those leave
## (Stage 5). Stepped once per simulation tick from main.gd._simulate(), after
## the enemies (whose spatial hash it reads) and the base's zap.
##
## Per tick:
##   1. burn deaths lit by a weapon become that weapon's kills (on_kill).
##   2. each finished weapon counts down; a ready one picks a target in RANGE
##      by its building's mode (nearest / strongest / first) and fires
##      PROJECTILE_COUNT shots, leading a moving target. Persistent weapons
##      (the whirl tower) instead keep their blades out while an enemy is
##      in RANGE, replace a lost one every 1 / FIRE_RATE seconds, and pull
##      them in after IDLE_SECONDS with nothing near.
##   3. ProjectileSystem moves the shots and resolves their hits.
##   4. EffectSystem sets off blasts and burns the ground.
##
## One StatBlock and one BehaviourSet per weapon TYPE (D7), both shared by
## every building and shot of that type. A behaviour upgrade bought in the
## shop is an unlock, "item:behaviour.<weapon>.<behaviour>"; learning one
## recompiles that type's set (_compile).
##
## Target modes are the only per-building state that is saved, by cell. Shots
## and effects in flight are not saved: a save in the middle of a night
## resumes with the weapons reloading.

const NONE := -1
const IDLE_SECONDS := 2.0
## Damage an enemy takes slamming into a wall (or a worker takes being hit by
## one), per px/s of push above EnemySystem.impact_speed.
const IMPACT_DAMAGE := 0.1

var level: LevelGenerator
var enemies: EnemySystem
var units: UnitSystem
var unlocks: Unlocks
var projectiles := ProjectileSystem.new()
var effects := EffectSystem.new()
var rng := RandomNumberGenerator.new()
var tick := 0

## Per weapon type, same index everywhere.
var types: Array[WeaponData] = []
var stats: Array[StatBlock] = []
var sets: Array[BehaviourSet] = []
var kills_by_type := PackedInt32Array()
## Recent chain arcs for the renderer: [from, to, tick]. Drained each frame.
var arcs: Array = []
## Where slowing hits landed, for the optional frost sprite: [pos, tick].
var chill_marks: Array = []
## Enemy id -> the hook holding it.
var hooked_by := {}
## Chain balls: shot -> the enemies it has caught, and enemy -> its shot.
var caught := {}
var held_by := {}

var _type_of := {}   # building type id -> weapon type index
## The finished weapon buildings, rebuilt when buildings change.
var _b := PackedInt32Array()
var _t := PackedInt32Array()
var _at := PackedVector2Array()
var _cd := PackedInt32Array()
var _idle := PackedInt32Array()
var _slots := PackedInt32Array()   # held shots out, one bit per slot
var _index := {}                   # building id -> index in the arrays above
var _dirty := true
var _modes := {}                   # Vector2i cell -> WeaponData.TargetMode
var _exposed := PackedInt32Array()
var _unit_hash := SpatialHash.new()


func setup(p_level: LevelGenerator, p_enemies: EnemySystem, p_units: UnitSystem,
		p_unlocks: Unlocks, modifiers: ModifierSet) -> void:
	level = p_level
	enemies = p_enemies
	units = p_units
	unlocks = p_unlocks
	projectiles.w = self
	effects.w = self
	for data in level.placeable_buildings:
		if data == null or data.weapon == null or _type_of.has(data.id):
			continue
		var wd := data.weapon
		_type_of[data.id] = types.size()
		types.append(wd)
		stats.append(StatBlock.new(modifiers, wd.tags, wd.base_stats))
		sets.append(BehaviourSet.new(wd.behaviours))
	kills_by_type.resize(types.size())
	# Methods, not lambdas (see WorkerRoster.attach).
	unlocks.changed.connect(_compile)
	level.level_generated.connect(_on_level_generated)
	level.building_placed.connect(_on_building_placed)
	level.construction_completed.connect(_on_construction_completed)
	level.building_removed.connect(_on_building_removed)
	enemies.wall_impact.connect(_on_wall_impact)
	enemies.unit_impact.connect(_on_unit_impact)
	_compile()


func clear() -> void:
	projectiles.reset_pool()
	effects.reset_pool()
	arcs.clear()
	chill_marks.clear()
	hooked_by.clear()
	caught.clear()
	held_by.clear()
	_modes.clear()
	kills_by_type.fill(0)
	_dirty = true


func _on_level_generated() -> void:
	projectiles.configure(level)
	effects.reset_pool()
	hooked_by.clear()
	caught.clear()
	held_by.clear()
	var tile := float(level.ground_layer.tile_set.tile_size.x)
	var origin := level.cell_to_world(Vector2i.ZERO) - Vector2(tile, tile) / 2.0
	_unit_hash.configure(origin, Vector2(level.grid.size) * tile, tile * 2.0)
	rng.seed = level.used_seed + 5
	_dirty = true


## Base behaviours plus every behaviour upgrade the run has learned.
func _compile() -> void:
	var known := unlocks.ids()
	for t in types.size():
		var ids := PackedStringArray(types[t].behaviours)
		var prefix := "item:behaviour.%s." % types[t].id
		for u in known:
			if u.begins_with(prefix):
				ids.append(u.trim_prefix(prefix))
		if ids != sets[t].ids:
			sets[t] = BehaviourSet.new(ids)


# --- Queries --------------------------------------------------------------------

func stat(t: int, s: int) -> float:
	return stats[t].get_value(s)


## The weapon type a building type fires, or -1.
func type_of(building_type: String) -> int:
	return _type_of.get(building_type, -1)


func is_weapon(building_id: int) -> bool:
	return level.store.is_alive(building_id) and _type_of.has(level.store.get_type(building_id))


func range_of(building_id: int) -> float:
	var t := type_of(level.store.get_type(building_id)) if level.store.is_alive(building_id) else -1
	return stat(t, Stats.Id.RANGE) if t != -1 else 0.0


func mode_of(building_id: int) -> int:
	if not is_weapon(building_id):
		return WeaponData.TargetMode.NEAREST
	var t := type_of(level.store.get_type(building_id))
	return _modes.get(level.store.get_cell(building_id), types[t].default_target)


func set_mode(building_id: int, mode: int) -> void:
	if is_weapon(building_id):
		_modes[level.store.get_cell(building_id)] = mode


## Nearest -> strongest -> first -> nearest. Returns the new mode.
func cycle_mode(building_id: int) -> int:
	var next := (mode_of(building_id) + 1) % WeaponData.TargetMode.size()
	set_mode(building_id, next)
	return next


func centre_of(building_id: int) -> Vector2:
	return level.cell_to_world(level.store.get_cell(building_id)) \
		+ level.get_footprint_offset(level.store.get_size(building_id))


func exposed_count() -> int:
	return _exposed.size()


## Exposed workers within `r` of `at` (friendly fire).
func exposed_units_near(at: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _exposed.is_empty():
		return out
	var ps := units.store.pos
	for u in _unit_hash.query(at, r):
		if units.is_exposed(u) and ps[u].distance_squared_to(at) <= r * r:
			out.append(u)
	return out


func nearest_enemy(at: Vector2, r: float, skip1 := NONE, skip2 := NONE) -> int:
	var best := NONE
	var best_d := r * r
	for e in enemies.nearby.query(at, r):
		if e == skip1 or e == skip2 or not enemies.is_alive(e):
			continue
		var d := enemies.pos[e].distance_squared_to(at)
		if d <= best_d:
			best = e
			best_d = d
	return best


func nearest_enemy_not_in(at: Vector2, r: float, skip: PackedInt32Array) -> int:
	var best := NONE
	var best_d := r * r
	for e in enemies.nearby.query(at, r):
		if not enemies.is_alive(e) or skip.has(e):
			continue
		var d := enemies.pos[e].distance_squared_to(at)
		if d <= best_d:
			best = e
			best_d = d
	return best


## No tile that stops shots lies between a and b (sampled every 12 px). The
## tile `a` is in does not count: a blast against a wall still reaches out.
func in_sight(a: Vector2, b: Vector2) -> bool:
	var g := level.grid
	var tile := float(level.ground_layer.tile_set.tile_size.x)
	var origin := level.cell_to_world(Vector2i.ZERO) - Vector2(tile, tile) / 2.0
	var start := Vector2i(((a - origin) / tile).floor())
	var n := ceili(a.distance_to(b) / 12.0)
	for i in range(1, n + 1):
		var c := Vector2i(((a.lerp(b, float(i) / n) - origin) / tile).floor())
		if c != start and g.in_bounds(c) and g.blocking[g.index(c)] & WorldGrid.BLOCKS_PROJECTILE:
			return false
	return true


# --- Harm -----------------------------------------------------------------------

## Every weapon's damage goes through here so that a kill, by a shot or a
## blast, reaches that weapon type's on_kill behaviours. `t` -1: no weapon (an
## impact). Returns true if it killed.
func hit_enemy(t: int, g: int, e: int, amount: float) -> bool:
	if not enemies.is_alive(e):
		return false
	var at := enemies.pos[e]
	var max_hp := enemies.max_hp[e]
	if not enemies.damage(e, amount, true):
		return false
	_on_enemy_killed(e, t, g, at, max_hp)
	return true


func _on_enemy_killed(e: int, t: int, g: int, at: Vector2, max_hp: float) -> void:
	if hooked_by.has(e):
		unhook(hooked_by[e])
	held_by.erase(e)   # its ball drops it from the list on its next step
	if t < 0:
		return
	kills_by_type[t] += 1
	for b in sets[t].kill:
		b.on_kill(self, t, g, at, max_hp)


## A chain link: the shot's damage and its hit effects, without its own
## on_unit_hit (no chain from a chain, no split).
func secondary_hit(p: int, e: int) -> void:
	var t := projectiles.type[p]
	if sets[t].direct_damage:
		hit_enemy(t, projectiles.gen[p], e, projectiles.dmg[p])
	for b in sets[t].secondary:
		b.on_unit_hit(self, p, e, false)


# --- Shots ----------------------------------------------------------------------

func _spawn(t: int, owner: int, at: Vector2, v: Vector2, g: int) -> int:
	var p := projectiles.alloc(t, owner, at, v, g, tick)
	if p == NONE:
		return NONE   # pool full: dropped
	var d := types[t]
	projectiles.dmg[p] = stat(t, Stats.Id.DAMAGE)
	projectiles.radius[p] = d.projectile_radius
	projectiles.pierce_left[p] = int(round(stat(t, Stats.Id.PIERCE_COUNT)))
	projectiles.bounce_left[p] = int(round(stat(t, Stats.Id.BOUNCE_COUNT)))
	projectiles.life[p] = maxi(int(round(stat(t, Stats.Id.PROJECTILE_LIFETIME) / GameClock.TICK_DELTA)), 1)
	projectiles.friendly[p] = 1 if d.friendly_fire else 0
	for b in sets[t].spawn:
		b.on_spawn(self, p)
	return p


## A split child: one generation later, from where the parent is, with
## what is left of the parent's bounces.
func spawn_child(p: int, v: Vector2, damage: float) -> int:
	var ps := projectiles
	var c := _spawn(ps.type[p], ps.owner[p], ps.pos[p], v, ps.gen[p] + 1)
	if c == NONE:
		return NONE
	ps.anchor[c] = ps.anchor[p]
	ps.dmg[c] = damage
	ps.bounce_left[c] = ps.bounce_left[p]
	ps.life[c] = maxi(ps.life[p], int(0.5 / GameClock.TICK_DELTA))
	return c


## Every shot ends here (never projectiles.release directly): it gives back
## a held shot's slot and lets go of a hooked enemy.
func end_shot(p: int) -> void:
	var ps := projectiles
	if not ps.is_alive(p):
		return
	if caught.has(p):
		_drop_caught(p)
	if ps.state[p] == ProjectileStore.State.HOOKED:
		hooked_by.erase(ps.hooked[p])
	elif ps.state[p] == ProjectileStore.State.HELD:
		var i: int = _index.get(ps.owner[p], -1)
		if i != -1 and ps.slot[p] >= 0:
			_slots[i] &= ~(1 << ps.slot[p])
	ps.release(p)


## A chain ball ends: everything it caught is let go where it is, stunned
## for STUN_DURATION.
func _drop_caught(p: int) -> void:
	var stun := stat(projectiles.type[p], Stats.Id.STUN_DURATION)
	for e in caught[p]:
		if held_by.get(e, -1) == p:
			held_by.erase(e)
			enemies.impulse[e] = Vector2.ZERO
			enemies.apply_stun(e, stun)
	caught.erase(p)


## One caught enemy is let go early (it hit a wall), stunned all the same.
func _drop_one(e: int) -> void:
	var p: int = held_by[e]
	held_by.erase(e)
	if caught.has(p):
		var list: PackedInt32Array = caught[p]
		var at := list.find(e)
		if at != -1:
			list.remove_at(at)
		caught[p] = list
		enemies.apply_stun(e, stat(projectiles.type[p], Stats.Id.STUN_DURATION))


## The hook lets go of its enemy and reels in.
func unhook(p: int) -> void:
	var ps := projectiles
	if not ps.is_alive(p):
		return
	var e := ps.hooked[p]
	if hooked_by.get(e, NONE) == p:
		hooked_by.erase(e)
	ps.hooked[p] = NONE
	ps.state[p] = ProjectileStore.State.RETURN
	ps.life[p] = int(3.0 / GameClock.TICK_DELTA)


func _end_held_shots(building_id: int) -> void:
	var ps := projectiles
	for p in ps.alive_ids():
		if ps.owner[p] == building_id and ps.state[p] == ProjectileStore.State.HELD:
			end_shot(p)


# --- Simulation -----------------------------------------------------------------

func step(dt: float) -> void:
	for k in enemies.burn_kills:
		var src: int = k[2]
		if src >= 0 and src < types.size():
			kills_by_type[src] += 1
			for b in sets[src].kill:
				b.on_kill(self, src, int(k[3]), k[0], float(k[1]))
	enemies.burn_kills.clear()
	if _dirty:
		_rebuild()
	_gather_exposed()
	var enemies_out := enemies.alive_count() > 0
	for i in _b.size():
		if _cd[i] > 0:
			_cd[i] -= 1
		var t := _t[i]
		if types[t].persistent:
			_step_held(i, t, enemies_out)
		elif enemies_out and _cd[i] <= 0:
			var e := _pick_target(i, t)
			if e != NONE:
				_fire(i, t, e)
				_cd[i] = _cooldown(t)
	projectiles.step(dt)
	effects.step()


func _cooldown(t: int) -> int:
	return maxi(int(round(1.0 / stat(t, Stats.Id.FIRE_RATE) / GameClock.TICK_DELTA)), 1)


## Workers outside, for friendly fire. Only gathered while something could
## hit them.
func _gather_exposed() -> void:
	_exposed.clear()
	if projectiles.alive_count() == 0 and effects.alive_count() == 0:
		return
	var us := units.store
	for u in us.size():
		if units.is_exposed(u):
			_exposed.append(u)
	if not _exposed.is_empty():
		_unit_hash.rebuild(_exposed, us.pos)


func _pick_target(i: int, t: int) -> int:
	var at := _at[i]
	var r := stat(t, Stats.Id.RANGE)
	var mode: int = _modes.get(level.store.get_cell(_b[i]), types[t].default_target)
	var best := NONE
	var best_v := INF
	for e in enemies.nearby.query(at, r):
		if not enemies.is_alive(e):
			continue
		var d := enemies.pos[e].distance_squared_to(at)
		if d > r * r:
			continue
		var v := d
		if mode == WeaponData.TargetMode.STRONGEST:
			v = -enemies.hp[e] * 1e6 + d   # most health; nearest among equals
		elif mode == WeaponData.TargetMode.FIRST:
			# No target yet (just arrived, chasing a worker): after every enemy
			# that has one, nearest first -- never skipped.
			var to := enemies.distance_to_target(e)
			v = to if to < INF else 1e9 + d
		if v < best_v:
			best_v = v
			best = e
	return best


func _fire(i: int, t: int, e: int) -> void:
	var from := _at[i]
	var d := types[t]
	var speed := maxf(stat(t, Stats.Id.PROJECTILE_SPEED), 1.0)
	# Lead the target once: where it will be when a shot fired now arrives.
	var ep := enemies.pos[e]
	var aim := ep + enemies.velocity_of(e) * (from.distance_to(ep) / speed)
	var dir := (aim - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var n := int(round(stat(t, Stats.Id.PROJECTILE_COUNT)))
	var lands := sets[t].lands
	for k in n:
		var off := (k - (n - 1) / 2.0) * d.spread
		var p := _spawn(t, _b[i], from, dir.rotated(deg_to_rad(off)) * speed, 0)
		if p == NONE:
			break
		projectiles.anchor[p] = from
		if lands:
			# A shell comes down where it was aimed, hit or miss.
			var flight := int(from.distance_to(aim) / speed / GameClock.TICK_DELTA) + 1
			projectiles.life[p] = mini(projectiles.life[p], maxi(flight, 1))


## Blades and balls: out while an enemy is in RANGE, replaced one at a time on
## the fire-rate cooldown, all pulled in after IDLE_SECONDS with none near.
func _step_held(i: int, t: int, enemies_out: bool) -> void:
	var near := enemies_out and nearest_enemy(_at[i], stat(t, Stats.Id.RANGE)) != NONE
	if near:
		_idle[i] = 0
	else:
		_idle[i] += 1
		if _idle[i] > int(IDLE_SECONDS / GameClock.TICK_DELTA) and _slots[i] != 0:
			_end_held_shots(_b[i])
		return
	var n := clampi(int(round(stat(t, Stats.Id.PROJECTILE_COUNT))), 1, 30)
	var fresh := _slots[i] == 0 and _cd[i] <= 0
	for s in n:
		if _slots[i] & (1 << s):
			continue
		if not fresh and _cd[i] > 0:
			return
		var p := _spawn(t, _b[i], _at[i], Vector2.ZERO, 0)
		if p == NONE:
			return
		projectiles.state[p] = ProjectileStore.State.HELD
		projectiles.slot[p] = s
		projectiles.anchor[p] = _at[i]
		_slots[i] |= 1 << s
		_cd[i] = _cooldown(t)
		if not fresh:
			return


## Which buildings are finished weapons, keeping each one's cooldown, idle
## time and held shots across the rebuild.
func _rebuild() -> void:
	_dirty = false
	var old := {}
	for i in _b.size():
		old[_b[i]] = [_cd[i], _idle[i], _slots[i]]
	_b.clear(); _t.clear(); _at.clear(); _cd.clear(); _idle.clear(); _slots.clear()
	_index.clear()
	for b in level.store.alive_ids():
		var t := type_of(level.store.get_type(b))
		if t == -1 or not level.store.is_complete(b):
			continue
		_index[b] = _b.size()
		_b.append(b)
		_t.append(t)
		_at.append(centre_of(b))
		var keep: Array = old.get(b, [0, 0, 0])
		_cd.append(keep[0]); _idle.append(keep[1]); _slots.append(keep[2])


func _on_building_placed(_type: String, _cell: Vector2i) -> void:
	_dirty = true


func _on_construction_completed(_id: int) -> void:
	_dirty = true


func _on_building_removed(b: int, _type: String, cell: Vector2i) -> void:
	_end_held_shots(b)
	_modes.erase(cell)
	_dirty = true


## A pushed enemy hit a wall: it takes the blow, and a hook dragging it lets go.
func _on_wall_impact(e: int, speed: float) -> void:
	if hooked_by.has(e):
		unhook(hooked_by[e])
	if held_by.has(e):
		_drop_one(e)
	var amount := (speed - enemies.impact_speed) * IMPACT_DAMAGE
	if amount > 0.0:
		hit_enemy(-1, 0, e, amount)


## A pushed enemy ran into a worker: the worker takes the blow.
func _on_unit_impact(_e: int, u: int, speed: float) -> void:
	var amount := (speed - enemies.impact_speed) * IMPACT_DAMAGE
	if amount > 0.0:
		units.damage_unit(u, amount)


# --- Saving ---------------------------------------------------------------------

## Target modes, by cell. Everything else is rebuilt from the level.
func get_save_data() -> Dictionary:
	var modes := []
	for cell in _modes:
		modes.append([cell.x, cell.y, _modes[cell]])
	return {"modes": modes}


## Call after the level has loaded.
func load_save_data(data: Dictionary) -> void:
	clear()
	for m in data.get("modes", []):
		if m is Array and m.size() == 3:
			_modes[Vector2i(int(m[0]), int(m[1]))] = clampi(int(m[2]), 0, WeaponData.TargetMode.size() - 1)
