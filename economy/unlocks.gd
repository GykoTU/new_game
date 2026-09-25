class_name Unlocks
extends RefCounted
## What this run has learned: blueprints ("blueprint:depot") and, later, items
## ("item:water_bucket"). One saved set of plain ids. Points of interest and
## enemies add blueprints here (Stages 3b, 4); the shop reads it to decide what
## the Craft tab shows.

signal changed

## Every run starts knowing these.
const STARTING := [
	"blueprint:builder_house",
	"blueprint:carrier_house",
	"blueprint:miner_house",
	"blueprint:depot",
	"blueprint:bucket",
	"blueprint:explorer_house",   # Stage 3b: the explorer must be buyable
]

## Blueprints a blueprint cache can teach (Stage 3b), in the order they are
## handed out. A cache opened once all of these are known gives relics instead.
const FINDABLE := [
	"blueprint:watchtower",
	"blueprint:city_hall",
]

var _ids := {}


## A new run: back to the starting set.
func reset() -> void:
	_ids.clear()
	for id in STARTING:
		_ids[id] = true
	changed.emit()


func has(id: String) -> bool:
	return id == "" or _ids.has(id)


## Returns true if it was new.
func add(id: String) -> bool:
	if id == "" or _ids.has(id):
		return false
	_ids[id] = true
	changed.emit()
	return true


## The next findable blueprint this run does not know, or "" if none is left.
func next_findable() -> String:
	for id in FINDABLE:
		if not _ids.has(id):
			return id
	return ""


func ids() -> PackedStringArray:
	return PackedStringArray(_ids.keys())


func get_save_data() -> Dictionary:
	return {"ids": ids()}


## A save without unlocks (older runs) gets the starting set.
func load_save_data(data: Dictionary) -> void:
	if not data.has("ids"):
		reset()
		return
	_ids.clear()
	for id in STARTING:   # always known, even if the save predates one of them
		_ids[id] = true
	for id in data["ids"]:
		_ids[String(id)] = true
	changed.emit()
