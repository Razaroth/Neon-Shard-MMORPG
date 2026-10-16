extends SceneTree
## Staged Godot motion capture. The same authoritative movement code drives actors.
const Roles = preload("res://scripts/archetypes.gd")
const Layout = preload("res://scripts/city_layout.gd")
const Motion = preload("res://scripts/character_motion.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var output := "/tmp/neon-fluid-captures"
	var args := OS.get_cmdline_user_args()
	if args.has("--capture-dir"):
		output = args[args.find("--capture-dir") + 1]
	DirAccess.make_dir_recursive_absolute(output)
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.visuals.transitions_enabled = false
	world.local_id = 42
	world.interface.enter_world()
	world.enemy_state = []
	world.state = []
	var points := [Vector2(600, 550), Vector2(760, 600), Vector2(930, 560), Vector2(600, 735), Vector2(930, 740)]
	for index in Roles.ORDER.size():
		var actor := {"id": 42 + index, "position": Layout.unproject(points[index] - Layout.ART_ORIGIN), "input": Vector2.ZERO, "last_input": 0.0}
		world.combat.prepare(actor, {"archetype": Roles.ORDER[index]})
		assert(not Layout.blocked(actor.position))
		world.state.append(actor)
	var observed: Dictionary = {}
	for tick in 240:
		var clip := "idle"
		if tick >= 30 and tick < 75: clip = "walk"
		if tick >= 75 and tick < 120: clip = "run"
		if tick >= 143 and tick < 188: clip = "attack"
		if tick >= 188 and tick < 225: clip = "walk"
		world.elapsed = tick / 30.0
		world.hud.text = "MOTION REFINEMENT\n" + clip.to_upper() + "\n\nContinuous 2D mesh motion\nStaged Godot playback"
		for actor in world.state:
			actor.input = Vector2(-1, 1).normalized() if tick < 188 else Vector2(1, -1).normalized()
			if clip not in ["walk", "run"]:
				actor.input = Vector2.ZERO
			actor.last_input = world.elapsed
			actor.sprinting = clip == "run"
			Motion.step(actor, 1.0 / 30, world.elapsed)
			var period: float = Roles.stats(actor.archetype).cooldown
			actor.attack_serial = int((tick - 143) / 30.0 / period) + 1 if clip == "attack" else 0
			actor.attack_age = fposmod((tick - 143) / 30.0, period) if clip == "attack" else 100.0
		world.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % tick)) == OK)
		for actor in world.visuals.animation.actors.values():
			observed[str(actor.clip)] = true
	for clip in ["idle", "walk", "run", "attack"]:
		assert(observed.has(clip), "Preview must render every animation state")
	print("MESH_BUILD_US_PER_ACTOR ", float(world.visuals.rig.build_usec) / maxf(1, world.visuals.rig.build_count))
	print("ANIMATION_CAPTURE_OK ", output)
	quit()
