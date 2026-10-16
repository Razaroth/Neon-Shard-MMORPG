extends RefCounted
## A continuous cutaway interior. Floor registration is shared with the server.
const SpriteAnimation = preload("res://scripts/classic_animation.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Zones = preload("res://scripts/zones.gd")
const Travel = preload("res://scripts/travel.gd")
const Layout = preload("res://scripts/city_layout.gd")
const CHARACTER_HEIGHT := 164.4
const CHARACTER_SCALE := CHARACTER_HEIGHT / 76.0
const COLUMN_OCCLUDERS := [
	[Vector2(423, 450), Vector2(432, 160), Vector2(446, 145), Vector2(446, 0), Vector2(527, 0), Vector2(529, 153), Vector2(549, 165), Vector2(558, 433), Vector2(580, 476), Vector2(532, 506), Vector2(455, 498), Vector2(423, 480)],
	[Vector2(1068, 596), Vector2(1092, 252), Vector2(1102, 234), Vector2(1102, 0), Vector2(1200, 0), Vector2(1202, 232), Vector2(1222, 253), Vector2(1214, 574), Vector2(1239, 625), Vector2(1180, 652), Vector2(1100, 643), Vector2(1068, 625)]
]
const MAINTENANCE_OCCLUDERS := [[Vector2(170, 590), Vector2(216, 573), Vector2(215, 285), Vector2(208, 273), Vector2(249, 254), Vector2(281, 269), Vector2(282, 289), Vector2(275, 575), Vector2(325, 603), Vector2(325, 624), Vector2(250, 654), Vector2(170, 621)]]
const CYAN := Color("5ee9e0")
const PINK := Color("ff4d93")
var canvas: Node2D
var room: Texture2D
var room_cache: Dictionary = {}
var zone := "concourse"
var transition_clock := 0.0
var transitions_enabled := true
var animation = SpriteAnimation.new()
var animation_textures: Dictionary = {}
var animation_delta := 0.0
var props: Texture2D
var offset := Vector2.ZERO
var time := 0.0
var previous_time := 0.0
var smooth_positions: Dictionary = {}
var focus := Vector2.ZERO
var detailed := true
var font: Font = ThemeDB.fallback_font

func _init() -> void:
	room = load(Zones.info("concourse").art)
	room_cache["concourse"] = room
	props = load("res://assets/city/props-atlas.png")
	for role in Roles.ORDER:
		animation_textures[role] = {}
		for layer in SpriteAnimation.layers(role):
			for clip in SpriteAnimation.COUNTS:
				var path := "res://assets/lpc/" + str(layer.prefix) + "/" + str(clip) + ".png"
				if not animation_textures[role].has(path):
					var texture := CanvasTexture.new()
					texture.diffuse_texture = load(path)
					texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					animation_textures[role][path] = texture

func screen(point: Vector2) -> Vector2:
	return offset + Layout.art_position(point)

func render(node: Node2D, players: Array, drones: Array, local_id: int, seconds: float, effects: bool) -> void:
	canvas = node
	time = seconds
	detailed = effects
	var delta := clampf(seconds - previous_time, 0, 0.1)
	previous_time = seconds
	animation_delta = delta
	var incoming_zone := zone
	for player in players:
		if int(player.id) == local_id:
			incoming_zone = Zones.valid(str(player.get("zone", "concourse")))
	if incoming_zone != zone:
		zone = incoming_zone
		if not room_cache.has(zone):
			room_cache[zone] = load(Zones.info(zone).art)
		room = room_cache[zone]
		smooth_positions.clear()
		animation.clear()
		transition_clock = 0.25 if transitions_enabled else 0.0
	transition_clock = maxf(0, transition_clock - delta)
	var player_ids: Array = []
	for player in players:
		player_ids.append(int(player.id))
	animation.retain(player_ids)
	players = players.duplicate(true)
	drones = drones.duplicate(true)
	var keys: Array = []
	for index in 2:
		var group: Array = players if index == 0 else drones
		for actor in group:
			var key := str(index) + ":" + str(actor.id)
			keys.append(key)
			var target: Vector2 = actor.position
			var previous: Vector2 = smooth_positions.get(key, target)
			actor.position = target if previous.distance_to(target) > 250 else previous.lerp(target, 1 - exp(-20 * delta))
			smooth_positions[key] = actor.position
	for key in smooth_positions.keys():
		if not keys.has(key):
			smooth_positions.erase(key)
	focus = Vector2.ZERO
	for player in players:
		if int(player.id) == local_id:
			focus = player.position
	var viewport := canvas.get_viewport_rect().size
	offset = Layout.camera_offset(focus, viewport)
	canvas.draw_texture_rect(room, Rect2(offset, Layout.ART_SIZE), false)
	# Local illumination grounds feet on the same floor as the painted architecture.
	if detailed:
		for player in players:
			var color: Color = Roles.stats(player.archetype).color
			var p := screen(player.position).round()
			canvas.draw_set_transform(p, 0, Vector2(1, 0.5))
			for radius in [29, 21, 13]:
				canvas.draw_circle(Vector2.ZERO, radius, Color(color, 0.018))
			canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var entities: Array = []
	for player in players:
		entities.append({"kind": "player", "position": player.position, "data": player})
	for drone in drones:
		if drone.hp > 0:
			entities.append({"kind": "drone", "position": drone.position, "data": drone})
	for index in Layout.columns(zone).size():
		entities.append({"kind": "column", "position": Layout.unproject(Layout.columns(zone)[index] - Layout.ART_ORIGIN), "data": {"index": index}})
	if zone == "concourse":
		entities.append({"kind": "terminal", "position": Vector2.ZERO, "data": {}})
	entities.append({"kind": "door", "position": Travel.door_position(zone), "data": {}})
	entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return screen(a.position).y < screen(b.position).y)
	for entry in entities:
		match entry.kind:
			"player":
				draw_player(entry.data, local_id)
			"drone":
				draw_drone(entry.data)
			"terminal":
				draw_terminal()
			"door":
				draw_door()
			"column":
				draw_column_foreground(entry.data.index)
	# Reapply only the column silhouettes and cutaway front wall, never floor rectangles.
	# This provides real foreground occlusion instead of making actors stand on walls.
	draw_front_railings()
	if detailed:
		# Fine drifting interior dust, rather than outdoor rain inside a room.
		for index in 28:
			var p := Vector2(fposmod(index * 131.2 + time * 5, viewport.x), fposmod(index * 81.7 - time * 8, viewport.y))
			canvas.draw_circle(p, 0.7, Color(0.6, 0.85, 0.9, 0.12))

	if transition_clock > 0:
		canvas.draw_rect(Rect2(Vector2.ZERO, viewport), Color(0.015, 0.025, 0.04, transition_clock / 0.25))

func draw_player(player: Dictionary, local_id: int) -> void:
	var p := screen(player.position).round()
	var style := Roles.stats(player.archetype)
	var pose: Dictionary = animation.sample(player, animation_delta)
	draw_shadow(p, 13 * CHARACTER_SCALE)
	var scale := maxf(1, roundf(CHARACTER_HEIGHT / SpriteAnimation.VISIBLE_HEIGHT))
	canvas.draw_set_transform(p, 0, Vector2(-1 if pose.mirror else 1, 1))
	for layer in SpriteAnimation.layers(player.archetype):
		var path := "res://assets/lpc/" + str(layer.prefix) + "/" + str(pose.sheet) + ".png"
		var texture: Texture2D = animation_textures[player.archetype][path]
		canvas.draw_texture_rect_region(texture, Rect2(-SpriteAnimation.FOOT * scale, SpriteAnimation.CELL * scale), pose.region, layer.color)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if int(player.id) == local_id:
		canvas.draw_arc(p, 16 * CHARACTER_SCALE, 0, TAU, 28, Color(style.color, 0.65), 1, true)
	# Compact labels avoid covering the surrounding room architecture.
	canvas.draw_string(font, p - Vector2(24, CHARACTER_HEIGHT + 8), style.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, style.color)
	canvas.draw_rect(Rect2(p - Vector2(22, CHARACTER_HEIGHT + 3), Vector2(44, 3)), Color("17232a"))
	canvas.draw_rect(Rect2(p - Vector2(22, CHARACTER_HEIGHT + 3), Vector2(44.0 * player.hp / player.max_hp, 3)), style.color)

func draw_drone(data: Dictionary) -> void:
	var ground := screen(data.position)
	var p := ground - Vector2(0, 26 + sin(time * 3 + data.id) * 3)
	draw_shadow(ground, 14)
	canvas.draw_texture_rect_region(props, Rect2(p - Vector2(32, 19), Vector2(64, 38)), Rect2(230, 0, 630, 380), Color("b0c8c9"))
	canvas.draw_rect(Rect2(p - Vector2(18, 25), Vector2(36.0 * data.hp / 60, 2)), PINK)

func draw_terminal() -> void:
	var p := screen(Vector2.ZERO)
	canvas.draw_texture_rect_region(props, Rect2(p - Vector2(23, 62), Vector2(46, 62)), Rect2(1140, 0, 330, 440), Color("b9d0d0"))
	canvas.draw_string(font, p + Vector2(-26, 18), "RELAY / E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, CYAN)

func overlay_polygon(points: Array, alpha: float) -> void:
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	for point in points:
		vertices.append(offset + point)
		uv.append(point / Layout.ART_SIZE)
	canvas.draw_polygon(vertices, PackedColorArray([Color(1, 1, 1, alpha)]), uv, room)

func draw_column_foreground(index: int) -> void:
	var points: Array = MAINTENANCE_OCCLUDERS[index] if zone == "maintenance" else COLUMN_OCCLUDERS[index]
	var focus_pixel := Layout.art_position(focus)
	var alpha := 0.3 if Geometry2D.is_point_in_polygon(focus_pixel - Vector2(0, CHARACTER_HEIGHT * 0.5), PackedVector2Array(points)) else 1.0
	overlay_polygon(points, alpha)

func draw_front_railings() -> void:
	if zone == "maintenance":
		overlay_polygon([Vector2(55, 586), Vector2(295, 718), Vector2(320, 781), Vector2(55, 650)], 1.0)
		overlay_polygon([Vector2(490, 830), Vector2(520, 857), Vector2(560, 849), Vector2(580, 879), Vector2(667, 870), Vector2(720, 894), Vector2(800, 886), Vector2(824, 916), Vector2(1000, 930), Vector2(1040, 964), Vector2(1050, 1024), Vector2(455, 1024), Vector2(455, 925)], 1.0)
		overlay_polygon([Vector2(1170, 886), Vector2(1480, 730), Vector2(1536, 736), Vector2(1536, 1024), Vector2(1230, 1024)], 1.0)
		return
	overlay_polygon([Vector2(0, 527), Vector2(76, 572), Vector2(278, 691), Vector2(279, 759), Vector2(0, 622)], 1.0)
	overlay_polygon([Vector2(1170, 783), Vector2(1408, 652), Vector2(1478, 634), Vector2(1482, 708), Vector2(1198, 870)], 1.0)

func draw_shadow(point: Vector2, radius: float) -> void:
	canvas.draw_set_transform(point, 0, Vector2(1, 0.45))
	canvas.draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.28))
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func draw_door() -> void:
	var p := screen(Travel.door_position(zone))
	canvas.draw_set_transform(p, 0, Vector2(1, 0.5))
	canvas.draw_circle(Vector2.ZERO, 24, Color(CYAN, 0.09))
	canvas.draw_arc(Vector2.ZERO, 22, 0, TAU, 28, Color(CYAN, 0.5), 1, true)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	canvas.draw_string(font, p + Vector2(-65, 22), Zones.info(zone).link_name + " / E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, CYAN)
