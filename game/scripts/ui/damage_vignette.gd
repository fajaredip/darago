class_name DamageVignette
extends ColorRect
## Red glow at the screen edges: flashes when the player is hit and pulses
## while HP is low.

const LOW_HP := 0.3

const SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.75);
	float edge = smoothstep(0.28, 0.62, length(p));
	COLOR = vec4(0.7, 0.02, 0.03, edge * intensity);
}
"""

var _hit := 0.0
var _time := 0.0
var _mat := ShaderMaterial.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER
	_mat.shader = shader
	material = _mat


func hit(strength := 1.0) -> void:
	_hit = maxf(_hit, strength)


## Called every frame with the player's HP fraction.
func update(hp_frac: float, delta: float) -> void:
	_time += delta
	_hit = maxf(_hit - delta * 2.2, 0.0)
	var low := 0.0
	if hp_frac < LOW_HP and hp_frac > 0.0:
		var depth := 1.0 - hp_frac / LOW_HP
		low = (0.3 + 0.35 * depth) * (0.75 + 0.25 * sin(_time * 5.0))
	var intensity := maxf(low, _hit * 0.6)
	# Kept drawn at a tiny value the first frames so the shader compiles before the fight.
	visible = intensity > 0.005 or _time < 0.2
	_mat.set_shader_parameter("intensity", intensity)
