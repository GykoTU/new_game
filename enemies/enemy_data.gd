class_name EnemyData
extends Resource
## One kind of enemy (Stage 4). Numbers live here, not in code, so balancing is
## editing a .tres. Referenced by `id` in saves, so an id must never change.

@export var id := ""
@export var display_name := ""

@export_group("Sprites")
## 32x32, or a horizontal strip of 32x32 frames.
@export_file("*.png") var sprite_idle := ""
## Optional. Missing: the idle sprite is used while moving too.
@export_file("*.png") var sprite_walk := ""
## Optional. Missing: the walk (or idle) sprite is used while attacking.
@export_file("*.png") var sprite_attack := ""

@export_group("Body")
@export var max_health := 30.0
## Pixels per second at speed 1 (a tile is 32 px).
@export var move_speed := 40.0
## Flyers cross water, lava and void. Buildings stop them like anything else.
@export var flying := false

@export_group("Attack")
## Damage per hit, to buildings and workers alike.
@export var damage := 5.0
@export var attack_interval := 1.0
## Workers closer than this (pixels) get chased and attacked instead of the target.
@export var aggro_range := 56.0

@export_group("Waves")
## What one of these costs from a night's budget.
@export var spawn_cost := 1.0
## First night it can appear on.
@export var first_night := 1
## Chance that killing one teaches a blueprint the run does not know yet.
@export_range(0.0, 1.0) var blueprint_drop_chance := 0.03
