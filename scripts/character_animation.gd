extends RefCounted
## Continuous, distance-driven 2D motion. Combat remains server owned.
const Roles = preload("res://scripts/archetypes.gd")
const Layout = preload("res://scripts/city_layout.gd")
# Weight, stride length, run lean, breathing period and recoil vary by class.
const PROFILES := {
	"vanguard": {"stride": 92.0, "lift": 0.7, "lean": 0.035, "breath": 3.8, "recoil": 0.042},
	"cipher": {"stride": 102.0, "lift": 0.85, "lean": 0.05, "breath": 3.2, "recoil": 0.008},
	"ronin": {"stride": 116.0, "lift": 1.1, "lean": 0.08, "breath": 2.9, "recoil": 0.018},
	"ghost": {"stride": 112.0, "lift": 0.8, "lean": 0.045, "breath": 4.0, "recoil": 0.022},
	"machinist": {"stride": 98.0, "lift": 0.9, "lean": 0.055, "breath": 3.4, "recoil": 0.015}
}
var actors: Dictionary = {}

static func attack_duration(archetype: String) -> float:
	return minf(0.5, Roles.stats(archetype).cooldown * 0.9)

static func foot(phase: float, travel: Vector2, lift: float) -> Vector2:
	var cycle := fposmod(phase, 1.0)
	# 60% stance gives a short double-support interval. Stance moves backwards
	# linearly against body travel; only the recovery foot lifts from the floor.
	if cycle < 0.6:
		return travel * (0.3 - cycle)
	var swing := (cycle - 0.6) / 0.4
	var t2 := swing * swing
	var t3 := t2 * swing
	# Hermite tangents match stance velocity at toe-off and touchdown.
	var advance := (2*t3 - 3*t2 + 1) * -0.3 + (t3 - 2*t2 + swing) * -0.4 + (-2*t3 + 3*t2) * 0.3 + (t3 - t2) * -0.4
	return travel * advance - Vector2(0, pow(sin(swing * PI), 2) * lift)

func sample(player: Dictionary, delta: float) -> Dictionary:
	var dt := maxf(0, delta)
	var id := int(player.id)
	var role: String = Roles.valid(player.archetype)
	var profile: Dictionary = PROFILES[role]
	var serial := int(player.get("attack_serial", 0))
	var age := float(player.get("attack_age", 100.0))
	var position: Vector2 = player.position
	if not actors.has(id):
		actors[id] = {"clip": "idle", "phase": 0.0, "move": 0.0, "run": 0.0, "speed": 0.0, "clock": float(id % 17) * 0.27, "serial": serial, "attack_clock": age, "mirror": false, "turn": 1.0, "lean": 0.0, "last_position": position, "direction": Vector2(1, 0.5).normalized()}
	var actor: Dictionary = actors[id]
	var displacement: Vector2 = position - Vector2(actor.last_position)
	actor.last_position = position
	var teleported := displacement.length() > 120
	if teleported:
		displacement = Vector2.ZERO
		actor.move = 0.0
		actor.speed = 0.0
	actor.clock = float(actor.clock) + dt
	var actual_speed := displacement.length() / maxf(dt, 0.00001) if dt > 0 else 0.0
	actor.speed = lerpf(float(actor.speed), actual_speed, 1 - exp(-18 * dt))
	var moving: bool = player.get("moving", false) and float(actor.speed) > 0.5
	var run_goal := 1.0 if player.get("running", false) else 0.0
	actor.move = lerpf(float(actor.move), 1.0 if moving else 0.0, 1 - exp(-16 * dt))
	actor.run = lerpf(float(actor.run), run_goal, 1 - exp(-10 * dt))
	var cycle_distance := float(profile.stride) * lerpf(0.85, 1.0, float(actor.run))
	# Preserve phase through walk/run/idle changes. Never advance feet on a wall.
	actor.phase = fposmod(float(actor.phase) + displacement.length() / cycle_distance, 1.0)
	var facing: Vector2 = player.get("facing", Vector2(1, 0.5))
	if displacement.length_squared() > 0.00001:
		actor.direction = displacement.normalized()
	var mirror_goal: bool = actor.mirror
	if absf(facing.x) > 0.25:
		mirror_goal = facing.x < 0
	# Turn hysteresis prevents diagonal jitter; a brief eased body compression
	# softens mirrored view changes without cycling unrelated direction artwork.
	if mirror_goal != bool(actor.mirror):
		actor.turn = move_toward(float(actor.turn), 0.82, dt * 3.0)
		if float(actor.turn) <= 0.825:
			actor.mirror = mirror_goal
	else:
		actor.turn = move_toward(float(actor.turn), 1.0, dt * 2.0)
	actor.attack_clock = float(actor.attack_clock) + dt
	if serial != int(actor.serial):
		actor.serial = serial
		actor.attack_clock = age
	else:
		actor.attack_clock = maxf(float(actor.attack_clock), age)
	var attack_t := float(actor.attack_clock) / attack_duration(role)
	var attacking := serial > 0 and attack_t < 1.0
	actor.clip = "attack" if attacking else "run" if moving and run_goal > 0 else "walk" if moving else "idle"
	var recoil := smoothstep(0.0, 0.08, attack_t) * exp(-maxf(0, attack_t - 0.08) * 7) if attacking else 0.0
	var lean_goal := float(profile.lean) * float(actor.run) * float(actor.move)
	actor.lean = lerpf(float(actor.lean), lean_goal, 1 - exp(-12 * dt))
	var direction: Vector2 = actor.direction
	var lift := lerpf(0.048, 0.085, float(actor.run)) * float(profile.lift)
	var movement: float = actor.move
	var projected_position := Layout.project(position) / 164.4
	var world_travel := Layout.project(direction * cycle_distance) / 164.4
	var left := planted_foot(actor, "left", float(actor.phase), projected_position, world_travel, lift, moving, dt, teleported)
	var right := planted_foot(actor, "right", float(actor.phase) + 0.5, projected_position, world_travel, lift, moving, dt, teleported)
	if actor.mirror:
		left.x = -left.x
		right.x = -right.x
	return {"archetype": role, "clip": actor.clip, "mirror": actor.mirror, "turn": actor.turn, "phase": actor.phase, "move": movement, "run": actor.run, "lean": actor.lean, "breath": sin(float(actor.clock) * TAU / float(profile.breath)), "left_foot": left, "right_foot": right, "crouch": lerpf(0.012, 0.042, float(actor.run)) * movement, "sway": sin(float(actor.phase) * TAU) * 0.006 * movement, "arm_swing": sin(float(actor.phase) * TAU) * lerpf(0.035, 0.11, float(actor.run)) * movement, "sword_angle": sword_angle(attack_t) if attacking else 0.0, "bob": (cos(float(actor.phase) * TAU * 2) - 1) * 0.006 * movement, "recoil": recoil * float(profile.recoil), "attack_t": attack_t, "attacking": attacking}

static func sword_angle(t: float) -> float:
	if t < 0.15:
		return lerpf(0, 0.22, smoothstep(0, 0.15, t))
	if t < 0.48:
		return lerpf(0.22, -1.95, smoothstep(0.15, 0.48, t))
	return lerpf(-1.95, 0, smoothstep(0.48, 1, t))

func planted_foot(actor: Dictionary, side: String, phase: float, position: Vector2, travel: Vector2, lift: float, moving: bool, dt: float, reset: bool) -> Vector2:
	var key := side + "_contact"
	var cycle := fposmod(phase, 1.0)
	var stance := cycle < 0.6
	var ideal := foot(phase, travel, lift)
	if not actor.has(key) or reset:
		actor[key] = {"stance": stance, "lock": position, "offset": Vector2.ZERO, "ground_y": 0.0, "was_moving": false, "swing_start": 0.6}
	var contact: Dictionary = actor[key]
	if moving:
		if not bool(contact.was_moving) and not stance:
			contact.takeoff = contact.offset
			contact.swing_start = cycle
		if stance:
			if not bool(contact.stance):
				contact.lock = position + ideal
			contact.offset = Vector2(contact.lock) - position
			contact.ground_y = Vector2(contact.offset).y
		else:
			if bool(contact.stance):
				contact.takeoff = Vector2(contact.lock) - position
				contact.swing_start = 0.6
			var start_phase := float(contact.swing_start)
			var swing := clampf((cycle - start_phase) / maxf(0.01, 1 - start_phase), 0, 1)
			var t2 := swing * swing
			var t3 := t2 * swing
			var start: Vector2 = contact.get("takeoff", travel * -0.3)
			var recovery := start * (2*t3 - 3*t2 + 1) + travel * -0.4 * (t3 - 2*t2 + swing) + travel * 0.3 * (-2*t3 + 3*t2) + travel * -0.4 * (t3 - t2)
			contact.ground_y = recovery.y
			contact.offset = recovery - Vector2(0, pow(sin(swing * PI), 2) * lift)
	else:
		# Keep the planted horizontal position; let an airborne boot settle without
		# restarting the cycle or drawing both feet back to the original pose.
		var offset: Vector2 = contact.offset
		offset.y = lerpf(offset.y, float(contact.ground_y), 1 - exp(-24 * dt))
		contact.offset = offset
		contact.lock = position + offset
	contact.stance = stance
	contact.was_moving = moving
	return contact.offset

func retain(ids: Array) -> void:
	for id in actors.keys():
		if not ids.has(id):
			actors.erase(id)

func clear() -> void:
	actors.clear()
