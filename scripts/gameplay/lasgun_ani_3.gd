extends Node2D
## lasgun_ani_3 — the ARENA Lasgun beam VFX (F12 pickup → arena_weapons → this node). A FRESH build:
## shares no code with lasgun_ani_1 (immediate-mode original) or lasgun_ani_2 (quad+shader), both kept
## as backups. Driven by arena_weapons each frame via set_beam(from, to, active, hit) — world-space, the
## node draws itself on an additive layer. To revert, point arena_weapons.gd's BeamScript back at ani_2.
##
## STAGE 1 (this pass): a clean base beam (glow halo → white core) + a punchy muzzle on the activation
## edge (scaled fire-flash + expanding shock ring). STAGES 2–4 will add body taper/flow/flicker/haze,
## a richer impact (burst/sparks/scorch/hit-pop), and a screen-shake (arena player) on top.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
# Base beam look (Stage 1 minimal — enriched in Stage 2)
@export var beam_width      := 16.0    # total beam width (px); arena set_beam carries no width
@export var beam_glow_color := Color(1.0, 0.70, 0.40)  # warm glow (core stays white)
@export var core_color      := Color(1.0, 1.0, 1.0)
@export var core_frac       := 0.20    # white core width / beam width
@export var glow_frac       := 1.6     # outer glow width / beam width
@export var beam_flicker    := 0.10
@export var beam_flicker_sp := 24.0
# Impact (Stage 1 minimal — enriched in Stage 3)
@export var flare_glow_color := Color(1.0, 0.35, 0.10)
@export var flare_glow_size  := 18.0
@export var flare_center_size := 5.0
@export var flare_spark_color := Color(1.0, 0.55, 0.15)
# Muzzle punch (Stage 1)
const BEAM_FIRE_FLASH_SIZE      := 46.0   # base fire-flash radius (px)
const BEAM_FIRE_FLASH_TIME      := 0.12   # fire-flash lifetime (s)
const BEAM_FIRE_FLASH_SIZE_MULT := 2.4    # multiply the fire-flash radius on activation
const BEAM_FIRE_RING_SIZE       := 70.0   # expanding shock-ring radius at fire-start
const BEAM_FIRE_RING_TIME       := 0.18   # ring lifetime (s)
const BEAM_FIRE_RING_WIDTH      := 6.0    # ring stroke width at birth (thins as it expands)
# Body taper / flow / fast-flicker / heat-haze (Stage 2)
const BEAM_TAPER_MUZZLE   := 0.55   # width multiplier at the gun end (narrower)
const BEAM_TAPER_IMPACT   := 1.15   # width multiplier at the impact end (fatter)
const BEAM_TAPER_POW      := 1.4    # easing curve of the taper
const BEAM_BODY_SEGS      := 22     # segments used to draw the tapered body
const BEAM_FLOW_SPEED     := 2.2    # energy-dash scroll (beam-lengths/sec) racing muzzle → impact
const BEAM_FLOW_COUNT     := 5      # scrolling energy dashes
const BEAM_FLOW_LEN       := 40.0   # dash length (px)
const BEAM_FLICKER_FAST   := 0.06   # extra high-freq flicker layered on the slow shimmer
const BEAM_FLICKER_FAST_SP:= 70.0
const BEAM_HAZE_PUFF_RATE := 18.0   # soft heat-haze puffs spawned per second along the beam
const BEAM_HAZE_PUFF_LIFE := 0.4
const BEAM_HAZE_PUFF_SIZE := 10.0
const BEAM_HAZE_PUFF_DRIFT:= 26.0   # px/s lateral drift as puffs peel off and fade
# Impact burst / first-contact pop / scorch (Stage 3)
const FLARE_BURST_SIZE_MULT  := 1.5    # scale the sustained impact glow/center
const FLARE_SPARKS           := 12     # base spark streaks per frame
const FLARE_SPARKS_MULT      := 1.6
const FLARE_SPARK_LEN        := 34.0
const FLARE_SPARK_SPREAD     := 1.7    # cone half-angle (rad) around "back toward the gun"
const FLARE_SPARK_WIDTH      := 2.0
const FLARE_RING_PULSE_SPEED := 8.0    # subtle pulsing of the sustained glow
const FLARE_HIT_POP_SIZE     := 70.0   # one-shot bright ring on FIRST contact
const FLARE_HIT_POP_TIME     := 0.14
const FLARE_SCORCH_SIZE      := 22.0   # dark scorch decal radius at the contact point
const FLARE_SCORCH_ALPHA     := 0.45
const FLARE_SCORCH_FADE      := 0.6    # how long a scorch mark lingers (s)
const FLARE_SCORCH_RATE      := 30.0   # scorch marks spawned per second of contact
const FLARE_SCORCH_COLOR     := Color(0.10, 0.03, 0.02)  # dark burn — drawn on the NORMAL-blend layer

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _active := false
var _hit := false
var _was_active := false
var _t := 0.0
var _fire_flash_t := 0.0
var _fire_ring_t := 0.0
var _haze_puffs: Array = []   # {pos, vel, life, size}
var _haze_acc := 0.0
var _was_hit := false
var _hit_pop_t := 0.0
var _hit_pop_pos := Vector2.ZERO
var _scorch: Array = []       # {pos, life, size}
var _scorch_acc := 0.0
var _scorch_node: Node2D = null   # normal-blend child for dark scorch (additive can't darken)

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	# Normal-blend child UNDER the additive beam for dark scorch marks (additive can't darken).
	_scorch_node = Node2D.new()
	_scorch_node.z_index = -1
	add_child(_scorch_node)
	_scorch_node.draw.connect(_draw_scorch)

## Driven by arena_weapons each frame (world-space coords; this node sits at the arena origin).
func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
	if active and not _was_active:
		_fire_flash_t = BEAM_FIRE_FLASH_TIME   # activation edge → muzzle punch
		_fire_ring_t = BEAM_FIRE_RING_TIME
	if hit and not _was_hit:                   # first-contact edge → impact pop
		_hit_pop_t = FLARE_HIT_POP_TIME
		_hit_pop_pos = to
	_was_hit = hit
	_was_active = active
	_from = from
	_to = to
	_active = active
	_hit = hit
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_fire_flash_t = maxf(0.0, _fire_flash_t - delta)
	_fire_ring_t = maxf(0.0, _fire_ring_t - delta)
	_hit_pop_t = maxf(0.0, _hit_pop_t - delta)
	_tick_haze(delta)
	_tick_scorch(delta)
	if _scorch_node != null:
		_scorch_node.queue_redraw()
	if _active or _fire_flash_t > 0.0 or _fire_ring_t > 0.0 or _hit_pop_t > 0.0 or not _haze_puffs.is_empty():
		queue_redraw()

## Spawn dark scorch marks at the moving contact point while the beam hits; cull on lifetime.
func _tick_scorch(delta: float) -> void:
	if _active and _hit:
		_scorch_acc += FLARE_SCORCH_RATE * delta
		while _scorch_acc >= 1.0:
			_scorch_acc -= 1.0
			_scorch.append({"pos": _to, "life": 0.0, "size": FLARE_SCORCH_SIZE * randf_range(0.7, 1.2)})
	var i := _scorch.size() - 1
	while i >= 0:
		var s: Dictionary = _scorch[i]
		s["life"] = float(s["life"]) + delta
		if float(s["life"]) >= FLARE_SCORCH_FADE:
			_scorch.remove_at(i)
		i -= 1

## Drawn on the normal-blend _scorch_node so the marks read as DARK (under the additive beam).
func _draw_scorch() -> void:
	for s: Dictionary in _scorch:
		var sl := 1.0 - float(s["life"]) / FLARE_SCORCH_FADE
		var sc := FLARE_SCORCH_COLOR
		_scorch_node.draw_circle(s["pos"], float(s["size"]) * (0.5 + 0.5 * sl), Color(sc.r, sc.g, sc.b, FLARE_SCORCH_ALPHA * sl))

## Spawn heat-haze puffs along the live beam, drift them perpendicular, cull on lifetime.
func _tick_haze(delta: float) -> void:
	if _active:
		var seg := _to - _from
		var L := seg.length()
		if L > 1.0:
			var dir := seg / L
			var perp := Vector2(-dir.y, dir.x)
			_haze_acc += BEAM_HAZE_PUFF_RATE * delta
			while _haze_acc >= 1.0:
				_haze_acc -= 1.0
				var side := 1.0 if randf() < 0.5 else -1.0
				var at := _from + dir * (randf() * L) + perp * randf_range(-beam_width * 0.4, beam_width * 0.4)
				_haze_puffs.append({
					"pos": at,
					"vel": perp * (side * BEAM_HAZE_PUFF_DRIFT) - dir * (BEAM_HAZE_PUFF_DRIFT * 0.2),
					"life": 0.0, "size": BEAM_HAZE_PUFF_SIZE * randf_range(0.7, 1.3),
				})
	var i := _haze_puffs.size() - 1
	while i >= 0:
		var p: Dictionary = _haze_puffs[i]
		p["life"] = float(p["life"]) + delta
		if float(p["life"]) >= BEAM_HAZE_PUFF_LIFE:
			_haze_puffs.remove_at(i)
		else:
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		i -= 1

func _draw() -> void:
	var a := _from
	var flick := 1.0 + sin(_t * beam_flicker_sp) * beam_flicker
	flick *= 1.0 + sin(_t * BEAM_FLICKER_FAST_SP) * BEAM_FLICKER_FAST   # fast high-freq shimmer
	var g := beam_glow_color

	# ── Muzzle punch (runs a beat past release while its timers tick) ──
	if _fire_flash_t > 0.0:
		var ft := _fire_flash_t / BEAM_FIRE_FLASH_TIME   # 1 → 0
		var fr := BEAM_FIRE_FLASH_SIZE * BEAM_FIRE_FLASH_SIZE_MULT * (0.45 + 0.55 * ft)
		draw_circle(a, fr, Color(g.r, g.g, g.b, 0.28 * ft))
		draw_circle(a, fr * 0.4, Color(1.0, 1.0, 1.0, 0.8 * ft))
	if _fire_ring_t > 0.0:
		var rt := 1.0 - _fire_ring_t / BEAM_FIRE_RING_TIME   # 0 → 1 expand
		var rr := maxf(1.0, BEAM_FIRE_RING_SIZE * rt)
		var rw := maxf(1.0, BEAM_FIRE_RING_WIDTH * (1.0 - rt))
		draw_arc(a, rr, 0.0, TAU, 48, Color(g.r, g.g, g.b, 0.6 * (1.0 - rt)), rw)

	# ── Heat-haze puffs (low-alpha atmosphere; linger/fade even after release) ──
	for hp: Dictionary in _haze_puffs:
		var hl := 1.0 - float(hp["life"]) / BEAM_HAZE_PUFF_LIFE
		var hsz := float(hp["size"]) * (0.6 + 0.5 * (1.0 - hl))
		draw_circle(hp["pos"], hsz, Color(g.r, g.g, g.b, 0.10 * hl))

	# ── First-contact pop: one-shot bright expanding ring at the impact point ──
	if _hit_pop_t > 0.0:
		var pt := 1.0 - _hit_pop_t / FLARE_HIT_POP_TIME   # 0 → 1 expand
		var pr := maxf(1.0, FLARE_HIT_POP_SIZE * pt)
		var pw := maxf(1.0, 5.0 * (1.0 - pt))
		draw_arc(_hit_pop_pos, pr, 0.0, TAU, 40, Color(1.0, 0.9, 0.7, 0.7 * (1.0 - pt)), pw)

	if not _active:
		return
	var b := _to
	var seg := b - a
	var L := seg.length()
	if L < 1.0:
		return
	var w := beam_width
	var dir := seg / L

	# ── Tapered body: narrow at the muzzle → fatter toward impact, drawn in segments ──
	var N := BEAM_BODY_SEGS
	for s in range(N):
		var u0 := float(s) / float(N)
		var u1 := float(s + 1) / float(N)
		var taper := lerpf(BEAM_TAPER_MUZZLE, BEAM_TAPER_IMPACT, pow((u0 + u1) * 0.5, BEAM_TAPER_POW))
		var p0 := a + dir * (L * u0)
		var p1 := a + dir * (L * u1)
		draw_line(p0, p1, Color(g.r, g.g, g.b, 0.22 * flick), maxf(2.0, w * glow_frac * taper))
		draw_line(p0, p1, Color(g.r, g.g, g.b, 0.45 * flick), maxf(2.0, w * glow_frac * 0.55 * taper))
		draw_line(p0, p1, Color(core_color.r, core_color.g, core_color.b, flick), maxf(1.5, w * core_frac * taper))

	# ── Flow: bright energy dashes racing muzzle → impact ──
	for k in range(BEAM_FLOW_COUNT):
		var ph := fmod(_t * BEAM_FLOW_SPEED + float(k) / float(BEAM_FLOW_COUNT), 1.0)
		var lead := a + dir * (L * ph)
		var tail := lead - dir * minf(BEAM_FLOW_LEN, L * ph)
		draw_line(tail, lead, Color(1.0, 1.0, 1.0, 0.5 * flick), maxf(1.5, w * core_frac * 1.2))

	# ── Impact burst — pulsing hot glow + spark spray (back toward the gun) + blinding center ──
	if _hit:
		var fg := flare_glow_color
		var pulse := 1.0 + 0.25 * sin(_t * FLARE_RING_PULSE_SPEED)
		var gsz := flare_glow_size * FLARE_BURST_SIZE_MULT * pulse
		draw_circle(b, gsz, Color(fg.r, fg.g, fg.b, 0.20))
		draw_circle(b, gsz * 0.55, Color(fg.r, fg.g, fg.b, 0.35))
		# Chaotic spark spray in a backward cone, re-jittered every frame.
		var back := (-dir).angle()
		var sc := flare_spark_color
		var n := maxi(1, int(FLARE_SPARKS * FLARE_SPARKS_MULT) + randi_range(-3, 3))
		for _i in n:
			var sang := back + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
			var sd := Vector2.from_angle(sang)
			var sp := Vector2(-sd.y, sd.x)
			var ln := FLARE_SPARK_LEN * randf_range(0.35, 1.0)
			var tip := b + sd * ln
			var br := randf_range(0.5, 1.0)
			draw_polygon(
				PackedVector2Array([b + sp * FLARE_SPARK_WIDTH * 0.5, b - sp * FLARE_SPARK_WIDTH * 0.5, tip]),
				PackedColorArray([Color(1.0, 0.85, 0.5, br), Color(1.0, 0.85, 0.5, br), Color(sc.r, sc.g, sc.b, 0.0)]))
		# Blinding hot center (jitters per frame).
		var csz := flare_center_size * FLARE_BURST_SIZE_MULT
		draw_circle(b, csz * randf_range(0.8, 1.2), Color(1.0, 1.0, 1.0, randf_range(0.7, 1.0)))
		draw_circle(b, csz * 0.45, Color(1.0, 1.0, 1.0, 1.0))
