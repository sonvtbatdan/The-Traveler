extends Control
## Standalone viewer for the Scorpion model.
##
## Renders the model in a 3D SubViewport with native materials. Auto-spins so you can watch it;
## drag / keys to rotate, Space to play a baked animation (if any).
##
## Controls:  drag = orbit · ←→/AD yaw · ↑↓/WS pitch · Q/E roll · R reset · Space anim · Z toggle auto-spin
##
## Optional emission brightness (off by default): set BODY_GAIN / TAIL_GAIN > 0 to glow it up.

const MODEL_PATH := "res://assets/3D models/Scorpion.glb"

# ── Optional brightness (0 = off → keep native PBR materials) ──
const BODY_GAIN := 0.0     # whole-body emission boost
const TAIL_GAIN := 0.0     # EXTRA emission ramped toward the tail
const TAIL_SIGN := 1.0     # +1 = tail at the max end of the long axis, -1 = min end
const BRIGHTEN_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color;
uniform float body_gain;
uniform float tail_gain;
uniform vec3 axis;
uniform float p_head;
uniform float p_tail;
varying vec3 v_local;
void vertex() { v_local = VERTEX; }
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	float denom = p_tail - p_head;
	float t = 0.0;
	if (abs(denom) > 0.0001) t = clamp((dot(v_local, axis) - p_head) / denom, 0.0, 1.0);
	EMISSION = c.rgb * (body_gain + tail_gain * t);
}
"""

# ── Rotation ──
const AUTO_SPIN_DPS := 20.0
const YAW_SPEED   := 1.8
const PITCH_SPEED := 1.8
const ROLL_SPEED  := 1.8
const MOUSE_SENS  := 0.01

var _pivot: Node3D
var _cam: Camera3D
var _label: Label
var _anim: AnimationPlayer

var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _dragging: bool = false
var _auto_spin: bool = true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(svc)

	var sv := SubViewport.new()
	sv.own_world_3d = true
	svc.add_child(sv)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-40.0), 0.0)
	key.light_energy = 1.2
	sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	sv.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.34, 0.42)
	e.ambient_light_energy = 1.0
	env.environment = e
	sv.add_child(env)

	_cam = Camera3D.new()
	sv.add_child(_cam)

	_pivot = Node3D.new()
	_pivot.name = "ScorpionPivot"
	sv.add_child(_pivot)

	var packed := load(MODEL_PATH) as PackedScene
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model != null:
		_pivot.add_child(model)
		_frame_camera(model)
		if BODY_GAIN > 0.0 or TAIL_GAIN > 0.0:
			_apply_brightness(model)
		_anim = _find_anim_player(model)
		_play_first_anim()
	else:
		push_warning("scorpion_test: could not load model at " + MODEL_PATH)
		_cam.position = Vector3(0.0, 0.0, 5.0)
		_cam.look_at(Vector3.ZERO, Vector3.UP)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.80, 0.90, 1.00))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 14)
	_label.position = Vector2(12.0, 10.0)
	add_child(_label)
	_apply_rotation()

func _process(delta: float) -> void:
	var changed := false
	if _auto_spin and not _dragging:
		_yaw += deg_to_rad(AUTO_SPIN_DPS) * delta
		changed = true
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		_yaw -= YAW_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		_yaw += YAW_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		_pitch -= PITCH_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		_pitch += PITCH_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_Q):
		_roll -= ROLL_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_E):
		_roll += ROLL_SPEED * delta; changed = true
	if changed:
		_apply_rotation()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kev := event as InputEventKey
		if kev.keycode == KEY_R:
			_yaw = 0.0; _pitch = 0.0; _roll = 0.0
			_apply_rotation()
		elif kev.keycode == KEY_Z:
			_auto_spin = not _auto_spin
			_apply_rotation()
		elif kev.keycode == KEY_SPACE and _anim != null:
			if _anim.is_playing():
				_anim.pause()
			else:
				_play_first_anim()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw   += mm.relative.x * MOUSE_SENS
		_pitch += mm.relative.y * MOUSE_SENS
		_apply_rotation()

func _apply_rotation() -> void:
	if _pivot != null:
		_pivot.transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _roll)), Vector3.ZERO)
	_update_label()

func _update_label() -> void:
	if _label == null:
		return
	var spin := "on" if _auto_spin else "off"
	var anim_hint := "   ·   Space anim" if _anim != null else ""
	_label.text = "SCORPION   ·   auto-spin %s\ndrag orbit · ←→/AD ↑↓/WS Q/E rotate · R reset · Z spin%s" % [spin, anim_hint]

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

func _apply_brightness(model: Node3D) -> void:
	for mi: MeshInstance3D in _all_mesh_instances(model):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var base := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var tex: Texture2D = base.albedo_texture if base != null else null
		var box := mi.get_aabb()
		var s := box.size
		var axis := Vector3(1, 0, 0)
		if s.y >= s.x and s.y >= s.z:
			axis = Vector3(0, 1, 0)
		elif s.z >= s.x and s.z >= s.y:
			axis = Vector3(0, 0, 1)
		var lo := box.position.dot(axis)
		var hi := (box.position + box.size).dot(axis)
		var p_head := lo if TAIL_SIGN >= 0.0 else hi
		var p_tail := hi if TAIL_SIGN >= 0.0 else lo
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = BRIGHTEN_SHADER
		mat.shader = sh
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("body_gain", BODY_GAIN)
		mat.set_shader_parameter("tail_gain", TAIL_GAIN)
		mat.set_shader_parameter("axis", axis)
		mat.set_shader_parameter("p_head", p_head)
		mat.set_shader_parameter("p_tail", p_tail)
		mi.set_surface_override_material(0, mat)

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

func _play_first_anim() -> void:
	if _anim == null:
		return
	var list := _anim.get_animation_list()
	if list.is_empty():
		return
	var anim := _anim.get_animation(list[0])
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim.play(list[0])
