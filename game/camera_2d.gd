extends Camera2D


var can_move: bool
var current_mouse_pos
var last_mouse_pos
var mouse_direction
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
	
	if last_mouse_pos:
		mouse_direction = last_mouse_pos - current_mouse_pos
	
	if Input.is_action_just_pressed("move_camera"):
		can_move = true
		
	if Input.is_action_just_released("move_camera"):
		can_move = false
	
	if Input.is_action_just_pressed("zoom_in"):
		set_zoom_level(zoom.x + zoom_speed)

	if Input.is_action_just_pressed("zoom_out"):
		set_zoom_level(zoom.x - zoom_speed)
	
	# get last mouse position
	last_mouse_pos = get_global_mouse_position()
	
	if can_move:
		position += mouse_direction + mouse_direction * camera_speed

func set_zoom_level(value: float):
	value = clamp(value, min_zoom, max_zoom)
	zoom = Vector2(value, value)
