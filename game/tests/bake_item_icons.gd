extends SceneTree
## Tool: renders 3D item models into transparent inventory icons
## (assets/ui/items/<name>.png), so icons match the look of the game world.
## Run (with a window, not headless):
##   Godot_v4.7.2-stable_win64_console.exe --path game -s res://tests/bake_item_icons.gd

const OUT := "res://assets/ui/items/"
const SIZE := 256
## [model, output name, rotation (degrees), tint]. A tint re-colours the model
## (one necklace model becomes copper, silver and gold).
const ITEMS := [
	["res://assets/kaykit/weapons/sword_1handed.gltf", "sword_iron", Vector3(0, 0, -45), Color.WHITE],
	["res://assets/kaykit/weapons/sword_2handed.gltf", "sword_steel", Vector3(0, 0, -45), Color.WHITE],
	["res://assets/kaykit/weapons/sword_2handed_color.gltf", "sword_knight", Vector3(0, 0, -45), Color.WHITE],
	["res://assets/models/necklace/necklace.obj", "necklace_copper", Vector3(70, 0, 0), Color(1.0, 0.62, 0.42)],
	["res://assets/models/necklace/necklace.obj", "necklace_silver", Vector3(70, 0, 0), Color(0.85, 0.9, 1.0)],
	["res://assets/models/necklace/necklace.obj", "necklace_gold", Vector3(70, 0, 0), Color(1.0, 0.85, 0.35)],
]
const NECKLACE_TEXTURE := "res://assets/models/necklace/necklace_diffuse.png"


func _initialize() -> void:
	await process_frame  # nodes need to be in the tree before transforms are read
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.85)
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.8, 0.85, 1.0)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0, 0, 10)
	vp.add_child(cam)

	for entry in ITEMS:
		var holder := Node3D.new()
		vp.add_child(holder)
		var model := _model(entry[0], entry[3])
		holder.add_child(model)
		holder.rotation_degrees = entry[2]
		# Centre the model and fit it into the frame (10% margin).
		var box := _bounds(holder)
		model.position -= holder.global_transform.basis.inverse() * box.get_center()
		box = _bounds(holder)
		cam.size = maxf(box.size.x, box.size.y) * 1.1
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		img.save_png(OUT + entry[1] + ".png")
		print("baked ", entry[1])
		holder.queue_free()
		await process_frame
	quit()


## World-space bounding box of every mesh under `node`.
func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## A scene (.gltf) is instanced; a bare mesh (.obj) gets a textured metal material.
func _model(path: String, tint: Color) -> Node3D:
	var res := load(path)
	if res is PackedScene:
		return (res as PackedScene).instantiate()
	var mi := MeshInstance3D.new()
	mi.mesh = res as Mesh
	mi.rotation_degrees.y = -90.0  # the necklace pendant points to +X: turn it to face down after the tilt
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(NECKLACE_TEXTURE)
	mat.albedo_color = tint
	mat.metallic = 0.6
	mat.roughness = 0.35
	# The cord is thin at icon size: a little glow in the metal colour and a dark
	# outline (inflated back faces) keep it readable.
	mat.emission_enabled = true
	mat.emission = tint * 0.7
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = Color(0.05, 0.04, 0.03)
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.03
	mat.next_pass = outline
	mi.material_override = mat
	return mi
