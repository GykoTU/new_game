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
## The level-up screen holds the clock while a pick is pending (Stage 7).
const PAUSE_LEVEL_UP := "level_up"
## A fallen run pays one relic per this many levels reached (Stage 8).
const SURVIVAL_LEVELS := 3

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
	"explorer": {
		"tags": ["unit", "worker", "explorer"],
		"base": {Stats.Id.MOVE_SPEED: 70.0},
		"stats": [Stats.Id.MOVE_SPEED],
	},
}

## What a new run starts with. Tunable in the inspector on the Main node.
@export var starting_resources: Dictionary[ResourceKind.Id, int] = {ResourceKind.Id.GOLD: 100}
@export var shop_catalogue: ShopCatalogue = preload("res://data/shop/catalogue.tres")
@export var augment_pool: AugmentPool = preload("res://data/augments/pool.tres")
## Stage 8: the relic tree. The run keeps a snapshot of what was owned when it
## started (`meta`), so the title screen's tree only changes the next run.
@export var meta_tree: MetaTree = preload("res://data/meta/tree.tres")
## Every kind of enemy (Stage 4). Saves refer to them by id, not by position here.
@export var enemy_kinds: Array[EnemyData] = [
	preload("res://data/enemies/goblin.tres"),
	preload("res://data/enemies/bee.tres"),
]
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
## What the player has seen (Stage 3b).
var fog := FogOfWar.new()
## What the explorer finds under the fog.
var pois := PointsOfInterest.new()
## Draws the fog. Created in _ready.
var fog_renderer: FogRenderer
## Stage 4: the enemies, who comes each night, and the base's own zap.
var enemies := EnemySystem.new()
var waves := Waves.new()
var defence := BaseDefence.new()
## Stage 5: weapon buildings, their shots and effects.
var weapons := WeaponSystem.new()
var projectile_renderer: ProjectileRenderer
var weapon_effects: WeaponEffects
var weapon_panel
## The shovel's marks (Stage 5 fixes).
var demolition := Demolition.new()
var dig_marks: DigMarks
## Grey and blue glows round dropped blueprints.
var cache_halos: CacheHalos
## Stage 6: walls, gates, roads, bridges, crossings.
var build_tools := BuildTools.new()
var wall_tiles := WallTiles.new()
var overlay_renderer: OverlayRenderer
var tool_bar
var _tool := -1          # BuildTools.Tool while a paint tool is in hand
## Stage 7: XP, levels, augments; building health as a stat.
var progression := Progression.new()
var building_stats := BuildingStats.new()
var level_up
var xp_bar
## Stage 8: the relic tree as it was when this run started.
var meta: MetaState
## False for a run saved before Stage 8: nothing is locked for it.
var _meta_locks := true
## Relics paid for surviving, shown in the summary (Stage 8).
var _survival_relics := 0
var _counting_reveals := true
var _night_number := 1
var _paint_gate := false  # this stroke paints gates (Shift at its start)
## Which item is being painted with: the water bucket (lava) or the shovel.
var _paint_tool := ""
## The weapon building whose panel is open, or -1.
var _selected_weapon := -1
## Drawing for the above. Created in _ready.
var enemy_renderer: EnemyRenderer
var combat_effects: CombatEffects
var health_bars: HealthBars
## Where the explorers are headed (only with its optional sprite). Created in _ready.
var explore_flags: ExploreFlags
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
## True while the player is choosing where to send a worker: a mine for a
## miner, anywhere for an explorer. `_dispatch_kind` says which.
var _dispatching := false
var _dispatch_kind: int = WorkerRoster.Kind.MINER
## Seconds the grant shortcut has been held, and grants given in this hold
## (debug builds only).
var _grant_held := 0.0
var _grants_this_hold := 0
## Painting lava marks with the water bucket in hand (see _on_paint_started).
var _paint_on := true
var _paint_last := Vector2i(-1, -1)


func _ready() -> void:
	shop = Shop.new(shop_catalogue, economy, roster, modifiers)
	progression.setup(augment_pool, modifiers)
	# The findable pool: every blueprint in the shop a run does not start with.
	unlocks.configure(shop_catalogue)
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
	fog.setup(level)
	pois.setup(level, unlocks, fog)
	units.pois = pois
	pois.spotted.connect(_on_poi_spotted)
	pois.opened.connect(_on_poi_opened)
	enemies.setup(level, units, unlocks, enemy_kinds)
	waves.setup(enemies, level)
	defence.setup(level, enemies, modifiers)
	weapons.setup(level, enemies, units, unlocks, modifiers)
	demolition.setup(level, economy, shop_catalogue)
	building_stats.setup(level, modifiers)
	progression.offer_ready.connect(_on_offer_ready)
	progression.augment_taken.connect(_on_augment_taken)
	fog.revealed.connect(_on_revealed)
	units.demolition = demolition
	demolition.dug.connect(_on_dug)
	# Walls and gates are painted, not crafted: half the paint price back.
	for key in ["wall", "gate"]:
		var back := {}
		var price := BuildTools.price_of(key)
		for k in price:
			if floori(price[k] * 0.5) > 0:
				back[k] = floori(price[k] * 0.5)
		demolition.set_refund(key, back)
	enemies.blueprint_dropped.connect(_on_blueprint_dropped)
	waves.night_planned.connect(_on_night_planned)
	units.unit_killed.connect(_on_unit_killed)
	var marks := TileMarks.new()
	marks.name = "LavaMarks"
	level.add_sibling(marks)   # drawn over the ground, under the units
	marks.bind(lava, level)
	item_bar = preload("res://UI/item_bar.gd").new()
	item_bar.name = "ItemBar"
	_add_ui(item_bar)
	item_bar.bind(unlocks)
	item_bar.item_pressed.connect(_on_item_pressed)
	tool_bar = preload("res://UI/item_bar.gd").new()
	tool_bar.name = "ToolBar"
	tool_bar.tools = true
	_add_ui(tool_bar)
	tool_bar.bind(unlocks)
	tool_bar.item_pressed.connect(_on_item_pressed)
	build_tools.setup(level, economy)
	units.tools = build_tools
	wall_tiles.bind(level)
	overlay_renderer = OverlayRenderer.new()
	overlay_renderer.name = "Overlays"
	level.add_child(overlay_renderer)
	overlay_renderer.bind(level, build_tools)
	day_bar = preload("res://UI/day_bar.gd").new()
	day_bar.name = "DayBar"
	_add_ui(day_bar)
	day_bar.bind(director)
	run_summary = preload("res://UI/run_summary.gd").new()
	run_summary.name = "RunSummary"
	_add_ui(run_summary)
	run_summary.return_pressed.connect(_return_to_title)
	xp_bar = preload("res://UI/xp_bar.gd").new()
	xp_bar.name = "XpBar"
	_add_ui(xp_bar)
	xp_bar.bind(progression)
	level_up = preload("res://UI/level_up.gd").new()
	level_up.name = "LevelUp"
	_add_ui(level_up)
	level_up.picked.connect(_on_augment_picked)
	level_up.rerolled.connect(_on_reroll)
	level_up.skipped.connect(_on_skip)
	weapon_panel = preload("res://UI/weapon_panel.gd").new()
	weapon_panel.name = "WeaponPanel"
	_add_ui(weapon_panel)
	weapon_panel.mode_pressed.connect(_on_weapon_mode_pressed)
	weapon_panel.closed.connect(_deselect_weapon)
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
	cache_halos = CacheHalos.new()
	cache_halos.name = "CacheHalos"
	add_child(cache_halos)
	move_child(cache_halos, building_glow.get_index() + 1)
	cache_halos.bind(pois)
	dig_marks = DigMarks.new()
	dig_marks.name = "DigMarks"
	add_child(dig_marks)
	move_child(dig_marks, cache_halos.get_index() + 1)
	dig_marks.bind(demolition, level)
	# Over everything in the world (z_index 2), under the placer's ghost.
	fog_renderer = FogRenderer.new()
	fog_renderer.name = "Fog"
	add_child(fog_renderer)
	move_child(fog_renderer, build_placer.get_index())
	fog_renderer.bind(level, fog)
	# Enemies and their effects with the units (z 1), so the fog hides them.
	enemy_renderer = EnemyRenderer.new()
	enemy_renderer.name = "EnemyRenderer"
	add_child(enemy_renderer)
	move_child(enemy_renderer, unit_renderer.get_index() + 1)
	enemy_renderer.bind(enemy_kinds)
	projectile_renderer = ProjectileRenderer.new()
	projectile_renderer.name = "ProjectileRenderer"
	add_child(projectile_renderer)
	move_child(projectile_renderer, enemy_renderer.get_index() + 1)
	projectile_renderer.bind(weapons.types)
	weapon_effects = WeaponEffects.new()
	weapon_effects.name = "WeaponEffects"
	add_child(weapon_effects)
	move_child(weapon_effects, projectile_renderer.get_index() + 1)
	weapon_effects.bind(weapons)
	combat_effects = CombatEffects.new()
	combat_effects.name = "CombatEffects"
	add_child(combat_effects)
	move_child(combat_effects, weapon_effects.get_index() + 1)
	health_bars = HealthBars.new()
	health_bars.name = "HealthBars"
	add_child(health_bars)
	move_child(health_bars, build_placer.get_index())
	health_bars.bind(level, units)
	explore_flags = ExploreFlags.new()
	explore_flags.name = "ExploreFlags"
	add_child(explore_flags)
	move_child(explore_flags, build_placer.get_index())
	explore_flags.bind(units.store, level)
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
	cache_halos.refresh(delta, light)
	fog_renderer.refresh()
	explore_flags.refresh()
	enemy_renderer.draw_enemies(enemies, clock.tick_count)
	projectile_renderer.draw_shots(weapons.projectiles, clock.tick_count, light)
	weapon_effects.refresh(clock.tick_count, light)
	combat_effects.refresh(defence, enemies, clock.tick_count, light)
	health_bars.refresh()
	day_bar.refresh()
	_debug_repeat(delta)


## The single place simulation order is decided. Every system that advances the
## world is stepped from here, in this order, with a fixed dt.
##   1. director -- day/night, the day counter (RunDirector.step)
##   2. waves -- tonight's groups set out on schedule (Waves.step)
##   3. units -- move, decide, build, chop, gather, haul (UnitSystem.step)
##   4. fog -- units that walked into a new tile look around (FogOfWar.step_units)
##   5. enemies -- fields, hash, targets, moving, hitting, burning (EnemySystem.step)
##   6. defence -- the base zaps, using the hash step 5 built (BaseDefence.step)
##   7. weapons -- aim and fire, then shots move and hit, then blasts and
##      burning ground (WeaponSystem.step), also on step 5's hash
##   8. forest -- stumps rot, trees regrow (Forest.step)
##   9. progression -- XP from kills and the survival drip (Progression.step);
##      a level-up pauses the clock through _on_offer_ready
## Systems land here as they are built, in the order they must run. The director
## goes first so that a phase change takes effect on the same tick the units
## decide what to do with it.
func _simulate(dt: float) -> void:
	director.step()
	units.night = director.is_night
	units.tick = clock.tick_count
	waves.step(clock.tick_count)
	units.step(dt)
	fog.step_units(units.store)
	enemies.tick = clock.tick_count
	enemies.step(dt)
	defence.step(clock.tick_count)
	weapons.tick = clock.tick_count
	weapons.step(dt)
	# 9. progression -- kills' XP and the survival drip (only with a base)
	if level.base_cell != LevelGenerator.INVALID_CELL:
		var kill_xp := floori(enemies.xp_bank)
		enemies.xp_bank -= kill_xp
		progression.add_xp(kill_xp)
		progression.step()
	else:
		enemies.xp_bank = 0.0
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
	_set_gates(false)
	units.clear()
	enemies.clear()
	defence.clear()
	weapons.clear()
	_deselect_weapon()
	modifiers.clear()
	shop.reset()
	roster.clear()
	unlocks.reset()
	inventory.clear()
	lava.clear()
	# The relic tree as owned right now: this run keeps it (see `meta`).
	meta = MetaState.new(meta_tree, SaveManager.profile.get("meta", {}))
	_meta_locks = true
	_survival_relics = 0
	var start := starting_resources.duplicate()
	var bonus := meta.start_resources()
	for k in bonus:
		start[k] = int(start.get(k, 0)) + int(bonus[k])
	economy.set_all(start)
	for b in meta.start_blueprints():
		unlocks.add(b)
	var sources := meta.modifier_sources()
	for source in sources:
		modifiers.add_source(source, sources[source])
	level.generate()
	pois.clear()
	waves.clear()
	forest.start_new(clock.tick_count, level.used_seed)
	clock.pop_pause(PAUSE_LEVEL_UP)
	level_up.hide_screen()
	_apply_meta_rules()
	progression.reset(level.used_seed + 7)
	_apply_augment_rules()
	_focus_camera(level.cell_to_world(level.start_cell))
	_count_run_started()
	# New game: the player picks where the base goes, inside the clearing the
	# fog leaves open. It can't be cancelled.
	build_placer.start("base", false)
	toast.show_message("Place your base in the clearing.", 4.0)


## Order matters. Shop purchases load before modifiers, because rebuilding an
## upgrade's modifiers reads its level from the purchase count. Modifiers load
## before the level: they are cheap to reject, so a run with a missing upgrade
## is refused before the map is built. On any failure the caller starts a new
## run, which resets everything this may have partly loaded.
##
## Keys missing from older saves are additive: a run saved before the economy
## existed gets the starting resources, and so on. RUN_VERSION did not move.
func _load_run(save: Dictionary) -> bool:
	# First: the tree this run started with. Its perks shape how progression
	# loads, and its "meta:" modifier sources are rebuilt from it.
	var saved_meta: Dictionary = save.get("meta", {})
	meta = MetaState.new(meta_tree, saved_meta.get("levels", {}))
	_meta_locks = bool(saved_meta.get("locks", false))   # older runs: nothing locked
	_survival_relics = 0
	_apply_meta_rules()
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
	# Before modifiers: augment sources are rebuilt from the stacks.
	progression.load_save_data(save.get("progression", {}))
	if not modifiers.load_save_data(save.get("modifiers", {}), _resolve_modifier_source):
		return false
	if not level.load_save_data(save["level"]):
		return false
	# After the level: units refer to buildings by cell.
	if not units.load_save_data(save.get("units", {})):
		return false
	forest.load_save_data(save.get("forest", {}))
	lava.load_save_data(save.get("lava", {}))
	pois.load_save_data(save.get("poi", {}))
	pois.relic_bonus = meta.perk("relic_bonus")
	enemies.load_save_data(save.get("enemies", {}))
	weapons.load_save_data(save.get("weapons", {}))
	demolition.load_save_data(save.get("demolition", {}))
	waves.load_save_data(save.get("waves", {}))
	director.load_save_data(save.get("director", {}))
	units.night = director.is_night
	build_tools.load_save_data(save.get("build_tools", {}))
	_set_gates(director.is_night)
	if save.has("clock"):
		clock.load_save_data(save["clock"])
	var focus := level.base_cell if level.base_cell != LevelGenerator.INVALID_CELL else level.start_cell
	_focus_camera(level.cell_to_world(focus))
	_apply_augment_rules()
	progression.resume_offer()   # a pick left open when the run was saved
	return true


## Assembles everything a run needs to resume. Systems own their own save
## shape; this function only decides which of them are in a run save.
func save_run() -> void:
	if _run_over:
		return   # the run save was deleted when the base fell; do not write it back
	# Relics found since the last save go into the profile in the same breath
	# as the run that no longer holds their caches (see PointsOfInterest).
	var relics := pois.take_pending_relics()
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
		"poi": pois.get_save_data(),
		"enemies": enemies.get_save_data(),
		"waves": waves.get_save_data(),
		"weapons": weapons.get_save_data(),
		"demolition": demolition.get_save_data(),
		"build_tools": build_tools.get_save_data(),
		"progression": progression.get_save_data(),
		"meta": {"levels": meta.get_levels(), "locks": _meta_locks},
		# progression joins this as it is built. SaveManager neither knows nor
		# cares what these keys mean.
	})
	if not ok:
		push_error("Main: the run could not be saved.")
		pois.relics_pending += relics   # still the run's; try again next save
		return
	_bank_relics(relics)


func _bank_relics(n: int) -> void:
	if n <= 0:
		return
	SaveManager.profile["relics"] = int(SaveManager.profile.get("relics", 0)) + n
	SaveManager.save_profile()


## Rebuilds a modifier source from current game data when a run is loaded, so a
## rebalanced upgrade reaches runs already in progress. Returns
## Array[StatModifier], or null if the source no longer exists.
## Augments (Stage 7) will be looked up here too.
func _resolve_modifier_source(source: String) -> Variant:
	if source.begins_with(Progression.SOURCE_PREFIX):
		return progression.resolve_source(source)
	if source.begins_with(MetaState.SOURCE_PREFIX):
		return meta.resolve_source(source)
	return shop.resolve_source(source)


# --- Day, night and death -----------------------------------------------------

## Dawn. Autosaving here means a lost run costs at most one day, and the day
## boundary is the one moment when nobody is mid-job.
func _on_day_started(day: int) -> void:
	save_run()
	toast.show_message("Day %d" % day, 3.0)


func _on_phase_changed(is_night: bool, day: int) -> void:
	_set_gates(is_night)
	if is_night:
		_night_number = day
		units.on_night_started()
		waves.start_night(day, clock.tick_count)   # toasts through _on_night_planned
	else:
		units.on_day_started()
		waves.end_night()
		enemies.burn_all()
		progression.on_dawn(_night_number)
		if progression.has_flag("second_wind") and level.base_cell != LevelGenerator.INVALID_CELL:
			var base := level.grid.get_occupant(level.base_cell)
			level.store.heal(base, level.store.get_max_health(base) * 0.25)


func _on_night_planned(_night: int, sides: PackedInt32Array, _shape: String) -> void:
	toast.show_message("Night falls. Enemies approach from %s." % Waves.describe_sides(sides), 4.0)


func _on_unit_killed(kind: int) -> void:
	toast.show_message("Your %s was killed." % WorkerRoster.display_of(kind).to_lower(), 3.0)


## A kill dropped a blueprint: a cache where it fell, glowing by rarity, for
## the explorer to bring in.
func _on_blueprint_dropped(blueprint: String, at: Vector2) -> void:
	if pois.add_dropped(at, blueprint) == BuildingStore.NONE:
		return   # no room: it goes back into the pool
	var rare := unlocks.rarity_of(blueprint) == ShopItemData.Rarity.RARE
	toast.show_message("An enemy dropped a %s blueprint. Your explorer can bring it in." \
		% ("rare" if rare else "common"), 4.0)


func _on_dug(type: String, refund: Dictionary) -> void:
	var data := level.get_building_data(type)
	var parts := PackedStringArray()
	for k in refund:
		parts.append("%d %s" % [refund[k], ResourceKind.display_of(k)])
	toast.show_message("Dug out the %s.%s" % [data.display_name if data != null else type,
		(" Back: " + ", ".join(parts) + ".") if not parts.is_empty() else ""], 2.5)


## The base is the run. Anything else being removed is ordinary business.
func _on_building_removed(id: int, type: String, _cell: Vector2i) -> void:
	if id == _selected_weapon:
		_deselect_weapon()
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
	_survival_relics = survival_relics()
	profile["relics"] = int(profile.get("relics", 0)) + pois.take_pending_relics() + _survival_relics
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
	rows.append(["Level reached", str(progression.level)])
	rows.append(["Relics found", str(pois.relics_found)])
	rows.append(["Relics for surviving", str(_survival_relics)])
	rows.append(["Best day so far", str(int(SaveManager.profile.get("best_day", 0)))])
	return rows


## Stage 8: what a fallen run pays into the relic tree on top of the relics
## it found: one per night survived, one per SURVIVAL_LEVELS levels reached.
func survival_relics() -> int:
	@warning_ignore("integer_division")
	return maxi(director.day - 1, 0) + progression.level / SURVIVAL_LEVELS


## The relic tree's rules for this run: locks, perks. Called on a new run
## (before progression resets) and on load (before progression loads).
func _apply_meta_rules() -> void:
	unlocks.set_locked(meta.locked_with_prefix("blueprint:") if _meta_locks else {})
	progression.locked = meta.locked_with("augment:") if _meta_locks else {}
	progression.rerolls_per_pick = 1 + meta.perk("rerolls")
	progression.choices = Progression.CHOICES + meta.perk("choices")
	pois.relic_bonus = meta.perk("relic_bonus")


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
	paths.append_array(LevelGenerator.POI_FILES.values())
	paths.append("res://assets/ui/relic.png")
	paths.append(ExploreFlags.FLAG)
	paths.append_array(EnemyRenderer.art_paths(enemy_kinds))
	paths.append_array(CombatEffects.art_paths())
	paths.append_array(ProjectileRenderer.art_paths(weapons.types))
	paths.append_array(WeaponEffects.art_paths())
	paths.append(DigMarks.MARK)
	paths.append_array(preload("res://UI/level_up.gd").art_paths(augment_pool))
	paths.append_array(preload("res://UI/xp_bar.gd").art_paths())
	paths.append_array(preload("res://UI/meta_tree_screen.gd").art_paths(meta_tree))
	paths.append_array(WallTiles.art_paths())
	paths.append_array(OverlayRenderer.art_paths())
	paths.append_array(preload("res://UI/shop_ui.gd").art_paths())
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


# --- Sending miners and explorers ---------------------------------------------

func _on_worker_slot_pressed(kind: int) -> void:
	if kind != WorkerRoster.Kind.MINER and kind != WorkerRoster.Kind.EXPLORER:
		return   # builders and carriers work on their own (assignable tasks: later)
	if _dispatching:
		var same := kind == _dispatch_kind
		_end_dispatch()
		if same:
			return   # a second click on the same slot just closes the mode
	if level.base_cell == LevelGenerator.INVALID_CELL:
		toast.show_message("Place your base first.")
		return
	if units.count(kind) == 0:
		toast.show_message("You have no %ss. Buy one in the shop." % WorkerRoster.display_of(kind).to_lower())
		return
	var stop := Keybinds.describe_action("cancel_placement")
	if kind == WorkerRoster.Kind.EXPLORER:
		if director.is_night:
			toast.show_message("Explorers don't go out at night.")
			return
		toast.show_message("Click anywhere to send the explorer, fog too.  %s: stop." % stop, 4.0)
	else:
		toast.show_message("Click a mine to send a miner.  Shift: send more.  %s: stop." % stop, 4.0)
	_dispatching = true
	_dispatch_kind = kind
	worker_ui.set_active(kind)


func _end_dispatch() -> void:
	_dispatching = false
	if worker_ui != null:
		worker_ui.set_active(-1)


## Left click while dispatching. Shift keeps the mode open to send more; any
## refusal closes it and says why.
func _dispatch_click(shift: bool) -> void:
	var cell := level.world_to_cell(get_global_mouse_position())
	var result := ""
	if _dispatch_kind == WorkerRoster.Kind.EXPLORER:
		result = units.send_explorer(cell)
	else:
		# A mine under the fog is not there as far as the player knows.
		var mine := level.grid.get_occupant(cell) if fog.is_explored(cell) else WorldGrid.NO_OCCUPANT
		result = "Click a mine." if mine == WorldGrid.NO_OCCUPANT else units.send_miner(mine)
	if result != "":
		toast.show_message(result)
		_end_dispatch()
	elif not shift:
		toast.hide_message()
		_end_dispatch()


# --- Callbacks ----------------------------------------------------------------

## Snaps the camera onto a point (no smoothing across the whole map).
func _focus_camera(world: Vector2) -> void:
	var cam: Camera2D = $Camera/Camera2D
	cam.global_position = world
	cam.reset_smoothing()


func _on_poi_spotted(id: int, type: String) -> void:
	units.on_poi_spotted(id, type)
	if type == PointsOfInterest.DROPPED:
		return   # the drop already said so
	var what: String = {PointsOfInterest.BLUEPRINT_CACHE: "a blueprint cache",
		PointsOfInterest.RELIC_CACHE: "a relic cache", PointsOfInterest.NPC_HOUSE: "a house",
		PointsOfInterest.FRUIT_TREE: "a strange tree"}.get(type, "something")
	toast.show_message("Spotted %s." % what, 2.5)


func _on_poi_opened(_type: String, message: String) -> void:
	toast.show_message(message, 4.0)
	if message != "":
		progression.add_xp(Progression.POI_XP)


# --- Progression (Stage 7) ----------------------------------------------------

func _on_revealed(indices: PackedInt32Array) -> void:
	if _counting_reveals and level.base_cell != LevelGenerator.INVALID_CELL:
		progression.on_tiles_revealed(indices.size())


## A pick is up: freeze the world and show the cards.
func _on_offer_ready(ids: PackedStringArray) -> void:
	if _run_over:
		return
	var augments := []
	var stacks := []
	for id in ids:
		augments.append(augment_pool.find(id))
		stacks.append(progression.stacks_of(id))
	clock.push_pause(PAUSE_LEVEL_UP)
	level_up.show_offer(progression.pick_level(), augments, stacks,
		progression.rerolls_left, progression.skip_gold())


func _after_pick() -> void:
	if progression.pending <= 0:
		level_up.hide_screen()
		clock.pop_pause(PAUSE_LEVEL_UP)


func _on_augment_picked(id: String) -> void:
	progression.take(id)
	_after_pick()


func _on_reroll() -> void:
	progression.reroll()


func _on_skip() -> void:
	economy.add(ResourceKind.Id.GOLD, progression.skip())
	_after_pick()


func _on_augment_taken(_id: String, _stacks: int) -> void:
	_apply_augment_rules()


## The rare augments' rules, pushed into the systems they change.
func _apply_augment_rules() -> void:
	weapons.spare_workers = progression.has_flag("careful_aim")
	weapons.gen_bonus = 1 if progression.has_flag("chain_reaction") else 0
	weapons.slowed_damage = 1.3 if progression.has_flag("shatter") else 1.0
	var extra := PackedStringArray()
	if progression.has_flag("volatile_world"):
		extra.append("explode_enemies")
	if extra != weapons.extra_behaviours:
		weapons.set_extra_behaviours(extra)
	enemies.drop_multiplier = 2.0 if progression.has_flag("scavengers") else 1.0
	enemies.spread_burn = progression.has_flag("wildfire")

## Runs after both a new level is generated and a save is loaded.
func _on_level_generated() -> void:
	pass


func _on_placement_finished(type: String, _cell: Vector2i) -> void:
	if type == "base":
		units.start_run_kit(meta.start_workers())
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
	var tool: int = BuildTools.BLUEPRINTS.find_key(id) if BuildTools.BLUEPRINTS.values().has(id) else -1
	if tool != -1:
		_tool = tool
		_paint_tool = "tool"
		var stage: Array = []
		for stages in tool_bar.TOOLS:
			if stages[0][0] == id:
				stage = stages[0]
		build_placer.start_paint(tool_bar.icon_of(stage), _can_tool_cell)
		toast.show_message("%s  %s: done." % [stage[3], cancel], 5.0)
	elif id == Demolition.ITEM:
		_paint_tool = "shovel"
		build_placer.start_paint("res://assets/ui/shovel.png", _can_dig_cell)
		toast.show_message("Click buildings to mark them for digging out.  %s: done." % cancel, 4.0)
	elif id == LavaWorks.ITEM_WATER_BUCKET:
		_paint_tool = "bucket"
		build_placer.start_paint("res://assets/ui/bucket_full.png", _can_mark_cell)
		toast.show_message("Drag over lava to mark it for cobble.  %s: done." % cancel, 4.0)
	elif id == LavaWorks.ITEM_BUCKET and not lava.has_water_bucket():
		build_placer.start_tile("res://assets/ui/bucket_empty.png", _can_fill_cell)
		toast.show_message("Click a water tile to fill the bucket there.  %s: cancel." % cancel, 4.0)


func _can_fill_cell(cell: Vector2i) -> bool:
	return fog.is_explored(cell) and lava.can_fill_at(level.grid.index(cell))


## Lava the bucket can mark, or a tile already marked (so a stroke can unmark).
func _can_mark_cell(cell: Vector2i) -> bool:
	if not fog.is_explored(cell):
		return false
	var i := level.grid.index(cell)
	return lava.is_markable(i) or lava.is_marked(i)


func _on_tile_picked(cell: Vector2i) -> void:
	if lava.set_fill_target(level.grid.index(cell)):
		toast.show_message("A builder will fill the bucket here.", 2.0)


## Gates open by day, close at night: for the enemies' flow fields and the
## gate pictures.
func _set_gates(night: bool) -> void:
	level.set_gates_open(not night)
	wall_tiles.set_night(night)


## A tile the tool in hand can paint (or unpaint). Shift: gates.
func _can_tool_cell(cell: Vector2i) -> bool:
	return build_tools.can_paint(_tool, cell, Input.is_key_pressed(KEY_SHIFT))


func _tool_paint(cell: Vector2i) -> void:
	var why := build_tools.paint(_tool, cell, _paint_gate)
	if why != "" and why != "skip":
		toast.show_message(why, 2.0)


## A building the shovel can mark (or unmark).
func _can_dig_cell(cell: Vector2i) -> bool:
	return level.grid.in_bounds(cell) and fog.is_explored(cell) \
		and demolition.can_dig(level.grid.get_occupant(cell))


## A stroke with the water bucket or the shovel in hand: the first tile decides
## whether this stroke marks or unmarks, and dragging carries on with the same
## choice.
func _on_paint_started(cell: Vector2i) -> void:
	if not level.grid.in_bounds(cell):
		return
	if not fog.is_explored(cell):
		return
	if _paint_tool == "shovel":
		var b := level.grid.get_occupant(cell)
		if demolition.can_dig(b):
			_paint_on = not demolition.is_marked(b)
			demolition.set_mark(b, _paint_on)
		_paint_last = cell
		return
	if _paint_tool == "tool":
		_paint_gate = Input.is_key_pressed(KEY_SHIFT)
		_paint_on = not build_tools.is_planned(_tool, cell, _paint_gate)
		if _paint_on:
			_tool_paint(cell)
		else:
			build_tools.unpaint(_tool, cell)
		_paint_last = cell
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
		if not fog.is_explored(c):
			continue
		if _paint_tool == "shovel":
			demolition.set_mark(level.grid.get_occupant(c), _paint_on)
		elif _paint_tool == "tool":
			if _paint_on:
				_tool_paint(c)
			else:
				build_tools.unpaint(_tool, c)
		else:
			lava.set_mark(level.grid.index(c), _paint_on)
	_paint_last = cell


## Left click on a finished weapon building opens its panel and shows its
## range. Construction sites and fogged tiles do not count.
func _weapon_click() -> bool:
	var cell := level.world_to_cell(get_global_mouse_position())
	if not fog.is_explored(cell) or not level.grid.in_bounds(cell):
		return false
	var id := level.grid.get_occupant(cell)
	if not weapons.is_weapon(id) or not level.store.is_complete(id):
		return false
	_selected_weapon = id
	weapon_effects.selected = id
	var t := weapons.type_of(level.store.get_type(id))
	var d := weapons.types[t]
	var numbers := "Damage %s   Range %.1f tiles" % [_num(weapons.stat(t, Stats.Id.DAMAGE)),
		weapons.stat(t, Stats.Id.RANGE) / 32.0]
	if not d.persistent:
		numbers += "\n%s shots a second" % _num(weapons.stat(t, Stats.Id.FIRE_RATE)
			* roundf(weapons.stat(t, Stats.Id.PROJECTILE_COUNT)))
	weapon_panel.show_weapon(d.display_name, numbers, weapons.mode_of(id), not d.persistent)
	return true


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _on_weapon_mode_pressed() -> void:
	if _selected_weapon != -1:
		weapon_panel.set_mode(weapons.cycle_mode(_selected_weapon))


func _deselect_weapon() -> void:
	_selected_weapon = -1
	if weapon_effects != null:
		weapon_effects.selected = -1
	if weapon_panel != null and weapon_panel.visible:
		weapon_panel.hide_panel()


## Left click on a plain tree marks it for chopping (or unmarks it). Builders
## chop marked trees when they have nothing more urgent to do.
func _tree_click() -> bool:
	var cell := level.world_to_cell(get_global_mouse_position())
	if not fog.is_explored(cell):
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

	if event.is_action_pressed("left_click") and not build_placer.is_active():
		if _weapon_click():
			get_viewport().set_input_as_handled()
			return
		_deselect_weapon()   # a click anywhere else closes the weapon panel
		if _tree_click():
			get_viewport().set_input_as_handled()
			return

	if _selected_weapon != -1 and (event.is_action_pressed("cancel_placement")
			or event.is_action_pressed("ui_cancel")):
		_deselect_weapon()
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
	elif event.is_action_pressed("debug_spawn_enemies"):
		_debug_spawn_enemies()
	elif event.is_action_pressed("debug_reveal_map"):
		_counting_reveals = false   # the dev shortcut is not exploring
		fog.reveal_all()
		_counting_reveals = true
		print("Debug: map revealed")
	elif event.is_action_pressed("debug_unlock_all"):
		# Blueprints only: upgrades still have to be bought (Ctrl+G pays).
		for id in unlocks.findable:
			unlocks.add(id)
		toast.show_message("Debug: every blueprint learned. Buy upgrades in the shop.", 2.5)
	elif event.is_action_pressed("debug_level_up"):
		progression.add_xp(progression.xp_to_next() - progression.xp)
	elif event.is_action_pressed("debug_invincible"):
		level.store.invincible = not level.store.invincible
		toast.show_message("Debug: buildings are %s." % ("invincible" if level.store.invincible
			else "vulnerable again"), 2.5)
	elif event.is_action_pressed("debug_kill_base"):
		if level.base_cell != LevelGenerator.INVALID_CELL:
			level.remove_building(level.base_cell)   # ends the run (_on_building_removed)
			print("Debug: base destroyed")
	else:
		return
	get_viewport().set_input_as_handled()


## Ten goblins on the map edge nearest the camera. By day they do not burn
## (only dawn sets enemies alight), so this works at any time.
func _debug_spawn_enemies() -> void:
	var cam: Camera2D = $Camera/Camera2D
	var cell := level.world_to_cell(cam.global_position)
	var g := level.grid
	var gaps := [cell.y, g.size.x - 1 - cell.x, g.size.y - 1 - cell.y, cell.x]   # N, E, S, W
	var side := 0
	for n in 4:
		if gaps[n] < gaps[side]:
			side = n
	var goblin := enemies.kind_index("goblin")
	var made := 0
	for n in 10:
		var at := waves.spawn_point(side, false)
		if at != Vector2.INF and enemies.spawn(goblin, at) != EnemyStore.NONE:
			made += 1
	print("Debug: %d goblins from the %s" % [made, Waves.SIDE_NAMES[side]])


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
