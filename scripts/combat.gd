extends RefCounted
## Server-only combat simulation. Clients supply intent, never damage or rewards.

const Archetypes = preload("res://scripts/archetypes.gd")
const Zones = preload("res://scripts/zones.gd")
const Layout = preload("res://scripts/city_layout.gd")

const TERMINAL := Vector2.ZERO
const MISSION_TARGET := 3
var zone := "concourse"
var enemies: Array = []
var clock := 0.0

func _init(room_id: String = "concourse") -> void:
	zone = Zones.valid(room_id)
	var homes: Array = [Vector2(180, 0), Vector2(0, 260), Vector2(-260, 0)]
	if zone == "maintenance":
		homes = [Layout.unproject(Vector2(1000, 650) - Layout.ART_ORIGIN), Layout.unproject(Vector2(750, 750) - Layout.ART_ORIGIN), Layout.unproject(Vector2(1100, 500) - Layout.ART_ORIGIN)]
	for point in homes:
		point = Layout.safe_position(point, zone)
		enemies.append({"position": point, "home": point, "hp": 60, "respawn": 0.0, "next_attack": 0.0})

func prepare(player: Dictionary, saved: Dictionary) -> void:
	player.zone = Zones.valid(str(saved.get("zone", "concourse")))
	player.travel_protection = 0.0
	player.archetype = Archetypes.valid(str(saved.get("archetype", "ronin")))
	var stats := Archetypes.stats(player.archetype)
	player.max_hp = stats.hp
	player.hp = clampi(int(saved.get("hp", stats.hp)), 1, stats.hp)
	player.next_attack = 0.0
	player.attacking = false
	player.scrap = maxi(0, int(saved.get("scrap", 0)))
	player.credits = maxi(0, int(saved.get("credits", 0)))
	player.kills = clampi(int(saved.get("kills", 0)), 0, MISSION_TARGET)
	player.rewarded = bool(saved.get("rewarded", false))

func step(delta: float, players: Dictionary) -> void:
	clock += delta
	players = players.duplicate()
	for id in players.keys():
		if str(players[id].get("zone", "concourse")) != zone:
			players.erase(id)
	for player in players.values():
		player.travel_protection = maxf(0, float(player.get("travel_protection", 0.0)) - delta)
		if player.attacking:
			player.travel_protection = 0.0
		if player.attacking and clock >= player.next_attack:
			# Consume the cooldown even on a miss; RPC frequency cannot increase damage.
			player.next_attack = clock + Archetypes.stats(player.archetype).cooldown
			var target: Dictionary = {}
			var distance: float = Archetypes.stats(player.archetype).range
			for enemy in enemies:
				var candidate: float = player.position.distance_to(enemy.position)
				if enemy.hp > 0 and candidate <= distance and Layout.can_travel(player.position, enemy.position, zone):
					target = enemy
					distance = candidate
			if not target.is_empty():
				target.hp -= Archetypes.stats(player.archetype).damage
				if target.hp <= 0:
					target.respawn = clock + 10.0
					player.scrap += 1
					player.kills = mini(MISSION_TARGET, player.kills + 1)
	for enemy in enemies:
		if enemy.hp <= 0:
			if clock >= enemy.respawn:
				enemy.hp = 60
				enemy.position = enemy.home
			continue
		var target: Dictionary = {}
		var distance := 340.0
		for player in players.values():
			# A small sanctuary around the terminal protects joining players.
			if (zone == "concourse" and player.position.distance_to(TERMINAL) < 90.0) or player.travel_protection > 0:
				continue
			var candidate: float = player.position.distance_to(enemy.position)
			if candidate < distance:
				target = player
				distance = candidate
		if target.is_empty():
			enemy.position = Layout.move_actor(enemy.position, enemy.position.direction_to(Layout.next_waypoint(enemy.position, enemy.home, zone)) * minf(enemy.position.distance_to(enemy.home), 65.0 * delta), zone)
		else:
			enemy.position = Layout.move_actor(enemy.position, enemy.position.direction_to(Layout.next_waypoint(enemy.position, target.position, zone)) * 65.0 * delta, zone) if distance > 45.0 or not Layout.can_travel(enemy.position, target.position, zone) else enemy.position
			if distance <= 55.0 and clock >= enemy.next_attack and Layout.can_travel(enemy.position, target.position, zone):
				enemy.next_attack = clock + 1.0
				target.hp -= 8
				if target.hp <= 0:
					target.position = spawn_position()
					target.hp = target.max_hp
					target.input = Vector2.ZERO

func interact(player: Dictionary) -> bool:
	if zone != "concourse" or str(player.get("zone", "concourse")) != zone or player.position.distance_to(TERMINAL) > 100.0 or player.kills < MISSION_TARGET or player.rewarded:
		return false
	player.rewarded = true
	player.credits += 100
	return true

func snapshot() -> Array:
	var result: Array = []
	for index in enemies.size():
		var enemy: Dictionary = enemies[index]
		result.append({"id": index, "position": enemy.position, "hp": enemy.hp})
	return result

func spawn_position() -> Vector2:
	return Vector2.ZERO if zone == "concourse" else Layout.safe_position(Layout.unproject(Zones.info(zone).arrival - Layout.ART_ORIGIN), zone)
