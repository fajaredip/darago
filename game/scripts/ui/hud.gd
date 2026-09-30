class_name Hud
extends CanvasLayer
## HUD built in code: HP/MP bars, skill bar, enemy health bars, combo counter,
## wave / enemy counter, wave announcements, help line and the win / lose screen.

const TITLE_FONT := preload("res://assets/fonts/title_font.tres")
const DEFAULT_ICONS: Array[Texture2D] = [
	preload("res://assets/ui/icons/quick-slash.svg"),
	preload("res://assets/ui/icons/sword-spin.svg"),
]
const DODGE_ICON := preload("res://assets/ui/icons/dodging.svg")
## Seconds the full help line stays up before it shrinks to a single hint.
const HELP_SECONDS := 20.0
const GOLD := Color(1.0, 0.85, 0.45)

var _hp_bar: ResourceBar
var _mp_bar: ResourceBar
var _slots: Array[SkillSlot] = []
var _vignette: DamageVignette
var _combo: Label
var _announce: Label
var _announce_tip: Label
var _objective: Label
var _class_label: Label
var _exp_bar: ResourceBar
var _level_up: Label
var _result: Control
var _result_title: Label
var _result_sub: Label
var _bars: Control
var _toast: Label
var _help: Label
var _help_open := true
var _help_touched := false
var _shown_combo := 0
var _last_hp := -1.0
var _wave_text := ""
var _wave_total := 0
## Enemy instance id -> trailing ("ghost") health fraction of its bar.
var _enemy_ghost := {}


func _ready() -> void:
	add_to_group("hud")
	var root := Control.new()
	_anchor(root, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette = DamageVignette.new()
	root.add_child(_vignette)

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
	_anchor(bottom, 0.5, 1.0, 0.5, 1.0, -240.0, -200.0, 240.0, -22.0)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 5)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 34)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	var stats := Game.player.stats
	var skills: Array[AttackData] = [stats.skill_1, stats.skill_2]
	for i in skills.size():
		var icon: Texture2D = skills[i].icon if skills[i].icon else DEFAULT_ICONS[i]
		_slots.append(_add_slot(row, icon, skills[i].color, skills[i].display_name))
	_slots.append(_add_slot(row, DODGE_ICON, Color(0.7, 0.82, 0.95), "Dodge"))

	_class_label = _label(18, GOLD, 5)
	_class_label.add_theme_font_override("font", TITLE_FONT)
	_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_class_label)
	_hp_bar = ResourceBar.new(Color(0.82, 0.16, 0.2), "HP", 480.0, 24.0)
	bottom.add_child(_hp_bar)
	_mp_bar = ResourceBar.new(Color(0.22, 0.45, 0.95), "MP", 480.0, 18.0, false)
	bottom.add_child(_mp_bar)

	_combo = _title_label(46, Color(1.0, 0.85, 0.35), 10)
	_anchor(_combo, 1.0, 0.35, 1.0, 0.35, -380.0, 0.0, -90.0, 60.0)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo.visible = false
	root.add_child(_combo)

	_objective = _title_label(20, Color(1.0, 0.93, 0.8), 6)
	_anchor(_objective, 1.0, 0.0, 1.0, 0.0, -360.0, 14.0, -22.0, 80.0)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_objective)

	_announce = _title_label(50, Color.WHITE, 10)
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
	_result_title = _title_label(84, Color.WHITE, 14)
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
	get_tree().create_timer(HELP_SECONDS).timeout.connect(_auto_close_help)
	_exp_bar = ResourceBar.new(Color(0.62, 0.45, 0.95), "EXP", 0.0, 14.0, false)
	_exp_bar.text_size = 11
	_anchor(_exp_bar, 0.0, 1.0, 1.0, 1.0, 8.0, -17.0, -8.0, -3.0)
	root.add_child(_exp_bar)
	_level_up = _title_label(40, Color(1.0, 0.85, 0.4), 10)
	_anchor(_level_up, 0.0, 0.33, 1.0, 0.33, 0.0, 0.0, 0.0, 60.0)
	_level_up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_up.modulate.a = 0.0
	root.add_child(_level_up)
	Progress.changed.connect(_refresh_level)
	Progress.leveled_up.connect(_on_level_up)
	_refresh_level()
	_warm_up_fonts()


## Draws the big texts once, invisibly, so their glyphs are rasterized before
## the first wave instead of stalling a frame mid-fight.
func _warm_up_fonts() -> void:
	var labels: Array[Label] = [_announce, _announce_tip, _combo, _result_title, _result_sub, _objective, _level_up]
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
	_objective.text = "Gelombang 0123456789 /\nMusuh"
	_level_up.text = "LEVEL UP! Lv 0123456789"
	await get_tree().process_frame
	await get_tree().process_frame
	for l in labels:
		l.self_modulate.a = 1.0
	_announce.modulate.a = 0.0
	_announce_tip.modulate.a = 0.0
	_combo.visible = _shown_combo >= 2
	_objective.text = ""
	_level_up.modulate.a = 0.0
	if _result_title.text == "MENANG! KALAH":
		_result.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"help"):
		_help_touched = true
		set_help_open(not _help_open)


func _auto_close_help() -> void:
	if not _help_touched:
		set_help_open(false)


## The full control list, or just a one-line hint on how to bring it back.
func set_help_open(open: bool) -> void:
	_help_open = open
	_refresh_key_hints()


## Help line and skill-slot keys follow the player's current key bindings.
func _refresh_key_hints() -> void:
	var s := Settings
	if _help_open:
		var move := PackedStringArray([s.key_name(&"move_forward"), s.key_name(&"move_left"),
				s.key_name(&"move_back"), s.key_name(&"move_right")])
		var single := true
		for k in move:
			single = single and k.length() == 1
		var move_text := "".join(move) if single else "/".join(move)
		_help.text = ("%s: gerak    Mouse: kamera    %s: serang (tahan = combo)    %s: serangan berat    %s: lompat\n"
				+ "Tekan arah 2x cepat / %s: dodge    %s / %s: skill    Di udara: %s / %s    Tahan %s: kursor    %s: status    %s: inventory    Esc: menu    %s: screenshot    %s: tutup bantuan") % [
				move_text, s.key_name(&"attack"), s.key_name(&"heavy"), s.key_name(&"jump"), s.key_name(&"dodge"),
				s.key_name(&"skill_1"), s.key_name(&"skill_2"), s.key_name(&"attack"), s.key_name(&"heavy"),
				s.key_name(&"show_cursor"), s.key_name(&"status"), s.key_name(&"inventory"), s.key_name(&"screenshot"), s.key_name(&"help")]
		_help.modulate.a = 1.0
	else:
		_help.text = "%s: bantuan tombol" % s.key_name(&"help")
		_help.modulate.a = 0.6
	if _slots.size() >= 3:
		_slots[0].set_key(s.key_name(&"skill_1"))
		_slots[1].set_key(s.key_name(&"skill_2"))
		_slots[2].set_key(s.key_name(&"dodge"))


func _refresh_level() -> void:
	var need := Progress.exp_to_next(Progress.level)
	_class_label.text = "%s   Lv %d" % [Game.player.stats.class_display_name, Progress.level]
	if need > 0:
		_exp_bar.set_values(Progress.experience, need)
		_exp_bar.text_override = "EXP  %d / %d  (%.1f%%)" % [Progress.experience, need, 100.0 * Progress.experience / need]
	else:
		_exp_bar.set_values(1.0, 1.0)
		_exp_bar.text_override = "EXP  level maksimal"
	_exp_bar.queue_redraw()


func _on_level_up(level: int) -> void:
	_level_up.text = "LEVEL UP!   Lv %d" % level
	_level_up.pivot_offset = _level_up.size * 0.5
	var tw := create_tween()
	tw.tween_property(_level_up, "modulate:a", 1.0, 0.2).from(0.0)
	tw.parallel().tween_property(_level_up, "scale", Vector2.ONE, 0.25).from(Vector2.ONE * 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(_level_up, "modulate:a", 0.0, 0.5)


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
	_wave_text = text
	_wave_total = 0
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


func _process(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	_hp_bar.set_values(p.hp, p.stats.max_hp)
	_mp_bar.set_values(p.mana, p.stats.max_mana)
	if _last_hp >= 0.0 and p.hp < _last_hp - 0.01:
		_vignette.hit(clampf((_last_hp - p.hp) / (p.stats.max_hp * 0.12), 0.5, 1.0))
	_last_hp = p.hp
	_vignette.update(_hp_bar.fraction(), delta)
	var skills: Array[AttackData] = [p.stats.skill_1, p.stats.skill_2]
	for i in skills.size():
		_slots[i].set_state(p.skill_cooldowns[i], skills[i].cooldown,
				p.mana >= skills[i].mana_cost, p.skill_denied_time[i] > 0.0)
	_slots[2].set_state(p.dodge_cooldown, p.stats.dodge_cooldown, true, false)
	_update_combo(p.combo_hits)
	_update_objective()
	_update_enemy_ghosts(delta)
	_bars.queue_redraw()


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


## Top-right: current wave and how many enemies of it are still standing.
func _update_objective() -> void:
	if _wave_text == "":
		return
	var alive := get_tree().get_nodes_in_group("enemies").size()
	_wave_total = maxi(_wave_total, alive)
	var text := _wave_text
	if _wave_total > 0:
		text += "\nMusuh  %d / %d" % [alive, _wave_total]
	_objective.text = text


func _update_enemy_ghosts(delta: float) -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null:
			continue
		var id := e.get_instance_id()
		var frac := clampf(e.hp / e.stats.max_hp, 0.0, 1.0)
		var ghost: float = _enemy_ghost.get(id, frac)
		_enemy_ghost[id] = maxf(frac, ghost - delta * 0.7) if ghost > frac else frac
		seen[id] = true
	for id in _enemy_ghost.keys():
		if not seen.has(id):
			_enemy_ghost.erase(id)


func _draw_enemy_bars() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := _bars.get_theme_default_font()
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
		var ghost: float = _enemy_ghost.get(e.get_instance_id(), frac)
		_bars.draw_rect(rect.grow(2.0), Color(0.02, 0.02, 0.03, 0.8))
		_bars.draw_rect(rect.grow(2.0), Color(0.8, 0.65, 0.4, 0.6), false, 1.0)
		if ghost > frac:
			_bars.draw_rect(Rect2(rect.position, Vector2(w * ghost, rect.size.y)), Color(1.0, 0.9, 0.75, 0.85))
		_bars.draw_rect(Rect2(rect.position, Vector2(w * frac, rect.size.y)), Color(0.88, 0.2, 0.18))
		_bars.draw_rect(Rect2(rect.position, Vector2(w * frac, 2.5)), Color(1.0, 1.0, 1.0, 0.2))
		# Named elites always show their name; normal enemies once they are fighting you.
		if e.stats.show_name or frac < 1.0:
			var fsize := 16 if e.stats.show_name else 13
			var name_color := GOLD if e.stats.show_name else Color(1.0, 1.0, 1.0, 0.85)
			var at := Vector2(rect.position.x - 60.0, rect.position.y - 7.0)
			_bars.draw_string_outline(font, at, e.stats.display_name, HORIZONTAL_ALIGNMENT_CENTER, w + 120.0, fsize, 4, Color(0, 0, 0, 0.85))
			_bars.draw_string(font, at, e.stats.display_name, HORIZONTAL_ALIGNMENT_CENTER, w + 120.0, fsize, name_color)


func _add_slot(parent: Control, icon: Texture2D, color: Color, title: String) -> SkillSlot:
	var slot := SkillSlot.new(icon, color, title)
	parent.add_child(slot)
	return slot


func _title_label(font_size: int, color: Color, outline: int) -> Label:
	var l := _label(font_size, color, outline)
	l.add_theme_font_override("font", TITLE_FONT)
	return l


func _label(font_size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
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
