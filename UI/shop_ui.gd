extends CanvasLayer
## The shop window. Toggled by the "shop" action; does not pause the game --
## the player has a pause key for that.
##
## Three tabs: Buy (workers, gold), Craft (buildings and items, resources)
## and Upgrades. Craft has two small sub-tabs, Utility and Weapons; Upgrades
## has Weapons and Workers. The item grid scrolls, at most three rows tall.

const TAB_WEAPONS := "res://assets/ui/tab_weapons.png"
const TAB_WORKERS := "res://assets/ui/tab_workers.png"
const TAB_UTILITY := "res://assets/ui/tab_utility.png"

@onready var _items := $Panel/VBox/ShopItems
@onready var _hint: Label = $Panel/VBox/Hint

var _tabs := {}   # ShopItemData.Section -> Button
var _groups: HBoxContainer
var _craft_groups: HBoxContainer
var _empty: Label


func _ready() -> void:
	visible = false
	layer = 4   # over the day and worker bars; under the resource bar (5), so prices stay in view
	var vbox := $Panel/VBox
	# Centred in the space under the resource bar.
	$Panel.position.y += 20.0
	# Buy / Craft / Upgrades, above the grid.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	var tabs := [
		[ShopItemData.Section.BUY, "Buy", "Workers, paid in gold."],
		[ShopItemData.Section.CRAFT, "Craft", "Buildings and items, paid in resources. Needs a blueprint."],
		[ShopItemData.Section.UPGRADES, "Upgrades", "Weapon and worker upgrades. Each needs its blueprint."],
	]
	for tab in tabs:
		var s: int = tab[0]
		var b := _tab_button(tab[1], tab[2], group, Vector2(96, 30))
		b.button_pressed = s == ShopItemData.Section.BUY
		b.pressed.connect(_on_section.bind(s))
		row.add_child(b)
		_tabs[s] = b
	vbox.add_child(row)
	vbox.move_child(row, 1)

	# Sub-tabs: Utility / Weapons under Craft, Weapons / Workers under Upgrades.
	_craft_groups = _sub_tabs([
		[ShopItemData.CraftGroup.UTILITY, "Utility", TAB_UTILITY],
		[ShopItemData.CraftGroup.WEAPONS, "Weapons", TAB_WEAPONS]], _items.set_craft_group)
	vbox.add_child(_craft_groups)
	vbox.move_child(_craft_groups, 2)
	_groups = _sub_tabs([
		[ShopItemData.UpgradeGroup.WEAPONS, "Weapons", TAB_WEAPONS],
		[ShopItemData.UpgradeGroup.WORKERS, "Workers", TAB_WORKERS]], _items.set_group)
	vbox.add_child(_groups)
	vbox.move_child(_groups, 3)

	# The grid scrolls, capped at three rows (ShopItems sizes the scroll area).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)
	vbox.move_child(scroll, _items.get_index())
	_items.reparent(scroll, false)

	_empty = Label.new()
	_empty.text = "Nothing here yet. Blueprints come from caches and fallen enemies."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_empty.add_theme_font_size_override("font_size", 13)
	_empty.visible = false
	vbox.add_child(_empty)
	vbox.move_child(_empty, scroll.get_index() + 1)
	_items.rebuilt.connect(_on_rebuilt)


## A row of small toggle buttons, the first pressed; `pick` gets the value.
func _sub_tabs(entries: Array, pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for n in entries.size():
		var e: Array = entries[n]
		var b := _tab_button(e[1], "", group, Vector2(84, 24))
		b.add_theme_font_size_override("font_size", 12)
		if Art.exists(e[2]):
			b.icon = Art.texture(e[2])
		b.button_pressed = n == 0
		b.pressed.connect(pick.bind(e[0]))
		row.add_child(b)
	row.visible = false
	return row


func _tab_button(text: String, tip: String, group: ButtonGroup, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	return b


func _on_section(s: ShopItemData.Section) -> void:
	_groups.visible = s == ShopItemData.Section.UPGRADES
	_craft_groups.visible = s == ShopItemData.Section.CRAFT
	_items.set_section(s)


func _on_rebuilt(count: int) -> void:
	_empty.visible = count == 0


## Art the shop uses beyond its items, for the missing-art report.
static func art_paths() -> Array:
	return [TAB_WEAPONS, TAB_WORKERS, TAB_UTILITY]


func bind(shop: Shop, economy: Economy, modifiers: ModifierSet) -> void:
	_items.bind(shop, economy, modifiers)


# _unhandled_input, not _input: while the controls list is capturing a new
# binding it consumes keys in _input, and the shop must not toggle underneath.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop"):
		visible = not visible
		if visible:
			_items.refresh()
			# Shows the live binding, so a rebound shop key is reflected here.
			_hint.text = "%s to close" % Keybinds.describe_action("shop")
		get_viewport().set_input_as_handled()
