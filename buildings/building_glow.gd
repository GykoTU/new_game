class_name BuildingGlow
extends MultiMeshInstance2D
## A faint warm halo over every finished player building at night, so the base
## and the houses stay readable once the world goes dark.
##
## One MultiMesh, one draw call however many buildings stand (D2). The instance
## list is rebuilt only when buildings change, never per frame; the per-frame
## work is one `modulate` assignment, which is how the glow fades in at dusk
## and out at dawn.
##
## Trees, stumps and mines do not glow: only what the player built, which is
## exactly what `LevelGenerator.get_building_data` knows about.
##
## The halo is drawn ADDITIVELY onto a canvas the day/night `CanvasModulate`
## has already darkened, and a CanvasModulate multiplies everything on its
## layer -- the halo included. So `set_night` divides the halo's colour by that
## tint: without it the glow would be dimmed by exactly the darkness it exists
## to fight, and changing `night_light` would silently change the glow too.

## Colour of the halo as it should LOOK on screen. Alpha is its strength at
## full night.
@export var glow_colour := Color(1.0, 0.82, 0.5, 0.30)
## Tiles of halo around the building's own footprint.
@export var margin_tiles := 1.2
## Texture resolution of the generated falloff. 64 is plenty for a blur.
@export var texture_size := 64

var _level: LevelGenerator
var _dirty := true
## Smallest instance_count the MultiMesh is grown to, to avoid reallocating
## every time one house is placed.
const _MIN_INSTANCES := 32


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	# A unit quad: the per-instance transform scales it to the building.
	mm.mesh = UnitRenderer.quad_mesh(1.0)
	mm.instance_count = _MIN_INSTANCES
	mm.visible_instance_count = 0
	multimesh = mm
	texture = _falloff_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	visible = false


func bind(level: LevelGenerator) -> void:
	_level = level
	# Methods, not lambdas: a lambda on a signal keeps this node alive through
	# the level, which is the same cycle WorkerRoster.attach warns about.
	level.level_generated.connect(_mark_dirty)
	level.building_placed.connect(_on_building_changed)
	level.building_removed.connect(_on_building_removed)
	level.construction_completed.connect(_on_construction_completed)


## Called once per rendered frame from main.gd, never from the simulation.
## `darkness` is 0 by day and 1 at full night; `tint` is what the day/night
## CanvasModulate is applying to this canvas right now.
func set_night(darkness: float, tint: Color) -> void:
	visible = darkness > 0.01 and _level != null
	if not visible:
		return
	if _dirty:
		_rebuild()
	modulate = Color(
		glow_colour.r / maxf(tint.r, 0.05),
		glow_colour.g / maxf(tint.g, 0.05),
		glow_colour.b / maxf(tint.b, 0.05),
		glow_colour.a * darkness)


func _mark_dirty() -> void:
	_dirty = true


func _on_building_changed(_type: String, _cell: Vector2i) -> void:
	_dirty = true


func _on_building_removed(_id: int, _type: String, _cell: Vector2i) -> void:
	_dirty = true


func _on_construction_completed(_id: int) -> void:
	_dirty = true


## One instance per finished player building, sized to its footprint.
func _rebuild() -> void:
	_dirty = false
	var tile := float(_level.ground_layer.tile_set.tile_size.x)
	var ids := PackedInt32Array()
	for b in _level.store.alive_ids():
		if _level.store.is_complete(b) and _level.get_building_data(_level.store.get_type(b)) != null:
			ids.append(b)
	var mm := multimesh
	if ids.size() > mm.instance_count:
		mm.instance_count = maxi(ids.size(), mm.instance_count * 2)
	mm.visible_instance_count = ids.size()
	for n in ids.size():
		var b := ids[n]
		var size: Vector2i = _level.store.get_size(b)
		var pos := _level.cell_to_world(_level.store.get_cell(b)) \
			+ _level.get_footprint_offset(size)
		var span := (Vector2(size) + Vector2.ONE * margin_tiles * 2.0) * tile
		mm.set_instance_transform_2d(n, Transform2D(0.0, span, 0.0, pos))


## White, fading to nothing at the edge. Generated, so the halo needs no art.
func _falloff_texture() -> Texture2D:
	var n := maxi(texture_size, 8)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var centre := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - centre, y - centre).length() / centre
			var a := 1.0 - smoothstep(0.0, 1.0, clampf(d, 0.0, 1.0))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
