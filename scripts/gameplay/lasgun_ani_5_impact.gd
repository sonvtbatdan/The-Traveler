extends Node2D
## lasgun_ani_5_impact — procedural radial energy burst (see lasgun_ani_5_impact.gdshader). Replaces
## the hand-drawn 12-frame impact flipbook, in the same palette as the muzzle/body so the beam reads
## as one continuous system instead of stamped sprites at each end.

const FxShader := preload("res://scripts/gameplay/lasgun_ani_5_impact.gdshader")

var beam   # untyped back-reference to lasgun_ani_5.gd (dynamic access to its @export tunables)

# Per-frame state, pushed by the parent's _process() before it calls queue_redraw() on this node.
var _to := Vector2.ZERO
var _ang := 0.0
var _hit := false
var _t := 0.0
var _activation := 0.0

func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = FxShader
	material = m
	m.set_shader_parameter("spikes", beam.im_spikes)
	m.set_shader_parameter("spike_min", beam.im_spike_min)
	m.set_shader_parameter("notch", beam.im_notch)
	m.set_shader_parameter("len_jitter", beam.im_len_jitter)
	m.set_shader_parameter("body_round", beam.im_body_round)
	m.set_shader_parameter("round_var", beam.im_round_var)
	m.set_shader_parameter("tip_frac", beam.im_tip_frac)
	m.set_shader_parameter("distort_amount", beam.im_distort)
	m.set_shader_parameter("core_radius", beam.im_core_radius)
	m.set_shader_parameter("core_color", beam.fx_core_color)
	m.set_shader_parameter("body_color", beam.fx_body_color)
	m.set_shader_parameter("glow_color", beam.fx_glow_color)

func _draw() -> void:
	if _activation <= 0.0001 or not _hit:
		return
	var pulse: float = 1.0 + sin(_t * beam.cap_pulse_speed) * beam.cap_pulse_amt
	var reach: float = beam.impact_cap_len * pulse
	if reach < 1.0:
		return

	var m := material as ShaderMaterial
	m.set_shader_parameter("frame", floor(_t * beam.muzzle_fps))
	m.set_shader_parameter("activation", _activation)

	draw_set_transform(_to, _ang, Vector2.ONE)
	draw_rect(Rect2(-reach * 0.5, -reach * 0.5, reach, reach), Color(1.0, 1.0, 1.0, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
