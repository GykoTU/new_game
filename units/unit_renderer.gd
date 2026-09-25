class_name UnitRenderer
extends Node2D
## Draws every unit, one MultiMeshInstance2D per (kind, animation): one draw
## call per batch however many units there are (D2). Drops lying on the ground
## are drawn here too, one batch per resource, underneath the units.
##
## A shader picks each unit's frame from a horizontal-strip sheet and mirrors
## it when the unit faces left. The frame count is read from the sheet itself
## (width / height), so a new sheet needs no code change. Frames advance on the
## simulation tick, so animation pauses with the game and speeds up with it.

## Seconds per animation frame (Aseprite's default is 100 ms).
@export var frame_time := 0.1

## Sprites per unit kind. "walk" is optional: listed or not, while its file
## does not exist the idle sprite is used for walking too (never a placeholder).
const LOOKS := {
	WorkerRoster.Kind.MINER: {"idle": "res://assets/npcs/worker.png"},
	WorkerRoster.Kind.BUILDER: {"idle": "res://assets/npcs/builder.png"},
	WorkerRoster.Kind.CARRIER: {"idle": "res://assets/npcs/carrier.png",
		"walk": "res://assets/npcs/carrier_walk.png"},
	WorkerRoster.Kind.EXPLORER: {"idle": "res://assets/npcs/explorer.png",
		"walk": "res://assets/npcs/explorer_walk.png"},
}

const _SHADER := """
shader_type canvas_item;
uniform float frames = 1.0;
varying vec2 v_custom;
void vertex() {
	v_custom = INSTANCE_CUSTOM.xy;
}
void fragment() {
	vec2 uv = UV;
	if (v_custom.y > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	uv.x = (uv.x + v_custom.x) / frames;
	COLOR = texture(TEXTURE, uv);
}
"""

## "kind:anim" -> {node: MultiMeshInstance2D, frames: int}
var _batches := {}
## ResourceKind.Id -> MultiMeshInstance2D
var _drop_batches := {}
var _mesh: ArrayMesh


func _ready() -> void:
	# Above building sprites, so a unit walking past a house is never hidden.
	z_index = 1
	_mesh = quad_mesh(32.0)
	var shader := Shader.new()
	shader.code = _SHADER
	# Drops first: children draw in order, so these end up under the units.
	# A drop uses its resource's icon until the artist draws dedicated sprites.
	for rkind in ResourceKind.count():
		var dmm := MultiMesh.new()
		dmm.transform_format = MultiMesh.TRANSFORM_2D
		dmm.mesh = _mesh
		dmm.instance_count = 16
		dmm.visible_instance_count = 0
		var dnode := MultiMeshInstance2D.new()
		dnode.multimesh = dmm
		dnode.texture = Art.texture(ResourceKind.icon_path_of(rkind))
		add_child(dnode)
		_drop_batches[rkind] = dnode
	for kind in LOOKS:
		for anim in LOOKS[kind]:
			if anim == "walk" and not Art.exists(LOOKS[kind][anim]):
				continue   # not drawn yet: walk with the idle sprite
			var tex := Art.texture(LOOKS[kind][anim])
			@warning_ignore("integer_division")
			var frames := maxi(tex.get_width() / maxi(tex.get_height(), 1), 1)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_2D
			mm.use_custom_data = true
			mm.mesh = _mesh
			mm.instance_count = 16
			mm.visible_instance_count = 0
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("frames", float(frames))
			var node := MultiMeshInstance2D.new()
			node.multimesh = mm
			node.texture = tex
			node.material = mat
			add_child(node)
			_batches["%d:%s" % [kind, anim]] = {"node": node, "frames": frames}


## Rebuilds every batch from the unit store. Called once per rendered frame,
## never from the simulation.
func draw_units(store: UnitStore, tick: int) -> void:
	var lists := {}
	for key in _batches:
		lists[key] = PackedInt32Array()
	for id in store.size():
		# Inside a building (home, base, or stationed at a mine): not drawn.
		if not store.is_alive(id) or store.inside[id] == 1 \
				or store.state[id] == UnitStore.State.STATIONED:
			continue
		var k: int = store.kind[id]
		var anim := "walk" if store.state[id] == UnitStore.State.WALKING \
			and _batches.has("%d:walk" % k) else "idle"
		lists["%d:%s" % [k, anim]].append(id)

	var ticks_per_frame := maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var ids: PackedInt32Array = lists[key]
		# Sort by y so overlapping units stack front-to-back correctly.
		var arr := Array(ids)
		arr.sort_custom(func(a, b): return store.pos[a].y < store.pos[b].y)
		var mm: MultiMesh = batch["node"].multimesh
		if arr.size() > mm.instance_count:
			mm.instance_count = maxi(arr.size(), mm.instance_count * 2)
		mm.visible_instance_count = arr.size()
		var frames: int = batch["frames"]
		for n in arr.size():
			var id: int = arr[n]
			mm.set_instance_transform_2d(n, Transform2D(0.0, store.pos[id]))
			@warning_ignore("integer_division")
			var frame := ((tick + store.anim_offset[id]) / ticks_per_frame) % frames
			mm.set_instance_custom_data(n, Color(float(frame), float(store.facing_left[id]), 0, 0))


## Rebuilds the drop batches. Bouncing drops follow their arc (DropStore).
func draw_drops(drops: DropStore, tick: int) -> void:
	var lists := {}
	for rkind in _drop_batches:
		lists[rkind] = PackedInt32Array()
	for d in drops.size():
		if drops.is_alive(d):
			lists[drops.kind[d]].append(d)
	for rkind in _drop_batches:
		var ids: PackedInt32Array = lists[rkind]
		var mm: MultiMesh = _drop_batches[rkind].multimesh
		if ids.size() > mm.instance_count:
			mm.instance_count = maxi(ids.size(), mm.instance_count * 2)
		mm.visible_instance_count = ids.size()
		for n in ids.size():
			mm.set_instance_transform_2d(n, Transform2D(0.0, drops.draw_pos(ids[n], tick)))


## A 2D quad built by hand: a 3D QuadMesh has Y pointing up and would draw
## every sprite upside down.
## A centred textured quad. Shared: BuildingGlow builds its halo from one too.
static func quad_mesh(size: float) -> ArrayMesh:
	var h := size / 2.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh
