class_name MarbleBag
extends RefCounted
## Random with memory (tuned after Stage 10): a bag of marbles drawn WITHOUT
## putting them back. When it is empty it is refilled with the same marbles.
## Over one bagful every outcome comes up exactly as often as it is in the bag,
## so bad luck cannot run on for long: a 1-in-20 chance that has missed 19
## times hits on the 20th draw.
##
## The same idea as the "marblebag" addon for Godot, written here so the game
## has no addon to install and the bags save with the run.

var rng: RandomNumberGenerator
var _all: Array = []
var _left: Array = []


func _init(contents: Array = [], p_rng: RandomNumberGenerator = null) -> void:
	_all = contents.duplicate()
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


## Draws one marble (refilling first if the bag is empty). null if the bag
## holds nothing at all.
func draw() -> Variant:
	if _all.is_empty():
		return null
	if _left.is_empty():
		_left = _all.duplicate()
	var i := rng.randi_range(0, _left.size() - 1)
	var m = _left[i]
	_left.remove_at(i)
	return m


func left() -> int:
	return _left.size()


func marbles() -> Array:
	return _all.duplicate()


func get_save_data() -> Dictionary:
	return {"all": _all.duplicate(), "left": _left.duplicate()}


func load_save_data(data: Dictionary) -> void:
	_all = Array(data.get("all", _all))
	_left = Array(data.get("left", []))
