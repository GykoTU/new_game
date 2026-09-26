class_name FlowField
extends RefCounted
## Distance-to-target for every tile, for one target building and one way of
## moving (D5). Enemies read `dist` and step to whichever neighbour is closer;
## no enemy ever runs a path search of its own.
##
## Built by Dijkstra from the target outward, with a BUCKET queue (Dial's
## algorithm): step costs are small integers, so a ring of buckets indexed by
## distance replaces a heap. The buckets are linked lists in flat packed arrays,
## because packed arrays stored inside an Array are copied on every write in
## GDScript -- a bucket of PackedInt32Array would make each push O(n).
##
## Built a slice at a time (`advance(budget)`) into a back buffer while enemies
## keep reading the finished front buffer, so a rebuild never stalls a frame
## and never leaves enemies without directions.

const INF := 1 << 30
## Larger than the biggest single step (a diagonal into a building: 350).
const BUCKETS := 512
const MASK := BUCKETS - 1
## Diagonal step cost for every straight step cost: x1.4, as integers.
static var DIAG := _diag_table()

var target := -1
var flying := false
## What enemies read. Empty until the first build finishes.
var dist := PackedInt32Array()
## Bumped on every finished build, so enemies know to re-plan their next step.
var version := 0
## Last tick an enemy planned with this field (for eviction).
var last_used := 0
## Set while a rebuild is wanted but one is already running.
var dirty := false

var _work := PackedInt32Array()
var _head := PackedInt32Array()
var _node_tile := PackedInt32Array()
var _node_dist := PackedInt32Array()
var _node_next := PackedInt32Array()
var _free_nodes := PackedInt32Array()
var _free_top := 0
var _queued := 0
var _d := 0
var _building := false


func is_ready() -> bool:
	return not dist.is_empty()


func is_building() -> bool:
	return _building


## Starts a (re)build toward these tiles.
func start(tile_count: int, goal_tiles: PackedInt32Array) -> void:
	_work.resize(tile_count)
	_work.fill(INF)
	_head.resize(BUCKETS)
	_head.fill(-1)
	_free_top = 0
	_node_tile.resize(0)
	_node_dist.resize(0)
	_node_next.resize(0)
	_free_nodes.resize(0)
	_queued = 0
	_d = 0
	for i in goal_tiles:
		_work[i] = 0
		_push(i, 0)
	_building = true
	dirty = false


## Expands up to `budget` tiles. Returns how many it expanded; the field turns
## ready (and `version` goes up) on the call that finishes.
func advance(costs: PackedByteArray, width: int, height: int, budget: int) -> int:
	if not _building:
		return 0
	var done := 0
	while done < budget and _queued > 0:
		var b := _d & MASK
		var node := _head[b]
		if node == -1:
			_d += 1
			continue
		_head[b] = _node_next[node]
		_queued -= 1
		var i := _node_tile[node]
		var d := _node_dist[node]
		_free_nodes[_free_top] = node   # capacity grows with the node pool
		_free_top += 1
		if d != _work[i]:
			continue   # superseded by a shorter route found later
		done += 1
		@warning_ignore("integer_division")
		var y := i / width
		var x := i - y * width
		var up := y > 0
		var down := y < height - 1
		var left := x > 0
		var right := x < width - 1
		# dist[n] is what it costs to reach the target FROM n, counting the
		# tile n itself: stepping into a building costs BREAK_COST, and an
		# enemy choosing between neighbours then compares totals directly.
		# The comparisons are inlined: most neighbours are not improved, and a
		# function call per neighbour would double the cost of a build.
		var n := 0
		var c := 0
		var nd := 0
		var n_up := up and costs[i - width] != 0
		var n_down := down and costs[i + width] != 0
		var n_left := left and costs[i - 1] != 0
		var n_right := right and costs[i + 1] != 0
		if n_up:
			n = i - width; nd = d + costs[n]
			if nd < _work[n]: _work[n] = nd; _push(n, nd)
		if n_down:
			n = i + width; nd = d + costs[n]
			if nd < _work[n]: _work[n] = nd; _push(n, nd)
		if n_left:
			n = i - 1; nd = d + costs[n]
			if nd < _work[n]: _work[n] = nd; _push(n, nd)
		if n_right:
			n = i + 1; nd = d + costs[n]
			if nd < _work[n]: _work[n] = nd; _push(n, nd)
		# Diagonals only where neither side is solid: no cutting corners.
		if n_up and n_left:
			n = i - width - 1; c = costs[n]
			if c != 0:
				nd = d + DIAG[c]
				if nd < _work[n]: _work[n] = nd; _push(n, nd)
		if n_up and n_right:
			n = i - width + 1; c = costs[n]
			if c != 0:
				nd = d + DIAG[c]
				if nd < _work[n]: _work[n] = nd; _push(n, nd)
		if n_down and n_left:
			n = i + width - 1; c = costs[n]
			if c != 0:
				nd = d + DIAG[c]
				if nd < _work[n]: _work[n] = nd; _push(n, nd)
		if n_down and n_right:
			n = i + width + 1; c = costs[n]
			if c != 0:
				nd = d + DIAG[c]
				if nd < _work[n]: _work[n] = nd; _push(n, nd)
	if _queued == 0:
		var t := dist
		dist = _work
		_work = t
		_building = false
		version += 1
	return done


static func _diag_table() -> PackedInt32Array:
	var t := PackedInt32Array()
	t.resize(256)
	for c in 256:
		t[c] = int(round(c * 1.4))
	return t


func _push(i: int, d: int) -> void:
	var node: int
	if _free_top > 0:
		_free_top -= 1
		node = _free_nodes[_free_top]
	else:
		node = _node_tile.size()
		_node_tile.append(0)
		_node_dist.append(0)
		_node_next.append(0)
		_free_nodes.append(0)
	_node_tile[node] = i
	_node_dist[node] = d
	var b := d & MASK
	_node_next[node] = _head[b]
	_head[b] = node
	_queued += 1
