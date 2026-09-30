class_name StatusWindow
extends CanvasLayer
## Character status panel (C): level, EXP, STR / AGI / INT / VIT and the combat
## numbers they give. Display only, so the game keeps running while it is open.

const GOLD := Color(0.86, 0.7, 0.38)
const TEXT := Color(0.95, 0.92, 0.86)
const MUTED := Color(0.72, 0.68, 0.62)
const PRIMARY_HINTS := {"STR": "ATK", "AGI": "Crit", "INT": "MP, regen MP", "VIT": "HP, DEF"}

var _panel: PanelContainer
var _level: Label
var _exp_bar: ResourceBar
var _exp_text: Label
var _primary := {}
var _combat := {}
var _gold: Label


func _ready() -> void:
	layer = 20
	_build()
	_panel.visible = false
	Progress.changed.connect(refresh)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"status"):
		toggle()


func refresh() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or not _panel.visible:
		return
	var s := p.stats
	var need := Progress.exp_to_next(Progress.level)
	_level.text = "%s   Lv %d" % [s.class_display_name, Progress.level]
	if need > 0:
		_exp_bar.set_values(Progress.experience, need)
		_exp_text.text = "EXP  %d / %d  (%.1f%%)" % [Progress.experience, need, 100.0 * Progress.experience / need]
	else:
		_exp_bar.set_values(1.0, 1.0)
		_exp_text.text = "Level maksimal"
	var primary := Progress.primary(s)
	var base := Progress.primary(s, false)
	for key in Progress.PRIMARY:
		var from_gear := roundi(primary[key] - base[key])
		(_primary[key] as Label).text = "%d" % roundi(primary[key]) + ("  (+%d)" % from_gear if from_gear > 0 else "")
	_combat["ATK"].text = "%d" % roundi(s.attack_power)
	_combat["DEF"].text = "%.1f  (-%.1f%% damage)" % [s.defense, 100.0 * Progress.damage_reduction(s.defense)]
	_combat["HP"].text = "%d" % roundi(s.max_hp)
	_combat["MP"].text = "%d" % roundi(s.max_mana)
	_combat["Regen MP"].text = "%.1f / detik" % s.mana_regen
	_combat["Crit"].text = "%.1f%%  (x%.1f damage)" % [100.0 * s.crit_chance, s.crit_multiplier]
	_gold.text = "Gold  %d" % Progress.gold


func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.09, 0.92)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 40.0
	_panel.offset_top = -250.0
	_panel.offset_right = 420.0
	_panel.offset_bottom = 250.0
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := _label("Status", 26, GOLD)
	title.add_theme_font_override("font", Hud.TITLE_FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_level = _label("", 20, TEXT)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_level)
	_exp_bar = ResourceBar.new(Color(0.62, 0.45, 0.95), "", 340.0, 12.0, false)
	_exp_bar.show_text = false
	box.add_child(_exp_bar)
	_exp_text = _label("", 14, MUTED)
	_exp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_exp_text)

	box.add_child(_section("Stat Utama"))
	var grid := _grid(box)
	for key in Progress.PRIMARY:
		grid.add_child(_label(key, 17, TEXT))
		var value := _label("", 17, TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		grid.add_child(_label(PRIMARY_HINTS[key], 13, MUTED))
		_primary[key] = value

	box.add_child(_section("Stat Tempur"))
	var combat := _grid(box)
	for key in ["ATK", "DEF", "HP", "MP", "Regen MP", "Crit"]:
		combat.add_child(_label(key, 16, TEXT))
		var value := _label("", 16, TEXT)
		combat.add_child(value)
		combat.add_child(Control.new())
		_combat[key] = value

	_gold = _label("", 16, GOLD)
	box.add_child(_gold)
	var hint := _label("Stat naik otomatis tiap level.  %s: tutup" % Settings.key_name(&"status"), 13, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _section(text: String) -> Label:
	var l := _label(text, 16, GOLD)
	l.add_theme_font_override("font", Hud.TITLE_FONT)
	return l


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
