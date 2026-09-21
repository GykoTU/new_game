extends CanvasLayer
## The shop window. Toggled by the "shop" action; does not pause the game --
## the player has a pause key for that.

@onready var _items := $Panel/VBox/ShopItems
@onready var _hint: Label = $Panel/VBox/Hint


func _ready() -> void:
	visible = false


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
