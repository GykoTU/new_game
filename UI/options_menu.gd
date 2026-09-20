extends CanvasLayer

@onready var volume_slider = $PanelContainer/VBoxContainer/VolumeSlider
@onready var fullscreen_check = $PanelContainer/VBoxContainer/FullscreenCheck

func _ready():
	visible = false
	volume_slider.value = Settings.volume
	fullscreen_check.button_pressed = Settings.fullscreen

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle():
	visible = not visible
	get_tree().paused = visible

func _on_volume_slider_value_changed(value):
	Settings.volume = value
	Settings.apply()
	Settings.save()

func _on_fullscreen_check_toggled(on):
	Settings.fullscreen = on
	Settings.apply()
	Settings.save()

func _on_resume_button_pressed():
	toggle()

func _on_quit_to_title_button_pressed():
	get_tree().paused = false
	EventBus.on_quit_button_pressed.emit()
	get_tree().change_scene_to_file("res://game/title_screen.tscn")
