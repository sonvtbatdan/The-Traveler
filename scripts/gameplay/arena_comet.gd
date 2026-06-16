extends Node2D
## A comet — a bright icy core (white-blue, bloomed) plus a long glowing tail that fades and narrows to
## nothing. Additive blend. The tail points AWAY from the light/star (same light_dir convention as the
## planets), like a real solar-wind tail. Optional faint second (dust) tail at a slight angle. Slow drift.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const TAIL_LEN     := Vector2(120.0, 260.0)   # tail length px
const TAIL_WIDTH   := Vector2(10.0, 22.0)     # tail width at the core
const CORE_RADIUS  := Vector2(3.0, 6.0)       # icy core size px
const CORE_COLOR   := Color(0.85, 0.92, 1.0)  # white-blue
const TAIL_COLOR   := Color(0.55, 0.78, 1.0)  # white-blue -> faint cyan
const LIGHT_DIR    := Vector2(0.6, -0.5)      # tail blows opposite this
const SECOND_TAIL  := true                    # faint straight dust tail at a small angle
const DUST_ANGLE   := 12.0                     # degrees offset of the dust tail
const DRIFT_SPEED  := Vector2(4.0, 14.0)      # slow creep px/s

var _tail_dir := Vector2.UP
var _tail_len := 180.0
var _tail_w := 14.0
var _core_r := 4.0
var _drift := Vector2.ZERO

func setup(rng: RandomNumberGenerator) -> void:
	_tail_len = rng.randf_range(TAIL_LEN.x, TAIL_LEN.y)
	_tail_w = rng.randf_range(TAIL_WIDTH.x, TAIL_WIDTH.y)
	_core_r = rng.randf_range(CORE_RADIUS.x, CORE_RADIUS.y)
	_tail_dir = (-LIGHT_DIR).normalized()   # away from the star
	var ds := rng.randf_range(DRIFT_SPEED.x, DRIFT_SPEED.y)
	_drift = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * ds
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	queue_redraw()

func _process(delta: float) -> void:
	position += _drift * delta

func _draw() -> void:
	var dir := _tail_dir
	var perp := Vector2(-dir.y, dir.x)
	_draw_tail(dir, perp, _tail_len, _tail_w, TAIL_COLOR, 0.55)
	if SECOND_TAIL:
		var d2 := dir.rotated(deg_to_rad(DUST_ANGLE))
		var perp2 := Vector2(-d2.y, d2.x)
		_draw_tail(d2, perp2, _tail_len * 0.8, _tail_w * 0.6, Color(0.9, 0.85, 0.7), 0.22)
	# Core bloom: a few stacked additive discs (bright centre, soft halo).
	for i in 4:
		var rr := _core_r * (1.0 + float(i) * 0.9)
		var cc := CORE_COLOR
		cc.a = 0.55 / float(i + 1)
		draw_circle(Vector2.ZERO, rr, cc)

## A tapering tail quad: wide+bright at the core, narrow+transparent at the tip.
func _draw_tail(dir: Vector2, perp: Vector2, length: float, width: float, col: Color, a0: float) -> void:
	var tip := dir * length
	var c0 := col; c0.a = a0
	var c1 := col; c1.a = 0.0
	var pts := PackedVector2Array([
		-perp * width * 0.5,              # base left
		perp * width * 0.5,               # base right
		tip + perp * width * 0.1,         # tip right
		tip - perp * width * 0.1,         # tip left
	])
	draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
