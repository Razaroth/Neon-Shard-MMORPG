extends RefCounted
## A shared connected texture mesh, with continuous hip/knee/foot/spine weights.
## This deforms a 2D skin; it is not a replacement for authored 3D skeletons.
const X_STEPS := 16
const Y_STEPS := 28
var rest := PackedVector2Array()
var uv := PackedVector2Array()
var indices := PackedInt32Array()
var meshes: Dictionary = {}
var skin_uv: Dictionary = {}
var skin_aspect: Dictionary = {}
var build_usec := 0
var build_count := 0

func _init() -> void:
	for y in Y_STEPS + 1:
		for x in X_STEPS + 1:
			var point := Vector2(float(x) / X_STEPS, float(y) / Y_STEPS)
			rest.append(point)
			uv.append(point / Vector2(6, 4))
	for y in Y_STEPS:
		for x in X_STEPS:
			var top := y * (X_STEPS + 1) + x
			indices.append_array(PackedInt32Array([top, top + 1, top + X_STEPS + 1, top + 1, top + X_STEPS + 2, top + X_STEPS + 1]))

func vertex(point: Vector2, pose: Dictionary) -> Vector2:
	var p := point
	var spine := 1.0 - smoothstep(0.15, 0.64, point.y)
	var legs := smoothstep(0.53, 0.91, point.y)
	var right := smoothstep(0.46, 0.57, point.x)
	# Preserve the weapon's rigid silhouette across the underlying leg weights.
	var weapon := 0.0
	if pose.archetype in ["vanguard", "ghost"]:
		var closest := Geometry2D.get_closest_point_to_segment(point, Vector2(0.5, 0.39), Vector2(0.89, 0.63))
		weapon = 1 - smoothstep(0.045, 0.09, point.distance_to(closest))
	legs *= 1 - weapon
	spine = lerpf(spine, 0.65, weapon)
	var feet: Vector2 = Vector2(pose.left_foot).lerp(pose.right_foot, right)
	p += feet * legs
	var knee := sin(clampf((point.y - 0.53) / 0.4, 0, 1) * PI)
	p.x += -feet.y * 0.30 * knee
	p.x += (float(pose.lean) - float(pose.recoil)) * spine
	p.y += float(pose.bob) * (1 - legs)
	p.y -= float(pose.breath) * 0.0035 * spine * (1 - float(pose.move) * 0.65)
	# Coat lag follows the stride with a smooth phase offset, strongest at the hem.
	var hem := smoothstep(0.5, 0.85, point.y) * (1 - smoothstep(0.23, 0.39, point.x))
	p.x += sin(float(pose.phase) * TAU - 0.8) * 0.018 * float(pose.move) * hem
	if pose.attacking:
		var t: float = clampf(pose.attack_t, 0, 1)
		if pose.archetype == "ronin":
			var slash := sin(t * PI) * 0.055
			p.x += slash * spine
			p.y -= slash * 0.25 * spine
		elif pose.archetype in ["cipher", "machinist"]:
			var hand := smoothstep(0.55, 0.80, point.x) * (1 - smoothstep(0.55, 0.7, point.y))
			p.x += sin(t * PI) * 0.018 * hand
			p.y -= sin(t * PI) * 0.015 * hand
	p.x = 0.5 + (p.x - 0.5) * float(pose.turn)
	return p

func bind_skin(role: String, region: Rect2, texture_size: Vector2) -> void:
	var coordinates := PackedVector2Array()
	for point in rest:
		coordinates.append((region.position + point * region.size) / texture_size)
	skin_uv[role] = coordinates
	skin_aspect[role] = region.size.x / region.size.y

func mesh_for(id: int, pose: Dictionary, height: float) -> ArrayMesh:
	var started := Time.get_ticks_usec()
	if not meshes.has(id):
		meshes[id] = ArrayMesh.new()
	var mesh: ArrayMesh = meshes[id]
	var vertices := PackedVector2Array()
	vertices.resize(rest.size())
	for i in rest.size():
		var transformed := vertex(rest[i], pose)
		var aspect: float = skin_aspect.get(pose.archetype, 1.0)
		transformed.x += (rest[i].x - 0.5) * (aspect - 1)
		vertices[i] = (transformed - Vector2(0.5, 1.0)) * height + Vector2(0, 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = skin_uv.get(pose.archetype, uv)
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	build_usec += Time.get_ticks_usec() - started
	build_count += 1
	return mesh

func retain(ids: Array) -> void:
	for id in meshes.keys():
		if not ids.has(id):
			meshes.erase(id)

func clear() -> void:
	meshes.clear()
