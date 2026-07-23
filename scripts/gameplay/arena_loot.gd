extends Node2D
## Collectible loot item dropped by a destroyed ruin box. Drifts freely at 20–50 px/s.
## Player walks within COLLECT_RADIUS to pick it up; no auto-magnetization.
##
## Types and effects:
##   coin / diamond → GameManager.add_money(50)
##   heart          → GameManager.heal(25)
##   magnetic       → pull all XP orbs toward the player with a 0→1200 px/s ramp over 2s
##   divinity       → spawns arena_divinity_visual.gd on the player: +20% ship size, instant-kills any
##                     touching enemy for 10s (200 dps to a boss instead), and full HP/shield damage
##                     immunity for that same 10s. Icon is drawn bigger + blinks gold while it sits on
##                     the ground (see DIVINITY_WIDTH / _draw()).

const LOOT_WIDTH      := 20.0
const DIVINITY_WIDTH  := 50.0
const ORB_WIDTH       := 44.0
const COLLECT_RADIUS  := 40.0
const ORB_COLLECT_RADIUS := 60.0   # orb of light is a big reward — easier to pick up
const SPEED_MIN       := 20.0
const SPEED_MAX       := 50.0
const DIVINITY_BLINK_HZ := 4.0
const DIVINITY_GLOW    := Color(1.0, 0.85, 0.15)
const ORB_GLOW         := Color(0.65, 0.85, 1.0)   # cool white-blue radiance

var _type: String = "coin"
var _value: int = 50   # money this coin is worth (Credit Extractor rolls variable values)
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _player: Node2D = null
var _dead: bool = false

func setup(world_pos: Vector2, type: String, value: int = 50) -> void:
	add_to_group("arena_loot")
	global_position = world_pos
	_type = type
	_value = value
	_load_tex()
	var speed := randf_range(SPEED_MIN, SPEED_MAX)
	var angle := randf() * TAU
	_vel = Vector2(cos(angle), sin(angle)) * speed
	_t = randf() * TAU

func _load_tex() -> void:
	var w := LOOT_WIDTH
	if _type == "divinity":
		w = DIVINITY_WIDTH
	elif _type == "orb_of_light":
		w = ORB_WIDTH
	var path := "res://assets/screen/%s.png" % _type
	_tex = load(path) as Texture2D
	if _tex == null:
		# orb_of_light has no PNG — it's drawn procedurally, so keep a square draw size.
		_draw_size = Vector2(w, w)
		return
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	_draw_size = Vector2(w, w * th / tw)

func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	global_position += _vel * delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var radius := ORB_COLLECT_RADIUS if _type == "orb_of_light" else COLLECT_RADIUS
	if _player != null and global_position.distance_to(_player.global_position) <= radius:
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
				GameManager.add_money(int(round(float(_value) * mult)))   # coin's rolled value × Scavenger/luck
			if GameManager.has_method("on_coin_pickup"):
				GameManager.on_coin_pickup()   # Credit Extractor on-coin buffs
		"heart":
			if GameManager.has_method("heal"):
				GameManager.heal(25)
		"magnetic":
			var mgr := get_tree().get_first_node_in_group("arena_xp_orb_mgr")
			if mgr != null:
				mgr.magnetize_all()
		"divinity":
			if _player != null and is_instance_valid(_player):
				var vis := preload("res://scripts/gameplay/arena_divinity_visual.gd").new()
				_player.add_child(vis)
		"orb_of_light":
			# Open the pick-1-of-3 selection (new items only, weapon+passive mix).
			var lvl := get_tree().get_first_node_in_group("levelup_ui")
			if lvl != null and lvl.has_method("grant_new_item_choice"):
				lvl.grant_new_item_choice()
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
	if _dead:
		return
	var bob := sin(_t * 3.0) * 2.0
	if _type == "orb_of_light":
		_draw_orb(bob)
		return
	if _tex == null:
		return
	var r := Rect2(-_draw_size * 0.5 + Vector2(0.0, bob), _draw_size)
	if _type == "divinity":
		# Bright gold flicker: pulse the icon's own tint + a soft glow halo behind it.
		var glow := 0.5 + 0.5 * sin(_t * TAU * DIVINITY_BLINK_HZ)
		draw_circle(Vector2(0.0, bob), _draw_size.x * 0.9, Color(DIVINITY_GLOW.r, DIVINITY_GLOW.g, DIVINITY_GLOW.b, 0.25 * glow))
		draw_texture_rect(_tex, r, false, DIVINITY_GLOW.lerp(Color.WHITE, 0.3 + 0.5 * glow))
	else:
		draw_texture_rect(_tex, r, false)

## Procedural "orb of light": a bright pulsing core wrapped in soft concentric glow rings. No texture.
func _draw_orb(bob: float) -> void:
	var c := Vector2(0.0, bob)
	var base := _draw_size.x * 0.5
	var pulse := 0.85 + 0.15 * sin(_t * TAU * 1.5)
	# Outer soft halo → inner rings (largest/faintest drawn first so the core lands on top).
	draw_circle(c, base * 1.6 * pulse, Color(ORB_GLOW.r, ORB_GLOW.g, ORB_GLOW.b, 0.08))
	draw_circle(c, base * 1.15 * pulse, Color(ORB_GLOW.r, ORB_GLOW.g, ORB_GLOW.b, 0.16))
	draw_circle(c, base * 0.75 * pulse, Color(ORB_GLOW.r, ORB_GLOW.g, ORB_GLOW.b, 0.30))
	draw_circle(c, base * 0.42 * pulse, Color(0.9, 0.96, 1.0, 0.85))
	draw_circle(c, base * 0.22 * pulse, Color(1.0, 1.0, 1.0, 1.0))   # hot white core
