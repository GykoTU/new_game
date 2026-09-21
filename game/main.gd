extends Node2D
## Run root. Owns the run's systems, the simulation update order, and the clock.
##
## Systems are stepped by explicit calls from _simulate(), not by connecting to
## a signal. Signal handlers run in connection order, which is invisible in the
## source and easy to reorder by accident; simulation order genuinely matters
## (enemies move, then projectiles step, then hits resolve, then damage applies)
## so it is written down in one readable place instead.

## Pause reason pushed while the options menu is open.
const PAUSE_OPTIONS := "options_menu"

## Stat blocks for unit types, one per TYPE (D7). Stage 2 moves these into the
## unit system; they exist now so upgrades have something to modify and the
## stat overlay can show it. "stats" is what the overlay lists.
const UNIT_TYPES := {
	"miner": {
		"tags": ["unit", "worker", "miner"],
		"stats": [Stats.Id.MOVE_SPEED, Stats.Id.GATHER_RATE, Stats.Id.CARRY_CAPACITY],
	},
	"builder": {
		"tags": ["unit", "worker", "builder"],
		"stats": [Stats.Id.MOVE_SPEED, Stats.Id.BUILD_SPEED, Stats.Id.REPAIR_RATE],
	},
}

## What a new run starts with. Tunable in the inspector on the Main node.
@export var starting_resources: Dictionary[ResourceKind.Id, int] = {ResourceKind.Id.GOLD: 100}
@export var shop_catalogue: ShopCatalogue = preload("res://data/shop/catalogue.tres")
## Debug builds only: how much of every resource the grant shortcut adds.
@export var debug_grant_amount := 100

@onready var clock: GameClock = $GameClock
@onready var level: LevelGenerator = $Level
@onready var build_placer: BuildPlacer = $BuildPlacer
@onready var options_menu: CanvasLayer = $UI/OptionsMenu
@onready var resource_bar: CanvasLayer = $UI/ResourceBar
@onready var shop_ui: CanvasLayer = $UI/ShopUI
@onready var worker_ui = $UI/WorkerUI/WorkerUI
@onready var stat_overlay: CanvasLayer = $UI/StatOverlay

## Every active stat modifier in this run: augments, upgrades, buffs, sales.
var modifiers := ModifierSet.new()
var economy := Economy.new()
var roster := WorkerRoster.new()
var shop: Shop
## UNIT_TYPES name -> StatBlock
var type_blocks := {}


func _ready() -> void:
	shop = Shop.new(shop_catalogue, economy, roster, modifiers)
	for type in UNIT_TYPES:
		type_blocks[type] = StatBlock.new(modifiers, PackedStringArray(UNIT_TYPES[type]["tags"]))

	EventBus.on_quit_button_pressed.connect(save_run)
	economy.changed.connect(func(kind, amount): EventBus.resource_changed.emit(kind, amount))
	roster.changed.connect(func(kind, count): EventBus.roster_changed.emit(kind, count))
	shop.purchased.connect(func(item, n): EventBus.shop_purchased.emit(item.id, n))
	level.level_generated.connect(_on_level_generated)
	build_placer.placement_finished.connect(_on_placement_finished)
	options_menu.visibility_changed.connect(_on_options_visibility_changed)

	resource_bar.bind(economy)
	shop_ui.bind(shop, economy, modifiers)
	worker_ui.bind(roster)
	stat_overlay.bind(self)

	# The level does not generate itself on _ready: children are readied before
	# their parent, so it would build a map before this node could decide that
	# a save should be loaded instead. A save this build cannot read is treated
	# as no save at all, rather than leaving the player in a half-built world.
	var save := SaveManager.load_run()
	var loaded := save.has("level") and _load_run(save)
	if not loaded:
		_start_new_run()

	Art.report_missing(_referenced_art())


func _process(delta: float) -> void:
	var ticks := clock.advance(delta)
	for i in ticks:
		_simulate(GameClock.TICK_DELTA)


## The single place simulation order is decided. Every system that advances the
## world is stepped from here, in this order, with a fixed dt.
## Systems land here as they are built (Stage 2 onward in TODO.md).
func _simulate(_dt: float) -> void:
	pass


# --- Run lifecycle ------------------------------------------------------------

func _start_new_run() -> void:
	modifiers.clear()
	shop.reset()
	roster.clear()
	economy.set_all(starting_resources)
	level.generate()
	_count_run_started()
	# New game: the player picks where the base goes. It can't be cancelled.
	build_placer.start("base", false)


## Order matters. Shop purchases load before modifiers, because rebuilding an
## upgrade's modifiers reads its level from the purchase count. Modifiers load
## before the level: they are cheap to reject, so a run with a missing upgrade
## is refused before the map is built. On any failure the caller starts a new
## run, which resets everything this may have partly loaded.
##
## Keys missing from older saves are additive: a run saved before the economy
## existed gets the starting resources, and so on. RUN_VERSION did not move.
func _load_run(save: Dictionary) -> bool:
	if save.has("economy"):
		if not economy.load_save_data(save["economy"]):
			return false
	else:
		economy.set_all(starting_resources)
	if save.has("roster") and not roster.load_save_data(save["roster"]):
		return false
	if save.has("shop") and not shop.load_save_data(save["shop"]):
		return false
	if not modifiers.load_save_data(save.get("modifiers", {}), _resolve_modifier_source):
		return false
	if not level.load_save_data(save["level"]):
		return false
	if save.has("clock"):
		clock.load_save_data(save["clock"])
	return true


## Assembles everything a run needs to resume. Systems own their own save
## shape; this function only decides which of them are in a run save.
func save_run() -> void:
	var ok := SaveManager.save_run({
		"level": level.get_save_data(),
		"clock": clock.get_save_data(),
		"economy": economy.get_save_data(),
		"roster": roster.get_save_data(),
		"shop": shop.get_save_data(),
		"modifiers": modifiers.get_save_data(),
		# progression and the day/night director join this as they are built.
		# SaveManager neither knows nor cares what these keys mean.
	})
	if not ok:
		push_error("Main: the run could not be saved.")


## Rebuilds a modifier source from current game data when a run is loaded, so a
## rebalanced upgrade reaches runs already in progress. Returns
## Array[StatModifier], or null if the source no longer exists.
## Augments (Stage 7) will be looked up here too.
func _resolve_modifier_source(source: String) -> Variant:
	return shop.resolve_source(source)


func _count_run_started() -> void:
	SaveManager.profile["runs_started"] = int(SaveManager.profile.get("runs_started", 0)) + 1
	SaveManager.save_profile()


## Every sprite path the UI references, for the missing-art report.
func _referenced_art() -> Array:
	var paths := []
	for kind in ResourceKind.count():
		paths.append(ResourceKind.icon_path_of(kind))
	for kind in WorkerRoster.Kind.COUNT:
		paths.append(WorkerRoster.icon_path_of(kind))
	for item in shop.items():
		if item != null:
			paths.append(item.icon_path)
	paths.append("res://assets/ui/sale_tag.png")
	return paths


# --- Callbacks ----------------------------------------------------------------

## Runs after both a new level is generated and a save is loaded.
func _on_level_generated() -> void:
	pass


func _on_placement_finished(type: String, cell: Vector2i) -> void:
	if type == "base":
		print("Base placed at ", cell)


## The options menu freezes the world through the clock rather than through
## get_tree().paused, so menu and UI animation keep running while time stops.
## Using a named reason means closing the menu cannot resume a run the player
## had paused themselves.
func _on_options_visibility_changed() -> void:
	if options_menu.visible:
		clock.push_pause(PAUSE_OPTIONS)
	else:
		clock.pop_pause(PAUSE_OPTIONS)


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


## Dev shortcuts. The build check comes FIRST: in release builds these actions
## have been erased from the InputMap, and asking about an action that does not
## exist is an error, not a false.
func _debug_input(event: InputEvent) -> void:
	if not Keybinds.dev_tools_enabled():
		return
	if event.is_action_pressed("debug_new_level"):
		_start_new_run()
		print("Debug: new run started, place your base")
	elif event.is_action_pressed("debug_grant_resources"):
		for kind in ResourceKind.count():
			economy.add(kind, debug_grant_amount)
	elif event.is_action_pressed("debug_stat_overlay"):
		stat_overlay.toggle()
	else:
		return
	get_viewport().set_input_as_handled()
