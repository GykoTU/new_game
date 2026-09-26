class_name BehaviourSet
extends RefCounted
## One weapon type's behaviours, pre-sorted into a list per hook (D6). Shared
## by every shot of that type; rebuilt only when the run learns a behaviour
## upgrade (WeaponSystem._compile), never per shot.

var ids := PackedStringArray()
var spawn: Array[Behaviour] = []
var step: Array[Behaviour] = []
var wall: Array[Behaviour] = []
var hit: Array[Behaviour] = []
var expire: Array[Behaviour] = []
var kill: Array[Behaviour] = []
## Hit effects a chain passes on (slow, burn, knockback).
var secondary: Array[Behaviour] = []
## False when the shot does its damage some other way: an exploding shell
## hurts through its blast, so the enemy it touched is not hit twice.
var direct_damage := true
var knockback_radial := false
## Lands where it was aimed, hit or miss (a shell).
var lands := false


func _init(p_ids: PackedStringArray = PackedStringArray()) -> void:
	var made: Array[Behaviour] = []
	for id in p_ids:
		if ids.has(id):
			continue
		var b := Behaviours.make(id)
		if b == null:
			push_warning("BehaviourSet: unknown behaviour '%s', skipped." % id)
			continue
		ids.append(id)
		made.append(b)
	made.sort_custom(func(a: Behaviour, b: Behaviour): return a.priority < b.priority)
	for b in made:
		var h := b.hooks()
		if h & Behaviour.ON_SPAWN: spawn.append(b)
		if h & Behaviour.ON_STEP: step.append(b)
		if h & Behaviour.ON_WALL: wall.append(b)
		if h & Behaviour.ON_HIT: hit.append(b)
		if h & Behaviour.ON_EXPIRE: expire.append(b)
		if h & Behaviour.ON_KILL: kill.append(b)
		if b.secondary: secondary.append(b)
	direct_damage = not (ids.has("explode") or ids.has("chain_ball"))
	knockback_radial = ids.has("explode")
	lands = ids.has("explode")


func has(id: String) -> bool:
	return ids.has(id)
