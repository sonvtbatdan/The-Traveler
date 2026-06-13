extends "res://scripts/gameplay/enemy_base.gd"

## Sentinel — spawns in a pair, descends from the top to 35% down the screen, then holds position and
## fires a wide spread fan once per second: SE_RAYS rays (each SE_RAY_SPREAD_DEG apart, centred on the
## player direction), each ray a line of SE_PER_RAY bullets. Bullets are non-tracking.

# ── Tunable constants (Sentinel) ──────────────────────────────────────────────
const SE_HP: float = 560.0   # 8× the original 70 (note: shape size scales with HP but is capped, so unchanged here)
const SE_XP: int = 14
const SE_COUNT: int = 2            # how many enter together per spawn
const SE_STOP_FRAC: float = 0.35   # descends to 35% down the screen…
const SE_STOP_NORTH_PX: float = 100.0   # …then shifted this many px up (north)
const SE_DESCEND_SPEED: float = 200.0
const SE_RAYS: int = 3             # rays per volley
const SE_PER_RAY: int = 5          # bullets per ray (a line)
const SE_RAY_SPREAD_DEG: float = 25.0   # angle between adjacent rays
const SE_FIRE_INTERVAL: float = 2.0     # one volley every 2s (half the old fire rate)
const SE_BULLET_DMG: int = 5
const SE_BULLET_SPEED: float = 160.0    # half the old bullet speed
const SE_BULLET_SPACING: float = 22.0   # px between the bullets within a ray

enum Phase { DESCEND, ENGAGE }
var _phase: int = Phase.DESCEND
var _stop_y: float = 0.0
var _fire_t: float = 0.0
# Per-instance fire-rate scaler (>1 = slower). Default 1.0 = unchanged; a choreography may raise it.
var fire_interval_mult: float = 1.0
# Vertical mirror (Enemy_group_1_inverse): when true the Sentinel enters from the BOTTOM and rises UP to a
# bottom-mirrored stop, and fires straight UP instead of DOWN. Default false → normal top-down behaviour.
## Set BEFORE spawn_at() (the manager's spawn_sentinel_at_inverted does this).
var flip_v: bool = false

func _configure() -> void:
	hp_max = SE_HP
	xp_reward = SE_XP
	contact_damage = 0
	contact_explodes = false
	body_color = Color(0.75, 0.45, 0.95)   # purple
	shape_kind = "diamond"

## Called by EnemyManager after add_child(): `index`/`count` spread the pair across the width.
func spawn(mgr: Node, index: int, count: int) -> void:
	var screen: Vector2 = mgr.screen_size()
	# Each sentinel pulls a fan-out lane so the pair (and successive sentinel waves) spread out.
	var x: float = mgr.take_lane_x()
	_stop_y = screen.y * SE_STOP_FRAC - SE_STOP_NORTH_PX
	position = Vector2(x - size.x * 0.5, -size.y)   # start just above the top edge
	_phase = Phase.DESCEND

## Choreography spawn: descend to the normal stationary row at an EXPLICIT column x (no fan-out lane).
## Used by Enemy_group_1, which then drives the U-path once is_engaged() is true.
func spawn_at(mgr: Node, x: float) -> void:
	var screen: Vector2 = mgr.screen_size()
	if flip_v:
		# Mirror: park in the LOWER band, starting just below the bottom edge (rises UP into place).
		_stop_y = screen.y - (screen.y * SE_STOP_FRAC - SE_STOP_NORTH_PX)
		position = Vector2(x - size.x * 0.5, screen.y + size.y)
	else:
		_stop_y = screen.y * SE_STOP_FRAC - SE_STOP_NORTH_PX
		position = Vector2(x - size.x * 0.5, -size.y)
	_phase = Phase.DESCEND

## Choreography spawn: descend from the top to an EXPLICIT parking point (x, stop_y) — both in
## SpaceScreen-local px. Used by Beginner_1 to place a Sentinel high (top-middle, a few cm down).
func spawn_at_pos(x: float, stop_y: float) -> void:
	_stop_y = stop_y
	position = Vector2(x - size.x * 0.5, -size.y)
	_phase = Phase.DESCEND

## True once it has finished descending and is holding/firing — i.e. parked at its stationary spot.
## A choreography may then move it freely (ENGAGE does not self-move; firing continues).
func is_engaged() -> bool:
	return _phase == Phase.ENGAGE

func _tick(delta: float) -> void:
	match _phase:
		Phase.DESCEND:
			# Normal: move down until reaching _stop_y. Flipped: move up until reaching the mirrored stop.
			var vdir := -1.0 if flip_v else 1.0
			position += Vector2(0.0, SE_DESCEND_SPEED * delta * vdir)
			var arrived: bool = center().y <= _stop_y if flip_v else center().y >= _stop_y
			if arrived:
				position = Vector2(position.x, _stop_y - size.y * 0.5)
				_phase = Phase.ENGAGE
				_fire_t = 0.0
		Phase.ENGAGE:
			var interval := SE_FIRE_INTERVAL * fire_interval_mult
			_fire_t += delta
			if _fire_t >= interval:
				_fire_t -= interval
				_fire_volley()

func _fire_volley() -> void:
	if _mgr == null or not _mgr.has_method("spawn_bullet"):
		return
	var muzzle := center()
	var aim := Vector2.UP if flip_v else Vector2.DOWN   # fire straight forward; UP when bottom-mirrored
	var half := float(SE_RAYS - 1) * 0.5
	for r in SE_RAYS:
		var ang := deg_to_rad(SE_RAY_SPREAD_DEG) * (float(r) - half)
		var rdir := aim.rotated(ang)
		for i in SE_PER_RAY:
			var pos := muzzle + rdir * (SE_BULLET_SPACING * float(i))
			_mgr.spawn_bullet(pos, rdir * SE_BULLET_SPEED, SE_BULLET_DMG)
