class_name StormRenderer
extends Sprite2D
## Draws the snowstorm (Stage 10) the way FogRenderer draws the fog: one
## texture, one pixel per tile (SnowStorm.storm, 255 = covered), stretched over
## the map. The shader turns covered tiles into a thick, drifting white-grey
## haze, from assets/effects/snowstorm.png when it exists (tiled, scrolling),
## else from noise. Rebuilt only when the storm changes (a few times a second).

const TEXTURE := "res://assets/effects/snowstorm.png"

const _SHADER := """
shader_type canvas_item;
uniform sampler2D drift : repeat_enable, filter_linear;
uniform bool has_drift = false;
uniform vec2 tiles = vec2(160.0, 120.0);
uniform vec4 haze : source_color = vec4(0.86, 0.89, 0.94, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float covered = texture(TEXTURE, UV).r;
	float a = clamp(covered * 2.0 - 0.15, 0.0, 1.0);
	vec2 p = UV * tiles;
	vec3 col = haze.rgb;
	float n;
	if (has_drift) {
		vec4 d = texture(drift, p * 0.5 + vec2(TIME * 0.35, TIME * 0.12));
		col = mix(col, d.rgb, d.a * 0.8);
		n = 0.9;
	} else {
		n = 0.82 + 0.18 * noise(p * 1.5 + vec2(TIME * 0.8, TIME * 0.3));
		col *= 0.92 + 0.08 * noise(p * 4.0 - vec2(TIME * 1.6, 0.0));
	}
	COLOR = vec4(col, a * n * haze.a);
}
"""

var _level: LevelGenerator
var _storm: SnowStorm
var _image: Image
var _texture: ImageTexture
var _version := -1


func _ready() -> void:
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Over everything in the world like the fog (which it sits just under).
	z_index = 2
	var shader := Shader.new()
	shader.code = _SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if Art.exists(TEXTURE):
		mat.set_shader_parameter("drift", Art.texture(TEXTURE))
		mat.set_shader_parameter("has_drift", true)
	material = mat


static func art_paths() -> Array:
	return [TEXTURE]


func bind(level: LevelGenerator, storm: SnowStorm) -> void:
	_level = level
	_storm = storm


## Called once per rendered frame from main.gd, never from the simulation.
func refresh() -> void:
	if _level == null or _storm == null or _level.ground_layer == null:
		return
	visible = _storm.has_snow()
	if not visible or _storm.version == _version:
		return
	_version = _storm.version
	var g := _level.grid
	if _storm.storm.size() != g.tile_count():
		return
	if _image == null or _image.get_size() != g.size:
		_image = Image.create_from_data(g.size.x, g.size.y, false, Image.FORMAT_L8, _storm.storm)
		_texture = ImageTexture.create_from_image(_image)
		texture = _texture
	else:
		_image.set_data(g.size.x, g.size.y, false, Image.FORMAT_L8, _storm.storm)
		_texture.update(_image)
	(material as ShaderMaterial).set_shader_parameter("tiles", Vector2(g.size))
	var tile := Vector2(_level.ground_layer.tile_set.tile_size)
	scale = tile
	global_position = _level.cell_to_world(Vector2i.ZERO) - tile / 2.0
