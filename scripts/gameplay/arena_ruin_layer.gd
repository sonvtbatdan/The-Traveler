extends Node2D
## Run-start spawner for the giant dead-ship wrecks. At the start of each run it drops exactly TWO
## stationary wrecks 10,000–20,000 px from the player, positioned so the two form a ~60–120° angle
## as seen from the player's spawn point. Each wreck handles its own lifecycle (giant ship → orb of
## light on death). This replaces the old periodic small-ruin drip.

const RuinScript := preload("res://scripts/gameplay/arena_ruin.gd")
const RuinPointerScript := preload("res://scripts/ui/hud/arena_ruin_pointer.gd")  # edge-of-screen arrow + distance

const SHIP_COUNT   := 2       # wrecks spawned at run start
const DIST_MIN     := 10000.0 # minimum spawn distance from player (px)
const DIST_MAX     := 20000.0 # maximum spawn distance from player (px)
const ANGLE_MIN    := 60.0    # minimum angle (deg) between the two wrecks, as seen from the player
const ANGLE_MAX    := 120.0   # maximum angle (deg) between the two wrecks

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
		var r: Node2D = RuinScript.new()
		get_parent().add_child(r)
		r.setup(randi_range(1, 4), _mgr)
		r.global_position = pos
		_spawn_pointer(r)

## Edge-of-screen arrow + live distance guiding the player to one wreck (mirrors _spawn_reward_chest's
## pointer). Its own CanvasLayer so it renders screen-space above gameplay; freed with the wreck.
func _spawn_pointer(target: Node2D) -> void:
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays (same as the chest pointer)
	get_parent().add_child(ptr_layer)
	var ptr: Node = RuinPointerScript.new()
	ptr_layer.add_child(ptr)
	ptr.setup(target)
