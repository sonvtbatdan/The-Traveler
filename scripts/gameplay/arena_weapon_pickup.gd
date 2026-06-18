extends Node2D
## A collectible weapon pickup (currently the Lasgun). Floats in place with a bob + pulsing glow so it reads
## as "grab me". Collected when the player flies within COLLECT_RANGE (its OWN fixed range — a weapon
## shouldn't magnetize across the screen like an XP orb). On collection it auto-equips the weapon by telling
## arena_weapons to activate it, pops, and frees. Gameplay plane (sharp, not blurred).

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SIZE          := 14.0                       # icon radius px
const GLOW          := 1.0                        # glow intensity
const COLLECT_RANGE := 46.0                        # fly within this to grab it
const BOB_AMP       := 4.0
const BOB_SPEED     := 2.2
const LAS_COLOR     := Color(1.0, 0.55, 0.22)      # lasgun warm-orange
const RING_COLOR    := Color(1.0, 0.8, 0.4)

var _kind: String = "lasgun"
var _t := 0.0
var _player: Node2D = null
var _popping := false
var _pop_t := 0.0

func setup(world_pos: Vector2, kind: String) -> void:
	global_position = world_pos
	_kind = kind
	_t = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	if _popping:
		_pop_t += delta
		queue_redraw()
		if _pop_t >= 0.25:
			queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and global_position.distance_to(_player.global_position) <= COLLECT_RANGE:
		_collect()
	queue_redraw()

func _collect() -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons != null and weapons.has_method("activate_lasgun"):
		weapons.activate_lasgun()
	_popping = true
	_pop_t = 0.0

func _draw() -> void:
	if _popping:
		var pt := clampf(_pop_t / 0.25, 0.0, 1.0)
		var r := SIZE * (1.0 + pt * 3.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, (1.0 - pt) * 0.8), 3.0)
		return
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.8 + 0.2 * sin(_t * BOB_SPEED * 1.6)
	# Glow halo.
	draw_circle(c, SIZE * 2.0 * pulse, Color(LAS_COLOR.r, LAS_COLOR.g, LAS_COLOR.b, 0.12 * GLOW))
	draw_circle(c, SIZE * 1.35 * pulse, Color(LAS_COLOR.r, LAS_COLOR.g, LAS_COLOR.b, 0.25 * GLOW))
	# Crate diamond.
	var d := SIZE
	var pts := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
	draw_colored_polygon(pts, Color(0.12, 0.10, 0.14, 0.9))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), RING_COLOR, 2.0)
	# Lasgun-flavoured emblem: a short bright beam streak across the crate.
	draw_line(c + Vector2(-d * 0.6, 0), c + Vector2(d * 0.6, 0), Color(LAS_COLOR.r, LAS_COLOR.g, LAS_COLOR.b, 0.9), 3.0 * pulse)
	draw_line(c + Vector2(-d * 0.6, 0), c + Vector2(d * 0.6, 0), Color(1, 1, 1, 0.9), 1.0)
