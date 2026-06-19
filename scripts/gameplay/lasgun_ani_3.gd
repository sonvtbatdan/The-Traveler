extends Node2D
## lasgun_ani_3 — the ARENA Lasgun beam VFX, REBUILT as a SPRITE-BASED 3-slice beam from hand-drawn art
## (body + muzzle cap + impact cap), animated with cheap scroll/pulse/flicker/wobble/packet tricks so the
## static textures read as a living, flowing beam. Shares no code with ani_1 (immediate procedural) or
## ani_2 (quad+shader) — both kept as backups. Drop-in: same set_beam/fire/release contract, so
## arena_weapons.gd swaps it with a one-line preload change.
##
## World-space: from/to are global positions; this node sits at the arena origin (parent transform identity).
##
## ── STAGE 1 (this pass): STATIC 3-slice beam ──
##   Body tiled (or stretched) between two fixed-size additive caps; activation_in/out fade. No animation
##   yet — Stages 2–4 add the "living" scroll/pulse/flicker/wobble/packets + animated caps.

# ── ART ───────────────────────────────────────────────────────────────────────
const BODY_PATH   := "res://assets/beams/lasgun3/body.png"
const MUZZLE_PATH  := "res://assets/beams/lasgun3/muzzle_cap.png"   # single fallback cap
const IMPACT_PATH  := "res://assets/beams/lasgun3/impact_cap.png"
const MUZZLE_FRAMES_DIR := "res://assets/beams/lasgun3/muzzle/"   # 12 pre-aligned variation frames (muzzle_00..11.png)
const MZ_FRAMES := 12

enum BodyFill { TILE, STRETCH }

# ── TUNABLES (Stage 1) ──────────────────────────────────────────────────────────
@export var beam_thickness  := 120.0   # on-screen height of the body art (full glow, px)
@export var start_cap_len   := 150.0   # muzzle cap square side (px) — shrink if the burst is too big over the ship
@export var impact_cap_len  := 170.0   # impact cap square side (px)
# Muzzle convergence anchor. _from (= arena _muzzle() = ship + fwd*MUZZLE_OFFSET) already EQUALS the gatling
# midpoint (base = ship + fwd*GAT_WING_FWD), because MUZZLE_OFFSET == GAT_WING_FWD == 22 in arena_weapons.gd.
# So the convergence sits between the two wing muzzles at (0,0) local by default.
@export var muzzle_fwd      := 45     # along-axis nudge of the convergence from _from, toward the firing direction
@export var muzzle_perp     := 0.0     # perpendicular nudge (0 = on-axis, between the two wing muzzles)
@export var muzzle_anchor_x := 0.436   # the convergence (pointy) point inside the muzzle art — fraction of width (from the aligned frames' anchor proof)
@export var muzzle_anchor_y := 0.503   # convergence point — fraction of height
@export var muzzle_fps      := 18.0    # flipbook speed cycling through the 12 muzzle variations (animated muzzle, in sync with the beam)
@export var body_overlap    := 24.0    # px the body begins BEHIND the convergence so it tucks under the muzzle (seamless attach)
@export var beam_bwd        := 130.0    # px to pull the beam body BACKWARD toward the muzzle (increase overlap, close the gap)
@export var body_fill_mode: BodyFill = BodyFill.TILE   # TILE (constant texel density) or STRETCH
@export var body_v_offset   := -10.0   # perpendicular shift of the BODY (negative = "up"); re-centres the art's slightly-low core onto the axis
@export var body_tail_fade    := 0.18  # fraction of beam length the body's TAIL (gun end) fades IN over (quadratic) → dissolves into the muzzle, no seam
@export var body_tail_fade_px := 0.0   # absolute-px override (if > 0, used instead of the fraction → constant fade length at any beam length)
@export var activation_in   := 0.05    # s to fade the beam in on fire
@export var activation_out  := 0.08    # s to fade out on release
# Per-piece tint (alpha is multiplied by the activation ramp each frame).
@export var body_modulate   := Color(1.0, 1.0, 1.0, 1.0)
@export var muzzle_modulate := Color(1.0, 1.0, 1.0, 1.0)
@export var impact_modulate := Color(1.0, 1.0, 1.0, 1.0)

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

# ── STATE ───────────────────────────────────────────────────────────────────────
var _body_tex: Texture2D = null
var _muzzle_tex: Texture2D = null
var _impact_tex: Texture2D = null
var _muzzle_frames: Array = []   # 12 AtlasTexture variation frames
var _muzzle_idx := 0
var _muzzle_anim_t := 0.0
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

## Load the 12 pre-aligned muzzle variation frames (already transparent; convergence at the same fraction in each).
func _load_muzzle_frames() -> void:
	for i in MZ_FRAMES:
		var tex := _load_tex("%smuzzle_%02d.png" % [MUZZLE_FRAMES_DIR, i])
		if tex != null:
			_muzzle_frames.append(tex)

## CPU-side load (Image.load — no Godot-import dependency, works on dev F5). Falls back to load().
## Returns null on failure; _draw guards against null so a missing file never crashes.
func _load_tex(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	var t := load(path) as Texture2D
	if t == null:
		push_warning("lasgun_ani_3: could not load %s" % path)
	return t

# ── DRIVER CONTRACT (matches lasgun_ani_2) ──────────────────────────────────────
## Aim from→to, toggle on/off, flag a hit. Called every frame by arena_weapons.
func set_beam(from: Vector2, to: Vector2, active: bool, hit: bool) -> void:
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

	# ── Body: dual scrolling layers from just behind the convergence to the hit point ──
	# beam_bwd pulls the tail further back toward the muzzle to increase overlap / close any gap.
	var x0 := conv.x - body_overlap - beam_bwd
	var x1 := L
	# Quadratic tail fade: the body ramps alpha 0→1 over `fade_len` from its tail (x0) so it dissolves into the muzzle.
	var fade_len := body_tail_fade_px if body_tail_fade_px > 0.0 else body_tail_fade * L
	if x1 - x0 > 2.0:
		_draw_body_layer(x0, x1, center_y, thick, scroll_speed * _t, 1.0, _lit(body_modulate, bright, 1.0), x0, fade_len)
		if layer2_enabled:
			_draw_body_layer(x0, x1, center_y, thick, layer2_speed * _t, layer2_scale, _lit(body_modulate, bright, layer2_alpha), x0, fade_len)

	# ── Traveling packets: bright dashes racing convergence → impact ──
	if packet_enabled and L - conv.x > 4.0:
		var pcol := _lit(packet_color, bright, 1.0)
		for i in maxi(1, packet_count):
			var ph := fposmod(_t * packet_speed + float(i) / float(maxi(1, packet_count)), 1.0)
			var px := lerpf(conv.x, L, ph)
			draw_line(Vector2(px - packet_len * 0.5, center_y), Vector2(px + packet_len * 0.5, center_y),
				pcol, maxf(1.0, thick * packet_width))

	# ── Muzzle: current flipbook variation (or fallback), drawn at native aspect with its convergence on `conv` ──
	var mtex: Texture2D = _muzzle_frames[_muzzle_idx] if not _muzzle_frames.is_empty() else _muzzle_tex
	if mtex != null:
		var fw := float(mtex.get_width())
		var fh := float(mtex.get_height())
		var mh := start_cap_len                              # drawn height (px)
		var mw := start_cap_len * (fw / maxf(1.0, fh))       # preserve the frame's aspect
		var tlx := conv.x - muzzle_anchor_x * mw             # anchor (frac) lands on conv
		var tly := conv.y - muzzle_anchor_y * mh
		draw_texture_rect(mtex, Rect2(tlx, tly, mw, mh), false, _lit(muzzle_modulate, bright, 1.0))

	# ── Impact cap at the hit point (only when the beam actually hits), on the axis ──
	if _hit and _impact_tex != null:
		_draw_cap_at(_impact_tex, L, 0.0, impact_cap_len, _lit(impact_modulate, bright, 1.0))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Piece colour: rgb scaled by `bright` (additive over-bright) + alpha = base.a * activation * alpha_mul.
func _lit(base: Color, bright: float, alpha_mul: float) -> Color:
	return Color(base.r * bright, base.g * bright, base.b * bright, base.a * _activation * alpha_mul)

## Draw one body layer across local-x [x0, x1] at vertical centre `center_y`, height `thick`, the texture
## SCROLLED by `scroll_px` (px toward impact) and tiled at native aspect × `tile_scale`. STRETCH fits once.
## The TAIL fades alpha 0→1 (quadratic) over `fade_len` px from `fade_x0` so the body dissolves into the muzzle.
func _draw_body_layer(x0: float, x1: float, center_y: float, thick: float, scroll_px: float, tile_scale: float, col: Color, fade_x0: float, fade_len: float) -> void:
	var top := center_y - thick * 0.5
	var th := float(_body_tex.get_height())
	if body_fill_mode == BodyFill.STRETCH:
		_draw_seg_faded(x0, x1, 0.0, float(_body_tex.get_width()), top, thick, col, fade_x0, fade_len)
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
			_draw_seg_faded(sx0, sx1, (sx0 - x) / tile_w * tw, (sx1 - x) / tile_w * tw, top, thick, col, fade_x0, fade_len)
		x += tile_w

## Draw one body segment [sx0,sx1] sampling src-u [su0,su1] (texture px). Where the segment lies within the
## tail-fade band [fade_x0, fade_x0+fade_len], split it into thin strips and ramp alpha quadratically; the rest
## is drawn full-alpha in a single call (alpha-only fade → invisible dissolve under the additive muzzle).
func _draw_seg_faded(sx0: float, sx1: float, su0: float, su1: float, top: float, thick: float, col: Color, fade_x0: float, fade_len: float) -> void:
	var th := float(_body_tex.get_height())
	if fade_len <= 0.0:
		draw_texture_rect_region(_body_tex, Rect2(sx0, top, sx1 - sx0, thick), Rect2(su0, 0.0, su1 - su0, th), col)
		return
	var span := sx1 - sx0
	var fade_end := fade_x0 + fade_len
	var split := clampf(fade_end, sx0, sx1)   # boundary between the faded part and the full-alpha part
	# Faded part [sx0, split] — thin strips, quadratic alpha.
	if split > sx0:
		const STRIP := 14.0
		var x := sx0
		while x < split:
			var a := x
			var b := minf(x + STRIP, split)
			var sua := lerpf(su0, su1, (a - sx0) / span)
			var sub := lerpf(su0, su1, (b - sx0) / span)
			var r := clampf(((a + b) * 0.5 - fade_x0) / fade_len, 0.0, 1.0)
			var am := r * r
			draw_texture_rect_region(_body_tex, Rect2(a, top, b - a, thick), Rect2(sua, 0.0, sub - sua, th),
				Color(col.r, col.g, col.b, col.a * am))
			x += STRIP
	# Full-alpha part [split, sx1].
	if sx1 > split:
		var su_split := lerpf(su0, su1, (split - sx0) / span)
		draw_texture_rect_region(_body_tex, Rect2(split, top, sx1 - split, thick), Rect2(su_split, 0.0, su1 - su_split, th), col)

## Draw a square cap (side px) centred at local (cx, cy) — explicit centre so cap placement is
## independent of body_v_offset (lets the muzzle convergence anchor exactly on the gatling midpoint).
func _draw_cap_at(tex: Texture2D, cx: float, cy: float, side: float, col: Color) -> void:
	var half := side * 0.5
	draw_texture_rect(tex, Rect2(cx - half, cy - half, side, side), false, col)
