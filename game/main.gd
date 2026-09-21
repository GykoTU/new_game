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

## Stat blocks for unit types, one per TYPE (D7). Keys match WorkerRoster's
## save keys. "base" overrides registry defaults; "stats" is what the F3
## overlay lists. All numbers are placeholders for balancing.
const UNIT_TYPES := {
	"miner": {
		"tags": ["unit", "worker", "miner"],
		"base": {Stats.Id.MOVE_SPEED: 48.0, Stats.Id.GATHER_RATE: 0.25},
		"stats": [Stats.Id.MOVE_SPEED, Stats.Id.GATHER_RATE],
	},
	"builder": {
		"tags": ["unit", "worker", "builder"],
		"base": {Stats.Id.MOVE_SPEED: 56.0},
		"stats": [Stats.Id.MOVE_SPEED, Stats.Id.BUILD_SPEED, Stats.Id.REPAIR_RATE],
	},
	"carrier": {
		"tags": ["unit", "worker", "carrier"],
		"base": {Stats.Id.MOVE_SPEED: 64.0, Stats.Id.CARRY_CAPACITY: 10.0},
		"stats": [Stats.Id.MOVE_SPEED, Stats.Id.CARRY_CAPACITY],
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
@onready var toast: CanvasLayer = $UI/Toast
@onready var unit_renderer: UnitRenderer = $UnitRenderer

## Every active stat modifier in this run: augments, upgrades, buffs, sales.
var modifiers := ModifierSet.new()
var economy := Economy.new()
var roster := WorkerRoster.new()
var shop: Shop
var units := UnitSystem.new()
## UNIT_TYPES name -> StatBlock
var type_blocks := {}
## True while the player is choosing a mine to send a miner to.
var _dispatching := false


func _ready() -> void:
	shop = Shop.new(shop_catalogue, economy, roster, modifiers)
	for type in UNIT_TYPES:
		type_blocks[type] = StatBlock.new(modifiers, PackedStringArray(UNIT_TYPES[type]["tags"]),
			UNIT_TYPES[type].get("base", {}))
	# Before any level exists: the unit system listens for level_generated to
	# build its pathing grid.
	units.setup(level, economy, modifiers, type_blocks)
	roster.attach(units)
	shop.purchase_check = _purchase_check

	EventBus.on_quit_button_pressed.connect(save_run)
	economy.changed.connect(func(kind, amount): EventBus.resource_changed.emit(kind, amount))
	roster.changed.connect(func(kind, count): EventBus.roster_changed.emit(kind, count))
	shop.purchased.connect(func(item, n): EventBus.shop_purchased.emit(item.id, n))
	level.level_generated.connect(_on_level_generated)
	build_placer.placement_finished.connect(_on_placement_finished)
	options_menu.visibility_changed.connect(_on_options_visibility_changed)

	resource_bar.bind(economy)
	shop_ui.bind(shop, economy, modifiers)
	worker_ui.bind(units)
	worker_ui.slot_pressed.connect(_on_worker_slot_pressed)
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
	# Drawn once per frame, after the simulation, never from inside it.
	unit_renderer.draw_units(units.store, clock.tick_count)
	unit_renderer.draw_drops(units.drops, clock.tick_count)


## The single place simulation order is decided. Every system that advances the
## world is stepped from here, in this order, with a fixed dt.
##   1. units -- move, decide, build, gather, haul (UnitSystem.step)
## Systems land here as they are built, in the order they must run.
func _simulate(dt: float) -> void:
	units.tick = clock.tick_count
	units.step(dt)


# --- Run lifecycle ------------------------------------------------------------

func _start_new_run() -> void:
	_end_dispatch()
	units.clear()
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
	# After the level: units refer to buildings by cell.
	if not units.load_save_data(save.get("units", {})):
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
		"units": units.get_save_data(),
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
	for data in level.placeable_buildings:
		if data != null and data.texture == null:
			paths.append(data.texture_path)
	for kind in UnitRenderer.LOOKS:
		for anim in UnitRenderer.LOOKS[kind]:
			paths.append(UnitRenderer.LOOKS[kind][anim])
	return paths


## Rules the shop checks beyond price. Workers need a base to arrive at, and
## builders and carriers need a free bed.
func _purchase_check(item: ShopItemData) -> String:
	if item.kind != ShopItemData.Kind.WORKER:
		return ""
	if level.base_cell == LevelGenerator.INVALID_CELL:
		return "Place your base first."
	if item.worker_kind != WorkerRoster.Kind.MINER and units.free_beds(item.worker_kind) <= 0:
		return "Needs a free bed: craft another %s house." % WorkerRoster.display_of(item.worker_kind).to_lower()
	return ""


# --- Sending miners -----------------------------------------------------------

func _on_worker_slot_pressed(kind: int) -> void:
	if kind != WorkerRoster.Kind.MINER:
		return   # builders and carriers work on their own (assignable tasks: later)
	if _dispatching:
		_end_dispatch()
		return
	if level.base_cell == LevelGenerator.INVALID_CELL:
		toast.show_message("Place your base first.")
		return
	if units.count(kind) == 0:
		toast.show_message("You have no miners. Buy one in the shop.")
		return
	_dispatching = true
	worker_ui.set_active(kind)
	toast.show_message("Click a mine to send a miner.  Shift: send more.  %s: stop." \
		% Keybinds.describe_action("cancel_placement"), 4.0)


func _end_dispatch() -> void:
	_dispatching = false
	if worker_ui != null:
		worker_ui.set_active(-1)


## Left click while dispatching. Shift keeps the mode open to send more; any
## refusal closes it and says why.
func _dispatch_click(shift: bool) -> void:
	var cell := level.world_to_cell(get_global_mouse_position())
	var mine := level.grid.get_occupant(cell) if level.grid.in_bounds(cell) else WorldGrid.NO_OCCUPANT
	var result := "Click a mine." if mine == WorldGrid.NO_OCCUPANT else units.send_miner(mine)
	if result != "":
		toast.show_message(result)
		_end_dispatch()
	elif not shift:
		toast.hide_message()
		_end_dispatch()


# --- Callbacks ----------------------------------------------------------------

## Runs after both a new level is generated and a save is loaded.
func _on_level_generated() -> void:
	pass


func _on_placement_finished(type: String, _cell: Vector2i) -> void:
	if type == "base":
		units.start_run_kit()


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
	if _dispatching:
		if event.is_action_pressed("left_click"):
			_dispatch_click(event is InputEventWithModifiers and event.shift_pressed)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("cancel_placement"):
			_end_dispatch()
			toast.hide_message()
			get_viewport().set_input_as_handled()
			return

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
