class_name BuildPlacer
extends Node2D
## Placement mode: shows a see-through preview of a building under the mouse,
## green where it can go and red where it can't. "left_click" places it,
## "cancel_placement" cancels (unless disabled, like for the first base).
## Crafted buildings are placed as construction sites for builders to finish;
## the base is placed complete.

signal placement_finished(type: String, cell: Vector2i)
## A tile picked in tile mode (start_tile), e.g. the water the bucket is sent to.
signal tile_picked(cell: Vector2i)
## Paint mode (start_paint): the press that starts a stroke, then every tile
## the mouse drags over. The owner decides what painting a tile means.
signal paint_started(cell: Vector2i)
signal paint_moved(cell: Vector2i)
signal placement_cancelled

@export var level: LevelGenerator
@export var valid_color := Color(0.6, 1.0, 0.6, 0.7)
@export var invalid_color := Color(1.0, 0.4, 0.4, 0.7)

var _type := ""
## Tile mode: no building, just a tile the player points at (see start_tile).
var _tile_mode := false
## Paint mode: like tile mode, but it stays active and drags (see start_paint).
var _paint_mode := false
var _painting := false
var _tile_ok: Callable
var _cancellable := true
var _construct := false
var _cell := Vector2i.ZERO
var _ghost := Sprite2D.new()


func _ready() -> void:
	_ghost.z_index = 100 # draw above the map and buildings
	_ghost.hide()
	add_child(_ghost)
	set_process(false)


## Tile mode: the same ghost and the same cancelling, but the player is
## picking a TILE, not placing a building. `ok` decides which tiles are green.
## Used to send the bucket to water.
func start_tile(icon_path: String, ok: Callable) -> void:
	_type = ""
	_tile_mode = true
	_tile_ok = ok
	_cancellable = true
	_ghost.texture = Art.texture(icon_path)
	_ghost.show()
	set_process(true)


## Paint mode: the ghost stays in hand and the player drags over tiles,
## stroke after stroke, until they cancel. Used to mark lava with the bucket.
func start_paint(icon_path: String, ok: Callable) -> void:
	start_tile(icon_path, ok)
	_paint_mode = true


func start(type: String, cancellable := true, construct := false) -> void:
	var data := level.get_building_data(type)
	if data == null:
		push_error("BuildPlacer: no BuildingData with id '%s'." % type)
		return
	_type = type
	_tile_mode = false
	_paint_mode = false
	_painting = false
	_cancellable = cancellable
	_construct = construct
	_ghost.texture = data.get_texture()
	_ghost.show()
	set_process(true)


func stop() -> void:
	_type = ""
	_tile_mode = false
	_paint_mode = false
	_painting = false
	_ghost.hide()
	set_process(false)


func is_active() -> bool:
	return _type != "" or _tile_mode or _paint_mode


func _process(_delta: float) -> void:
	_cell = level.world_to_cell(get_global_mouse_position())
	if _tile_mode or _paint_mode:
		_ghost.global_position = level.cell_to_world(_cell)
		_ghost.modulate = valid_color if _tile_ok.call(_cell) else invalid_color
		return
	var data := level.get_building_data(_type)
	_ghost.global_position = level.cell_to_world(_cell) + level.get_footprint_offset(data.size)
	_ghost.modulate = valid_color if level.can_place(_type, _cell) else invalid_color


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if _paint_mode:
		_paint_input(event)
		return
	# Actions rather than raw mouse buttons, so both can be rebound.
	if event.is_action_pressed("left_click"):
		# From the mouse, not the cached cell: _process runs once per frame, so
		# a click in the same frame as a fast move would land a tile behind.
		_cell = level.world_to_cell(get_global_mouse_position())
		if _tile_mode:
			if _tile_ok.call(_cell):
				var picked := _cell
				stop()
				tile_picked.emit(picked)
			get_viewport().set_input_as_handled()
			return
		var type := _type
		var cell := _cell
		var placed := level.place_construction(type, cell) != BuildingStore.NONE \
			if _construct else level.place_building(type, cell)
		if placed:
			stop()
			placement_finished.emit(type, cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel_placement") and _cancellable:
		stop()
		placement_cancelled.emit()
		get_viewport().set_input_as_handled()


## Paint mode input: press starts a stroke, motion continues it, release ends
## it, and the ghost stays in hand for the next one until the player cancels.
func _paint_input(event: InputEvent) -> void:
	_cell = level.world_to_cell(get_global_mouse_position())
	if event.is_action_pressed("left_click"):
		_painting = true
		paint_started.emit(_cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("left_click"):
		_painting = false
		get_viewport().set_input_as_handled()
	elif _painting and event is InputEventMouseMotion:
		paint_moved.emit(_cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel_placement"):
		stop()
		placement_cancelled.emit()
		get_viewport().set_input_as_handled()
