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
	var cycle_distance := float(profile.stride) * lerpf(0.7, 1.0, float(actor.run))
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
	var recoil := exp(-attack_t * 8.0) * (1 - smoothstep(0.55, 1.0, attack_t)) if attacking else 0.0
	var lean_goal := float(profile.lean) * float(actor.run) * float(actor.move)
	actor.lean = lerpf(float(actor.lean), lean_goal, 1 - exp(-12 * dt))
	var direction: Vector2 = actor.direction
	var travel := Layout.project(direction * cycle_distance) / 164.4
	if actor.mirror:
		travel.x = -travel.x
	var lift := lerpf(0.048, 0.085, float(actor.run)) * float(profile.lift)
	var movement: float = actor.move
	return {"archetype": role, "clip": actor.clip, "mirror": actor.mirror, "turn": actor.turn, "phase": actor.phase, "move": movement, "run": actor.run, "lean": actor.lean, "breath": sin(float(actor.clock) * TAU / float(profile.breath)), "left_foot": foot(float(actor.phase), travel, lift) * movement, "right_foot": foot(float(actor.phase) + 0.5, travel, lift) * movement, "bob": (cos(float(actor.phase) * TAU * 2) - 1) * 0.006 * movement, "recoil": recoil * float(profile.recoil), "attack_t": attack_t, "attacking": attacking}

func retain(ids: Array) -> void:
	for id in actors.keys():
		if not ids.has(id):
			actors.erase(id)

func clear() -> void:
	actors.clear()
