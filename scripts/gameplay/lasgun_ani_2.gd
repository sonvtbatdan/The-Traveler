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
@export var beam_thickness   := 30.0     # baseline beam thickness (px); quad height = this * HEIGHT_PAD
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

var _quad: MeshInstance2D = null
var _mat: ShaderMaterial = null
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _active := false
var _hit := false
var _activation := 0.0   # 0..1 ramped envelope pushed to the shader

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

func _process(delta: float) -> void:
	# Ramp the activation envelope in on fire, out on release.
	var target := 1.0 if _active else 0.0
	var rate := (1.0 / maxf(0.001, activation_in)) if _active else (1.0 / maxf(0.001, activation_out))
	_activation = move_toward(_activation, target, rate * delta)
	if _quad == null:
		return
	if _activation <= 0.0001:
		_quad.visible = false
		return
	_quad.visible = true
	_mat.set_shader_parameter("activation", _activation)

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
