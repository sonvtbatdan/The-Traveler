extends "res://scripts/gameplay/enemy_base.gd"

## Dragonfly — enters from the top, then orbits the player in a tightening spiral until close enough
## to dive in.  Rotates visually at 20 rpm.  Explodes on contact (10 damage).

const DF_HP: float = 90.0
const DF_XP: int = 10
const DF_CONTACT_DMG: int = 10
const DF_ENTRY_SPEED: float = 140.0
const DF_SPIRAL_SPEED: float = 100.0   # target movement speed during orbit
const DF_SPIN_RATE: float = 1.2        # rad/s orbital spin
const DF_SHRINK_RATE: float = 28.0     # px/s radius shrink
const DF_ORBIT_RADIUS_START: float = 180.0
const DF_ORBIT_RADIUS_END: float = 32.0
const DF_DIVE_SPEED: float = 160.0
const DF_ROT_SPEED: float = TAU / 3.0   # visual 20 rpm
const DF_CULL: float = 800.0
# Orbit center drifts toward the player at this speed (px/s) — player faster than this can pull away
const DF_ORBIT_CENTER_SPEED: float = 80.0

enum Phase { ENTRY, SPIRAL, DIVE }
var _phase: int = Phase.ENTRY
var _entry_target: Vector2 = Vector2.ZERO
var _orbit_angle: float = 0.0
var _orbit_radius: float = DF_ORBIT_RADIUS_START
var _orbit_center: Vector2 = Vector2.ZERO   # drifts toward player at DF_ORBIT_CENTER_SPEED
var _dive_target: Vector2 = Vector2.ZERO    # captured once when DIVE begins (aim-once)
var _plume_base_cols:  Array = []   # [PackedColorArray] per plume
var _plume_red_cols:   Array = []   # pre-built red-tone gradient per plume
var _plume_in_red: bool = false

func _ready() -> void:
	super._ready()
	var red := PackedColorArray([
		Color(1.0, 0.20, 0.10, 1.0),
		Color(0.85, 0.05, 0.02, 1.0),
		Color(0.60, 0.00, 0.00, 0.85),
		Color(0.40, 0.00, 0.00, 0.00),
	])
	for p: CPUParticles2D in _plumes:
		_plume_base_cols.append(p.color_ramp.colors.duplicate() if p.color_ramp != null else PackedColorArray())
		_plume_red_cols.append(red)

func _update_plume_color() -> void:
	if _mgr == null:
		return
	var want_red := center().distance_to(_mgr.ship_center()) < 350.0
	if want_red == _plume_in_red:
		return
	_plume_in_red = want_red
	var src: Array = _plume_red_cols if want_red else _plume_base_cols
	for i: int in _plumes.size():
		if _plumes[i].color_ramp != null and i < src.size():
			_plumes[i].color_ramp.colors = src[i]

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = DF_HP
	xp_reward = DF_XP
	contact_damage = DF_CONTACT_DMG
	contact_explodes = true
	contact_active = false
	body_color = Color(0.2, 0.7, 0.9)
	shape_kind = "diamond"
	icon_path = "res://assets/enemies/animaldragonfly.png"

func spawn(mgr: Node) -> void:
	_mgr = mgr
	var screen: Vector2 = mgr.screen_size()
	position = Vector2(randf_range(size.x, screen.x - size.x), -size.y)
	_entry_target = Vector2(center().x, screen.y * 0.18)
	_phase = Phase.ENTRY

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	_update_plume_color()
	rotation += DF_ROT_SPEED * delta
	match _phase:
		Phase.ENTRY:
			var to := _entry_target - center()
			if to.length() <= 8.0:
				position = _entry_target - size * 0.5
				_phase = Phase.SPIRAL
				# Initialise orbit from current displacement to player
				var offset: Vector2 = center() - _mgr.ship_center()
				_orbit_radius = clampf(offset.length(), DF_ORBIT_RADIUS_END, DF_ORBIT_RADIUS_START)
				_orbit_angle = offset.angle()
				_orbit_center = _mgr.ship_center()   # anchor; drifts from here
				contact_active = true
			else:
				position += to.normalized() * DF_ENTRY_SPEED * delta
		Phase.SPIRAL:
			_orbit_angle += DF_SPIN_RATE * delta
			_orbit_radius = maxf(DF_ORBIT_RADIUS_END, _orbit_radius - DF_SHRINK_RATE * delta)
			_orbit_center = _orbit_center.move_toward(_mgr.ship_center(), DF_ORBIT_CENTER_SPEED * delta)
			var spiral_pos: Vector2 = _orbit_center + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * _orbit_radius
			var to := spiral_pos - center()
			var move := minf(to.length(), DF_SPIRAL_SPEED * delta)
			if to.length() > 0.5:
				position += to.normalized() * move
			if _orbit_radius <= DF_ORBIT_RADIUS_END:
				_dive_target = _mgr.ship_center()   # capture once; player can dodge the dive
				_phase = Phase.DIVE
		Phase.DIVE:
			var to: Vector2 = _dive_target - center()
			position += to.normalized() * DF_DIVE_SPEED * delta
			var c := center()
			var screen: Vector2 = _mgr.screen_size()
			if c.x < -DF_CULL or c.x > screen.x + DF_CULL or c.y < -DF_CULL or c.y > screen.y + DF_CULL:
				despawn()
