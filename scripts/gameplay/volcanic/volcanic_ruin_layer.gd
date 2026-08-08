extends Node2D
## Spawner for the Volcanic map's rescue-character ruin landmark — engineer.glb/psyker.glb (assets/map/
## volcanic/, moved there 2026-08-06 from assets/ruin/). Mirrors rubicon_ruin_layer.gd's combat/pointer/spin
## plumbing (VolcanicTrees.spawn_landmark() for the live .glb, arena_enemy.gd as the 2D combat/hit-detection
## vehicle, arena_ruin_pointer.gd for the edge-of-screen arrow) — see that file's header for the full rundown
## — but placement avoids the lava river the way volcanic_temple_layer.gd's temples do (VolcanicNoise.
## is_river position retry) instead of rubicon's ground-ring carving, since volcanic_ground.gd has no
## apply_landmarks equivalent.
##
##   - AT MOST ONE spawns per run — MetaManager.rescue_candidate_for_map("volcanic") decides WHICH character
##     (engineer until rescued, then psyker, then Scholar once every map's own pair is rescued) is this run's
##     target, or "" if nothing is left to offer.
##   - spawns within DIST_MAX (15000px) of the player at run start — no periodic extra spawns; one shot.
##   - spins continuously in place at ROT_RPM (volcanic's temples stay still — this is what visually marks a
##     ruin as a rescue target instead of a static landmark).
##   - on death, feeds GameManager.run_rescue_char_id/run_rescue_collected + fires the immediate "taken aboard"
##     toast (ArenaToast) — arena.gd's _show_run_over reads those at run-end for the actual rescue result line
##     and the MetaManager.unlock_room() call; this file itself never calls unlock_room.
##   - no "drop_loot" — 2026-08-06, on request: unlike the temple boss, breaking a rescue landmark does NOT
##     drop an orb of light (the rescue itself, resolved at run-end, IS the reward).

const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")
const ArenaToastScript := preload("res://scripts/ui/hud/arena_toast.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const VolcanicNoise := preload("res://scripts/gameplay/volcanic/volcanic_noise.gd")
const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")

const DIST_MIN := 10000.0   # minimum spawn distance from player (px) — matches the rubicon ruin's own range
const DIST_MAX := 15000.0   # maximum spawn distance from player (px) — "trong khoảng tối đa 15000" per request
const RIVER_AVOID_MARGIN := 1.3    # mirrors volcanic_temple_layer.gd's own margin — never spawn right at the
                                    # lava's edge either, not just literally inside it
const MAX_POSITION_TRIES := 40     # give up and accept a lava-adjacent spot rather than looping forever
const RUIN_HP := 400.0
const ENEMY_HP_TUNE := 2.0   # arena_enemy.gd's global ×2 HP tune for every non-"boss_stub" enemy — divide it
                              # back out here so RUIN_HP is the actual effective HP, not RUIN_HP*2
const RUIN_SCALE_MULT := 1.5   # matches rubicon_ruin_layer.gd's own — a personal-scale wreck, not a giant landmark
const ROT_RPM := 12.0
const ROT_SPEED := deg_to_rad(ROT_RPM * 360.0 / 60.0)   # rad/s — temples stay still, ruins spin in place

var _mgr: Node = null
var _player: Node2D = null
var _river_width: float = 0.0
var _active: Array = []   # [{key, enemy, node3d}] — 0 or 1 entries

func _ready() -> void:
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		call_deferred("_ready")   # player not built yet — retry next frame
		return
	var s := VolcanicTerrainSettings.load_settings()
	_river_width = float(s["river_width"])
	var char_id := MetaManager.rescue_candidate_for_map("volcanic")
	if char_id == "":
		return   # both engineer+psyker already rescued, and Scholar not eligible here yet (or done too)
	var pos := _pick_dry_position(_player.global_position)
	_spawn_ruin(char_id, pos)

func _process(delta: float) -> void:
	for entry: Dictionary in _active:
		var node3d: Node3D = entry["node3d"]
		if is_instance_valid(node3d):
			node3d.rotation.y += ROT_SPEED * delta

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

func _spawn_ruin(key: String, pos: Vector2) -> void:
	var trees := get_tree().get_first_node_in_group("volcanic_trees")
	if trees == null or not trees.has_method("spawn_landmark"):
		return
	var def: Dictionary = MetaManager.RESCUE_CHARACTER_DEFS[key]
	var result: Dictionary = await trees.call("spawn_landmark", String(def["glb"]), pos, RUIN_SCALE_MULT)
	if result.is_empty():
		return
	var node3d: Node3D = result["node"]
	var radius: float = float(result["radius"])

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
	var entry := {"key": key, "enemy": e, "node3d": node3d}
	_active.append(entry)
	e.tree_exited.connect(_on_ruin_gone.bind(entry))

## Freed on the enemy's own tree_exited — frees the companion 3D visual. On a GENUINE kill (gated on the
## enemy's own `_dead` flag, same convention rubicon_ruin_layer.gd's _on_ruin_gone uses), flags the run as
## having collected this rescue and fires the immediate "taken aboard" toast — the actual rescue OUTCOME
## and the MetaManager.unlock_room() call are decided later, at run-end, by arena.gd's _show_run_over.
func _on_ruin_gone(entry: Dictionary) -> void:
	var e: Node2D = entry["enemy"]
	if is_instance_valid(e) and bool(e.get("_dead")):
		GameManager.run_rescue_collected = true
		var name: String = String(MetaManager.RESCUE_CHARACTER_DEFS[entry["key"]]["name"])
		ArenaToastScript.show(self, "%s has been taken on your ship" % name)
	if is_instance_valid(entry["node3d"]):
		entry["node3d"].queue_free()
	_active.erase(entry)

## Edge-of-screen arrow + live distance guiding the player to the ruin (mirrors rubicon_ruin_layer.gd's own
## _spawn_pointer, minus the glb_path arg — see arena_ruin_pointer.gd's header on why only rescue ruins get
## the spinning-GLB icon).
func _spawn_pointer(target: Node2D, glb_path: String) -> void:
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays (same as the chest/temple pointer)
	get_parent().add_child(ptr_layer)
	var ptr: Node = RuinPointerScript.new()
	ptr_layer.add_child(ptr)
	ptr.setup(target, glb_path)
