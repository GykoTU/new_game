extends ColorRect

func _gui_input(event: InputEvent):
	if event.is_action_pressed("left_click"):
		get_parent().panel_clicked()

func insert_building():
	pass
