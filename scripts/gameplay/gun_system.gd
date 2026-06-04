extends Control

const SS_OFFSET                := Vector2(270.0, 8.0)
const MOUNT_AUTOFIRE           := false  # inventory weapons only — old ship-mount auto-fire retired. Set true to restore.
const BOSS_SHIP_SCALE_MULT     := 0.5    # ship (and hitbox) shrinks to half its boost size during a boss fight
const FIRE_INTERVAL            := 0.5    # gun: 2 shots/sec
const TURRET_FIRE_INTERVAL     := 0.66   # turret: ~1.5 shots/sec
const LIGHTNING_FIRE_INTERVAL  := 0.75
const LIGHTNING_CHAIN_COUNT    := 3
const LIGHTNING_DURATION       := 0.25
const FLOAT_RADIUS             := 2.0
const BULLET_SPEED             := 500.0
const RAILGUN_BULLET_SPEED     := 900.0
const CANON_FIRE_INTERVAL      := 1.0    # 1 shot/sec
const CANON_BULLET_SPEED       := 1000.0 # 2× gun
const BURST_STAGGER            := 0.04   # seconds giữa các bullet trong burst
const RAILGUN_CONE_HALF        := PI / 6.0           # 30° mỗi bên → tổng 60° cone
const RAILGUN_SWEEP_STEP       := 4.5 * PI / 180.0   # 4.5° mỗi shot
const RAILGUN_FIRE_RATE        := 10.0   # bullets/sec during firing phase
const RAILGUN_FIRING_DURATION  := 5.0   # seconds per firing phase
const RAILGUN_OVERHEAT_DURATION:= 2.0   # seconds per overheat phase
const RAILGUN_FIRING_FRAME_TIME  := 0.5  # seconds per frame (forward)
const RAILGUN_OVERHEAT_FRAME_TIME:= 0.3  # seconds per frame (backward)
const SHELL_EJECT_SPEED := 80.0
const SHELL_ROT_DELAY   := 0.1
const SHELL_FADE_START  := 0.8
const SHELL_LIFETIME    := 1.3
const SCREEN_BOUNDS       := Rect2(270.0, 8.0, 700.0, 764.0)  # SpaceScreen bounds
const SCREEN_BOUNDS_INSET := Rect2(280.0, 18.0, 680.0, 744.0) # inset 10px — bullets & lightning clip
const IMPACT_SIZE       := Vector2(20.0, 23.0)                # W=20, H proportional (100:113)
const CANON_MK2_FIRE_INTERVAL  := 0.6   # 6 frames × 0.1s = 1 shot per 0.6s
const CANON_MK2_IMPACT_RADIUS  := 30.0  # half of 60px explosion
const SHIP_MOVE_SPD            := 200.0  # px/s, arrow key movement in manual boost

var _bullet_tex:           Texture2D = null
var _shell_tex:            Texture2D = null
var _turret_bullet_tex:    Texture2D = null
var _sfx_gun_shoot:        AudioStream = null
var _sfx_turret_shoot:     AudioStream = null
var _sfx_gun_booms:        Array[AudioStream] = []
var _sfx_gun_boom_big:     AudioStream = null
var _sfx_zaps:             Array[AudioStream] = []
var _sfx_lasers:           Array[AudioStream] = []
var _impact_frames:        Array = []
var _impact_delays:        Array = []
var _turret_impact_frames: Array = []
var _turret_impact_delays: Array = []
var _gun_frames:           Array = []
var _gun_delays:           Array = []
var _gun_mk2_frames:       Array = []
var _gun_mk2_delays:       Array = []
var _gun_mk3_frames:       Array = []
var _gun_mk3_delays:       Array = []
var _turret_frames:        Array = []
var _turret_delays:        Array = []
var _turret_mk2_frames:    Array = []
var _turret_mk2_delays:    Array = []
var _emitter_frames:       Array = []
var _emitter_delays:       Array = []
var _railgun_frames:       Array = []
var _railgun_bullet_tex:   Texture2D = null
var _railgun_states:       Dictionary = {}  # EditableObjectNode -> {phase,phase_acc,frame,frame_acc,fire_acc}
var _bolt_bullet_tex:      Texture2D = null
var _canon_impact_frames:  Array = []
var _canon_impact_delays:  Array = []
var _canon_bolt_frames:    Array = []
var _canon_bolt_delays:    Array = []
var _sfx_bolt:             AudioStream = null
var _sfx_railgun:          AudioStream = null
var _canon_fire_accs:      Dictionary = {}
var _burst_queue:          Array = []  # [{from,dir,dmg,tex,imp_idx,speed,delay}]
var _canon_bolt_mk2_frames:   Array = []
var _canon_bolt_mk2_delays:   Array = []
var _canon_impact_mk2_frames: Array = []
var _canon_impact_mk2_delays: Array = []
var _bolt_bullet_mk2_tex:     Texture2D = null

var _bullets:          Array[TextureRect] = []
var _bullet_vel:       Array[Vector2]     = []
var _bullet_dmg:       Array[float]       = []
var _bullet_imp_idx:   Array[int]         = []   # 0=gun impact, 1=turret impact

var _shells:        Array[TextureRect] = []
var _shell_vel:     Array[Vector2]     = []
var _shell_age:     Array[float]       = []
var _shell_rot_spd: Array[float]       = []

var _impacts:      Array = []   # [{tr, frame, acc}]
var _gun_anims:    Array = []   # [{tr, frame, acc, frames, delays, gun_eo}]
var _static_rects: Dictionary = {}  # EditableObjectNode -> TextureRect (frame 0 GIF)

var _gun_fire_accs:       Dictionary = {}
var _turret_fire_accs:    Dictionary = {}
var _lightning_fire_accs: Dictionary = {}

var _lightning_chains:    Array = []   # [{lines: Array, age: float}]
var _float_time:          float = 0.0
var _spaceship_eo:        EditableObjectNode = null
var _spaceship_origin:    Vector2 = Vector2.ZERO
var _spaceship_origin_sz: Vector2 = Vector2.ZERO
var _current_scale:       float   = 1.0  # animated by tween (1.0 <-> 0.5)
var _scale_tween:         Tween   = null
var _ship_pop_tween:      Tween   = null
var _weapon_eo_rels:      Dictionary = {}  # EditableObjectNode -> Vector2 (offset từ ship center)
var _thrust_eos:          Array = []       # thrust.png reference EOs — hidden in gameplay
var _auto_thrust_eos:     Array = []       # auto.gif reference EOs — hidden, display via TextureRect
var _auto_thrust_frames:  Array = []
var _auto_thrust_delays:  Array = []
var _manual_thrust_eos:   Array = []       # manual.gif reference EOs — hidden, display via TextureRect
var _manual_thrust_frames: Array = []
var _manual_thrust_delays: Array = []
var _manual_thrust_rects:  Dictionary = {} # auto EO -> manual TR (derived from auto EO position/size)

var _lasers:     Array = []   # [{lines: Array[Line2D], age: float}]
const LASER_DURATION := 0.18
const LASER_COUNT    := 3

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_load_assets()

func refresh_layout() -> void:
	_refresh_static_frames()

func reset_to_origin() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
		_scale_tween = null
	if _ship_pop_tween and _ship_pop_tween.is_valid():
		_ship_pop_tween.kill()
		_ship_pop_tween = null
	_current_scale = 1.0
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.position     = _spaceship_origin
		_spaceship_eo.scale        = Vector2.ONE
		_spaceship_eo.pivot_offset = Vector2.ZERO
	for raw_eo in _static_rects.keys():
		if not is_instance_valid(raw_eo):
			continue
		var eo := raw_eo as EditableObjectNode
		if eo == null or not is_instance_valid(_static_rects[raw_eo]):
			continue
		var rel_ro: Vector2 = _weapon_eo_rels.get(raw_eo, Vector2.ZERO)
		(_static_rects[raw_eo] as TextureRect).position = _spaceship_origin_sz * 0.5 + rel_ro - eo.size * 0.5

func _ready() -> void:
	WeaponManager.catalog_updated.connect(_refresh_static_frames)
	WeaponManager.weapons_reset.connect(_refresh_static_frames)
	WeaponManager.weapon_purchased.connect(func(_id: String, _side: String): _refresh_static_frames())
	GameManager.boost_changed.connect(_on_boost_changed)
	GameManager.boss_spawned.connect(_retarget_scale)   # ship shrinks when the boss fight starts
	GameManager.boss_killed.connect(_retarget_scale)    # …and restores when it ends
	_refresh_static_frames()

## Ship scale target: 0.5 while boosting / 1.0 idle, halved again during the boss fight.
func _scale_target() -> float:
	var t: float = 0.5 if GameManager.manual_boost else 1.0
	if GameManager.boss_max_hp > 0:
		t *= BOSS_SHIP_SCALE_MULT
	return t

func _retarget_scale() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_method(_set_current_scale, _current_scale, _scale_target(), 1.0)

func _on_boost_changed(active: bool) -> void:
	_retarget_scale()
	var mult: float = 2.0 if active else 1.0
	for bg in get_tree().get_nodes_in_group("scrolling_bg"):
		if bg.has_method("set_speed_mult"):
			bg.set_speed_mult(mult)
	for ov in get_tree().get_nodes_in_group("scrolling_overlay"):
		if ov.has_method("set_speed_mult"):
			ov.set_speed_mult(mult)
	for raw_eo in _auto_thrust_eos:
		if not is_instance_valid(raw_eo):
			continue
		var eo := raw_eo as EditableObjectNode
		if _static_rects.has(eo) and is_instance_valid(_static_rects[eo]):
			_static_rects[eo].visible = not active
		if _manual_thrust_rects.has(eo) and is_instance_valid(_manual_thrust_rects[eo]):
			(_manual_thrust_rects[eo] as TextureRect).visible = active

func _set_current_scale(s: float) -> void:
	_current_scale = s

func _load_assets() -> void:
	var rb := load("res://assets/sprites/weapons/Gun Bullet Sprite.png") as Texture2D
	if rb:
		_bullet_tex = rb
	var rs := load("res://assets/sprites/weapons/Gun Bullet Shell.png") as Texture2D
	if rs:
		_shell_tex = rs

	var imp := GifLoader.load_gif("res://assets/sprites/weapons/Gun-Impact50.gif")
	if imp != null:
		if imp.has_meta("gif_frames"):
			_impact_frames = imp.get_meta("gif_frames")
			_impact_delays = imp.get_meta("gif_delays")
		else:
			_impact_frames = [imp]; _impact_delays = [0.05]

	var ganim := GifLoader.load_gif("res://assets/sprites/weapons/Gun.gif")
	if ganim != null:
		if ganim.has_meta("gif_frames"):
			_gun_frames = ganim.get_meta("gif_frames")
			_gun_delays = ganim.get_meta("gif_delays")
		else:
			_gun_frames = [ganim]; _gun_delays = [0.05]

	var ganim2 := GifLoader.load_gif("res://assets/sprites/weapons/Gun-Mk2.gif")
	if ganim2 != null:
		if ganim2.has_meta("gif_frames"):
			_gun_mk2_frames = ganim2.get_meta("gif_frames")
			_gun_mk2_delays = ganim2.get_meta("gif_delays")
		else:
			_gun_mk2_frames = [ganim2]; _gun_mk2_delays = [0.05]

	var tanim := GifLoader.load_gif("res://assets/sprites/weapons/Turret.gif")
	if tanim != null:
		if tanim.has_meta("gif_frames"):
			_turret_frames = tanim.get_meta("gif_frames")
			_turret_delays = tanim.get_meta("gif_delays")
		else:
			_turret_frames = [tanim]; _turret_delays = [0.05]

	var tanim2 := GifLoader.load_gif("res://assets/sprites/weapons/TurretMK2.gif")
	if tanim2 != null:
		if tanim2.has_meta("gif_frames"):
			_turret_mk2_frames = tanim2.get_meta("gif_frames")
			_turret_mk2_delays = tanim2.get_meta("gif_delays")
		else:
			_turret_mk2_frames = [tanim2]; _turret_mk2_delays = [0.05]

	var tbimp := GifLoader.load_gif("res://assets/sprites/weapons/Turretbullet.gif")
	if tbimp != null:
		var tbframes: Array = tbimp.get_meta("gif_frames") if tbimp.has_meta("gif_frames") else [tbimp]
		if not tbframes.is_empty():
			_turret_bullet_tex = tbframes[0] as Texture2D

	var timp := GifLoader.load_gif("res://assets/sprites/weapons/Turret-Impact50.gif")
	if timp != null:
		if timp.has_meta("gif_frames"):
			_turret_impact_frames = timp.get_meta("gif_frames")
			_turret_impact_delays = timp.get_meta("gif_delays")
		else:
			_turret_impact_frames = [timp]; _turret_impact_delays = [0.05]

	var eaniim := GifLoader.load_gif("res://assets/sprites/weapons/emitter.gif")
	if eaniim != null:
		if eaniim.has_meta("gif_frames"):
			_emitter_frames = eaniim.get_meta("gif_frames")
			_emitter_delays = eaniim.get_meta("gif_delays")
		else:
			_emitter_frames = [eaniim]; _emitter_delays = [0.05]

	var ganim3 := GifLoader.load_gif("res://assets/sprites/weapons/Gun-Mk3.gif")
	if ganim3 != null:
		if ganim3.has_meta("gif_frames"):
			_gun_mk3_frames = ganim3.get_meta("gif_frames")
			_gun_mk3_delays = ganim3.get_meta("gif_delays")
		else:
			_gun_mk3_frames = [ganim3]; _gun_mk3_delays = [0.05]

	var bbanim := GifLoader.load_gif("res://assets/sprites/weapons/BoltBullet.gif")
	if bbanim != null:
		var bbframes: Array = bbanim.get_meta("gif_frames") if bbanim.has_meta("gif_frames") else [bbanim]
		if not bbframes.is_empty():
			_bolt_bullet_tex = bbframes[0] as Texture2D

	var cianim := GifLoader.load_gif("res://assets/sprites/weapons/canonimpact.gif")
	if cianim != null:
		if cianim.has_meta("gif_frames"):
			_canon_impact_frames = cianim.get_meta("gif_frames")
			_canon_impact_delays = cianim.get_meta("gif_delays")
		else:
			_canon_impact_frames = [cianim]; _canon_impact_delays = [0.05]

	var cbanim := GifLoader.load_gif("res://assets/sprites/weapons/Canonbolt.gif")
	if cbanim != null:
		if cbanim.has_meta("gif_frames"):
			_canon_bolt_frames = cbanim.get_meta("gif_frames")
			_canon_bolt_delays = cbanim.get_meta("gif_delays")
		else:
			_canon_bolt_frames = [cbanim]; _canon_bolt_delays = [0.2]

	var cbanim2 := GifLoader.load_gif("res://assets/sprites/weapons/CanonboltMKII.gif")
	if cbanim2 != null:
		if cbanim2.has_meta("gif_frames"):
			_canon_bolt_mk2_frames = cbanim2.get_meta("gif_frames")
			_canon_bolt_mk2_delays = cbanim2.get_meta("gif_delays")
		else:
			_canon_bolt_mk2_frames = [cbanim2]; _canon_bolt_mk2_delays = [0.1]

	var cianim2 := GifLoader.load_gif("res://assets/sprites/weapons/canonimpactmkII.gif")
	if cianim2 != null:
		if cianim2.has_meta("gif_frames"):
			_canon_impact_mk2_frames = cianim2.get_meta("gif_frames")
			_canon_impact_mk2_delays = cianim2.get_meta("gif_delays")
		else:
			_canon_impact_mk2_frames = [cianim2]; _canon_impact_mk2_delays = [0.05]

	var bmk2 := load("res://assets/sprites/weapons/canonshellmkII.png") as Texture2D
	if bmk2 != null:
		var bmk2_img := bmk2.get_image()
		if bmk2_img != null:
			var bmk2_h := maxi(1, int(bmk2_img.get_height() * 10.0 / maxi(1, bmk2_img.get_width())))
			bmk2_img.resize(10, bmk2_h, Image.INTERPOLATE_BILINEAR)
			_bolt_bullet_mk2_tex = ImageTexture.create_from_image(bmk2_img)
		else:
			_bolt_bullet_mk2_tex = bmk2

	_sfx_bolt    = load("res://assets/audio/sfx/bolt.wav")    as AudioStream
	_sfx_railgun = load("res://assets/audio/sfx/railgun2.wav") as AudioStream

	var ranim := GifLoader.load_gif("res://assets/sprites/weapons/Railgun.gif")
	if ranim != null:
		_railgun_frames = ranim.get_meta("gif_frames") if ranim.has_meta("gif_frames") else [ranim]
	var rbanim := GifLoader.load_gif("res://assets/sprites/weapons/Railgunbullet.gif")
	if rbanim != null:
		var rbframes: Array = rbanim.get_meta("gif_frames") if rbanim.has_meta("gif_frames") else [rbanim]
		if not rbframes.is_empty():
			_railgun_bullet_tex = rbframes[0] as Texture2D

	var auto_anim := GifLoader.load_gif("res://assets/sprites/thrust/auto.gif")
	if auto_anim != null:
		if auto_anim.has_meta("gif_frames"):
			_auto_thrust_frames = auto_anim.get_meta("gif_frames")
			_auto_thrust_delays = auto_anim.get_meta("gif_delays")
		else:
			_auto_thrust_frames = [auto_anim]; _auto_thrust_delays = [0.05]

	var manual_anim := GifLoader.load_gif("res://assets/sprites/thrust/manual.gif")
	if manual_anim != null:
		if manual_anim.has_meta("gif_frames"):
			_manual_thrust_frames = manual_anim.get_meta("gif_frames")
			_manual_thrust_delays = manual_anim.get_meta("gif_delays")
		else:
			_manual_thrust_frames = [manual_anim]; _manual_thrust_delays = [0.05]

	_sfx_gun_shoot    = load("res://assets/audio/sfx/gunshoot.wav") as AudioStream
	_sfx_turret_shoot = load("res://assets/audio/sfx/turretshoot.wav") as AudioStream
	_sfx_gun_boom_big = load("res://assets/audio/sfx/gunboombig.wav") as AudioStream
	for i in range(1, 6):
		var boom := load("res://assets/audio/sfx/gunboom%d.wav" % i) as AudioStream
		if boom != null:
			_sfx_gun_booms.append(boom)
	var zi := 1
	while true:
		var zap := load("res://assets/audio/sfx/zap%d.wav" % zi) as AudioStream
		if zap == null:
			break
		_sfx_zaps.append(zap)
		zi += 1
	var li := 1
	while true:
		var las := load("res://assets/audio/sfx/laser%d.wav" % li) as AudioStream
		if las == null:
			break
		_sfx_lasers.append(las)
		li += 1

func _play_sfx(stream: AudioStream, weapon_key: String = "") -> void:
	if stream == null:
		return
	var vol := AudioManager.get_weapon_sfx_vol(weapon_key) if weapon_key != "" else AudioManager.sfx_volume
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(vol)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _process(delta: float) -> void:
	for eo: EditableObjectNode in WeaponManager.get_active_objects("gun"):
		if not _gun_fire_accs.has(eo):
			_gun_fire_accs[eo] = randf() * FIRE_INTERVAL
		_gun_fire_accs[eo] += delta
		if _gun_fire_accs[eo] >= FIRE_INTERVAL:
			_gun_fire_accs[eo] -= FIRE_INTERVAL
			_fire_gun(eo)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("turret"):
		if not _turret_fire_accs.has(eo):
			_turret_fire_accs[eo] = randf() * TURRET_FIRE_INTERVAL
		_turret_fire_accs[eo] += delta
		if _turret_fire_accs[eo] >= TURRET_FIRE_INTERVAL:
			_turret_fire_accs[eo] -= TURRET_FIRE_INTERVAL
			_fire_turret(eo)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("railgun"):
		if not _railgun_states.has(eo):
			_railgun_states[eo] = {"phase": "firing", "phase_acc": 0.0, "frame": 0, "frame_acc": 0.0,
				"fire_acc": randf() * (1.0 / RAILGUN_FIRE_RATE),  # lệch pha ban đầu
				"sweep_angle": randf_range(-RAILGUN_CONE_HALF, RAILGUN_CONE_HALF),
				"sweep_dir": 1.0 if randf() > 0.5 else -1.0}
		_tick_railgun(eo, delta)
	# Dọn state của EO không còn tồn tại
	for raw_eo in _railgun_states.keys():
		if not is_instance_valid(raw_eo):
			_railgun_states.erase(raw_eo)
	# Canon Heavy Bolt
	for eo: EditableObjectNode in WeaponManager.get_active_objects("left_canon_heavy_bolt"):
		var iv := _canon_interval_for(eo)
		if not _canon_fire_accs.has(eo):
			_canon_fire_accs[eo] = randf() * iv
		_canon_fire_accs[eo] += delta
		if _canon_fire_accs[eo] >= iv:
			_canon_fire_accs[eo] -= iv
			_fire_canon(eo)
	# Burst queue (Gun Mk2/Mk3, Turret Mk2 stagger)
	var bi := _burst_queue.size() - 1
	while bi >= 0:
		var entry: Dictionary = _burst_queue[bi]
		entry["delay"] -= delta
		if float(entry["delay"]) <= 0.0:
			_spawn_bullet(entry["from"], entry["dir"], entry["dmg"], entry["tex"], entry["imp_idx"], entry["speed"])
			var esfx := entry.get("sfx") as AudioStream
			if esfx != null:
				_play_sfx(esfx, entry.get("weapon_key", "") as String)
			_burst_queue.remove_at(bi)
		else:
			_burst_queue[bi] = entry
		bi -= 1
	if GameManager.manual_boost and _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_handle_ship_movement(delta)
	_float_time += delta
	var ship_off    := Vector2(sin(_float_time * 1.9), cos(_float_time * 1.3)) * FLOAT_RADIUS
	var emitter_off := Vector2(sin(_float_time * 2.3), cos(_float_time * 1.7)) * FLOAT_RADIUS
	var ship_center := _spaceship_origin + ship_off + _spaceship_origin_sz * 0.5

	# Spaceship: position + scale force-apply mỗi frame
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.position     = _spaceship_origin + ship_off
		_spaceship_eo.pivot_offset = _spaceship_origin_sz * 0.5
		if not (_ship_pop_tween and _ship_pop_tween.is_valid()):
			_spaceship_eo.scale = Vector2(_current_scale, _current_scale)

	# Weapon EOs: tính trực tiếp từ ship_center + rel * scale — không lag
	for raw_eo in _weapon_eo_rels.keys():
		if not is_instance_valid(raw_eo):
			continue
		var eo := raw_eo as EditableObjectNode
		if eo == null:
			continue
		var rel: Vector2   = _weapon_eo_rels[raw_eo]
		var wc: Vector2    = ship_center + rel * _current_scale   # weapon visual center (global)
		var wp: Vector2    = wc - eo.size * 0.5                   # top-left global position
		# Convert global wp to local position relative to parent (spaceship or ObjectsContainer)
		var parent_node := eo.get_parent() as Control
		if parent_node != null and parent_node != get_parent():
			eo.position = wp - parent_node.global_position
		else:
			eo.position = wp
		if _static_rects.has(raw_eo) and is_instance_valid(_static_rects[raw_eo]):
			var tr: TextureRect = _static_rects[raw_eo] as TextureRect
			if eo.source_path.get_file().get_basename().to_lower().begins_with("lightning"):
				tr.position = _spaceship_origin_sz * 0.5 + rel - eo.size * 0.5 + emitter_off
	# Lightning emitter fire accumulator
	for eo: EditableObjectNode in WeaponManager.get_active_objects("lightning_emitter"):
		if not _lightning_fire_accs.has(eo):
			_lightning_fire_accs[eo] = randf() * LIGHTNING_FIRE_INTERVAL
		_lightning_fire_accs[eo] += delta
		if _lightning_fire_accs[eo] >= LIGHTNING_FIRE_INTERVAL:
			_lightning_fire_accs[eo] -= LIGHTNING_FIRE_INTERVAL
			_fire_lightning(eo)
	_tick_bullets(delta)
	_tick_shells(delta)
	_tick_impacts(delta)
	_tick_gun_anims(delta)
	_tick_lightning_chains(delta)
	_tick_lasers(delta)
	if GameManager.manual_boost and _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_check_ship_asteroid_collision()

func _handle_ship_movement(delta: float) -> void:
	var mv := Vector2(
		(float(Input.is_physical_key_pressed(KEY_D)) + float(Input.is_physical_key_pressed(KEY_RIGHT)))
		- (float(Input.is_physical_key_pressed(KEY_A)) + float(Input.is_physical_key_pressed(KEY_LEFT))),
		(float(Input.is_physical_key_pressed(KEY_S)) + float(Input.is_physical_key_pressed(KEY_DOWN)))
		- (float(Input.is_physical_key_pressed(KEY_W)) + float(Input.is_physical_key_pressed(KEY_UP)))
	)
	if mv == Vector2.ZERO:
		return
	_spaceship_origin += mv.normalized() * SHIP_MOVE_SPD * delta
	_spaceship_origin.x = clampf(_spaceship_origin.x,
		SCREEN_BOUNDS.position.x,
		SCREEN_BOUNDS.end.x - _spaceship_origin_sz.x)
	_spaceship_origin.y = clampf(_spaceship_origin.y,
		SCREEN_BOUNDS.position.y,
		SCREEN_BOUNDS.end.y - _spaceship_origin_sz.y)

# ── Static frame (frame 0 GIF thay cho PNG khi không bắn) ────────────────────

func _refresh_static_frames() -> void:
	for d: Dictionary in _gun_anims:
		var raw_tr = d.get("tr")
		if is_instance_valid(raw_tr) and not _static_rects.values().has(raw_tr):
			(raw_tr as Node).queue_free()
	_gun_anims.clear()
	for eo in _static_rects.keys():
		if not is_instance_valid(eo):
			continue
		var old := _static_rects[eo] as TextureRect
		if old != null and is_instance_valid(old):
			old.queue_free()
	_static_rects.clear()
	_manual_thrust_rects.clear()
	var prev_ship := _spaceship_eo
	_spaceship_eo = _find_spaceship_eo()
	if _spaceship_eo != null:
		if prev_ship == _spaceship_eo:
			# Trừ float offset để tránh origin drift khi gọi giữa gameplay
			var cur_off := Vector2(sin(_float_time * 1.9), cos(_float_time * 1.3)) * FLOAT_RADIUS
			_spaceship_origin = _spaceship_eo.position - cur_off
		else:
			_spaceship_origin = _spaceship_eo.position
			_spaceship_eo.object_clicked.connect(_on_ship_clicked)
		_spaceship_origin_sz = _spaceship_eo.size
	# Cache weapon EO rels: offset từ ship center (layout gốc, không có float/scale)
	_weapon_eo_rels.clear()
	var ship_center: Vector2 = _spaceship_origin + _spaceship_origin_sz * 0.5
	var parent := get_parent()
	var cur_ship_off := Vector2(sin(_float_time * 1.9), cos(_float_time * 1.3)) * FLOAT_RADIUS
	var _all_candidate_eos: Array = []
	if is_instance_valid(parent):
		for child in parent.get_children():
			_all_candidate_eos.append(child)
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		for child in _spaceship_eo.get_children():
			_all_candidate_eos.append(child)
	for child in _all_candidate_eos:
		var eo := child as EditableObjectNode
		if eo == null or eo == _spaceship_eo or eo.is_group_layer():
			continue
		# Khôi phục vị trí gốc thực: bỏ ship_off và scale hiện tại
		var eo_center: Vector2 = eo.global_position + eo.size * 0.5 - cur_ship_off
		var true_eo_center: Vector2 = ship_center + (eo_center - ship_center) / _current_scale if _current_scale > 0.0 else eo_center
		_weapon_eo_rels[eo] = true_eo_center - ship_center
	# Reset railgun states khi catalog thay đổi (weapon mới mua/reset)
	_railgun_states.clear()
	# Ẩn toàn bộ PNG — chỉ dùng làm tham chiếu tọa độ
	for weapon_id in ["gun", "turret", "lightning_emitter", "railgun", "left_canon_heavy_bolt", "wing"]:
		for eo: EditableObjectNode in WeaponManager.get_all_objects(weapon_id):
			eo.modulate.a = 0.0
	# Thrust: ẩn PNG reference, toggle auto.gif theo boost state
	_thrust_eos.clear()
	_auto_thrust_eos.clear()
	_manual_thrust_eos.clear()
	var _thrust_candidates: Array = []
	if is_instance_valid(parent):
		for child in parent.get_children():
			_thrust_candidates.append(child)
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		for child in _spaceship_eo.get_children():
			_thrust_candidates.append(child)
	for child in _thrust_candidates:
		var eo := child as EditableObjectNode
		if eo == null or eo.is_group_layer():
			continue
		var base := eo.source_path.get_file().get_basename().to_lower()
		if base == "thrust":
			_thrust_eos.append(eo)
			eo.modulate.a = 0.0
		elif base == "auto":
			_auto_thrust_eos.append(eo)
			eo.modulate.a = 0.0
			_setup_auto_thrust_idle(eo)
		elif base == "manual":
			_manual_thrust_eos.append(eo)
			eo.modulate.a = 0.0
	# Tạo static frame (GIF frame 0) cho các vũ khí đang active
	for eo: EditableObjectNode in WeaponManager.get_active_objects("gun"):
		var cx: float = eo.global_position.x + eo.size.x * 0.5
		var side: String = "L" if cx < WeaponManager.ship_cx else "R"
		var tier: int = WeaponManager.get_tier("gun", side)
		var frames: Array
		if tier >= 2 and not _gun_mk3_frames.is_empty():
			frames = _gun_mk3_frames
		elif tier >= 1 and not _gun_mk2_frames.is_empty():
			frames = _gun_mk2_frames
		else:
			frames = _gun_frames
		_setup_static_frame(eo, frames)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("turret"):
		var tcx: float  = eo.global_position.x + eo.size.x * 0.5
		var tside: String = "L" if tcx < WeaponManager.ship_cx else "R"
		var ttier: int  = WeaponManager.get_tier("turret", tside)
		var tframes := _turret_mk2_frames if ttier >= 1 and not _turret_mk2_frames.is_empty() else _turret_frames
		_setup_static_frame(eo, tframes)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("lightning_emitter"):
		_setup_emitter_idle(eo)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("railgun"):
		_setup_static_frame(eo, _railgun_frames)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("left_canon_heavy_bolt"):
		var cframes := _canon_bolt_mk2_frames if _canon_tier(eo) >= 1 and not _canon_bolt_mk2_frames.is_empty() else _canon_bolt_frames
		_setup_static_frame(eo, cframes)
	for eo: EditableObjectNode in WeaponManager.get_active_objects("wing"):
		if eo.texture_rect.texture == null:
			continue
		var wing_img := eo.texture_rect.texture.get_image()
		if wing_img == null:
			continue
		_setup_static_frame(eo, [ImageTexture.create_from_image(wing_img)])

func _setup_static_frame(eo: EditableObjectNode, frames: Array) -> void:
	if frames.is_empty():
		return
	var tr := TextureRect.new()
	tr.texture = _resize_frame(frames[0] as Texture2D, eo.size)
	tr.size = eo.size
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rel_sf: Vector2 = _weapon_eo_rels.get(eo, Vector2.ZERO)
	tr.position = _spaceship_origin_sz * 0.5 + rel_sf - eo.size * 0.5
	tr.flip_h = eo.texture_rect.flip_h
	tr.z_as_relative = false
	tr.z_index = _eo_effective_z(eo)
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.add_child(tr)
	else:
		add_child(tr)
	_static_rects[eo] = tr
	eo.modulate.a = 0.0  # ẩn PNG nhưng giữ visible=true để get_active_objects vẫn tìm thấy

## Emitter: looping GIF animation + float effect (vị trí update mỗi frame trong _process)
func _setup_emitter_idle(eo: EditableObjectNode) -> void:
	if _emitter_frames.is_empty():
		return
	var resized: Array = []
	for f in _emitter_frames:
		resized.append(_resize_frame(f as Texture2D, eo.size))
	var tr := TextureRect.new()
	tr.texture = resized[0] as Texture2D
	tr.size = eo.size
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rel_em: Vector2 = _weapon_eo_rels.get(eo, Vector2.ZERO)
	tr.position = _spaceship_origin_sz * 0.5 + rel_em - eo.size * 0.5
	tr.flip_h = eo.texture_rect.flip_h
	tr.z_as_relative = false
	tr.z_index = _eo_effective_z(eo)
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.add_child(tr)
	else:
		add_child(tr)
	_static_rects[eo] = tr
	eo.modulate.a = 0.0
	_gun_anims.append({"tr": tr, "frame": 0, "acc": 0.0,
		"gun_eo": eo, "frames": resized, "delays": _emitter_delays, "loop": true})

func _setup_auto_thrust_idle(eo: EditableObjectNode) -> void:
	if _auto_thrust_frames.is_empty():
		return
	var resized: Array = []
	for f in _auto_thrust_frames:
		resized.append(_resize_frame(f as Texture2D, eo.size))
	var tr := TextureRect.new()
	tr.texture = resized[0] as Texture2D
	tr.size = eo.size
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rel_at: Vector2 = _weapon_eo_rels.get(eo, Vector2.ZERO)
	var tr_pos: Vector2 = _spaceship_origin_sz * 0.5 + rel_at - eo.size * 0.5
	tr.position = tr_pos
	tr.flip_h = eo.texture_rect.flip_h
	tr.visible = not GameManager.manual_boost
	tr.z_as_relative = false
	tr.z_index = _eo_effective_z(eo)
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.add_child(tr)
	else:
		add_child(tr)
	_static_rects[eo] = tr
	_gun_anims.append({"tr": tr, "frame": 0, "acc": 0.0,
		"gun_eo": null, "frames": resized, "delays": _auto_thrust_delays, "loop": true})
	if not _manual_thrust_frames.is_empty():
		var mresized: Array = []
		for f in _manual_thrust_frames:
			mresized.append(_resize_frame(f as Texture2D, eo.size))
		var mtr := TextureRect.new()
		mtr.texture = mresized[0] as Texture2D
		mtr.size = eo.size
		mtr.stretch_mode = TextureRect.STRETCH_KEEP
		mtr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
		mtr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mtr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mtr.position = tr_pos
		mtr.flip_h = eo.texture_rect.flip_h
		mtr.visible = GameManager.manual_boost
		mtr.z_as_relative = false
		mtr.z_index = _eo_effective_z(eo)
		if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
			_spaceship_eo.add_child(mtr)
		else:
			add_child(mtr)
		_manual_thrust_rects[eo] = mtr
		_gun_anims.append({"tr": mtr, "frame": 0, "acc": 0.0,
			"gun_eo": null, "frames": mresized, "delays": _manual_thrust_delays, "loop": true})

func _setup_manual_thrust_idle(eo: EditableObjectNode) -> void:
	if _manual_thrust_frames.is_empty():
		return
	var resized: Array = []
	for f in _manual_thrust_frames:
		resized.append(_resize_frame(f as Texture2D, eo.size))
	var tr := TextureRect.new()
	tr.texture = resized[0] as Texture2D
	tr.size = eo.size
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = eo.position
	tr.flip_h = eo.texture_rect.flip_h
	tr.visible = GameManager.manual_boost   # shown only during manual boost
	tr.z_index = eo.z_index
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.add_child(tr)
	else:
		add_child(tr)
	_static_rects[eo] = tr
	_gun_anims.append({"tr": tr, "frame": 0, "acc": 0.0,
		"gun_eo": null, "frames": resized, "delays": _manual_thrust_delays, "loop": true})

## Trả về z_index tuyệt đối của một weapon EO trong CanvasLayer.
## Với z_as_relative=true (weapon là child của spaceship): effective_z = parent.z + local_z
func _eo_effective_z(eo: EditableObjectNode) -> int:
	if not eo.z_as_relative:
		return eo.z_index
	var parent_item := eo.get_parent() as CanvasItem
	if parent_item == null:
		return eo.z_index
	return parent_item.z_index + eo.z_index

func _resize_frame(frame: Texture2D, target_size: Vector2) -> Texture2D:
	var tex := frame as ImageTexture
	if tex == null:
		return frame
	var img := tex.get_image()
	if img == null:
		return frame
	var copy := img.duplicate()
	copy.resize(int(target_size.x), int(target_size.y), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(copy)

# ─────────────────────────────────────────────────────────────────────────────

func _boss_target_oc() -> Vector2:
	var bf := get_tree().get_first_node_in_group("boss_fight")
	if bf == null:
		return Vector2(INF, INF)
	var brect: Rect2 = bf.call("get_boss_hit_rect")
	if not brect.has_area():
		return Vector2(INF, INF)
	return brect.get_center()

func _get_ast_centers_oc() -> Array[Vector2]:
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	if not is_instance_valid(ast_node) or not ast_node.has_method("get_asteroid_centers"):
		return []
	var centers: Array[Vector2] = ast_node.get_asteroid_centers()
	for i in range(centers.size()):
		centers[i] += SS_OFFSET
	return centers

func _fire_gun(eo: EditableObjectNode) -> void:
	if not MOUNT_AUTOFIRE: return
	var gun_top := Vector2(eo.global_position.x + eo.size.x * 0.5, eo.global_position.y + eo.size.y * (1.0 - _current_scale) * 0.5)
	var target: Vector2
	if GameManager.boss_max_hp > 0:
		target = _boss_target_oc()
	else:
		var centers := _get_ast_centers_oc()
		if centers.is_empty():
			return
		var valid: Array[Vector2] = []
		for c in centers:
			if c.y <= gun_top.y - 100.0:
				valid.append(c)
		target = _nearest(gun_top, valid)
	if not is_finite(target.x):
		return
	var dir := (target - gun_top).normalized()
	var eject_left: bool = gun_top.x < WeaponManager.ship_cx
	var side: String = "L" if eject_left else "R"
	var tier: int = WeaponManager.get_tier("gun", side)
	if tier >= 2:
		_queue_burst(gun_top, [dir.rotated(-0.07), dir, dir.rotated(0.07)], 1.0, _bullet_tex, 0, BULLET_SPEED, _sfx_gun_shoot, "gun")
	elif tier >= 1:
		_queue_burst(gun_top, [dir.rotated(-0.06), dir.rotated(0.06)], 1.0, _bullet_tex, 0, BULLET_SPEED, _sfx_gun_shoot, "gun")
	else:
		_spawn_bullet(gun_top, dir, 1.0, _bullet_tex, 0)
		_play_sfx(_sfx_gun_shoot, "gun")
	_spawn_shell(gun_top, dir, eject_left)
	_start_gun_anim(eo, tier)

func _fire_turret(eo: EditableObjectNode) -> void:
	if not MOUNT_AUTOFIRE: return
	var turret_top := Vector2(eo.global_position.x + eo.size.x * 0.5, eo.global_position.y + eo.size.y * (1.0 - _current_scale) * 0.5)
	var target: Vector2
	if GameManager.boss_max_hp > 0:
		target = _boss_target_oc()
	else:
		var centers := _get_ast_centers_oc()
		if centers.is_empty():
			return
		var valid: Array[Vector2] = []
		for c in centers:
			if c.y <= turret_top.y - 100.0:
				valid.append(c)
		target = _nearest(turret_top, valid)
	if not is_finite(target.x):
		return
	var dir := (target - turret_top).normalized()
	var tside: String = "L" if turret_top.x < WeaponManager.ship_cx else "R"
	var ttier: int    = WeaponManager.get_tier("turret", tside)
	if ttier >= 1:
		_queue_burst(turret_top, [dir.rotated(-0.05), dir.rotated(0.05)], 1.0, _turret_bullet_tex, 1, BULLET_SPEED, _sfx_turret_shoot, "turret")
	else:
		_spawn_bullet(turret_top, dir, 1.0, _turret_bullet_tex, 1)
		_play_sfx(_sfx_turret_shoot, "turret")
	_start_turret_anim(eo, ttier)

func _fire_railgun_bullet(eo: EditableObjectNode, angle: float = 0.0) -> void:
	if not MOUNT_AUTOFIRE: return
	if _railgun_bullet_tex == null:
		return
	var top := Vector2(eo.global_position.x + eo.size.x * 0.5, eo.global_position.y + eo.size.y * (1.0 - _current_scale) * 0.5)
	_spawn_bullet(top, Vector2(0.0, -1.0).rotated(angle), 0.2, _railgun_bullet_tex, 2, RAILGUN_BULLET_SPEED)
	_play_sfx(_sfx_railgun, "railgun")

func _queue_burst(from: Vector2, dirs: Array, dmg: float, tex: Texture2D, imp_idx: int, speed: float, sfx: AudioStream = null, weapon_key: String = "") -> void:
	for i in dirs.size():
		_burst_queue.append({"from": from, "dir": dirs[i], "dmg": dmg,
			"tex": tex, "imp_idx": imp_idx, "speed": speed, "delay": i * BURST_STAGGER,
			"sfx": sfx, "weapon_key": weapon_key})

func _canon_tier(eo: EditableObjectNode) -> int:
	var rel: Vector2 = _weapon_eo_rels.get(eo, Vector2.ZERO)
	var side: String = "L" if rel.x <= 0.0 else "R"
	return WeaponManager.get_tier("left_canon_heavy_bolt", side)

func _canon_interval_for(eo: EditableObjectNode) -> float:
	return CANON_MK2_FIRE_INTERVAL if _canon_tier(eo) >= 1 else CANON_FIRE_INTERVAL

func _fire_canon(eo: EditableObjectNode) -> void:
	if not MOUNT_AUTOFIRE: return
	_start_canon_anim(eo)

func _start_canon_anim(eo: EditableObjectNode) -> void:
	var tier := _canon_tier(eo)
	var frames := _canon_bolt_mk2_frames if tier >= 1 and not _canon_bolt_mk2_frames.is_empty() else _canon_bolt_frames
	var delays := _canon_bolt_mk2_delays if tier >= 1 and not _canon_bolt_mk2_delays.is_empty() else _canon_bolt_delays
	if frames.is_empty():
		_fire_canon_bullet(eo)
		return
	_start_weapon_anim(eo, frames, delays)
	if not _gun_anims.is_empty():
		var last: Dictionary = _gun_anims[_gun_anims.size() - 1]
		last["fire_on_end"] = true
		_gun_anims[_gun_anims.size() - 1] = last

func _fire_canon_bullet(eo: EditableObjectNode) -> void:
	var tier := _canon_tier(eo)
	var btex := _bolt_bullet_mk2_tex if tier >= 1 and _bolt_bullet_mk2_tex != null else _bolt_bullet_tex
	if btex == null:
		return
	var top := Vector2(eo.global_position.x + eo.size.x * 0.5, eo.global_position.y + eo.size.y * (1.0 - _current_scale) * 0.5)
	var target: Vector2
	if GameManager.boss_max_hp > 0:
		target = _boss_target_oc()
	else:
		var ast_node := get_tree().get_first_node_in_group("asteroid_main")
		if not is_instance_valid(ast_node) or not ast_node.has_method("get_asteroid_centers"):
			return
		var centers: Array[Vector2] = ast_node.get_asteroid_centers()
		var sizes: Array[Vector2]   = ast_node.get_asteroid_sizes()
		var valid: Array[Vector2] = []
		for i in range(centers.size()):
			if sizes[i].x > 35.0 and (centers[i] + SS_OFFSET).y <= top.y - 50.0:
				valid.append(centers[i] + SS_OFFSET)
		target = _nearest(top, valid)
	if not is_finite(target.x):
		return
	var imp_idx := 4 if tier >= 1 else 3
	var dmg := 1.0 if tier >= 1 else 2.0
	_spawn_bullet(top, (target - top).normalized(), dmg, btex, imp_idx, CANON_BULLET_SPEED)
	_play_sfx(_sfx_bolt, "canon")

func _tick_railgun(eo: EditableObjectNode, delta: float) -> void:
	var st: Dictionary = _railgun_states[eo]
	var tr := _static_rects.get(eo) as TextureRect
	if tr == null or not is_instance_valid(tr) or _railgun_frames.is_empty():
		return
	match st["phase"]:
		"firing":
			st["phase_acc"] = float(st["phase_acc"]) + delta
			st["frame_acc"] = float(st["frame_acc"]) + delta
			st["fire_acc"]  = float(st["fire_acc"])  + delta
			while float(st["fire_acc"]) >= 1.0 / RAILGUN_FIRE_RATE:
				st["fire_acc"] = float(st["fire_acc"]) - 1.0 / RAILGUN_FIRE_RATE
				_fire_railgun_bullet(eo, float(st["sweep_angle"]))
				var next: float = float(st["sweep_angle"]) + RAILGUN_SWEEP_STEP * float(st["sweep_dir"])
				if abs(next) >= RAILGUN_CONE_HALF:
					next = clampf(next, -RAILGUN_CONE_HALF, RAILGUN_CONE_HALF)
					st["sweep_dir"] = -float(st["sweep_dir"])
				st["sweep_angle"] = next
			while float(st["frame_acc"]) >= RAILGUN_FIRING_FRAME_TIME:
				st["frame_acc"] = float(st["frame_acc"]) - RAILGUN_FIRING_FRAME_TIME
				st["frame"] = mini(int(st["frame"]) + 1, _railgun_frames.size() - 1)
			tr.texture = _resize_frame(_railgun_frames[int(st["frame"])] as Texture2D, eo.size)
			if float(st["phase_acc"]) >= RAILGUN_FIRING_DURATION:
				st["phase"]     = "overheat"
				st["phase_acc"] = 0.0
				st["frame_acc"] = 0.0
				st["frame"]     = _railgun_frames.size() - 1
		"overheat":
			st["phase_acc"] = float(st["phase_acc"]) + delta
			st["frame_acc"] = float(st["frame_acc"]) + delta
			while float(st["frame_acc"]) >= RAILGUN_OVERHEAT_FRAME_TIME:
				st["frame_acc"] = float(st["frame_acc"]) - RAILGUN_OVERHEAT_FRAME_TIME
				st["frame"] = maxi(int(st["frame"]) - 1, 0)
			tr.texture = _resize_frame(_railgun_frames[int(st["frame"])] as Texture2D, eo.size)
			if float(st["phase_acc"]) >= RAILGUN_OVERHEAT_DURATION:
				st["phase"]     = "firing"
				st["phase_acc"] = 0.0
				st["frame_acc"] = 0.0
				st["frame"]     = 0
				st["fire_acc"]  = 0.0
	_railgun_states[eo] = st

func _nearest(from: Vector2, pts: Array[Vector2]) -> Vector2:
	var best := Vector2(INF, INF)
	var best_d := INF
	for p: Vector2 in pts:
		var d := from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best

# ── Bullet ────────────────────────────────────────────────────────────────────

func _spawn_bullet(from: Vector2, dir: Vector2, dmg: float, tex: Texture2D, impact_idx: int, speed: float = BULLET_SPEED) -> void:
	if tex == null:
		return
	var bsz := tex.get_size()
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = bsz
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.pivot_offset = bsz / 2.0
	tr.rotation = atan2(dir.x, -dir.y)
	tr.position = from - bsz / 2.0
	tr.scale = Vector2(_current_scale, _current_scale)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.z_as_relative = false
	tr.z_index = (_spaceship_eo.z_index + 50) if _spaceship_eo != null else 150
	add_child(tr)
	_bullets.append(tr)
	_bullet_vel.append(dir * speed)
	_bullet_dmg.append(dmg)
	_bullet_imp_idx.append(impact_idx)

func _tick_bullets(delta: float) -> void:
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	var i := _bullets.size() - 1
	while i >= 0:
		var tr: TextureRect = _bullets[i]
		if not is_instance_valid(tr):
			_bullets.remove_at(i); _bullet_vel.remove_at(i); _bullet_dmg.remove_at(i); _bullet_imp_idx.remove_at(i); i -= 1; continue
		tr.position += _bullet_vel[i] * delta
		var center := tr.position + tr.size * 0.5
		var hit := false
		if is_instance_valid(ast_node) and ast_node.has_method("get_asteroid_centers"):
			var centers: Array[Vector2] = ast_node.get_asteroid_centers()
			var sizes: Array[Vector2]   = ast_node.get_asteroid_sizes()
			for j in range(centers.size()):
				var c: Vector2 = centers[j] + SS_OFFSET
				if center.distance_to(c) < 18.0:
					var dir := _bullet_vel[i].normalized()
					var idx: int      = _bullet_imp_idx[i]
					var is_turret:    bool = idx == 1
					var is_railgun:   bool = idx == 2
					var is_canon:     bool = idx == 3
					var is_canon_mk2: bool = idx == 4
					var imp_f: Array = _turret_impact_frames if is_turret else \
						(_canon_impact_mk2_frames if is_canon_mk2 else \
						(_canon_impact_frames if is_canon else _impact_frames))
					var imp_d: Array = _turret_impact_delays if is_turret else \
						(_canon_impact_mk2_delays if is_canon_mk2 else \
						(_canon_impact_delays if is_canon else _impact_delays))
					var fixed: float = 10.0 if is_railgun else \
						(60.0 if is_canon_mk2 else (30.0 if is_canon else 0.0))
					_spawn_impact(centers[j], ast_node, sizes[j], dir, imp_f, imp_d, 0.0, fixed)
					if is_canon_mk2:
						for i2 in range(centers.size()):
							var c2: Vector2 = centers[i2] + SS_OFFSET
							if center.distance_to(c2) < CANON_MK2_IMPACT_RADIUS:
								ast_node.damage_near(centers[i2], 5.0, 1.0)
						WeaponManager.record_damage("left_canon_heavy_bolt", 1.0)
					else:
						ast_node.damage_near(centers[j], 22.0, _bullet_dmg[i])
						var wid: String = "turret" if is_turret else \
							("railgun" if is_railgun else ("left_canon_heavy_bolt" if is_canon else "gun"))
						WeaponManager.record_damage(wid, _bullet_dmg[i])
					var ast_w: float = sizes[j].x
					var boom_key: String = "turret" if is_turret else \
						("canon" if (is_canon or is_canon_mk2) else "gun")
					if ast_w >= 45.0:
						_play_sfx(_sfx_gun_boom_big, boom_key)
					elif not _sfx_gun_booms.is_empty():
						_play_sfx(_sfx_gun_booms[randi() % _sfx_gun_booms.size()], boom_key)
					hit = true
					break
		if not hit:
			var _bf := get_tree().get_first_node_in_group("boss_fight")
			if _bf != null:
				var brect: Rect2 = _bf.call("get_boss_hit_rect")
				if brect.has_area() and brect.has_point(center):
					GameManager.take_boss_damage(maxi(1, int(round(_bullet_dmg[i]))))
					hit = true
		if not hit:
			hit = not SCREEN_BOUNDS_INSET.has_point(center)
		if hit:
			tr.queue_free(); _bullets.remove_at(i); _bullet_vel.remove_at(i); _bullet_dmg.remove_at(i); _bullet_imp_idx.remove_at(i)
		i -= 1

# ── Shell ─────────────────────────────────────────────────────────────────────

func _spawn_shell(gun_ss: Vector2, fire_dir: Vector2, eject_left: bool) -> void:
	if _shell_tex == null:
		return
	# LGun ejects left (X < gun.X), RGun ejects right (X > gun.X)
	var perp := Vector2(fire_dir.y, -fire_dir.x) if eject_left else Vector2(-fire_dir.y, fire_dir.x)
	var vel := (perp * 0.8 - fire_dir * 0.3).normalized() * SHELL_EJECT_SPEED
	var ssz := _shell_tex.get_size()
	var tr := TextureRect.new()
	tr.texture = _shell_tex
	tr.size = ssz
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.pivot_offset = ssz / 2.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.position = gun_ss - ssz / 2.0
	tr.z_as_relative = false
	tr.z_index = (_spaceship_eo.z_index + 50) if _spaceship_eo != null else 150
	add_child(tr)
	_shells.append(tr)
	_shell_vel.append(vel)
	_shell_age.append(0.0)
	_shell_rot_spd.append(randf_range(-1.0, 1.0) * 15.0 * PI)

func _tick_shells(delta: float) -> void:
	var i := _shells.size() - 1
	while i >= 0:
		var tr: TextureRect = _shells[i]
		if not is_instance_valid(tr):
			_shells.remove_at(i); _shell_vel.remove_at(i)
			_shell_age.remove_at(i); _shell_rot_spd.remove_at(i); i -= 1; continue
		var age: float = _shell_age[i] + delta
		_shell_age[i] = age
		tr.position += _shell_vel[i] * delta
		if age > SHELL_ROT_DELAY:
			tr.rotation += _shell_rot_spd[i] * delta
		if age > SHELL_FADE_START:
			tr.modulate.a = clampf(
				1.0 - (age - SHELL_FADE_START) / (SHELL_LIFETIME - SHELL_FADE_START), 0.0, 1.0)
		if age >= SHELL_LIFETIME:
			tr.queue_free()
			_shells.remove_at(i); _shell_vel.remove_at(i)
			_shell_age.remove_at(i); _shell_rot_spd.remove_at(i)
		i -= 1

# ── Impact ────────────────────────────────────────────────────────────────────

func _spawn_impact(ss_center: Vector2, screen: Node, asteroid_size: Vector2, direction: Vector2, imp_frames: Array, imp_delays: Array, rot_offset: float = 0.0, fixed_size: float = 0.0) -> void:
	if imp_frames.is_empty() or not is_instance_valid(screen):
		return
	var impact_size := IMPACT_SIZE
	if fixed_size > 0.0:
		impact_size = Vector2(fixed_size, fixed_size)
	elif asteroid_size != Vector2.ZERO:
		var ast_scale: float = (asteroid_size.x + asteroid_size.y) * 0.5 / ((IMPACT_SIZE.x + IMPACT_SIZE.y) * 0.5)
		impact_size = IMPACT_SIZE * ast_scale
	var tr := TextureRect.new()
	tr.texture = imp_frames[0]
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.z_index = 5
	screen.add_child(tr)
	tr.size = impact_size
	tr.pivot_offset = impact_size * 0.5
	tr.position = ss_center - impact_size * 0.5
	tr.rotation = atan2(direction.y, direction.x) + PI * 0.5 + rot_offset
	tr.scale = Vector2(_current_scale, _current_scale)
	_impacts.append({"tr": tr, "frame": 0, "acc": 0.0, "frames": imp_frames, "delays": imp_delays})

func _tick_impacts(delta: float) -> void:
	var i := _impacts.size() - 1
	while i >= 0:
		var d: Dictionary = _impacts[i]
		var tr: TextureRect = d["tr"]
		if not is_instance_valid(tr):
			_impacts.remove_at(i); i -= 1; continue
		var acc: float   = float(d["acc"]) + delta
		var frm: int     = int(d["frame"])
		var frames: Array  = d.get("frames", _impact_frames)
		var delays: Array  = d.get("delays", _impact_delays)
		var delay: float = float(delays[frm]) if frm < delays.size() else 0.05
		if acc >= delay:
			acc -= delay
			frm += 1
			if frm >= frames.size():
				tr.queue_free(); _impacts.remove_at(i); i -= 1; continue
			tr.texture = frames[frm]
		d["acc"] = acc; d["frame"] = frm; _impacts[i] = d
		i -= 1

# ── Weapon fire animation ──────────────────────────────────────────────────────

## Resize GIF frames CPU-side về đúng kích thước PNG, đặt đúng vị trí PNG
func _start_weapon_anim(eo: EditableObjectNode, frames: Array, delays: Array) -> void:
	if frames.is_empty():
		return
	var resized: Array = []
	for f in frames:
		resized.append(_resize_frame(f as Texture2D, eo.size))
	# Ẩn static frame (frame 0 tĩnh) trong lúc animation chạy
	if _static_rects.has(eo) and is_instance_valid(_static_rects[eo]):
		_static_rects[eo].visible = false
	var tr := TextureRect.new()
	tr.texture = resized[0] as Texture2D
	tr.size = eo.size
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rel_wa: Vector2 = _weapon_eo_rels.get(eo, Vector2.ZERO)
	tr.position = _spaceship_origin_sz * 0.5 + rel_wa - eo.size * 0.5
	tr.flip_h   = eo.texture_rect.flip_h
	tr.z_as_relative = false
	tr.z_index  = _eo_effective_z(eo)
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		_spaceship_eo.add_child(tr)
	else:
		add_child(tr)
	_gun_anims.append({"tr": tr, "frame": 0, "acc": 0.0, "gun_eo": eo, "frames": resized, "delays": delays})

func _start_gun_anim(eo: EditableObjectNode, tier: int) -> void:
	var frames: Array
	var delays: Array
	if tier >= 2 and not _gun_mk3_frames.is_empty():
		frames = _gun_mk3_frames; delays = _gun_mk3_delays
	elif tier >= 1 and not _gun_mk2_frames.is_empty():
		frames = _gun_mk2_frames; delays = _gun_mk2_delays
	else:
		frames = _gun_frames; delays = _gun_delays
	_start_weapon_anim(eo, frames, delays)

func _start_turret_anim(eo: EditableObjectNode, tier: int = 0) -> void:
	var frames := _turret_mk2_frames if tier >= 1 and not _turret_mk2_frames.is_empty() else _turret_frames
	var delays := _turret_mk2_delays if tier >= 1 and not _turret_mk2_delays.is_empty() else _turret_delays
	_start_weapon_anim(eo, frames, delays)

func _tick_gun_anims(delta: float) -> void:
	var i := _gun_anims.size() - 1
	while i >= 0:
		var d: Dictionary = _gun_anims[i]
		var raw_tr = d.get("tr")
		if not is_instance_valid(raw_tr):
			_gun_anims.remove_at(i); i -= 1; continue
		var tr := raw_tr as TextureRect
		if tr == null:
			_gun_anims.remove_at(i); i -= 1; continue
		var acc: float   = float(d["acc"]) + delta
		var frm: int     = int(d["frame"])
		var frames: Array  = d.get("frames", _gun_frames)
		var delays: Array  = d.get("delays", _gun_delays)
		var delay: float = float(delays[frm]) if frm < delays.size() else 0.05
		if acc >= delay:
			acc -= delay
			frm += 1
			if frm >= frames.size():
				if d.get("loop", false):
					frm = 0
					tr.texture = frames[0] as Texture2D
				else:
					tr.queue_free()
					var raw_gun_eo = d.get("gun_eo")
					if raw_gun_eo != null and is_instance_valid(raw_gun_eo):
						var gun_eo := raw_gun_eo as EditableObjectNode
						if gun_eo != null:
							if _static_rects.has(gun_eo) and is_instance_valid(_static_rects[gun_eo]):
								_static_rects[gun_eo].visible = true
							else:
								gun_eo.modulate.a = 1.0
							if d.get("fire_on_end", false):
								_fire_canon_bullet(gun_eo)
					_gun_anims.remove_at(i); i -= 1; continue
			else:
				tr.texture = frames[frm]
		d["acc"] = acc; d["frame"] = frm; _gun_anims[i] = d
		i -= 1

# ── Lightning Emitter ──────────────────────────────────────────────────────────

func _fire_lightning(eo: EditableObjectNode) -> void:
	if not MOUNT_AUTOFIRE: return
	var float_off := Vector2(sin(_float_time * 2.3), cos(_float_time * 1.7)) * FLOAT_RADIUS
	var emitter_oc := eo.global_position + eo.size * 0.5 + float_off
	if GameManager.boss_max_hp > 0:
		var boss_t := _boss_target_oc()
		if is_finite(boss_t.x):
			var line := _make_lightning(emitter_oc, boss_t)
			_lightning_chains.append({"lines": [line], "age": 0.0})
			if not _sfx_zaps.is_empty():
				_play_sfx(_sfx_zaps[randi() % _sfx_zaps.size()], "lightning")
			GameManager.take_boss_damage(5)
		return
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	if not is_instance_valid(ast_node) or not ast_node.has_method("get_asteroid_centers"):
		return
	var centers_ss: Array[Vector2] = ast_node.get_asteroid_centers()
	if centers_ss.is_empty():
		return
	# Chain: emitter → A → B → C
	var targets_oc: Array[Vector2] = []
	var used: Array[int] = []
	var prev_oc := emitter_oc
	for _n in range(LIGHTNING_CHAIN_COUNT):
		var best_i := -1
		var best_d := INF
		for i in range(centers_ss.size()):
			if i in used:
				continue
			var c_oc := centers_ss[i] + SS_OFFSET
			var dist := prev_oc.distance_to(c_oc)
			if dist > 100.0:
				continue
			var d2 := dist * dist
			if d2 < best_d:
				best_d = d2; best_i = i
		if best_i < 0:
			break
		used.append(best_i)
		targets_oc.append(centers_ss[best_i] + SS_OFFSET)
		prev_oc = targets_oc[-1]
	if targets_oc.is_empty():
		return
	var lines: Array = []
	var prev := emitter_oc
	for t_oc in targets_oc:
		lines.append(_make_lightning(prev, t_oc))
		if not _sfx_zaps.is_empty():
			_play_sfx(_sfx_zaps[randi() % _sfx_zaps.size()], "lightning")
		prev = t_oc
	_lightning_chains.append({"lines": lines, "age": 0.0})
	for t_oc in targets_oc:
		ast_node.damage_near(t_oc - SS_OFFSET, 15.0, 1)
	WeaponManager.record_damage("lightning_emitter", float(targets_oc.size()))
	var _bf_l := get_tree().get_first_node_in_group("boss_fight")
	if _bf_l != null:
		var brect_l: Rect2 = _bf_l.call("get_boss_hit_rect")
		if brect_l.has_area():
			for t_oc in targets_oc:
				if brect_l.has_point(t_oc):
					GameManager.take_boss_damage(5)
					break

func _make_lightning(from_oc: Vector2, to_oc: Vector2) -> Line2D:
	var line := Line2D.new()
	line.width = 1.5
	line.default_color = Color(0.55, 0.85, 1.0, 1.0)
	var perp := (to_oc - from_oc).rotated(PI * 0.5).normalized()
	var pts := PackedVector2Array()
	pts.append(from_oc)
	for i in range(1, 8):
		var t: float = float(i) / 8.0
		var p := from_oc.lerp(to_oc, t)
		p += perp * randf_range(-5.0, 5.0)
		p.x = clampf(p.x, SCREEN_BOUNDS_INSET.position.x, SCREEN_BOUNDS_INSET.end.x)
		p.y = clampf(p.y, SCREEN_BOUNDS_INSET.position.y, SCREEN_BOUNDS_INSET.end.y)
		pts.append(p)
	pts.append(to_oc)
	line.points = pts
	add_child(line)
	return line

func _tick_lightning_chains(delta: float) -> void:
	var i := _lightning_chains.size() - 1
	while i >= 0:
		var d: Dictionary = _lightning_chains[i]
		var age: float = float(d["age"]) + delta
		if age >= LIGHTNING_DURATION:
			for line in d["lines"]:
				if is_instance_valid(line):
					(line as Line2D).queue_free()
			_lightning_chains.remove_at(i)
		else:
			var alpha: float = 1.0 - age / LIGHTNING_DURATION
			for line in d["lines"]:
				if is_instance_valid(line):
					(line as Line2D).modulate.a = alpha
			d["age"] = age; _lightning_chains[i] = d
		i -= 1

# ── Ship collision (boost mode) ────────────────────────────────────────────────

func _check_ship_asteroid_collision() -> void:
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	if not is_instance_valid(ast_node) or not ast_node.has_method("check_ship_collision"):
		return
	var ship_center_oc := _spaceship_eo.global_position + _spaceship_origin_sz * 0.5
	var ship_center_ss := ship_center_oc - SS_OFFSET
	var ship_radius    := _spaceship_origin_sz.x * 0.5 * _current_scale
	ast_node.check_ship_collision(ship_center_ss, ship_radius)

# ── Laser (click ship) ─────────────────────────────────────────────────────────

func _on_ship_clicked(_obj: EditableObjectNode) -> void:
	if GameManager.ship_hp <= 0:
		return
	if not _sfx_lasers.is_empty():
		_play_sfx(_sfx_lasers[randi() % _sfx_lasers.size()])
	# Pop effect: to nhẹ 3% rồi về lại _current_scale
	if _spaceship_eo != null and is_instance_valid(_spaceship_eo):
		if _ship_pop_tween and _ship_pop_tween.is_valid():
			_ship_pop_tween.kill()
		var pop := _current_scale * 1.03
		_ship_pop_tween = create_tween()
		_ship_pop_tween.tween_property(_spaceship_eo, "scale",
			Vector2(pop, pop), 0.05)
		_ship_pop_tween.tween_property(_spaceship_eo, "scale",
			Vector2(_current_scale, _current_scale), 0.15)
	var ship_oc := _spaceship_eo.global_position + _spaceship_origin_sz * 0.5
	if GameManager.boss_max_hp > 0:
		var boss_t := _boss_target_oc()
		if is_finite(boss_t.x):
			var line := _make_laser_line(ship_oc, boss_t)
			_lasers.append({"lines": [line], "age": 0.0})
			GameManager.take_boss_damage(10)
		return
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	if not is_instance_valid(ast_node) or not ast_node.has_method("get_asteroid_centers"):
		return
	var centers_ss: Array[Vector2] = ast_node.get_asteroid_centers()
	if centers_ss.is_empty():
		return
	# 3 nearest asteroids
	var sorted := centers_ss.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return ship_oc.distance_squared_to(a + SS_OFFSET) < ship_oc.distance_squared_to(b + SS_OFFSET))
	var targets: Array[Vector2] = []
	for i in range(mini(LASER_COUNT, sorted.size())):
		targets.append(sorted[i])
	var lines: Array = []
	for t_ss in targets:
		var t_oc := t_ss + SS_OFFSET
		lines.append(_make_laser_line(ship_oc, t_oc))
		_laser_raycast(ship_oc, t_oc, ast_node, centers_ss)
	_lasers.append({"lines": lines, "age": 0.0})

func _make_laser_line(from_oc: Vector2, to_oc: Vector2) -> Node2D:
	var clipped := _clip_to_bounds(from_oc, to_oc)
	var pts    := PackedVector2Array([from_oc, clipped])
	var root   := Node2D.new()
	root.z_index       = 4
	root.z_as_relative = false   # absolute — dưới spaceship (z=6)
	# Outer glow
	var g1 := Line2D.new(); g1.width = 5.0
	g1.default_color = Color(1.0, 0.05, 0.05, 0.10); g1.points = pts
	root.add_child(g1)
	# Mid shimmer
	var g2 := Line2D.new(); g2.width = 1.8
	g2.default_color = Color(1.0, 0.35, 0.35, 0.55); g2.points = pts
	root.add_child(g2)
	# Bright core
	var g3 := Line2D.new(); g3.width = 0.5
	g3.default_color = Color(1.0, 0.92, 0.92, 1.0); g3.points = pts
	root.add_child(g3)
	get_parent().add_child(root)
	return root

func _clip_to_bounds(from_oc: Vector2, to_oc: Vector2) -> Vector2:
	var b := SCREEN_BOUNDS_INSET
	var dir := (to_oc - from_oc)
	var t_max := 1.0
	for axis in [0, 1]:
		if abs(dir[axis]) < 0.001:
			continue
		var t0 := (b.position[axis] - from_oc[axis]) / dir[axis]
		var t1 := (b.end[axis]      - from_oc[axis]) / dir[axis]
		if t0 > t1:
			var tmp := t0; t0 = t1; t1 = tmp
		t_max = minf(t_max, t1)
	return from_oc + dir * clampf(t_max, 0.0, 1.0)

func _laser_raycast(from_oc: Vector2, to_oc: Vector2, ast_node: Node, centers_ss: Array[Vector2]) -> void:
	var dir := (to_oc - from_oc).normalized()
	var len := from_oc.distance_to(to_oc)
	for i in range(centers_ss.size()):
		var c_oc := centers_ss[i] + SS_OFFSET
		# Project onto laser direction
		var t := (c_oc - from_oc).dot(dir)
		if t < 0.0 or t > len:
			continue
		var closest := from_oc + dir * t
		if closest.distance_to(c_oc) < 18.0:
			ast_node.damage_near(centers_ss[i], 5.0, 1)
	var _bf_r := get_tree().get_first_node_in_group("boss_fight")
	if _bf_r != null:
		var brect_r: Rect2 = _bf_r.call("get_boss_hit_rect")
		if brect_r.has_area():
			var t_b := (brect_r.get_center() - from_oc).dot(dir)
			if t_b >= 0.0 and t_b <= len:
				GameManager.take_boss_damage(5)

func _tick_lasers(delta: float) -> void:
	var i := _lasers.size() - 1
	while i >= 0:
		var d: Dictionary = _lasers[i]
		var age: float = float(d["age"]) + delta
		if age >= LASER_DURATION:
			for node in d["lines"]:
				if is_instance_valid(node):
					(node as Node).queue_free()
			_lasers.remove_at(i)
		else:
			var alpha := 1.0 - age / LASER_DURATION
			for node in d["lines"]:
				if is_instance_valid(node):
					(node as CanvasItem).modulate.a = alpha
			d["age"] = age; _lasers[i] = d
		i -= 1

func _find_spaceship_eo() -> EditableObjectNode:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return null
	for child in parent.get_children():
		var eo := child as EditableObjectNode
		if eo != null and eo.source_path.get_file().get_basename().to_lower() == "spaceship":
			return eo
	return null
