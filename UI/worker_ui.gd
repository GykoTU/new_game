extends HBoxContainer
## The worker bar along the bottom. The first slots show how many of each
## worker kind the player owns. In Stage 2 these become the place workers are
## selected from before sending them to a mine.

@onready var template = $Panel
@export var panel_amount: int = 5
@export var panel_size: int = 96
## Keep this a whole multiple of the art's 32 px (here 2x). A fractional scale
## such as the old 48 px (1.5x) gives uneven pixel widths and looks smudged.
@export var icon_size: int = 64
@export var count_font_size: int = 22

var _counts := {}   # WorkerRoster.Kind -> Label


func _ready():
	# Set up the template slot
	template.custom_minimum_size = Vector2(panel_size, panel_size)
	template.self_modulate = Color(0, 0, 0, 0.9)

	# Add panels to hbox
	for panel in panel_amount - 1:
		add_child(template.duplicate())


func bind(roster: WorkerRoster) -> void:
	var panels := get_children()
	for kind in WorkerRoster.Kind.COUNT:
		if kind >= panels.size():
			break
		var panel: Control = panels[kind]
		panel.tooltip_text = WorkerRoster.display_of(kind)

		var icon := TextureRect.new()
		icon.texture = Art.texture(WorkerRoster.icon_path_of(kind))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Centred at an exact size, rather than filling the panel minus a margin,
		# so the scale stays a whole multiple whatever panel_size is.
		icon.set_anchors_preset(Control.PRESET_CENTER)
		icon.offset_left = -icon_size / 2.0
		icon.offset_top = -icon_size / 2.0
		icon.offset_right = icon_size / 2.0
		icon.offset_bottom = icon_size / 2.0
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)

		var count := Label.new()
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.offset_right = -6
		count.offset_bottom = -2
		count.add_theme_font_size_override("font_size", count_font_size)
		count.add_theme_constant_override("outline_size", 5)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(count)
		_counts[kind] = count

	roster.changed.connect(_on_changed)
	for kind in WorkerRoster.Kind.COUNT:
		_on_changed(kind, roster.count(kind))


func _on_changed(kind: int, count: int) -> void:
	if _counts.has(kind):
		_counts[kind].text = str(count)
