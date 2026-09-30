class_name StatusWindow
extends CanvasLayer
## Character panel (C), laid out like Dragon Nest's: class, level, HP / MP and
## the stats on the left, the worn equipment in a column on the right.
## Display only, so the game keeps running while it is open.

const GOLD := SettingsMenu.GOLD
const TEXT := SettingsMenu.TEXT
const MUTED := SettingsMenu.MUTED
const VALUE := Color(1.0, 0.82, 0.4)  # numbers in gold, like the reference
const PRIMARY_HINTS := {"STR": "ATK", "AGI": "Crit", "INT": "MP", "VIT": "HP, DEF"}
const SLOT_SIZE := 62.0

var _panel: PanelContainer
var _values := {}
var _exp_bar: ResourceBar
var _exp_text: Label
var _slots := {}


func _ready() -> void:
	layer = 20
	_build()
	_panel.visible = false
	Progress.changed.connect(refresh)
	Inventory.changed.connect(refresh)


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
	_put("Class", s.class_display_name)
	_put("Lv.", "%d" % Progress.level)
	_put("HP", "%d / %d" % [ceili(p.hp), roundi(s.max_hp)])
	_put("MP", "%d / %d" % [floori(p.mana), roundi(s.max_mana)])
	_put("MP Recovery", "%.1f / detik" % s.mana_regen)
	if need > 0:
		_exp_bar.set_values(Progress.experience, need)
		_exp_text.text = "EXP  %d / %d  (%.1f%%)" % [Progress.experience, need, 100.0 * Progress.experience / need]
	else:
		_exp_bar.set_values(1.0, 1.0)
		_exp_text.text = "EXP  level maksimal"
	var primary := Progress.primary(s)
	var base := Progress.primary(s, false)
	for key in Progress.PRIMARY:
		var from_gear := roundi(primary[key] - base[key])
		_put(key, "%d" % roundi(primary[key]) + ("  (+%d)" % from_gear if from_gear > 0 else ""))
	_put("Attack Power", "%d" % roundi(s.attack_power))
	_put("Defense", "%.1f  (-%.1f%%)" % [s.defense, 100.0 * Progress.damage_reduction(s.defense)])
	_put("Critical", "%.1f%%" % (100.0 * s.crit_chance))
	_put("Critical Damage", "x%.1f" % s.crit_multiplier)
	_put("Gold", "%d" % Progress.gold)
	for slot in ItemDB.EQUIP_SLOTS:
		var item: Dictionary = Inventory.equipped.get(slot, {})
		var box: Panel = _slots[slot]
		box.add_theme_stylebox_override("panel", InventoryWindow.slot_style(item))
		var icon: TextureRect = box.get_meta(&"icon")
		icon.texture = ItemDB.icon(item, slot)
		icon.modulate = Color.WHITE if not item.is_empty() else Color(1, 1, 1, 0.12)
		var plus: Label = box.get_meta(&"plus")
		var e := int(item.get("enhance", 0))
		plus.text = "+%d" % e if e > 0 else ""


func _process(_delta: float) -> void:
	# HP and MP change during fights; the rest updates through signals.
	if _panel.visible and Engine.get_process_frames() % 10 == 0:
		refresh()


func _put(key: String, text: String) -> void:
	(_values[key] as Label).text = text


func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.09, 0.93)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 40.0
	_panel.offset_top = -340.0  # stays clear of the quickslot bar
	_panel.offset_right = 640.0
	_panel.offset_bottom = 260.0
	_panel.draw.connect(func() -> void: _panel.draw_style_box(InventoryWindow.frame_style(), Rect2(Vector2.ZERO, _panel.size)))
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)
	var title := _label("Character", 24, GOLD)
	title.add_theme_font_override("font", Hud.TITLE_FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	outer.add_child(InventoryWindow.divider())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)

	# Left: numbers.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380.0, 0.0)
	left.add_theme_constant_override("separation", 4)
	columns.add_child(left)
	_rows(left, ["Class", "Lv.", "HP", "MP", "MP Recovery"])
	_exp_bar = ResourceBar.new(Color(0.62, 0.45, 0.95), "EXP", 380.0, 10.0, false)
	_exp_bar.show_text = false
	left.add_child(_exp_bar)
	_exp_text = _label("", 13, MUTED)
	left.add_child(_exp_text)
	left.add_child(_section("Stat Utama"))
	_rows(left, Progress.PRIMARY, PRIMARY_HINTS)
	left.add_child(_section("Stat Tempur"))
	_rows(left, ["Attack Power", "Defense", "Critical", "Critical Damage"])
	left.add_child(InventoryWindow.divider())
	_rows(left, ["Gold"])

	# Right: equipment in two columns (armor parts | weapon and accessories).
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(right)
	for group in [["helmet", "armor", "gloves", "legs", "boots"], ["weapon", "necklace", "accessory", "accessory_2"]]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		right.add_child(column)
		for slot: String in group:
			var box := Panel.new()
			box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon := TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.position = Vector2(7.0, 7.0)
			icon.size = Vector2(SLOT_SIZE - 14.0, SLOT_SIZE - 14.0)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(icon)
			var plus := _label("", 13, Color(1.0, 0.9, 0.5))
			plus.add_theme_constant_override("outline_size", 4)
			plus.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			plus.position = Vector2(6.0, 1.0)
			box.add_child(plus)
			box.set_meta(&"icon", icon)
			box.set_meta(&"plus", plus)
			column.add_child(box)
			_slots[slot] = box

	var hint := _label("Stat naik otomatis tiap level.   %s: tutup   %s: inventory" % [
			Settings.key_name(&"status"), Settings.key_name(&"inventory")], 13, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)


## Label / value rows; `hints` adds a small note after the value (e.g. STR -> ATK).
func _rows(parent: Control, keys: Array, hints := {}) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for key: String in keys:
		var name_label := _label(key, 16, TEXT)
		name_label.custom_minimum_size.x = 150.0
		grid.add_child(name_label)
		var value := _label("", 16, VALUE)
		value.custom_minimum_size.x = 150.0
		grid.add_child(value)
		grid.add_child(_label(hints.get(key, ""), 12, MUTED))
		_values[key] = value


func _section(text: String) -> Label:
	var l := _label(text, 16, GOLD)
	l.add_theme_font_override("font", Hud.TITLE_FONT)
	return l


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
