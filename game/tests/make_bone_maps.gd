extends SceneTree
## Dev tool: writes the BoneMap resources that retarget the Quaternius animation
## libraries onto Godot's SkeletonProfileHumanoid (same profile the VRM
## importer uses), so their animations play on the anime characters.
##   Godot --headless --path game -s res://tests/make_bone_maps.gd

const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Little": "pinky"}
const SEGMENTS_THUMB := ["Metacarpal", "Proximal", "Distal"]
const SEGMENTS := ["Proximal", "Intermediate", "Distal"]


func _initialize() -> void:
	_save("res://assets/animations/ual1_bone_map.tres", _ual1())
	_save("res://assets/animations/ual2_bone_map.tres", _ual2())
	quit()


## Universal Animation Library 1 (Rigify "DEF-" names).
func _ual1() -> Dictionary:
	var m := {
		"Root": "root", "Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002",
		"UpperChest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head",
	}
	for side in [["Left", "L"], ["Right", "R"]]:
		var s: String = side[0]
		var x: String = side[1]
		m[s + "Shoulder"] = "DEF-shoulder." + x
		m[s + "UpperArm"] = "DEF-upper_arm." + x
		m[s + "LowerArm"] = "DEF-forearm." + x
		m[s + "Hand"] = "DEF-hand." + x
		m[s + "UpperLeg"] = "DEF-thigh." + x
		m[s + "LowerLeg"] = "DEF-shin." + x
		m[s + "Foot"] = "DEF-foot." + x
		m[s + "Toes"] = "DEF-toe." + x
		for finger in FINGERS:
			var segs: Array = SEGMENTS_THUMB if finger == "Thumb" else SEGMENTS
			var src: String = "DEF-thumb" if finger == "Thumb" else "DEF-f_" + FINGERS[finger]
			for i in 3:
				m[s + finger + segs[i]] = "%s.%02d.%s" % [src, i + 1, x]
	return m


## Universal Animation Library 2 (Unreal-mannequin names).
func _ual2() -> Dictionary:
	var m := {
		"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02",
		"UpperChest": "spine_03", "Neck": "neck_01", "Head": "Head",
	}
	for side in [["Left", "l"], ["Right", "r"]]:
		var s: String = side[0]
		var x: String = side[1]
		m[s + "Shoulder"] = "clavicle_" + x
		m[s + "UpperArm"] = "upperarm_" + x
		m[s + "LowerArm"] = "lowerarm_" + x
		m[s + "Hand"] = "hand_" + x
		m[s + "UpperLeg"] = "thigh_" + x
		m[s + "LowerLeg"] = "calf_" + x
		m[s + "Foot"] = "foot_" + x
		m[s + "Toes"] = "ball_" + x
		for finger in FINGERS:
			var segs: Array = SEGMENTS_THUMB if finger == "Thumb" else SEGMENTS
			for i in 3:
				m[s + finger + segs[i]] = "%s_%02d_%s" % [FINGERS[finger], i + 1, x]
	return m


func _save(path: String, mapping: Dictionary) -> void:
	var bone_map := BoneMap.new()
	var profile := SkeletonProfileHumanoid.new()
	bone_map.profile = profile
	var missing := PackedStringArray()
	for i in profile.bone_size:
		var bone := profile.get_bone_name(i)
		if mapping.has(bone):
			bone_map.set_skeleton_bone_name(bone, mapping[bone])
		else:
			missing.append(bone)
	var err := ResourceSaver.save(bone_map, path)
	print("%s: %d mapped, unmapped profile bones: %s (save err %d)" % [path, mapping.size(), ", ".join(missing), err])
