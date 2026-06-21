extends Control

## EnemyManager — owns every normal enemy, the reusable enemy bullet, and the cross-faction
## explosion. Added as a child of SpaceScreen (full-rect), so its own and its enemies' coordinates are
## SpaceScreen-local — the same space weapon_system bullets use. Group: "enemy_manager".
##
## It is also the single place that knows the ship's current position/hitbox (for enemy contact +
## enemy bullets + explosions), found by locating the spaceship EditableObjectNode in ObjectsContainer
## exactly like gun_system does.

const SS_OFFSET := Vector2(15.0, 8.0)   # SpaceScreen origin in viewport/ObjectsContainer coords

const EnemyDummy := preload("res://scripts/gameplay/enemy_dummy.gd")
const EnemyDiver := preload("res://scripts/gameplay/enemy_diver.gd")
const EnemyShooter := preload("res://scripts/gameplay/enemy_shooter.gd")
const EnemySentinel := preload("res://scripts/gameplay/enemy_sentinel.gd")
const EnemyBombingWanderer := preload("res://scripts/gameplay/enemy_bombing_wanderer.gd")
const EnemyBomb := preload("res://scripts/gameplay/enemy_bomb.gd")
const EnemySwarmFlock := preload("res://scripts/gameplay/enemy_swarm_flock.gd")
const EnemySwarmMember := preload("res://scripts/gameplay/enemy_swarm.gd")
const EnemyBeamer := preload("res://scripts/gameplay/enemy_beamer.gd")
const EnemyMissileLauncher := preload("res://scripts/gameplay/enemy_missile_launcher.gd")
const EnemyBeeHiveFlock := preload("res://scripts/gameplay/enemy_bee_flock.gd")
const EnemyBugFlock := preload("res://scripts/gameplay/enemy_bug_flock.gd")
const EnemyFliesFlock := preload("res://scripts/gameplay/enemy_flies_flock.gd")
const EnemyCentipede := preload("res://scripts/gameplay/enemy_centipede.gd")
const EnemyDragonfly := preload("res://scripts/gameplay/enemy_dragonfly.gd")
const EnemyOctopus := preload("res://scripts/gameplay/enemy_octopus.gd")
const EnemySpider := preload("res://scripts/gameplay/enemy_spider.gd")

# Reusable enemy bullet tuning.
const BULLET_RADIUS := 5.0
const BULLET_COLOR  := Color(1.0, 0.55, 0.2)
const BULLET_MAX_LIFE := 6.0

var _oc: Control = null                 # ObjectsContainer (to find the ship EO)
var _ship_eo: EditableObjectNode = null
var _bullets: Array = []                # {pos, vel, dmg, life}
var _explosions: Array = []             # {center, radius, t, life} — visual rings only
var _screen_size: Vector2 = Vector2(700.0, 764.0)   # passed in (don't trust the Control's own .size)

func setup(oc: Control, screen_size: Vector2) -> void:
	_oc = oc
	_screen_size = screen_size
	# Set the rect explicitly — full-rect anchors don't resolve .size in time for spawn math, which is
	# why all internal positioning uses _screen_size (the asteroid layer takes screen size the same way).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = screen_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true   # keep enemies/bullets inside the play area (like the asteroid layer)
	z_index = 2   # above asteroids (1), below weapon FX (50)
	add_to_group("enemy_manager")

## Play-area size in SpaceScreen-local coords. Use this, NOT the Control's .size, for spawn math.
func screen_size() -> Vector2:
	return _screen_size

# ── Ship position (SpaceScreen-local), mirroring gun_system / weapon_system ────
func _find_ship() -> EditableObjectNode:
	if _ship_eo != null and is_instance_valid(_ship_eo):
		return _ship_eo
	if _oc == null or not is_instance_valid(_oc):
		return null
	for ch in _oc.get_children():
		var eo := ch as EditableObjectNode
		if eo != null and eo.source_path.get_file().get_basename().to_lower() == "spaceship":
			_ship_eo = eo
			return eo
	return null

func ship_center() -> Vector2:
	var eo := _find_ship()
	if eo == null:
		return _screen_size * 0.5
	return (eo.get_global_transform() * (eo.size * 0.5)) - global_position

func ship_radius() -> float:
	var eo := _find_ship()
	if eo == null:
		return 19.0
	return eo.size.x * 0.5 * eo.scale.x - 5.0

# ── Reusable enemy bullet ─────────────────────────────────────────────────────
## Spawn one enemy bullet at `pos` (SpaceScreen-local) moving at `vel` px/s, dealing `dmg` to the ship.
func spawn_bullet(pos: Vector2, vel: Vector2, dmg: int) -> void:
	_bullets.append({"pos": pos, "vel": vel, "dmg": dmg, "life": 0.0})

func _tick_bullets(delta: float) -> void:
	if _bullets.is_empty():
		return
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
		elif float(b["life"]) > BULLET_MAX_LIFE or p.x < -20.0 or p.x > _screen_size.x + 20.0 or p.y < -20.0 or p.y > _screen_size.y + 20.0:
			_bullets.remove_at(i)
		i -= 1

# ── Cross-faction explosion (bombs) ───────────────────────────────────────────
## Damage EVERYTHING in a radius — other enemies, the boss, and the player — from one call.
##   • enemies: iterate the "normal_enemy" group and apply on_weapon_hit (their armor DR applies)
##   • boss:    GameManager.take_boss_damage if the boss hit rect overlaps the blast
##   • player:  GameManager.ship_take_damage if the ship circle overlaps the blast
func explode(blast_center: Vector2, blast_radius: float, dmg: int, source: Node = null) -> void:
	# Player
	if ship_center().distance_to(blast_center) <= blast_radius + ship_radius():
		GameManager.ship_take_damage(dmg)
	# Boss (its hit rect is in ObjectsContainer coords → shift by SS_OFFSET to SpaceScreen-local)
	var bf := get_tree().get_first_node_in_group("boss_fight")
	if bf != null and bf.has_method("get_boss_hit_rect"):
		var br: Rect2 = bf.get_boss_hit_rect()
		if br.has_area():
			var br_ss := Rect2(br.position - SS_OFFSET, br.size)
			if _circle_hits_rect(blast_center, blast_radius, br_ss):
				GameManager.take_boss_damage(dmg)
	# Other enemies (duck-typed — every node in this group is a NormalEnemy subclass)
	for n in get_tree().get_nodes_in_group("normal_enemy"):
		if n == source or not n.has_method("on_weapon_hit"):
			continue
		if n.center().distance_to(blast_center) <= blast_radius + n.radius():
			n.on_weapon_hit(float(dmg))
	_explosions.append({"center": blast_center, "radius": blast_radius, "t": 0.0, "life": 0.4})
	queue_redraw()

func _tick_explosions(delta: float) -> void:
	if _explosions.is_empty():
		return
	var i := _explosions.size() - 1
	while i >= 0:
		_explosions[i]["t"] = float(_explosions[i]["t"]) + delta
		if float(_explosions[i]["t"]) >= float(_explosions[i]["life"]):
			_explosions.remove_at(i)
		i -= 1

func _circle_hits_rect(c: Vector2, r: float, rect: Rect2) -> bool:
	var nx := clampf(c.x, rect.position.x, rect.position.x + rect.size.x)
	var ny := clampf(c.y, rect.position.y, rect.position.y + rect.size.y)
	return Vector2(nx, ny).distance_to(c) <= r

# ── Spawning (called by the stat-panel debug buttons) ─────────────────────────
func spawn_dummy() -> void:
	var e := EnemyDummy.new()
	add_child(e)   # _ready() computes the size from HP
	var px := randf_range(_screen_size.x * 0.2, _screen_size.x * 0.8)
	e.position = Vector2(px - e.size.x * 0.5, _screen_size.y * 0.25)

# Horizontal fan-out lanes: top-entering enemies pull a lane so consecutive spawns don't stack.
const FAN_LANES := 5
var _lane: int = 0

## Next evenly-spaced spawn x (px), cycling across FAN_LANES (10/30/50/70/90% of the width).
func take_lane_x() -> float:
	var f := (float(_lane % FAN_LANES) + 0.5) / float(FAN_LANES)
	_lane += 1
	return _screen_size.x * f

# Small vertical stagger so simultaneous Bombing_wanderers (same height) don't overlap.
const WANDERER_ROWS := 3
const WANDERER_ROW_GAP := 50.0
var _wrow: int = 0

func take_wanderer_y_offset() -> float:
	var o := (float(_wrow % WANDERER_ROWS) - float(WANDERER_ROWS - 1) * 0.5) * WANDERER_ROW_GAP
	_wrow += 1
	return o

## One Diver "spawn" = a burst of DV_BURST_COUNT from the SAME edge. Member 0 is the lead (tracks
## the player's live position while off-screen); the other two oscillate alongside it. Each enters
## DV_BURST_DELAY after the previous (deterministic per-member stagger — no coroutine). All tracking +
## oscillation lives in the enemy itself, so the manager just assigns roles.
## `h_speed_delta` is added to the dash speed of divers entering from a HORIZONTAL edge (left/right) — a
## choreography can pass a negative value to make side divers slower. 0 = unchanged (the default).
func spawn_diver(edges: Array = [], h_speed_delta: float = 0.0) -> void:
	var pool: Array = edges if not edges.is_empty() else EnemyDiver.DV_EDGES
	var edge: String = String(pool[randi() % pool.size()]) if not pool.is_empty() else "top"
	var delta: float = h_speed_delta if (edge == "left" or edge == "right") else 0.0
	var n: int = EnemyDiver.DV_BURST_COUNT
	for i in n:
		var e := EnemyDiver.new()
		add_child(e)
		e.spawn_member(self, edge, i == 0, float(i) * EnemyDiver.DV_BURST_DELAY, delta)

## Generic spawn dispatcher used by the wave director: spawn one "unit" of `type`, passing recipe
## `edges` where the enemy uses them (only the Diver today). Type names match LevelRecipe.ENEMY_TYPES.
func spawn_type(type: String, edges: Array = []) -> void:
	match type:
		"diver":             spawn_diver(edges)
		"shooter":           spawn_shooter()
		"sentinels":         spawn_sentinels()
		"bombing_wanderer":  spawn_bombing_wanderer()
		"swarm":             spawn_swarm()
		"beamer":            spawn_beamer()
		"missile_launcher":  spawn_missile_launcher()
		"bee":               spawn_bee()
		"bug":               spawn_bug()
		"flies":             spawn_flies()
		"centipede":         spawn_centipede()
		"dragonfly":         spawn_dragonfly()
		"octopus":           spawn_octopus()
		"spider":            spawn_spider()

func spawn_shooter() -> void:
	var e := EnemyShooter.new()
	add_child(e)
	e.spawn(self)

## One Beamer — a stationary orb that charges + fires a laser at the player. Spawns in the upper band.
func spawn_beamer() -> void:
	var e := EnemyBeamer.new()
	add_child(e)   # _ready() computes its size
	var px := randf_range(_screen_size.x * 0.3, _screen_size.x * 0.7)
	e.position = Vector2(px, _screen_size.y * 0.22) - e.size * 0.5

## One Missile_launcher — a tanky stationary enemy that descends to the upper band and fires a one-shot
## fan of boomerang plasma darts. Positions itself in spawn() (centred, top entry).
func spawn_missile_launcher() -> void:
	var e := EnemyMissileLauncher.new()
	add_child(e)   # _ready() computes its size from HP
	e.spawn(self)

func spawn_sentinels() -> void:
	var count: int = EnemySentinel.SE_COUNT
	for i in count:
		var e := EnemySentinel.new()
		add_child(e)
		e.spawn(self, i, count)

# ── Choreography spawn helpers: create ONE enemy at a chosen spot and RETURN it, so a choreography can
# script its movement / connect its death. (Used by Enemy_group_1; harmless for anything else.) ──

## One Beamer returned to the caller so a choreography can set external_control, position, and aim().
## (Created unpositioned; the choreography places it.) Returns the node.
func spawn_beamer_node() -> Node:
	var e := EnemyBeamer.new()
	add_child(e)   # _ready() computes its size
	return e

## One Sentinel descending to the stationary row at column `x` (px). Returns the node.
func spawn_sentinel_at(x: float) -> Node:
	var e := EnemySentinel.new()
	add_child(e)
	e.spawn_at(self, x)
	return e

## Vertical mirror of spawn_sentinel_at: the Sentinel enters from the BOTTOM, rises to a bottom-mirrored
## stop, and fires UP. Used by Enemy_group_1_inverse. Returns the node.
func spawn_sentinel_at_inverted(x: float) -> Node:
	var e := EnemySentinel.new()
	add_child(e)
	e.flip_v = true          # set before spawn_at so it picks the mirrored entry/stop
	e.spawn_at(self, x)
	return e

## One Sentinel descending to an EXPLICIT parking point `center_pos` (px). Returns the node.
func spawn_sentinel_at_pos(center_pos: Vector2) -> Node:
	var e := EnemySentinel.new()
	add_child(e)
	e.spawn_at_pos(center_pos.x, center_pos.y)
	return e

## One externally-controlled Shooter appearing at `center_pos` (px, SpaceScreen-local), firing as normal
## while the choreography drives its position. Returns the node.
func spawn_shooter_external(center_pos: Vector2) -> Node:
	var e := EnemyShooter.new()
	add_child(e)
	e.spawn_external(self, center_pos)
	return e

## One solo Diver (a lead that tracks + aims at the player) from `edge`. Returns the node.
func spawn_diver_solo(edge: String) -> Node:
	var e := EnemyDiver.new()
	add_child(e)
	e.spawn_member(self, edge, true, 0.0)
	return e

## One "launch" Diver erupting from `origin` with initial velocity `vel_up` (fountain → dive). Returns it.
func spawn_diver_launch(origin: Vector2, vel_up: Vector2) -> Node:
	var e := EnemyDiver.new()
	add_child(e)
	e.spawn_launch(self, origin, vel_up)
	return e

## Visual-only explosion ring at `center` (no damage) — used for the Sentinel-death pop in Enemy_group_1.
func flash_explosion(center: Vector2, radius: float) -> void:
	_explosions.append({"center": center, "radius": radius, "t": 0.0, "life": 0.4})
	queue_redraw()

## One bare swarm bead (no circle flock) — a choreography drives it via set_track_pose / begin_zoom.
## Used by Enemy_group_2 to trace custom shapes (box + DIE). Returns the node.
func spawn_swarm_member() -> Node:
	var m := EnemySwarmMember.new()
	add_child(m)
	return m

func spawn_bombing_wanderer() -> void:
	var e := EnemyBombingWanderer.new()
	add_child(e)
	e.spawn(self)

## One Bombing_wanderer returned to the caller so a choreography can track its death. `side` ("left"/
## "right"/"") forces the entry edge. Returns the node.
func spawn_bombing_wanderer_node(side: String = "") -> Node:
	var e := EnemyBombingWanderer.new()
	add_child(e)
	e.spawn(self, side)
	return e

## Drop a bomb at `pos` (SpaceScreen-local). Called by the Bombing_wanderer.
func spawn_bomb(pos: Vector2) -> void:
	var b := EnemyBomb.new()
	add_child(b)
	b.position = pos - b.size * 0.5

## Debug: spawn a lone bomb (upper-middle) so the explosion can be tested directly from the panel.
func spawn_bomb_test() -> void:
	spawn_bomb(Vector2(_screen_size.x * 0.5, _screen_size.y * 0.3))

## Active swarm-flock stations: each concurrent swarm takes a distinct slot (0=left,1=right,2+=lower
## rows) so they don't overlap. Slots free up when a flock is wiped, so they recycle.
var _swarm_slots: Dictionary = {}

func _next_free_swarm_slot() -> int:
	var s := 0
	while _swarm_slots.has(s):
		s += 1
	return s

func spawn_swarm() -> void:
	var slot := _next_free_swarm_slot()
	_swarm_slots[slot] = true
	var flock := EnemySwarmFlock.new()
	add_child(flock)
	flock.setup(self, slot)
	flock.spawn_flock()
	flock.tree_exited.connect(_on_swarm_freed.bind(slot))

func _on_swarm_freed(slot: int) -> void:
	_swarm_slots.erase(slot)

## One swarm circle (flock) whose ring forms centered at `ring_center` (px), entering from a side.
## Returns the flock node (it frees itself once all members are gone). For choreographies.
func spawn_swarm_at(ring_center: Vector2, from_left: bool = true) -> Node:
	var flock := EnemySwarmFlock.new()
	add_child(flock)
	flock.setup(self, 0)
	flock.spawn_flock_at(ring_center, from_left)
	return flock

## ── Animal-group spawners ─────────────────────────────────────────────────────

func spawn_bee() -> void:
	var flock := EnemyBeeHiveFlock.new()
	add_child(flock)
	flock.setup(self)
	flock.spawn_flock()

func spawn_bug() -> void:
	var flock := EnemyBugFlock.new()
	add_child(flock)
	flock.setup(self)
	flock.spawn_flock()

func spawn_flies() -> void:
	var flock := EnemyFliesFlock.new()
	add_child(flock)
	flock.setup(self)
	flock.spawn_flock()

func spawn_centipede() -> void:
	var e := EnemyCentipede.new()
	add_child(e)
	e.spawn(self)

func spawn_dragonfly() -> void:
	var e := EnemyDragonfly.new()
	add_child(e)
	e.spawn(self)

func spawn_octopus() -> void:
	var e := EnemyOctopus.new()
	add_child(e)
	e.spawn(self)

func spawn_spider() -> void:
	var e := EnemySpider.new()
	add_child(e)
	e.spawn(self)

func clear_enemies() -> void:
	for n in get_tree().get_nodes_in_group("normal_enemy"):
		if n.has_method("despawn"):
			n.despawn()
	_bullets.clear()
	_explosions.clear()
	queue_redraw()

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick_bullets(delta)
	_tick_explosions(delta)
	if not _bullets.is_empty() or not _explosions.is_empty():
		queue_redraw()

func _draw() -> void:
	# Oblong bullet oriented along travel: dark-red rim → red → light → white core (layered gradient).
	for b: Dictionary in _bullets:
		var p: Vector2 = b["pos"]
		var v: Vector2 = b["vel"]
		var ang := v.angle() if (v as Vector2).length() > 0.01 else 0.0
		var ca := cos(ang)
		var sa := sin(ang)
		draw_colored_polygon(_bullet_oblong(p, 8.0, 4.6, ca, sa, 18), Color(0.40, 0.0, 0.0))      # dark rim
		draw_colored_polygon(_bullet_oblong(p, 6.3, 3.5, ca, sa, 18), Color(0.85, 0.10, 0.06))    # red
		draw_colored_polygon(_bullet_oblong(p, 4.3, 2.4, ca, sa, 16), Color(1.0, 0.55, 0.45))     # light red
		draw_colored_polygon(_bullet_oblong(p, 2.5, 1.5, ca, sa, 14), Color(1.0, 1.0, 1.0))       # white core
	for ex: Dictionary in _explosions:
		var a := 1.0 - clampf(float(ex["t"]) / maxf(0.01, float(ex["life"])), 0.0, 1.0)
		draw_arc(ex["center"], float(ex["radius"]), 0.0, TAU, 32, Color(1.0, 0.6, 0.2, a), 3.0)

## Points of an ellipse (half-extents rx along travel, ry across) centred at `c`, rotated by (ca,sa) =
## (cos,sin) of the travel angle. Used to draw the oblong bullet's concentric gradient layers.
func _bullet_oblong(c: Vector2, rx: float, ry: float, ca: float, sa: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segs)
	for i in segs:
		var t := TAU * float(i) / float(segs)
		var x := rx * cos(t)
		var y := ry * sin(t)
		pts[i] = c + Vector2(x * ca - y * sa, x * sa + y * ca)
	return pts
