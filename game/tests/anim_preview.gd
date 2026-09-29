extends SceneTree
## Dev tool: poses a character with retargeted animations and saves contact
## sheets (one strip of frames per animation) to check timing and retargeting.
##   Godot --path game -s res://tests/anim_preview.gd -- <out_dir> <model> <lib/anim>[@frames] [...]
## Frames default to 6 evenly spaced samples; "@0.1,0.2" picks exact times.

const CELL := 256

var _out := ""
var _jobs: PackedStringArray


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var model_path := args[1]
	_jobs = args.slice(2)
	_run(model_path)


func _run(model_path: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.38, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	world.add_child(sun)
	var cam := Camera3D.new()
	var eye := Vector3(2.2, 1.5, -2.4)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.9, -0.6) - eye), eye)
	world.add_child(cam)

	# A class .tres shows the model exactly as the game builds it (with weapon).
	var class_stats: PlayerStats = load(model_path) if model_path.ends_with(".tres") else null
	var scene: PackedScene = class_stats.model if class_stats else load(model_path)
	var model: Node3D = scene.instantiate()
	world.add_child(model)
	var player := AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	player.root_motion_track = NodePath("%GeneralSkeleton:Root")
	for lib_name in ["ual1", "ual2"]:
		player.add_animation_library(lib_name, load("res://assets/animations/%s.glb" % lib_name))
	# "hold:<influence>" jobs blend the class's sword-arm hold pose over the clip.
	var hold: PoseLayer = null
	if class_stats and not class_stats.hold_pose_bones.is_empty():
		var hold_skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		hold = PoseLayer.new()
		hold.influence = 0.0
		hold_skel.add_child(hold)
		hold.capture(player.get_animation(class_stats.hold_pose_anim), class_stats.hold_pose_time,
				class_stats.hold_pose_bones, hold_skel)
	if class_stats and class_stats.weapon:
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = class_stats.weapon_bone
		skel.add_child(attachment)
		var weapon: Node3D = class_stats.weapon.instantiate()
		attachment.add_child(weapon)
		var basis := Basis.from_euler(class_stats.weapon_rotation * (PI / 180.0)).scaled(Vector3.ONE * class_stats.weapon_scale)
		weapon.transform = Transform3D(basis, class_stats.weapon_position)
	var own: AnimationPlayer = model.get_node_or_null("AnimationPlayer")
	if own and own != player and own.has_animation(&"1H_Melee_Attack_Chop"):
		player = own  # KayKit characters carry their own animations

	for job in _jobs:
		# "cam:x,y,z" moves the camera for the following jobs (it looks at the chest).
		if job.begins_with("cam:"):
			var c := job.trim_prefix("cam:").split(",")
			var e := Vector3(float(c[0]), float(c[1]), float(c[2]))
			cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 1.0, 0.0) - e), e)
			continue
		if job.begins_with("hold:"):
			if hold:
				hold.influence = float(job.trim_prefix("hold:"))
			continue
		var parts := job.split("@")
		var anim_name := parts[0]
		if not player.has_animation(anim_name):
			print("missing animation: ", anim_name)
			continue
		var length := player.get_animation(anim_name).length
		var times: Array[float] = []
		if parts.size() > 1:
			for s in parts[1].split(","):
				times.append(float(s))
		else:
			for i in 6:
				times.append(length * i / 5.0)
		var sheet := Image.create(CELL * times.size(), CELL, false, Image.FORMAT_RGB8)
		for i in times.size():
			player.play(anim_name)
			player.seek(times[i], true)
			player.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var side := mini(img.get_width(), img.get_height()) * 3 / 5
			img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
			img.resize(CELL, CELL)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, 0))
		var file := _out.path_join(anim_name.replace("/", "_") + ".png")
		sheet.save_png(file)
		print("%s length=%.2f frames at %s" % [anim_name, length, str(times)])
	quit()
