class_name CacheHalos
extends Node2D
## The glow round every dropped blueprint: grey for common, blue for rare, so
## the player sees at a glance what an enemy left behind. Drawn additively in
## code (no sprite), pulsing slowly, and unlit: it stays bright at night, like
## BuildingGlow. Under the fog, so a cache in unexplored ground stays hidden.

const COMMON := Color(0.85, 0.85, 0.9)
const RARE := Color(0.3, 0.55, 1.0)

@export var radius := 26.0
@export var strength := 0.55
## Seconds per pulse.
@export var pulse_seconds := 1.6

var _pois: PointsOfInterest
var _caches: Array = []
var _time := 0.0
var _unlight := Color.WHITE


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func bind(pois: PointsOfInterest) -> void:
	_pois = pois


## Once per rendered frame.
func refresh(delta: float, tint: Color = Color.WHITE) -> void:
	_time += delta
	_unlight = Color(1.0 / maxf(tint.r, 0.05), 1.0 / maxf(tint.g, 0.05), 1.0 / maxf(tint.b, 0.05))
	_caches = _pois.dropped() if _pois != null else []
	if not _caches.is_empty() or visible:
		queue_redraw()


func _draw() -> void:
	var pulse := 0.8 + 0.2 * sin(_time * TAU / maxf(pulse_seconds, 0.1))
	for c in _caches:
		var at: Vector2 = c[0]
		var colour := RARE if int(c[1]) == ShopItemData.Rarity.RARE else COMMON
		# A soft disc: rings from the outside in, each a little brighter.
		for k in 6:
			var t := float(k) / 6.0
			var a := strength * pulse * (0.08 + 0.12 * t)
			draw_circle(at, radius * pulse * (1.0 - t * 0.7), Color(colour.r, colour.g, colour.b, a) * _unlight)
