class_name WallTiles
extends RefCounted
## Picks the right picture for every wall and gate sprite (Stage 6).
##
## Walls: the connecting sheet (16 frames of 32x32; frame = which neighbours
## are walls or gates: N=1, E=2, S=4, W=8), or the single wall.png until the
## sheet exists. Gates: open by day, closed at night; drawn for a horizontal
## wall, and for a vertical one (walls north or south, none east or west)
## with the _v pictures, or the horizontal ones turned 90 degrees.
##
## Buildings stay ordinary Sprite2Ds (LevelGenerator); this only changes their
## texture, region and rotation, for the changed tile and its neighbours.

const DIR := "res://assets/buildings/walls/"
const WALL := DIR + "wall.png"
const WALL_SHEET := DIR + "wall_sheet.png"
const GATE_OPEN := DIR + "gate_open.png"
const GATE_CLOSED := DIR + "gate_closed.png"
const GATE_OPEN_V := DIR + "gate_open_v.png"
const GATE_CLOSED_V := DIR + "gate_closed_v.png"

var level: LevelGenerator
var _night := false


func bind(p_level: LevelGenerator) -> void:
	level = p_level
	# Methods, not lambdas.
	level.level_generated.connect(refresh_all)
	level.building_placed.connect(_on_placed)
	level.building_removed.connect(_on_removed)


static func art_paths() -> Array:
	return [WALL, WALL_SHEET, GATE_OPEN, GATE_CLOSED, GATE_OPEN_V, GATE_CLOSED_V]


func set_night(night: bool) -> void:
	if night == _night:
		return
	_night = night
	for b in level.store.alive_ids():
		if level.store.get_type(b) == "gate":
			_update(b)


func refresh_all() -> void:
	for b in level.store.alive_ids():
		if _is_wallish(b):
			_update(b)


func _on_placed(_type: String, cell: Vector2i) -> void:
	_around(cell)


func _on_removed(_id: int, _type: String, cell: Vector2i) -> void:
	_around(cell)


func _around(cell: Vector2i) -> void:
	for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var c: Vector2i = cell + d
		if level.grid.in_bounds(c):
			var b := level.grid.get_occupant(c)
			if _is_wallish(b):
				_update(b)


func _is_wallish(b: int) -> bool:
	if not level.store.is_alive(b):
		return false
	var t := level.store.get_type(b)
	return t == "wall" or t == "gate"


## N=1, E=2, S=4, W=8: which neighbours are walls or gates.
func mask_of(cell: Vector2i) -> int:
	var m := 0
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for n in 4:
		var c: Vector2i = cell + dirs[n]
		if level.grid.in_bounds(c) and _is_wallish(level.grid.get_occupant(c)):
			m |= 1 << n
	return m


func _update(b: int) -> void:
	var sprite := level.store.get_sprite(b)
	if sprite == null:
		return
	var cell := level.store.get_cell(b)
	var m := mask_of(cell)
	sprite.rotation = 0.0
	if level.store.get_type(b) == "wall":
		if Art.exists(WALL_SHEET):
			sprite.texture = Art.texture(WALL_SHEET)
			sprite.region_enabled = true
			var h := float(sprite.texture.get_height())
			sprite.region_rect = Rect2(m * h, 0.0, h, h)
		else:
			sprite.region_enabled = false
			sprite.texture = Art.texture(WALL)
		return
	# A gate: vertical if it joins walls north/south but not east/west.
	var vertical := (m & 5) != 0 and (m & 10) == 0
	var closed := _night
	var path := GATE_CLOSED if closed else GATE_OPEN
	sprite.region_enabled = false
	if vertical:
		var v := GATE_CLOSED_V if closed else GATE_OPEN_V
		if Art.exists(v):
			path = v
		else:
			sprite.rotation = PI / 2.0
	sprite.texture = Art.texture(path)
