extends CanvasLayer
## Which day it is and how far through the day or night, just under the
## resource bar.
##
## Read-only: it polls the RunDirector once a frame rather than listening for
## a signal, because the progress bar changes every frame anyway. The text is
## only rewritten when it actually changes, so a paused game costs nothing.

const SUN := "res://assets/ui/sun.png"
const MOON := "res://assets/ui/moon.png"

## Whole multiples of the art's 32 px (see ResourceBar on why).
@export var icon_size := 32
@export var font_size := 20
@export var bar_size := Vector2(160.0, 8.0)
## Distance below the top of the screen: clears the resource bar.
@export var top_margin := 54

var _director: RunDirector
var _icon: TextureRect
var _label: Label
var _fill: ColorRect
var _shown_text := ""
var _shown_night := true


func _ready() -> void:
	layer = 2
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = top_margin
	panel.tooltip_text = "Waves come at night."
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_label)

	# A plain two-rectangle bar: a ProgressBar would drag a theme along for
	# something that is two colours and one width.
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.18)
	track.custom_minimum_size = bar_size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(track)
	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.size = Vector2(0.0, bar_size.y)
	track.add_child(_fill)


func bind(director: RunDirector) -> void:
	_director = director
	refresh()


## Every sprite this bar references, for the missing-art report.
static func art_paths() -> Array:
	return [SUN, MOON]


## Called once a frame from main.gd, after the simulation.
func refresh() -> void:
	if _director == null:
		return
	var text := "Day %d" % _director.day
	if _director.is_night:
		text = "Night %d" % _director.day
	if text != _shown_text:
		_shown_text = text
		_label.text = text
	if _director.is_night != _shown_night:
		_shown_night = _director.is_night
		_icon.texture = Art.texture(MOON if _shown_night else SUN)
		_fill.color = Color(0.62, 0.70, 1.0, 0.85) if _shown_night else Color(1.0, 0.86, 0.45, 0.9)
	# Drains as the phase runs out, so a short bar means something is coming.
	_fill.size = Vector2(bar_size.x * (1.0 - _director.phase_progress()), bar_size.y)
