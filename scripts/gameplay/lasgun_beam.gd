extends Node2D
# =============================================================================
# Lasgun procedural beam — SELF-CONTAINED COPY of the player Lasgun beam from
# weapon_system.gd (_tick_beam_fx / _draw_beam_fx / _draw_flare / _draw_flare_debris
# / _pseudo + the BEAM_*/FLARE_* constants). Copied verbatim (only `_glow.draw_*`
# → `draw_*` on self) so the player's Lasgun in weapon_system.gd stays byte-for-byte
# untouched. This node IS its own additive glow (BLEND_MODE_ADD) and drives any number
# of registered beams — the Chromeleon orbs use two (blue + teal).
#
# Usage:
#   var fx := LasgunBeamScript.new(); add_child(fx)
#   var beam := fx.make_beam(color, width)          # returns a ctx Dictionary
#   fx.set_beam(beam, from, to, active, hit)        # each frame while firing
#   beam["beam_active"] = false                     # stop (debris finishes on its own)
# =============================================================================

# ── Beam look (copied from weapon_system.gd; core stays white, colour lives in the glow) ──
const BEAM_CORE_COLOR   := Color(1.0, 1.0, 1.0)   # pure white core (always)
const BEAM_CORE_FRAC    := 0.28   # fat white core
const BEAM_INNER_FRAC   := 0.46
const BEAM_HAZE_FRAC    := 0.95
const BEAM_INNER_ALPHA  := 0.55
const BEAM_HAZE_ALPHA   := 0.18
const BEAM_FLICKER      := 0.12
const BEAM_FLICKER_SPEED:= 28.0
const BEAM_WOBBLE_AMP    := 4.0
const BEAM_WOBBLE_FREQ   := 0.05
const BEAM_WOBBLE_SPEED  := 7.0
const BEAM_PULSE_COUNT   := 5
const BEAM_PULSE_SPEED   := 620.0
const BEAM_PULSE_LEN     := 46.0
# Smooth helix ribbons — sine strands braiding around the beam, scrolling gun→impact (replaces crackle)
const BEAM_RIBBON_COUNT  := 2
const BEAM_RIBBON_AMP    := 7.0
const BEAM_RIBBON_WAVES  := 5.0
const BEAM_RIBBON_SCROLL := 6.0
const BEAM_RIBBON_WIDTH  := 2.5
const BEAM_RIBBON_SEGS   := 48
const BEAM_RIBBON_ALPHA  := 0.6
const BEAM_ELEC_INTENSITY:= 0.0   # jagged crackle replaced by smooth ribbons
const BEAM_ELEC_SEGMENTS := 9
const BEAM_ELEC_AMP      := 6.0
const BEAM_ELEC_SPEED    := 22.0
const BEAM_PARTICLE_RATE := 26.0
const BEAM_PARTICLE_SPEED:= 900.0
const BEAM_PARTICLE_LEN  := 18.0
const BEAM_PARTICLE_LIFE := 0.6
const BEAM_FIRE_FLASH_SIZE := 42.0
const BEAM_FIRE_FLASH_TIME := 0.12

# ── Impact flare (cutting-torch / welding-arc) ──
const FLARE_CORE_COLOR     := Color(1.0, 1.0, 1.0)
const FLARE_SPARK_COLOR    := Color(1.0, 0.55, 0.15)
const FLARE_GLOW_COLOR     := Color(1.0, 0.35, 0.10)
const FLARE_CENTER_SIZE    := 4.0
const FLARE_GLOW_SIZE      := 16.0
const FLARE_SPARKS         := 12
const FLARE_SPARK_LEN      := 34.0
const FLARE_SPARK_SPREAD   := 1.7
const FLARE_SPARK_WIDTH    := 2.0
const FLARE_DEBRIS_RATE    := 40.0
const FLARE_DEBRIS_SPEED   := 260.0
const FLARE_DEBRIS_LIFE    := 0.35
const FLARE_DEBRIS_GRAVITY := 600.0
const FLARE_DEBRIS_SIZE    := 2.5
const FLARE_CHUNK_RATE     := 28.0
const FLARE_CHUNK_SIZE     := 9.0
const FLARE_CHUNK_SPEED    := 200.0
const FLARE_CHUNK_LIFE     := 0.18
const FLARE_CHUNK_LUMPS    := 0.35

var _beam_time := 0.0       # shared accumulator for the beam flicker / flare shimmer
var _ctxs: Array = []       # registered beam ctx dicts

func _ready() -> void:
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # reads as light, not paint
	material = gm
	z_as_relative = false
	z_index = 200

## Register a beam; returns its ctx (the same field set weapon_system uses).
func make_beam(color: Color, width: float) -> Dictionary:
	var ctx := {
		"beam_active": false, "beam_from": Vector2.ZERO, "beam_to": Vector2.ZERO,
		"beam_color": color, "beam_width": width, "beam_hit": false,
		"beam_particles": [], "beam_part_acc": 0.0, "beam_was_active": false,
		"fire_flash_t": 0.0, "flare_debris": [], "flare_debris_acc": 0.0,
		"flare_chunks": [], "flare_chunk_acc": 0.0,
	}
	_ctxs.append(ctx)
	return ctx

## Update a beam's geometry + state for this frame.
func set_beam(ctx: Dictionary, from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
	ctx["beam_from"] = from
	ctx["beam_to"]   = to
	ctx["beam_active"] = active
	ctx["beam_hit"]    = hit

func _process(delta: float) -> void:
	_beam_time += delta
	for ctx: Dictionary in _ctxs:
		_tick_beam_fx(ctx, delta)
	queue_redraw()

func _draw() -> void:
	for ctx: Dictionary in _ctxs:
		_draw_beam_fx(ctx)

func _pseudo(a: float, b: float) -> float:
	var v := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (v - floor(v)) * 2.0 - 1.0

## Per-frame beam FX bookkeeping (fire flash + streak particles + debris) for ONE beam.
func _tick_beam_fx(ctx: Dictionary, delta: float) -> void:
	var active: bool = bool(ctx["beam_active"])
	var hit: bool = bool(ctx["beam_hit"])
	var bfrom: Vector2 = ctx["beam_from"]
	var bto: Vector2 = ctx["beam_to"]
	var bwidth: float = float(ctx["beam_width"])
	# Muzzle flash the instant the beam turns on.
	if active and not bool(ctx["beam_was_active"]):
		ctx["fire_flash_t"] = BEAM_FIRE_FLASH_TIME
	ctx["beam_was_active"] = active
	ctx["fire_flash_t"] = maxf(0.0, float(ctx["fire_flash_t"]) - delta)

	# Spawn + advance streak particles streaming gun → impact along the beam.
	var beam_len := bfrom.distance_to(bto)
	var particles: Array = ctx["beam_particles"]
	if active:
		ctx["beam_part_acc"] = float(ctx["beam_part_acc"]) + BEAM_PARTICLE_RATE * delta
		while float(ctx["beam_part_acc"]) >= 1.0:
			ctx["beam_part_acc"] = float(ctx["beam_part_acc"]) - 1.0
			particles.append({
				"along": 0.0,
				"off": randf_range(-bwidth * 0.35, bwidth * 0.35),
				"life": 0.0,
			})
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["along"] = float(p["along"]) + BEAM_PARTICLE_SPEED * delta
		p["life"] = float(p["life"]) + delta
		if float(p["along"]) > beam_len or float(p["life"]) > BEAM_PARTICLE_LIFE:
			particles.remove_at(i)
		else:
			particles[i] = p
		i -= 1

	# Molten debris flecks sprayed back toward the gun off the contact point.
	var debris: Array = ctx["flare_debris"]
	if active and hit:
		var bdir := bto - bfrom
		bdir = bdir.normalized() if bdir.length() > 0.001 else Vector2.UP
		var back_ang := (-bdir).angle()
		ctx["flare_debris_acc"] = float(ctx["flare_debris_acc"]) + FLARE_DEBRIS_RATE * delta
		while float(ctx["flare_debris_acc"]) >= 1.0:
			ctx["flare_debris_acc"] = float(ctx["flare_debris_acc"]) - 1.0
			var ang := back_ang + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
			var spd := FLARE_DEBRIS_SPEED * randf_range(0.5, 1.0)
			debris.append({
				"pos": bto, "vel": Vector2.from_angle(ang) * spd,
				"life": 0.0, "max_life": FLARE_DEBRIS_LIFE * randf_range(0.6, 1.0),
			})
	var di := debris.size() - 1
	while di >= 0:
		var fb: Dictionary = debris[di]
		fb["life"] = float(fb["life"]) + delta
		if float(fb["life"]) >= float(fb["max_life"]):
			debris.remove_at(di)
			di -= 1
			continue
		var v: Vector2 = fb["vel"]
		v.y += FLARE_DEBRIS_GRAVITY * delta   # arc down like molten flecks
		fb["vel"] = v
		fb["pos"] = (fb["pos"] as Vector2) + v * delta
		debris[di] = fb
		di -= 1

	# Chunky energy splatter — thick blobs with mass, sprayed back+out, short-lived.
	var chunks: Array = ctx["flare_chunks"]
	if active and hit:
		var cdir := bto - bfrom
		cdir = cdir.normalized() if cdir.length() > 0.001 else Vector2.UP
		var cback := (-cdir).angle()
		ctx["flare_chunk_acc"] = float(ctx["flare_chunk_acc"]) + FLARE_CHUNK_RATE * delta
		while float(ctx["flare_chunk_acc"]) >= 1.0:
			ctx["flare_chunk_acc"] = float(ctx["flare_chunk_acc"]) - 1.0
			var cang := cback + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
			var cspd := FLARE_CHUNK_SPEED * randf_range(0.4, 1.0)
			var lumps: Array = []
			for _k in range(8):
				lumps.append(randf_range(1.0 - FLARE_CHUNK_LUMPS, 1.0 + FLARE_CHUNK_LUMPS))
			chunks.append({
				"pos": bto, "vel": Vector2.from_angle(cang) * cspd,
				"life": 0.0, "max_life": FLARE_CHUNK_LIFE * randf_range(0.7, 1.0),
				"size": FLARE_CHUNK_SIZE * randf_range(0.7, 1.2), "lumps": lumps,
			})
	var ci := chunks.size() - 1
	while ci >= 0:
		var cb: Dictionary = chunks[ci]
		cb["life"] = float(cb["life"]) + delta
		if float(cb["life"]) >= float(cb["max_life"]):
			chunks.remove_at(ci)
			ci -= 1
			continue
		var cv: Vector2 = cb["vel"]
		cv.y += FLARE_DEBRIS_GRAVITY * delta
		cb["vel"] = cv
		cb["pos"] = (cb["pos"] as Vector2) + cv * delta
		chunks[ci] = cb
		ci -= 1

func _draw_beam_fx(ctx: Dictionary) -> void:
	_draw_flare_debris(ctx)   # molten flecks (keep flying even after the beam stops)
	if not bool(ctx["beam_active"]):
		return
	var a: Vector2 = ctx["beam_from"]
	var b: Vector2 = ctx["beam_to"]
	var flick := 1.0 + sin(_beam_time * BEAM_FLICKER_SPEED) * BEAM_FLICKER   # subtle shimmer
	var w: float = float(ctx["beam_width"])
	var g: Color = ctx["beam_color"]   # glow colour (blue for the Lasgun, teal for the tether)
	# Outer haze — stacked soft lines → smooth falloff, no hard edge
	draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * 0.4 * flick), w * BEAM_HAZE_FRAC * 1.8)
	draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * 0.7 * flick), w * BEAM_HAZE_FRAC * 1.25)
	draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * flick),       w * BEAM_HAZE_FRAC)
	# Inner glow — glow colour blended halfway to white
	var iw := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5, BEAM_INNER_ALPHA * flick)
	draw_line(a, b, iw, maxf(2.0, w * BEAM_INNER_FRAC))

	# Beam axis
	var seg := b - a
	var L := seg.length()
	var dir := (seg / L) if L > 0.001 else Vector2.UP
	var perp := Vector2(-dir.y, dir.x)

	# (1) Energy wobble layer — rippling bright polyline (heat-haze / turbulence)
	if BEAM_WOBBLE_AMP > 0.0 and L > 1.0:
		var wprev := a
		for s in range(1, 17):
			var alo := L * float(s) / 16.0
			var woff := sin(alo * BEAM_WOBBLE_FREQ - _beam_time * BEAM_WOBBLE_SPEED) * BEAM_WOBBLE_AMP
			var wpt := a + dir * alo + perp * woff
			draw_line(wprev, wpt, Color(g.r, g.g, g.b, 0.30 * flick), maxf(2.0, w * 0.16))
			wprev = wpt

	# (2) Scrolling energy pulses — bright dashes racing gun → impact
	if L > 1.0:
		for k in BEAM_PULSE_COUNT:
			var phase := fmod(_beam_time * BEAM_PULSE_SPEED + float(k) * (L / float(maxi(1, BEAM_PULSE_COUNT))), L)
			var pc := a + dir * phase
			var pt := pc - dir * minf(BEAM_PULSE_LEN, phase)
			draw_line(pt, pc, Color(1.0, 1.0, 1.0, 0.45 * flick), maxf(2.0, w * 0.22))

	# (3) Smooth helix ribbons — sine strands braiding around the beam, scrolling gun → impact
	if BEAM_RIBBON_COUNT > 0 and L > 1.0:
		var rcol := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5, BEAM_RIBBON_ALPHA * flick)
		for rb in BEAM_RIBBON_COUNT:
			var rphase := float(rb) * TAU / float(maxi(1, BEAM_RIBBON_COUNT))
			var rpts := PackedVector2Array()
			rpts.resize(BEAM_RIBBON_SEGS + 1)
			for s in range(BEAM_RIBBON_SEGS + 1):
				var f := float(s) / float(BEAM_RIBBON_SEGS)
				var roff := sin(f * BEAM_RIBBON_WAVES * TAU - _beam_time * BEAM_RIBBON_SCROLL + rphase) * BEAM_RIBBON_AMP
				rpts[s] = a + dir * (L * f) + perp * roff
			draw_polyline(rpts, rcol, BEAM_RIBBON_WIDTH)

	# Core — thin pure white, straight, on top
	draw_line(a, b, Color(BEAM_CORE_COLOR.r, BEAM_CORE_COLOR.g, BEAM_CORE_COLOR.b, flick), maxf(1.5, w * BEAM_CORE_FRAC))

	# (4) Stretched particles streaming down the beam
	for p: Dictionary in (ctx["beam_particles"] as Array):
		var alo := float(p["along"])
		if alo > L:
			continue
		var ppos := a + dir * alo + perp * float(p["off"])
		var ptail := ppos - dir * BEAM_PARTICLE_LEN
		var pl := clampf(1.0 - float(p["life"]) / BEAM_PARTICLE_LIFE, 0.0, 1.0)
		draw_line(ptail, ppos, Color(1.0, 1.0, 1.0, 0.55 * pl), 2.0)

	# (5) Fire flash at the muzzle the instant the beam turns on
	var fire_flash_t: float = float(ctx["fire_flash_t"])
	if fire_flash_t > 0.0:
		var ft := fire_flash_t / BEAM_FIRE_FLASH_TIME   # 1 → 0
		var fr := BEAM_FIRE_FLASH_SIZE * (1.0 + (1.0 - ft) * 0.8)
		draw_circle(a, fr, Color(g.r, g.g, g.b, 0.25 * ft))
		draw_circle(a, fr * 0.4, Color(1.0, 1.0, 1.0, 0.7 * ft))

	if bool(ctx["beam_hit"]):
		_draw_flare(b, dir, flick)

## Cutting-torch / welding-arc burst at the contact point. `dir` = beam direction.
func _draw_flare(at: Vector2, dir: Vector2, _flick: float) -> void:
	var back_ang := (-dir).angle()   # toward the gun
	var gc := FLARE_GLOW_COLOR
	draw_circle(at, FLARE_GLOW_SIZE, Color(gc.r, gc.g, gc.b, 0.20))
	draw_circle(at, FLARE_GLOW_SIZE * 0.55, Color(gc.r, gc.g, gc.b, 0.35))
	var n := maxi(1, FLARE_SPARKS + randi_range(-3, 3))
	var sc := FLARE_SPARK_COLOR
	for _i in n:
		var ang := back_ang + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
		var d := Vector2.from_angle(ang)
		var perp := Vector2(-d.y, d.x)
		var ln := FLARE_SPARK_LEN * randf_range(0.35, 1.0)
		var tip := at + d * ln
		var br := randf_range(0.5, 1.0)   # per-spark brightness jitter
		draw_polygon(
			PackedVector2Array([at + perp * FLARE_SPARK_WIDTH * 0.5, at - perp * FLARE_SPARK_WIDTH * 0.5, tip]),
			PackedColorArray([
				Color(1.0, 0.85, 0.5, br),
				Color(1.0, 0.85, 0.5, br),
				Color(sc.r, sc.g, sc.b, 0.0),
			]))
	draw_circle(at, FLARE_CENTER_SIZE * randf_range(0.8, 1.2), Color(1.0, 1.0, 1.0, randf_range(0.7, 1.0)))
	draw_circle(at, FLARE_CENTER_SIZE * 0.45, Color(FLARE_CORE_COLOR.r, FLARE_CORE_COLOR.g, FLARE_CORE_COLOR.b, 1.0))

## Persistent molten flecks + chunky splatter (drawn even after the beam stops).
func _draw_flare_debris(ctx: Dictionary) -> void:
	for cb: Dictionary in (ctx["flare_chunks"] as Array):
		var ct := clampf(1.0 - float(cb["life"]) / float(cb["max_life"]), 0.0, 1.0)
		var cp: Vector2 = cb["pos"]
		var r: float = float(cb["size"]) * (0.5 + 0.5 * ct)
		var lumps: Array = cb["lumps"]
		var n: int = lumps.size()
		var pts := PackedVector2Array()
		for k in range(n):
			var ang: float = TAU * float(k) / float(n)
			pts.append(cp + Vector2(cos(ang), sin(ang)) * r * float(lumps[k]))
		draw_colored_polygon(pts, Color(1.0, 0.6, 0.25, 0.85 * ct))
		draw_circle(cp, r * 0.4, Color(1.0, 0.9, 0.6, 0.9 * ct))
	for fb: Dictionary in (ctx["flare_debris"] as Array):
		var t := clampf(1.0 - float(fb["life"]) / float(fb["max_life"]), 0.0, 1.0)
		var p: Vector2 = fb["pos"]
		var v: Vector2 = fb["vel"]
		var tail := p - v.normalized() * FLARE_DEBRIS_SIZE * 2.2
		draw_line(tail, p, Color(1.0, 0.75, 0.35, 0.7 * t), maxf(1.0, FLARE_DEBRIS_SIZE * 0.7))
		draw_circle(p, FLARE_DEBRIS_SIZE * t, Color(1.0, 0.85, 0.5, t))
