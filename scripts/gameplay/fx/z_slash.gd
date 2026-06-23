extends Node2D
class_name ZSlash
## Sweeping energy-slash VFX for the Z-Sword — reworked toward a blue-white CRESCENT BLADE (per detailed crit:
## the old version read as a uniform green "neon tube"). Layers (additive HDR, back→front): blue bloom aura →
## translucent CYAN crescent body with a thin→thick→thin-sharp WIDTH CURVE → parallel white-blue ghost streaks →
## flying energy SHARDS → a HARD near-overexposed white-cyan OUTER cutting edge → a bright leading impact bloom.
## A faint tapered origin wisp keeps it attached to the ship without the old rigid tube. Layer-4 screen
## DISTORTION (z_slash_distort.gdshader) refracts the background along the arc. Driven by arena_weapons._tick_zsword.

const SPAN        := 1.55     # rad of crescent behind the leading edge (~89°)
const SEGS        := 32
const BODY_PEAK   := 46.0     # crescent half-width at its MIDDLE (px); tapers to a sharp point at both ends
const BLOOM_PEAK  := 96.0     # blue aura half-width (wide soft halo)
const FADE_TIME   := 0.15
const GHOST_COUNT := 4        # parallel inner streaks
const EDGE_W      := 2.8      # hard outer cutting-edge line width
const ORIGIN_INNER := 14.0    # origin wisp starts just outside the ship
# Palette — white core → cyan body → blue glow → faint violet (NO green).
const CORE_COL    := Color(2.3, 2.7, 3.0)   # white-hot, faint cyan — the overexposed cutting edge
const EDGE_COL    := Color(1.4, 2.5, 3.3)   # bright cyan-white outer rim
const BODY_COL    := Color(0.42, 1.35, 2.3) # pale cyan body
const GLOW_COL    := Color(0.22, 0.8, 2.5)  # saturated blue aura
const GHOST_COL   := Color(1.0, 1.95, 2.8)  # white-blue inner streaks
const SHARD_COL   := Color(1.5, 2.3, 3.1)   # white-blue flying shards
const VIOLET_COL  := Color(1.2, 0.8, 2.5)   # faint violet near the impact bloom
const BODY_ALPHA  := 0.5
const BLOOM_ALPHA := 0.14
# Shards (flying energy fragments — direction + impact).
const SHARD_EMIT_INT := 0.045   # trailing shard cadence during the sweep
const SHARD_LIFE  := 0.32
const SHARD_LEN   := 30.0
const SHARD_SPEED_MIN := 280.0
const SHARD_SPEED_MAX := 660.0
const SHARD_HIT_COUNT := 8       # shards per enemy-hit burst
# Layer-4 screen distortion.
const DISTORT_SHADER := "res://scripts/gameplay/fx/z_slash_distort.gdshader"
const DISTORT_ENABLED := true
const DISTORT_FORCE := 0.02
const DISTORT_LAYER := 79

var _active := false
var _fading := false
var _alpha := 0.0
var _clock := 0.0
var _center := Vector2.ZERO
var _radius := 0.0
var _start := 0.0
var _lead := 0.0
var _shards: Array = []          # {pos, vel, age, ttl, len}
var _shard_acc := 0.0
var _distort_layer: CanvasLayer = null
var _distort_rect: ColorRect = null
var _distort_mat: ShaderMaterial = null

func _ready() -> void:
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = cm
	z_index = 7
	if DISTORT_ENABLED:
		_distort_mat = ShaderMaterial.new()
		_distort_mat.shader = load(DISTORT_SHADER)
		_distort_mat.set_shader_parameter("force", 0.0)
		_distort_rect = ColorRect.new()
		_distort_rect.material = _distort_mat
		_distort_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_distort_layer = CanvasLayer.new()
		_distort_layer.layer = DISTORT_LAYER
		_distort_layer.add_child(_distort_rect)
		_distort_layer.hide()
		add_child(_distort_layer)
	hide()

## Called every frame while the blade sweeps. center/radius = ring; start = sweep origin; lead = blade angle.
func set_sweep(center: Vector2, radius: float, start_ang: float, lead_ang: float) -> void:
	_center = center
	_radius = radius
	_start = start_ang
	_lead = lead_ang
	_active = true
	_fading = false
	_alpha = 1.0
	show()
	queue_redraw()

func fade_out() -> void:
	if _active:
		_fading = true

## Impact: a burst of directional white-blue shards at a hit position.
func add_spark(pos: Vector2) -> void:
	var out := (pos - _center).normalized()
	if out == Vector2.ZERO:
		out = Vector2.RIGHT
	for _k in SHARD_HIT_COUNT:
		var ang := out.angle() + randf_range(-0.9, 0.9)
		var v := Vector2(cos(ang), sin(ang)) * randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX)
		_emit_shard(pos, v)

func _emit_shard(pos: Vector2, vel: Vector2) -> void:
	_shards.append({"pos": pos, "vel": vel, "age": 0.0, "ttl": SHARD_LIFE * randf_range(0.7, 1.2),
		"len": SHARD_LEN * randf_range(0.6, 1.3)})

func _process(delta: float) -> void:
	_clock += delta
	# Tick shards (drawn fragments — no particle nodes).
	var i := _shards.size() - 1
	while i >= 0:
		var s: Dictionary = _shards[i]
		s["age"] = float(s["age"]) + delta
		s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		if float(s["age"]) >= float(s["ttl"]):
			_shards.remove_at(i)
		else:
			_shards[i] = s
		i -= 1
	if not _active:
		if not _shards.is_empty():
			queue_redraw()
		return
	if not _fading:
		# Trail shards flying off the leading edge (direction cue), biased along the sweep tangent + outward.
		_shard_acc += delta
		while _shard_acc >= SHARD_EMIT_INT:
			_shard_acc -= SHARD_EMIT_INT
			var dl := Vector2(cos(_lead), sin(_lead))
			var tang := dl.rotated(PI * 0.5)                    # sweep direction (+angle)
			var v := (tang * randf_range(0.7, 1.0) + dl * randf_range(0.1, 0.5)).normalized() \
					* randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX)
			_emit_shard(_center + dl * _radius, v)
	else:
		_alpha -= delta / FADE_TIME
		if _alpha <= 0.0:
			_active = false
			_fading = false
			_alpha = 0.0
			hide()
			if _distort_layer != null:
				_distort_layer.hide()
	queue_redraw()

## Crescent half-width along the trail (p: 0 tail → 1 lead): thin → thick(middle) → thin-and-SHARP. Not a tube.
func _w(p: float, peak: float) -> float:
	return peak * pow(clampf(4.0 * p * (1.0 - p), 0.0, 1.0), 0.55)

func _draw() -> void:
	# shards can outlive the body fade
	if not _shards.is_empty():
		_draw_shards()
	if not _active or _alpha <= 0.0:
		return
	var swept := _lead - _start
	var span := minf(SPAN, maxf(0.0, swept))
	if span < 0.02:
		return
	var tail := _lead - span
	_draw_origin_wisp()                                   # faint tapered connector → ship (no rigid tube)
	_draw_crescent(tail, span, 0.0, BLOOM_PEAK, GLOW_COL, BLOOM_ALPHA, true)   # blue bloom aura (wide, dim)
	_draw_crescent(tail, span, 0.0, BODY_PEAK, BODY_COL, BODY_ALPHA, false)    # translucent cyan body
	_draw_ghosts(tail, span)                              # parallel white-blue inner streaks
	_draw_cutting_edge(tail, span)                        # HARD bright outer rim (the cutting edge)
	_draw_lead_bloom()                                    # bright impact mass at the leading edge
	_update_distort(span)

## A crescent quad-strip tail→lead, centred at radius+`r_off`, half-width from `_w(p,peak)`. Alpha rises from the
## tail; `lead_strong` biases brightness toward the leading edge (used for the bloom aura).
func _draw_crescent(tail: float, span: float, r_off: float, peak: float, col: Color, a_mult: float, lead_strong: bool) -> void:
	var r0 := _radius + r_off
	for i in SEGS:
		var p0 := float(i) / float(SEGS)
		var p1 := float(i + 1) / float(SEGS)
		var a0 := tail + span * p0
		var a1 := tail + span * p1
		var w0 := _w(p0, peak)
		var w1 := _w(p1, peak)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var av0 := _alpha * a_mult * (0.3 + 0.7 * p0 if lead_strong else clampf(p0 * 1.8, 0.0, 1.0))
		var av1 := _alpha * a_mult * (0.3 + 0.7 * p1 if lead_strong else clampf(p1 * 1.8, 0.0, 1.0))
		var c0 := Color(col.r, col.g, col.b, av0)
		var c1 := Color(col.r, col.g, col.b, av1)
		draw_polygon(PackedVector2Array([d0 * (r0 - w0) + _center, d0 * (r0 + w0) + _center,
			d1 * (r0 + w1) + _center, d1 * (r0 - w1) + _center]), PackedColorArray([c0, c0, c1, c1]))

## Parallel white-blue inner streaks (speed lines) — long, mostly parallel to the arc, broken into fragments.
func _draw_ghosts(tail: float, span: float) -> void:
	for g in GHOST_COUNT:
		var r_off := lerpf(-0.55, 0.45, float(g) / float(GHOST_COUNT - 1)) * BODY_PEAK
		var phase := float(g) * 1.7
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in SEGS + 1:
			var p := float(i) / float(SEGS)
			var a := tail + span * p
			var d := Vector2(cos(a), sin(a))
			# break into fragments along the arc (gaps), brighter toward the lead
			var brk := smoothstep(0.35, 0.6, sin(p * 22.0 + phase) * 0.5 + 0.5)
			var av := pow(p, 1.3) * _alpha * 0.8 * brk
			pts.append(d * (_radius + r_off) + _center)
			cols.append(Color(GHOST_COL.r, GHOST_COL.g, GHOST_COL.b, av))
		draw_polyline_colors(pts, cols, 1.8, true)

## HARD outer cutting edge — a thin, near-overexposed line riding the crescent's OUTER boundary, brightest at lead.
func _draw_cutting_edge(tail: float, span: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in SEGS + 1:
		var p := float(i) / float(SEGS)
		var a := tail + span * p
		var d := Vector2(cos(a), sin(a))
		pts.append(d * (_radius + _w(p, BODY_PEAK)) + _center)         # ride the outer edge of the body
		var col := EDGE_COL.lerp(CORE_COL, smoothstep(0.6, 1.0, p))    # overexposed white toward the lead
		cols.append(Color(col.r, col.g, col.b, pow(p, 0.9) * _alpha))
	draw_polyline_colors(pts, cols, EDGE_W, true)

## Bright impact bloom at the leading edge (the "blooms into a bright mass" zone): blue → cyan → white core + violet.
func _draw_lead_bloom() -> void:
	var dl := Vector2(cos(_lead), sin(_lead))
	var c := _center + dl * _radius
	var a := _alpha
	draw_circle(c, 26.0, Color(GLOW_COL.r, GLOW_COL.g, GLOW_COL.b, 0.18 * a))
	draw_circle(c, 15.0, Color(VIOLET_COL.r, VIOLET_COL.g, VIOLET_COL.b, 0.16 * a))
	draw_circle(c, 11.0, Color(BODY_COL.r, BODY_COL.g, BODY_COL.b, 0.5 * a))
	draw_circle(c, 5.5, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.95 * a))

## Faint tapered radial wisp from the ship to the crescent — keeps it attached without the old rigid bright tube.
func _draw_origin_wisp() -> void:
	var dl := Vector2(cos(_lead), sin(_lead))
	var perp := dl.rotated(PI * 0.5)
	var p_in := _center + dl * ORIGIN_INNER
	var p_out := _center + dl * (_radius - BODY_PEAK * 0.3)
	var col := Color(BODY_COL.r, BODY_COL.g, BODY_COL.b, 0.22 * _alpha)
	draw_polygon(PackedVector2Array([p_in + perp * 1.5, p_out + perp * 6.0, p_out - perp * 6.0, p_in - perp * 1.5]),
		PackedColorArray([col, col, col, col]))
	draw_circle(p_in, 5.0, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.4 * _alpha))   # small origin flash

## Flying energy shards — thin bright white-blue fragments stretched along their velocity, fading.
func _draw_shards() -> void:
	for s in _shards:
		var pos: Vector2 = s["pos"]
		var vel: Vector2 = s["vel"]
		var k := 1.0 - float(s["age"]) / float(s["ttl"])
		if k <= 0.0 or vel == Vector2.ZERO:
			continue
		var tail := pos - vel.normalized() * float(s["len"])
		draw_line(tail, pos, Color(SHARD_COL.r, SHARD_COL.g, SHARD_COL.b, 0.25 * k), 3.0, true)   # soft
		draw_line(tail, pos, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.9 * k), 1.4, true)        # bright core

## LAYER 4 — drive the screen-distortion band each frame from the slash's world params.
func _update_distort(span: float) -> void:
	if _distort_rect == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var xf := vp.get_canvas_transform()
	var scale: float = xf.get_scale().y
	var scr := xf * _center
	_distort_layer.show()
	_distort_rect.size = vp_size
	_distort_rect.position = Vector2.ZERO
	_distort_mat.set_shader_parameter("center", scr / vp_size)
	_distort_mat.set_shader_parameter("radius_px", _radius * scale)
	_distort_mat.set_shader_parameter("thickness_px", BODY_PEAK * scale)
	_distort_mat.set_shader_parameter("ang_lead", _lead)
	_distort_mat.set_shader_parameter("ang_span", span)
	_distort_mat.set_shader_parameter("force", DISTORT_FORCE * _alpha)
	_distort_mat.set_shader_parameter("aberration", 0.2)   # low → less rainbow fringing (critique: avoid rainbow)
