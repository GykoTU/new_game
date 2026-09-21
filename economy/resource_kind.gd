class_name ResourceKind
extends RefCounted
## Registry of every gatherable resource: id, save key, display name, icon, and
## the building that yields it.
##
## Adding a resource is one enum entry and one table row.

## APPEND-ONLY, for the same reason as Stats.Id: shop items store costs keyed by
## this integer, so reordering silently changes what things cost. Saves use the
## string key instead, so they survive even a mistake here.
enum Id {
	GOLD,
	QUARTZ,
	COPPER,
	DIAMOND,
	FRUIT,
	COUNT,
}

const _TABLE := [
	# id           save key    display     icon                               yielded by
	[Id.GOLD,    "gold",    "Gold",    "res://assets/ui/gold_coin.png", "mine_gold"],
	[Id.QUARTZ,  "quartz",  "Quartz",  "res://assets/ui/quartz.png",    "mine_quartz"],
	[Id.COPPER,  "copper",  "Copper",  "res://assets/ui/copper.png",    "mine_copper"],
	[Id.DIAMOND, "diamond", "Diamond", "res://assets/ui/diamond.png",   "mine_diamond"],
	[Id.FRUIT,   "fruit",   "Fruit",   "res://assets/ui/fruit.png",     "tree_fruit"],
]

static var _keys := PackedStringArray()
static var _display := PackedStringArray()
static var _icons := PackedStringArray()
static var _sources := PackedStringArray()
static var _ids_by_key := {}


static func _static_init() -> void:
	_keys.resize(Id.COUNT)
	_display.resize(Id.COUNT)
	_icons.resize(Id.COUNT)
	_sources.resize(Id.COUNT)
	if _TABLE.size() != Id.COUNT:
		push_error("ResourceKind: table has %d rows but Id has %d." % [_TABLE.size(), Id.COUNT])
	for i in _TABLE.size():
		var row: Array = _TABLE[i]
		if row[0] != i:
			push_error("ResourceKind: row %d is for id %d. Rows must be in Id order." % [i, row[0]])
		_keys[i] = row[1]
		_display[i] = row[2]
		_icons[i] = row[3]
		_sources[i] = row[4]
		_ids_by_key[row[1]] = i


# Named *_of rather than get_*: on the class itself, get_name() and friends
# resolve to the script resource's built-ins and silently shadow these.
static func count() -> int:
	return Id.COUNT


static func key_of(id: int) -> String:
	return _keys[id]


static func display_of(id: int) -> String:
	return _display[id]


static func icon_path_of(id: int) -> String:
	return _icons[id]


## The building type that yields this resource, e.g. "mine_gold".
static func source_of(id: int) -> String:
	return _sources[id]


## -1 if unknown.
static func id_from_key(key: String) -> int:
	return _ids_by_key.get(key, -1)
