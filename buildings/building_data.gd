class_name BuildingData
extends Resource
## Describes a building the player can place. Create one per building type:
## FileSystem dock -> right-click -> Create New -> Resource -> BuildingData.

## Unique name used in code and save files, e.g. "base", "farm", "storage".
@export var id := ""
@export var display_name := ""
@export var texture: Texture2D
## Size in tiles. The building's cell is its top-left corner.
@export var size := Vector2i.ONE
## Only one can exist at a time (e.g. the base).
@export var unique := false
## Hit points. Enemies destroy buildings; building workers repair them.
@export var max_health := 100.0

@export_group("Grid")
## Units cannot walk through this building's tiles. True for almost everything.
@export var blocks_units := true
## Projectiles stop at this building's tiles. Walls set this; weapons and mines
## do not, or your own defences would shoot each other's cover.
@export var blocks_projectiles := false
## Which ground types it can be built on. Order matches LevelGenerator.Ground.
@export_flags("Grass 1", "Grass 2", "Grass 3", "Flowers", "Ice", "Lava", "Water", "Sand", "Void")
var allowed_grounds := 0b000000111 # all three grass types by default
