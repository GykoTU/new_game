class_name BaseDefence
extends RefCounted
## The base fights back (Stage 4): every so often it zaps the nearest enemy in
## range. Until Stage 5's weapon buildings, this is the only thing that kills.
##
## Damage, fire rate and range are ordinary stats on a StatBlock tagged
## "building", "base", "weapon", so an upgrade or augment that targets those
## tags reaches it with no special code (D7, D9).

## Recent zaps for CombatEffects to draw: [from, to, tick]. Drained there.
var zaps: Array = []
var stats: StatBlock
var level: LevelGenerator
var enemies: EnemySystem

var _cooldown := 0


func setup(p_level: LevelGenerator, p_enemies: EnemySystem, modifiers: ModifierSet) -> void:
	level = p_level
	enemies = p_enemies
	stats = StatBlock.new(modifiers, PackedStringArray(["building", "base", "weapon"]), {
		Stats.Id.DAMAGE: 12.0,
		Stats.Id.FIRE_RATE: 1.25,
		Stats.Id.RANGE: 176.0,   # five and a half tiles
	})


func clear() -> void:
	zaps.clear()
	_cooldown = 0


func range_px() -> float:
	return stats.get_value(Stats.Id.RANGE)


## One simulation tick. Uses the spatial hash EnemySystem.step() just built.
func step(tick: int) -> void:
	if _cooldown > 0:
		_cooldown -= 1
		if _cooldown > 0:
			return
	if level.base_cell == LevelGenerator.INVALID_CELL or enemies.count() == 0:
		return
	var from := level.get_base_position()
	# The hash was built at the start of this tick: skip anything killed since.
	var r := range_px()
	var e := -1
	var best := r * r
	for id in enemies.nearby.query(from, r):
		if not enemies.is_alive(id):
			continue
		var d := enemies.pos[id].distance_squared_to(from)
		if d <= best:
			best = d
			e = id
	if e == -1:
		return   # ready, and fires the moment something comes in range
	zaps.append([from, enemies.pos[e], tick])
	enemies.damage(e, stats.get_value(Stats.Id.DAMAGE), true)
	_cooldown = maxi(int(round(1.0 / stats.get_value(Stats.Id.FIRE_RATE) / GameClock.TICK_DELTA)), 1)
