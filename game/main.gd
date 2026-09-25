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
## Pause reason pushed when the base falls. Never popped: the run is over, and
## the only way on is back to the title screen.
const PAUSE_GAME_OVER := "game_over"

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
## Debug builds only: holding the grant shortcut repeats it after this delay,
## this many times per second.
@export var debug_grant_repeat_delay := 0.35
@export var debug_grant_repeats_per_second := 10.0
## Debug builds only: while held, each grant is this many times the previous
## one (for stress tests), up to debug_grant_max per grant.
@export var debug_grant_growth := 1.25
@export var debug_grant_max := 1_000_000_000

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
@onready var building_ui = $UI/BuildingUI/BuildingUI

## Every active stat modifier in this run: augments, upgrades, buffs, sales.
var modifiers := ModifierSet.new()
var economy := Economy.new()
var roster := WorkerRoster.new()
var shop: Shop
var units := UnitSystem.new()
## Blueprints (and later items) this run knows.
var unlocks := Unlocks.new()
## Crafted buildings waiting in the building bar.
var inventory := BuildingInventory.new()
## Marked trees, stumps and regrowth.
var forest := Forest.new()
## Lava marked for cobble, and the bucket.
var lava := LavaWorks.new()
## The day counter and the day/night cycle.
var director := RunDirector.new()
## Owned items (the bucket), top left. Created in _ready.
var item_bar
## Day number and phase progress, under the resource bar. Created in _ready.
var day_bar
## Shown when the base falls. Created in _ready.
var run_summary
## Tints the world (not the UI) with the director's light. Created in _ready.
var _tint: CanvasModulate
## The faint halo under buildings at night. Created in _ready.
var building_glow: BuildingGlow
## True from the moment the base falls, so the run is neither saved nor ended twice.
var _run_over := false
## UNIT_TYPES name -> StatBlock
var type_blocks := {}
## True while the player is choosing a mine to send a miner to.
var _dispatching := false
## Seconds the grant shortcut has been held, and grants given in this hold
## (debug builds only).
var _grant_held := 0.0
var _grants_this_hold := 0
## Painting lava marks with the water bucket in hand (see _on_paint_started).
var _paint_on := true
var _paint_last := Vector2i(-1, -1)


func _ready() -> void:
	shop = Shop.new(shop_catalogue, economy, roster, modifiers)
	for type in UNIT_TYPES:
		type_blocks[type] = StatBlock.new(modifiers, PackedStringArray(UNIT_TYPES[type]["tags"]),
			UNIT_TYPES[type].get("base", {}))
	# Before any level exists: the unit system listens for level_generated to
	# build its pathing grid.
	units.setup(level, economy, modifiers, type_blocks)
	roster.attach(units)
	forest.setup(level)
	units.forest = forest
	lava.setup(level, unlocks)
	units.lava = lava
	var marks := TileMarks.new()
	marks.name = "LavaMarks"
	level.add_sibling(marks)   # drawn over the ground, under the units
	marks.bind(lava, level)
	item_bar = preload("res://UI/item_bar.gd").new()
	item_bar.name = "ItemBar"
	_add_ui(item_bar)
	item_bar.bind(unlocks)
	item_bar.item_pressed.connect(_on_item_pressed)
	day_bar = preload("res://UI/day_bar.gd").new()
	day_bar.name = "DayBar"
	_add_ui(day_bar)
	day_bar.bind(director)
	run_summary = preload("res://UI/run_summary.gd").new()
	run_summary.name = "RunSummary"
	_add_ui(run_summary)
	run_summary.return_pressed.connect(_return_to_title)
	# A CanvasModulate tints its own canvas layer, so as a child of Main it
	# colours the world (level, marks, units) and leaves every UI layer alone.
	_tint = CanvasModulate.new()
	_tint.name = "DayNightTint"
	add_child(_tint)
	building_glow = BuildingGlow.new()
	building_glow.name = "BuildingGlow"
	add_child(building_glow)
	# Above the ground and the buildings it lights, below the units, who stay
	# crisp on top of it.
	move_child(building_glow, unit_renderer.get_index())
	building_glow.bind(level)
	director.day_started.connect(_on_day_started)
	director.phase_changed.connect(_on_phase_changed)
	level.building_removed.connect(_on_building_removed)
	build_placer.tile_picked.connect(_on_tile_picked)
	build_placer.paint_started.connect(_on_paint_started)
	build_placer.paint_moved.connect(_on_paint_moved)
	shop.purchase_check = _purchase_check
	shop.unlocks = unlocks
	shop.inventory = inventory

	EventBus.on_quit_button_pressed.connect(save_run)
	economy.changed.connect(func(kind, amount): EventBus.resource_changed.emit(kind, amount))
	roster.changed.connect(func(kind, count): EventBus.roster_changed.emit(kind, count))
	shop.purchased.connect(func(item, n): EventBus.shop_purchased.emit(item.id, n))
	level.level_generated.connect(_on_level_generated)
	build_placer.placement_finished.connect(_on_placement_finished)
	build_placer.placement_cancelled.connect(toast.hide_message)
	options_menu.visibility_changed.connect(_on_options_visibility_changed)

	resource_bar.bind(economy)
	shop_ui.bind(shop, economy, modifiers)
	worker_ui.bind(units)
	worker_ui.slot_pressed.connect(_on_worker_slot_pressed)
	building_ui.bind(inventory, level)
	building_ui.slot_pressed.connect(_on_building_slot_pressed)
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


## UI created in code goes in front of the options menu, which stays last so it
## draws over everything else.
func _add_ui(node: Node) -> void:
	$UI.add_child(node)
	$UI.move_child(node, options_menu.get_index())


func _process(delta: float) -> void:
	var ticks := clock.advance(delta)
	for i in ticks:
		_simulate(GameClock.TICK_DELTA)
	# Drawn once per frame, after the simulation, never from inside it.
	unit_renderer.draw_units(units.store, clock.tick_count)
	unit_renderer.draw_drops(units.drops, clock.tick_count)
	var light := director.light_colour()
	_tint.color = light
	building_glow.set_night(director.darkness(), light)
	day_bar.refresh()
	_debug_repeat(delta)


## The single place simulation order is decided. Every system that advances the
## world is stepped from here, in this order, with a fixed dt.
##   1. director -- day/night, the day counter (RunDirector.step)
##   2. units -- move, decide, build, chop, gather, haul (UnitSystem.step)
##   3. forest -- stumps rot, trees regrow (Forest.step)
## Systems land here as they are built, in the order they must run. The director
## goes first so that a phase change takes effect on the same tick the units
## decide what to do with it.
func _simulate(dt: float) -> void:
	director.step()
	units.night = director.is_night
	units.tick = clock.tick_count
	units.step(dt)
	forest.step(clock.tick_count)


# --- Run lifecycle ------------------------------------------------------------

func _start_new_run() -> void:
	_end_dispatch()
	build_placer.stop()
	_run_over = false
	run_summary.hide_summary()
	clock.pop_pause(PAUSE_GAME_OVER)
	director.reset()
	units.night = false
	units.clear()
	modifiers.clear()
	shop.reset()
	roster.clear()
	unlocks.reset()
	inventory.clear()
	lava.clear()
	economy.set_all(starting_resources)
	level.generate()
	forest.start_new(clock.tick_count, level.used_seed)
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
	unlocks.load_save_data(save.get("unlocks", {}))
	inventory.load_save_data(save.get("inventory", {}))
	if not modifiers.load_save_data(save.get("modifiers", {}), _resolve_modifier_source):
		return false
	if not level.load_save_data(save["level"]):
		return false
	# After the level: units refer to buildings by cell.
	if not units.load_save_data(save.get("units", {})):
		return false
	forest.load_save_data(save.get("forest", {}))
	lava.load_save_data(save.get("lava", {}))
	director.load_save_data(save.get("director", {}))
	units.night = director.is_night
	if save.has("clock"):
		clock.load_save_data(save["clock"])
	return true


## Assembles everything a run needs to resume. Systems own their own save
## shape; this function only decides which of them are in a run save.
func save_run() -> void:
	if _run_over:
		return   # the run save was deleted when the base fell; do not write it back
	var ok := SaveManager.save_run({
		"level": level.get_save_data(),
		"clock": clock.get_save_data(),
		"economy": economy.get_save_data(),
		"roster": roster.get_save_data(),
		"shop": shop.get_save_data(),
		"modifiers": modifiers.get_save_data(),
		"units": units.get_save_data(),
		"unlocks": unlocks.get_save_data(),
		"inventory": inventory.get_save_data(),
		"forest": forest.get_save_data(),
		"lava": lava.get_save_data(),
		"director": director.get_save_data(),
		# progression joins this as it is built. SaveManager neither knows nor
		# cares what these keys mean.
	})
	if not ok:
		push_error("Main: the run could not be saved.")


## Rebuilds a modifier source from current game data when a run is loaded, so a
## rebalanced upgrade reaches runs already in progress. Returns
## Array[StatModifier], or null if the source no longer exists.
## Augments (Stage 7) will be looked up here too.
func _resolve_modifier_source(source: String) -> Variant:
	return shop.resolve_source(source)


# --- Day, night and death -----------------------------------------------------

## Dawn. Autosaving here means a lost run costs at most one day, and the day
## boundary is the one moment when nobody is mid-job.
func _on_day_started(day: int) -> void:
	save_run()
	toast.show_message("Day %d" % day, 3.0)


func _on_phase_changed(is_night: bool, _day: int) -> void:
	if is_night:
		units.on_night_started()
		toast.show_message("Night falls. Everyone heads home.", 3.0)
	else:
		units.on_day_started()


## The base is the run. Anything else being removed is ordinary business.
func _on_building_removed(_id: int, type: String, _cell: Vector2i) -> void:
	if type == "base" and not _run_over:
		_end_run()


## Freeze the world, throw the run away, keep what the profile remembers.
func _end_run() -> void:
	_run_over = true
	_end_dispatch()
	build_placer.stop()
	clock.push_pause(PAUSE_GAME_OVER)
	toast.hide_message()
	SaveManager.delete_run()
	var profile := SaveManager.profile
	profile["runs_ended"] = int(profile.get("runs_ended", 0)) + 1
	profile["best_day"] = maxi(int(profile.get("best_day", 0)), director.day)
	profile["total_ticks"] = int(profile.get("total_ticks", 0)) + clock.tick_count
	SaveManager.save_profile()
	run_summary.show_run("Your base has fallen", _summary_rows())


func _summary_rows() -> Array:
	var seconds := int(clock.get_elapsed_seconds())
	var workers := 0
	for kind in WorkerRoster.Kind.COUNT:
		workers += units.count(kind)
	var rows := [
		["Days survived", str(director.day)],
		["Time", "%d:%02d" % [floori(seconds / 60.0), seconds % 60]],
		["Workers", str(workers)],
	]
	for kind in ResourceKind.count():
		var amount := economy.amount(kind)
		if amount > 0:
			rows.append([ResourceKind.display_of(kind), str(amount)])
	rows.append(["Best day so far", str(int(SaveManager.profile.get("best_day", 0)))])
	return rows


func _return_to_title() -> void:
	get_tree().change_scene_to_file("res://game/title_screen.tscn")


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
	paths.append(building_ui.SLOT_TEXTURE)
	paths.append_array(preload("res://UI/item_bar.gd").art_paths())
	paths.append_array(preload("res://UI/day_bar.gd").art_paths())
	for data in level.placeable_buildings:
		if data != null and data.texture == null:
			paths.append(data.texture_path)
	for kind in UnitRenderer.LOOKS:
		for anim in UnitRenderer.LOOKS[kind]:
			paths.append(UnitRenderer.LOOKS[kind][anim])
	return paths


## Rules the shop checks beyond price. Workers need a base to arrive at and a
## free bed in a finished house of their kind (miner houses for miners).
func _purchase_check(item: ShopItemData) -> String:
	if item.kind == ShopItemData.Kind.UPGRADE:
		return ""
	if level.base_cell == LevelGenerator.INVALID_CELL:
		return "Place your base first."
	if item.kind != ShopItemData.Kind.WORKER:
		return ""
	if units.free_beds(item.worker_kind) <= 0:
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
	else:
		inventory.take(type)   # placed from the building bar
		toast.hide_message()


func _on_building_slot_pressed(type: String) -> void:
	if level.base_cell == LevelGenerator.INVALID_CELL or build_placer.is_active():
		return
	_end_dispatch()
	build_placer.start(type, true, true)
	var where := "next to a mine without one" if type == UnitSystem.WORKER_HOUSE else ""
	toast.show_message("Click to place%s.  %s: cancel." % [(" " + where) if where != "" else "",
		Keybinds.describe_action("cancel_placement")], 4.0)


## The bucket is taken in hand from the item bar, like a building from the
## building bar. Empty: the next click on water sends a builder to fill it.
## Full: drag over lava to mark it for cobble. Cancelling works the same way.
func _on_item_pressed(id: String) -> void:
	if build_placer.is_active():
		return
	_end_dispatch()
	var cancel := Keybinds.describe_action("cancel_placement")
	if id == LavaWorks.ITEM_WATER_BUCKET:
		build_placer.start_paint("res://assets/ui/bucket_full.png", _can_mark_cell)
		toast.show_message("Drag over lava to mark it for cobble.  %s: done." % cancel, 4.0)
	elif id == LavaWorks.ITEM_BUCKET and not lava.has_water_bucket():
		build_placer.start_tile("res://assets/ui/bucket_empty.png", _can_fill_cell)
		toast.show_message("Click a water tile to fill the bucket there.  %s: cancel." % cancel, 4.0)


func _can_fill_cell(cell: Vector2i) -> bool:
	return level.grid.in_bounds(cell) and lava.can_fill_at(level.grid.index(cell))


## Lava the bucket can mark, or a tile already marked (so a stroke can unmark).
func _can_mark_cell(cell: Vector2i) -> bool:
	if not level.grid.in_bounds(cell):
		return false
	var i := level.grid.index(cell)
	return lava.is_markable(i) or lava.is_marked(i)


func _on_tile_picked(cell: Vector2i) -> void:
	if lava.set_fill_target(level.grid.index(cell)):
		toast.show_message("A builder will fill the bucket here.", 2.0)


## A stroke with the water bucket in hand: the first tile decides whether this
## stroke marks or unmarks, and dragging carries on with the same choice.
func _on_paint_started(cell: Vector2i) -> void:
	if not level.grid.in_bounds(cell):
		return
	var i := level.grid.index(cell)
	_paint_on = not lava.is_marked(i)
	_paint_last = cell
	lava.set_mark(i, _paint_on)


## Marks (or unmarks) every tile on the line from the last painted tile, so a
## fast drag does not skip tiles between two mouse events.
func _on_paint_moved(cell: Vector2i) -> void:
	if cell == _paint_last:
		return
	var from := _paint_last
	var steps := maxi(absi(cell.x - from.x), absi(cell.y - from.y))
	for n in range(1, steps + 1):
		var c := Vector2i((Vector2(from).lerp(Vector2(cell), float(n) / steps)).round())
		if level.grid.in_bounds(c):
			lava.set_mark(level.grid.index(c), _paint_on)
	_paint_last = cell


## Left click on a plain tree marks it for chopping (or unmarks it). Builders
## chop marked trees when they have nothing more urgent to do.
func _tree_click() -> bool:
	var cell := level.world_to_cell(get_global_mouse_position())
	if not level.grid.in_bounds(cell):
		return false
	var id := level.grid.get_occupant(cell)
	if forest.is_tree(id):
		var marked := forest.toggle_mark(id)
		toast.show_message("Marked for chopping." if marked else "No longer marked.", 1.5)
		return true
	if level.store.is_alive(id) and level.store.get_type(id) == "tree_fruit":
		toast.show_message("Fruit trees are kept for their fruit.", 1.5)
		return true
	return false


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

	if event.is_action_pressed("left_click") and not build_placer.is_active() and _tree_click():
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
		_debug_grant()   # once on press; holding repeats it (_debug_repeat)
	elif event.is_action_pressed("debug_stat_overlay"):
		stat_overlay.toggle()
	elif event.is_action_pressed("debug_skip_phase"):
		director.force_phase_end()
		print("Debug: skipping to the end of the ", "night" if director.is_night else "day")
	elif event.is_action_pressed("debug_kill_base"):
		if level.base_cell != LevelGenerator.INVALID_CELL:
			level.remove_building(level.base_cell)   # ends the run (_on_building_removed)
			print("Debug: base destroyed")
	else:
		return
	get_viewport().set_input_as_handled()


## Each grant in one hold is bigger than the last: 100, 125, 156, ... so a few
## seconds of holding reaches millions.
func _debug_grant() -> void:
	var amount := mini(int(round(debug_grant_amount * pow(debug_grant_growth, _grants_this_hold))),
		debug_grant_max)
	_grants_this_hold += 1
	for kind in ResourceKind.count():
		economy.add(kind, amount)


## Holding the grant shortcut keeps granting: after a short delay, several
## times a second. Wall time on purpose: it must work while the game is paused.
func _debug_repeat(delta: float) -> void:
	if not Keybinds.dev_tools_enabled() or not Input.is_action_pressed("debug_grant_resources"):
		_grant_held = 0.0
		_grants_this_hold = 0
		return
	var before := _grant_held
	_grant_held += delta
	var interval := 1.0 / maxf(debug_grant_repeats_per_second, 0.1)
	var start := debug_grant_repeat_delay
	# Grants for every repeat boundary crossed this frame (a slow frame can cross several).
	var n := 0
	if _grant_held >= start:
		n = int(floor((_grant_held - start) / interval)) + 1
		if before >= start:
			n -= int(floor((before - start) / interval)) + 1
	for i in n:
		_debug_grant()
