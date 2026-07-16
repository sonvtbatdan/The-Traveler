extends Node2D
## EnergyVortex — a soft GLOWING spiral-vortex VFX (luminous swirling arms + a bloomed core + twinkling
## sparkles), drawn with layered translucent polylines (no texture/particles) for a soft additive glow rather
## than hard lines. Used both as a live preview in Creep Edit and anchored on arena enemies.
##
## NOTE: intentionally NO class_name — instantiate via preload + .new() and type the var as Node2D, then call
## setup() dynamically. Typing by a fresh class_name can break a headless first-boot (same lesson as ZSlash).

const TWIST      := 3.1    # radians each spiral arm wraps over its length (the "swirl" tightness)
const ARM_SEGS   := 20     # polyline resolution per arm (perf: was 32)
const PULSE_FREQ := 3.0    # radius breathing speed
const PULSE_AMP  := 0.08   # radius breathing amplitude (±)
const SPARKLES   := 8      # twinkling star points (perf: was 12)
const REF_RADIUS := 40.0   # radius at which line widths + sparkle dots render at their native pixel size
const REDRAW_HZ  := 30.0   # perf: throttle the procedural redraw — a background swirl needs no 60fps repaint
# Per glow pass: [width_px, alpha_multiplier] — soft mid → narrow+bright core (perf: dropped the widest underlay).
const GLOW_PASSES := [Vector2(3.6, 0.18), Vector2(1.6, 0.50)]

var radius:    float = 40.0
var spin:      float = 2.2                                  # swirl rotation speed (rad/s; negative = reverse)
var arms:      int   = 3
var width_mult: float = 1.0                                 # per-instance line-thickness multiplier
var sparkle_mult: float = 1.0                               # per-instance sparkle (particle) opacity multiplier
var col_core:  Color = Color(0.75, 0.92, 1.0, 1.0)
var col_mid:   Color = Color(0.45, 0.40, 1.0, 0.9)
var col_outer: Color = Color(0.55, 0.20, 0.95, 0.0)
var draw_halo: bool = true   # the breathing (scale-pulsing) bloom-circle underlay; off for Black Hole,
							 # which draws its own infalling accretion rings instead
var _t: float = 0.0
var _redraw_acc: float = 0.0

func _ready() -> void:
	z_index = 2
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive → reads as glowing energy
	material = cm

## Configure from a style dict (the same dict the Creep Edit Vortex panel edits + saves).
func setup(style: Dictionary) -> void:
	radius    = float(style.get("radius", radius))
	spin      = float(style.get("spin",   spin))
	arms      = maxi(1, int(style.get("arms", arms)))
	width_mult = float(style.get("width_mult", width_mult))
	sparkle_mult = float(style.get("sparkle_mult", sparkle_mult))
	col_core  = style.get("col_core",  col_core)
	col_mid   = style.get("col_mid",   col_mid)
	col_outer = style.get("col_outer", col_outer)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_redraw_acc += delta
	if _redraw_acc >= 1.0 / REDRAW_HZ:
		_redraw_acc = 0.0
		queue_redraw()

## Colour along an arm: core → mid → outer (alpha envelope applied by the caller).
func _arm_col(t: float) -> Color:
	if t < 0.5:
		return col_core.lerp(col_mid, t * 2.0)
	return col_mid.lerp(col_outer, (t - 0.5) * 2.0)

func _draw() -> void:
	var rot := _t * spin
	var rad := radius * (1.0 + sin(_t * PULSE_FREQ) * PULSE_AMP)
	# Shrink line thickness + sparkle dots together with the configured radius so a small vortex
	# reads as a scaled-down copy (1.0 at REF_RADIUS → no change for default-radius vortexes).
	var size_scale := radius / REF_RADIUS
	# Soft bloom halo around the (deliberately dim) core → reads as a glowing nebula, dark at the very centre.
	# Alpha follows a sin bump (fades at the innermost AND outermost ring) so the core fades like the arms.
	if draw_halo:
		for i in 5:
			var f := float(i) / 5.0
			var c := col_mid
			c.a = col_mid.a * 0.10 * sin(clampf(0.15 + f * 0.85, 0.0, 1.0) * PI)
			draw_circle(Vector2.ZERO, rad * (0.18 + f * 0.55), c)
	# Spiral arms — mirrored handedness (−TWIST) while the rotation (rot) is unchanged.
	for a in arms:
		var base := TAU * float(a) / float(arms) + rot
		var pts := PackedVector2Array()
		for s in ARM_SEGS + 1:
			var t := float(s) / float(ARM_SEGS)
			var ang := base - t * TWIST
			pts.append(Vector2(cos(ang), sin(ang)) * (t * rad))
		for pass_def: Vector2 in GLOW_PASSES:
			var cols := PackedColorArray()
			for s in ARM_SEGS + 1:
				var t := float(s) / float(ARM_SEGS)
				var col := _arm_col(t)
				col.a = col.a * pass_def.y * sin(clampf(t, 0.0, 1.0) * PI)   # fade at the centre AND the tip
				cols.append(col)
			draw_polyline_colors(pts, cols, pass_def.x * width_mult * size_scale, true)
	_draw_sparkles(rad, rot, size_scale)

## Twinkling star points scattered through the swirl (deterministic per index → no per-frame jitter).
## Each is a soft 2-layer glow dot whose alpha also fades toward the centre/rim (sin envelope) like the arms.
func _draw_sparkles(rad: float, rot: float, size_scale: float = 1.0) -> void:
	for k in SPARKLES:
		var seed := float(k) * 12.9898
		var ang := fmod(seed * 7.0, TAU) + rot * 0.35
		var frac := 0.30 + 0.62 * fmod(seed * 0.618034, 1.0)
		var rr := rad * frac
		var tw := 0.45 + 0.55 * sin(_t * 4.0 + seed)
		var radial := sin(clampf(frac, 0.0, 1.0) * PI)   # fade near the centre AND the rim, like the arms
		var a := col_core.a * 0.5 * tw * sparkle_mult * radial
		if a <= 0.01:
			continue
		var p := Vector2(cos(ang), sin(ang)) * rr
		var core := (0.6 + 1.3 * tw) * size_scale
		var c := col_core
		c.a = a * 0.35                       # soft outer glow
		draw_circle(p, core * 2.0, c)
		c.a = a                              # bright inner point
		draw_circle(p, core, c)
