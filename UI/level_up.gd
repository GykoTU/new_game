extends CanvasLayer
## The level-up screen (Stage 7): three augment cards over the frozen world,
## a reroll (once per level-up) and a skip (for gold). main.gd pauses the clock
## while it is up and hands it each offer; this only shows and reports.

signal picked(id: String)
signal rerolled
signal skipped

const CARD := {
	ShopItemData.Rarity.COMMON: "res://assets/ui/augment_card_common.png",
	ShopItemData.Rarity.RARE: "res://assets/ui/augment_card_rare.png",
}
const BORDER := {
	ShopItemData.Rarity.COMMON: Color(0.62, 0.62, 0.66),
	ShopItemData.Rarity.RARE: Color(0.3, 0.55, 1.0),
}
const CARD_SIZE := Vector2(176, 232)

@export var font_size := 16

var _title: Label
var _cards: HBoxContainer
var _reroll: Button
var _skip: Button


func _ready() -> void:
	layer = 7   # over the toast (6), under the run summary (8)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 16)
	dim.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_constant_override("outline_size", 6)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	column.add_child(_title)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 14)
	column.add_child(_cards)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_reroll = Button.new()
	_reroll.text = "Reroll"
	_reroll.tooltip_text = "Draw new cards. Once per level-up, unless the relic tree gives more."
	_reroll.custom_minimum_size = Vector2(150, 36)
	_reroll.focus_mode = Control.FOCUS_NONE
	_reroll.pressed.connect(func(): rerolled.emit())
	row.add_child(_reroll)
	_skip = Button.new()
	_skip.custom_minimum_size = Vector2(150, 36)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(func(): skipped.emit())
	row.add_child(_skip)


static func art_paths(pool: AugmentPool) -> Array:
	var out: Array = CARD.values()
	for a in pool.items:
		if a != null:
			out.append(a.icon_path)
	return out


## Shows one offer. `augments` are the offered AugmentData; `stacks` how many
## of each the player has already.
## `rerolls` is how many are left for this pick; the count shows when above one.
func show_offer(level: int, augments: Array, stacks: Array, rerolls: int, skip_gold: int) -> void:
	_title.text = "Level %d!" % level
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for n in augments.size():
		_cards.add_child(_card(augments[n], int(stacks[n])))
	_reroll.disabled = rerolls <= 0
	_reroll.text = "Reroll" if rerolls <= 1 else "Reroll  (%d)" % rerolls
	_skip.text = "Skip  (+%d gold)" % skip_gold
	visible = true


func hide_screen() -> void:
	visible = false


func _card(a: AugmentData, owned: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = ", ".join(a.tags)
	b.pressed.connect(func(): picked.emit(a.id))
	var bg_path: String = CARD[a.rarity]
	for state in ["normal", "hover", "pressed"]:
		if Art.exists(bg_path):
			var tex := StyleBoxTexture.new()
			tex.texture = Art.texture(bg_path)
			if state != "normal":
				tex.modulate_color = Color(1.15, 1.15, 1.15)
			b.add_theme_stylebox_override(state, tex)
		else:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.1, 0.1, 0.13, 0.97) if state == "normal" else Color(0.16, 0.16, 0.2, 0.97)
			box.border_color = BORDER[a.rarity]
			box.set_border_width_all(3 if state == "normal" else 4)
			box.set_corner_radius_all(8)
			b.add_theme_stylebox_override(state, box)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	col.add_child(_icon(a))
	col.add_child(_label(a.display_name, font_size + 2, Color.WHITE))
	var rarity := "Rare" if a.rarity == ShopItemData.Rarity.RARE else "Common"
	var stack_text := "" if a.max_stacks <= 1 else "  %d / %d" % [owned, a.max_stacks]
	col.add_child(_label(rarity + stack_text, font_size - 4, BORDER[a.rarity].lightened(0.2)))
	var desc := _label(a.description, font_size - 2, Color(0.85, 0.85, 0.88))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = CARD_SIZE.x - 28
	col.add_child(desc)
	return b


func _icon(a: AugmentData) -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Art.exists(a.icon_path):
		var t := TextureRect.new()
		t.texture = Art.texture(a.icon_path)
		t.custom_minimum_size = Vector2(64, 64)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
		return holder
	# Stand-in: a coloured badge with the initials.
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = BORDER[a.rarity].darkened(0.35)
	box.set_corner_radius_all(32)
	badge.add_theme_stylebox_override("panel", box)
	var words := a.display_name.split(" ")
	var initials := ""
	for w in words:
		if w != "":
			initials += w[0]
	var l := _label(initials.substr(0, 2), 24, Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(l)
	holder.add_child(badge)
	return holder


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
