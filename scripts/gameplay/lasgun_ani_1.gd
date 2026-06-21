extends Node2D
## lasgun_ani_1 — BACKUP COPY of the clean sprite 3-slice Lasgun beam (the pre-flipbook lasgun_ani_3).
## Saved verbatim as the "known-good" beam so the flipbook experiment in lasgun_ani_4 can be reverted to
## this at any time. Same set_beam/fire/release contract — drop-in via a one-line preload in arena_weapons.gd.
##
## SPRITE-BASED 3-slice beam from hand-drawn art (body + muzzle cap + impact cap), animated with cheap
## scroll/pulse/flicker/wobble/packet tricks so the static textures read as a living, flowing beam.
## World-space: from/to are global positions; this node sits at the arena origin (parent transform identity).

# ── ART ───────────────────────────────────────────────────────────────────────
const BODY_PATH   := "res://assets/beams/lasgun3/body.png"
const MUZZLE_PATH  := "res://assets/beams/lasgun3/muzzle_cap.png"   # single fallback cap
const IMPACT_PATH  := "res://assets/beams/lasgun3/impact_cap.png"
const MUZZLE_FRAMES_DIR := "res://assets/beams/lasgun3/muzzle/"   # 12 pre-aligned variation frames (muzzle_00..11.png)
const MZ_FRAMES := 12
const IMPACT_FRAMES_DIR := "res://assets/beam references/Sprit_sheet_lasgun_impact/"   # 12 aligned impact frames (impact_00..11.png), 388×366, anchor at the hit point
const IMPACT_FRAMES := 12

enum BodyFill { TILE, STRETCH }

# ── TUNABLES (Stage 1) ──────────────────────────────────────────────────────────
@export var beam_thickness  := 120.0   # on-screen height of the body art (full glow, px)
@export var start_cap_len   := 150.0   # muzzle STAMP draw size (px). Sprite size only — reserves NO beam length.
@export var impact_cap_len  := 170.0   # impact STAMP draw size (px). Sprite size only — reserves NO beam length.
# Muzzle convergence anchor. _from (= arena _muzzle() = ship + fwd*MUZZLE_OFFSET) already EQUALS the gatling
# midpoint (base = ship + fwd*GAT_WING_FWD), because MUZZLE_OFFSET == GAT_WING_FWD == 22 in arena_weapons.gd.
# So the convergence sits between the two wing muzzles at (0,0) local by default.
@export var muzzle_fwd      := 45     # along-axis nudge of the convergence from _from, toward the firing direction
@export var muzzle_perp     := 0.0     # perpendicular nudge (0 = on-axis, between the two wing muzzles)
@export var muzzle_anchor_x := 0.436   # the convergence (pointy) point inside the muzzle art — fraction of width (from the aligned frames' anchor proof)
@export var muzzle_anchor_y := 0.503   # convergence point — fraction of height
@export var muzzle_fps      := 18.0    # flipbook speed cycling through the 12 muzzle variations (animated muzzle, in sync with the beam)
@export var body_overlap    := 24.0    # px the body begins BEHIND the convergence — a small COSMETIC tuck under the muzzle, NOT a length reservation
@export var body_fill_mode: BodyFill = BodyFill.TILE   # TILE (constant texel density) or STRETCH
@export var body_v_offset   := -10.0   # perpendicular shift of the BODY (negative = "up"); re-centres the art's slightly-low core onto the axis
@export var body_tail_fade    := 0.18  # fraction fallback (used only if body_tail_fade_px <= 0)
@export var body_tail_fade_px := 60.0  # CONSTANT tail-fade length (px) — the body's gun-end dissolves over this many px regardless of range, so the origin stays at the muzzle (no far-range gap)
@export var body_head_fade_px := 60.0  # CONSTANT head-fade length (px) — the body's impact-end tapers over this many px so it dissolves into the impact burst (0 = hard end)
@export var activation_in   := 0.05    # s to fade the beam in on fire
@export var activation_out  := 0.08    # s to fade out on release
# Per-piece tint (alpha is multiplied by the activation ramp each frame).
@export var body_modulate   := Color(1.0, 1.0, 1.0, 1.0)
@export var muzzle_modulate := Color(1.0, 1.0, 1.0, 1.0)
@export var impact_modulate := Color(1.0, 1.0, 1.0, 1.0)
# Impact-cap art is asymmetric (beam enters from the left, burst on the right). Anchor = where the burst
# sits inside the art, as fractions → drawn so the burst lands ON the hit point, beam-axis aligned (no spin).
@export var impact_anchor_x := 0.85   # forward edge of the burst → explosion sits ON/behind the obstacle (splashes back), not through it
@export var impact_anchor_y := 0.53   # burst's vertical centroid → beam axis runs through the core

# ── TUNABLES (Stage 2 — the "living" layer: scroll / parallax / breathe / flicker / wobble / packets) ──
@export_group("Living")
@export var scroll_speed     := 1000.0   # px/s the body texture scrolls toward impact (energy flow). +ve = toward impact
@export var layer2_enabled   := true    # second body copy at a different speed/scale → never-repeating complexity
@export var layer2_speed     := -120.0  # px/s of the 2nd copy (often opposite sign)
@export var layer2_scale     := 1.15    # different tile scale so the two never sync
@export var layer2_alpha     := 0.6     # 2nd copy alpha
@export var pulse_speed      := 6.0     # breathing pulse (width + brightness)
@export var pulse_width_amt  := 0.06    # thickness *= 1 + sin(t*pulse_speed)*this
@export var pulse_bright_amt := 0.10    # brightness pulse depth
@export var pulse_speed2     := 9.7     # 2nd desynced brightness pulse so it's not metronomic
@export var flicker_amt      := 0.06    # rapid small brightness jitter (the life signal)
@export var flicker_speed    := 55.0
@export var wobble_amt       := 3.0     # px lateral (perpendicular) sway of the body
@export var wobble_speed     := 2.0
@export var packet_enabled   := true    # bright packets racing down the beam
@export var packet_count     := 3
@export var packet_speed     := 2.5     # loops/sec along the beam
@export var packet_len       := 40.0    # dash length (px)
@export var packet_width     := 0.35    # fraction of (pulsed) beam thickness
@export var packet_color     := Color(1.0, 1.0, 1.0, 0.9)

# ── TUNABLES (Stage 3 — animated caps: muzzle fire-start punch + subtle pulse, impact spin/shimmer) ──
@export_group("Caps")
@export var cap_pulse_speed   := 7.0    # subtle continuous scale pulse on both caps
@export var cap_pulse_amt     := 0.05   # scale *= 1 + sin(t*cap_pulse_speed)*this
@export var birth_punch_mult  := 1.5    # muzzle scale at the fire-start edge (punches big, then settles)
@export var birth_punch_time  := 0.12   # s for the muzzle punch to settle back to 1
# ── TUNABLES (Stage 4 — Isaac model: body bears ALL length; muzzle+impact are length-independent stamps.
# Short range needs NO floor/fit/cap-subtraction — the stamps are pinned to the gun & hit point so they
# can't collide. The only short-range knob is an ALPHA-only fade of the body when it gets very short. ──
@export_group("Short range")
@export var span_full := 120.0   # body at full strength at/above this gun→hit distance (px)
@export var span_min  := 40.0    # body fully faded below this (only the muzzle + impact stamps remain) → fades only at true point-blank

# ── STATE ───────────────────────────────────────────────────────────────────────
var _body_tex: Texture2D = null
var _muzzle_tex: Texture2D = null
var _impact_tex: Texture2D = null
var _muzzle_frames: Array = []   # 12 AtlasTexture variation frames
var _impact_frames: Array = []   # 12 aligned impact frames (synced to the muzzle via _muzzle_idx)
var _packet_tex: Texture2D = null   # procedural soft radial glow for the traveling packets (built in _ready)
var _muzzle_idx := 0
var _muzzle_anim_t := 0.0
var _muzzle_birth_t := 999.0   # seconds since the fire-start edge (drives the muzzle scale-punch); large = settled
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _active := false
var _hit := false
var _was_active := false
var _t := 0.0
var _activation := 0.0   # 0..1 ramped envelope

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	_body_tex = _load_tex(BODY_PATH)
	_muzzle_tex = _load_tex(MUZZLE_PATH)
	_impact_tex = _load_tex(IMPACT_PATH)
	_load_muzzle_frames()
	_load_impact_frames()
	_packet_tex = _make_glow_tex(64)

## Build a soft radial-alpha glow: white core (alpha 1) fading smoothly to transparent at the rim (alpha 0).
## Drawn additively + stretched per packet, so the dash fades to nothing at every edge (no hard rectangle).
func _make_glow_tex(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			# Normalised distance from centre (0 at core → 1 at the inscribed rim).
			var d := Vector2(x - c, y - c).length() / c
			# Smooth falloff: bright plateau in the middle, alpha → 0 well before the corners.
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a   # quadratic → softer, glow-like edge
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## Load the 12 pre-aligned muzzle variation frames (already transparent; convergence at the same fraction in each).
func _load_muzzle_frames() -> void:
	for i in MZ_FRAMES:
		var tex := _load_tex("%smuzzle_%02d.png" % [MUZZLE_FRAMES_DIR, i])
		if tex != null:
			_muzzle_frames.append(tex)

## Load the 12 aligned impact frames (full frame — consistent canvas → anchor stays put). Synced to the muzzle.
func _load_impact_frames() -> void:
	for i in IMPACT_FRAMES:
		var tex := _load_tex("%simpact_%02d.png" % [IMPACT_FRAMES_DIR, i])
		if tex != null:
			_impact_frames.append(tex)

## CPU-side load (Image.load — no Godot-import dependency, works on dev F5). Falls back to load().
## Returns null on failure; _draw guards against null so a missing file never crashes.
func _load_tex(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	var t := load(path) as Texture2D
	if t == null:
		push_warning("lasgun_ani_1: could not load %s" % path)
	return t

# ── DRIVER CONTRACT (matches lasgun_ani_2) ──────────────────────────────────────
## Aim from→to, toggle on/off, flag a hit. Called every frame by arena_weapons.
func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
	if active and not _active:   # fire-start edge → restart the muzzle scale-punch
		_muzzle_birth_t = 0.0
	_was_active = _active
	_from = from
	_to = to
	_active = active
	_hit = hit
	queue_redraw()

## Alias for the spec's fire(origin, target) — continuous: call each frame to keep aiming.
func fire(origin: Vector2, target: Vector2) -> void:
	set_beam(origin, target, true, _hit)

## Stop firing; the beam fades out over activation_out seconds.
func release() -> void:
	_active = false

func _process(delta: float) -> void:
	_t += delta
	_muzzle_birth_t += delta
	var target := 1.0 if _active else 0.0
	var rate := (1.0 / maxf(0.001, activation_in)) if _active else (1.0 / maxf(0.001, activation_out))
	_activation = move_toward(_activation, target, rate * delta)
	# Cycle the muzzle variation flipbook while firing (animated muzzle, driven by the same _t as the beam).
	if _active and not _muzzle_frames.is_empty():
		_muzzle_anim_t += delta
		var spf := 1.0 / maxf(1.0, muzzle_fps)
		while _muzzle_anim_t >= spf:
			_muzzle_anim_t -= spf
			_muzzle_idx = (_muzzle_idx + 1) % MZ_FRAMES
	if _active or _activation > 0.0001:
		queue_redraw()

func _draw() -> void:
	if _activation <= 0.0001 or _body_tex == null:
		return
	var seg := _to - _from
	var L := seg.length()
	if L < 1.0:
		return
	var ang := seg.angle()
	# Work in beam-local space: +X = down-beam, +Y = perpendicular, origin at _from (= the gatling midpoint).
	draw_set_transform(_from, ang, Vector2.ONE)

	# ── Living modulators (Stage 2): breathe (width+brightness), flicker, wobble — all driven by _t ──
	var pulse_w := 1.0 + sin(_t * pulse_speed) * pulse_width_amt
	var pulse_b := 1.0 + (sin(_t * pulse_speed) + sin(_t * pulse_speed2)) * 0.5 * pulse_bright_amt
	var flick := 1.0 + (sin(_t * flicker_speed) * 0.6 + sin(_t * flicker_speed * 2.3) * 0.4) * flicker_amt
	var bright := maxf(0.0, pulse_b * flick)
	var thick := beam_thickness * pulse_w
	var center_y := body_v_offset + sin(_t * wobble_speed) * wobble_amt

	# Convergence point (the muzzle's pointy core) = the gatling midpoint, nudgeable.
	var conv := Vector2(muzzle_fwd, muzzle_perp)

	# ── Body bears ALL length (Isaac model): it stretches/tiles from the gun to the TRUE hit point. The
	# muzzle + impact are length-independent stamps pinned to the gun & hit, so they can never collide —
	# no floor, no fit-scaling, no cap-length subtraction. body_overlap is only a small cosmetic tuck. ──
	var x0 := conv.x - body_overlap
	var x1 := L
	# Alpha-only short-range fade: as the gun→hit span shrinks below span_full→span_min, fade the body out
	# so only the muzzle + impact stamps remain (they overlap harmlessly). NOT length math.
	var body_a := smoothstep(span_min, span_full, L - conv.x)
	# Symmetric end fades: the body ramps alpha 0→1 over `fade_len` from its tail (x0, gun end) AND
	# 1→0 over `head_len` into its head (x1, impact end) → dissolves into BOTH the muzzle and the impact burst.
	var fade_len := body_tail_fade_px if body_tail_fade_px > 0.0 else body_tail_fade * L
	var head_len := body_head_fade_px
	if body_a > 0.001 and x1 - x0 > 2.0:
		_draw_body_layer(x0, x1, center_y, thick, scroll_speed * _t, 1.0, _lit(body_modulate, bright, body_a), x0, fade_len, x1, head_len)
		if layer2_enabled:
			_draw_body_layer(x0, x1, center_y, thick, layer2_speed * _t, layer2_scale, _lit(body_modulate, bright, layer2_alpha * body_a), x0, fade_len, x1, head_len)

	# ── Traveling packets: soft additive glints racing convergence → impact ──
	# Stretched radial-glow texture (white core → transparent rim) so each packet fades to nothing at
	# every edge — no hard rectangle. Additive blend comes from the node material (BLEND_MODE_ADD).
	if packet_enabled and _packet_tex != null and L - conv.x > 4.0:
		var pcol := _lit(packet_color, bright, 1.0)
		var ph_h := maxf(1.0, thick * packet_width)   # cross-beam glow height (px)
		for i in maxi(1, packet_count):
			var ph := fposmod(_t * packet_speed + float(i) / float(maxi(1, packet_count)), 1.0)
			var px := lerpf(conv.x, L, ph)
			# Fade each glint in/out near the beam ends so packets don't pop at the muzzle/impact.
			var edge := minf(ph, 1.0 - ph) / 0.15
			var pc := Color(pcol.r, pcol.g, pcol.b, pcol.a * clampf(edge, 0.0, 1.0))
			draw_texture_rect(_packet_tex,
				Rect2(px - packet_len * 0.5, center_y - ph_h * 0.5, packet_len, ph_h), false, pc)

	# ── Muzzle (flipbook variation): fire-start scale-PUNCH + subtle pulse, anchored so convergence stays on `conv` ──
	var mtex: Texture2D = _muzzle_frames[_muzzle_idx] if not _muzzle_frames.is_empty() else _muzzle_tex
	if mtex != null:
		var fw := float(mtex.get_width())
		var fh := float(mtex.get_height())
		var mscale := _muzzle_birth_mult() * (1.0 + sin(_t * cap_pulse_speed) * cap_pulse_amt)
		var mh := start_cap_len * mscale                     # drawn height (px), authored stamp size
		var mw := start_cap_len * (fw / maxf(1.0, fh)) * mscale
		var tlx := conv.x - muzzle_anchor_x * mw             # anchor (frac) lands on conv at any scale
		var tly := conv.y - muzzle_anchor_y * mh
		draw_texture_rect(mtex, Rect2(tlx, tly, mw, mh), false, _lit(muzzle_modulate, bright, 1.0))

	# ── Impact cap (only on hit): animated flipbook SYNCED to the muzzle (shares _muzzle_idx), aligned to
	# the beam (NO spin) + scale pulse. Anchored so the art's hit point lands on _to. ──
	var itex: Texture2D = _impact_frames[_muzzle_idx % _impact_frames.size()] if not _impact_frames.is_empty() else _impact_tex
	if _hit and itex != null:
		var ifw := float(itex.get_width())
		var ifh := float(itex.get_height())
		var ipulse := 1.0 + sin(_t * cap_pulse_speed) * cap_pulse_amt   # authored stamp size (no fit)
		var ih := impact_cap_len * ipulse
		var iw := impact_cap_len * (ifw / maxf(1.0, ifh)) * ipulse
		draw_set_transform(_to, ang, Vector2.ONE)   # stamp on the TRUE hit point; rotation = beam angle
		draw_texture_rect(itex, Rect2(-impact_anchor_x * iw, -impact_anchor_y * ih, iw, ih), false, _lit(impact_modulate, bright, 1.0))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Piece colour: rgb scaled by `bright` (additive over-bright) + alpha = base.a * activation * alpha_mul.
func _lit(base: Color, bright: float, alpha_mul: float) -> Color:
	return Color(base.r * bright, base.g * bright, base.b * bright, base.a * _activation * alpha_mul)

## Draw one body layer across local-x [x0, x1] at vertical centre `center_y`, height `thick`, the texture
## SCROLLED by `scroll_px` (px toward impact) and tiled at native aspect × `tile_scale`. STRETCH fits once.
## The TAIL fades alpha 0→1 (quadratic) over `fade_len` px from `fade_x0` so the body dissolves into the muzzle.
func _draw_body_layer(x0: float, x1: float, center_y: float, thick: float, scroll_px: float, tile_scale: float, col: Color, fade_x0: float, fade_len: float, head_x1: float, head_len: float) -> void:
	var top := center_y - thick * 0.5
	var th := float(_body_tex.get_height())
	if body_fill_mode == BodyFill.STRETCH:
		_draw_seg_faded(x0, x1, 0.0, float(_body_tex.get_width()), top, thick, col, fade_x0, fade_len, head_x1, head_len)
		return
	var tw := float(_body_tex.get_width())
	var tile_w := beam_thickness * (tw / maxf(1.0, th)) * maxf(0.05, tile_scale)
	if tile_w < 1.0:
		return
	var off := fposmod(scroll_px, tile_w)        # +X shift (toward impact) as scroll_px grows
	var x := x0 - tile_w + off
	while x < x1:
		var sx0 := maxf(x, x0)
		var sx1 := minf(x + tile_w, x1)
		if sx1 > sx0:
			_draw_seg_faded(sx0, sx1, (sx0 - x) / tile_w * tw, (sx1 - x) / tile_w * tw, top, thick, col, fade_x0, fade_len, head_x1, head_len)
		x += tile_w

## Body alpha multiplier at local-x `x`: a tail ramp 0→1 over `fade_len` from `fade_x0` (gun end) × a head
## ramp 1→0 over `head_len` into `head_x1` (impact end). Either ramp is skipped when its length is <= 0.
func _body_alpha(x: float, fade_x0: float, fade_len: float, head_x1: float, head_len: float) -> float:
	var a := 1.0
	if fade_len > 0.0:
		a *= clampf((x - fade_x0) / fade_len, 0.0, 1.0)
	if head_len > 0.0:
		a *= clampf((head_x1 - x) / head_len, 0.0, 1.0)
	return a

## Draw one body segment [sx0,sx1] sampling src-u [su0,su1] (texture px) as smooth TEXTURED GRADIENT QUADS
## (per-vertex alpha → GPU-interpolated, no stair-steps). Split at the tail-fade-end and head-fade-start so
## the alpha is linear within each sub-quad; alpha at each break = `_body_alpha` (tapers at BOTH ends).
func _draw_seg_faded(sx0: float, sx1: float, su0: float, su1: float, top: float, thick: float, col: Color, fade_x0: float, fade_len: float, head_x1: float, head_len: float) -> void:
	var th := float(_body_tex.get_height())
	if fade_len <= 0.0 and head_len <= 0.0:
		draw_texture_rect_region(_body_tex, Rect2(sx0, top, sx1 - sx0, thick), Rect2(su0, 0.0, su1 - su0, th), col)
		return
	var span := sx1 - sx0
	if span <= 0.0:
		return
	# Break points where the alpha slope changes (only those strictly inside the segment), sorted.
	var bps: Array[float] = [sx0, sx1]
	var t_end := fade_x0 + fade_len
	var h_start := head_x1 - head_len
	if t_end > sx0 and t_end < sx1:
		bps.append(t_end)
	if h_start > sx0 and h_start < sx1:
		bps.append(h_start)
	bps.sort()
	for i in range(bps.size() - 1):
		var a: float = bps[i]
		var b: float = bps[i + 1]
		if b - a <= 0.01:
			continue
		var ua := lerpf(su0, su1, (a - sx0) / span)
		var ub := lerpf(su0, su1, (b - sx0) / span)
		var aa := _body_alpha(a, fade_x0, fade_len, head_x1, head_len)
		var ab := _body_alpha(b, fade_x0, fade_len, head_x1, head_len)
		_draw_body_quad(a, b, ua, ub, top, thick, col, aa, ab)

## A textured quad from x [xa,xb] sampling src-u [ua,ub] (texture px), with a smooth per-vertex alpha
## ramp aa→ab (full art height). draw_polygon interpolates the vertex colours per-pixel → no banding.
func _draw_body_quad(xa: float, xb: float, ua: float, ub: float, top: float, thick: float, col: Color, aa: float, ab: float) -> void:
	var tw := float(_body_tex.get_width())
	var pts := PackedVector2Array([
		Vector2(xa, top), Vector2(xb, top), Vector2(xb, top + thick), Vector2(xa, top + thick)])
	var uvs := PackedVector2Array([
		Vector2(ua / tw, 0.0), Vector2(ub / tw, 0.0), Vector2(ub / tw, 1.0), Vector2(ua / tw, 1.0)])
	var ca := Color(col.r, col.g, col.b, col.a * aa)
	var cb := Color(col.r, col.g, col.b, col.a * ab)
	draw_polygon(pts, PackedColorArray([ca, cb, cb, ca]), uvs, _body_tex)

## Muzzle scale at the fire-start edge: punches to birth_punch_mult, eases back to 1 over birth_punch_time.
func _muzzle_birth_mult() -> float:
	if _muzzle_birth_t >= birth_punch_time:
		return 1.0
	var r := _muzzle_birth_t / maxf(0.0001, birth_punch_time)   # 0..1
	return lerpf(birth_punch_mult, 1.0, r * r)                  # quadratic ease-out from the punch
