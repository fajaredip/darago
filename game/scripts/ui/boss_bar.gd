class_name BossBar
extends Control
## Boss health bar displayed at the top of the screen when a Boss is engaged.
## Shows boss title, subtitle, layered health bar with hit ghosting, and fade-in/out.

const TITLE_FONT := preload("res://assets/fonts/title_font.tres")
const BAR_WIDTH := 640.0
const BAR_HEIGHT := 22.0

var boss: Enemy
var _name_label: Label
var _bar: ResourceBar
var _target_hp := 0.0
var _max_hp := 1.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_top = 0.0
	anchor_right = 0.5
	anchor_bottom = 0.0
	offset_left = -BAR_WIDTH * 0.5
	offset_top = 26.0
	offset_right = BAR_WIDTH * 0.5
	offset_bottom = 86.0

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", TITLE_FONT)
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text = "PANGLIMA TENGKORAK KUNO"
	vbox.add_child(_name_label)

	_bar = ResourceBar.new(Color(0.85, 0.18, 0.22), "BOSS", BAR_WIDTH, BAR_HEIGHT, true)
	vbox.add_child(_bar)
	modulate.a = 0.0


func set_boss(e: Enemy, boss_title := "PANGLIMA TENGKORAK KUNO") -> void:
	boss = e
	_name_label.text = boss_title
	_max_hp = e.stats.max_hp
	_target_hp = e.hp
	_bar.set_values(e.hp, _max_hp)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.5)


func dismiss() -> void:
	boss = null
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _process(_delta: float) -> void:
	if not boss or not is_instance_valid(boss):
		if modulate.a > 0.0 and boss == null:
			dismiss()
		return
	_target_hp = maxf(boss.hp, 0.0)
	_bar.set_values(_target_hp, _max_hp)
	if boss.hp <= 0.0:
		dismiss()
