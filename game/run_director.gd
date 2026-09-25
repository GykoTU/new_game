class_name RunDirector
extends RefCounted
## The shape of a run: which day it is, whether it is day or night, and the
## light level the world is drawn with.
##
## Counted in simulation ticks like everything else (section 5 of
## ARCHITECTURE.md), so the cycle pauses with the game and runs faster at 2x
## and 4x. A run starts at dawn of day 1.
##
## Waves (Stage 4) will hang off night_started; the day counter is what makes
## them stronger each day.

## Dusk and dawn: the phase that just ended is in `was_night`.
signal phase_changed(is_night: bool, day: int)
## A new day began (dawn). main.gd autosaves here.
signal day_started(day: int)

## Seconds of simulation time, at speed 1.
var day_seconds := 120.0
var night_seconds := 60.0
## How long the light takes to change at dusk and dawn.
var twilight_seconds := 6.0
## How dark night gets: the world's colour is multiplied by this.
var night_light := 0.55
## The night tint, mixed in as it gets darker.
var night_colour := Color(0.62, 0.70, 1.0)

var day := 1
var is_night := false
## Ticks spent in the current phase.
var phase_ticks := 0


func reset() -> void:
	day = 1
	is_night = false
	phase_ticks = 0


## One simulation tick. Emits at most one phase change per call.
func step() -> void:
	phase_ticks += 1
	if phase_ticks < _phase_ticks_total():
		return
	phase_ticks = 0
	is_night = not is_night
	if not is_night:
		day += 1
		day_started.emit(day)
	phase_changed.emit(is_night, day)


## Dev shortcut only: the current phase ends on the next step().
func force_phase_end() -> void:
	phase_ticks = maxi(int(_phase_ticks_total()) - 1, 0)


func phase_seconds() -> float:
	return night_seconds if is_night else day_seconds


## 0 at the start of the phase, 1 at its end.
func phase_progress() -> float:
	return clampf(float(phase_ticks) / maxf(_phase_ticks_total(), 1.0), 0.0, 1.0)


func seconds_left() -> float:
	return maxf(phase_seconds() - phase_ticks * GameClock.TICK_DELTA, 0.0)


## What the world is tinted with right now: white by day, dark blue at night,
## easing across the twilight at each end of the night.
##
## Opaque, always. A CanvasModulate multiplies alpha too, so a tint with alpha
## below 1 would make the whole world translucent rather than dark.
func light_colour() -> Color:
	var dark := night_colour * night_light
	dark.a = 1.0
	return Color.WHITE.lerp(dark, _darkness())


## 0 in full day, 1 in full night. The building glow fades with it.
func darkness() -> float:
	return _darkness()


## 0 in full day, 1 in full night. Both twilights belong to the NIGHT: dusk is
## its first `twilight_seconds` and dawn its last. Days are therefore always
## fully lit (including the first one, where the player is placing their base),
## and the light is still continuous across both boundaries, because the night
## begins and ends at 0 darkness. A night shorter than two twilights simply
## never reaches full dark.
func _darkness() -> float:
	if not is_night:
		return 0.0
	var into := phase_ticks * GameClock.TICK_DELTA
	var left := maxf(night_seconds - into, 0.0)
	return _smooth(clampf(minf(into, left) / maxf(twilight_seconds, 0.001), 0.0, 1.0))


## Cosine ease, so the light does not jerk at the ends of twilight.
static func _smooth(t: float) -> float:
	return 0.5 - 0.5 * cos(t * PI)


func _phase_ticks_total() -> float:
	return maxf(phase_seconds() / GameClock.TICK_DELTA, 1.0)


func get_save_data() -> Dictionary:
	return {"day": day, "night": is_night, "phase_ticks": phase_ticks}


func load_save_data(data: Dictionary) -> void:
	day = maxi(int(data.get("day", 1)), 1)
	is_night = bool(data.get("night", false))
	phase_ticks = maxi(int(data.get("phase_ticks", 0)), 0)
