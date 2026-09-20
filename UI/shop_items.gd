extends GridContainer

@onready var template: Panel = $Panel

@export var row_amount: int = 3
@export var panel_amount: int = 4   # panels per row
@export var panel_size: int = 64
@export var spacing: int = 4

func _ready():
	columns = panel_amount

	# Spacing between slots (GridContainer uses h_separation / v_separation)
	add_theme_constant_override("h_separation", spacing)
	add_theme_constant_override("v_separation", spacing)

	# Set up the template slot
	template.custom_minimum_size = Vector2(panel_size, panel_size)
	template.self_modulate = Color(0, 0, 0, 0.9)

	# The template counts as the first slot, so add one fewer
	for i in row_amount * panel_amount - 1:
		add_child(template.duplicate())
