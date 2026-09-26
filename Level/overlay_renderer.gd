class_name OverlayRenderer
extends Node2D
## Draws roads, bridges and crossings (Stage 6): the built ones, and faded
## plans waiting for a builder. A child of the level, kept between the ground
## and the buildings, so a wall on a road hides it.
##
## Each kind uses its connecting sheet if it exists (16 frames of 32x32,
## frame = neighbours of the same kind: N=1, E=2, S=4, W=8), else its single
## tile, else a plain coloured stand-in. Redrawn only when the grid or the
## plans change, never per frame.

const FILES := {
	WorldGrid.Overlay.ROAD: ["res://assets/ground/road.png", "res://assets/ground/road_sheet.png"],
	WorldGrid.Overlay.BRIDGE: ["res://assets/ground/bridge.png", "res://assets/ground/bridge_sheet.png"],
	WorldGrid.Overlay.CROSSING: ["res://assets/ground/crossing.png", "res://assets/ground/crossing_sheet.png"],
}
const STAND_IN := {
	WorldGrid.Overlay.ROAD: Color(0.55, 0.45, 0.32),
	WorldGrid.Overlay.BRIDGE: Color(0.6, 0.42, 0.24),
	WorldGrid.Overlay.CROSSING: Color(0.5, 0.52, 0.58),
}
const PLAN_ALPHA := 0.45

var _level: LevelGenerator
var _tools: BuildTools
var _single := {}   # kind -> Texture2D or null
var _sheet := {}    # kind -> Texture2D or null
var _dirty := true


func bind(level: LevelGenerator, tools: BuildTools) -> void:
	_level = level
	_tools = tools
	for kind in FILES:
		_single[kind] = Art.texture(FILES[kind][0]) if Art.exists(FILES[kind][0]) else null
		_sheet[kind] = Art.texture(FILES[kind][1]) if Art.exists(FILES[kind][1]) else null
	# Methods, not lambdas.
	level.level_generated.connect(_on_level_generated)
	level.grid.tiles_changed.connect(_on_tiles_changed)
	tools.plans_changed.connect(_mark_dirty)


static func art_paths() -> Array:
	var out := []
	for kind in FILES:
		out.append_array(FILES[kind])
	return out


func _on_level_generated() -> void:
	# The level rebuilds its ground and building nodes on every new map: stay
	# between them.
	if get_parent() == _level and _level.buildings_root != null:
		_level.move_child(self, _level.buildings_root.get_index())
	_mark_dirty()


func _on_tiles_changed(_indices: PackedInt32Array) -> void:
	_mark_dirty()


func _mark_dirty() -> void:
	_dirty = true
	queue_redraw()


## Which neighbours (N, E, S, W) hold the same kind, built or planned.
func _mask(i: int, kind: int) -> int:
	var g := _level.grid
	var c := g.cell_at(i)
	var m := 0
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for n in 4:
		var d: Vector2i = c + dirs[n]
		if not g.in_bounds(d):
			continue
		var j := g.index(d)
		if g.overlay[j] == kind or (_tools.plans().has(j) and int(_tools.plans()[j][0]) == kind):
			m |= 1 << n
	return m


func _draw() -> void:
	if _level == null or _level.ground_layer == null or _level.ground_layer.tile_set == null:
		return
	_dirty = false
	var g := _level.grid
	var tile := Vector2(_level.ground_layer.tile_set.tile_size)
	var over := g.overlay
	for i in over.size():
		if over[i] != WorldGrid.Overlay.NONE:
			_draw_tile(i, over[i], 1.0, tile)
	var plans := _tools.plans()
	for i in plans:
		_draw_tile(i, int(plans[i][0]), PLAN_ALPHA, tile)


func _draw_tile(i: int, kind: int, alpha: float, tile: Vector2) -> void:
	var centre := _level.cell_to_world(_level.grid.cell_at(i))
	var rect := Rect2(centre - tile / 2.0, tile)
	var modulate_colour := Color(1, 1, 1, alpha)
	var sheet: Texture2D = _sheet.get(kind)
	if sheet != null:
		draw_texture_rect_region(sheet, rect, Rect2(_mask(i, kind) * tile.x, 0.0, tile.x, tile.y), modulate_colour)
		return
	var single: Texture2D = _single.get(kind)
	if single != null:
		draw_texture_rect(single, rect, false, modulate_colour)
		return
	var c: Color = STAND_IN[kind]
	draw_rect(rect.grow(-1.0), Color(c.r, c.g, c.b, 0.9 * alpha))
	if kind != WorldGrid.Overlay.ROAD:   # planks / slabs
		for k in range(1, 4):
			var y := rect.position.y + rect.size.y * k / 4.0
			draw_line(Vector2(rect.position.x + 2, y), Vector2(rect.end.x - 2, y), Color(0, 0, 0, 0.25 * alpha), 1.0)
