class_name BuildingData
extends Resource
## Describes a building the player can place. Create one per building type:
## FileSystem dock -> right-click -> Create New -> Resource -> BuildingData.

## Unique name used in code and save files, e.g. "base", "farm", "storage".
@export var id := ""
@export var display_name := ""
## Either a texture, or (preferred for new buildings) a path: a path whose file
## is missing shows the placeholder instead of making this resource fail to
## load. Read through get_texture(), never directly.
@export var texture: Texture2D
@export_file("*.png") var texture_path := ""
## Size in tiles. The building's cell is its top-left corner.
@export var size := Vector2i.ONE
## Only one can exist at a time (e.g. the base).
@export var unique := false
## Hit points. Enemies destroy buildings; building workers repair them.
@export var max_health := 100.0
## Builder-seconds to construct at build_speed 1.0. 0 = appears complete.
## Two builders finish in half the time.
@export var build_work := 0.0
## For stat targeting, e.g. ["building", "house", "builder_house"].
@export var tags := PackedStringArray()
## Tiles of fog cleared around it, once, when it is finished. 0 = none.
## The watchtower's whole job; any building can have one.
@export var reveal_radius := 0

@export_group("Placement")
## If set, it must be placed touching (8 neighbours) a building whose type
## starts with this, e.g. "mine_" for a miner house.
@export var must_touch_prefix := ""
## With must_touch_prefix: the touched building may not already be touched by
## another building of this type. One miner house per mine.
@export var one_per_touched := false

@export_group("Housing")
## A house gives beds to one kind of unit; capacity is the HOUSE_CAPACITY stat.
@export var is_house := false
@export var house_for: WorkerRoster.Kind = WorkerRoster.Kind.BUILDER
## Beds before upgrades: the base of this house type's HOUSE_CAPACITY stat.
## 0 = the stat's registry default (3).
@export var beds := 0

@export_group("Grid")
## Units cannot walk through this building's tiles. True for almost everything.
@export var blocks_units := true
## Projectiles stop at this building's tiles. Walls set this; weapons and mines
## do not, or your own defences would shoot each other's cover.
@export var blocks_projectiles := false
## Which ground types it can be built on. Order matches LevelGenerator.Ground.
@export_flags("Grass 1", "Grass 2", "Grass 3", "Flowers", "Ice", "Lava", "Water", "Sand", "Void", "Cobble")
var allowed_grounds := 0b000000111 # all three grass types by default


func get_texture() -> Texture2D:
	if texture != null:
		return texture
	return Art.texture(texture_path)
