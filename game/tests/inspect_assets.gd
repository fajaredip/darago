extends SceneTree
## Dev tool: prints the structure of imported models (bones, meshes, animations).
##   Godot --headless --path game -s res://tests/inspect_assets.gd -- <res://path> [...]


func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		_inspect(path)
	quit()


func _inspect(path: String) -> void:
	print("\n=== ", path)
	var packed: PackedScene = load(path)
	if packed == null:
		print("  cannot load")
		return
	var root := packed.instantiate()
	_walk(root, 0)
	for skel: Skeleton3D in root.find_children("*", "Skeleton3D", true, false):
		var names := PackedStringArray()
		for i in skel.get_bone_count():
			names.append(skel.get_bone_name(i))
		print("  skeleton '%s' bones(%d): %s" % [skel.name, skel.get_bone_count(), ", ".join(names)])
		print("  motion_scale=%.3f" % skel.motion_scale)
	for player: AnimationPlayer in root.find_children("*", "AnimationPlayer", true, false):
		var list := player.get_animation_list()
		print("  animations(%d): %s" % [list.size(), ", ".join(list)])
		for anim_name in list.slice(0, 3):
			var anim := player.get_animation(anim_name)
			var tracks := PackedStringArray()
			for t in mini(anim.get_track_count(), 4):
				tracks.append(str(anim.track_get_path(t)))
			print("    %s len=%.2f tracks=%d e.g. %s" % [anim_name, anim.length, anim.get_track_count(), ", ".join(tracks)])
	var aabb := AABB()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh:
			aabb = aabb.merge(mi.mesh.get_aabb())
	print("  mesh AABB size: ", aabb.size)
	root.free()


func _walk(node: Node, depth: int) -> void:
	if depth > 4:
		return
	var extra := ""
	if node is MeshInstance3D and node.mesh:
		var mats := PackedStringArray()
		for s in node.mesh.get_surface_count():
			var m: Material = node.get_active_material(s)
			mats.append(m.get_class() + ("(" + m.shader.resource_path.get_file() + ")" if m is ShaderMaterial and m.shader else ""))
		extra = " surfaces=%d mats=[%s]" % [node.mesh.get_surface_count(), ", ".join(mats)]
	print("  ".repeat(depth + 1), node.name, " <", node.get_class(), ">", extra)
	for c in node.get_children():
		_walk(c, depth + 1)
