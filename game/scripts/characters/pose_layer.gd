class_name PoseLayer
extends SkeletonModifier3D
## Holds some bones in a fixed pose on top of whatever animation plays, blended
## by `influence` (e.g. the sword arm stays steady while the body runs).


var _bones := PackedInt32Array()
var _rotations: Array[Quaternion] = []


## Copies the local rotations of `bone_names` from `anim` at `time`.
## `track_prefix` is how the animation addresses the skeleton.
func capture(anim: Animation, time: float, bone_names: PackedStringArray, skeleton: Skeleton3D, track_prefix := "%GeneralSkeleton:") -> void:
	_bones.clear()
	_rotations.clear()
	for bone in bone_names:
		var idx := skeleton.find_bone(bone)
		var track := anim.find_track(NodePath(track_prefix + bone), Animation.TYPE_ROTATION_3D)
		if idx < 0 or track < 0:
			push_warning("PoseLayer: no bone or rotation track for '%s'" % bone)
			continue
		_bones.append(idx)
		_rotations.append(anim.rotation_track_interpolate(track, time))


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for i in _bones.size():
		skeleton.set_bone_pose_rotation(_bones[i], _rotations[i])
