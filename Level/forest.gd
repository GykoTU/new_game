class_name Forest
extends RefCounted
## Plain trees: which ones the player marked for chopping, how far along each
## chop is, stumps rotting away, and new trees growing back.
##
## Builders do the chopping (JobBoard CHOP lists marked_trees()); the unit
## system calls chop() with their work and pops the wood when a tree falls.
## Fruit trees are not part of this: they are kept for fruit.
##
## Everything timed runs on simulation ticks through TimedEvents, and new tree
## spots come from a saved RNG, so a loaded run regrows exactly what it would
## have.

## A tree is felled after this many builder-seconds (BUILD_SPEED * dt).
var chop_work := 4.0
## Wood drops per felled tree.
var wood_per_tree := 3
## How long a stump stands before it disappears.
var stump_seconds := 60.0
## How often a new tree tries to grow, while there are fewer than at the start.
var regrow_seconds := 45.0

const TREE := "tree"
const STUMP := "tree_stump"
## Tint of a tree marked for chopping, until a mark sprite exists.
const MARK_TINT := Color(1.0, 0.55, 0.45)
const EV_STUMP := "stump_gone"
const EV_REGROW := "regrow"

var level: LevelGenerator
var events := TimedEvents.new()
## Trees on the map when the run began; regrowth tops up to this.
var target_trees := 0

var _marked := {}    # tree building id -> true
var _chop := {}      # tree building id -> builder-seconds so far
var _rng := RandomNumberGenerator.new()


func setup(p_level: LevelGenerator) -> void:
	level = p_level
	level.building_removed.connect(_on_building_removed)


## A fresh map: count its trees and start the regrowth clock.
func start_new(tick: int, rng_seed: int) -> void:
	clear()
	_rng.seed = rng_seed
	target_trees = tree_count()
	events.schedule(tick + _ticks(regrow_seconds), EV_REGROW)


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
			EV_REGROW:
				if tree_count() < target_trees:
					_grow_one()
				events.schedule(tick + _ticks(regrow_seconds), EV_REGROW)


## A new tree on a random free grass tile with nothing built around it, so it
## never walls in a door. Gives up quietly after a few tries.
func _grow_one() -> void:
	var size := level.map_size
	for _attempt in 40:
		var c := Vector2i(_rng.randi_range(1, size.x - 2), _rng.randi_range(1, size.y - 2))
		if level.grid.is_occupied(c) or not level.grid.is_grass(level.grid.get_ground(c)):
			continue
		var crowded := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if level.grid.is_occupied(c + Vector2i(dx, dy)):
					crowded = true
		if not crowded:
			level.add_feature(TREE, c)
			return


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
	if events.count(EV_REGROW) == 0:
		events.schedule(_ticks(regrow_seconds), EV_REGROW)   # older saves
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
