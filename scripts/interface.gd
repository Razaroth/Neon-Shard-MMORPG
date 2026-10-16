extends CanvasLayer

const Roles = preload("res://scripts/archetypes.gd")
var world: Node2D
var menu: Control
var game_hud: Control
var host: LineEdit
var slot_picker: OptionButton
var connect_button: Button
var status: Label
var hud: Label
var location: Label
var interaction: Label
var selected := "ronin"
var buttons: Dictionary = {}
var role_title: Label
var role_description: Label
var role_stats: Label
var portrait: Portrait

class Portrait extends Node2D:
	var selected := "ronin"
	var clock := 0.0
	var textures: Dictionary = {}
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var atlas: Texture2D = load("res://assets/portraits/characters-atlas.png")
		for index in Roles.ORDER.size():
			var texture := AtlasTexture.new()
			texture.atlas = atlas
			texture.region = Rect2(index * atlas.get_width() / 5.0, 0, atlas.get_width() / 5.0, atlas.get_height())
			texture.filter_clip = true
			textures[Roles.ORDER[index]] = texture
	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()
	func _draw() -> void:
		var accent: Color = Roles.stats(selected).color
		for i in 4:
			draw_arc(Vector2(0, -110), 110 + i * 16, clock * 0.05 + i, clock * 0.05 + i + 3.8, 60, Color(accent, 0.06 + i * 0.015), 1, true)
		draw_line(Vector2(-170, 12), Vector2(170, 12), Color(accent, 0.3), 1)
		if textures.has(selected):
			draw_texture_rect(textures[selected], Rect2(-115, -440, 230, 460), false)

func label(parent: Node, value: String, size: int, color: Color = Color("dfecf5")) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

func style(color: Color, border: Color, margin: int = 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func build(owner_world: Node2D) -> void:
	world = owner_world
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_stylebox("normal", "Button", style(Color("101b2c"), Color("2b3b50")))
	theme.set_stylebox("hover", "Button", style(Color("213548"), Color("62d7d1")))
	theme.set_stylebox("pressed", "Button", style(Color("28495a"), Color("92fff1")))
	theme.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), Color("71d8d0")))
	theme.set_stylebox("normal", "LineEdit", style(Color("0a1321"), Color("334457")))
	theme.set_color("font_color", "LineEdit", Color("c5dbe6"))
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.theme = theme
	add_child(menu)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.04, 0.075, 0.9)
	veil.position = Vector2(0, 0)
	veil.size = Vector2(520, 720)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(veil)
	var left := VBoxContainer.new()
	left.position = Vector2(40, 24)
	left.size = Vector2(434, 670)
	left.add_theme_constant_override("separation", 8)
	menu.add_child(left)
	label(left, "N / S     •     COMMUNITY WORLDS", 12, Color("6edfd2"))
	label(left, "NEON SHARD", 42)
	label(left, "EVERY EDGE HAS A PRICE", 17, Color("96aabd"))
	label(left, "An original cyberpunk frontier. Your server. Your story.", 12, Color("6f849e"))
	for id in Roles.ORDER:
		var data: Dictionary = Roles.stats(id)
		var button := Button.new()
		button.text = "%s    /    %s\n%s" % [data.name, data.weapon, data.role]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(434, 62)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func() -> void: choose(id))
		left.add_child(button)
		buttons[id] = button
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	left.add_child(slots)
	label(slots, "CHARACTER SLOT", 11, Color("7994aa"))
	slot_picker = OptionButton.new()
	for slot in 5:
		slot_picker.add_item("Slot %s" % (slot + 1))
	slot_picker.select(clampi(int(world.option("--slot", "1")) - 1, 0, 4))
	slots.add_child(slot_picker)
	label(left, "WORLD ADDRESS  /  UDP %s" % world.port, 11, Color("7994aa"))
	host = LineEdit.new()
	host.text = world.option("--host", "127.0.0.1")
	host.placeholder_text = "Server hostname or IP"
	left.add_child(host)
	connect_button = Button.new()
	connect_button.text = "ENTER DISTRICT   →"
	connect_button.custom_minimum_size.y = 42
	connect_button.pressed.connect(world._join)
	left.add_child(connect_button)
	status = label(left, "Existing slots restore their saved class. Five slots per server.", 11, Color("89a2b9"))
	var detail_background := Panel.new()
	detail_background.position = Vector2(735, 515)
	detail_background.size = Vector2(510, 180)
	detail_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_background.add_theme_stylebox_override("panel", style(Color(0.025, 0.045, 0.08, 0.92), Color("2b4053"), 0))
	menu.add_child(detail_background)
	var detail := VBoxContainer.new()
	detail.position = Vector2(755, 525)
	detail.size = Vector2(450, 165)
	detail.add_theme_constant_override("separation", 7)
	menu.add_child(detail)
	role_title = label(detail, "", 32)
	role_description = label(detail, "", 14)
	role_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_description.custom_minimum_size.x = 440
	role_stats = label(detail, "", 12, Color("95b1c5"))
	portrait = Portrait.new()
	portrait.position = Vector2(965, 470)
	menu.add_child(portrait)
	var sector := label(menu, "KAIRO EXCHANGE\nCONCOURSE / 09", 16, Color("b5d0db"))
	sector.position = Vector2(550, 40)
	choose(Roles.valid(world.option("--class", "ronin")))
	game_hud = Control.new()
	game_hud.theme = theme
	game_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud.hide()
	add_child(game_hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 504)
	panel.add_theme_stylebox_override("panel", style(Color(0.025, 0.05, 0.09, 0.93), Color("365365"), 18))
	game_hud.add_child(panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	panel.add_child(info)
	location = label(info, "N / S     KAIRO EXCHANGE", 15, Color("64e3d3"))
	hud = label(info, "Synchronizing district…", 14)
	var control_background := Panel.new()
	control_background.position = Vector2(300, 656)
	control_background.size = Vector2(700, 48)
	control_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_background.add_theme_stylebox_override("panel", style(Color(0.025, 0.045, 0.08, 0.92), Color("2b4053"), 0))
	game_hud.add_child(control_background)
	var controls := label(game_hud, "WASD WALK   SHIFT RUN   SPACE ATTACK   E INTERACT / TRAVEL   F8 EFFECTS", 12, Color("a6bbc9"))
	controls.position = Vector2(325, 674)
	interaction = label(game_hud, "", 17, Color("89f8e6"))
	interaction.position = Vector2(440, 617)
	var badge := label(game_hud, "COMMUNITY WORLD\nPRIVATE TEST BUILD", 12, Color("90a9c2"))
	badge.position = Vector2(1060, 28)

func choose(id: String) -> void:
	selected = Roles.valid(id)
	var data := Roles.stats(selected)
	for key in buttons:
		buttons[key].add_theme_stylebox_override("normal", style(Color("182c34") if key == selected else Color("101722"), data.color if key == selected else Color("29364b")))
		buttons[key].add_theme_color_override("font_color", data.color if key == selected else Color("9aadc0"))
	role_title.text = data.name + " / " + data.weapon
	role_title.add_theme_font_size_override("font_size", 25)
	role_title.modulate = data.color
	role_description.text = data.description
	role_stats.text = "VITALITY %s     MOBILITY %s     REACH %s units\nClass choice is permanent for this character." % [data.hp, int(data.speed), int(data.range)]
	portrait.selected = selected

func enter_world() -> void:
	menu.hide()
	game_hud.show()

func show_menu() -> void:
	menu.show()
	game_hud.hide()
