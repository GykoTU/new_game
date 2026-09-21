extends CanvasLayer

@onready var volume_slider = $PanelContainer/VBoxContainer/VolumeSlider
@onready var fullscreen_check = $PanelContainer/VBoxContainer/FullscreenCheck
@onready var _box = $PanelContainer/VBoxContainer
@onready var _resume = $PanelContainer/VBoxContainer/ResumeButton

var _controls_scroll: ScrollContainer
var _controls_toggle: Button

func _ready():
	visible = false
	volume_slider.value = Settings.volume
	fullscreen_check.button_pressed = Settings.fullscreen
	_add_controls_section()


## A "Controls" toggle and the scrollable shortcut list, inserted above Resume.
## Built in code so the list always matches Keybinds.ACTIONS.
func _add_controls_section() -> void:
	_controls_toggle = Button.new()
	_controls_toggle.text = "Controls"
	_controls_toggle.toggle_mode = true
	_box.add_child(_controls_toggle)
	_box.move_child(_controls_toggle, _resume.get_index())

	_controls_scroll = ScrollContainer.new()
	_controls_scroll.custom_minimum_size = Vector2(340, 280)
	_controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_scroll.visible = false
	_controls_scroll.add_child(ControlsList.new())
	_box.add_child(_controls_scroll)
	_box.move_child(_controls_scroll, _resume.get_index())

	_controls_toggle.toggled.connect(func(on): _controls_scroll.visible = on)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	# While open the menu is modal: nothing underneath -- camera, shop, speed
	# keys, building placement -- reacts to keys or mouse buttons. This relies
	# on OptionsMenu being the LAST child of UI in main.tscn: unhandled input
	# runs in reverse tree order, so the last child sees it first.
	if visible and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()

## main.gd watches visibility_changed and pushes a clock pause reason, so the
## world freezes while this menu keeps animating. Do not use get_tree().paused.
func toggle():
	visible = not visible
	if visible:
		_collapse_sections()


## The menu always opens with every section closed, whatever was open last time.
func _collapse_sections() -> void:
	_controls_toggle.button_pressed = false
	_controls_scroll.visible = false
	_controls_scroll.scroll_vertical = 0

func _on_volume_slider_value_changed(value):
	Settings.volume = value
	Settings.apply()
	Settings.save()

func _on_fullscreen_check_toggled(on):
	Settings.fullscreen = on
	Settings.apply()
	Settings.save()

func _on_resume_button_pressed():
	toggle()

func _on_quit_to_title_button_pressed():
	EventBus.on_quit_button_pressed.emit()
	get_tree().change_scene_to_file("res://game/title_screen.tscn")
