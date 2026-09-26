extends CanvasLayer
## The small panel shown when the player clicks a finished weapon building:
## its name, its numbers, and which enemy it aims at. The button cycles the
## target mode (nearest -> strongest -> first); main.gd applies it through
## WeaponSystem, which saves it by the building's cell.
##
## The whirl tower does not aim, so it shows no button.

signal mode_pressed
signal closed

const MODE_NAMES := ["Nearest", "Strongest", "First"]
const MODE_HINTS := [
	"Shoots the enemy closest to it.",
	"Shoots the enemy with the most health left.",
	"Shoots the enemy closest to the building it is attacking.",
]

@export var font_size := 18

var _panel: PanelContainer
var _title: Label
var _numbers: Label
var _mode: Button


func _ready() -> void:
	layer = 3
	visible = false
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.9)
	style.border_color = Color(0.45, 0.45, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = -16
	_panel.offset_right = -16
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", font_size + 4)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close := Button.new()
	close.text = "x"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (right click or Esc also closes it)"
	close.pressed.connect(_on_close)
	top.add_child(close)

	_numbers = Label.new()
	_numbers.add_theme_font_size_override("font_size", font_size - 2)
	_numbers.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	column.add_child(_numbers)

	_mode = Button.new()
	_mode.custom_minimum_size = Vector2(220, 36)
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.add_theme_font_size_override("font_size", font_size)
	_mode.pressed.connect(_on_mode)
	column.add_child(_mode)


## Fills the panel for one weapon and shows it.
func show_weapon(title: String, numbers: String, mode: int, aims: bool) -> void:
	_title.text = title
	_numbers.text = numbers
	_mode.visible = aims
	set_mode(mode)
	visible = true


func set_mode(mode: int) -> void:
	_mode.text = "Target: %s" % MODE_NAMES[clampi(mode, 0, MODE_NAMES.size() - 1)]
	_mode.tooltip_text = MODE_HINTS[clampi(mode, 0, MODE_HINTS.size() - 1)] + "\nClick to change."


func hide_panel() -> void:
	visible = false


func _on_mode() -> void:
	mode_pressed.emit()


func _on_close() -> void:
	visible = false
	closed.emit()
