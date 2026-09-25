class_name PointsOfInterest
extends RefCounted
## Points of interest (Stage 3b): what the explorer finds under the fog.
##
## The generator places them as ordinary buildings whose type starts with
## "poi_"; this class decides what they mean. A point of interest is SPOTTED
## the moment its tile is explored (by anyone -- a watchtower counts), and
## OPENED when the explorer has stood beside it for `open_seconds`:
##
##   blueprint cache  teaches the next Unlocks.FINDABLE blueprint, then vanishes;
##                    relics instead once every findable blueprint is known
##   relic cache      relics, then vanishes
##   NPC house        placeholder message; stays, visited once
##   fruit tree       placeholder message; stays, visited once
##
## Relics belong to the permanent profile, but are only written there when the
## RUN is saved (main.gd takes them with take_pending_relics() inside
## save_run() and at death). Writing them at once would let a player open a
## cache, quit without saving, reload the dawn save and open it again.

## A point of interest came into view for the first time.
signal spotted(id: int, type: String)
## The explorer finished at one. `message` is what to tell the player.
signal opened(type: String, message: String)

const PREFIX := "poi_"
const BLUEPRINT_CACHE := "poi_blueprint_cache"
const RELIC_CACHE := "poi_relic_cache"
const NPC_HOUSE := "poi_npc_house"
const FRUIT_TREE := "poi_fruit_tree"

## Seconds the explorer spends at one before it gives up its contents.
var open_seconds := 3.0
## Relics in a relic cache, inclusive range.
var relics_per_cache := Vector2i(1, 3)
## Relics in a blueprint cache once there is no blueprint left to learn.
var relics_instead_of_blueprint := 2

var level: LevelGenerator
var unlocks: Unlocks
## Found this run and not yet written to the profile.
var relics_pending := 0
## Found this run in total, for the run summary.
var relics_found := 0

var _pois := PackedInt32Array()   # every live point of interest (building ids)
var _seen := {}                   # id -> true once its tile was explored
var _visited := {}                # id -> true for the ones that stay (NPC, fruit tree)
var _rng := RandomNumberGenerator.new()


func setup(p_level: LevelGenerator, p_unlocks: Unlocks, fog: FogOfWar) -> void:
	level = p_level
	unlocks = p_unlocks
	# Methods, not lambdas (see WorkerRoster.attach).
	level.level_generated.connect(_on_level_generated)
	level.building_removed.connect(_on_building_removed)
	fog.revealed.connect(_on_revealed)


## A new run. (Loading calls load_save_data instead.)
func clear() -> void:
	_visited.clear()
	relics_pending = 0
	relics_found = 0
	_rng.seed = level.used_seed if level != null else 0


## Called for a generated AND a loaded map. "Seen" is not saved: it is exactly
## "its tile is explored", which the level already saves.
func _on_level_generated() -> void:
	_pois.clear()
	_seen.clear()
	_visited.clear()
	for id in level.store.alive_ids():
		if is_poi(id):
			_pois.append(id)
			if level.grid.is_explored(level.store.get_cell(id)):
				_seen[id] = true


func is_poi(id: int) -> bool:
	return level.store.is_alive(id) and level.store.get_type(id).begins_with(PREFIX)


## Spotted, and still has something for the explorer.
func is_waiting(id: int) -> bool:
	return _seen.has(id) and not _visited.has(id) and level.store.is_alive(id)


## Every point of interest the explorer should go to, nearest-first is the
## caller's business.
func waiting() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _pois:
		if is_waiting(id):
			out.append(id)
	return out


func all() -> PackedInt32Array:
	return _pois


func _on_revealed(_indices: PackedInt32Array) -> void:
	# A handful of points of interest per map: checking each is cheaper than
	# looking every revealed tile up.
	for id in _pois:
		if _seen.has(id) or not level.store.is_alive(id):
			continue
		if level.grid.is_explored(level.store.get_cell(id)):
			_seen[id] = true
			spotted.emit(id, level.store.get_type(id))


func _on_building_removed(id: int, _type: String, _cell: Vector2i) -> void:
	var at := _pois.find(id)
	if at != -1:
		_pois.remove_at(at)
	_seen.erase(id)
	_visited.erase(id)


## The explorer has finished at `id`. Grants what it holds and returns the
## message for the player ("" if there was nothing: already opened).
func open(id: int) -> String:
	if not is_poi(id) or _visited.has(id):
		return ""
	var type := level.store.get_type(id)
	var message := ""
	match type:
		BLUEPRINT_CACHE:
			var blueprint := unlocks.next_findable()
			if blueprint != "":
				unlocks.add(blueprint)
				message = "Blueprint found: %s. Craft it in the shop." % _blueprint_name(blueprint)
			else:
				message = _grant_relics(relics_instead_of_blueprint, "Nothing left to learn here, but")
			level.remove_building(level.store.get_cell(id))
		RELIC_CACHE:
			message = _grant_relics(_rng.randi_range(relics_per_cache.x, relics_per_cache.y), "")
			level.remove_building(level.store.get_cell(id))
		NPC_HOUSE:
			_visited[id] = true
			message = "Someone lives here, but has nothing to say yet."
		FRUIT_TREE:
			_visited[id] = true
			message = "A tree heavy with strange fruit. Nobody knows what it does yet."
		_:
			_visited[id] = true
			message = "Nothing here."
	opened.emit(type, message)
	return message


func _grant_relics(n: int, lead: String) -> String:
	relics_pending += n
	relics_found += n
	var found := "%d relic%s" % [n, "" if n == 1 else "s"]
	if lead != "":
		return "%s %s." % [lead, found]
	return "Found %s." % found


## Hands over the relics not yet in the profile, and forgets them.
func take_pending_relics() -> int:
	var n := relics_pending
	relics_pending = 0
	return n


func _blueprint_name(blueprint: String) -> String:
	var type := blueprint.trim_prefix("blueprint:")
	var data := level.get_building_data(type)
	return data.display_name if data != null else type.capitalize()


# --- Saving -------------------------------------------------------------------

## Visited ones by cell. Opened caches are simply gone from the level; "seen"
## is derived from the fog.
func get_save_data() -> Dictionary:
	var visited: Array[Vector2i] = []
	for id in _visited:
		if level.store.is_alive(id):
			visited.append(level.store.get_cell(id))
	return {"visited": visited, "pending": relics_pending, "found": relics_found,
		"rng_state": _rng.state}


## Call after the level has loaded (level_generated has rebuilt the list).
func load_save_data(data: Dictionary) -> void:
	_visited.clear()
	for c in data.get("visited", []):
		if level.grid.in_bounds(c):
			var id := level.grid.get_occupant(c)
			if is_poi(id):
				_visited[id] = true
	relics_pending = maxi(int(data.get("pending", 0)), 0)
	relics_found = maxi(int(data.get("found", 0)), 0)
	if data.has("rng_state"):
		_rng.state = int(data["rng_state"])
