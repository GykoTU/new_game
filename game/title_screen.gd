extends Control

const RELIC_ICON := "res://assets/ui/relic.png"
const META_TREE := preload("res://data/meta/tree.tres")

@onready var continue_button = $VBoxContainer/ContinueButton

var _relic_row: HBoxContainer
var _tree_button: Button
var _tree_screen


func _ready():
	continue_button.disabled = not SaveManager.has_run()
	# Stage 8: the relic tree, between runs.
	_tree_button = Button.new()
	_tree_button.name = "RelicTreeButton"
	_tree_button.text = "Relic Tree"
	_tree_button.pressed.connect(open_relic_tree)
	$VBoxContainer.add_child(_tree_button)
	$VBoxContainer.move_child(_tree_button, continue_button.get_index() + 1)
	_tree_screen = preload("res://UI/meta_tree_screen.gd").new()
	_tree_screen.name = "RelicTree"
	_tree_screen.visible = false
	add_child(_tree_screen)
	_tree_screen.closed.connect(_on_tree_closed)
	_add_relic_count()


func open_relic_tree() -> void:
	$VBoxContainer.visible = false
	_tree_screen.open(META_TREE)


func _on_tree_closed() -> void:
	$VBoxContainer.visible = true
	_add_relic_count()


## Relics are kept across runs (Stage 3b; spent on the relic tree since
## Stage 8). Shown only once the player has some, so a first-time player
## isn't shown a zero.
func _add_relic_count() -> void:
	if _relic_row != null:
		_relic_row.queue_free()
		_relic_row = null
	var relics := int(SaveManager.profile.get("relics", 0))
	if relics <= 0:
		return
	var row := HBoxContainer.new()
	_relic_row = row
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
