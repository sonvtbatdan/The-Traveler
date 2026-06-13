extends "res://scripts/gameplay/enemy_base.gd"

## Beamer — a standalone version of the Chromeleon Phase-2 orb's laser attack. It sits where it spawns
## and loops: CHARGE (light-gather motes + ⚠ warning sign) → FIRE (a wide rainbow Lasgun beam straight
## DOWN, north → south, regardless of where the player is) → COOLDOWN → repeat. A rainbow glow halo
## animates the whole time. The beam/charge/glow are copied from boss_chromeleon.gd and re-homed into the
## normal-enemy world (SpaceScreen-local space, the EnemyManager, GameManager damage) so the boss orb is
## untouched. Movement + real avatar come later — this is a stationary glowing-orb placeholder.

const LasgunBeamScript := preload("res://scripts/gameplay/lasgun_beam.gd")

# ── Tunables ──────────────────────────────────────────────────────────────────
const BM_HP: float = 60.0
const BM_XP: int = 12
const BM_IDLE_T: float = 0.6        # brief settle before the first charge
const BM_CHARGE_T: float = 1.0      # telegraph (motes gather + warning sign)
const BM_FIRE_T: float = 3.0        # beam-on duration
const BM_COOLDOWN_T: float = 1.5    # rest between shots
const BM_LASER_WIDTH: float = 50.0  # beam width (px) — matches the orb
const BM_LASER_DMG: int = 5         # damage per tick while the beam overlaps the ship
const BM_LASER_DMG_INT: float = 0.5 # seconds between damage ticks
const BM_GLOW_RADIUS: float = 30.0
const BM_GLOW_ALPHA: float = 0.6
const BM_BEAM_COL := Color(0.6, 0.7, 1.0, 1.0)   # initial; recoloured rainbow every frame while firing
const RAINBOW_SPEED: float = 0.5
const RAINBOW_SAT: float = 0.9

enum Ph { IDLE, CHARGE, FIRE, COOLDOWN }
var _ph: int = Ph.IDLE
var _ph_t: float = 0.0
var _clock: float = 0.0
var _fire_dir: Vector2 = Vector2.DOWN   # default straight down; a choreography can re-aim via aim()
# ── Choreography control (default off → the standalone enemy fires straight down on its own loop) ──
var external_control: bool = false      # when true, a choreography drives firing on/off + direction + position
var fire_enabled: bool = true           # external mode: gate the charge→fire loop (false = dormant, beam off)
var continuous_fire: bool = false       # external mode: after one charge, keep the beam ON (no cooldown gap)
var _dmg_acc: float = 0.0
var _beam_fx: Node = null
var _beam: Dictionary = {}
var _glow: Node = null

func _configure() -> void:
	hp_max = BM_HP
	xp_reward = BM_XP
	contact_damage = 0          # it beams; never rams
	contact_explodes = false
	body_color = Color(0.16, 0.12, 0.22)   # dark core; the rainbow glow is the real look
	shape_kind = "circle"

func _tick(delta: float) -> void:
	_clock += delta
	_ensure_fx()
	_update_glow()
	# External control: a choreography can hold the beamer dormant (beam off, glow on) while it repositions.
	if external_control and not fire_enabled:
		if _ph != Ph.IDLE:
			_ph = Ph.IDLE; _ph_t = 0.0
			_deactivate_beam()
		return
	_ph_t += delta
	match _ph:
		Ph.IDLE:
			# External control: charge the instant firing is enabled (no idle delay). Standalone keeps BM_IDLE_T.
			if external_control or _ph_t >= BM_IDLE_T:
				_enter_charge()
		Ph.CHARGE:
			queue_redraw()   # blink the warning sign
			if _ph_t >= BM_CHARGE_T:
				_ph = Ph.FIRE; _ph_t = 0.0; _dmg_acc = 0.0
				queue_redraw()
		Ph.FIRE:
			var origin := center()
			var length := _arena_edge_len(origin, _fire_dir)
			var hit := _beam_hits_ship(origin, _fire_dir, length, BM_LASER_WIDTH)
			if not _beam.is_empty():
				_beam["beam_color"] = _rainbow(0.0)
			if _beam_fx != null and is_instance_valid(_beam_fx) and not _beam.is_empty():
				_beam_fx.set_beam(_beam, origin, origin + _fire_dir * length, true, hit)
			_dmg_acc = _accrue_beam_dmg(_dmg_acc, hit, delta)
			if _ph_t >= BM_FIRE_T and not (external_control and continuous_fire):
				_deactivate_beam()
				_ph = Ph.COOLDOWN; _ph_t = 0.0
		Ph.COOLDOWN:
			if _ph_t >= BM_COOLDOWN_T:
				_enter_charge()

## Begin a charge: spawn the gather-motes telegraph. The beam fires along _fire_dir (default straight
## DOWN; a choreography can re-aim via aim()).
func _enter_charge() -> void:
	_ph = Ph.CHARGE; _ph_t = 0.0
	_spawn_channel()
	queue_redraw()

## Choreography control: point the beam in a fixed direction (up/down/left/right/any).
func aim(dir: Vector2) -> void:
	if dir.length() > 0.01:
		_fire_dir = dir.normalized()

# ── FX nodes (parented to the EnemyManager → unrotated, SpaceScreen-local space) ──
func _ensure_fx() -> void:
	if _mgr == null or not is_instance_valid(_mgr):
		return
	if _beam_fx == null or not is_instance_valid(_beam_fx):
		_beam_fx = LasgunBeamScript.new()
		_mgr.add_child(_beam_fx)
		_beam = _beam_fx.make_beam(BM_BEAM_COL, BM_LASER_WIDTH)
	if _glow == null or not is_instance_valid(_glow):
		_glow = _OrbGlow.new()
		_glow.z_index = -1
		_glow.z_as_relative = true
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = m
		_mgr.add_child(_glow)

func _update_glow() -> void:
	if _glow == null or not is_instance_valid(_glow):
		return
	_glow.position = center()
	_glow.set_glow(_rainbow(0.0), BM_GLOW_RADIUS, BM_GLOW_ALPHA)
	_glow.visible = true

func _spawn_channel() -> void:
	if _mgr == null or not is_instance_valid(_mgr):
		return
	var fx := _ChannelFX.new()
	fx.position = center()
	fx.z_index = 3
	fx.z_as_relative = true
	fx.setup(_rainbow(0.0), BM_CHARGE_T, 1.0, 1.0)
	_mgr.add_child(fx)

func _deactivate_beam() -> void:
	if not _beam.is_empty():
		_beam["beam_active"] = false

func _exit_tree() -> void:
	super()   # base unregisters the weapon target
	if _beam_fx != null and is_instance_valid(_beam_fx):
		_beam_fx.queue_free()
	if _glow != null and is_instance_valid(_glow):
		_glow.queue_free()
	_beam_fx = null; _glow = null; _beam = {}

# ── Adapted orb helpers (boss couplings swapped for the normal-enemy world) ───
func _rainbow(offset: float) -> Color:
	return Color.from_hsv(fposmod(_clock * RAINBOW_SPEED + offset, 1.0), RAINBOW_SAT, 1.0)

## Distance from `o` to the screen edge along (unit) `dir` — keeps the beam inside the play area.
func _arena_edge_len(o: Vector2, dir: Vector2) -> float:
	var screen: Vector2 = _mgr.screen_size() if (_mgr != null and is_instance_valid(_mgr)) else Vector2(700, 764)
	var t := screen.length()
	if dir.x > 0.0001:    t = minf(t, (screen.x - o.x) / dir.x)
	elif dir.x < -0.0001: t = minf(t, (0.0 - o.x) / dir.x)
	if dir.y > 0.0001:    t = minf(t, (screen.y - o.y) / dir.y)
	elif dir.y < -0.0001: t = minf(t, (0.0 - o.y) / dir.y)
	return t if t > 0.0 else screen.length()

## Wide-beam hit test: ship within half-width (+ its radius) of the beam ray, along its length.
func _beam_hits_ship(origin: Vector2, dir: Vector2, length: float, width: float) -> bool:
	if _mgr == null or not is_instance_valid(_mgr):
		return false
	var ship_c: Vector2 = _mgr.ship_center()
	var ship_r: float = _mgr.ship_radius()
	var to := ship_c - origin
	var t := clampf(to.dot(dir), 0.0, length)
	var closest := origin + dir * t
	return ship_c.distance_to(closest) <= width * 0.5 + ship_r

## Damage on a fair interval while the beam overlaps the ship. Returns the accumulator.
func _accrue_beam_dmg(dmg_acc: float, hit: bool, delta: float) -> float:
	if hit:
		dmg_acc += delta
		if dmg_acc >= BM_LASER_DMG_INT:
			dmg_acc -= BM_LASER_DMG_INT
			GameManager.ship_take_damage(BM_LASER_DMG)
	else:
		dmg_acc = 0.0
	return dmg_acc

# ── Draw: base body + the charge warning sign ─────────────────────────────────
func _draw() -> void:
	super()   # the circle body + HP bar
	if _ph == Ph.CHARGE and fmod(_ph_t * 4.0, 1.0) < 0.6:
		_draw_warn_sign(size * 0.5 + _fire_dir * 46.0, 18.0)

## Amber ⚠ triangle (copied from the orb / elephant warning sign).
func _draw_warn_sign(c: Vector2, s: float = 18.0) -> void:
	var amber := Color(1.0, 0.78, 0.1)
	var dark := Color(0.12, 0.09, 0.0)
	var p0 := c + Vector2(0.0, -s)
	var p1 := c + Vector2(s * 0.9, s * 0.7)
	var p2 := c + Vector2(-s * 0.9, s * 0.7)
	draw_colored_polygon(PackedVector2Array([p0, p1, p2]), amber)
	draw_polyline(PackedVector2Array([p0, p1, p2, p0]), dark, 2.0)
	draw_line(c + Vector2(0.0, -s * 0.35), c + Vector2(0.0, s * 0.18), dark, 3.0)
	draw_circle(c + Vector2(0.0, s * 0.42), 2.0, dark)

# ── Copied FX inner classes (verbatim from boss_chromeleon orbs) ──────────────
## Soft additive rainbow halo (recoloured each frame via set_glow).
class _OrbGlow extends Node2D:
	var _col := Color.WHITE
	var _rad := 26.0
	var _a := 0.6
	func set_glow(col: Color, rad: float, a: float) -> void:
		_col = col; _rad = rad; _a = a
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, _rad * 1.9, Color(_col.r, _col.g, _col.b, _a * 0.16))
		draw_circle(Vector2.ZERO, _rad * 1.1, Color(_col.r, _col.g, _col.b, _a * 0.4))
		draw_circle(Vector2.ZERO, _rad * 0.6, Color(_col.r, _col.g, _col.b, _a * 0.7))

## Inward light-gather motes spiralling toward the focus over `dur` (the charge telegraph).
class _ChannelFX extends Node2D:
	var _t := 0.0
	var _dur := 1.0
	var _col := Color.WHITE
	var _motes: Array = []
	func setup(color: Color, dur: float, scale: float = 1.0, mote_mult: float = 1.0) -> void:
		_col = color
		_dur = maxf(dur, 0.01)
		var n: int = int(round(12.0 * mote_mult))
		for i in n:
			_motes.append({
				"ang":  randf() * TAU,
				"rad":  randf_range(80.0, 150.0) * scale,
				"spin": randf_range(2.5, 5.0) * (1.0 if randf() < 0.5 else -1.0),
				"size": randf_range(3.0, 6.0) * scale,
				"hue":  randf(),
			})
	func _process(delta: float) -> void:
		_t += delta
		if _t >= _dur:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var p: float = clampf(_t / _dur, 0.0, 1.0)
		for m in _motes:
			var ang: float = float(m["ang"]) + float(m["spin"]) * _t
			var rad: float = float(m["rad"]) * (1.0 - p)
			var pos := Vector2(cos(ang), sin(ang)) * rad
			var a: float = 1.0 - p
			var sz: float = float(m["size"]) * (1.0 - 0.5 * p)
			var col := Color.from_hsv(fposmod(float(m["hue"]) + _t * 0.5, 1.0), 0.9, 1.0)
			draw_circle(pos, sz * 2.2, Color(col.r, col.g, col.b, a * 0.25))
			draw_circle(pos, sz, Color(col.r, col.g, col.b, a))
