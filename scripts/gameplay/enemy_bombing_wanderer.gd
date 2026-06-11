extends "res://scripts/gameplay/enemy_base.gd"

## Bombing_wanderer — enters from the left or right edge at 80% height (measured from the bottom),
## then drifts horizontally at BW_SPEED, BOUNCING back and forth between the side edges (it doesn't
## leave). It drops its first Bomb BW_BOMB_INTERVAL seconds after entering, then one more every
## BW_BOMB_INTERVAL. Bombs are a separate enemy (enemy_bomb.gd). The wanderer does no contact damage.

# ── Tunable constants (Bombing_wanderer) ──────────────────────────────────────
const BW_HP: float = 120.0
const BW_XP: int = 24
const BW_HEIGHT_FROM_BOTTOM: float = 0.80   # 80% up from the bottom → y = H * (1 - 0.80)
const BW_SPEED: float = 100.0               # drift speed (was 300; /3)
const BW_BOMB_INTERVAL: float = 3.0         # first drop 3s after entering, then every 3s

var _vel: Vector2 = Vector2.ZERO
var _drop_t: float = 0.0

func _configure() -> void:
	hp_max = BW_HP
	xp_reward = BW_XP
	contact_damage = 0
	contact_explodes = false
	body_color = Color(0.6, 0.15, 0.2)   # maroon
	shape_kind = "square"

func spawn(mgr: Node) -> void:
	var screen: Vector2 = mgr.screen_size()
	# Base height (80% up from bottom) + a small per-spawn vertical stagger so wanderers don't overlap.
	var y: float = screen.y * (1.0 - BW_HEIGHT_FROM_BOTTOM) + mgr.take_wanderer_y_offset()
	if randf() < 0.5:
		position = Vector2(0.0 - size.x * 0.5, y - size.y * 0.5)   # enter from the left, go right
		_vel = Vector2(BW_SPEED, 0.0)
	else:
		position = Vector2(screen.x - size.x * 0.5, y - size.y * 0.5)   # enter from the right, go left
		_vel = Vector2(-BW_SPEED, 0.0)
	_drop_t = 0.0   # first bomb drops BW_BOMB_INTERVAL after entering (no bomb on entry)

func _tick(delta: float) -> void:
	position += _vel * delta
	# Bounce between the side edges (stay fully on-screen).
	if _mgr != null:
		var screen: Vector2 = _mgr.screen_size()
		var left := size.x * 0.5
		var right := screen.x - size.x * 0.5
		var c := center()
		if c.x <= left and _vel.x < 0.0:
			_vel.x = absf(_vel.x)
			position = Vector2(left - size.x * 0.5, position.y)
		elif c.x >= right and _vel.x > 0.0:
			_vel.x = -absf(_vel.x)
			position = Vector2(right - size.x * 0.5, position.y)
	_drop_t += delta
	if _drop_t >= BW_BOMB_INTERVAL:
		_drop_t -= BW_BOMB_INTERVAL
		_drop_bomb()

func _drop_bomb() -> void:
	if _mgr != null and _mgr.has_method("spawn_bomb"):
		_mgr.spawn_bomb(center())
