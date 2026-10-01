class_name SkillWindow
extends CanvasLayer
## Skill tree (K), laid out like Dragon Nest's: the class's skills on a grid
## (arrows show what a skill needs first), "+" spends SP, SP total on the left,
## and the quickslot bar at the bottom. Drag a learned active skill (or a potion)
## onto a quickslot; drag slots to swap them; right-click or drag out to clear.
## The game pauses while it is open.

const INK := Color(0.24, 0.16, 0.09)
const INK_MUTED := Color(0.45, 0.35, 0.25)
const INK_VALUE := Color(0.45, 0.24, 0.05)
const CREAM := Color(1.0, 0.95, 0.84)
const BAD := Color(0.75, 0.16, 0.1)
const CELL := Vector2(168.0, 78.0)
const ICON := 62.0
const QUICK := 50.0
const POTION_HP := preload("res://assets/ui/items/potion_hp.png")
const POTION_MP := preload("res://assets/ui/items/potion_mp.png")


## A skill icon in the grid; learned active skills can be dragged to a quickslot.
class SkillIcon extends Control:
	var window: SkillWindow
	var skill: SkillData

	func _get_drag_data(_at: Vector2) -> Variant:
		if skill.kind != SkillData.Kind.ACTIVE or Progress.skill_level(skill) <= 0:
			return null
		set_drag_preview(window.drag_preview(skill.icon))
		return {"entry": "skill:" + String(skill.id)}

	func _draw() -> void:
		draw_style_box(UiSkin.slot(), Rect2(Vector2.ZERO, size))
		var learned := Progress.skill_level(skill) > 0
		draw_texture_rect(skill.icon, Rect2(Vector2.ONE * 6.0, size - Vector2.ONE * 12.0), false,
				Color.WHITE if learned else Color(0.35, 0.33, 0.32))


## A potion in the "Item" box, draggable to a quickslot.
class PotionIcon extends Control:
	var window: SkillWindow
	var entry := ""
	var icon: Texture2D

	func _get_drag_data(_at: Vector2) -> Variant:
		set_drag_preview(window.drag_preview(icon))
		return {"entry": entry}

	func _draw() -> void:
		draw_style_box(UiSkin.slot(), Rect2(Vector2.ZERO, size))
		draw_texture_rect(icon, Rect2(Vector2.ONE * 5.0, size - Vector2.ONE * 10.0), false)


## One of the 10 quickslots: drop target, and draggable to swap / clear.
class QuickCell extends Control:
	var window: SkillWindow
	var index := 0

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("entry")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("from_slot"):
			Progress.swap_quickslots(int(data["from_slot"]), index)
		else:
			Progress.set_quickslot(index, String(data["entry"]))
		Sfx.play("equip")

	func _get_drag_data(_at: Vector2) -> Variant:
		var entry := Progress.quickslot(index)
		if entry == "":
			return null
		set_drag_preview(window.drag_preview(window.entry_icon(entry)))
		return {"entry": entry, "from_slot": index}

	func _notification(what: int) -> void:
		# Dragged out of the bar and dropped anywhere else: the slot is cleared.
		if what == NOTIFICATION_DRAG_END and not get_viewport().gui_is_drag_successful():
			var data: Variant = get_viewport().gui_get_drag_data()
			if data is Dictionary and int(data.get("from_slot", -1)) == index:
				Progress.set_quickslot(index, "")

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			Progress.set_quickslot(index, "")

	func _draw() -> void:
		draw_style_box(UiSkin.slot(), Rect2(Vector2.ZERO, size))
		var tex := window.entry_icon(Progress.quickslot(index))
		if tex:
			draw_texture_rect(tex, Rect2(Vector2.ONE * 5.0, size - Vector2.ONE * 10.0), false)
		var font := get_theme_default_font()
		var key := Settings.key_name(Progress.QUICKSLOT_ACTIONS[index])
		draw_string_outline(font, Vector2(5.0, 14.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(5.0, 14.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CREAM)


var _root: Control
var _grid: Control
var _cells := {}
var _quick: Array[QuickCell] = []
var _sp_left: Label
var _sp_used: Label
var _reset_btn: Button
var _reset_armed := 0.0
var _tooltip: PanelContainer
var _tip_title: Label
var _tip_body: RichTextLabel
var _hover_skill: SkillData


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Progress.changed.connect(_refresh)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_root.visible = false
	_tooltip.visible = false
	get_tree().paused = false
	if not Game.test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed(&"menu"):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"skills"):
		return
	if _root.visible:
		close()
	elif not get_tree().paused:
		open()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _reset_armed > 0.0:
		_reset_armed -= delta
		if _reset_armed <= 0.0:
			_reset_btn.text = "Reset SP"
	if _tooltip.visible:
		var at := _root.get_global_mouse_position() + Vector2(18.0, 18.0)
		var limit := _root.size - _tooltip.size - Vector2(8.0, 8.0)
		_tooltip.position = at.clamp(Vector2.ZERO, limit)


# --- actions -----------------------------------------------------------------

func raise(skill: SkillData) -> bool:
	if Progress.raise_skill(_stats(), skill):
		Sfx.play("level_up")
		return true
	Sfx.play("deny")
	return false


func _on_reset_pressed() -> void:
	# Free, but asks for a second click so it is not done by accident.
	if _reset_armed <= 0.0:
		_reset_armed = 3.0
		_reset_btn.text = "Klik lagi untuk reset"
		return
	_reset_armed = 0.0
	_reset_btn.text = "Reset SP"
	Progress.reset_skills(_stats())
	Sfx.play("equip")


func drag_preview(tex: Texture2D) -> Control:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = Vector2(QUICK, QUICK)
	r.position = -r.size * 0.5
	var holder := Control.new()
	holder.add_child(r)
	return holder


func entry_icon(entry: String) -> Texture2D:
	if entry == "potion_hp":
		return POTION_HP
	if entry == "potion_mp":
		return POTION_MP
	if entry.begins_with("skill:"):
		var s := Progress.find_skill(_stats(), StringName(entry.trim_prefix("skill:")))
		return s.icon if s else null
	return null


func _stats() -> PlayerStats:
	return Game.player.stats


# --- refresh -------------------------------------------------------------------

func _refresh() -> void:
	if not _root.visible or Game.player == null:
		return
	var stats := _stats()
	_sp_left.text = "%d" % Progress.sp_left(stats)
	_sp_used.text = "Terpakai  %d / %d" % [Progress.sp_spent(stats), Progress.sp_total()]
	for skill: SkillData in _cells:
		var cell: Dictionary = _cells[skill]
		var lv := Progress.skill_level(skill)
		(cell["level"] as Label).text = "Lv.%d" % lv if lv > 0 else "-"
		(cell["level"] as Label).add_theme_color_override("font_color", INK if lv > 0 else INK_MUTED)
		var plus := cell["plus"] as Button
		plus.disabled = Progress.raise_blocker(stats, skill) != ""
		(cell["icon"] as Control).queue_redraw()
	for q in _quick:
		q.queue_redraw()
	_grid.queue_redraw()
	if _hover_skill:
		_show_tip(_hover_skill)


func _show_tip(skill: SkillData) -> void:
	_hover_skill = skill
	var stats := _stats()
	var lv := Progress.skill_level(skill)
	_tip_title.text = skill.display_name
	var kind := "Skill aktif" if skill.kind == SkillData.Kind.ACTIVE else "Skill pasif"
	var text := "[color=#%s]%s   Lv %d / %d[/color]\n%s\n\n" % [INK_MUTED.to_html(false), kind, lv, skill.max_level, skill.description]
	if lv > 0:
		text += "[b]Sekarang:[/b] %s\n" % skill.effect_text(lv)
	if lv < skill.max_level:
		text += "[b]Lv %d:[/b] %s\n" % [lv + 1, skill.effect_text(lv + 1)]
		text += "[color=#%s]Biaya %d SP[/color]\n" % [INK_VALUE.to_html(false), skill.sp_cost(lv + 1)]
		var blocker := Progress.raise_blocker(stats, skill)
		if blocker != "":
			text += "[color=#%s]%s[/color]\n" % [BAD.to_html(false), blocker]
	if skill.kind == SkillData.Kind.ACTIVE and lv > 0:
		text += "\n[color=#%s]Seret ke quickslot untuk dipakai.[/color]" % INK_MUTED.to_html(false)
	_tip_body.text = text
	_tooltip.visible = true
	_tooltip.reset_size()


func _hide_tip(skill: SkillData) -> void:
	if _hover_skill == skill:
		_hover_skill = null
		_tooltip.visible = false


# --- build --------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiSkin.theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiSkin.panel("red", 12.0))
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	outer.add_child(head)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 40.0
	head.add_child(spacer)
	var title := _label("Skill", 24, CREAM)
	title.add_theme_font_override("font", Hud.TITLE_FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := TextureButton.new()
	close_btn.texture_normal = UiSkin.texture("close.png")
	close_btn.custom_minimum_size = Vector2(40.0, 40.0)
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	outer.add_child(columns)

	# Left: class tabs, SP, reset, potions to drag.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 200.0
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var tab := _button("Warrior", 17)
	tab.theme_type_variation = &"ButtonGreen"
	left.add_child(tab)
	var spec := _button("Spesialisasi (segera)", 14)
	spec.disabled = true
	left.add_child(spec)
	left.add_child(InventoryWindow.divider())
	left.add_child(_label("SP tersisa", 15, INK_MUTED))
	_sp_left = _label("0", 34, INK_VALUE)
	_sp_left.add_theme_font_override("font", Hud.TITLE_FONT)
	left.add_child(_sp_left)
	_sp_used = _label("", 14, INK_MUTED)
	left.add_child(_sp_used)
	left.add_child(_label("+%d SP tiap naik level" % Progress.SP_PER_LEVEL, 13, INK_MUTED))
	_reset_btn = _button("Reset SP", 15)
	_reset_btn.theme_type_variation = &"ButtonRed"
	_reset_btn.pressed.connect(_on_reset_pressed)
	left.add_child(_reset_btn)
	left.add_child(InventoryWindow.divider())
	left.add_child(_label("Item", 15, INK_MUTED))
	var potions := HBoxContainer.new()
	potions.add_theme_constant_override("separation", 10)
	left.add_child(potions)
	for p in [["potion_hp", POTION_HP], ["potion_mp", POTION_MP]]:
		var pi := PotionIcon.new()
		pi.window = self
		pi.entry = p[0]
		pi.icon = p[1]
		pi.custom_minimum_size = Vector2(QUICK, QUICK)
		potions.add_child(pi)
	var help := _label("Seret skill atau potion ke quickslot di bawah. Klik kanan slot untuk mengosongkan.", 12, INK_MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 200.0
	left.add_child(help)

	# Right: the skill grid.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	_grid = Control.new()
	_grid.draw.connect(_draw_arrows)
	right.add_child(_grid)
	var rows := 1
	for skill in Progress.skills_for(Game.player.stats):
		rows = maxi(rows, skill.grid_pos.y + 1)
		_add_cell(skill)
	_grid.custom_minimum_size = Vector2(CELL.x * 4.0, CELL.y * rows + 12.0 * (rows - 1))

	right.add_child(InventoryWindow.divider())
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 6)
	quick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(quick_row)
	for i in Progress.QUICKSLOT_ACTIONS.size():
		var q := QuickCell.new()
		q.window = self
		q.index = i
		q.custom_minimum_size = Vector2(QUICK, QUICK)
		quick_row.add_child(q)
		_quick.append(q)

	_tooltip = PanelContainer.new()
	_tooltip.add_theme_stylebox_override("panel", UiSkin.panel("plain", 4.0))
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_root.add_child(_tooltip)
	var tip_box := VBoxContainer.new()
	tip_box.custom_minimum_size.x = 340.0
	_tooltip.add_child(tip_box)
	_tip_title = _label("", 18, INK)
	_tip_title.add_theme_font_override("font", Hud.TITLE_FONT)
	tip_box.add_child(_tip_title)
	_tip_body = RichTextLabel.new()
	_tip_body.bbcode_enabled = true
	_tip_body.fit_content = true
	_tip_body.scroll_active = false
	_tip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_body.custom_minimum_size.x = 340.0
	_tip_body.add_theme_font_size_override("normal_font_size", 14)
	_tip_body.add_theme_font_size_override("bold_font_size", 14)
	_tip_body.add_theme_color_override("default_color", INK)
	tip_box.add_child(_tip_body)


func _add_cell(skill: SkillData) -> void:
	var cell := Control.new()
	cell.position = Vector2(skill.grid_pos.x * CELL.x, skill.grid_pos.y * (CELL.y + 12.0))
	cell.size = CELL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(cell)
	var icon := SkillIcon.new()
	icon.window = self
	icon.skill = skill
	icon.position = Vector2(8.0, (CELL.y - ICON) * 0.5)
	icon.size = Vector2(ICON, ICON)
	icon.mouse_entered.connect(_show_tip.bind(skill))
	icon.mouse_exited.connect(_hide_tip.bind(skill))
	cell.add_child(icon)
	var lv := _label("-", 16, INK)
	lv.position = Vector2(ICON + 16.0, 8.0)
	cell.add_child(lv)
	var plus := _button("+", 18)
	plus.position = Vector2(ICON + 16.0, 36.0)
	plus.size = Vector2(38.0, 34.0)
	plus.custom_minimum_size = Vector2(38.0, 34.0)
	plus.pressed.connect(func() -> void: raise(skill))
	plus.mouse_entered.connect(_show_tip.bind(skill))
	plus.mouse_exited.connect(_hide_tip.bind(skill))
	cell.add_child(plus)
	_cells[skill] = {"icon": icon, "level": lv, "plus": plus}


## Arrows from a skill to the skill that needs it (Dragon Nest style).
func _draw_arrows() -> void:
	for skill: SkillData in _cells:
		if skill.requires == &"":
			continue
		var req := Progress.find_skill(_stats(), skill.requires)
		if req == null or not _cells.has(req):
			continue
		var from: Control = _cells[req]["icon"]
		var to: Control = _cells[skill]["icon"]
		var a: Vector2 = (from.get_parent() as Control).position + from.position + Vector2(ICON * 0.5, ICON + 2.0)
		var b: Vector2 = (to.get_parent() as Control).position + to.position + Vector2(ICON * 0.5, -4.0)
		var met := Progress.skill_level(req) >= skill.requires_level
		var c := Color(0.55, 0.32, 0.1) if met else Color(0.55, 0.47, 0.38, 0.6)
		_grid.draw_line(a, b, c, 4.0)
		_grid.draw_colored_polygon(PackedVector2Array([b + Vector2(-8, -10), b + Vector2(8, -10), b + Vector2(0, 2)]), c)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b
