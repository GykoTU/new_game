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
	[
		["item:shovel", "Shovel", "res://assets/ui/shovel.png",
			"Click it, then click buildings to mark them (again to unmark). A builder digs a marked building out; half its crafting cost comes back."],
	],
]

## The build tools (Stage 6), in their own bar in the bottom-right corner:
## the same slots, a second instance of this script with `tools` set.
## A fifth entry is the picture used until the tool icon exists.
const TOOLS := [
	[
		["blueprint:wall", "Walls", "res://assets/ui/tool_wall.png",
			"Drag to paint walls (1 iron each); hold Shift for gates (4 wood and 1 iron). Start on an unbuilt one to take it back.",
			"res://assets/buildings/walls/wall.png"],
	],
	[
		["blueprint:road", "Roads", "res://assets/ui/tool_road.png",
			"Drag to paint roads (1 wood each). Your workers walk faster on them; enemies do not.",
			"res://assets/ground/road.png"],
	],
	[
		["blueprint:bridge", "Bridges", "res://assets/ui/tool_bridge.png",
			"Drag over water to paint a bridge (2 wood and 1 copper each). Builders build out from the shore.",
			"res://assets/ground/bridge.png"],
	],
	[
		["blueprint:crossing", "Void crossings", "res://assets/ui/tool_crossing.png",
			"Drag over void to paint a crossing (2 wood and 1 quartz each). Builders build out from the edge.",
			"res://assets/ground/crossing.png"],
	],
]

## Whole multiples of 32 px: the frame at 2x, the item at 1x.
@export var slot_size := 64
@export var icon_size := 32

## Set before adding to the tree: this bar shows the build tools, bottom
## right, instead of the items, top left.
var tools := false

var _unlocks: Unlocks
var _row: HBoxContainer


func _ready() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	_row.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_row)
	if tools:
		# Bottom right: anchored to the corner, growing left and up from it.
		_row.anchor_left = 1.0
		_row.anchor_top = 1.0
		_row.anchor_right = 1.0
		_row.anchor_bottom = 1.0
		_row.offset_left = -8
		_row.offset_top = -8
		_row.offset_right = -8
		_row.offset_bottom = -8
		_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		_row.position = Vector2(8, 8)


func bind(unlocks: Unlocks) -> void:
	_unlocks = unlocks
	unlocks.changed.connect(refresh)
	refresh()


## Every stage icon, for the missing-art report.
static func art_paths() -> Array:
	var out := [SLOT_TEXTURE]
	for stages in ITEMS + TOOLS:
		for stage in stages:
			out.append(stage[2])
	return out


## The slot's icon: the tool icon, or its stand-in picture until it exists.
static func icon_of(stage: Array) -> String:
	if Art.exists(stage[2]) or stage.size() < 5:
		return stage[2]
	return stage[4]


func refresh() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for stages in (TOOLS if tools else ITEMS):
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
	icon.texture = Art.texture(icon_of(stage))
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
