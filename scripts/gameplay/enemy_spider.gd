extends "res://scripts/gameplay/enemy_base.gd"

## Spider — like Octopus but jumps ONLY along 45° diagonals (↗ ↘ ↙ ↖), choosing the diagonal
## direction that is closest to the player.  Same ease-in/out arc, range, speed, interval.
## Explodes on contact (8 damage).

const SP_HP: float = 60.0
const SP_XP: int = 8
const SP_CONTACT_DMG: int = 8
const SP_JUMP_RANGE: float = 200.0
const SP_JUMP_SPEED: float = 600.0
const SP_JUMP_INTERVAL: float = 1.0

var _jump_acc: float = 0.0
var _jumping: bool = false
var _jump_start: Vector2 = Vector2.ZERO
var _jump_end: Vector2 = Vector2.ZERO
var _jump_t: float = 0.0
var _jump_duration: float = 0.0

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = SP_HP
	xp_reward = SP_XP
	contact_damage = SP_CONTACT_DMG
	contact_explodes = true
	contact_active = false
	body_color = Color(0.75, 0.35, 0.15)
	shape_kind = "diamond"
	icon_path = "res://assets/enemies/animalspider.png"

func spawn(mgr: Node) -> void:
	_mgr = mgr
	var screen: Vector2 = mgr.screen_size()
	position = Vector2(randf_range(size.x, screen.x - size.x * 2.0), -size.y)
	_jump_acc = 0.4

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	if _jumping:
		_jump_t += delta
		var frac := clampf(_jump_t / _jump_duration, 0.0, 1.0)
		var ease := frac * frac * (3.0 - 2.0 * frac)
		position = _jump_start.lerp(_jump_end, ease) - size * 0.5
		if frac >= 1.0:
			_jumping = false
			contact_active = false
			_jump_acc = 0.0
	else:
		_jump_acc += delta
		if _jump_acc >= SP_JUMP_INTERVAL:
			_start_jump()

func _start_jump() -> void:
	var screen: Vector2 = _mgr.screen_size()
	var target: Vector2 = _mgr.ship_center()
	var to: Vector2 = target - center()
	# Snap direction to nearest 45° diagonal
	var dx := to.x if absf(to.x) > 1.0 else (1.0 if randf() > 0.5 else -1.0)
	var dy := to.y if absf(to.y) > 1.0 else (1.0 if randf() > 0.5 else -1.0)
	var jump_dir := Vector2(sign(dx), sign(dy)).normalized()   # always a 45° diagonal
	_jump_start = center()
	var raw_end := center() + jump_dir * SP_JUMP_RANGE
	_jump_end = Vector2(
		clampf(raw_end.x, size.x * 0.5, screen.x - size.x * 0.5),
		clampf(raw_end.y, size.y * 0.5, screen.y - size.y * 0.5)
	)
	_jump_duration = maxf(0.05, _jump_start.distance_to(_jump_end) / SP_JUMP_SPEED)
	_jump_t = 0.0
	_jumping = true
	contact_active = true
