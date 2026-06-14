extends Control

const SCREEN_ORIGIN  := Vector2(15.0, 8.0)
const SCREEN_SIZE    := Vector2(955.0, 764.0)
const GRID_SPACING   := 50.0
const MAJOR_INTERVAL := 100.0  # thicker line every 100px

var show_grid:        bool  = false
var is_edit_open:     bool  = false
var fire_points:      Array = []   # Array[Dictionary {pos:Vector2, id:int}]
var selected_fp_idx:  int   = -1

func _process(_delta: float) -> void:
	if is_edit_open:
		queue_redraw()

func _draw() -> void:
	if not is_edit_open:
		return
	if show_grid:
		_draw_grid()
		_draw_mouse_coords()
	_draw_fire_points()

# ── Grid ──────────────────────────────────────────────────────────────────────

func _draw_grid() -> void:
	var origin := SCREEN_ORIGIN
	var end    := SCREEN_ORIGIN + SCREEN_SIZE
	var minor  := Color(1.0, 1.0, 1.0, 0.18)
	var major  := Color(1.0, 1.0, 1.0, 0.42)
	var axis_x := Color(0.45, 1.0, 0.45, 0.70)
	var axis_y := Color(1.0, 0.45, 0.45, 0.70)

	# Vertical lines
	var x := origin.x
	while x <= end.x + 0.5:
		var rel := x - origin.x
		var col := major if fmod(rel, MAJOR_INTERVAL) < 0.5 else minor
		draw_line(Vector2(x, origin.y), Vector2(x, end.y), col, 1.0)
		x += GRID_SPACING

	# Horizontal lines
	var y := origin.y
	while y <= end.y + 0.5:
		var rel := y - origin.y
		var col := major if fmod(rel, MAJOR_INTERVAL) < 0.5 else minor
		draw_line(Vector2(origin.x, y), Vector2(end.x, y), col, 1.0)
		y += GRID_SPACING

	# Axis highlights (X=0 vertical, Y=0 horizontal)
	draw_line(origin, Vector2(origin.x, end.y), axis_x, 2.0)
	draw_line(origin, Vector2(end.x, origin.y), axis_y, 2.0)

	# Coordinate labels every 100px
	var lbl_col := Color(1.0, 1.0, 0.55, 0.88)
	x = origin.x
	while x <= end.x + 0.5:
		var cx := int(x - origin.x)
		if cx % 100 == 0:
			var shadow_off := Vector2(1.0, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, origin.y + 12) + shadow_off,
				str(cx), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.7))
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, origin.y + 12),
				str(cx), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lbl_col)
		x += GRID_SPACING
	y = origin.y + MAJOR_INTERVAL
	while y <= end.y + 0.5:
		var cy := int(y - origin.y)
		if cy % 100 == 0:
			var shadow_off := Vector2(1.0, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(origin.x + 3, y - 1) + shadow_off,
				str(cy), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.7))
			draw_string(ThemeDB.fallback_font, Vector2(origin.x + 3, y - 1),
				str(cy), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lbl_col)
		y += GRID_SPACING

# ── Mouse coordinates ─────────────────────────────────────────────────────────

func _draw_mouse_coords() -> void:
	var mp  := get_viewport().get_mouse_position()
	var c   := mp - SCREEN_ORIGIN
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
		var vp_pos: Vector2    = (fp["pos"] as Vector2) + SCREEN_ORIGIN
		var is_sel: bool       = (i == selected_fp_idx)
		var col := Color(0.25, 0.85, 1.0, 0.95) if is_sel \
				 else Color(1.0, 0.55, 0.12, 0.90)
		# Crosshair
		draw_line(vp_pos + Vector2(-10, 0), vp_pos + Vector2(10, 0), col, 2.0)
		draw_line(vp_pos + Vector2(0, -10), vp_pos + Vector2(0, 10), col, 2.0)
		# Ring
		draw_arc(vp_pos, 5.5, 0.0, TAU, 20, col, 1.5)
		# Label with shadow
		var fp_id: int = fp.get("id", i + 1)
		var lbl_pos := vp_pos + Vector2(10.0, -3.0)
		draw_string(ThemeDB.fallback_font, lbl_pos + Vector2(1, 1),
			"FP%d" % fp_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, lbl_pos,
			"FP%d" % fp_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
