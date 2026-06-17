extends Node2D
## A collectible XP orb dropped by a dying enemy. Sits and gently bobs until the player comes within their
## pickup radius (GameManager.get_pickup_radius() — widened by the Magnet upgrade), then magnetizes toward the
## player, accelerating as it closes. On reaching the player it grants its XP (GameManager.add_xp) and pops.
## Lives on the gameplay plane (sharp, not blurred). Persists until collected (survival-friendly).

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const ORB_SIZE       := 5.0          # drawn core radius px
const COLLECT_RADIUS := 16.0         # distance to the player at which it's collected
const MAGNET_SPEED   := 120.0        # starting fly speed once magnetized (px/s)
const MAGNET_ACCEL   := 900.0        # acceleration toward the player while magnetized (px/s²)
const MAGNET_MAX     := 1400.0       # speed cap (px/s)
const BOB_AMP        := 2.5          # idle bob amplitude px
const BOB_SPEED      := 3.0          # idle bob rad/s
const CORE_COLOR     := Color(0.45, 1.0, 0.7)   # XP green-cyan
const GLOW_COLOR     := Color(0.30, 0.95, 0.85)

var _value: int = 1
var _vel := Vector2.ZERO
var _magnetized := false
var _t := 0.0
var _player: Node2D = null

func setup(world_pos: Vector2, value: int) -> void:
	global_position = world_pos
	_value = value
	_t = randf() * TAU   # desync the bob so a cluster doesn't pulse in lockstep

func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			queue_redraw()
			return
	var to := _player.global_position - global_position
	var d := to.length()
	var radius: float = GameManager.get_pickup_radius() if GameManager.has_method("get_pickup_radius") else 90.0
	if _magnetized or d <= radius:
		_magnetized = true   # once caught, stays caught even if the player dashes briefly out of range
		var dir := to / maxf(d, 0.001)
		var spd := maxf(_vel.length(), MAGNET_SPEED) + MAGNET_ACCEL * delta
		_vel = dir * minf(spd, MAGNET_MAX)
		global_position += _vel * delta
		if d <= COLLECT_RADIUS:
			_collect()
			return
	queue_redraw()

func _collect() -> void:
	if GameManager.has_method("add_xp"):
		GameManager.add_xp(_value)
	queue_free()

func _draw() -> void:
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.85 + 0.15 * sin(_t * BOB_SPEED * 1.7)
	# Soft outer glow → bright core → white centre.
	draw_circle(c, ORB_SIZE * 2.4 * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.18))
	draw_circle(c, ORB_SIZE * 1.5 * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.35))
	draw_circle(c, ORB_SIZE * pulse, CORE_COLOR)
	draw_circle(c, ORB_SIZE * 0.45, Color(1, 1, 1, 0.9))
