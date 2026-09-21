class_name ControlsList
extends VBoxContainer
## Every shortcut, grouped by category, with click-to-rebind.
##
## Click a binding, then press a key (Ctrl/Shift/Alt combinations work) or a
## mouse button. Esc cancels. Debug shortcuts appear only in debug builds.
##
## Capture happens in _input, which runs before _unhandled_input, and every key
## or button event is consumed while capturing -- so pressing Space to bind it
## does not also pause the game, and B does not also open the shop.

const UNBOUND_COLOR := Color(1.0, 0.45, 0.45)
const HEADER_COLOR := Color(0.75, 0.75, 0.75)
const FONT_SIZE := 13

var _buttons := {}   # action -> Button
var _capturing := ""
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	var category := -1
	for row in Keybinds.visible_rows():
		if row[2] != category:
			category = row[2]
			var header := Label.new()
			header.text = Keybinds.CATEGORY_NAMES[category]
			if category == Keybinds.Category.DEBUG:
				header.text += "  (dev builds only)"
			header.add_theme_color_override("font_color", HEADER_COLOR)
			header.add_theme_font_size_override("font_size", FONT_SIZE)
			add_child(header)

		var line := HBoxContainer.new()
		var action_label := Label.new()
		action_label.text = row[1]
		action_label.custom_minimum_size.x = 150
		action_label.add_theme_font_size_override("font_size", FONT_SIZE)
		line.add_child(action_label)

		var button := Button.new()
		button.custom_minimum_size.x = 160
		button.focus_mode = Control.FOCUS_NONE
		# PASS, not the default STOP: the button still gets its clicks, but a
		# scroll wheel over it reaches the ScrollContainer instead of dying here.
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.disabled = not row[3]
		if not row[3]:
			button.tooltip_text = "Fixed, so the menu can always be reached."
		button.pressed.connect(_begin_capture.bind(row[0]))
		line.add_child(button)
		add_child(line)
		_buttons[row[0]] = button

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 310
	_status.add_theme_font_size_override("font_size", 12)
	add_child(_status)

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_on_reset)
	add_child(reset)

	visibility_changed.connect(_cancel_capture)
	refresh()


func refresh() -> void:
	for action in _buttons:
		var button: Button = _buttons[action]
		if action == _capturing:
			button.text = "Press a key..."
			button.remove_theme_color_override("font_color")
			continue
		button.text = Keybinds.describe_action(action)
		if Keybinds.bindings(action).is_empty():
			button.add_theme_color_override("font_color", UNBOUND_COLOR)
		else:
			button.remove_theme_color_override("font_color")


func _begin_capture(action: String) -> void:
	_capturing = action
	_status.text = "Press a key or mouse button for \"%s\". Esc cancels." % Keybinds.label_of(action)
	refresh()


func _cancel_capture() -> void:
	if _capturing == "":
		return
	_capturing = ""
	_status.text = ""
	refresh()


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	if event is InputEventKey and event.pressed \
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_cancel_capture()
		_status.text = "Cancelled."
		return

	var binding := Keybinds.binding_from(event)
	if binding == null:
		# Swallow releases and lone modifiers too, so nothing else reacts.
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()

	var action := _capturing
	_capturing = ""
	var result := Keybinds.rebind(action, binding)
	var key := Keybinds.describe(binding)
	if not result["ok"]:
		_status.text = result["reason"]
	elif result["taken_from"] != "":
		_status.text = "%s moved from \"%s\" to \"%s\". \"%s\" may now be unbound." % [
			key, Keybinds.label_of(result["taken_from"]), Keybinds.label_of(action),
			Keybinds.label_of(result["taken_from"])]
	else:
		_status.text = "%s bound to \"%s\"." % [key, Keybinds.label_of(action)]
	Settings.save()
	refresh()


func _on_reset() -> void:
	_capturing = ""
	Keybinds.reset_all()
	Settings.save()
	_status.text = "All bindings reset to defaults."
	refresh()
