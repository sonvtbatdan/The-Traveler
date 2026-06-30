extends Control
## Procedural player/boss vitals bar. A rounded TRAPEZOID that sits FLUSH on the screen edge (wider at the edge,
## narrowing toward the play area) like the cockpit bezels. The INNER box is the HP (green, fills left→right,
## reaching the flush edge); the SHIELD is an outer layer that HALF-WRAPS the inner side (the top, for the
## player) — a band hugging that side + the slanted sides, sharing the flush edge — filling left→right blue.
## `mode = "player"` → bottom, flush on the bottom edge. `mode = "boss"` → mirrored (wider at top), GONE when no
## boss, DROPS DOWN on spawn.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_H := 52.0
const BAR_W_FRAC := 0.5
const BAR_W_MIN := 480.0
const BAR_W_MAX := 900.0
const INNER_PAD := 6.0        # shield-wrap band thickness (inner HP box inset from the outer, on the wrap side)
const SLANT_FRAC := 0.55      # trapezoid side slant as a fraction of the height
const CORNER_R := 12.0        # rounded radius on the NARROW (inner-facing) edge corners only
const BOTTOM_MARGIN := 0.0    # player: flush on the bottom screen edge
const TOP_MARGIN := 16.0      # boss: rests just below the thin top XP bar (after the drop-down)
const DROP_TIME := 0.7
const HP_COL    := Color(0.30, 0.85, 0.45, 0.97)
const HP_LOW    := Color(0.90, 0.30, 0.25, 0.97)
const SHIELD_COL := Color(0.30, 0.62, 1.0, 0.95)
const TRACK_COL := Color(0.06, 0.07, 0.10, 0.92)
const INNER_TRACK := Color(0.09, 0.11, 0.15, 0.92)
const EDGE_COL  := Color(0.40, 0.55, 0.85, 0.95)
const EDGE_DIM  := Color(0.40, 0.55, 0.85, 0.5)

const FILL_LERP := 10.0       # fill smoothing rate (higher = snappier catch-up to the real value)
const FLASH_DUR := 0.28       # damage white-flash duration (s)
const LOW_HP_FRAC := 0.3      # below this HP fraction → the border pulses red

var mode: String = "player"
var _font: FontFile = null
var _boss_anim: float = 0.0
var _hp_disp: float = 1.0     # displayed HP fraction (lerps toward the real one)
var _sh_disp: float = 1.0     # displayed shield fraction
var _prev_hp: float = -1.0    # last frame's absolute HP/shield (to detect damage = a drop)
var _prev_sh: float = -1.0
var _hp_flash: float = 0.0    # HP damage-flash timer
var _sh_flash: float = 0.0    # shield damage-flash timer
var _t: float = 0.0           # clock for the low-HP pulse
var _cur: Dictionary = {}     # latest vitals snapshot (set in _process, read in _draw)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as FontFile

func _process(delta: float) -> void:
	_t += delta
	if mode == "boss":
		var active := GameManager.boss_max_hp > 0 and GameManager.boss_hp > 0
		if active:
			visible = true
			_boss_anim = minf(1.0, _boss_anim + delta / DROP_TIME)
		else:
			visible = false
			_boss_anim = 0.0
			_prev_hp = -1.0   # reset so the next boss doesn't flash on first appearance
			_prev_sh = -1.0
	var v := _vitals()
	_cur = v
	var hp_target := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var sh_target := clampf(float(v["sh"]) / float(v["sh_max"]), 0.0, 1.0) if float(v["sh_max"]) > 0.0 else 0.0
	# Damage = an absolute drop → trigger the white flash for that layer.
	if _prev_hp >= 0.0 and float(v["hp"]) < _prev_hp - 0.01:
		_hp_flash = FLASH_DUR
	if _prev_sh >= 0.0 and float(v["sh"]) < _prev_sh - 0.01:
		_sh_flash = FLASH_DUR
	_prev_hp = float(v["hp"])
	_prev_sh = float(v["sh"])
	# Smoothly catch the displayed fills up to their targets.
	var k := clampf(delta * FILL_LERP, 0.0, 1.0)
	_hp_disp = lerpf(_hp_disp, hp_target, k)
	_sh_disp = lerpf(_sh_disp, sh_target, k)
	_hp_flash = maxf(0.0, _hp_flash - delta)
	_sh_flash = maxf(0.0, _sh_flash - delta)
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
	var ox := o.x
	var oy := o.y
	var w := sz.x
	var h := sz.y
	var slant := minf(h * SLANT_FRAC, w * 0.25)
	var flip := mode == "boss"   # boss mirrors vertically (wide at the top edge)
	# Outer trapezoid corners + which corners get rounded (only the NARROW inner-facing edge).
	var outer_c: PackedVector2Array
	var inner_c: PackedVector2Array
	var flags: Array
	if not flip:
		# Player: wide BOTTOM (flush on screen bottom), narrow TOP; shield wraps the top.
		outer_c = PackedVector2Array([Vector2(ox + slant, oy), Vector2(ox + w - slant, oy), Vector2(ox + w, oy + h), Vector2(ox, oy + h)])
		inner_c = PackedVector2Array([Vector2(ox + slant + INNER_PAD, oy + INNER_PAD), Vector2(ox + w - slant - INNER_PAD, oy + INNER_PAD), Vector2(ox + w, oy + h), Vector2(ox, oy + h)])
		flags = [true, true, false, false]
	else:
		# Boss: wide TOP, narrow BOTTOM; shield wraps the bottom (mirror of the player).
		outer_c = PackedVector2Array([Vector2(ox, oy), Vector2(ox + w, oy), Vector2(ox + w - slant, oy + h), Vector2(ox + slant, oy + h)])
		inner_c = PackedVector2Array([Vector2(ox, oy), Vector2(ox + w, oy), Vector2(ox + w - slant - INNER_PAD, oy + h - INNER_PAD), Vector2(ox + slant + INNER_PAD, oy + h - INNER_PAD)])
		flags = [false, false, true, true]
	var outer := _round_poly(outer_c, CORNER_R, flags)
	var inner := _round_poly(inner_c, maxf(3.0, CORNER_R - INNER_PAD), flags)
	# Outer dark track → SHIELD blue fill (outer, L→R) → inner dark track (covers inner, leaving the wrap band)
	# → HP green fill (inner, L→R) → double outline.
	draw_colored_polygon(outer, TRACK_COL)
	var sh_max: float = v["sh_max"]
	var has_shield := sh_max > 0.0
	if has_shield and _sh_disp > 0.0:
		var sh_col := SHIELD_COL.lerp(Color.WHITE, (_sh_flash / FLASH_DUR) * 0.85)   # white-flash on shield damage
		draw_colored_polygon(_clip_x(outer, ox + w * _sh_disp), sh_col)
	draw_colored_polygon(inner, INNER_TRACK)
	var hf := _hp_disp
	var hp_col: Color = HP_COL if hf > LOW_HP_FRAC else HP_LOW
	hp_col = hp_col.lerp(Color.WHITE, (_hp_flash / FLASH_DUR) * 0.85)                 # white-flash on HP damage
	if hf > 0.0:
		draw_colored_polygon(_clip_x(inner, ox + w * hf), hp_col)
	var iol := inner.duplicate(); iol.append(inner[0])
	draw_polyline(iol, EDGE_DIM, 1.5, true)
	# Low-HP: pulse the outer border red.
	var edge := EDGE_COL
	if hf <= LOW_HP_FRAC:
		edge = EDGE_COL.lerp(Color(1.0, 0.2, 0.2), 0.5 + 0.5 * sin(_t * 8.0))
	var ol := outer.duplicate(); ol.append(outer[0])
	draw_polyline(ol, edge, 2.0, true)
	# Readouts.
	if _font != null:
		var hp_txt := "%d / %d" % [int(round(v["hp"])), int(v["hp_max"])]
		var hp_y := (oy + h * 0.62) if not flip else (oy + h * 0.46)
		draw_string(_font, Vector2(ox + slant + 14.0, hp_y), hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		if has_shield:
			var sh_txt := "%d / %d" % [int(round(v["sh"])), int(sh_max)]
			draw_string(_font, Vector2(ox + w - slant - 96.0, oy + h * 0.36), sh_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.93, 1.0))

## Round only the corners flagged true (the narrow inner-facing edge); flagged-false corners stay sharp so the
## wide edge sits flush on the screen edge.
func _round_poly(pts: PackedVector2Array, r: float, flags: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		if i >= flags.size() or not bool(flags[i]):
			out.append(pts[i])
			continue
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
