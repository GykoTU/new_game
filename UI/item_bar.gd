extends CanvasLayer
## Items the run owns (the bucket, later more), as a row of slots in the top
## left corner. Hidden while the run owns none. Clicking a slot emits
## item_pressed; main.gd decides what that means (the empty bucket is taken to
## a water tile, the same way a building is placed).
##
## Items are unlock ids (see Unlocks). An item can have stages -- the empty
## bucket becomes the water bucket -- so each slot lists its ids best first
## and shows the first one owned.

signal item_pressed(id: String)

const SLOT_TEXTURE := "res://assets/ui/building_slot.png"

## One entry per slot: [unlock id, name, icon, tooltip], best stage first.
const ITEMS := [
	[
		["item:water_bucket", "Water bucket", "res://assets/ui/bucket_full.png",
			"Click it, then drag over lava to mark it. Builders turn marked lava into cobble."],
		["item:bucket", "Bucket (empty)", "res://assets/ui/bucket_empty.png",
			"Click it, then click a water tile: a builder goes there and fills it."],
	],
]

## Whole multiples of 32 px: the frame at 2x, the item at 1x.
@export var slot_size := 64
@export var icon_size := 32

var _unlocks: Unlocks
var _row: HBoxContainer


func _ready() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	_row.position = Vector2(8, 8)
	_row.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_row)


func bind(unlocks: Unlocks) -> void:
	_unlocks = unlocks
	unlocks.changed.connect(refresh)
	refresh()


## Every stage icon, for the missing-art report.
static func art_paths() -> Array:
	var out := [SLOT_TEXTURE]
	for stages in ITEMS:
		for stage in stages:
			out.append(stage[2])
	return out


func refresh() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for stages in ITEMS:
		for stage in stages:
			if _unlocks.has(stage[0]):
				_row.add_child(_make_slot(stage))
				break
	_row.visible = _row.get_child_count() > 0


func _make_slot(stage: Array) -> Control:
	var frame := TextureRect.new()
	frame.texture = Art.texture(SLOT_TEXTURE)
	frame.custom_minimum_size = Vector2(slot_size, slot_size)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.tooltip_text = "%s\n%s" % [stage[1], stage[3]]
	var id: String = stage[0]
	frame.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("left_click"):
			item_pressed.emit(id)
			frame.accept_event())
	frame.mouse_entered.connect(func(): frame.modulate = Color(1.25, 1.25, 1.25))
	frame.mouse_exited.connect(func(): frame.modulate = Color.WHITE)
	var icon := TextureRect.new()
	icon.texture = Art.texture(stage[2])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.offset_left = -icon_size / 2.0
	icon.offset_top = -icon_size / 2.0
	icon.offset_right = icon_size / 2.0
	icon.offset_bottom = icon_size / 2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	return frame
