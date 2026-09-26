class_name Waves
extends RefCounted
## Who comes each night, from where, and when (Stage 4).
##
## At dusk a night is planned in full: a budget that grows with the day, spent
## on the kinds allowed so far, split into groups that arrive from 1-3 map
## edges over the first `spawn_window` seconds. The plan is a queue of
## [ticks after dusk, kind, side, health multiplier], saved with the run, so a
## night resumed from a save carries on where it was.
##
## Waves scale by SHAPE, not only by number (ARCHITECTURE.md, RunDirector):
## from night 3 each night is a "swarm" (many, fragile, bee-heavy), an "elite"
## night (few, tough) or a plain mix. That keeps the enemy count bounded as
## runs get long, and makes nights feel different.

signal night_planned(night: int, sides: PackedInt32Array, shape: String)

enum Side { NORTH, EAST, SOUTH, WEST }
const SIDE_NAMES := ["north", "east", "south", "west"]

## Budget for night 1, and what each further night adds (in spawn_cost units).
var base_budget := 6.0
var budget_per_night := 4.0
## Health grows this much per night (0.15 = +15%).
var health_growth := 0.15
## Seconds after dusk over which the groups set out.
var spawn_window := 15.0
var group_size := Vector2i(3, 5)
## Seconds between members of one group.
var group_spacing := 0.4

var enemies: EnemySystem
var level: LevelGenerator
var night := 0
var shape := ""
var sides := PackedInt32Array()
var _start_tick := 0
var _queue: Array = []   # sorted by the first element
var _rng := RandomNumberGenerator.new()


func setup(p_enemies: EnemySystem, p_level: LevelGenerator) -> void:
	enemies = p_enemies
	level = p_level


func clear() -> void:
	_queue.clear()
	night = 0
	shape = ""
	sides = PackedInt32Array()
	_rng.seed = (level.used_seed if level != null else 0) + 17


func pending() -> int:
	return _queue.size()


## Dusk of night `p_night`: plan it.
func start_night(p_night: int, tick: int) -> void:
	night = p_night
	_start_tick = tick
	_queue.clear()
	var count_mult := 1.0
	var hp_mult := 1.0
	var bee_share := 0.0 if night < 2 else 0.3
	shape = "mixed"
	if night >= 3:
		match _rng.randi_range(0, 2):
			0:
				shape = "swarm"; count_mult = 1.6; hp_mult = 0.6; bee_share = 0.6
			1:
				shape = "elite"; count_mult = 0.55; hp_mult = 2.0; bee_share = 0.15
	var budget := (base_budget + budget_per_night * (night - 1)) * count_mult
	var health := (1.0 + health_growth * (night - 1)) * hp_mult
	# Which kinds may come tonight.
	var goblin := enemies.kind_index("goblin")
	var bee := enemies.kind_index("bee")
	var allowed := []
	for k in enemies.kinds.size():
		if enemies.kinds[k].first_night <= night:
			allowed.append(k)
	if allowed.is_empty():
		return
	# Spend the budget.
	var picks: Array[int] = []
	var guard := 0
	while budget > 0.0 and guard < EnemyStore.CAP:
		guard += 1
		var k: int = allowed[_rng.randi() % allowed.size()]
		if bee != -1 and goblin != -1 and allowed.has(bee):
			k = bee if _rng.randf() < bee_share else goblin
		picks.append(k)
		budget -= maxf(enemies.kinds[k].spawn_cost, 0.1)
	# Sides: one, then two from night 3, three from night 6.
	var n_sides := 1 if night < 3 else (2 if night < 6 else 3)
	var all := [Side.NORTH, Side.EAST, Side.SOUTH, Side.WEST]
	_shuffle(all)
	sides = PackedInt32Array(all.slice(0, n_sides))
	# Groups, each at its own moment and side.
	var i := 0
	while i < picks.size():
		var size := _rng.randi_range(group_size.x, group_size.y)
		var side: int = sides[_rng.randi() % sides.size()]
		var at := _rng.randf_range(0.0, spawn_window)
		for m in mini(size, picks.size() - i):
			var t := int((at + m * group_spacing) / GameClock.TICK_DELTA)
			_queue.append([t, picks[i], side, health])
			i += 1
	_queue.sort_custom(func(a, b): return a[0] < b[0])
	night_planned.emit(night, sides, shape)


## One simulation tick: spawns whoever is due.
func step(tick: int) -> void:
	while not _queue.is_empty() and tick - _start_tick >= int(_queue[0][0]):
		var entry: Array = _queue.pop_front()
		var at := spawn_point(int(entry[2]), enemies.kinds[int(entry[1])].flying)
		if at != Vector2.INF:
			enemies.spawn(int(entry[1]), at, float(entry[3]))


## Dawn: whoever has not set out yet stays away.
func end_night() -> void:
	_queue.clear()


## A free tile on the given edge (walkable for walkers), as a world position,
## or Vector2.INF if the whole edge is closed.
func spawn_point(side: int, flying: bool) -> Vector2:
	var g := level.grid
	for attempt in 40:
		# Up to 3 tiles in from the edge, so a lake on the border is not a wall.
		@warning_ignore("integer_division")
		var depth := mini(attempt / 12, 2)
		var c: Vector2i
		match side:
			Side.NORTH: c = Vector2i(_rng.randi_range(0, g.size.x - 1), depth)
			Side.SOUTH: c = Vector2i(_rng.randi_range(0, g.size.x - 1), g.size.y - 1 - depth)
			Side.WEST: c = Vector2i(depth, _rng.randi_range(0, g.size.y - 1))
			_: c = Vector2i(g.size.x - 1 - depth, _rng.randi_range(0, g.size.y - 1))
		var i := g.index(c)
		if g.occupancy[i] != WorldGrid.NO_OCCUPANT:
			continue
		if not flying and g.blocks_unit_at(i):
			continue
		return level.cell_to_world(c)
	return Vector2.INF


## "the north and east"
static func describe_sides(p_sides: PackedInt32Array) -> String:
	var names := PackedStringArray()
	for s in p_sides:
		names.append(SIDE_NAMES[s])
	if names.size() <= 1:
		return "the " + (names[0] if names.size() == 1 else "dark")
	return "the " + ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


func _shuffle(arr: Array) -> void:
	for n in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, n)
		var tmp = arr[n]
		arr[n] = arr[j]
		arr[j] = tmp


func get_save_data() -> Dictionary:
	var queue := []
	for entry in _queue:
		queue.append([int(entry[0]), enemies.kinds[int(entry[1])].id, int(entry[2]), float(entry[3])])
	return {"night": night, "shape": shape, "sides": sides, "start_tick": _start_tick,
		"queue": queue, "rng_state": _rng.state}


func load_save_data(data: Dictionary) -> void:
	_queue.clear()
	night = int(data.get("night", 0))
	shape = String(data.get("shape", ""))
	sides = PackedInt32Array(data.get("sides", PackedInt32Array()))
	_start_tick = int(data.get("start_tick", 0))
	for entry in data.get("queue", []):
		var k := enemies.kind_index(String(entry[1]))
		if k != -1:
			_queue.append([int(entry[0]), k, int(entry[2]), float(entry[3])])
	if data.has("rng_state"):
		_rng.state = int(data["rng_state"])
