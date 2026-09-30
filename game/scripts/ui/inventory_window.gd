class_name InventoryWindow
extends CanvasLayer
## Inventory (I): the 30-slot bag, the three equipment slots, item details with
## a comparison against what is worn, and Equip / Enhance / Sell.
## The game pauses while it is open.

const GOLD := SettingsMenu.GOLD
const TEXT := SettingsMenu.TEXT
const MUTED := SettingsMenu.MUTED
const SLOT_SIZE := 64.0
const COLUMNS := 6
const ICONS := {
	"weapon": preload("res://assets/ui/icons/broadsword.svg"),
	"armor": preload("res://assets/ui/icons/breastplate.svg"),
	"accessory": preload("res://assets/ui/icons/ring.svg"),
}
const COIN_ICON := preload("res://assets/ui/icons/two-coins.svg")
const GOOD := Color(0.45, 0.95, 0.45)
const BAD := Color(1.0, 0.45, 0.4)

var _root: Control
var _bag_title: Label
var _bag_buttons: Array[Button] = []
var _equip_buttons := {}
var _equip_names := {}
var _gold: Label
var _detail_title: Label
var _detail_info: Label
var _detail_stats: RichTextLabel
var _equip_btn: Button
var _enhance_btn: Button
var _sell_btn: Button
var _message: Label
## Item id picked by a click (the buttons act on it), and the one under the mouse.
var _selected := -1
var _hovered := -1


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Inventory.changed.connect(_refresh)
	Progress.changed.connect(_refresh)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	_selected = -1
	_hovered = -1
	_message.text = ""
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false
	if not Game.test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# Esc closes this window instead of opening the settings menu behind it.
	if _root.visible and event.is_action_pressed(&"menu"):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"inventory"):
		return
	if _root.visible:
		close()
	elif not get_tree().paused:  # not on top of the settings menu
		open()
	get_viewport().set_input_as_handled()


func select(id: int) -> void:
	_selected = id
	_message.text = ""
	_refresh()


# --- actions -----------------------------------------------------------------

func equip_selected() -> void:
	var item := Inventory.find(_selected)
	if item.is_empty():
		return
	if Inventory.is_equipped(_selected):
		if not Inventory.unequip(item["slot"]):
			_say("Inventory penuh: tidak bisa melepas", BAD)
			return
		_say("Dilepas: %s" % ItemDB.title(item), MUTED)
	else:
		Inventory.equip(_selected)
		_say("Dipakai: %s" % ItemDB.title(item), GOOD)
	Sfx.play("equip")


func enhance_selected(roll := -1.0) -> String:
	var item := Inventory.find(_selected)
	if item.is_empty():
		return ""
	var result := Inventory.enhance(_selected, roll)
	match result:
		"ok":
			_say("Enhance berhasil!  %s" % ItemDB.title(item), GOOD)
			Sfx.play("enhance_ok")
		"fail":
			_say("Enhance gagal... gold hilang, item tetap %s" % ItemDB.title(item), BAD)
			Sfx.play("enhance_fail")
		"gold":
			_say("Gold tidak cukup", BAD)
			Sfx.play("deny")
		_:
			_say("Sudah enhance maksimal (+%d)" % ItemDB.MAX_ENHANCE, MUTED)
	_refresh()
	return result


func sell_selected() -> void:
	var item := Inventory.find(_selected)
	if item.is_empty() or Inventory.is_equipped(_selected):
		return
	var price := Inventory.sell(_selected)
	_selected = -1
	_say("Terjual: %s  (+%d gold)" % [ItemDB.title(item), price], GOLD)
	Sfx.play("coin")


func _quick(id: int) -> void:
	_selected = id
	equip_selected()


func _say(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)


# --- refresh ------------------------------------------------------------------

func _refresh() -> void:
	if not _root.visible:
		return
	for i in _bag_buttons.size():
		var item: Dictionary = Inventory.items[i] if i < Inventory.items.size() else {}
		_style_slot(_bag_buttons[i], item)
	for slot in ItemDB.SLOTS:
		var item: Dictionary = Inventory.equipped.get(slot, {})
		_style_slot(_equip_buttons[slot], item, slot)
		var name_label: Label = _equip_names[slot]
		name_label.text = ItemDB.title(item) if not item.is_empty() else "(kosong)"
		name_label.add_theme_color_override("font_color", ItemDB.color(item) if not item.is_empty() else MUTED)
	_bag_title.text = "Inventory   %d / %d" % [Inventory.items.size(), Inventory.SIZE]
	_gold.text = "%d" % Progress.gold
	_show_detail()


func _style_slot(button: Button, item: Dictionary, empty_slot := "") -> void:
	var id := int(item.get("id", -1))
	button.set_meta(&"item_id", id)
	var has_item := not item.is_empty()
	var edge := ItemDB.color(item) if has_item else Color(0.35, 0.32, 0.3)
	var selected := has_item and id == _selected
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.09, 0.12) if state == "normal" else Color(0.18, 0.16, 0.2)
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color.WHITE if selected else edge
		sb.set_border_width_all(3 if selected else 2)
		sb.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, sb)
	var slot: String = item.get("slot", empty_slot)
	button.icon = ICONS.get(slot, null)
	var tint := ItemDB.color(item).lerp(Color.WHITE, 0.25) if has_item else Color(1, 1, 1, 0.12)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(c, tint)
	var plus: Label = button.get_meta(&"plus_label")
	var e := int(item.get("enhance", 0))
	plus.text = "+%d" % e if e > 0 else ""


func _show_detail() -> void:
	var id := _hovered if _hovered >= 0 else _selected
	var item := Inventory.find(id)
	var buttons_on := not item.is_empty() and id == _selected
	_equip_btn.visible = buttons_on
	_enhance_btn.visible = buttons_on
	_sell_btn.visible = buttons_on
	if item.is_empty():
		_detail_title.text = "Pilih item"
		_detail_title.add_theme_color_override("font_color", MUTED)
		_detail_info.text = "Klik item untuk melihat detail."
		_detail_stats.text = ""
		return
	var worn := Inventory.is_equipped(id)
	_detail_title.text = ItemDB.title(item)
	_detail_title.add_theme_color_override("font_color", ItemDB.color(item))
	_detail_info.text = "%s   Lv %d   %s%s" % [ItemDB.SLOT_NAMES[item["slot"]], int(item["ilvl"]),
			ItemDB.RARITY_NAMES[int(item["rarity"])], "   (dipakai)" if worn else ""]
	var own := ItemDB.stats(item)
	var text := "\n".join(ItemDB.stat_lines(own))
	if not worn:
		var current: Dictionary = Inventory.equipped.get(item["slot"], {})
		if current.is_empty():
			text += "\n\n[color=#%s]Slot %s masih kosong[/color]" % [GOOD.to_html(false), ItemDB.SLOT_NAMES[item["slot"]]]
		else:
			text += "\n\n[color=#%s]Dibanding %s:[/color]" % [MUTED.to_html(false), ItemDB.title(current)]
			var theirs := ItemDB.stats(current)
			var any := false
			for stat in ItemDB.STAT_ORDER:
				var diff := int(own.get(stat, 0)) - int(theirs.get(stat, 0))
				if diff != 0:
					any = true
					var c := GOOD if diff > 0 else BAD
					text += "\n[color=#%s]%s %+d[/color]" % [c.to_html(false), stat, diff]
			if not any:
				text += "\nsama"
	_detail_stats.text = text
	_equip_btn.text = "Lepas" if worn else "Pakai"
	var chance := ItemDB.enhance_chance(item)
	if chance <= 0.0:
		_enhance_btn.text = "Enhance maks"
		_enhance_btn.disabled = true
	else:
		var cost := ItemDB.enhance_cost(item)
		_enhance_btn.text = "Enhance +%d  (%d%%, %d gold)" % [int(item["enhance"]) + 1, roundi(chance * 100.0), cost]
		_enhance_btn.disabled = Progress.gold < cost
	_sell_btn.text = "Jual  %d gold" % ItemDB.sell_price(item)
	_sell_btn.disabled = worn


# --- build ------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = SettingsMenu.make_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.09, 0.96)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	panel.add_child(columns)

	# Left: equipment, gold, details and actions.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360.0, 0.0)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	left.add_child(_title("Equipment"))
	for slot in ItemDB.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		left.add_child(row)
		var button := _slot_button()
		button.pressed.connect(func() -> void: _on_slot_pressed(button))
		row.add_child(button)
		_equip_buttons[slot] = button
		var labels := VBoxContainer.new()
		labels.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(labels)
		labels.add_child(_label(ItemDB.SLOT_NAMES[slot], 13, MUTED))
		var name_label := _label("", 16, TEXT)
		labels.add_child(name_label)
		_equip_names[slot] = name_label
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	left.add_child(gold_row)
	var coin := TextureRect.new()
	coin.texture = COIN_ICON
	coin.custom_minimum_size = Vector2(22.0, 22.0)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.modulate = Color(1.0, 0.82, 0.3)
	gold_row.add_child(coin)
	_gold = _label("0", 17, Color(1.0, 0.85, 0.4))
	gold_row.add_child(_gold)
	left.add_child(HSeparator.new())
	_detail_title = _label("", 19, TEXT)
	left.add_child(_detail_title)
	_detail_info = _label("", 13, MUTED)
	left.add_child(_detail_info)
	_detail_stats = RichTextLabel.new()
	_detail_stats.bbcode_enabled = true
	_detail_stats.fit_content = true
	_detail_stats.scroll_active = false
	_detail_stats.custom_minimum_size = Vector2(0.0, 150.0)
	_detail_stats.add_theme_font_size_override("normal_font_size", 15)
	_detail_stats.add_theme_color_override("default_color", TEXT)
	left.add_child(_detail_stats)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	left.add_child(actions)
	_equip_btn = _button("Pakai")
	_equip_btn.pressed.connect(equip_selected)
	actions.add_child(_equip_btn)
	_sell_btn = _button("Jual")
	_sell_btn.pressed.connect(sell_selected)
	actions.add_child(_sell_btn)
	_enhance_btn = _button("Enhance")
	_enhance_btn.pressed.connect(func() -> void: enhance_selected())
	left.add_child(_enhance_btn)
	_message = _label("", 14, MUTED)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(360.0, 40.0)
	left.add_child(_message)

	# Right: the bag.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	_bag_title = _title("Inventory")
	right.add_child(_bag_title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	for i in Inventory.SIZE:
		var button := _slot_button()
		button.pressed.connect(func() -> void: _on_slot_pressed(button))
		grid.add_child(button)
		_bag_buttons.append(button)
	var hint := _label("Klik: pilih    Klik kanan: pakai / lepas    %s / Esc: tutup" % Settings.key_name(&"inventory"), 13, MUTED)
	right.add_child(hint)
	var rules := _label("Enhance +1 sampai +%d: tiap level +%d%% stat utama.\nGagal = gold hilang, item tidak turun." % [ItemDB.MAX_ENHANCE, roundi(ItemDB.ENHANCE_STEP * 100.0)], 13, MUTED)
	right.add_child(rules)


func _slot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 44)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta(&"item_id", -1)
	var plus := _label("", 13, Color(1.0, 0.9, 0.5))
	plus.add_theme_constant_override("outline_size", 4)
	plus.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	plus.position = Vector2(SLOT_SIZE - 26.0, 2.0)
	b.add_child(plus)
	b.set_meta(&"plus_label", plus)
	b.mouse_entered.connect(func() -> void:
		_hovered = int(b.get_meta(&"item_id"))
		_show_detail())
	b.mouse_exited.connect(func() -> void:
		_hovered = -1
		_show_detail())
	b.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and int(b.get_meta(&"item_id")) >= 0:
			_quick(int(b.get_meta(&"item_id"))))
	return b


func _on_slot_pressed(button: Button) -> void:
	var id := int(button.get_meta(&"item_id"))
	if id >= 0:
		select(id)


func _title(text: String) -> Label:
	var l := _label(text, 22, GOLD)
	l.add_theme_font_override("font", Hud.TITLE_FONT)
	return l


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b
