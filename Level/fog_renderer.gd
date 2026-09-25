class_name FogRenderer
extends Sprite2D
## Draws the fog: ONE texture, one pixel per tile, stretched over the map by
## this sprite and turned into darkness by a tiny shader. One draw call and no
## node per tile, however big the map.
##
## WorldGrid.explored is stored as 0 / 255 precisely so it can be handed to an
## L8 image as it is: rebuilding the texture is one native copy, no GDScript
## loop. It happens at most once per rendered frame, and only after something
## was revealed.
##
## Linear filtering blends neighbouring pixels, which is what softens the fog's
## edge. The shader then doubles the fog's slope so it is fully opaque by the
## BOUNDARY of the first hidden tile: a hidden tile is never partly visible,
## and only the outer half of the last explored tile is shaded.

const _SHADER := """
shader_type canvas_item;
uniform vec4 fog_colour : source_color = vec4(0.015, 0.015, 0.025, 1.0);
void fragment() {
	float seen = texture(TEXTURE, UV).r;
	COLOR = vec4(fog_colour.rgb, fog_colour.a * clamp((1.0 - seen) * 2.0, 0.0, 1.0));
}
"""

var _level: LevelGenerator
var _fog: FogOfWar
var _image: Image
var _texture: ImageTexture
var _dirty := true


func _ready() -> void:
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Over the ground, buildings, drops, units (1) and the night glow; under
	# the build placer's ghost (100), which may be dragged across the fog edge.
	z_index = 2
	var shader := Shader.new()
	shader.code = _SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat


func bind(level: LevelGenerator, fog: FogOfWar) -> void:
	_level = level
	_fog = fog
	# Methods, not lambdas (see WorkerRoster.attach).
	level.level_generated.connect(_mark_dirty)
	fog.revealed.connect(_on_revealed)


func _mark_dirty() -> void:
	_dirty = true


func _on_revealed(_indices: PackedInt32Array) -> void:
	_dirty = true


## Called once per rendered frame from main.gd, never from the simulation.
func refresh() -> void:
	if not _dirty or _level == null or _level.ground_layer == null:
		return
	_dirty = false
	var g := _level.grid
	if g.tile_count() == 0:
		visible = false
		return
	visible = _fog.any_hidden()
	if not visible:
		return
	if _image == null or _image.get_size() != g.size:
		_image = Image.create_from_data(g.size.x, g.size.y, false, Image.FORMAT_L8, g.explored)
		_texture = ImageTexture.create_from_image(_image)
		texture = _texture
	else:
		_image.set_data(g.size.x, g.size.y, false, Image.FORMAT_L8, g.explored)
		_texture.update(_image)
	# One texture pixel per tile, with its top-left on tile (0, 0)'s corner.
	var tile := Vector2(_level.ground_layer.tile_set.tile_size)
	scale = tile
	global_position = _level.cell_to_world(Vector2i.ZERO) - tile / 2.0
