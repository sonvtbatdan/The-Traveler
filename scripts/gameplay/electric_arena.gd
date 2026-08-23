extends Node2D
## DEV-ONLY ISOLATED PREVIEW — NOT the real Electric map. The actual Electric (reachable from Hub → Launch)
## is scenes/arena.tscn + arena.gd, same as Default: full ship/weapons/HUD/dev-mode/enemy-waves, branching
## on MetaManager.selected_map_id == "electric" to swap in the background built here (see arena.gd's
## _build_electric_background()) and a separate spawn timeline (arena_wave_director_v2._last_wave_cfg_path()).
## This standalone scene exists ONLY to preview/tune the terrain (ground/clouds/trees) in isolation, fast,
## without booting the whole arena — see tools/screenshot_electric.gd, which runs THIS scene.

const GroundScript := preload("res://scripts/gameplay/electric/electric_ground.gd")
const CloudsScript := preload("res://scripts/gameplay/electric/electric_clouds.gd")
const TreesScript := preload("res://scripts/gameplay/electric/electric_trees.gd")
const PlayerScript := preload("res://scripts/gameplay/electric/electric_player.gd")

var _player: CharacterBody2D
var _camera: Camera2D
var _ground: CanvasLayer
var _clouds: Node2D
var _trees: Node2D

func _ready() -> void:
	# Order matters: ground (own CanvasLayer, always behind) → trees (ONE merged 3D pass — every scattered
	# asset AND the real cloud-occluder mesh share one World3D/camera, see electric_trees.gd) → clouds
	# (decorative 2D atmosphere, purely stylistic) → player — see arena.gd's _build_electric_background() for
	# the full explanation (this preview mirrors it).
	_ground = GroundScript.new()
	add_child(_ground)

	_trees = TreesScript.new()
	add_child(_trees)

	_clouds = CloudsScript.new()
	add_child(_clouds)

	_player = PlayerScript.new()
	_player.position = Vector2.ZERO
	add_child(_player)

	_camera = Camera2D.new()
	_player.add_child(_camera)
	_camera.make_current()

func _process(_delta: float) -> void:
	if _player == null:
		return
	var pos: Vector2 = _player.global_position
	_ground.set_world_offset(pos)
	_clouds.set_world_offset(pos)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_trees.update_view(pos, vp_size)
