extends SceneTree

const Layout = preload("res://scripts/city_layout.gd")
const Simulation = preload("res://scripts/combat.gd")

func world(pixel: Vector2) -> Vector2:
	return Layout.unproject(pixel - Layout.ART_ORIGIN)

func _init() -> void:
	assert(not Layout.blocked(Vector2.ZERO))
	assert(Layout.blocked(world(Vector2(750, 160))), "Rear architecture must block movement")
	var column: Vector2 = Layout.COLUMN_BASES[0]
	assert(Layout.blocked(world(column)), "The painted column base must have real collision")
	var migrated := Layout.safe_position(world(column))
	assert(not Layout.blocked(migrated), "Old characters inside a new fixture must relocate onto the floor")
	assert(Layout.safe_position(Vector2(180, 0)) == Vector2(180, 0), "Valid saves must remain unchanged")
	var a := world(column + Vector2(-130, 0))
	var b := world(column + Vector2(130, 0))
	assert(not Layout.blocked(a) and not Layout.blocked(b))
	assert(not Layout.can_travel(a, b), "Support columns must break direct routes")
	var actor := a
	for tick in 900:
		var waypoint := Layout.next_waypoint(actor, b)
		actor = Layout.move_actor(actor, actor.direction_to(waypoint) * minf(3, actor.distance_to(waypoint)))
		assert(not Layout.blocked(actor))
		if actor.distance_to(b) < 5:
			break
	assert(actor.distance_to(b) < 5, "The room must be connected around its columns")
	var stopped := Layout.move_actor(a, b - a)
	assert(not Layout.blocked(stopped) and stopped.distance_to(b) > 10, "A long movement frame cannot tunnel through a column")
	var simulation = Simulation.new()
	var player := {"position": b, "input": Vector2.ZERO}
	simulation.prepare(player, {"archetype": "vanguard"})
	simulation.enemies = [{"position": a, "home": a, "hp": 60, "respawn": 0.0, "next_attack": 0.0}]
	for tick in 900:
		simulation.step(1.0 / 60.0, {2: player})
		assert(not Layout.blocked(simulation.enemies[0].position))
	assert(player.hp < player.max_hp, "Drones must pursue around interior fixtures")
	var ranged = Simulation.new()
	var ghost := {"position": world(column + Vector2(-110, 0)), "input": Vector2.ZERO}
	ranged.prepare(ghost, {"archetype": "ghost"})
	ghost.attacking = true
	ranged.enemies = [{"position": world(column + Vector2(110, 0)), "home": world(column + Vector2(110, 0)), "hp": 60, "respawn": 0.0, "next_attack": 0.0}]
	assert(ghost.position.distance_to(ranged.enemies[0].position) < 280)
	ranged.step(0.01, {3: ghost})
	assert(ranged.enemies[0].hp == 60, "Attacks cannot pass through columns")
	# Every supported camera location keeps the authored room covering the viewport.
	for pixel in [Vector2(350, 470), Vector2(800, 620), Vector2(1300, 600), Vector2(930, 850)]:
		var point := world(pixel)
		assert(not Layout.blocked(point))
		var offset := Layout.camera_offset(point, Vector2(1280, 720))
		assert(offset.x <= 0 and offset.y <= 0)
		assert(offset.x + Layout.ART_SIZE.x >= 1280 and offset.y + Layout.ART_SIZE.y >= 720)
	print("INTERIOR_ROUTES_OK authored floor, column collision, navigation, enemy pursuit, sightlines, save migration, camera coverage")
	quit()
