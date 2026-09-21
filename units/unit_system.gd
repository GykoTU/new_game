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

## Ticks between an idle unit's decisions (a third of a second at 60 ticks/s).
## Staggered per unit, so idle units never all pathfind on the same tick.
const THINK_INTERVAL := 20
const WORKER_HOUSE := "worker_house"

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
var economy: Economy
var modifiers: ModifierSet
## "miner" / "builder" / "carrier" -> StatBlock, one per type (D7).
var type_blocks := {}
## The simulation tick, set by main.gd before each step.
var tick := 0

var _house_blocks := {}   # house building type -> StatBlock, for HOUSE_CAPACITY
var _house_mine := {}     # worker house id -> mine id
var _mine_house := {}     # mine id -> worker house id
var _progress := {}       # mine id -> float: work toward the next drop
## The run's first miner lives in a miner home next to the base and walks out
## to mine outside, until it is sent to a mine whose home has a free bed.
var _commuter := UnitStore.NONE
var _commuter_house := UnitStore.NONE
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
	board.set_provider(JobBoard.Kind.BUILD, _construction_sites)
	board.set_provider(JobBoard.Kind.REPAIR, _damaged_buildings)
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
	_commuter_house = UnitStore.NONE
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


## True while the first miner still lives by the base (not moved into a mine's
## home).
func is_commuter(id: int) -> bool:
	return id == _commuter and store.is_alive(id) and _is_commuting(id)


func _is_commuting(id: int) -> bool:
	return store.home[id] == _commuter_house and _commuter_house != UnitStore.NONE


## Beds in finished houses for this kind of unit.
func beds(kind: int) -> int:
	var total := 0
	for house in _houses_for(kind):
		total += capacity(house)
	return total


## How many more of a kind can be bought right now. Miners live at their mine,
## so this is only meaningful for builders and carriers.
func free_beds(kind: int) -> int:
	return beds(kind) - count(kind)


func capacity(house: int) -> int:
	var type := level.store.get_type(house)
	if not _house_blocks.has(type):
		var data := level.get_building_data(type)
		_house_blocks[type] = StatBlock.new(modifiers, data.tags if data != null else PackedStringArray())
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

## The free start of every run: a builder house, a carrier house and a miner
## home next to the base, each with one worker inside. The miner is the
## commuter (see _commuter). Called when the base is placed.
func start_run_kit() -> void:
	var base := _base_id()
	if base == UnitStore.NONE:
		return
	for type in ["builder_house", "carrier_house", WORKER_HOUSE]:
		var cell := _free_cell_near(level.base_cell, type, 4)
		if cell != LevelGenerator.INVALID_CELL:
			level.place_building(type, cell)
			if type == WORKER_HOUSE:
				_commuter_house = level.grid.get_occupant(cell)
	spawn_bought(WorkerRoster.Kind.BUILDER)
	spawn_bought(WorkerRoster.Kind.CARRIER)
	var anchor := _commuter_house if _commuter_house != UnitStore.NONE else base
	_commuter = store.spawn(WorkerRoster.Kind.MINER, _spot_next_to(anchor), _commuter_house,
		_stat(WorkerRoster.Kind.MINER, Stats.Id.MAX_HEALTH), tick)
	changed.emit(WorkerRoster.Kind.MINER)


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
## An idle bought miner is preferred. It moves into the mine's home; if the
## mine has none yet, one is ordered (its cost paid now) as a construction
## site that a builder then builds. With no bought miner idle, the commuter
## goes instead: into the mine's home if a bed is free, otherwise it mines
## outside the mine, for free.
func send_miner(mine: int) -> String:
	if not level.store.is_alive(mine) or ResourceKind.id_from_source(level.store.get_type(mine)) == -1 \
			or not level.store.get_type(mine).begins_with("mine_"):
		return "That is not a mine."
	var house := house_of_mine(mine)
	if not level.store.is_alive(house):
		house = UnitStore.NONE
	var bed_free := house != UnitStore.NONE and residents(house) < capacity(house)

	var miner := _nearest_available(WorkerRoster.Kind.MINER, _building_pos(mine))
	if miner == UnitStore.NONE:
		if is_commuter(_commuter) and store.state[_commuter] != UnitStore.State.STATIONED:
			return _send_commuter(mine, house, bed_free)
		return "No idle miners. Buy one in the shop."
	var miner_cell := _cell_of(miner)

	if house == UnitStore.NONE:
		var cost := _home_cost()
		if not economy.can_afford(cost):
			return "A miner home here costs %s." % _describe(cost)
		var spots := level.free_cells_around(mine, WORKER_HOUSE, miner_cell)
		if spots.is_empty():
			return "There is no ground next to this mine a home can stand on."
		for c in spots:
			if not pathing.cells_between(miner_cell, c).is_empty():
				house = level.place_construction(WORKER_HOUSE, c)
				break
		if house == UnitStore.NONE:
			return "Can't reach this mine yet."
		economy.spend(cost)
		_house_mine[house] = mine
		_mine_house[mine] = house
	elif not bed_free:
		return "This mine's home is full."

	var cells := _cells_to(miner_cell, house)
	if cells.is_empty():
		return "Can't reach this mine yet."
	store.home[miner] = house
	_walk_cells(miner, cells, UnitStore.Task.TO_MINE_HOUSE)
	changed.emit(WorkerRoster.Kind.MINER)
	return ""


func _send_commuter(mine: int, house: int, bed_free: bool) -> String:
	var id := _commuter
	var from := _cell_of(id)
	if bed_free:
		var to_house := _cells_to(from, house)
		if to_house.is_empty():
			return "Can't reach this mine yet."
		store.home[id] = house   # moves in for good; its old home by the base stays empty
		store.target[id] = UnitStore.NONE
		_walk_cells(id, to_house, UnitStore.Task.TO_MINE_HOUSE)
	else:
		if store.state[id] == UnitStore.State.MINING and store.target[id] == mine:
			return ""   # already mining here
		var cells := _cells_to(from, mine)
		if cells.is_empty():
			return "Can't reach this mine yet."
		store.target[id] = mine
		_walk_cells(id, cells, UnitStore.Task.TO_MINE)
	changed.emit(WorkerRoster.Kind.MINER)
	return ""


func _home_cost() -> Dictionary:
	var data := level.get_building_data(WORKER_HOUSE)
	return data.cost if data != null else {}


static func _describe(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append("%d %s" % [cost[k], ResourceKind.display_of(k)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


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
	_gather(dt)


## Builders: build > repair > (cobble > chop, later) > go home.
## Carriers: fetch drops > go home. Only carriers carry resources.
## Miners: to their mine's home if they have one, else home (the commuter's
## house by the base, or the base itself for miners not yet sent).
func _think(id: int) -> void:
	if store.carry[id] > 0:
		_deliver(id)
		return
	match store.kind[id]:
		WorkerRoster.Kind.BUILDER:
			if not _take_job(id):
				_go_home_if_away(id)
		WorkerRoster.Kind.CARRIER:
			if not _take_drop(id):
				_go_home_if_away(id)
		WorkerRoster.Kind.MINER:
			var house: int = store.home[id]
			if _house_mine.has(house) and level.store.is_alive(house):
				var cells := _cells_to(_cell_of(id), house)
				if not cells.is_empty():
					_walk_cells(id, cells, UnitStore.Task.TO_MINE_HOUSE)
					return
			if not _is_commuting(id):
				store.home[id] = UnitStore.NONE   # lost or unreachable: wait in the base
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
			if level.store.is_alive(store.target[id]):
				store.state[id] = UnitStore.State.WORKING
			else:
				store.target[id] = UnitStore.NONE
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
	# An idle unit decides again at once, instead of standing for a think tick.
	if store.state[id] == UnitStore.State.IDLE:
		store.think_at[id] = tick
	changed.emit(store.kind[id])


# --- Builders -----------------------------------------------------------------

func _take_job(id: int) -> bool:
	var from := _cell_of(id)
	var tries := 0
	for job in board.candidates(store.pos[id]):
		var b: int = job[1]
		if _workers_on(b) >= JobBoard.MAX_WORKERS:
			continue
		var cells := _cells_to(from, b)
		tries += 1
		if not cells.is_empty():
			store.target[id] = b
			_walk_cells(id, cells, UnitStore.Task.TO_JOB)
			return true
		if tries >= 5:
			break
	return false


func _work(id: int, dt: float) -> void:
	var b: int = store.target[id]
	if not level.store.is_alive(b):
		_stop_working(id)
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


func _stop_working(id: int) -> void:
	store.target[id] = UnitStore.NONE
	store.state[id] = UnitStore.State.IDLE
	store.think_at[id] = tick


func _workers_on(b: int) -> int:
	var n := 0
	for id in store.size():
		if store.is_alive(id) and store.target[id] == b and store.kind[id] == WorkerRoster.Kind.BUILDER:
			n += 1
	return n


func _construction_sites() -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in level.store.alive_ids():
		if not level.store.is_complete(b):
			out.append(b)
	return out


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
	var data := level.get_building_data(level.store.get_type(b))
	if data != null and data.is_house:
		changed.emit(data.house_for)


# --- Miners gathering, drops, hauling ----------------------------------------

## Stationed miners, and the commuter mining outside, work toward the next drop. Each whole unit of work pops one
## resource out of the mine; a mine with too many drops lying around pauses.
func _gather(dt: float) -> void:
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
	var origin := level.store.get_cell(mine)
	var size := level.store.get_size(mine)
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
	drops.spawn(kind, _building_pos(mine), level.cell_to_world(cell) + jitter, mine, tick)
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


## Walks what the unit carries to the base (the nearest depot, from 2b).
func _deliver(id: int) -> void:
	var base := _base_id()
	if base == UnitStore.NONE:
		return
	var cells := _cells_to(_cell_of(id), base)
	if not cells.is_empty():
		_walk_cells(id, cells, UnitStore.Task.TO_DROPOFF)
	elif _is_beside(id, base):
		_dropoff(id)


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
		if store.target[id] == b:
			store.target[id] = UnitStore.NONE
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
				var refuge := _base_id()
				if id == _commuter and b != _commuter_house and level.store.is_alive(_commuter_house):
					store.home[id] = _commuter_house
					refuge = _commuter_house
				var cells := _cells_to(_cell_of(id), refuge)
				if not cells.is_empty():
					_walk_cells(id, cells, UnitStore.Task.FLEE)
			else:
				store.state[id] = UnitStore.State.IDLE
				store.think_at[id] = tick
			changed.emit(store.kind[id])
	if b == _commuter_house:
		_commuter_house = UnitStore.NONE   # the first miner now just waits in the base
	_progress.erase(b)
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
	var commuter_house = null
	if level.store.is_alive(_commuter_house):
		commuter_house = level.store.get_cell(_commuter_house)
	return {"units": units, "houses": houses, "drops": dropped, "progress": progress,
		"commuter_house": commuter_house}


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
	if data.get("commuter_house") != null:
		_commuter_house = level.grid.get_occupant(data["commuter_house"])
		if not level.store.is_alive(_commuter_house):
			_commuter_house = UnitStore.NONE
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
		if int(entry["carry"]) > 0:
			store.carry[id] = int(entry["carry"])
			store.carry_kind[id] = ResourceKind.id_from_key(entry["carry_kind"])
			var cells := _cells_to(_cell_of(id), _base_id())
			if not cells.is_empty():
				_walk_cells(id, cells, UnitStore.Task.TO_DROPOFF)
	for kind in WorkerRoster.Kind.COUNT:
		changed.emit(kind)
	return true


# --- Helpers ------------------------------------------------------------------

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
	return store.kind[id] != WorkerRoster.Kind.MINER or store.home[id] == UnitStore.NONE


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
