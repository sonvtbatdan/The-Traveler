extends "res://scripts/gameplay/enemy_base.gd"

## Bee — one member of a BeeHiveFlockof 12 (4 rows × 3 cols).
## The flock places it off-screen, then it flies to its formation slot; once all slots are filled
## the flock launches rows one-by-one.  Each bee dives aim-once at the player, accelerating to
## BE_DIVE_SPEED_MAX.  Explodes on contact (8 damage).

const BE_HP: float = 20.0
const BE_XP: int = 3
const BE_CONTACT_DMG: int = 8
const BE_ENTER_SPEED: float = 120.0
const BE_DIVE_SPEED_INIT: float = 80.0
const BE_DIVE_SPEED_MAX: float = 150.0
const BE_DIVE_ACCEL: float = 140.0   # px/s²
const BE_ARRIVE_DIST: float = 5.0
const BE_CULL: float = 800.0

enum Phase { ENTER, HOLD, DIVE }
var _phase: int = Phase.ENTER
var _target_pos: Vector2 = Vector2.ZERO   # world-space centre of this member's formation slot
var _heading: float = 0.0
var _dive_speed: float = BE_DIVE_SPEED_INIT
var _plume_base: Array = []   # [{vel_min, vel_max}] per plume

func _ready() -> void:
	super._ready()
	for p: CPUParticles2D in _plumes:
		_plume_base.append({"vel_min": p.initial_velocity_min, "vel_max": p.initial_velocity_max})

func _apply_plume_vel_mult(m: float) -> void:
	for i: int in _plumes.size():
		_plumes[i].initial_velocity_min = float(_plume_base[i]["vel_min"]) * m
		_plumes[i].initial_velocity_max = float(_plume_base[i]["vel_max"]) * m

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = BE_HP
	xp_reward = BE_XP
	contact_damage = BE_CONTACT_DMG
	contact_explodes = true
	contact_active = false
	body_color = Color(0.95, 0.82, 0.1)
	shape_kind = "triangle"
	icon_path = "res://assets/enemies/animalbee.png"

## Called by BeeHiveFlock immediately after add_child.
func set_formation_pos(pos: Vector2) -> void:
	_target_pos = pos   # centre of the formation slot

func is_in_position() -> bool:
	return _phase == Phase.HOLD

func is_diving() -> bool:
	return _phase == Phase.DIVE

## Called by BeeHiveFlock to launch this bee's dive.
func begin_dive() -> void:
	if _dead or _phase == Phase.DIVE:
		return
	_phase = Phase.DIVE
	contact_active = true
	_dive_speed = BE_DIVE_SPEED_INIT
	if _mgr != null:
		_heading = (_mgr.ship_center() - center()).angle()

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	match _phase:
		Phase.ENTER:
			var to := _target_pos - center()
			if to.length() <= BE_ARRIVE_DIST:
				position = _target_pos - size * 0.5
				_phase = Phase.HOLD
			else:
				position += to.normalized() * BE_ENTER_SPEED * delta
				rotation = to.angle() + PI * 0.5
		Phase.HOLD:
			pass
		Phase.DIVE:
			_dive_speed = minf(_dive_speed + BE_DIVE_ACCEL * delta, BE_DIVE_SPEED_MAX)
			position += Vector2.from_angle(_heading) * _dive_speed * delta
			rotation = _heading + PI * 0.5
			var c := center()
			var screen: Vector2 = _mgr.screen_size()
			if c.x < -BE_CULL or c.x > screen.x + BE_CULL or c.y < -BE_CULL or c.y > screen.y + BE_CULL:
				despawn()
	_apply_plume_vel_mult(2.0 if _phase == Phase.DIVE else 1.0)
