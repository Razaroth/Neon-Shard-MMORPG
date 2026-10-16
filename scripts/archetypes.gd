extends RefCounted
## Original roles inspired by cyberpunk build styles; shared client/server data.
const ORDER := ["vanguard", "cipher", "ronin", "ghost", "machinist"]
const DATA := {
	"vanguard": {"name": "VANGUARD", "role": "Heavy weapons / frontline", "description": "Armored street enforcer. Slow, resilient, devastating up close.", "color": Color("ffad66"), "hp": 150, "speed": 125.0, "range": 105.0, "damage": 30, "cooldown": 0.65, "weapon": "BREACH CANNON"},
	"cipher": {"name": "CIPHER", "role": "Hacking / remote disruption", "description": "Network infiltrator. Reach rogue machines with a long-range pulse.", "color": Color("66f5e0"), "hp": 85, "speed": 150.0, "range": 230.0, "damage": 15, "cooldown": 0.5, "weapon": "NEURAL PULSE"},
	"ronin": {"name": "RONIN", "role": "Blades / reflexes", "description": "Augmented duelist. Close distance and strike at blistering speed.", "color": Color("ff5a95"), "hp": 100, "speed": 180.0, "range": 85.0, "damage": 20, "cooldown": 0.3, "weapon": "ARC BLADE"},
	"ghost": {"name": "GHOST", "role": "Precision / mobility", "description": "Rooftop marksman. Keep your distance and make every shot count.", "color": Color("b39bff"), "hp": 80, "speed": 170.0, "range": 280.0, "damage": 35, "cooldown": 0.9, "weapon": "RAIL CARBINE"},
	"machinist": {"name": "MACHINIST", "role": "Engineering / energy weapons", "description": "Scrapyard innovator. A balanced frame with a tuned induction rig.", "color": Color("83ceff"), "hp": 110, "speed": 145.0, "range": 170.0, "damage": 20, "cooldown": 0.45, "weapon": "INDUCTION RIG"}
}

static func valid(id: String) -> String:
	return id if DATA.has(id) else "ronin"

static func stats(id: String) -> Dictionary:
	return DATA[valid(id)]
