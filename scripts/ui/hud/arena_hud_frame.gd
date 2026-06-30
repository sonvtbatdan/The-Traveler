extends Control
## Procedural cockpit-frame bezels: angled trapezoidal outlines hugging the four screen edges, leaving the
## centre open for gameplay. Pure decoration (drawn behind the HUD widgets). No art — swap to textures later
## by replacing _draw. Recomputes from the viewport size every frame so it tracks window resizes.

const LINE_COL := Color(0.32, 0.50, 0.78, 0.85)
const LINE_W := 2.0
const M := 6.0        # outer margin from the screen edge
const SIDE_INSET := 70.0   # how far the left/right bezels reach in from the edge at their widest
const SIDE_TOP := 0.22     # left/right bezel spans this fraction of the height (top..bottom)
const SIDE_BOT := 0.78
const TB_INSET := 70.0     # how far the top/bottom bezels reach in (vertically)
const TB_SIDE := 0.24      # top/bottom bezel spans this fraction of the width (left..right)
const CHAMFER := 48.0      # diagonal corner cut length

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	# Left bezel (vertical trapezoid open toward the centre).
	_poly([
		Vector2(M, vp.y * SIDE_TOP),
		Vector2(M + SIDE_INSET, vp.y * SIDE_TOP + CHAMFER),
		Vector2(M + SIDE_INSET, vp.y * SIDE_BOT - CHAMFER),
		Vector2(M, vp.y * SIDE_BOT),
	])
	# Right bezel (mirror).
	_poly([
		Vector2(vp.x - M, vp.y * SIDE_TOP),
		Vector2(vp.x - M - SIDE_INSET, vp.y * SIDE_TOP + CHAMFER),
		Vector2(vp.x - M - SIDE_INSET, vp.y * SIDE_BOT - CHAMFER),
		Vector2(vp.x - M, vp.y * SIDE_BOT),
	])
	# NOTE: top + bottom bezels are intentionally NOT drawn — those spots are the boss vitals bar (top,
	# drops down on spawn) and the player vitals bar (bottom). Drawing bezels there would double up.

func _poly(pts: Array) -> void:
	var pv := PackedVector2Array(pts)
	draw_polyline(pv, LINE_COL, LINE_W, true)
