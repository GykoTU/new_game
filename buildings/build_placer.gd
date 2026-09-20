class_name BuildPlacer
extends Node2D
## Placement mode: shows a see-through preview of a building under the mouse,
## green where it can go and red where it can't. Left click places it,
## right click cancels (unless cancelling is disabled, like for the first base).

signal placement_finished(type: String, cell: Vector2i)
signal placement_cancelled

@export var level: LevelGenerator
@export var valid_color := Color(0.6, 1.0, 0.6, 0.7)
@export var invalid_color := Color(1.0, 0.4, 0.4, 0.7)

var _type := ""
var _cancellable := true
var _cell := Vector2i.ZERO
var _ghost := Sprite2D.new()


func _ready() -> void:
	_ghost.z_index = 100 # draw above the map and buildings
	_ghost.hide()
	add_child(_ghost)
	set_process(false)


func start(type: String, cancellable := true) -> void:
	var data := level.get_building_data(type)
	if data == null:
		push_error("BuildPlacer: no BuildingData with id '%s'." % type)
		return
	_type = type
	_cancellable = cancellable
	_ghost.texture = data.texture
	_ghost.show()
	set_process(true)


func stop() -> void:
	_type = ""
	_ghost.hide()
	set_process(false)


func is_active() -> bool:
	return _type != ""


func _process(_delta: float) -> void:
	var data := level.get_building_data(_type)
	_cell = level.world_to_cell(get_global_mouse_position())
	_ghost.global_position = level.cell_to_world(_cell) + level.get_footprint_offset(data.size)
	_ghost.modulate = valid_color if level.can_place(_type, _cell) else invalid_color


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var type := _type
			var cell := _cell
			if level.place_building(type, cell):
				stop()
				placement_finished.emit(type, cell)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _cancellable:
			stop()
			placement_cancelled.emit()
			get_viewport().set_input_as_handled()
