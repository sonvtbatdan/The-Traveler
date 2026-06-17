extends Node2D
## Lasgun beam VFX, ported from lasgun_beam.gd into the arena (world-space, gameplay plane → sharp, never
## blurred). Additive blend (CanvasItemMaterial BLEND_MODE_ADD). arena_weapons drives it each frame via
## set_beam(from, to, active, hit); this node draws the layered glow: outer haze → inner glow → energy
## wobble → scrolling pulses → helix ribbons → white core → muzzle flash + impact flare. Procedural/cheap
## (no per-frame particle allocation) to protect FPS.

# ── TUNABLES (ported from lasgun_beam.gd) ────────────────────────────────────────
const BEAM_WIDTH       := 14.0                      # total beam width (px)
const RAINBOW          := true                      # rainbow laser (hue cycles over time + flows down the beam)
const RAINBOW_SPEED    := 0.5                        # hue cycles/sec
const RAINBOW_FLOW     := 0.6                        # extra hue offset across the beam length (rainbow flow)
const GLOW_COLOR       := Color(1.0, 0.55, 0.22)    # warm/hot laser glow (used when RAINBOW = false)
const CORE_COLOR       := Color(1.0, 1.0, 1.0)      # pure white core
const CORE_FRAC        := 0.28
const INNER_FRAC       := 0.46
const HAZE_FRAC        := 0.95
const INNER_ALPHA      := 0.55
const HAZE_ALPHA       := 0.18
const FLICKER          := 0.12
const FLICKER_SPEED    := 28.0
const WOBBLE_AMP       := 4.0
const WOBBLE_FREQ      := 0.05
const WOBBLE_SPEED     := 7.0
const PULSE_COUNT      := 5
const PULSE_SPEED      := 620.0
const PULSE_LEN        := 46.0
const RIBBON_COUNT     := 2
const RIBBON_AMP       := 7.0
const RIBBON_WAVES     := 5.0
const RIBBON_SCROLL    := 6.0
const RIBBON_WIDTH     := 2.5
const RIBBON_SEGS      := 40
const FLARE_GLOW_COLOR := Color(1.0, 0.35, 0.10)
const FLARE_SPARK_COLOR:= Color(1.0, 0.55, 0.15)
const FLARE_GLOW_SIZE  := 16.0
const FLARE_SPARKS     := 10
const FLARE_SPARK_LEN  := 30.0
const FIRE_FLASH_SIZE  := 26.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _active := false
var _hit := false
var _t := 0.0

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m

func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
	_from = from
	_to = to
	_active = active
	_hit = hit
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if _active:
		queue_redraw()   # keep the pulses/wobble/ribbons animating

func _draw() -> void:
	if not _active:
		return
	var a := _from
	var b := _to
	var d := b - a
	var L := d.length()
	if L < 1.0:
		return
	var dir := d / L
	var perp := Vector2(-dir.y, dir.x)
	var w := BEAM_WIDTH
	var base_hue := fposmod(_t * RAINBOW_SPEED, 1.0)
	var g := Color.from_hsv(base_hue, 0.85, 1.0) if RAINBOW else GLOW_COLOR
	var flick := 1.0 - FLICKER * 0.5 + FLICKER * 0.5 * sin(_t * FLICKER_SPEED)

	# Outer haze (3 stacked soft lines).
	draw_line(a, b, Color(g.r, g.g, g.b, HAZE_ALPHA * 0.4 * flick), w * HAZE_FRAC * 1.8)
	draw_line(a, b, Color(g.r, g.g, g.b, HAZE_ALPHA * 0.7 * flick), w * HAZE_FRAC * 1.25)
	draw_line(a, b, Color(g.r, g.g, g.b, HAZE_ALPHA * flick), w * HAZE_FRAC)
	# Inner glow (blended toward white).
	var iw := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5, INNER_ALPHA * flick)
	draw_line(a, b, iw, maxf(2.0, w * INNER_FRAC))
	# Energy wobble polyline (heat-haze ripple).
	var wprev := a
	for s in range(1, 17):
		var alo := L * float(s) / 16.0
		var woff := sin(alo * WOBBLE_FREQ - _t * WOBBLE_SPEED) * WOBBLE_AMP
		var wpt := a + dir * alo + perp * woff
		var wc := Color.from_hsv(fposmod(base_hue + (alo / L) * RAINBOW_FLOW, 1.0), 0.8, 1.0) if RAINBOW else g
		draw_line(wprev, wpt, Color(wc.r, wc.g, wc.b, 0.30 * flick), maxf(2.0, w * 0.16))
		wprev = wpt
	# Scrolling energy pulses (bright dashes racing gun → impact).
	for k in PULSE_COUNT:
		var phase := fmod(_t * PULSE_SPEED + float(k) * (L / float(maxi(1, PULSE_COUNT))), L)
		var pc := a + dir * phase
		var pt := pc - dir * minf(PULSE_LEN, phase)
		draw_line(pt, pc, Color(1.0, 1.0, 1.0, 0.45 * flick), maxf(2.0, w * 0.22))
	# Helix ribbons (sine strands braiding around the beam).
	var rwhite := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5)
	for rb in RIBBON_COUNT:
		var rphase := float(rb) * TAU / float(maxi(1, RIBBON_COUNT))
		var rpts := PackedVector2Array()
		var rcols := PackedColorArray()
		rpts.resize(RIBBON_SEGS + 1)
		rcols.resize(RIBBON_SEGS + 1)
		for s2 in range(RIBBON_SEGS + 1):
			var f := float(s2) / float(RIBBON_SEGS)
			var roff := sin(f * RIBBON_WAVES * TAU - _t * RIBBON_SCROLL + rphase) * RIBBON_AMP
			rpts[s2] = a + dir * (L * f) + perp * roff
			var rc := Color.from_hsv(fposmod(base_hue + f * RAINBOW_FLOW + float(rb) * 0.2, 1.0), 0.55, 1.0) if RAINBOW else rwhite
			rcols[s2] = Color(rc.r, rc.g, rc.b, 0.45 * flick)
		draw_polyline_colors(rpts, rcols, RIBBON_WIDTH)
	# White core.
	draw_line(a, b, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, flick), maxf(1.5, w * CORE_FRAC))
	# Muzzle flash.
	draw_circle(a, FIRE_FLASH_SIZE * 0.5, Color(g.r, g.g, g.b, 0.30 * flick))
	draw_circle(a, FIRE_FLASH_SIZE * 0.22, Color(1.0, 1.0, 1.0, 0.7 * flick))
	# Impact flare at the contact point.
	if _hit:
		draw_circle(b, FLARE_GLOW_SIZE, Color(FLARE_GLOW_COLOR.r, FLARE_GLOW_COLOR.g, FLARE_GLOW_COLOR.b, 0.35 * flick))
		draw_circle(b, FLARE_GLOW_SIZE * 0.4, Color(1.0, 1.0, 1.0, 0.8 * flick))
		for i in FLARE_SPARKS:
			var ang := -dir.angle() + PI + randf_range(-0.85, 0.85)
			var sp := Vector2(cos(ang), sin(ang)) * FLARE_SPARK_LEN * randf_range(0.5, 1.0)
			draw_line(b, b + sp, Color(FLARE_SPARK_COLOR.r, FLARE_SPARK_COLOR.g, FLARE_SPARK_COLOR.b, 0.5 * flick), 2.0)
