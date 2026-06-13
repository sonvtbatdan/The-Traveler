extends "res://scripts/gameplay/enemy_base.gd"

## Sentinel — spawns in a pair, descends from the top to 35% down the screen, then holds position and
## fires a wide spread fan once per second: SE_RAYS rays (each SE_RAY_SPREAD_DEG apart, centred on the
## player direction), each ray a line of SE_PER_RAY bullets. Bullets are non-tracking.

# ── Tunable constants (Sentinel) ──────────────────────────────────────────────
const SE_HP: float = 70.0
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

func _configure() -> void:
	hp_max = SE_HP
	xp_reward = SE_XP
	contact_damage = 0
	contact_explodes = false
	body_color = Color(0.75, 0.45, 0.95)   # purple
	shape_kind = "diamond"
	icon_path  = "res://assets/enemies/sentinel.png"

## Called by EnemyManager after add_child(): `index`/`count` spread the pair across the width.
func spawn(mgr: Node, index: int, count: int) -> void:
	var screen: Vector2 = mgr.screen_size()
	# Each sentinel pulls a fan-out lane so the pair (and successive sentinel waves) spread out.
	var x: float = mgr.take_lane_x()
	_stop_y = screen.y * SE_STOP_FRAC - SE_STOP_NORTH_PX
	position = Vector2(x - size.x * 0.5, -size.y)   # start just above the top edge
	_phase = Phase.DESCEND

func _tick(delta: float) -> void:
	match _phase:
		Phase.DESCEND:
			position += Vector2(0.0, SE_DESCEND_SPEED * delta)
			if center().y >= _stop_y:
				position = Vector2(position.x, _stop_y - size.y * 0.5)
				_phase = Phase.ENGAGE
				_fire_t = 0.0
		Phase.ENGAGE:
			_fire_t += delta
			if _fire_t >= SE_FIRE_INTERVAL:
				_fire_t -= SE_FIRE_INTERVAL
				_fire_volley()

func _fire_volley() -> void:
	if _mgr == null or not _mgr.has_method("spawn_bullet"):
		return
	var muzzle := center()
	var aim := Vector2.DOWN   # fire straight forward (down), not aimed at the player
	var half := float(SE_RAYS - 1) * 0.5
	for r in SE_RAYS:
		var ang := deg_to_rad(SE_RAY_SPREAD_DEG) * (float(r) - half)
		var rdir := aim.rotated(ang)
		for i in SE_PER_RAY:
			var pos := muzzle + rdir * (SE_BULLET_SPACING * float(i))
			_mgr.spawn_bullet(pos, rdir * SE_BULLET_SPEED, SE_BULLET_DMG)
