extends Node2D
## FRAME-RATE STRESS HARNESS — standalone scene (run it directly with F6).
##
## Loads the REAL arena (scenes/arena.tscn — so every manager, the player, camera, weapons, and the plume/orb
## MultiMeshes are wired exactly as in-game), then after a short settle it BURST-SPAWNS a full horde at once:
## ENEMY_COUNT enemies scattered across the screen + ORB_COUNT XP orbs to walk over and collect. A top-left
## overlay shows live FPS + enemy/orb counts so you can measure the horde cost directly.
##
## The player is made effectively unkillable and set to max level for the duration so (a) the horde doesn't end
## the test in two seconds and (b) collecting the orb pile doesn't trigger the level-up screen mid-measurement.

const ArenaScene  := preload("res://scenes/arena.tscn")
const Director     := preload("res://scripts/gameplay/arena_wave_director.gd")   # reuse its ENEMY_DEFS table
const EnemyScript  := preload("res://scripts/gameplay/arena_enemy.gd")

# ── EDIT THESE ────────────────────────────────────────────────────────────────
const ENEMY_COUNT := 500     # label total; actual composition is COMPOSITION below
const ORB_COUNT   := 500
const SPAWN_DELAY := 0.6      # let the arena finish _ready + its deferred setup before the burst
const FILL_RADIUS := 720.0    # enemies scattered in a disc this big around the player (fills the screen)
const ORB_SPREAD  := 520.0    # XP orbs scattered in a ±box this size around the player
# Horde composition: [enemy type, how many]. Currently 400 flies + 100 bugs.
const COMPOSITION: Array = [
	["fly", 400],
	["bug", 100],
]

var _arena: Node = null
var _rng := RandomNumberGenerator.new()
var _label: Label = null
var _spawned: bool = false
var _acc: float = 0.0

# ── Diagnostic isolation toggles (bisect the bottleneck) ──────────────────────
# Press 1-4 while the test runs; whichever one makes FPS jump when turned OFF is the dominant cost.
var _sep_on: bool = true        # [1] enemy-vs-enemy separation pass (manager _physics_process)
var _enemies_visible: bool = true  # [2] enemy body drawing (hide = no _draw / no sprite render, logic still runs)
var _orbs_visible: bool = true  # [3] XP-orb MultiMesh rendering
var _weapons_on: bool = true    # [4] weapon firing/processing
var _plumes_visible: bool = true  # [5] enemy plume MultiMesh (ADDITIVE → prime overdraw suspect when clumped)
var _glow_on: bool = true       # [6] glow/bloom post-process (full-screen every frame — top fixed-cost suspect)
var _nebula_on: bool = true     # [7] procedural nebula background shader (full-screen every frame)
var _world_env: WorldEnvironment = null
var _nebula: CanvasItem = null
var _phys_cap: bool = false     # [8] cap physics to 1 tick/frame — if this jumps FPS, the substep spiral is the cause

func _ready() -> void:
	_rng.randomize()
	_arena = ArenaScene.instantiate()
	add_child(_arena)
	_build_overlay()

func _build_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 200   # above the arena HUD
	add_child(cl)
	_label = Label.new()
	_label.position = Vector2(14.0, 44.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.70))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	cl.add_child(_label)

func _process(delta: float) -> void:
	if not _spawned:
		_acc += delta
		if _acc >= SPAWN_DELAY:
			_burst()
			_spawned = true
	if _label != null:
		var enemies := get_tree().get_nodes_in_group("arena_enemy").size()
		var orbs := 0
		var om := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
		if om != null:
			var n: Variant = om.get("_n")
			if n != null:
				orbs = int(n)
		# Godot's live monitors — proc_ms + phys_ms = CPU (script); if both are low but FPS is low too, it's GPU.
		# Separation runs in the manager's _physics_process, so it shows up specifically in phys_ms.
		var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var state := "spawning in %.1fs" % maxf(0.0, SPAWN_DELAY - _acc) if not _spawned else "LIVE"
		_label.text = "FPS %d   ·   proc %.1fms   ·   phys %.1fms   ·   draws %d\nenemies %d   ·   orbs %d   ·   [%s]\ntoggles:  [1] sep %s  [2] enemy-draw %s  [3] orbs %s  [4] weapons %s  [5] plumes %s  [6] glow %s  [7] nebula %s  [8] phys-cap %s" % [
			Engine.get_frames_per_second(), proc_ms, phys_ms, draws,
			enemies, orbs, state,
			_on(_sep_on), _on(_enemies_visible), _on(_orbs_visible), _on(_weapons_on), _on(_plumes_visible), _on(_glow_on), _on(_nebula_on), _on(_phys_cap)]

func _on(b: bool) -> String:
	return "ON" if b else "off"

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			_sep_on = not _sep_on
			var m := get_tree().get_first_node_in_group("enemy_manager")
			if m != null:
				(m as Node).set_physics_process(_sep_on)   # separation is the manager's ONLY _physics_process
		KEY_2:
			_enemies_visible = not _enemies_visible
			for e in get_tree().get_nodes_in_group("arena_enemy"):
				if e is CanvasItem:
					(e as CanvasItem).visible = _enemies_visible   # hidden = no _draw / no GPU sprite; logic still runs
		KEY_3:
			_orbs_visible = not _orbs_visible
			var om := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
			if om is CanvasItem:
				(om as CanvasItem).visible = _orbs_visible
		KEY_4:
			_weapons_on = not _weapons_on
			var w := get_tree().get_first_node_in_group("arena_weapons")
			if w != null:
				(w as Node).set_process(_weapons_on)
				(w as Node).set_physics_process(_weapons_on)
		KEY_5:
			_plumes_visible = not _plumes_visible
			var pm := get_tree().get_first_node_in_group("arena_plume_mgr")
			if pm is CanvasItem:
				(pm as CanvasItem).visible = _plumes_visible
		KEY_6:
			_glow_on = not _glow_on
			_find_fx()
			if _world_env != null and _world_env.environment != null:
				_world_env.environment.glow_enabled = _glow_on
		KEY_7:
			_nebula_on = not _nebula_on
			_find_fx()
			if _nebula != null:
				_nebula.visible = _nebula_on
		KEY_8:
			_phys_cap = not _phys_cap
			Engine.max_physics_steps_per_frame = 1 if _phys_cap else 8   # 1 = no catch-up spiral

## Locate the glow WorldEnvironment + the nebula node inside the instanced arena (cached after first find).
func _find_fx() -> void:
	if (_world_env != null and _nebula != null) or _arena == null:
		return
	var stack: Array = [_arena]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _world_env == null and n is WorldEnvironment:
			_world_env = n as WorldEnvironment
		if _nebula == null and n is CanvasItem:
			var scr: Script = n.get_script() as Script
			if scr != null and scr.resource_path.ends_with("arena_nebula.gd"):
				_nebula = n as CanvasItem
		for c in n.get_children():
			stack.append(c)

func _burst() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var mgr := get_tree().get_first_node_in_group("enemy_manager")
	if player == null or _arena == null:
		return
	var center := player.global_position
	# Keep the test running: max level (no level-up pause on the mass orb collect) + a huge HP pool.
	if "player_level" in GameManager and "MAX_LEVEL" in GameManager:
		GameManager.player_level = GameManager.MAX_LEVEL
	if "ship_max_hp" in GameManager:
		GameManager.ship_max_hp = 100_000_000
	if "ship_hp" in GameManager:
		GameManager.ship_hp = 100_000_000
	# Enemies scattered across a screen-filling disc around the player, per COMPOSITION (400 fly + 100 bug).
	var defs: Dictionary = Director.ENEMY_DEFS
	for entry: Array in COMPOSITION:
		var type_id := String(entry[0])
		var count := int(entry[1])
		if not defs.has(type_id):
			push_warning("test_frame_rate: unknown enemy type '%s'" % type_id)
			continue
		for i in count:
			var def: Dictionary = (defs[type_id] as Dictionary).duplicate()
			var e := EnemyScript.new()
			e.configure(type_id, mgr, def)
			# Uniform-ish disc scatter (sqrt for even area density).
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * FILL_RADIUS
			e.position = center + Vector2(cos(a), sin(a)) * r
			_arena.add_child(e)
	# 500 XP orbs scattered near the player (walk over them to collect — tests the batched-collect path).
	var om := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
	if om != null and om.has_method("spawn"):
		for i in ORB_COUNT:
			var p := center + Vector2(_rng.randf_range(-ORB_SPREAD, ORB_SPREAD), _rng.randf_range(-ORB_SPREAD, ORB_SPREAD))
			om.call("spawn", p, _rng.randf_range(1.0, 8.0))
