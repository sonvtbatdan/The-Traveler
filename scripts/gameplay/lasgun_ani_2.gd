extends Node2D
class_name LasgunAni2
## lasgun_ani_2 — procedural blue energy beam built as a shader-on-a-quad (NEW, shares no code with
## lasgun_ani_1). A unit QuadMesh (MeshInstance2D) is stretched/rotated along the fire vector; the
## lasgun_ani_2.gdshader paints all four layers (blue glow halo → cyan-white body → white hot core →
## comet head + tail fray) procedurally with in-shader fbm turbulence, scrolling striations and flicker.
##
## Driven by arena_weapons each frame via set_beam(from, to, active, hit) — same contract as ani_1 — so
## swapping is a one-line preload change. fire(origin, target) is provided as an alias. World-space:
## from/to are global positions and the parent's transform is assumed identity (matches the arena rig).

const SHADER_PATH := "res://scripts/gameplay/lasgun_ani_2.gdshader"

# ── TUNABLES ─────────────────────────────────────────────────────────────────────
# Geometry
@export var beam_thickness   := 90.0     # baseline beam thickness (px) — 3× wider; quad height = this * HEIGHT_PAD
@export var beam_length      := 2000.0   # max beam length cap (px); actual length comes from from→to
const HEIGHT_PAD             := 3.0      # quad-height multiplier so glow + head fan never clip (spec: ×3)
# Colors
@export var core_color := Color(1.0, 0.972, 1.0)   # #ffffff / #f0f8ff — hot white core
@export var body_color := Color(0.62, 0.82, 1.0)   # #8fc4ff..#cfe6ff — cyan-white body
@export var glow_color := Color(0.31, 0.55, 1.0)   # #3a6cff..#6fa0ff — blue halo
# Layer widths (fraction of half-thickness; 0 = centerline, 1 = padded edge)
@export var core_width := 0.06
@export var body_width := 0.18
@export var glow_width := 0.5
# Head / tail shaping
@export var head_flare_power := 2.0      # how much every layer fans toward the tip
@export var head_softness    := 0.06     # tail fade-in sharpness
@export var tail_fray_amount := 0.6      # frayed parallel streaks behind the origin
# Turbulence / wisps
@export var distort_amount     := 0.16
@export var distort_scale      := 4.0
@export var noise_scroll_speed := 1.4
# Striations (energy flow tail → head)
@export var stria_freq     := 40.0
@export var stria_speed    := 8.0
@export var stria_strength := 0.25
# Flicker (~8–12 Hz brightness pulse)
@export var flicker_speed  := 60.0
@export var flicker_amount := 0.10
# Master
@export var overall_intensity := 1.0
@export var activation_in     := 0.05    # seconds to ramp width/alpha in on fire
@export var activation_out    := 0.08    # seconds to fade out on release
# ── Evaporating sparks (tiny beam-coloured motes ejected perpendicular, fade fast) ──
@export var spark_enabled   := true
@export var spark_color     := Color(0.75, 0.88, 1.0)  # white-blue, like the beam
@export var spark_rate      := 140.0   # motes spawned per second along the whole beam (twice as numerous)
@export var spark_size_min  := 1.0     # px (small, randomized)
@export var spark_size_max  := 3.0
@export var spark_speed_min := 40.0    # perpendicular eject speed (px/s)
@export var spark_speed_max := 120.0
@export var spark_life_min  := 0.15    # how quickly they evaporate (s)
@export var spark_life_max  := 0.40
@export var spark_spread    := 0.28    # rad jitter around the perpendicular
# ── Traveling pulse + axial roll (shader) + muzzle fire (procedural), all white-blue ──
@export var wave_color    := Color(0.80, 0.90, 1.0)  # white-blue mask wave
@export var wave_speed    := 3.0     # pulse travel speed (away from the muzzle → toward the target)
@export var wave_strength := 0.7
@export var wave_noise    := 2.5     # phase jitter (rad) → irregular, non-uniform pulses
# Four FIXED pixel wavelengths (primes → huge LCM → the pulses never converge), length-independent.
@export var wave_len_1    := 137.0
@export var wave_len_2    := 191.0
@export var wave_len_3    := 251.0
@export var wave_len_4    := 313.0
@export var roll_speed    := 1.5     # coil scroll speed (how fast the coils travel along the beam)
@export var roll_amp      := 0.13    # coil weave amplitude (UV.y) — how far the threads wrap off the centerline
@export var roll_freq     := 18.0    # (unused now — coil wavelengths come from wave_len_1..4)
@export var roll_width    := 0.06    # coil thread thickness
@export var roll_strength := 0.5     # coil brightness
@export var coil_noise    := 0.06    # small random wobble on the coils → irregular
@export var coil_amp_1    := 0.85    # per-coil weave amplitude as a fraction of roll_amp (all < 1 unit)
@export var coil_amp_2    := 0.65
@export var coil_amp_3    := 0.45
@export var coil_amp_4    := 0.30
@export var muzzle_enabled := true
@export var muzzle_color   := Color(0.45, 0.62, 1.0)  # deeper blue muzzle fire
@export var muzzle_len     := 65.4   # radial reach of the fan (px) — twice as big
@export var muzzle_tongues := 2      # flame prongs
@export var muzzle_spread  := 1.2    # full fan angle of the prongs (rad)
# Stage 1 — concave notches + asymmetry (frozen per flash)
@export var muzzle_notch_depth := 0.45  # how far the valleys between tongues pull back toward the base (0=none, 1=to base)
@export var muzzle_sharpness   := 2.0   # higher = needlier tongues, deeper notches
@export var muzzle_asym        := 0.35  # per-tongue length/angle asymmetry (0=symmetric fan)
@export var muzzle_curve       := 0.30  # sideways hook applied along each tongue (0=straight)
@export var muzzle_seed_jitter := 0.30  # frozen-per-flash radius jitter (replaces per-frame strobe)
# Stage 2 — punch-out → collapse birth envelope
@export var muzzle_attack    := 0.04  # s to punch to peak on activation (snappier)
@export var muzzle_peak_mult := 1.9   # size multiplier at the punch peak vs steady-state (harder pop)
@export var muzzle_settle    := 0.14  # s to ease from peak down to steady-state (quicker settle)
@export var muzzle_frame_time := 0.05 # seconds per procedural "frame" — the shape re-rolls each tick (flipbook cycle)
@export var muzzle_passes := 2        # (unused since the blob render — superseded by muzzle_soft_gain)
# Stage 1 — soft additive blob render (feathered edges like the beam)
@export var muzzle_blobs_per_tongue := 14    # soft circles marched along each tongue centerline (more = smoother)
@export var muzzle_blob_r_base      := 11.0  # blob radius near the gun (px, soft & fat)
@export var muzzle_blob_r_tip       := 1.5   # blob radius at the tongue tip (→ soft point)
@export var muzzle_base_bloom       := 18.0  # radius of the soft root glow at the muzzle base
@export var muzzle_soft_gain        := 1.0   # master alpha multiplier for the whole muzzle
@export var muzzle_blob_jitter      := 0.25  # frozen-per-frame radius jitter on each blob (organic edge, no strobe)
# Shader-driven muzzle (the SAME beam texture reshaped — muzzle_mode = 1). The blob/polygon exports above are now unused.
@export var muzzle_fan_width := 1.5   # muzzle quad width = beam_thickness * this (the fan span — twice as big)
@export var muzzle_intensity := 2.8   # muzzle brightness multiplier (so it pops above the beam, not fused)
@export var mz_tongues       := 6.0   # number of flame tongues across the fan (one more prong)
@export var mz_spread        := 0.9   # fan HALF-angle (rad) — tongues radiate ±this from the gun (~103° full)
@export var mz_sharpness     := 1     # (retired — replaced by mz_body_round)
@export var mz_notch         := 0.45  # valley depth between tongues (0..1 — clearer gaps)
@export var mz_len_jitter    := 0.35  # per-tongue length variation (more organic asymmetry)
@export var mz_tip_softness  := 0.50  # (retired — tip taper now driven by mz_tip_frac)
@export var mz_body_round    := 2.0   # CENTER fatness: >1 fat/convex leaf, =1 diamond, <1 needle
@export var mz_tip_frac      := 0.2   # fraction of tongue length used for the tip taper (small = blade w/ sudden point)
@export var mz_count_min     := 2.0   # per-frame tongue count re-rolls in [mz_count_min, mz_tongues]
@export var mz_round_var     := 1.8   # per-tongue fatness jitter around mz_body_round (needle↔leaf spread)
@export var mz_asym          := 0.4   # per-tongue sideways lean → asymmetric spikes (0 = symmetric)

var _quad: MeshInstance2D = null
var _mat: ShaderMaterial = null
var _muzzle_quad: MeshInstance2D = null   # second quad, same shader, muzzle_mode = 1 (flame tongues)
var _muzzle_mat: ShaderMaterial = null
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _active := false
var _hit := false
var _activation := 0.0   # 0..1 ramped envelope pushed to the shader
var _spark_node: Node2D = null   # additive child that draws the evaporating motes
var _sparks: Array = []          # {pos, vel, life, max_life, size}
var _spark_acc := 0.0
var _spark_dirty := false
var _t := 0.0
var _was_active := false       # activation edge (false→true) for the muzzle birth punch
var _muzzle_seed := 0          # frozen per-flash random seed (geometry jitter held for one flash)
var _muzzle_birth_t := 0.0     # seconds since this flash began (drives the punch-out → settle)

func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE   # unit quad; we stretch via the node's scale (UVs stay 0..1)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_quad = MeshInstance2D.new()
	_quad.mesh = mesh
	_quad.material = _mat
	_quad.visible = false
	add_child(_quad)
	_apply_static_uniforms(_mat)
	# Muzzle quad — the SAME shader with muzzle_mode = 1 (the beam texture reshaped into flame tongues).
	_muzzle_mat = ShaderMaterial.new()
	_muzzle_mat.shader = load(SHADER_PATH)
	_apply_static_uniforms(_muzzle_mat)
	_muzzle_mat.set_shader_parameter("muzzle_mode", 1)
	_muzzle_quad = MeshInstance2D.new()
	_muzzle_quad.mesh = mesh   # reuse the unit QuadMesh
	_muzzle_quad.material = _muzzle_mat
	_muzzle_quad.visible = false
	add_child(_muzzle_quad)    # drawn over the beam
	_push_muzzle_uniforms()
	if spark_enabled:
		_spark_node = Node2D.new()
		var sm := CanvasItemMaterial.new()
		sm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_spark_node.material = sm
		add_child(_spark_node)   # drawn over the quad
		_spark_node.draw.connect(_draw_overlays)   # evaporating sparks + muzzle fire

## Driver entry point (matches lasgun_ani_1): aim the beam from→to, toggle on/off, flag a hit.
func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
	if active and not _was_active:   # fire-start edge → new frozen seed + restart the birth punch
		_muzzle_seed = randi()
		_muzzle_birth_t = 0.0
	_was_active = active
	_active = active
	_hit = hit
	if active:
		var d := to - from
		var L := d.length()
		if L >= 1.0:
			_from = from
			_to = from + d.normalized() * minf(L, beam_length)
			_place_quad()

## Alias for the spec's fire(origin, target) — continuous: call each frame to keep aiming.
func fire(origin: Vector2, target: Vector2) -> void:
	set_beam(origin, target, true, false)

## Stop firing; the beam fades out over activation_out seconds.
func release() -> void:
	_active = false

func _place_quad() -> void:
	var d := _to - _from
	var L := d.length()
	if L < 1.0:
		return
	_quad.position = (_from + _to) * 0.5
	_quad.rotation = d.angle()
	_quad.scale = Vector2(L, beam_thickness * HEIGHT_PAD)
	if _mat != null:
		_mat.set_shader_parameter("beam_len", L)   # px → pixel-fixed wave wavelengths

func _process(delta: float) -> void:
	_t += delta
	_muzzle_birth_t += delta
	# Ramp the activation envelope in on fire, out on release.
	var target := 1.0 if _active else 0.0
	var rate := (1.0 / maxf(0.001, activation_in)) if _active else (1.0 / maxf(0.001, activation_out))
	_activation = move_toward(_activation, target, rate * delta)
	_tick_sparks(delta)
	_update_muzzle_quad()
	if _quad == null:
		return
	if _activation <= 0.0001:
		_quad.visible = false
		return
	_quad.visible = true
	_mat.set_shader_parameter("activation", _activation)

## Tiny beam-coloured motes that "evaporate": spawned at random points along the live beam, ejected
## perpendicular (with a little jitter), random small size, drifting out then fading away shortly.
func _tick_sparks(delta: float) -> void:
	if _spark_node == null:
		return
	if _active and _activation > 0.4:
		var d := _to - _from
		var L := d.length()
		if L > 1.0:
			var dir := d / L
			var perp := Vector2(-dir.y, dir.x)
			_spark_acc += spark_rate * delta
			while _spark_acc >= 1.0:
				_spark_acc -= 1.0
				var side := 1.0 if randf() < 0.5 else -1.0
				var ejdir := perp.rotated(randf_range(-spark_spread, spark_spread)) * side
				var origin := _from + dir * (randf() * L) + perp * randf_range(-beam_thickness * 0.3, beam_thickness * 0.3)
				_sparks.append({
					"pos": origin, "vel": ejdir * randf_range(spark_speed_min, spark_speed_max),
					"life": 0.0, "max_life": randf_range(spark_life_min, spark_life_max),
					"size": randf_range(spark_size_min, spark_size_max),
				})
	var i := _sparks.size() - 1
	while i >= 0:
		var p: Dictionary = _sparks[i]
		p["life"] = float(p["life"]) + delta
		if float(p["life"]) >= float(p["max_life"]):
			_sparks.remove_at(i)
		else:
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		i -= 1
	# Redraw while firing (muzzle animates) or while there are motes, plus one frame after they clear.
	if _active or not _sparks.is_empty() or _spark_dirty:
		_spark_node.queue_redraw()
	_spark_dirty = not _sparks.is_empty()

func _draw_overlays() -> void:
	_draw_sparks()   # muzzle is now the shader quad (_muzzle_quad), not an immediate-mode draw

func _draw_sparks() -> void:
	var c := spark_color
	for p: Dictionary in _sparks:
		var lf := 1.0 - float(p["life"]) / float(p["max_life"])
		var sz := float(p["size"]) * (0.6 + 0.4 * lf)
		_spark_node.draw_circle(p["pos"], sz, Color(c.r, c.g, c.b, lf))

## Deterministic [0,1) hash — frozen geometry jitter for one flash (seeded by _muzzle_seed).
func _h(s: int, k: int) -> float:
	var v := sin(float(s) * 12.9898 + float(k) * 78.233) * 43758.5453
	return v - floor(v)

## Position/scale the muzzle quad at the gun each frame, oriented along the fire direction, with the
## birth punch as a scale multiplier. The shader (muzzle_mode = 1) draws the flame from the beam texture.
func _update_muzzle_quad() -> void:
	if _muzzle_quad == null:
		return
	var d := _to - _from
	if not muzzle_enabled or _activation <= 0.01 or d.length() < 1.0:
		_muzzle_quad.visible = false
		return
	var dir := d.normalized()
	var mb := _muzzle_birth_mult()
	var mlen := muzzle_len * mb
	var mwid := beam_thickness * muzzle_fan_width * mb
	_muzzle_quad.visible = true
	_muzzle_quad.position = _from + dir * (mlen * 0.5)   # UV.x = 0 sits at the gun (_from)
	_muzzle_quad.rotation = dir.angle()
	_muzzle_quad.scale = Vector2(mlen, mwid)
	_muzzle_mat.set_shader_parameter("activation", _activation)
	_muzzle_mat.set_shader_parameter("mz_aspect", mwid / maxf(1.0, mlen))   # un-squash the polar angles
	_push_muzzle_uniforms()

## Birth punch-out → collapse multiplier (punch over muzzle_attack, ease back over muzzle_settle).
func _muzzle_birth_mult() -> float:
	if _muzzle_birth_t < muzzle_attack:
		return lerpf(1.0, muzzle_peak_mult, _muzzle_birth_t / maxf(0.0001, muzzle_attack))
	return lerpf(muzzle_peak_mult, 1.0, clampf((_muzzle_birth_t - muzzle_attack) / maxf(0.0001, muzzle_settle), 0.0, 1.0))

## Push the live-tunable mz_* flame-shape uniforms to the muzzle material.
func _push_muzzle_uniforms() -> void:
	if _muzzle_mat == null:
		return
	_muzzle_mat.set_shader_parameter("mz_tongues", mz_tongues)
	_muzzle_mat.set_shader_parameter("mz_spread", mz_spread)
	_muzzle_mat.set_shader_parameter("mz_sharpness", mz_sharpness)
	_muzzle_mat.set_shader_parameter("mz_notch", mz_notch)
	_muzzle_mat.set_shader_parameter("mz_len_jitter", mz_len_jitter)
	_muzzle_mat.set_shader_parameter("mz_tip_softness", mz_tip_softness)
	_muzzle_mat.set_shader_parameter("mz_body_round", mz_body_round)
	_muzzle_mat.set_shader_parameter("mz_tip_frac", mz_tip_frac)
	_muzzle_mat.set_shader_parameter("mz_count_min", mz_count_min)
	_muzzle_mat.set_shader_parameter("mz_round_var", mz_round_var)
	_muzzle_mat.set_shader_parameter("mz_asym", mz_asym)
	_muzzle_mat.set_shader_parameter("mz_frame", floor(_t / maxf(0.001, muzzle_frame_time)))   # flipbook tick — new shape each muzzle_frame_time
	_muzzle_mat.set_shader_parameter("overall_intensity", muzzle_intensity)   # brighter than the beam so it reads

func _apply_static_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("head_flare_power", head_flare_power)
	mat.set_shader_parameter("head_softness", head_softness)
	mat.set_shader_parameter("tail_fray_amount", tail_fray_amount)
	mat.set_shader_parameter("core_width", core_width)
	mat.set_shader_parameter("body_width", body_width)
	mat.set_shader_parameter("glow_width", glow_width)
	mat.set_shader_parameter("core_color", core_color)
	mat.set_shader_parameter("body_color", body_color)
	mat.set_shader_parameter("glow_color", glow_color)
	mat.set_shader_parameter("distort_amount", distort_amount)
	mat.set_shader_parameter("distort_scale", distort_scale)
	mat.set_shader_parameter("noise_scroll_speed", noise_scroll_speed)
	mat.set_shader_parameter("stria_freq", stria_freq)
	mat.set_shader_parameter("stria_speed", stria_speed)
	mat.set_shader_parameter("stria_strength", stria_strength)
	mat.set_shader_parameter("flicker_speed", flicker_speed)
	mat.set_shader_parameter("flicker_amount", flicker_amount)
	mat.set_shader_parameter("overall_intensity", overall_intensity)
	mat.set_shader_parameter("activation", _activation)
	mat.set_shader_parameter("wave_color", wave_color)
	mat.set_shader_parameter("wave_speed", wave_speed)
	mat.set_shader_parameter("wave_strength", wave_strength)
	mat.set_shader_parameter("wave_len_1", wave_len_1)
	mat.set_shader_parameter("wave_len_2", wave_len_2)
	mat.set_shader_parameter("wave_len_3", wave_len_3)
	mat.set_shader_parameter("wave_len_4", wave_len_4)
	mat.set_shader_parameter("roll_speed", roll_speed)
	mat.set_shader_parameter("roll_amp", roll_amp)
	mat.set_shader_parameter("roll_freq", roll_freq)
	mat.set_shader_parameter("roll_width", roll_width)
	mat.set_shader_parameter("roll_strength", roll_strength)
	mat.set_shader_parameter("wave_noise", wave_noise)
	mat.set_shader_parameter("coil_noise", coil_noise)
	mat.set_shader_parameter("coil_amp_1", coil_amp_1)
	mat.set_shader_parameter("coil_amp_2", coil_amp_2)
	mat.set_shader_parameter("coil_amp_3", coil_amp_3)
	mat.set_shader_parameter("coil_amp_4", coil_amp_4)
