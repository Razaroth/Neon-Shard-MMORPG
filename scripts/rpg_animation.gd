extends RefCounted
## Original cyberpunk identities redrawn as frame-based RPG sprites.
const Roles = preload("res://scripts/archetypes.gd")
const VISIBLE_HEIGHT := 54.0
const COUNTS := {"walk": 9, "run": 8, "attack": 6}
var actors: Dictionary = {}

func sample(player: Dictionary, delta: float) -> Dictionary:
	var id := int(player.id)
	var age := float(player.get("attack_age", 100.0))
	var serial := int(player.get("attack_serial", 0))
	if not actors.has(id):
		actors[id] = {"position": player.position, "phase": 0.0, "serial": serial, "attack_age": age, "view": 2, "clip": "idle"}
	var actor: Dictionary = actors[id]
	var distance: float = Vector2(actor.position).distance_to(player.position)
	actor.position = player.position
	actor.attack_age = float(actor.attack_age) + delta
	if serial != int(actor.serial):
		actor.serial = serial
		actor.attack_age = age
	else:
		actor.attack_age = maxf(float(actor.attack_age), age)
	var facing: Vector2 = player.get("facing", Vector2(1, 0.5))
	if facing.length_squared() > 0.01:
		var side_view: bool = int(actor.view) in [1, 3]
		if absf(facing.x) > absf(facing.y) * (0.85 if side_view else 1.2):
			actor.view = 3 if facing.x > 0 else 1
		else:
			actor.view = 2 if facing.y > 0 else 0
	var moving: bool = player.get("moving", false)
	var running: bool = player.get("running", false)
	var duration := minf(0.6, float(Roles.stats(player.archetype).cooldown) * 0.9)
	var attacking := serial > 0 and float(actor.attack_age) < duration
	var clip := "attack" if attacking else "run" if moving and running else "walk" if moving else "idle"
	if moving and distance < 120:
		actor.phase = fposmod(float(actor.phase) + distance / (82.0 if running else 78.0), 1.0)
	var sheet := "walk"
	var frame := 0
	if clip == "walk": frame = 1 + int(float(actor.phase) * 8) % 8
	elif clip == "run":
		sheet = "run"
		frame = int(float(actor.phase) * 8) % 8
	elif clip == "attack":
		sheet = "attack"
		frame = mini(int(COUNTS[sheet]) - 1, int(float(actor.attack_age) / duration * int(COUNTS[sheet])))
	actor.clip = clip
	return {"clip": clip, "sheet": sheet, "frame": frame, "view": actor.view, "mirror": clip == "attack" and int(actor.view) == 1 and player.archetype in ["vanguard", "cipher", "ghost", "machinist"]}

func retain(ids: Array) -> void:
	for id in actors.keys():
		if not ids.has(id): actors.erase(id)

func clear() -> void:
	actors.clear()

static func region(_texture_size: Vector2, pose: Dictionary, layout: Dictionary) -> Rect2:
	var frame: Array = layout.frames[int(pose.view)][int(pose.frame)].rect
	return Rect2(Vector2(frame[0], frame[1]), Vector2(frame[2], frame[3]))
