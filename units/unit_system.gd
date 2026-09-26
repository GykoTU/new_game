class_name UnitSystem
extends RefCounted
## What every worker does: builders, miners and carriers.
##
## Stepped once per simulation tick from main.gd._simulate(). Owns the unit
## store, the drops lying on the ground, unit pathing and the builder job
## board. Everything here runs on fixed ticks, so it behaves identically
## at every game speed (section 5 of ARCHITECTURE.md).
##
## Cross-references that must survive a save are written as CELLS: building
## and unit ids are reassigned when a run loads.

## A count, idle count or bed count changed. The worker bar listens.
## (Refusals are not signals: send_miner returns the reason to its caller.)
signal changed(kind: int)
## A worker died (Stage 4: enemies). Its bed is free again.
signal unit_killed(kind: int)

## Ticks between an idle unit's decisions (a third of a second at 60 ticks/s).
## Staggered per unit, so idle units never all pathfind on the same tick.
const THINK_INTERVAL := 20
const WORKER_HOUSE := "worker_house"
const DEPOT := "depot"

## Most drops that may lie around one mine. Once reached, its miners pause
## until someone picks some up.
var drops_per_mine_cap := 20
## Hit points restored per second per builder, times the REPAIR_RATE stat.
var repair_hp_per_second := 10.0

var store := UnitStore.new()
var drops := DropStore.new()
var pathing := UnitPathing.new()
var board := JobBoard.new()
var level: LevelGenerator
## Marked trees and chopping (Stage 2b). Optional: without it, builders never chop.
var forest: Forest
## Lava marks, cobble and the bucket (Stage 2c). Optional, like forest.
var lava: LavaWorks
## Points of interest (Stage 3b). Optional: without it, explorers only explore.
var pois: PointsOfInterest
var economy: Economy
var modifiers: ModifierSet
## "miner" / "builder" / "carrier" -> StatBlock, one per type (D7).
var type_blocks := {}
## The simulation tick, set by main.gd before each step.
var tick := 0
## Night: workers stay home, except builders, who still take repair jobs (and
## are out in the open while they do). Set by main.gd from the RunDirector.
var night := false

var _house_blocks := {}   # house building type -> StatBlock, for HOUSE_CAPACITY
var _house_mine := {}     # worker house id -> mine id
var _mine_house := {}     # mine id -> worker house id
var _progress := {}       # mine id -> float: work toward the next drop
## The run's first miner. It lives in the base and walks out to mine outside
## a mine, until it moves into a miner house: the first one built, or one it
## is sent to with a free bed.
var _commuter := UnitStore.NONE
## True once the first miner house has been built; the commuter moves into it.
var _first_house_done := false
## The mine the commuter was working when night fell, so dawn sends it back.
var _commuter_mine := UnitStore.NONE
## Point of interest id -> tick until which it counts as unreachable. An idle
## explorer re-thinks three times a second; a failed A* search over the whole
## map each time would be the most expensive thing in the simulation.
var _poi_unreachable := {}
## Ticks an unreachable point of interest is left alone before trying again.
const POI_RETRY_TICKS := 600
var _rng := RandomNumberGenerator.new()


func setup(p_level: LevelGenerator, p_economy: Economy, p_modifiers: ModifierSet,
		p_type_blocks: Dictionary) -> void:
	level = p_level
	economy = p_economy
	modifiers = p_modifiers
	type_blocks = p_type_blocks
	# Methods, not lambdas: see WorkerRoster.attach on why lambdas in a
	# RefCounted class can leak it.
	level.level_generated.connect(_on_level_generated)
	level.building_removed.connect(_on_building_removed)
	level.construction_completed.connect(_on_construction_completed)
	level.building_placed.connect(_on_building_placed)
	board.set_provider(JobBoard.Kind.BUILD, _construction_sites)
	board.set_provider(JobBoard.Kind.REPAIR, _damaged_buildings)
	board.set_provider(JobBoard.Kind.CHOP, _marked_trees)
	board.set_provider(JobBoard.Kind.COBBLE, _cobble_tiles)
	board.set_provider(JobBoard.Kind.FILL, _fill_tiles)
	board.set_position_lookup(_tile_pos, JobBoard.Kind.COBBLE)
	board.set_position_lookup(_tile_pos, JobBoard.Kind.FILL)
	board.set_position_lookup(_building_pos)


func _on_level_generated() -> void:
	pathing.rebuild(level.grid)


func clear() -> void:
	store.clear()
	_house_mine.clear()
	_mine_house.clear()
	_progress.clear()
	drops.clear()
	_commuter = UnitStore.NONE
	_first_house_done = false
	_commuter_mine = UnitStore.NONE
	_poi_unreachable.clear()
	for kind in WorkerRoster.Kind.COUNT:
		changed.emit(kind)


# --- Queries ------------------------------------------------------------------

func count(kind: int) -> int:
	return store.count(kind)


## Units of a kind standing idle and free to be given work. For miners this
## means waiting at the base, not yet assigned to a mine.
func idle_count(kind: int) -> int:
	var n := 0
	for id in store.ids_of_kind(kind):
		if _is_available(id) or (id == _commuter and _is_commuting(id)
				and store.state[id] != UnitStore.State.MINING and store.task[id] != UnitStore.Task.TO_MINE):
			n += 1
	return n


## True while the first miner still lives in the base (not moved into a miner
## house).
func is_commuter(id: int) -> bool:
	return id == _commuter and store.is_alive(id) and _is_commuting(id)


func _is_commuting(id: int) -> bool:
	return id == _commuter and store.home[id] == UnitStore.NONE


## Beds in finished houses for this kind of unit.
func beds(kind: int) -> int:
	var total := 0
	for house in _houses_for(kind):
		total += capacity(house)
	return total


## How many more of a kind can be bought right now: beds in finished houses
## (miner houses, for miners) minus every unit of that kind. The first miner
## counts too, even while it commutes from the base: otherwise, when it could
## not move into a house (its house was destroyed and rebuilt, or the house
## was out of reach), the bed it should have had was sold to a bought miner
## and the miners outnumbered the beds.
func free_beds(kind: int) -> int:
	return beds(kind) - count(kind)


func capacity(house: int) -> int:
	var type := level.store.get_type(house)
	if not _house_blocks.has(type):
		var data := level.get_building_data(type)
		var base := {}
		if data != null and data.beds > 0:
			base[Stats.Id.HOUSE_CAPACITY] = float(data.beds)
		_house_blocks[type] = StatBlock.new(modifiers,
			data.tags if data != null else PackedStringArray(), base)
	return int(round(_house_blocks[type].get_value(Stats.Id.HOUSE_CAPACITY)))


func residents(house: int) -> int:
	var n := 0
	for id in store.size():
		if store.is_alive(id) and store.home[id] == house:
			n += 1
	return n


## Drops from this mine still lying on the ground.
func drops_at(mine: int) -> int:
	return drops.count_from(mine)


func house_of_mine(mine: int) -> int:
	return int(_mine_house.get(mine, UnitStore.NONE))


# --- Spawning -----------------------------------------------------------------

## The free start of every run: a builder house and a carrier house next to
## the base, a builder and a carrier inside them, and the first miner, who
## waits in the base (see _commuter). Called when the base is placed.
func start_run_kit() -> void:
	var base := _base_id()
	if base == UnitStore.NONE:
		return
	for type in ["builder_house", "carrier_house"]:
		var cell := _free_cell_near(level.base_cell, type, 4)
		if cell != LevelGenerator.INVALID_CELL:
			level.place_building(type, cell)
	spawn_bought(WorkerRoster.Kind.BUILDER)
	spawn_bought(WorkerRoster.Kind.CARRIER)
	_commuter = spawn_bought(WorkerRoster.Kind.MINER)


## Adds one unit, as if bought. Builders and carriers move into a house with a
## free bed; miners wait inside the base until sent to a mine. Either way the
## unit starts inside and is not drawn until it has something to do. Returns the id, or
## NONE if there is no base yet.
func spawn_bought(kind: int) -> int:
	var base := _base_id()
	if base == UnitStore.NONE:
		return UnitStore.NONE
	var home := UnitStore.NONE
	if kind != WorkerRoster.Kind.MINER:
		home = _house_with_free_bed(kind)
	var at := _spot_next_to(home if home != UnitStore.NONE else base)
	var id := store.spawn(kind, at, home, _stat(kind, Stats.Id.MAX_HEALTH), tick)
	changed.emit(kind)
	return id


# --- Miners -------------------------------------------------------------------

## Sends a miner to a mine. Returns "" on success, or the reason it was refused.
##
## A mine with a miner house that has a free bed: the nearest idle bought
## miner moves in (or, with none idle, the first miner). A mine without one:
## only the first miner can work it, mining outside. Miner houses are crafted
## and placed next to a mine by the player; they are never ordered from here.
func send_miner(mine: int) -> String:
	if not level.store.is_alive(mine) or ResourceKind.id_from_source(level.store.get_type(mine)) == -1 \
			or not level.store.get_type(mine).begins_with("mine_"):
		return "That is not a mine."
	var house := house_of_mine(mine)
	if not level.store.is_alive(house):
		house = UnitStore.NONE
	var bed_free := house != UnitStore.NONE and residents(house) < capacity(house)
	var commuter_free := is_commuter(_commuter)

	if bed_free:
		var miner := _nearest_available(WorkerRoster.Kind.MINER, _building_pos(mine))
		if miner == UnitStore.NONE and commuter_free:
			miner = _commuter
		if miner == UnitStore.NONE:
			return "No idle miners. Buy one in the shop."
		return _move_in(miner, house)

	if commuter_free:
		return _send_commuter_outside(mine)
	if _nearest_available(WorkerRoster.Kind.MINER, _building_pos(mine)) == UnitStore.NONE:
		return "No idle miners. Buy one in the shop."
	if house != UnitStore.NONE:
		return "This mine's house is full."
	return "Build a miner house next to this mine first."


func _move_in(id: int, house: int) -> String:
	var cells := _cells_to(_cell_of(id), house)
	if cells.is_empty():
		return "Can't reach this mine yet."
	store.home[id] = house
	store.target[id] = UnitStore.NONE
	_walk_cells(id, cells, UnitStore.Task.TO_MINE_HOUSE)
	changed.emit(WorkerRoster.Kind.MINER)
	return ""


func _send_commuter_outside(mine: int) -> String:
	var id := _commuter
	if store.state[id] == UnitStore.State.MINING and store.target[id] == mine:
		return ""   # already mining here
	var cells := _cells_to(_cell_of(id), mine)
	if cells.is_empty():
		return "Can't reach this mine yet."
	store.target[id] = mine
	_walk_cells(id, cells, UnitStore.Task.TO_MINE)
	changed.emit(WorkerRoster.Kind.MINER)
	return ""


## A miner house was placed: link it to the mine it touches that has none.
## (can_place already made sure there is one.)
func _on_building_placed(type: String, cell: Vector2i) -> void:
	if type != WORKER_HOUSE:
		return
	var house := level.grid.get_occupant(cell)
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			var c := Vector2i(x, y)
			if not level.grid.in_bounds(c):
				continue
			var m := level.grid.get_occupant(c)
			if level.store.is_alive(m) and level.store.get_type(m).begins_with("mine_") \
					and not _mine_house.has(m):
				_house_mine[house] = m
				_mine_house[m] = house
				return


# --- Harm (Stage 4) -----------------------------------------------------------

## True while the unit is out in the open, where enemies can reach it. Inside a
## house, the base, or stationed at a mine, it is safe.
func is_exposed(id: int) -> bool:
	return store.is_alive(id) and store.inside[id] == 0 \
		and store.state[id] != UnitStore.State.STATIONED


## Full health for this kind of unit (the MAX_HEALTH stat).
func max_health(kind: int) -> float:
	return _stat(kind, Stats.Id.MAX_HEALTH)


## Enemy damage. Returns true on the hit that kills it.
func damage_unit(id: int, amount: float) -> bool:
	if not is_exposed(id):
		return false
	store.hp[id] -= amount
	if store.hp[id] > 0.0:
		return false
	kill_unit(id)
	return true


## Gone for good: what it carried is lost, what it had claimed is released,
## and its bed is free for a new one from the shop.
func kill_unit(id: int) -> void:
	if not store.is_alive(id):
		return
	var kind: int = store.kind[id]
	_release_drop(id)
	if id == _commuter:
		_commuter = UnitStore.NONE
		_commuter_mine = UnitStore.NONE
	store.despawn(id)
	changed.emit(kind)
	unit_killed.emit(kind)


# --- Explorers ----------------------------------------------------------------

## Sends an explorer toward a tile, fog or not. Returns "" on success, or why
## not. It walks as far toward the tile as the ground allows (a click on water
## ends at the shore), stopping on the way at any point of interest it spots.
func send_explorer(cell: Vector2i) -> String:
	if count(WorkerRoster.Kind.EXPLORER) == 0:
		return "You have no explorers. Buy one in the shop."
	if night:
		return "Explorers don't go out at night."
	if not level.grid.in_bounds(cell):
		return "That is off the map."
	# An explorer with no errand first, then any not busy opening something;
	# nearest to the spot either way.
	var best := UnitStore.NONE
	var best_score := INF
	var target := level.cell_to_world(cell)
	for id in store.ids_of_kind(WorkerRoster.Kind.EXPLORER):
		if store.state[id] == UnitStore.State.OPENING:
			continue
		var score := store.pos[id].distance_squared_to(target)
		if store.goal[id] != UnitStore.NONE:
			score += 1e12
		if score < best_score:
			best = id
			best_score = score
	if best == UnitStore.NONE:
		return "Your explorer is busy. Try again in a moment."
	if pathing.cells_toward(_cell_of(best), cell).size() <= 1:
		return "Your explorer can't get any closer to there."
	store.goal[best] = level.grid.index(cell)
	# On its way to a point of interest: finish that first, the goal waits.
	if not (store.state[best] == UnitStore.State.WALKING and store.task[best] == UnitStore.Task.TO_POI):
		store.state[best] = UnitStore.State.IDLE
		store.task[best] = UnitStore.Task.NONE
		store.think_at[best] = tick
	changed.emit(WorkerRoster.Kind.EXPLORER)
	return ""


## A point of interest came into view. Explorers out exploring stop and
## reconsider, which sends the nearest one on a detour; idle ones at home go
## too (a watchtower may have spotted it).
func on_poi_spotted(_poi: int = -1, _type: String = "") -> void:
	for id in store.ids_of_kind(WorkerRoster.Kind.EXPLORER):
		var st: int = store.state[id]
		if st == UnitStore.State.IDLE or (st == UnitStore.State.WALKING
				and store.task[id] in [UnitStore.Task.TO_EXPLORE, UnitStore.Task.GO_HOME]):
			store.state[id] = UnitStore.State.IDLE
			store.task[id] = UnitStore.Task.NONE
			store.think_at[id] = tick


## Explorer: walk to the nearest spotted point of interest no other explorer
## is already seeing to. Returns false if there is none it can reach.
func _go_open_poi(id: int) -> bool:
	if pois == null:
		return false
	var from := _cell_of(id)
	var here := store.pos[id]
	var candidates := Array(pois.waiting())
	candidates.sort_custom(func(a, b): return _building_pos(a).distance_squared_to(here) \
		< _building_pos(b).distance_squared_to(here))
	for poi in candidates:
		if int(_poi_unreachable.get(poi, -1)) > tick or _poi_taken(poi, id):
			continue
		var cells := _cells_to(from, poi)
		if cells.is_empty():
			_poi_unreachable[poi] = tick + POI_RETRY_TICKS
			continue
		store.target[id] = poi
		_walk_cells(id, cells, UnitStore.Task.TO_POI)
		return true
	return false


## True if another explorer is walking to, or opening, this point of interest.
func _poi_taken(poi: int, except: int) -> bool:
	for other in store.ids_of_kind(WorkerRoster.Kind.EXPLORER):
		if other != except and store.target[other] == poi and (store.state[other] == UnitStore.State.OPENING
				or (store.state[other] == UnitStore.State.WALKING and store.task[other] == UnitStore.Task.TO_POI)):
			return true
	return false


## Explorer: on toward the tile it was sent to. Returns false (and forgets the
## goal) once it is as close as it can get.
func _head_for_goal(id: int) -> bool:
	var goal: int = store.goal[id]
	if goal == UnitStore.NONE:
		return false
	var cells := pathing.cells_toward(_cell_of(id), level.grid.cell_at(goal))
	if cells.size() <= 1:
		store.goal[id] = UnitStore.NONE   # arrived, or this is as near as it gets
		changed.emit(WorkerRoster.Kind.EXPLORER)
		return false
	_walk_cells(id, cells, UnitStore.Task.TO_EXPLORE)
	return true


func _finish_opening(id: int) -> void:
	var poi: int = store.target[id]
	store.target[id] = UnitStore.NONE
	store.state[id] = UnitStore.State.IDLE
	store.think_at[id] = tick
	if pois != null:
		pois.open(poi)   # may remove the building; nothing here refers to it any more


# --- Day and night ------------------------------------------------------------

## Dusk: everyone heads home. Builders keep repairing (they re-decide on their
## next think), carriers deliver what they are carrying first, and the
## commuter remembers its mine so it can go back at dawn.
func on_night_started() -> void:
	for id in store.size():
		if not store.is_alive(id) or store.state[id] == UnitStore.State.STATIONED:
			continue
		if store.kind[id] == WorkerRoster.Kind.MINER and is_commuter(id) \
				and store.state[id] == UnitStore.State.MINING:
			_commuter_mine = store.target[id]
			store.target[id] = UnitStore.NONE
			store.state[id] = UnitStore.State.IDLE
		if store.state[id] == UnitStore.State.WORKING and store.job[id] != JobBoard.Kind.REPAIR:
			_stop_working(id)   # a half-built site keeps its progress
		if store.kind[id] == WorkerRoster.Kind.EXPLORER and store.state[id] == UnitStore.State.WALKING \
				and store.task[id] != UnitStore.Task.GO_HOME:
			# Turn back now rather than walk on into the dark. The goal is kept:
			# it sets out again at dawn, like the commuter.
			store.state[id] = UnitStore.State.IDLE
			store.task[id] = UnitStore.Task.NONE
			store.target[id] = UnitStore.NONE
		if store.state[id] == UnitStore.State.IDLE:
			store.think_at[id] = tick   # decide again now, which sends them home


## Dawn: the commuter goes back to the mine it was working last night, unless
## the player gave it another mine overnight or it moved into a house.
func on_day_started() -> void:
	var mine := _commuter_mine
	_commuter_mine = UnitStore.NONE
	if mine == UnitStore.NONE or not is_commuter(_commuter):
		return
	if not level.store.is_alive(mine):
		return   # the mine is gone; the miner waits in the base
	if store.state[_commuter] == UnitStore.State.MINING \
			or store.task[_commuter] == UnitStore.Task.TO_MINE:
		return   # already sent somewhere
	_send_commuter_outside(mine)


# --- Simulation ---------------------------------------------------------------

func step(dt: float) -> void:
	for id in store.size():
		if not store.is_alive(id):
			continue
		match store.state[id]:
			UnitStore.State.WALKING:
				_move(id, dt)
			UnitStore.State.WORKING:
				_work(id, dt)
			UnitStore.State.WAITING:
				if tick >= store.think_at[id]:
					store.think_at[id] = tick + THINK_INTERVAL
					var house: int = store.home[id]
					if level.store.is_alive(house) and level.store.is_complete(house):
						store.state[id] = UnitStore.State.STATIONED
			UnitStore.State.IDLE:
				if tick >= store.think_at[id]:
					store.think_at[id] = tick + THINK_INTERVAL
					_think(id)
			UnitStore.State.OPENING:
				if tick >= store.think_at[id]:
					_finish_opening(id)
	_gather(dt)


## By day, builders: build > repair > fill > cobble > chop, then go home;
## carriers fetch drops, then go home.
##
## At night everyone stays home, with one exception: builders still repair
## damaged buildings, which means leaving the house to do it.
## Miners: to their mine's home if they have one, else home (the commuter's
## house by the base, or the base itself for miners not yet sent).
func _think(id: int) -> void:
	if store.carry[id] > 0:
		_deliver(id)
		return
	match store.kind[id]:
		WorkerRoster.Kind.BUILDER:
			if not _take_job(id, [JobBoard.Kind.REPAIR] if night else []):
				_go_home_if_away(id)
		WorkerRoster.Kind.CARRIER:
			if night or not _take_drop(id):
				_go_home_if_away(id)
		WorkerRoster.Kind.MINER:
			if night and is_commuter(id):
				_go_home_if_away(id)   # the commuter sleeps in the base
				return
			var house: int = store.home[id]
			if _house_mine.has(house) and level.store.is_alive(house):
				var cells := _cells_to(_cell_of(id), house)
				if not cells.is_empty():
					_walk_cells(id, cells, UnitStore.Task.TO_MINE_HOUSE)
					return
			store.home[id] = UnitStore.NONE   # lost or unreachable: wait in the base
			_go_home_if_away(id)
		WorkerRoster.Kind.EXPLORER:
			# Points of interest in sight first (the detour), then the spot it
			# was sent to, then home. Never out at night.
			if night or not (_go_open_poi(id) or _head_for_goal(id)):
				_go_home_if_away(id)


func _move(id: int, dt: float) -> void:
	var points: PackedVector2Array = store.path[id]
	var i: int = store.path_i[id]
	var p: Vector2 = store.pos[id]
	var remaining := _stat(store.kind[id], Stats.Id.MOVE_SPEED) * dt
	while remaining > 0.0 and i < points.size():
		var to := points[i]
		var d := p.distance_to(to)
		if d <= remaining:
			p = to
			remaining -= d
			i += 1
		else:
			var dir := (to - p) / d
			p += dir * remaining
			remaining = 0.0
			if absf(dir.x) > 0.2:
				store.facing_left[id] = 1 if dir.x < 0.0 else 0
	store.pos[id] = p
	store.path_i[id] = i
	if i >= points.size():
		_arrive(id)


func _arrive(id: int) -> void:
	var task: int = store.task[id]
	store.task[id] = UnitStore.Task.NONE
	store.state[id] = UnitStore.State.IDLE
	match task:
		UnitStore.Task.TO_MINE_HOUSE:
			var house: int = store.home[id]
			if level.store.is_alive(house):
				store.state[id] = UnitStore.State.STATIONED if level.store.is_complete(house) \
					else UnitStore.State.WAITING
			else:
				store.home[id] = UnitStore.NONE
		UnitStore.Task.TO_JOB:
			if JobBoard.is_tile_job(store.job[id]) or level.store.is_alive(store.target[id]):
				store.state[id] = UnitStore.State.WORKING   # tile jobs re-check in _work_tile
			else:
				store.target[id] = UnitStore.NONE
				store.job[id] = UnitStore.NONE
		UnitStore.Task.TO_MINE:
			if level.store.is_alive(store.target[id]):
				store.state[id] = UnitStore.State.MINING
			else:
				store.target[id] = UnitStore.NONE
		UnitStore.Task.TO_PICKUP:
			_pickup(id)
		UnitStore.Task.TO_DROPOFF:
			_dropoff(id)
		UnitStore.Task.GO_HOME, UnitStore.Task.FLEE:
			store.inside[id] = 1
		UnitStore.Task.TO_POI:
			var poi: int = store.target[id]
			if pois != null and pois.is_waiting(poi):
				store.state[id] = UnitStore.State.OPENING
				store.think_at[id] = tick + int(round(pois.open_seconds / GameClock.TICK_DELTA))
			else:
				store.target[id] = UnitStore.NONE   # someone got there first
		# TO_EXPLORE needs nothing: idle, it re-thinks and heads on or home.
	# An idle unit decides again at once, instead of standing for a think tick.
	if store.state[id] == UnitStore.State.IDLE:
		store.think_at[id] = tick
	changed.emit(store.kind[id])


# --- Builders -----------------------------------------------------------------

func _take_job(id: int, only: Array = []) -> bool:
	var from := _cell_of(id)
	var tries := 0
	for job in board.candidates(store.pos[id], only):
		var kind: int = job[0]
		var b: int = job[1]
		if _workers_on(b, kind) >= JobBoard.max_workers(kind):
			continue
		var cells: Array[Vector2i]
		if JobBoard.is_tile_job(kind):
			# Stand next to the tile: lava and water can't be stood on.
			cells = pathing.cells_to_building(from, level.grid.cell_at(b), Vector2i.ONE)
		else:
			cells = _cells_to(from, b)
		tries += 1
		if not cells.is_empty():
			store.target[id] = b
			store.job[id] = kind
			_walk_cells(id, cells, UnitStore.Task.TO_JOB)
			return true
		if tries >= 5:
			break
	return false


func _work(id: int, dt: float) -> void:
	var b: int = store.target[id]
	if JobBoard.is_tile_job(store.job[id]):
		_work_tile(id, dt)
		return
	if not level.store.is_alive(b):
		_stop_working(id)
		return
	if forest != null and forest.is_tree(b):
		if not forest.is_marked(b):
			_stop_working(id)   # unmarked while being chopped
			return
		var cell := level.store.get_cell(b)
		var chop := _stat(WorkerRoster.Kind.BUILDER, Stats.Id.BUILD_SPEED) * dt
		if forest.chop(b, chop, tick):
			# The tree is a stump now (and this builder already let go of it).
			for i in forest.wood_per_tree:
				_pop_drop_at(cell, Vector2i.ONE, ResourceKind.Id.WOOD, DropStore.NONE)
		return
	if not level.store.is_complete(b):
		var work := _stat(WorkerRoster.Kind.BUILDER, Stats.Id.BUILD_SPEED) * dt
		if level.add_construction_work(b, work):
			_stop_working(id)
	elif level.store.get_health(b) < level.store.get_max_health(b):
		var hp := repair_hp_per_second * _stat(WorkerRoster.Kind.BUILDER, Stats.Id.REPAIR_RATE) * dt
		if level.store.heal(b, hp) >= level.store.get_max_health(b):
			_stop_working(id)
	else:
		_stop_working(id)


## Tile jobs: cobble a marked lava tile, or fill the bucket at the water.
func _work_tile(id: int, dt: float) -> void:
	var i: int = store.target[id]
	var work := _stat(WorkerRoster.Kind.BUILDER, Stats.Id.BUILD_SPEED) * dt
	if lava == null:
		_stop_working(id)
	elif store.job[id] == JobBoard.Kind.COBBLE:
		if not lava.is_marked(i) or not lava.has_water_bucket() or lava.cobble(i, work):
			_stop_working(id)   # done, or unmarked meanwhile
	elif store.job[id] == JobBoard.Kind.FILL:
		if lava.has_water_bucket() or lava.fill(work):
			_stop_working(id)
	else:
		_stop_working(id)


func _stop_working(id: int) -> void:
	store.job[id] = UnitStore.NONE
	store.target[id] = UnitStore.NONE
	store.state[id] = UnitStore.State.IDLE
	store.think_at[id] = tick


## Builders working, or on their way to work, on this job. Tile jobs and
## building jobs never count against each other (their ids are different
## things: tile indices and building ids).
func _workers_on(b: int, kind: int) -> int:
	var tile := JobBoard.is_tile_job(kind)
	var n := 0
	if kind == JobBoard.Kind.FILL:
		# There is one bucket: every water tile is the same job.
		for id in store.size():
			if store.is_alive(id) and store.job[id] == JobBoard.Kind.FILL:
				n += 1
		return n
	for id in store.size():
		if store.is_alive(id) and store.target[id] == b and store.kind[id] == WorkerRoster.Kind.BUILDER \
				and JobBoard.is_tile_job(store.job[id]) == tile \
				and (not tile or store.job[id] == kind):
			n += 1
	return n


func _cobble_tiles() -> PackedInt32Array:
	return lava.cobble_jobs() if lava != null else PackedInt32Array()


func _fill_tiles() -> PackedInt32Array:
	return lava.fill_jobs() if lava != null else PackedInt32Array()


func _tile_pos(i: int) -> Vector2:
	return level.cell_to_world(level.grid.cell_at(i))


func _construction_sites() -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in level.store.alive_ids():
		if not level.store.is_complete(b):
			out.append(b)
	return out


func _marked_trees() -> PackedInt32Array:
	return forest.marked_trees() if forest != null else PackedInt32Array()


func _damaged_buildings() -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in level.store.alive_ids():
		if level.store.is_complete(b) and level.store.get_health(b) < level.store.get_max_health(b):
			out.append(b)
	return out


func _on_construction_completed(b: int) -> void:
	for id in store.size():
		if store.is_alive(id) and store.home[id] == b and store.state[id] == UnitStore.State.WAITING:
			store.state[id] = UnitStore.State.STATIONED
	# The first miner house built: the first miner moves in, wherever it is.
	if _house_mine.has(b) and not _first_house_done:
		_first_house_done = true
		if is_commuter(_commuter) and residents(b) < capacity(b):
			_move_in(_commuter, b)
	var data := level.get_building_data(level.store.get_type(b))
	if data != null and data.is_house:
		changed.emit(data.house_for)


# --- Miners gathering, drops, hauling ----------------------------------------

## Stationed miners, and the commuter mining outside, work toward the next drop. Each whole unit of work pops one
## resource out of the mine; a mine with too many drops lying around pauses.
##
## **Mines stand idle at night**, even for a miner that moved into its house
## after dusk: nothing is produced until dawn. Part-finished work is kept, so a
## night costs exactly the night, not the progress made before it.
func _gather(dt: float) -> void:
	if night:
		return
	var miners_at := {}   # mine id -> miners working it
	for id in store.size():
		if not store.is_alive(id):
			continue
		var mine := UnitStore.NONE
		if store.state[id] == UnitStore.State.STATIONED:
			mine = int(_house_mine.get(store.home[id], UnitStore.NONE))
		elif store.state[id] == UnitStore.State.MINING:
			mine = store.target[id]
		if mine != UnitStore.NONE:
			miners_at[mine] = int(miners_at.get(mine, 0)) + 1
	if miners_at.is_empty():
		return
	var rate := _stat(WorkerRoster.Kind.MINER, Stats.Id.GATHER_RATE)
	for mine in miners_at:
		if not level.store.is_alive(mine):
			continue
		var work: float = float(_progress.get(mine, 0.0)) + miners_at[mine] * rate * dt
		while work >= 1.0:
			if drops.count_from(mine) >= drops_per_mine_cap or not _pop_drop(mine):
				work = 1.0   # full: wait here until something is picked up
				break
			work -= 1.0
		_progress[mine] = work


## One resource bounces out of the mine onto a random walkable tile near it.
## Returns false if there is nowhere for it to land.
func _pop_drop(mine: int) -> bool:
	var kind := ResourceKind.id_from_source(level.store.get_type(mine))
	if kind == -1:
		return false
	return _pop_drop_at(level.store.get_cell(mine), level.store.get_size(mine), kind, mine)


## A drop of `kind` bounces from the footprint at origin/size onto a random free,
## walkable tile within 2 of it. `source` is the mine it counts against (its
## cap), or NONE. Returns false if there is nowhere for it to land.
func _pop_drop_at(origin: Vector2i, size: Vector2i, kind: int, source: int) -> bool:
	var spots: Array[Vector2i] = []
	for y in range(origin.y - 2, origin.y + size.y + 2):
		for x in range(origin.x - 2, origin.x + size.x + 2):
			var c := Vector2i(x, y)
			if level.grid.in_bounds(c) and not level.grid.is_occupied(c) \
					and level.grid.is_passable_at(level.grid.index(c)):
				spots.append(c)
	if spots.is_empty():
		return false
	var cell := spots[_rng.randi() % spots.size()]
	var jitter := Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
	var from := level.cell_to_world(origin) + level.get_footprint_offset(size)
	drops.spawn(kind, from, level.cell_to_world(cell) + jitter, source, tick)
	return true


## Claims the nearest landed drop nobody else is fetching and walks to it.
func _take_drop(id: int) -> bool:
	if drops.count() == 0:
		return false
	var candidates := []
	for d in drops.size():
		if drops.is_alive(d) and drops.claimed_by[d] == UnitStore.NONE and drops.has_landed(d, tick):
			candidates.append([store.pos[id].distance_squared_to(drops.pos[d]), d])
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var from := _cell_of(id)
	for n in mini(candidates.size(), 3):
		var d: int = candidates[n][1]
		var to := level.world_to_cell(drops.pos[d])
		var cells: Array[Vector2i] = [to]
		if from != to:
			cells = pathing.cells_between(from, to)
		if cells.is_empty():
			continue
		drops.claimed_by[d] = id
		store.fetch[id] = d
		_walk_cells(id, cells, UnitStore.Task.TO_PICKUP)
		return true
	return false


## At the drop: take it, plus any other landed drops of the same resource
## lying close by, up to what this unit can carry. Then head for the base.
func _pickup(id: int) -> void:
	var d: int = store.fetch[id]
	store.fetch[id] = UnitStore.NONE
	if not drops.is_alive(d) or drops.claimed_by[d] != id:
		return
	var room := maxi(int(_stat(store.kind[id], Stats.Id.CARRY_CAPACITY)), 1)
	var kind: int = drops.kind[d]
	var here: Vector2 = drops.pos[d]
	drops.despawn(d)
	var taken := 1
	for other in drops.size():
		if taken >= room:
			break
		if drops.is_alive(other) and drops.kind[other] == kind \
				and drops.claimed_by[other] == UnitStore.NONE and drops.has_landed(other, tick) \
				and drops.pos[other].distance_to(here) <= 48.0:
			drops.despawn(other)
			taken += 1
	store.carry[id] = taken
	store.carry_kind[id] = kind
	_deliver(id)


## Walks what the unit carries to the nearest drop-off: the base or a finished
## depot, whichever is closer in a straight line. Resources count the moment
## they arrive at either.
func _deliver(id: int) -> void:
	var to := _nearest_dropoff(store.pos[id])
	if to == UnitStore.NONE:
		return
	if _is_beside(id, to):
		_dropoff(id)
		store.think_at[id] = tick
		return
	var cells := _cells_to(_cell_of(id), to)
	if cells.is_empty() and to != _base_id():
		to = _base_id()   # that depot is cut off: fall back to the base
		cells = _cells_to(_cell_of(id), to)
	if not cells.is_empty():
		_walk_cells(id, cells, UnitStore.Task.TO_DROPOFF)


func _nearest_dropoff(from: Vector2) -> int:
	var best := _base_id()
	var best_d := INF if best == UnitStore.NONE else from.distance_squared_to(_building_pos(best))
	for b in level.store.alive_ids():
		if level.store.get_type(b) != DEPOT or not level.store.is_complete(b):
			continue
		var d := from.distance_squared_to(_building_pos(b))
		if d < best_d:
			best = b
			best_d = d
	return best


func _dropoff(id: int) -> void:
	if store.carry[id] > 0 and store.carry_kind[id] >= 0:
		economy.add(store.carry_kind[id], store.carry[id])
	store.carry[id] = 0


## A unit that stops fetching lets go of its drop, so someone else can take it.
func _release_drop(id: int) -> void:
	var d: int = store.fetch[id]
	store.fetch[id] = UnitStore.NONE
	if drops.is_alive(d) and drops.claimed_by[d] == id:
		drops.claimed_by[d] = UnitStore.NONE


# --- Losing buildings ---------------------------------------------------------

func _on_building_removed(b: int, _type: String, _cell: Vector2i) -> void:
	for id in store.size():
		if not store.is_alive(id):
			continue
		if store.target[id] == b and not JobBoard.is_tile_job(store.job[id]):
			store.target[id] = UnitStore.NONE
			store.job[id] = UnitStore.NONE
			if store.state[id] != UnitStore.State.STATIONED:
				store.state[id] = UnitStore.State.IDLE
				store.think_at[id] = tick
		if store.home[id] == b:
			store.home[id] = UnitStore.NONE
			store.inside[id] = 0   # the building around it is gone
			if store.kind[id] == WorkerRoster.Kind.MINER:
				# Safe inside; exposed the moment the house falls. Run for the base,
				# or, for the first miner, back to its old home by the base.
				if store.state[id] == UnitStore.State.STATIONED or store.state[id] == UnitStore.State.WAITING:
					store.state[id] = UnitStore.State.IDLE
				var cells := _cells_to(_cell_of(id), _base_id())
				if not cells.is_empty():
					_walk_cells(id, cells, UnitStore.Task.FLEE)
			else:
				store.state[id] = UnitStore.State.IDLE
				store.think_at[id] = tick
			changed.emit(store.kind[id])
	_progress.erase(b)
	_poi_unreachable.erase(b)
	if _house_mine.has(b):
		_mine_house.erase(_house_mine[b])
		_house_mine.erase(b)
	if _mine_house.has(b):
		_house_mine.erase(_mine_house[b])
		_mine_house.erase(b)
	# Drops outlive their mine; they just stop counting toward its cap.
	for d in drops.size():
		if drops.is_alive(d) and drops.mine[d] == b:
			drops.mine[d] = DropStore.NONE


# --- Saving -------------------------------------------------------------------

## Units, worker houses and drops, with every reference written as a cell.
## Claims and trips in progress are not saved: units decide again on load.
func get_save_data() -> Dictionary:
	var units := []
	for id in store.alive_ids():
		var h: int = store.home[id]
		var home_cell = null
		if level.store.is_alive(h):
			home_cell = level.store.get_cell(h)
		units.append({
			"kind": WorkerRoster.key_of(store.kind[id]),
			"pos": store.pos[id],
			"home": home_cell,
			"stationed": store.state[id] == UnitStore.State.STATIONED,
			"commuter": id == _commuter,
			"mining": level.store.get_cell(store.target[id]) \
				if store.state[id] == UnitStore.State.MINING and level.store.is_alive(store.target[id]) \
				else Vector2i(-1, -1),
			"inside": store.inside[id] == 1,
			"goal": _goal_cell(id),
			"carry": store.carry[id],
			"carry_kind": ResourceKind.key_of(store.carry_kind[id]) if store.carry[id] > 0 else "",
			"hp": store.hp[id],
		})
	var houses := []
	for h in _house_mine:
		if level.store.is_alive(h) and level.store.is_alive(_house_mine[h]):
			houses.append({"house": level.store.get_cell(h), "mine": level.store.get_cell(_house_mine[h])})
	var progress := []
	for m in _progress:
		if level.store.is_alive(m):
			progress.append({"mine": level.store.get_cell(m), "work": float(_progress[m])})
	var dropped := []
	for d in drops.size():
		if not drops.is_alive(d):
			continue
		var m: int = drops.mine[d]
		var mine_cell = null
		if level.store.is_alive(m):
			mine_cell = level.store.get_cell(m)
		dropped.append({"kind": ResourceKind.key_of(drops.kind[d]), "pos": drops.pos[d],
			"mine": mine_cell})
	return {"units": units, "houses": houses, "drops": dropped, "progress": progress,
		"first_house_done": _first_house_done}


## Call after the level has loaded. Returns false if the save names a unit
## kind this build does not have.
func load_save_data(data: Dictionary) -> bool:
	clear()
	for entry in data.get("houses", []):
		var h := level.grid.get_occupant(entry["house"])
		var m := level.grid.get_occupant(entry["mine"])
		if level.store.is_alive(h) and level.store.is_alive(m):
			_house_mine[h] = m
			_mine_house[m] = h
	for entry in data.get("progress", []):
		var m := level.grid.get_occupant(entry["mine"])
		if level.store.is_alive(m):
			_progress[m] = float(entry["work"])
	_first_house_done = bool(data.get("first_house_done", not _house_mine.is_empty()))
	for entry in data.get("drops", []):
		var rkind := ResourceKind.id_from_key(entry["kind"])
		if rkind == -1:
			continue   # a resource this build no longer has
		var m := DropStore.NONE
		if entry["mine"] != null:
			m = level.grid.get_occupant(entry["mine"])
		# Born long ago, so it loads already landed.
		drops.spawn(rkind, entry["pos"], entry["pos"], m, tick - DropStore.BOUNCE_TICKS)
	for entry in data.get("units", []):
		var kind := WorkerRoster.KEYS_INDEX.get(entry["kind"], -1) as int
		if kind == -1:
			push_error("UnitSystem: save names an unknown unit kind '%s'." % entry["kind"])
			return false
		var home := UnitStore.NONE
		if entry["home"] != null:
			home = level.grid.get_occupant(entry["home"])
			if not level.store.is_alive(home):
				home = UnitStore.NONE
		var id := store.spawn(kind, entry["pos"], home, float(entry["hp"]), tick)
		store.inside[id] = 1 if entry.get("inside", false) else 0
		if kind == WorkerRoster.Kind.MINER and home != UnitStore.NONE:
			if entry["stationed"] and level.store.is_complete(home):
				store.state[id] = UnitStore.State.STATIONED
			# Otherwise it resumes walking to its house on its first think.
		if entry.get("commuter", false):
			_commuter = id
		var mining: Vector2i = entry.get("mining", Vector2i(-1, -1))
		if mining != Vector2i(-1, -1):
			var m := level.grid.get_occupant(mining)
			if level.store.is_alive(m):
				store.state[id] = UnitStore.State.MINING
				store.target[id] = m
		var goal = entry.get("goal", null)
		if goal != null and level.grid.in_bounds(goal):
			store.goal[id] = level.grid.index(goal)
		if int(entry["carry"]) > 0:
			store.carry[id] = int(entry["carry"])
			store.carry_kind[id] = ResourceKind.id_from_key(entry["carry_kind"])
			_deliver(id)
	for kind in WorkerRoster.Kind.COUNT:
		changed.emit(kind)
	return true


# --- Helpers ------------------------------------------------------------------

## An explorer's goal as a cell for the save, or null.
func _goal_cell(id: int) -> Variant:
	if store.goal[id] == UnitStore.NONE:
		return null
	return level.grid.cell_at(store.goal[id])


func _stat(kind: int, stat: int) -> float:
	return type_blocks[WorkerRoster.key_of(kind)].get_value(stat)


func _base_id() -> int:
	if level.base_cell == LevelGenerator.INVALID_CELL:
		return UnitStore.NONE
	return level.grid.get_occupant(level.base_cell)


func _cell_of(id: int) -> Vector2i:
	return level.world_to_cell(store.pos[id])


func _building_pos(b: int) -> Vector2:
	return level.cell_to_world(level.store.get_cell(b)) \
		+ level.get_footprint_offset(level.store.get_size(b))


func _cells_to(from: Vector2i, b: int) -> Array[Vector2i]:
	if not level.store.is_alive(b):
		return []
	return pathing.cells_to_building(from, level.store.get_cell(b), level.store.get_size(b))


func _walk_cells(id: int, cells: Array[Vector2i], task: int) -> void:
	var points := PackedVector2Array()
	for c in cells:
		points.append(level.cell_to_world(c))
	store.walk(id, points, task)


func _go_home_if_away(id: int) -> void:
	var home: int = store.home[id]
	var anchor := home if home != UnitStore.NONE and level.store.is_alive(home) else _base_id()
	if anchor == UnitStore.NONE:
		return
	# Already at the door: step inside rather than shuffle.
	if _is_beside(id, anchor):
		store.inside[id] = 1
		return
	var cells := _cells_to(_cell_of(id), anchor)
	if not cells.is_empty():
		_walk_cells(id, cells, UnitStore.Task.GO_HOME)


## True if the unit stands on or next to the building's footprint.
func _is_beside(id: int, b: int) -> bool:
	var c := _cell_of(id)
	var o := level.store.get_cell(b)
	var sz := level.store.get_size(b)
	return c.x >= o.x - 1 and c.y >= o.y - 1 and c.x <= o.x + sz.x and c.y <= o.y + sz.y


func _is_available(id: int) -> bool:
	if store.state[id] != UnitStore.State.IDLE and not (
			store.state[id] == UnitStore.State.WALKING and store.task[id] == UnitStore.Task.GO_HOME):
		return false
	# Miners: waiting in the base, not yet sent. The first miner is picked
	# separately (see send_miner), so it is not counted here.
	return store.kind[id] != WorkerRoster.Kind.MINER or (store.home[id] == UnitStore.NONE and id != _commuter)


func _nearest_available(kind: int, near: Vector2) -> int:
	var best := UnitStore.NONE
	var best_d := INF
	for id in store.ids_of_kind(kind):
		if not _is_available(id):
			continue
		var d := store.pos[id].distance_squared_to(near)
		if d < best_d:
			best = id
			best_d = d
	return best


func _houses_for(kind: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in level.store.alive_ids():
		if not level.store.is_complete(b):
			continue
		var data := level.get_building_data(level.store.get_type(b))
		if data != null and data.is_house and data.house_for == kind:
			out.append(b)
	return out


func _house_with_free_bed(kind: int) -> int:
	for house in _houses_for(kind):
		if residents(house) < capacity(house):
			return house
	return UnitStore.NONE


## A walkable tile touching a building, as a world position; the building's own
## centre if every neighbour is blocked.
func _spot_next_to(b: int) -> Vector2:
	var origin := level.store.get_cell(b)
	var size := level.store.get_size(b)
	for y in range(origin.y - 1, origin.y + size.y + 1):
		for x in range(origin.x - 1, origin.x + size.x + 1):
			var c := Vector2i(x, y)
			if level.grid.in_bounds(c) and level.grid.is_passable_at(level.grid.index(c)):
				return level.cell_to_world(c)
	return _building_pos(b)


## Nearest cell within `radius` rings of `center` where a building of `type`
## may go, or INVALID_CELL.
func _free_cell_near(center: Vector2i, type: String, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != r:
					continue
				var c := Vector2i(x, y)
				if level.grid.in_bounds(c) and level.can_place(type, c):
					return c
	return LevelGenerator.INVALID_CELL
