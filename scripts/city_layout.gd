extends RefCounted
## Authored transit hall: geometry is registered against the painted room floor.
## The server uses only these coordinates, never the client artwork.
const WORLD_LIMIT := 1100.0
const NAV_CELL := 25.0
const ART_ORIGIN := Vector2(800, 620)
const ART_SIZE := Vector2(1536, 1024)
const PROJECT_SCALE := 0.65
const FOOT_CLEARANCE := 11.0
const FLOOR := [Vector2(60, 470), Vector2(735, 315), Vector2(1210, 454), Vector2(1340, 454), Vector2(1510, 340), Vector2(1525, 450), Vector2(1438, 520), Vector2(1420, 646), Vector2(1150, 795), Vector2(1070, 860), Vector2(815, 970), Vector2(550, 830), Vector2(320, 700), Vector2(76, 564)]
const COLUMN_BASES := [Vector2(500, 476), Vector2(1152, 620)]
const MAINTENANCE_FLOOR := [Vector2(60, 515), Vector2(155, 370), Vector2(170, 300), Vector2(190, 260), Vector2(280, 205), Vector2(355, 235), Vector2(380, 285), Vector2(570, 325), Vector2(760, 380), Vector2(900, 395), Vector2(1100, 475), Vector2(1400, 585), Vector2(1450, 650), Vector2(1390, 740), Vector2(1100, 890), Vector2(900, 935), Vector2(720, 905), Vector2(520, 850), Vector2(330, 770), Vector2(150, 680), Vector2(65, 590)]
const MAINTENANCE_COLUMNS := [Vector2(245, 610)]
static var floor_shapes := {"concourse": PackedVector2Array(FLOOR), "maintenance": PackedVector2Array(MAINTENANCE_FLOOR)}
static var navigations: Dictionary = {}
static var cells_by_zone: Dictionary = {}

static func columns(zone: String = "concourse") -> Array:
	return MAINTENANCE_COLUMNS if zone == "maintenance" else COLUMN_BASES

static func project(point: Vector2) -> Vector2:
	return Vector2(point.x - point.y, (point.x + point.y) * 0.5) * PROJECT_SCALE

static func unproject(pixel: Vector2) -> Vector2:
	return Vector2(pixel.x + 2 * pixel.y, 2 * pixel.y - pixel.x) / (2 * PROJECT_SCALE)

static func art_position(point: Vector2) -> Vector2:
	return ART_ORIGIN + project(point)

static func camera_offset(point: Vector2, viewport: Vector2) -> Vector2:
	var desired := art_position(point) - Vector2(0, 100)
	var camera := desired.clamp(viewport * 0.5, ART_SIZE - viewport * 0.5)
	return viewport * 0.5 - camera

static func column_polygon(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(-85, 0), center + Vector2(0, -43), center + Vector2(85, 0), center + Vector2(0, 43)])

static func _near_edge(point: Vector2, polygon: PackedVector2Array) -> bool:
	for index in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])) < FOOT_CLEARANCE:
			return true
	return false

static func blocked(point: Vector2, zone: String = "concourse") -> bool:
	if not point.is_finite() or absf(point.x) > WORLD_LIMIT or absf(point.y) > WORLD_LIMIT:
		return true
	var art := art_position(point)
	var floor_polygon: PackedVector2Array = floor_shapes.get(zone, floor_shapes.concourse)
	if not Geometry2D.is_point_in_polygon(art, floor_polygon) or _near_edge(art, floor_polygon):
		return true
	for center in columns(zone):
		if art.distance_squared_to(center) > 110.0 * 110.0:
			continue
		var shape := column_polygon(center)
		if Geometry2D.is_point_in_polygon(art, shape) or _near_edge(art, shape):
			return true
	return false

static func _navigation(zone: String = "concourse") -> AStarGrid2D:
	if navigations.has(zone):
		return navigations[zone]
	var navigation := AStarGrid2D.new()
	var free_cells: Array[Vector2i] = []
	navigation.region = Rect2i(-44, -44, 89, 89)
	navigation.cell_size = Vector2.ONE * NAV_CELL
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(-44, 45):
		for y in range(-44, 45):
			var id := Vector2i(x, y)
			var solid := blocked(Vector2(id) * NAV_CELL, zone)
			navigation.set_point_solid(id, solid)
			if not solid:
				free_cells.append(id)
	navigations[zone] = navigation
	cells_by_zone[zone] = free_cells
	return navigation

static func _nearest_id(point: Vector2, visible: bool = false, zone: String = "concourse") -> Vector2i:
	_navigation(zone)
	var result := Vector2i.ZERO
	var distance := INF
	for id in cells_by_zone[zone]:
		var position := Vector2(id) * NAV_CELL
		var candidate := position.distance_squared_to(point)
		if candidate < distance and (not visible or can_travel(point, position, zone)):
			result = id
			distance = candidate
	return result

static func safe_position(point: Vector2, zone: String = "concourse") -> Vector2:
	if not point.is_finite():
		return Vector2.ZERO
	if not blocked(point, zone):
		return point
	return Vector2(_nearest_id(point, false, zone)) * NAV_CELL

static func can_travel(from: Vector2, target: Vector2, zone: String = "concourse") -> bool:
	var steps := maxi(1, ceili(from.distance_to(target) / 8.0))
	for index in range(steps + 1):
		if blocked(from.lerp(target, float(index) / steps), zone):
			return false
	return true

static func move_actor(from: Vector2, displacement: Vector2, zone: String = "concourse") -> Vector2:
	var steps := maxi(1, ceili(displacement.length() / 8.0))
	var increment := displacement / steps
	var result := from
	for index in steps:
		if not blocked(result + increment, zone):
			result += increment
		else:
			if not blocked(result + Vector2(increment.x, 0), zone):
				result.x += increment.x
			if not blocked(result + Vector2(0, increment.y), zone):
				result.y += increment.y
	return result

static func next_waypoint(from: Vector2, target: Vector2, zone: String = "concourse") -> Vector2:
	target = safe_position(target, zone)
	if can_travel(from, target, zone):
		return target
	var grid := _navigation(zone)
	var path := grid.get_point_path(_nearest_id(from, true, zone), _nearest_id(target, false, zone))
	var waypoint := from
	for point in path:
		if can_travel(from, point, zone):
			waypoint = point
		else:
			break
	return waypoint
