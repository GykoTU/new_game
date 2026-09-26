class_name AugmentData
extends Resource
## One augment (Stage 7): what a level-up can offer. Commons are stat
## modifiers that stack; rares are one-off rule changes (`flag`), read by the
## system they change (Progression.has_flag).
##
## Create in data/augments/ and list in data/augments/pool.tres.

## Unique, stable id: saves use it ("aug:<id>" modifier sources). Rename
## display_name instead.
@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## 32x32. Missing: a coloured badge with the initials.
@export_file("*.png") var icon_path := ""
@export var rarity: ShopItemData.Rarity = ShopItemData.Rarity.COMMON
## Synergy tags: "weapon", "fire", "worker"... Offers lean toward tags the
## player already owns, and `requires_tags` can demand them.
@export var tags := PackedStringArray()
## How many times it can be taken. Commons 5, rares 1.
@export var max_stacks := 5
## Only offered once the player owns this many augments (stacks count) with
## each tag, e.g. {"fire": 2}.
@export var requires_tags: Dictionary[String, int] = {}
## The modifiers at one stack. N stacks scale them like shop upgrade levels
## (ShopItemData.modifiers_at): FLAT and INCREASE times N, MULTIPLIER to the N.
@export var modifiers: Array[StatModifier] = []
## A rule this augment switches on (rares), e.g. "careful_aim". "" = none.
@export var flag := ""


func modifiers_at(stacks: int) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if stacks <= 0:
		return out
	for m in modifiers:
		if m == null:
			continue
		var value := m.value
		match m.op:
			StatModifier.Op.FLAT, StatModifier.Op.INCREASE:
				value = m.value * stacks
			StatModifier.Op.MULTIPLIER:
				value = pow(m.value, stacks)
		out.append(StatModifier.make(m.stat, m.op, value, m.tags))
	return out
