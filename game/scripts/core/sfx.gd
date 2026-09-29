extends Node
## Autoload "Sfx": placeholder sound effects synthesized in code at startup,
## so the prototype has impact audio without any sound files.

const MIX_RATE := 22050
const VOICES := 16

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	_sounds["swing"] = _whoosh(0.15, 0.35, 0.55)
	_sounds["swing_heavy"] = _whoosh(0.24, 0.2, 0.8)
	_sounds["dodge"] = _whoosh(0.2, 0.12, 0.45)
	_sounds["jump"] = _whoosh(0.12, 0.3, 0.35)
	_sounds["hit"] = _impact(0.13, 120.0, 0.9, 1.0)
	_sounds["hit_heavy"] = _impact(0.28, 70.0, 1.0, 0.7)
	_sounds["thud"] = _impact(0.2, 55.0, 0.8, 0.2)
	_sounds["hurt"] = _tone(0.22, 260.0, 90.0, 0.5, 0.5)
	_sounds["enemy_die"] = _tone(0.4, 420.0, 70.0, 0.45, 0.2)
	_sounds["telegraph"] = _tone(0.3, 180.0, 360.0, 0.35, 0.0)
	_sounds["wave"] = _tone(0.6, 330.0, 660.0, 0.3, 0.0)
	_sounds["deny"] = _tone(0.1, 160.0, 140.0, 0.3, 0.0)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	_sounds.clear()


func play(sound: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if not _sounds.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sounds[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Filtered noise swelling up and down: sword swings, dodges.
func _whoosh(duration: float, brightness: float, volume: float) -> AudioStreamWAV:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var gain := sqrt((2.0 - brightness) / brightness)
	for i in n:
		var t := float(i) / n
		var env := pow(sin(PI * pow(t, 0.6)), 2.0)
		var a := brightness * (0.4 + 0.6 * sin(PI * t))
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * a
		out[i] = lp * gain * env * volume * 0.5
	return _to_wav(out)


## Pitched-down thump plus a noise crack: hits and landings.
func _impact(duration: float, freq: float, volume: float, crack: float) -> AudioStreamWAV:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		phase += TAU * freq * (1.0 + 2.0 * exp(-t * 35.0)) / MIX_RATE
		var thump := sin(phase) * exp(-t * 14.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.5
		var noise := lp * exp(-t * 45.0) * crack * 1.6
		var fade := clampf((duration - t) / 0.02, 0.0, 1.0)
		out[i] = (thump * 0.9 + noise) * volume * fade
	return _to_wav(out)


## Frequency sweep with optional grit: cues, hurt, death.
func _tone(duration: float, f0: float, f1: float, volume: float, grit: float) -> AudioStreamWAV:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / MIX_RATE
		var s := sin(phase) * 0.7 + signf(sin(phase)) * 0.3
		s += _rng.randf_range(-1.0, 1.0) * grit
		var env := minf(1.0, k * 40.0) * pow(1.0 - k, 1.5)
		out[i] = s * env * volume
	return _to_wav(out)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
