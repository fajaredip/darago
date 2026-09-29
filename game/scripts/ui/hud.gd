class_name Hud
extends CanvasLayer
## Prototype HUD built in code: HP/MP bars, skill cooldowns, enemy health
## bars, combo counter, wave announcements and the win / lose screen.



class Slot:
	var panel: Panel
	var cover: ColorRect
	var name_label: Label
	var key_label: Label
	var cooldown_label: Label


var _hp_bar: ProgressBar
var _hp_text: Label
var _mp_bar: ProgressBar
var _mp_text: Label
var _slots: Array[Slot] = []
var _combo: Label
var _announce: Label
var _announce_tip: Label
var _result: Control
var _result_title: Label
var _result_sub: Label
var _bars: Control
var _toast: Label
var _help: Label
var _shown_combo := 0


func _ready() -> void:
	add_to_group("hud")
	var root := Control.new()
	_anchor(root, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_toast = _label(18, Color(1.0, 0.95, 0.8), 5)
	_anchor(_toast, 0.0, 0.0, 1.0, 0.0, 0.0, 70.0, 0.0, 100.0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_bars = Control.new()
	_anchor(_bars, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_enemy_bars)
	root.add_child(_bars)

	var bottom := VBoxContainer.new()
	_anchor(bottom, 0.5, 1.0, 0.5, 1.0, -240.0, -190.0, 240.0, -24.0)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	bottom.add_child(row)
	var stats := Game.player.stats
	_slots.append(_make_slot(row, "1", stats.skill_1.display_name, stats.skill_1.color))
	_slots.append(_make_slot(row, "2", stats.skill_2.display_name, stats.skill_2.color))
	_slots.append(_make_slot(row, "2x arah", "Dodge", Color(0.7, 0.8, 0.9)))

	var class_label := _label(18, Color(1.0, 0.85, 0.45), 5)
	class_label.text = stats.class_display_name
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(class_label)
	_hp_bar = _make_bar(bottom, Color(0.85, 0.2, 0.22))
	_hp_text = _bar_label(_hp_bar)
	_mp_bar = _make_bar(bottom, Color(0.25, 0.5, 0.95))
	_mp_text = _bar_label(_mp_bar)

	_combo = _label(46, Color(1.0, 0.85, 0.35), 10)
	_anchor(_combo, 1.0, 0.35, 1.0, 0.35, -380.0, 0.0, -90.0, 60.0)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo.visible = false
	root.add_child(_combo)

	_announce = _label(50, Color.WHITE, 10)
	_anchor(_announce, 0.0, 0.16, 1.0, 0.16, 0.0, 0.0, 0.0, 70.0)
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.modulate.a = 0.0
	root.add_child(_announce)
	_announce_tip = _label(22, Color(1.0, 0.9, 0.6), 6)
	_anchor(_announce_tip, 0.0, 0.16, 1.0, 0.16, 0.0, 72.0, 0.0, 110.0)
	_announce_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_tip.modulate.a = 0.0
	root.add_child(_announce_tip)

	_result = VBoxContainer.new()
	_anchor(_result, 0.0, 0.3, 1.0, 0.3, 0.0, 0.0, 0.0, 160.0)
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.visible = false
	root.add_child(_result)
	_result_title = _label(84, Color.WHITE, 14)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(_result_title)
	_result_sub = _label(24, Color.WHITE, 6)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(_result_sub)

	_help = _label(14, Color(1, 1, 1, 0.75), 4)

	_anchor(_help, 0.0, 0.0, 0.0, 0.0, 16.0, 10.0, 900.0, 56.0)
	root.add_child(_help)
	Settings.changed.connect(_refresh_key_hints)
	_refresh_key_hints()
	_warm_up_fonts()


## Draws the big texts once, invisibly, so their glyphs are rasterized before
## the first wave instead of stalling a frame mid-fight.
func _warm_up_fonts() -> void:
	var labels: Array[Label] = [_announce, _announce_tip, _combo, _result_title, _result_sub]
	for l in labels:
		# Nearly (not fully) transparent: fully transparent items may be skipped.
		l.self_modulate.a = 0.02
		l.modulate.a = 1.0
	_announce.text = "Gelombang 0123456789 / MENANG! KALAH"
	_announce_tip.text = "Tips: hantaman kapak Tengkorak Raksasa bisa dihindari dengan lompat (Spasi)"
	_combo.text = "0123456789 HIT"
	_combo.visible = true
	_result.visible = true
	_result_title.text = "MENANG! KALAH"
	_result_sub.text = "Semua gelombang dikalahkan. Tekan R untuk main lagi coba"
	await get_tree().process_frame
	await get_tree().process_frame
	for l in labels:
		l.self_modulate.a = 1.0
	_announce.modulate.a = 0.0
	_announce_tip.modulate.a = 0.0
	_combo.visible = _shown_combo >= 2
	if _result_title.text == "MENANG! KALAH":
		_result.visible = false


## Help line and skill-slot keys follow the player's current key bindings.
func _refresh_key_hints() -> void:
	var s := Settings
	var move := PackedStringArray([s.key_name(&"move_forward"), s.key_name(&"move_left"),
			s.key_name(&"move_back"), s.key_name(&"move_right")])
	var single := true
	for k in move:
		single = single and k.length() == 1
	var move_text := "".join(move) if single else "/".join(move)
	_help.text = ("%s: gerak    Mouse: kamera    %s: serang (tahan = combo)    %s: serangan berat    %s: lompat\n"
			+ "Tekan arah 2x cepat / %s: dodge    %s / %s: skill    Di udara: %s / %s    Tahan %s: kursor    Esc: menu    %s: screenshot") % [
			move_text, s.key_name(&"attack"), s.key_name(&"heavy"), s.key_name(&"jump"), s.key_name(&"dodge"),
			s.key_name(&"skill_1"), s.key_name(&"skill_2"), s.key_name(&"attack"), s.key_name(&"heavy"),
			s.key_name(&"show_cursor"), s.key_name(&"screenshot")]
	if _slots.size() >= 2:
		_slots[0].key_label.text = s.key_name(&"skill_1")
		_slots[1].key_label.text = s.key_name(&"skill_2")


## Short message at the top of the screen (e.g. "screenshot copied").
func toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # also while the menu pauses the game
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15).from(0.0)
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func announce(text: String, tip := "") -> void:
	_announce.text = text
	_announce_tip.text = tip
	var hold := 1.4 if tip == "" else 3.0
	for label: Label in [_announce, _announce_tip]:
		var tw := create_tween()
		tw.tween_property(label, "modulate:a", 1.0, 0.25).from(0.0)
		tw.tween_interval(hold)
		tw.tween_property(label, "modulate:a", 0.0, 0.5)


func show_result(title: String, subtitle: String, color: Color) -> void:
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", color)
	_result_sub.text = subtitle
	_result.visible = true
	create_tween().tween_property(_result, "modulate:a", 1.0, 0.4).from(0.0)


func _process(_delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	_hp_bar.max_value = p.stats.max_hp
	_hp_bar.value = p.hp
	_hp_text.text = "HP  %d / %d" % [ceili(p.hp), roundi(p.stats.max_hp)]
	_mp_bar.max_value = p.stats.max_mana
	_mp_bar.value = p.mana
	_mp_text.text = "MP  %d / %d" % [floori(p.mana), roundi(p.stats.max_mana)]
	var skills: Array[AttackData] = [p.stats.skill_1, p.stats.skill_2]
	for i in skills.size():
		_update_slot(_slots[i], p.skill_cooldowns[i], skills[i].cooldown)
		var tint := Color.WHITE
		if p.skill_denied_time[i] > 0.0:
			tint = Color(1.0, 0.45, 0.45)
		elif p.mana < skills[i].mana_cost:
			tint = Color(0.55, 0.55, 0.7)
		_slots[i].panel.modulate = tint
	_update_slot(_slots[2], p.dodge_cooldown, p.stats.dodge_cooldown)
	_update_combo(p.combo_hits)
	_bars.queue_redraw()


func _update_slot(slot: Slot, remaining: float, total: float) -> void:
	var frac := clampf(remaining / total, 0.0, 1.0) if total > 0.0 else 0.0
	slot.cover.anchor_top = 1.0 - frac
	var cooling := remaining > 0.05
	slot.cooldown_label.text = ("%.1f" % remaining) if cooling else ""
	slot.name_label.visible = not cooling


func _update_combo(hits: int) -> void:
	if hits == _shown_combo:
		return
	_shown_combo = hits
	_combo.visible = hits >= 2
	if not _combo.visible:
		return
	_combo.text = "%d HIT" % hits
	_combo.pivot_offset = _combo.size * 0.5
	create_tween().tween_property(_combo, "scale", Vector2.ONE, 0.12).from(Vector2.ONE * 1.35)


func _draw_enemy_bars() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := ThemeDB.fallback_font
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.state == Enemy.State.SPAWN:
			continue
		var pos := e.get_global_transform_interpolated().origin + Vector3.UP * e.bar_height
		if cam.is_position_behind(pos):
			continue
		var sp := cam.unproject_position(pos)
		var w := 64.0 * e.stats.size
		var rect := Rect2(sp.x - w * 0.5, sp.y, w, 7.0)
		var frac := clampf(e.hp / e.stats.max_hp, 0.0, 1.0)
		_bars.draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.75))
		_bars.draw_rect(Rect2(rect.position, Vector2(w * frac, rect.size.y)), Color(0.9, 0.22, 0.2))
		if e.stats.show_name:
			_bars.draw_string(font, Vector2(rect.position.x - 40.0, rect.position.y - 6.0), e.stats.display_name,
					HORIZONTAL_ALIGNMENT_CENTER, w + 80.0, 16)


func _make_slot(parent: Control, key: String, title: String, color: Color) -> Slot:
	var slot := Slot.new()
	slot.panel = Panel.new()
	slot.panel.custom_minimum_size = Vector2(84.0, 84.0)
	slot.panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.85)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	slot.panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(slot.panel)

	slot.name_label = _label(13, Color.WHITE, 4)
	slot.name_label.text = title
	slot.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	slot.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor(slot.name_label, 0.0, 0.0, 1.0, 1.0, 4.0, 4.0, -4.0, -6.0)
	slot.panel.add_child(slot.name_label)

	slot.key_label = _label(16, color.lightened(0.4), 4)
	slot.key_label.text = key
	_anchor(slot.key_label, 0.0, 0.0, 1.0, 1.0, 7.0, 3.0, 0.0, 0.0)
	slot.panel.add_child(slot.key_label)

	slot.cover = ColorRect.new()
	slot.cover.color = Color(0, 0, 0, 0.65)
	slot.cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(slot.cover, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	slot.panel.add_child(slot.cover)

	slot.cooldown_label = _label(26, Color.WHITE, 6)
	slot.cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anchor(slot.cooldown_label, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	slot.panel.add_child(slot.cooldown_label)
	return slot


func _make_bar(parent: Control, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(480.0, 22.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	parent.add_child(bar)
	return bar


func _bar_label(bar: ProgressBar) -> Label:
	var l := _label(14, Color.WHITE, 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anchor(l, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	bar.add_child(l)
	return l


func _label(size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _anchor(c: Control, left: float, top: float, right: float, bottom: float,
		off_left: float, off_top: float, off_right: float, off_bottom: float) -> void:
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom
	c.offset_left = off_left
	c.offset_top = off_top
	c.offset_right = off_right
	c.offset_bottom = off_bottom
