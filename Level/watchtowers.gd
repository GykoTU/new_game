class_name Watchtowers
extends RefCounted
## Where each watchtower looks (Stage 10). A finished watchtower sees a long
## CONE in the direction the player aimed it: CONE_LENGTH tiles, CONE_HALF
## either side, blocked by mountains. The cone explores what it covers (once,
## when set) and, in the snowfield, keeps it clear of the storm (SnowStorm).
##
## The aim is set right after placing a tower (main.gd asks for a click) and
## can be changed by clicking the tower later. A tower not yet aimed looks
## away from the base. Saved by cell: {"x,y": angle in radians}.

signal changed

const TYPE := "watchtower"
const CONE_LENGTH := 14
const CONE_HALF := deg_to_rad(25.0)

var level: LevelGenerator
var fog: FogOfWar
var _aim := {}     # building id -> angle
var _cones := {}   # building id -> PackedInt32Array (finished towers only)


func setup(p_level: LevelGenerator, p_fog: FogOfWar) -> void:
	level = p_level
	fog = p_fog
	# Methods, not lambdas (see WorkerRoster.attach).
	level.building_removed.connect(_on_building_removed)
	level.construction_completed.connect(_on_construction_completed)
	level.level_generated.connect(_on_level_generated)


func clear() -> void:
	_aim.clear()
	_cones.clear()


func is_watchtower(id: int) -> bool:
	return level.store.is_alive(id) and level.store.get_type(id) == TYPE


## The tower's centre tile.
func centre_of(id: int) -> Vector2i:
	@warning_ignore("integer_division")
	return level.store.get_cell(id) + level.store.get_size(id) / 2


func aim_of(id: int) -> float:
	if _aim.has(id):
		return _aim[id]
	var home := level.base_cell if level.base_cell != LevelGenerator.INVALID_CELL else level.start_cell
	var away := Vector2(centre_of(id) - home)
	return away.angle() if away.length_squared() > 0.0 else 0.0


## Points tower `id` at the world position `at`.
func aim_at(id: int, at: Vector2) -> void:
	if not is_watchtower(id):
		return
	var from := level.cell_to_world(centre_of(id))
	set_aim(id, (at - from).angle())


func set_aim(id: int, angle: float) -> void:
	_aim[id] = wrapf(angle, -PI, PI)
	if level.store.is_complete(id):
		_build_cone(id)
	changed.emit()


## Every finished tower's cone, as tile indices.
func cone_tiles() -> Array:
	return _cones.values()


## The tiles a tower at `centre` aimed at `angle` sees (for the preview too).
func cone(centre: Vector2i, angle: float) -> PackedInt32Array:
	var g := level.grid
	var out := PackedInt32Array()
	var dir := Vector2.RIGHT.rotated(angle)
	var r := CONE_LENGTH
	var cos_half := cos(CONE_HALF)
	for y in range(maxi(centre.y - r, 0), mini(centre.y + r, g.size.y - 1) + 1):
		for x in range(maxi(centre.x - r, 0), mini(centre.x + r, g.size.x - 1) + 1):
			var d := Vector2(x - centre.x, y - centre.y)
			var dist := d.length()
			if dist > r + 0.5:
				continue
			if dist >= 1.0 and d.dot(dir) < dist * cos_half:
				continue
			var c := Vector2i(x, y)
			if g.sees(centre, c):
				out.append(g.index(c))
	return out


func _build_cone(id: int) -> void:
	var tiles := cone(centre_of(id), aim_of(id))
	_cones[id] = tiles
	# What the cone covers is explored, like any sight.
	var fresh := PackedInt32Array()
	var g := level.grid
	for i in tiles:
		if g.explored[i] == WorldGrid.UNEXPLORED:
			g.explored[i] = WorldGrid.EXPLORED
			fresh.append(i)
	if not fresh.is_empty() and fog != null:
		fog.revealed.emit(fresh)


func _on_construction_completed(id: int) -> void:
	if is_watchtower(id):
		_build_cone(id)
		changed.emit()


func _on_building_removed(id: int, _type: String, _cell: Vector2i) -> void:
	if _aim.erase(id) or _cones.erase(id):
		changed.emit()


func _on_level_generated() -> void:
	_cones.clear()
	for id in level.store.alive_ids():
		if is_watchtower(id) and level.store.is_complete(id):
			_build_cone(id)


func get_save_data() -> Dictionary:
	var out := {}
	for id in _aim:
		if level.store.is_alive(id):
			var c := level.store.get_cell(id)
			out["%d,%d" % [c.x, c.y]] = _aim[id]
	return out


## After the level: towers are found by cell.
func load_save_data(data: Dictionary) -> void:
	_aim.clear()
	_cones.clear()
	for key in data:
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		var id := level.grid.get_occupant(Vector2i(int(parts[0]), int(parts[1])))
		if is_watchtower(id):
			_aim[id] = float(data[key])
	_on_level_generated()
	changed.emit()
