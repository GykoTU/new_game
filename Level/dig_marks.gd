class_name DigMarks
extends Node2D
## Draws the buildings marked for digging out: the optional shovel mark sprite
## over each, or a brown outline round its footprint. Redrawn only when the
## marks change.

const MARK := "res://assets/ui/shovel_mark.png"
const EDGE := Color(0.62, 0.42, 0.2, 0.95)
const FILL := Color(0.45, 0.3, 0.15, 0.22)

var _demolition: Demolition
var _level: LevelGenerator
var _mark: Texture2D


func _ready() -> void:
	z_index = 1   # over the buildings, with the units
	if Art.exists(MARK):
		_mark = Art.texture(MARK)


func bind(demolition: Demolition, level: LevelGenerator) -> void:
	_demolition = demolition
	_level = level
	demolition.marks_changed.connect(queue_redraw)
	level.construction_completed.connect(_on_changed)
	queue_redraw()


func _on_changed(_id: int) -> void:
	queue_redraw()


func _draw() -> void:
	if _demolition == null or _level.ground_layer == null or _level.ground_layer.tile_set == null:
		return
	var tile := Vector2(_level.ground_layer.tile_set.tile_size)
	for id in _demolition.marked():
		var size := Vector2(_level.store.get_size(id)) * tile
		var centre := _level.cell_to_world(_level.store.get_cell(id)) \
			+ _level.get_footprint_offset(_level.store.get_size(id))
		var r := Rect2(centre - size / 2.0, size).grow(-1.0)
		if _mark != null:
			var s := Vector2(_mark.get_width(), _mark.get_height())
			draw_texture(_mark, centre - s / 2.0)
		else:
			draw_rect(r, FILL)
			draw_rect(r, EDGE, false, 2.0)
