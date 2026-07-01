extends Node2D
## A collectible XP orb dropped by a dying enemy. Sits and gently bobs until the player comes within their
## pickup radius (GameManager.get_pickup_radius() — widened by the Magnet upgrade), then magnetizes toward the
## player, accelerating as it closes. On reaching the player it grants its XP (GameManager.add_xp) and pops.
## Lives on the gameplay plane (sharp, not blurred). Persists until collected (survival-friendly).

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const COLLECT_RADIUS      := 16.0

# ── XP orb tiers (threshold = max xp for that tier, inclusive) ────────────────
const TIER_GREEN_MAX  :=  2.5    # face-value XP now (÷20 of the old scale): tiers rescaled ÷20, mults ×20,
const TIER_YELLOW_MAX :=  5.0    # caps unchanged → orbs keep the same on-screen size/color as before.
const TIER_RED_MAX    := 25.0
#                                  25+     xp:  radius = xp × 2.0   (purple)
const TIER_GREEN_MULT  := 20.0
const TIER_YELLOW_MULT := 10.0
const TIER_RED_MULT    := 4.0
const TIER_PURPLE_MULT := 2.0
# Visual cap per tier so no orb overwhelms the screen (outer glow = cap × 1.8)
const TIER_GREEN_CAP  :=  8.0   # → max outer glow ≈ 29 px diam
const TIER_YELLOW_CAP := 14.0   # → max outer glow ≈ 50 px diam
const TIER_RED_CAP    := 22.0   # → max outer glow ≈ 79 px diam
const TIER_PURPLE_CAP := 32.0   # → max outer glow ≈ 115 px diam
const MAGNET_SPEED        := 120.0    # starting fly speed once magnetized naturally (px/s)
const MAGNET_ACCEL        := 900.0    # acceleration when magnetized naturally (px/s²)
const MAGNET_MAX          := 1400.0   # speed cap for natural magnetization
const FORCE_MAGNET_ACCEL  := 600.0    # acceleration when pulled by magnetic item (0→1200 in 2s)
const FORCE_MAGNET_MAX    := 1200.0   # speed cap for forced magnetization
const BOB_AMP        := 2.5
const BOB_SPEED      := 3.0
const GREEN_CORE  := Color(0.45, 1.0,  0.7)
const GREEN_GLOW  := Color(0.30, 0.95, 0.85)
const YELLOW_CORE := Color(1.0,  0.95, 0.2)
const YELLOW_GLOW := Color(0.95, 0.85, 0.0)
const RED_CORE    := Color(1.0,  0.18, 0.08)
const RED_GLOW    := Color(1.0,  0.05, 0.0)
const PURPLE_CORE := Color(0.75, 0.2,  1.0)
const PURPLE_GLOW := Color(0.55, 0.0,  0.9)

var _value: float = 1.0
var _vel := Vector2.ZERO
var _magnetized := false
var _force_magnet := false   # true when pulled by the magnetic loot item (starts from 0 speed)
var _t := 0.0
var _player: Node2D = null

func setup(world_pos: Vector2, value: float) -> void:
	add_to_group("arena_xp_orb")
	global_position = world_pos
	_value = value
	_t = randf() * TAU   # desync the bob so a cluster doesn't pulse in lockstep

func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			queue_redraw()
			return
	var to := _player.global_position - global_position
	var d := to.length()
	var radius: float = GameManager.get_pickup_radius() if GameManager.has_method("get_pickup_radius") else 90.0
	if _magnetized or d <= radius:
		_magnetized = true
		var dir := to / maxf(d, 0.001)
		if _force_magnet:
			# Accelerate from 0 → FORCE_MAGNET_MAX over 2 s (linear ramp)
			var spd := _vel.length() + FORCE_MAGNET_ACCEL * delta
			_vel = dir * minf(spd, FORCE_MAGNET_MAX)
		else:
			var spd := maxf(_vel.length(), MAGNET_SPEED) + MAGNET_ACCEL * delta
			_vel = dir * minf(spd, MAGNET_MAX)
		global_position += _vel * delta
		if d <= COLLECT_RADIUS:
			_collect()
			return
	queue_redraw()

func _collect() -> void:
	if GameManager.has_method("add_xp"):
		GameManager.add_xp(_value)
	var stream := load("res://assets/audio/sfx/equip.wav") as AudioStream
	if stream != null:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = linear_to_db(0.6)
		if get_parent() != null:
			get_parent().add_child(p)
		else:
			add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	queue_free()

## Called by the magnetic loot drop — pulls this orb toward the player with a smooth 0→1200 px/s ramp.
func force_magnetize() -> void:
	_force_magnet = true
	_magnetized = true
	_vel = Vector2.ZERO

## Instant collect (legacy, kept for compatibility).
func collect() -> void:
	_collect()

func _tier_params() -> Array:
	var sz: float
	var cc: Color
	var gc: Color
	if _value <= TIER_GREEN_MAX:
		sz = minf(float(_value) * TIER_GREEN_MULT,  TIER_GREEN_CAP);  cc = GREEN_CORE;  gc = GREEN_GLOW
	elif _value <= TIER_YELLOW_MAX:
		sz = minf(float(_value) * TIER_YELLOW_MULT, TIER_YELLOW_CAP); cc = YELLOW_CORE; gc = YELLOW_GLOW
	elif _value <= TIER_RED_MAX:
		sz = minf(float(_value) * TIER_RED_MULT,    TIER_RED_CAP);    cc = RED_CORE;    gc = RED_GLOW
	else:
		sz = minf(float(_value) * TIER_PURPLE_MULT, TIER_PURPLE_CAP); cc = PURPLE_CORE; gc = PURPLE_GLOW
	return [sz, cc, gc]

func _draw() -> void:
	var params := _tier_params()
	var sz: float     = params[0]
	var core_col: Color = params[1]
	var glow_col: Color = params[2]
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.85 + 0.15 * sin(_t * BOB_SPEED * 1.7)
	# Soft outer glow → bright core → white centre.
	draw_circle(c, sz * 1.8 * pulse, Color(glow_col.r, glow_col.g, glow_col.b, 0.15))
	draw_circle(c, sz * 1.1 * pulse, Color(glow_col.r, glow_col.g, glow_col.b, 0.30))
	draw_circle(c, sz * 0.7 * pulse, core_col)
	draw_circle(c, sz * 0.30, Color(1, 1, 1, 0.88))
