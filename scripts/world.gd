extends Node2D

const WORLD_LIMIT := 1100.0
const SNAPSHOT_INTERVAL := 0.05
const MAX_PLAYERS := 32 # Admission limit, not a measured capacity claim.
const Zones = preload("res://scripts/zones.gd")
const Travel = preload("res://scripts/travel.gd")
const Archetypes = preload("res://scripts/archetypes.gd")
const Layout = preload("res://scripts/city_layout.gd")
const CityVisuals = preload("res://scripts/city_visuals.gd")
const Interface = preload("res://scripts/interface.gd")
var visuals: RefCounted
var interface: CanvasLayer
var effects := true
const Combat = preload("res://scripts/combat.gd")
var combat = Combat.new()
var combats: Dictionary = {}
var client_zone := "concourse"
var travel_mode := ""
var travel_entered := false
var observer_saw_company := false
var observer_alone_clock := 0.0
var enemy_state: Array = []
var class_probe := false
var gameplay_smoke := false
var verify_progress := false
var hud: Label
var server_mode := false
var smoke := false
var port := 2456
var save_dir := "user://world"
var identity_file := "user://identity.cfg"
var token := ""
var players: Dictionary = {}
var pending: Dictionary = {}
var characters: Dictionary = {}
var state: Array = []
var local_id := 0
var elapsed := 0.0
var snapshot_clock := 0.0
var smoke_clock := 0.0
var smoke_direction := Vector2.RIGHT
var smoke_origin := Vector2.ZERO
var smoke_started := false
var smoke_moved := false
var smoke_finished := false
var smoke_saw_peers := false
var host_field: LineEdit
var status_label: Label
var connect_button: Button

func option(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _ready() -> void:
	server_mode = OS.get_cmdline_user_args().has("--server")
	for mode in ["--travel-smoke", "--return-smoke", "--verify-room", "--observe-travel"]:
		if OS.get_cmdline_user_args().has(mode):
			travel_mode = mode
	class_probe = OS.get_cmdline_user_args().has("--verify-class")
	gameplay_smoke = OS.get_cmdline_user_args().has("--combat-smoke")
	verify_progress = OS.get_cmdline_user_args().has("--verify-progress")
	smoke = OS.get_cmdline_user_args().has("--smoke-client") or gameplay_smoke or verify_progress or class_probe or not travel_mode.is_empty()
	port = int(option("--port", "2456"))
	save_dir = option("--save-dir", save_dir)
	identity_file = option("--identity-file", identity_file)
	# All gameplay routes through the server; peer-to-peer relay is unnecessary.
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	if server_mode:
		combats = {"concourse": combat, "maintenance": Combat.new("maintenance")}
		_start_server()
	else:
		_build_ui()
		if smoke:
			_join()

func _start_server() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var path := save_dir.path_join("characters.json")
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("Invalid character save; refusing to overwrite it.")
			get_tree().quit(1)
			return
		characters = parsed
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("Cannot bind server: %s" % error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print("SERVER_READY port=%s characters=%s" % [port, characters.size()])

func _build_ui() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visuals = CityVisuals.new()
	interface = Interface.new()
	add_child(interface)
	interface.build(self)
	host_field = interface.host
	connect_button = interface.connect_button
	status_label = interface.status
	hud = interface.hud

func _join() -> void:
	var config := ConfigFile.new()
	if config.load(identity_file) == OK:
		token = str(config.get_value("identity", "token", ""))
	if token.length() != 64:
		token = Crypto.new().generate_random_bytes(32).hex_encode()
		config.set_value("identity", "token", token)
		if config.save(identity_file) != OK:
			_fail("Cannot save local character identity")
			return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host_field.text.strip_edges(), port)
	if error != OK:
		_fail("Connection could not start: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	connect_button.disabled = true
	status_label.text = "Connecting…"

func _connected() -> void:
	local_id = multiplayer.get_unique_id()
	register_character.rpc_id(1, token, interface.selected, interface.slot_picker.selected)
	host_field.release_focus()
	connect_button.release_focus()
	interface.enter_world()
	status_label.text = "Connected · WASD / arrows to move"

func _connection_failed() -> void:
	_fail("Connection failed; check host, UDP port, and firewall")

func _server_disconnected() -> void:
	if smoke_finished:
		get_tree().quit(0)
		return
	state.clear()
	enemy_state.clear()
	_fail("Server disconnected")

func _fail(message: String) -> void:
	push_warning(message)
	if status_label:
		status_label.text = message
		connect_button.disabled = false
		interface.show_menu()
	if smoke:
		get_tree().quit(1)

func _peer_connected(id: int) -> void:
	if server_mode:
		pending[id] = elapsed

func _peer_disconnected(id: int) -> void:
	if server_mode:
		if players.has(id):
			_remember(id)
			players.erase(id)
			_save()
		pending.erase(id)

@rpc("any_peer", "call_remote", "reliable")
func register_character(identity: String, requested_class: String = "ronin", character_slot: int = 0) -> void:
	if not server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	if character_slot < 0 or character_slot >= 5:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if not pending.has(id) or identity.length() != 64 or not identity.is_valid_hex_number(false):
		return
	var key := identity.sha256_text() if character_slot == 0 else (identity + ":" + str(character_slot)).sha256_text()
	for other in players.values():
		if other.key == key:
			multiplayer.multiplayer_peer.disconnect_peer(id)
			return
	var saved: Dictionary = characters.get(key, {})
	if saved.is_empty():
		saved = {"archetype": Archetypes.valid(requested_class)}
	var zone := Zones.valid(str(saved.get("zone", "concourse")))
	var pos := Layout.safe_position(Vector2(float(saved.get("x", 0.0)), float(saved.get("y", 0.0))), zone)
	players[id] = {"key": key, "position": pos, "input": Vector2.ZERO, "last_input": elapsed}
	combats[zone].prepare(players[id], saved)
	pending.erase(id)
	print("PLAYER_JOINED peer=%s" % id)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(direction: Vector2) -> void:
	if not server_mode or not direction.is_finite():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].input = direction.limit_length(1.0)
		players[id].last_input = elapsed

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_state(snapshot: Array, drones: Array) -> void:
	state = snapshot
	enemy_state = drones
	for player in state:
		if int(player.id) == local_id:
			client_zone = Zones.valid(str(player.get("zone", "concourse")))
			interface.location.text = "N / S     " + Zones.info(client_zone).name
			interface.interaction.text = ""
			var door := Travel.door_position(client_zone)
			if player.position.distance_to(door) <= Travel.INTERACT_RANGE and Layout.can_travel(player.position, door, client_zone):
				interface.interaction.text = "[ E ]  " + Zones.info(client_zone).link_name
			elif client_zone == "concourse" and player.position.length() <= 100:
				interface.interaction.text = "[ E ]  RELAY CONSOLE"
			if travel_mode == "--verify-room":
				if client_zone != option("--expect-room", "maintenance") or int(player.scrap) != int(option("--expect-scrap", "1")) or int(player.hp) != int(option("--expect-hp", str(player.hp))):
					_fail("Room, loot or health did not survive reconnect")
					return
				_finish_smoke("ROOM_RESTORED zone=%s hp=%s scrap=%s" % [client_zone, player.hp, player.scrap])
			for visible_player in state:
				if str(visible_player.get("zone", "concourse")) != client_zone:
					_fail("Snapshot leaked players from another room")
					return
			hud.text = "%s  /  HP %s/%s\nSCRAP %s     CREDITS %s\n\nSIGNAL CLEANUP  /  %s of 3\n%s" % [Archetypes.stats(player.archetype).name, player.hp, player.max_hp, player.scrap, player.credits, player.kills, "Contract complete" if player.rewarded else ("Return to the concourse relay" if client_zone == "maintenance" else "Return to terminal [E]") if player.kills >= 3 else "Disable rogue drones [Space]"]
			if class_probe:
				if player.archetype != option("--expect-class", "ronin"):
					_fail("Unexpected class in saved character slot")
					return
				_finish_smoke("CLASS_SLOT_OK " + player.archetype)
			if verify_progress:
				if player.archetype != option("--expect-class", "ronin"):
					_fail("Class changed on reconnect")
					return
				if player.rewarded and player.credits == 100 and player.scrap >= 3:
					_finish_smoke("PROGRESS_RESTORED")
				else:
					_fail("Mission progress was not restored")
	if smoke:
		smoke_saw_peers = smoke_saw_peers or state.size() >= int(option("--expect-peers", "1"))
		for player in state:
			if int(player.id) == local_id:
				var pos: Vector2 = player.position
				if not smoke_started:
					smoke_started = true
					smoke_origin = pos
					print("INITIAL_POSITION %.3f %.3f" % [pos.x, pos.y])
					print("CHARACTER_CLASS %s" % player.archetype)
					var expected := option("--expect-class", "")
					if not expected.is_empty() and expected != player.archetype:
						_fail("Unexpected character class")
				if pos.distance_to(smoke_origin) > 20.0:
					smoke_moved = true

func _physics_process(delta: float) -> void:
	elapsed += delta
	if server_mode:
		for id in pending.keys():
			if elapsed - float(pending[id]) > 10.0:
				multiplayer.multiplayer_peer.disconnect_peer(id)
				pending.erase(id)
		for id in players:
			var player: Dictionary = players[id]
			var direction: Vector2 = player.input if elapsed - player.last_input < 0.3 else Vector2.ZERO
			if elapsed - player.last_input >= 0.3:
				player.attacking = false
			player.position = Layout.move_actor(player.position, direction * Archetypes.stats(player.archetype).speed * delta, player.zone).clamp(Vector2.ONE * -WORLD_LIMIT, Vector2.ONE * WORLD_LIMIT)
		for zone in Zones.IDS:
			combats[zone].step(delta, _zone_players(zone))
		snapshot_clock += delta
		if snapshot_clock >= SNAPSHOT_INTERVAL:
			snapshot_clock = 0.0
			var snapshots := _snapshots()
			for id in players:
				var remote: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(id)
				if remote != null and remote.get_state() == ENetPacketPeer.STATE_CONNECTED and remote.get_channels() > 0:
					var zone: String = players[id].zone
					receive_state.rpc_id(id, snapshots[zone], combats[zone].snapshot())
		if int(elapsed / 5.0) > int((elapsed - delta) / 5.0):
			for id in players:
				_remember(id)
			_save()
	else:
		if smoke_finished:
			return
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and local_id != 0:
			var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
			if not travel_mode.is_empty():
				direction = _travel_pilot(delta)
			elif gameplay_smoke:
				direction = _combat_pilot()
			elif smoke and not verify_progress and smoke_started:
				for player in state:
					if int(player.id) == local_id and not Layout.can_travel(player.position, player.position + smoke_direction * 30, client_zone):
						smoke_direction = -smoke_direction
				direction = smoke_direction
				smoke_clock += delta
				if smoke_clock > 6.0:
					if smoke_moved and smoke_saw_peers:
						_finish_smoke("SMOKE_OK authoritative movement observed")
						return
					else:
						_fail("No authoritative movement received")
			if not smoke:
				set_attack.rpc_id(1, Input.is_physical_key_pressed(KEY_SPACE))
			submit_input.rpc_id(1, direction)
		if smoke and elapsed > (65.0 if not travel_mode.is_empty() else 40.0 if gameplay_smoke else 12.0):
			_fail("Smoke test timed out")
		queue_redraw()

func _remember(id: int) -> void:
	var player: Dictionary = players[id]
	characters[player.key] = {"zone": player.zone, "x": player.position.x, "y": player.position.y, "archetype": player.archetype, "hp": player.hp, "scrap": player.scrap, "credits": player.credits, "kills": player.kills, "rewarded": player.rewarded}

func _save() -> void:
	var path := save_dir.path_join("characters.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write world save")
		return
	file.store_string(JSON.stringify(characters))
	file.close()
	var error := DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		push_error("Cannot replace world save: %s" % error)

func _draw() -> void:
	if not server_mode:
		visuals.render(self, state, enemy_state, local_id, elapsed, effects)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		effects = not effects
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and not server_mode and local_id != 0 and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		use_terminal.rpc_id(1)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func set_attack(held: bool) -> void:
	if server_mode:
		var id := multiplayer.get_remote_sender_id()
		if players.has(id):
			players[id].attacking = held

@rpc("any_peer", "call_remote", "reliable")
func use_terminal() -> void:
	if server_mode:
		var id := multiplayer.get_remote_sender_id()
		if not players.has(id):
			return
		var player: Dictionary = players[id]
		if Travel.apply(player, elapsed):
			_remember(id)
			_save()
			print("PLAYER_TRAVEL peer=%s room=%s" % [id, player.zone])
		elif combats[player.zone].interact(player):
			_remember(id)
			_save()

func _combat_pilot() -> Vector2:
	for player in state:
		if int(player.id) != local_id:
			continue
		if player.rewarded:
			_finish_smoke("COMBAT_OK scrap=%s credits=%s" % [player.scrap, player.credits])
			return Vector2.ZERO
		var target := Vector2.ZERO
		if player.kills < 3:
			var distance := INF
			for enemy in enemy_state:
				var candidate: float = player.position.distance_to(enemy.position)
				if enemy.hp > 0 and candidate < distance:
					distance = candidate
					target = enemy.position
			set_attack.rpc_id(1, true)
			if distance < Archetypes.stats(player.archetype).range * 0.8 and Layout.can_travel(player.position, target, client_zone):
				return Vector2.ZERO
		else:
			set_attack.rpc_id(1, false)
			use_terminal.rpc_id(1)
		return player.position.direction_to(Layout.next_waypoint(player.position, target, client_zone)) if player.position.distance_to(target) > 50 else Vector2.ZERO
	return Vector2.ZERO

func _finish_smoke(message: String) -> void:
	if smoke_finished:
		return
	print(message)
	smoke_finished = true
	leave_world.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func leave_world() -> void:
	if not server_mode:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		_remember(id)
		players.erase(id)
		_save()
	left_world.rpc_id(id)

@rpc("authority", "call_remote", "reliable")
func left_world() -> void:
	if smoke_finished:
		get_tree().quit(0)

func _zone_players(zone: String) -> Dictionary:
	var result: Dictionary = {}
	for id in players:
		if players[id].zone == zone:
			result[id] = players[id]
	return result

func _snapshots() -> Dictionary:
	var snapshots := {"concourse": [], "maintenance": []}
	for id in players:
		var entry: Dictionary = players[id].duplicate()
		entry.moving = entry.input.length_squared() > 0.01
		for field in ["key", "input", "last_input", "next_travel"]:
			entry.erase(field)
		entry.id = id
		snapshots[entry.zone].append(entry)
	return snapshots

func _travel_pilot(delta: float) -> Vector2:
	for player in state:
		if int(player.id) != local_id:
			continue
		if travel_mode == "--observe-travel":
			observer_saw_company = observer_saw_company or state.size() >= 2
			if observer_saw_company and state.size() == 1:
				observer_alone_clock += delta
				if observer_alone_clock >= 1.0:
					_finish_smoke("ROOM_ISOLATION_OK departed player is no longer visible")
			return Vector2.ZERO
		if travel_mode == "--verify-room":
			return Vector2.ZERO
		if travel_mode == "--return-smoke" and client_zone == "concourse":
			_finish_smoke("RETURN_TRAVEL_OK room=concourse")
			return Vector2.ZERO
		var target := Travel.door_position(client_zone)
		if travel_mode == "--travel-smoke" and client_zone == "maintenance":
			if not travel_entered:
				travel_entered = true
				print("ENTERED_MAINTENANCE")
			if player.scrap >= 1:
				_finish_smoke("TRAVEL_COMBAT_OK room=maintenance hp=%s scrap=%s" % [player.hp, player.scrap])
				return Vector2.ZERO
			var distance := INF
			for enemy in enemy_state:
				var candidate: float = player.position.distance_to(enemy.position)
				if enemy.hp > 0 and candidate < distance:
					distance = candidate
					target = enemy.position
			set_attack.rpc_id(1, true)
			if distance < Archetypes.stats(player.archetype).range * 0.8 and Layout.can_travel(player.position, target, client_zone):
				return Vector2.ZERO
		else:
			set_attack.rpc_id(1, false)
			if player.position.distance_to(target) < Travel.INTERACT_RANGE - 5:
				use_terminal.rpc_id(1)
				return Vector2.ZERO
		var waypoint := Layout.next_waypoint(player.position, target, client_zone)
		return player.position.direction_to(waypoint)
	return Vector2.ZERO
