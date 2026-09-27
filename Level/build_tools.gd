class_name BuildTools
extends RefCounted
## The paint tools of Stage 6: walls (and gates), roads, bridges over water,
## crossings over void. Each is an item-bar slot keyed by a blueprint unlock;
## the player drags it over tiles like the water bucket.
##
##   paint     each tile is paid for at once (PRICES) and becomes a plan:
##             walls and gates are ordinary construction sites
##             (LevelGenerator.place_construction) that builders build;
##             roads, bridges and crossings are tile plans here, built by
##             builders as a PAVE job (JobBoard) into the grid's overlay.
##   unpaint   a stroke that starts on a plan removes plans instead, and
##             gives their price back. Finished pieces stay (the shovel digs
##             walls out; built roads are permanent for now).
##
## Bridges only go on water and crossings only on void, and a plan is only
## worked once it touches walkable ground, so they grow out from the shore.
## Plans are saved by tile.

signal plans_changed

enum Tool { WALL, ROAD, BRIDGE, CROSSING }

const R := ResourceKind.Id
## Per tile, paid when painted.
## Stage 9: each gate pays with the rung before it. Gates are iron-bound;
## a bridge (to quartz) costs copper, a crossing (into the void) quartz.
const PRICES := {
	"wall": {R.WOOD: 2},
	"gate": {R.WOOD: 4, R.IRON: 1},
	"road": {R.WOOD: 1},
	"bridge": {R.WOOD: 2, R.COPPER: 1},
	"crossing": {R.WOOD: 2, R.QUARTZ: 1},
}
## The unlock that shows each tool in the item bar.
const BLUEPRINTS := {
	Tool.WALL: "blueprint:wall",
	Tool.ROAD: "blueprint:road",
	Tool.BRIDGE: "blueprint:bridge",
	Tool.CROSSING: "blueprint:crossing",
}
## Builder-seconds to build one tile of each overlay.
const WORK := {
	WorldGrid.Overlay.ROAD: 0.5,
	WorldGrid.Overlay.BRIDGE: 1.5,
	WorldGrid.Overlay.CROSSING: 2.0,
}
const _NAME := {WorldGrid.Overlay.ROAD: "road", WorldGrid.Overlay.BRIDGE: "bridge",
	WorldGrid.Overlay.CROSSING: "crossing"}

var level: LevelGenerator
var economy: Economy
var _plans := {}   # tile index -> [overlay kind, builder-seconds done]


func setup(p_level: LevelGenerator, p_economy: Economy) -> void:
	level = p_level
	economy = p_economy
	# Methods, not lambdas (see WorkerRoster.attach).
	level.level_generated.connect(clear)


func clear() -> void:
	_plans.clear()
	plans_changed.emit()


static func overlay_of(tool: int) -> int:
	match tool:
		Tool.ROAD: return WorldGrid.Overlay.ROAD
		Tool.BRIDGE: return WorldGrid.Overlay.BRIDGE
		Tool.CROSSING: return WorldGrid.Overlay.CROSSING
	return WorldGrid.Overlay.NONE


static func price_of(key: String) -> Dictionary:
	return PRICES.get(key, {})


# --- Painting ---------------------------------------------------------------

## "wall" or "gate" if an unbuilt one stands here, else "".
func planned_type(cell: Vector2i) -> String:
	if not level.grid.in_bounds(cell):
		return ""
	var b := level.grid.get_occupant(cell)
	if level.store.is_alive(b) and not level.store.is_complete(b):
		var t := level.store.get_type(b)
		if t == "wall" or t == "gate":
			return t
	return ""


## True if a stroke starting here would unpaint: a plan of this tool is here
## (for a gate stroke, a planned gate; a planned wall is swapped instead).
func is_planned(tool: int, cell: Vector2i, gate := false) -> bool:
	if not level.grid.in_bounds(cell):
		return false
	if tool == Tool.WALL:
		var t := planned_type(cell)
		return t == "gate" if gate else t != ""
	var i := level.grid.index(cell)
	return _plans.has(i) and int(_plans[i][0]) == overlay_of(tool)


## Could this tile be painted (or unpainted) with this tool?
func can_paint(tool: int, cell: Vector2i, gate := false) -> bool:
	if not level.grid.in_bounds(cell) or not level.grid.is_explored(cell):
		return false
	if tool == Tool.WALL:
		return planned_type(cell) != "" or level.can_place("gate" if gate else "wall", cell)
	if is_planned(tool, cell):
		return true
	var i := level.grid.index(cell)
	if _plans.has(i) or level.grid.overlay[i] != WorldGrid.Overlay.NONE or level.grid.is_occupied(cell):
		return false
	var g: int = level.grid.ground[i]
	match tool:
		Tool.BRIDGE:
			return g == WorldGrid.Ground.WATER
		Tool.CROSSING:
			return g == WorldGrid.Ground.VOID
		Tool.ROAD:
			return (int(WorldGrid.GROUND_BLOCKING[g]) & WorldGrid.BLOCKS_UNIT) == 0
	return false


## Paints one tile. Returns "" on success, "skip" if there is nothing to do
## here, or why not ("Not enough resources for a gate."). A gate painted over
## an unbuilt wall replaces it (the wall is refunded).
func paint(tool: int, cell: Vector2i, gate := false) -> String:
	if not can_paint(tool, cell, gate) or is_planned(tool, cell, gate):
		return "skip"
	var key := ("gate" if gate else "wall") if tool == Tool.WALL else String(_NAME[overlay_of(tool)])
	var price := price_of(key)
	var swap := tool == Tool.WALL and gate and planned_type(cell) == "wall"
	var credit := price_of("wall") if swap else {}
	var need := {}
	for k in price:
		need[k] = maxi(int(price[k]) - int(credit.get(k, 0)), 0)
	if not economy.can_afford(need):
		return "Not enough resources for a %s." % key
	if swap:
		unpaint(tool, cell)
	if tool == Tool.WALL:
		if level.place_construction(key, cell) == BuildingStore.NONE:
			return "skip"
	else:
		_plans[level.grid.index(cell)] = [overlay_of(tool), 0.0]
		plans_changed.emit()
	economy.spend(price)
	return ""


## Removes a plan of this tool at `cell` and refunds it. False if none.
func unpaint(tool: int, cell: Vector2i) -> bool:
	if not is_planned(tool, cell):
		return false
	var i := level.grid.index(cell)
	var key: String
	if tool == Tool.WALL:
		var b := level.grid.occupancy[i]
		key = level.store.get_type(b)
		level.remove_building(cell)
	else:
		key = _NAME[int(_plans[i][0])]
		_plans.erase(i)
		plans_changed.emit()
	var price := price_of(key)
	for k in price:
		economy.add(k, price[k])
	return true


# --- Building -----------------------------------------------------------------

func plans() -> Dictionary:
	return _plans


## JobBoard provider: plans a builder can work on -- ones touching walkable
## ground (a bridge grows out from the shore, tile by tile).
func jobs() -> PackedInt32Array:
	var out := PackedInt32Array()
	var g := level.grid
	for i in _plans:
		var c := g.cell_at(i)
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.ZERO]:
			var n: Vector2i = c + d
			if g.in_bounds(n) and g.is_passable_at(g.index(n)):
				out.append(i)
				break
	return out


## Adds builder work. Returns true on the call that finishes the tile.
func pave(i: int, work: float) -> bool:
	if not _plans.has(i):
		return false
	var plan: Array = _plans[i]
	var kind: int = plan[0]
	plan[1] = float(plan[1]) + work
	if plan[1] < float(WORK[kind]):
		return false
	_plans.erase(i)
	level.grid.set_overlay_at(i, kind)
	plans_changed.emit()
	return true


# --- Saving -------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var out := []
	for i in _plans:
		out.append([i, _plans[i][0], _plans[i][1]])
	return {"plans": out}


## Call after the level has loaded (the overlay itself is in the level save).
func load_save_data(data: Dictionary) -> void:
	_plans.clear()
	for p in data.get("plans", []):
		var i := int(p[0])
		if i >= 0 and i < level.grid.tile_count():
			_plans[i] = [int(p[1]), float(p[2])]
	plans_changed.emit()
