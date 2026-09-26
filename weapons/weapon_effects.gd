class_name WeaponEffects
extends Node2D
## What the weapons leave on screen besides the shots themselves: hook ropes,
## the chain cannon's balls (drawn here, not by ProjectileRenderer, because
## their chain can pay out), frost chain arcs, explosions, burning ground,
## frost hits, stunned enemies, and the range circle of the weapon the player
## selected. Drawn with _draw
## from the lists the simulation fills (EffectSystem.blasts, WeaponSystem.arcs
## and chill_marks), which this node drains every frame.
##
## Every sprite is optional. Without one: an explosion is an expanding orange
## disc and ring, burning ground a flickering orange patch, the chain balls
## two dots and a line, a frost hit nothing extra, a stun three circling
## dots. Fire, frost and shots are drawn unlit (see CombatEffects); ropes are
## lit objects.

const EXPLOSION := "res://assets/effects/explosion.png"
const BURNING_GROUND := "res://assets/effects/burning_ground.png"
const FROST_HIT := "res://assets/effects/frost_hit.png"
const STUN := "res://assets/effects/stun.png"

@export var blast_seconds := 0.3
@export var arc_seconds := 0.15
@export var frame_time := 0.07

## The building whose range is shown, or -1. Set by main.gd.
var selected := -1

var _w: WeaponSystem
var _blasts: Array = []   # [pos, radius, tick]
var _arcs: Array = []     # [from, to, tick, seed]
var _chills: Array = []   # [pos, tick]
var _tick := 0
var _unlight := Color.WHITE
var _explosion: Texture2D
var _ground: Texture2D
var _frost: Texture2D
var _stun: Texture2D
var _rope_types := {}     # weapon type index -> true for hooks
var _split_types := {}    # weapon type index -> its sprite (or null) for draw_split


func _ready() -> void:
	z_index = 1   # with enemies and units: under the fog
	if Art.exists(EXPLOSION): _explosion = Art.texture(EXPLOSION)
	if Art.exists(BURNING_GROUND): _ground = Art.texture(BURNING_GROUND)
	if Art.exists(FROST_HIT): _frost = Art.texture(FROST_HIT)
	if Art.exists(STUN): _stun = Art.texture(STUN)


func bind(w: WeaponSystem) -> void:
	_w = w
	for t in w.types.size():
		var b := w.types[t].behaviours
		if b.has("hook"): _rope_types[t] = true
		if w.types[t].draw_split:
			var path := w.types[t].projectile_sprite
			_split_types[t] = Art.texture(path) if Art.exists(path) else null


static func art_paths() -> Array:
	return [EXPLOSION, BURNING_GROUND, FROST_HIT, STUN]


## Once per rendered frame. Takes over the new events, forgets old ones.
func refresh(tick: int, tint: Color = Color.WHITE) -> void:
	_tick = tick
	_unlight = Color(1.0 / maxf(tint.r, 0.05), 1.0 / maxf(tint.g, 0.05), 1.0 / maxf(tint.b, 0.05))
	_blasts.append_array(_w.effects.blasts)
	_w.effects.blasts.clear()
	for a in _w.arcs:
		_arcs.append([a[0], a[1], a[2], randi()])
	_w.arcs.clear()
	_chills.append_array(_w.chill_marks)
	_w.chill_marks.clear()
	var blast_ticks := _life(blast_seconds, _explosion)
	var arc_ticks := int(round(arc_seconds / GameClock.TICK_DELTA))
	var chill_ticks := _life(0.2, _frost) if _frost != null else 0
	_blasts = _blasts.filter(func(b): return tick - int(b[2]) <= blast_ticks)
	_arcs = _arcs.filter(func(a): return tick - int(a[2]) <= arc_ticks)
	_chills = _chills.filter(func(c): return tick - int(c[1]) <= chill_ticks)
	queue_redraw()


func _life(seconds: float, strip: Texture2D) -> int:
	if strip != null:
		return CombatEffects._frames(strip) * maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	return int(round(seconds / GameClock.TICK_DELTA))


func _draw() -> void:
	if _w == null:
		return
	var tpf := maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	_draw_ground(tpf)
	_draw_tethers()
	_draw_stuns(tpf)
	for b in _blasts:
		var at: Vector2 = b[0]
		var r: float = b[1]
		var age := _tick - int(b[2])
		if _explosion != null:
			@warning_ignore("integer_division")
			var frame := age / tpf
			if frame < CombatEffects._frames(_explosion):
				var h := float(_explosion.get_height())
				draw_texture_rect_region(_explosion, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0),
					Rect2(frame * h, 0.0, h, h), _unlight)
		else:
			var t := clampf(age / maxf(blast_seconds / GameClock.TICK_DELTA, 1.0), 0.0, 1.0)
			draw_circle(at, r * lerpf(0.4, 1.0, t), Color(1.0, 0.6, 0.2, 0.45 * (1.0 - t)) * _unlight)
			draw_arc(at, r * lerpf(0.5, 1.05, t), 0.0, TAU, 24, Color(1.0, 0.9, 0.6, 0.9 * (1.0 - t)) * _unlight, 2.0)
	for a in _arcs:
		var from: Vector2 = a[0]
		var to: Vector2 = a[1]
		var fade := 1.0 - float(_tick - int(a[2])) / maxf(arc_seconds / GameClock.TICK_DELTA, 1.0)
		if fade <= 0.0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = int(a[3])
		var pts := PackedVector2Array([from])
		var normal := (to - from).orthogonal().normalized()
		for n in range(1, 4):
			pts.append(from.lerp(to, n / 4.0) + normal * rng.randf_range(-4.0, 4.0))
		pts.append(to)
		draw_polyline(pts, Color(0.5, 0.8, 1.0, 0.35 * fade) * _unlight, 4.0)
		draw_polyline(pts, Color(0.9, 0.97, 1.0, fade) * _unlight, 1.5)
	if _frost != null:
		for c in _chills:
			@warning_ignore("integer_division")
			var frame := (_tick - int(c[1])) / tpf
			if frame < CombatEffects._frames(_frost):
				var h := float(_frost.get_height())
				var at: Vector2 = c[0]
				draw_texture_rect_region(_frost, Rect2(at - Vector2(h, h) / 2.0, Vector2(h, h)),
					Rect2(frame * h, 0.0, h, h), _unlight)
	if selected != -1 and _w.is_weapon(selected):
		var at := _w.centre_of(selected)
		var r := _w.range_of(selected)
		draw_circle(at, r, Color(1.0, 1.0, 1.0, 0.06) * _unlight)
		draw_arc(at, r, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.55) * _unlight, 1.5)


func _draw_ground(tpf: int) -> void:
	var fx := _w.effects
	if fx.alive_count() == 0:
		return
	for id in EffectSystem.CAP:
		if not fx.is_alive(id) or fx.kind[id] != EffectSystem.Kind.GROUND:
			continue
		var at := fx.pos[id]
		var r := fx.radius[id]
		# Dies down over its last half second.
		var fade := clampf(fx.ticks[id] / 30.0, 0.0, 1.0)
		if _ground != null:
			var frames := CombatEffects._frames(_ground)
			@warning_ignore("integer_division")
			var frame := ((_tick + id * 7) / tpf) % frames
			var h := float(_ground.get_height())
			draw_texture_rect_region(_ground, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0),
				Rect2(frame * h, 0.0, h, h), Color(_unlight.r, _unlight.g, _unlight.b, fade))
		else:
			var flicker := 0.75 + 0.25 * sin(_tick * 0.6 + id * 1.7)
			draw_circle(at, r, Color(1.0, 0.35, 0.05, 0.28 * fade * flicker) * _unlight)
			draw_circle(at, r * 0.55, Color(1.0, 0.7, 0.2, 0.3 * fade * flicker) * _unlight)


## A rope from each hook to its tower, and the chain cannon's balls: the two
## halves of the sprite pulled apart by how far the catch radius has grown,
## the middle (chain) column stretched between them, spinning as they fly.
func _draw_tethers() -> void:
	var ps := _w.projectiles
	if ps.alive_count() == 0 or (_rope_types.is_empty() and _split_types.is_empty()):
		return
	for p in ps.alive_ids():
		var t := ps.type[p]
		if _rope_types.has(t):
			draw_line(ps.anchor[p], ps.pos[p], Color(0.45, 0.32, 0.18), 2.0)
		elif _split_types.has(t):
			var d := _w.types[t]
			var extra := maxf(ps.radius[p] - d.projectile_radius, 0.0)
			var rot := (_tick - ps.born[p]) * GameClock.TICK_DELTA * d.spin_speed
			draw_set_transform(ps.pos[p], rot, Vector2.ONE)
			var tex: Texture2D = _split_types[t]
			if tex != null:
				var w := float(tex.get_width())
				var h := float(tex.get_height())
				var cx := floorf(w / 2.0)
				if extra > 0.0:
					draw_texture_rect_region(tex, Rect2(-extra - 1.0, -h / 2.0, extra * 2.0 + 2.0, h),
						Rect2(cx - 1.0, 0.0, 2.0, h), _unlight)
				draw_texture_rect_region(tex, Rect2(-w / 2.0 - extra, -h / 2.0, cx, h),
					Rect2(0.0, 0.0, cx, h), _unlight)
				draw_texture_rect_region(tex, Rect2(cx - w / 2.0 + extra, -h / 2.0, w - cx, h),
					Rect2(cx, 0.0, w - cx, h), _unlight)
			else:
				var r := d.projectile_radius
				var half := r * 0.55 + extra
				draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Color(0.65, 0.68, 0.72) * _unlight, 2.0)
				draw_circle(Vector2(-half, 0.0), r * 0.45, d.projectile_color * _unlight)
				draw_circle(Vector2(half, 0.0), r * 0.45, d.projectile_color * _unlight)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Over every stunned enemy: the stun strip, or three small dots circling.
func _draw_stuns(tpf: int) -> void:
	var en := _w.enemies
	if en.alive_count() == 0:
		return
	for e in EnemyStore.CAP:
		if not en.is_alive(e) or en.stun_ticks[e] <= 0:
			continue
		var at := en.pos[e] + Vector2(0.0, -16.0)
		if _stun != null:
			var h := float(_stun.get_height())
			@warning_ignore("integer_division")
			var frame := (_tick / tpf) % CombatEffects._frames(_stun)
			draw_texture_rect_region(_stun, Rect2(at - Vector2(h, h) / 2.0, Vector2(h, h)),
				Rect2(frame * h, 0.0, h, h), _unlight)
		else:
			for k in 3:
				var a := _tick * 0.15 + k * TAU / 3.0
				draw_circle(at + Vector2(cos(a) * 7.0, sin(a) * 2.5), 1.6,
					Color(1.0, 0.95, 0.5) * _unlight)
