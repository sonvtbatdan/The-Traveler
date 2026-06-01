extends Control

const SS_OFFSET         := Vector2(270.0, 8.0)
const FIRE_INTERVAL     := 0.5           # 2 shots / second
const BULLET_SPEED      := 500.0
const SHELL_EJECT_SPEED := 80.0
const SHELL_ROT_DELAY   := 0.1
const SHELL_FADE_START  := 0.8
const SHELL_LIFETIME    := 1.3
const SCREEN_BOUNDS     := Rect2(270.0, 8.0, 700.0, 764.0)   # StreamScreen bounds
const GUN_ANIM_SIZE     := Vector2(34.0, 151.0)
const IMPACT_SIZE       := Vector2(20.0, 23.0)                # W=20, H proportional (100:113)

var _bullet_tex:    Texture2D = null
var _shell_tex:     Texture2D = null
var _impact_frames: Array     = []
var _impact_delays: Array     = []
var _gun_frames:    Array     = []
var _gun_delays:    Array     = []

var _bullets:    Array[TextureRect] = []
var _bullet_vel: Array[Vector2]     = []

var _shells:        Array[TextureRect] = []
var _shell_vel:     Array[Vector2]     = []
var _shell_age:     Array[float]       = []
var _shell_rot_spd: Array[float]       = []

var _impacts:   Array = []   # [{tr, frame, acc}]
var _gun_anims: Array = []   # [{tr, frame, acc}]

var _fire_acc: float = 0.0

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_load_assets()

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

func _process(delta: float) -> void:
	_fire_acc += delta
	if _fire_acc >= FIRE_INTERVAL:
		_fire_acc -= FIRE_INTERVAL
		_try_fire()
	_tick_bullets(delta)
	_tick_shells(delta)
	_tick_impacts(delta)
	_tick_gun_anims(delta)

func _try_fire() -> void:
	var gun_objs := WeaponManager.get_active_objects("gun")
	if gun_objs.is_empty():
		return
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	if not is_instance_valid(ast_node) or not ast_node.has_method("get_asteroid_centers"):
		return
	var centers: Array[Vector2] = ast_node.get_asteroid_centers()
	# Convert from StreamScreen space to ObjectsContainer space
	for i in range(centers.size()):
		centers[i] += SS_OFFSET
	if centers.is_empty():
		return
	for eo: EditableObjectNode in gun_objs:
		# Bullet spawns from the top-center of the gun (gun_system in ObjectsContainer space)
		var gun_top := Vector2(
			eo.position.x + eo.size.x * 0.5,
			eo.position.y
		)
		# Only target asteroids above the gun (smaller Y), at least 100px above gun_top
		var valid_centers: Array[Vector2] = []
		for c in centers:
			if c.y <= gun_top.y - 100.0:
				valid_centers.append(c)

		var target := _nearest(gun_top, valid_centers)
		if not is_finite(target.x):
			continue
		var dir := (target - gun_top).normalized()
		_spawn_bullet(gun_top, dir)
		_spawn_shell(gun_top, dir)
		_start_gun_anim(eo)

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

func _spawn_bullet(from: Vector2, dir: Vector2) -> void:
	if _bullet_tex == null:
		return
	var bsz := _bullet_tex.get_size()
	var tr := TextureRect.new()
	tr.texture = _bullet_tex
	tr.size = bsz
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.pivot_offset = bsz / 2.0
	tr.rotation = atan2(dir.x, -dir.y)
	tr.position = from - bsz / 2.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	_bullets.append(tr)
	_bullet_vel.append(dir * BULLET_SPEED)

func _tick_bullets(delta: float) -> void:
	var ast_node := get_tree().get_first_node_in_group("asteroid_main")
	var i := _bullets.size() - 1
	while i >= 0:
		var tr: TextureRect = _bullets[i]
		if not is_instance_valid(tr):
			_bullets.remove_at(i); _bullet_vel.remove_at(i); i -= 1; continue
		tr.position += _bullet_vel[i] * delta
		var center := tr.position + tr.size * 0.5
		var hit := false
		if is_instance_valid(ast_node) and ast_node.has_method("get_asteroid_centers"):
			var centers: Array[Vector2] = ast_node.get_asteroid_centers()
			var sizes: Array[Vector2]   = ast_node.get_asteroid_sizes()
			for j in range(centers.size()):
				var c: Vector2 = centers[j] + SS_OFFSET
				if center.distance_to(c) < 18.0:
					_spawn_impact(centers[j], ast_node, sizes[j])
					ast_node.collect_near(centers[j], 22.0)
					hit = true
					break
		if not hit:
			hit = not SCREEN_BOUNDS.has_point(center)
		if hit:
			tr.queue_free(); _bullets.remove_at(i); _bullet_vel.remove_at(i)
		i -= 1

# ── Shell ─────────────────────────────────────────────────────────────────────

func _spawn_shell(gun_ss: Vector2, fire_dir: Vector2) -> void:
	if _shell_tex == null:
		return
	var perp := Vector2(-fire_dir.y, fire_dir.x) * (1.0 if randf() < 0.5 else -1.0)
	var vel := (perp * 0.8 - fire_dir * 0.3).normalized() * SHELL_EJECT_SPEED
	var ssz := _shell_tex.get_size()
	var tr := TextureRect.new()
	tr.texture = _shell_tex
	tr.size = ssz
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.pivot_offset = ssz / 2.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = gun_ss - ssz / 2.0
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

func _spawn_impact(ss_center: Vector2, screen: Node, asteroid_size: Vector2) -> void:
	if _impact_frames.is_empty() or not is_instance_valid(screen):
		return
	var impact_size := IMPACT_SIZE
	if asteroid_size != Vector2.ZERO:
		var scale: float = (asteroid_size.x + asteroid_size.y) * 0.5 / ((IMPACT_SIZE.x + IMPACT_SIZE.y) * 0.5)
		impact_size = IMPACT_SIZE * scale
	var tr := TextureRect.new()
	tr.texture = _impact_frames[0]
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = 5
	screen.add_child(tr)
	tr.size = impact_size
	tr.pivot_offset = impact_size * 0.5
	tr.position = ss_center - impact_size * 0.5
	_impacts.append({"tr": tr, "frame": 0, "acc": 0.0})

func _tick_impacts(delta: float) -> void:
	var i := _impacts.size() - 1
	while i >= 0:
		var d: Dictionary = _impacts[i]
		var tr: TextureRect = d["tr"]
		if not is_instance_valid(tr):
			_impacts.remove_at(i); i -= 1; continue
		var acc: float = float(d["acc"]) + delta
		var frm: int   = int(d["frame"])
		var delay: float = float(_impact_delays[frm]) if frm < _impact_delays.size() else 0.05
		if acc >= delay:
			acc -= delay
			frm += 1
			if frm >= _impact_frames.size():
				tr.queue_free(); _impacts.remove_at(i); i -= 1; continue
			tr.texture = _impact_frames[frm]
		d["acc"] = acc; d["frame"] = frm; _impacts[i] = d
		i -= 1

# ── Gun fire animation ─────────────────────────────────────────────────────────

func _start_gun_anim(eo: EditableObjectNode) -> void:
	if _gun_frames.is_empty():
		return
	# Hide the gun sprite, show animation at its position (ObjectsContainer space)
	eo.visible = false
	var tr := TextureRect.new()
	tr.texture = _gun_frames[0]
	tr.size = GUN_ANIM_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = eo.position
	tr.flip_h = eo.texture_rect.flip_h
	add_child(tr)
	_gun_anims.append({"tr": tr, "frame": 0, "acc": 0.0, "gun_eo": eo})

func _tick_gun_anims(delta: float) -> void:
	var i := _gun_anims.size() - 1
	while i >= 0:
		var d: Dictionary = _gun_anims[i]
		var tr: TextureRect = d["tr"]
		if not is_instance_valid(tr):
			_gun_anims.remove_at(i); i -= 1; continue
		var acc: float = float(d["acc"]) + delta
		var frm: int   = int(d["frame"])
		var delay: float = float(_gun_delays[frm]) if frm < _gun_delays.size() else 0.05
		if acc >= delay:
			acc -= delay
			frm += 1
			if frm >= _gun_frames.size():
				tr.queue_free()
				var gun_eo: EditableObjectNode = d.get("gun_eo")
				if gun_eo != null and is_instance_valid(gun_eo):
					gun_eo.visible = true
				_gun_anims.remove_at(i); i -= 1; continue
			tr.texture = _gun_frames[frm]
		d["acc"] = acc; d["frame"] = frm; _gun_anims[i] = d
		i -= 1
