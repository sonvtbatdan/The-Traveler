extends Control

const SCREEN_ORIGIN  := Vector2(15.0, 8.0)
const SCREEN_SIZE    := Vector2(955.0, 764.0)
const GRID_SPACING   := 50.0
const MAJOR_INTERVAL := 100.0  # thicker line every 100px

var show_grid:        bool    = false
var is_edit_open:     bool    = false
var fire_points:      Array   = []   # Array[Dictionary {pos:Vector2, id:int, dir_angle:float}]
var selected_fp_idx:  int     = -1
var thrust_points:    Array   = []   # Array[Dictionary {pos:Vector2, id:int, dir_angle:float}]
var selected_tp_idx:  int     = -1
var tentacle_points:   Array  = []   # Array[Dictionary {pos:Vector2, id:int, dir_angle:float}]
var selected_tenp_idx: int    = -1
var vortex_points:     Array  = []   # Array[Dictionary {pos:Vector2, id:int}] (directionless)
var selected_vortex_idx: int  = -1
var zoom:             float   = 1.0
var canvas_offset:    Vector2 = Vector2.ZERO

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_edit_open:
		return
	if show_grid:
		_draw_grid()
		_draw_mouse_coords()
	_draw_fire_points()
	_draw_thrust_points()
	_draw_tentacle_points()
	_draw_vortex_points()

# ── Grid ──────────────────────────────────────────────────────────────────────

func _to_vp(ss_pos: Vector2) -> Vector2:
	return canvas_offset + (ss_pos + SCREEN_ORIGIN) * zoom

func _draw_grid() -> void:
	var origin := canvas_offset + SCREEN_ORIGIN * zoom
	var end    := canvas_offset + (SCREEN_ORIGIN + SCREEN_SIZE) * zoom
	var spacing := GRID_SPACING * zoom
	var major_px := MAJOR_INTERVAL * zoom
	var minor  := Color(1.0, 1.0, 1.0, 0.18)
	var major  := Color(1.0, 1.0, 1.0, 0.42)
	var axis_x := Color(0.45, 1.0, 0.45, 0.70)
	var axis_y := Color(1.0, 0.45, 0.45, 0.70)

	# Vertical lines
	var x := origin.x
	while x <= end.x + 0.5:
		var rel := x - origin.x
		var col := major if fmod(rel, major_px) < 0.5 else minor
		draw_line(Vector2(x, origin.y), Vector2(x, end.y), col, 1.0)
		x += spacing

	# Horizontal lines
	var y := origin.y
	while y <= end.y + 0.5:
		var rel := y - origin.y
		var col := major if fmod(rel, major_px) < 0.5 else minor
		draw_line(Vector2(origin.x, y), Vector2(end.x, y), col, 1.0)
		y += spacing

	# Axis highlights
	draw_line(origin, Vector2(origin.x, end.y), axis_x, 2.0)
	draw_line(origin, Vector2(end.x, origin.y), axis_y, 2.0)

	# Coordinate labels every 100px (only when zoom >= 0.5 to avoid clutter)
	var lbl_col := Color(1.0, 1.0, 0.55, 0.88)
	x = origin.x
	var xi := 0
	while x <= end.x + 0.5:
		if xi % 100 == 0 and zoom >= 0.5:
			var shadow_off := Vector2(1.0, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, origin.y + 12) + shadow_off,
				str(xi), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.7))
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, origin.y + 12),
				str(xi), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lbl_col)
		x += spacing
		xi += int(GRID_SPACING)
	y = origin.y + spacing
	var yi := int(GRID_SPACING)
	while y <= end.y + 0.5:
		if yi % 100 == 0 and zoom >= 0.5:
			var shadow_off := Vector2(1.0, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(origin.x + 3, y - 1) + shadow_off,
				str(yi), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.7))
			draw_string(ThemeDB.fallback_font, Vector2(origin.x + 3, y - 1),
				str(yi), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lbl_col)
		y += spacing
		yi += int(GRID_SPACING)

# ── Mouse coordinates ─────────────────────────────────────────────────────────

func _draw_mouse_coords() -> void:
	var mp  := get_viewport().get_mouse_position()
	var c   := (mp - canvas_offset) / zoom - SCREEN_ORIGIN
	var txt := "(%d, %d)" % [int(c.x), int(c.y)]
	var off := Vector2(14.0, -10.0)
	draw_string(ThemeDB.fallback_font, mp + off + Vector2(1, 1), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.0, 0.0, 0.75))
	draw_string(ThemeDB.fallback_font, mp + off, txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 1.0, 0.5, 0.96))

# ── Fire point markers ────────────────────────────────────────────────────────

func _draw_fire_points() -> void:
	for i: int in fire_points.size():
		var fp:     Dictionary = fire_points[i]
		var vp_pos: Vector2    = _to_vp(fp["pos"] as Vector2)
		var is_sel: bool       = (i == selected_fp_idx)
		var col := Color(0.25, 0.85, 1.0, 0.95) if is_sel \
				 else Color(1.0, 0.55, 0.12, 0.90)
		# Crosshair
		draw_line(vp_pos + Vector2(-10, 0), vp_pos + Vector2(10, 0), col, 2.0)
		draw_line(vp_pos + Vector2(0, -10), vp_pos + Vector2(0, 10), col, 2.0)
		# Ring
		draw_arc(vp_pos, 5.5, 0.0, TAU, 20, col, 1.5)
		# Direction arrow
		var dir_angle: float = float(fp.get("dir_angle", 0.0))
		var dir_vec   := Vector2.RIGHT.rotated(dir_angle) * 32.0
		var tip       := vp_pos + dir_vec
		var arr_col   := Color(0.25, 1.0, 0.45, 0.95) if is_sel else Color(0.55, 1.0, 0.35, 0.80)
		draw_line(vp_pos, tip, arr_col, 2.0)
		var back := -dir_vec.normalized() * 7.0
		draw_line(tip, tip + back.rotated(0.5),  arr_col, 2.0)
		draw_line(tip, tip + back.rotated(-0.5), arr_col, 2.0)
		draw_string(ThemeDB.fallback_font, tip + Vector2(4.0, -2.0),
			"%d°" % int(round(rad_to_deg(dir_angle))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, arr_col)
		# Label with shadow
		var fp_id: int = fp.get("id", i + 1)
		var lbl_pos := vp_pos + Vector2(10.0, -3.0)
		draw_string(ThemeDB.fallback_font, lbl_pos + Vector2(1, 1),
			"FP%d" % fp_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, lbl_pos,
			"FP%d" % fp_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

# ── Thrust point markers ──────────────────────────────────────────────────────

func _draw_thrust_points() -> void:
	for i: int in thrust_points.size():
		var tp:     Dictionary = thrust_points[i]
		var vp_pos: Vector2    = _to_vp(tp["pos"] as Vector2)
		var is_sel: bool       = (i == selected_tp_idx)
		var col := Color(0.20, 1.0, 0.80, 0.95) if is_sel \
				 else Color(0.10, 0.75, 0.55, 0.90)
		# Diamond marker
		draw_line(vp_pos + Vector2(-8, 0),  vp_pos + Vector2(0, -8),  col, 2.0)
		draw_line(vp_pos + Vector2(0, -8),  vp_pos + Vector2(8, 0),   col, 2.0)
		draw_line(vp_pos + Vector2(8, 0),   vp_pos + Vector2(0, 8),   col, 2.0)
		draw_line(vp_pos + Vector2(0, 8),   vp_pos + Vector2(-8, 0),  col, 2.0)
		# Direction arrow
		var dir_angle: float = float(tp.get("dir_angle", 0.0))
		var dir_vec   := Vector2.RIGHT.rotated(dir_angle) * 32.0
		var tip       := vp_pos + dir_vec
		var arr_col   := Color(0.20, 1.0, 0.80, 0.95) if is_sel else Color(0.10, 0.90, 0.65, 0.80)
		draw_line(vp_pos, tip, arr_col, 2.0)
		var back := -dir_vec.normalized() * 7.0
		draw_line(tip, tip + back.rotated(0.5),  arr_col, 2.0)
		draw_line(tip, tip + back.rotated(-0.5), arr_col, 2.0)
		draw_string(ThemeDB.fallback_font, tip + Vector2(4.0, -2.0),
			"%d°" % int(round(rad_to_deg(dir_angle))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, arr_col)
		# Label with shadow
		var tp_id: int  = tp.get("id", i + 1)
		var lbl_pos := vp_pos + Vector2(10.0, -3.0)
		draw_string(ThemeDB.fallback_font, lbl_pos + Vector2(1, 1),
			"TP%d" % tp_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, lbl_pos,
			"TP%d" % tp_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

# ── Tentacle point markers ────────────────────────────────────────────────────

func _draw_tentacle_points() -> void:
	for i: int in tentacle_points.size():
		var tn:     Dictionary = tentacle_points[i]
		var vp_pos: Vector2    = _to_vp(tn["pos"] as Vector2)
		var is_sel: bool       = (i == selected_tenp_idx)
		var col := Color(0.95, 0.55, 1.0, 0.98) if is_sel \
				 else Color(0.70, 0.30, 0.95, 0.90)
		# Hexagon marker (distinct from FP crosshair / TP diamond)
		var pts := PackedVector2Array()
		for h in 6:
			pts.append(vp_pos + Vector2.RIGHT.rotated(TAU * float(h) / 6.0 + PI / 6.0) * 8.0)
		for h in 6:
			draw_line(pts[h], pts[(h + 1) % 6], col, 2.0)
		# Direction arrow — longer, since it shows the tentacle's outward direction
		var dir_angle: float = float(tn.get("dir_angle", 0.0))
		var dir_vec   := Vector2.RIGHT.rotated(dir_angle) * 42.0
		var tip       := vp_pos + dir_vec
		var arr_col   := Color(1.0, 0.65, 1.0, 0.98) if is_sel else Color(0.85, 0.45, 1.0, 0.85)
		draw_line(vp_pos, tip, arr_col, 2.5)
		var back := -dir_vec.normalized() * 9.0
		draw_line(tip, tip + back.rotated(0.5),  arr_col, 2.5)
		draw_line(tip, tip + back.rotated(-0.5), arr_col, 2.5)
		draw_string(ThemeDB.fallback_font, tip + Vector2(4.0, -2.0),
			"%d°" % int(round(rad_to_deg(dir_angle))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, arr_col)
		# Label with shadow
		var tn_id: int = tn.get("id", i + 1)
		var lbl_pos := vp_pos + Vector2(11.0, -3.0)
		draw_string(ThemeDB.fallback_font, lbl_pos + Vector2(1, 1),
			"Tn%d" % tn_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, lbl_pos,
			"Tn%d" % tn_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

# ── Vortex point markers (directionless — a small swirl glyph) ───────────────────

func _draw_vortex_points() -> void:
	for i: int in vortex_points.size():
		var vx:     Dictionary = vortex_points[i]
		var vp_pos: Vector2    = _to_vp(vx["pos"] as Vector2)
		var is_sel: bool       = (i == selected_vortex_idx)
		var col := Color(0.55, 0.85, 1.0, 0.98) if is_sel else Color(0.40, 0.65, 0.95, 0.90)
		# Two concentric swirl arcs to read as a vortex marker.
		draw_arc(vp_pos, 9.0, 0.4, 0.4 + TAU * 0.75, 18, col, 2.0)
		draw_arc(vp_pos, 5.0, 3.5, 3.5 + TAU * 0.75, 14, col, 2.0)
		draw_circle(vp_pos, 2.0, col)
		var vx_id: int = vx.get("id", i + 1)
		var lbl_pos := vp_pos + Vector2(11.0, -3.0)
		draw_string(ThemeDB.fallback_font, lbl_pos + Vector2(1, 1),
			"Vx%d" % vx_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, lbl_pos,
			"Vx%d" % vx_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
