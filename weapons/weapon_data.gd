class_name WeaponData
extends Resource
## What a weapon building fires (Stage 5). Referenced from its BuildingData
## (`weapon`), and shared by every building of that type: one StatBlock and
## one behaviour set per TYPE, never per building (D7).
##
## Numbers are stats (`base_stats`), so upgrades are ordinary modifiers on the
## weapon's tags. Behaviours (`behaviours`) decide what happens; they read their
## numbers from those stats (ARCHITECTURE.md, "Weapon behaviours").

enum TargetMode {
	NEAREST,     ## closest to the weapon
	STRONGEST,   ## most health left
	FIRST,       ## closest to the building it is attacking
}

## Same as the building's id, e.g. "arrow_tower". Saves and unlocks use it.
@export var id := ""
@export var display_name := ""
@export var default_target := TargetMode.NEAREST
## Stat tags: always "weapon" plus the id, so "+10% damage to all weapons" and
## "+1 pierce for arrow towers" are both plain modifiers.
@export var tags := PackedStringArray()
## Starting values of this weapon's stats, by Stats.Id.
@export var base_stats: Dictionary[Stats.Id, float] = {}
## Behaviour ids every shot has (see Behaviours.make). Upgrades add more.
@export var behaviours := PackedStringArray()
## Persistent weapons (the whirl tower) keep PROJECTILE_COUNT shots alive around
## them instead of firing at targets; a lost shot is replaced after a cooldown.
@export var persistent := false
## Split, chain and on-kill explosions stop at this generation.
@export var max_generation := 2
## Whether its shots hurt your workers. Default true: routing workers around
## your own defences is part of the game.
@export var friendly_fire := true
## Degrees between shots when PROJECTILE_COUNT > 1.
@export var spread := 12.0

@export_group("Shot")
## 32x32, drawn pointing right; a horizontal strip animates.
@export_file("*.png") var projectile_sprite := ""
## The stand-in dot's colour while the sprite does not exist.
@export var projectile_color := Color(1.0, 0.9, 0.5)
## Hit radius in pixels.
@export var projectile_radius := 5.0
## Turn the sprite to face its flight (arrows yes, cannonballs no).
@export var rotate_sprite := true
## Spin as it flies, in radians a second (the chain ball tumbles). 0 = none.
@export var spin_speed := 0.0
## Drawn as two halves pulled apart by how far the shot's hit radius has grown
## past projectile_radius, with the sprite's middle column stretched between
## them: the chain ball's chain paying out (WeaponEffects draws these shots).
@export var draw_split := false
