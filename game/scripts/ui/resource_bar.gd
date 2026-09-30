class_name ResourceBar
extends Control
## Framed HP / MP bar. When the value drops, a pale "ghost" part stays for a
## moment and then drains, so the size of a hit stays readable.

const GHOST_HOLD := 0.45
const GHOST_DRAIN := 0.6  # fraction of the bar per second

var _fill: Color
var _prefix: String
var _value := 1.0
var _max := 1.0
var _ghost := 1.0
var _hold := 0.0
var _use_ghost := true
## Text drawn on the bar: off, or a fixed text instead of "HP  473 / 500".
var show_text := true
var text_override := ""
var text_size := 14


func _init(fill: Color, prefix: String, width := 480.0, height := 22.0, ghost := true) -> void:
	_use_ghost = ghost
	_fill = fill
	_prefix = prefix
	custom_minimum_size = Vector2(width, height)
	mouse_filter = MOUSE_FILTER_IGNORE


func set_values(value: float, max_value: float) -> void:
	max_value = maxf(max_value, 0.001)
	if is_equal_approx(value, _value) and is_equal_approx(max_value, _max):
		return
	var frac := clampf(value / max_value, 0.0, 1.0)
	if frac < _value / _max - 0.0001:
		_hold = GHOST_HOLD  # every new hit restarts the pause
	if frac > _ghost or not _use_ghost:
		_ghost = frac
	_value = value
	_max = max_value
	queue_redraw()


func fraction() -> float:
	return clampf(_value / _max, 0.0, 1.0)


func _process(delta: float) -> void:
	var frac := fraction()
	if _ghost <= frac:
		return
	if _hold > 0.0:
		_hold -= delta
	else:
		_ghost = maxf(frac, _ghost - GHOST_DRAIN * delta)
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.03, 0.03, 0.05, 0.72)
	frame.border_color = Color(0.85, 0.7, 0.42, 0.9)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(5)
	frame.anti_aliasing = true
	draw_style_box(frame, rect)

	var inner := rect.grow(-3.0)
	var frac := fraction()
	if _ghost > frac:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * _ghost, inner.size.y)), Color(1.0, 0.93, 0.78, 0.85))
	if frac > 0.0:
		var w := inner.size.x * frac
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), _fill)
		# Light strip on top and a dark one at the bottom give the bar some volume.
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y * 0.38)), Color(1.0, 1.0, 1.0, 0.18))
		draw_rect(Rect2(inner.position + Vector2(0.0, inner.size.y * 0.8), Vector2(w, inner.size.y * 0.2)), Color(0.0, 0.0, 0.0, 0.18))
	# Quarter ticks help judge the value at a glance.
	for q in [0.25, 0.5, 0.75]:
		var x: float = inner.position.x + inner.size.x * q
		draw_line(Vector2(x, inner.position.y + 2.0), Vector2(x, inner.end.y - 2.0), Color(0.0, 0.0, 0.0, 0.3), 1.0)

	if not show_text:
		return
	var font := get_theme_default_font()
	var fsize := text_size
	var text := text_override if text_override != "" else "%s  %d / %d" % [_prefix, ceili(_value) if _prefix == "HP" else floori(_value), roundi(_max)]
	var baseline := (size.y + font.get_ascent(fsize) - font.get_descent(fsize)) * 0.5
	var pos := Vector2(0.0, baseline)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fsize, 4, Color(0, 0, 0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fsize, Color.WHITE)
