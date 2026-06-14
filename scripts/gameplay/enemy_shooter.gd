extends "res://scripts/gameplay/enemy_base.gd"

## Shooter — enters at a 45° angle into the top quarter of the screen, swoops ~1cm inward, then
## stops and holds position, firing non-tracking bullets at the player's position-at-the-moment once
## per second. Bullets are aimed once on launch and fly straight (dodge by moving after it fires).

# ── Tunable constants (Shooter) ───────────────────────────────────────────
const SH_HP: float = 50.0
const SH_XP: int = 10
const SH_TOP_BAND: float = 0.25     # it enters/stops within the top 25% of the screen
const SH_ENTRY_CM: float = 1.0      # how far it travels inward before stopping (~1cm)
const SH_ENTRY_SPEED: float = 300.0 # px/s during the entry swoop
const SH_FIRE_INTERVAL: float = 1.0 # seconds between shots (fire rate 1/s)
const SH_BULLET_DMG: int = 5
const SH_BULLET_SPEED: float = 160.0   # matched to the Sentinel's SE_BULLET_SPEED
const SH_TURN_RATE: float = 6.0     # how fast it rotates to face the player (lower = smoother/slower turn)

enum Phase { ENTER, ENGAGE }
var _phase: int = Phase.ENTER
var _dir: Vector2 = Vector2(1, 1).normalized()
var _stop: Vector2 = Vector2.ZERO
var _entry_remaining: float = 0.0
var _fire_t: float = 0.0
# When true, a choreography drives this shooter's POSITION; self-movement is suppressed but its normal
# firing continues. Combat is unchanged — only the scripted movement differs.
var external_control: bool = false
# Per-instance fire-rate scaler (>1 = slower). Default 1.0 = unchanged; a choreography may raise it.
var fire_interval_mult: float = 1.0
# Gate firing on/off (default on). A choreography sets this false to hold fire while it flies the shooter
# into position, then true once parked (so it forms up THEN shoots). Combat is otherwise unchanged.
var fire_enabled: bool = true

func _configure() -> void:
	hp_max = SH_HP
	xp_reward = SH_XP
	contact_damage = 0          # it shoots; no contact damage
	contact_explodes = false
	icon_path = "res://assets/enemies/jetfighter.png"

## Called by EnemyManager after add_child(): pick a stop point in the top band + a 45° entry line.
func spawn(mgr: Node) -> void:
	var screen: Vector2 = mgr.screen_size()
	# Horizontal position comes from the manager's fan-out lanes (so jets don't stack); y stays random.
	_stop = Vector2(mgr.take_lane_x(), randf_range(screen.y * 0.06, screen.y * SH_TOP_BAND))
	var sx := -1.0 if randf() < 0.5 else 1.0
	_dir = Vector2(sx, 1.0).normalized()           # 45° downward, entering left- or right-ward
	var dist := cm_to_px(SH_ENTRY_CM)
	_entry_remaining = dist
	position = (_stop - _dir * dist) - size * 0.5  # start one entry-length back along the 45° line
	rotation = _dir.angle() + PI * 0.5             # face travel direction
	_phase = Phase.ENTER

## Choreography spawn: appear at `center_pos` under external movement control, firing immediately. The
## choreography moves it each frame (slide-in + drift); its self-movement entry is skipped.
func spawn_external(mgr: Node, center_pos: Vector2) -> void:
	external_control = true
	position = center_pos - size * 0.5
	_phase = Phase.ENGAGE
	_fire_t = 0.0

func _tick(delta: float) -> void:
	if external_control:
		_tick_fire(delta)   # position is driven by the choreography; just keep shooting normally
		return
	match _phase:
		Phase.ENTER:
			var step := SH_ENTRY_SPEED * delta
			position += _dir * step
			_entry_remaining -= step
			if _entry_remaining <= 0.0:
				position = _stop - size * 0.5
				_phase = Phase.ENGAGE
				_fire_t = 0.0
		Phase.ENGAGE:
			_tick_fire(delta)

func _tick_fire(delta: float) -> void:
	if not fire_enabled:
		return   # held by a choreography until it reaches its position
	if _mgr == null or not is_instance_valid(_mgr):
		return
	var ship: Vector2 = _mgr.ship_center()
	# Ease the facing toward the player instead of snapping (avoids a jerk when it starts aiming after a
	# scripted fly-in). Bullets aim independently in _fire(), so this is purely the visual turn.
	var target_rot := (ship - center()).angle() + PI * 0.5
	rotation = lerp_angle(rotation, target_rot, clampf(SH_TURN_RATE * delta, 0.0, 1.0))
	var interval := SH_FIRE_INTERVAL * fire_interval_mult
	_fire_t += delta
	if _fire_t >= interval:
		_fire_t -= interval
		_fire(ship)

func _fire(ship: Vector2) -> void:
	if _mgr == null or not _mgr.has_method("spawn_bullet"):
		return
	var muzzle := center()
	var dir := (ship - muzzle)
	if dir.length() < 0.01:
		return
	_mgr.spawn_bullet(muzzle, dir.normalized() * SH_BULLET_SPEED, SH_BULLET_DMG)
