extends Node2D
## Gatling muzzle-fire FX (additive, gameplay-plane → sharp). Draws a small forward flame burst at each wing
## muzzle while firing: an orange flame cone + hot inner cone + white core + flickering streaks fanning
## forward. arena_weapons drives it each frame via set_state() (positions, aim dir, intensity, colors).

# ── TUNABLES (flame shape) ──────────────────────────────────────────────────────
const LEN        := 30.0   # flame length at full intensity (px)
const WIDTH      := 18.0   # flame base width
const STREAKS    := 5      # frayed streaks fanning forward
const STREAK_LEN := 30.0
const STREAK_SPREAD := 0.36

var _muzzles: Array = []   # [Vector2 world]
var _dir := Vector2.UP
var _intensity := 0.0
var _core := Color(1.0, 1.0, 0.85)
var _body := Color(1.0, 0.82, 0.25)
var _edge := Color(1.0, 0.5, 0.12)

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m

func set_state(muzzles: Array, dir: Vector2, intensity: float, core: Color, body: Color, edge: Color) -> void:
	_muzzles = muzzles
	_dir = dir
	_intensity = intensity
	_core = core
	_body = body
	_edge = edge
	queue_redraw()

func _draw() -> void:
	if _intensity <= 0.01 or _muzzles.is_empty():
		return
	var perp := Vector2(-_dir.y, _dir.x)
	for mp: Vector2 in _muzzles:
		_draw_flame(mp, perp)

func _draw_flame(o: Vector2, perp: Vector2) -> void:
	var k := _intensity
	var flick := k * randf_range(0.7, 1.0)
	var ln := LEN * k
	var hw := WIDTH * 0.5 * k
	# Orange flame cone (base at the muzzle → tip forward).
	draw_colored_polygon(PackedVector2Array([o - perp * hw, o + perp * hw, o + _dir * ln]),
		Color(_body.r, _body.g, _body.b, 0.55 * flick))
	# Brighter inner cone.
	draw_colored_polygon(PackedVector2Array([o - perp * hw * 0.5, o + perp * hw * 0.5, o + _dir * ln * 0.85]),
		Color(_core.r, _core.g, _core.b, 0.7 * flick))
	# White-hot core dot.
	draw_circle(o, hw * 0.6, Color(1.0, 1.0, 1.0, 0.85 * flick))
	# Frayed streaks fanning forward (flicker per frame).
	for i in STREAKS:
		var ang := _dir.angle() + randf_range(-STREAK_SPREAD, STREAK_SPREAD)
		var sl := STREAK_LEN * k * randf_range(0.4, 1.1)
		draw_line(o, o + Vector2.from_angle(ang) * sl, Color(_edge.r, _edge.g, _edge.b, randf_range(0.3, 0.7) * flick), 2.0)
