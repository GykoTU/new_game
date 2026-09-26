class_name EnemyRenderer
extends Node2D
## Draws every enemy: one MultiMeshInstance2D per (kind, animation), so one
## draw call per batch however many enemies there are (D2), sorted by y inside
## each batch. Same sheet convention as UnitRenderer: a horizontal strip whose
## frame count is width / height.
##
## The shader also shows two things the simulation knows: a white HIT FLASH
## (EnemyStore.flash) and an orange BURN tint (dawn, and later burn effects).
## Animation sheets that do not exist yet are skipped, never shown as a
## placeholder: walk falls back to idle, attack to walk.

## Seconds per animation frame.
@export var frame_time := 0.1

const _SHADER := """
shader_type canvas_item;
uniform float frames = 1.0;
varying vec4 v_custom;
void vertex() {
	v_custom = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 uv = UV;
	if (v_custom.g > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	uv.x = (uv.x + v_custom.r) / frames;
	vec4 c = texture(TEXTURE, uv);
	c.rgb = mix(c.rgb, vec3(1.0, 0.45, 0.12), v_custom.a * 0.55);
	c.rgb = mix(c.rgb, vec3(1.0), v_custom.b);
	COLOR = c;
}
"""

const ANIMS := ["idle", "walk", "attack"]

var _batches := {}   # "kind:anim" -> {node, frames}
var _kinds: Array[EnemyData] = []
var _mesh: ArrayMesh


func _ready() -> void:
	z_index = 1   # with the units: over buildings, under the fog


func bind(kinds: Array[EnemyData]) -> void:
	_kinds = kinds
	_mesh = UnitRenderer.quad_mesh(32.0)
	var shader := Shader.new()
	shader.code = _SHADER
	for k in kinds.size():
		var d := kinds[k]
		var paths := {"idle": d.sprite_idle, "walk": d.sprite_walk, "attack": d.sprite_attack}
		for anim in ANIMS:
			var path: String = paths[anim]
			if anim != "idle" and not Art.exists(path):
				continue
			var tex := Art.texture(path)
			@warning_ignore("integer_division")
			var frames := maxi(tex.get_width() / maxi(tex.get_height(), 1), 1)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_2D
			mm.use_custom_data = true
			mm.mesh = _mesh
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
			_batches["%d:%s" % [k, anim]] = {"node": node, "frames": frames}


## Every sprite path the enemies may use, for the missing-art report.
static func art_paths(kinds: Array[EnemyData]) -> Array:
	var out := []
	for d in kinds:
		for path in [d.sprite_idle, d.sprite_walk, d.sprite_attack]:
			if path != "":
				out.append(path)
	return out


func _anim_for(k: int, attacking: bool) -> String:
	if attacking and _batches.has("%d:attack" % k):
		return "attack"
	if _batches.has("%d:walk" % k):
		return "walk"
	return "idle"


## Once per rendered frame, after the simulation.
func draw_enemies(store: EnemyStore, tick: int) -> void:
	var lists := {}
	for key in _batches:
		lists[key] = []
	for e in EnemyStore.CAP:
		if not store.is_alive(e):
			continue
		var k: int = store.kind[e]
		lists["%d:%s" % [k, _anim_for(k, store.state[e] == EnemyStore.State.ATTACK)]].append(e)
	var ticks_per_frame := maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var ids: Array = lists[key]
		ids.sort_custom(func(a, b): return store.pos[a].y < store.pos[b].y)
		var mm: MultiMesh = batch["node"].multimesh
		if ids.size() > mm.instance_count:
			mm.instance_count = maxi(ids.size(), mm.instance_count * 2)
		mm.visible_instance_count = ids.size()
		var frames: int = batch["frames"]
		for n in ids.size():
			var e: int = ids[n]
			mm.set_instance_transform_2d(n, Transform2D(0.0, store.pos[e]))
			@warning_ignore("integer_division")
			var frame := ((tick + store.anim_offset[e]) / ticks_per_frame) % frames
			var burning := 1.0 if store.burn_ticks[e] > 0 else 0.0
			mm.set_instance_custom_data(n, Color(float(frame), float(store.facing_left[e]),
				minf(store.flash[e] / 6.0, 1.0), burning))
