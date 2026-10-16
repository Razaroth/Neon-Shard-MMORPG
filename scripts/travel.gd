extends RefCounted
const Zones = preload("res://scripts/zones.gd")
const Layout = preload("res://scripts/city_layout.gd")
const INTERACT_RANGE := 70.0
const COOLDOWN := 1.2

static func door_position(zone: String) -> Vector2:
	return Layout.unproject(Zones.info(zone).door - Layout.ART_ORIGIN)

static func apply(player: Dictionary, clock: float) -> bool:
	var zone := Zones.valid(str(player.get("zone", "concourse")))
	var door := door_position(zone)
	if clock < float(player.get("next_travel", 0.0)) or player.position.distance_to(door) > INTERACT_RANGE or not Layout.can_travel(player.position, door, zone):
		return false
	var destination: String = Zones.info(zone).target
	player.zone = destination
	player.position = Layout.safe_position(Layout.unproject(Zones.info(destination).arrival - Layout.ART_ORIGIN), destination)
	player.input = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.moving = false
	player.running = false
	player.sprinting = false
	player.attack_started = -100.0
	player.attacking = false
	player.last_input = clock
	player.next_travel = clock + COOLDOWN
	player.travel_protection = 2.0
	return true
