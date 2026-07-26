extends CanvasLayer
## Screen ambient darkening (vignette) + player hit flash. A full-viewport ColorRect overlay UNDER the HUD:
## the screen edges darken (dark-environment mood — the light reads as centered on the player, who the follow
## camera keeps at screen centre), and the whole screen tints on a player hit — BLUE when the shield absorbs
## it, WHITE-RED when it reaches the hull. Poll-based off GameManager ship_hp / ship_shield.

const SHADER_CODE := "shader_type canvas_item;
uniform float vig_strength : hint_range(0.0, 1.0) = 0.45;
uniform float vig_inner = 0.34;
uniform float vig_outer = 0.98;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.4, 0.35, 1.0);
void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.42;                 // 0 centre → ~1 corner
	float vig = smoothstep(vig_inner, vig_outer, d) * vig_strength;   // black edge darkening
	float fa = flash * (0.35 + 0.65 * smoothstep(0.15, 1.0, d));      // hit tint, edge-weighted
	float a = fa + vig * (1.0 - fa);                          // flash (colour) composited over vignette (black)
	vec3 c = flash_color.rgb * fa / max(a, 0.0001);
	COLOR = vec4(c, a);
}"

const FLASH_DUR := 0.35
const HULL_COL := Color(1.0, 0.4, 0.35)     # white-red — took hull damage
const SHIELD_COL := Color(0.35, 0.6, 1.0)   # blue — shield absorbed the hit

var _mat: ShaderMaterial = null
var _flash: float = 0.0
var _prev_hp: float = -1.0
var _prev_sh: float = -1.0

func _ready() -> void:
	layer = 9   # above gameplay, below the HUD (layer 10) so the HUD isn't darkened/tinted
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _mat
	add_child(rect)

func _process(delta: float) -> void:
	var hp := float(GameManager.ship_hp)
	var shd := float(GameManager.ship_shield)
	if _prev_hp >= 0.0:
		if hp < _prev_hp - 0.01:
			_flash = 1.0
			_mat.set_shader_parameter("flash_color", HULL_COL)     # hull damage → white-red
		elif shd < _prev_sh - 0.01:
			_flash = 1.0
			_mat.set_shader_parameter("flash_color", SHIELD_COL)   # shield absorbed → blue
	_prev_hp = hp
	_prev_sh = shd
	_flash = maxf(0.0, _flash - delta / FLASH_DUR)
	_mat.set_shader_parameter("flash", _flash)
