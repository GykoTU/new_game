extends HBoxContainer

@onready var template = $Panel
@export var panel_amount: int = 5
@export var panel_size: int = 64

# Called when the node enters the scene tree for the first time.
func _ready():
	
	# Set up the template slot
	template.custom_minimum_size = Vector2(panel_size, panel_size)
	template.self_modulate = Color(0, 0, 0, 0.9)
	
	# Add panels to hbox
	for panel in panel_amount - 1:
		add_child(template.duplicate())
