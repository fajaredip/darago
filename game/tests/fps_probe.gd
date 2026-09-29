extends Node
## Measures real frame rate while fighting and logs frames slower than 30 ms.
## Game adds this node when the "--fps-probe" user argument is given.
##   Godot --path game -- --fps-probe [--probe-idle] [--probe-uncapped]

const WARMUP := 3.0
const MEASURE := 8.0

var _time := 0.0
var _frames := 0
var _worst := 0.0
var _action_timer := 0.0
var _actions: Array[StringName] = [&"attack", &"attack", &"heavy", &"jump", &"attack", &"heavy",
		&"skill_2", &"attack", &"skill_1", &"dodge"]
var _next_action := 0
## "--probe-idle": no attacks (isolates rendering / frame pacing).
var _idle := "--probe-idle" in OS.get_cmdline_user_args()


func _ready() -> void:
	# "--probe-uncapped": ignore the refresh-rate cap to see raw frame times.
	if "--probe-uncapped" in OS.get_cmdline_user_args():
		Engine.max_fps = 0
	# "--probe-cap60": force a 60 fps limiter to compare frame pacing.
	if "--probe-cap60" in OS.get_cmdline_user_args():
		Engine.max_fps = 60


func _process(delta: float) -> void:
	_time += delta
	var p := Game.player
	if p and is_instance_valid(p) and not _idle:
		p.mana = p.stats.max_mana
		p.hp = p.stats.max_hp
		_action_timer -= delta
		if _action_timer <= 0.0:
			_action_timer = 0.2
			p.request_action(_actions[_next_action])
			_next_action = (_next_action + 1) % _actions.size()
	if delta > 0.03:
		print("  slow frame %.1f ms at t=%.2f s" % [delta * 1000.0, _time])
	if _time < WARMUP:
		return
	_frames += 1
	_worst = maxf(_worst, delta)
	if _time >= WARMUP + MEASURE:
		print("FPS average: %.1f   worst frame: %.1f ms   enemies: %d" % [
				_frames / MEASURE, _worst * 1000.0, get_tree().get_nodes_in_group("enemies").size()])
		get_tree().quit()
