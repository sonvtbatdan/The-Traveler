extends Node2D
## lasgun_ani_5 — fully procedural GPU-shader-driven beam, no sprite/texture art anywhere. Body AND
## muzzle ("head") are the SAME single-quad procedural energy-tube shader (ported from
## lasgun_ani_2.gdshader's straight-beam branch, replacing the body.png tile+fade texture): the tube's
## width envelope tapers to a true point at its origin and a radial glow makes that point read as a
## bright ignition spark, so the muzzle is literally the tube opening up rather than a separately coded
## piece glued on — nothing to visually disconnect. Impact is still its own procedural shader VFX
## (lasgun_ani_5_impact) since a burst is a genuinely different shape from a tube. Same
## set_beam/fire/release contract as lasgun_ani_1 — drop-in via a one-line preload swap in
## arena_weapons.gd. lasgun_ani_1.gd remains the known-good sprite-based fallback; this file does not
## modify it.
##
## Why split into child nodes: Godot's `material` is a CanvasItem-level property, not a per-draw-call
## one. Body and impact need their own ShaderMaterial with different uniforms live at the same time, so
## they can't share one node's material. Packets (still a plain additive glow blob, no shader needed)
## get their own child too. All of this is invisible to callers, which only ever see this root node.

const CapsScript := preload("res://scripts/gameplay/lasgun_ani_5_caps.gd")
const ImpactScript := preload("res://scripts/gameplay/lasgun_ani_5_impact.gd")
const BodyShader := preload("res://scripts/gameplay/lasgun_ani_5.gdshader")

# ── TUNABLES (Stage 1) ──────────────────────────────────────────────────────────
@export var beam_thickness  := 120.0
@export var impact_cap_len  := 170.0
@export var muzzle_fwd      := -5     # along-axis position of the tube's true origin (the ignition point)
@export var muzzle_fps      := 18.0
@export var body_v_offset   := 0.0    # was -10 in lasgun_ani_1 to recentre the old body.png art's off-centre core; the procedural shader's core is already exactly on UV.y=0.5, so no offset is needed
@export var activation_in   := 0.05
@export var activation_out  := 0.08

@export_group("Living")
@export var pulse_speed      := 6.0
@export var pulse_width_amt  := 0.06
@export var pulse_bright_amt := 0.10
@export var pulse_speed2     := 9.7
@export var flicker_amt      := 0.06
@export var flicker_speed    := 55.0
@export var wobble_amt       := 3.0
@export var wobble_speed     := 2.0
@export var packet_enabled   := true
@export var packet_count     := 3
@export var packet_speed     := 2.5
@export var packet_len       := 40.0
@export var packet_width     := 0.35
@export var packet_color     := Color(1.0, 1.0, 1.0, 0.9)

@export_group("Caps")
@export var cap_pulse_speed   := 7.0    # also drives the ignition point's subtle continuous pulse
@export var cap_pulse_amt     := 0.05
@export var birth_punch_mult  := 1.5    # fire-start punch: the ignition point's radius scales by this
@export var birth_punch_time  := 0.12   # ...easing back to 1 over this many seconds

@export_group("Short range")
@export var span_full := 120.0
@export var span_min  := 40.0

@export_group("Impact FX")
@export var im_spikes      := 10.0    # max spike count around the burst
@export var im_spike_min   := 5.0     # spikes re-roll in [im_spike_min, im_spikes] each tick
@export var im_notch       := 0.55    # valley depth between spikes (0..1)
@export var im_len_jitter  := 0.35    # per-spike length variation
@export var im_body_round  := 2.2     # >1 fat/convex, =1 diamond, <1 needle
@export var im_round_var   := 1.4     # per-spike fatness jitter
@export var im_tip_frac    := 0.35    # fraction of length used for the tip taper
@export var im_distort     := 0.12    # fbm shimmer on the tip radius
@export var im_core_radius := 0.16    # solid hot-core disc radius (fraction of quad half-size)

@export_group("Body FX")
@export var body_core_width       := 0.08
@export var body_body_width       := 0.3
@export var body_glow_width       := 0.95
@export var body_head_flare_power := 2.0
@export var body_head_softness    := 0.06
@export var body_tail_fray_amount := 0.6
@export var body_distort_amount   := 0.16
@export var body_distort_scale    := 4.0
@export var body_noise_scroll_speed := 1.4
@export var body_stria_freq       := 40.0
@export var body_stria_speed      := 8.0
@export var body_stria_strength   := 0.25
@export var body_flicker_speed    := 60.0
@export var body_flicker_amount   := 0.10
@export var body_wave_speed       := 3.0
@export var body_wave_strength    := 0.7
@export var body_roll_speed       := 1.5
@export var body_roll_amp         := 0.18
@export var body_roll_strength    := 0.5
@export var body_wave_color       := Color(1.0, 0.55, 0.35)
@export var body_cone_frac        := 0.08    # fraction of the tube's length spent opening from a point to full width
@export var body_point_radius_mult := 1.0    # ignition point radius = beam_thickness * 0.5 * this — so it always matches the tube's width
@export var body_point_boost      := 1.6     # extra brightness multiplier on the ignition point
@export var body_point_color_bias := 0.4     # 0 = point is white-hot (core_color), 1 = point is red (body_color)

@export_group("FX Palette")
@export var fx_core_color := Color(1.0, 0.95, 0.85)
@export var fx_body_color := Color(1.0, 0.25, 0.15)
@export var fx_glow_color := Color(0.85, 0.05, 0.05)

# ── STATE ───────────────────────────────────────────────────────────────────────
var _caps: Node2D = null
var _impact_fx: Node2D = null
var _muzzle_birth_t := 999.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _active := false
var _hit := false
var _was_active := false
var _t := 0.0
var _activation := 0.0

# Cached per-frame "living" state (computed once in _process, consumed by _draw() and pushed to the
# children so all nodes redraw from a single source of truth instead of recomputing pulse/wobble twice).
var _ang := 0.0
var _L := 0.0
var _conv := Vector2.ZERO
var _thick := 0.0
var _center_y := 0.0
var _bright := 1.0
var _x0 := 0.0
var _x1 := 0.0
var _body_a := 0.0

func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = BodyShader
	material = m
	m.set_shader_parameter("core_width", body_core_width)
	m.set_shader_parameter("body_width", body_body_width)
	m.set_shader_parameter("glow_width", body_glow_width)
	m.set_shader_parameter("head_flare_power", body_head_flare_power)
	m.set_shader_parameter("head_softness", body_head_softness)
	m.set_shader_parameter("tail_fray_amount", body_tail_fray_amount)
	m.set_shader_parameter("distort_amount", body_distort_amount)
	m.set_shader_parameter("distort_scale", body_distort_scale)
	m.set_shader_parameter("noise_scroll_speed", body_noise_scroll_speed)
	m.set_shader_parameter("stria_freq", body_stria_freq)
	m.set_shader_parameter("stria_speed", body_stria_speed)
	m.set_shader_parameter("stria_strength", body_stria_strength)
	m.set_shader_parameter("flicker_speed", body_flicker_speed)
	m.set_shader_parameter("flicker_amount", body_flicker_amount)
	m.set_shader_parameter("wave_speed", body_wave_speed)
	m.set_shader_parameter("wave_strength", body_wave_strength)
	m.set_shader_parameter("roll_speed", body_roll_speed)
	m.set_shader_parameter("roll_amp", body_roll_amp)
	m.set_shader_parameter("roll_strength", body_roll_strength)
	m.set_shader_parameter("core_color", fx_core_color)
	m.set_shader_parameter("body_color", fx_body_color)
	m.set_shader_parameter("glow_color", fx_glow_color)
	m.set_shader_parameter("wave_color", body_wave_color)
	m.set_shader_parameter("cone_frac", body_cone_frac)
	m.set_shader_parameter("point_boost", body_point_boost)
	m.set_shader_parameter("point_color_bias", body_point_color_bias)

	_caps = CapsScript.new()
	_caps.beam = self
	add_child(_caps)

	_impact_fx = ImpactScript.new()
	_impact_fx.beam = self
	add_child(_impact_fx)

# ── DRIVER CONTRACT (matches lasgun_ani_1) ──────────────────────────────────────
## Aim from→to, toggle on/off, flag a hit. Called every frame by arena_weapons.
func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
	if active and not _active:   # fire-start edge → restart the muzzle scale-punch
		_muzzle_birth_t = 0.0
	_was_active = _active
	_from = from
	_to = to
	_active = active
	_hit = hit

## Alias for the spec's fire(origin, target) — continuous: call each frame to keep aiming.
func fire(origin: Vector2, target: Vector2) -> void:
	set_beam(origin, target, true, _hit)

## Stop firing; the beam fades out over activation_out seconds.
func release() -> void:
	_active = false

func _process(delta: float) -> void:
	_t += delta
	_muzzle_birth_t += delta
	var target := 1.0 if _active else 0.0
	var rate := (1.0 / maxf(0.001, activation_in)) if _active else (1.0 / maxf(0.001, activation_out))
	var prev_activation := _activation
	_activation = move_toward(_activation, target, rate * delta)

	# Keep redrawing one extra frame past the moment activation reaches exactly 0 (move_toward lands
	# on the target exactly, it doesn't asymptote), so _draw() gets one last call to draw NOTHING and
	# clear each CanvasItem's cached display list. Without this, the beam freezes on its last faint
	# frame forever instead of disappearing, since a CanvasItem only redraws when queue_redraw() is
	# called — it never auto-clears just because nothing calls queue_redraw() anymore.
	if not (_active or _activation > 0.0 or prev_activation > 0.0):
		return

	var seg := _to - _from
	_L = seg.length()
	if _L >= 1.0:
		_ang = seg.angle()

		# ── Living modulators: breathe (width), wobble — the shader handles its own flicker/turbulence ──
		var pulse_w := 1.0 + sin(_t * pulse_speed) * pulse_width_amt
		var pulse_b := 1.0 + (sin(_t * pulse_speed) + sin(_t * pulse_speed2)) * 0.5 * pulse_bright_amt
		var flick := 1.0 + (sin(_t * flicker_speed) * 0.6 + sin(_t * flicker_speed * 2.3) * 0.4) * flicker_amt
		_bright = maxf(0.0, pulse_b * flick)   # consumed by the packets child only
		_thick = beam_thickness * pulse_w
		_center_y = body_v_offset + sin(_t * wobble_speed) * wobble_amt
		_conv = Vector2(muzzle_fwd, 0.0)

		# Body starts exactly at the muzzle's convergence point (no backward tuck): with the muzzle now
		# anchored close to/slightly behind the gun (muzzle_fwd), a fixed backward overlap could push the
		# body's tail behind the muzzle — and even behind the player — breaking the intended draw order
		# (player, then beam head, then beam body). The shader's own head_softness already fades the
		# body's tail in smoothly, so no manual tuck is needed to hide a hard edge.
		_x0 = _conv.x
		_x1 = _L
		_body_a = smoothstep(span_min, span_full, _L - _conv.x)

	queue_redraw()

	# Push shared per-frame state to the children and let them redraw this frame too.
	_caps._from = _from
	_caps._ang = _ang
	_caps._conv = _conv
	_caps._L = _L
	_caps._activation = _activation
	_caps._t = _t
	_caps._bright = _bright
	_caps._thick = _thick
	_caps._center_y = _center_y
	_caps.queue_redraw()

	_impact_fx._to = _to
	_impact_fx._ang = _ang
	_impact_fx._hit = _hit
	_impact_fx._t = _t
	_impact_fx._activation = _activation
	_impact_fx.queue_redraw()

## Ignition-point scale at the fire-start edge: punches to birth_punch_mult, eases back to 1 over
## birth_punch_time. Formerly lasgun_ani_5_muzzle.gd's _muzzle_birth_mult(); now drives the body
## shader's `point_radius_px` directly since the ignition point lives in the body shader itself.
func _birth_mult() -> float:
	if _muzzle_birth_t >= birth_punch_time:
		return 1.0
	var r: float = _muzzle_birth_t / maxf(0.0001, birth_punch_time)
	return lerpf(birth_punch_mult, 1.0, r * r)

func _draw() -> void:
	if _activation <= 0.0001 or _L < 1.0 or _body_a <= 0.001 or _x1 - _x0 <= 2.0:
		return
	draw_set_transform(_from, _ang, Vector2.ONE)

	var m := material as ShaderMaterial
	m.set_shader_parameter("beam_len", _x1 - _x0)
	m.set_shader_parameter("thickness_px", _thick)
	m.set_shader_parameter("point_radius_px", _thick * 0.5 * body_point_radius_mult)
	m.set_shader_parameter("birth_mult", _birth_mult())
	m.set_shader_parameter("activation", _activation * _body_a)

	var top := _center_y - _thick * 0.5
	draw_rect(Rect2(_x0, top, _x1 - _x0, _thick), Color(1.0, 1.0, 1.0, 1.0))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
