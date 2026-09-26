class_name FlowFields
extends RefCounted
## The flow-field cache (D5): at most SLOTS fields, one per (target building,
## ground or flying), shared by every enemy heading there.
##
## Owns the two ENEMY cost layers, one byte per tile, kept in step with the
## grid through tiles_changed:
##   0          impassable -- water, lava, void (ground only), and trees, mines,
##              stumps and points of interest (enemies walk around those)
##   10 / 14    open or rough ground (flyers: 10 everywhere)
##   BREAK_COST a player building: passable only by smashing it
## so an enemy goes around your buildings when it reasonably can, and through
## them when they wall its target in.
##
## A grid change marks every field dirty; each rebuilds in slices from
## advance(), sharing one budget, while enemies keep the old directions.

const SLOTS := 8
## What stepping into a player building costs, in tenths of a tile: an enemy
## walks up to about 24 extra tiles around a building rather than break
## through it. Breaking is slow (a house takes a goblin ~15 s), and this cost is
## what that time is worth in walking. Must stay below 256: a byte.
const BREAK_COST := 250
## Fields nobody has planned with for this long are dropped when a slot is needed.
const IDLE_TICKS := 180

## Tile expansions per simulation tick, shared by every field being built.
## Each costs about 2 microseconds in GDScript, so this is roughly 1.5 ms a
## tick; a 100x100 map's field is ready in about 13 ticks.
var budget_per_tick := 800
## Bumped whenever any field finishes a build. Enemies remember the value they
## planned with and re-plan when it moves: one integer compare per tick
## instead of looking their field up.
var generation := 0

var level: LevelGenerator
var cost_ground := PackedByteArray()
var cost_fly := PackedByteArray()
var _fields: Array[FlowField] = []


func setup(p_level: LevelGenerator) -> void:
	level = p_level
	# Methods, not lambdas (see WorkerRoster.attach). The grid object lives as
	# long as the level: resize() reuses it.
	level.level_generated.connect(_on_level_generated)
	level.grid.tiles_changed.connect(_on_tiles_changed)


func clear() -> void:
	_fields.clear()


func _on_level_generated() -> void:
	_fields.clear()
	var n := level.grid.tile_count()
	cost_ground.resize(n)
	cost_fly.resize(n)
	for i in n:
		_derive(i)


func _on_tiles_changed(indices: PackedInt32Array) -> void:
	if cost_ground.size() != level.grid.tile_count():
		return   # mid-generation; level_generated rebuilds everything
	for i in indices:
		_derive(i)
	# Enemies re-plan at once (the ground under a planned step may have
	# changed), even before the fields catch up.
	generation += 1
	for f in _fields:
		if f.is_building():
			f.dirty = true   # finish, then start again with the new ground
		else:
			_start(f)


func _derive(i: int) -> void:
	var g := level.grid
	var occ := g.occupancy[i]
	if occ != WorldGrid.NO_OCCUPANT:
		var player := level.get_building_data(level.store.get_type(occ)) != null
		var c := BREAK_COST if player else 0
		cost_ground[i] = c
		cost_fly[i] = c
		return
	var ground: int = g.ground[i]
	cost_fly[i] = 10
	if (int(WorldGrid.GROUND_BLOCKING[ground]) & WorldGrid.BLOCKS_UNIT) != 0:
		cost_ground[i] = 0
	else:
		cost_ground[i] = int(WorldGrid.GROUND_COST[ground])


func costs(flying: bool) -> PackedByteArray:
	return cost_fly if flying else cost_ground


## The field toward `target`, creating it if a slot is free (or can be freed).
## Returns null when every slot is busy with a field someone is using: the
## caller should pick a target that already has one.
func request(target: int, flying: bool, tick: int) -> FlowField:
	var f := find(target, flying)
	if f != null:
		return f
	if _fields.size() >= SLOTS:
		var oldest := -1
		for n in _fields.size():
			if tick - _fields[n].last_used > IDLE_TICKS and (oldest == -1
					or _fields[n].last_used < _fields[oldest].last_used):
				oldest = n
		if oldest == -1:
			return null
		_fields.remove_at(oldest)
	f = FlowField.new()
	f.target = target
	f.flying = flying
	f.last_used = tick
	_fields.append(f)
	_start(f)
	return f


func find(target: int, flying: bool) -> FlowField:
	for f in _fields:
		if f.target == target and f.flying == flying:
			return f
	return null


## The target is gone: its fields are useless.
func drop_target(target: int) -> void:
	for n in range(_fields.size() - 1, -1, -1):
		if _fields[n].target == target:
			_fields.remove_at(n)


func count() -> int:
	return _fields.size()


func _start(f: FlowField) -> void:
	var goal := PackedInt32Array()
	var store := level.store
	if store.is_alive(f.target):
		var o := store.get_cell(f.target)
		var sz := store.get_size(f.target)
		for y in sz.y:
			for x in sz.x:
				var c := o + Vector2i(x, y)
				if level.grid.in_bounds(c):
					goal.append(level.grid.index(c))
	f.start(level.grid.tile_count(), goal)


## One simulation tick of building work, shared across the fields in progress.
func advance() -> void:
	var left := budget_per_tick
	var w := level.grid.size.x
	var h := level.grid.size.y
	for f in _fields:
		if left <= 0:
			break
		if not f.is_building():
			if f.dirty:
				_start(f)
			else:
				continue
		var before := f.version
		left -= f.advance(costs(f.flying), w, h, left)
		if f.version != before:
			generation += 1
