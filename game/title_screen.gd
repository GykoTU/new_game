extends Control

const RELIC_ICON := "res://assets/ui/relic.png"

@onready var continue_button = $VBoxContainer/ContinueButton

func _ready():
	continue_button.disabled = not SaveManager.has_run()
	_add_relic_count()

## Relics are kept across runs (Stage 3b; spent in Stage 8). Shown only once
## the player has found some, so a first-time player isn't shown a zero.
func _add_relic_count() -> void:
	var relics := int(SaveManager.profile.get("relics", 0))
	if relics <= 0:
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = Art.texture(RELIC_ICON)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var label := Label.new()
	label.text = "%d relic%s" % [relics, "" if relics == 1 else "s"]
	row.add_child(icon)
	row.add_child(label)
	$VBoxContainer.add_child(row)

func _on_new_game_button_pressed():
	# Starting fresh discards the previous run. The profile is untouched.
	SaveManager.delete_run()
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_continue_button_pressed():
	# main.gd loads the run itself; nothing to do here but switch scenes.
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
