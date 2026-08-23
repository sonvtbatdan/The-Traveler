extends Node2D
## Spawner for the temple boss landmark — exactly TEMPLE_COUNT (2) per run, each appearing at its own random
## TIME within SPAWN_WINDOW (30min of GameManager.run_time), mirroring electric_temple_layer.gd's own schedule
## (2026-08-06, on request: "Mỗi map chỉ có 2 temple random spawn vào những thời điểm ngẫu nhiên trong vòng 30
## phút run time. Bắn temple drop orb of light."). Each spawns DIST_MIN-DIST_MAX from the player's CURRENT
## position at ITS OWN scheduled moment, avoiding the lava river (VolcanicNoise.is_river position retry — no
## ElectricGround-style ground-ring system exists here to guarantee dry land after the fact).
##
## 2026-08-06: promoted from a purely visual landmark (no HP, never dies) to a full boss fight — ported the
## combat/pointer machinery from electric_temple_layer.gd verbatim (arena_enemy.gd 2D combat vehicle,
## arena_ruin_pointer.gd edge-of-screen arrow, "drop_loot": "orb_of_light" on death), exactly as this file's
## own prior header anticipated ("Port the combat machinery back from electric_temple_layer.gd if a boss fight
## is ever wanted here too — nothing here precludes it"). temple.glb is excluded from the regular
## density-scatter pool (VolcanicAssetScan.SCATTER_EXCLUDED) — this spawner, via VolcanicTrees.
## spawn_landmark(), is its only spawn path. Still stationary (no spin) — only the rescue-character ruins spin.
##
## PLUME ATTACHMENT (unchanged): volcanic_landmark_mark.gd lets the user click points on a top-down reference
## render of temple.glb (tools/bake_volcanic_landmark.gd) to mark where smoke/flame should rise from. Each
## mark is stored as a NORMALIZED local-space offset (fx, fz, each -0.5..0.5) within the bake's own reference
## frame — see LANDMARK_MARK_FRAME_MARGIN — NOT a world position, because the mark needs to follow the model
## regardless of where THIS PARTICULAR instance ends up spawning (random position) or facing (random yaw,
## from VolcanicTrees.spawn_landmark). _mark_to_world() converts one mark to that instance's actual world
## position: scale by the frame span, rotate by the instance's yaw (Vector3.rotated(UP, yaw) — same rotation
## Godot itself applies to the model, so this can't disagree with what's actually rendered), then divide the
## rotated Z by _z_comp to undo the same camera-tilt Z-foreshortening every other 2D->3D placement in this
## map's scatter system accounts for (VolcanicTrees/VolcanicAssetLayer's CAM_ISO_DEG). On death, plumes for
## that instance are explicitly cleared (clouds.clear_landmark_plumes) — landmarks are no longer permanent for
## the run now that they can die.

const VolcanicNoise := preload("res://scripts/gameplay/volcanic/volcanic_noise.gd")
const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")
const VolcanicAssetLayerScript := preload("res://scripts/gameplay/volcanic/volcanic_asset_layer.gd")
const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")

const TEMPLE_GLB_PATH := "res://assets/map/volcanic/landmark/temple.glb"
const TEMPLE_ICON_PATH := "res://assets/map/volcanic/landmark/temple.png"
const TEMPLE_COUNT := 2       # total temples for the whole run — "mỗi map chỉ có 2 temple"
const SPAWN_WINDOW := 1800.0  # 30 minutes, in seconds — matches electric_temple_layer.gd's own window
const TEMPLE_SCALE_MULT := 3.0     # matches electric_temple_layer.gd's TEMPLE_SCALE_MULT — a landmark should
									# read as much bigger than ordinary scatter decoration
const DIST_MIN := 10000.0          # matches electric_temple_layer.gd's own range (was 2500-6000, visual-only era)
const DIST_MAX := 15000.0
const TEMPLE_HP := 2000.0          # matches electric_temple_layer.gd's TEMPLE_HP
const ENEMY_HP_TUNE := 2.0         # arena_enemy.gd's global ×2 HP tune for every non-"boss_stub" enemy —
									# divide it back out so TEMPLE_HP is the actual effective HP
const RIVER_AVOID_MARGIN := 1.3    # multiplies the live river_width so a temple never spawns RIGHT at the
									# lava's edge either, not just literally inside it
const MAX_POSITION_TRIES := 40     # give up and accept a lava-adjacent spot rather than looping forever if
									# river_width is turned up very high in the Terrain Edit panel

## Must match tools/bake_volcanic_landmark.gd's own copy — the world-unit span (both axes, square frame) the
## bake camera's orthogonal view covers, as a multiple of the model's own half_extent. See this file's header.
const LANDMARK_MARK_FRAME_MARGIN := 1.15

var _mgr: Node = null
var _player: Node2D = null
var _z_comp: float = 1.0
var _river_width: float = 0.0
var _spawn_times: Array = []   # TEMPLE_COUNT random floats in [0, SPAWN_WINDOW), sorted ascending
var _spawned_count: int = 0    # how many of _spawn_times have already fired
var _active: Array = []   # [{"id": int, "enemy": Node2D, "pos": Vector2, "yaw": float, "half_extent": Vector2, "node": Node3D}]
var _next_id: int = 0

func _ready() -> void:
	add_to_group("volcanic_temple_layer")   # so volcanic_landmark_mark.gd can find this instance and re-sync
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_z_comp = 1.0 / cos(deg_to_rad(VolcanicAssetLayerScript.CAM_ISO_DEG))
	var s := VolcanicTerrainSettings.load_settings()
	_river_width = float(s["river_width"])
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		call_deferred("_ready")   # player not built yet — retry next frame
		return
	_spawn_times.clear()
	for _i in TEMPLE_COUNT:
		_spawn_times.append(randf() * SPAWN_WINDOW)
	_spawn_times.sort()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	while _spawned_count < _spawn_times.size() and GameManager.run_time >= float(_spawn_times[_spawned_count]):
		_spawned_count += 1
		var pos := _pick_dry_position(_player.global_position)
		_spawn_one(pos)

func _pick_dry_position(origin: Vector2) -> Vector2:
	var half_width: float = _river_width * RIVER_AVOID_MARGIN
	var pos := origin
	for _try in MAX_POSITION_TRIES:
		var angle := randf() * TAU
		var dist := randf_range(DIST_MIN, DIST_MAX)
		pos = origin + Vector2(cos(angle), sin(angle)) * dist
		if half_width <= 0.0 or not VolcanicNoise.is_river(pos, half_width):
			return pos
	return pos   # exhausted retries — accept whatever the last roll was rather than looping forever

func _spawn_one(pos: Vector2) -> void:
	var trees := get_tree().get_first_node_in_group("volcanic_trees")
	if trees == null or not trees.has_method("spawn_landmark"):
		return
	var result: Dictionary = await trees.call("spawn_landmark", TEMPLE_GLB_PATH, pos, TEMPLE_SCALE_MULT)
	if result.is_empty():
		return
	var node3d: Node3D = result["node"]
	var radius: float = float(result["radius"])
	var half_extent: Vector2 = result["half_extent"]
	var yaw: float = float(result["yaw"])

	var e: Node2D = EnemyScript.new()
	# configure() must run BEFORE add_child (it sets fields _ready/_load_icon consume).
	e.configure("temple", _mgr, {
		"behavior": "dummy",          # stationary + never distance-culled
		"hp": TEMPLE_HP / ENEMY_HP_TUNE,
		"speed": 0.0,
		"size": radius,               # 2D hit-radius matches the real 3D model's measured footprint
		"contact": 0,                 # no contact damage — safe to fly right up to
		"xp": 0.0,                    # no XP dump (the orb of light is the reward)
		"no_collide": true,           # player flies through; no crowd-separation push
		"drop_loot": "orb_of_light",  # dropped on death → pick-1-of-3 new-item choice
		"icon": TEMPLE_ICON_PATH,     # never actually drawn (sprite_alpha 0) — only feeds the pointer's arrow
		"sprite_alpha": 0.0,          # the live 3D model (node3d) is the real visual, not this 2D sprite
	})
	e.position = pos                  # parent (Arena) sits at world origin, so local == global
	get_parent().add_child(e)
	_spawn_pointer(e)

	var id := _next_id
	_next_id += 1
	var entry := {
		"id": id, "enemy": e, "pos": pos, "yaw": yaw,
		"half_extent": half_extent, "node": node3d,
	}
	_active.append(entry)
	_push_plumes_for(entry)
	e.tree_exited.connect(_on_temple_gone.bind(entry))

## Freed on the enemy's own tree_exited (fires once its death-pop animation finishes and arena_enemy.gd
## queue_free()s itself, or if it's ever removed any other way) — frees the companion 3D visual, clears this
## temple's plumes, and drops it out of _active. Also fires GameManager.boss_defeated on a GENUINE kill
## (gated on the enemy's own `_dead` flag, same convention as electric_temple_layer.gd's own _on_temple_gone)
## so temples feed the same salvage-screen/blueprint pipeline as every other boss.
##
## 2026-08-18 crash fix: at end-of-run (RETURN TO DOCK -> get_tree().change_scene_to_file(), arena.gd) the whole
## scene tree tears down, which fires the enemy's tree_exited (and this callback) WHILE this very node may
## already be outside the tree itself — get_tree() on a node not currently in the tree returns null, so calling
## .get_first_node_in_group() on it crashed the game ("Cannot call method 'get_first_node_in_group' on a null
## value"). Guard it like atlantic_temple_layer.gd's own _on_temple_gone already does.
func _on_temple_gone(entry: Dictionary) -> void:
	var e: Node2D = entry["enemy"]
	if is_instance_valid(e) and bool(e.get("_dead")) and GameManager.has_signal("boss_defeated"):
		GameManager.boss_defeated.emit()
	var tree := get_tree()
	if tree != null:
		var clouds := tree.get_first_node_in_group("volcanic_clouds")
		if clouds != null and clouds.has_method("clear_landmark_plumes"):
			clouds.call("clear_landmark_plumes", entry["id"])
	if is_instance_valid(entry["node"]):
		entry["node"].queue_free()
	_active.erase(entry)

## Public: called by volcanic_landmark_mark.gd (live, whenever a mark is added/removed on either tab) — re-
## reads the persisted marks and re-registers every currently-spawned landmark's plumes from scratch.
func refresh_landmark_marks() -> void:
	for entry: Dictionary in _active:
		_push_plumes_for(entry)

func _push_plumes_for(entry: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var clouds := tree.get_first_node_in_group("volcanic_clouds")
	if clouds == null or not clouds.has_method("set_landmark_plumes"):
		return
	var s := VolcanicTerrainSettings.load_settings()
	var entries: Array = []
	for kind: String in ["smoke", "flame"]:
		var marks: Array = s.get("landmark_marks_%s" % kind, [])
		for m: Dictionary in marks:
			entries.append({"kind": kind, "pos": _mark_to_world(entry, float(m.get("fx", 0.0)), float(m.get("fz", 0.0)))})
	clouds.call("set_landmark_plumes", entry["id"], entries)

## Converts one landmark-mark (fx, fz, each -0.5..0.5 — see this file's header) to a world position for THIS
## specific spawned `entry` (its own yaw + half_extent, since scale/facing differ per instance).
func _mark_to_world(entry: Dictionary, fx: float, fz: float) -> Vector2:
	var half_extent: Vector2 = entry["half_extent"]
	var frame_span: float = maxf(half_extent.x, half_extent.y) * 2.0 * LANDMARK_MARK_FRAME_MARGIN
	var local := Vector3(fx * frame_span, 0.0, fz * frame_span)
	var rotated := local.rotated(Vector3.UP, float(entry["yaw"]))
	var pos: Vector2 = entry["pos"]
	return pos + Vector2(rotated.x, rotated.z / _z_comp)

## Edge-of-screen arrow + live distance guiding the player to one temple (mirrors electric_temple_layer.gd's
## own _spawn_pointer exactly — arena_ruin_pointer.gd is generic, takes any Node2D target).
func _spawn_pointer(target: Node2D) -> void:
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays (same as the chest/ruin pointer)
	get_parent().add_child(ptr_layer)
	var ptr: Node = RuinPointerScript.new()
	ptr_layer.add_child(ptr)
	ptr.setup(target)
