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
@export var muzzle_len     := 80.0   # central flame-spike length (px)
@export var muzzle_tongues := 5      # flame prongs
@export var muzzle_spread  := 1.2    # full fan angle of the prongs (rad)

var _quad: MeshInstance2D = null
var _mat: ShaderMaterial = null
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
	_apply_static_uniforms()
	if spark_enabled:
		_spark_node = Node2D.new()
		var sm := CanvasItemMaterial.new()
		sm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_spark_node.material = sm
		add_child(_spark_node)   # drawn over the quad
		_spark_node.draw.connect(_draw_overlays)   # evaporating sparks + muzzle fire

## Driver entry point (matches lasgun_ani_1): aim the beam from→to, toggle on/off, flag a hit.
func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
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
	# Ramp the activation envelope in on fire, out on release.
	var target := 1.0 if _active else 0.0
	var rate := (1.0 / maxf(0.001, activation_in)) if _active else (1.0 / maxf(0.001, activation_out))
	_activation = move_toward(_activation, target, rate * delta)
	_tick_sparks(delta)
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
	_draw_sparks()
	if muzzle_enabled:
		_draw_muzzle()

func _draw_sparks() -> void:
	var c := spark_color
	for p: Dictionary in _sparks:
		var lf := 1.0 - float(p["life"]) / float(p["max_life"])
		var sz := float(p["size"]) * (0.6 + 0.4 * lf)
		_spark_node.draw_circle(p["pos"], sz, Color(c.r, c.g, c.b, lf))

## White-blue muzzle fire at the shooting point: a fan of flickering tapered flame tongues (central
## spike longest), re-jittered each frame, plus a hot base flash. Shape modelled on the reference sheet.
func _draw_muzzle() -> void:
	if not _active or _activation < 0.3:
		return
	var d := _to - _from
	if d.length() < 1.0:
		return
	var dir := -d.normalized()   # muzzle fire flares back off the gun (opposite the beam)
	var base := _from
	var hw0 := beam_thickness * 0.5
	var flick := 0.75 + 0.25 * sin(_t * 40.0)
	var c := muzzle_color
	for k in range(muzzle_tongues):
		var f := (float(k) / float(maxi(1, muzzle_tongues - 1))) - 0.5   # -0.5 .. 0.5
		var td := dir.rotated(f * muzzle_spread)
		var tp := Vector2(-td.y, td.x)
		var ln := muzzle_len * (1.0 - absf(f) * 0.55) * randf_range(0.55, 1.0) * flick * _activation
		var hw := hw0 * (1.0 - absf(f) * 0.4) * randf_range(0.7, 1.0)
		var tip := base + td * ln
		_spark_node.draw_polygon(
			PackedVector2Array([base + tp * hw, base - tp * hw, tip]),
			PackedColorArray([Color(c.r, c.g, c.b, 0.8), Color(c.r, c.g, c.b, 0.8), Color(c.r, c.g, c.b, 0.0)]))
	# Blue base glow (no white circle).
	_spark_node.draw_circle(base, hw0 * 1.3 * flick, Color(c.r, c.g, c.b, 0.35 * _activation))

func _apply_static_uniforms() -> void:
	_mat.set_shader_parameter("head_flare_power", head_flare_power)
	_mat.set_shader_parameter("head_softness", head_softness)
	_mat.set_shader_parameter("tail_fray_amount", tail_fray_amount)
	_mat.set_shader_parameter("core_width", core_width)
	_mat.set_shader_parameter("body_width", body_width)
	_mat.set_shader_parameter("glow_width", glow_width)
	_mat.set_shader_parameter("core_color", core_color)
	_mat.set_shader_parameter("body_color", body_color)
	_mat.set_shader_parameter("glow_color", glow_color)
	_mat.set_shader_parameter("distort_amount", distort_amount)
	_mat.set_shader_parameter("distort_scale", distort_scale)
	_mat.set_shader_parameter("noise_scroll_speed", noise_scroll_speed)
	_mat.set_shader_parameter("stria_freq", stria_freq)
	_mat.set_shader_parameter("stria_speed", stria_speed)
	_mat.set_shader_parameter("stria_strength", stria_strength)
	_mat.set_shader_parameter("flicker_speed", flicker_speed)
	_mat.set_shader_parameter("flicker_amount", flicker_amount)
	_mat.set_shader_parameter("overall_intensity", overall_intensity)
	_mat.set_shader_parameter("activation", _activation)
	_mat.set_shader_parameter("wave_color", wave_color)
	_mat.set_shader_parameter("wave_speed", wave_speed)
	_mat.set_shader_parameter("wave_strength", wave_strength)
	_mat.set_shader_parameter("wave_len_1", wave_len_1)
	_mat.set_shader_parameter("wave_len_2", wave_len_2)
	_mat.set_shader_parameter("wave_len_3", wave_len_3)
	_mat.set_shader_parameter("wave_len_4", wave_len_4)
	_mat.set_shader_parameter("roll_speed", roll_speed)
	_mat.set_shader_parameter("roll_amp", roll_amp)
	_mat.set_shader_parameter("roll_freq", roll_freq)
	_mat.set_shader_parameter("roll_width", roll_width)
	_mat.set_shader_parameter("roll_strength", roll_strength)
	_mat.set_shader_parameter("wave_noise", wave_noise)
	_mat.set_shader_parameter("coil_noise", coil_noise)
	_mat.set_shader_parameter("coil_amp_1", coil_amp_1)
	_mat.set_shader_parameter("coil_amp_2", coil_amp_2)
	_mat.set_shader_parameter("coil_amp_3", coil_amp_3)
	_mat.set_shader_parameter("coil_amp_4", coil_amp_4)
