extends Node2D
## Collectible loot item dropped by a destroyed ruin box. Drifts freely at 20–50 px/s.
## Player walks within COLLECT_RADIUS to pick it up; no auto-magnetization.
##
## Types and effects:
##   coin / diamond → GameManager.add_money(50)
##   heart          → GameManager.heal(25)
##   magnetic       → pull all XP orbs toward the player with a 0→1200 px/s ramp over 2s
##   shield         → GameManager.activate_shield(10s) + spawn visual overlay on player

const LOOT_WIDTH     := 20.0
const COLLECT_RADIUS := 40.0
const SPEED_MIN      := 20.0
const SPEED_MAX      := 50.0

var _type: String = "coin"
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _player: Node2D = null
var _dead: bool = false

func setup(world_pos: Vector2, type: String) -> void:
	add_to_group("arena_loot")
	global_position = world_pos
	_type = type
	_load_tex()
	var speed := randf_range(SPEED_MIN, SPEED_MAX)
	var angle := randf() * TAU
	_vel = Vector2(cos(angle), sin(angle)) * speed
	_t = randf() * TAU

func _load_tex() -> void:
	var path := "res://assets/screen/%s.png" % _type
	_tex = load(path) as Texture2D
	if _tex == null:
		return
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	_draw_size = Vector2(LOOT_WIDTH, LOOT_WIDTH * th / tw)

func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	global_position += _vel * delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and global_position.distance_to(_player.global_position) <= COLLECT_RADIUS:
		_collect()
		return
	queue_redraw()

func _collect() -> void:
	if _dead:
		return
	_dead = true
	_play_collect_sfx()
	match _type:
		"coin", "diamond":
			if GameManager.has_method("add_money"):
				var mult: float = GameManager.run_coin_mult if "run_coin_mult" in GameManager else 1.0
				mult += GameManager.run_luck if "run_luck" in GameManager else 0.0   # Lucky drone boosts coins too
				GameManager.add_money(int(round(50.0 * mult)))   # Scavenger passive + luck scale pickups
		"heart":
			if GameManager.has_method("heal"):
				GameManager.heal(25)
		"magnetic":
			for orb in get_tree().get_nodes_in_group("arena_xp_orb"):
				if is_instance_valid(orb) and orb.has_method("force_magnetize"):
					orb.force_magnetize()
		"shield":
			if GameManager.has_method("activate_shield"):
				GameManager.activate_shield(10.0)
			if _player != null and is_instance_valid(_player):
				var vis := preload("res://scripts/gameplay/arena_shield_visual.gd").new()
				_player.add_child(vis)
	queue_free()

func _play_collect_sfx() -> void:
	var stream := load("res://assets/audio/sfx/start.mp3") as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = linear_to_db(0.8)
	if get_parent() != null:
		get_parent().add_child(p)
	else:
		add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _draw() -> void:
	if _tex == null or _dead:
		return
	var bob := sin(_t * 3.0) * 2.0
	var r := Rect2(-_draw_size * 0.5 + Vector2(0.0, bob), _draw_size)
	draw_texture_rect(_tex, r, false)
