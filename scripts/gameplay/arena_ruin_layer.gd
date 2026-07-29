extends Node2D
## Run-start spawner for the giant dead-ship wrecks. At the start of each run it spawns exactly TWO
## stationary wrecks 10,000–20,000 px from the player, positioned so the two form a ~60–120° angle as
## seen from the player's spawn point.
##
## Each wreck is a REAL arena_enemy (behavior "dummy" = sits still & is never distance-culled), so it
## takes every weapon effect + bullet bounce exactly like a normal enemy. It's configured to sit still,
## spin slowly in place, deal no contact damage, grant no XP, and drop an "orb of light" on death (→ the
## pick-1-of-3 new-item choice). An edge-of-screen arrow (arena_ruin_pointer.gd) guides the player to each.

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")  # edge-of-screen arrow + distance

const SHIP_COUNT   := 2       # wrecks spawned at run start
const DIST_MIN     := 10000.0 # minimum spawn distance from player (px)
const DIST_MAX     := 20000.0 # maximum spawn distance from player (px)
const ANGLE_MIN    := 60.0    # minimum angle (deg) between the two wrecks, as seen from the player
const ANGLE_MAX    := 120.0   # maximum angle (deg) between the two wrecks
const GIANT_HP     := 5000.0  # ×2 ENEMY_HP_TUNE (non-boss) → ~10,000 effective HP
const GIANT_SIZE   := 80.0    # ~4× a normal ship; scales BOTH the sprite and the hitbox
const GIANT_SPIN   := deg_to_rad(8.0)   # slow idle rotation (rad/s)

var _mgr: Node = null
var _player: Node2D = null

func _ready() -> void:
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not is_instance_valid(_player):
		# Player not built yet — retry next frame.
		call_deferred("_ready")
		return
	_spawn_wrecks()

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
