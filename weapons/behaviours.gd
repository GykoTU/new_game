class_name Behaviours
extends RefCounted
## Every behaviour a shot can have, and make(id) to get its shared instance.
## Adding one: a class below, a line in make(), and (if the shop should sell
## it) an ITEM whose item_id is "behaviour.<weapon id>.<behaviour id>".
##
## Pierce is not here: every shot has pierce_left from its PIERCE_COUNT stat,
## and ProjectileSystem counts it down. What happens when it runs out (end,
## split, bounce on) is up to the behaviours below.

const S := Stats.Id

static var _made := {}


## The shared instance for `id`, or null if there is no such behaviour.
static func make(id: String) -> Behaviour:
	if _made.has(id):
		return _made[id]
	var b: Behaviour = null
	match id:
		"knockback": b = Knockback.new()
		"slow": b = Slow.new()
		"burn": b = Burn.new()
		"explode": b = Explode.new()
		"bounce": b = Bounce.new()
		"split": b = Split.new()
		"chain": b = Chain.new()
		"homing": b = Homing.new()
		"hook": b = Hook.new()
		"orbit": b = Orbit.new()
		"chain_ball": b = ChainBall.new()
		"long_chain": b = LongChain.new()
		"burning_ground": b = BurningGround.new()
		"explode_enemies": b = ExplodeEnemies.new()
	if b != null:
		b.id = id
		_made[id] = b
	return b


# --- Effects of being hit (passed on by chains) -----------------------------------

## Pushes what it hits along the shot's flight. An exploding shot pushes
## outward from the blast instead (EffectSystem), so this steps aside for it.
class Knockback extends Behaviour:
	func _init() -> void:
		priority = 40
		secondary = true

	func hooks() -> int:
		return ON_HIT

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		var ps := w.projectiles
		if w.sets[ps.type[p]].knockback_radial:
			return false
		var dir := ps.vel[p].normalized()
		if dir == Vector2.ZERO:
			dir = (w.enemies.pos[e] - ps.pos[p]).normalized()
		w.enemies.apply_impulse(e, dir * w.stat(ps.type[p], S.KNOCKBACK))
		return false


class Slow extends Behaviour:
	func _init() -> void:
		priority = 30
		secondary = true

	func hooks() -> int:
		return ON_HIT

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		var t := w.projectiles.type[p]
		w.enemies.apply_slow(e, w.stat(t, S.SLOW_STRENGTH), w.stat(t, S.SLOW_DURATION))
		if w.chill_marks.size() < 64:
			w.chill_marks.append([w.enemies.pos[e], w.tick])
		return false


class Burn extends Behaviour:
	func _init() -> void:
		priority = 30
		secondary = true

	func hooks() -> int:
		return ON_HIT

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		var t := w.projectiles.type[p]
		w.enemies.apply_burn(e, w.stat(t, S.BURN_DPS), w.stat(t, S.BURN_DURATION), t,
			w.projectiles.gen[p])
		return false


# --- What the shot does next --------------------------------------------------------

## A blast of AREA_RADIUS where it hits an enemy, a wall, or the ground at the
## end of its flight. Walls between the blast and a victim shield it.
class Explode extends Behaviour:
	func _init() -> void:
		priority = 10

	func hooks() -> int:
		return ON_HIT | ON_WALL | ON_EXPIRE

	func _blast(w: WeaponSystem, p: int) -> void:
		var ps := w.projectiles
		var t := ps.type[p]
		var kb := w.stat(t, S.KNOCKBACK) if w.sets[t].has("knockback") else 0.0
		w.effects.blast(ps.pos[p], w.stat(t, S.AREA_RADIUS), ps.dmg[p], t, ps.gen[p], kb, 0)

	func on_unit_hit(w: WeaponSystem, p: int, _e: int, _final: bool) -> bool:
		_blast(w, p)
		return false

	func on_wall_hit(w: WeaponSystem, p: int, _normal: Vector2) -> bool:
		_blast(w, p)
		return false

	func on_expire(w: WeaponSystem, p: int) -> bool:
		_blast(w, p)
		return false


## Off walls: reflect (both components at a corner). Off an enemy, once it has
## no pierce left: on toward the nearest other enemy, or off at an angle.
## Each costs one of BOUNCE_COUNT.
class Bounce extends Behaviour:
	const REACH := 160.0

	func _init() -> void:
		priority = 60

	func hooks() -> int:
		return ON_WALL | ON_HIT

	func on_wall_hit(w: WeaponSystem, p: int, normal: Vector2) -> bool:
		var ps := w.projectiles
		if ps.bounce_left[p] <= 0:
			return false
		ps.bounce_left[p] -= 1
		var v := ps.vel[p]
		if normal.x != 0.0: v.x = -v.x
		if normal.y != 0.0: v.y = -v.y
		ps.vel[p] = v
		return true

	func on_unit_hit(w: WeaponSystem, p: int, e: int, final: bool) -> bool:
		var ps := w.projectiles
		if not final or ps.bounce_left[p] <= 0:
			return false
		ps.bounce_left[p] -= 1
		var speed := ps.vel[p].length()
		var next := w.nearest_enemy(ps.pos[p], REACH, e, ps.last_hit[p])
		if next != EnemyStore.NONE:
			var to := w.enemies.pos[next] - ps.pos[p]
			ps.vel[p] = to.normalized() * speed
			# Lands on it: an exploding shell that misses still goes off there.
			ps.life[p] = maxi(int(to.length() / maxf(speed, 1.0) / GameClock.TICK_DELTA) + 2, 4)
		else:
			ps.vel[p] = ps.vel[p].rotated(deg_to_rad(w.rng.randf_range(100.0, 160.0)
				* (1.0 if w.rng.randf() < 0.5 else -1.0)))
			ps.life[p] = int(0.5 / GameClock.TICK_DELTA)
		ps.last_hit2[p] = ps.last_hit[p]
		ps.last_hit[p] = e
		return true


## At the first enemy it hits, the shot becomes SPLIT_COUNT shots fanning out
## 60 degrees wide, at a share of its damage, one generation later. They carry
## on with the pierce it had left. The weapon's max_generation decides whether
## they split again (arrows: 1, so they do not).
class Split extends Behaviour:
	const FAN := 60.0
	const CHILD_DAMAGE := 0.6

	func _init() -> void:
		priority = 70   # last: the hit's other effects happen first

	func hooks() -> int:
		return ON_HIT

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		var ps := w.projectiles
		if ps.gen[p] >= w.max_gen(ps.type[p]):
			return false
		var n := int(round(w.stat(ps.type[p], S.SPLIT_COUNT)))
		if n <= 0:
			return false
		for i in n:
			var off := 0.0 if n == 1 else lerpf(-FAN / 2.0, FAN / 2.0, float(i) / (n - 1))
			var c := w.spawn_child(p, ps.vel[p].rotated(deg_to_rad(off)), ps.dmg[p] * CHILD_DAMAGE)
			if c != ProjectileStore.NONE:
				ps.last_hit[c] = e
				ps.pierce_left[c] = ps.pierce_left[p]
		w.end_shot(p)   # replaced by its children
		return false


## Arcs on from what it hit to CHAIN_COUNT more enemies, each the nearest not
## yet struck within reach of the last. Instant, no extra shots: the arcs pass
## on damage and the secondary effects (a frost chain slows every link).
class Chain extends Behaviour:
	const REACH := 112.0

	func _init() -> void:
		priority = 20

	func hooks() -> int:
		return ON_HIT

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		var ps := w.projectiles
		var n := int(round(w.stat(ps.type[p], S.CHAIN_COUNT)))
		var struck := PackedInt32Array([e])
		var from := w.enemies.pos[e]
		for i in n:
			var next := w.nearest_enemy_not_in(from, REACH, struck)
			if next == EnemyStore.NONE:
				break
			var to := w.enemies.pos[next]
			if w.arcs.size() < 128:   # visuals only; drained by the renderer
				w.arcs.append([from, to, w.tick])
			struck.append(next)
			w.secondary_hit(p, next)
			from = to
		return false


## Curves toward the nearest enemy ahead, turning at most TURN radians a second.
class Homing extends Behaviour:
	const REACH := 160.0
	const TURN := 6.0

	func hooks() -> int:
		return ON_STEP

	func on_step(w: WeaponSystem, p: int, dt: float) -> void:
		var ps := w.projectiles
		if ps.state[p] != ProjectileStore.State.FLY:
			return
		if (w.tick + p) % 4 == 0 or not w.enemies.is_alive(ps.seek[p]):
			ps.seek[p] = w.nearest_enemy(ps.pos[p], REACH, ps.last_hit[p], ps.last_hit2[p])
		var s := ps.seek[p]
		if not w.enemies.is_alive(s):
			return
		var v := ps.vel[p]
		var turn := v.angle_to(w.enemies.pos[s] - ps.pos[p])
		ps.vel[p] = v.rotated(clampf(turn, -TURN * dt, TURN * dt))


## Flies out, grabs the first enemy it touches and drags it back toward the
## tower at PULL_STRENGTH px/s, through the enemy impulse channel, so walls
## still stop it (and a wall hit lets go: WeaponSystem._on_wall_impact).
## Misses reel back in after RANGE or their lifetime.
class Hook extends Behaviour:
	const HOLD_SECONDS := 1.5
	const LET_GO := 30.0

	func _init() -> void:
		priority = 5

	func hooks() -> int:
		return ON_HIT | ON_STEP | ON_WALL | ON_EXPIRE

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		var ps := w.projectiles
		if ps.state[p] == ProjectileStore.State.FLY:
			ps.state[p] = ProjectileStore.State.HOOKED
			ps.hooked[p] = e
			ps.life[p] = int(HOLD_SECONDS / GameClock.TICK_DELTA)
			w.hooked_by[e] = p
		return true

	func on_step(w: WeaponSystem, p: int, dt: float) -> void:
		var ps := w.projectiles
		var t := ps.type[p]
		match ps.state[p]:
			ProjectileStore.State.FLY:
				if ps.pos[p].distance_to(ps.anchor[p]) > w.stat(t, S.RANGE) * 1.15:
					ps.state[p] = ProjectileStore.State.RETURN
			ProjectileStore.State.HOOKED:
				var e := ps.hooked[p]
				if not w.enemies.is_alive(e):
					w.unhook(p)
					return
				var ep := w.enemies.pos[e]
				var home := ps.anchor[p] - ep
				if home.length() < LET_GO:
					w.unhook(p)
					return
				w.enemies.impulse[e] = home.normalized() * w.stat(t, S.PULL_STRENGTH)
				ps.vel[p] = (ep - ps.pos[p]) / dt
			ProjectileStore.State.RETURN:
				var to := ps.anchor[p] - ps.pos[p]
				var speed := w.stat(t, S.PROJECTILE_SPEED) * 1.4
				if to.length() <= speed * dt + 2.0:
					ps.vel[p] = Vector2.ZERO
					ps.life[p] = 0   # home: ends this tick, on_expire lets it go
					return
				ps.vel[p] = to.normalized() * speed

	func on_wall_hit(w: WeaponSystem, p: int, _normal: Vector2) -> bool:
		w.projectiles.state[p] = ProjectileStore.State.RETURN
		return true

	func on_expire(w: WeaponSystem, p: int) -> bool:
		var ps := w.projectiles
		match ps.state[p]:
			ProjectileStore.State.HOOKED:
				w.unhook(p)
			ProjectileStore.State.FLY:
				ps.state[p] = ProjectileStore.State.RETURN
			_:
				return false   # reeled in
		ps.life[p] = int(3.0 / GameClock.TICK_DELTA)
		return true


## Blades circling the tower at ORBIT_RADIUS, PROJECTILE_COUNT of them evenly
## spaced, at PROJECTILE_SPEED along the circle. Persistent (WeaponData).
class Orbit extends Behaviour:
	func hooks() -> int:
		return ON_STEP

	func on_step(w: WeaponSystem, p: int, dt: float) -> void:
		var ps := w.projectiles
		var t := ps.type[p]
		var r := maxf(w.stat(t, S.ORBIT_RADIUS), 8.0)
		var n := maxi(int(round(w.stat(t, S.PROJECTILE_COUNT))), 1)
		var a := w.tick * dt * w.stat(t, S.PROJECTILE_SPEED) / r + ps.slot[p] * TAU / n
		ps.vel[p] = (ps.anchor[p] + Vector2.from_angle(a) * r - ps.pos[p]) / dt
		ps.angle[p] = w.tick * 0.35   # the blade spins as it goes


## The chain cannon's pair of chained balls (Stage 5 rework). Aimed like the
## cannon, but it flies a fixed distance, RANGE, whatever it was aimed at, so
## it sweeps through and past its target. It does no damage. Every enemy it
## touches, up to PIERCE_COUNT, is caught: stunned and dragged along bunched
## round the balls, through the impulse channel, so a wall still stops it
## (and lets it go: WeaponSystem._on_wall_impact). When the shot ends -- its
## distance flown, or a wall -- the caught are dropped there, stunned for
## STUN_DURATION (WeaponSystem.end_shot).
class ChainBall extends Behaviour:
	## Fastest a caught enemy is pulled toward its place by the balls, px/s.
	const MAX_PULL := 700.0

	func _init() -> void:
		priority = 20

	func hooks() -> int:
		return ON_SPAWN | ON_HIT | ON_STEP

	## Flies RANGE pixels at PROJECTILE_SPEED: life from distance, not time.
	func on_spawn(w: WeaponSystem, p: int) -> void:
		var t := w.projectiles.type[p]
		var speed := maxf(w.stat(t, S.PROJECTILE_SPEED), 1.0)
		w.projectiles.life[p] = maxi(int(round(w.stat(t, S.RANGE) / speed / GameClock.TICK_DELTA)), 1)

	func on_unit_hit(w: WeaponSystem, p: int, e: int, _final: bool) -> bool:
		if w.held_by.has(e):
			return true   # already caught, by this shot or another
		var caught: PackedInt32Array = w.caught.get(p, PackedInt32Array())
		if caught.size() < int(round(w.stat(w.projectiles.type[p], S.PIERCE_COUNT))):
			caught.append(e)
			w.caught[p] = caught
			w.held_by[e] = p
			w.enemies.apply_stun(e, 0.1)
		return true   # never stops at an enemy

	func on_step(w: WeaponSystem, p: int, dt: float) -> void:
		var caught: PackedInt32Array = w.caught.get(p, PackedInt32Array())
		if caught.is_empty():
			return
		var ps := w.projectiles
		var en := w.enemies
		var alive := PackedInt32Array()
		for e in caught:
			if en.is_alive(e) and w.held_by.get(e, -1) == p:
				alive.append(e)
		w.caught[p] = alive
		var n := alive.size()
		# Bunched round the balls, spread a little wider on a longer chain.
		var ring := minf(6.0 + 2.0 * n, ps.radius[p] * 0.7)
		var spin := (w.tick - ps.born[p]) * dt * 3.0
		for k in n:
			var e := alive[k]
			var spot := ps.pos[p] + ps.vel[p] * dt + Vector2.from_angle(spin + k * TAU / n) * ring
			en.impulse[e] = ((spot - en.pos[e]) / dt).limit_length(MAX_PULL)
			en.apply_stun(e, 0.1)


## Paying-out chain: the balls fly apart as the shot travels, so its catch
## radius grows by GROW px a second, up to MAX_EXTRA. Drawn by WeaponEffects
## as the two halves of the sprite pulled apart (WeaponData.draw_split).
class LongChain extends Behaviour:
	const GROW := 40.0
	const MAX_EXTRA := 40.0

	func _init() -> void:
		priority = 10   # before the balls drag, so the ring uses the new radius

	func hooks() -> int:
		return ON_STEP

	func on_step(w: WeaponSystem, p: int, dt: float) -> void:
		var ps := w.projectiles
		var base := w.types[ps.type[p]].projectile_radius
		ps.radius[p] = base + minf((w.tick - ps.born[p]) * dt * GROW, MAX_EXTRA)


## Some flames leave the ground burning where they die out: a patch of
## AREA_RADIUS that sets enemies alight and hurts workers for BURN_DURATION.
class BurningGround extends Behaviour:
	const CHANCE := 0.25

	func _init() -> void:
		priority = 80

	func hooks() -> int:
		return ON_EXPIRE

	func on_expire(w: WeaponSystem, p: int) -> bool:
		if w.rng.randf() < CHANCE:
			var ps := w.projectiles
			var t := ps.type[p]
			w.effects.ground(ps.pos[p], w.stat(t, S.AREA_RADIUS), w.stat(t, S.BURN_DPS),
				w.stat(t, S.BURN_DURATION), t, ps.gen[p])
		return false


## An enemy this weapon kills explodes a moment later: DAMAGE plus a share of
## the dead enemy's health, at least MIN_RADIUS wide. A blast that kills sets
## off the next, one generation later, up to the weapon's max_generation --
## the chain-depth cap that keeps a packed crowd from detonating forever.
class ExplodeEnemies extends Behaviour:
	const MIN_RADIUS := 40.0
	const HP_SHARE := 0.3
	const DELAY_TICKS := 8

	func hooks() -> int:
		return ON_KILL

	func on_kill(w: WeaponSystem, t: int, gen: int, at: Vector2, max_hp: float) -> void:
		if gen >= w.max_gen(t):
			return
		w.effects.blast(at, maxf(w.stat(t, S.AREA_RADIUS), MIN_RADIUS),
			w.stat(t, S.DAMAGE) + max_hp * HP_SHARE, t, gen + 1, 0.0, DELAY_TICKS)
