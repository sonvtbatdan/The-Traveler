extends "res://scripts/gameplay/enemy_base.gd"

## Kingfisher — the simplest attacker. Picks a screen edge (from KF_EDGES), lines its entry point up
## with the player's position at spawn, shows a warning sign there for KF_WARN_TIME, then enters at
## that exact point and zooms straight inward at KF_SPEED. It does NOT track — dodge by leaving its
## line/column. Explodes on contact with the player only.

# ── Tunable constants (Kingfisher) ────────────────────────────────────────────
const KF_HP: float = 40.0
const KF_XP: int = 8
const KF_SPEED: float = 650.0       # straight-line dash speed (px/s) — 35% slower than the original 1000
const KF_CONTACT_DMG: int = 10      # damage to the ship on contact (then it explodes)
const KF_WARN_TIME: float = 1.0     # seconds the warning sign shows before it enters
const KF_WARN_INSET: float = 26.0   # how far inward the warning is drawn so the edge doesn't clip it
# Which edges it may enter from — TUNE PER STAGE (e.g. ["top"] for map 1, ["top","left"] for map 2).
const KF_EDGES: Array = ["top", "bottom", "left", "right"]
# One "spawn" sends a burst of 3, all from the SAME edge aimed at one captured player spot, each
# delayed from the last and offset sideways so they're adjacent without overlapping (see enemy_manager).
const KF_BURST_COUNT: int = 3
const KF_BURST_DELAY: float = 0.5   # seconds between each kingfisher in the burst
const KF_BURST_GAP: float = 52.0    # sideways gap between burst members (> their size → no overlap)

enum Phase { DELAY, WARN, FLY }
var _phase: int = Phase.WARN
var _warn_t: float = 0.0
var _delay_t: float = 0.0
var _start_delay: float = 0.0    # burst stagger: this member waits this long before its warning starts
var _vel: Vector2 = Vector2.ZERO
var _inward: Vector2 = Vector2.DOWN
var _entry: Vector2 = Vector2.ZERO

func _configure() -> void:
	hp_max = KF_HP
	xp_reward = KF_XP
	contact_damage = KF_CONTACT_DMG
	contact_explodes = true
	auto_register = false     # only a warning sign until it actually enters → not damageable yet
	contact_active = false    # no contact during the warning
	body_color = Color(0.95, 0.45, 0.35)
	shape_kind = "triangle"
	icon_path  = "res://assets/enemies/kingfisher.png"

## Called by EnemyManager for each burst member. `edge` is fixed (shared by the whole burst), `aim` is
## the player position captured at the START of the burst (so all 3 target the same spot), and
## `lateral` shifts the entry ALONG the edge so members are adjacent without overlapping (0 = the
## first one, exactly on the player; ±KF_BURST_GAP = the followers).
func spawn_member(mgr: Node, edge: String, aim: Vector2, lateral: float, start_delay: float = 0.0) -> void:
	var screen: Vector2 = mgr.screen_size()
	var w: float = screen.x
	var h: float = screen.y
	match edge:
		"bottom":
			_entry = Vector2(clampf(aim.x + lateral, 0.0, w), h)
			_vel = Vector2(0.0, -KF_SPEED); _inward = Vector2.UP
		"left":
			_entry = Vector2(0.0, clampf(aim.y + lateral, 0.0, h))
			_vel = Vector2(KF_SPEED, 0.0); _inward = Vector2.RIGHT
		"right":
			_entry = Vector2(w, clampf(aim.y + lateral, 0.0, h))
			_vel = Vector2(-KF_SPEED, 0.0); _inward = Vector2.LEFT
		_:  # top (default)
			_entry = Vector2(clampf(aim.x + lateral, 0.0, w), 0.0)
			_vel = Vector2(0.0, KF_SPEED); _inward = Vector2.DOWN
	position = _entry - size * 0.5
	rotation = 0.0   # stay unrotated during WARN so the warning's inward offset is screen-aligned
	_start_delay = start_delay
	_delay_t = 0.0
	_warn_t = 0.0
	_phase = Phase.DELAY if start_delay > 0.0 else Phase.WARN   # later burst members wait first
	queue_redraw()

func _tick(delta: float) -> void:
	match _phase:
		Phase.DELAY:
			_delay_t += delta   # dormant (invisible, unregistered) until its burst slot comes up
			if _delay_t >= _start_delay:
				_phase = Phase.WARN
				_warn_t = 0.0
				queue_redraw()
		Phase.WARN:
			_warn_t += delta
			queue_redraw()   # blink the warning
			if _warn_t >= KF_WARN_TIME:
				_phase = Phase.FLY
				position = _entry - size * 0.5            # enter at the exact telegraphed point
				rotation = _vel.angle() + PI * 0.5        # now face the travel direction
				contact_active = true
				_register()                               # now it can be shot
				queue_redraw()
		Phase.FLY:
			position += _vel * delta
			if _off_screen():
				despawn()   # flew past the far edge without hitting anyone — no XP

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
	var c := size * 0.5 + _inward * KF_WARN_INSET
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
