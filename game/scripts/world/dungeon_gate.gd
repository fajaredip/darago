class_name DungeonGate
extends Node3D
## Interactive doorway gate between dungeon rooms.
## Blocks the doorway (collision + closed wooden door) while its room is not clear,
## then the door swings open with sound, dust VFX and screenshake.

signal opened
signal closed

const PIECES := "res://assets/kaykit/dungeon/"
const DOOR_WIDTH := 4.0
const WALL_HEIGHT := 4.0
## Width of the walkable hole in the doorway frame.
const OPENING := 1.8
## How far the door leaf swings open.
const SWING := -1.8326  # -105 degrees

var is_open := false

var _door_frame: Node3D
var _gate_mesh: Node3D
var _collider: CollisionShape3D
var _body: StaticBody3D


func _ready() -> void:
	_build_gate()


func _build_gate() -> void:
	# wall_doorway = stone frame + a wooden door leaf ("wall_doorway_door") whose
	# origin sits on its hinge, so opening is just a swing around Y.
	var frame_scene := _load_piece("wall_doorway")
	if frame_scene:
		_door_frame = frame_scene.instantiate()
		add_child(_door_frame)
		_gate_mesh = _door_frame.find_child("wall_doorway_door", true, false) as Node3D

	_body = StaticBody3D.new()
	_body.collision_layer = Game.LAYER_WORLD
	_body.collision_mask = 0
	add_child(_body)
	# The frame's solid sides always block; only the doorway itself opens.
	for side in [-1.0, 1.0]:
		var side_shape := BoxShape3D.new()
		side_shape.size = Vector3(DOOR_WIDTH * 0.5 - OPENING * 0.5, WALL_HEIGHT, 0.8)
		var side_col := CollisionShape3D.new()
		side_col.shape = side_shape
		side_col.position = Vector3(side * (OPENING * 0.5 + side_shape.size.x * 0.5), WALL_HEIGHT * 0.5, 0.0)
		_body.add_child(side_col)
	var shape := BoxShape3D.new()
	shape.size = Vector3(OPENING, WALL_HEIGHT, 0.8)
	_collider = CollisionShape3D.new()
	_collider.shape = shape
	_collider.position = Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
	_body.add_child(_collider)


func _load_piece(piece_name: String) -> PackedScene:
	var path := PIECES + piece_name + ".gltf.glb"
	if not ResourceLoader.exists(path):
		path = PIECES + piece_name + ".glb"
	if ResourceLoader.exists(path):
		return load(path)
	return null


func open(instant := false) -> void:
	if is_open:
		return
	is_open = true
	_collider.set_deferred("disabled", true)
	if instant:
		if _gate_mesh:
			_gate_mesh.rotation.y = SWING
		opened.emit()
		return

	# Dramatic opening: sound, camera shake, dust ring and tween
	Sfx.play("thud")
	Game.shake(0.35)
	Vfx.ring(global_position + Vector3.UP * 0.1, 2.8, Color(0.8, 0.85, 1.0, 0.6), 0.6)
	if _gate_mesh:
		var tw := create_tween()
		tw.tween_property(_gate_mesh, "rotation:y", SWING, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): opened.emit())
	else:
		opened.emit()


func close(instant := false) -> void:
	if not is_open:
		return
	is_open = false
	_collider.set_deferred("disabled", false)
	if instant:
		if _gate_mesh:
			_gate_mesh.rotation.y = 0.0
		closed.emit()
		return
	Sfx.play("thud")
	Game.shake(0.4)
	if _gate_mesh:
		var tw := create_tween()
		tw.tween_property(_gate_mesh, "rotation:y", 0.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): closed.emit())
	else:
		closed.emit()
