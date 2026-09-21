extends Camera2D


var can_move: bool
var current_mouse_pos
var last_mouse_pos
## Starts at zero, not null: it used to stay null until the mouse had moved,
## so starting a pan before that crashed on "Nil * float".
var mouse_direction := Vector2.ZERO
var zoom_changed

@export var zoom_speed : float
@export var min_zoom: float
@export var max_zoom: float
@export var camera_speed: float


# Called when the node enters the scene tree for the first time.
func _ready():
	can_move = false
	last_mouse_pos = null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	
	# Get mouse direction
	current_mouse_pos = get_global_mouse_position()
	
	# "!= null", not a truth test: Vector2(0, 0) counts as false, so the old check
	# skipped this whenever the mouse sat at world origin.
	if last_mouse_pos != null:
		mouse_direction = last_mouse_pos - current_mouse_pos

	# Released anywhere -- even over a menu -- so a drag can never stay stuck on.
	if can_move and not Input.is_action_pressed("move_camera"):
		can_move = false

	# get last mouse position
	last_mouse_pos = get_global_mouse_position()
	
	if can_move:
		position += mouse_direction + mouse_direction * camera_speed

# Starting a pan and zooming are events, not polled input. Polling
# (Input.is_action_just_pressed) sees every scroll, including ones a menu has
# already used, which made the camera zoom while scrolling the options list.
# _unhandled_input only receives what the UI did not consume.
func _unhandled_input(event: InputEvent) -> void:
	# Never react while the pointer is over any UI element, whether or not that
	# element remembered to consume the event. Correct by construction for
	# panels added later.
	if get_viewport().gui_get_hovered_control() != null:
		return
	if event.is_action_pressed("move_camera"):
		can_move = true
	elif event.is_action_pressed("zoom_in"):
		set_zoom_level(zoom.x + zoom_speed)
	elif event.is_action_pressed("zoom_out"):
		set_zoom_level(zoom.x - zoom_speed)


func set_zoom_level(value: float):
	value = clamp(value, min_zoom, max_zoom)
	zoom = Vector2(value, value)
