extends CanvasLayer
## Shown once, over the frozen world, when the base falls.
##
## It does not decide anything: main.gd ends the run (pauses the clock, deletes
## the run save, updates the profile) and then hands this panel the lines to
## show. The only way out is back to the title screen -- there is nothing to
## continue, because the run save is already gone.

signal return_pressed

@export var title_font_size := 40
@export var row_font_size := 20

var _dim: ColorRect
var _rows: VBoxContainer
var _title: Label


func _ready() -> void:
	layer = 8   # above the toast (6), below nothing
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: the world underneath must not take clicks while this is up.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	style.border_color = Color(0.55, 0.22, 0.2)
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dim.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)

	_title = Label.new()
	_title.text = "Your base has fallen"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", title_font_size)
	column.add_child(_title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)

	var button := Button.new()
	button.text = "Return to title"
	button.custom_minimum_size = Vector2(240, 44)
	button.add_theme_font_size_override("font_size", row_font_size)
	button.pressed.connect(func(): return_pressed.emit())
	column.add_child(button)
	button.focus_mode = Control.FOCUS_ALL


## `rows` is an array of [label, value] pairs.
func show_run(title: String, rows: Array) -> void:
	_title.text = title
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 24)
		var name_label := Label.new()
		name_label.text = str(row[0])
		name_label.add_theme_font_size_override("font_size", row_font_size)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Label.new()
		value_label.text = str(row[1])
		value_label.add_theme_font_size_override("font_size", row_font_size)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(value_label)
		_rows.add_child(line)
	visible = true


func hide_summary() -> void:
	visible = false
