extends Control
## Procedural player/boss vitals bar — a rounded-corner TRAPEZOID styled like the side slot boxes (thin border,
## dark interior, double outline). The INSIDE box is the HP (green, fills left→right); the SHIELD is blue and
## covers only the TOP HALF of the trapezoid (fills left→right, overlaid on the HP). `mode = "player"` pins it
## bottom-center; `mode = "boss"` reads the boss (no shield), pins top-center, is GONE when no boss, and DROPS
## DOWN on spawn.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_H := 50.0           # bar height (px)
const BAR_W_FRAC := 0.5       # bar width as a fraction of the viewport
const BAR_W_MIN := 480.0
const BAR_W_MAX := 900.0
const INNER_PAD := 5.0        # inset of the inner HP box from the outer box (gives the double-outline look)
const SLANT_FRAC := 0.6       # trapezoid side slant as a fraction of the height (wider at the top)
const CORNER_R := 12.0        # rounded-corner radius
const BOTTOM_MARGIN := 14.0   # player: gap from the bottom edge
const TOP_MARGIN := 18.0      # boss: resting gap from the top edge (clears the thin top XP bar)
const DROP_TIME := 0.7        # boss bar drop-down duration (s)
const HP_COL    := Color(0.30, 0.85, 0.45, 0.97)
const HP_LOW    := Color(0.90, 0.30, 0.25, 0.97)
const SHIELD_COL := Color(0.30, 0.62, 1.0, 0.95)
const TRACK_COL := Color(0.06, 0.07, 0.10, 0.92)   # outer box interior (matches the side slot boxes)
const INNER_TRACK := Color(0.09, 0.11, 0.15, 0.92) # inner HP box empty track
const EDGE_COL  := Color(0.40, 0.55, 0.85, 0.95)   # outer border (same blue as the weapon slots)
const EDGE_DIM  := Color(0.40, 0.55, 0.85, 0.5)    # inner border (the second outline)

var mode: String = "player"
var _font: FontFile = null
var _boss_anim: float = 0.0   # boss drop-down progress 0 (hidden above) → 1 (fully dropped)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as FontFile

func _process(delta: float) -> void:
	if mode == "boss":
		var active := GameManager.boss_max_hp > 0 and GameManager.boss_hp > 0
		if active:
			visible = true
			_boss_anim = minf(1.0, _boss_anim + delta / DROP_TIME)
		else:
			visible = false           # completely gone when there is no boss
			_boss_anim = 0.0
	queue_redraw()

func _bar_size() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(clampf(vp.x * BAR_W_FRAC, BAR_W_MIN, BAR_W_MAX), BAR_H)

func _origin() -> Vector2:
	var vp := get_viewport_rect().size
	var sz := _bar_size()
	var x := (vp.x - sz.x) * 0.5
	if mode == "player":
		return Vector2(x, vp.y - sz.y - BOTTOM_MARGIN)
	var t := smoothstep(0.0, 1.0, _boss_anim)
	return Vector2(x, lerpf(-sz.y - 8.0, TOP_MARGIN, t))

func _vitals() -> Dictionary:
	if mode == "boss":
		var bmax := float(maxi(1, GameManager.boss_max_hp))
		return {"hp": float(GameManager.boss_hp), "hp_max": bmax, "sh": 0.0, "sh_max": 0.0}
	var hpmax := float(maxi(1, GameManager.ship_max_hp))
	var shmax: float = GameManager.shield_capacity_total() if GameManager.has_method("shield_capacity_total") else 0.0
	return {"hp": float(GameManager.ship_hp), "hp_max": hpmax, "sh": GameManager.ship_shield, "sh_max": shmax}

func _draw() -> void:
	if mode == "boss" and not visible:
		return
	var v := _vitals()
	var o := _origin()
	var sz := _bar_size()
	# Outer box (the trapezoid that looks like the side slot boxes).
	var box := Rect2(o, sz)
	var slant := minf(sz.y * SLANT_FRAC, sz.x * 0.25)
	var outer := _round_poly(_trapezoid(box, slant), CORNER_R)
	draw_colored_polygon(outer, TRACK_COL)
	# Inner HP box (inset → double-outline look). The INSIDE box is the HP (green, fills L→R).
	var ib := box.grow(-INNER_PAD)
	var islant := minf(ib.size.y * SLANT_FRAC, ib.size.x * 0.25)
	var inner_trap := _trapezoid(ib, islant)
	var inner := _round_poly(inner_trap, maxf(3.0, CORNER_R - INNER_PAD))
	draw_colored_polygon(inner, INNER_TRACK)
	var hf := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var hp_col: Color = HP_COL if hf > 0.3 else HP_LOW
	if hf > 0.0:
		draw_colored_polygon(_clip_x(inner, ib.position.x + ib.size.x * hf), hp_col)
	# SHIELD: blue, covers only the TOP HALF of the inner box, fills L→R (drawn over the HP).
	var sh_max: float = v["sh_max"]
	var has_shield := sh_max > 0.0
	if has_shield:
		var sf := clampf(float(v["sh"]) / sh_max, 0.0, 1.0)
		if sf > 0.0:
			var midy := ib.position.y + ib.size.y * 0.5
			var lx_mid := ib.position.x + islant * 0.5
			var rx_mid := ib.position.x + ib.size.x - islant * 0.5
			var sh_trap := PackedVector2Array([inner_trap[0], inner_trap[1], Vector2(rx_mid, midy), Vector2(lx_mid, midy)])
			var sh := _round_poly(sh_trap, maxf(3.0, CORNER_R - INNER_PAD))
			draw_colored_polygon(_clip_x(sh, ib.position.x + ib.size.x * sf), SHIELD_COL)
	# Double outline: inner (dim) then outer (bright) — matches the side slot boxes' framing.
	var iol := inner.duplicate(); iol.append(inner[0])
	draw_polyline(iol, EDGE_DIM, 1.5, true)
	var ol := outer.duplicate(); ol.append(outer[0])
	draw_polyline(ol, EDGE_COL, 2.0, true)
	# Readouts (HP in the lower band so the shield band stays clean).
	if _font != null:
		var hp_txt := "%d / %d" % [int(round(v["hp"])), int(v["hp_max"])]
		draw_string(_font, Vector2(o.x + slant + 12.0, o.y + sz.y * 0.82),
			hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		if has_shield:
			var sh_txt := "%d / %d" % [int(round(v["sh"])), int(sh_max)]
			draw_string(_font, Vector2(o.x + sz.x - slant - 96.0, o.y + sz.y * 0.40),
				sh_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.93, 1.0))

## Trapezoid corners (wider at the top): top edge full width, bottom edge inset by `slant` on each side.
func _trapezoid(box: Rect2, slant: float) -> PackedVector2Array:
	return PackedVector2Array([
		box.position,
		box.position + Vector2(box.size.x, 0.0),
		box.position + Vector2(box.size.x - slant, box.size.y),
		box.position + Vector2(slant, box.size.y),
	])

## Round each corner of a convex polygon with a small quadratic-bezier fillet (radius r).
func _round_poly(pts: PackedVector2Array, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var prev: Vector2 = pts[(i - 1 + n) % n]
		var cur: Vector2 = pts[i]
		var nxt: Vector2 = pts[(i + 1) % n]
		var din := cur - prev
		var dout := nxt - cur
		var ri := minf(r, minf(din.length(), dout.length()) * 0.45)
		var p0 := cur - din.normalized() * ri
		var p1 := cur + dout.normalized() * ri
		var steps := 4
		for s in steps + 1:
			var t := float(s) / float(steps)
			var u := 1.0 - t
			out.append(u * u * p0 + 2.0 * u * t * cur + t * t * p1)
	return out

## Sutherland–Hodgman clip of a convex polygon to the half-plane x ≤ x_cut (for the left→right fill).
func _clip_x(poly: PackedVector2Array, x_cut: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var a_in := a.x <= x_cut
		var b_in := b.x <= x_cut
		if a_in:
			out.append(a)
		if a_in != b_in and absf(b.x - a.x) > 0.0001:
			var t := (x_cut - a.x) / (b.x - a.x)
			out.append(Vector2(x_cut, a.y + (b.y - a.y) * t))
	return out
