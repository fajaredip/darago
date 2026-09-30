class_name RewardChest
extends Node3D
## Reward chest spawned after completing the dungeon (Dragon Nest Pick-a-Chest).
## Player approaches and presses [F] to open. Drops gold coins + rare/epic gear.

signal picked(chest: RewardChest)

const CHEST_PIECE := "res://assets/kaykit/dungeon/chest_gold.glb"

var is_open := false
var is_locked := false
var chest_index := 0

var _chest_node: Node3D
var _prompt: Label3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_mesh()
	_build_prompt()


func _build_mesh() -> void:
	if ResourceLoader.exists(CHEST_PIECE):
		var scene: PackedScene = load(CHEST_PIECE)
		_chest_node = scene.instantiate()
		add_child(_chest_node)

	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 1.0, 1.4)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.5
	body.add_child(col)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text = "[%s] Buka Peti" % Settings.key_name(&"interact")
	_prompt.font_size = 28
	_prompt.outline_size = 8
	_prompt.modulate = Color(1.0, 0.9, 0.4)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.position = Vector3(0.0, 1.3, 0.0)
	_prompt.visible = false
	add_child(_prompt)


func _process(_delta: float) -> void:
	if is_open or is_locked:
		_prompt.visible = false
		return
	var p := Game.player
	if not p or not is_instance_valid(p):
		_prompt.visible = false
		return
	var dist := global_position.distance_to(p.global_position)
	_prompt.visible = dist <= 3.2
	if _prompt.visible and Input.is_action_just_pressed(&"interact"):
		open()


func open() -> void:
	if is_open or is_locked:
		return
	is_open = true
	_prompt.visible = false
	picked.emit(self)

	Sfx.play("enhance_ok")
	Game.shake(0.3)
	Vfx.ring(global_position + Vector3.UP * 0.1, 2.4, Color(1.0, 0.85, 0.3), 0.6)

	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.18, 1.25, 1.18), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.2)

	# Guaranteed Rare (2) or Epic (3) item drop!
	var rarity := 3 if _rng.randf() < 0.45 else 2
	var drop_item := ItemDB.roll(Progress.dungeon_level(), [0, 0, 55, 45], _rng)
	drop_item["rarity"] = rarity
	var gold_amt := _rng.randi_range(40, 75)

	var p_pos := global_position + Vector3.UP * 0.8
	Loot.spawn(p_pos, gold_amt, drop_item)
	for i in 3:
		var offset := Vector3(_rng.randf_range(-0.7, 0.7), 0.0, _rng.randf_range(-0.7, 0.7))
		Loot.spawn(p_pos + offset, _rng.randi_range(15, 30), {})


func lock_and_fade() -> void:
	if is_open:
		return
	is_locked = true
	_prompt.visible = false
	# Node3D has no modulate: the unpicked chests sink a little and shrink instead.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ONE * 0.8, 0.6).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "position:y", position.y - 0.25, 0.6).set_trans(Tween.TRANS_CUBIC)
