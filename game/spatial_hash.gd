class_name SpatialHash
extends RefCounted
## "Who is near this point?" for hundreds of moving things (ARCHITECTURE.md
## section 10). Rebuilt from scratch every simulation tick with a counting
## sort -- two passes over the ids, no allocation once warm -- and queried by
## the cells a circle overlaps. Callers do the exact distance test.
##
## Positions outside the map clamp to the border cells, so nothing is lost.

var cell_size := 64.0
var origin := Vector2.ZERO
var cols := 1
var rows := 1

var _start := PackedInt32Array()   # per cell: first index into _items; one extra at the end
var _items := PackedInt32Array()   # ids, grouped by cell
var _cell := PackedInt32Array()    # scratch: each id's cell, in rebuild order
var _fill := PackedInt32Array()    # scratch: write cursor per cell


## `size` is the area covered, in pixels, starting at `p_origin`.
func configure(p_origin: Vector2, size: Vector2, p_cell_size: float) -> void:
	origin = p_origin
	cell_size = p_cell_size
	cols = maxi(int(ceil(size.x / cell_size)), 1)
	rows = maxi(int(ceil(size.y / cell_size)), 1)
	_start.resize(cols * rows + 1)
	_fill.resize(cols * rows)
	_start.fill(0)


func _cell_of(p: Vector2) -> int:
	var cx := clampi(floori((p.x - origin.x) / cell_size), 0, cols - 1)
	var cy := clampi(floori((p.y - origin.y) / cell_size), 0, rows - 1)
	return cy * cols + cx


## `ids` are the entries to index; `positions` is indexed BY id.
func rebuild(ids: PackedInt32Array, positions: PackedVector2Array) -> void:
	var n := ids.size()
	_items.resize(n)
	_cell.resize(n)
	_start.fill(0)
	for k in n:
		var c := _cell_of(positions[ids[k]])
		_cell[k] = c
		_start[c + 1] += 1
	for c in cols * rows:
		_start[c + 1] += _start[c]
	for c in cols * rows:
		_fill[c] = _start[c]
	for k in n:
		var c := _cell[k]
		_items[_fill[c]] = ids[k]
		_fill[c] += 1


## Every id in the cells a circle overlaps. Some may be outside the circle.
func query(center: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := clampi(floori((center.x - radius - origin.x) / cell_size), 0, cols - 1)
	var x1 := clampi(floori((center.x + radius - origin.x) / cell_size), 0, cols - 1)
	var y0 := clampi(floori((center.y - radius - origin.y) / cell_size), 0, rows - 1)
	var y1 := clampi(floori((center.y + radius - origin.y) / cell_size), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := cy * cols + cx
			for k in range(_start[c], _start[c + 1]):
				out.append(_items[k])
	return out


## The nearest id within `radius` of `center`, or -1.
func nearest(center: Vector2, radius: float, positions: PackedVector2Array) -> int:
	var best := -1
	var best_d := radius * radius
	for id in query(center, radius):
		var d := positions[id].distance_squared_to(center)
		if d <= best_d:
			best = id
			best_d = d
	return best
