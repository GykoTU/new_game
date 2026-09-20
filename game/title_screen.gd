extends Control

@onready var continue_button = $VBoxContainer/ContinueButton

func _ready():
	continue_button.disabled = not SaveManager.has_save()

func _on_new_game_button_pressed():
	SaveManager.reset()
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_continue_button_pressed():
	SaveManager.load_game()
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
