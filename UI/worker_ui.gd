extends HBoxContainer
## The worker bar along the bottom: one slot per worker kind.
##
## Miners show idle/total: click the slot, then click a mine to send one.
## Builders, carriers and explorers show count/beds, since beds are what limit
## buying more. Explorers are sent like miners: click the slot, then anywhere.

signal slot_pressed(kind: int)

const ACTIVE_COLOR := Color(0.22, 0.34, 0.52, 0.95)
const IDLE_COLOR := Color(0, 0, 0, 0.9)

@onready var template = $Panel
@export var panel_amount: int = 5
@export var panel_size: int = 96
## Keep this a whole multiple of the art's 32 px (here 2x). A fractional scale
## such as the old 48 px (1.5x) gives uneven pixel widths and looks smudged.
@export var icon_size: int = 64
@export var count_font_size: int = 20

var _units = null
var _panels := {}   # WorkerRoster.Kind -> Panel
var _counts := {}   # WorkerRoster.Kind -> Label


func _ready():
	# Set up the template slot
	template.custom_minimum_size = Vector2(panel_size, panel_size)
	template.self_modulate = IDLE_COLOR

	# Add panels to hbox
	for panel in panel_amount - 1:
		add_child(template.duplicate())


func bind(units) -> void:
	_units = units
	var panels := get_children()
	for kind in WorkerRoster.Kind.COUNT:
		if kind >= panels.size():
			break
		var panel: Control = panels[kind]
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_panel_input.bind(kind))
		_panels[kind] = panel

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

	units.changed.connect(func(_kind): refresh())
	refresh()


func refresh() -> void:
	if _units == null:
		return
	for kind in _counts:
		var label: Label = _counts[kind]
		var panel: Control = _panels[kind]
		var total: int = _units.count(kind)
		var kind_name := WorkerRoster.display_of(kind)
		if kind == WorkerRoster.Kind.MINER:
			var idle: int = _units.idle_count(kind)
			label.text = "%d/%d" % [idle, total]
			panel.tooltip_text = "%ss: %d idle of %d.\nClick, then click a mine to send one." % [kind_name, idle, total]
		else:
			var beds: int = _units.beds(kind)
			label.text = "%d/%d" % [total, beds]
			panel.tooltip_text = "%ss: %d, beds for %d." % [kind_name, total, beds]
			if kind == WorkerRoster.Kind.EXPLORER:
				panel.tooltip_text += "\nClick, then click anywhere (fog too) to send one."


## Highlights the slot of the kind being commanded; -1 clears it.
func set_active(kind: int) -> void:
	for k in _panels:
		_panels[k].self_modulate = ACTIVE_COLOR if k == kind else IDLE_COLOR


func _on_panel_input(event: InputEvent, kind: int) -> void:
	if event.is_action_pressed("left_click"):
		slot_pressed.emit(kind)
		accept_event()
