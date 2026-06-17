extends Node2D
## A collectible XP orb dropped by a dying enemy. Sits and gently bobs until the player comes within their
## pickup radius (GameManager.get_pickup_radius() — widened by the Magnet upgrade), then magnetizes toward the
## player, accelerating as it closes. On reaching the player it grants its XP (GameManager.add_xp) and pops.
## Lives on the gameplay plane (sharp, not blurred). Persists until collected (survival-friendly).

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const ORB_SIZE            := 5.0
const COLLECT_RADIUS      := 16.0
const MAGNET_SPEED        := 120.0    # starting fly speed once magnetized naturally (px/s)
const MAGNET_ACCEL        := 900.0    # acceleration when magnetized naturally (px/s²)
const MAGNET_MAX          := 1400.0   # speed cap for natural magnetization
const FORCE_MAGNET_ACCEL  := 600.0    # acceleration when pulled by magnetic item (0→1200 in 2s)
const FORCE_MAGNET_MAX    := 1200.0   # speed cap for forced magnetization
const BOB_AMP        := 2.5
const BOB_SPEED      := 3.0
const CORE_COLOR     := Color(0.45, 1.0, 0.7)
const GLOW_COLOR     := Color(0.30, 0.95, 0.85)

var _value: int = 1
var _vel := Vector2.ZERO
var _magnetized := false
var _force_magnet := false   # true when pulled by the magnetic loot item (starts from 0 speed)
var _t := 0.0
var _player: Node2D = null

func setup(world_pos: Vector2, value: int) -> void:
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

func _draw() -> void:
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.85 + 0.15 * sin(_t * BOB_SPEED * 1.7)
	# Soft outer glow → bright core → white centre.
	draw_circle(c, ORB_SIZE * 2.4 * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.18))
	draw_circle(c, ORB_SIZE * 1.5 * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.35))
	draw_circle(c, ORB_SIZE * pulse, CORE_COLOR)
	draw_circle(c, ORB_SIZE * 0.45, Color(1, 1, 1, 0.9))
