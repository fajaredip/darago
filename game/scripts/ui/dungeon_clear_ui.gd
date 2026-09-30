class_name DungeonClearUI
extends Control
## Displays dungeon clear evaluation, ranking (SSS / SS / S / A / B), clear time,
## combo, and prompts player to pick a reward chest.

const TITLE_FONT := preload("res://assets/fonts/title_font.tres")
const GOLD := Color(1.0, 0.85, 0.35)

var _title: Label
var _rank_label: Label
var _stats_label: Label
var _hint_label: Label


func _init(clear_time_sec: float, max_combo: int, damage_taken: float) -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.88)
	style.border_color = Color(0.85, 0.7, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(480.0, 240.0)

	# Center on screen
	card.anchor_left = 0.5
	card.anchor_top = 0.36
	card.anchor_right = 0.5
	card.anchor_bottom = 0.36
	card.offset_left = -240.0
	card.offset_top = -120.0
	card.offset_right = 240.0
	card.offset_bottom = 120.0
	add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_override("font", TITLE_FONT)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text = "DUNGEON CLEAR!"
	vbox.add_child(_title)

	# Calculate Rank
	var rank := "S"
	var rank_color := GOLD
	if clear_time_sec <= 60.0 and max_combo >= 20:
		rank = "SSS"
		rank_color = Color(1.0, 0.35, 0.85)
	elif clear_time_sec <= 90.0 and max_combo >= 12:
		rank = "SS"
		rank_color = Color(1.0, 0.65, 0.2)
	elif clear_time_sec <= 120.0:
		rank = "S"
		rank_color = GOLD
	elif clear_time_sec <= 180.0:
		rank = "A"
		rank_color = Color(0.4, 0.85, 1.0)
	else:
		rank = "B"
		rank_color = Color(0.7, 0.9, 0.7)

	_rank_label = Label.new()
	_rank_label.add_theme_font_override("font", TITLE_FONT)
	_rank_label.add_theme_font_size_override("font_size", 48)
	_rank_label.add_theme_color_override("font_color", rank_color)
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.text = "RANK %s" % rank
	vbox.add_child(_rank_label)

	var mins := int(clear_time_sec) / 60
	var secs := int(clear_time_sec) % 60
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 15)
	_stats_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.text = "Waktu: %02d:%02d  |  Combo Max: %d HIT  |  Damage: %d" % [mins, secs, max_combo, roundi(damage_taken)]
	vbox.add_child(_stats_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.text = "Pilih 1 dari 4 Peti Hadiah [F] di Ruang Boss!"
	vbox.add_child(_hint_label)

	# Enter animation
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.35).from(Vector2.ONE * 0.85).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
