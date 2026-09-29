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
## Stage 10: on a map with caves, groups come out of CAVE MOUTHS instead of
## the edges. Walkers use the caves whose exit the base can be reached from on
## the ground (bridges, crossings and cobble count; buildings do not, since
## enemies break them), so opening a pass joins that region's caves to the
## night. Fliers use any cave within FLIER_RANGE tiles of the base, over the
## ridges. A queue entry's source is then a cave's tile index, not a side.
## Maps without caves (older saves, tests) still use the edges.
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

## How far (tiles) fliers may come from, over the mountains.
const FLIER_RANGE := 60.0

var enemies: EnemySystem
var level: LevelGenerator
## Tonight's groups come from caves (tile indices of cave mouths), not sides.
var from_caves := false
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
	from_caves = false
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
	# Sides (or caves): one, then two from night 3, three from night 6.
	var n_sides := 1 if night < 3 else (2 if night < 6 else 3)
	var walk_from := PackedInt32Array()
	var fly_from := PackedInt32Array()
	from_caves = _pick_caves(n_sides, walk_from, fly_from)
	if from_caves:
		sides = _directions_of(walk_from + fly_from)
	else:
		var all := [Side.NORTH, Side.EAST, Side.SOUTH, Side.WEST]
		_shuffle(all)
		sides = PackedInt32Array(all.slice(0, n_sides))
	# Groups, each at its own moment and side (or cave).
	var i := 0
	while i < picks.size():
		var size := _rng.randi_range(group_size.x, group_size.y)
		var side: int = sides[_rng.randi() % sides.size()]
		if from_caves:
			var pool := fly_from if enemies.kinds[picks[i]].flying and not fly_from.is_empty() else walk_from
			if pool.is_empty():
				pool = fly_from
			side = pool[_rng.randi() % pool.size()]
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
		var at := cave_point(int(entry[2])) if from_caves \
			else spawn_point(int(entry[2]), enemies.kinds[int(entry[1])].flying)
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


## Tonight's caves: `n` for walkers among those the base can be walked to
## from, `n` for fliers among those within FLIER_RANGE. False if the map has
## no caves (or none is usable): the edges are used instead.
func _pick_caves(n: int, walk_from: PackedInt32Array, fly_from: PackedInt32Array) -> bool:
	var ids := level.caves()
	if ids.is_empty():
		return false
	var g := level.grid
	var home := level.base_cell if level.base_cell != LevelGenerator.INVALID_CELL else level.start_cell
	var reach := reachable_from(home)
	var walkable := []
	var near := []
	for id in ids:
		var cell := level.store.get_cell(id)
		var exit := level.cave_exit_of(cell)
		if exit == LevelGenerator.INVALID_CELL:
			continue
		if reach[g.index(exit)] != 0:
			walkable.append(g.index(cell))
		if Vector2(cell - home).length() <= FLIER_RANGE:
			near.append(g.index(cell))
	if walkable.is_empty() and near.is_empty():
		return false
	_shuffle(walkable)
	_shuffle(near)
	for k in mini(n, walkable.size()):
		walk_from.append(walkable[k])
	for k in mini(n, near.size()):
		fly_from.append(near[k])
	return true


## 1 for every tile a walker could reach from `cell` on the ground alone
## (overlays count, buildings do not: enemies break them), else 0.
func reachable_from(cell: Vector2i) -> PackedByteArray:
	var g := level.grid
	var out := PackedByteArray()
	out.resize(g.tile_count())
	var w := g.size.x
	var stack := PackedInt32Array()
	for dy in [-1, 0, 1, 2, 3]:
		for dx in [-1, 0, 1, 2, 3]:
			var c: Vector2i = cell + Vector2i(dx, dy)
			if g.in_bounds(c) and (g.ground_blocking_at(g.index(c)) & WorldGrid.BLOCKS_UNIT) == 0:
				out[g.index(c)] = 1
				stack.append(g.index(c))
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		@warning_ignore("integer_division")
		var y := i / w
		var x := i % w
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= g.size.y:
				continue
			var j := ny * w + nx
			if out[j] == 0 and (g.ground_blocking_at(j) & WorldGrid.BLOCKS_UNIT) == 0:
				out[j] = 1
				stack.append(j)
	return out


## Where a group from the cave at tile index `i` steps out, or Vector2.INF.
func cave_point(i: int) -> Vector2:
	var g := level.grid
	if i < 0 or i >= g.tile_count():
		return Vector2.INF
	var exit := level.cave_exit_of(g.cell_at(i))
	if exit == LevelGenerator.INVALID_CELL:
		return Vector2.INF
	var tile := float(level.ground_layer.tile_set.tile_size.x)
	return level.cell_to_world(exit) + Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)) * tile


## The compass sides the given caves lie on, seen from the base, for the toast.
func _directions_of(cave_tiles: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var home := level.base_cell if level.base_cell != LevelGenerator.INVALID_CELL else level.start_cell
	for i in cave_tiles:
		var d := Vector2(level.grid.cell_at(i) - home)
		var side: int
		if absf(d.x) > absf(d.y):
			side = Side.EAST if d.x > 0 else Side.WEST
		else:
			side = Side.SOUTH if d.y > 0 else Side.NORTH
		if not out.has(side):
			out.append(side)
	return out


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
		"queue": queue, "rng_state": _rng.state, "caves": from_caves}


func load_save_data(data: Dictionary) -> void:
	_queue.clear()
	night = int(data.get("night", 0))
	shape = String(data.get("shape", ""))
	sides = PackedInt32Array(data.get("sides", PackedInt32Array()))
	_start_tick = int(data.get("start_tick", 0))
	from_caves = bool(data.get("caves", false))
	for entry in data.get("queue", []):
		var k := enemies.kind_index(String(entry[1]))
		if k != -1:
			_queue.append([int(entry[0]), k, int(entry[2]), float(entry[3])])
	if data.has("rng_state"):
		_rng.state = int(data["rng_state"])
