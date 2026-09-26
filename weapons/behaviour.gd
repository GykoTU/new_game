class_name Behaviour
extends RefCounted
## One thing a shot can DO (D6): bounce, split, hook, explode... A behaviour is
## a stateless singleton shared by every shot and every weapon that has it;
## whatever it needs to remember about one shot lives in that shot's scratch
## slots (ProjectileStore). Its numbers come from the weapon's stats
## (`w.stat(type, Stats.Id.BOUNCE_COUNT)`), so "+1 bounce" is a modifier and
## never code.
##
## A subclass overrides the hooks it needs and lists them in hooks(); a
## BehaviourSet only calls a behaviour from the hooks it declared, so an
## arrow with no stepping behaviour costs nothing per tick beyond its flight.
## All the behaviours are in behaviours.gd, made by Behaviours.make(id).

const ON_SPAWN := 1
const ON_STEP := 2
const ON_WALL := 4
const ON_HIT := 8
const ON_EXPIRE := 16
const ON_KILL := 32

## Its id in data and unlocks ("bounce" in "behaviour.cannon.bounce").
var id := ""
## Lower runs first within each hook. Explode (10) runs before bounce (60), so
## a bouncing shell explodes, then bounces.
var priority := 50
## Also applied to the enemies a chain jumps to (slow, burn, knockback): the
## effects of being hit, as opposed to what the shot itself does next.
var secondary := false


func hooks() -> int:
	return 0


## Just fired.
func on_spawn(_w: WeaponSystem, _p: int) -> void:
	pass


## Every tick, before it moves. Steer by changing vel[p]; to put a shot at an
## exact point, set vel[p] = (point - pos[p]) / dt so walls still apply.
func on_step(_w: WeaponSystem, _p: int, _dt: float) -> void:
	pass


## It is about to enter a tile that stops shots (or leave the map). `normal`
## is the side it hit, both axes for a corner. Return true to keep flying.
func on_wall_hit(_w: WeaponSystem, _p: int, _normal: Vector2) -> bool:
	return false


## It hit enemy `e` (after its direct damage). `final`: it has no pierce left,
## so it ends here unless some behaviour returns true to keep it going.
func on_unit_hit(_w: WeaponSystem, _p: int, _e: int, _final: bool) -> bool:
	return false


## Its life ran out. Return true to keep it (a hook reels back in first).
func on_expire(_w: WeaponSystem, _p: int) -> bool:
	return false


## Something of weapon type `type` killed an enemy at `at`: a shot, a blast or
## a burn. `gen` is the killer's generation. The shot may already be gone, so
## this gets no shot id.
func on_kill(_w: WeaponSystem, _type: int, _gen: int, _at: Vector2, _max_hp: float) -> void:
	pass
