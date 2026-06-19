extends Node2D
## Arena — world-space foundation for the survival pivot (Phase 1). Builds, in code: a Player
## (CharacterBody2D) with the ship sprite + a follow Camera2D, WASD movement, mouse auto-aim, placeholder
## auto-fire, and an infinite multi-layer parallax starfield. NOTHING is ported from the old game yet
## (inventory/weapons/bosses/enemies/affixes come later). All knobs are in the TUNABLES block below.

const HudHpDisplayScript := preload("res://scripts/ui/hud/hud_hp_display.gd")
const ArenaEnemyMgrScript := preload("res://scripts/gameplay/arena_enemy_manager.gd")
const WaveDirectorScript := preload("res://scripts/gameplay/arena_wave_director.gd")
const TestTemplateScript := preload("res://scripts/gameplay/test_template.gd")
const WaveEditorScript   := preload("res://scripts/ui/hud/arena_wave_editor.gd")
const USE_TEST_SPAWNER   := false   # true → use test_template.gd (spawn one enemy every 5s) instead of the timeline
const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaNebulaScript  := preload("res://scripts/gameplay/arena_nebula.gd")
const ArenaDustScript    := preload("res://scripts/gameplay/arena_dust.gd")
const ArenaPlanetsScript := preload("res://scripts/gameplay/arena_planets.gd")
const ArenaAsteroidsScript := preload("res://scripts/gameplay/arena_asteroids.gd")
const ArenaCometsScript    := preload("res://scripts/gameplay/arena_comets.gd")
const ArenaStructuresScript := preload("res://scripts/gameplay/arena_structures.gd")
const ArenaSolarSystemScript := preload("res://scripts/gameplay/arena_solar_system.gd")
const ArenaDofScript     := preload("res://scripts/gameplay/arena_dof.gd")
const PlanetMenuScript   := preload("res://scripts/ui/hud/arena_planet_menu.gd")
const DebugSpawnScript   := preload("res://scripts/gameplay/arena_debug_spawn.gd")
const PerfOverlayScript  := preload("res://scripts/ui/hud/perf_overlay.gd")
const LevelUpUIScript    := preload("res://scripts/ui/hud/arena_levelup_ui.gd")
const ArenaRuinLayerScript := preload("res://scripts/gameplay/arena_ruin_layer.gd")
const ArenaHudButtonsScript := preload("res://scripts/ui/hud/arena_hud_buttons.gd")
const RESET_RUN_ON_START := true   # each arena run starts a fresh VS climb (level 1, no upgrades). Flip off to keep saved level.

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
# Solar-system start + soft boundary (world space; the player flies the world, the system orbits origin).
const PLAYER_START   := Vector2(0.0, -1100.0)   # offset from origin so the player doesn't spawn on the sun
const SOFT_BOUNDARY  := 9000.0                   # past Neptune's reach; gentle inward drift begins here
const HARD_BOUNDARY  := 10500.0                  # absolute clamp (player can't pass)
const BOUNDARY_PULL  := 2.2                      # inward drift past the soft edge (per second × overshoot px)
const VIGNETTE_FADE  := 2200.0                   # distance the edge vignette fades in over, before SOFT
const BOUNDARY_VIGNETTE_SHADER := "res://assets/shaders/boundary_vignette.gdshader"

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player: CharacterBody2D = null
var _ship_spr: Sprite2D = null
var _tex_normal: Texture2D = null
var _tex_lean: Texture2D = null
var _fire_acc: float = 0.0
var _projectiles: Array = []   # {node, vel, life, start}
var _edge_vignette_mat: ShaderMaterial = null   # boundary "edge of system" cue

func _ready() -> void:
	randomize()                          # fresh RNG each launch → random spawn spot (below)
	if RESET_RUN_ON_START and GameManager.has_method("reset_run"):
		GameManager.reset_run()          # fresh VS climb: level 1, no upgrades, full HP
	# Depth-of-field: all non-gameplay layers render into the DoF SubViewport (blurred/dimmed/desaturated
	# behind the sharp gameplay plane). bg is that SubViewport; parallax/streaming are unchanged because its
	# camera is synced to the main camera each frame.
	var dof := ArenaDofScript.new()
	add_child(dof)
	var bg: Node = dof.background_parent()   # DoF SubViewport, or the arena itself when the mask is disabled
	add_child(ArenaNebulaScript.new())      # procedural nebula — EXCLUDED from the blur (stays sharp in the
	                                        # main viewport at CL -10, behind the DoF composite at CL -5)
	bg.add_child(ArenaDustScript.new())     # dark space dust, lit by ship/weapon lights
	var planets := ArenaPlanetsScript.new()      # sparse mid-parallax procedural planets (z -50)
	var comets := ArenaCometsScript.new()        # rare mid-parallax comets (z -48)
	var structures := ArenaStructuresScript.new() # rare huge gas/dust structures (z -60, slow far parallax)
	var asteroids := ArenaAsteroidsScript.new()  # fast near-parallax asteroid fields (z -10, sells speed)
	# Authored solar system (replaces random planet scatter): planets/belt on the blurred 0.40 layer; its sun
	# is hosted in the MAIN viewport (sharp, excluded from the blur).
	var solar := ArenaSolarSystemScript.new()
	solar.sun_host = self
	if ArenaDofScript.ENABLED:               # per-layer depth dim only when the mask is on
		planets.modulate = ArenaDofScript.MID_MODULATE
		comets.modulate = ArenaDofScript.MID_MODULATE
		structures.modulate = ArenaDofScript.FAR_MODULATE
		asteroids.modulate = ArenaDofScript.MID_MODULATE
		solar.modulate = ArenaDofScript.MID_MODULATE
	bg.add_child(planets)                    # streaming OFF (helpers/F10 only); solar system provides planets
	bg.add_child(comets)
	bg.add_child(structures)
	bg.add_child(asteroids)
	bg.add_child(solar)
	add_child(PlanetMenuScript.new())    # F6 menu: inspect/drag-spawn planets (input stays in the main viewport)
	add_child(DebugSpawnScript.new())    # F5 asteroids / F9 comet / F10 planet+moons (Shift = clear)
	add_child(ArenaHudButtonsScript.new())  # bottom-right HUD: Setting / Devon / Quit
	_build_parallax(bg)
	_build_player()
	_build_ui()
	_build_boundary_vignette()
	add_child(PerfOverlayScript.new())   # always-on FPS/frame-ms readout (top-right) for tuning
	add_child(LevelUpUIScript.new())     # VS choose-1-of-3 on level-up (pauses the game)
	add_child(ArenaEnemyMgrScript.new())  # world-space enemy services (bullets, explosions, ship pos)
	if USE_TEST_SPAWNER:
		add_child(TestTemplateScript.new())   # quick test: one enemy every 5s
	else:
		add_child(WaveDirectorScript.new())   # authored-timeline wave spawner
		add_child(WaveEditorScript.new())     # F7 in-game wave editor (add/edit/remove waves live)
	add_child(ArenaWeaponsScript.new())   # Gatling gun + Gauss cannon, auto-firing toward the ship facing
	add_child(ArenaRuinLayerScript.new()) # periodic ruin ships (every 5–15s): ship → box → loot drop

## Full-screen "edge of system" vignette; its intensity is driven by player→boundary proximity each frame.
func _build_boundary_vignette() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 90   # above gameplay, below the perf overlay (99) / settings (100)
	add_child(cl)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(BOUNDARY_VIGNETTE_SHADER)
	m.set_shader_parameter("intensity", 0.0)
	rect.material = m
	cl.add_child(rect)
	_edge_vignette_mat = m

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
	_player.position = PLAYER_START   # offset from the sun at origin (solar system orbits world origin)

	var spr := Sprite2D.new()
	var tex := load(SHIP_SPRITE) as Texture2D
	_tex_normal = tex
	_tex_lean   = load("res://assets/screen/lean.png") as Texture2D
	spr.texture = tex
	# Scale the (large) source art down to PLAYER_SIZE_PX on its longest side.
	var longest := maxf(float(tex.get_width()), float(tex.get_height())) if tex != null else 1.0
	var s := PLAYER_SIZE_PX / maxf(1.0, longest)
	spr.scale = Vector2(s, s)
	# The ship art points UP (forward = −Y); Sprite2D rotation 0 keeps it upright.
	_ship_spr = spr
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

func _build_parallax(parent: Node) -> void:
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
		if ArenaDofScript.ENABLED:
			px.modulate = ArenaDofScript.FAR_MODULATE   # deepest layer → recede most (only when the mask is on)
		var spr := Sprite2D.new()
		spr.texture = _make_star_tex(tile, count, dot, bright)
		spr.centered = false
		px.add_child(spr)
		parent.add_child(px)   # into the DoF SubViewport (blurred background)
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
func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed_mult: float = GameManager.get_move_speed_mult() if GameManager.has_method("get_move_speed_mult") else 1.0
	_player.velocity = dir * MOVE_SPEED * speed_mult
	_update_ship_lean(dir)
	_player.move_and_slide()
	_apply_boundary(delta)

## Soft outer edge: past SOFT_BOUNDARY the player drifts gently back inward (stronger the further out), and is
## hard-clamped at HARD_BOUNDARY. A screen vignette fades in as the edge nears. Not a wall — a current.
func _apply_boundary(delta: float) -> void:
	var pos := _player.global_position
	var d := pos.length()
	if d > SOFT_BOUNDARY and d > 0.0:
		var inward := -pos / d
		_player.global_position += inward * (d - SOFT_BOUNDARY) * BOUNDARY_PULL * delta
		if d > HARD_BOUNDARY:
			_player.global_position = (pos / d) * HARD_BOUNDARY
	if _edge_vignette_mat != null:
		var f := clampf((d - (SOFT_BOUNDARY - VIGNETTE_FADE)) / VIGNETTE_FADE, 0.0, 1.0)
		_edge_vignette_mat.set_shader_parameter("intensity", f)

func _update_ship_lean(dir: Vector2) -> void:
	if _ship_spr == null:
		return
	# Project world-space movement onto the ship's local right axis so lean is
	# correct regardless of which way the ship is facing.
	var local_x := dir.dot(Vector2.RIGHT.rotated(_player.rotation))
	var new_tex: Texture2D
	var flip: bool
	if local_x < -0.1:
		new_tex = _tex_lean
		flip = false
	elif local_x > 0.1:
		new_tex = _tex_lean
		flip = true
	else:
		new_tex = _tex_normal
		flip = false
	if _ship_spr.texture == new_tex and _ship_spr.flip_h == flip:
		return
	_ship_spr.texture = new_tex
	_ship_spr.flip_h = flip
	if new_tex != null:
		var longest := maxf(float(new_tex.get_width()), float(new_tex.get_height()))
		var s := PLAYER_SIZE_PX / maxf(1.0, longest)
		_ship_spr.scale = Vector2(s, s)

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
