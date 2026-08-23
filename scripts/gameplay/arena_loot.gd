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
##
## 2026-08-19, on request ("thay cho file png cũ... áp dụng logic xoay xoay giống như chest"): a type whose
## art was upgraded to assets/screen/<type>.glb (heart/magnetic/divinity as of this pass) renders as a live,
## continuously-spinning SubViewport model — same recipe as arena_chest.gd's own "xoay giống như landmark"
## precedent (SubViewport + 2 DirectionalLight3D + Camera3D fixed at ISO_DEG, model centered/spun about its
## own AABB) — instead of the flat draw_texture_rect() PNG path. VP_SIZE is deliberately smaller than the
## chest's (and MSAA is off): the chest is one per run, but several of these can be alive at once (loot never
## despawns until collected) so each instance stays cheap. Any type with no glb (coin today) keeps the old
## PNG path unchanged; orb_of_light has neither and stays fully procedural.

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
const VP_SIZE          := 64             # 3D render resolution — small on purpose, see class doc comment
const ISO_DEG          := 30.0           # camera tilt — matches arena_chest.gd's ISO_DEG
const ROT_RPM          := 12.0           # matches arena_chest.gd/electric+volcanic_ruin_layer.gd's ROT_RPM
const ROT_SPEED        := deg_to_rad(ROT_RPM * 360.0 / 60.0)   # rad/s

var _type: String = "coin"
var _value: int = 50   # money this coin is worth (Credit Extractor rolls variable values)
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _player: Node2D = null
var _dead: bool = false
var _is_3d: bool = false
var _vp: SubViewport = null
var _cam: Camera3D = null
var _pivot: Node3D = null
var _spr3d: Sprite2D = null

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
	_draw_size = Vector2(w, w)   # square default — kept as-is for the 3D path and the no-art procedural orb
	var glb_path := "res://assets/screen/%s.glb" % _type
	if ResourceLoader.exists(glb_path) and _build_model_viewport(glb_path, w):
		return
	var path := "res://assets/screen/%s.png" % _type
	_tex = load(path) as Texture2D
	if _tex == null:
		return   # orb_of_light: no art at all — drawn procedurally, square _draw_size from above stands
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	_draw_size = Vector2(w, w * th / tw)

## Renders `glb_path` into a small SubViewport and shows it on a Sprite2D child — see this file's header
## for the recipe (identical to arena_chest.gd's _build_model_viewport()). Returns false (no state changed)
## if the model fails to load, so _load_tex() can fall back to the PNG path.
func _build_model_viewport(glb_path: String, display_px: float) -> bool:
	var packed := load(glb_path) as PackedScene
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model == null:
		push_warning("arena_loot: could not load " + glb_path)
		return false

	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_vp.add_child(_cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	_pivot.add_child(model)
	_frame_cam(model)

	_spr3d = Sprite2D.new()
	_spr3d.texture = _vp.get_texture()
	_spr3d.scale = Vector2.ONE * (display_px / float(VP_SIZE))
	add_child(_spr3d)
	_is_3d = true
	return true

## Center `model` on its own AABB and place the camera at a fixed ISO_DEG tilt, backed off just far enough
## to fit the whole model — identical recipe to arena_chest.gd's _frame_cam().
func _frame_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(ISO_DEG)
	_cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	_cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far  = dist + radius * 2.0

## Mirrors arena_chest.gd's own _model_aabb() exactly.
func _model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in _model_meshes(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _model_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_model_meshes(c))
	return out

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
	if _is_3d:
		_pivot.rotation.y += ROT_SPEED * delta
		_spr3d.position = Vector2(0.0, sin(_t * 3.0) * 2.0)   # same bob as the PNG path's _draw()
		if _type == "divinity":
			var glow := 0.5 + 0.5 * sin(_t * TAU * DIVINITY_BLINK_HZ)
			_spr3d.modulate = DIVINITY_GLOW.lerp(Color.WHITE, 0.3 + 0.5 * glow)
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
	if _type == "divinity":
		# Bright gold flicker halo behind the icon — the icon's own tint pulse is applied in _process()
		# (_spr3d.modulate) for the 3D path, or below via draw_texture_rect's modulate for the PNG path.
		var glow := 0.5 + 0.5 * sin(_t * TAU * DIVINITY_BLINK_HZ)
		draw_circle(Vector2(0.0, bob), _draw_size.x * 0.9, Color(DIVINITY_GLOW.r, DIVINITY_GLOW.g, DIVINITY_GLOW.b, 0.25 * glow))
		if _is_3d:
			return
		draw_texture_rect(_tex, Rect2(-_draw_size * 0.5 + Vector2(0.0, bob), _draw_size), false, DIVINITY_GLOW.lerp(Color.WHITE, 0.3 + 0.5 * glow))
		return
	if _is_3d or _tex == null:
		return   # 3D path: the live model is the Sprite2D child (_spr3d), nothing to draw here
	draw_texture_rect(_tex, Rect2(-_draw_size * 0.5 + Vector2(0.0, bob), _draw_size), false)

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
