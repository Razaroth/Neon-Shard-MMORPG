extends SceneTree
const Sprites = preload("res://scripts/classic_animation.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Combat = preload("res://scripts/combat.gd")
const Motion = preload("res://scripts/character_motion.gd")

func _init() -> void:
	for role in Roles.ORDER:
		for layer in Sprites.layers(role):
			for clip in Sprites.COUNTS:
				var texture: Texture2D = load("res://assets/lpc/" + layer.prefix + "/" + clip + ".png")
				assert(texture.get_size() == Vector2(Sprites.COUNTS[clip] * 64, 256))
		var texture: Texture2D = load("res://assets/lpc/body/bodies/" + Sprites.SKINS[role].body + "/walk.png")
		var sheet := texture.get_image()
		for view in 4:
			var contact := sheet.get_region(Rect2i(64, view * 64, 64, 64)).get_data()
			var passing := sheet.get_region(Rect2i(3 * 64, view * 64, 64, 64)).get_data()
			var opposite := sheet.get_region(Rect2i(5 * 64, view * 64, 64, 64)).get_data()
			assert(contact != passing and contact != opposite)
		var actor := {"id": 2, "position": Vector2.ZERO, "input": Vector2.ZERO, "last_input": 0.0}
		Combat.new().prepare(actor, {"archetype": role})
		var animation = Sprites.new()
		var pose: Dictionary = animation.sample(actor, 0.0)
		assert(pose.clip == "idle")
		actor.moving = true
		actor.position += Vector2(12, 0)
		pose = animation.sample(actor, 0.1)
		assert(pose.clip == "walk" and pose.frame > 0)
		var phase: float = animation.actors[2].phase
		actor.running = true
		pose = animation.sample(actor, 0.01)
		assert(pose.clip == "run" and is_equal_approx(animation.actors[2].phase, phase))
		actor.facing = Vector2.LEFT
		pose = animation.sample(actor, 0.01)
		assert(pose.view == 1 and not pose.mirror)
		actor.facing = Vector2(-1, -1)
		assert(animation.sample(actor, 0.01).view == 1, "Small diagonal changes must not flicker the view")
		actor.facing = Vector2.UP
		assert(animation.sample(actor, 0.01).view == 0)
		actor.facing = Vector2.DOWN
		assert(animation.sample(actor, 0.01).view == 2)
		actor.moving = false
		actor.attacking = true
		pose = animation.sample(actor, 0.1)
		assert(pose.clip == "idle", "Attack intent cannot fabricate a server-confirmed strike")
		actor.attack_serial = 1
		actor.attack_age = 0.0
		pose = animation.sample(actor, 0.0)
		assert(pose.clip == "attack" and pose.frame == 0)
		pose = animation.sample(actor, float(Roles.stats(role).cooldown) * 0.45)
		assert(pose.clip == "attack" and pose.frame > 0)
		assert(animation.sample(actor, 1.0).clip == "idle")
		assert(Rect2(Vector2.ZERO, Vector2(Sprites.COUNTS[pose.sheet] * 64, 256)).encloses(pose.region))
		animation.retain([])
		assert(animation.actors.is_empty())
	# Sprint starts more decisively, but retains the class speed cap and collision.
	for role in Roles.ORDER:
		var speeds: Array = []
		for sprint in [false, true]:
			var actor := {"id": 8, "position": Vector2.ZERO, "input": Vector2.RIGHT, "last_input": 0.0}
			Combat.new().prepare(actor, {"archetype": role})
			actor.sprinting = sprint
			Motion.step(actor, 1.0 / 60, 0.0)
			speeds.append(actor.velocity.length())
			assert(actor.velocity.length() <= float(Roles.stats(role).speed))
			Motion.step(actor, 1.0 / 60, 1.0)
			assert(not actor.moving and not actor.running, "Stale input must stop a dash")
		assert(speeds[1] > speeds[0] * 1.5)
	# The same traveled distance selects the same stride at different display rates.
	var phases: Array = []
	for rate in [30, 120]:
		var actor := {"id": 3, "position": Vector2.ZERO, "archetype": "ronin", "moving": true}
		var animation = Sprites.new()
		animation.sample(actor, 0)
		for tick in rate:
			actor.position += Vector2.RIGHT * 60.0 / rate
			animation.sample(actor, 1.0 / rate)
		phases.append(animation.actors[3].phase)
	assert(absf(phases[0] - phases[1]) < 0.0001)
	print("CLASSIC_ANIMATION_RULES_OK layered LPC sheets, distinct contact/passing poses, four facings, view hysteresis, server attack timing, frame bounds and distance-driven playback")
	quit()
