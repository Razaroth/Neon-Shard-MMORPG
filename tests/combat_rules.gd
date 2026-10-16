extends SceneTree

func _init() -> void:
	var combat = preload("res://scripts/combat.gd").new()
	var player := {"position": Vector2(-700, 0), "input": Vector2.ZERO}
	combat.prepare(player, {})
	player.attacking = true
	var players := {2: player}
	combat.step(0.01, players)
	assert(combat.enemies[0].hp == 60, "Out of range attacks must miss")
	player.position = Vector2(180, 0)
	combat.step(0.5, players)
	assert(combat.enemies[0].hp == 40)
	for i in 10:
		combat.step(0.001, players)
	assert(combat.enemies[0].hp == 40, "Rapid requests must not bypass cooldown")
	combat.step(0.5, players)
	combat.step(0.5, players)
	assert(combat.enemies[0].hp == 0)
	assert(player.scrap == 1 and player.kills == 1)
	assert(not combat.interact(player), "Incomplete contracts cannot pay out")
	player.kills = 3
	player.position = Vector2(700, 0)
	assert(not combat.interact(player), "Remote turn-in must fail")
	player.position = Vector2.ZERO
	assert(combat.interact(player))
	assert(not combat.interact(player), "Contract reward cannot be duplicated")
	assert(player.credits == 100)
	player.attacking = false
	player.position = Vector2(1000, 1000)
	combat.step(10.1, players)
	assert(combat.enemies[0].hp == 60, "Drones must respawn")
	player.hp = 1
	player.position = combat.enemies[0].position
	combat.step(1.1, players)
	assert(player.hp == 100 and player.position == Vector2.ZERO, "Defeat must return players to sanctuary")
	var returning := {}
	combat.prepare(returning, {"hp": 42, "scrap": 3, "credits": 100, "kills": 3, "rewarded": true})
	assert(returning.hp == 42 and returning.rewarded and returning.credits == 100, "Rejoining must preserve health and contract progress")
	print("COMBAT_RULES_OK range, cooldown, loot, rewards, respawn, defeat")
	quit()
