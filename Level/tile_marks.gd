class_name TileMarks
extends Node2D
## Draws the lava tiles marked for cobble: a see-through fill and an outline
## per tile. Redrawn only when the marks change, never per frame.

const FILL := Color(0.35, 0.8, 1.0, 0.35)
const EDGE := Color(0.6, 0.95, 1.0, 0.9)

var _lava: LavaWorks
var _level: LevelGenerator


func bind(lava: LavaWorks, level: LevelGenerator) -> void:
	_lava = lava
	_level = level
	lava.marks_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if _lava == null or _level.ground_layer == null or _level.ground_layer.tile_set == null:
		return
	var size := Vector2(_level.ground_layer.tile_set.tile_size)
	for i in _lava.marked_tiles():
		var center := _level.cell_to_world(_level.grid.cell_at(i))
		var r := Rect2(center - size / 2.0, size).grow(-2.0)
		draw_rect(r, FILL)
		draw_rect(r, EDGE, false, 2.0)
