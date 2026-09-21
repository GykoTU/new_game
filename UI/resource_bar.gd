extends CanvasLayer
## Resource counters along the top of the screen. One entry per ResourceKind,
## so a new resource appears here without touching this file.

## Keep this a whole multiple of the art's 32 px. Pixel art scaled by a fraction
## (24 px is 0.75x) gets uneven pixel widths and looks smudged.
@export var icon_size := 32
@export var font_size := 24

var _labels := {}   # ResourceKind.Id -> Label


func _ready() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	# Containers default to PASS; STOP keeps clicks and scrolls from falling
	# through to the camera or the build placer underneath.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)

	for kind in ResourceKind.count():
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.tooltip_text = ResourceKind.display_of(kind)
		var icon := TextureRect.new()
		icon.texture = Art.texture(ResourceKind.icon_path_of(kind))
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		var label := Label.new()
		label.text = "0"
		label.custom_minimum_size.x = font_size * 2
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		cell.add_child(icon)
		cell.add_child(label)
		row.add_child(cell)
		_labels[kind] = label


func bind(economy: Economy) -> void:
	economy.changed.connect(_on_changed)
	for kind in ResourceKind.count():
		_on_changed(kind, economy.amount(kind))


func _on_changed(kind: int, amount: int) -> void:
	_labels[kind].text = str(amount)
