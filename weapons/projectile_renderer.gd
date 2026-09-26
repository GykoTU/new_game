class_name ProjectileRenderer
extends Node2D
## Draws every shot: one MultiMeshInstance2D per weapon type, so one draw call
## per type however many shots are out (D2). Sprites are drawn pointing right
## and turned to face their flight (WeaponData.rotate_sprite); a horizontal
## strip animates, frame count = width / height, like every other sheet.
##
## Until a weapon's shot sprite exists it is drawn as a soft dot in the
## weapon's projectile_color, sized to its hit radius: plain, but readable.
##
## Shots are light-ish things in a dark night: like the zap, they are drawn
## unlit (the night tint is undone per frame, see CombatEffects).

@export var frame_time := 0.08

const _SHADER := """
shader_type canvas_item;
uniform float frames = 1.0;
varying vec4 v_custom;
void vertex() {
	v_custom = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 uv = UV;
	uv.x = (uv.x + v_custom.r) / frames;
	COLOR = texture(TEXTURE, uv) * vec4(v_custom.gba, 1.0);
}
"""

var _batches: Array = []   # per type: {node, frames, rotate}
var _unlight := Color.WHITE


func _ready() -> void:
	z_index = 1   # with enemies and units: under the fog


func bind(types: Array[WeaponData]) -> void:
	var shader := Shader.new()
	shader.code = _SHADER
	for d in types:
		var tex: Texture2D
		var size: float
		if Art.exists(d.projectile_sprite):
			tex = Art.texture(d.projectile_sprite)
			size = float(tex.get_height())
		else:
			tex = dot_texture(d.projectile_color)
			size = d.projectile_radius * 2.0 + 4.0
		@warning_ignore("integer_division")
		var frames := maxi(tex.get_width() / maxi(tex.get_height(), 1), 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = UnitRenderer.quad_mesh(size)
		mm.instance_count = 32
		mm.visible_instance_count = 0
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("frames", float(frames))
		var node := MultiMeshInstance2D.new()
		node.multimesh = mm
		node.texture = tex
		node.material = mat
		add_child(node)
		_batches.append({"node": node, "frames": frames, "rotate": d.rotate_sprite,
			"skip": d.draw_split, "spin": d.spin_speed})


## Every shot sprite path, for the missing-art report.
static func art_paths(types: Array[WeaponData]) -> Array:
	var out := []
	for d in types:
		if d.projectile_sprite != "" and not out.has(d.projectile_sprite):
			out.append(d.projectile_sprite)
	return out


## A 16x16 soft round dot in `colour`: the stand-in for a missing shot sprite.
static func dot_texture(colour: Color) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8)) / 8.0
			var a := clampf((1.0 - d) * 3.0, 0.0, 1.0)
			var c := colour.lerp(Color.WHITE, clampf(0.5 - d, 0.0, 0.5))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


## Once per rendered frame, after the simulation.
func draw_shots(ps: ProjectileStore, tick: int, tint: Color = Color.WHITE) -> void:
	_unlight = Color(1.0 / maxf(tint.r, 0.05), 1.0 / maxf(tint.g, 0.05), 1.0 / maxf(tint.b, 0.05))
	var lists := []
	for b in _batches:
		lists.append(PackedInt32Array())
	if ps.alive_count() > 0:
		for p in ps.alive_ids():
			var t := ps.type[p]
			if t >= 0 and t < lists.size():
				lists[t].append(p)
	var tpf := maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	for t in _batches.size():
		var batch: Dictionary = _batches[t]
		var ids: PackedInt32Array = lists[t] if not batch["skip"] else PackedInt32Array()
		var mm: MultiMesh = batch["node"].multimesh
		if ids.size() > mm.instance_count:
			mm.instance_count = maxi(ids.size(), mm.instance_count * 2)
		mm.visible_instance_count = ids.size()
		var frames: int = batch["frames"]
		var turn: bool = batch["rotate"]
		var spin: float = batch["spin"]
		for n in ids.size():
			var p := ids[n]
			var rot := 0.0
			if ps.state[p] == ProjectileStore.State.HELD:
				rot = ps.angle[p]
			elif spin != 0.0:
				rot = (tick - ps.born[p]) * GameClock.TICK_DELTA * spin
			elif turn and ps.vel[p] != Vector2.ZERO:
				rot = ps.vel[p].angle()
				if ps.state[p] == ProjectileStore.State.RETURN:
					rot += PI   # a reeling hook still points away from its tower
			mm.set_instance_transform_2d(n, Transform2D(rot, ps.pos[p]))
			@warning_ignore("integer_division")
			var frame := ((tick - ps.born[p]) / tpf) % frames
			mm.set_instance_custom_data(n, Color(float(frame), _unlight.r, _unlight.g, _unlight.b))
