extends "res://scripts/gameplay/enemy_base.gd"

## Diver — a tracking-warning dasher. One "spawn" sends a burst of DV_BURST_COUNT from the SAME
## edge. While still OFF-SCREEN (the WARN phase) each member's warning sign SLIDES along that edge:
##   • the LEAD tracks the player's live position (warning projected onto the edge), and
##   • the two FOLLOWERS oscillate back and forth within ±DV_FOLLOW_RANGE of the lead at 100–300 px/s
##     (independent speed/phase → they can end up both on one side, or one on each side).
## When a member's warn time elapses it ENTERS at its current warning spot: the LEAD dashes toward the
## player's position captured that instant, the FOLLOWERS dash straight inward. It does NOT track once
## on-screen — dodge by leaving its path. Explodes on contact with the player only.

# ── Tunable constants (Diver) ────────────────────────────────────────────
const DV_HP: float = 40.0
const DV_XP: int = 8
const DV_SPEED: float = 650.0       # straight-line dash speed (px/s)
const DV_CONTACT_DMG: int = 10      # damage to the ship on contact (then it explodes)
const DV_WARN_TIME: float = 1.0     # seconds the warning sign tracks before it enters
const DV_WARN_INSET: float = 26.0   # how far inward the warning is drawn so the edge doesn't clip it
# Which edges it may enter from — TUNE PER STAGE (e.g. ["top"] for map 1, ["top","left"] for map 2).
const DV_EDGES: Array = ["top", "bottom", "left", "right"]
const DV_BURST_COUNT: int = 3
const DV_BURST_DELAY: float = 0.2     # seconds between each member entering (staggered)
const DV_FOLLOW_RANGE: float = 150.0  # followers stay within this many px (along the edge) of the lead
const DV_OSC_SPEED_MIN: float = 100.0 # follower back-and-forth speed range (px/s)
const DV_OSC_SPEED_MAX: float = 300.0

enum Phase { DELAY, WARN, FLY }
var _phase: int = Phase.WARN
var _warn_t: float = 0.0
var _delay_t: float = 0.0
var _start_delay: float = 0.0     # burst stagger: this member waits this long before its warning starts
var _edge: String = "top"
var _is_lead: bool = true          # the lead tracks the player; followers oscillate around it
var _inward: Vector2 = Vector2.DOWN
var _vel: Vector2 = Vector2.ZERO
var _entry: Vector2 = Vector2.ZERO
# Follower oscillation along the edge, relative to the lead's (player-projected) position.
var _osc_off: float = 0.0
var _osc_dir: float = 1.0
var _osc_speed: float = 0.0
var _speed_delta: float = 0.0   # per-instance dash-speed adjustment (a choreography may slow some divers)

func _configure() -> void:
	hp_max = DV_HP
	xp_reward = DV_XP
	contact_damage = DV_CONTACT_DMG
	contact_explodes = true
	auto_register = false     # only a warning sign until it actually enters → not damageable yet
	contact_active = false    # no contact during the warning
	body_color = Color(0.95, 0.45, 0.35)
	shape_kind = "triangle"

## Called by EnemyManager for each burst member. `edge` is shared by the whole burst, `is_lead` marks
## the player-tracking lead (i == 0), and `start_delay` staggers when this member's warning begins.
func spawn_member(mgr: Node, edge: String, is_lead: bool, start_delay: float = 0.0, speed_delta: float = 0.0) -> void:
	_edge = edge
	_is_lead = is_lead
	_speed_delta = speed_delta
	match edge:
		"bottom": _inward = Vector2.UP
		"left":   _inward = Vector2.RIGHT
		"right":  _inward = Vector2.LEFT
		_:        _inward = Vector2.DOWN   # top
	# Followers get a randomized oscillation so the two never move identically (→ varied left/right mix).
	if not is_lead:
		_osc_off   = randf_range(-DV_FOLLOW_RANGE, DV_FOLLOW_RANGE)
		_osc_dir   = 1.0 if randf() < 0.5 else -1.0
		_osc_speed = randf_range(DV_OSC_SPEED_MIN, DV_OSC_SPEED_MAX)
	_start_delay = start_delay
	_delay_t = 0.0
	_warn_t = 0.0
	rotation = 0.0   # stay unrotated during WARN so the warning's inward offset is screen-aligned
	_phase = Phase.DELAY if start_delay > 0.0 else Phase.WARN   # later burst members wait first
	_update_tracking()   # snap the warning onto its starting spot immediately
	queue_redraw()

## Launch spawn (Enemy_group_1 sentinel death): fire out of `origin` along `vel_up` and fly straight off
## the map (FLY phase → despawns once off-screen). No warning, no diving back — it just leaves.
func spawn_launch(mgr: Node, origin: Vector2, vel_up: Vector2) -> void:
	_is_lead = false
	position = origin - size * 0.5
	_vel = vel_up
	_phase = Phase.FLY
	rotation = vel_up.angle() + PI * 0.5
	contact_active = true
	_register()
	queue_redraw()

func _tick(delta: float) -> void:
	match _phase:
		Phase.DELAY:
			_delay_t += delta   # dormant (invisible) but already following so it appears mid-track
			_advance_osc(delta)
			_update_tracking()
			if _delay_t >= _start_delay:
				_phase = Phase.WARN
				_warn_t = 0.0
				queue_redraw()
		Phase.WARN:
			_warn_t += delta
			_advance_osc(delta)
			_update_tracking()   # warning slides along the edge, tracking the player / oscillating
			queue_redraw()       # blink the warning
			if _warn_t >= DV_WARN_TIME:
				_enter()
		Phase.FLY:
			position += _vel * delta
			if _off_screen():
				despawn()   # flew past the far edge without hitting anyone — no XP

## Slide the warning to its current tracked spot (lead: player projection; follower: + oscillation).
func _update_tracking() -> void:
	if _mgr == null or not is_instance_valid(_mgr):
		return
	_entry = _tracked_entry(_mgr.ship_center())
	position = _entry - size * 0.5

## The on-edge point this member currently targets, given the live player position `aim`.
func _tracked_entry(aim: Vector2) -> Vector2:
	var screen: Vector2 = _mgr.screen_size()
	var w: float = screen.x
	var h: float = screen.y
	var off: float = 0.0 if _is_lead else _osc_off
	match _edge:
		"bottom": return Vector2(clampf(aim.x + off, 0.0, w), h)
		"left":   return Vector2(0.0, clampf(aim.y + off, 0.0, h))
		"right":  return Vector2(w, clampf(aim.y + off, 0.0, h))
		_:        return Vector2(clampf(aim.x + off, 0.0, w), 0.0)   # top

## Followers bounce back and forth within ±DV_FOLLOW_RANGE of the lead.
func _advance_osc(delta: float) -> void:
	if _is_lead:
		return
	_osc_off += _osc_dir * _osc_speed * delta
	if _osc_off >= DV_FOLLOW_RANGE:
		_osc_off = DV_FOLLOW_RANGE
		_osc_dir = -1.0
	elif _osc_off <= -DV_FOLLOW_RANGE:
		_osc_off = -DV_FOLLOW_RANGE
		_osc_dir = 1.0

## WARN → FLY: lock the entry point and dash direction, then become damageable.
func _enter() -> void:
	_phase = Phase.FLY
	var aim: Vector2 = _mgr.ship_center() if (_mgr != null and is_instance_valid(_mgr)) else center()
	_entry = _tracked_entry(aim)
	position = _entry - size * 0.5            # enter at the exact telegraphed point
	var spd := maxf(50.0, DV_SPEED + _speed_delta)   # per-instance speed (e.g. horizontal divers slowed)
	if _is_lead:
		var dir := aim - _entry                # lead homes on the player's position at this instant
		_vel = (dir.normalized() if dir.length() > 0.01 else _inward) * spd
	else:
		_vel = _inward * spd                   # followers dash straight inward
	rotation = _vel.angle() + PI * 0.5         # face the travel direction
	contact_active = true
	_register()                                # now it can be shot
	queue_redraw()

func _off_screen() -> bool:
	if _mgr == null:
		return false
	var c := center()
	var screen: Vector2 = _mgr.screen_size()
	var m := 48.0
	return c.x < -m or c.x > screen.x + m or c.y < -m or c.y > screen.y + m

func _draw() -> void:
	match _phase:
		Phase.DELAY:
			pass            # not visible yet
		Phase.WARN:
			_draw_warning()
		_:
			super()         # base draws the triangle body + HP bar

func _draw_warning() -> void:
	var c := size * 0.5 + _inward * DV_WARN_INSET
	var pulse := 0.35 + 0.65 * absf(sin(_warn_t * TAU * 2.0))
	var col := Color(1.0, 0.3, 0.2, pulse)
	var r := size.x * 0.65
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -r), c + Vector2(-r * 0.9, r * 0.7), c + Vector2(r * 0.9, r * 0.7)]),
		Color(1.0, 0.3, 0.2, pulse * 0.45))
	draw_arc(c, r, 0.0, TAU, 20, col, 2.0)
	# exclamation mark
	draw_line(c + Vector2(0.0, -r * 0.35), c + Vector2(0.0, r * 0.12), Color(1, 1, 1, pulse), 3.0)
	draw_circle(c + Vector2(0.0, r * 0.38), 2.5, Color(1, 1, 1, pulse))
