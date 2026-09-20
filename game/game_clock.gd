class_name GameClock
extends Node
## Owns simulation time for a run. See ARCHITECTURE.md, "Time and the update loop".
##
## The clock never scales delta. It hands out whole ticks of a FIXED size, and a
## higher game speed simply produces more of them per frame. Scaling delta
## instead would change how far things move between collision samples, which at
## 4x would let a projectile pass straight through a one-tile wall. Every speed
## therefore simulates identically -- faster only means more of the same steps.
##
## The clock has no _process of its own on purpose. Godot calls _process on a
## parent before its children, so a clock that ticked itself would always be one
## frame behind the Main node reading it. Main calls advance() explicitly, which
## also keeps the whole update order visible in one place.

## Emitted when the speed setting changes. Also mirrored on EventBus.
signal speed_changed(speed: float)
## Emitted when the clock starts or stops running, for any reason.
signal running_changed(is_running: bool)

## Length of one simulation tick, in seconds. Identical at every game speed.
const TICK_DELTA := 1.0 / 60.0

## Ceiling on ticks produced in a single frame. Without it a slow frame requests
## more ticks next frame, which makes that frame slower still -- the classic
## death spiral. Hitting the cap means simulation time falls behind wall-clock
## time, which is the right trade: the game slows down instead of locking up.
const MAX_TICKS_PER_FRAME := 8

## Player-selectable speeds, in order. Index maps to the game_speed_1..3 actions.
const SPEED_STEPS: PackedFloat32Array = [1.0, 2.0, 4.0]

## Pause reason used by the player's own pause key.
const PAUSE_PLAYER := "player"

## Current speed multiplier. Independent of pausing: a paused clock remembers
## the speed it will resume at.
var speed: float = 1.0:
	set(value):
		value = maxf(value, 0.0)
		if is_equal_approx(value, speed):
			return
		var was_running := is_running()
		speed = value
		speed_changed.emit(speed)
		EventBus.game_speed_changed.emit(speed)
		_notify_running(was_running)

## Simulation ticks elapsed since the run began. Advances only while the clock
## runs, so unlike wall-clock time it is unaffected by pausing, frame rate or
## the speed setting. That makes it the deterministic measure of run progress,
## and it is what the run save stores.
var tick_count: int = 0

## Leftover wall-clock time not yet converted into a whole tick.
var _accumulator := 0.0
## Active pause reasons, used as a set. A reason must be popped by whoever
## pushed it, so closing the options menu cannot resume a run the player
## deliberately paused.
var _pause_reasons := {}


## Advances wall-clock time and returns how many simulation ticks to run now.
## Call once per frame, before stepping any system.
func advance(delta: float) -> int:
	if not is_running():
		# Drop the leftover so resuming does not fast-forward through the time
		# spent sitting in a menu.
		_accumulator = 0.0
		return 0

	_accumulator += delta * speed
	var ticks := int(_accumulator / TICK_DELTA)
	if ticks > MAX_TICKS_PER_FRAME:
		ticks = MAX_TICKS_PER_FRAME
		_accumulator = 0.0
	else:
		_accumulator -= ticks * TICK_DELTA
	tick_count += ticks
	return ticks


# --- Pausing ------------------------------------------------------------------

## Suppresses time under a named reason. Pushing the same reason twice is a
## no-op, so callers do not need to track whether they already pushed it.
func push_pause(reason: String) -> void:
	if _pause_reasons.has(reason):
		return
	var was_running := is_running()
	_pause_reasons[reason] = true
	_notify_running(was_running)


func pop_pause(reason: String) -> void:
	if not _pause_reasons.has(reason):
		return
	var was_running := is_running()
	_pause_reasons.erase(reason)
	_notify_running(was_running)


func has_pause(reason: String) -> bool:
	return _pause_reasons.has(reason)


func toggle_player_pause() -> void:
	if has_pause(PAUSE_PLAYER):
		pop_pause(PAUSE_PLAYER)
	else:
		push_pause(PAUSE_PLAYER)


## Clears every reason. For run teardown only -- not for closing a menu.
func clear_pauses() -> void:
	if _pause_reasons.is_empty():
		return
	var was_running := is_running()
	_pause_reasons.clear()
	_notify_running(was_running)


func is_paused() -> bool:
	return not _pause_reasons.is_empty()


## True when simulation time is actually advancing.
func is_running() -> bool:
	return _pause_reasons.is_empty() and speed > 0.0


## Seconds of simulation time elapsed this run. Derived from tick_count, so it
## stays consistent with the simulation rather than with the wall clock.
func get_elapsed_seconds() -> float:
	return tick_count * TICK_DELTA


## Plain data for the run save. Speed is included so resuming feels the same
## way the player left it; tick_count is the part that actually matters.
func get_save_data() -> Dictionary:
	return {"tick_count": tick_count, "speed": speed}


func load_save_data(data: Dictionary) -> void:
	tick_count = int(data.get("tick_count", 0))
	speed = float(data.get("speed", 1.0))
	_accumulator = 0.0


func _notify_running(was_running: bool) -> void:
	var now := is_running()
	if now != was_running:
		running_changed.emit(now)
