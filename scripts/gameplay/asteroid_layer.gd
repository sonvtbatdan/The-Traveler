extends Control

const ASTEROID_DIR: String = "res://assets/asteroid/"
const MIN_SPEED: float = 30.0
const MAX_SPEED: float = 120.0
const MIN_W: float = 5.0
const MAX_W: float = 50.0
const MIN_COUNT: int = 5
const MAX_COUNT: int = 50
const MIN_RPM: float = 3.0
const MAX_RPM: float = 30.0
const CONE_HALF_DEG: float = 15.0
const MIN_HITBOX: float = 36.0
const HP_PER_WIDTH: float = 1.5   # asteroid HP = width × this (tune to taste)

var _is_under: bool = false
var _screen_w: float = 0.0
var _screen_h: float = 0.0
var _source_imgs: Array[Image] = []
var _img_types: Array[String] = []
var _blur_mat: ShaderMaterial = null

var _nodes: Array[TextureRect] = []
var _velocities: Array[Vector2] = []
var _rot_speeds: Array[float] = []
var _hp: Array[float] = []        # current HP, parallel to _nodes
var _hp_max: Array[float] = []    # full HP, parallel to _nodes

func setup(screen_w: float, screen_h: float, is_under: bool) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 0 if is_under else 1
	_is_under = is_under
	_screen_w = screen_w
	_screen_h = screen_h
	if is_under:
		_build_blur_mat()
	else:
		add_to_group("asteroid_main")
	_load_textures()
	var count: int = randi_range(MIN_COUNT, MAX_COUNT)
	for _i: int in count:
		_spawn(true)

func _build_blur_mat() -> void:
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE * 3.0;
	vec4 c = texture(TEXTURE, UV);
	c += texture(TEXTURE, UV + vec2( ps.x,  0.0));
	c += texture(TEXTURE, UV + vec2(-ps.x,  0.0));
	c += texture(TEXTURE, UV + vec2( 0.0,  ps.y));
	c += texture(TEXTURE, UV + vec2( 0.0, -ps.y));
	c += texture(TEXTURE, UV + vec2( ps.x,  ps.y));
	c += texture(TEXTURE, UV + vec2(-ps.x,  ps.y));
	c += texture(TEXTURE, UV + vec2( ps.x, -ps.y));
	c += texture(TEXTURE, UV + vec2(-ps.x, -ps.y));
	COLOR = c / 9.0;
}"""
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = shader

func _load_textures() -> void:
	var dir := DirAccess.open(ASTEROID_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".png"):
			var raw := load(ASTEROID_DIR + fname) as Texture2D
			if raw:
				_source_imgs.append(raw.get_image())
				_img_types.append(_extract_type(fname))
		fname = dir.get_next()
	dir.list_dir_end()

func _extract_type(fname: String) -> String:
	var base: String = fname.get_basename()
	var result: String = ""
	for ch: String in base:
		if ch >= "0" and ch <= "9":
			break
		result += ch
	return result

func _spawn(initial: bool) -> void:
	if _source_imgs.is_empty():
		return
	var pick: int = randi() % _source_imgs.size()
	var src_img: Image = _source_imgs[pick]
	var type_name: String = _img_types[pick]
	var sw: int = src_img.get_width()
	var sh: int = src_img.get_height()
	var w: float = randf_range(MIN_W, MAX_W)
	var h: float = w * (float(sh) / float(sw)) if sw > 0 else w

	var x: float = randf_range(0.0, _screen_w)
	var y: float = -h if not initial else randf_range(-h, _screen_h)

	var angle_rad: float = deg_to_rad(randf_range(-CONE_HALF_DEG, CONE_HALF_DEG))
	var speed: float = randf_range(MIN_SPEED, MAX_SPEED)
	var vel: Vector2 = Vector2(sin(angle_rad), cos(angle_rad)) * speed

	var rpm: float = randf_range(MIN_RPM, MAX_RPM)
	if randf() < 0.5:
		rpm = -rpm
	var rot_speed: float = rpm * TAU / 60.0

	var img := src_img.duplicate()
	img.resize(int(w), int(h), Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)

	var hit_w: float = max(w, MIN_HITBOX)
	var hit_h: float = max(h, MIN_HITBOX)

	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = Vector2(hit_w, hit_h)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tr.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tr.pivot_offset = Vector2(hit_w * 0.5, hit_h * 0.5)
	tr.position = Vector2(x - hit_w * 0.5, y - (hit_h - h) * 0.5)
	tr.set_meta("type", type_name)

	if _is_under:
		tr.modulate = Color(0.35, 0.35, 0.45, 0.85)
		if _blur_mat != null:
			tr.material = _blur_mat
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_asteroid_gui_input.bind(tr))

	var hp: float = maxf(1.0, w * HP_PER_WIDTH)

	add_child(tr)
	_nodes.append(tr)
	_velocities.append(vel)
	_rot_speeds.append(rot_speed)
	_hp.append(hp)
	_hp_max.append(hp)

func _on_asteroid_gui_input(event: InputEvent, tr: TextureRect) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_on_asteroid_clicked(tr)

func _on_asteroid_clicked(tr: TextureRect) -> void:
	var idx: int = _nodes.find(tr)
	if idx < 0:
		return
	_destroy_index(idx, true)   # clicking grabs the whole rock regardless of HP

# ── Damage API (used by weapon_system; works in this layer's local space) ─────

## Damage the nearest asteroid whose body contains local_pos (within hit_radius).
## Returns true if something was hit (so a bullet can despawn).
func damage_point(local_pos: Vector2, hit_radius: float, amount: float) -> bool:
	var best: int = -1
	var best_d: float = INF
	for i in range(_nodes.size()):
		var tr: TextureRect = _nodes[i]
		if not is_instance_valid(tr):
			continue
		var center: Vector2 = tr.position + tr.size * 0.5
		var ar: float = maxf(tr.size.x, tr.size.y) * 0.5
		var d: float = center.distance_to(local_pos)
		if d <= ar + hit_radius and d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	_apply_damage(best, amount)
	return true

## Damage every asteroid within radius of center. Returns the centers that were
## hit (for visual arcs). Iterates backward so destruction-driven shifts are safe.
func damage_area(center: Vector2, radius: float, amount: float) -> Array:
	var hit_centers: Array = []
	var i: int = _nodes.size() - 1
	while i >= 0:
		var tr: TextureRect = _nodes[i]
		if is_instance_valid(tr):
			var c: Vector2 = tr.position + tr.size * 0.5
			var ar: float = maxf(tr.size.x, tr.size.y) * 0.5
			if c.distance_to(center) <= radius + ar:
				hit_centers.append(c)
				_apply_damage(i, amount)
		i -= 1
	return hit_centers

## Piercing hit: deal dmg_pool to the nearest asteroid containing local_pos, and
## return how much damage was ABSORBED (= min(dmg_pool, that asteroid's HP)).
## The caller subtracts that from its projectile's remaining damage so the shot
## keeps going with the leftover. Returns 0.0 if nothing was hit.
func pierce_at(local_pos: Vector2, hit_radius: float, dmg_pool: float) -> float:
	var best: int = -1
	var best_d: float = INF
	for i in range(_nodes.size()):
		var tr: TextureRect = _nodes[i]
		if not is_instance_valid(tr):
			continue
		var center: Vector2 = tr.position + tr.size * 0.5
		var ar: float = maxf(tr.size.x, tr.size.y) * 0.5
		var d: float = center.distance_to(local_pos)
		if d <= ar + hit_radius and d < best_d:
			best_d = d
			best = i
	if best < 0:
		return 0.0
	var absorbed: float = minf(dmg_pool, _hp[best])
	_apply_damage(best, dmg_pool)
	return absorbed

## Damaged asteroids (HP < full), for drawing HP bars on the weapon layer.
func get_damaged_asteroids() -> Array:
	var out: Array = []
	for i in range(_nodes.size()):
		var tr: TextureRect = _nodes[i]
		if not is_instance_valid(tr):
			continue
		if _hp[i] < _hp_max[i]:
			out.append({
				"pos": tr.position + tr.size * 0.5,
				"w": tr.size.x,
				"frac": clampf(_hp[i] / _hp_max[i], 0.0, 1.0),
			})
	return out

func _apply_damage(i: int, amount: float) -> void:
	if i < 0 or i >= _hp.size():
		return
	_hp[i] -= amount
	if _hp[i] <= 0.0:
		_destroy_index(i, true)
	else:
		_flash(_nodes[i])

func _flash(tr: TextureRect) -> void:
	if not is_instance_valid(tr):
		return
	tr.modulate = Color(2.4, 2.4, 2.4, 1.0)
	var t := create_tween()
	t.tween_property(tr, "modulate", Color.WHITE, 0.18)

## Remove an asteroid from all parallel arrays (no loot/fade) and respawn one.
func _remove_index(i: int) -> void:
	_nodes.remove_at(i)
	_velocities.remove_at(i)
	_rot_speeds.remove_at(i)
	_hp.remove_at(i)
	_hp_max.remove_at(i)

## Destroy an asteroid: optional loot, fade out, remove from arrays, respawn.
func _destroy_index(i: int, give_loot: bool) -> void:
	var tr: TextureRect = _nodes[i]
	if give_loot and is_instance_valid(tr):
		_collect_loot(String(tr.get_meta("type", "")))
	_remove_index(i)
	if is_instance_valid(tr):
		_fade_and_free(tr)
	_spawn(false)

func _fade_and_free(tr: TextureRect) -> void:
	if not is_instance_valid(tr):
		return
	var tween := create_tween()
	tween.tween_property(tr, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		if is_instance_valid(tr):
			tr.queue_free())

func get_asteroid_centers() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for tr: TextureRect in _nodes:
		if is_instance_valid(tr):
			result.append(tr.position + tr.size * 0.5)
	return result

func get_asteroid_sizes() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for tr: TextureRect in _nodes:
		if is_instance_valid(tr):
			result.append(tr.texture.get_size() if tr.texture != null else tr.size)
	return result


func collect_near(pos: Vector2, radius: float) -> void:
	var i: int = _nodes.size() - 1
	while i >= 0:
		var tr: TextureRect = _nodes[i]
		if is_instance_valid(tr):
			var center: Vector2 = tr.position + tr.size * 0.5
			if center.distance_to(pos) <= radius:
				_destroy_index(i, true)
		i -= 1

func _collect_loot(type_name: String) -> void:
	var r: float = randf()
	match type_name:
		"dirt":
			if r < 0.50:
				pass
			elif r < 0.75:
				MaterialManager.add("organic", 1)
			else:
				MaterialManager.add("nonmetal", 1)
		"ice":
			if r < 0.25:
				pass
			elif r < 0.75:
				MaterialManager.add("liquid", 1)
			else:
				MaterialManager.add("organic", 1)
		"jewel":
			if r < 0.25:
				MaterialManager.add("metal", 1)
			elif r < 0.75:
				MaterialManager.add("nonmetal", 1)
			else:
				MaterialManager.add("liquid", 1)
		"metal":
			if r < 0.25:
				MaterialManager.add("metal", 2)
			elif r < 0.75:
				MaterialManager.add("metal", 1)
		"rare":
			if r < 0.25:
				MaterialManager.add("metal", 1)
				MaterialManager.add("nonmetal", 1)
			elif r < 0.50:
				MaterialManager.add("organic", 1)
				MaterialManager.add("liquid", 1)
			elif r < 0.75:
				MaterialManager.add("organic", 1)
				MaterialManager.add("metal", 1)
			else:
				MaterialManager.add("liquid", 1)
				MaterialManager.add("nonmetal", 1)

func _process(delta: float) -> void:
	var i: int = _nodes.size() - 1
	while i >= 0:
		var tr: TextureRect = _nodes[i]
		if not is_instance_valid(tr):
			_remove_index(i)
			i -= 1
			continue
		tr.position += _velocities[i] * delta
		tr.rotation += _rot_speeds[i] * delta
		if tr.position.y > _screen_h:
			tr.queue_free()
			_remove_index(i)
			_spawn(false)
		i -= 1
