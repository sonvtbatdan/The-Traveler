extends Node2D
## Arena — world-space foundation for the survival pivot (Phase 1). Builds, in code: a Player
## (CharacterBody2D) with the ship sprite + a follow Camera2D, WASD movement, mouse auto-aim, placeholder
## auto-fire, and an infinite multi-layer parallax starfield. NOTHING is ported from the old game yet
## (inventory/weapons/bosses/enemies/affixes come later). All knobs are in the TUNABLES block below.

const HudHpDisplayScript := preload("res://scripts/ui/hud/hud_hp_display.gd")
const ArenaEnemyMgrScript := preload("res://scripts/gameplay/arena_enemy_manager.gd")
const WaveDirectorScript := preload("res://scripts/gameplay/arena_wave_director.gd")
const WaveEditorScript   := preload("res://scripts/ui/hud/arena_wave_editor.gd")
const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaNebulaScript  := preload("res://scripts/gameplay/arena_nebula.gd")
const PerfOverlayScript  := preload("res://scripts/ui/hud/perf_overlay.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SHIP_SPRITE     := "res://assets/screen/Spaceship.png"
const CAM_ZOOM        := Vector2(1.0, 1.0)   # >1 zooms in, <1 zooms out
const PLAYER_SIZE_PX  := 48.0                 # ship drawn this many px on its longest side (scaled from the texture)
const PLAYER_RADIUS   := 16.0                 # collision circle radius (for later)
const MOVE_SPEED      := 320.0                # px/s
const TURN_INSTANT    := false               # true = snap to face mouse; false = eased turn
const TURN_SPEED      := 12.0                 # eased turn rate (higher = snappier)
const FIRE_INTERVAL   := 0.25                 # s between auto-fire shots
const PROJ_SPEED      := 700.0               # px/s
const PROJ_LIFETIME   := 1.5                  # s before a projectile despawns
const PROJ_MAX_DIST   := 1400.0              # px travelled before despawn (whichever first)
const PROJ_COLOR      := Color(1.0, 0.95, 0.55)
const PROJ_DAMAGE     := 10.0               # damage each projectile deals to an enemy on hit
const PROJ_HIT_RADIUS := 22.0               # projectile↔enemy hit distance (px)
const USE_PLACEHOLDER_FIRE := false         # Phase-3: real weapons (arena_weapons.gd) replace the throwaway dart
# Parallax star layers (far → near): [parallax factor, tile size, star count, dot size, brightness]
const STAR_LAYERS := [
	[0.03, 1024, 130, 1.0, 0.55],   # far, faint, sparse  (deep parallax — slow drift)
	[0.06, 1024, 90,  1.5, 0.8],    # mid
	[0.10, 1024, 55,  2.0, 1.0],    # near, bright (still deep; nothing at surface but ship/enemies)
]

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player: CharacterBody2D = null
var _fire_acc: float = 0.0
var _projectiles: Array = []   # {node, vel, life, start}

func _ready() -> void:
	randomize()                          # fresh RNG each launch → random spawn spot (below)
	add_child(ArenaNebulaScript.new())   # procedural nebula on a back CanvasLayer (behind the star dots)
	_build_parallax()
	_build_player()
	_build_ui()
	add_child(PerfOverlayScript.new())   # always-on FPS/frame-ms readout (top-right) for tuning
	add_child(ArenaEnemyMgrScript.new())  # world-space enemy services (bullets, explosions, ship pos)
	add_child(WaveDirectorScript.new())   # authored-timeline wave spawner (replaces the basic ring spawner)
	add_child(WaveEditorScript.new())     # F7 in-game wave editor (add/edit/remove waves live)
	add_child(ArenaWeaponsScript.new())   # Gatling gun + Gauss cannon, auto-firing toward the ship facing

## Screen-space HUD: host the sprite HP/shield display (reads GameManager; self-pins top-left in the arena).
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var hp := HudHpDisplayScript.new()
	hp.arena_mode = true   # re-pin the HP cluster to the top-left corner (legacy keeps its layout pos)
	ui.add_child(hp)

# ── Setup ─────────────────────────────────────────────────────────────────────
func _build_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "Player"
	_player.position = Vector2.ZERO   # stays near origin (float precision); the nebula randomizes its own patch

	var spr := Sprite2D.new()
	var tex := load(SHIP_SPRITE) as Texture2D
	spr.texture = tex
	# Scale the (large) source art down to PLAYER_SIZE_PX on its longest side.
	var longest := maxf(float(tex.get_width()), float(tex.get_height())) if tex != null else 1.0
	var s := PLAYER_SIZE_PX / maxf(1.0, longest)
	spr.scale = Vector2(s, s)
	# The ship art points UP (forward = −Y); Sprite2D rotation 0 keeps it upright.
	_player.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = PLAYER_RADIUS
	col.shape = shape
	_player.add_child(col)

	var cam := Camera2D.new()
	cam.zoom = CAM_ZOOM
	cam.enabled = true
	_player.add_child(cam)

	add_child(_player)
	_player.add_to_group("player")   # enemies/spawner find the player via this group
	cam.make_current()

func _build_parallax() -> void:
	var i := 0
	for layer in STAR_LAYERS:
		var factor: float = layer[0]
		var tile: int = int(layer[1])
		var count: int = int(layer[2])
		var dot: float = layer[3]
		var bright: float = layer[4]
		var px := Parallax2D.new()
		px.scroll_scale = Vector2(factor, factor)
		px.repeat_size = Vector2(float(tile), float(tile))
		px.repeat_times = 3
		px.z_index = -100 + i   # well behind the player/projectiles
		var spr := Sprite2D.new()
		spr.texture = _make_star_tex(tile, count, dot, bright)
		spr.centered = false
		px.add_child(spr)
		add_child(px)
		i += 1

## Build a seamless tiling star texture: random faint dots on a transparent tile (dots kept inside the
## tile so the repeated edges stay transparent → no seams).
func _make_star_tex(tile: int, count: int, dot: float, bright: float) -> Texture2D:
	var img := Image.create(tile, tile, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := int(ceil(dot))
	for _k in count:
		var cx := randi_range(r, tile - 1 - r)
		var cy := randi_range(r, tile - 1 - r)
		var b := bright * randf_range(0.5, 1.0)
		var tint := randf()   # slight blue/white variety
		var col := Color(0.8 + 0.2 * tint, 0.85 + 0.15 * tint, 1.0, b)
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if Vector2(ox, oy).length() <= dot:
					img.set_pixel(cx + ox, cy + oy, col)
	return ImageTexture.create_from_image(img)

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_player.velocity = dir * MOVE_SPEED
	_player.move_and_slide()

func _process(delta: float) -> void:
	if _player == null:
		return
	_aim(delta)
	if USE_PLACEHOLDER_FIRE:
		_fire_acc += delta
		while _fire_acc >= FIRE_INTERVAL:
			_fire_acc -= FIRE_INTERVAL
			_spawn_projectile()
		_tick_projectiles(delta)

## Smoothly rotate the ship to face the mouse (sprite forward = −Y → +PI/2 offset).
func _aim(delta: float) -> void:
	var target := (get_global_mouse_position() - _player.global_position).angle() + PI * 0.5
	if TURN_INSTANT:
		_player.rotation = target
	else:
		_player.rotation = lerp_angle(_player.rotation, target, clampf(TURN_SPEED * delta, 0.0, 1.0))

## Placeholder projectile: a little dart Polygon2D flying along the ship's current facing.
func _spawn_projectile() -> void:
	var fwd := Vector2.UP.rotated(_player.rotation)
	var proj := Polygon2D.new()
	proj.polygon = PackedVector2Array([Vector2(0, -7), Vector2(4, 5), Vector2(-4, 5)])
	proj.color = PROJ_COLOR
	proj.position = _player.global_position + fwd * 20.0
	proj.rotation = _player.rotation
	add_child(proj)
	_projectiles.append({"node": proj, "vel": fwd * PROJ_SPEED, "life": 0.0, "start": proj.position})

func _tick_projectiles(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var i := _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var n := p["node"] as Node2D
		if n == null or not is_instance_valid(n):
			_projectiles.remove_at(i)
			i -= 1
			continue
		n.position += (p["vel"] as Vector2) * delta
		p["life"] = float(p["life"]) + delta
		var dead := float(p["life"]) >= PROJ_LIFETIME or n.position.distance_to(p["start"]) >= PROJ_MAX_DIST
		# Hit test vs enemies (the new take_damage contract proves aim → fire → kill).
		if not dead:
			for en in enemies:
				if is_instance_valid(en) and n.global_position.distance_to((en as Node2D).global_position) <= PROJ_HIT_RADIUS:
					if en.has_method("take_damage"):
						en.take_damage(PROJ_DAMAGE)
					dead = true
					break
		if dead:
			n.queue_free()
			_projectiles.remove_at(i)
		i -= 1
