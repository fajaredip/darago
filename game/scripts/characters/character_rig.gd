class_name CharacterRig
extends Node3D
## Visual body of a character: an imported model, the AnimationPlayer that
## drives it and attached weapons. Gameplay code only calls play()/hold()/
## freeze(), so models and animation sets can be swapped per class or enemy.

var player: AnimationPlayer
var skeleton: Skeleton3D
var model: Node3D

var _current: StringName = &""
var _speed := 1.0
var _frozen := false


## Sets up a model. `libraries` maps library names to AnimationLibrary resources
## played on the humanoid skeleton (VRM + retargeted animations). Without
## libraries, the model's own AnimationPlayer is used (KayKit characters).
func setup(scene: PackedScene, overlay: Material, libraries: Dictionary = {}, model_scale := 1.0, turn_around := false) -> void:
	model = scene.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * model_scale
	if turn_around:
		model.rotation.y += PI  # glTF models face +Z; our characters face -Z
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	if libraries.is_empty():
		player = model.find_children("*", "AnimationPlayer", true, false)[0]
	else:
		player = AnimationPlayer.new()
		player.name = "BodyAnimator"
		model.add_child(player)
		player.root_node = NodePath("..")
		# Root-motion clips move the "Root" bone; gameplay code moves the body instead.
		player.root_motion_track = NodePath("%GeneralSkeleton:Root")
		for lib_name in libraries:
			player.add_animation_library(lib_name, libraries[lib_name])
	player.playback_default_blend_time = 0.1
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = overlay


## Plays an animation (no-op if it is already playing, except for a speed update).
func play(anim: StringName, blend := 0.12, speed := 1.0, from := -1.0) -> void:
	if anim == &"" or not player.has_animation(anim):
		return
	_speed = speed
	if anim == _current and from < 0.0 and player.is_playing():
		_apply_speed()
		return
	_current = anim
	player.play(anim, blend)
	if from >= 0.0:
		player.seek(from, true)
	_apply_speed()


## Freezes the pose of `anim` at `time` (used for held poses like spins).
func hold(anim: StringName, time: float, blend := 0.06) -> void:
	play(anim, blend, 1.0, time)
	_speed = 0.0
	_apply_speed()


## Hitstop: pauses animation while true.
func freeze(on: bool) -> void:
	if on == _frozen:
		return
	_frozen = on
	_apply_speed()


func current() -> StringName:
	return _current


## Makes looping clips (locomotion) loop even if the source file didn't mark them.
func set_looping(anims: Array[StringName]) -> void:
	for anim in anims:
		if player.has_animation(anim):
			player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR


## Adds a layer that can hold `bones` in the pose `anim` has at `time`
## (blend it in and out with the returned layer's `influence`).
func add_pose_layer(bones: PackedStringArray, anim: StringName, time: float) -> PoseLayer:
	var layer := PoseLayer.new()
	layer.influence = 0.0
	skeleton.add_child(layer)
	if player.has_animation(anim):
		layer.capture(player.get_animation(anim), time, bones, skeleton)
	return layer


## Attaches `node` to a skeleton bone with a local offset.
func attach(node: Node3D, bone: StringName, offset: Transform3D) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	attachment.add_child(node)
	node.transform = offset


func _apply_speed() -> void:
	player.speed_scale = 0.0 if _frozen else _speed
