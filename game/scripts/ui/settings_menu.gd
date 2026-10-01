class_name SettingsMenu
extends CanvasLayer
## Esc menu: pauses the game and offers Control Setting (key bindings, mouse
## sensitivity), Game Setting (volumes) and Exit Game. Every change is applied
## and saved at once through the Settings autoload.

## Ink colours on the parchment panels (shared by the other windows).
const GOLD := Color(0.45, 0.24, 0.05)
const TEXT := Color(0.24, 0.16, 0.09)
const MUTED := Color(0.45, 0.35, 0.25)
const VOLUME_ROWS := [[&"Master", "Volume utama"], [&"Music", "Musik"], [&"SFX", "Efek suara"]]

var _root: Control
var _pages := {}
var _page := ""
var _first_button: Button
var _binding_buttons := {}  # "action|slot" -> Button
var _listen_action: StringName = &""
var _listen_slot := -1
var _note: Label
var _sensitivity_slider: HSlider
var _sensitivity_value: Label
var _volume_sliders := {}
var _volume_values := {}
var _confirm: Control
var _confirm_question: Label
var _confirm_yes: Button
var _confirm_action := Callable()
var _difficulty: OptionButton


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Settings.changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	_show_page("main")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_stop_listening()
	_confirm.visible = false
	_root.visible = false
	get_tree().paused = false
	if not Game.test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _listen_action != &"":
		_capture_binding(event)
		return
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		if not is_open():
			open()
		elif _confirm.visible:
			_confirm.visible = false
		elif _page != "main":
			_show_page("main")
		else:
			close()


## While waiting for a new key: Esc cancels, Delete / Backspace empties the slot.
func _capture_binding(event: InputEvent) -> void:
	var code := ""
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_stop_listening()
			return
		if key.physical_keycode != KEY_DELETE and key.physical_keycode != KEY_BACKSPACE:
			code = Settings.code_from_event(key)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		var wheel := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if not button.pressed or button.button_index in wheel:
			return  # the wheel stays reserved for camera zoom
		code = Settings.code_from_event(button)
	else:
		return
	get_viewport().set_input_as_handled()
	var action := _listen_action
	var slot := _listen_slot
	_stop_listening()
	var taken := Settings.set_binding(action, slot, code)
	if taken != &"" and taken != action:
		_note.text = "%s dipindahkan dari \"%s\"." % [Settings.display_name(code), Settings.action_label(taken)]
	else:
		_note.text = ""


func _start_listening(action: StringName, slot: int) -> void:
	_stop_listening()
	_listen_action = action
	_listen_slot = slot
	_binding_buttons["%s|%d" % [action, slot]].text = "Tekan tombol..."
	_note.text = "Tekan tombol keyboard atau mouse.   Esc: batal   Delete: kosongkan"


func _stop_listening() -> void:
	_listen_action = &""
	_listen_slot = -1
	_refresh()


func _refresh() -> void:
	for entry in Settings.ACTIONS:
		for slot in Settings.SLOTS:
			var button: Button = _binding_buttons["%s|%d" % [entry[0], slot]]
			button.text = Settings.display_name(Settings.bindings[entry[0]][slot])
	_sensitivity_slider.set_value_no_signal(Settings.mouse_sensitivity)
	_sensitivity_value.text = "%.2fx" % Settings.mouse_sensitivity
	for row in VOLUME_ROWS:
		var percent := roundi(Settings.volumes[row[0]] * 100.0)
		_volume_sliders[row[0]].set_value_no_signal(percent)
		_volume_values[row[0]].text = "%d%%" % percent


func _show_page(page_name: String) -> void:
	if _listen_action != &"":
		_stop_listening()
	_page = page_name
	for key in _pages:
		_pages[key].visible = key == page_name
	_note.text = ""
	if page_name == "game":
		_refresh_difficulty()
	if page_name == "main":
		_first_button.grab_focus.call_deferred()


func _ask_exit() -> void:
	_ask("Keluar dari game?", "Ya, keluar", get_tree().quit)


## Shows the yes / cancel overlay; `action` runs on "yes".
func _ask(question: String, yes_text: String, action: Callable) -> void:
	_confirm_question.text = question
	_confirm_yes.text = yes_text
	_confirm_action = action
	_confirm.visible = true


func _restart_dungeon() -> void:
	close()
	get_tree().reload_current_scene()


func _refresh_difficulty() -> void:
	_difficulty.clear()
	for i in Progress.DIFFICULTIES.size():
		var text := "%s  (Lv %d)" % [Progress.difficulty_name(i), int(Progress.DIFFICULTIES[i][1])]
		if not Progress.is_unlocked(i):
			text += "  - terkunci"
		_difficulty.add_item(text, i)
		_difficulty.set_item_disabled(i, not Progress.is_unlocked(i))
	_difficulty.select(Progress.difficulty)


func _on_difficulty_picked(index: int) -> void:
	_difficulty.select(Progress.difficulty)  # only changes once confirmed
	if index == Progress.difficulty:
		return
	_ask("Ganti ke %s? Dungeon dimulai ulang." % Progress.difficulty_name(index), "Ya, ganti", func() -> void:
		Progress.set_difficulty(index)
		_restart_dungeon())


# --- Building the UI -----------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks never reach the game
	_root.theme = make_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_fill(dim)
	_root.add_child(dim)
	var box := _panel(_root, 600.0)
	_pages["main"] = _build_main(box)
	_pages["controls"] = _build_controls(box)
	_pages["game"] = _build_game(box)
	_confirm = _build_confirm()


func _build_main(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_title("PENGATURAN"))
	var items := [
		["Lanjutkan", close],
		["Control Setting", _show_page.bind("controls")],
		["Game Setting", _show_page.bind("game")],
		["Exit Game", _ask_exit],
	]
	for item in items:
		var b := _button(item[0], 22)
		b.custom_minimum_size = Vector2(0, 52)
		if item[0] == "Lanjutkan":
			b.theme_type_variation = &"ButtonGreen"
		elif item[0] == "Exit Game":
			b.theme_type_variation = &"ButtonRed"
		b.pressed.connect(item[1])
		page.add_child(b)
		if _first_button == null:
			_first_button = b
	parent.add_child(page)
	return page


func _build_controls(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.add_child(_title("Control Setting"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for header in ["Aksi", "Utama", "Cadangan"]:
		grid.add_child(_label(header, 16, GOLD))
	for entry in Settings.ACTIONS:
		var name_label := _label(entry[1], 17, TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		for slot in Settings.SLOTS:
			var b := _button("", 16)
			b.custom_minimum_size = Vector2(150, 34)
			b.pressed.connect(_start_listening.bind(entry[0], slot))
			grid.add_child(b)
			_binding_buttons["%s|%d" % [entry[0], slot]] = b
	var info := _label("Dodge juga bisa dengan menekan arah 2x cepat. Esc selalu membuka menu ini.", 14, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var sens_label := _label("Sensitivitas mouse", 17, TEXT)
	sens_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(sens_label)
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.2
	_sensitivity_slider.max_value = 3.0
	_sensitivity_slider.step = 0.05
	_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensitivity_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sensitivity_slider.value_changed.connect(func(value: float) -> void: Settings.set_mouse_sensitivity(value))
	row.add_child(_sensitivity_slider)
	_sensitivity_value = _label("", 17, GOLD)
	_sensitivity_value.custom_minimum_size = Vector2(64, 0)
	row.add_child(_sensitivity_value)
	page.add_child(row)

	_note = _label("", 15, GOLD)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(0, 22)
	page.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var reset := _button("Reset Default", 18)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		_note.text = "Semua tombol dan sensitivitas kembali ke bawaan.")
	buttons.add_child(reset)
	var back := _button("Kembali", 18)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_show_page.bind("main"))
	buttons.add_child(back)
	page.add_child(buttons)
	parent.add_child(page)
	return page


func _build_game(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.add_child(_title("Game Setting"))
	for entry in VOLUME_ROWS:
		var bus: StringName = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := _label(entry[1], 18, TEXT)
		name_label.custom_minimum_size = Vector2(160, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.max_value = 100.0
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			Settings.set_volume(bus, value / 100.0)
			_volume_values[bus].text = "%d%%" % roundi(value))
		row.add_child(slider)
		var value_label := _label("", 18, GOLD)
		value_label.custom_minimum_size = Vector2(56, 0)
		row.add_child(value_label)
		_volume_sliders[bus] = slider
		_volume_values[bus] = value_label
		page.add_child(row)
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 12)
	var diff_label := _label("Tingkat kesulitan", 18, TEXT)
	diff_label.custom_minimum_size = Vector2(160, 0)
	diff_row.add_child(diff_label)
	_difficulty = OptionButton.new()
	_difficulty.add_theme_font_size_override("font_size", 16)
	_difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty.item_selected.connect(_on_difficulty_picked)
	diff_row.add_child(_difficulty)
	page.add_child(diff_row)
	var diff_note := _label("Lv dungeon = kekuatan musuh, EXP dan level item. Selesaikan dungeon untuk membuka tingkat berikutnya.", 13, MUTED)
	diff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diff_note.custom_minimum_size.x = 420.0
	page.add_child(diff_note)
	var wipe := _button("Hapus data save", 16)
	wipe.theme_type_variation = &"ButtonRed"
	wipe.pressed.connect(func() -> void:
		_ask("Hapus semua progres? Level, item, gold dan tingkat kesulitan kembali ke awal.", "Ya, hapus", func() -> void:
			Progress.reset()
			_restart_dungeon()))
	page.add_child(wipe)
	var back := _button("Kembali", 18)
	back.pressed.connect(_show_page.bind("main"))
	page.add_child(back)
	parent.add_child(page)
	return page


func _build_confirm() -> Control:
	var overlay := Control.new()
	_fill(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	_root.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	_fill(dim)
	overlay.add_child(dim)
	var box := _panel(overlay, 380.0, "plain")
	var question := _label("", 22, TEXT)
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_question = question
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(question)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var yes := _button("Ya, keluar", 18)
	yes.theme_type_variation = &"ButtonRed"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func() -> void:
		overlay.visible = false
		if _confirm_action.is_valid():
			_confirm_action.call())
	_confirm_yes = yes
	buttons.add_child(yes)
	var no := _button("Batal", 18)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void: overlay.visible = false)
	buttons.add_child(no)
	box.add_child(buttons)
	return overlay


## Centered bordered panel; returns the VBox to fill.
func _panel(parent: Control, width: float, kind := "green") -> VBoxContainer:
	var center := CenterContainer.new()
	_fill(center)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiSkin.panel(kind, 12.0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box


## Parchment theme shared by the game's windows (see UiSkin).
static func make_theme() -> Theme:
	return UiSkin.theme()


func _title(text: String) -> Label:
	var l := _label(text, 26, UiSkin.CREAM)  # sits on the panel's ribbon
	l.add_theme_font_override("font", Hud.TITLE_FONT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	return b


func _fill(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
