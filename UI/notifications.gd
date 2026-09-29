extends CanvasLayer
## Notifications (tuned after Stage 10), top right: what exploring found -- a
## blueprint learned, relics, a place visited. Each stays until the player
## clicks it; the newest is on top, at most MAX_SHOWN at once (older ones wait
## below the fold and move up as others are dismissed).

signal dismissed(count: int)

const BACKGROUND := "res://assets/ui/notification.png"
const MAX_SHOWN := 6
const WIDTH := 300.0

@export var top_margin := 60   # below the resource bar
@export var right_margin := 12
@export var font_size := 14

var _column: VBoxContainer
var _waiting: Array = []   # [text, icon path] not shown yet (oldest first)


func _ready() -> void:
	layer = 3
	_column = VBoxContainer.new()
	_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_column.offset_top = top_margin
	_column.offset_right = -right_margin
	_column.custom_minimum_size.x = WIDTH
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)


static func art_paths() -> Array:
	return [BACKGROUND]


## Adds one. `icon_path` may be "" (no picture).
func push(text: String, icon_path := "") -> void:
	if text == "":
		return
	if _column.get_child_count() >= MAX_SHOWN:
		_waiting.append([text, icon_path])
		return
	_column.add_child(_entry(text, icon_path))
	_column.move_child(_column.get_child(_column.get_child_count() - 1), 0)


func count() -> int:
	return _column.get_child_count() + _waiting.size()


func clear() -> void:
	for c in _column.get_children():
		c.queue_free()
		_column.remove_child(c)
	_waiting.clear()


## Dismisses the one at `index` (0 = top), as a click would.
func dismiss(index: int) -> void:
	if index < 0 or index >= _column.get_child_count():
		return
	var entry := _column.get_child(index)
	_column.remove_child(entry)
	entry.queue_free()
	if not _waiting.is_empty():
		var next: Array = _waiting.pop_front()
		_column.add_child(_entry(next[0], next[1]))   # an older one: at the bottom
	dismissed.emit(count())


func _entry(text: String, icon_path: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, 40)
	panel.tooltip_text = "Click to dismiss."
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if Art.exists(BACKGROUND):
		var tex := StyleBoxTexture.new()
		tex.texture = Art.texture(BACKGROUND)
		tex.texture_margin_left = 12
		tex.texture_margin_right = 12
		tex.texture_margin_top = 12
		tex.texture_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", tex)
	else:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.05, 0.07, 0.82)
		box.border_color = Color(0.95, 0.8, 0.4, 0.8)
		box.border_width_left = 3
		box.set_corner_radius_all(6)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	if icon_path != "" and Art.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = Art.texture(icon_path)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 70.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	panel.gui_input.connect(_on_entry_input.bind(panel))
	panel.mouse_entered.connect(_hover.bind(panel, true))
	panel.mouse_exited.connect(_hover.bind(panel, false))
	return panel


func _on_entry_input(event: InputEvent, entry: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		entry.accept_event()
		dismiss(entry.get_index())


func _hover(entry: Control, on: bool) -> void:
	entry.modulate = Color(1.2, 1.2, 1.2) if on else Color.WHITE
