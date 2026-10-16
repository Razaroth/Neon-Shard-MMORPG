extends RefCounted
## Server-owned room destinations. Clients request interaction, never a destination.
const IDS := ["concourse", "maintenance"]
const DATA := {
	"concourse": {"name": "KAIRO EXCHANGE", "art": "res://assets/interiors/kairo-concourse.png", "door": Vector2(1420, 440), "arrival": Vector2(1330, 550), "target": "maintenance", "link_name": "MAINTENANCE BAY"},
	"maintenance": {"name": "MAINTENANCE BAY", "art": "res://assets/interiors/maintenance-bay.png", "door": Vector2(280, 260), "arrival": Vector2(430, 410), "target": "concourse", "link_name": "KAIRO EXCHANGE"}
}

static func valid(id: String) -> String:
	return id if DATA.has(id) else "concourse"

static func info(id: String) -> Dictionary:
	return DATA[valid(id)]
