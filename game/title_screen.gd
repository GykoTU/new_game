extends Control

@onready var continue_button = $VBoxContainer/ContinueButton

func _ready():
	continue_button.disabled = not SaveManager.has_run()

func _on_new_game_button_pressed():
	# Starting fresh discards the previous run. The profile is untouched.
	SaveManager.delete_run()
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_continue_button_pressed():
	# main.gd loads the run itself; nothing to do here but switch scenes.
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
