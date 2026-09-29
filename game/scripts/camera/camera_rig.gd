class_name CameraRig
extends Node3D
## Third-person action camera: mouse orbit, scroll zoom, wall collision,
## smooth follow and light screen shake.

## Titik pandang di atas kepala, supaya musuh di depan tidak tertutup badan.
@export var follow_height := 2.0
@export var follow_sharpness := 16.0
@export var mouse_sensitivity := 0.0025
@export var min_pitch_deg := -65.0
@export var max_pitch_deg := 20.0
@export var distance := 6.5
@export var min_distance := 2.5
@export var max_distance := 11.0
@export var zoom_step := 0.75
## Batas guncangan kamera (meter). Jaga kecil supaya tidak pusing.
@export var max_shake := 0.25

var camera: Camera3D
var _pitch_node: Node3D
var _arm: SpringArm3D
var _target: Node3D
var _yaw := 0.0
var _pitch := -0.35
var _target_distance := 6.0
var _shake := 0.0
var _shake_time := 0.0
## True while Alt is held and freed the cursor (released = capture again).
var _alt_freed := false


func _ready() -> void:
	# Moved in _process from the target's interpolated transform instead.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.collision_mask = Game.LAYER_WORLD
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_arm.spring_length = distance
	_pitch_node.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 300.0
	_arm.add_child(camera)
	camera.make_current()
	_target_distance = distance
	Game.camera_rig = self
	if not Game.test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func follow(target: Node3D) -> void:
	_target = target
	global_position = target.global_position + Vector3.UP * follow_height


func yaw() -> float:
	return _yaw


func describe() -> String:
	return "Kamera: yaw=%.0f° pitch=%.0f° jarak=%.1f m" % [rad_to_deg(_yaw), rad_to_deg(_pitch), _arm.spring_length]


func add_shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var motion := event as InputEventMouseMotion
		var sensitivity := mouse_sensitivity * Settings.mouse_sensitivity
		_yaw = wrapf(_yaw - motion.relative.x * sensitivity, -PI, PI)
		_pitch = clampf(_pitch - motion.relative.y * sensitivity,
				deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	elif event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = maxf(min_distance, _target_distance - zoom_step)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = minf(max_distance, _target_distance + zoom_step)
		elif not captured and not _alt_freed and not Game.test_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("show_cursor"):
		# Dragon Nest style: hold Alt to use the cursor, release to fight again.
		if captured:
			_alt_freed = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_released("show_cursor") and _alt_freed:
		_alt_freed = false
		if not Game.test_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var goal := _target.get_global_transform_interpolated().origin + Vector3.UP * follow_height
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)
	_arm.spring_length = lerpf(_arm.spring_length, _target_distance, 1.0 - exp(-10.0 * delta))
	_shake = maxf(0.0, _shake - delta * 2.5)
	_shake_time += delta
	var amp := _shake * _shake * max_shake
	camera.h_offset = (sin(_shake_time * 71.0) + sin(_shake_time * 113.0) * 0.5) * amp
	camera.v_offset = (sin(_shake_time * 89.0) + sin(_shake_time * 131.0) * 0.5) * amp
