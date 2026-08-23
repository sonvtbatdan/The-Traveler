extends Node2D
## Spawner for the Electric (electric) map's rescue-character ruin landmark — constructor.glb
## (assets/map/electric/landmark/) rendered/fought exactly like electric_temple_layer.gd's temple boss
## (ElectricTrees.spawn_landmark() for the live .glb, arena_enemy.gd as the 2D combat/hit-detection
## vehicle, arena_ruin_pointer.gd for the edge-of-screen arrow, ElectricGround.apply_landmarks for the
## dry-land clearing ring — see electric_temple_layer.gd's own header for the full rundown of that
## shared plumbing), but:
##   - spawns only if Constructor isn't rescued yet — MetaManager.rescue_candidate_for_map("electric")
##     returns "constructor" or "" (2026-08-19: Electric owns exactly one rescue character now, no
##     queue/fallback — see RESCUE_MAP_QUEUE's own doc comment).
##   - spawns within DIST_MAX (15000px) of the player at run start — no periodic extra spawns; one shot.
##   - spins continuously in place at ROT_RPM (temples stay still — this is what visually marks a ruin as a
##     rescue target instead of a static landmark).
##   - on death, feeds GameManager.run_rescue_char_id/run_rescue_collected + fires the immediate "taken aboard"
##     toast (ArenaToast) — arena.gd's _show_run_over reads those at run-end for the actual rescue result line
##     ("successfully rescued" / "failed rescued" / "not found") and the MetaManager.unlock_room() call; this
##     file itself never calls unlock_room (a death after collecting still shouldn't unlock).
##   - no "drop_loot" — 2026-08-06, on request: unlike the temple boss, breaking a rescue landmark does NOT
##     drop an orb of light (the rescue itself, resolved at run-end, IS the reward).

const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")
const ArenaToastScript := preload("res://scripts/ui/hud/arena_toast.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")

const DIST_MIN := 10000.0   # minimum spawn distance from player (px) — matches electric_temple_layer.gd's own
const DIST_MAX := 15000.0   # maximum spawn distance from player (px) — "trong khoảng tối đa 15000" per request
const RUIN_HP := 400.0
const ENEMY_HP_TUNE := 2.0   # arena_enemy.gd's global ×2 HP tune for every non-"boss_stub" enemy — divide it
                              # back out here so RUIN_HP is the actual effective HP, not RUIN_HP*2 (same
                              # compensation electric_temple_layer.gd's own TEMPLE_HP does)
const RUIN_SCALE_MULT := 1.5   # bigger than the default DESIRED_HEIGHT_PX scatter scale, smaller than the
                                 # temple's 3x — reads as a personal-scale wreck, not a giant landmark
const ROT_RPM := 12.0
const ROT_SPEED := deg_to_rad(ROT_RPM * 360.0 / 60.0)   # rad/s — temples stay still, ruins spin in place

var _mgr: Node = null
var _player: Node2D = null
var _active: Array = []   # [{key, enemy, node3d, pos, radius, half_extent, yaw}] — 0 or 1 entries

func _ready() -> void:
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		call_deferred("_ready")   # player not built yet — retry next frame
		return
	var char_id := MetaManager.rescue_candidate_for_map("electric")
	if char_id == "":
		return   # Constructor already rescued
	var angle := randf() * TAU
	var dist := randf_range(DIST_MIN, DIST_MAX)
	var pos: Vector2 = _player.global_position + Vector2(cos(angle), sin(angle)) * dist
	_spawn_ruin(char_id, pos)

func _process(delta: float) -> void:
	for entry: Dictionary in _active:
		var node3d: Node3D = entry["node3d"]
		if is_instance_valid(node3d):
			node3d.rotation.y += ROT_SPEED * delta

func _spawn_ruin(key: String, pos: Vector2) -> void:
	var trees := get_tree().get_first_node_in_group("electric_trees")
	if trees == null or not trees.has_method("spawn_landmark"):
		return
	var def: Dictionary = MetaManager.RESCUE_CHARACTER_DEFS[key]
	var result: Dictionary = await trees.call("spawn_landmark", String(def["glb"]), pos, RUIN_SCALE_MULT)
	if result.is_empty():
		return
	var node3d: Node3D = result["node"]
	var radius: float = float(result["radius"])
	var half_extent: Vector2 = result["half_extent"]
	var yaw: float = float(result["yaw"])

	var e: Node2D = EnemyScript.new()
	# configure() must run BEFORE add_child (it sets fields _ready/_load_icon consume).
	e.configure("ruin_" + key, _mgr, {
		"behavior": "dummy",          # stationary + never distance-culled
		"hp": RUIN_HP / ENEMY_HP_TUNE,
		"speed": 0.0,
		"size": radius,               # 2D hit-radius matches the real 3D model's measured footprint
		"contact": 0,                 # no contact damage — safe to fly right up to
		"xp": 0.0,                    # no XP dump — not a normal kill (mirrors temple's own convention)
		"no_collide": true,           # player flies through; no crowd-separation push
		"icon": String(def["icon"]),  # never actually drawn (sprite_alpha 0) — only feeds the pointer's arrow
		"sprite_alpha": 0.0,          # the live 3D model (node3d) is the real visual, not this 2D sprite
	})
	e.position = pos                  # parent (Arena) sits at world origin, so local == global
	get_parent().add_child(e)
	_spawn_pointer(e, String(def["glb"]))

	GameManager.run_rescue_char_id = key
	var entry := {"key": key, "enemy": e, "node3d": node3d, "pos": pos, "radius": radius, "half_extent": half_extent, "yaw": yaw}
	_active.append(entry)
	_push_landmarks()
	e.tree_exited.connect(_on_ruin_gone.bind(entry))

## Freed on the enemy's own tree_exited — frees the companion 3D visual and drops this ruin out of the
## ground's ring set. On a GENUINE kill (gated on the enemy's own `_dead` flag, same convention electric_
## temple_layer.gd's _on_temple_gone uses), flags the run as having collected this rescue and fires the
## immediate "taken aboard" toast — the actual rescue OUTCOME (successfully/failed rescued) and the
## MetaManager.unlock_room() call are decided later, at run-end, by arena.gd's _show_run_over.
func _on_ruin_gone(entry: Dictionary) -> void:
	var e: Node2D = entry["enemy"]
	if is_instance_valid(e) and bool(e.get("_dead")):
		GameManager.run_rescue_collected = true
		var name: String = String(MetaManager.RESCUE_CHARACTER_DEFS[entry["key"]]["name"])
		ArenaToastScript.show(self, "%s has been taken on your ship" % name)
	if is_instance_valid(entry["node3d"]):
		entry["node3d"].queue_free()
	_active.erase(entry)
	_push_landmarks()

func _push_landmarks() -> void:
	if not is_inside_tree():
		return   # whole scene tearing down (run end/quit) — nothing to push to, and get_tree() would error
	var ground := get_tree().get_first_node_in_group("electric_ground")
	if ground == null or not ground.has_method("apply_landmarks"):
		return
	var landmarks: Array = []
	for entry: Dictionary in _active:
		landmarks.append({
			"pos": entry["pos"], "radius": entry["radius"],
			"half_extent": entry["half_extent"], "yaw": entry["yaw"],
		})
	ground.call("apply_landmarks", landmarks, "ruin")   # own source key — see ElectricGround.apply_landmarks

## Edge-of-screen arrow + live distance guiding the player to the ruin (mirrors electric_temple_layer.gd's own
## _spawn_pointer, minus the glb_path arg — see arena_ruin_pointer.gd's header on why only rescue ruins get
## the spinning-GLB icon).
func _spawn_pointer(target: Node2D, glb_path: String) -> void:
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays (same as the chest/temple pointer)
	get_parent().add_child(ptr_layer)
	var ptr: Node = RuinPointerScript.new()
	ptr_layer.add_child(ptr)
	ptr.setup(target, glb_path)
