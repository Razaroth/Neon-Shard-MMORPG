extends RefCounted
## Artist-authored LPC frames. No deformation, anatomy interpolation or warping.
const Roles = preload("res://scripts/archetypes.gd")
const CELL := Vector2(64, 64)
const FOOT := Vector2(32, 60)
const VISIBLE_HEIGHT := 54.0
const COUNTS := {"walk": 9, "run": 8, "shoot": 13, "slash": 6, "spellcast": 7}
const SKINS := {
	"vanguard": {"body": "female", "pants": "thin", "hair": "half_up", "attack": "shoot", "shirt": Color(1.6, 0.82, 0.3), "hair_color": Color(0.35, 0.3, 0.35), "skin": Color(0.76, 0.61, 0.49)},
	"cipher": {"body": "male", "pants": "male", "hair": "halfmessy", "attack": "spellcast", "shirt": Color(0.3, 0.6, 0.63), "hair_color": Color(0.3, 0.3, 0.38), "skin": Color(1, 1, 1)},
	"ronin": {"body": "female", "pants": "thin", "hair": "ponytail2", "attack": "slash", "shirt": Color(0.65, 0.3, 0.55), "hair_color": Color(2.3, 2.7, 3.3), "skin": Color(1, 1, 1)},
	"ghost": {"body": "male", "pants": "male", "hair": "hood", "attack": "shoot", "shirt": Color(0.45, 0.35, 0.65), "hair_color": Color(0.45, 0.35, 0.65), "skin": Color(0.9, 0.9, 0.95)},
	"machinist": {"body": "female", "pants": "thin", "hair": "high_ponytail", "attack": "spellcast", "shirt": Color(0.3, 0.55, 0.9), "hair_color": Color(1.7, 0.6, 0.22), "skin": Color(1, 1, 1)}
}
var actors: Dictionary = {}

static func layers(role: String) -> Array:
	var skin: Dictionary = SKINS[Roles.valid(role)]
	var result: Array = []
	if skin.hair in ["ponytail2", "high_ponytail"]:
		result.append({"prefix": "hair/" + skin.hair + "/adult/bg", "color": skin.hair_color})
	result.append_array([
		{"prefix": "body/bodies/" + skin.body, "color": skin.skin},
		{"prefix": "head/heads/human/" + skin.body, "color": skin.skin},
		{"prefix": "legs/pants/" + skin.pants, "color": Color(0.3, 0.34, 0.42)},
		{"prefix": "feet/boots/basic/" + skin.pants, "color": Color(0.3, 0.32, 0.4)},
		{"prefix": "torso/clothes/longsleeve/longsleeve/" + skin.body, "color": skin.shirt},
		{"prefix": "torso/clothes/longsleeve/longsleeves/" + skin.body, "color": skin.shirt}
	])
	var hair: String = skin.hair
	var prefix := "hat/cloth/hood/adult" if hair == "hood" else "hair/" + hair + "/adult" + ("/fg" if hair in ["ponytail2", "high_ponytail"] else "")
	result.append({"prefix": prefix, "color": skin.hair_color})
	return result

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
		sheet = SKINS[player.archetype].attack
		frame = mini(int(COUNTS[sheet]) - 1, int(float(actor.attack_age) / duration * int(COUNTS[sheet])))
	actor.clip = clip
	return {"clip": clip, "sheet": sheet, "frame": frame, "view": actor.view, "mirror": false, "region": Rect2(Vector2(frame, actor.view) * CELL, CELL)}

func retain(ids: Array) -> void:
	for id in actors.keys():
		if not ids.has(id): actors.erase(id)

func clear() -> void:
	actors.clear()
