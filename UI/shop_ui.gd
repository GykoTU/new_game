extends CanvasLayer

# Called when the node enters the scene tree for the first time.
func _ready():
	visible = false


func _input(event: InputEvent):
	if event.is_action_pressed("shop"):
		visible = not visible
