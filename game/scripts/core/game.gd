extends Node
## Autoload "Game": input actions, collision layers, shared references
## (player, camera, effect container) and global time effects.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

var player: Player
var camera_rig: CameraRig
## The running level (Main), for screenshots' context notes.
var level: Node
## Container for spawned effects (slashes, sparks, damage numbers).
var world: Node3D
## True when started with the "--smoke-test" or "--fps-probe" user argument.
var test_mode := false

var _tester_path := ""


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if "--smoke-test" in args:
		_tester_path = "res://tests/smoke_test.gd"
	elif "--fps-probe" in args:
		_tester_path = "res://tests/fps_probe.gd"
	elif "--key-selftest" in args:
		_tester_path = "res://tests/key_selftest.gd"
	test_mode = _tester_path != ""
	# V-Sync is off in project settings: on the dev laptop (hybrid GPU) it halves
	# the frame rate (~34 fps measured). Cap to the monitor refresh instead
	# (60 fps cap measured smooth: worst frame 17 ms).
	var hz := DisplayServer.screen_get_refresh_rate()
	Engine.max_fps = roundi(hz) if hz > 0.0 else 60
	_setup_input()


func _ready() -> void:
	if test_mode:
		var tester: Node = load(_tester_path).new()
		get_tree().root.add_child.call_deferred(tester)


func _exit_tree() -> void:
	Vfx.clear_cache()


func shake(amount: float) -> void:
	if camera_rig and is_instance_valid(camera_rig):
		camera_rig.add_shake(amount)


## Briefly slows the whole game, e.g. on the last kill of a wave.
func slow_motion(scale: float, real_seconds: float) -> void:
	Engine.time_scale = scale
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0


func _setup_input() -> void:
	_bind_keys(&"move_forward", [KEY_W, KEY_UP])
	_bind_keys(&"move_back", [KEY_S, KEY_DOWN])
	_bind_keys(&"move_left", [KEY_A, KEY_LEFT])
	_bind_keys(&"move_right", [KEY_D, KEY_RIGHT])
	_bind_keys(&"jump", [KEY_SPACE])
	# Main dodge is double-tapping a direction (see Player); Shift is a backup.
	_bind_keys(&"dodge", [KEY_SHIFT])
	_bind_keys(&"skill_1", [KEY_1, KEY_Q])
	_bind_keys(&"skill_2", [KEY_2, KEY_E])
	_bind_keys(&"restart", [KEY_R])
	_bind_keys(&"toggle_mouse", [KEY_ESCAPE])
	_bind_keys(&"show_cursor", [KEY_ALT])
	_bind_keys(&"screenshot", [KEY_BACKSLASH])
	_bind_mouse(&"attack", MOUSE_BUTTON_LEFT)
	_bind_mouse(&"heavy", MOUSE_BUTTON_RIGHT)


func _bind_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
