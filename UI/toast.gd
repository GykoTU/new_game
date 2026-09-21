extends CanvasLayer
## A short message above the worker bar: why an order was refused, what to do
## next. Never blocks clicks, and fades on real time, not game time, so it
## still disappears while the game is paused.

@export var seconds := 2.5

var _panel: PanelContainer
var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -112
	_panel.modulate.a = 0.0
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)


func show_message(text: String, hold: float = -1.0) -> void:
	_label.text = text
	_panel.modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(hold if hold > 0.0 else seconds)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)


func hide_message() -> void:
	if _tween != null:
		_tween.kill()
	_panel.modulate.a = 0.0
