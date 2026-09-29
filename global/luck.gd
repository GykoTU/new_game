class_name Luck
extends RefCounted
## The run's luck (tuned after Stage 10): every roll that can leave a player
## unlucky goes through a MarbleBag, so it has memory.
##
##   chance(key, p)          true about p of the time -- exactly
##                           round(p * n) times in every n draws. n is 20,
##                           or 1/p for rarer chances (up to 100), so a 3%
##                           blueprint drop comes once in every 34 kills.
##   pick_range(key, lo, hi) each whole number from lo to hi once per bagful.
##
## Each key has its own bag; a chance that changes (a rarer cache further out,
## Scavengers doubling drops) uses the bag for its new odds. Saved with the
## run ("luck"): the bags keep their memory across saves.

var rng := RandomNumberGenerator.new()
var _bags := {}   # key -> MarbleBag


func reset(seed_value: int) -> void:
	rng.seed = seed_value
	_bags.clear()


## True about `p` of the time, with memory.
func chance(key: String, p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	var n := 20
	if p < 0.05:
		n = mini(int(ceil(1.0 / p)), 100)
	var hits := clampi(int(round(p * n)), 1, n - 1)
	var bag_key := "%s:%d/%d" % [key, hits, n]
	if not _bags.has(bag_key):
		var marbles := []
		for k in n:
			marbles.append(k < hits)
		_bags[bag_key] = MarbleBag.new(marbles, rng)
	return bool(_bags[bag_key].draw())


## A whole number from lo to hi (inclusive), each once per bagful.
func pick_range(key: String, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	var bag_key := "%s:%d-%d" % [key, lo, hi]
	if not _bags.has(bag_key):
		_bags[bag_key] = MarbleBag.new(range(lo, hi + 1), rng)
	return int(_bags[bag_key].draw())


func get_save_data() -> Dictionary:
	var bags := {}
	for k in _bags:
		bags[k] = _bags[k].get_save_data()
	return {"rng_state": rng.state, "rng_seed": rng.seed, "bags": bags}


func load_save_data(data: Dictionary) -> void:
	_bags.clear()
	if data.has("rng_seed"):
		rng.seed = int(data["rng_seed"])
	if data.has("rng_state"):
		rng.state = int(data["rng_state"])
	var bags: Dictionary = data.get("bags", {})
	for k in bags:
		var bag := MarbleBag.new([], rng)
		bag.load_save_data(bags[k])
		_bags[String(k)] = bag
