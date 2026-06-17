extends Sprite2D
## A comet — a soft diffuse bright head blending into a streaky translucent tail, rendered by a shader on a
## long rectangular quad (this Sprite2D + a 4×4 white tex so UV spans 0..1), ROTATED so local +X = the tail
## direction (away from the light/star). Additive blend. Slow drift.
##
## TWO LOOKS for A/B — flip COMET_VERSION:
##   1 = comet_1.gdshader (archived cone: narrow head → fans wider toward the tip)
##   2 = comet_2.gdshader (teardrop: widest at the head → narrows to a fine point)
## Each version is self-contained (_apply_v1 / _apply_v2 + its own V1_/V2_ tunables) so flipping is faithful.

const COMET_VERSION := 2
const SHADER_1 := "res://assets/shaders/comet_1.gdshader"
const SHADER_2 := "res://assets/shaders/comet_2.gdshader"

# ── COMMON TUNABLES ─────────────────────────────────────────────────────────────
const QUAD_LEN      := Vector2(560.0, 820.0)  # quad length px (along the tail) — long
const QUAD_ASPECT   := Vector2(2.4, 3.0)      # length/height → elongated
const HEAD_X        := 0.16                    # head position along the quad (UV.x; left margin for the coma)
const TAIL_LENGTH   := Vector2(0.72, 0.86)    # how far down-tail the tail reaches (UV.x)
const COMA_COLOR    := Color(0.85, 0.92, 1.0) # bluish-white head
const TAIL_COLOR    := Color(0.55, 0.78, 1.0) # white-blue → faint cyan dust tail
const ION_COLOR     := Color(0.45, 0.65, 1.0) # straighter, bluer ion tail
const SECOND_TAIL   := true                   # false → one tail only
const ION_ANGLE     := Vector2(0.04, 0.09)    # ion-tail shear (small → same-way trail, no X)
const LIGHT_DIR     := Vector2(0.6, -0.5)     # tail blows opposite this
const DRIFT_SPEED   := Vector2(16.0, 38.0)    # travel speed px/s (head-first, opposite the tail)

# ── V1 TUNABLES (archived cone look) ────────────────────────────────────────────
const V1_TAIL_BASE_MULT := 0.95
const V1_FAN_SPREAD     := Vector2(0.16, 0.26)
const V1_TAIL_SOFTNESS  := Vector2(1.5, 2.3)
const V1_TAIL_OPACITY   := Vector2(0.55, 0.8)
const V1_CORE_SIZE      := Vector2(0.028, 0.045)
const V1_CORE_BRIGHT    := Vector2(1.7, 2.3)
const V1_COMA_SIZE      := Vector2(0.09, 0.13)
const V1_COMA_GLOW      := Vector2(0.28, 0.48)
const V1_STREAK_INTENSITY := Vector2(0.5, 0.85)
const V1_STREAK_FINE    := Vector2(16.0, 26.0)
const V1_STREAK_LEN     := Vector2(2.0, 3.5)
const V1_CURVE_AMOUNT   := Vector2(0.06, 0.14)
const V1_EDGE_IRREG     := Vector2(0.02, 0.05)
const V1_ION_FAN_SPREAD := 0.09

# ── V2 TUNABLES (teardrop look) ─────────────────────────────────────────────────
const V2_TAIL_BASE_MULT := 1.05               # head (widest) half-width = coma_size * this
const V2_TAPER_POW      := Vector2(0.7, 1.1)  # taper curve (lower = stays fat longer)
const V2_TIP_FRAC       := Vector2(0.04, 0.10) # tip half-width as a fraction of the head (→ fine point)
const V2_TAIL_SOFTNESS  := Vector2(1.4, 2.2)
const V2_TAIL_OPACITY   := Vector2(0.30, 0.5) # delicate / translucent
const V2_TAIL_FADE      := Vector2(2.2, 3.0)  # brightness fade down-tail (higher = head-concentrated)
const V2_CORE_SIZE      := Vector2(0.03, 0.05)
const V2_CORE_BRIGHT    := Vector2(1.5, 2.0)
const V2_COMA_SIZE      := Vector2(0.11, 0.16) # bigger → more diffuse head
const V2_COMA_GLOW      := Vector2(0.35, 0.55)
const V2_HEAD_SOFTNESS  := Vector2(1.2, 1.5)  # <2 = softer, broader glow melting into the tail
const V2_HEAD_ELONG     := Vector2(1.9, 2.8)  # oblong head stretched along the tail axis (not round)
const V2_STREAK_INTENSITY := Vector2(0.4, 0.7)
const V2_STREAK_FINE    := Vector2(28.0, 44.0) # fine dense silky strands
const V2_STREAK_LEN     := Vector2(2.0, 3.5)
const V2_FLOW_SPEED     := Vector2(0.04, 0.10) # tail filaments scroll head→tip → travelling-through-space feel
const V2_FLICKER_AMT    := Vector2(0.12, 0.24) # per-strand brightness boil
const V2_FLICKER_SPEED  := Vector2(1.2, 2.2)
const V2_WOBBLE_AMT     := Vector2(0.012, 0.028) # slow sideways breathing of the filaments
const V2_WOBBLE_SPEED   := Vector2(0.6, 1.2)
const V2_HEAD_PULSE_AMT := Vector2(0.08, 0.16) # gentle nucleus brightness pulse
const V2_HEAD_PULSE_SPEED := Vector2(1.4, 2.6)
const V2_CURVE_AMOUNT   := Vector2(0.04, 0.10)
const V2_EDGE_IRREG     := Vector2(0.015, 0.04)

static var _white_tex: Texture2D = null
static var _shaders: Dictionary = {}   # path → Shader (cached)

var _drift := Vector2.ZERO

func _get_shader(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path)
	return _shaders[path]

func setup(rng: RandomNumberGenerator) -> void:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	texture = _white_tex
	centered = true

	# Long rectangular quad, rotated so local +X points down-tail (away from the light).
	var tail_dir := (-LIGHT_DIR).normalized()
	var length := rng.randf_range(QUAD_LEN.x, QUAD_LEN.y)
	var aspect := rng.randf_range(QUAD_ASPECT.x, QUAD_ASPECT.y)
	var height := length / aspect
	var texw := float(_white_tex.get_width())
	scale = Vector2(length, height) / texw
	rotation = tail_dir.angle()

	var m := ShaderMaterial.new()
	if COMET_VERSION == 2:
		m.shader = _get_shader(SHADER_2)
		_apply_v2(m, rng, aspect)
	else:
		m.shader = _get_shader(SHADER_1)
		_apply_v1(m, rng, aspect)
	material = m

	# Travel head-first: the head leads (opposite the tail direction), so it looks like it's flying forward.
	var ds := rng.randf_range(DRIFT_SPEED.x, DRIFT_SPEED.y)
	_drift = -tail_dir * ds

func _rand_sign(rng: RandomNumberGenerator) -> float:
	return 1.0 if rng.randf() < 0.5 else -1.0

func _apply_v1(m: ShaderMaterial, rng: RandomNumberGenerator, aspect: float) -> void:
	m.set_shader_parameter("head_x", HEAD_X)
	m.set_shader_parameter("aspect", aspect)
	m.set_shader_parameter("tail_length", rng.randf_range(TAIL_LENGTH.x, TAIL_LENGTH.y))
	m.set_shader_parameter("tail_base_mult", V1_TAIL_BASE_MULT)
	m.set_shader_parameter("fan_spread", rng.randf_range(V1_FAN_SPREAD.x, V1_FAN_SPREAD.y))
	m.set_shader_parameter("tail_softness", rng.randf_range(V1_TAIL_SOFTNESS.x, V1_TAIL_SOFTNESS.y))
	m.set_shader_parameter("tail_opacity", rng.randf_range(V1_TAIL_OPACITY.x, V1_TAIL_OPACITY.y))
	m.set_shader_parameter("core_size", rng.randf_range(V1_CORE_SIZE.x, V1_CORE_SIZE.y))
	m.set_shader_parameter("core_brightness", rng.randf_range(V1_CORE_BRIGHT.x, V1_CORE_BRIGHT.y))
	m.set_shader_parameter("coma_size", rng.randf_range(V1_COMA_SIZE.x, V1_COMA_SIZE.y))
	m.set_shader_parameter("coma_glow", rng.randf_range(V1_COMA_GLOW.x, V1_COMA_GLOW.y))
	m.set_shader_parameter("streak_intensity", rng.randf_range(V1_STREAK_INTENSITY.x, V1_STREAK_INTENSITY.y))
	m.set_shader_parameter("streak_fine", rng.randf_range(V1_STREAK_FINE.x, V1_STREAK_FINE.y))
	m.set_shader_parameter("streak_len", rng.randf_range(V1_STREAK_LEN.x, V1_STREAK_LEN.y))
	m.set_shader_parameter("curve_amount", rng.randf_range(V1_CURVE_AMOUNT.x, V1_CURVE_AMOUNT.y) * _rand_sign(rng))
	m.set_shader_parameter("edge_irregularity", rng.randf_range(V1_EDGE_IRREG.x, V1_EDGE_IRREG.y))
	m.set_shader_parameter("ion_fan_spread", V1_ION_FAN_SPREAD)
	m.set_shader_parameter("coma_color", COMA_COLOR)
	m.set_shader_parameter("tail_color", TAIL_COLOR)
	m.set_shader_parameter("ion_color", ION_COLOR)
	m.set_shader_parameter("second_tail", SECOND_TAIL)
	m.set_shader_parameter("ion_angle", rng.randf_range(ION_ANGLE.x, ION_ANGLE.y))
	m.set_shader_parameter("seed", rng.randf() * 100.0)

func _apply_v2(m: ShaderMaterial, rng: RandomNumberGenerator, aspect: float) -> void:
	m.set_shader_parameter("head_x", HEAD_X)
	m.set_shader_parameter("aspect", aspect)
	m.set_shader_parameter("tail_length", rng.randf_range(TAIL_LENGTH.x, TAIL_LENGTH.y))
	m.set_shader_parameter("tail_base_mult", V2_TAIL_BASE_MULT)
	m.set_shader_parameter("taper_pow", rng.randf_range(V2_TAPER_POW.x, V2_TAPER_POW.y))
	m.set_shader_parameter("tip_frac", rng.randf_range(V2_TIP_FRAC.x, V2_TIP_FRAC.y))
	m.set_shader_parameter("tail_softness", rng.randf_range(V2_TAIL_SOFTNESS.x, V2_TAIL_SOFTNESS.y))
	m.set_shader_parameter("tail_opacity", rng.randf_range(V2_TAIL_OPACITY.x, V2_TAIL_OPACITY.y))
	m.set_shader_parameter("tail_fade", rng.randf_range(V2_TAIL_FADE.x, V2_TAIL_FADE.y))
	m.set_shader_parameter("core_size", rng.randf_range(V2_CORE_SIZE.x, V2_CORE_SIZE.y))
	m.set_shader_parameter("core_brightness", rng.randf_range(V2_CORE_BRIGHT.x, V2_CORE_BRIGHT.y))
	m.set_shader_parameter("coma_size", rng.randf_range(V2_COMA_SIZE.x, V2_COMA_SIZE.y))
	m.set_shader_parameter("coma_glow", rng.randf_range(V2_COMA_GLOW.x, V2_COMA_GLOW.y))
	m.set_shader_parameter("head_softness", rng.randf_range(V2_HEAD_SOFTNESS.x, V2_HEAD_SOFTNESS.y))
	m.set_shader_parameter("head_elong", rng.randf_range(V2_HEAD_ELONG.x, V2_HEAD_ELONG.y))
	m.set_shader_parameter("streak_intensity", rng.randf_range(V2_STREAK_INTENSITY.x, V2_STREAK_INTENSITY.y))
	m.set_shader_parameter("streak_fine", rng.randf_range(V2_STREAK_FINE.x, V2_STREAK_FINE.y))
	m.set_shader_parameter("streak_len", rng.randf_range(V2_STREAK_LEN.x, V2_STREAK_LEN.y))
	m.set_shader_parameter("flow_speed", rng.randf_range(V2_FLOW_SPEED.x, V2_FLOW_SPEED.y))
	m.set_shader_parameter("flicker_amt", rng.randf_range(V2_FLICKER_AMT.x, V2_FLICKER_AMT.y))
	m.set_shader_parameter("flicker_speed", rng.randf_range(V2_FLICKER_SPEED.x, V2_FLICKER_SPEED.y))
	m.set_shader_parameter("wobble_amt", rng.randf_range(V2_WOBBLE_AMT.x, V2_WOBBLE_AMT.y))
	m.set_shader_parameter("wobble_speed", rng.randf_range(V2_WOBBLE_SPEED.x, V2_WOBBLE_SPEED.y))
	m.set_shader_parameter("head_pulse_amt", rng.randf_range(V2_HEAD_PULSE_AMT.x, V2_HEAD_PULSE_AMT.y))
	m.set_shader_parameter("head_pulse_speed", rng.randf_range(V2_HEAD_PULSE_SPEED.x, V2_HEAD_PULSE_SPEED.y))
	m.set_shader_parameter("curve_amount", rng.randf_range(V2_CURVE_AMOUNT.x, V2_CURVE_AMOUNT.y) * _rand_sign(rng))
	m.set_shader_parameter("edge_irregularity", rng.randf_range(V2_EDGE_IRREG.x, V2_EDGE_IRREG.y))
	m.set_shader_parameter("coma_color", COMA_COLOR)
	m.set_shader_parameter("tail_color", TAIL_COLOR)
	m.set_shader_parameter("ion_color", ION_COLOR)
	m.set_shader_parameter("second_tail", SECOND_TAIL)
	m.set_shader_parameter("ion_angle", rng.randf_range(ION_ANGLE.x, ION_ANGLE.y))
	m.set_shader_parameter("seed", rng.randf() * 100.0)

func _process(delta: float) -> void:
	position += _drift * delta
