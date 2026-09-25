class_name ExploreFlags
extends Node2D
## A flag where each explorer is headed, drawn over the fog so the player can
## see where they sent it. Optional art: until assets/ui/explore_flag.png
## exists nothing is drawn at all (a grey placeholder square floating in the
## fog would look like a bug, not like a flag).

const FLAG := "res://assets/ui/explore_flag.png"

var _texture: Texture2D
var _store: UnitStore
var _level: LevelGenerator
var _drawn := PackedInt32Array()   # goals drawn last frame, to skip redundant redraws


func _ready() -> void:
	z_index = 3   # above the fog (2)
	if Art.exists(FLAG):
		_texture = Art.texture(FLAG)


func bind(store: UnitStore, level: LevelGenerator) -> void:
	_store = store
	_level = level


## Called once per rendered frame from main.gd. Redraws only when a goal moved.
func refresh() -> void:
	if _texture == null or _store == null:
		return
	var goals := PackedInt32Array()
	for id in _store.ids_of_kind(WorkerRoster.Kind.EXPLORER):
		if _store.goal[id] != UnitStore.NONE:
			goals.append(_store.goal[id])
	if goals != _drawn:
		_drawn = goals
		queue_redraw()


func _draw() -> void:
	if _texture == null:
		return
	var half := _texture.get_size() / 2.0
	for goal in _drawn:
		draw_texture(_texture, _level.cell_to_world(_level.grid.cell_at(goal)) - half)
