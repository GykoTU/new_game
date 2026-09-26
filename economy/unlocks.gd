class_name Unlocks
extends RefCounted
## What this run has learned: blueprints ("blueprint:depot") and items
## ("item:water_bucket"). One saved set of plain ids. Points of interest and
## enemy drops add blueprints here; the shop reads it to decide what it shows.
##
## The FINDABLE POOL is every blueprint the run can still find. main.gd builds
## it from the shop catalogue (configure): each item's blueprint, with the
## item's rarity and the blueprint it `requires` (a weapon upgrade needs its
## weapon). A find picks a rarity first (rare with `rare_chance`, if a rare
## one is left), then one of that rarity at random.
##
## A blueprint lying on the map in a dropped cache is RESERVED: it cannot be
## picked again until the explorer brings it in (or the cache is lost).

signal changed

const Rarity := ShopItemData.Rarity

## Every run starts knowing these.
const STARTING := [
	"blueprint:builder_house",
	"blueprint:carrier_house",
	"blueprint:miner_house",
	"blueprint:depot",
	"blueprint:bucket",
	"blueprint:shovel",
	"blueprint:explorer_house",   # Stage 3b: the explorer must be buyable
	"blueprint:arrow_tower",      # Stage 5: the one weapon every run has
]

## The findable buildings, for a pool without a catalogue (tools, tests).
## main.gd replaces the pool with configure().
const FINDABLE := [
	"blueprint:watchtower",
	"blueprint:city_hall",
	"blueprint:cannon",
	"blueprint:frost_tower",
	"blueprint:flame_tower",
	"blueprint:hook_tower",
	"blueprint:chain_cannon",
	"blueprint:whirl_tower",
]

## Chance that a find is rare, while a rare blueprint is left to find.
var rare_chance := 0.2
## What this run can find. FINDABLE until configure(); tests may narrow it.
var findable: Array = FINDABLE.duplicate()

var _ids := {}
var _reserved := {}
var _rarity := {}     # blueprint -> Rarity (missing: common)
var _requires := {}   # blueprint -> blueprint that must be known first
var _names := {}      # blueprint -> what the player calls it


## The pool from the shop: every item's blueprint that a run does not start
## with.
func configure(catalogue: ShopCatalogue) -> void:
	findable = []
	_rarity.clear()
	_requires.clear()
	_names.clear()
	for item in catalogue.items:
		if item == null or item.blueprint == "":
			continue
		var id := item.blueprint
		if not _names.has(id):
			_names[id] = item.display_name
		if STARTING.has(id) or findable.has(id):
			continue
		findable.append(id)
		_rarity[id] = item.rarity
		if item.requires != "":
			_requires[id] = item.requires


## A new run: back to the starting set.
func reset() -> void:
	_ids.clear()
	_reserved.clear()
	for id in STARTING:
		_ids[id] = true
	changed.emit()


func has(id: String) -> bool:
	return id == "" or _ids.has(id)


## Returns true if it was new. Learning a blueprint ends its reservation.
func add(id: String) -> bool:
	_reserved.erase(id)
	if id == "" or _ids.has(id):
		return false
	_ids[id] = true
	changed.emit()
	return true


func rarity_of(id: String) -> int:
	return int(_rarity.get(id, Rarity.COMMON))


func name_of(id: String) -> String:
	return String(_names.get(id, id.trim_prefix("blueprint:").capitalize()))


## Held back from picks while it lies on the map.
func reserve(id: String) -> void:
	if id != "":
		_reserved[id] = true


func release_reservation(id: String) -> void:
	_reserved.erase(id)


func is_reserved(id: String) -> bool:
	return _reserved.has(id)


## Could be found right now: unknown, not lying on the map, and whatever it
## requires is known.
func is_findable(id: String) -> bool:
	return not _ids.has(id) and not _reserved.has(id) and has(String(_requires.get(id, "")))


## A random findable blueprint (rarity first, then uniformly), or "" if none
## is left. Does not learn it: the caller does (add, or reserve for a drop).
func pick_findable(rng: RandomNumberGenerator) -> String:
	var common: Array = []
	var rare: Array = []
	for id in findable:
		if is_findable(id):
			if rarity_of(id) == Rarity.RARE:
				rare.append(id)
			else:
				common.append(id)
	if common.is_empty() and rare.is_empty():
		return ""
	var roll := rng.randf()   # always drawn, so the stream does not depend on the pool
	var pool := rare if not rare.is_empty() and (common.is_empty() or roll < rare_chance) else common
	return pool[rng.randi_range(0, pool.size() - 1)]


func ids() -> PackedStringArray:
	return PackedStringArray(_ids.keys())


func get_save_data() -> Dictionary:
	return {"ids": ids(), "reserved": PackedStringArray(_reserved.keys())}


## A save without unlocks (older runs) gets the starting set.
func load_save_data(data: Dictionary) -> void:
	if not data.has("ids"):
		reset()
		return
	_ids.clear()
	_reserved.clear()
	for id in STARTING:   # always known, even if the save predates one of them
		_ids[id] = true
	for id in data["ids"]:
		_ids[String(id)] = true
	for id in data.get("reserved", []):
		_reserved[String(id)] = true
	changed.emit()
