class_name StatModifier
extends Resource
## One change to one stat, for things that carry the right tags.
##
## A Resource so it can be authored in the inspector: an augment or a shop
## upgrade will hold an Array[StatModifier] (Stages 1 and 7).
##
## Deliberately has NO `source` field. A .tres is shared by everything that
## references it, so two augments pointing at the same modifier would fight over
## a source written onto it. ModifierSet records which source added what instead.

enum Op {
	## Added to the base value, before any percentage applies.
	FLAT,
	## A fraction. Increases add together: 0.2 and 0.3 give +50%.
	INCREASE,
	## A factor. Multipliers multiply together: 1.5 and 1.5 give x2.25.
	MULTIPLIER,
}

@export var stat: Stats.Id = Stats.Id.DAMAGE
@export var op: Op = Op.INCREASE
## FLAT: absolute amount. INCREASE: fraction (0.2 = +20%). MULTIPLIER: factor (1.5).
@export var value := 0.0
## Applies only to targets carrying EVERY one of these tags. Empty = everything.
## ["weapon", "fire"] reaches fire weapons and nothing else.
@export var tags := PackedStringArray()


static func make(p_stat: int, p_op: int, p_value: float,
		p_tags: PackedStringArray = PackedStringArray()) -> StatModifier:
	var m := StatModifier.new()
	m.stat = p_stat as Stats.Id
	m.op = p_op as Op
	m.value = p_value
	m.tags = p_tags
	return m


## True if a target with these tags should receive this modifier.
func applies_to(target_tags: Dictionary) -> bool:
	for t in tags:
		if not target_tags.has(t):
			return false
	return true
