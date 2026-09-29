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
##
## TIERS (Stage 9): every findable blueprint has the tier of what it costs
## (ResourceKind.tier_of_cost). A region cache offers its region's tier, and
## lower ones once that tier is exhausted; enemy drops offer up to the highest
## tier the run has REACHED (held any of that tier's resources). The next
## gate's blueprint (GATE_KEYS) always comes first in its tier's caches.
##
## A LOCKED blueprint (Stage 8) is kept out of the pool until its relic-tree
## node is bought. main.gd sets the locks from the run's tree snapshot; they
## are not saved here.

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
	"blueprint:wall",             # Stage 6: walls and gates, painted
	"blueprint:road",
	"blueprint:pickaxe",          # Stage 9: iron's first use, from the start
]

## Findable blueprints that are not shop items (Stage 6 paint tools), with
## their names. Common. Their tier comes from BuildTools' prices.
const EXTRA_FINDABLE := {
	"blueprint:bridge": "Bridge",
	"blueprint:crossing": "Void Crossing",
}
const EXTRA_PRICE_KEYS := {"blueprint:bridge": "bridge", "blueprint:crossing": "crossing"}

## The key to the next region, found in the caches of the region before it:
## lava caches (tier 2) hold the bridge, water caches (tier 3) the crossing.
const GATE_KEYS := {2: "blueprint:bridge", 3: "blueprint:crossing"}

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
	"blueprint:bridge",
	"blueprint:crossing",
]

## Chance that a find is rare, while a rare blueprint is left to find.
var rare_chance := 0.2
## The run's luck (tuned after Stage 10): rare-or-common comes from a marble
## bag. Null (tests, the pool alone): a plain roll.
var luck: Luck
## What this run can find. FINDABLE until configure(); tests may narrow it.
var findable: Array = FINDABLE.duplicate()

var _ids := {}
var _reserved := {}
var _rarity := {}     # blueprint -> Rarity (missing: common)
var _requires := {}   # blueprint -> blueprint that must be known first
var _names := {}      # blueprint -> what the player calls it
var _tiers := {}      # blueprint -> resource-ladder tier (missing: 1)
## The highest resource tier this run has held (Stage 9). Saved.
var reached_tier := 1
var _locked := {}     # blueprint -> true: not findable this run (relic tree)


## The pool from the shop: every item's blueprint that a run does not start
## with.
func configure(catalogue: ShopCatalogue) -> void:
	findable = []
	_rarity.clear()
	_requires.clear()
	_names.clear()
	_tiers.clear()
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
		_tiers[id] = ResourceKind.tier_of_cost(item.base_cost)
		if item.requires != "":
			_requires[id] = item.requires
	for id in EXTRA_FINDABLE:
		if not findable.has(id):
			findable.append(id)
			_names[id] = EXTRA_FINDABLE[id]
			_tiers[id] = ResourceKind.tier_of_cost(BuildTools.price_of(EXTRA_PRICE_KEYS[id]))


## A new run: back to the starting set.
func reset() -> void:
	_ids.clear()
	_reserved.clear()
	reached_tier = 1
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


func tier_of(id: String) -> int:
	return int(_tiers.get(id, 1))


## The run held a resource of `tier`: drops may now offer that tier.
func reach_tier(tier: int) -> void:
	reached_tier = maxi(reached_tier, tier)


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
	return not _ids.has(id) and not _reserved.has(id) and not _locked.has(id) \
		and has(String(_requires.get(id, "")))


## Blueprints kept out of this run's pool: {"blueprint:whirl_tower": true}.
func set_locked(blueprints: Dictionary) -> void:
	_locked = blueprints.duplicate()


func is_locked(id: String) -> bool:
	return _locked.has(id)


## A random findable blueprint (rarity first, then uniformly), or "" if none
## is left. Does not learn it: the caller does (add, or reserve for a drop).
##
## `tier` > 0 (a region cache): that tier's gate key if it is still to find,
## else a blueprint of that tier, else of the highest lower tier with any
## left. `max_tier` > 0 (an enemy drop): any tier up to it. `rare` >= 0
## overrides rare_chance (caches further out are rarer).
func pick_findable(rng: RandomNumberGenerator, tier := 0, max_tier := 0, rare := -1.0) -> String:
	if tier > 0:
		var key: String = GATE_KEYS.get(tier, "")
		if key != "" and findable.has(key) and is_findable(key):
			rng.randf()   # keep the stream the same length either way
			return key
		for t in range(tier, 0, -1):
			var got := _pick(rng, t, t, rare)
			if got != "":
				return got
		return ""
	return _pick(rng, 1 if max_tier > 0 else 0, max_tier, rare)


func _pick(rng: RandomNumberGenerator, lo: int, hi: int, rare: float) -> String:
	var chance := rare_chance if rare < 0.0 else rare
	var common: Array = []
	var rare_ids: Array = []
	for id in findable:
		if hi > 0 and (tier_of(id) < lo or tier_of(id) > hi):
			continue
		if is_findable(id):
			if rarity_of(id) == Rarity.RARE:
				rare_ids.append(id)
			else:
				common.append(id)
	if common.is_empty() and rare_ids.is_empty():
		return ""
	var roll := rng.randf()   # always drawn, so the stream does not depend on the pool
	var is_rare := roll < chance
	if luck != null and not rare_ids.is_empty() and not common.is_empty():
		is_rare = luck.chance("rare", chance)
	var pool := rare_ids if not rare_ids.is_empty() and (common.is_empty() or is_rare) else common
	return pool[rng.randi_range(0, pool.size() - 1)]


func ids() -> PackedStringArray:
	return PackedStringArray(_ids.keys())


func get_save_data() -> Dictionary:
	return {"ids": ids(), "reserved": PackedStringArray(_reserved.keys()), "tier": reached_tier}


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
	reached_tier = clampi(int(data.get("tier", 1)), 1, ResourceKind.MAX_TIER)
	changed.emit()
