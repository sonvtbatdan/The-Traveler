extends "res://scripts/gameplay/enemy_base.gd"

## Bombing_wanderer — enters from a side edge into the TOP THIRD of the map, then WANDERS in any
## direction at BW_SPEED, BOUNCING off the top / left / right edges and the 1/3 line (the "2-3 line": the
## top of the lower two-thirds). It drops a Bomb every BW_BOMB_INTERVAL. Bombs are a separate enemy
## (enemy_bomb.gd). The wanderer does no contact damage.

# ── Tunable constants (Bombing_wanderer) ──────────────────────────────────────
const BW_HP: float = 240.0                  # doubled (was 120)
const BW_XP: int = 24
const BW_BAND_FRAC: float = 1.0 / 3.0       # confined to the top third → bounces off y = H/3 (the "2-3 line")
const BW_SPEED: float = 100.0               # wander speed
const BW_BOMB_INTERVAL: float = 3.0         # first drop 3s after entering, then every 3s
const BW_ENTRY_SPREAD_DEG: float = 60.0     # initial inward heading varies ±this (so it wanders any direction)

var _vel: Vector2 = Vector2.ZERO
var _drop_t: float = 0.0

func _configure() -> void:
	_hp_mult = 1.0   # effective HP = BW_HP × 1.0 = 240 (PDF target)
	hp_max = BW_HP
	xp_reward = BW_XP
	contact_damage = 0
	contact_explodes = false
	body_color = Color(0.6, 0.15, 0.2)   # maroon
	shape_kind = "square"
	icon_path  = "res://assets/enemies/bombing.gif"

## `side` = "left" / "right" to force the entry edge (else random). Enters into the top third with a
## random inward 2D heading, then bounces around.
func spawn(mgr: Node, side: String = "") -> void:
	var screen: Vector2 = mgr.screen_size()
	var band: float = screen.y * BW_BAND_FRAC
	var y: float = randf_range(size.y, maxf(size.y, band - size.y))   # a y inside the top third
	var from_left: bool
	if side == "left":
		from_left = true
	elif side == "right":
		from_left = false
	else:
		from_left = randf() < 0.5
	var spread := deg_to_rad(BW_ENTRY_SPREAD_DEG)
	if from_left:
		position = Vector2(-size.x * 0.5, y - size.y * 0.5)
		_vel = Vector2.RIGHT.rotated(randf_range(-spread, spread)) * BW_SPEED
	else:
		position = Vector2(screen.x - size.x * 0.5, y - size.y * 0.5)
		_vel = Vector2.LEFT.rotated(randf_range(-spread, spread)) * BW_SPEED
	_drop_t = 0.0   # first bomb drops BW_BOMB_INTERVAL after entering (no bomb on entry)

func _tick(delta: float) -> void:
	position += _vel * delta
	# Bounce off the top third's walls: top / left / right edges + the y = H/3 "2-3 line".
	if _mgr != null:
		var screen: Vector2 = _mgr.screen_size()
		var left := size.x * 0.5
		var right := screen.x - size.x * 0.5
		var top := size.y * 0.5
		var bottom := screen.y * BW_BAND_FRAC   # the "2-3 line"
		var c := center()
		if c.x <= left and _vel.x < 0.0:
			_vel.x = absf(_vel.x)
			position = Vector2(left - size.x * 0.5, position.y)
		elif c.x >= right and _vel.x > 0.0:
			_vel.x = -absf(_vel.x)
			position = Vector2(right - size.x * 0.5, position.y)
		if c.y <= top and _vel.y < 0.0:
			_vel.y = absf(_vel.y)
			position = Vector2(position.x, top - size.y * 0.5)
		elif c.y >= bottom and _vel.y > 0.0:
			_vel.y = -absf(_vel.y)
			position = Vector2(position.x, bottom - size.y * 0.5)
	_drop_t += delta
	if _drop_t >= BW_BOMB_INTERVAL:
		_drop_t -= BW_BOMB_INTERVAL
		_drop_bomb()

func _drop_bomb() -> void:
	if _mgr != null and _mgr.has_method("spawn_bomb"):
		_mgr.spawn_bomb(_muzzle(0))
