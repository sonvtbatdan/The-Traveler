extends Node2D
## lasgun_ani_1 — the ORIGINAL lasgun beam VFX (immediate-mode draw_*), saved verbatim from the former
## arena_lasgun_beam.gd. Currently DISABLED: nothing instantiates this. Driven (when re-enabled) by
## arena_weapons each frame via set_beam(from, to, active, hit); draws the layered glow: outer haze →
## inner glow → energy wobble → scrolling pulses → helix ribbons → white core → muzzle flash + impact
## flare. Procedural/cheap (no per-frame particle allocation) to protect FPS.
## To re-enable: point arena_weapons.gd's BeamScript preload back at this file.

# ── TUNABLES (ported from lasgun_beam.gd) ────────────────────────────────────────
const BEAM_WIDTH       := 14.0                      # total beam width (px)
# Cast-light glow corridor (wide soft additive halo that bleeds the beam colour outward → brightens the bg).
const GLOW_CORRIDOR_WIDTH := 54.0                   # px of falloff each side beyond the beam edge (wider halo)
const GLOW_OPACITY        := 0.22                   # peak per-layer alpha (additive → brighter cast light)
const GLOW_SATURATION     := 0.6                    # halo saturation (softer/lighter than the 0.85 core)
const GLOW_LAYERS         := 8                      # gradient smoothness (more = smoother, more draw calls)
const CORRIDOR_END_FADE   := 0.20                   # fraction of beam length the corridor feathers to α0 at each end
const RAINBOW          := true                      # rainbow laser (hue cycles over time + flows down the beam)
const RAINBOW_SPEED    := 0.5                        # hue cycles/sec
const RAINBOW_FLOW     := 0.6                        # extra hue offset across the beam length (rainbow flow)
# ── Muzzle cone flare (Part 1) ──
const MUZZLE_FLARE_LEN       := 100.0  # px the cone flare spans from the source before reaching beam width (gradual)
const MUZZLE_FLARE_WIDTH     := 22.0   # full width of the cone at its wide (far) end — matches the beam body (no pinch)
const MUZZLE_FLARE_INTENSITY := 0.55   # cone brightness (additive)
const MUZZLE_FLARE_LAYERS    := 3      # nested cones (wide+faint → narrow+bright)
const MUZZLE_FLARE_CURVE     := 1.6    # taper curve (higher = stays narrow near the source then flares open fast)
# ── Tapered writhing body (Parts 1+2c) ──
const CORE_MUZZLE_W := 22.0            # body width at the muzzle
const CORE_TIP_W    := 8.0             # body width at the tip (≤ muzzle → narrows toward the tip)
const BODY_ALPHA    := 0.22            # filled-body additive alpha
const SEGMENTS      := 24              # segments along the beam (perf knob; lower = cheaper)
const EDGE_TURB_AMP   := 5.0           # writhing edge perpendicular wobble (px)
const EDGE_TURB_FREQ  := 0.045         # writhe ripples per px
const EDGE_TURB_SPEED := 4.0           # writhe churn speed
const EDGE_FLARE_COUNT := 5            # little tendrils spitting off the edges
const EDGE_FLARE_LEN   := 18.0
# ── Living energy motion (Part 2a/b) ──
const PULSE_AMOUNT       := 0.35       # breathing width/brightness amount
const PULSE_FREQ         := 0.018      # breathing waves per px
const PULSE_TRAVEL_SPEED := 5.0        # breathing wave travel speed
const FLOW_SPEED    := 9.0             # energy bands scroll muzzle→tip at this speed (the "channeling" cue)
const FLOW_FREQ     := 0.020           # band frequency along the beam
const FLOW_CONTRAST := 1.0             # band brightness contrast
const FLOW_BASE     := 0.35            # min brightness between bands
# ── Frayed dissipating tip (Part 2d) ──
const TIP_FRAY_COUNT  := 9
const TIP_FRAY_LEN    := 42.0
const TIP_FRAY_SPREAD := 0.7           # fan half-angle (rad)
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

## Cheap 1D turbulence (sum of sines, ~[-1,1]) — drives flow + writhing edges without FastNoiseLite.
func _turb(x: float) -> float:
	return 0.6 * sin(x) + 0.3 * sin(x * 2.17 + 1.3) + 0.22 * sin(x * 3.71 + 2.6)

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

	# Cast-light glow corridor (wide, soft, additive) — drawn FIRST, under the crisp core.
	# Feathered on every side: perpendicular → α0 at the outer extent, longitudinal → α0 at both
	# ends (point at the muzzle), so no rectangular draw extent / box seam ever shows.
	var gc := Color.from_hsv(base_hue, GLOW_SATURATION, 1.0) if RAINBOW else GLOW_COLOR
	var CSEG := 20
	var c_half := w * 0.5 + GLOW_CORRIDOR_WIDTH
	for c_side: float in [1.0, -1.0]:
		for cs in range(CSEG):
			var cf0 := float(cs) / float(CSEG)
			var cf1 := float(cs + 1) / float(CSEG)
			var cwin0 := smoothstep(0.0, CORRIDOR_END_FADE, cf0) * (1.0 - smoothstep(1.0 - CORRIDOR_END_FADE, 1.0, cf0))
			var cwin1 := smoothstep(0.0, CORRIDOR_END_FADE, cf1) * (1.0 - smoothstep(1.0 - CORRIDOR_END_FADE, 1.0, cf1))
			var cbp0 := a + dir * (L * cf0)
			var cbp1 := a + dir * (L * cf1)
			var cpk0 := GLOW_OPACITY * cwin0 * flick
			var cpk1 := GLOW_OPACITY * cwin1 * flick
			var cquad := PackedVector2Array([
				cbp0 + perp * (c_side * w * 0.5),
				cbp0 + perp * (c_side * c_half),
				cbp1 + perp * (c_side * c_half),
				cbp1 + perp * (c_side * w * 0.5),
			])
			var ccols := PackedColorArray([
				Color(gc.r, gc.g, gc.b, cpk0),
				Color(gc.r, gc.g, gc.b, 0.0),
				Color(gc.r, gc.g, gc.b, 0.0),
				Color(gc.r, gc.g, gc.b, cpk1),
			])
			draw_polygon(cquad, ccols)

	var N := maxi(2, SEGMENTS)
	# Writhing tapered BODY — a filled polygon with noise-perturbed edges + breathing width.
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	top.resize(N + 1)
	bot.resize(N + 1)
	for s in range(N + 1):
		var f := float(s) / float(N)
		var along := L * f
		var pulse := 1.0 + PULSE_AMOUNT * sin(along * PULSE_FREQ - _t * PULSE_TRAVEL_SPEED)
		var open_t := smoothstep(0.0, MUZZLE_FLARE_LEN / L, f)  # point at the muzzle → full body width over the flare span
		var hw := lerpf(CORE_MUZZLE_W, CORE_TIP_W, f) * 0.5 * pulse * open_t
		var et := EDGE_TURB_AMP * _turb(along * EDGE_TURB_FREQ + _t * EDGE_TURB_SPEED)
		var eb := EDGE_TURB_AMP * _turb(along * EDGE_TURB_FREQ * 1.13 - _t * EDGE_TURB_SPEED + 5.0)
		var bp := a + dir * along
		top[s] = bp + perp * (hw + et)
		bot[s] = bp - perp * (hw + eb)
	var body := PackedVector2Array()
	for p: Vector2 in top:
		body.append(p)
	for j in range(bot.size() - 1, -1, -1):
		body.append(bot[j])
	draw_colored_polygon(body, Color(g.r, g.g, g.b, BODY_ALPHA * flick))

	# Outer haze — segmented soft tube (3 width tiers) that tapers to a point at the muzzle (no flat cap).
	var HSEG := 16
	for hs in range(HSEG):
		var hf0 := float(hs) / float(HSEG)
		var hf1 := float(hs + 1) / float(HSEG)
		var hramp := smoothstep(0.0, MUZZLE_FLARE_LEN / L, (hf0 + hf1) * 0.5)
		var hp0 := a + dir * (L * hf0)
		var hp1 := a + dir * (L * hf1)
		draw_line(hp0, hp1, Color(g.r, g.g, g.b, HAZE_ALPHA * 0.4 * flick), maxf(0.5, w * HAZE_FRAC * 1.8 * hramp))
		draw_line(hp0, hp1, Color(g.r, g.g, g.b, HAZE_ALPHA * 0.7 * flick), maxf(0.5, w * HAZE_FRAC * 1.25 * hramp))
		draw_line(hp0, hp1, Color(g.r, g.g, g.b, HAZE_ALPHA * flick), maxf(0.5, w * HAZE_FRAC * hramp))

	# Flowing inner glow — segmented, energy bands stream muzzle → tip.
	var iw := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5)
	for s in range(N):
		var f0 := float(s) / float(N)
		var f1 := float(s + 1) / float(N)
		var alo := L * (f0 + f1) * 0.5
		var pulse := 1.0 + PULSE_AMOUNT * sin(alo * PULSE_FREQ - _t * PULSE_TRAVEL_SPEED)
		var flow := 0.5 + 0.5 * _turb(alo * FLOW_FREQ - _t * FLOW_SPEED)
		var bright := flick * lerpf(FLOW_BASE, 1.0, clampf(flow * FLOW_CONTRAST, 0.0, 1.0))
		draw_line(a + dir * (L * f0), a + dir * (L * f1), Color(iw.r, iw.g, iw.b, INNER_ALPHA * bright), maxf(2.0, w * INNER_FRAC * pulse))

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

	# Scrolling energy pulses (bright dashes racing gun → tip — reinforce the flow).
	for k in PULSE_COUNT:
		var phase := fmod(_t * PULSE_SPEED + float(k) * (L / float(maxi(1, PULSE_COUNT))), L)
		var pc := a + dir * phase
		var pt := pc - dir * minf(PULSE_LEN, phase)
		draw_line(pt, pc, Color(1.0, 1.0, 1.0, 0.45 * flick), maxf(2.0, w * 0.22))

	# Edge flares — short tendrils spitting off the writhing body.
	for i in EDGE_FLARE_COUNT:
		var ef := randf()
		var side := 1.0 if randf() < 0.5 else -1.0
		var ehw := lerpf(CORE_MUZZLE_W, CORE_TIP_W, ef) * 0.5
		var ebase := a + dir * (L * ef) + perp * (side * ehw)
		var etip := ebase + perp * (side * EDGE_FLARE_LEN * randf_range(0.4, 1.0)) + dir * randf_range(-8.0, 16.0)
		draw_line(ebase, etip, Color(g.r, g.g, g.b, 0.4 * flick), maxf(1.0, w * 0.1))

	# Segmented white CORE — drawn over the motion so it stays crisp/readable.
	for s in range(N):
		var f0 := float(s) / float(N)
		var f1 := float(s + 1) / float(N)
		var alo := L * (f0 + f1) * 0.5
		var pulse := 1.0 + PULSE_AMOUNT * sin(alo * PULSE_FREQ - _t * PULSE_TRAVEL_SPEED)
		var flow := 0.5 + 0.5 * _turb(alo * FLOW_FREQ - _t * FLOW_SPEED)
		var bright := flick * lerpf(0.6, 1.0, clampf(flow * FLOW_CONTRAST, 0.0, 1.0))
		draw_line(a + dir * (L * f0), a + dir * (L * f1), Color(1.0, 1.0, 1.0, bright), maxf(1.5, w * CORE_FRAC * pulse))

	# Muzzle cone flare — feathered megaphone: sharp point at the source opening to beam width.
	# Bright centerline → α0 at the perp edges, brightness easing to 0 at the flare end so the cone
	# dissolves seamlessly into the beam body (no bulge, no pinch, no hard edge).
	var flare_len := minf(MUZZLE_FLARE_LEN, L)
	var FSEG := 14
	var cone_end_hw := MUZZLE_FLARE_WIDTH * 0.5
	for f_side: float in [1.0, -1.0]:
		for fs in range(FSEG):
			var ff0 := float(fs) / float(FSEG)
			var ff1 := float(fs + 1) / float(FSEG)
			var fhw0 := cone_end_hw * pow(ff0, MUZZLE_FLARE_CURVE)
			var fhw1 := cone_end_hw * pow(ff1, MUZZLE_FLARE_CURVE)
			var fc0 := a + dir * (flare_len * ff0)
			var fc1 := a + dir * (flare_len * ff1)
			var fb0 := MUZZLE_FLARE_INTENSITY * (1.0 - ff0) * flick
			var fb1 := MUZZLE_FLARE_INTENSITY * (1.0 - ff1) * flick
			var fquad := PackedVector2Array([
				fc0,
				fc0 + perp * (f_side * fhw0),
				fc1 + perp * (f_side * fhw1),
				fc1,
			])
			var fcols := PackedColorArray([
				Color(g.r, g.g, g.b, fb0),
				Color(g.r, g.g, g.b, 0.0),
				Color(g.r, g.g, g.b, 0.0),
				Color(g.r, g.g, g.b, fb1),
			])
			draw_polygon(fquad, fcols)
	draw_circle(a, w * 0.6, Color(g.r, g.g, g.b, 0.4 * flick))
	draw_circle(a, w * 0.3, Color(1.0, 1.0, 1.0, 0.9 * flick))

	# Frayed dissipating tip — a fan of flickering wisps fanning off the end.
	draw_circle(b, w * 0.55, Color(g.r, g.g, g.b, 0.22 * flick))
	for i in TIP_FRAY_COUNT:
		var fang := dir.angle() + randf_range(-TIP_FRAY_SPREAD, TIP_FRAY_SPREAD)
		var flen := TIP_FRAY_LEN * randf_range(0.35, 1.0)
		draw_line(b, b + Vector2.from_angle(fang) * flen, Color(g.r, g.g, g.b, randf_range(0.2, 0.6) * flick), maxf(1.0, w * 0.12))

	# Impact flare at the contact point (when it hits an enemy).
	if _hit:
		draw_circle(b, FLARE_GLOW_SIZE, Color(FLARE_GLOW_COLOR.r, FLARE_GLOW_COLOR.g, FLARE_GLOW_COLOR.b, 0.35 * flick))
		draw_circle(b, FLARE_GLOW_SIZE * 0.4, Color(1.0, 1.0, 1.0, 0.8 * flick))
		for i in FLARE_SPARKS:
			var ang := -dir.angle() + PI + randf_range(-0.85, 0.85)
			var sp := Vector2(cos(ang), sin(ang)) * FLARE_SPARK_LEN * randf_range(0.5, 1.0)
			draw_line(b, b + sp, Color(FLARE_SPARK_COLOR.r, FLARE_SPARK_COLOR.g, FLARE_SPARK_COLOR.b, 0.5 * flick), 2.0)
