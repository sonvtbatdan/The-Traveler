extends Node2D
## Boss charge telegraph — translucent concentric energy rings COLLAPSING inward into the boss centre, plus
## an inward-pulling ember haze. Says "something is charging up in here". A child of the boss;
## `begin(size_px)` raises it, freeing the node ends it.
##
## Palette is per-caller (2026-09-02): The Skull's Move 2 keeps the original RED defaults; Nautilus's Move 5
## passes a BLUE one. Pass `{"rim": Color, "core": Color, "ember": Color}` — any key you leave out keeps the
## red default, so existing callers are untouched.
##
## The rings are drawn as annuli (draw_arc with a width), never stacked discs — overlapping translucent
## discs accumulate alpha toward the middle and turn a gradient into a dark blob (same note as
## metalfly_swarm_ring.gd, which this is the inward mirror of).
##
## NOTE: no class_name — preload + .new(), typed Node2D, call begin() dynamically.

const RING_COUNT   := 5       # rings sharing one phase clock, evenly offset → a continuous inward flow
const RING_PERIOD  := 0.55    # seconds for one ring to travel rim -> centre
const RING_W       := 5.0
const ARC_POINTS   := 64
const COL_RIM      := Color(1.0, 0.16, 0.10, 0.42)
const COL_CORE     := Color(1.0, 0.55, 0.30, 0.30)

var _r_max: float = 120.0
var _t: float = 0.0
var _particles: CPUParticles2D = null
var _col_rim: Color = COL_RIM
var _col_core: Color = COL_CORE

func begin(size_px: float, palette: Dictionary = {}) -> void:
	_r_max = maxf(60.0, size_px * 0.95)
	_col_rim = palette.get("rim", COL_RIM)
	_col_core = palette.get("core", COL_CORE)
	var ember: Color = palette.get("ember", Color(1.0, 0.35, 0.15))
	z_index = 4
	# Inward-sucked ember haze — emitted on a ring at _r_max, radial_accel negative so it falls to the centre.
	_particles = CPUParticles2D.new()
	_particles.emitting = true
	_particles.amount = 90
	_particles.lifetime = RING_PERIOD * 1.6
	_particles.local_coords = true
	# CPUParticles2D has no RING shape (that's 3D) — SPHERE_SURFACE = points on a circle of this radius.
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	_particles.emission_sphere_radius = _r_max
	_particles.direction = Vector2.ZERO
	_particles.spread = 0.0
	_particles.gravity = Vector2.ZERO
	_particles.radial_accel_min = -_r_max * 3.4
	_particles.radial_accel_max = -_r_max * 2.2
	_particles.tangential_accel_min = -_r_max * 0.8
	_particles.tangential_accel_max = _r_max * 0.8
	_particles.scale_amount_min = size_px * 0.02
	_particles.scale_amount_max = size_px * 0.055
	var g := Gradient.new()
	# born faint → hot at mid-life → fades out as it reaches the middle, all keyed off the caller's ember hue.
	var hot := ember.lightened(0.45); hot.a = 0.0
	var mid := ember;                 mid.a = 0.9
	var cool := ember.darkened(0.45); cool.a = 0.0
	g.colors = PackedColorArray([hot, mid, cool])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_particles.color_ramp = g
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_particles.material = mat
	# A textureless CPUParticles2D draws hard SQUARES — give it a soft round dot so the embers read as
	# circular (user: "các particle hình tròn chứ ko phải vuông như hiện tại").
	_particles.texture = _round_dot()
	add_child(_particles)
	set_process(true)

## Soft radial-falloff white dot — same recipe as arena_enemy._make_plume's particle texture.
static func _round_dot() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(8, 8)
	for iy in 16:
		for ix in 16:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	for i in RING_COUNT:
		# phase 1 = just born at the rim, 0 = arrived at the centre
		var phase := fmod(_t / RING_PERIOD + float(i) / float(RING_COUNT), 1.0)
		var r := _r_max * phase
		if r < 3.0:
			continue
		# fade in as it appears at the rim, fade out as it reaches the middle
		var a := clampf(phase * 3.0, 0.0, 1.0) * clampf((1.0 - phase) * 2.2 + 0.15, 0.0, 1.0)
		var col := _col_rim.lerp(_col_core, 1.0 - phase)
		col.a *= a
		draw_arc(Vector2.ZERO, r, 0.0, TAU, ARC_POINTS, col, RING_W, true)
		# a fainter glow ring just outside it
		var gcol := col
		gcol.a *= 0.35
		draw_arc(Vector2.ZERO, r + RING_W * 1.6, 0.0, TAU, ARC_POINTS, gcol, RING_W * 2.4, true)
