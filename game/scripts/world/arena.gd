class_name Arena
extends Node3D
## Dungeon arena built from KayKit Dungeon Remastered pieces (4 m grid):
## tiled floor, stone walls with torches and banners, pillars, props,
## plus the sky, sun and ambient light. Collision uses simple shapes.

const SIZE := 40.0
const TILE := 4.0
const WALL_HEIGHT := 4.0
const PILLAR_RING := 9.0
const PIECES := "res://assets/kaykit/dungeon/"
## Wall variants by position along each side (index 0..9); others are plain.
const WALL_VARIANTS := {1: "wall_arched", 3: "wall_window_closed", 4: "wall_gated", 6: "wall_shelves", 8: "wall_cracked"}
const BANNERS := ["banner_patternA_red", "banner_red", "banner_patternB_red", "banner_shield_red"]

var _scenes := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 12
	_build_environment()
	_build_floor()
	_build_walls()
	for i in 6:
		var a := TAU * i / 6.0
		_build_pillar(Vector3(cos(a), 0.0, sin(a)) * PILLAR_RING)
	_build_props()


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
	env.fog_density = 0.008
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Low evening sun: long shadows, warm key light; torches do the rest.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)


func _build_floor() -> void:
	var body := _static_body(Vector3(0.0, -0.5, 0.0))
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE, 1.0, SIZE)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var half := SIZE * 0.5 - TILE * 0.5
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			# Rock rubble only on the outer ring, so the fighting area stays clean.
			var outer := absf(x) > half - 0.1 or absf(z) > half - 0.1
			var tile := "floor_tile_large_rocks" if outer and _rng.randf() < 0.3 else "floor_tile_large"
			_piece(tile, Vector3(x, 0.0, z), 90.0 * _rng.randi_range(0, 3))
			z += TILE
		x += TILE


func _build_walls() -> void:
	var half := SIZE * 0.5 - 0.5
	# [wall center, inward direction (for rotation and props)]
	var sides := [
		[Vector3(0.0, 0.0, -half), Vector3(0, 0, 1)],
		[Vector3(0.0, 0.0, half), Vector3(0, 0, -1)],
		[Vector3(-half, 0.0, 0.0), Vector3(1, 0, 0)],
		[Vector3(half, 0.0, 0.0), Vector3(-1, 0, 0)],
	]
	for side in sides:
		var center: Vector3 = side[0]
		var inward: Vector3 = side[1]
		var along := Vector3(inward.z, 0.0, -inward.x)
		var yaw := atan2(inward.x, inward.z)
		var size := Vector3(SIZE, WALL_HEIGHT, 1.0) if absf(inward.z) > 0.5 else Vector3(1.0, WALL_HEIGHT, SIZE)
		_collision_box(center + Vector3.UP * WALL_HEIGHT * 0.5, size)
		for i in 10:
			var pos := center + along * (-18.0 + TILE * i)
			var wall_name: String = WALL_VARIANTS.get(i, "wall")
			_piece(wall_name, pos, rad_to_deg(yaw))
			var face := pos + inward * 0.55
			if i == 2 or i == 7:
				_torch(face + Vector3.UP * 2.3, yaw)
			elif i == 0 or i == 5 or i == 9:
				_piece(BANNERS[_rng.randi_range(0, BANNERS.size() - 1)], face - inward * 0.3, rad_to_deg(yaw))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			CameraOcclusion.make_fadeable(_piece("pillar", Vector3(half * sx, 0.0, half * sz), 0.0), 0.9, WALL_HEIGHT)


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


## Clutter along the walls and in the corners; the middle stays open for fights.
func _build_props() -> void:
	var c := SIZE * 0.5 - 2.6
	var layout := [
		["barrel_large", Vector3(-c, 0, -c), 0.0, 0.9], ["barrel_small_stack", Vector3(-c + 2.2, 0, -c), 20.0, 0.8],
		["crates_stacked", Vector3(c, 0, -c), 15.0, 1.0], ["box_stacked", Vector3(c - 2.4, 0, -c + 0.2), -10.0, 0.9],
		["chest_gold", Vector3(-c, 0, c), 45.0, 0.9], ["keg_decorated", Vector3(-c + 2.3, 0, c), 0.0, 0.7],
		["rubble_large", Vector3(c - 1.5, 0, c - 0.5), -135.0, 0.9],
		["table_long_broken", Vector3(-c, 0, 0.0), 90.0, 0.9], ["shelf_large", Vector3(c + 0.9, 0, 6.0), -90.0, 0.9],
		["sword_shield_broken", Vector3(6.0, 0, c + 0.8), 180.0, 1.0], ["candle_triple", Vector3(-6.0, 0, -c - 0.6), 0.0, 1.0],
		["barrel_small", Vector3(c + 0.6, 0, -6.0), 0.0, 0.9], ["box_small_decorated", Vector3(-c - 0.3, 0, 7.0), 30.0, 0.9],
	]
	for p in layout:
		var node := _piece(p[0], p[1], p[2])
		node.scale = Vector3.ONE * float(p[3])
		if p[0] in ["barrel_large", "crates_stacked", "chest_gold", "rubble_large", "table_long_broken", "shelf_large", "box_stacked"]:
			var body := _collision_box(p[1] + Vector3.UP * 0.8, Vector3(1.8, 1.6, 1.8))
			CameraOcclusion.make_fadeable(node, 1.1, 3.2 if p[0] == "shelf_large" else 2.2, body)


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


## Instances a dungeon piece by name (files are "<name>.gltf.glb" or "<name>.glb").
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
