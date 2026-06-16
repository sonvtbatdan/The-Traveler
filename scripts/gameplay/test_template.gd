extends Node2D
## QUICK ENEMY TEST HARNESS. Spawns ONE enemy of ENEMY_TYPE every INTERVAL seconds, up to COUNT total,
## just off-screen around the player. Change the three knobs below to test any enemy fast — nothing else.
##
## To use it: open arena.gd and set `const USE_TEST_SPAWNER := true` (it swaps this in for the wave
## timeline). Flip it back to false for the normal authored waves.

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const Director    := preload("res://scripts/gameplay/arena_wave_director.gd")   # reuse its ENEMY_DEFS table

# ── EDIT THESE ────────────────────────────────────────────────────────────────
const ENEMY_TYPE  := "diver"   # LOCKED type — set this to the enemy you want to test
const COUNT       := 30        # how many to spawn (you change this)
const INTERVAL    := 10.0      # seconds between spawns
const SPAWN_RADIUS := 720.0    # how far off-screen they appear (around the player)

var _player: Node2D = null
var _mgr: Node = null
var _spawned: int = 0
var _acc: float = 0.0

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_spawn()   # one immediately so you don't wait for the first interval

func _process(delta: float) -> void:
	if _spawned >= COUNT:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_acc += delta
	if _acc >= INTERVAL:
		_acc -= INTERVAL
		_spawn()

func _spawn() -> void:
	if _spawned >= COUNT or _player == null:
		return
	var defs: Dictionary = Director.ENEMY_DEFS
	if not defs.has(ENEMY_TYPE):
		push_warning("test_template: unknown enemy type '%s'" % ENEMY_TYPE)
		return
	var def: Dictionary = (defs[ENEMY_TYPE] as Dictionary).duplicate()
	var e := EnemyScript.new()
	e.configure(ENEMY_TYPE, _mgr, def)
	var a := randf() * TAU
	e.position = _player.global_position + Vector2(cos(a), sin(a)) * SPAWN_RADIUS
	get_parent().add_child(e)   # sibling of the player in the arena world
	_spawned += 1
