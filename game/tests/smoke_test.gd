extends Node
## Automated smoke test for the combat prototype. Game adds this node when
## the "--smoke-test" user argument is given.
##   Headless:    Godot --headless --path game --fixed-fps 60 -- --smoke-test
##   Screenshots: Godot --path game --fixed-fps 60 -- --smoke-test --shots=C:/some/folder

var _failures: Array[String] = []
var _shots := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	_run()


func _run() -> void:
	print("== darago smoke test ==")
	await _frames(5)
	var p := Game.player
	_check(p != null, "player spawned")
	if p == null:
		_finish()
		return
	_check(p.stats.combo.size() == 3, "3-hit combo loaded from data")
	_check(p.stats.skill_1 != null and p.stats.skill_2 != null, "2 skills loaded from data")

	await _frames(150)
	var enemies := _enemies()
	_check(enemies.size() == 3, "wave 1 spawned 3 enemies (got %d)" % enemies.size())
	await _shot("01_wave1")
	if enemies.size() < 3:
		_finish()
		return

	# Freeze enemies and park them so each check is deterministic.
	for i in enemies.size():
		enemies[i].set_physics_process(false)
		enemies[i].global_position = Vector3(-15.0 + i * 3.0, 0.0, -15.0)
	var front := enemies[0]
	var back := enemies[1]
	var attacker := enemies[2]
	front.hp = 100000.0
	front.global_position = p.global_position + p.facing * 2.0
	back.global_position = p.global_position - p.facing * 2.0
	await _frames(2)

	var front_hp := front.hp
	var back_hp := back.hp
	p.request_action(&"attack")
	await _frames(13)
	await _shot("02a_trail")
	await _frames(2)
	_check(front.hp < front_hp, "basic attack damages the enemy in front")
	_check(back.hp == back_hp, "basic attack misses the enemy behind")
	p.request_action(&"attack")
	await _frames(18)
	p.request_action(&"attack")
	await _frames(12)
	await _shot("02_combo_finisher")
	_check(p._combo_index == 2, "combo chains to the 3rd hit (index %d)" % p._combo_index)
	await _frames(40)
	back.global_position = Vector3(-10.0, 0.0, -15.0)

	# Dodge: moves, grants i-frames.
	var start := p.global_position
	p.set_move_input(Vector2(1.0, 0.0))
	p.request_action(&"dodge")
	await _frames(3)
	_check(p.state == Player.State.DODGE, "dodge starts")
	_check(not p.take_hit(10.0, p.global_position + Vector3(0.0, 0.0, -1.0), 5.0), "dodge i-frames block damage")
	await _frames(5)
	await _shot("09_dodge")
	await _frames(25)
	p.set_move_input(Vector2.ZERO)
	var moved := p.global_position.distance_to(start)
	_check(moved > 3.5, "dodge moves the player (%.1f m)" % moved)
	await _frames(20)
	# Running seen from the game camera (sword carried, trailing).
	p.set_move_input(Vector2(0.0, -1.0))
	await _frames(24)
	await _shot("10_run")
	p.set_move_input(Vector2.ZERO)
	await _frames(20)

	# Dash skill: costs mana, goes on cooldown, cannot be spammed.
	p.mana = p.stats.max_mana
	front.global_position = p.global_position + p.facing * 3.0
	await _frames(1)
	front_hp = front.hp
	var mana_before := p.mana
	p.request_action(&"skill_1")
	await _frames(4)
	_check(p.state == Player.State.ATTACK and p._is_skill, "dash skill starts")
	_check(p.mana <= mana_before - 19.0, "dash skill costs mana")
	_check(p.skill_cooldowns[0] > 4.0, "dash skill goes on cooldown")
	await _frames(30)
	_check(front.hp < front_hp, "dash skill damages the enemy on its path")
	await _frames(20)
	var mana_mid := p.mana
	p.request_action(&"skill_1")
	await _frames(3)
	_check(p.mana >= mana_mid - 1.0 and not (p.state == Player.State.ATTACK and p._is_skill),
			"skill on cooldown cannot be reused")
	await _frames(20)

	# Whirl skill: multi-hit around the player.
	p.mana = p.stats.max_mana
	front.global_position = p.global_position + p.facing * 1.5
	await _frames(1)
	front_hp = front.hp
	p.request_action(&"skill_2")
	await _frames(22)
	await _shot("03_whirl")
	await _frames(30)
	_check(front.hp < front_hp, "whirl skill damages nearby enemies")
	await _frames(40)

	# Jump, then an air attack.
	var ground_y := p.global_position.y
	p.request_action(&"jump")
	await _frames(12)
	_check(p.global_position.y > ground_y + 0.8, "jump lifts the player (%.2f m)" % (p.global_position.y - ground_y))
	p.request_action(&"attack")
	await _frames(3)
	_check(p.state == Player.State.ATTACK and p._attack == p.stats.air_combo[0], "left click in the air uses the air combo")
	await _frames(2)
	await _shot("06_air_attack")
	await _frames(88)
	_check(p.is_on_floor() and p.state == Player.State.FREE, "player lands and recovers after an air attack")

	# Right click heavy attack launches a light enemy.
	front.state = Enemy.State.CHASE
	front.global_position = p.global_position + p.facing * 2.0
	await _frames(2)
	front_hp = front.hp
	p.request_action(&"heavy")
	await _frames(16)
	await _shot("07_heavy")
	await _frames(9)
	_check(p._attack == p.stats.heavy, "right click uses the heavy attack")
	_check(front.hp < front_hp and front.state == Enemy.State.AIRBORNE, "heavy attack damages and launches")
	await _frames(40)

	# Right click in the air: plunge that hits on landing.
	front.state = Enemy.State.CHASE
	front.global_position = p.global_position + p.facing * 1.5
	await _frames(2)
	front_hp = front.hp
	p.request_action(&"jump")
	await _frames(14)
	p.request_action(&"heavy")
	await _frames(4)
	_check(p._attack == p.stats.air_heavy, "right click in the air uses the plunge")
	await _frames(9)
	await _shot("08_plunge")
	await _frames(51)
	_check(front.hp < front_hp, "plunge hits on landing")
	await _frames(30)

	# Double-tapping a direction dodges that way (Dragon Nest style).
	p._on_direction_tapped(Vector2(-1.0, 0.0), 100.0)
	p._on_direction_tapped(Vector2(-1.0, 0.0), 100.1)
	await _frames(3)
	var left := Basis(Vector3.UP, Game.camera_rig.yaw()) * Vector3.LEFT
	_check(p.state == Player.State.DODGE and p._dodge_dir.dot(left) > 0.9, "double-tap left dodges left")
	await _frames(40)
	p._on_direction_tapped(Vector2(1.0, 0.0), 200.0)
	p._on_direction_tapped(Vector2(1.0, 0.0), 200.6)
	await _frames(3)
	_check(p.state != Player.State.DODGE, "slow double-tap does not dodge")
	await _frames(20)

	# Enemy attack: telegraph, then damage.
	front.global_position = Vector3(-15.0, 0.0, -15.0)
	await _frames(2)
	p._iframes = 0.0
	attacker.global_position = p.global_position + p.facing * 1.5
	attacker._attack_cd = 0.0
	attacker.set_physics_process(true)
	var player_hp := p.hp
	await _frames(25)
	await _shot("04_telegraph")
	await _frames(45)
	_check(p.hp < player_hp, "enemy attack damages the player")

	# Clearing the wave starts the next one.
	for e in _enemies():
		e.set_physics_process(true)
		e.take_hit(1000000.0, false, p.stats.combo[0], p.global_position, p.facing)
	await _frames(240)
	var wave2 := _enemies()
	_check(wave2.size() == 5, "wave 2 spawned 5 enemies (got %d)" % wave2.size())
	await _frames(40)
	await _shot("05_wave2")

	# The giant skeleton ground slam misses a jumping player but hits a grounded one.
	var ogre: Enemy = null
	for e in wave2:
		e.set_physics_process(false)
		if e.stats.ground_only:
			ogre = e
	_check(ogre != null, "wave 2 contains a giant skeleton")
	if ogre:
		for i in wave2.size():
			wave2[i].global_position = Vector3(-15.0 + i * 3.0, 0.0, 15.0)
		ogre.global_position = p.global_position + p.facing * 2.0
		ogre._face_instant(p.global_position - ogre.global_position)
		await _frames(30)
		p._iframes = 0.0
		var hp_before := p.hp
		p.request_action(&"jump")
		await _frames(15)
		ogre._perform_attack()
		_check(p.hp == hp_before, "jumping avoids the giant skeleton ground slam")
		await _frames(90)
		p._iframes = 0.0
		hp_before = p.hp
		ogre._perform_attack()
		_check(p.hp < hp_before, "giant skeleton ground slam hits a grounded player")

	# The "\" screenshot feature (needs a real renderer; skipped headless).
	if _shots != "":
		var png: String = await Screenshot.capture(_shots.path_join("feature"))
		await _frames(30)  # the PNG is written on a worker thread
		_check(png != "" and FileAccess.file_exists(png), "screenshot key saves a PNG")
		var note := FileAccess.get_file_as_string(png.get_basename() + ".txt")
		_check(note.contains("Pemain Warrior") and note.contains("Level:"), "screenshot saves a context note")
	_finish()


func _enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		out.append(node as Enemy)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _shot(shot_name: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(shot_name + ".png"))
	print("  shot  " + shot_name)


func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
	else:
		print("SMOKE TEST FAILED: %d check(s)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
