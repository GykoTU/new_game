class_name BuildingStats
extends RefCounted
## Building health as a stat (Stage 7): one StatBlock per building type
## (D7), tagged with the type's tags plus "building" and its id, whose
## MAX_HEALTH starts at BuildingData.max_health. So "+25% health for walls" is
## an ordinary modifier on ["wall"].
##
## Applied to every building of the type whenever modifiers change, to each
## new one as it is placed, and to the whole map after a load. Health keeps its
## share of the maximum (BuildingStore.set_max_health).

var level: LevelGenerator
var modifiers: ModifierSet
var _blocks := {}   # building type -> StatBlock


func setup(p_level: LevelGenerator, p_modifiers: ModifierSet) -> void:
	level = p_level
	modifiers = p_modifiers
	for data in level.placeable_buildings:
		if data == null or _blocks.has(data.id):
			continue
		var tags := PackedStringArray(data.tags)
		for t in ["building", data.id]:
			if not tags.has(t):
				tags.append(t)
		_blocks[data.id] = StatBlock.new(modifiers, tags, {Stats.Id.MAX_HEALTH: data.max_health})
	# Methods, not lambdas.
	modifiers.changed.connect(apply_all)
	level.level_generated.connect(apply_all)
	level.building_placed.connect(_on_placed)


func max_health_of(type: String) -> float:
	var block: StatBlock = _blocks.get(type)
	return block.get_value(Stats.Id.MAX_HEALTH) if block != null else 0.0


func apply_all() -> void:
	for b in level.store.alive_ids():
		_apply(b)


func _on_placed(_type: String, cell: Vector2i) -> void:
	_apply(level.grid.get_occupant(cell))


func _apply(b: int) -> void:
	if not level.store.is_alive(b):
		return
	var block: StatBlock = _blocks.get(level.store.get_type(b))
	if block == null:
		return
	var v := block.get_value(Stats.Id.MAX_HEALTH)
	if not is_equal_approx(v, level.store.get_max_health(b)):
		level.store.set_max_health(b, v)
