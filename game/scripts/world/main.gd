extends Node3D
## Combat prototype: builds the arena, spawns enemy waves and handles
## win / lose / restart.

const GRUNT := preload("res://data/enemies/grunt.tres")
const BRUTE := preload("res://data/enemies/brute.tres")
const MUSIC_BATTLE := "res://assets/audio/music/battle_determined_pursuit.ogg"
const AMBIENCE := "res://assets/audio/music/ambience_forgotten_tomb.ogg"

## Tiap gelombang: x = jumlah Tengkorak, y = jumlah Tengkorak Raksasa.
@export var waves: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 1), Vector2i(5, 2)]

var hud: Hud
var _wave := -1
var _alive := 0
var _finished := false
var _ogre_tip_shown := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Engine.time_scale = 1.0
	_rng.randomize()
	Game.level = self
	Sfx.play_ambience(AMBIENCE)
	var effects := Node3D.new()
	effects.name = "Effects"
	effects.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(effects)
	Game.world = effects
	add_child(Arena.new())
	var player := Player.new()
	player.name = "Player"
	player.position = Vector3(0.0, 0.1, 5.0)
	player.died.connect(_on_player_died)
	add_child(player)
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
	add_child(bag)  # after the menu: it sees Esc first and closes itself
	get_tree().create_timer(1.0).timeout.connect(_next_wave)


## Draws each enemy model once under the floor (still inside the camera view)
## during the quiet first second: the GPU's first draw of a new model stalled
## a frame by ~50 ms when the wave appeared (measured).
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
	# Same for the loot shapes (coin, item box, light beam).
	for drop: Dictionary in [{}, {"rarity": 3}]:
		var loot := Loot.new()
		loot.gold = 0 if drop else 1
		loot.item = drop
		Game.world.add_child(loot)
		loot.global_position = Vector3(x, -3.0, 2.0)
		loot.set_physics_process(false)  # never collected
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
	hud.announce("Gelombang %d / %d" % [_wave + 1, waves.size()], tip)
	Sfx.play("wave")
	if _wave == 0:
		Sfx.play_music(MUSIC_BATTLE)
	var points := _spawn_points(wave.x + wave.y)
	for i in points.size():
		_spawn(GRUNT if i < wave.x else BRUTE, points[i])


func _spawn_points(count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var base := _rng.randf() * TAU
	var player_pos := Game.player.global_position if Game.player else Vector3.ZERO
	for i in count:
		var a := base + TAU * i / count
		var r := _rng.randf_range(12.0, 15.5)
		var point := Vector3(cos(a) * r, 0.1, sin(a) * r)
		if point.distance_to(player_pos) < 6.0:
			point = Vector3(-point.x, point.y, -point.z)
		points.append(point)
	return points


func _spawn(stats: EnemyStats, pos: Vector3) -> void:
	var enemy := Enemy.new()
	enemy.stats = stats
	enemy.position = pos
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_alive += 1
	Vfx.ring(Vector3(pos.x, 0.05, pos.z), 1.6 * stats.size, Color(0.8, 0.35, 1.0, 0.8), 0.5)


func _on_enemy_died(enemy: Enemy) -> void:
	_alive -= 1
	if not _finished:
		Progress.add_exp(enemy.stats.exp_reward)
		Vfx.float_text(enemy.global_position + Vector3.UP * (enemy.bar_height + 0.6),
				"+%d EXP" % enemy.stats.exp_reward, Color(0.8, 0.7, 1.0), 0.8)
		Loot.drop_for(enemy.stats, enemy.global_position)
	if _alive <= 0 and not _finished:
		Game.slow_motion(0.25, 0.6)
		get_tree().create_timer(2.0).timeout.connect(_next_wave)


func _on_player_died() -> void:
	if _finished:
		return
	_finished = true
	Sfx.stop_music()
	hud.show_result("KALAH", "Tekan R untuk coba lagi", Color(1.0, 0.4, 0.35))


func _win() -> void:
	_finished = true
	Sfx.stop_music()
	Sfx.play("wave")
	hud.show_result("MENANG!", "Semua gelombang dikalahkan. Tekan R untuk main lagi", Color(1.0, 0.85, 0.35))
