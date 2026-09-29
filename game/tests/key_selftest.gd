extends Node
## Presses the screenshot key through the real input path, then quits.
## Game adds this node for the "--key-selftest" user argument.
##   Godot --path game -- --key-selftest


func _ready() -> void:
	await get_tree().create_timer(2.0).timeout
	var press := InputEventKey.new()
	press.physical_keycode = KEY_BACKSLASH
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().create_timer(3.0).timeout
	print("KEY SELFTEST DONE, folder: ", Screenshot.default_folder())
	get_tree().quit()
