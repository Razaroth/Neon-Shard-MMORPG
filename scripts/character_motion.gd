extends RefCounted
## Server-owned locomotion. Existing class speeds are the running speeds.
const Roles = preload("res://scripts/archetypes.gd")
const Layout = preload("res://scripts/city_layout.gd")
const WALK_RATIO := 0.65

static func step(player: Dictionary, delta: float, clock: float) -> void:
	var fresh := clock - float(player.last_input) < 0.3
	var direction: Vector2 = player.input if fresh else Vector2.ZERO
	if not fresh:
		player.attacking = false
		player.sprinting = false
	var previous: Vector2 = player.position
	var running: bool = player.get("sprinting", false) and fresh
	var speed: float = Roles.stats(player.archetype).speed * (1.0 if running else WALK_RATIO)
	var target_velocity := direction * speed
	var velocity: Vector2 = player.get("velocity", Vector2.ZERO)
	var acceleration: float = Roles.stats(player.archetype).speed * (7.0 if player.archetype == "vanguard" else 10.0)
	if running:
		acceleration *= 1.6
	var braking: float = Roles.stats(player.archetype).speed * 14.0
	velocity = velocity.move_toward(target_velocity, (braking if direction.is_zero_approx() else acceleration) * delta)
	if not fresh:
		velocity = Vector2.ZERO
	player.position = Layout.move_actor(previous, velocity * delta, player.zone)
	player.velocity = (player.position - previous) / maxf(delta, 0.00001)
	player.moving = player.velocity.length_squared() > 1.0
	player.running = running and player.moving
	# Facing uses the projected screen direction, and is retained when stopped.
	if player.moving:
		player.facing = Layout.project(player.velocity).normalized()
