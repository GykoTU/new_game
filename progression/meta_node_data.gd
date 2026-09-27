class_name MetaNodeData
extends Resource
## One node of the relic tree (Stage 8): bought with relics between runs, kept
## in the profile. A node can hold any mix of effects; its branch only decides
## its colour. Every effect is per level unless noted, and levels are
## `costs.size()`.
##
## Create in data/meta/ and list in data/meta/tree.tres.

enum Branch { ROOT, ARMS, HANDS, WALLS, PATHS }

## Unique, stable id: the profile and run saves use it ("meta:<id>" modifier
## sources). Rename display_name instead.
@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## 48x48. Missing: a circle with the initials, in the branch colour.
@export_file("*.png") var icon_path := ""
@export var branch: Branch = Branch.ROOT
## Where it sits on the tree screen, relative to the centre, in pixels.
@export var position := Vector2.ZERO
## The nodes it grows from. It can be bought once ONE of them is owned, or,
## with `needs_all`, once ALL of them are (a synergy node between branches).
@export var links := PackedStringArray()
@export var needs_all := false
## Relics for each level: [3, 5, 8] is a three-level node. Empty: owned from
## the start (the root).
@export var costs := PackedInt32Array()

@export_group("Effects")
## Stat modifiers at one level, scaled like shop upgrade levels.
@export var modifiers: Array[StatModifier] = []
## Added to the run's starting resources, per level.
@export var start_resources: Dictionary[ResourceKind.Id, int] = {}
## Extra workers when the base is placed, per level (WorkerRoster.Kind).
@export var start_workers: Dictionary[int, int] = {}
## Blueprints every run starts knowing (once owned, any level).
@export var start_blueprints := PackedStringArray()
## Content that stays out of runs until this node is owned:
## "blueprint:<id>" (no longer findable) or "augment:<id>" (never offered).
@export var unlocks_content := PackedStringArray()
## Rule numbers, per level: "rerolls" (extra rerolls per level-up),
## "choices" (extra augment cards), "relic_bonus" (extra relics per cache).
@export var perks: Dictionary[String, int] = {}


func max_level() -> int:
	return costs.size()


func is_root() -> bool:
	return costs.is_empty()


## Relics for the next level, or -1 when maxed.
func cost_at(level: int) -> int:
	return costs[level] if level < costs.size() else -1


## Relics spent to reach `level`.
func spent_at(level: int) -> int:
	var total := 0
	for n in mini(level, costs.size()):
		total += costs[n]
	return total


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
