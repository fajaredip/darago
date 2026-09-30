class_name SkillSlot
extends Control
## One HUD skill button: icon, key, clockwise cooldown sweep, a flash when the
## skill is ready again, and tints for "not enough MP" / "can't use now".

const SIZE := 72.0

var _icon: Texture2D
var _color: Color
var _remaining := 0.0
var _total := 0.0
var _usable := true
var _denied := false
var _flash := 0.0
var _box := StyleBoxFlat.new()
var _key_label: Label
var _cd_label: Label


func _init(icon: Texture2D, color: Color, title: String) -> void:
	_icon = icon
	_color = color
	custom_minimum_size = Vector2(SIZE, SIZE + 18.0)
	mouse_filter = MOUSE_FILTER_IGNORE
	_box.set_corner_radius_all(10)
	_box.set_border_width_all(2)
	_box.anti_aliasing = true

	_key_label = _label(15, color.lightened(0.45), 4)
	_key_label.position = Vector2(6.0, 1.0)
	add_child(_key_label)
	_cd_label = _label(24, Color.WHITE, 6)
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label.size = Vector2(SIZE, SIZE)
	add_child(_cd_label)
	var name_label := _label(12, Color(1.0, 1.0, 1.0, 0.85), 4)
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-14.0, SIZE + 1.0)
	name_label.size = Vector2(SIZE + 28.0, 17.0)
	add_child(name_label)


func set_key(text: String) -> void:
	_key_label.text = text


func set_state(remaining: float, total: float, usable: bool, denied: bool) -> void:
	if _remaining > 0.05 and remaining <= 0.05:
		_flash = 1.0  # just came off cooldown
	var changed := not is_equal_approx(remaining, _remaining) or usable != _usable or denied != _denied
	_remaining = remaining
	_total = total
	_usable = usable
	_denied = denied
	_cd_label.text = ("%.1f" % remaining) if remaining > 0.05 else ""
	if changed:
		queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	var is_ready := _remaining <= 0.05
	var edge := _color if is_ready and _usable else _color.darkened(0.45)
	if _denied:
		edge = Color(1.0, 0.35, 0.3)
	_box.bg_color = Color(_color.r * 0.22, _color.g * 0.22, _color.b * 0.22, 0.9)
	_box.border_color = edge.lerp(Color.WHITE, _flash)
	draw_style_box(_box, rect)

	var tint := _color.lightened(0.55)
	if _denied:
		tint = Color(1.0, 0.45, 0.4)
	elif not _usable:
		tint = Color(0.45, 0.5, 0.75)  # not enough MP
	elif not is_ready:
		tint = tint.darkened(0.3)
	draw_texture_rect(_icon, rect.grow(-11.0), false, tint)

	if not is_ready and _total > 0.0:
		_draw_sweep(rect.grow(-2.0), clampf(_remaining / _total, 0.0, 1.0))
	if _flash > 0.0:
		var glow := StyleBoxFlat.new()
		glow.set_corner_radius_all(10)
		glow.bg_color = Color(1.0, 1.0, 1.0, 0.35 * _flash)
		draw_style_box(glow, rect)


## Dark sector covering the part of the cooldown still left, shrinking clockwise.
func _draw_sweep(rect: Rect2, frac: float) -> void:
	var c := rect.get_center()
	var half := rect.size * 0.5
	var points := PackedVector2Array([c])
	var start := -PI * 0.5 + TAU * (1.0 - frac)
	var steps := maxi(ceili(frac * 48.0), 2)
	for i in steps + 1:
		var a := start + TAU * frac * i / steps
		var dir := Vector2(cos(a), sin(a))
		# Ray from the center to the edge of the square.
		var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
		points.append(c + dir * t)
	draw_colored_polygon(points, Color(0.0, 0.0, 0.0, 0.62))


func _label(font_size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l
