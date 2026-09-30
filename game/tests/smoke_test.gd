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
	_check(Progress.level == 1 and is_equal_approx(p.stats.max_hp, 500.0) and is_equal_approx(p.stats.max_mana, 100.0)
			and is_equal_approx(p.stats.attack_power, 22.0) and is_equal_approx(p.stats.defense, 5.0) and absf(p.stats.crit_chance - 0.15) < 0.005,
			"Lv 1 Warrior stats from STR/AGI/INT/VIT: HP 500, MP 100, ATK 22, DEF 5, crit 15%")
	if p == null:
		_finish()
		return
	_check(p.stats.combo.size() == 3, "3-hit combo loaded from data")
	_check(p.stats.skill_1 != null and p.stats.skill_2 != null, "2 skills loaded from data")

	await _frames(150)
	var enemies := _enemies()
	_check(enemies.size() == 3, "wave 1 spawned 3 enemies (got %d)" % enemies.size())
	var missing := PackedStringArray()
	for event in Sfx.EVENTS:
		for layer in Sfx.EVENTS[event]:
			if Sfx._banks.get(layer[0], []).is_empty():
				missing.append("%s/%s" % [event, layer[0]])
	_check(missing.is_empty(), "every sound event has samples (missing: %s)" % ", ".join(missing))
	_check(Sfx._music.playing and Sfx._ambience.playing, "battle music and ambience play after wave 1")
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
	var hud_ui: Hud = get_tree().get_first_node_in_group("hud")
	_check(hud_ui._slots[0]._cd_label.text != "", "skill bar shows the dash cooldown")
	_check(hud_ui._objective.text.contains("Musuh  3 / 3"), "top-right shows the enemy count (%s)" % hud_ui._objective.text.replace("\n", " | "))
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
	var hp_ui: Hud = get_tree().get_first_node_in_group("hud")
	# A fresh hit of our own: the enemy's hit above may already have drained its ghost.
	p._iframes = 0.0
	p.take_hit(40.0, p.global_position + p.facing, 0.0)
	await _frames(3)
	_check(hp_ui._hp_bar._ghost > hp_ui._hp_bar.fraction(), "HP bar keeps a ghost of the damage taken")

	var hp_before_pot := p.hp
	p.use_hp_potion()
	_check(p.hp > hp_before_pot and p.hp_potions == 4, "HP potion heals the player")
	_check(p.hp_potion_cd > 0.0, "HP potion has cooldown")
	p.mana = 20.0
	p.use_mp_potion()
	_check(p.mana > 20.0 and p.mp_potions == 4, "MP potion restores mana")

	# Clearing the wave starts the next one.
	for e in _enemies():
		e.set_physics_process(true)
		e.take_hit(1000000.0, false, p.stats.combo[0], p.global_position, p.facing)
	await _frames(240)
	var wave2 := _enemies()
	_check(wave2.size() == 5, "wave 2 spawned 5 enemies (got %d)" % wave2.size())
	_check(Progress.level == 1 and Progress.experience == 60, "defeating wave 1 gives 3 x 20 EXP (got %d)" % Progress.experience)
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
		ogre.hp = ogre.stats.max_hp * 0.6
		for e in wave2:
			e.hp = minf(e.hp, e.stats.max_hp * 0.8)
		await _frames(2)
		await _shot("05b_enemy_names")
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
		# The PNG is written on a worker thread: wait for it in real time, not frames.
		for i in 30:
			if png != "" and FileAccess.file_exists(png.get_basename() + ".txt"):
				break
			await get_tree().create_timer(0.1, true, false, true).timeout
		_check(png != "" and FileAccess.file_exists(png), "screenshot key saves a PNG")
		var note := FileAccess.get_file_as_string(png.get_basename() + ".txt")
		_check(note.contains("Pemain Warrior") and note.contains("Level:"), "screenshot saves a context note")

	# Level up: stats grow, HP and MP refill, the status window shows it, the save keeps it.
	var hp_max_before := p.stats.max_hp
	var atk_before := p.stats.attack_power
	p.hp = p.stats.max_hp * 0.5
	Progress.add_exp(Progress.exp_to_next(Progress.level) - Progress.experience)
	await _frames(10)
	_check(Progress.level == 2 and p.stats.max_hp > hp_max_before and p.stats.attack_power > atk_before,
			"level up raises the Warrior's stats (Lv %d, HP %d, ATK %d)" % [Progress.level, p.stats.max_hp, p.stats.attack_power])
	_check(is_equal_approx(p.hp, p.stats.max_hp), "level up refills HP")
	await _shot("10a_level_up")
	var status: StatusWindow = get_tree().current_scene.get_node("StatusWindow")
	var key_c := InputEventKey.new()
	key_c.physical_keycode = KEY_C
	key_c.pressed = true
	Input.parse_input_event(key_c)
	await _frames(3)
	_check(status.is_open() and status._values["Lv."].text == "2", "C opens the character window (Lv %s)" % status._values["Lv."].text)
	await _shot("10d_status")
	status.toggle()
	Progress.use_file("user://save_smoke_test.cfg")
	Progress.save_file()
	var saved_level := Progress.level
	var saved_exp := Progress.experience
	Progress.level = 1
	Progress.experience = 0
	Progress.load_file()
	_check(Progress.level == saved_level and Progress.experience == saved_exp, "level and EXP are saved and loaded back")

	# Items: gold and items on the floor are collected; equip, enhance, sell, save.
	var gold_before := Progress.gold
	var item_rng := RandomNumberGenerator.new()
	item_rng.seed = 7
	var sword := ItemDB.generate("weapon", 3, 2, item_rng)
	var drops: Array[Loot] = [Loot.spawn(p.global_position, 12, {}), Loot.spawn(p.global_position, 0, sword)]
	await _frames(30)
	for drop in drops:  # walk up to each drop (the player may still be sliding)
		if is_instance_valid(drop):
			p.velocity = Vector3.ZERO
			p.global_position = Vector3(drop.global_position.x, p.global_position.y, drop.global_position.z)
			await _frames(40)
	_check(Progress.gold >= gold_before + 12, "gold on the floor flies to the player and is collected")
	_check(sword.has("id") and not Inventory.find(int(sword.get("id", -1))).is_empty(), "an item on the floor goes into the inventory")
	var bag: InventoryWindow = get_tree().current_scene.get_node("InventoryWindow")
	var key_i := InputEventKey.new()
	key_i.physical_keycode = KEY_I
	key_i.pressed = true
	Input.parse_input_event(key_i)
	await _frames(3)
	_check(bag.is_open() and get_tree().paused, "I opens the inventory and pauses the game")
	var sword_id := int(sword.get("id", -1))
	bag.select(sword_id)
	await _shot("10e_inventory")
	var atk_plain := p.stats.attack_power
	bag.equip_selected()
	_check(Inventory.is_equipped(sword_id) and p.stats.attack_power > atk_plain,
			"equipping a sword raises ATK (%d -> %d)" % [atk_plain, p.stats.attack_power])
	Progress.gold = 1000
	var atk_equipped := p.stats.attack_power
	var result := bag.enhance_selected(0.0)
	_check(result == "ok" and int(Inventory.find(sword_id)["enhance"]) == 1 and p.stats.attack_power > atk_equipped,
			"enhance +1 succeeds and raises ATK (%d -> %d)" % [atk_equipped, p.stats.attack_power])
	var gold_mid := Progress.gold
	result = bag.enhance_selected(0.999)
	_check(result == "fail" and int(Inventory.find(sword_id)["enhance"]) == 1 and Progress.gold < gold_mid,
			"a failed enhance costs gold but the item stays +1")
	await _shot("10f_inventory_enhanced")
	Inventory.add(ItemDB.generate("armor", 2, 0, item_rng))
	var junk_id := int(Inventory.items.back()["id"])
	bag.select(junk_id)
	var gold_sell := Progress.gold
	bag.sell_selected()
	_check(Inventory.find(junk_id).is_empty() and Progress.gold > gold_sell, "selling an item gives gold")
	Progress.save_file()
	Inventory.items = []
	Inventory.equipped = {}
	Progress.load_file()
	_check(Inventory.is_equipped(sword_id) and int(Inventory.find(sword_id)["enhance"]) == 1,
			"equipment and enhancement are saved and loaded back")
	# Armor parts and the two ring slots.
	var def_before := p.stats.defense
	Inventory.add(ItemDB.generate("helmet", 5, 1, item_rng))
	Inventory.equip(int(Inventory.items.back()["id"]))
	_check(Inventory.equipped.has("helmet") and p.stats.defense > def_before, "a helmet goes in its own slot and adds DEF")
	var rings: Array[int] = []
	for r in 3:
		Inventory.add(ItemDB.generate("accessory", 5, 0, item_rng))
		rings.append(int(Inventory.items.back()["id"]))
		Inventory.equip(rings[r])
	_check(Inventory.equipped_slot(rings[1]) == "accessory_2" and Inventory.equipped_slot(rings[2]) == "accessory"
			and not Inventory.is_equipped(rings[0]), "two rings fill both ring slots; a third replaces the first")
	_check(ItemDB.icon(Inventory.equipped["helmet"]) != null and ItemDB.icon({}, "accessory_2") != null, "every slot has an icon")
	bag.close()
	await _frames(2)
	_check(not bag.is_open() and not get_tree().paused, "closing the inventory resumes the game")

	# A pillar between camera and player turns see-through; the camera does not snap in.
	var rig := Game.camera_rig
	var pillar_pos := Vector3(cos(TAU / 6.0), 0.0, sin(TAU / 6.0)) * Arena.PILLAR_RING
	var pillar: Node3D = null
	for v: Node3D in get_tree().get_nodes_in_group(CameraOcclusion.GROUP):
		if v.global_position.distance_to(pillar_pos) < 0.5:
			pillar = v
	_check(pillar != null, "pillars are registered as see-through pieces")
	for e in _enemies():
		e.set_physics_process(false)
		e.global_position = Vector3(-15.0, 0.0, -15.0)
	p.global_position = pillar_pos - Vector3(0.0, 0.0, 3.0)
	p.velocity = Vector3.ZERO
	rig._yaw = 0.0  # camera behind the player on +Z, looking through the pillar
	rig._pitch = -0.3
	rig._target_distance = 6.5
	rig.follow(p)
	await _frames(60)
	if pillar:
		_check(rig.occlusion.drawn_alpha(pillar) < 0.5, "a pillar blocking the view is drawn see-through (alpha %.2f)" % rig.occlusion.drawn_alpha(pillar))
	_check(rig._arm.get_hit_length() > 5.5, "the camera looks through the pillar instead of snapping in (%.1f m)" % rig._arm.get_hit_length())
	await _shot("10c_pillar_fade")
	rig._yaw = PI
	await _frames(60)
	if pillar:
		_check(rig.occlusion.drawn_alpha(pillar) >= 1.0, "the pillar turns solid again when it is out of the way")

	# Low HP: the screen edges glow red.
	var hp_keep := p.hp
	p.hp = p.stats.max_hp * 0.15
	await _frames(20)
	await _shot("10b_low_hp")
	p.hp = hp_keep

	# Esc menu and settings (saved to a scratch file, never the player's own).
	Settings.use_file("user://settings_smoke_test.cfg")
	var menu: SettingsMenu = get_tree().current_scene.get_node("SettingsMenu")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(3)
	_check(menu.is_open() and get_tree().paused, "Esc opens the menu and pauses the game")
	await _shot("11_menu")
	menu._show_page("controls")
	menu._start_listening(&"jump", 1)
	var key_f := InputEventKey.new()
	key_f.physical_keycode = KEY_F
	key_f.pressed = true
	Input.parse_input_event(key_f)
	await _frames(3)
	var jump_keys := InputMap.action_get_events(&"jump").map(func(e: InputEvent) -> String: return Settings.code_from_event(e))
	_check("key:%d" % KEY_F in jump_keys, "rebinding a key through the menu updates the controls")
	await _shot("12_controls")
	var taken := Settings.set_binding(&"skill_1", 0, "key:%d" % KEY_F)
	_check(taken == &"jump" and Settings.bindings[&"jump"][1] == "", "a key can only be bound to one action")
	Settings.set_mouse_sensitivity(1.7)
	Settings.set_volume(&"Music", 0.5)
	var music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	_check(absf(music_db - linear_to_db(0.5)) < 0.1, "music volume slider changes the Music bus")
	Settings.mouse_sensitivity = 1.0
	Settings.load_file()
	_check(is_equal_approx(Settings.mouse_sensitivity, 1.7) and Settings.bindings[&"skill_1"][0] == "key:%d" % KEY_F,
			"settings are saved and loaded back")
	menu._show_page("game")
	await _frames(2)
	await _shot("13_game")
	var hud: Hud = get_tree().get_first_node_in_group("hud")
	hud.toast("tes")
	await _frames(20)
	_check(hud._toast.modulate.a > 0.9, "messages still show while the menu pauses the game")
	Settings.reset_to_defaults()
	_check(Settings.key_name(&"screenshot") == "\\", "the screenshot key is shown as \\ (got %s)" % Settings.key_name(&"screenshot"))
	_check(Settings.bindings[&"jump"][0] == "key:%d" % KEY_SPACE and is_equal_approx(Settings.volumes[&"Music"], 1.0),
			"reset restores default keys and volumes")
	menu.close()
	await _frames(2)
	_check(not menu.is_open() and not get_tree().paused, "closing the menu resumes the game")
	var help_before := hud._help_open
	var f1 := InputEventKey.new()
	f1.physical_keycode = KEY_F1
	f1.pressed = true
	Input.parse_input_event(f1)
	await _frames(3)
	_check(hud._help_open != help_before, "F1 toggles the help line")

	# Multi-room & Boss & Reward Chest test:
	var main_scene: Main = get_tree().current_scene as Main
	_check(main_scene != null and main_scene.arena != null, "main scene and arena initialized")
	_check(main_scene.arena.gate_1.is_open, "clearing room 1 opens gate 1")
	_check(not main_scene.arena.gate_2.is_open, "gate 2 remains locked before room 2 clear")

	# Clear room 2 enemies:
	for e in _enemies():
		e.set_physics_process(true)
		e.take_hit(1000000.0, false, p.stats.combo[0], p.global_position, p.facing)
	await _frames(240)
	_check(main_scene.arena.gate_2.is_open, "clearing room 2 opens gate 2")
	_check(main_scene._boss != null, "room 3 spawns the boss")
	_check(main_scene._boss_bar != null, "boss health bar is displayed")

	# Defeat boss in room 3:
	for e in _enemies():
		e.set_physics_process(true)
		e.take_hit(1000000.0, false, p.stats.combo[0], p.global_position, p.facing)
	await _frames(60)

	var clear_ui: DungeonClearUI = null
	# The win screen comes 2 s after the last kill, slowed down by the slow-motion.
	for wait in 40:
		for child in hud.get_children():
			if child is DungeonClearUI:
				clear_ui = child
		if clear_ui:
			break
		await _frames(15)
	_check(clear_ui != null, "dungeon clear UI is shown with rank")
	_check(main_scene.arena.portal_node.visible, "exit portal appears after victory")

	# Find reward chests
	var chests: Array[RewardChest] = []
	for child in main_scene.get_children():
		if child is RewardChest:
			chests.append(child)
	_check(chests.size() == 4, "4 reward chests spawned in boss room (got %d)" % chests.size())
	_check(InputMap.has_action(&"interact"), "the interact key (F) exists")
	if chests.size() == 4:
		p.velocity = Vector3.ZERO
		p.global_position = chests[0].global_position + Vector3(0.0, 0.0, 1.8)
		await _frames(5)
		var key_f2 := InputEventKey.new()
		key_f2.physical_keycode = KEY_F
		key_f2.pressed = true
		Input.parse_input_event(key_f2)
		await _frames(3)
		var key_f2_up := key_f2.duplicate() as InputEventKey
		key_f2_up.pressed = false
		Input.parse_input_event(key_f2_up)
		await _frames(40)
		_check(chests[0].is_open, "pressing F next to a chest opens it and drops a reward")
		_check(chests[1].is_locked and chests[2].is_locked and chests[3].is_locked, "other 3 chests become locked")

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
