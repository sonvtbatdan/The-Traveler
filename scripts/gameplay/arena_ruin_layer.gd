extends Node2D
## Spawner for the giant dead-ship wrecks. At the start of each run it drops exactly TWO stationary
## wrecks 10,000–15,000 px from the player, positioned so the two form a ~60–120° angle as seen from the
## player's spawn point. After that, one more wreck spawns every PERIODIC_INTERVAL near the player's
## THEN-current position (not the original run-start point) so later wrecks stay reachable as the run
## goes on. Each wreck handles its own lifecycle (giant ship → orb of light on death).

const RuinScript := preload("res://scripts/gameplay/arena_ruin.gd")
const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")  # edge-of-screen icon + distance
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")   # wrecks are stationary "dummy" arena_enemy instances

const SHIP_COUNT   := 2       # wrecks spawned at run start
const DIST_MIN     := 10000.0 # minimum spawn distance from player (px)
const DIST_MAX     := 15000.0 # maximum spawn distance from player (px)
const ANGLE_MIN    := 60.0    # minimum angle (deg) between the two run-start wrecks, as seen from the player
const ANGLE_MAX    := 120.0   # maximum angle (deg) between the two run-start wrecks
const PERIODIC_INTERVAL := 180.0   # seconds between each additional wreck after the run-start pair (3 min)
const GIANT_HP     := 5000.0  # ×2 ENEMY_HP_TUNE (non-boss) → ~10,000 effective HP
const GIANT_SIZE   := 80.0    # ~4× a normal ship; scales BOTH the sprite and the hitbox
const GIANT_SPIN   := deg_to_rad(8.0)   # slow idle rotation (rad/s)

var _mgr: Node = null
var _player: Node2D = null
var _periodic_acc: float = 0.0

func _ready() -> void:
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		# Player not built yet — retry next frame.
		call_deferred("_ready")
		return
	_spawn_wrecks()

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	_periodic_acc += delta
	if _periodic_acc >= PERIODIC_INTERVAL:
		_periodic_acc -= PERIODIC_INTERVAL
		_spawn_one_wreck(_player.global_position, randf() * TAU)

func _spawn_wrecks() -> void:
	var origin := _player.global_position
	var base := randf() * TAU
	var sep := deg_to_rad(randf_range(ANGLE_MIN, ANGLE_MAX))
	if randf() < 0.5:
		sep = -sep                       # randomize which side the second wreck sits on
	var angles := [base, base + sep]
	for i in range(SHIP_COUNT):
		var a: float = angles[i]
		var dist := randf_range(DIST_MIN, DIST_MAX)
		var pos: Vector2 = origin + Vector2(cos(a), sin(a)) * dist
		_spawn_wreck(pos, randi_range(1, 4))

## One periodic wreck: a random distance out from `origin` along `angle` (used by _process, near the player's
## current position). Delegates to _spawn_wreck so the spawn path stays identical to the run-start pair.
func _spawn_one_wreck(origin: Vector2, angle: float) -> void:
	var dist := randf_range(DIST_MIN, DIST_MAX)
	var pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
	_spawn_wreck(pos, randi_range(1, 4))

func _spawn_wreck(pos: Vector2, variant: int) -> void:
	var e: Node2D = EnemyScript.new()
	# configure() must run BEFORE add_child (it sets fields _ready/_load_icon consume).
	e.configure("dead_ship", _mgr, {
		"behavior": "dummy",          # stationary + never distance-culled
		"hp": GIANT_HP,
		"speed": 0.0,
		"size": GIANT_SIZE,
		"contact": 0,                 # no contact damage — safe to fly right up to
		"xp": 0.0,                    # no XP dump (the orb of light is the reward)
		"no_collide": true,           # player flies through; no crowd-separation push
		"idle_spin": GIANT_SPIN,
		"drop_loot": "orb_of_light",  # dropped on death → pick-1-of-3 new-item choice
		"icon": "res://assets/ruin/ship%d.png" % variant,
	})
	e.position = pos                  # parent (Arena) sits at world origin, so local == global
	get_parent().add_child(e)
	_spawn_pointer(e)

## Edge-of-screen arrow + live distance guiding the player to one wreck (mirrors _spawn_reward_chest's
## pointer). Its own CanvasLayer so it renders screen-space above gameplay; freed with the wreck.
func _spawn_pointer(target: Node2D) -> void:
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays (same as the chest pointer)
	get_parent().add_child(ptr_layer)
	var ptr: Node = RuinPointerScript.new()
	ptr_layer.add_child(ptr)
	ptr.setup(target)
