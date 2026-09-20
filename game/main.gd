extends Node2D
## Run root. Owns the simulation update order and drives the clock.
##
## Systems are stepped by explicit calls from _simulate(), not by connecting to
## a signal. Signal handlers run in connection order, which is invisible in the
## source and easy to reorder by accident; simulation order genuinely matters
## (enemies move, then projectiles step, then hits resolve, then damage applies)
## so it is written down in one readable place instead.

## Pause reason pushed while the options menu is open.
const PAUSE_OPTIONS := "options_menu"

@onready var clock: GameClock = $GameClock
@onready var level: LevelGenerator = $Level
@onready var build_placer: BuildPlacer = $BuildPlacer
@onready var options_menu: CanvasLayer = $UI/OptionsMenu


func _ready() -> void:
	EventBus.on_quit_button_pressed.connect(save_run)
	level.level_generated.connect(_on_level_generated)
	build_placer.placement_finished.connect(_on_placement_finished)
	options_menu.visibility_changed.connect(_on_options_visibility_changed)

	# The level no longer generates itself on _ready: children are readied
	# before their parent, so it would have built a map before this node could
	# decide that a save should be loaded instead. Generation is explicit now.
	# A save this build cannot read is treated as no save at all, rather than
	# leaving the player in a half-built world.
	var save := SaveManager.load_run()
	var loaded := false
	if save.has("level"):
		loaded = level.load_save_data(save["level"])
	if loaded:
		if save.has("clock"):
			clock.load_save_data(save["clock"])
	else:
		level.generate()
		_count_run_started()
		# New game: the player picks where the base goes. It can't be cancelled.
		build_placer.start("base", false)


func _process(delta: float) -> void:
	var ticks := clock.advance(delta)
	for i in ticks:
		_simulate(GameClock.TICK_DELTA)


## The single place simulation order is decided. Every system that advances the
## world is stepped from here, in this order, with a fixed dt.
## Systems land here as they are built (Stage 1 onward in TODO.md).
func _simulate(_dt: float) -> void:
	pass


# --- Callbacks ----------------------------------------------------------------

## Runs after both a new level is generated and a save is loaded.
func _on_level_generated() -> void:
	pass


func _on_placement_finished(type: String, cell: Vector2i) -> void:
	if type == "base":
		print("Base placed at ", cell)
		# Start the actual game here: spawn workers, enable the UI, etc.


## The options menu freezes the world through the clock rather than through
## get_tree().paused, so menu and UI animation keep running while time stops.
## Using a named reason means closing the menu cannot resume a run the player
## had paused themselves.
func _on_options_visibility_changed() -> void:
	if options_menu.visible:
		clock.push_pause(PAUSE_OPTIONS)
	else:
		clock.pop_pause(PAUSE_OPTIONS)


## Assembles everything a run needs to resume. Systems own their own save
## shape; this function only decides which of them are in a run save.
func save_run() -> void:
	var ok := SaveManager.save_run({
		"level": level.get_save_data(),
		"clock": clock.get_save_data(),
		# resources, progression and the day/night director join this as they
		# are built. SaveManager neither knows nor cares what these keys mean.
	})
	if not ok:
		push_error("Main: the run could not be saved.")


func _count_run_started() -> void:
	SaveManager.profile["runs_started"] = int(SaveManager.profile.get("runs_started", 0)) + 1
	SaveManager.save_profile()


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_pause"):
		clock.toggle_player_pause()
		get_viewport().set_input_as_handled()
		return

	for i in GameClock.SPEED_STEPS.size():
		if event.is_action_pressed("game_speed_%d" % (i + 1)):
			clock.speed = GameClock.SPEED_STEPS[i]
			get_viewport().set_input_as_handled()
			return

	_debug_input(event)


## Ctrl+N generates a brand new level. Debug builds only.
func _debug_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N and event.ctrl_pressed:
			level.level_seed = 0
			level.generate()
			build_placer.start("base", false)
			print("New level generated, place your base")
