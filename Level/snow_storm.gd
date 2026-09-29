class_name SnowStorm
extends RefCounted
## The snowfield's storm (Stage 10). Snow tiles are COVERED unless something of
## the player's sees them right now:
##
##   workers and buildings  a small disc around them (UNIT_SIGHT, BUILDING_SIGHT)
##   watchtowers            a long cone the player aims (Watchtowers)
##
## Sight is blocked by mountains like exploring is (WorldGrid.sees). A covered
## tile hides everything on it that is not the player's: terrain, mines,
## caches and enemies. Enemies on covered tiles cannot be targeted -- by any
## weapon, wherever it stands (EnemySystem.is_hidden).
##
## `storm` is one byte per tile, 255 = covered, handed as it is to
## StormRenderer's texture like the fog. It is rebuilt every UPDATE_TICKS ticks
## from the snow tiles' base (every snow tile covered) and the sight sources;
## only tiles near snow are ever touched, so a map without snow costs nothing.

const COVERED := 255
const UPDATE_TICKS := 6
const UNIT_SIGHT := 3
const EXPLORER_SIGHT := 4
const BUILDING_SIGHT := 3

## Covered snow tiles (255) or not (0), per tile.
var storm := PackedByteArray()
## Bumped whenever `storm` was rebuilt (the renderer compares it).
var version := 0

var level: LevelGenerator
var units: UnitStore
var watchtowers   # Watchtowers (untyped: it holds a reference back)
var _base := PackedByteArray()        # every snow tile covered
var _near_snow := PackedByteArray()   # 1 within BUILDING_SIGHT + 1 of snow
var _has_snow := false
var _sources := {}                    # building id -> its visible disc (indices)
var _origin := Vector2.ZERO
var _inv_tile := 1.0 / 32.0


func setup(p_level: LevelGenerator, p_units: UnitStore) -> void:
	level = p_level
	units = p_units
	# Methods, not lambdas (see WorkerRoster.attach).
	level.level_generated.connect(_on_level_generated)
	level.building_removed.connect(_on_building_removed)
	level.construction_completed.connect(_on_construction_completed)
	level.building_placed.connect(_on_building_placed)


func has_snow() -> bool:
	return _has_snow


## True if the tile at index `i` is covered by the storm.
func hidden_at(i: int) -> bool:
	return _has_snow and i >= 0 and i < storm.size() and storm[i] == COVERED


## True if the world position is on a covered tile.
func hidden_pos(p: Vector2) -> bool:
	if not _has_snow:
		return false
	var g := level.grid
	var cx := floori((p.x - _origin.x) * _inv_tile)
	var cy := floori((p.y - _origin.y) * _inv_tile)
	if cx < 0 or cy < 0 or cx >= g.size.x or cy >= g.size.y:
		return false
	return storm[cy * g.size.x + cx] == COVERED


func _on_level_generated() -> void:
	var g := level.grid
	var n := g.tile_count()
	var tile := float(level.ground_layer.tile_set.tile_size.x)
	_inv_tile = 1.0 / tile
	_origin = level.cell_to_world(Vector2i.ZERO) - Vector2(tile, tile) / 2.0
	_base.resize(n)
	_base.fill(0)
	_near_snow.resize(n)
	_near_snow.fill(0)
	_has_snow = false
	var reach := BUILDING_SIGHT + 1
	for i in n:
		if g.ground[i] != WorldGrid.Ground.SNOW:
			continue
		_has_snow = true
		_base[i] = COVERED
		var c := g.cell_at(i)
		for y in range(maxi(c.y - reach, 0), mini(c.y + reach, g.size.y - 1) + 1):
			for x in range(maxi(c.x - reach, 0), mini(c.x + reach, g.size.x - 1) + 1):
				_near_snow[y * g.size.x + x] = 1
	_sources.clear()
	for id in level.store.alive_ids():
		_consider(id)
	storm = _base.duplicate()
	version += 1


## A player building near snow becomes a sight source once it stands.
func _consider(id: int) -> void:
	if not _has_snow or not level.store.is_alive(id) or not level.store.is_complete(id):
		return
	if level.get_building_data(level.store.get_type(id)) == null:
		return   # mines, trees, caves: not the player's
	var cell := level.store.get_cell(id)
	@warning_ignore("integer_division")
	var mid := cell + level.store.get_size(id) / 2
	if _near_snow[level.grid.index(mid)] == 0:
		return
	_sources[id] = level.grid.visible_disc(mid, BUILDING_SIGHT)


func _on_building_placed(_type: String, cell: Vector2i) -> void:
	_consider(level.grid.get_occupant(cell))


func _on_construction_completed(id: int) -> void:
	_consider(id)


func _on_building_removed(id: int, _type: String, _cell: Vector2i) -> void:
	_sources.erase(id)


## One simulation tick. Rebuilds the storm every UPDATE_TICKS ticks.
func step(tick: int) -> void:
	if not _has_snow or tick % UPDATE_TICKS != 0:
		return
	rebuild()


func rebuild() -> void:
	if not _has_snow:
		return
	var g := level.grid
	storm = _base.duplicate()
	for id in _sources:
		for i in _sources[id]:
			storm[i] = 0
	if watchtowers != null:
		for tiles in watchtowers.cone_tiles():
			for i in tiles:
				storm[i] = 0
	var w := g.size.x
	for id in units.size():
		if not units.is_alive(id):
			continue
		var p: Vector2 = units.pos[id]
		var cx := floori((p.x - _origin.x) * _inv_tile)
		var cy := floori((p.y - _origin.y) * _inv_tile)
		if cx < 0 or cy < 0 or cx >= w or cy >= g.size.y or _near_snow[cy * w + cx] == 0:
			continue
		var r := EXPLORER_SIGHT if units.kind[id] == WorkerRoster.Kind.EXPLORER else UNIT_SIGHT
		for i in g.visible_disc(Vector2i(cx, cy), r):
			storm[i] = 0
	version += 1
