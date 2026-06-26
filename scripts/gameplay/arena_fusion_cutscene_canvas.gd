extends Control
## Draw layer for arena_fusion_cutscene.gd — renders the black hole (suction phase) and the nova ring (nova
## phase) in screen space. Reads the owning cutscene's elapsed time + centre each frame. Set via set_script on a
## full-rect Control child; `owner_cutscene` is assigned by the parent right after construction.

var owner_cutscene: Node = null

const SUCTION_T := 1.4
const NOVA_T    := 0.7

func _draw() -> void:
	if owner_cutscene == null:
		return
	var t: float = owner_cutscene.get("_t")
	var c: Vector2 = owner_cutscene.get("_center")

	if t < SUCTION_T:
		var u := clampf(t / SUCTION_T, 0.0, 1.0)
		_draw_black_hole(c, u)
	elif t < SUCTION_T + NOVA_T:
		var nu := clampf((t - SUCTION_T) / NOVA_T, 0.0, 1.0)
		_draw_nova(c, nu)

func _draw_black_hole(c: Vector2, u: float) -> void:
	var r := lerpf(8.0, 78.0, u * u)
	# Spinning accretion ring (gold → violet), drawn as overlapping arcs that thicken as the hole grows.
	var spin := u * TAU * 3.0
	for i in 5:
		var a0 := spin + TAU * float(i) / 5.0
		draw_arc(c, r + 10.0, a0, a0 + 0.9, 16, Color(1.0, 0.7, 0.2, 0.65 * u), 5.0, true)
		draw_arc(c, r + 20.0, -a0, -a0 + 0.7, 16, Color(0.7, 0.4, 1.0, 0.45 * u), 3.0, true)
	# Bright rim then the dark core (the "hole").
	draw_circle(c, r + 4.0, Color(1.0, 0.85, 0.4, 0.5 * u))
	draw_circle(c, r, Color(0.02, 0.0, 0.05, 0.95))
	draw_circle(c, r * 0.6, Color(0.0, 0.0, 0.0, 1.0))

func _draw_nova(c: Vector2, nu: float) -> void:
	var a := clampf(1.0 - nu, 0.0, 1.0)
	# Expanding bright ring.
	var rr := lerpf(20.0, 520.0, nu)
	draw_arc(c, rr, 0.0, TAU, 96, Color(1.0, 0.95, 0.7, 0.9 * a), 14.0, true)
	draw_arc(c, rr * 0.7, 0.0, TAU, 96, Color(1.0, 0.8, 0.4, 0.6 * a), 8.0, true)
	# Radial light spikes bursting outward.
	var spikes := 12
	for i in spikes:
		var ang := TAU * float(i) / float(spikes)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c, c + dir * rr * 1.05, Color(1.0, 0.9, 0.6, 0.7 * a), 3.0, true)
	# Hot core that contracts as the flash fades.
	draw_circle(c, lerpf(90.0, 24.0, nu), Color(1.0, 1.0, 0.95, 0.85 * a))
