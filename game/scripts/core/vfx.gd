class_name Vfx
extends RefCounted
## Placeholder materials and effects built in code (no textures needed).
## Spawned effects are parented to Game.world and free themselves.

static var _arc_cache := {}
static var _sphere: SphereMesh
static var _streak: BoxMesh
static var _keepalive: Array[Material] = []


## Call once at level start, before any fighting.
## 1. Keeps one material of every variant alive. Godot builds a material's shader
##    when its RID is first requested and frees it with its last user, so our
##    short-lived effects recompiled it on every spawn (measured 16-25 ms each).
## 2. Spawns every effect and glyph once, nearly invisible, so meshes and font
##    glyphs are built before the first hit instead of during it.
static func warm_up(at: Vector3, attacks: Array[AttackData], enemies: Array[EnemyStats]) -> void:
	var faint := Color(1, 1, 1, 0.01)
	_keepalive = [unshaded(faint, true, true), unshaded(faint, true, false), unshaded(faint, false, true),
			unshaded(faint, false, false), overlay_material(), solid(Color.WHITE), glow(Color.WHITE)]
	for m in _keepalive:
		m.get_rid()
	for size in [1.0, 1.35]:
		float_text(at, "0123456789!DODGE", faint, size)
	for a in attacks:
		if a and a.impact_ring:
			ring(at, a.impact_radius if a.impact_radius > 0.0 else a.radius, faint)
	for e in enemies:
		ring(at, e.attack_radius, faint)
	hit_spark(at, faint)
	ring(at, 1.0, faint)


## Drops cached meshes (called on exit so nothing is reported as leaked).
static func clear_cache() -> void:
	_arc_cache.clear()
	_sphere = null
	_streak = null
	_keepalive.clear()


static func solid(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.4
	return m


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func unshaded(color: Color, additive := false, vertex_alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.vertex_color_use_as_albedo = vertex_alpha
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## Transparent layer drawn over a character, used for hit flashes and tints.
static func overlay_material() -> StandardMaterial3D:
	var m := unshaded(Color(1, 1, 1, 0))
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


## Flat pie / ring slice on the XZ plane, centred on -Z (forward).
## radial_fade: inner edge transparent. sweep: +1 / -1 fades the arc toward one side.
static func arc_mesh(inner: float, outer: float, arc_degrees: float, radial_fade := true, sweep := 0) -> ArrayMesh:
	var key := "%s|%s|%s|%s|%s" % [inner, outer, arc_degrees, radial_fade, sweep]
	if _arc_cache.has(key):
		return _arc_cache[key]
	var segments := maxi(8, int(arc_degrees / 6.0))
	var half := deg_to_rad(minf(arc_degrees, 360.0)) * 0.5
	var inner_alpha := 0.0 if radial_fade else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var k0 := float(i) / segments
		var k1 := float(i + 1) / segments
		var a0 := lerpf(-half, half, k0)
		var a1 := lerpf(-half, half, k1)
		var d0 := Vector3(sin(a0), 0.0, -cos(a0))
		var d1 := Vector3(sin(a1), 0.0, -cos(a1))
		var s0 := _sweep_alpha(k0, sweep)
		var s1 := _sweep_alpha(k1, sweep)
		var in0 := Color(1, 1, 1, inner_alpha * s0)
		var in1 := Color(1, 1, 1, inner_alpha * s1)
		var out0 := Color(1, 1, 1, s0)
		var out1 := Color(1, 1, 1, s1)
		st.set_color(in0)
		st.add_vertex(d0 * inner)
		st.set_color(out0)
		st.add_vertex(d0 * outer)
		st.set_color(out1)
		st.add_vertex(d1 * outer)
		st.set_color(in0)
		st.add_vertex(d0 * inner)
		st.set_color(out1)
		st.add_vertex(d1 * outer)
		st.set_color(in1)
		st.add_vertex(d1 * inner)
	var mesh := st.commit()
	_arc_cache[key] = mesh
	return mesh


static func _sweep_alpha(k: float, sweep: int) -> float:
	if sweep > 0:
		return k * k
	if sweep < 0:
		return (1.0 - k) * (1.0 - k)
	return 1.0


## Bright flash plus flying streaks where a hit lands.
static func hit_spark(pos: Vector3, color: Color, size := 1.0) -> void:
	var world := Game.world
	if world == null:
		return
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 12
		_sphere.rings = 6
		_streak = BoxMesh.new()
		_streak.size = Vector3(0.06, 0.06, 1.0)
	var flash := MeshInstance3D.new()
	flash.mesh = _sphere
	var flash_mat := unshaded(Color(1, 1, 1, 0.9), true)
	flash.material_override = flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 1.3 * size, 0.1).from(Vector3.ONE * 0.3 * size)
	tw.tween_property(flash_mat, "albedo_color:a", 0.0, 0.1)
	tw.chain().tween_callback(flash.queue_free)
	var streak_mat := unshaded(color.lightened(0.3), true)
	for i in 7:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.8), randf_range(-1.0, 1.0)).normalized()
		var s := MeshInstance3D.new()
		s.mesh = _streak
		s.material_override = streak_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(s)
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		s.global_transform = Transform3D(Basis.looking_at(dir, up), pos)
		var length := randf_range(0.4, 0.9) * size
		s.scale = Vector3(1.0, 1.0, length)
		var st := s.create_tween().set_parallel(true)
		st.tween_property(s, "global_position", pos + dir * length * 1.4, 0.14).set_ease(Tween.EASE_OUT)
		st.tween_property(s, "scale", Vector3(0.3, 0.3, 0.05), 0.14)
		st.chain().tween_callback(s.queue_free)


static func damage_number(pos: Vector3, amount: float, color: Color, crit := false) -> void:
	float_text(pos, str(roundi(amount)) + ("!" if crit else ""), color, 1.35 if crit else 1.0)


## Billboard text that pops, rises and fades.
static func float_text(pos: Vector3, text: String, color: Color, size := 1.0) -> void:
	var world := Game.world
	if world == null:
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = int(56 * size)
	l.outline_size = 14
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.render_priority = 10
	l.outline_render_priority = 9
	world.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.3), randf_range(-0.35, 0.35))
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).from(Vector3.ONE * 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y + 0.9, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


## Expanding ring on the ground: shockwaves, dust, spawn marks.
static func ring(pos: Vector3, radius: float, color: Color, duration := 0.3) -> void:
	var world := Game.world
	if world == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = arc_mesh(0.75, 1.0, 360.0, false, 0)
	var mat := unshaded(color, true, true)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration).from(Vector3(radius * 0.3, 1.0, radius * 0.3)).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
