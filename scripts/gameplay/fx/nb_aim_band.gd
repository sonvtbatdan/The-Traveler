extends Node2D
## Nautilus Move 1 telegraph — a red highlight BAND laid from the boss toward the player, marking the lane
## it is about to charge down. While it's aiming the band re-points at the player every frame; the instant
## the dash starts the caller stops updating it (`lock()`), so the band shows the committed lane the boss
## will actually travel, not where the player ran off to.
##
## World-space: parented to the arena root (NOT the boss) and given absolute from/to points every frame, the
## same reason arena_enemy.gd's LaserBeamScript is — a child of the boss would inherit its rotation/scale.
##
## NOTE: no class_name — preload + .new(), matching this folder's convention.

const COL_CORE  := Color(1.0, 0.30, 0.22, 0.55)   # centre stripe
const COL_EDGE  := Color(1.0, 0.10, 0.06, 0.0)    # feathered rim (alpha 0 → soft falloff)
const COL_LINE  := Color(1.0, 0.55, 0.45, 0.85)   # thin bright spine
const PULSE_HZ  := 3.2
const ARROW_GAP := 110.0    # px between the chevrons that run down the lane
const ARROW_LEN := 26.0
const ARROW_W   := 0.55     # half-angle of a chevron, radians

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _width: float = 90.0
var _t: float = 0.0
var _charge: float = 0.0   # 0..1 — fills as the charge completes; drives brightness + spine thickness

func begin(width_px: float) -> void:
	_width = maxf(24.0, width_px)
	z_index = 3     # under the boss body / bullets, over the terrain
	set_process(true)

## Absolute world endpoints, re-sent every frame while aiming. `charge01` drives the "about to go" ramp.
func aim(from: Vector2, to: Vector2, charge01: float) -> void:
	_from = from
	_to = to
	_charge = clampf(charge01, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var seg := _to - _from
	var len_px := seg.length()
	if len_px < 8.0:
		return
	var dir := seg / len_px
	var perp := Vector2(-dir.y, dir.x)
	# Breathe + brighten as the charge fills, so the last half-second reads as "NOW".
	var pulse := 0.75 + 0.25 * sin(_t * TAU * PULSE_HZ)
	var boost := 0.45 + 0.55 * _charge
	var half := _width * 0.5 * (0.85 + 0.15 * pulse)

	# Feathered band: a bright core quad plus two alpha-0 rim quads, so the lane fades out sideways instead
	# of ending on a hard line (draw_polygon with per-vertex colours = a free gradient, no shader needed).
	var core := COL_CORE
	core.a *= boost * pulse
	var edge := COL_EDGE
	_band(dir, perp, len_px, 0.0, half * 0.42, core, core)       # solid centre
	_band(dir, perp, len_px, half * 0.42, half, core, edge)      # falloff to the rim
	_band(dir, perp, len_px, -half, -half * 0.42, edge, core)

	# Thin bright spine down the middle.
	var line := COL_LINE
	line.a *= boost
	draw_line(_from, _to, line, maxf(1.5, 3.0 * boost), true)

	# Chevrons marching toward the target — reads as direction-of-travel at a glance.
	var scroll := fposmod(_t * 190.0, ARROW_GAP)
	var d := scroll
	while d < len_px:
		var p := _from + dir * d
		var a := line
		a.a *= 0.75
		draw_line(p, p - dir.rotated(ARROW_W) * ARROW_LEN, a, maxf(1.5, 2.5 * boost), true)
		draw_line(p, p - dir.rotated(-ARROW_W) * ARROW_LEN, a, maxf(1.5, 2.5 * boost), true)
		d += ARROW_GAP

## One quad spanning [off_a, off_b] sideways off the lane's centre line, colour-lerped across that span.
func _band(dir: Vector2, perp: Vector2, len_px: float, off_a: float, off_b: float, col_a: Color, col_b: Color) -> void:
	var pts := PackedVector2Array([
		_from + perp * off_a, _from + perp * off_b,
		_from + dir * len_px + perp * off_b, _from + dir * len_px + perp * off_a,
	])
	draw_polygon(pts, PackedColorArray([col_a, col_b, col_b, col_a]))
