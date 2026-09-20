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
## Which ground types it can be built on. Order matches LevelGenerator.Ground.
@export_flags("Grass 1", "Grass 2", "Grass 3", "Flowers", "Ice", "Lava", "Water", "Sand", "Void")
var allowed_grounds := 0b000000111 # all three grass types by default
