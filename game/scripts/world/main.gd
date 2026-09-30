class_name Main
extends Node3D
## Multi-room dungeon combat: manages room progression, doorway gates,
## enemy waves, the boss encounter with BossBar, dungeon clear evaluation,
## and Pick-a-Chest rewards.

const GRUNT := preload("res://data/enemies/grunt.tres")
const BRUTE := preload("res://data/enemies/brute.tres")
const MUSIC_BATTLE := "res://assets/audio/music/battle_determined_pursuit.ogg"
const AMBIENCE := "res://assets/audio/music/ambience_forgotten_tomb.ogg"

## Tiap gelombang: x = jumlah Tengkorak, y = jumlah Tengkorak Raksasa.
@export var waves: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 1), Vector2i(5, 2)]

var hud: Hud
var arena: Arena
var _wave := -1
var _alive := 0
var _finished := false
var _ogre_tip_shown := false
var _boss: Enemy
var _boss_bar: BossBar
var _start_time := 0.0
var _max_combo := 0
var _total_damage := 0.0
var _last_player_hp := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Engine.time_scale = 1.0
	_rng.randomize()
	_start_time = Time.get_ticks_msec() * 0.001
	Game.level = self
	Sfx.play_ambience(AMBIENCE)

	var effects := Node3D.new()
	effects.name = "Effects"
	effects.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(effects)
	Game.world = effects

	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	var player := Player.new()
	player.name = "Player"
	# Spawns at the beginning of Room 1 (facing forward toward -Z)
	player.position = Vector3(0.0, 0.1, 24.0)
	player.died.connect(_on_player_died)
	add_child(player)
	_last_player_hp = player.stats.max_hp

	var s := player.stats
	var attacks: Array[AttackData] = [s.heavy, s.air_heavy, s.skill_1, s.skill_2]
	attacks.append_array(s.combo)
	attacks.append_array(s.air_combo)
	Vfx.warm_up(player.position + Vector3(0.0, 1.0, -3.0), attacks, [GRUNT, BRUTE])
	_warm_up_enemy_models()

	var rig := CameraRig.new()
	add_child(rig)
	rig.follow(player)

	hud = Hud.new()
	add_child(hud)

	var status := StatusWindow.new()
	status.name = "StatusWindow"
	add_child(status)

	var menu := SettingsMenu.new()
	menu.name = "SettingsMenu"
	add_child(menu)

	var bag := InventoryWindow.new()
	bag.name = "InventoryWindow"
	add_child(bag)

	get_tree().create_timer(1.0).timeout.connect(_next_wave)


func _process(_delta: float) -> void:
	var p := Game.player
	if p and is_instance_valid(p):
		_max_combo = maxi(_max_combo, p.combo_hits)
		if _last_player_hp >= 0.0 and p.hp < _last_player_hp:
			_total_damage += (_last_player_hp - p.hp)
		_last_player_hp = p.hp


func _warm_up_enemy_models() -> void:
	var overlay := Vfx.overlay_material()
	var x := -1.5
	for stats: EnemyStats in [GRUNT, BRUTE]:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.position = Vector3(x, -3.0, 2.0)
		rig.setup(stats.model, overlay, {}, stats.model_scale, true)
		rig.play(stats.anim_idle, 0.0)
		if stats.weapon:
			rig.attach(stats.weapon.instantiate(), stats.weapon_bone, Transform3D.IDENTITY)
		get_tree().create_timer(0.8).timeout.connect(rig.queue_free)
		x += 3.0
	for drop: Dictionary in [{}, {"rarity": 3}]:
		var loot := Loot.new()
		loot.gold = 0 if drop else 1
		loot.item = drop
		Game.world.add_child(loot)
		loot.global_position = Vector3(x, -3.0, 2.0)
		loot.set_physics_process(false)
		get_tree().create_timer(0.8).timeout.connect(loot.queue_free)
		x += 1.5


func describe() -> String:
	var status := "selesai" if _finished else "berjalan"
	return "Level: gelombang %d/%d, musuh hidup %d, %s" % [maxi(_wave + 1, 0), waves.size(), _alive, status]


func _unhandled_input(event: InputEvent) -> void:
	if _finished and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _next_wave() -> void:
	if _finished:
		return
	_wave += 1
	if _wave >= waves.size():
		_win()
		return

	var wave := waves[_wave]
	var tip := ""
	if wave.y > 0 and not _ogre_tip_shown:
		_ogre_tip_shown = true
		tip = "Tips: hantaman kapak Tengkorak Raksasa bisa dihindari dengan lompat (Spasi)"

	var room_title := "Ruang 1: Penyusupan"
	if _wave == 1:
		room_title = "Ruang 2: Aula Utama"
	elif _wave == 2:
		room_title = "Ruang 3: Kubah Boss"

	hud.announce("%s (%d / %d)" % [room_title, _wave + 1, waves.size()], tip)
	Sfx.play("wave")
	if _wave == 0:
		Sfx.play_music(MUSIC_BATTLE)

	var points := _spawn_points(wave.x + wave.y)
	for i in points.size():
		var is_brute := i >= wave.x
		var stats := BRUTE if is_brute else GRUNT
		var is_boss_enemy := (_wave == waves.size() - 1 and is_brute and i == points.size() - 1)
		_spawn(stats, points[i], is_boss_enemy)


func _spawn_points(count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var center_z := 20.0 if _wave == 0 else (0.0 if _wave == 1 else -28.0)
	var radius := 5.0 if _wave == 0 else (8.0 if _wave == 1 else 9.5)
	var base := _rng.randf() * TAU
	for i in count:
		var a := base + TAU * i / count
		var r := _rng.randf_range(radius * 0.7, radius)
		var point := Vector3(cos(a) * r, 0.1, center_z + sin(a) * r * 0.6)
		points.append(point)
	return points


func _spawn(stats: EnemyStats, pos: Vector3, is_boss := false) -> void:
	var enemy := Enemy.new()
	if is_boss:
		var boss_stats: EnemyStats = stats.duplicate()
		boss_stats.display_name = "Panglima Tengkorak"
		boss_stats.max_hp = 1200.0
		boss_stats.size = 1.35
		boss_stats.attack_power = 35.0
		boss_stats.exp_reward = 150
		enemy.stats = boss_stats
		_boss = enemy
	else:
		enemy.stats = stats
	enemy.position = pos
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_alive += 1
	Vfx.ring(Vector3(pos.x, 0.05, pos.z), 1.6 * enemy.stats.size, Color(0.8, 0.35, 1.0, 0.8), 0.5)

	if is_boss:
		_boss_bar = BossBar.new()
		hud.add_child(_boss_bar)
		_boss_bar.set_boss(enemy, "PANGLIMA TENGKORAK KUNO")


func _on_enemy_died(enemy: Enemy) -> void:
	_alive -= 1
	if not _finished:
		Progress.add_exp(enemy.stats.exp_reward)
		Vfx.float_text(enemy.global_position + Vector3.UP * (enemy.bar_height + 0.6),
				"+%d EXP" % enemy.stats.exp_reward, Color(0.8, 0.7, 1.0), 0.8)
		Loot.drop_for(enemy.stats, enemy.global_position)

	if _alive <= 0 and not _finished:
		Game.slow_motion(0.25, 0.6)
		# Open respective gates based on cleared room
		if _wave == 0 and arena and arena.gate_1:
			arena.gate_1.open()
			hud.announce("Area 1 Bersih!", "Gerbang 1 Terbuka! Silakan maju ke Aula Utama")
		elif _wave == 1 and arena and arena.gate_2:
			arena.gate_2.open()
			hud.announce("Area 2 Bersih!", "Pintu Ruang Boss Terbuka! Bersiaplah")
		get_tree().create_timer(2.0).timeout.connect(_next_wave)


func _on_player_died() -> void:
	if _finished:
		return
	_finished = true
	Sfx.stop_music()
	hud.show_result("KALAH", "Tekan R untuk coba lagi", Color(1.0, 0.4, 0.35))


func _win() -> void:
	_finished = true
	Progress.on_dungeon_cleared()
	Sfx.stop_music()
	Sfx.play("wave")
	if arena and arena.gate_2:
		arena.gate_2.open(true)

	var clear_time := (Time.get_ticks_msec() * 0.001) - _start_time
	var clear_ui := DungeonClearUI.new(clear_time, _max_combo, _total_damage)
	hud.add_child(clear_ui)

	# Spawn Pick-a-Chest in Room 3
	_spawn_chests()
	# Reveal Exit Portal
	if arena:
		arena.show_portal()


func _spawn_chests() -> void:
	var xs := [-4.5, -1.5, 1.5, 4.5]
	var chests: Array[RewardChest] = []
	for i in xs.size():
		var chest := RewardChest.new()
		chest.chest_index = i
		chest.position = Vector3(xs[i], 0.1, -34.0)
		chest.rotation.y = deg_to_rad(180.0)
		add_child(chest)
		chests.append(chest)
		chest.picked.connect(func(picked_chest: RewardChest):
			for other in chests:
				if other != picked_chest:
					other.lock_and_fade()
			hud.toast("Peti Hadiah Berhasil Diambil! Masuki Portal untuk keluar")
		)
