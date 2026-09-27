class_name MetaState
extends RefCounted
## What the player owns of the relic tree (Stage 8), and what that does to a
## run. Two copies exist:
##
##   the PROFILE's   the title screen's tree buys into it and refunds it;
##                   saved as profile["meta"] = {node id: level}.
##   a RUN's         a snapshot taken when the run starts, saved with the run
##                   (key "meta"). Continuing a run uses the tree it started
##                   with, so buying or refunding between sessions changes
##                   the NEXT run, never one in progress.
##
## A node can be bought when it is not maxed and its links are met: one owned
## neighbour, or all of them for a synergy node (`needs_all`). The root is
## always owned. Only a full refund exists, so nothing is ever left hanging
## from a node that was sold.

const SOURCE_PREFIX := "meta:"

var tree: MetaTree
var levels := {}   # node id -> level (roots are never stored)


func _init(p_tree: MetaTree = null, p_levels: Dictionary = {}) -> void:
	tree = p_tree
	load_levels(p_levels)


## Reads saved levels: unknown nodes are dropped, levels clamped to the node.
func load_levels(data: Dictionary) -> void:
	levels.clear()
	if tree == null:
		return
	for id in data:
		var n := tree.find(String(id))
		if n == null or n.is_root():
			continue
		var l := clampi(int(data[id]), 0, n.max_level())
		if l > 0:
			levels[n.id] = l


func get_levels() -> Dictionary:
	return levels.duplicate()


func level_of(id: String) -> int:
	var n := tree.find(id) if tree != null else null
	if n == null:
		return 0
	return 1 if n.is_root() else int(levels.get(id, 0))


func is_owned(id: String) -> bool:
	return level_of(id) > 0


func is_maxed(n: MetaNodeData) -> bool:
	return n.is_root() or level_of(n.id) >= n.max_level()


## Its links are met (it may still be maxed).
func is_reachable(n: MetaNodeData) -> bool:
	if n.is_root():
		return true
	if n.links.is_empty():
		return true
	for l in n.links:
		var owned := is_owned(l)
		if n.needs_all and not owned:
			return false
		if not n.needs_all and owned:
			return true
	return n.needs_all


func next_cost(n: MetaNodeData) -> int:
	return n.cost_at(level_of(n.id))


func can_buy(n: MetaNodeData, relics: int) -> bool:
	return not is_maxed(n) and is_reachable(n) and relics >= next_cost(n)


## Buys one level. Returns the relics it cost (the caller takes them), or -1.
func buy(id: String, relics: int) -> int:
	var n := tree.find(id)
	if n == null or not can_buy(n, relics):
		return -1
	var cost := next_cost(n)
	levels[id] = level_of(id) + 1
	return cost


## Relics spent on everything owned.
func spent() -> int:
	var total := 0
	for id in levels:
		var n := tree.find(id)
		if n != null:
			total += n.spent_at(int(levels[id]))
	return total


## Sells everything. Returns the relics to give back.
func refund_all() -> int:
	var back := spent()
	levels.clear()
	return back


# --- What it does to a run ---------------------------------------------------

func _owned_nodes() -> Array[MetaNodeData]:
	var out: Array[MetaNodeData] = []
	if tree == null:
		return out
	for n in tree.nodes:
		if n != null and not n.is_root() and level_of(n.id) > 0:
			out.append(n)
	return out


## Modifier sources: "meta:<id>" -> Array[StatModifier].
func modifier_sources() -> Dictionary:
	var out := {}
	for n in _owned_nodes():
		if not n.modifiers.is_empty():
			out[SOURCE_PREFIX + n.id] = n.modifiers_at(level_of(n.id))
	return out


## Rebuilds a "meta:" modifier source when a run loads, or null if it is not one.
func resolve_source(source: String) -> Variant:
	if not source.begins_with(SOURCE_PREFIX):
		return null
	var n := tree.find(source.substr(SOURCE_PREFIX.length())) if tree != null else null
	if n == null:
		return null
	return n.modifiers_at(level_of(n.id))


## ResourceKind.Id -> extra starting amount.
func start_resources() -> Dictionary:
	var out := {}
	for n in _owned_nodes():
		for k in n.start_resources:
			out[k] = int(out.get(k, 0)) + n.start_resources[k] * level_of(n.id)
	return out


## WorkerRoster.Kind -> extra workers when the base is placed.
func start_workers() -> Dictionary:
	var out := {}
	for n in _owned_nodes():
		for k in n.start_workers:
			out[int(k)] = int(out.get(int(k), 0)) + int(n.start_workers[k]) * level_of(n.id)
	return out


func start_blueprints() -> PackedStringArray:
	var out := PackedStringArray()
	for n in _owned_nodes():
		for b in n.start_blueprints:
			if not out.has(b):
				out.append(b)
	return out


func perk(name: String) -> int:
	var total := 0
	for n in _owned_nodes():
		total += int(n.perks.get(name, 0)) * level_of(n.id)
	return total


## Content kept out of the run: "blueprint:..." and "augment:..." ids that an
## unowned node unlocks. -> {id: true}
func locked_content() -> Dictionary:
	var out := {}
	if tree == null:
		return out
	for n in tree.nodes:
		if n == null or level_of(n.id) > 0:
			continue
		for c in n.unlocks_content:
			out[c] = true
	return out


## The locked ids with a prefix, keeping it: {"blueprint:whirl_tower": true}.
func locked_with_prefix(prefix: String) -> Dictionary:
	var out := {}
	for c in locked_content():
		if String(c).begins_with(prefix):
			out[String(c)] = true
	return out


## The locked ids with a prefix, without it: locked_with("augment:").
func locked_with(prefix: String) -> Dictionary:
	var out := {}
	for c in locked_content():
		if String(c).begins_with(prefix):
			out[String(c).substr(prefix.length())] = true
	return out
