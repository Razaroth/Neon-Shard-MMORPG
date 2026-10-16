extends SceneTree
const Sprites = preload("res://scripts/rpg_animation.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Combat = preload("res://scripts/combat.gd")
const Motion = preload("res://scripts/character_motion.gd")

func _init() -> void:
	var layouts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rpg/manifest.json"))["classes"]
	for role in Roles.ORDER:
		for clip in Sprites.COUNTS:
			var texture: Texture2D = load("res://assets/rpg/" + role + "/" + clip + ".png")
			assert(texture != null)
			assert(FileAccess.get_sha256("res://assets/rpg/" + role + "/" + clip + ".png") == layouts[role][clip].sha256)
			for anchor in layouts[role][clip].registration:
				assert(anchor.height > 0 and anchor.scale_height > 0)
			var sheet := texture.get_image()
			var cell := Vector2(sheet.get_size()) / Vector2(Sprites.COUNTS[clip], 4)
			assert(absf(cell.x / cell.y - 1.0) < 0.06, "Sprite sheets must preserve their square-cell grid")
			for view in range(1, 4):
				var y := int(layouts[role][clip].row_regions[view][0])
				var opaque := 0
				for x in sheet.get_width():
					if sheet.get_pixel(x, y).a >= 230.0 / 255.0:
						opaque += 1
				assert(opaque <= 2, "Row boundaries must cross empty space, never a neighboring boot or head")
			for view in 4:
				var frames: Array = []
				for frame in Sprites.COUNTS[clip]:
					var pose := {"sheet": clip, "frame": frame, "view": view}
					var region := Sprites.region(texture.get_size(), pose, layouts[role][clip])
					assert(Rect2(Vector2.ZERO, texture.get_size()).encloses(region))
					for polygon in layouts[role][clip].frames[view][frame].polygons:
						var vertices := PackedVector2Array()
						for point in polygon:
							var vertex := Vector2(point[0], point[1])
							assert(Rect2(Vector2.ZERO, texture.get_size()).has_point(vertex))
							vertices.append(vertex)
						assert(Geometry2D.triangulate_polygon(vertices).size() == (vertices.size() - 2) * 3)

					var image := sheet.get_region(Rect2i(region))
					assert(image.get_used_rect().get_area() > 0, "No animation frame may be empty")
					frames.append(image.get_data())
				assert(frames[1] != frames[3] and frames[1] != frames[5], "Moving poses must contain different artwork")
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
	print("RPG_ANIMATION_RULES_OK five converted classes, isolated atlas rows, distinct contact/passing poses, four facings, view hysteresis, server attack timing, frame bounds and distance-driven playback")
	quit()
