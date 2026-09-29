extends Node
## Autoload "Sfx": sound effects built from CC0 samples (see CREDITS.md) and the
## music / ambience players.
##
## Each event plays one random sample from every layer it lists, so hits can
## stack a blade slash with a body impact and repeated swings never sound the
## same twice. Pass a world position to make a sound come from that spot.

const SFX_DIR := "res://assets/audio/sfx/"
## event -> layers of [sample-name prefix, volume dB]
const EVENTS := {
	"swing": [["swing_light", -5.0]],
	"swing_heavy": [["swing_heavy", -3.0]],
	"hit": [["slash", -9.0], ["punch_medium", -3.0], ["bone_break", -12.0]],
	"hit_heavy": [["slash", -6.0], ["punch_heavy", -1.0], ["bone_heavy", -6.0]],
	"thud": [["thud", -5.0]],
	"hurt": [["voice_hurt", -4.0], ["punch_medium", -7.0]],
	"effort": [["voice_effort", -7.0]],
	"enemy_die": [["bone_break", -3.0], ["clatter", -5.0]],
	"telegraph": [["clash", -11.0]],
	"wave": [["bell", -6.0]],
	"deny": [["click", -12.0]],
	"jump": [["cloth", -12.0]],
	"dodge": [["swing_light", -10.0], ["cloth", -9.0]],
	"footstep": [["step", -19.0]],
}
const VOICES_2D := 16
const VOICES_3D := 12

var _banks := {}  # prefix -> Array[AudioStream]
var _last := {}  # prefix -> index played last time (avoid instant repeats)
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _music_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_bus(&"SFX")
	_ensure_bus(&"Music")
	_load_banks()
	for i in VOICES_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players_2d.append(p)
	for i in VOICES_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 8.0
		p.max_distance = 45.0
		add_child(p)
		_players_3d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Music"
	add_child(_ambience)


func _exit_tree() -> void:
	for p in _players_2d:
		p.stop()
		p.stream = null
	for p in _players_3d:
		p.stop()
		p.stream = null
	if _music_tween:
		_music_tween.kill()
	for p in [_music, _ambience]:
		p.stop()
		p.stream = null
	_banks.clear()


## Plays `event`. With `at` (a Vector3) the sound is positioned in the world.
func play(event: String, volume_db := 0.0, pitch_jitter := 0.06, at: Variant = null) -> void:
	if not EVENTS.has(event):
		return
	var pitch := 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	for layer in EVENTS[event]:
		var stream := _pick(layer[0])
		if stream == null:
			continue
		if at is Vector3:
			var p := _players_3d[_next_3d]
			_next_3d = (_next_3d + 1) % VOICES_3D
			p.global_position = at
			_start(p, stream, float(layer[1]) + volume_db, pitch)
		else:
			var p := _players_2d[_next_2d]
			_next_2d = (_next_2d + 1) % VOICES_2D
			_start(p, stream, float(layer[1]) + volume_db, pitch)


## Crossfades to a looping music track (null / "" fades the music out).
func play_music(path: String, volume_db := -12.0, fade := 1.5) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, "volume_db", -40.0, fade * 0.5)
	if path == "":
		_music_tween.tween_callback(_music.stop)
		return
	var stream := _looping(path)
	_music_tween.tween_callback(func() -> void:
		_music.stream = stream
		_music.volume_db = -40.0
		_music.play())
	_music_tween.tween_property(_music, "volume_db", volume_db, fade)


func stop_music(fade := 2.0) -> void:
	play_music("", -40.0, fade * 2.0)


func play_ambience(path: String, volume_db := -24.0) -> void:
	_ambience.stream = _looping(path)
	_ambience.volume_db = volume_db
	_ambience.play()


func _start(p: Node, stream: AudioStream, volume_db: float, pitch: float) -> void:
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _pick(prefix: String) -> AudioStream:
	var bank: Array = _banks.get(prefix, [])
	if bank.is_empty():
		return null
	var i := _rng.randi_range(0, bank.size() - 1)
	if bank.size() > 1 and i == _last.get(prefix, -1):
		i = (i + 1) % bank.size()
	_last[prefix] = i
	return bank[i]


## Groups sample files by name prefix: "swing_heavy_3.ogg" -> "swing_heavy".
func _load_banks() -> void:
	for file in ResourceLoader.list_directory(SFX_DIR):
		if not file.ends_with(".ogg"):
			continue
		var base := file.get_basename()
		var prefix := base.substr(0, base.rfind("_"))
		if not _banks.has(prefix):
			_banks[prefix] = []
		_banks[prefix].append(load(SFX_DIR + file))


func _looping(path: String) -> AudioStream:
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
