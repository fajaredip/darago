class_name HitQuery
extends RefCounted
## Simple melee hit tests. Targets need `global_position`, `body_radius`
## and `can_be_hit()`.


## Returns the candidates inside a horizontal pie slice in front of `origin`.
static func in_arc(origin: Vector3, forward: Vector3, radius: float, arc_degrees: float, height: float, candidates: Array) -> Array:
	var result := []
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	var min_dot := cos(deg_to_rad(arc_degrees * 0.5))
	for c in candidates:
		if not is_instance_valid(c) or not c.can_be_hit():
			continue
		var to: Vector3 = c.global_position - origin
		if absf(to.y) > height:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		var target_radius: float = c.body_radius
		if dist > radius + target_radius:
			continue
		# Point-blank targets always count, otherwise check the angle.
		if arc_degrees >= 360.0 or dist < target_radius + 0.3 or fwd.dot(flat / dist) >= min_dot:
			result.append(c)
	return result
