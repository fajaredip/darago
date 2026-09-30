class_name Enemy
extends CharacterBody3D
## Melee enemy: chases the player, telegraphs its attack, and reacts to hits
## with hitstun, launch / juggle and knockdown. Numbers come from EnemyStats.

signal died(enemy: Enemy)

enum State { SPAWN, CHASE, WINDUP, RECOVER, HITSTUN, AIRBORNE, DOWN, GETUP, DEAD }

const GRAVITY := 28.0
const AIR_GRAVITY := 19.0
const SPAWN_TIME := 1.1
const DOWN_TIME := 0.9
const GETUP_TIME := 0.6
const DEAD_TIME := 2.0

@export var stats: EnemyStats

var hp := 0.0
var state := State.SPAWN
var body_radius := 0.45
## Height of the HP bar above the feet.
var bar_height := 2.2

var _state_time := 0.0
var _stun_time := 0.0
var _hitstop := 0.0
var _attack_cd := 0.0
var _yaw := 0.0
var _flash := 0.0
var _knockdown_pending := false
var _rng := RandomNumberGenerator.new()

## Shaken during hitstop; holds the rig.
var _model: Node3D
var _rig: CharacterRig
var _overlay: StandardMaterial3D
var _telegraph: Node3D
var _telegraph_fill: MeshInstance3D
var _trail: WeaponTrail


func _ready() -> void:
	_rng.randomize()
	stats = Progress.scale_enemy(stats)  # grow to the dungeon level of the chosen difficulty
	hp = stats.max_hp
	body_radius = 0.45 * stats.size
	bar_height = 2.0 * stats.size + 0.2
	collision_layer = Game.LAYER_ENEMY
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_ENEMY
	# Only the level counts as a moving platform; never ride on other characters.
	platform_floor_layers = Game.LAYER_WORLD
	add_to_group("enemies")
	_build_body()
	_build_telegraph()
	_attack_cd = _rng.randf_range(0.2, 1.0)
	if Game.player and is_instance_valid(Game.player):
		_face_instant(Game.player.global_position - global_position)


func describe() -> String:
	var dist := -1.0
	if Game.player and is_instance_valid(Game.player):
		dist = global_position.distance_to(Game.player.global_position)
	return "Musuh %s: state=%s anim=%s HP %d/%d jarak=%.1f m" % [
			stats.display_name, State.keys()[state], _rig.current(), hp, stats.max_hp, dist]


func can_be_hit() -> bool:
	return state != State.DEAD and state != State.SPAWN


func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Called by the player's attacks.
func take_hit(amount: float, crit: bool, attack: AttackData, from_pos: Vector3, attacker_facing: Vector3) -> void:
	if not can_be_hit():
		return
	var dmg := amount * 100.0 / (100.0 + stats.defense)
	hp -= dmg
	_flash = 1.0
	_hitstop = attack.hitstop
	var dir := attacker_facing if attack.push_along_facing else global_position - from_pos
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else attacker_facing
	var chest := global_position + Vector3.UP * 0.9 * stats.size
	Vfx.hit_spark(chest - dir * body_radius * 0.7, attack.color, 1.4 if crit else 1.0)
	Vfx.damage_number(global_position + Vector3.UP * (bar_height + 0.2), dmg,
			Color(1.0, 0.85, 0.3) if crit else Color.WHITE, crit)
	if hp <= 0.0:
		_die(dir * maxf(attack.knockback, 4.0))
		return
	if stats.armored_windup and state == State.WINDUP:
		return  # super armor: takes damage but keeps attacking
	_telegraph.visible = false
	var kb := attack.knockback * (1.0 - stats.knockback_resist)
	velocity.x = dir.x * kb
	velocity.z = dir.z * kb
	var launch := attack.launch * (1.0 - stats.launch_resist)
	if launch > 0.5:
		velocity.y = launch
		_knockdown_pending = true
		_set_state(State.AIRBORNE)
	elif state == State.AIRBORNE:
		# Juggle: normal hits keep them up, knockdown hits spike them down.
		velocity.y = -9.0 if attack.knockdown else maxf(velocity.y, 3.5)
		_knockdown_pending = true
		_set_state(State.AIRBORNE)
	elif state == State.DOWN:
		pass  # stays down while taking damage
	elif attack.knockdown and stats.knockback_resist < 0.5:
		velocity.y = 4.5
		_knockdown_pending = true
		_set_state(State.AIRBORNE)
	else:
		_stun_time = attack.hitstun * (1.0 - stats.knockback_resist * 0.6)
		_set_state(State.HITSTUN)


func _physics_process(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta
		_rig.freeze(true)
		_trail.paused = true
		_model.position = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * 0.07
		return
	_rig.freeze(false)
	_trail.paused = false
	_model.position = Vector3.ZERO
	_state_time += delta
	# Weapon trail through the end of the wind-up and the swing that follows.
	_trail.emitting = (state == State.WINDUP and _state_time > stats.windup * 0.7) \
			or (state == State.RECOVER and _state_time < 0.12)
	_attack_cd -= delta
	match state:
		State.SPAWN:
			if _state_time >= SPAWN_TIME:
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			_windup(delta)
		State.RECOVER:
			_friction(delta, 30.0)
			if _state_time >= stats.recover_time:
				_set_state(State.CHASE)
		State.HITSTUN:
			_friction(delta, 14.0)
			if _state_time >= _stun_time:
				_set_state(State.CHASE)
		State.AIRBORNE:
			if is_on_floor() and _state_time > 0.1:
				_land()
		State.DOWN:
			_friction(delta, 20.0)
			if _state_time >= DOWN_TIME:
				_set_state(State.GETUP)
		State.GETUP:
			if _state_time >= GETUP_TIME:
				_set_state(State.CHASE)
		State.DEAD:
			_friction(delta, 6.0)
			if _state_time >= DEAD_TIME:
				queue_free()
				return
	if not is_on_floor():
		velocity.y -= (AIR_GRAVITY if state == State.AIRBORNE else GRAVITY) * delta
	move_and_slide()
	if global_position.y < -10.0 and state != State.DEAD:
		hp = 0.0
		_die(Vector3.ZERO)
	_update_visuals(delta)


# --- AI ------------------------------------------------------------------

func _chase(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.state == Player.State.DEAD:
		_friction(delta, 20.0)
		return
	var to := p.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	_face(dir, delta, 8.0)
	var desired := Vector3.ZERO
	if dist > stats.attack_range * 0.8:
		desired = dir * stats.move_speed
	desired += _separation() * stats.move_speed
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 25.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if dist <= stats.attack_range and _attack_cd <= 0.0:
		_start_windup()


func _start_windup() -> void:
	_set_state(State.WINDUP)
	_telegraph.visible = true
	_telegraph_fill.scale = Vector3.ONE * 0.01
	if stats.heavy:
		Sfx.play("telegraph", 0.0, 0.06, global_position)


func _windup(delta: float) -> void:
	_friction(delta, 30.0)
	var k := clampf(_state_time / stats.windup, 0.0, 1.0)
	var p := Game.player
	# Track the player early in the wind-up, then commit so it can be dodged.
	if k < stats.track_fraction and p and is_instance_valid(p):
		_face(p.global_position - global_position, delta, 10.0)
	_telegraph_fill.scale = Vector3.ONE * maxf(0.01, k)
	if k >= 1.0:
		_perform_attack()


func _perform_attack() -> void:
	_telegraph.visible = false
	var p := Game.player
	if p and is_instance_valid(p):
		var reach_height := 0.5 if stats.ground_only else 2.0
		var hits := HitQuery.in_arc(global_position, forward(), stats.attack_radius, stats.attack_arc, reach_height, [p])
		if not hits.is_empty():
			p.take_hit(stats.attack_power * _rng.randf_range(0.9, 1.1), global_position, stats.attack_knockback)
		elif stats.ground_only and not HitQuery.in_arc(global_position, forward(), stats.attack_radius, stats.attack_arc, 10.0, [p]).is_empty():
			# In range but airborne: the jump dodged it.
			Vfx.float_text(p.global_position + Vector3.UP * 2.0, "DODGE", Color(1.0, 0.95, 0.8))
	if stats.attack_arc >= 360.0:
		Vfx.ring(global_position + Vector3.UP * 0.1, stats.attack_radius, Color(1.0, 0.35, 0.2), 0.35)
	if stats.heavy:
		Game.shake(0.15)
	Sfx.play("swing_heavy" if stats.heavy else "swing", 0.0, 0.08, global_position)
	_set_state(State.RECOVER)
	_attack_cd = stats.attack_cooldown * _rng.randf_range(0.7, 1.3)


## Push away from nearby enemies so groups spread around the player.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		var other := node as Enemy
		var d := global_position - other.global_position
		d.y = 0.0
		var l := d.length()
		var min_dist := body_radius + other.body_radius + 0.6
		if l < min_dist and l > 0.001:
			push += d / l * (1.0 - l / min_dist)
	return push


func _land() -> void:
	if _knockdown_pending:
		_knockdown_pending = false
		_set_state(State.DOWN)
		Vfx.ring(global_position + Vector3.UP * 0.05, 1.2 * stats.size, Color(0.9, 0.85, 0.7, 0.6), 0.3)
		Sfx.play("thud", 0.0, 0.08, global_position)
	else:
		_stun_time = 0.2
		_set_state(State.HITSTUN)


func _die(push: Vector3) -> void:
	_set_state(State.DEAD)
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	_telegraph.visible = false
	velocity = push + Vector3.UP * 5.0
	Sfx.play("enemy_die", 0.0, 0.1, global_position)
	died.emit(self)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_on_state_entered(new_state)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	_yaw = lerp_angle(_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * delta))
	rotation.y = _yaw


func _face_instant(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	_yaw = atan2(-dir.x, -dir.z)
	rotation.y = _yaw


func _friction(delta: float, amount: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, amount * delta)
	velocity.x = hv.x
	velocity.z = hv.z


# --- Visuals -------------------------------------------------------------

## Plays the animation that belongs to a state the enemy just entered.
func _on_state_entered(new_state: State) -> void:
	match new_state:
		State.SPAWN:
			_rig.play(stats.anim_spawn, 0.0, stats.anim_spawn_speed, 0.0)
		State.WINDUP:
			# Slow the swing down so the weapon lands exactly when the wind-up ends.
			_rig.play(stats.anim_attack, 0.08, stats.attack_anim_contact / stats.windup, 0.0)
		State.RECOVER:
			_rig.play(stats.anim_attack, 0.0, 1.0)
		State.HITSTUN:
			_rig.play(stats.anim_hit, 0.04, 1.3, 0.0)
		State.AIRBORNE:
			_rig.play(stats.anim_air, 0.05, 1.0, 0.0)
		State.DOWN:
			_rig.play(stats.anim_down, 0.08, 1.2, 0.0)
		State.GETUP:
			var clip := _rig.player.get_animation(stats.anim_getup)
			var speed := (clip.length - stats.anim_getup_offset) / GETUP_TIME if clip else 1.0
			_rig.play(stats.anim_getup, 0.1, speed, stats.anim_getup_offset)
		State.DEAD:
			_rig.play(stats.anim_death, 0.06, 1.3, 0.0)


func _update_visuals(delta: float) -> void:
	if state == State.CHASE:
		var speed := Vector2(velocity.x, velocity.z).length()
		if speed > 0.5:
			_rig.play(stats.anim_move, 0.15, clampf(speed / stats.move_anim_reference_speed, 0.6, 1.6))
		else:
			_rig.play(stats.anim_idle, 0.2)
	var s := 1.0
	if state == State.DEAD and _state_time > DEAD_TIME - 0.4:
		s = (DEAD_TIME - _state_time) / 0.4
	_model.scale = Vector3.ONE * maxf(s, 0.01)

	_flash = maxf(0.0, _flash - delta * 7.0)
	var tint := Color(1, 1, 1, 0)
	if _flash > 0.0:
		tint = Color(1, 1, 1, _flash * 0.85)
	elif state == State.WINDUP:
		var w := _state_time / stats.windup
		tint = Color(1.0, 0.1, 0.05, 0.15 + 0.35 * w + 0.1 * sin(_state_time * 30.0))
	_overlay.albedo_color = tint


func _build_body() -> void:
	var s := stats.size
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45 * s
	shape.height = 1.5 * s
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.75 * s
	add_child(col)

	_overlay = Vfx.overlay_material()
	_model = Node3D.new()
	add_child(_model)
	_rig = CharacterRig.new()
	_model.add_child(_rig)
	_rig.setup(stats.model, _overlay, {}, stats.model_scale, true)
	_rig.set_looping([stats.anim_idle, stats.anim_move])
	_trail = WeaponTrail.new()
	_trail.color = Color(1.0, 0.4, 0.25, 0.8)
	add_child(_trail)
	if stats.weapon:
		var weapon: Node3D = stats.weapon.instantiate()
		var basis := Basis.from_euler(stats.weapon_rotation * (PI / 180.0))
		_rig.attach(weapon, stats.weapon_bone, Transform3D(basis, stats.weapon_position))
		for mi: MeshInstance3D in weapon.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = _overlay
		_trail.setup(weapon, stats.weapon_trail_base, stats.weapon_trail_tip)
	_on_state_entered(State.SPAWN)


func _build_telegraph() -> void:
	_telegraph = Node3D.new()
	_telegraph.position.y = 0.05
	_telegraph.visible = false
	add_child(_telegraph)
	var mesh := Vfx.arc_mesh(0.0, stats.attack_radius, stats.attack_arc, false, 0)
	var zone := MeshInstance3D.new()
	zone.mesh = mesh
	zone.material_override = Vfx.unshaded(Color(1.0, 0.2, 0.1, 0.22), false, true)
	zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.add_child(zone)
	_telegraph_fill = MeshInstance3D.new()
	_telegraph_fill.mesh = mesh
	_telegraph_fill.material_override = Vfx.unshaded(Color(1.0, 0.25, 0.1, 0.4), false, true)
	_telegraph_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_fill.position.y = 0.01
	_telegraph.add_child(_telegraph_fill)
