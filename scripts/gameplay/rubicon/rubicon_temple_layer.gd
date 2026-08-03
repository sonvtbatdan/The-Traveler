extends Node2D
## Spawner for the giant temple boss landmark — same spawn rule as arena_ruin_layer.gd's dead-ship wrecks
## (2 stationary landmarks 10,000-15,000 px from the player at run start, ~60-120° apart as seen from the
## player's spawn point, then one more every PERIODIC_INTERVAL near the player's THEN-current position), but
## rendered as the REAL temple.glb model (via RubiconTrees.spawn_landmark(), the same shared 3D pass every
## scattered tree/cloud-occluder renders through) instead of a flat 2D wreck sprite. temple.glb is excluded
## from the regular density-scatter pool (RubiconAssetScan.SCATTER_EXCLUDED) — this is its only spawn path.
##
## Combat/HP/hit-detection/loot-on-death still goes through the normal 2D EnemyScript (arena_enemy.gd) — that
## system has no notion of a live 3D visual, so this enemy is configured with "sprite_alpha": 0.0 (its own
## flat icon never actually draws) while still loading "icon" so arena_ruin_pointer.gd's edge-of-screen arrow
## can borrow that texture (_tex) same as it does for a real wreck. The temple's own baked icon (temple.png,
## tools/bake_rubicon_trees.gd) exists purely for that pointer.
##
## Ground gets a golden worn-clearing area under/around each currently-alive temple (RubiconGround.
## apply_landmarks) — solid-filled from the model's own center out to its actual BASE footprint (an oriented
## box from spawn_landmark's half_extent/yaw, not a circle) plus a ring margin, and that fill also suppresses
## the river mask beneath it (rubicon_ground.gdshader's final_river_mask) — so ground is GUARANTEED under the
## temple no matter where it spawns, without this spawner needing to search for dry land itself; position is
## picked the same simple way as arena_ruin_layer.gd's dead-ship wrecks. Pushed every time a temple spawns or
## dies.

const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")

const TEMPLE_GLB_PATH := "res://assets/map/rubicon/temple.glb"
const TEMPLE_ICON_PATH := "res://assets/map/rubicon/temple.png"

const TEMPLE_COUNT := 2       # temples spawned at run start — matches arena_ruin_layer.gd's SHIP_COUNT
const DIST_MIN     := 10000.0 # minimum spawn distance from player (px)
const DIST_MAX     := 15000.0 # maximum spawn distance from player (px)
const ANGLE_MIN    := 60.0    # minimum angle (deg) between the two run-start temples, as seen from the player
const ANGLE_MAX    := 120.0   # maximum angle (deg) between the two run-start temples
const PERIODIC_INTERVAL := 180.0   # seconds between each additional temple after the run-start pair (3 min)
const TEMPLE_HP := 2000.0
const ENEMY_HP_TUNE := 2.0   # arena_enemy.gd's global ×2 HP tune for every non-"boss_stub" enemy — must divide
                              # it back out of "hp" here so the temple's actual displayed/effective hp_max
                              # comes out to exactly TEMPLE_HP, not TEMPLE_HP*2 (verified via debug_temple_spawn)
const TEMPLE_SCALE_MULT := 3.0   # 3x the regular auto-scale every scattered type gets (RubiconTrees.
                                  # DESIRED_HEIGHT_PX) — a landmark boss should read as much bigger than
                                  # ordinary decoration; the 2D hit-radius scales with it (spawn_landmark)

var _mgr: Node = null
var _player: Node2D = null
var _periodic_acc: float = 0.0
var _active: Array = []   # [{enemy, node3d, pos, radius}] — every currently-alive temple

func _ready() -> void:
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		call_deferred("_ready")   # player not built yet — retry next frame
		return
	_spawn_temples()

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	_periodic_acc += delta
	if _periodic_acc >= PERIODIC_INTERVAL:
		_periodic_acc -= PERIODIC_INTERVAL
		var angle := randf() * TAU
		var dist := randf_range(DIST_MIN, DIST_MAX)
		var pos: Vector2 = _player.global_position + Vector2(cos(angle), sin(angle)) * dist
		_spawn_temple(pos)

func _spawn_temples() -> void:
	var origin := _player.global_position
	var base := randf() * TAU
	var sep := deg_to_rad(randf_range(ANGLE_MIN, ANGLE_MAX))
	if randf() < 0.5:
		sep = -sep   # randomize which side the second temple sits on
	var angles := [base, base + sep]
	for i in range(TEMPLE_COUNT):
		var a: float = angles[i]
		var dist := randf_range(DIST_MIN, DIST_MAX)
		var pos: Vector2 = origin + Vector2(cos(a), sin(a)) * dist
		_spawn_temple(pos)

func _spawn_temple(pos: Vector2) -> void:
	var trees := get_tree().get_first_node_in_group("rubicon_trees")
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

	var entry := {"enemy": e, "node3d": node3d, "pos": pos, "radius": radius, "half_extent": half_extent, "yaw": yaw}
	_active.append(entry)
	_push_landmarks()
	e.tree_exited.connect(_on_temple_gone.bind(entry))

## Freed on the enemy's own tree_exited (fires once its death-pop animation finishes and arena_enemy.gd
## queue_free()s itself, or if it's ever removed any other way) — frees the companion 3D visual and drops
## this temple out of the ground's ring set.
func _on_temple_gone(entry: Dictionary) -> void:
	if is_instance_valid(entry["node3d"]):
		entry["node3d"].queue_free()
	_active.erase(entry)
	_push_landmarks()

func _push_landmarks() -> void:
	if not is_inside_tree():
		return   # whole scene tearing down (run end/quit) — nothing to push to, and get_tree() would error
	var ground := get_tree().get_first_node_in_group("rubicon_ground")
	if ground == null or not ground.has_method("apply_landmarks"):
		return
	var landmarks: Array = []
	for entry: Dictionary in _active:
		landmarks.append({
			"pos": entry["pos"], "radius": entry["radius"],
			"half_extent": entry["half_extent"], "yaw": entry["yaw"],
		})
	ground.call("apply_landmarks", landmarks)

## Edge-of-screen arrow + live distance guiding the player to one temple (mirrors arena_ruin_layer.gd's own
## _spawn_pointer exactly — arena_ruin_pointer.gd is generic, takes any Node2D target).
func _spawn_pointer(target: Node2D) -> void:
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays (same as the chest/ruin pointer)
	get_parent().add_child(ptr_layer)
	var ptr: Node = RuinPointerScript.new()
	ptr_layer.add_child(ptr)
	ptr.setup(target)
