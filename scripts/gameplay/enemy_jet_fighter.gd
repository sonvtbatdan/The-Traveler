extends "res://scripts/gameplay/enemy_base.gd"

## Jet_fighter — enters at a 45° angle into the top quarter of the screen, swoops ~1cm inward, then
## stops and holds position, firing non-tracking bullets at the player's position-at-the-moment once
## per second. Bullets are aimed once on launch and fly straight (dodge by moving after it fires).

# ── Tunable constants (Jet_fighter) ───────────────────────────────────────────
const JF_HP: float = 50.0
const JF_XP: int = 10
const JF_TOP_BAND: float = 0.25     # it enters/stops within the top 25% of the screen
const JF_ENTRY_CM: float = 1.0      # how far it travels inward before stopping (~1cm)
const JF_ENTRY_SPEED: float = 300.0 # px/s during the entry swoop
const JF_FIRE_INTERVAL: float = 1.0 # seconds between shots (fire rate 1/s)
const JF_BULLET_DMG: int = 5
const JF_BULLET_SPEED: float = 360.0

enum Phase { ENTER, ENGAGE }
var _phase: int = Phase.ENTER
var _dir: Vector2 = Vector2(1, 1).normalized()
var _stop: Vector2 = Vector2.ZERO
var _entry_remaining: float = 0.0
var _fire_t: float = 0.0

func _configure() -> void:
	hp_max = JF_HP
	xp_reward = JF_XP
	contact_damage = 0          # it shoots; no contact damage
	contact_explodes = false
	body_color = Color(0.4, 0.7, 1.0)   # blue jet
	shape_kind = "triangle"

## Called by EnemyManager after add_child(): pick a stop point in the top band + a 45° entry line.
func spawn(mgr: Node) -> void:
	var screen: Vector2 = mgr.screen_size()
	# Horizontal position comes from the manager's fan-out lanes (so jets don't stack); y stays random.
	_stop = Vector2(mgr.take_lane_x(), randf_range(screen.y * 0.06, screen.y * JF_TOP_BAND))
	var sx := -1.0 if randf() < 0.5 else 1.0
	_dir = Vector2(sx, 1.0).normalized()           # 45° downward, entering left- or right-ward
	var dist := cm_to_px(JF_ENTRY_CM)
	_entry_remaining = dist
	position = (_stop - _dir * dist) - size * 0.5  # start one entry-length back along the 45° line
	rotation = _dir.angle() + PI * 0.5             # face travel direction
	_phase = Phase.ENTER

func _tick(delta: float) -> void:
	match _phase:
		Phase.ENTER:
			var step := JF_ENTRY_SPEED * delta
			position += _dir * step
			_entry_remaining -= step
			if _entry_remaining <= 0.0:
				position = _stop - size * 0.5
				_phase = Phase.ENGAGE
				_fire_t = 0.0
		Phase.ENGAGE:
			var ship: Vector2 = _mgr.ship_center()
			rotation = (ship - center()).angle() + PI * 0.5   # aim at the player (cosmetic)
			_fire_t += delta
			if _fire_t >= JF_FIRE_INTERVAL:
				_fire_t -= JF_FIRE_INTERVAL
				_fire(ship)

func _fire(ship: Vector2) -> void:
	if _mgr == null or not _mgr.has_method("spawn_bullet"):
		return
	var muzzle := center()
	var dir := (ship - muzzle)
	if dir.length() < 0.01:
		return
	_mgr.spawn_bullet(muzzle, dir.normalized() * JF_BULLET_SPEED, JF_BULLET_DMG)
