extends SceneTree
const SpriteAnimation = preload("res://scripts/character_animation.gd")
const Motion = preload("res://scripts/character_motion.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Combat = preload("res://scripts/combat.gd")
const Layout = preload("res://scripts/city_layout.gd")

func _init() -> void:
	for role in Roles.ORDER:
		var player := {"id": 2, "position": Vector2.ZERO, "input": Vector2.RIGHT, "last_input": 0.0}
		Combat.new().prepare(player, {"archetype": role})
		Motion.step(player, 0.1, 0.1)
		var walk_distance: float = player.position.length()
		assert(player.moving and not player.running)
		assert(is_equal_approx(walk_distance, Roles.stats(role).speed * Motion.WALK_RATIO * 0.1))
		player.position = Vector2.ZERO
		player.sprinting = true
		Motion.step(player, 0.1, 0.1)
		assert(player.running and player.position.length() > walk_distance)
		assert(is_equal_approx(player.position.length(), Roles.stats(role).speed * 0.1))
		var animation = SpriteAnimation.new()
		var pose: Dictionary = animation.sample(player, 0.0)
		assert(pose.clip == "run")
		assert(animation.sample(player, 0.1).frame != pose.frame)
		player.running = false
		assert(animation.sample(player, 0.01).clip == "walk")
		player.facing = Vector2.LEFT
		assert(animation.sample(player, 0.01).mirror)
		player.input = Vector2.ZERO
		Motion.step(player, 0.1, 0.2)
		assert(not player.moving and animation.sample(player, 0.01).clip == "idle")
		assert(animation.sample(player, 0.01).mirror, "Facing persists when stopped")
		player.attack_serial = 1
		player.attack_age = 0.0
		assert(animation.sample(player, 0.01).clip == "attack")
		assert(animation.sample(player, SpriteAnimation.attack_duration(role) * 0.5).frame == 3)
		assert(animation.sample(player, SpriteAnimation.attack_duration(role)).clip == "idle", "Attack ends without retriggering from stale intent")
		player.attack_serial += 1
		player.attack_age = 0.0
		assert(animation.sample(player, 0.01).clip == "attack")
		player.attack_age = 100.0
		assert(animation.sample(player, 0.01).clip == "idle", "A server-side cancellation ends an active attack")
		player.attacking = true
		player.attack_age = 100.0
		assert(animation.sample(player, 0.1).clip == "idle", "Held attack intent alone cannot fabricate an attack")
		player.input = Vector2.RIGHT
		player.sprinting = true
		Motion.step(player, 0.1, 2.0)
		assert(not player.running and not player.moving and not player.attacking, "Stale inputs stop locomotion and attacks")
		animation.retain([])
		assert(animation.actors.is_empty())
		var region := SpriteAnimation.region(Vector2(1536, 1024), {"frame": 5, "row": 3})
		assert(region == Rect2(1312, 768, 192, 256))
	# A wall push is not actual movement; clients must not display a walking loop.
	var wall_actor := {"id": 3, "position": Vector2.ZERO, "input": Vector2.RIGHT, "last_input": 0.0}
	Combat.new().prepare(wall_actor, {"archetype": "ronin"})
	for i in 500:
		wall_actor.last_input = i * 0.1
		Motion.step(wall_actor, 0.1, i * 0.1)
	assert(not wall_actor.moving, "Animation must stop when blocked against the room boundary")
	print("ANIMATION_RULES_OK five classes, walk/run speed, clip transitions, facing, attack timing, stale input, wall blocking")
	quit()
