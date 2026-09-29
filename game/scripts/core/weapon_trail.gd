class_name WeaponTrail
extends MeshInstance3D
## Ribbon that follows a weapon's edge while `emitting` and fades out behind it
## (the sword trail of an action game). Built each frame from sampled blade
## base / tip positions, smoothed with Catmull-Rom so fast swings stay round.

const SUBDIVISIONS := 3

## Seconds a sample stays visible.
var lifetime := 0.16
var color := Color(1, 1, 1, 0.9)
var emitting := false
## Hitstop: the trail freezes along with the swing.
var paused := false

var _base: Node3D
var _tip: Node3D
var _bases := PackedVector3Array()
var _tips := PackedVector3Array()
var _ages := PackedFloat32Array()
var _mesh := ImmediateMesh.new()


## Follows the segment from `base_offset` to `tip_offset` in the weapon's space.
func setup(weapon: Node3D, base_offset: Vector3, tip_offset: Vector3) -> void:
	_base = Node3D.new()
	weapon.add_child(_base)
	_base.position = base_offset
	_tip = Node3D.new()
	weapon.add_child(_tip)
	_tip.position = tip_offset


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	material_override = Vfx.unshaded(Color.WHITE, true, true)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if _base == null:
		return
	if not paused:
		for i in _ages.size():
			_ages[i] += delta
		if emitting:
			_bases.append(_base.global_position)
			_tips.append(_tip.global_position)
			_ages.append(0.0)
		while not _ages.is_empty() and _ages[0] > lifetime:
			_bases.remove_at(0)
			_tips.remove_at(0)
			_ages.remove_at(0)
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var n := _ages.size()
	if n < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n - 1:
		for s in SUBDIVISIONS:
			var t := float(s) / SUBDIVISIONS
			_add_pair(_spline(_bases, i, t), _spline(_tips, i, t), lerpf(_ages[i], _ages[i + 1], t))
	_add_pair(_bases[n - 1], _tips[n - 1], _ages[n - 1])
	_mesh.surface_end()


func _add_pair(base: Vector3, tip: Vector3, age: float) -> void:
	var fade := clampf(1.0 - age / lifetime, 0.0, 1.0)
	_mesh.surface_set_color(Color(color.r, color.g, color.b, color.a * fade * 0.1))
	_mesh.surface_add_vertex(base)
	_mesh.surface_set_color(Color(color.r, color.g, color.b, color.a * fade))
	_mesh.surface_add_vertex(tip)


static func _spline(points: PackedVector3Array, i: int, t: float) -> Vector3:
	var n := points.size()
	var p0 := points[maxi(i - 1, 0)]
	var p1 := points[i]
	var p2 := points[mini(i + 1, n - 1)]
	var p3 := points[mini(i + 2, n - 1)]
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)
