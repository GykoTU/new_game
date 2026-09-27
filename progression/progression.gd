class_name Progression
extends RefCounted
## XP, levels and augments (Stage 7).
##
##   XP        kills (EnemySystem hands over what its kills were worth),
##             exploration (tiles revealed, points of interest opened) and the
##             survival drip (1 XP every DRIP_SECONDS of running game time,
##             plus DAWN_BONUS x night at each dawn). Nothing counts before
##             the base is placed (main.gd only feeds it then).
##   levels    xp_to_next(level) = BASE_XP * GROWTH^(level - 1). Every level
##             gained is a PENDING pick; main.gd shows the level-up screen and
##             pauses the clock while any are pending.
##   offers    three different augments, drawn by weight from those the
##             player may take (not maxed, required tags owned). Weight =
##             rarity weight x (1 + SYNERGY per owned stack sharing a tag),
##             capped at MAX_SYNERGY. One reroll per level-up; skipping pays
##             gold. The relic tree (Stage 8) can add rerolls and cards, and
##             keeps some augments out until bought (`locked`).
##   taking    a common's modifiers go in as the source "aug:<id>" scaled by
##             its stacks (like shop upgrade levels); a rare's `flag` switches
##             a rule on, read by the system it changes (has_flag).
##
## Saved: xp, level, pending picks, stacks per augment, rerolls left for this
## pick, the rng. The current offer is drawn again after loading.

signal xp_changed(xp: int, needed: int, level: int)
## A new offer is up (after a level-up, a reroll or a pick with more pending).
signal offer_ready(ids: PackedStringArray)
signal augment_taken(id: String, stacks: int)

const SOURCE_PREFIX := "aug:"
## Stage 9 pacing: about one pick every two days (a day and night are 3
## minutes). Stage 7 had 15 / 1.3 / 10 s / 3 / 25, about 1.6 picks a day.
const BASE_XP := 50.0
const GROWTH := 1.25
const DRIP_SECONDS := 20.0
const DAWN_BONUS := 2
const TILES_PER_XP := 40
const POI_XP := 5
const CHOICES := 3
const RARITY_WEIGHT := {ShopItemData.Rarity.COMMON: 10.0, ShopItemData.Rarity.RARE: 3.0}
const SYNERGY := 0.5
const MAX_SYNERGY := 3.0

var pool: AugmentPool
var modifiers: ModifierSet
var rng := RandomNumberGenerator.new()

var xp := 0
var level := 1
## Level-ups not yet picked.
var pending := 0
var offer := PackedStringArray()
## Rerolls left for the current pick.
var rerolls_left := 1
## Per level-up; the relic tree adds to both (main.gd sets them per run).
var rerolls_per_pick := 1
var choices := CHOICES
## Augment ids never offered in this run (locked in the relic tree).
var locked := {}
var _stacks := {}          # augment id -> stacks taken
var _flags := {}           # flag -> true
var _drip_ticks := 0
var _tiles := 0            # revealed tiles not yet worth an XP


func setup(p_pool: AugmentPool, p_modifiers: ModifierSet) -> void:
	pool = p_pool
	modifiers = p_modifiers


## A new run.
func reset(seed_value: int) -> void:
	xp = 0
	level = 1
	pending = 0
	offer = PackedStringArray()
	rerolls_left = rerolls_per_pick
	_stacks.clear()
	_flags.clear()
	_drip_ticks = 0
	_tiles = 0
	rng.seed = seed_value
	xp_changed.emit(xp, xp_to_next(), level)


func xp_to_next(at_level := -1) -> int:
	var l := level if at_level < 0 else at_level
	return int(round(BASE_XP * pow(GROWTH, l - 1)))


func has_flag(flag: String) -> bool:
	return _flags.has(flag)


func stacks_of(id: String) -> int:
	return int(_stacks.get(id, 0))


func taken() -> Dictionary:
	return _stacks


# --- XP -------------------------------------------------------------------------

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		pending += 1
		gained += 1
	xp_changed.emit(xp, xp_to_next(), level)
	if gained > 0 and offer.is_empty():
		_new_offer()


## One simulation tick of the survival drip.
func step() -> void:
	_drip_ticks += 1
	if _drip_ticks >= int(round(DRIP_SECONDS / GameClock.TICK_DELTA)):
		_drip_ticks = 0
		add_xp(1)


func on_tiles_revealed(n: int) -> void:
	_tiles += n
	@warning_ignore("integer_division")
	var whole := _tiles / TILES_PER_XP
	if whole > 0:
		_tiles -= whole * TILES_PER_XP
		add_xp(whole)


func on_dawn(night: int) -> void:
	add_xp(DAWN_BONUS * maxi(night, 1))


# --- Offers ---------------------------------------------------------------------

## Tag counts over everything taken, stacks included.
func owned_tags() -> Dictionary:
	var out := {}
	for id in _stacks:
		var a := pool.find(id)
		if a == null:
			continue
		for t in a.tags:
			out[t] = int(out.get(t, 0)) + int(_stacks[id])
	return out


func can_offer(a: AugmentData, tags: Dictionary) -> bool:
	if a == null or stacks_of(a.id) >= a.max_stacks or locked.has(a.id):
		return false
	for t in a.requires_tags:
		if int(tags.get(t, 0)) < int(a.requires_tags[t]):
			return false
	return true


func weight_of(a: AugmentData, tags: Dictionary) -> float:
	var shared := 0
	for t in a.tags:
		shared += int(tags.get(t, 0))
	return float(RARITY_WEIGHT.get(a.rarity, 1.0)) * minf(1.0 + SYNERGY * shared, MAX_SYNERGY)


## Up to `choices` different augments, by weight. Fewer if the pool runs dry.
func draw() -> PackedStringArray:
	var tags := owned_tags()
	var cands: Array[AugmentData] = []
	var weights: Array[float] = []
	for a in pool.items:
		if can_offer(a, tags):
			cands.append(a)
			weights.append(weight_of(a, tags))
	var out := PackedStringArray()
	while out.size() < choices and not cands.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var roll := rng.randf() * total
		var pick := cands.size() - 1
		for n in cands.size():
			roll -= weights[n]
			if roll < 0.0:
				pick = n
				break
		out.append(cands[pick].id)
		cands.remove_at(pick)
		weights.remove_at(pick)
	return out


func _new_offer(keep_rerolls := false) -> void:
	if not keep_rerolls:
		rerolls_left = rerolls_per_pick
	offer = draw()
	if offer.is_empty():
		# Everything is maxed: the levels still count, there is nothing to pick.
		pending = 0
		return
	offer_ready.emit(offer)


## Takes one of the offered augments. Returns false if it was not offered.
func take(id: String) -> bool:
	if pending <= 0 or not offer.has(id):
		return false
	var a := pool.find(id)
	var n := stacks_of(id) + 1
	_stacks[id] = n
	_apply(a, n)
	augment_taken.emit(id, n)
	_next()
	return true


func can_reroll() -> bool:
	return pending > 0 and rerolls_left > 0


## Draws new cards, `rerolls_per_pick` times per level-up. Returns false if
## none is left.
func reroll() -> bool:
	if not can_reroll():
		return false
	offer = draw()
	rerolls_left -= 1
	offer_ready.emit(offer)
	return true


## Passes on this pick. Returns the gold it pays (the caller adds it).
func skip() -> int:
	if pending <= 0:
		return 0
	var gold := skip_gold()
	_next()
	return gold


func skip_gold() -> int:
	return 15 + 5 * pick_level()


## The level this pick is for: with several queued, the first one.
func pick_level() -> int:
	return level - pending + 1


func _next() -> void:
	pending -= 1
	offer = PackedStringArray()
	if pending > 0:
		_new_offer()


func _apply(a: AugmentData, n: int) -> void:
	if a.flag != "":
		_flags[a.flag] = true
	if not a.modifiers.is_empty():
		modifiers.add_source(SOURCE_PREFIX + a.id, a.modifiers_at(n))


## Rebuilds an augment's modifiers when a run loads (main._resolve_modifier_source).
## Returns Array[StatModifier], or null if this is not an augment source.
func resolve_source(source: String) -> Variant:
	if not source.begins_with(SOURCE_PREFIX):
		return null
	var a := pool.find(source.substr(SOURCE_PREFIX.length()))
	if a == null:
		return null
	return a.modifiers_at(stacks_of(a.id))


# --- Saving ---------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"xp": xp, "level": level, "pending": pending, "stacks": _stacks.duplicate(),
		"rerolls_left": rerolls_left, "drip": _drip_ticks, "tiles": _tiles, "rng_state": rng.state}


## Call BEFORE modifiers load: their "aug:" sources are rebuilt from the
## stacks read here. An augment this build no longer has is dropped.
func load_save_data(data: Dictionary) -> void:
	xp = int(data.get("xp", 0))
	level = maxi(int(data.get("level", 1)), 1)
	pending = maxi(int(data.get("pending", 0)), 0)
	# Before Stage 8 a save said only whether the one reroll was used.
	if data.has("rerolls_left"):
		rerolls_left = maxi(int(data["rerolls_left"]), 0)
	else:
		rerolls_left = 0 if bool(data.get("reroll_used", false)) else rerolls_per_pick
	_drip_ticks = int(data.get("drip", 0))
	_tiles = int(data.get("tiles", 0))
	_stacks.clear()
	_flags.clear()
	var saved: Dictionary = data.get("stacks", {})
	for id in saved:
		var a := pool.find(String(id))
		if a == null:
			continue
		_stacks[a.id] = mini(int(saved[id]), a.max_stacks)
		if a.flag != "":
			_flags[a.flag] = true
	if data.has("rng_state"):
		rng.state = int(data["rng_state"])
	offer = PackedStringArray()
	xp_changed.emit(xp, xp_to_next(), level)


## After loading: brings the pick back up if one was pending.
func resume_offer() -> void:
	if pending > 0 and offer.is_empty():
		_new_offer(true)   # the rerolls left were saved
