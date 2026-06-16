extends Node2D
## Arena spawner — periodically spawns enemies in a ring around the player (off-screen), up to a
## max-alive cap. Added as a child of the Arena; spawns enemies as siblings in world space.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SPAWN_INTERVAL    := 1.0     # seconds between spawns
const MAX_ALIVE         := 30      # cap on living enemies
const SPAWN_RADIUS      := 720.0   # ring radius around the player (off-screen at default zoom)
const SPAWN_RADIUS_VARY := 140.0   # ± jitter on the ring radius

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")

var _acc: float = 0.0
var _player: Node2D = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_acc += delta
	if _acc >= SPAWN_INTERVAL:
		_acc -= SPAWN_INTERVAL
		_spawn()

func _spawn() -> void:
	if get_tree().get_nodes_in_group("arena_enemy").size() >= MAX_ALIVE:
		return
	var ang := randf() * TAU
	var r := SPAWN_RADIUS + randf_range(-SPAWN_RADIUS_VARY, SPAWN_RADIUS_VARY)
	var e := EnemyScript.new()
	e.position = _player.global_position + Vector2(cos(ang), sin(ang)) * r
	get_parent().add_child(e)   # sibling of the player in the Arena (world space)
