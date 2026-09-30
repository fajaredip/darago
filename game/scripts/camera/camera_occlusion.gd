class_name CameraOcclusion
extends Node
## Fades pillars and props that block the view of the player or sit right in
## front of the camera, instead of letting the camera arm snap in behind them.
## Level pieces opt in with `CameraOcclusion.make_fadeable()`; their collision
## bodies are then ignored by the camera arm.

const GROUP := &"camera_fade"
## How see-through a blocking piece becomes (0 = solid, 1 = invisible).
const FADED := 0.72
const FADE_SPEED := 6.0
## Extra room around a piece's radius that still counts as "in the way".
const LINE_MARGIN := 0.35
## A piece this close (horizontally, beyond its radius) to the camera fades too.
const NEAR_CAMERA := 1.3

var _rig: CameraRig
## visual node -> current transparency
var _amount := {}
## visual node -> Array of [MeshInstance3D, surface index, see-through copy of its material, original alpha]
var _surfaces := {}
## Frames left in which every piece is drawn with its see-through material, so
## those shaders are compiled before the fight instead of on the first fade.
var _warm_frames := 3


## Marks `visual` (and its collision `body`, if any) as a piece the camera may
## look through. The piece is treated as an upright cylinder at the visual's origin.
static func make_fadeable(visual: Node3D, radius: float, height: float, body: CollisionObject3D = null) -> void:
	visual.add_to_group(GROUP)
	visual.set_meta(&"fade_radius", radius)
	visual.set_meta(&"fade_height", height)
	if body:
		visual.set_meta(&"fade_body", body)


func setup(rig: CameraRig, arm: SpringArm3D) -> void:
	_rig = rig
	for visual: Node3D in get_tree().get_nodes_in_group(GROUP):
		if visual.has_meta(&"fade_body"):
			var body: CollisionObject3D = visual.get_meta(&"fade_body")
			arm.add_excluded_object(body.get_rid())
		_surfaces[visual] = _see_through_surfaces(visual)
		_apply(visual, 0.001)


## Transparency of a piece right now (for tests).
func amount(visual: Node3D) -> float:
	return _amount.get(visual, 0.0)


## Alpha the piece is actually drawn with (1 = solid), read from its materials.
func drawn_alpha(visual: Node3D) -> float:
	var alpha := 1.0
	for s: Array in _surfaces.get(visual, []):
		var mat := (s[0] as MeshInstance3D).get_surface_override_material(s[1]) as BaseMaterial3D
		if mat:
			alpha = minf(alpha, mat.albedo_color.a)
	return alpha


func _process(delta: float) -> void:
	if _rig == null or _rig.camera == null:
		return
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			for visual: Node3D in _surfaces:
				_apply(visual, 0.0)
		return
	var target := _rig.global_position  # the point the camera looks at, above the head
	var cam: Vector3 = _rig.camera.global_position
	var aims: Array[Vector3] = [target, target + Vector3.DOWN * 1.0]
	for visual: Node3D in _surfaces:
		if not is_instance_valid(visual):
			continue
		var goal := FADED if _blocks(visual, cam, aims) else 0.0
		var now: float = _amount.get(visual, 0.0)
		if is_equal_approx(now, goal):
			continue
		now = move_toward(now, goal, FADE_SPEED * delta)
		_amount[visual] = now
		_apply(visual, now)

func _blocks(visual: Node3D, cam: Vector3, aims: Array[Vector3]) -> bool:
	var radius: float = visual.get_meta(&"fade_radius")
	var height: float = visual.get_meta(&"fade_height")
	var base := visual.global_position
	var center := Vector2(base.x, base.z)
	var cam2 := Vector2(cam.x, cam.z)
	if cam2.distance_to(center) < radius + NEAR_CAMERA and cam.y < base.y + height + 1.0:
		return true
	for aim in aims:
		var aim2 := Vector2(aim.x, aim.z)
		var seg := aim2 - cam2
		var len_sq := seg.length_squared()
		if len_sq < 0.0001:
			continue
		var t := clampf((center - cam2).dot(seg) / len_sq, 0.0, 1.0)
		if t >= 0.98:
			continue  # the piece is beyond the player, not in between
		if center.distance_to(cam2 + seg * t) > radius + LINE_MARGIN:
			continue
		# Height of the sight line where it passes the piece.
		if lerpf(cam.y, aim.y, t) < base.y + height:
			return true
	return false


## The GeometryInstance3D.transparency property has no effect in the Mobile
## renderer, so each surface gets its own alpha-blended copy of its material.
func _see_through_surfaces(visual: Node3D) -> Array:
	var out := []
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var copy := src.duplicate() as BaseMaterial3D
			# Depth pre-pass: the piece still sorts against itself, so no inner faces show through.
			copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			out.append([mi, s, copy, src.albedo_color.a])
	return out


func _apply(visual: Node3D, value: float) -> void:
	for s: Array in _surfaces.get(visual, []):
		var mi := s[0] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		if value <= 0.0:
			mi.set_surface_override_material(s[1], null)
			continue
		var copy := s[2] as BaseMaterial3D
		copy.albedo_color.a = float(s[3]) * (1.0 - value)
		mi.set_surface_override_material(s[1], copy)
