extends RefCounted
## A shared connected texture mesh, with continuous hip/knee/foot/spine weights.
## This deforms a 2D skin; it is not a replacement for authored 3D skeletons.
const X_STEPS := 16
const Y_STEPS := 28
# Hip, knee and sole anchors registered to each stable class skin.
const JOINTS := {
	"vanguard": [[Vector2(0.48,0.56), Vector2(0.39,0.74), Vector2(0.34,0.94)], [Vector2(0.59,0.56), Vector2(0.62,0.73), Vector2(0.65,0.91)]],
	"cipher": [[Vector2(0.44,0.55), Vector2(0.37,0.75), Vector2(0.33,0.94)], [Vector2(0.56,0.55), Vector2(0.57,0.75), Vector2(0.62,0.90)]],
	"ronin": [[Vector2(0.44,0.49), Vector2(0.32,0.72), Vector2(0.28,0.94)], [Vector2(0.57,0.49), Vector2(0.61,0.69), Vector2(0.70,0.86)]],
	"ghost": [[Vector2(0.46,0.57), Vector2(0.35,0.75), Vector2(0.31,0.94)], [Vector2(0.57,0.57), Vector2(0.62,0.73), Vector2(0.65,0.89)]],
	"machinist": [[Vector2(0.46,0.55), Vector2(0.38,0.74), Vector2(0.34,0.94)], [Vector2(0.58,0.55), Vector2(0.64,0.73), Vector2(0.67,0.90)]]
}
var rest := PackedVector2Array()
var uv := PackedVector2Array()
var indices := PackedInt32Array()
var meshes: Dictionary = {}
var skin_uv: Dictionary = {}
var skin_aspect: Dictionary = {}
var binding_cache: Dictionary = {}
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

static func solve_leg(hip: Vector2, knee: Vector2, ankle: Vector2, target: Vector2, hip_shift: Vector2) -> Dictionary:
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var new_hip := hip + hip_shift
	var direction := new_hip.direction_to(target)
	if direction.is_zero_approx():
		direction = hip.direction_to(ankle)
	var distance := clampf(new_hip.distance_to(target), absf(upper - lower) + 0.00001, upper + lower - 0.00001)
	var adjacent := (upper * upper + distance * distance - lower * lower) / (2 * distance)
	var perpendicular := Vector2(-direction.y, direction.x)
	var bind_perp := Vector2(-(ankle - hip).y, (ankle - hip).x).normalized()
	var bend := -1.0 if (knee - hip).dot(bind_perp) < 0 else 1.0
	var new_knee := new_hip + direction * adjacent + perpendicular * sqrt(maxf(0, upper * upper - adjacent * adjacent)) * bend
	var new_ankle := new_hip + direction * distance
	return {"hip": hip, "knee": knee, "ankle": ankle, "new_hip": new_hip, "new_knee": new_knee, "new_ankle": new_ankle, "thigh_angle": (new_knee - new_hip).angle() - (knee - hip).angle(), "shin_angle": (new_ankle - new_knee).angle() - (ankle - knee).angle(), "thigh_transform": Transform2D((new_knee - new_hip).angle() - (knee - hip).angle(), new_hip) * Transform2D(0, -hip), "shin_transform": Transform2D((new_ankle - new_knee).angle() - (ankle - knee).angle(), new_knee) * Transform2D(0, -knee)}

func prepare(pose: Dictionary) -> void:
	if pose.has("bones"):
		return
	var aspect: float = skin_aspect.get(pose.archetype, 1.0)
	var joints: Array = JOINTS[pose.archetype]
	var bones: Array = []
	var shift := Vector2(pose.sway, float(pose.crouch) + float(pose.bob))
	for index in 2:
		var bind: Array = joints[index]
		var hip := Vector2((bind[0].x - 0.5) * aspect + 0.5, bind[0].y)
		var knee := Vector2((bind[1].x - 0.5) * aspect + 0.5, bind[1].y)
		var ankle := Vector2((bind[2].x - 0.5) * aspect + 0.5, bind[2].y)
		var offset: Vector2 = pose.left_foot if index == 0 else pose.right_foot
		bones.append(solve_leg(hip, knee, ankle, ankle + offset, shift))
	pose.bones = bones
	var gun: bool = pose.archetype in ["vanguard", "ghost"]
	var left_angle: float = pose.arm_swing * (0.12 if gun else 0.25 if pose.archetype == "ronin" else 0.8)
	var right_angle: float = -pose.arm_swing * (0.12 if gun else 0.9 if pose.archetype == "ronin" else 0.25)
	pose.left_arm_transform = Transform2D(left_angle, Vector2(0.38, 0.29)) * Transform2D(0, Vector2(-0.38, -0.29))
	pose.right_arm_transform = Transform2D(right_angle, Vector2(0.64, 0.29)) * Transform2D(0, Vector2(-0.64, -0.29))

func leg_vertex(point: Vector2, bone: Dictionary, knee_weight: float, boot_weight: float) -> Vector2:
	var thigh: Vector2 = bone.thigh_transform * point
	var shin: Vector2 = bone.shin_transform * point
	var result := thigh.lerp(shin, knee_weight)
	# Boots keep their bind orientation at contact instead of rotating with shins.
	var boot: Vector2 = bone.new_ankle + point - Vector2(bone.ankle)
	return result.lerp(boot, boot_weight)

func weights_for(point: Vector2, role: String) -> PackedFloat32Array:
	if not binding_cache.has(role):
		binding_cache[role] = {}
	var cache: Dictionary = binding_cache[role]
	if cache.has(point):
		return cache[point]
	var aspect: float = skin_aspect.get(role, 1.0)
	var spine := 1.0 - smoothstep(0.15, 0.64, point.y)
	var legs := smoothstep(0.54, 0.70, point.y)
	var right := smoothstep(0.46, 0.57, point.x)
	var weapon := 0.0
	if role in ["vanguard", "ghost"]:
		var closest := Geometry2D.get_closest_point_to_segment(point, Vector2(0.5, 0.39), Vector2(0.89, 0.63))
		weapon = 1 - smoothstep(0.045, 0.09, point.distance_to(closest))
	legs *= 1 - weapon
	spine = lerpf(spine, 0.65, weapon)
	var arm_gate := smoothstep(0.20, 0.29, point.y) * (1 - smoothstep(0.53, 0.64, point.y))
	var hem := smoothstep(0.5, 0.85, point.y) * (1 - smoothstep(0.23, 0.39, point.x))
	var joints: Array = JOINTS[role]
	var values := PackedFloat32Array([spine, legs, right, weapon, (1 - smoothstep(0.25, 0.42, point.x)) * arm_gate, smoothstep(0.59, 0.75, point.x) * arm_gate, hem, (point.x - 0.5) * aspect + 0.5, smoothstep(joints[0][1].y - 0.04, joints[0][1].y + 0.04, point.y), smoothstep(joints[0][2].y - 0.075, joints[0][2].y - 0.025, point.y), smoothstep(joints[1][1].y - 0.04, joints[1][1].y + 0.04, point.y), smoothstep(joints[1][2].y - 0.075, joints[1][2].y - 0.025, point.y)])
	cache[point] = values
	return values

func vertex(point: Vector2, pose: Dictionary) -> Vector2:
	prepare(pose)
	var p := point
	var weights := weights_for(point, str(pose.archetype))
	var physical := Vector2(weights[7], point.y)
	var spine: float = weights[0]
	var legs: float = weights[1]
	var right: float = weights[2]
	var weapon: float = weights[3]
	var left := leg_vertex(physical, pose.bones[0], weights[8], weights[9])
	var other := leg_vertex(physical, pose.bones[1], weights[10], weights[11])
	p += (left.lerp(other, right) - physical) * legs
	p += Vector2(pose.sway, float(pose.crouch) + float(pose.bob)) * (1 - legs)
	# Counter-swing at the shoulders, reduced on hands carrying weapons/devices.
	var left_arm: float = weights[4]
	var right_arm: float = weights[5]
	var left_arm_transform: Transform2D = pose.left_arm_transform
	var right_arm_transform: Transform2D = pose.right_arm_transform
	p += (left_arm_transform * point - point) * left_arm * (1 - weapon)
	p += (right_arm_transform * point - point) * right_arm * (1 - weapon)
	p.x += (float(pose.lean) - float(pose.recoil)) * spine
	p.y -= float(pose.breath) * 0.0035 * spine * (1 - float(pose.move) * 0.65)
	# Coat lag follows the stride with a smooth phase offset, strongest at the hem.
	var hem: float = weights[6]
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
	binding_cache.erase(role)
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
