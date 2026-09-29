extends SceneTree
## Dev tool: computes how a sword should sit in a humanoid's hand from the
## skeleton's own finger bones (rest pose), and prints weapon_position /
## weapon_rotation for the class .tres.
##   Godot --headless --path game -s res://tests/compute_grip.gd -- <model> [Right|Left] [tilt] [reverse]
##
## Grip model: the blade leaves the fist on the thumb/index side, i.e. along the
## knuckle line from little finger to index finger; the blade's flat faces the
## palm. The sword model's blade runs along its +Y, its flat faces +Z.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var side := args[1] if args.size() > 1 else "Right"
	var model: Node3D = load(args[0]).instantiate()
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var hand := _rest(skel, side + "Hand")
	var index := _rest(skel, side + "IndexProximal").origin
	var little := _rest(skel, side + "LittleProximal").origin
	var middle := _rest(skel, side + "MiddleProximal").origin
	var thumb := _rest(skel, side + "ThumbProximal").origin

	var knuckles := (index - little).normalized()  # blade direction
	if args.size() > 3 and args[3] == "reverse":
		knuckles = -knuckles  # blade out of the little-finger side (trailing carry)
	var fingers := (middle - hand.origin).normalized()
	var palm := fingers.cross(knuckles).normalized()  # palm normal (sign checked below)
	# The thumb sits on the palm side; flip the normal to point toward it.
	if palm.dot(thumb - hand.origin) < 0.0:
		palm = -palm
	# Blade slightly tilted forward from the knuckle line, like a real grip.
	var tilt := float(args[2]) if args.size() > 2 else 0.25
	var blade := (knuckles + fingers * tilt).normalized()
	var flat := (palm - blade * palm.dot(blade)).normalized()
	var world := Basis(blade.cross(flat), blade, flat)  # columns: X, Y (blade), Z (flat)
	var local := hand.basis.inverse() * world
	# Fist centre: a bit past the wrist toward the knuckles, on the palm side.
	var grip_world := hand.origin.lerp(middle, 0.55) + palm * 0.02
	var grip_local := hand.basis.inverse() * (grip_world - hand.origin)

	var euler := local.orthonormalized().get_euler() * (180.0 / PI)
	print("knuckles=%s fingers=%s palm=%s" % [knuckles, fingers, palm])
	print("weapon_position = Vector3(%.3f, %.3f, %.3f)" % [grip_local.x, grip_local.y, grip_local.z])
	print("weapon_rotation = Vector3(%.1f, %.1f, %.1f)" % [euler.x, euler.y, euler.z])
	model.free()
	quit()


func _rest(skel: Skeleton3D, bone: String) -> Transform3D:
	var idx := skel.find_bone(bone)
	assert(idx >= 0, "bone not found: " + bone)
	return skel.get_bone_global_rest(idx)
