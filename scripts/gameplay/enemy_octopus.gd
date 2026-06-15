extends "res://scripts/gameplay/enemy_base.gd"

## Octopus — stationary between jumps; leaps toward the player (aim-once) every OC_JUMP_INTERVAL
## seconds.  Each jump has ease-in / ease-out smoothing and is capped to OC_JUMP_RANGE px.
## Explodes on contact (20 damage).

const OC_HP: float = 240.0
const OC_XP: int = 24
const OC_CONTACT_DMG: int = 20
const OC_JUMP_RANGE: float = 200.0
const OC_JUMP_SPEED: float = 600.0   # peak travel speed (arc centre)
const OC_JUMP_INTERVAL: float = 1.0

var _jump_acc: float = 0.0
var _jumping: bool = false
var _jump_start: Vector2 = Vector2.ZERO
var _jump_end: Vector2 = Vector2.ZERO
var _jump_t: float = 0.0
var _jump_duration: float = 0.0

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = OC_HP
	xp_reward = OC_XP
	contact_damage = OC_CONTACT_DMG
	contact_explodes = true
	contact_active = false
	body_color = Color(0.55, 0.2, 0.75)
	shape_kind = "circle"
	icon_path = "res://assets/enemies/animaloctopus.png"

func spawn(mgr: Node) -> void:
	_mgr = mgr
	var screen: Vector2 = mgr.screen_size()
	position = Vector2(randf_range(size.x, screen.x - size.x * 2.0), -size.y)
	_jump_acc = 0.4   # brief initial pause before first jump

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	if _jumping:
		_jump_t += delta
		var frac := clampf(_jump_t / _jump_duration, 0.0, 1.0)
		var ease := frac * frac * (3.0 - 2.0 * frac)   # smoothstep
		position = _jump_start.lerp(_jump_end, ease) - size * 0.5
		if frac >= 1.0:
			_jumping = false
			contact_active = false
			_jump_acc = 0.0
	else:
		_jump_acc += delta
		if _jump_acc >= OC_JUMP_INTERVAL:
			_start_jump()

func _start_jump() -> void:
	var screen: Vector2 = _mgr.screen_size()
	var target: Vector2 = _mgr.ship_center()
	var to: Vector2 = target - center()
	var dist := minf(to.length(), OC_JUMP_RANGE)
	if dist < 1.0:
		_jump_acc = 0.0
		return
	_jump_start = center()
	var raw_end := center() + to.normalized() * dist
	_jump_end = Vector2(
		clampf(raw_end.x, size.x * 0.5, screen.x - size.x * 0.5),
		clampf(raw_end.y, size.y * 0.5, screen.y - size.y * 0.5)
	)
	_jump_duration = maxf(0.05, _jump_start.distance_to(_jump_end) / OC_JUMP_SPEED)
	_jump_t = 0.0
	_jumping = true
	contact_active = true
