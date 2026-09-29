class_name WatchCones
extends Node2D
## Draws watchtower cones (Stage 10): a faint wedge for every finished tower,
## and a brighter preview while the player is aiming one.

const COLOUR := Color(1.0, 0.95, 0.7, 0.10)
const EDGE := Color(1.0, 0.95, 0.7, 0.35)
const PREVIEW := Color(1.0, 0.9, 0.5, 0.22)

var _level: LevelGenerator
var _towers: Watchtowers
## The tower being aimed (building id), or -1; the preview follows the mouse.
var aiming := -1


func _ready() -> void:
	z_index = 3   # over the storm and the fog: the player must see what they aim


func bind(level: LevelGenerator, towers: Watchtowers) -> void:
	_level = level
	_towers = towers
	towers.changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	if aiming != -1:
		queue_redraw()


func _draw() -> void:
	if _level == null or _towers == null:
		return
	for id in _level.store.alive_ids():
		if not _towers.is_watchtower(id) or id == aiming:
			continue
		if _level.store.is_complete(id):
			_wedge(id, _towers.aim_of(id), COLOUR, EDGE)
	if aiming != -1 and _towers.is_watchtower(aiming):
		var from := _level.cell_to_world(_towers.centre_of(aiming))
		_wedge(aiming, (get_global_mouse_position() - from).angle(), PREVIEW, EDGE)


func _wedge(id: int, angle: float, fill: Color, edge: Color) -> void:
	var tile := float(_level.ground_layer.tile_set.tile_size.x)
	var from := to_local(_level.cell_to_world(_towers.centre_of(id)))
	var r := Watchtowers.CONE_LENGTH * tile
	var pts := PackedVector2Array([from])
	var steps := 12
	for k in steps + 1:
		var a := angle - Watchtowers.CONE_HALF + 2.0 * Watchtowers.CONE_HALF * k / steps
		pts.append(from + Vector2.RIGHT.rotated(a) * r)
	draw_colored_polygon(pts, fill)
	var rim := pts.duplicate()
	rim.append(from)
	draw_polyline(rim, edge, 1.5, true)
