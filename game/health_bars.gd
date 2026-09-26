class_name HealthBars
extends Node2D
## Small bars over damaged player buildings and hurt workers out in the open.
## Only what is damaged gets a bar, so a healthy base shows nothing. Drawn in
## code; no art.

@export var building_width := 28.0
@export var unit_width := 18.0
@export var height := 4.0

var _level: LevelGenerator
var _units: UnitSystem
var _bars: Array = []   # [center_top, width, fraction]


func _ready() -> void:
	z_index = 3   # over units and the fog's soft edge


func bind(level: LevelGenerator, units: UnitSystem) -> void:
	_level = level
	_units = units


## Once per rendered frame.
func refresh() -> void:
	var had := not _bars.is_empty()
	_bars.clear()
	if _level == null or _level.ground_layer == null:
		return
	var tile := float(_level.ground_layer.tile_set.tile_size.y)
	var bs := _level.store
	for b in bs.alive_ids():
		var hp := bs.get_health(b)
		var mx := bs.get_max_health(b)
		if hp >= mx or mx <= 0.0:
			continue
		if _level.get_building_data(bs.get_type(b)) == null:
			continue   # trees and mines are never hurt anyway
		var center := _level.cell_to_world(bs.get_cell(b)) + _level.get_footprint_offset(bs.get_size(b))
		var top := center - Vector2(0.0, bs.get_size(b).y * tile / 2.0 + 4.0)
		_bars.append([top, building_width, hp / mx])
	var us := _units.store
	for u in us.size():
		if not _units.is_exposed(u):
			continue
		var max_hp := _units.max_health(us.kind[u])
		if us.hp[u] < max_hp:
			_bars.append([us.pos[u] - Vector2(0.0, 18.0), unit_width, us.hp[u] / max_hp])
	if had or not _bars.is_empty():
		queue_redraw()


func _draw() -> void:
	for bar in _bars:
		var top: Vector2 = bar[0]
		var w: float = bar[1]
		var f: float = clampf(bar[2], 0.0, 1.0)
		var r := Rect2(top - Vector2(w / 2.0, 0.0), Vector2(w, height))
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75))
		var col := Color(0.85, 0.2, 0.15).lerp(Color(0.35, 0.85, 0.3), f)
		draw_rect(Rect2(r.position, Vector2(w * f, height)), col)
