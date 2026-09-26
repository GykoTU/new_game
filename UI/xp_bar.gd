extends CanvasLayer
## The level and the XP toward the next one (Stage 7), just under the day bar.
## Listens to Progression.xp_changed; nothing per frame.

const ICON := "res://assets/ui/level.png"

@export var bar_size := Vector2(160.0, 6.0)
## Distance below the top of the screen: clears the day bar.
@export var top_margin := 102

var _label: Label
var _fill: ColorRect


func _ready() -> void:
	layer = 2
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 5
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = top_margin
	panel.tooltip_text = "XP from kills, exploring and surviving. Each level lets you pick an augment."
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	if Art.exists(ICON):
		var icon := TextureRect.new()
		icon.texture = Art.texture(ICON)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_constant_override("outline_size", 3)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.18)
	track.custom_minimum_size = bar_size
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(track)
	_fill = ColorRect.new()
	_fill.color = Color(0.55, 0.95, 0.55, 0.9)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.size = Vector2(0.0, bar_size.y)
	track.add_child(_fill)


static func art_paths() -> Array:
	return [ICON]


func bind(progression: Progression) -> void:
	progression.xp_changed.connect(_on_xp)
	_on_xp(progression.xp, progression.xp_to_next(), progression.level)


func _on_xp(xp: int, needed: int, level: int) -> void:
	_label.text = "Lv %d" % level
	_fill.size = Vector2(bar_size.x * clampf(float(xp) / maxf(needed, 1.0), 0.0, 1.0), bar_size.y)
