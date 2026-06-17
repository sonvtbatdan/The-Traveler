extends Node2D
## World-space enemy services for the arena — the port of the legacy EnemyManager's API, but in world
## coordinates (no SpaceScreen). Enemies find it via group "enemy_manager" and call the SAME methods they
## did before: ship_center / ship_radius / screen_size / spawn_bullet / explode / spawn_bomb / take_lane_x /
## take_wanderer_y_offset. It owns the enemy-bullet pool + explosion FX and routes damage through GameManager.

const ArenaEnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const XpOrbScript := preload("res://scripts/gameplay/arena_xp_orb.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const BULLET_RADIUS    := 5.0
const BULLET_MAX_LIFE  := 6.0
const BULLET_MAX_DIST  := 2200.0
const BULLET_COLOR     := Color(1.0, 0.45, 0.35)

var _player: Node2D = null
var _bullets: Array = []      # {pos, vel, dmg, life}
var _explosions: Array = []   # {pos, age, max_age, radius}
var _lane_i: int = 0
var _wanderer_i: int = 0

func _ready() -> void:
	add_to_group("enemy_manager")
	z_index = -1   # bullets/explosions just under the player/enemies
	_player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_tick_bullets(delta)
	_tick_explosions(delta)
	queue_redraw()

# ── Legacy API (now world-space) ───────────────────────────────────────────────
func ship_center() -> Vector2:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position

func ship_radius() -> float:
	return 16.0   # matches arena.PLAYER_RADIUS

## The visible view size in world units (viewport / camera zoom). Used as the off-screen spawn extent.
func screen_size() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom if cam != null else Vector2.ONE
	return Vector2(vp.x / maxf(0.01, z.x), vp.y / maxf(0.01, z.y))

## Round-robin lane x across the current view width, in world coords (around the player).
func take_lane_x() -> float:
	var lanes := [0.1, 0.3, 0.5, 0.7, 0.9]
	var f: float = lanes[_lane_i % lanes.size()]
	_lane_i += 1
	var vs := screen_size()
	return ship_center().x - vs.x * 0.5 + vs.x * f

func take_wanderer_y_offset() -> float:
	var rows := [-50.0, 0.0, 50.0]
	var o: float = rows[_wanderer_i % rows.size()]
	_wanderer_i += 1
	return o

# ── Enemy bullets ───────────────────────────────────────────────────────────────
func spawn_bullet(pos: Vector2, vel: Vector2, dmg: int) -> void:
	_bullets.append({"pos": pos, "vel": vel, "dmg": dmg, "life": 0.0, "start": pos})

func _tick_bullets(delta: float) -> void:
	var sc := ship_center()
	var sr := ship_radius()
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var p: Vector2 = b["pos"]
		if p.distance_to(sc) <= sr + BULLET_RADIUS:
			GameManager.ship_take_damage(int(b["dmg"]))
			_bullets.remove_at(i)
		elif float(b["life"]) >= BULLET_MAX_LIFE or p.distance_to(b["start"]) >= BULLET_MAX_DIST:
			_bullets.remove_at(i)
		i -= 1

# ── Explosions (cross-faction blast) ────────────────────────────────────────────
func explode(blast_center: Vector2, blast_radius: float, dmg: int, source: Node = null) -> void:
	# Player
	if ship_center().distance_to(blast_center) <= blast_radius + ship_radius():
		GameManager.ship_take_damage(dmg)
	# All enemies (skip the source so a bomb doesn't re-hit itself in a chain)
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if en == source or not is_instance_valid(en):
			continue
		if (en as Node2D).global_position.distance_to(blast_center) <= blast_radius and en.has_method("take_damage"):
			en.take_damage(float(dmg))
	_explosions.append({"pos": blast_center, "age": 0.0, "max_age": 0.4, "radius": blast_radius})

func _tick_explosions(delta: float) -> void:
	var i := _explosions.size() - 1
	while i >= 0:
		var e: Dictionary = _explosions[i]
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) >= float(e["max_age"]):
			_explosions.remove_at(i)
		i -= 1

## Drop a collectible XP orb at a world position (gameplay plane → sharp, magnetizes to the player).
func spawn_xp_orb(pos: Vector2, value: int) -> void:
	var o := XpOrbScript.new()
	get_parent().add_child(o)   # same gameplay container as the enemies
	o.setup(pos, value)

## Drop a bomb enemy at a world position (falls toward the player, explodes on contact/death).
func spawn_bomb(pos: Vector2) -> void:
	var b := ArenaEnemyScript.new()
	b.configure("bomb", self)
	b.position = pos
	get_parent().add_child(b)

## Throw a FAST bomb from `pos` aimed straight at the player (it auto-aims on init, explodes on contact).
func throw_bomb(pos: Vector2) -> void:
	var b := ArenaEnemyScript.new()
	b.configure("thrown_bomb", self)
	b.position = pos
	get_parent().add_child(b)

# ── Draw bullets + explosion rings (world space) ───────────────────────────────
func _draw() -> void:
	for b: Dictionary in _bullets:
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		var dir := v.normalized() if v.length() > 0.01 else Vector2.UP
		var tail := p - dir * 9.0
		draw_line(tail, p, Color(BULLET_COLOR.r, BULLET_COLOR.g, BULLET_COLOR.b, 0.5), 3.0)
		draw_circle(p, BULLET_RADIUS, BULLET_COLOR)
		draw_circle(p, BULLET_RADIUS * 0.5, Color(1, 1, 1, 0.9))
	for e: Dictionary in _explosions:
		var t := clampf(float(e["age"]) / maxf(0.01, float(e["max_age"])), 0.0, 1.0)
		var r := float(e["radius"]) * (0.4 + 0.6 * t)
		draw_arc(e["pos"], r, 0.0, TAU, 32, Color(1.0, 0.55, 0.2, 1.0 - t), 3.0)
		draw_circle(e["pos"], r * 0.5, Color(1.0, 0.7, 0.3, (1.0 - t) * 0.4))
