extends GridContainer
## The shop's item grid, built from the catalogue. One slot per item of the
## current section (Buy or Craft), in catalogue order: icon, name, level, price.
## Items whose blueprint the run does not know are hidden.
##
## A slot is greyed out when the item is unaffordable or maxed. A resource the
## player is short of is shown in red. When a sale applies, the original price
## is struck through next to the new one and the sale badge appears.

const SALE_BADGE := "res://assets/ui/sale_tag.png"
const SHORT_COLOR := Color(1.0, 0.45, 0.45)
const STRUCK_COLOR := Color(0.55, 0.55, 0.55)

@export var columns_per_row := 4
@export var slot_size := Vector2(132, 150)
@export var icon_size := 48
@export var spacing := 6

var _shop: Shop
var section: ShopItemData.Section = ShopItemData.Section.BUY
var _economy: Economy
## One entry per item: {item, button, level, price, badge}
var _slots: Array[Dictionary] = []


func _ready() -> void:
	columns = columns_per_row
	add_theme_constant_override("h_separation", spacing)
	add_theme_constant_override("v_separation", spacing)


func bind(shop: Shop, economy: Economy, modifiers: ModifierSet) -> void:
	_shop = shop
	_economy = economy
	_build()
	economy.changed.connect(func(_k, _a): refresh())
	modifiers.changed.connect(refresh)
	shop.purchased.connect(func(item, _n):
		if item.kind == ShopItemData.Kind.ITEM:
			_rebuild()
		else:
			refresh())
	if shop.unlocks != null:
		shop.unlocks.changed.connect(_rebuild)
	refresh()


func set_section(value: ShopItemData.Section) -> void:
	section = value
	_rebuild()


func _rebuild() -> void:
	if _shop == null:
		return
	_build()
	refresh()


func _build() -> void:
	for child in get_children():
		remove_child(child)   # now, so the grid lays out only the new slots
		child.queue_free()
	_slots.clear()
	for item in _shop.items():
		if item == null or item.section != section or not _shop.is_known(item):
			continue
		if item.kind == ShopItemData.Kind.ITEM and _shop.is_maxed(item):
			continue   # a one-off item already owned: it leaves the shop
		var button := Button.new()
		button.custom_minimum_size = slot_size
		button.tooltip_text = item.description
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_buy.bind(item))
		_style_slot(button)

		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(box)

		var icon := TextureRect.new()
		icon.texture = Art.texture(item.icon_path)
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)

		box.add_child(_label(item.display_name, 13))
		var level := _label("", 11)
		box.add_child(level)

		var price := RichTextLabel.new()
		price.fit_content = true
		price.scroll_active = false
		price.autowrap_mode = TextServer.AUTOWRAP_OFF
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.add_theme_font_size_override("normal_font_size", 12)
		box.add_child(price)

		var reason := _label("", 10)
		reason.add_theme_color_override("font_color", SHORT_COLOR)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.custom_minimum_size.x = slot_size.x - 12
		box.add_child(reason)

		var badge := TextureRect.new()
		badge.texture = Art.texture(SALE_BADGE)
		badge.custom_minimum_size = Vector2(24, 24)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -26
		badge.offset_right = -2
		badge.offset_top = 2
		badge.offset_bottom = 26
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.visible = false
		button.add_child(badge)

		add_child(button)
		_slots.append({"item": item, "button": button, "level": level,
			"price": price, "badge": badge, "reason": reason})


func refresh() -> void:
	if _shop == null:
		return
	for slot in _slots:
		var item: ShopItemData = slot["item"]
		var n := _shop.purchases_of(item)
		var level: Label = slot["level"]
		if item.kind == ShopItemData.Kind.WORKER:
			level.text = "Bought %d" % n
		elif item.kind == ShopItemData.Kind.BUILDING:
			level.text = "Crafted %d" % n
		elif item.kind == ShopItemData.Kind.ITEM:
			level.text = "One-off"
		elif item.max_level > 0:
			level.text = "Lv %d / %d" % [n, item.max_level]
		else:
			level.text = "Lv %d" % n
		_fill_price(slot["price"], item)
		slot["badge"].visible = _shop.is_discounted(item) and not _shop.is_maxed(item)
		slot["button"].disabled = not _shop.can_buy(item)
		var why := _shop.block_reason(item) if not _shop.is_maxed(item) else ""
		slot["reason"].text = why
		slot["reason"].visible = why != ""
		slot["button"].tooltip_text = item.description + ("\n" + why if why != "" else "")


func _fill_price(rich: RichTextLabel, item: ShopItemData) -> void:
	rich.clear()
	rich.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	if _shop.is_maxed(item):
		rich.add_text("MAX")
		rich.pop()
		return
	var now := _shop.price(item)
	var was := _shop.base_price(item)
	var kinds := now.keys()
	kinds.sort()
	for kind in kinds:
		rich.add_image(Art.texture(ResourceKind.icon_path_of(kind)), 14, 14)
		if int(was.get(kind, 0)) != int(now[kind]):
			rich.push_color(STRUCK_COLOR)
			rich.push_strikethrough()
			rich.add_text(" %d" % was[kind])
			rich.pop()
			rich.pop()
		var short := _economy.amount(kind) < int(now[kind])
		if short:
			rich.push_color(SHORT_COLOR)
		rich.add_text(" %d  " % now[kind])
		if short:
			rich.pop()
	rich.pop()


## Slots need their own outline: the default button style is nearly the same
## colour as the shop's backing panel and the slots blur into one block.
func _style_slot(button: Button) -> void:
	var looks := {
		"normal":   [Color(0.15, 0.15, 0.18), Color(0.32, 0.32, 0.38)],
		"hover":    [Color(0.21, 0.21, 0.25), Color(0.55, 0.55, 0.62)],
		"pressed":  [Color(0.12, 0.12, 0.14), Color(0.55, 0.55, 0.62)],
		"disabled": [Color(0.11, 0.11, 0.12), Color(0.20, 0.20, 0.23)],
	}
	for state in looks:
		var box := StyleBoxFlat.new()
		box.bg_color = looks[state][0]
		box.border_color = looks[state][1]
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, box)


func _on_buy(item: ShopItemData) -> void:
	_shop.buy(item)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
