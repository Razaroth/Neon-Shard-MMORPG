extends SceneTree
const MotionAnimation = preload("res://scripts/character_animation.gd")
const Rig = preload("res://scripts/character_rig.gd")
const Motion = preload("res://scripts/character_motion.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Combat = preload("res://scripts/combat.gd")
const Layout = preload("res://scripts/city_layout.gd")

func actor(role: String) -> Dictionary:
	var player := {"id": 2, "position": Vector2.ZERO, "input": Vector2.RIGHT, "last_input": 0.0}
	Combat.new().prepare(player, {"archetype": role})
	return player

func _init() -> void:
	for role in Roles.ORDER:
		var player := actor(role)
		var animation = MotionAnimation.new()
		animation.sample(player, 0.0)
		Motion.step(player, 1.0 / 60, 0.0)
		var first_speed: float = player.velocity.length()
		assert(first_speed > 0 and first_speed < Roles.stats(role).speed * Motion.WALK_RATIO, "Start must accelerate rather than jump to full speed")
		for tick in 60:
			player.last_input = tick / 60.0
			Motion.step(player, 1.0 / 60, tick / 60.0)
			animation.sample(player, 1.0 / 60)
		assert(is_equal_approx(player.velocity.length(), Roles.stats(role).speed * Motion.WALK_RATIO))
		var phase: float = animation.actors[2].phase
		player.sprinting = true
		Motion.step(player, 1.0 / 60, player.last_input)
		var pose: Dictionary = animation.sample(player, 1.0 / 60)
		assert(pose.clip == "run" and pose.run > 0 and pose.run < 1)
		assert(fposmod(float(pose.phase) - phase, 1.0) < 0.1, "Walk/run transitions preserve gait phase")
		player.facing = Vector2.LEFT
		assert(not animation.sample(player, 1.0 / 60).mirror, "Turns must ease rather than snap")
		for tick in 12: pose = animation.sample(player, 1.0 / 60)
		assert(pose.mirror)
		var stopped: Vector2 = player.position
		var phase_stopped: float = pose.phase
		player.moving = false
		for tick in 30:
			pose = animation.sample(player, 1.0 / 60)
		assert(pose.clip == "idle" and pose.move < 0.01)
		assert(is_equal_approx(pose.phase, phase_stopped), "Feet must not cycle while stopped or blocked")
		assert(player.position == stopped)
		player.attack_serial = 1
		player.attack_age = 0.0
		pose = animation.sample(player, 0.0)
		assert(pose.clip == "attack" and is_zero_approx(pose.recoil), "Recoil must build smoothly from rest")
		pose = animation.sample(player, MotionAnimation.attack_duration(role) * 0.08)
		assert(pose.recoil > 0)
		pose = animation.sample(player, MotionAnimation.attack_duration(role) * 0.5)
		assert(animation.sample(player, MotionAnimation.attack_duration(role)).clip == "idle")
		player.attack_serial += 1
		player.attack_age = 0.0
		animation.sample(player, 0.0)
		player.attack_age = 100.0
		assert(animation.sample(player, 0.01).clip == "idle", "Server cancellation stops an attack")
		player.input = Vector2.RIGHT
		player.sprinting = true
		player.attacking = true
		Motion.step(player, 0.1, 10.0)
		assert(not player.moving and not player.running and not player.attacking, "Stale input stops immediately")
		animation.retain([])
		assert(animation.actors.is_empty())
	# Stance feet counter body travel at a constant rate; swing lifts continuously.
	var travel := Vector2(0.4, 0.1)
	var planted_a := MotionAnimation.foot(0.1, travel, 0.08)
	var planted_b := MotionAnimation.foot(0.2, travel, 0.08)
	assert((planted_b - planted_a).is_equal_approx(-travel * 0.1))
	assert(MotionAnimation.foot(0.8, travel, 0.08).y < 0)
	assert(MotionAnimation.foot(0.99999, travel, 0.08).distance_to(MotionAnimation.foot(0.0, travel, 0.08)) < 0.0001, "Loop boundary must be continuous")
	# The same traveled distance gives the same phase at 30 and 120 Hz.
	var phases: Array = []
	for rate in [30, 120]:
		var animation = MotionAnimation.new()
		var player := actor("ronin")
		animation.sample(player, 0.0)
		player.moving = true
		for tick in rate:
			player.position += Vector2.RIGHT * 60.0 / rate
			animation.sample(player, 1.0 / rate)
		phases.append(animation.actors[2].phase)
	assert(absf(phases[0] - phases[1]) < 0.0001, "Gait must be distance-driven rather than display-frame driven")
	var wall_actor := actor("ronin")
	for tick in 500:
		wall_actor.last_input = tick * 0.1
		Motion.step(wall_actor, 0.1, tick * 0.1)
	assert(not wall_actor.moving, "Wall pushes cannot animate a walk")
	# Mesh vertices stay finite and change continuously between adjacent samples.
	var animation = MotionAnimation.new()
	var player := actor("ronin")
	var pose: Dictionary = animation.sample(player, 0.0)
	var rig = Rig.new()
	for point in rig.rest:
		assert(rig.vertex(point, pose).is_finite())
	# Solving a reachable or unreachable target must never lengthen either bone.
	for role in Roles.ORDER:
		for bind in Rig.JOINTS[role]:
			for offset in [Vector2.ZERO, Vector2(0.07, -0.04), Vector2(1, 1), Vector2(-1, -1)]:
				var solution := Rig.solve_leg(bind[0], bind[1], bind[2], bind[2] + offset, Vector2(0.004, 0.03))
				assert(is_equal_approx(solution.new_hip.distance_to(solution.new_knee), bind[0].distance_to(bind[1])), "Thigh length must stay rigid")
				assert(is_equal_approx(solution.new_knee.distance_to(solution.new_ankle), bind[1].distance_to(bind[2])), "Shin length must stay rigid")
				assert(solution.new_knee.is_finite() and solution.new_ankle.is_finite())
	# A planted boot retains its screen-space world position during acceleration.
	var planted = MotionAnimation.new()
	var walker := actor("cipher")
	planted.sample(walker, 0.0)
	walker.moving = true
	var origin := Vector2.ZERO
	for tick in 12:
		walker.position += Vector2.RIGHT * (tick + 1) * 0.04
		var contact_pose: Dictionary = planted.sample(walker, 1.0 / 60)
		var world_foot := Layout.project(walker.position) / 164.4 + Vector2(contact_pose.left_foot)
		if tick == 0: origin = world_foot
		assert(world_foot.distance_to(origin) < 0.00001, "A stance foot must stay planted as speed changes")
	walker.moving = false
	var before_stop: Dictionary = planted.sample(walker, 1.0 / 60)
	for tick in 30: planted.sample(walker, 1.0 / 60)
	var after_stop: Dictionary = planted.sample(walker, 1.0 / 60)
	assert(is_equal_approx(before_stop.left_foot.x, after_stop.left_foot.x), "Stopping must not pull planted boots horizontally toward the bind pose")
	# Resuming an interrupted swing starts from the settled boot, not a mid-air pose.
	var resume = MotionAnimation.new()
	var runner := actor("ronin")
	resume.sample(runner, 0.0)
	runner.moving = true
	for tick in 75:
		runner.position += Vector2.RIGHT
		resume.sample(runner, 1.0 / 60)
	runner.moving = false
	for tick in 60: resume.sample(runner, 1.0 / 60)
	var settled: Dictionary = resume.sample(runner, 1.0 / 60)
	runner.moving = true
	runner.position += Vector2.RIGHT * 0.05
	var restarted: Dictionary = resume.sample(runner, 1.0 / 60)
	assert(Vector2(restarted.left_foot).distance_to(settled.left_foot) < 0.01, "Restarting an interrupted swing must not pop a boot into the air")
	assert(is_zero_approx(MotionAnimation.sword_angle(0)) and is_zero_approx(MotionAnimation.sword_angle(1)))
	assert(MotionAnimation.sword_angle(0.15) > 0 and MotionAnimation.sword_angle(0.48) < -1.8, "Sword motion needs anticipation, strike and recovery")
	print("ANIMATION_RULES_OK acceleration, phase continuity, class motion, foot contact, loop seam, display-rate independence, joint lengths, planted feet, sword recovery and wall blocking")
	quit()
