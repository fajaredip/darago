class_name Player
extends CharacterBody3D
## Player character with Dragon Nest style controls: camera-relative movement,
## left-click combo, right-click heavy attack, jump with air attacks,
## double-tap dodge with i-frames, mana skills and hit reactions.
## The class (stats, moves, model, animations) lives in res://data/classes/*.tres,
## attacks in res://data/attacks/*.tres.

signal died

enum State { FREE, ATTACK, DODGE, HURT, DEAD }

const BODY_RADIUS := 0.4
const COMBO_GRACE := 0.35
## Metres between footstep sounds while running.
const STEP_LENGTH := 1.9
## Directions that dodge when tapped twice: [input action, move input].
const TAP_DIRECTIONS := [
	[&"move_forward", Vector2(0, -1)],
	[&"move_back", Vector2(0, 1)],
	[&"move_left", Vector2(-1, 0)],
	[&"move_right", Vector2(1, 0)],
]

@export var stats: PlayerStats = preload("res://data/classes/warrior.tres")
## Dragon Nest style: the character always faces where the camera looks.
@export var face_camera := true

var hp := 0.0
var mana := 0.0
var state := State.FREE
var facing := Vector3.FORWARD
var body_radius := BODY_RADIUS
var combo_hits := 0
var combo_timer := 0.0
var skill_cooldowns: Array[float] = [0.0, 0.0]
## Short timer the HUD uses to flash a skill that could not be used.
var skill_denied_time: Array[float] = [0.0, 0.0]
var dodge_cooldown := 0.0
const POTION_MAX_CD := 8.0
var hp_potions := 5
var mp_potions := 5
var hp_potion_cd := 0.0
var mp_potion_cd := 0.0

var _yaw := 0.0
var _state_time := 0.0
var _attack: AttackData
var _is_skill := false
var _combo_index := -1
var _combo_grace := 0.0
var _hit_log := {}
var _active_started := false
var _vfx_ticks := 0
var _hitstop := 0.0
var _iframes := 0.0
var _dodge_dir := Vector3.ZERO
var _move_input := Vector2.ZERO
var _buffered: StringName = &""
var _buffer_left := 0.0
var _hurt_flash := 0.0
var _recovery_anim_started := false
## While > 0 the landing animation plays before idle/run take over.
var _land_anim_left := 0.0
var _step_distance := 0.0
var _air_combo := 0
var _air_heavy_used := false
var _was_on_floor := true
var _plunge_landed := false
## Direction of a double-tap dodge (move-input space); zero = use current input.
var _dodge_input := Vector2.ZERO
var _tap_dir := Vector2.ZERO
var _tap_time := -10.0
## >0 squashes the body (landing), <0 stretches it (jump take-off).
var _squash := 0.0

## Turned for spins, run direction and squash; holds the rig.
var _model: Node3D
var _rig: CharacterRig
var _overlay: StandardMaterial3D
## Weapon node, its trail, and the layer that steadies the sword arm while running.
var _weapon: Node3D
var _arm_hold: PoseLayer
var _trail: WeaponTrail


func _ready() -> void:
	# Own copy of the class: level (and later gear) change its numbers.
	stats = stats.duplicate()
	Progress.apply_to(stats)
	Progress.leveled_up.connect(_on_level_up)
	Inventory.equipment_changed.connect(_on_gear_changed)
	hp = stats.max_hp
	mana = stats.max_mana
	collision_layer = Game.LAYER_PLAYER
	platform_floor_layers = Game.LAYER_WORLD
	_restore_collision()
	_build_body()
	_set_yaw(0.0)
	Game.player = self


## New gear: recompute stats, keeping the same share of HP and MP.
func _on_gear_changed() -> void:
	var hp_share := hp / stats.max_hp
	var mp_share := mana / stats.max_mana
	Progress.apply_to(stats)
	if state != State.DEAD:
		hp = stats.max_hp * hp_share
		mana = stats.max_mana * mp_share


func _on_level_up(_level: int) -> void:
	Progress.apply_to(stats)
	if state == State.DEAD:
		return
	hp = stats.max_hp
	mana = stats.max_mana
	var gold := Color(1.0, 0.82, 0.35)
	Vfx.ring(global_position + Vector3.UP * 0.05, 3.2, gold, 0.6)
	Vfx.ring(global_position + Vector3.UP * 1.0, 2.0, Color(1.0, 0.95, 0.7, 0.8), 0.45)
	Sfx.play("level_up")


func can_be_hit() -> bool:
	return state != State.DEAD


## Queue an action: "attack", "heavy", "jump", "dodge", "skill_1" or "skill_2".
## Used by input polling and tests; later also the hook for network input.
func request_action(action: StringName) -> void:
	_buffered = action
	_buffer_left = stats.input_buffer


func set_move_input(value: Vector2) -> void:
	_move_input = value


## One-line state summary for screenshot notes.
func describe() -> String:
	var attack := ""
	if state == State.ATTACK and _attack:
		attack = " serangan='%s' t=%.2fs" % [_attack.display_name, _state_time]
	return "Pemain %s: state=%s%s anim=%s HP %d/%d MP %d/%d pos=(%.1f, %.1f, %.1f) kecepatan=%.1f m/s di_tanah=%s combo_hit=%d" % [
			stats.class_display_name, State.keys()[state], attack, _rig.current(), hp, stats.max_hp, mana, stats.max_mana,
			global_position.x, global_position.y, global_position.z, Vector2(velocity.x, velocity.z).length(),
			is_on_floor(), combo_hits]


## Called by enemies. Returns true if the hit connected.
func take_hit(amount: float, from_pos: Vector3, knockback: float) -> bool:
	if state == State.DEAD:
		return false
	if _iframes > 0.0:
		if state == State.DODGE or (state == State.ATTACK and _attack.iframes > 0.0):
			Vfx.float_text(global_position + Vector3.UP * 2.0, "DODGE", Color(1.0, 0.95, 0.8))
		return false
	var dmg := amount * 100.0 / (100.0 + stats.defense)
	hp = maxf(0.0, hp - dmg)
	_hurt_flash = 1.0
	_hitstop = 0.07
	Vfx.damage_number(global_position + Vector3.UP * 2.0, dmg, Color(1.0, 0.35, 0.3))
	Sfx.play("hurt")
	Game.shake(0.3)
	if hp <= 0.0:
		_die()
		return true
	if state == State.ATTACK and _attack.super_armor:
		return true
	var dir := global_position - from_pos
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -facing
	velocity.x = dir.x * knockback
	velocity.z = dir.z * knockback
	state = State.HURT
	_state_time = 0.0
	_iframes = stats.hurt_iframes
	_combo_index = -1
	_restore_collision()
	_rig.play(stats.anim_hurt, 0.05)
	return true


func _physics_process(delta: float) -> void:
	_read_input()
	if _hitstop > 0.0:
		_hitstop -= delta
		_rig.freeze(true)  # the whole pose stops on impact
		_trail.paused = true
		return
	_rig.freeze(false)
	_trail.paused = false
	_tick_timers(delta)
	_state_time += delta
	match state:
		State.FREE:
			_state_free(delta)
		State.ATTACK:
			_state_attack(delta)
		State.DODGE:
			_state_dodge(delta)
		State.HURT:
			_state_hurt(delta)
		State.DEAD:
			_friction(delta, 20.0)
	if not is_on_floor():
		velocity.y -= stats.gravity * _gravity_scale() * delta
	var fall_speed := -velocity.y
	move_and_slide()
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_on_landed(fall_speed)
	_was_on_floor = on_floor
	if global_position.y < -10.0:
		global_position = Vector3(0.0, 1.0, 0.0)
		velocity = Vector3.ZERO
	_update_visuals(delta)


# --- Input ---------------------------------------------------------------

func _read_input() -> void:
	if Game.test_mode:
		return
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var now := Time.get_ticks_msec() * 0.001
	for entry in TAP_DIRECTIONS:
		if Input.is_action_just_pressed(entry[0]):
			_on_direction_tapped(entry[1], now)
	if Input.is_action_just_pressed("dodge"):
		_dodge_input = Vector2.ZERO
		request_action(&"dodge")
	if Input.is_action_just_pressed("jump"):
		request_action(&"jump")
	if Input.is_action_just_pressed("skill_1"):
		request_action(&"skill_1")
	if Input.is_action_just_pressed("skill_2"):
		request_action(&"skill_2")
	if Input.is_action_just_pressed("potion_hp"):
		use_hp_potion()
	if Input.is_action_just_pressed("potion_mp"):
		use_mp_potion()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("heavy"):
			request_action(&"heavy")
		elif Input.is_action_just_pressed("attack"):
			request_action(&"attack")
		elif Input.is_action_pressed("attack") and _buffer_left <= 0.0:
			# Holding the button keeps the combo going.
			request_action(&"attack")


## Dragon Nest style evade: tapping the same direction twice quickly dodges that way.
func _on_direction_tapped(dir: Vector2, now: float) -> void:
	if dir == _tap_dir and now - _tap_time <= stats.double_tap_window:
		_tap_time = -10.0
		_dodge_input = dir
		request_action(&"dodge")
	else:
		_tap_dir = dir
		_tap_time = now


func _consume_buffer() -> void:
	_buffered = &""
	_buffer_left = 0.0


## Starts the buffered action if the current state allows it.
func _try_buffered(can_act: bool, can_dodge: bool) -> bool:
	if _buffer_left <= 0.0:
		return false
	match _buffered:
		&"jump":
			if not can_act or not is_on_floor():
				return false
			_consume_buffer()
			_jump()
			return true
		&"attack":
			if not can_act:
				return false
			if not is_on_floor():
				if _air_combo >= stats.air_combo.size():
					return false
				_consume_buffer()
				_air_combo += 1
				_start_attack(stats.air_combo[_air_combo - 1], false)
				return true
			var next := 0
			var chaining := (state == State.ATTACK and not _is_skill) or (_combo_grace > 0.0 and _combo_index >= 0)
			if chaining:
				next = (_combo_index + 1) % stats.combo.size()
			_consume_buffer()
			_combo_index = next
			_start_attack(stats.combo[next], false)
			return true
		&"heavy":
			if not can_act:
				return false
			var heavy := stats.heavy
			if not is_on_floor():
				if _air_heavy_used:
					return false
				_air_heavy_used = true
				heavy = stats.air_heavy
			_consume_buffer()
			if heavy == null:
				return false
			_combo_index = -1
			_start_attack(heavy, false)
			return true
		&"dodge":
			if not can_dodge or dodge_cooldown > 0.0 or not is_on_floor():
				return false
			_consume_buffer()
			_start_dodge()
			return true
		&"skill_1", &"skill_2":
			if not can_act:
				return false
			var i := 0 if _buffered == &"skill_1" else 1
			var skill := stats.skill_1 if i == 0 else stats.skill_2
			_consume_buffer()
			if skill == null or skill_cooldowns[i] > 0.0 or mana < skill.mana_cost:
				skill_denied_time[i] = 0.4
				Sfx.play("deny")
				return false
			mana -= skill.mana_cost
			skill_cooldowns[i] = skill.cooldown
			_combo_index = -1
			_start_attack(skill, true)
			return true
	return false


# --- States --------------------------------------------------------------

func _state_free(delta: float) -> void:
	var dir := _world_move_dir()
	var accel := stats.acceleration if is_on_floor() else stats.acceleration * stats.air_control
	_accelerate(dir * stats.move_speed, accel, delta)
	if face_camera:
		_turn_toward(_camera_yaw(), delta)
	elif dir.length() > 0.1:
		_turn_toward(_yaw_of(dir), delta)
	_try_buffered(true, true)


func _state_attack(delta: float) -> void:
	var a := _attack
	var active_end := a.startup + a.active
	if a.plunge and not _plunge_landed:
		# Hang briefly, then dive; the timeline waits here until _on_landed().
		_friction(delta, 20.0)
		if _state_time >= a.startup:
			_state_time = a.startup
			velocity.y = -a.plunge_speed
		else:
			velocity.y = 0.0
		return
	if a.lunge_distance > 0.0 and _state_time < active_end:
		var speed := a.lunge_distance / maxf(active_end, 0.01)
		velocity.x = facing.x * speed
		velocity.z = facing.z * speed
	else:
		_friction(delta, 40.0 if is_on_floor() else 8.0)
	while _vfx_ticks < a.hits and _state_time >= a.startup + _vfx_ticks * a.hit_interval:
		_vfx_ticks += 1
		_spawn_swing_fx(a)
	var hit_start := a.startup + a.active * a.hit_point
	if _state_time >= hit_start and (not _active_started or _state_time <= active_end):
		if not _active_started:
			_active_started = true
			if a.impact_ring:
				_spawn_impact(a)
		_process_hits(a)
	# Sword trail while the blade is actually swinging.
	_trail.emitting = _state_time >= a.startup * 0.5 and _state_time <= active_end + 0.06
	if _state_time >= active_end and not _recovery_anim_started:
		_recovery_anim_started = true
		if a.recovery_animation != &"":
			_rig.play(a.recovery_animation, 0.1, a.recovery_anim_speed)
	if _state_time >= a.cancel_after:
		if _try_buffered(true, true):
			return
		if _move_input.length() > 0.2 and _state_time >= active_end:
			_end_action()
			return
	elif _state_time >= stats.dodge_cancel_after and _try_buffered(false, true):
		return
	if _state_time >= active_end + a.recovery:
		_end_action()


func _state_dodge(delta: float) -> void:
	var t := clampf(_state_time / stats.dodge_duration, 0.0, 1.0)
	# Speed decays linearly to zero, which covers exactly dodge_distance.
	var speed := stats.dodge_distance / stats.dodge_duration * 2.0 * (1.0 - t)
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed
	if t >= 0.7 and _try_buffered(true, false):
		return
	if t >= 1.0:
		_end_action()


func _state_hurt(delta: float) -> void:
	_friction(delta, 18.0)
	if _state_time >= stats.hurt_stun:
		_end_action()


func _start_attack(a: AttackData, is_skill: bool) -> void:
	_attack = a
	_is_skill = is_skill
	state = State.ATTACK
	_state_time = 0.0
	_hit_log.clear()
	_active_started = false
	_vfx_ticks = 0
	_combo_grace = 0.0
	_plunge_landed = false
	_recovery_anim_started = false
	_trail.color = Color(a.color.r, a.color.g, a.color.b, 0.9)
	if a.iframes > 0.0:
		_iframes = maxf(_iframes, a.iframes)
	if a.air_float > 0.0:
		velocity.y = a.air_float  # hover: also cancels the rest of the jump
	_snap_facing()
	collision_mask = Game.LAYER_WORLD if a.pass_through else Game.LAYER_WORLD | Game.LAYER_ENEMY
	if a.anim_hold >= 0.0:
		_rig.hold(a.animation, a.anim_hold)
	else:
		_rig.play(a.animation, 0.06, a.anim_speed, a.anim_offset)


func _jump() -> void:
	if state == State.ATTACK:
		_end_action()
	velocity.y = stats.jump_velocity
	_combo_index = -1
	_combo_grace = 0.0
	_squash = -0.06
	_land_anim_left = 0.0
	_rig.play(stats.anim_jump, 0.08, 1.6, stats.anim_jump_offset)
	Sfx.play("jump")
	Vfx.ring(global_position + Vector3.UP * 0.05, 0.9, Color(0.85, 0.8, 0.7, 0.4), 0.2)


func _on_landed(fall_speed: float) -> void:
	_air_combo = 0
	_air_heavy_used = false
	if fall_speed > 4.0:
		_squash = clampf(fall_speed / 120.0, 0.02, 0.08)
		Vfx.ring(global_position + Vector3.UP * 0.05, 1.0, Color(0.85, 0.8, 0.7, 0.5), 0.25)
		Sfx.play("thud", -10.0)
	if state == State.ATTACK:
		if _attack.plunge:
			_plunge_landed = true
			if _attack.land_anim_offset >= 0.0:
				_rig.play(_attack.animation, 0.04, _attack.anim_speed, _attack.land_anim_offset)
		elif _attack.air_float > 0.0:
			_end_action()  # touching the ground cancels air attacks
	if state == State.FREE and fall_speed > 4.0:
		_land_anim_left = 0.22
		_rig.play(stats.anim_land, 0.06, 1.6, stats.anim_land_offset)


## Air attacks float, the plunge drives its own fall speed.
func _gravity_scale() -> float:
	if state != State.ATTACK:
		return 1.0
	if _attack.plunge:
		return 1.0 if _plunge_landed else 0.0
	if _attack.air_float > 0.0 and _state_time < _attack.startup + _attack.active:
		return 0.25
	return 1.0


func _start_dodge() -> void:
	state = State.DODGE
	_state_time = 0.0
	var dir := _input_to_world(_dodge_input) if _dodge_input != Vector2.ZERO else _world_move_dir()
	_dodge_input = Vector2.ZERO
	_dodge_dir = dir if dir.length() > 0.1 else -facing
	_iframes = maxf(_iframes, stats.dodge_iframes)
	dodge_cooldown = stats.dodge_cooldown
	_combo_index = -1
	collision_mask = Game.LAYER_WORLD
	_rig.play(stats.anim_dodge, 0.05, stats.anim_dodge_length / stats.dodge_duration, 0.0)
	Sfx.play("dodge")
	Vfx.ring(global_position + Vector3.UP * 0.05, 1.3, Color(0.85, 0.8, 0.7, 0.45), 0.3)


func _end_action() -> void:
	if state == State.ATTACK and not _is_skill:
		_combo_grace = COMBO_GRACE
	state = State.FREE
	_state_time = 0.0
	_restore_collision()


func _die() -> void:
	state = State.DEAD
	_state_time = 0.0
	velocity = Vector3.ZERO
	_restore_collision()
	_rig.play(stats.anim_death, 0.08)
	died.emit()


# --- Combat --------------------------------------------------------------

func _process_hits(a: AttackData) -> void:
	var targets := HitQuery.in_arc(global_position, facing, a.radius, a.arc_degrees, a.height,
			get_tree().get_nodes_in_group("enemies"))
	var landed := false
	for target in targets:
		# x = times hit by this attack, y = time of the last hit
		var rec: Vector2 = _hit_log.get(target, Vector2(0.0, -INF))
		if rec.x >= a.hits or _state_time - rec.y < a.hit_interval:
			continue
		_hit_log[target] = Vector2(rec.x + 1.0, _state_time)
		var dmg := stats.attack_power * a.damage_multiplier * randf_range(0.92, 1.08)
		var crit := randf() < stats.crit_chance
		if crit:
			dmg *= stats.crit_multiplier
		target.take_hit(dmg, crit, a, global_position, facing)
		mana = minf(stats.max_mana, mana + a.mana_gain)
		combo_hits += 1
		combo_timer = 2.0
		landed = true
	if landed:
		_hitstop = maxf(_hitstop, a.hitstop)
		Game.shake(a.camera_shake)
		Sfx.play(a.hit_sound)


func _spawn_impact(a: AttackData) -> void:
	var center := global_position + facing * a.impact_offset + Vector3.UP * 0.05
	Vfx.ring(center, a.impact_radius if a.impact_radius > 0.0 else a.radius, a.color, 0.35)
	Game.shake(a.camera_shake * 0.6)


func _spawn_swing_fx(a: AttackData) -> void:
	Sfx.play(a.swing_sound)
	if a.voice:
		Sfx.play("effort")


func _tick_timers(delta: float) -> void:
	_iframes = maxf(0.0, _iframes - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	hp_potion_cd = maxf(0.0, hp_potion_cd - delta)
	mp_potion_cd = maxf(0.0, mp_potion_cd - delta)
	for i in skill_cooldowns.size():
		skill_cooldowns[i] = maxf(0.0, skill_cooldowns[i] - delta)
		skill_denied_time[i] = maxf(0.0, skill_denied_time[i] - delta)
	_buffer_left -= delta
	_land_anim_left -= delta
	if _combo_grace > 0.0:
		_combo_grace -= delta
		if _combo_grace <= 0.0 and state != State.ATTACK:
			_combo_index = -1
	combo_timer -= delta
	if combo_timer <= 0.0:
		combo_hits = 0
	if state != State.DEAD:
		mana = minf(stats.max_mana, mana + stats.mana_regen * delta)


func use_hp_potion() -> void:
	if state == State.DEAD:
		return
	if hp_potions <= 0:
		var hud_ui: Hud = get_tree().get_first_node_in_group("hud")
		if hud_ui:
			hud_ui.toast("Potion HP habis!")
		Sfx.play("deny")
		return
	if hp_potion_cd > 0.0:
		Sfx.play("deny")
		return
	if hp >= stats.max_hp:
		var hud_ui: Hud = get_tree().get_first_node_in_group("hud")
		if hud_ui:
			hud_ui.toast("HP sudah penuh!")
		Sfx.play("deny")
		return
	hp_potions -= 1
	hp_potion_cd = POTION_MAX_CD
	var heal_amt := stats.max_hp * 0.35
	hp = minf(hp + heal_amt, stats.max_hp)
	Sfx.play("level_up")
	Vfx.ring(global_position + Vector3.UP * 0.1, 2.2, Color(0.3, 1.0, 0.4), 0.5)
	Vfx.float_text(global_position + Vector3.UP * 2.0, "+%d HP" % roundi(heal_amt), Color(0.35, 1.0, 0.45), 0.8)


func use_mp_potion() -> void:
	if state == State.DEAD:
		return
	if mp_potions <= 0:
		var hud_ui: Hud = get_tree().get_first_node_in_group("hud")
		if hud_ui:
			hud_ui.toast("Potion MP habis!")
		Sfx.play("deny")
		return
	if mp_potion_cd > 0.0:
		Sfx.play("deny")
		return
	if mana >= stats.max_mana:
		var hud_ui: Hud = get_tree().get_first_node_in_group("hud")
		if hud_ui:
			hud_ui.toast("MP sudah penuh!")
		Sfx.play("deny")
		return
	mp_potions -= 1
	mp_potion_cd = POTION_MAX_CD
	var mana_amt := stats.max_mana * 0.50
	mana = minf(mana + mana_amt, stats.max_mana)
	Sfx.play("level_up")
	Vfx.ring(global_position + Vector3.UP * 0.1, 2.2, Color(0.3, 0.65, 1.0), 0.5)
	Vfx.float_text(global_position + Vector3.UP * 2.0, "+%d MP" % roundi(mana_amt), Color(0.4, 0.7, 1.0), 0.8)


# --- Movement helpers ----------------------------------------------------

func _camera_yaw() -> float:
	if Game.camera_rig and is_instance_valid(Game.camera_rig):
		return Game.camera_rig.yaw()
	return _yaw


func _world_move_dir() -> Vector3:
	return _input_to_world(_move_input)


## Converts a move input (x = right, y = back) to a flat world direction.
func _input_to_world(input: Vector2) -> Vector3:
	var v := Vector3(input.x, 0.0, input.y)
	if v.length_squared() < 0.01:
		return Vector3.ZERO
	return (Basis(Vector3.UP, _camera_yaw()) * v).normalized()


func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _set_yaw(value: float) -> void:
	_yaw = wrapf(value, -PI, PI)
	rotation.y = _yaw
	facing = Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _turn_toward(target_yaw: float, delta: float) -> void:
	_set_yaw(lerp_angle(_yaw, target_yaw, 1.0 - exp(-stats.turn_speed * delta)))


func _snap_facing() -> void:
	if face_camera:
		_set_yaw(_camera_yaw())
	else:
		var dir := _world_move_dir()
		if dir.length() > 0.1:
			_set_yaw(_yaw_of(dir))


func _accelerate(target: Vector3, accel: float, delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _friction(delta: float, amount: float) -> void:
	_accelerate(Vector3.ZERO, amount, delta)


func _restore_collision() -> void:
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMY


# --- Visuals -------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	var k := 1.0 - exp(-16.0 * delta)
	var body_yaw := 0.0
	var spin := false
	match state:
		State.FREE:
			_update_locomotion(delta)
			var move := Vector3(velocity.x, 0.0, velocity.z)
			if is_on_floor() and move.length() > 1.0:
				# Only forward-running clips exist: turn the body toward the run
				# direction; attacks snap back to the camera direction.
				body_yaw = wrapf(_yaw_of(move) - _yaw, -PI, PI)
		State.ATTACK:
			var a := _attack
			if a.model_spins > 0 and _state_time >= a.startup and _state_time < a.startup + a.active:
				var w := (_state_time - a.startup) / maxf(a.active, 0.001)
				body_yaw = TAU * a.model_spins * w
				spin = true
		State.DODGE:
			body_yaw = wrapf(_yaw_of(_dodge_dir) - _yaw, -PI, PI)
	if spin:
		_model.rotation.y = body_yaw
	else:
		_model.rotation.y = lerp_angle(_model.rotation.y, body_yaw, k)
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-12.0 * delta))
	_model.scale = Vector3(1.0 + _squash, 1.0 - _squash, 1.0 + _squash)

	_hurt_flash = maxf(0.0, _hurt_flash - delta * 4.0)
	_overlay.albedo_color = Color(1.0, 0.15, 0.1, _hurt_flash * 0.5)

	if state != State.ATTACK:
		_trail.emitting = false
	# While running or jumping the sword arm keeps its guard pose, so the blade
	# stays steady at the side instead of pumping with the run cycle.
	var moving := state == State.FREE and (not is_on_floor() or Vector2(velocity.x, velocity.z).length() > 1.0)
	# Blend in gently, let go fast so the first swing of an attack isn't held back.
	_arm_hold.influence = move_toward(_arm_hold.influence, 1.0 if moving else 0.0, delta * (8.0 if moving else 24.0))


## Idle / run / air animations while the player is free to move, plus footsteps.
func _update_locomotion(delta: float) -> void:
	if not is_on_floor():
		if velocity.y < 0.0 or _rig.current() != stats.anim_jump:
			_rig.play(stats.anim_air, 0.2)
		return
	if _land_anim_left > 0.0:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.8:
		_rig.play(stats.anim_run, 0.15, clampf(speed / stats.run_anim_reference_speed, 0.5, 1.4))
		_step_distance += speed * delta
		if _step_distance >= STEP_LENGTH:
			_step_distance = 0.0
			Sfx.play("footstep", 0.0, 0.1)
	else:
		_rig.play(stats.anim_idle, 0.2)
		_step_distance = STEP_LENGTH * 0.6  # first step comes quickly


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	_overlay = Vfx.overlay_material()
	_model = Node3D.new()
	add_child(_model)
	_rig = CharacterRig.new()
	_model.add_child(_rig)
	_rig.setup(stats.model, _overlay, stats.animation_libraries, stats.model_scale)
	_rig.set_looping([stats.anim_idle, stats.anim_run, stats.anim_air])
	_trail = WeaponTrail.new()
	add_child(_trail)
	_arm_hold = _rig.add_pose_layer(stats.hold_pose_bones, stats.hold_pose_anim, stats.hold_pose_time)
	if stats.weapon:
		_weapon = stats.weapon.instantiate()
		var rot := stats.weapon_rotation * (PI / 180.0)
		var basis := Basis.from_euler(rot).scaled(Vector3.ONE * stats.weapon_scale)
		_rig.attach(_weapon, stats.weapon_bone, Transform3D(basis, stats.weapon_position))
		for mi: MeshInstance3D in _weapon.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = _overlay
		_trail.setup(_weapon, stats.weapon_trail_base, stats.weapon_trail_tip)
	_rig.play(stats.anim_idle, 0.0)

