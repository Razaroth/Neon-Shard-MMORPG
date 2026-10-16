extends SceneTree
## Staged Godot playback preview, not a live multiplayer recording.
const Roles = preload("res://scripts/archetypes.gd")
const Layout = preload("res://scripts/city_layout.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var output := "/tmp/neon-animation-captures"
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
		var actor := {"id": 42 + index, "position": Layout.unproject(points[index] - Layout.ART_ORIGIN)}
		world.combat.prepare(actor, {"archetype": Roles.ORDER[index]})
		assert(not Layout.blocked(actor.position))
		world.state.append(actor)
	var clips := ["idle", "walk", "run", "attack", "run"]
	var observed: Dictionary = {}
	for tick in 120:
		var stage := tick / 24
		var clip: String = clips[stage]
		world.elapsed = tick / 12.0
		world.hud.text = "ANIMATION PREVIEW\n" + clip.to_upper() + (" / LEFT" if stage == 4 else " / RIGHT") + "\n\nFive classes / 6-frame clips\nStaged Godot playback"
		for index in world.state.size():
			var actor: Dictionary = world.state[index]
			actor.moving = clip in ["walk", "run"]
			actor.running = clip == "run"
			actor.facing = Vector2.LEFT if stage == 4 else Vector2.RIGHT
			var period: float = Roles.stats(actor.archetype).cooldown
			actor.attack_serial = int((tick - 72) / 12.0 / period) + 1 if clip == "attack" else 0
			actor.attack_age = fposmod((tick - 72) / 12.0, period) if clip == "attack" else 100.0
		world.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		assert(image.save_png(output.path_join("frame-%03d.png" % tick)) == OK)
		for actor in world.visuals.animation.actors.values():
			observed[str(actor.clip)] = true
	for clip in ["idle", "walk", "run", "attack"]:
		assert(observed.has(clip), "Preview must render every animation state")
	print("ANIMATION_CAPTURE_OK ", output)
	quit()
