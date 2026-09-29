extends SceneTree
## Dev tool: prints the bounding box of each model (to lay out modular pieces)
## and optionally its animation names.
##   Godot --headless --path game -s res://tests/measure_assets.gd -- [--anims] <res://path> [...]


func _initialize() -> void:
	var show_anims := false
	for path in OS.get_cmdline_user_args():
		if path == "--anims":
			show_anims = true
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			print(path, ": cannot load")
			continue
		var root := packed.instantiate()
		var aabb := _aabb(root, Transform3D.IDENTITY)
		print("%s  size=%s  pos=%s" % [path.get_file(), _v(aabb.size), _v(aabb.position)])
		if show_anims:
			for player: AnimationPlayer in root.find_children("*", "AnimationPlayer", true, false):
				var names := PackedStringArray()
				for n in player.get_animation_list():
					names.append("%s(%.2f)" % [n, player.get_animation(n).length])
				print("  anims: ", ", ".join(names))
		root.free()
	quit()


func _aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var have := false
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		result = t * (node as MeshInstance3D).mesh.get_aabb()
		have = true
	for c in node.get_children():
		var sub := _aabb(c, t)
		if sub.size != Vector3.ZERO:
			result = sub if not have else result.merge(sub)
			have = true
	return result


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
