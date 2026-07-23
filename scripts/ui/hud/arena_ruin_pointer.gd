extends Control
## Off-screen pointer to ONE giant dead-ship wreck: a chrome arrow pinned to the screen edge in the
## wreck's direction, spinning around its long axis, with the live distance printed beside it. Unlike
## arena_chest_pointer.gd (which finds its single target by group), this holds a direct reference to a
## specific wreck so several can coexist — arena_ruin_layer.gd spawns one per wreck. When its wreck is
## destroyed, the pointer frees itself (and its parent CanvasLayer). Modeled on arena_chest_pointer.gd.

const FONT        := preload("res://assets/fonts/Gameplay.ttf")
const EDGE_MARGIN := 74.0     # how far inside the screen edge the arrow sits
const ARROW_LEN   := 52.0
const ARROW_W     := 20.0     # max width when face-on
const SPIN_SPEED  := 6.0      # long-axis spin (rad/s)
const BASE_COL    := Color(0.52, 0.62, 0.74)   # cool steel (distinguishes from the warm chest arrow)
const LIT_COL     := Color(0.85, 0.94, 1.0)    # bright blue-white highlight (matches the orb of light)
const EDGE_COL    := Color(0.10, 0.12, 0.16, 0.9)

var _target: Node2D = null
var _player: Node2D = null
var _spin: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _show: bool = false
var _lbl: Label = null

## Point this arrow at a specific wreck node.
func setup(target: Node2D) -> void:
	_target = target

func _ready() -> void:
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl = Label.new()
	_lbl.add_theme_font_override("font", FONT)
	_lbl.add_theme_font_size_override("font_size", 16)
	_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_lbl.add_theme_constant_override("outline_size", 4)
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)

func _process(delta: float) -> void:
	_spin += delta * SPIN_SPEED
	# Wreck destroyed → its job is done; remove the pointer (and its dedicated CanvasLayer).
	if _target == null or not is_instance_valid(_target):
		var p := get_parent()
		if p is CanvasLayer:
			p.queue_free()
		else:
			queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_show = _player != null and is_instance_valid(_player)
	_lbl.visible = _show
	if _show:
		var vp := get_viewport_rect().size
		var center := vp * 0.5
		var target_screen := get_viewport().get_canvas_transform() * _target.global_position
		var d := target_screen - center
		_dir = d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		# Clamp the arrow to the screen edge (inset by EDGE_MARGIN) along the wreck's direction.
		var half := center - Vector2(EDGE_MARGIN, EDGE_MARGIN)
		var tx := (half.x / absf(_dir.x)) if absf(_dir.x) > 0.0001 else 1.0e9
		var ty := (half.y / absf(_dir.y)) if absf(_dir.y) > 0.0001 else 1.0e9
		_anchor = center + _dir * minf(tx, ty)
		var dist := int(round(_player.global_position.distance_to(_target.global_position)))
		_lbl.text = str(dist)
		_lbl.reset_size()
		_lbl.position = _anchor - _dir * (ARROW_LEN * 0.5 + 16.0) - _lbl.size * 0.5
	queue_redraw()

func _draw() -> void:
	if not _show:
		return
	var dir := _dir
	var perp := Vector2(-dir.y, dir.x)
	# Spin around the long axis: width pinches to a sliver edge-on, a bright highlight peaks face-on.
	var face := absf(cos(_spin))
	var w := ARROW_W * (0.20 + 0.80 * face)
	var sw := w * 0.5
	var a := _anchor
	var tip := a + dir * (ARROW_LEN * 0.5)
	var hb := tip - dir * (ARROW_LEN * 0.42)        # arrowhead base
	var tail := a - dir * (ARROW_LEN * 0.5)
	var body := BASE_COL.lerp(LIT_COL, 0.30 + 0.55 * face)
	draw_colored_polygon(PackedVector2Array([tail + perp * sw, hb + perp * sw, hb - perp * sw, tail - perp * sw]), body)
	draw_colored_polygon(PackedVector2Array([tip, hb + perp * w, hb - perp * w]), body)
	# Moving specular highlight down the centre line (brightest face-on).
	var hi := LIT_COL
	hi.a = pow(face, 1.5)
	draw_line(tail + dir * 3.0, tip - dir * 3.0, hi, maxf(1.5, w * 0.22), true)
	# Dark contour for contrast.
	draw_polyline(PackedVector2Array([tail + perp * sw, hb + perp * sw, tip, hb - perp * sw, tail - perp * sw, tail + perp * sw]), EDGE_COL, 1.5, true)
