extends Node
## Autoload "Settings": key bindings, mouse sensitivity and volumes. Loaded from
## and saved to user://settings.cfg; applied to the InputMap and audio buses.
## Bindings are stored as codes: "key:<physical keycode>" or "mouse:<button>".

signal changed

const FILE := "user://settings.cfg"
const SLOTS := 2
## Rebindable actions in menu order: [action, label]. "menu" (Esc) is fixed.
const ACTIONS := [
	[&"move_forward", "Maju"], [&"move_back", "Mundur"], [&"move_left", "Kiri"], [&"move_right", "Kanan"],
	[&"attack", "Serang"], [&"heavy", "Serangan berat"], [&"jump", "Lompat"], [&"dodge", "Dodge"],
	[&"skill_1", "Skill 1"], [&"skill_2", "Skill 2"], [&"show_cursor", "Tampilkan kursor (tahan)"],
	[&"screenshot", "Screenshot"], [&"restart", "Main lagi (setelah selesai)"],
]
const BUSES := [&"Master", &"Music", &"SFX"]
const MOUSE_NAMES := {1: "Klik Kiri", 2: "Klik Kanan", 3: "Klik Tengah", 8: "Mouse Samping 1", 9: "Mouse Samping 2"}
## Friendlier labels for keys whose engine names are long words.
const KEY_SYMBOLS := {"BackSlash": "\\", "Slash": "/", "BracketLeft": "[", "BracketRight": "]",
		"Semicolon": ";", "Apostrophe": "'", "Comma": ",", "Period": ".", "Minus": "-", "Equal": "=",
		"QuoteLeft": "`"}

## action -> Array of SLOTS codes ("" = empty slot)
var bindings := {}
## Multiplier on the camera's base mouse sensitivity.
var mouse_sensitivity := 1.0
## bus name -> linear volume 0..1
var volumes := {}

var _path := FILE


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var testing := "--smoke-test" in args or "--fps-probe" in args or "--key-selftest" in args
	reset_to_defaults(false)
	if not testing:  # tests always run with the default keys
		load_file()
	apply_bindings()


func _ready() -> void:
	apply_volumes.call_deferred()  # after Sfx has created the Music / SFX buses


static func default_bindings() -> Dictionary:
	return {
		&"move_forward": [_key(KEY_W), _key(KEY_UP)],
		&"move_back": [_key(KEY_S), _key(KEY_DOWN)],
		&"move_left": [_key(KEY_A), _key(KEY_LEFT)],
		&"move_right": [_key(KEY_D), _key(KEY_RIGHT)],
		&"attack": [_mouse(MOUSE_BUTTON_LEFT), ""],
		&"heavy": [_mouse(MOUSE_BUTTON_RIGHT), ""],
		&"jump": [_key(KEY_SPACE), ""],
		&"dodge": [_key(KEY_SHIFT), ""],
		&"skill_1": [_key(KEY_1), _key(KEY_Q)],
		&"skill_2": [_key(KEY_2), _key(KEY_E)],
		&"show_cursor": [_key(KEY_ALT), ""],
		&"screenshot": [_key(KEY_BACKSLASH), ""],
		&"restart": [_key(KEY_R), ""],
	}


func reset_to_defaults(save := true) -> void:
	bindings = default_bindings()
	mouse_sensitivity = 1.0
	for bus in BUSES:
		volumes[bus] = 1.0
	if save:
		apply_bindings()
		apply_volumes()
		save_file()
		changed.emit()


## Puts `code` in `slot` of `action`. A code can only be bound once: if another
## action had it, it is removed there. Returns that other action ("" if none).
func set_binding(action: StringName, slot: int, code: String) -> StringName:
	var taken_from: StringName = &""
	if code != "":
		for other in bindings:
			for s in SLOTS:
				if bindings[other][s] == code and not (other == action and s == slot):
					bindings[other][s] = ""
					taken_from = other
	bindings[action][slot] = code
	apply_bindings()
	save_file()
	changed.emit()
	return taken_from


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.2, 3.0)
	save_file()
	changed.emit()


func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	apply_volumes()
	save_file()


func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for code in bindings[action]:
			var ev := event_from_code(code)
			if ev:
				InputMap.action_add_event(action, ev)
	if not InputMap.has_action(&"menu"):
		InputMap.add_action(&"menu")
		InputMap.action_add_event(&"menu", event_from_code(_key(KEY_ESCAPE)))


func apply_volumes() -> void:
	for bus in volumes:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var v: float = volumes[bus]
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)


func save_file() -> void:
	var cfg := ConfigFile.new()
	for action in bindings:
		cfg.set_value("input", String(action), bindings[action])
	cfg.set_value("mouse", "sensitivity", mouse_sensitivity)
	for bus in volumes:
		cfg.set_value("audio", String(bus), volumes[bus])
	cfg.save(_path)


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return
	for action in bindings:
		var saved: Variant = cfg.get_value("input", String(action), null)
		if saved is Array and saved.size() == SLOTS:
			bindings[action] = [String(saved[0]), String(saved[1])]
	mouse_sensitivity = clampf(float(cfg.get_value("mouse", "sensitivity", 1.0)), 0.2, 3.0)
	for bus in BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", String(bus), 1.0)), 0.0, 1.0)


## Tests point saving/loading at a scratch file so the player's own settings stay untouched.
func use_file(path: String) -> void:
	_path = path


static func event_from_code(code: String) -> InputEvent:
	if code.begins_with("key:"):
		var ev := InputEventKey.new()
		ev.physical_keycode = int(code.trim_prefix("key:")) as Key
		return ev
	if code.begins_with("mouse:"):
		var ev := InputEventMouseButton.new()
		ev.button_index = int(code.trim_prefix("mouse:")) as MouseButton
		return ev
	return null


## Code for a key or mouse-button event, "" for anything else.
static func code_from_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		return _key(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	if event is InputEventMouseButton:
		return _mouse((event as InputEventMouseButton).button_index)
	return ""


static func display_name(code: String) -> String:
	if code.begins_with("key:"):
		var text := OS.get_keycode_string(int(code.trim_prefix("key:")))
		return KEY_SYMBOLS.get(text, text)
	if code.begins_with("mouse:"):
		var button := int(code.trim_prefix("mouse:"))
		return MOUSE_NAMES.get(button, "Mouse %d" % button)
	return "—"


## First bound key of `action`, for HUD hints.
func key_name(action: StringName) -> String:
	for code in bindings.get(action, []):
		if code != "":
			return display_name(code)
	return "—"


static func action_label(action: StringName) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[1]
	return String(action)


static func _key(code: Key) -> String:
	return "key:%d" % code


static func _mouse(button: MouseButton) -> String:
	return "mouse:%d" % button
