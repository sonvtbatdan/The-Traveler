extends Node2D
## Boss: the animated 3D scorpion, as a world-space actor for boss_fight_test.
##
## Renders Scorpion.glb in a SubViewport shown on a Sprite2D (same 3D→2D bridge as the player ship),
## is shootable by the player's weapons (group "arena_enemy" + take_damage), and runs attack "moves".
##
## MOVE 1 ("track & drill"):
##   TRACK phase (TRACK_TIME s) — play "Head bobbing", tilt left/right, and slide horizontally to stay
##     aligned with the player's X (mirrors the player so they can't just walk out from under it).
##   CHARGE phase — accelerate hard toward the player while spinning about the model's long axis (X),
##     like a drill. On reaching the player (or timing out) it loops back to TRACK.
##
## Model axes (from the user's reference): X = long axis (head↔tail) · Z = up↔down · Y = depth.

const MODEL_PATH := "res://assets/3D models/Boss_Scorpion_1.glb"
const MUZZLE_CFG := "res://scorpion_muzzles.cfg"
const VIEWS_CFG  := "res://scorpion_views.cfg"   # named orientations (front/side/top) from test_boss_scorpion
const VP_SIZE    := 320
const DISPLAY_PX := 260.0     # on-screen size of the boss

# ── Look (matches test_boss_scorpion) ──
const METALLIC_MULT := 0.55
const HUE_SHIFT   := 0.0
const SATURATION  := 0.85
const VALUE       := 1.35
const WHITEN_GRAYS := 0.45
const GRAY_SAT_MAX := 0.22
const DARKEN_REDS  := 0.70
const RED_TARGET   := Color("880000")
const RED_HUE_BAND := 0.07
const RED_SAT_MIN  := 0.35

# ── Orientation (tune so the FACE points at the camera / player) ──
# Fallback base facing, only used if scorpion_views.cfg has no saved "side" view yet.
const BASE_YAW_DEG   := 0.0
const BASE_PITCH_DEG := 0.0
const BASE_ROLL_DEG  := 0.0
const SPIN_AXIS := Vector3(0, 0, 1)   # CHARGE spin axis (model-local Z). Tilt is a separate screen-lean.

# ── Move 1 behaviour ──
const HOME_OFFSET := 360.0     # distance to the SIDE of the player it hovers (3/9 o'clock start)
const HOME_SIDE   := 1.0       # +1 = right (3 o'clock), -1 = left (9 o'clock)
const TRACK_TIME  := 3.0       # aiming phase length (matches the tilt timeline)
const HOME_LERP   := 4.0       # how fast it settles beside the player
const TILT_DEG    := 22.0      # left/right lean amplitude (bigger = more dramatic)
const LEAN_EASE   := 70.0      # deg/s the lean eases between holds (lower = slower / more deliberate)
const CHARGE_ACCEL := 1100.0   # px/s^2
const CHARGE_MAX   := 1500.0   # px/s
const SPIN_DPS     := 900.0    # drill-spin speed during CHARGE
const CHARGE_TIMEOUT := 2.0
const REACH_DIST   := 46.0     # "hit" the player within this distance → end charge

const RECOLOR_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_tex : source_color;
uniform sampler2D orm_tex : hint_default_white;
uniform bool has_orm;
uniform float metallic_val;
uniform float roughness_val;
uniform float metallic_mult;
uniform sampler2D normal_tex : hint_normal;
uniform bool has_normal;
uniform float hue_shift;
uniform float sat_mul;
uniform float val_mul;
uniform float white_amt;
uniform float gray_sat_max;
uniform vec3 red_target : source_color;
uniform float red_amt;
uniform float red_hue_band;
uniform float red_sat_min;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void fragment() {
	vec3 orig = texture(albedo_tex, UV).rgb;
	vec3 h = rgb2hsv(orig);
	float gray_mask = (1.0 - smoothstep(gray_sat_max * 0.5, gray_sat_max, h.y)) * smoothstep(0.15, 0.5, h.z);
	float hue_dist = min(h.x, 1.0 - h.x);
	float red_mask = (1.0 - smoothstep(0.0, red_hue_band, hue_dist)) * smoothstep(red_sat_min * 0.5, red_sat_min, h.y);
	h.x = fract(h.x + hue_shift);
	h.y = clamp(h.y * sat_mul, 0.0, 1.0);
	h.z = h.z * val_mul;
	vec3 col = clamp(hsv2rgb(h), 0.0, 1.0);
	col = mix(col, vec3(1.0), clamp(gray_mask * white_amt, 0.0, 1.0));
	col = mix(col, red_target, clamp(red_mask * red_amt, 0.0, 1.0));
	ALBEDO = col;
	float m = metallic_val;
	float r = roughness_val;
	if (has_orm) {
		vec4 orm = texture(orm_tex, UV);
		r = orm.g;
		m = orm.b;
	}
	METALLIC = clamp(m * metallic_mult, 0.0, 1.0);
	ROUGHNESS = r;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
}
"""

# targetable interface (so the player's gatling can lock + hit it)
var hit_radius: float = DISPLAY_PX * 0.35
var _hp: float = 4000.0
var _hp_max: float = 4000.0

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _spr: Sprite2D
var _muzzle_anchors: Dictionary = {}
var _flash: float = 0.0

# move state
enum { TRACK, CHARGE }
var _state: int = TRACK
var _t: float = 0.0
var _spin: float = 0.0
var _lean: float = 0.0
var _vel: Vector2 = Vector2.ZERO
var _charge_dir: Vector2 = Vector2.DOWN
var _views: Dictionary = {}   # "front"/"side"/"top" -> Quaternion, loaded from scorpion_views.cfg


func _ready() -> void:
	add_to_group("arena_enemy")
	z_index = 40
	_load_views()
	_build_viewport()
	_spr = Sprite2D.new()
	_spr.texture = _vp.get_texture()
	var s := DISPLAY_PX / float(VP_SIZE)
	_spr.scale = Vector2(s, s)
	add_child(_spr)
	_play("Head bobbing")
	_apply_model(_view("side"), 0.0, 0.0)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var ppos := player.global_position if player != null else global_position + Vector2(0.0, HOME_OFFSET_Y)

	match _state:
		TRACK:
			_t += delta
			# hover to the SIDE of the player (3/9 o'clock), showing the side profile
			var home := ppos + Vector2(HOME_OFFSET * HOME_SIDE, 0.0)
			global_position = global_position.lerp(home, clampf(HOME_LERP * delta, 0.0, 1.0))
			# deliberate tilt timeline: left 0.5s · right 1s · left 1s · hold 0.5s
			var target := 0.0
			if _t < 0.5:
				target = -1.0
			elif _t < 1.5:
				target = 1.0
			elif _t < 2.5:
				target = -1.0
			_lean = move_toward(_lean, target * deg_to_rad(TILT_DEG), deg_to_rad(LEAN_EASE) * delta)
			_apply_model(_view("side"), _lean, 0.0)
			if _t >= TRACK_TIME:
				_state = CHARGE
				_t = 0.0
				_vel = Vector2.ZERO
				_spin = 0.0
				_charge_dir = (ppos - global_position).normalized()
		CHARGE:
			_t += delta
			_vel = _vel.move_toward(_charge_dir * CHARGE_MAX, CHARGE_ACCEL * delta)
			global_position += _vel * delta
			_spin += deg_to_rad(SPIN_DPS) * delta
			_apply_model(_view("side"), 0.0, _spin)
			if global_position.distance_to(ppos) < REACH_DIST or _t > CHARGE_TIMEOUT:
				_begin_track(ppos)

	queue_redraw()


## Orient the model to a saved base view, add a left/right screen-lean, and spin about SPIN_AXIS.
## `base_q` = saved orientation (e.g. the "side" view) · `lean` = screen-plane left/right tilt ·
## `spin` = rotation about the model's own SPIN_AXIS (the charge drill).
func _apply_model(base_q: Quaternion, lean: float, spin: float) -> void:
	if _pivot == null:
		return
	var base := Basis(base_q)
	# lean about the view-forward axis (world Z) → screen-plane left/right tilt
	var b := Basis(Vector3(0, 0, 1), lean) * base * Basis(SPIN_AXIS.normalized(), spin)
	_pivot.transform = Transform3D(b, Vector3.ZERO)

## A saved orientation (front/side/top) from scorpion_views.cfg; falls back to the BASE_*_DEG euler.
func _view(vname: String) -> Quaternion:
	if _views.has(vname):
		return _views[vname]
	return Basis.from_euler(Vector3(deg_to_rad(BASE_PITCH_DEG), deg_to_rad(BASE_YAW_DEG), deg_to_rad(BASE_ROLL_DEG))).get_rotation_quaternion()

func _load_views() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(VIEWS_CFG) != OK or not cfg.has_section("views"):
		return
	for k: String in cfg.get_section_keys("views"):
		_views[k] = cfg.get_value("views", k)

func _begin_track(ppos: Vector2) -> void:
	_state = TRACK
	_t = 0.0
	_lean = 0.0
	_vel = Vector2.ZERO
	global_position = ppos + Vector2(HOME_OFFSET * HOME_SIDE, 0.0)
	_play("Head bobbing")


# ── Targetable interface (mirrors player_2_test.TargetDummy) ──
func is_dead() -> bool:
	return false   # test dummy: never dies so the fight keeps going

func take_damage(amount: float, _stagger: float = 0.0, _knock: float = 0.0, _ignore_armor: bool = false, _bleeds: bool = false, _was_crit: bool = false, _kind: String = "") -> void:
	_hp = maxf(0.0, _hp - amount)
	_flash = 0.08
	if _hp <= 0.0:
		_hp = _hp_max   # keep it alive for testing

func hp_fraction() -> float:
	return _hp / _hp_max

func _draw() -> void:
	# thin hit-flash ring + a small HP bar above the boss (debug feedback)
	if _flash > 0.0:
		draw_arc(Vector2.ZERO, hit_radius, 0.0, TAU, 32, Color(1.0, 0.9, 0.5, 0.8), 3.0, true)
	var bw := DISPLAY_PX * 0.8
	var by := -DISPLAY_PX * 0.55
	draw_rect(Rect2(-bw * 0.5, by, bw, 6.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-bw * 0.5, by, bw * hp_fraction(), 6.0), Color(0.9, 0.2, 0.2))


# ── 3D render (SubViewport → this node's Sprite2D) ──
func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-40.0), 0.0)
	key.light_energy = 2.2
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 1.1
	_vp.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.88, 0.98)
	e.ambient_light_energy = 2.0
	env.environment = e
	_vp.add_child(env)

	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	var packed := load(MODEL_PATH) as PackedScene
	_model = (packed.instantiate() as Node3D) if packed != null else null
	if _model != null:
		_pivot.add_child(_model)
		_frame_camera(_model)
		_style_materials(_model)
		_load_muzzle_anchors()
		_anim = _find_anim_player(_model)
	else:
		push_warning("boss_scorpion: could not load model at " + MODEL_PATH)
		_cam.position = Vector3(0.0, 0.0, 5.0)
		_cam.look_at(Vector3.ZERO, Vector3.UP)

func _play(clip: String) -> void:
	if _anim == null:
		return
	var a := _anim.get_animation(clip)
	if a != null:
		a.loop_mode = Animation.LOOP_LINEAR
		_anim.play(clip)

func _load_muzzle_anchors() -> void:
	_muzzle_anchors.clear()
	var cfg := ConfigFile.new()
	if _model == null or cfg.load(MUZZLE_CFG) != OK or not cfg.has_section("muzzles"):
		return
	for key: String in cfg.get_section_keys("muzzles"):
		var a := Node3D.new()
		a.position = cfg.get_value("muzzles", key)
		_model.add_child(a)
		_muzzle_anchors[int(key)] = a

## World-space 2D position of muzzle `slot` (for future moves that fire projectiles).
func muzzle_world(slot: int) -> Vector2:
	var a: Node3D = _muzzle_anchors.get(slot, null)
	if a == null or _cam == null or _spr == null:
		return global_position
	var pix := _cam.unproject_position(a.global_position)
	return global_position + (pix - Vector2(VP_SIZE, VP_SIZE) * 0.5) * _spr.scale.x

func _frame_camera(model: Node3D) -> void:
	var aabb := _combined_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	_cam.position = Vector3(0.0, 0.0, dist)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far  = dist + radius * 2.0

func _style_materials(root: Node) -> void:
	for mi: MeshInstance3D in _all_mesh_instances(root):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null:
				continue
			var mat := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = RECOLOR_SHADER
			mat.shader = sh
			var orm := src.metallic_texture
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mat.set_shader_parameter("orm_tex", orm)
			mat.set_shader_parameter("has_orm", orm != null)
			mat.set_shader_parameter("metallic_val", src.metallic)
			mat.set_shader_parameter("roughness_val", src.roughness)
			mat.set_shader_parameter("metallic_mult", METALLIC_MULT)
			mat.set_shader_parameter("normal_tex", src.normal_texture)
			mat.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
			mat.set_shader_parameter("hue_shift", HUE_SHIFT)
			mat.set_shader_parameter("sat_mul", SATURATION)
			mat.set_shader_parameter("val_mul", VALUE)
			mat.set_shader_parameter("white_amt", WHITEN_GRAYS)
			mat.set_shader_parameter("gray_sat_max", GRAY_SAT_MAX)
			mat.set_shader_parameter("red_target", RED_TARGET)
			mat.set_shader_parameter("red_amt", DARKEN_REDS)
			mat.set_shader_parameter("red_hue_band", RED_HUE_BAND)
			mat.set_shader_parameter("red_sat_min", RED_SAT_MIN)
			mi.set_surface_override_material(si, mat)

func _combined_aabb(root: Node) -> AABB:
	var acc := AABB()
	var has := false
	var inv := _pivot.global_transform.affine_inverse()
	for mi: MeshInstance3D in _all_mesh_instances(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c: Node in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
