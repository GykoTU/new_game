extends CanvasLayer
## The shop window. Toggled by the "shop" action; does not pause the game --
## the player has a pause key for that.

@onready var _items := $Panel/VBox/ShopItems
@onready var _hint: Label = $Panel/VBox/Hint


var _tabs := {}   # ShopItemData.Section -> Button


func _ready() -> void:
	visible = false
	# Buy (gold) and Craft (resources) tabs, above the grid.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for s in [ShopItemData.Section.BUY, ShopItemData.Section.CRAFT]:
		var b := Button.new()
		b.text = "Buy" if s == ShopItemData.Section.BUY else "Craft"
		b.tooltip_text = "Workers and upgrades, paid in gold." if s == ShopItemData.Section.BUY \
			else "Buildings and items, paid in resources. Needs a blueprint."
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 30)
		b.button_pressed = s == ShopItemData.Section.BUY
		b.pressed.connect(_items.set_section.bind(s))
		row.add_child(b)
		_tabs[s] = b
	var vbox := $Panel/VBox
	vbox.add_child(row)
	vbox.move_child(row, 1)


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
