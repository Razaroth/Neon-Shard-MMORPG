extends SceneTree

func _init() -> void:
	var Roles = preload("res://scripts/archetypes.gd")
	var Simulation = preload("res://scripts/combat.gd")
	var Layout = preload("res://scripts/city_layout.gd")
	assert(Roles.valid("unknown") == "ronin")
	for id in Roles.ORDER:
		var sim = Simulation.new()
		var actor := {"position": Vector2.ZERO, "input": Vector2.ZERO}
		sim.prepare(actor, {"archetype": id})
		assert(actor.max_hp == Roles.stats(id).hp and actor.hp == actor.max_hp)
		actor.attacking = true
		# At this distance only the ranged Cipher and Ghost should connect.
		sim.enemies = [{"position": Vector2(210, 0), "home": Vector2(210, 0), "hp": 60, "next_attack": 0.0, "respawn": 0.0}]
		sim.step(0.01, {2: actor})
		assert((sim.enemies[0].hp < 60) == (id in ["cipher", "ghost"]), "Class reach must be enforced by the server")
		var hp: int = sim.enemies[0].hp
		for i in 10:
			sim.step(0.001, {2: actor})
		assert(sim.enemies[0].hp == hp, "Class cooldown cannot be bypassed")
	var legacy := {}
	Simulation.new().prepare(legacy, {"hp": 42})
	assert(legacy.archetype == "ronin" and legacy.hp == 42, "Old saves must migrate safely")
	var column := Layout.unproject(Layout.COLUMN_BASES[0] - Layout.ART_ORIGIN)
	assert(Layout.blocked(column), "Room columns must have collision")
	assert(not Layout.blocked(Vector2.ZERO))
	assert(Layout.move_actor(Vector2.ZERO, Vector2(20, 0)) == Vector2(20, 0), "Concourse floor must remain traversable")
	print("CLASS_RULES_OK five classes, reach, cooldowns, legacy saves, interior collision")
	quit()
