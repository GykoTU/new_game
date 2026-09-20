extends Node2D

const LEVEL_SCENE := preload("res://Level/level_generator.tscn")

# Utility Scenes
var level: LevelGenerator
var build_placer: BuildPlacer
var camera: Node2D

# UI Scenes
var options_menu: CanvasLayer
var buildings_ui: CanvasLayer
var workers_ui: CanvasLayer
var shop_ui: CanvasLayer

# Called when the node enters the scene tree for the first time.
func _ready():
	
	# Connect to EventBus
	EventBus.on_quit_button_pressed.connect(save_level)
	
	# load scenes
	var camera_scene = load("res://game/camera.tscn")
	var options_menu_scene = load("res://UI/options_menu.tscn")
	var shop_ui_scene = load("res://UI/shop_ui.tscn")
	var buildings_ui_scene = load("res://UI/building_ui.tscn")
	var workers_ui_scene = load("res://UI/worker_ui.tscn")
	
	
	# instantiate scenes
	camera = camera_scene.instantiate()
	level = LEVEL_SCENE.instantiate() as LevelGenerator
	options_menu = options_menu_scene.instantiate()
	shop_ui = shop_ui_scene.instantiate()
	buildings_ui = buildings_ui_scene.instantiate()
	workers_ui = workers_ui_scene.instantiate()
	
	# the build placer is created in code, it needs to know the level
	build_placer = BuildPlacer.new()
	build_placer.level = level
	build_placer.placement_finished.connect(_on_placement_finished)
	
	# Get map data from save
	var save := SaveManager.load_game()
	# only generate level when save is empty
	level.generate_on_ready = save.is_empty()
	
	# Connect BEFORE add_child: a new level is generated the moment it's added,
	# so connecting afterwards would miss the signal.
	level.level_generated.connect(_on_level_generated)
	
	# add to main node
	add_child(camera)
	add_child(level) # a new level generates here
	add_child(build_placer)
	add_child(options_menu)
	add_child(shop_ui)
	add_child(buildings_ui)
	add_child(workers_ui)
	
	if save.is_empty():
		# New game: the player picks where the base goes. It can't be cancelled.
		build_placer.start("base", false)
	else:
		# if save exists load the save (after add_child, so the level is in the tree)
		level.load_save_data(save["level"])
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

# Runs after both a new level is generated and a save is loaded.
func _on_level_generated() -> void:
	pass

func _on_placement_finished(type: String, cell: Vector2i) -> void:
	if type == "base":
		print("Base placed at ", cell)
		# Start the actual game here: spawn workers, enable the UI, etc.

func save_level():
	SaveManager.save_game(level)

# Debug only: Ctrl+N generates a brand new level. Doesn't exist in exported builds.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N and event.ctrl_pressed:
			level.level_seed = 0
			level.generate()
			build_placer.start("base", false)
			print("New level generated, place your base")
