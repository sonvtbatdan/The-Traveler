extends "res://scripts/gameplay/enemy_base.gd"

## Bug — one member of a BugFlock (4 rows × 4 cols, 16 total).
## Two-phase launch: first the member EXPANDS sideways to its launch position, then dives at the
## player aim-once.  Explodes on contact (5 damage).

const BU_HP: float = 15.0
const BU_XP: int = 3
const BU_CONTACT_DMG: int = 5
const BU_ENTER_SPEED: float = 120.0
const BU_EXPAND_SPEED: float = 110.0
const BU_DIVE_SPEED_INIT: float = 75.0
const BU_DIVE_SPEED_MAX: float = 150.0
const BU_DIVE_ACCEL: float = 130.0
const BU_ARRIVE_DIST: float = 5.0
const BU_CULL: float = 800.0

enum Phase { ENTER, HOLD, EXPAND, DIVE }
var _phase: int = Phase.ENTER
var _target_pos: Vector2 = Vector2.ZERO   # formation slot centre
var _expand_pos: Vector2 = Vector2.ZERO   # wider launch position (set by flock)
var _heading: float = 0.0
var _dive_speed: float = BU_DIVE_SPEED_INIT

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = BU_HP
	xp_reward = BU_XP
	contact_damage = BU_CONTACT_DMG
	contact_explodes = true
	contact_active = false
	body_color = Color(0.3, 0.80, 0.35)
	shape_kind = "triangle"
	icon_path = "res://assets/enemies/animalbug.png"

func set_formation_pos(pos: Vector2) -> void:
	_target_pos = pos

func is_in_position() -> bool:
	return _phase == Phase.HOLD

func is_done_expanding() -> bool:
	return _phase == Phase.DIVE

## Called by BugFlock; member first expands to `launch_pos`, then auto-dives.
func begin_dive_from(launch_pos: Vector2) -> void:
	if _dead:
		return
	_expand_pos = launch_pos
	_phase = Phase.EXPAND

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	match _phase:
		Phase.ENTER:
			var to := _target_pos - center()
			if to.length() <= BU_ARRIVE_DIST:
				position = _target_pos - size * 0.5
				_phase = Phase.HOLD
			else:
				position += to.normalized() * BU_ENTER_SPEED * delta
				rotation = to.angle() + PI * 0.5
		Phase.HOLD:
			pass
		Phase.EXPAND:
			var to := _expand_pos - center()
			if to.length() <= BU_ARRIVE_DIST:
				position = _expand_pos - size * 0.5
				# Launch dive from here
				_phase = Phase.DIVE
				contact_active = true
				_dive_speed = BU_DIVE_SPEED_INIT
				_heading = (_mgr.ship_center() - center()).angle()
			else:
				position += to.normalized() * BU_EXPAND_SPEED * delta
				rotation = to.angle() + PI * 0.5
		Phase.DIVE:
			_dive_speed = minf(_dive_speed + BU_DIVE_ACCEL * delta, BU_DIVE_SPEED_MAX)
			position += Vector2.from_angle(_heading) * _dive_speed * delta
			rotation = _heading + PI * 0.5
			var c := center()
			var screen: Vector2 = _mgr.screen_size()
			if c.x < -BU_CULL or c.x > screen.x + BU_CULL or c.y < -BU_CULL or c.y > screen.y + BU_CULL:
				despawn()
