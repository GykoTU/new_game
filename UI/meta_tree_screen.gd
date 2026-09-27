extends CanvasLayer
## The relic tree (Stage 8), opened from the title screen. Nodes grow out of
## the Hearth in four branches; a synergy node between two branches needs both
## of its neighbours. Click a node to buy its next level with relics; Refund
## all gives every relic back. Buying writes the profile at once; runs take a
## snapshot when they start (MetaState), so this only changes the next run.

signal closed

const BACKGROUND := "res://assets/ui/meta/tree_background.png"
const RELIC_ICON := "res://assets/ui/relic.png"
const NODE_SIZE := 56.0
const COLOURS := {
	MetaNodeData.Branch.ROOT: Color(0.95, 0.85, 0.6),
	MetaNodeData.Branch.ARMS: Color(0.92, 0.38, 0.32),
	MetaNodeData.Branch.HANDS: Color(0.45, 0.82, 0.42),
	MetaNodeData.Branch.WALLS: Color(0.42, 0.62, 0.98),
	MetaNodeData.Branch.PATHS: Color(0.96, 0.76, 0.3),
}
const GOLD := Color(1.0, 0.84, 0.35)
const LOCKED := Color(0.35, 0.35, 0.38)

## Where the tree's centre sits, as a share of the screen.
@export var centre := Vector2(0.5, 0.42)

var state: MetaState
var _canvas: TreeCanvas
var _buttons := {}        # node id -> Button
var _relics_label: Label
var _info_name: Label
var _info_body: Label
var _info_cost: Label
var _refund: Button
var _refund_armed := false
var _hovered := ""


## Draws the lines between nodes, under the node buttons.
class TreeCanvas extends Control:
	var screen

	func _draw() -> void:
		screen.draw_links(self)


func _ready() -> void:
	layer = 5
	var bg: Control
	if Art.exists(BACKGROUND):
		var tex := TextureRect.new()
		tex.texture = Art.texture(BACKGROUND)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg = tex
	else:
		var rect := ColorRect.new()
		rect.color = Color(0.07, 0.07, 0.09)
		bg = rect
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_canvas = TreeCanvas.new()
	_canvas.screen = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.resized.connect(_layout)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(_label("Relic Tree", 28, Color.WHITE))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	if Art.exists(RELIC_ICON):
		var icon := TextureRect.new()
		icon.texture = Art.texture(RELIC_ICON)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	_relics_label = _label("", 18, GOLD)
	row.add_child(_relics_label)

	# The info panel: what the hovered node does and costs.
	var info := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	info.add_theme_stylebox_override("panel", style)
	info.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_bottom = -60
	info.custom_minimum_size = Vector2(540, 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(col)
	_info_name = _label("", 18, Color.WHITE)
	_info_body = _label("", 14, Color(0.85, 0.85, 0.88))
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.custom_minimum_size.x = 510
	_info_cost = _label("", 14, GOLD)
	col.add_child(_info_name)
	col.add_child(_info_body)
	col.add_child(_info_cost)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	buttons.offset_bottom = -16
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	_refund = Button.new()
	_refund.custom_minimum_size = Vector2(170, 36)
	_refund.focus_mode = Control.FOCUS_NONE
	_refund.pressed.connect(_on_refund)
	buttons.add_child(_refund)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 36)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back)
	buttons.add_child(back)


static func art_paths(tree: MetaTree) -> Array:
	var out: Array = [BACKGROUND]
	for n in tree.nodes:
		if n != null:
			out.append(n.icon_path)
	return out


## Shows the tree owned in the profile.
func open(tree: MetaTree) -> void:
	state = MetaState.new(tree, SaveManager.profile.get("meta", {}))
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for n in tree.nodes:
		if n == null:
			continue
		var b := _node_button(n)
		_canvas.add_child(b)
		_buttons[n.id] = b
	_refund_armed = false
	_hovered = ""
	visible = true
	_layout()
	_refresh()


func relics() -> int:
	return int(SaveManager.profile.get("relics", 0))


## Buys one level of a node. Returns true if it was bought.
func buy(id: String) -> bool:
	var cost := state.buy(id, relics())
	if cost < 0:
		return false
	SaveManager.profile["relics"] = relics() - cost
	SaveManager.profile["meta"] = state.get_levels()
	SaveManager.save_profile()
	_refund_armed = false
	_refresh()
	return true


## Gives every spent relic back. Returns how many.
func refund_all() -> int:
	var back := state.refund_all()
	SaveManager.profile["relics"] = relics() + back
	SaveManager.profile["meta"] = state.get_levels()
	SaveManager.save_profile()
	_refresh()
	return back


func _on_refund() -> void:
	if not _refund_armed:
		_refund_armed = true   # a second click confirms
		_refresh()
		return
	_refund_armed = false
	refund_all()


func _on_back() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


func _centre() -> Vector2:
	return _canvas.size * centre


func _layout() -> void:
	if state == null:
		return
	for id in _buttons:
		var n := state.tree.find(id)
		_buttons[id].position = _centre() + n.position - Vector2(NODE_SIZE, NODE_SIZE) * 0.5
	_canvas.queue_redraw()


func _node_button(n: MetaNodeData) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	b.size = Vector2(NODE_SIZE, NODE_SIZE)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(buy.bind(n.id))
	b.mouse_entered.connect(_on_hover.bind(n.id))
	b.mouse_exited.connect(_on_hover.bind(""))
	if Art.exists(n.icon_path):
		var t := TextureRect.new()
		t.name = "Icon"
		t.texture = Art.texture(n.icon_path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
	else:
		var initials := ""
		for w in n.display_name.split(" "):
			if w != "" and initials.length() < 2:
				initials += w[0]
		b.text = initials
		b.add_theme_font_size_override("font_size", 18)
	# The level under the node.
	var lvl := _label("", 12, Color.WHITE)
	lvl.name = "Level"
	lvl.position = Vector2(-12, NODE_SIZE + 2)
	lvl.size = Vector2(NODE_SIZE + 24, 16)
	b.add_child(lvl)
	return b


func _refresh() -> void:
	_relics_label.text = "%d relic%s" % [relics(), "" if relics() == 1 else "s"]
	var spent := state.spent()
	_refund.disabled = spent <= 0
	_refund.text = ("Click again: refund %d" % spent) if _refund_armed else "Refund all"
	for id in _buttons:
		_style(state.tree.find(id), _buttons[id])
	_show_info(_hovered)
	_canvas.queue_redraw()


func _style(n: MetaNodeData, b: Button) -> void:
	var colour: Color = COLOURS[n.branch]
	var level := state.level_of(n.id)
	var reachable := state.is_reachable(n)
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(NODE_SIZE * 0.5))
	box.set_border_width_all(3)
	var icon_alpha := 1.0
	if level > 0:
		box.bg_color = colour.darkened(0.45)
		box.border_color = GOLD if state.is_maxed(n) else colour.lightened(0.15)
	elif reachable:
		box.bg_color = Color(0.12, 0.12, 0.15)
		box.border_color = colour if state.can_buy(n, relics()) else colour.darkened(0.45)
		icon_alpha = 0.8
	else:
		box.bg_color = Color(0.08, 0.08, 0.1)
		box.border_color = LOCKED
		icon_alpha = 0.35
	var hover := box.duplicate() as StyleBoxFlat
	hover.set_border_width_all(4)
	hover.bg_color = box.bg_color.lightened(0.08)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", box)
	b.modulate = Color(1, 1, 1, 1)
	var icon := b.get_node_or_null("Icon")
	if icon != null:
		icon.modulate = Color(1, 1, 1, icon_alpha)
	else:
		b.add_theme_color_override("font_color", Color(1, 1, 1, icon_alpha))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, icon_alpha))
	var lvl: Label = b.get_node("Level")
	lvl.text = "" if n.is_root() else "%d / %d" % [level, n.max_level()]
	lvl.add_theme_color_override("font_color", GOLD if state.is_maxed(n) else Color(1, 1, 1, 0.4 + 0.6 * icon_alpha))


func _on_hover(id: String) -> void:
	_hovered = id
	_show_info(id)


func _show_info(id: String) -> void:
	var n := state.tree.find(id) if id != "" else null
	if n == null:
		_info_name.text = "Spend relics to shape your next runs"
		_info_body.text = "Nodes grow from the Hearth. A node between two branches needs both. " \
			+ "Changes apply when you start a new run" \
			+ (" (your saved run keeps the tree it began with)." if SaveManager.has_run() else ".")
		_info_cost.text = "Relics come from relic caches and from every run's survival."
		return
	_info_name.text = n.display_name
	_info_body.text = n.description
	if n.is_root():
		_info_cost.text = "Always yours."
	elif state.is_maxed(n):
		_info_cost.text = "Level %d / %d: complete." % [state.level_of(n.id), n.max_level()]
	elif not state.is_reachable(n):
		var names := PackedStringArray()
		for l in n.links:
			var ln := state.tree.find(l)
			names.append(ln.display_name if ln != null else l)
		_info_cost.text = "Needs %s first." % (" and ".join(names) if n.needs_all else " or ".join(names))
	else:
		var cost := state.next_cost(n)
		_info_cost.text = "Level %d / %d. Next: %d relic%s%s" % [state.level_of(n.id), n.max_level(), cost,
			"" if cost == 1 else "s", "" if relics() >= cost else " (not enough)"]


## Lines between linked nodes: bright between two owned ones, dim toward a
## node that can be bought, faint (dashed for a synergy node) elsewhere.
func draw_links(canvas: Control) -> void:
	if state == null:
		return
	var c := _centre()
	for n in state.tree.nodes:
		if n == null:
			continue
		for l in n.links:
			var other := state.tree.find(l)
			if other == null:
				continue
			var a := c + other.position
			var b := c + n.position
			var colour: Color = COLOURS[n.branch]
			var own_a := state.is_owned(other.id)
			var own_b := state.is_owned(n.id)
			if own_a and own_b:
				canvas.draw_line(a, b, colour, 4.0, true)
			elif own_a:
				if n.needs_all:
					canvas.draw_dashed_line(a, b, colour.darkened(0.3), 3.0, 8.0)
				else:
					canvas.draw_line(a, b, colour.darkened(0.35), 3.0, true)
			else:
				canvas.draw_dashed_line(a, b, Color(LOCKED, 0.6), 2.0, 6.0)


func _label(text: String, font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
