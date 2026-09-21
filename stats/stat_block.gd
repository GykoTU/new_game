class_name StatBlock
extends RefCounted
## Resolved stats for one kind of thing: a weapon type, an enemy type, workers.
##
## One block per TYPE, not per instance. Hundreds of enemies share the goblin
## block; its resolved values are copied into each enemy's arrays at spawn. A
## block per instance would mean hundreds of caches re-resolving on every
## modifier change, which is the per-entity overhead D2 exists to avoid.
## Per-instance, short-lived effects (slowed, burning) are status slots on the
## entity itself, not modifiers. See ARCHITECTURE.md, "Stats and modifiers".
##
## Reads are cached per stat. A read is two array reads and a compare until a
## change touches THAT stat; a change to fire rate leaves damage cached.

## What this block is, for modifier targeting: ["weapon", "fire"].
var tags := PackedStringArray()

var _set: ModifierSet
var _tag_set := {}
## Float64, not Float32: blocks are per type, so memory is irrelevant, and
## float32 turns 0.7 into 0.69999999 -- enough to flip a shop price by one.
var _base := PackedFloat64Array()
var _cache := PackedFloat64Array()
## Per stat: the set's stat_generation this cache entry was built from.
## -1 forces a resolve.
var _resolved_at := PackedInt32Array()


## `base_values` overrides registry defaults: {Stats.Id.DAMAGE: 25.0}.
func _init(modifier_set: ModifierSet, p_tags: PackedStringArray = PackedStringArray(),
		base_values: Dictionary = {}) -> void:
	_set = modifier_set
	tags = p_tags
	for t in tags:
		_tag_set[t] = true
	_base.resize(Stats.count())
	_cache.resize(Stats.count())
	_resolved_at.resize(Stats.count())
	_resolved_at.fill(-1)
	for i in Stats.count():
		_base[i] = Stats.default_of(i)
	for id in base_values:
		_base[id] = base_values[id]


func get_value(stat: int) -> float:
	if _resolved_at[stat] != _set.stat_generation[stat]:
		_resolve(stat)
	return _cache[stat]


func get_base(stat: int) -> float:
	return _base[stat]


## Changing a base value invalidates the cache just like a modifier would.
func set_base(stat: int, value: float) -> void:
	_base[stat] = value
	_resolved_at[stat] = -1


func _resolve(stat: int) -> void:
	var flat := 0.0
	var increase := 0.0
	var multiplier := 1.0
	for entry in _set.entries_for(stat):
		var m: StatModifier = entry[1]
		if not m.applies_to(_tag_set):
			continue
		match m.op:
			StatModifier.Op.FLAT:
				flat += m.value
			StatModifier.Op.INCREASE:
				increase += m.value
			StatModifier.Op.MULTIPLIER:
				multiplier *= m.value
	_cache[stat] = Stats.combine(stat, _base[stat], flat, increase, multiplier)
	_resolved_at[stat] = _set.stat_generation[stat]
