class_name ShopItemData
extends Resource
## One thing the shop sells. Create these in data/shop/ and list them in the
## catalogue; the shop shows them in catalogue order.

enum Kind {
	## Adds one worker of `worker_kind` to the roster.
	WORKER,
	## Each purchase raises the level by one; `modifiers` scale with the level.
	UPGRADE,
	## Adds one building of `building_id` to the owned-buildings inventory, to
	## be placed from the building bar. (Appended: kinds are saved as ints.)
	BUILDING,
}

## Which tab of the shop it is in. Buy is paid in gold only, Craft in
## resources only: a data rule, checked by a test over the catalogue.
enum Section {
	BUY,
	CRAFT,
}

## Unique, stable id. Used in save files ("upg:<id>"), so renaming it breaks
## runs that bought it. Change display_name instead.
@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## A path rather than a Texture2D, so a missing or renamed sprite shows the
## fallback instead of making this file fail to load.
@export_file("*.png") var icon_path := ""
@export var kind: Kind = Kind.UPGRADE
@export var section: Section = Section.BUY
## Unlock id the run must know before this shows in the shop, e.g.
## "blueprint:depot". Empty = always known.
@export var blueprint := ""
## Extra tags for price targeting. "shop" and the kind ("worker" / "upgrade" /
## "building") are always added, so a sale on ["shop", "upgrade"] needs nothing here.
@export var tags := PackedStringArray()

@export_group("Price")
## Cost of the first purchase, per resource.
@export var base_cost: Dictionary[ResourceKind.Id, int] = {}
## Each purchase multiplies the next price by this. 1.0 = constant price.
@export var cost_growth := 1.0
## 0 = no limit.
@export var max_level := 0

@export_group("Worker")
@export var worker_kind: WorkerRoster.Kind = WorkerRoster.Kind.MINER

@export_group("Building")
## BuildingData id added to the inventory.
@export var building_id := ""

@export_group("Upgrade")
## The modifiers at level 1. Level N scales them: FLAT and INCREASE by N,
## MULTIPLIER to the power N. So "+10% move speed" at level 3 is +30%, and
## "x1.1 damage" at level 3 is x1.331.
@export var modifiers: Array[StatModifier] = []


## Tags used to resolve this item's price.
func price_tags() -> PackedStringArray:
	var out := PackedStringArray(["shop", ["worker", "upgrade", "building"][kind]])
	for t in tags:
		if not out.has(t):
			out.append(t)
	return out


## The modifiers this item contributes at a given level. Fresh copies: the
## authored ones are shared .tres data and must never be mutated.
func modifiers_at(level: int) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if level <= 0:
		return out
	for m in modifiers:
		if m == null:
			continue
		var value := m.value
		match m.op:
			StatModifier.Op.FLAT, StatModifier.Op.INCREASE:
				value = m.value * level
			StatModifier.Op.MULTIPLIER:
				value = pow(m.value, level)
		out.append(StatModifier.make(m.stat, m.op, value, m.tags))
	return out
