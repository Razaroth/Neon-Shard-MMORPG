extends SceneTree
const Zones = preload("res://scripts/zones.gd")
const Layout = preload("res://scripts/city_layout.gd")
const Travel = preload("res://scripts/travel.gd")
const Combat = preload("res://scripts/combat.gd")

func _init() -> void:
	for zone in Zones.IDS:
		var door := Travel.door_position(zone)
		var arrival := Layout.unproject(Zones.info(zone).arrival - Layout.ART_ORIGIN)
		assert(not Layout.blocked(door, zone), "Door must be on reachable floor: " + zone)
		assert(not Layout.blocked(arrival, zone), "Arrival must be on reachable floor: " + zone)
		assert(Layout.next_waypoint(Vector2.ZERO, door, zone) != Vector2.ZERO)
	var actor := {"position": Vector2.ZERO, "input": Vector2.RIGHT, "last_input": 0.0}
	Combat.new().prepare(actor, {"archetype": "vanguard", "zone": "concourse", "hp": 42, "scrap": 7, "credits": 100, "kills": 2})
	assert(not Travel.apply(actor, 10), "Remote travel must be rejected")
	actor.position = Travel.door_position("concourse")
	actor.attacking = true
	assert(Travel.apply(actor, 10))
	assert(actor.zone == "maintenance" and not Layout.blocked(actor.position, actor.zone))
	assert(actor.hp == 42 and actor.scrap == 7 and actor.credits == 100 and actor.kills == 2 and actor.archetype == "vanguard", "Travel must preserve character progress")
	assert(actor.input == Vector2.ZERO and not actor.attacking, "Old movement and attack intent must clear at the doorway")
	assert(actor.travel_protection > 0)
	actor.position = Travel.door_position("maintenance")
	assert(not Travel.apply(actor, 10.1), "Queued interactions cannot bounce the player between rooms")
	assert(Travel.apply(actor, 12) and actor.zone == "concourse")
	# A foreign-room character cannot damage or attract this room's enemy.
	var simulation = Combat.new("maintenance")
	var foreign := {"position": Vector2(200, 0), "input": Vector2.ZERO}
	simulation.prepare(foreign, {"zone": "concourse"})
	foreign.attacking = true
	simulation.enemies = [{"position": Vector2(200, 0), "home": Vector2(200, 0), "hp": 60, "respawn": 0.0, "next_attack": 0.0}]
	simulation.step(0.1, {3: foreign})
	assert(simulation.enemies[0].hp == 60 and foreign.hp == foreign.max_hp)
	var resident := {"position": Vector2(200, 0), "input": Vector2.ZERO}
	simulation.prepare(resident, {"zone": "maintenance"})
	resident.attacking = true
	simulation.step(0.6, {3: foreign, 4: resident})
	assert(simulation.enemies[0].hp == 40, "Only this room's player can deal damage")
	# Arrival protection prevents spawn damage, and ends when the player attacks.
	var protected := {"position": Travel.door_position("concourse"), "input": Vector2.ZERO, "last_input": 0.0}
	Combat.new().prepare(protected, {"zone": "concourse", "hp": 42})
	assert(Travel.apply(protected, 20))
	var guard = Combat.new("maintenance")
	guard.enemies = [{"position": protected.position, "home": protected.position, "hp": 60, "respawn": 0.0, "next_attack": 0.0}]
	guard.step(0.01, {5: protected})
	assert(protected.hp == 42)
	protected.attacking = true
	guard.step(0.01, {5: protected})
	assert(protected.hp < 42 and protected.travel_protection == 0)
	# Snapshot isolation must agree with simulation isolation.
	var world = preload("res://scripts/world.gd").new()
	world.players = {3: foreign, 4: resident}
	var snapshots: Dictionary = world._snapshots()
	assert(snapshots.concourse.size() == 1 and snapshots.concourse[0].id == 3)
	assert(snapshots.maintenance.size() == 1 and snapshots.maintenance[0].id == 4)
	world.free()
	assert(Zones.valid("unknown-old-room") == "concourse")
	print("TRAVEL_RULES_OK doorway range, round trip, cooldown, stat preservation, room isolation, arrival protection")
	quit()
