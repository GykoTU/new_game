class_name Stats
extends RefCounted
## Registry of every stat in the game: its id, name, default and clamp range.
##
## Adding a stat is one enum entry and one table row. Ids are ints, so resolving
## a stat is an array index, never a string hash.
##
## Many stats exist to parameterise a *behaviour* rather than to be a number in
## their own right: bounce_count is read by the bounce behaviour, area_radius by
## explosions. That is the bridge between the two systems -- behaviours decide
## what happens, stats decide how much -- and it is why an upgrade like
## "+1 bounce" needs no special code. See docs/mechanics-coverage.md.

## APPEND-ONLY. StatModifier .tres files store the stat as an integer, so
## inserting or reordering an entry silently retargets every saved modifier to
## the wrong stat. New stats go at the end, just before COUNT. Never remove one;
## retire it by leaving it unused.
enum Id {
	# --- weapons and projectiles
	DAMAGE,
	FIRE_RATE,
	RANGE,
	PROJECTILE_SPEED,
	PROJECTILE_COUNT,
	PROJECTILE_LIFETIME,
	PIERCE_COUNT,
	BOUNCE_COUNT,
	SPLIT_COUNT,
	AREA_RADIUS,
	ORBIT_RADIUS,
	# --- effects applied to what gets hit
	KNOCKBACK,
	PULL_STRENGTH,
	SLOW_STRENGTH,
	SLOW_DURATION,
	BURN_DPS,
	BURN_DURATION,
	# --- units
	MOVE_SPEED,
	GATHER_RATE,
	CARRY_CAPACITY,
	# --- buildings
	MAX_HEALTH,
	BUILD_SPEED,
	REPAIR_RATE,
	# --- economy
	SHOP_PRICE,
	HOUSE_CAPACITY,
	COUNT,
}

## One row per stat, in Id order. Checked at load time: a missing, extra or
## misordered row is reported immediately rather than surfacing later as the
## wrong stat being read.
##
## Clamps are deliberate. A game built on stacking multipliers WILL eventually
## push fire_rate towards zero or slow_strength to 100%, and the first symptom is
## a division by zero or an enemy frozen forever, far away from whatever caused
## it. Bounding at the source is cheaper than hunting it down.
##
## FIRE_RATE is shots per second rather than a cooldown, so that "+20%" is
## always good news; consumers compute cooldown as 1.0 / fire_rate.
## Counts are stored as floats and rounded by whoever consumes them.
const _TABLE := [
	# id                       name                   default  min    max
	[Id.DAMAGE,              "damage",               10.0,   0.0,   INF],
	[Id.FIRE_RATE,           "fire_rate",             1.0,   0.05,  60.0],
	[Id.RANGE,               "range",               160.0,   0.0,   INF],
	[Id.PROJECTILE_SPEED,    "projectile_speed",    240.0,   0.0,   4000.0],
	[Id.PROJECTILE_COUNT,    "projectile_count",      1.0,   1.0,   64.0],
	[Id.PROJECTILE_LIFETIME, "projectile_lifetime",   2.0,   0.05,  60.0],
	[Id.PIERCE_COUNT,        "pierce_count",          0.0,   0.0,   64.0],
	[Id.BOUNCE_COUNT,        "bounce_count",          0.0,   0.0,   64.0],
	[Id.SPLIT_COUNT,         "split_count",           0.0,   0.0,   8.0],
	[Id.AREA_RADIUS,         "area_radius",           0.0,   0.0,   INF],
	[Id.ORBIT_RADIUS,        "orbit_radius",          0.0,   0.0,   INF],
	[Id.KNOCKBACK,           "knockback",             0.0,   0.0,   INF],
	[Id.PULL_STRENGTH,       "pull_strength",         0.0,   0.0,   INF],
	[Id.SLOW_STRENGTH,       "slow_strength",         0.0,   0.0,   0.9],
	[Id.SLOW_DURATION,       "slow_duration",         0.0,   0.0,   60.0],
	[Id.BURN_DPS,            "burn_dps",              0.0,   0.0,   INF],
	[Id.BURN_DURATION,       "burn_duration",         0.0,   0.0,   60.0],
	[Id.MOVE_SPEED,          "move_speed",           60.0,   0.0,   2000.0],
	[Id.GATHER_RATE,         "gather_rate",           1.0,   0.0,   INF],
	[Id.CARRY_CAPACITY,      "carry_capacity",       10.0,   0.0,   INF],
	[Id.MAX_HEALTH,          "max_health",          100.0,   1.0,   INF],
	[Id.BUILD_SPEED,         "build_speed",           1.0,   0.0,   INF],
	[Id.REPAIR_RATE,         "repair_rate",           1.0,   0.0,   INF],
	[Id.SHOP_PRICE,          "shop_price",            1.0,   0.1,   INF],
	[Id.HOUSE_CAPACITY,      "house_capacity",        3.0,   1.0,   64.0],
]

static var _names := PackedStringArray()
static var _defaults := PackedFloat64Array()
static var _mins := PackedFloat64Array()
static var _maxs := PackedFloat64Array()
static var _ids_by_name := {}


static func _static_init() -> void:
	_names.resize(Id.COUNT)
	_defaults.resize(Id.COUNT)
	_mins.resize(Id.COUNT)
	_maxs.resize(Id.COUNT)
	if _TABLE.size() != Id.COUNT:
		push_error("Stats: table has %d rows but Id has %d stats." % [_TABLE.size(), Id.COUNT])
	for i in _TABLE.size():
		var row: Array = _TABLE[i]
		if row[0] != i:
			push_error("Stats: table row %d is for id %d. Rows must be in Id order." % [i, row[0]])
		_names[i] = row[1]
		_defaults[i] = row[2]
		_mins[i] = row[3]
		_maxs[i] = row[4]
		_ids_by_name[row[1]] = i


static func count() -> int:
	return Id.COUNT


## Accessors are deliberately NOT named get_name / get_default: called on the
## class (Stats.get_name), those resolve to the built-in methods of the script
## resource itself and silently shadow these, failing only at runtime.
static func name_of(id: int) -> String:
	return _names[id]


static func default_of(id: int) -> float:
	return _defaults[id]


static func min_of(id: int) -> float:
	return _mins[id]


static func max_of(id: int) -> float:
	return _maxs[id]


## -1 if no stat has that name. For data files and debugging, never for hot code.
static func id_from_name(stat_name: String) -> int:
	return _ids_by_name.get(stat_name, -1)


## The one place the order of operations is decided. Do not reorder this.
##
##     final = (base + flat) * (1 + sum of increases) * product of multipliers
##
## Increases ADD to each other: two +50% increases give x2.
## Multipliers MULTIPLY: two x1.5 multipliers give x2.25.
## That difference is what lets a rare augment be worth more than a common one,
## and it only means anything if the order never varies.
static func combine(id: int, base: float, flat: float, increase: float, multiplier: float) -> float:
	var value := (base + flat) * (1.0 + increase) * multiplier
	return clampf(value, _mins[id], _maxs[id])
