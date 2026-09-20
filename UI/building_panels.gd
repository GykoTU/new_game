extends HBoxContainer

@export var num_panels: int
@export var panel_size: int
@onready var panel = $ColorRect

# Called when the node enters the scene tree for the first time.
func _ready():
	
	# Setup size
	size = Vector2(panel_size, panel_size)
	
	# Make set amount of panels
	for i in num_panels:
		size.x += panel_size
		@warning_ignore("integer_division")
		position.x -= round(panel_size / 2)
		var copy = panel.duplicate()
		add_child(copy)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass
	
func panel_clicked():
	print("clicked panel")
