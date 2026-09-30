class_name Arena
extends Node3D
## Multi-room dungeon built from KayKit Dungeon Remastered pieces (4 m grid):
## - Room 1 (Penyusupan / Antechamber): Z in [14, 34]
## - Gate 1: at Z = 14
## - Room 2 (Aula Pilar / Grand Pillar Hall): Z in [-14, 14] with the 6-pillar ring
## - Gate 2 (Boss Gate): at Z = -14
## - Room 3 (Kubah Boss / Boss Chamber): Z in [-44, -14]
## With tiled floors, stone walls, torches, banners, and interactive gates.

const TILE := 4.0
const WALL_HEIGHT := 4.0
const PILLAR_RING := 9.0
const PIECES := "res://assets/kaykit/dungeon/"
const BANNERS := ["banner_patternA_red", "banner_red", "banner_patternB_red", "banner_shield_red"]

var gate_1: DungeonGate
var gate_2: DungeonGate
var portal_node: Node3D

var _scenes := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 12
	_build_environment()
	_build_floor()
	_build_walls()
	_build_gates()
	# The 6 pillars in Room 2 (preserves exact PILLAR_RING positions for tests)
	for i in 6:
		var a := TAU * i / 6.0
		_build_pillar(Vector3(cos(a), 0.0, sin(a)) * PILLAR_RING)
	# Additional framing pillars in Room 3 (Boss Chamber)
	_build_pillar(Vector3(-10.0, 0.0, -22.0))
	_build_pillar(Vector3(10.0, 0.0, -22.0))
	_build_pillar(Vector3(-10.0, 0.0, -38.0))
	_build_pillar(Vector3(10.0, 0.0, -38.0))
	_build_props()
	_build_portal(Vector3(0.0, 0.1, -42.0))


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.2, 0.38)
	sky_mat.sky_horizon_color = Color(0.55, 0.45, 0.5)
	sky_mat.ground_horizon_color = Color(0.3, 0.26, 0.28)
	sky_mat.ground_bottom_color = Color(0.1, 0.09, 0.1)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.75)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.3, 0.42)
	env.fog_density = 0.007
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Low evening sun: long shadows, warm key light
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_floor() -> void:
	# Single unified floor collider spanning all 3 rooms
	_collision_box(Vector3(0.0, -0.5, -5.0), Vector3(38.0, 1.0, 88.0))

	# Floor grid across X: [-16, 16], Z: [-44, 32]
	var min_x := -16.0
	var max_x := 16.0
	var min_z := -44.0
	var max_z := 32.0

	var x := min_x
	while x <= max_x:
		var z := min_z
		while z <= max_z:
			var outer := absf(x) > max_x - 1.0 or z < min_z + 1.0 or z > max_z - 1.0
			var tile := "floor_tile_large_rocks" if outer and _rng.randf() < 0.25 else "floor_tile_large"
			_piece(tile, Vector3(x, 0.0, z), 90.0 * _rng.randi_range(0, 3))
			z += TILE
		x += TILE


func _build_walls() -> void:
	# Perimeter walls
	# North wall (Z = -46.0)
	_build_wall_row(Vector3(-18.0, 0.0, -46.0), Vector3(18.0, 0.0, -46.0), Vector3(0, 0, 1))
	# South wall (Z = 34.0)
	_build_wall_row(Vector3(-18.0, 0.0, 34.0), Vector3(18.0, 0.0, 34.0), Vector3(0, 0, -1))
	# West wall (X = -18.0)
	_build_wall_col(Vector3(-18.0, 0.0, -46.0), Vector3(-18.0, 0.0, 34.0), Vector3(1, 0, 0))
	# East wall (X = 18.0)
	_build_wall_col(Vector3(18.0, 0.0, -46.0), Vector3(18.0, 0.0, 34.0), Vector3(-1, 0, 0))

	# Partition 1 at Z = 14.0. Wall pieces are 4 m wide and centred on their
	# position, so the rows stop at x = -4 / 4: the gate fills x in [-2, 2].
	_build_wall_row(Vector3(-16.0, 0.0, 14.0), Vector3(-4.0, 0.0, 14.0), Vector3(0, 0, -1))
	_build_wall_row(Vector3(4.0, 0.0, 14.0), Vector3(16.0, 0.0, 14.0), Vector3(0, 0, -1))

	# Partition 2 at Z = -14.0 (with gap for Gate 2 at X = 0)
	_build_wall_row(Vector3(-16.0, 0.0, -14.0), Vector3(-4.0, 0.0, -14.0), Vector3(0, 0, 1))
	_build_wall_row(Vector3(4.0, 0.0, -14.0), Vector3(16.0, 0.0, -14.0), Vector3(0, 0, 1))

	# Corner pillars
	for sx in [-16.0, 16.0]:
		for sz in [-44.0, 32.0]:
			CameraOcclusion.make_fadeable(_piece("pillar", Vector3(sx, 0.0, sz), 0.0), 0.9, WALL_HEIGHT)


func _build_wall_row(start_pos: Vector3, end_pos: Vector3, inward: Vector3) -> void:
	var yaw := atan2(inward.x, inward.z)
	var length := absf(end_pos.x - start_pos.x)
	var center := (start_pos + end_pos) * 0.5
	# Pieces reach half a tile past the first and last position.
	_collision_box(center + Vector3.UP * WALL_HEIGHT * 0.5, Vector3(length + TILE, WALL_HEIGHT, 1.0))

	var x := start_pos.x
	var i := 0
	while x <= end_pos.x:
		var pos := Vector3(x, 0.0, start_pos.z)
		var wall_name := "wall_arched" if i % 3 == 1 else "wall"
		_piece(wall_name, pos, rad_to_deg(yaw))
		var face := pos + inward * 0.55
		if i % 3 == 0:
			_torch(face + Vector3.UP * 2.3, yaw)
		elif i % 3 == 2 and _rng.randf() < 0.6:
			_piece(BANNERS[_rng.randi_range(0, BANNERS.size() - 1)], face - inward * 0.3, rad_to_deg(yaw))
		x += TILE
		i += 1


func _build_wall_col(start_pos: Vector3, end_pos: Vector3, inward: Vector3) -> void:
	var yaw := atan2(inward.x, inward.z)
	var length := absf(end_pos.z - start_pos.z)
	var center := (start_pos + end_pos) * 0.5
	_collision_box(center + Vector3.UP * WALL_HEIGHT * 0.5, Vector3(1.0, WALL_HEIGHT, length))

	var z := start_pos.z
	var i := 0
	while z <= end_pos.z:
		var pos := Vector3(start_pos.x, 0.0, z)
		var wall_name := "wall_window_closed" if i % 4 == 1 else "wall"
		_piece(wall_name, pos, rad_to_deg(yaw))
		var face := pos + inward * 0.55
		if i % 4 == 0:
			_torch(face + Vector3.UP * 2.3, yaw)
		elif i % 4 == 2 and _rng.randf() < 0.5:
			_piece(BANNERS[_rng.randi_range(0, BANNERS.size() - 1)], face - inward * 0.3, rad_to_deg(yaw))
		z += TILE
		i += 1


func _build_gates() -> void:
	gate_1 = DungeonGate.new()
	gate_1.position = Vector3(0.0, 0.0, 14.0)
	gate_1.rotation.y = deg_to_rad(180.0)
	add_child(gate_1)

	gate_2 = DungeonGate.new()
	gate_2.position = Vector3(0.0, 0.0, -14.0)
	add_child(gate_2)


func _build_pillar(pos: Vector3) -> void:
	var body := _static_body(pos)
	var shape := CylinderShape3D.new()
	shape.radius = 0.8
	shape.height = WALL_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = WALL_HEIGHT * 0.5
	body.add_child(col)
	var visual := _piece("pillar_decorated", pos, rad_to_deg(atan2(pos.x, pos.z)))
	CameraOcclusion.make_fadeable(visual, 0.9, WALL_HEIGHT, body)


func _build_props() -> void:
	var props := [
		# Room 1 props
		["barrel_large", Vector3(-12.0, 0, 30.0), 0.0, 0.9],
		["barrel_small_stack", Vector3(-10.0, 0, 30.0), 20.0, 0.8],
		["crates_stacked", Vector3(12.0, 0, 30.0), 15.0, 1.0],
		["box_stacked", Vector3(10.0, 0, 30.0), -10.0, 0.9],
		# Room 2 props
		["shelf_large", Vector3(-14.0, 0, 6.0), 90.0, 0.9],
		["barrel_large", Vector3(14.0, 0, -6.0), 0.0, 0.9],
		["table_long_broken", Vector3(-12.0, 0, -4.0), 90.0, 0.9],
		["rubble_large", Vector3(12.0, 0, 4.0), -135.0, 0.9],
		# Room 3 props (Boss Room)
		["candle_triple", Vector3(-4.0, 0, -42.0), 0.0, 1.1],
		["candle_triple", Vector3(4.0, 0, -42.0), 0.0, 1.1],
		["sword_shield_broken", Vector3(-8.0, 0, -40.0), 45.0, 1.0],
	]
	for p in props:
		var node := _piece(p[0], p[1], p[2])
		node.scale = Vector3.ONE * float(p[3])
		if p[0] in ["barrel_large", "crates_stacked", "table_long_broken", "shelf_large", "box_stacked"]:
			var body := _collision_box(p[1] + Vector3.UP * 0.8, Vector3(1.8, 1.6, 1.8))
			CameraOcclusion.make_fadeable(node, 1.1, 3.2 if p[0] == "shelf_large" else 2.2, body)


func _build_portal(pos: Vector3) -> void:
	portal_node = Node3D.new()
	portal_node.position = pos
	add_child(portal_node)

	# Portal frame
	_piece("wall_arched", pos, 0.0)
	# Glowing portal ring
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.1
	ring_mesh.outer_radius = 1.5
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.rotation.x = deg_to_rad(90.0)
	ring.position.y = 1.8
	ring.material_override = Vfx.glow(Color(0.2, 0.75, 1.0, 0.9), 4.0)
	portal_node.add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.8, 1.0)
	light.light_energy = 2.5
	light.omni_range = 8.0
	light.position.y = 1.8
	portal_node.add_child(light)

	# Start hidden until boss is defeated
	portal_node.visible = false


func show_portal() -> void:
	if portal_node:
		portal_node.visible = true
		portal_node.scale = Vector3.ZERO
		var tw := create_tween()
		tw.tween_property(portal_node, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _torch(pos: Vector3, yaw: float) -> void:
	_piece("torch_mounted", pos, rad_to_deg(yaw))
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.14
	flame_mesh.height = 0.36
	var flame := MeshInstance3D.new()
	flame.mesh = flame_mesh
	flame.material_override = Vfx.glow(Color(1.0, 0.6, 0.2), 5.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inward := Vector3(sin(yaw), 0.0, cos(yaw))
	flame.position = pos + Vector3.UP * 0.62 + inward * 0.28
	add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.omni_attenuation = 1.4
	light.position = flame.position + inward * 0.4
	add_child(light)


func _piece(piece_name: String, pos: Vector3, yaw_deg: float) -> Node3D:
	if not _scenes.has(piece_name):
		var path := PIECES + piece_name + ".gltf.glb"
		if not ResourceLoader.exists(path):
			path = PIECES + piece_name + ".glb"
		_scenes[piece_name] = load(path)
	var node: Node3D = _scenes[piece_name].instantiate()
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	add_child(node)
	return node


func _static_body(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	return body


func _collision_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := _static_body(center)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body
