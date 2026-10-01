class_name UiSkin
extends RefCounted
## Parchment look shared by every window: 9-slice panels, beige / green / red
## buttons, item slots and the ink colours for text drawn on paper.
## Art: assets/ui/parchment (cut from art_source/ui_parchment by tests/slice_ui_sheet.gd).

const DIR := "res://assets/ui/parchment/"

## Text on parchment.
const INK := Color(0.24, 0.16, 0.09)
const INK_MUTED := Color(0.45, 0.35, 0.25)
const INK_TITLE := Color(0.5, 0.16, 0.08)
const INK_VALUE := Color(0.45, 0.24, 0.05)
## Text on the red / green ribbons and on coloured buttons.
const CREAM := Color(1.0, 0.95, 0.84)
const GOOD := Color(0.12, 0.5, 0.12)
const BAD := Color(0.75, 0.16, 0.1)

## [texture, left, top, right, bottom] 9-slice margins (pixels of the scaled art).
const PANELS := {
	"plain": ["panel.png", 40, 40, 40, 40],
	"red": ["panel_red.png", 44, 58, 44, 40],
	"green": ["panel_green.png", 44, 58, 44, 40],
	"tooltip": ["tooltip.png", 22, 22, 22, 22],
}


static func texture(file: String) -> Texture2D:
	return load(DIR + file)


## Window background. `pad` is extra room between the frame and the content.
static func panel(kind := "plain", pad := 10.0) -> StyleBoxTexture:
	var p: Array = PANELS[kind]
	var sb := StyleBoxTexture.new()
	sb.texture = texture(p[0])
	sb.texture_margin_left = p[1]
	sb.texture_margin_top = p[2]
	sb.texture_margin_right = p[3]
	sb.texture_margin_bottom = p[4]
	sb.content_margin_left = p[1] * 0.6 + pad
	sb.content_margin_right = p[3] * 0.6 + pad
	# On ribbon panels the first row (the title) sits on the ribbon itself.
	sb.content_margin_top = 14.0 if kind != "plain" and kind != "tooltip" else p[2] * 0.6 + pad
	sb.content_margin_bottom = p[4] * 0.6 + pad
	return sb


## Button background: colour "" (beige), "green" or "red"; state "", "hover" or "pressed".
static func button(color := "", state := "") -> StyleBoxTexture:
	var file := "button"
	if color != "":
		file += "_" + color
	if state != "":
		file += "_" + state
	var sb := StyleBoxTexture.new()
	sb.texture = texture(file + ".png")
	sb.texture_margin_left = 18
	sb.texture_margin_right = 18
	sb.texture_margin_top = 16
	sb.texture_margin_bottom = 16
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10 if state != "pressed" else 8
	return sb


## Recessed item slot. Brighter when hovered.
static func slot(hover := false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture("slot.png")
	sb.set_texture_margin_all(16)
	if hover:
		sb.modulate_color = Color(1.12, 1.1, 1.05)
	return sb


## Coloured outline drawn over a slot: rarity of the item (none for Normal or
## empty), white when picked. Rare and Epic glow.
static func rarity_border(item: Dictionary, selected := false) -> StyleBox:
	var rarity := int(item.get("rarity", 0))
	if item.is_empty() or (rarity == 0 and not selected):
		return StyleBoxEmpty.new()
	var c := ItemDB.color(item)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(6)
	sb.border_color = c.lerp(Color.WHITE, 0.5) if selected else c
	sb.set_border_width_all(4 if selected else 3)
	sb.expand_margin_left = 1
	sb.expand_margin_right = 1
	sb.expand_margin_top = 1
	sb.expand_margin_bottom = 1
	if rarity >= 2 or selected:
		sb.shadow_color = Color(c.r, c.g, c.b, 0.55)
		sb.shadow_size = 6
	return sb


## Theme for windows on parchment: ink text, beige buttons, and the
## "ButtonGreen" / "ButtonRed" variations for confirm / danger buttons.
static func theme() -> Theme:
	var t := Theme.new()
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, button())
		t.set_stylebox("hover", type, button("", "hover"))
		t.set_stylebox("pressed", type, button("", "pressed"))
		t.set_stylebox("disabled", type, _dim(button()))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_disabled_color", type, INK_MUTED)
	for variation in [["ButtonGreen", "green"], ["ButtonRed", "red"]]:
		var name: String = variation[0]
		t.set_type_variation(name, "Button")
		t.set_stylebox("normal", name, button(variation[1]))
		t.set_stylebox("hover", name, button(variation[1], "hover"))
		t.set_stylebox("pressed", name, button(variation[1], "pressed"))
		t.set_stylebox("disabled", name, _dim(button(variation[1])))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, name, CREAM)
	t.set_stylebox("panel", "PopupMenu", panel("plain", 0.0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK_TITLE)
	t.set_color("font_disabled_color", "PopupMenu", INK_MUTED)
	t.set_color("font_color", "Label", INK)
	return t


static func _dim(sb: StyleBoxTexture) -> StyleBoxTexture:
	sb.modulate_color = Color(1, 1, 1, 0.55)
	return sb
