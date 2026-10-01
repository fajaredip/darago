class_name Loot
extends Node3D
## Gold or an item lying on the floor. It pops out of a defeated enemy, waits
## a moment, then flies to the player once they come near and is collected.

const PICKUP_RADIUS := 2.4
const PICKUP_DELAY := 0.45
const FLY_SPEED := 14.0
const COIN_SINGLE := preload("res://assets/kaykit/dungeon/coin.gltf.glb")
const COIN_STACK_SMALL := preload("res://assets/kaykit/dungeon/coin_stack_small.gltf.glb")
const COIN_STACK_MEDIUM := preload("res://assets/kaykit/dungeon/coin_stack_medium.gltf.glb")
const CHEST := preload("res://assets/kaykit/dungeon/chest_gold.glb")

var gold := 0
var item := {}

var _age := 0.0
var _flying := false
var _full_notice := false
var _visual: Node3D


## Everything one defeated enemy drops at `pos`.
static func drop_for(stats: EnemyStats, pos: Vector3) -> void:
	var rng := Inventory.rng
	var amount := rng.randi_range(stats.gold_min, stats.gold_max)
	if amount > 0:
		spawn(pos, amount, {})
	if rng.randf() < stats.drop_chance:
		spawn(pos, 0, ItemDB.roll(Progress.dungeon_level(), stats.drop_weights, rng))


static func spawn(pos: Vector3, gold_amount: int, drop: Dictionary) -> Loot:
	var loot := Loot.new()
	loot.gold = gold_amount
	loot.item = drop
	Game.world.add_child(loot)
	loot.global_position = pos + Vector3.UP * 0.6
	# Hop out to a random spot next to the enemy.
	var a := randf() * TAU
	var land := pos + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.8, 1.6)
	land.y = 0.35
	var tw := loot.create_tween()
	tw.tween_property(loot, "global_position", land, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return loot


func _ready() -> void:
	_visual = Node3D.new()
	_visual.position.y = -0.3  # the loot node floats; its model stands on the floor
	add_child(_visual)
	if item.is_empty():
		var model := COIN_SINGLE if gold < 10 else (COIN_STACK_SMALL if gold < 30 else COIN_STACK_MEDIUM)
		_visual.add_child(_fit(model.instantiate(), 0.5))
		_floor_glow(Color(1.0, 0.78, 0.25, 0.8), 0.32)
		return
	# Items drop as a small treasure chest; the rarity shows as coloured light.
	_visual.add_child(_fit(CHEST.instantiate(), 0.62))
	var c := ItemDB.color(item)
	_floor_glow(Color(c.r, c.g, c.b, 0.9), 0.5)
	if int(item["rarity"]) >= 2:
		# Rare and Epic drops get a light beam, so they are seen from afar.
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.14
		cyl.height = 3.0
		beam.mesh = cyl
		beam.position.y = 1.2
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.material_override = Vfx.unshaded(Color(c.r, c.g, c.b, 0.35), true)
		add_child(beam)


## Scales a KayKit model so its largest side is `size` metres, standing on y = 0.
func _fit(model: Node3D, size: float) -> Node3D:
	var box := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != model:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		box = t * mi.get_aabb() if first else box.merge(t * mi.get_aabb())
		first = false
	var s := size / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.001))
	model.scale = Vector3.ONE * s
	var c := box.get_center()
	model.position = Vector3(-c.x, -box.position.y, -c.z) * s
	return model


## Ring of colour on the floor under the drop (solid, so it reads on light floors).
func _floor_glow(color: Color, radius: float) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = Vfx.arc_mesh(0.7, 1.0, 360.0, false, 0)
	ring.scale = Vector3(radius, 1.0, radius)
	ring.position.y = -0.2  # just above the floor tiles
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = Vfx.unshaded(color)
	add_child(ring)


func _physics_process(delta: float) -> void:
	_age += delta
	_visual.rotation.y += delta * 1.6
	_visual.position.y = -0.3 + sin(_age * 3.0) * 0.06
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.state == Player.State.DEAD:
		return
	var target := p.global_position + Vector3.UP * 1.0
	var dist := global_position.distance_to(target)
	if not _flying:
		if _age < PICKUP_DELAY or dist > PICKUP_RADIUS:
			return
		if not item.is_empty() and Inventory.is_full():
			if not _full_notice:
				_full_notice = true
				get_tree().call_group("hud", "toast", "Inventory penuh: jual atau buang item dulu (I)")
			return
		_flying = true
	global_position = global_position.move_toward(target, FLY_SPEED * delta)
	if dist < 0.45:
		_collect(p)


func _collect(p: Player) -> void:
	if item.is_empty():
		Progress.add_gold(gold)
		Vfx.float_text(p.global_position + Vector3.UP * 2.1, "+%d Gold" % gold, Color(1.0, 0.82, 0.3), 0.7)
		Sfx.play("coin")
	else:
		if not Inventory.add(item):
			_flying = false
			return
		var rarity: String = ItemDB.RARITY_NAMES[int(item["rarity"])]
		Vfx.float_text(p.global_position + Vector3.UP * 2.3, ItemDB.title(item), ItemDB.color(item), 0.8)
		get_tree().call_group("hud", "toast", "Dapat: %s [%s]   (I: inventory)" % [ItemDB.title(item), rarity])
		Sfx.play("pickup")
	queue_free()
