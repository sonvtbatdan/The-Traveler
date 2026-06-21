extends Node2D
## Periodic spawner for ruin ships. Every 5–15 seconds it drops one random ship (variant 1–4) just
## off-screen around the player. The spawned node handles its own lifecycle (ship → box → loot).

const RuinScript := preload("res://scripts/gameplay/arena_ruin.gd")

const SPAWN_MIN    := 5.0    # minimum seconds between spawns
const SPAWN_MAX    := 15.0   # maximum seconds between spawns
const RING_MIN     := 650.0  # minimum spawn distance from player (px)
const RING_MAX     := 800.0  # maximum spawn distance from player (px)

var _timer: float = 0.0
var _mgr: Node = null
var _player: Node2D = null

func _ready() -> void:
	_timer = randf_range(SPAWN_MIN, SPAWN_MAX)
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	_timer -= delta
	if _timer <= 0.0:
		_spawn_ship()
		_timer = randf_range(SPAWN_MIN, SPAWN_MAX)

func _spawn_ship() -> void:
	var angle := randf() * TAU
	var dist := randf_range(RING_MIN, RING_MAX)
	var pos := _player.global_position + Vector2(cos(angle), sin(angle)) * dist
	var r: Node2D = RuinScript.new()
	get_parent().add_child(r)
	r.setup(randi_range(1, 4), _mgr)
	r.global_position = pos
