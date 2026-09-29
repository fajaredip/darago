extends Node
## Autoload "Screenshot": press "\" to save the current frame as a PNG (plus a
## .txt with what the game was doing) into the project's screenshots folder,
## and copy the image to the clipboard so it can be pasted straight into chat.

var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot") and not _busy:
		capture()


## Saves the next rendered frame. Returns the PNG path. `folder` overrides the
## default screenshots folder (tests use this); the clipboard is skipped then.
func capture(folder := "") -> String:
	_busy = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():  # headless runs have nothing to capture
		_busy = false
		return ""
	var dir := folder if folder != "" else default_folder()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var png := dir.path_join("shot_%s.png" % stamp)
	var context := _describe(stamp)
	var to_clipboard := folder == "" and OS.get_name() == "Windows"
	# PNG compression takes ~100 ms: do it off the main thread so play doesn't stutter.
	WorkerThreadPool.add_task(_save.bind(image, png, context, to_clipboard))
	get_tree().call_group("hud", "toast", "Screenshot disalin: tekan Ctrl+V di chat  (juga tersimpan di folder screenshots)")
	_busy = false
	return png


## D:/.../darago/screenshots when running from the project folder, else user://.
func default_folder() -> String:
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if project == "" or not DirAccess.dir_exists_absolute(project):
		return ProjectSettings.globalize_path("user://screenshots")
	return project.get_base_dir().path_join("screenshots")


func _save(image: Image, png: String, context: String, to_clipboard: bool) -> void:
	image.save_png(png)
	var file := FileAccess.open(png.get_basename() + ".txt", FileAccess.WRITE)
	if file:
		file.store_string(context)
		file.close()
	if to_clipboard:
		_copy_to_clipboard.call_deferred(png)


## Godot 4.7 can read images from the clipboard but not write them, so let
## Windows do it (verified: the PNG lands in the clipboard at full size).
func _copy_to_clipboard(png: String) -> void:
	var path := png.replace("/", "\\").replace("'", "''")
	var script := "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; " \
			+ "$img = [System.Drawing.Image]::FromFile('%s'); [System.Windows.Forms.Clipboard]::SetImage($img); $img.Dispose()" % path
	OS.create_process("powershell.exe", ["-NoProfile", "-STA", "-WindowStyle", "Hidden", "-Command", script])


## What the game was doing at the moment of the shot, for the conversation.
func _describe(stamp: String) -> String:
	var lines := PackedStringArray()
	lines.append("Darago screenshot %s" % stamp)
	lines.append("FPS %d, window %s" % [Engine.get_frames_per_second(), str(get_viewport().get_visible_rect().size)])
	if Game.level and is_instance_valid(Game.level):
		lines.append(Game.level.describe())
	if Game.player and is_instance_valid(Game.player):
		lines.append(Game.player.describe())
	if Game.camera_rig and is_instance_valid(Game.camera_rig):
		lines.append(Game.camera_rig.describe())
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy:
			lines.append(enemy.describe())
	return "\n".join(lines) + "\n"
