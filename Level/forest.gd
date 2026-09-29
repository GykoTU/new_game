class_name Forest
extends RefCounted
## Plain trees: which ones the player marked for chopping, how far along each
## chop is, stumps rotting away, and new trees growing back.
##
## Builders do the chopping (JobBoard CHOP lists marked_trees()); the unit
## system calls chop() with their work and pops the wood when a tree falls.
## Fruit trees are not part of this: they are kept for fruit.
##
## Everything timed runs on simulation ticks through TimedEvents, so a loaded
## run regrows exactly what it would have.
##
## Regrowth (tuned after Stage 10): a felled tree comes back WHERE IT STOOD,
## `regrow_seconds` after it fell (its stump is gone by then). If something
## was built there, it grows on the nearest free tile instead (see
## _spot_near). The map keeps its forests where they were, including the ones
## by the base. A tree never grows next to a building (8 neighbours), walls
## and roads excepted: it would block a door, a mine or a gate.

## A tree is felled after this many builder-seconds (BUILD_SPEED * dt).
var chop_work := 4.0
## Wood drops per felled tree.
var wood_per_tree := 3
## How long a stump stands before it disappears.
var stump_seconds := 20.0
## How long after it fell a tree grows back where it stood.
var regrow_seconds := 30.0
## How far (tiles) a tree may move when its spot was built on.
var regrow_search := 8
## Buildings a tree may grow next to: walls (a tree against a wall blocks
## nothing). Roads are no building at all. Gates are not in here: a tree
## beside a gate could block the way through.
const TREE_NEIGHBOURS_OK := ["wall", "tree", "tree_stump"]

const TREE := "tree"
const STUMP := "tree_stump"
## Tint of a tree marked for chopping, until a mark sprite exists.
const MARK_TINT := Color(1.0, 0.55, 0.45)
const EV_STUMP := "stump_gone"
## Stage 10 tuning: one per felled tree, carrying its cell.
const EV_GROW_BACK := "grow_back"
## Before that, a repeating event grew trees at random spots. Ignored in old
## saves (the trees felled in them simply do not come back).
const EV_REGROW := "regrow"

var level: LevelGenerator
var events := TimedEvents.new()
## Trees on the map when the run began (kept for the saves and the tests).
var target_trees := 0
## Painted roads and bridges (BuildTools), so a tree never grows on a plan.
var tools: BuildTools

var _marked := {}    # tree building id -> true
var _chop := {}      # tree building id -> builder-seconds so far
var _rng := RandomNumberGenerator.new()


func setup(p_level: LevelGenerator) -> void:
	level = p_level
	level.building_removed.connect(_on_building_removed)


## A fresh map: count its trees.
func start_new(_tick: int, rng_seed: int) -> void:
	clear()
	_rng.seed = rng_seed
	target_trees = tree_count()


func clear() -> void:
	events.clear()
	_marked.clear()
	_chop.clear()
	target_trees = 0


func tree_count() -> int:
	return level.store.cells_of_type(TREE).size()


func is_tree(id: int) -> bool:
	return level.store.is_alive(id) and level.store.get_type(id) == TREE


func is_marked(id: int) -> bool:
	return _marked.has(id)


## Marks or unmarks a plain tree. Returns the new state; false for anything
## that is not a plain tree.
func toggle_mark(id: int) -> bool:
	if not is_tree(id):
		return false
	if _marked.has(id):
		_marked.erase(id)
		_tint(id, Color.WHITE)
		return false
	_marked[id] = true
	_tint(id, MARK_TINT)
	return true


## JobBoard provider: every tree waiting to be chopped.
func marked_trees() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _marked:
		if is_tree(id):
			out.append(id)
	return out


## Adds builder work to a marked tree. Returns true on the call that fells it;
## the tree is then already a stump, and the caller pops the wood.
func chop(id: int, work: float, tick: int) -> bool:
	if not is_tree(id) or not _marked.has(id):
		return false
	var done: float = float(_chop.get(id, 0.0)) + work
	if done < chop_work:
		_chop[id] = done
		return false
	var cell := level.store.get_cell(id)
	level.remove_building(cell)   # -> _on_building_removed clears the mark
	level.add_feature(STUMP, cell)
	events.schedule(tick + _ticks(stump_seconds), EV_STUMP, cell)
	events.schedule(tick + _ticks(regrow_seconds), EV_GROW_BACK, cell)
	return true


## Runs due events. Called once per tick from main._simulate.
func step(tick: int) -> void:
	for ev in events.pop_due(tick):
		match ev["kind"]:
			EV_STUMP:
				var c: Vector2i = ev["cell"]
				var id := level.grid.get_occupant(c)
				if level.store.is_alive(id) and level.store.get_type(id) == STUMP:
					level.remove_building(c)
			EV_GROW_BACK:
				var at := _spot_near(ev["cell"])
				if at != LevelGenerator.INVALID_CELL:
					level.add_feature(TREE, at)
			EV_REGROW:
				pass   # an old save's repeating event: dropped (see EV_REGROW)


## Where a tree felled at `cell` grows back: the cell itself if a tree may
## grow there, else the nearest tile within `regrow_search` where one may,
## ring by ring. INVALID_CELL if there is none (the tree is lost).
func _spot_near(cell: Vector2i) -> Vector2i:
	if _can_grow(cell):
		return cell
	for r in range(1, regrow_search + 1):
		var ring: Array[Vector2i] = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					ring.append(cell + Vector2i(dx, dy))
		ring.sort_custom(func(a, b): return (a - cell).length_squared() < (b - cell).length_squared())
		for c in ring:
			if _can_grow(c):
				return c
	return LevelGenerator.INVALID_CELL


## A tree may grow here: on the map, grass or snow, nothing built, no road,
## bridge or plan on it, and no building beside it (walls excepted).
func _can_grow(c: Vector2i) -> bool:
	var g := level.grid
	if not g.in_bounds(c) or g.is_occupied(c):
		return false
	var ground := g.get_ground(c)
	if not (g.is_grass(ground) or ground == WorldGrid.Ground.SNOW):
		return false
	var i := g.index(c)
	if g.overlay[i] != WorldGrid.Overlay.NONE:
		return false
	if tools != null and tools.plans().has(i):
		return false
	return not _touches_building(c)


## A building within one tile that a tree must keep clear of: any player
## building but a wall, and mines (miner houses and drops need the room).
func _touches_building(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if (dx == 0 and dy == 0) or not level.grid.in_bounds(n):
				continue
			var id := level.grid.get_occupant(n)
			if not level.store.is_alive(id):
				continue
			var t := level.store.get_type(id)
			if TREE_NEIGHBOURS_OK.has(t):
				continue
			if t.begins_with("mine_") or level.get_building_data(t) != null:
				return true
	return false


func _on_building_removed(id: int, _type: String, _cell: Vector2i) -> void:
	_marked.erase(id)
	_chop.erase(id)


func _tint(id: int, color: Color) -> void:
	var sprite := level.store.get_sprite(id)
	if sprite != null:
		sprite.self_modulate = color


static func _ticks(seconds: float) -> int:
	return maxi(int(round(seconds / GameClock.TICK_DELTA)), 1)


# --- Saving -------------------------------------------------------------------

## Marks and chop progress by cell (ids are reassigned on load).
func get_save_data() -> Dictionary:
	var marked: Array[Vector2i] = []
	var chop_cells: Array[Vector2i] = []
	var chop_work_done := PackedFloat32Array()
	for id in _marked:
		if is_tree(id):
			marked.append(level.store.get_cell(id))
	for id in _chop:
		if is_tree(id):
			chop_cells.append(level.store.get_cell(id))
			chop_work_done.append(_chop[id])
	return {"marked": marked, "chop_cells": chop_cells, "chop_work": chop_work_done,
		"target": target_trees, "events": events.get_save_data(),
		"rng_seed": _rng.seed, "rng_state": _rng.state}


## Call after the level has loaded.
func load_save_data(data: Dictionary) -> void:
	clear()
	target_trees = int(data.get("target", tree_count()))
	events.load_save_data(data.get("events", {}))
	_rng.seed = int(data.get("rng_seed", 0))
	if data.has("rng_state"):
		_rng.state = int(data["rng_state"])
	for c in data.get("marked", []):
		var id := level.grid.get_occupant(c)
		if is_tree(id):
			_marked[id] = true
			_tint(id, MARK_TINT)
	var cells: Array = data.get("chop_cells", [])
	var work: PackedFloat32Array = data.get("chop_work", PackedFloat32Array())
	for i in mini(cells.size(), work.size()):
		var id := level.grid.get_occupant(cells[i])
		if is_tree(id):
			_chop[id] = work[i]
