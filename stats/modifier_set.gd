class_name ModifierSet
extends RefCounted
## Every active stat modifier in a run, grouped by the source that added it.
##
## Sources are the unit of change. Taking an augment adds a source; buying the
## next level of an upgrade replaces one; a timed buff expiring removes one. All
## the modifiers a source contributed arrive and leave together, so nothing can
## be left behind by removing them one at a time.
##
## Staleness is tracked PER STAT. `stat_generation[stat]` moves only when a
## change touches that stat, and StatBlocks compare it per stat, so a buff to
## fire rate re-resolves fire rate and nothing else. Measured: resolving every
## stat on every change cost ~2.7 ms per change across 50 blocks, which timed
## buffs expiring several times a second would feel. Do not simplify this back
## to a single counter without re-running the benchmark.

## Emitted after any change. For UI; gameplay reads through StatBlocks.
signal changed

## Bumped on every change, whatever it touched. For coarse "did anything change".
var generation := 0
## Per stat: the `generation` at which that stat last changed.
var stat_generation := PackedInt32Array()

## source (String) -> Array[StatModifier]
var _by_source := {}
## Stats.Id -> Array of [source, StatModifier]. Rebuilt on change so that
## resolving a stat only visits modifiers for that stat.
var _by_stat: Array = []


func _init() -> void:
	stat_generation.resize(Stats.count())
	stat_generation.fill(0)
	_rebuild_index()


## Adds a source, or replaces it if it already exists (e.g. upgrade level 2 -> 3).
func add_source(source: String, modifiers: Array[StatModifier]) -> void:
	var touched := {}
	if _by_source.has(source):
		_collect_stats(_by_source[source], touched)   # replaced ones change too
	_collect_stats(modifiers, touched)
	_by_source[source] = modifiers.duplicate()
	_changed(touched)


func remove_source(source: String) -> void:
	if not _by_source.has(source):
		return
	var touched := {}
	_collect_stats(_by_source[source], touched)
	_by_source.erase(source)
	_changed(touched)


func has_source(source: String) -> bool:
	return _by_source.has(source)


func sources() -> PackedStringArray:
	return PackedStringArray(_by_source.keys())


func clear() -> void:
	_by_source.clear()
	_changed_all()


## Modifiers that target one stat, as [source, StatModifier] pairs. Read-only.
func entries_for(stat: int) -> Array:
	return _by_stat[stat]


# --- Saving -------------------------------------------------------------------

## Saves WHICH sources are active, not what they resolved to. On load the
## modifiers are rebuilt from current data, so rebalancing an augment reaches
## runs already in progress instead of freezing them at the old numbers.
func get_save_data() -> Dictionary:
	return {"sources": sources()}


## `resolver(source: String) -> Array[StatModifier]`, or null if the source no
## longer exists. Returns false if any source could not be rebuilt: a run with an
## augment silently missing has different balance from the one the player left,
## and like a level with a building missing, that is worse than not loading.
func load_save_data(data: Dictionary, resolver: Callable) -> bool:
	clear()
	var saved: PackedStringArray = data.get("sources", PackedStringArray())
	var unknown := PackedStringArray()
	for source in saved:
		var mods = resolver.call(source)
		if mods == null:
			unknown.append(source)
			continue
		var typed: Array[StatModifier] = []
		typed.assign(mods)
		_by_source[source] = typed
	_changed_all()
	if not unknown.is_empty():
		push_error("ModifierSet: save names sources this build cannot rebuild: %s"
			% ", ".join(unknown))
		return false
	return true


# --- Internals ----------------------------------------------------------------

func _changed(touched: Dictionary) -> void:
	generation += 1
	for stat in touched:
		stat_generation[stat] = generation
	_rebuild_index()
	changed.emit()


func _changed_all() -> void:
	generation += 1
	stat_generation.fill(generation)
	_rebuild_index()
	changed.emit()


func _collect_stats(modifiers: Array, into: Dictionary) -> void:
	for m in modifiers:
		if m != null:
			into[m.stat] = true


func _rebuild_index() -> void:
	_by_stat.resize(Stats.count())
	for i in Stats.count():
		_by_stat[i] = []
	for source in _by_source:
		for m in _by_source[source]:
			if m == null:
				continue
			_by_stat[m.stat].append([source, m])
