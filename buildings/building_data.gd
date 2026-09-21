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

## Resources paid when this building is ordered in play (a miner home is paid
## for when a miner is assigned to a mine without one). Moves to the Craft
## section of the shop in Stage 2b.
@export var cost: Dictionary[ResourceKind.Id, int] = {}

@export_group("Housing")
## A house gives beds to one kind of unit; capacity is the HOUSE_CAPACITY stat.
@export var is_house := false
@export var house_for: WorkerRoster.Kind = WorkerRoster.Kind.BUILDER

@export_group("Grid")
## Units cannot walk through this building's tiles. True for almost everything.
@export var blocks_units := true
## Projectiles stop at this building's tiles. Walls set this; weapons and mines
## do not, or your own defences would shoot each other's cover.
@export var blocks_projectiles := false
## Which ground types it can be built on. Order matches LevelGenerator.Ground.
@export_flags("Grass 1", "Grass 2", "Grass 3", "Flowers", "Ice", "Lava", "Water", "Sand", "Void")
var allowed_grounds := 0b000000111 # all three grass types by default


func get_texture() -> Texture2D:
	if texture != null:
		return texture
	return Art.texture(texture_path)
