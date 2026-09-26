class_name CombatEffects
extends Node2D
## Short-lived combat visuals: the base's zap bolts, enemy deaths, and the
## flame over burning enemies. Drawn with _draw from lists the simulation
## fills (BaseDefence.zaps, EnemySystem.deaths) and this node drains.
##
## Every sprite here is optional. Without it, the zap is a plain bolt, a death
## is a small fading ring, and burning shows only as the orange tint the enemy
## shader already applies.

const ZAP_HIT := "res://assets/effects/zap_hit.png"
const DEATH := "res://assets/effects/enemy_death.png"
const BURN := "res://assets/effects/burn.png"

## How long a zap bolt stays on screen, and a death without a sprite.
@export var zap_seconds := 0.12
@export var death_seconds := 0.35
## Seconds per frame of the optional sprite strips.
@export var frame_time := 0.07

var _zaps: Array = []     # [from, to, tick, seed]
var _deaths: Array = []   # [pos, tick]
var _burning := PackedVector2Array()
var _tick := 0
## Undoes the night tint for the bolt, which is light, not a lit object (same
## reasoning as BuildingGlow). Set by main.gd each frame.
var _unlight := Color.WHITE
var _zap_hit: Texture2D
var _death: Texture2D
var _burn: Texture2D


func _ready() -> void:
	z_index = 1   # with enemies and units: under the fog
	if Art.exists(ZAP_HIT): _zap_hit = Art.texture(ZAP_HIT)
	if Art.exists(DEATH): _death = Art.texture(DEATH)
	if Art.exists(BURN): _burn = Art.texture(BURN)


static func art_paths() -> Array:
	return [ZAP_HIT, DEATH, BURN]


## Once per rendered frame. Takes over the new zaps and deaths, forgets old ones.
func refresh(defence: BaseDefence, enemies: EnemySystem, tick: int, tint: Color = Color.WHITE) -> void:
	_tick = tick
	_unlight = Color(1.0 / maxf(tint.r, 0.05), 1.0 / maxf(tint.g, 0.05), 1.0 / maxf(tint.b, 0.05))
	for z in defence.zaps:
		_zaps.append([z[0], z[1], z[2], randi()])
	defence.zaps.clear()
	for d in enemies.deaths:
		_deaths.append([d[0], d[2]])
	enemies.deaths.clear()
	var zap_ticks := _life(zap_seconds, _zap_hit)
	var death_ticks := _life(death_seconds, _death)
	_zaps = _zaps.filter(func(z): return tick - int(z[2]) <= zap_ticks)
	_deaths = _deaths.filter(func(d): return tick - int(d[1]) <= death_ticks)
	_burning.clear()
	if _burn != null:
		for e in EnemyStore.CAP:
			if enemies.is_alive(e) and enemies.burn_ticks[e] > 0:
				_burning.append(enemies.pos[e])
	queue_redraw()


## Ticks an effect lasts: its sprite strip's length, or the plain duration.
func _life(seconds: float, strip: Texture2D) -> int:
	if strip != null:
		return _frames(strip) * maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	return int(round(seconds / GameClock.TICK_DELTA))


static func _frames(tex: Texture2D) -> int:
	@warning_ignore("integer_division")
	return maxi(tex.get_width() / maxi(tex.get_height(), 1), 1)


func _draw() -> void:
	var tpf := maxi(int(round(frame_time / GameClock.TICK_DELTA)), 1)
	for z in _zaps:
		var from: Vector2 = z[0]
		var to: Vector2 = z[1]
		var age := _tick - int(z[2])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(z[3])
		# A jagged bolt: a few kinked segments, brighter core over a soft glow.
		var pts := PackedVector2Array([from])
		var normal := (to - from).orthogonal().normalized()
		for n in range(1, 5):
			pts.append(from.lerp(to, n / 5.0) + normal * rng.randf_range(-6.0, 6.0))
		pts.append(to)
		var fade := 1.0 - float(age) / maxf(zap_seconds / GameClock.TICK_DELTA, 1.0)
		if fade > 0.0:
			draw_polyline(pts, Color(0.55, 0.8, 1.0, 0.35 * fade) * _unlight, 5.0)
			draw_polyline(pts, Color(0.92, 0.97, 1.0, fade) * _unlight, 1.5)
		if _zap_hit != null:
			_draw_strip(_zap_hit, to, age, tpf)
	for d in _deaths:
		var at: Vector2 = d[0]
		var age := _tick - int(d[1])
		if _death != null:
			_draw_strip(_death, at, age, tpf)
		else:
			var t := float(age) / maxf(death_seconds / GameClock.TICK_DELTA, 1.0)
			draw_arc(at, lerpf(4.0, 14.0, t), 0.0, TAU, 16, Color(1, 1, 1, 0.8 * (1.0 - t)), 2.0)
	if _burn != null:
		var frames := _frames(_burn)
		@warning_ignore("integer_division")
		var frame := (_tick / tpf) % frames
		for p in _burning:
			_draw_frame(_burn, p, frame)


func _draw_strip(tex: Texture2D, at: Vector2, age: int, tpf: int) -> void:
	@warning_ignore("integer_division")
	var frame := age / tpf
	if frame < _frames(tex):
		_draw_frame(tex, at, frame)


func _draw_frame(tex: Texture2D, at: Vector2, frame: int) -> void:
	var h := float(tex.get_height())
	draw_texture_rect_region(tex, Rect2(at - Vector2(h, h) / 2.0, Vector2(h, h)),
		Rect2(frame * h, 0.0, h, h))
