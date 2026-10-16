extends SceneTree
## Render fixtures only: does not claim a live multiplayer session.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.visuals.transitions_enabled = false
	world.elapsed = 2.0
	world.local_id = 42
	var args := OS.get_cmdline_user_args()
	var output := "/tmp/neon-shard-captures"
	if args.has("--capture-dir"):
		output = args[args.find("--capture-dir") + 1]
	DirAccess.make_dir_recursive_absolute(output)
	for id in world.Archetypes.ORDER:
		world.interface.buttons[id].pressed.emit()
		assert(world.interface.selected == id and world.interface.portrait.selected == id)
		assert(world.interface.connect_button.get_global_rect().end.y <= 720, "Connection controls must remain visible")
		world.queue_redraw()
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		assert(not image.is_empty())
		assert(image.save_png(output.path_join("class-" + id + ".png")) == OK)
	world.interface.enter_world()
	world.state = []
	var index := 0
	for id in world.Archetypes.ORDER:
		if index >= 3:
			break
		var player := {"id": 42 + index, "position": [Vector2(-130, 0), Vector2(100, 60), Vector2(0, -180)][index], "key": "fixture"}
		world.combat.prepare(player, {"archetype": id})
		player.attacking = index == 2
		world.state.append(player)
		index += 1
	world.enemy_state = world.combat.snapshot()
	world.hud.text = "VANGUARD  /  HP 150/150\nSCRAP 0     CREDITS 0\n\nSIGNAL CLEANUP  /  0 of 3\nDisable rogue drones [Space]"
	for mode in ["city", "city-low"]:
		world.effects = mode == "city"
		world.queue_redraw()
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output.path_join(mode + ".png")) == OK)
	for angle in [{"name": "counter", "pixel": Vector2(350, 470)}, {"name": "doorway", "pixel": Vector2(1300, 600)}, {"name": "occlusion", "pixel": Vector2(1160, 530)}]:
		world.effects = true
		world.state[0].position = world.Layout.unproject(angle.pixel - world.Layout.ART_ORIGIN)
		assert(not world.Layout.blocked(world.state[0].position), "Render fixtures must place the actor on the real floor")
		world.visuals.smooth_positions.clear()
		world.queue_redraw()
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output.path_join("city-" + angle.name + ".png")) == OK)
	world.state[0].position = world.Travel.door_position("concourse")
	world.visuals.smooth_positions.clear()
	world.interface.interaction.text = "[ E ]  MAINTENANCE BAY"
	world.queue_redraw()
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join("concourse-travel.png")) == OK)
	for player in world.state:
		var id: String = player.archetype
		player.position = world.Layout.safe_position([Vector2.ZERO, Vector2(130, 80), Vector2(-80, 150)][player.id - 42], "maintenance")
		world.combat.prepare(player, {"zone": "maintenance", "archetype": id})
	world.enemy_state = world.Combat.new("maintenance").snapshot()
	world.interface.location.text = "N / S     MAINTENANCE BAY"
	world.interface.interaction.text = ""
	for view in [{"name": "maintenance", "point": Vector2.ZERO}, {"name": "maintenance-door", "point": world.Travel.door_position("maintenance")}, {"name": "maintenance-column", "point": world.Layout.unproject(Vector2(245, 540) - world.Layout.ART_ORIGIN)}]:
		world.interface.interaction.text = "[ E ]  KAIRO EXCHANGE" if view.name == "maintenance-door" else ""
		world.state[0].position = view.point
		assert(not world.Layout.blocked(view.point, "maintenance"))
		world.visuals.smooth_positions.clear()
		world.queue_redraw()
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output.path_join(view.name + ".png")) == OK)
	print("VISUAL_CAPTURE_OK ", output)
	quit()
