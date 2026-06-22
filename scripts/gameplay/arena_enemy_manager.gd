extends Node2D
## World-space enemy services for the arena — the port of the legacy EnemyManager's API, but in world
## coordinates (no SpaceScreen). Enemies find it via group "enemy_manager" and call the SAME methods they
## did before: ship_center / ship_radius / screen_size / spawn_bullet / explode / spawn_bomb / take_lane_x /
## take_wanderer_y_offset. It owns the enemy-bullet pool + explosion FX and routes damage through GameManager.

const ArenaEnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const XpOrbScript      := preload("res://scripts/gameplay/arena_xp_orb.gd")
const LootScript       := preload("res://scripts/gameplay/arena_loot.gd")
const SFX_HIT          := preload("res://assets/audio/sfx/hit.wav")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const BULLET_RADIUS    := 5.0
const BULLET_MAX_LIFE  := 6.0
const BULLET_MAX_DIST  := 2200.0
const BULLET_COLOR     := Color(1.0, 0.45, 0.35)

const HIT_FLASH_DUR := 0.12
const HIT_FLASH_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 screen = texture(screen_texture, SCREEN_UV);
	vec3 red = vec3(0.85, 0.0, 0.0);
	vec3 blended = 1.0 - (1.0 - red) * (1.0 - screen.rgb);
	COLOR.rgb = mix(screen.rgb, blended, intensity);
	COLOR.a = 1.0;
}
"""

var _player: Node2D = null
var _bullets: Array = []      # {pos, vel, dmg, life}
var _explosions: Array = []   # {pos, age, max_age, radius}
var _lane_i: int = 0
var _wanderer_i: int = 0

var _hit_player: AudioStreamPlayer = null
var _hit_flash_rect: ColorRect = null
var _hit_flash_mat: ShaderMaterial = null
var _hit_flash_t: float = 0.0

func _ready() -> void:
	add_to_group("enemy_manager")
	z_index = -1   # bullets/explosions just under the player/enemies
	_player = get_tree().get_first_node_in_group("player")
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = SFX_HIT
	_hit_player.bus = "SFX"
	add_child(_hit_player)
	var sh := Shader.new()
	sh.code = HIT_FLASH_SHADER
	_hit_flash_mat = ShaderMaterial.new()
	_hit_flash_mat.shader = sh
	_hit_flash_mat.set_shader_parameter("intensity", 0.0)
	var cl := CanvasLayer.new()
	cl.layer = 95
	_hit_flash_rect = ColorRect.new()
	_hit_flash_rect.color = Color.WHITE
	_hit_flash_rect.material = _hit_flash_mat
	_hit_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash_rect.hide()
	cl.add_child(_hit_flash_rect)
	add_child(cl)
	GameManager.player_hit.connect(_play_hit)

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_tick_bullets(delta)
	_tick_explosions(delta)
	queue_redraw()
	if _hit_flash_rect != null:
		if _hit_flash_t > 0.0:
			_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
			var vp := get_viewport()
			if vp != null:
				_hit_flash_rect.size = vp.get_visible_rect().size
			_hit_flash_mat.set_shader_parameter("intensity", (_hit_flash_t / HIT_FLASH_DUR) * 0.35)
			_hit_flash_rect.show()
		else:
			_hit_flash_rect.hide()

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

## Deflect every enemy bullet within `radius` of `center` to fly outward at ≥ `force` px/s. Used by the
## Bulwark thruster + Guardian drone to shove incoming fire away. Returns how many bullets were pushed.
func push_bullets_away(center: Vector2, radius: float, force: float) -> int:
	var n := 0
	for b: Dictionary in _bullets:
		var p: Vector2 = b["pos"]
		var d := p.distance_to(center)
		if d <= radius:
			var away := (p - center).normalized() if d > 0.01 else Vector2.UP
			b["vel"] = away * maxf((b["vel"] as Vector2).length(), force)
			n += 1
	return n

## Offset from `center` to the nearest enemy bullet within `radius` (Vector2.ZERO if none). The Smart
## thruster reads this to nudge the ship off incoming fire.
func nearest_bullet_offset(center: Vector2, radius: float) -> Vector2:
	var best := Vector2.ZERO
	var best_d := radius
	for b: Dictionary in _bullets:
		var off: Vector2 = (b["pos"] as Vector2) - center
		var d := off.length()
		if d < best_d:
			best_d = d
			best = off
	return best

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
	# Ruin ships/boxes also take blast damage
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if ruin == source or not is_instance_valid(ruin):
			continue
		if (ruin as Node2D).global_position.distance_to(blast_center) <= blast_radius and ruin.has_method("take_damage"):
			ruin.take_damage(float(dmg))
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

## Drop a loot item (coin / diamond / heart / magnetic / shield) at a world position.
func spawn_loot(pos: Vector2, type: String) -> void:
	var l := LootScript.new()
	get_parent().add_child(l)
	l.setup(pos, type)

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

## Spawn a small flock of bee enemies near the player — used by the F12 debug palette to test plume VFX.
func spawn_bee() -> void:
	const BEE_DEF := {"behavior": "swarm_dive", "hp": 20.0, "speed": 150.0, "size": 12.0,
		"contact": 8, "explodes": true, "xp": 3, "icon": "res://assets/enemies/animalbee.png"}
	var pp := ship_center()
	for i in 6:
		var e := ArenaEnemyScript.new()
		e.configure("bee", self, BEE_DEF)
		var a := TAU * float(i) / 6.0
		e.position = pp + Vector2(cos(a), sin(a)) * 500.0
		get_parent().add_child(e)

const RETALIATION_RADIUS := 220.0   # Barbed Wire aux: enemies within this of the player take the return hit

func _play_hit() -> void:
	if _hit_player != null:
		_hit_player.stop()
		_hit_player.play()
	_hit_flash_t = HIT_FLASH_DUR
	# Barbed Wire aux item: return flat damage to nearby enemies whenever the player is hit.
	var retal: float = GameManager.upg_retaliation if "upg_retaliation" in GameManager else 0.0
	if retal > 0.0:
		var center := ship_center()
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			if (en as Node2D).global_position.distance_to(center) <= RETALIATION_RADIUS and en.has_method("take_damage"):
				en.take_damage(retal)

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
