extends Node2D

const LEVEL_SCENE := preload("res://Level/level_generator.tscn")
const SAVE_PATH := "user://savegame.dat"

var level: Node2D

var camera: Node2D
var options_menu: CanvasLayer
var buildings_ui: CanvasLayer

# Called when the node enters the scene tree for the first time.
func _ready():
	
	# Connect to EventBus
	EventBus.on_quit_button_pressed.connect(save_level)
	
	# load scenes
	var camera_scene = load("res://game/camera.tscn")
	var options_menu_scene = load("res://UI/options_menu.tscn")
	var builduings_ui_scene = load("res://UI/buildings_ui.tscn")
	
	# instantiate scenes
	camera = camera_scene.instantiate()
	level = LEVEL_SCENE.instantiate()
	options_menu = options_menu_scene.instantiate()
	buildings_ui = builduings_ui_scene.instantiate()
	
	# Get map data from save
	var save := SaveManager.load_game()
	# only generate level when save is empty
	level.generate_on_ready = save.is_empty()
	
	# if save exists load the save
	if not save.is_empty():
		level.load_save_data(save["level"])
	
	# add to main node
	add_child(camera)
	add_child(level)
	add_child(options_menu)
	add_child(buildings_ui)
	
	# Connect other events to functions to wait for level generation
	level.level_generated.connect(_on_level_generated)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func _on_level_generated() -> void:
	pass
	
func save_level():
	SaveManager.save_game(level)
