extends HBoxContainer
## The building bar on the left edge: crafted buildings waiting to be placed,
## one slot per building type with a count, in the order each type was first
## crafted.
##
## One column of slots_per_column slots is always shown, empty ones included.
## When there are more types than fit, hovering the bar while holding the
## "expand_building_bar" action (Shift) opens further columns to the right,
## drawn partly transparent. Clicking a filled slot starts placing that
## building (main.gd does the placing).

signal slot_pressed(type: String)

const SLOT_TEXTURE := "res://assets/ui/building_slot.png"
const EXPAND_ACTION := "expand_building_bar"

## Whole multiples of the art's 32 px (see resource_bar.gd): the slot frame is
## drawn at 3x, the building at 2x on top of it.
@export var slot_size := 96
@export var icon_size := 64
@export var slots_per_column := 5
## Alpha of the columns only shown while the bar is expanded.
@export var extra_alpha := 0.6

var _inventory: BuildingInventory
var _level: LevelGenerator
var _columns: Array[Control] = []
var _expanded := false


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind(inventory: BuildingInventory, level: LevelGenerator) -> void:
	_inventory = inventory
	_level = level
	inventory.changed.connect(_rebuild)
	_rebuild()


func is_expanded() -> bool:
	return _expanded


func _rebuild() -> void:
	for c in _columns:
		c.queue_free()
	_columns.clear()
	var types := _inventory.types()
	var columns := maxi(1, ceili(float(types.size()) / slots_per_column))
	for col in columns:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		for row in slots_per_column:
			var i := col * slots_per_column + row
			var type := types[i] if i < types.size() else ""
			column.add_child(_make_slot(type, _inventory.count(type) if type != "" else 0))
		add_child(column)
		_columns.append(column)
	_apply_expanded()


## A slot: the frame image, and the building (if any) drawn on top of it.
func _make_slot(type: String, n: int) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(slot_size, slot_size)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	# No button look of its own: the frame image IS the slot.
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	var frame := TextureRect.new()
	frame.texture = Art.texture(SLOT_TEXTURE)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(frame)

	if type == "":
		button.disabled = true
		return button

	var data := _level.get_building_data(type)
	button.tooltip_text = "%s  x%d\nClick to place." % [data.display_name if data else type, n]
	button.pressed.connect(func(): slot_pressed.emit(type))
	# Brighter while hovered, so the slot under the mouse is obvious.
	button.mouse_entered.connect(func(): frame.modulate = Color(1.25, 1.25, 1.25))
	button.mouse_exited.connect(func(): frame.modulate = Color.WHITE)

	var icon := TextureRect.new()
	icon.texture = data.get_texture() if data != null else Art.fallback()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.offset_left = -icon_size / 2.0
	icon.offset_top = -icon_size / 2.0
	icon.offset_right = icon_size / 2.0
	icon.offset_bottom = icon_size / 2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	var count := Label.new()
	count.text = "x%d" % n
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.offset_right = -6
	count.offset_bottom = -2
	count.add_theme_font_size_override("font_size", 20)
	count.add_theme_constant_override("outline_size", 5)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(count)
	return button


# Polled: expanding needs both the hover and the held key, and the key can be
# pressed or released while the mouse stays still.
func _process(_delta: float) -> void:
	var over := get_global_rect().grow(4).has_point(get_viewport().get_mouse_position())
	var want := over and InputMap.has_action(EXPAND_ACTION) and Input.is_action_pressed(EXPAND_ACTION)
	if want != _expanded:
		_expanded = want
		_apply_expanded()


func _apply_expanded() -> void:
	for i in _columns.size():
		_columns[i].visible = i == 0 or _expanded
		_columns[i].modulate.a = 1.0 if i == 0 else extra_alpha
