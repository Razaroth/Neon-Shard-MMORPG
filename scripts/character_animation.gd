extends RefCounted
## Six-frame clips, clocked per actor. Rendering never changes combat timing.
const Roles = preload("res://scripts/archetypes.gd")
const COLUMNS := 6
const ROWS := 4
const CLIPS := {"idle": {"row": 0, "fps": 5.0}, "walk": {"row": 1, "fps": 9.0}, "run": {"row": 2, "fps": 13.0}, "attack": {"row": 3, "fps": 12.0}}
var actors: Dictionary = {}

static func attack_duration(archetype: String) -> float:
	return minf(0.5, Roles.stats(archetype).cooldown * 0.9)

func sample(player: Dictionary, delta: float) -> Dictionary:
	var id := int(player.id)
	var serial := int(player.get("attack_serial", 0))
	var age := float(player.get("attack_age", 100.0))
	var duration := attack_duration(player.archetype)
	if not actors.has(id):
		actors[id] = {"clip": "", "clock": 0.0, "serial": serial, "attack_clock": age, "mirror": false}
	var actor: Dictionary = actors[id]
	actor.attack_clock = float(actor.attack_clock) + delta
	if serial != int(actor.serial):
		actor.serial = serial
		# Start at the server-observed age, avoiding replay after stalled snapshots.
		actor.attack_clock = age
	else:
		actor.attack_clock = maxf(float(actor.attack_clock), age)
	var facing: Vector2 = player.get("facing", Vector2(1, 0.5))
	if absf(facing.x) > 0.05:
		actor.mirror = facing.x < 0
	var clip := "idle"
	if player.get("moving", false):
		clip = "run" if player.get("running", false) else "walk"
	if serial > 0 and float(actor.attack_clock) < duration:
		clip = "attack"
	if clip != str(actor.clip):
		actor.clip = clip
		actor.clock = 0.0
	else:
		actor.clock = float(actor.clock) + delta
	var frame := int(float(actor.clock) * float(CLIPS[clip].fps)) % COLUMNS
	if clip == "attack":
		frame = clampi(int(float(actor.attack_clock) / duration * COLUMNS), 0, COLUMNS - 1)
	return {"archetype": player.archetype, "clip": clip, "frame": frame, "row": CLIPS[clip].row, "mirror": actor.mirror}

func retain(ids: Array) -> void:
	for id in actors.keys():
		if not ids.has(id):
			actors.erase(id)

func clear() -> void:
	actors.clear()

static func region(texture_size: Vector2, pose: Dictionary) -> Rect2:
	var size := texture_size / Vector2(COLUMNS, ROWS)
	var rect := Rect2(Vector2(pose.frame, pose.row) * size, size)
	# Generated attack effects can cross a cell edge. Exclude that outer band so
	# a neighboring frame's muzzle flash or blade cannot leak into this pose.
	if int(pose.row) == 3:
		rect.position.x += size.x * 0.125
		rect.size.x -= size.x * 0.25
		if pose.get("archetype", "") == "ronin" and int(pose.frame) == 5:
			rect.position.x += size.x * 0.125
			rect.size.x -= size.x * 0.125
	return rect
