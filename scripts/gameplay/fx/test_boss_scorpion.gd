extends Control
## Test bench for the animated scorpion boss.
##
## Renders Scorpion.glb in a 3D SubViewport with all its baked animations, lets you place
## attack-anchor points on the model (same system as the ship's muzzle points), and fires a
## scripted 2D projectile synced to a specific FRAME of an attack clip — so you can line the
## shot up with the exact moment the stinger strikes.
##
## Controls:
##   drag / ←→↑↓ / Q E  rotate   ·   R reset   ·   Z auto-spin   ·   Space pause/resume clip
##   1..9  play clip N        ·   F  play the attack clip   ·   G  fire a test projectile now
##   P  toggle anchor-edit    ·   [ / ]  active anchor slot  ·   click  place anchor (auto-saves)
##   X  clear the active slot (in edit mode)
##
## Frame timing: set ATTACK_FRAMES below (clip name → strike frame). Watch the "frame" readout
## in the label while a clip plays to find the right number, then plug it in.

const MODEL_PATH  := "res://assets/3D models/Boss_Scorpion_1.glb"
const MUZZLE_CFG  := "res://scorpion_muzzles.cfg"   # authored here, loadable by a future boss script
const MUZZLE_SLOTS    := 20
const MUZZLE_MARKER_R := 0.06

# ── Frame-synced attack ──
const ANIM_FPS := 30.0                        # must match the .glb import fps (Ship_model_1 uses 30)
const ATTACK_CLIP := "Tail_open"              # the tail-strike clip (F plays it; frame-sync targets it)
const ATTACK_SLOT := 1                        # which anchor the strike fires from (place it on the stinger)
const ATTACK_FRAMES := { "Tail_open": [20] }  # clip name → strike frame(s), 0..30 for Tail_open — TUNE by eye
const PROJ_SPEED := 520.0                     # test projectile speed (px/s), fired downward = mock "at player"

# ── Look / brightness ──
# The HSV-brighten shader you added in Blender does NOT export through glTF, and the model's baked
# metallic map makes it read dark against a dark scene. These knobs re-create the bright look in Godot.
const KEY_LIGHT      := 2.2                    # main light energy
const FILL_LIGHT     := 1.1                    # opposite fill so the far side isn't black
const AMBIENT_COLOR  := Color(0.85, 0.88, 0.98)  # bright, slightly cool — what the metal reflects
const AMBIENT_ENERGY := 2.0
const METALLIC_MULT  := 0.55                   # <1 tames the dark "mirror" look of the metallic bake
# HSV recolour of the albedo — same idea as the Blender Hue/Sat/Value node, but this one applies in-game.
# Changes the ACTUAL colours (no white wash), and keeps the normal map / roughness / metal intact.
const HUE_SHIFT   := 0.0     # 0 = keep hues · 0.5 = opposite colour · small values = tint the whole model
const SATURATION  := 0.85    # <1 fades toward grey/white · 1 = unchanged · >1 = more vivid
const VALUE       := 1.35    # >1 brightens the real colours · 1 = unchanged · <1 = darker
# Selective per-colour tweaks — detected from each pixel's ORIGINAL colour:
const WHITEN_GRAYS := 0.45          # push grey/silver patches toward white (0 = off, 1 = full white)
const GRAY_SAT_MAX := 0.22          # a pixel counts as "grey" when its saturation is below this
const DARKEN_REDS  := 0.70          # push red patches toward RED_TARGET (0 = off, 1 = full)
const RED_TARGET   := Color("880000")   # target dark red for the red patches
const RED_HUE_BAND := 0.07          # how close to pure red (in hue) a pixel must be to count as "red"
const RED_SAT_MIN  := 0.35          # minimum saturation for a pixel to count as "red"

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
	// detect the patches from the ORIGINAL colour (before any global tweak)
	float gray_mask = (1.0 - smoothstep(gray_sat_max * 0.5, gray_sat_max, h.y)) * smoothstep(0.15, 0.5, h.z);
	float hue_dist = min(h.x, 1.0 - h.x);
	float red_mask = (1.0 - smoothstep(0.0, red_hue_band, hue_dist)) * smoothstep(red_sat_min * 0.5, red_sat_min, h.y);
	// global HSV
	h.x = fract(h.x + hue_shift);
	h.y = clamp(h.y * sat_mul, 0.0, 1.0);
	h.z = h.z * val_mul;
	vec3 col = clamp(hsv2rgb(h), 0.0, 1.0);
	// selective: grey/silver -> white, red -> dark red
	col = mix(col, vec3(1.0), clamp(gray_mask * white_amt, 0.0, 1.0));
	col = mix(col, red_target, clamp(red_mask * red_amt, 0.0, 1.0));
	ALBEDO = col;   // no ALPHA write — stays opaque
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

# ── Rotation tuning ──
const AUTO_SPIN_DPS := 20.0
const YAW_SPEED   := 1.8
const PITCH_SPEED := 1.8
const ROLL_SPEED  := 1.8
const MOUSE_SENS  := 0.01

# Overlay that draws the test projectiles on top of the 3D render.
class ProjLayer extends Node2D:
	var projs: Array = []   # each: { pos: Vector2, vel: Vector2, life: float }
	func _draw() -> void:
		for p: Dictionary in projs:
			var pos: Vector2 = p["pos"]
			var vel: Vector2 = p["vel"]
			var tail := pos - vel.normalized() * 16.0
			draw_line(tail, pos, Color(1.0, 0.55, 0.15, 0.65), 3.0)
			draw_circle(pos, 5.0, Color(1.0, 0.40, 0.12))
			draw_circle(pos, 2.0, Color(1.0, 0.90, 0.70))

var _svc: SubViewportContainer
var _sv: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _label: Label
var _proj_layer: ProjLayer

var _clips: PackedStringArray = PackedStringArray()
var _attack_clip: String = ""

var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _dragging: bool = false
var _auto_spin: bool = true

# ── Anchor editor state ──
var _edit: bool = false
var _active_slot: int = 1
var _muzzle_pts: Dictionary = {}       # int slot -> Vector3 (model-local)
var _muzzle_anchors: Dictionary = {}   # int slot -> Node3D on model (for projection; rides animation)
var _muzzle_markers: Dictionary = {}   # int slot -> Node3D holder (sphere + number label)
var _status: String = ""

# ── Frame-sync edge detection ──
var _last_frame: int = -1
var _last_clip: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_svc = SubViewportContainer.new()
	_svc.stretch = true   # SubViewport size follows this container → screen coords map 1:1 (no scaling math)
	_svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_svc)

	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_4X
	_svc.add_child(_sv)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-40.0), 0.0)
	key.light_energy = KEY_LIGHT
	_sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = FILL_LIGHT
	_sv.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT_COLOR
	e.ambient_light_energy = AMBIENT_ENERGY
	env.environment = e
	_sv.add_child(env)

	_cam = Camera3D.new()
	_sv.add_child(_cam)

	_pivot = Node3D.new()
	_pivot.name = "ScorpionPivot"
	_sv.add_child(_pivot)

	var packed := load(MODEL_PATH) as PackedScene
	_model = (packed.instantiate() as Node3D) if packed != null else null
	if _model != null:
		_pivot.add_child(_model)
		_frame_camera(_model)
		_style_materials(_model)
		_add_model_collider(_model)
		_load_muzzles()
		_load_muzzle_anchors()
		_refresh_muzzle_markers()
		_anim = _find_anim_player(_model)
		_clips = _anim.get_animation_list() if _anim != null else PackedStringArray()
		_resolve_attack_clip()
		var _dbg := ""
		for _c: String in _clips:
			var _a := _anim.get_animation(_c)
			if _a != null:
				_dbg += "  %s=%df" % [_c, int(_a.length * ANIM_FPS)]
		print("[test_boss_scorpion] clip frames:%s   attack_clip: %s" % [_dbg, _attack_clip])
		if not _clips.is_empty():
			_play_clip(_clips[0])
	else:
		push_warning("test_boss_scorpion: could not load model at " + MODEL_PATH)
		_cam.position = Vector3(0.0, 0.0, 5.0)
		_cam.look_at(Vector3.ZERO, Vector3.UP)

	_proj_layer = ProjLayer.new()
	_proj_layer.z_index = 100
	add_child(_proj_layer)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.80, 0.90, 1.00))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 13)
	_label.position = Vector2(12.0, 10.0)
	add_child(_label)

	_apply_rotation()


func _process(delta: float) -> void:
	# ── rotation ──
	var changed := false
	if _auto_spin and not _dragging and not _edit:
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

	# ── frame-synced attack: fire when the play-head crosses a strike frame ──
	if _anim != null and _anim.is_playing():
		var clip := _anim.current_animation
		var frame := int(_anim.current_animation_position * ANIM_FPS)
		var wrapped: bool = (clip != _last_clip) or (frame < _last_frame)   # clip change or loop wrap
		var prev := -1 if wrapped else _last_frame
		if ATTACK_FRAMES.has(clip):
			for f: int in ATTACK_FRAMES[clip]:
				if prev < f and frame >= f:
					_on_strike()
		_last_frame = frame
		_last_clip = clip

	# ── advance test projectiles ──
	if _proj_layer != null and not _proj_layer.projs.is_empty():
		var alive: Array = []
		for p: Dictionary in _proj_layer.projs:
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
			p["life"] = (p["life"] as float) - delta
			if (p["life"] as float) > 0.0 and (p["pos"] as Vector2).y < size.y + 60.0:
				alive.append(p)
		_proj_layer.projs = alive
		_proj_layer.queue_redraw()

	_update_label()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_R:
				_yaw = 0.0; _pitch = 0.0; _roll = 0.0; _apply_rotation()
			KEY_Z:
				_auto_spin = not _auto_spin
			KEY_SPACE:
				if _anim != null:
					if _anim.is_playing(): _anim.pause()
					else: _anim.play()
			KEY_F:
				if _attack_clip != "": _play_clip(_attack_clip)
			KEY_G:
				_on_strike()   # manual fire, ignores frame timing (test the anchor/projectile alone)
			KEY_P:
				_edit = not _edit
				if _edit:
					if _anim != null: _anim.pause()   # freeze the model so anchors land precisely
					_status = "edit ON — 1-9 pick slot, click to place"
				else:
					if _anim != null: _anim.play()    # resume the animation on exit
					_status = ""
				_refresh_muzzle_markers()
			KEY_BRACKETLEFT:
				if _edit: _cycle_slot(-1)
			KEY_BRACKETRIGHT:
				if _edit: _cycle_slot(1)
			KEY_X:
				if _edit: _clear_slot()
			_:
				if k.keycode >= KEY_1 and k.keycode <= KEY_9:
					var n := k.keycode - KEY_1 + 1
					if _edit:
						_active_slot = clampi(n, 1, MUZZLE_SLOTS)   # 1-9 pick the muzzle slot while editing
						_refresh_muzzle_markers()
					elif n - 1 < _clips.size():
						_play_clip(_clips[n - 1])
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _edit:
				if mb.pressed: _place_muzzle_at(mb.position)
			else:
				_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging and not _edit:
		var mm := event as InputEventMouseMotion
		_yaw   += mm.relative.x * MOUSE_SENS
		_pitch += mm.relative.y * MOUSE_SENS
		_apply_rotation()


# ── Animation ────────────────────────────────────────────────────────────────
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c: Node in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

## Pick the clip that F and the frame-sync target. Prefer ATTACK_CLIP, else a name containing
## attack/sting/tail, else the first clip.
func _resolve_attack_clip() -> void:
	_attack_clip = ""
	if _clips.is_empty():
		return
	if _clips.has(ATTACK_CLIP):
		_attack_clip = ATTACK_CLIP
		return
	for c: String in _clips:
		var lc := c.to_lower()
		if lc.contains("attack") or lc.contains("sting") or lc.contains("tail"):
			_attack_clip = c
			return
	_attack_clip = _clips[0]

func _play_clip(clip_name: String) -> void:
	if _anim == null or clip_name == "":
		return
	var anim := _anim.get_animation(clip_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR   # loop so you can watch the strike repeat while tuning
	_anim.play(clip_name)
	_last_clip = ""    # re-arm frame-sync for the new clip
	_last_frame = -1


# ── Attack ───────────────────────────────────────────────────────────────────
## Spawn a test projectile from the stinger anchor, flying downward (mock "fire at the player").
func _on_strike() -> void:
	if _proj_layer == null:
		return
	var origin := _muzzle_screen(ATTACK_SLOT)
	_proj_layer.projs.append({
		"pos": origin,
		"vel": Vector2(0.0, PROJ_SPEED),
		"life": 2.0,
	})

## Project anchor `slot` (a 3D point on the model) to a 2D screen position. Because the container
## stretches the viewport to fill the screen, unproject_position already returns screen coords.
func _muzzle_screen(slot: int) -> Vector2:
	var a: Node3D = _muzzle_anchors.get(slot, null)
	if a == null or _cam == null:
		return size * 0.5
	return _cam.unproject_position(a.global_position)


# ── Anchor editor (ported from ship_rotation_test.gd) ─────────────────────────
func _cycle_slot(step: int) -> void:
	_active_slot = (_active_slot - 1 + step + MUZZLE_SLOTS) % MUZZLE_SLOTS + 1
	_refresh_muzzle_markers()

## Raycast the click into the 3D scene and store the hit as a MODEL-LOCAL point in the active slot.
func _place_muzzle_at(screen_pos: Vector2) -> void:
	if _model == null or _cam == null or _sv == null:
		return
	var world := _sv.find_world_3d()
	if world == null:
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var space := world.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_status = "missed — click on the model"
		return
	_muzzle_pts[_active_slot] = _model.to_local(hit["position"])   # rotation/anim-independent
	_save_muzzles()
	_load_muzzle_anchors()
	_refresh_muzzle_markers()

func _clear_slot() -> void:
	if _muzzle_pts.has(_active_slot):
		_muzzle_pts.erase(_active_slot)
		_save_muzzles()
		_load_muzzle_anchors()
		_refresh_muzzle_markers()

## Node3D anchors used for projection — children of the model so they ride its rotation + animation.
func _load_muzzle_anchors() -> void:
	for a: Node3D in _muzzle_anchors.values():
		if is_instance_valid(a):
			a.queue_free()
	_muzzle_anchors.clear()
	if _model == null:
		return
	for slot: int in _muzzle_pts.keys():
		var a := Node3D.new()
		a.position = _muzzle_pts[slot]
		_model.add_child(a)
		_muzzle_anchors[slot] = a

## Rebuild the on-model marker spheres + number labels (active slot green, others orange).
func _refresh_muzzle_markers() -> void:
	for id: int in _muzzle_markers.keys():
		var n: Node = _muzzle_markers[id]
		if is_instance_valid(n):
			n.queue_free()
	_muzzle_markers.clear()
	if _model == null or not _edit:
		return   # only show markers while editing, so they don't cover the model in play
	for id: int in _muzzle_pts.keys():
		var holder := Node3D.new()
		holder.position = _muzzle_pts[id]
		_model.add_child(holder)

		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = MUZZLE_MARKER_R
		sphere.height = MUZZLE_MARKER_R * 2.0
		dot.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 1.0, 0.35) if id == _active_slot else Color(1.0, 0.45, 0.1)
		mat.no_depth_test = true
		dot.material_override = mat
		holder.add_child(dot)

		var lbl := Label3D.new()
		lbl.text = str(id)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.0016
		lbl.position = Vector3(0.0, MUZZLE_MARKER_R * 2.2, 0.0)
		holder.add_child(lbl)

		_muzzle_markers[id] = holder

func _save_muzzles() -> void:
	var cfg := ConfigFile.new()
	for id: int in _muzzle_pts.keys():
		cfg.set_value("muzzles", str(id), _muzzle_pts[id])
	var err := cfg.save(MUZZLE_CFG)
	if err == OK:
		_status = "saved ✓ (%d pts)" % _muzzle_pts.size()
	else:
		_status = "SAVE FAILED (%d)" % err
		push_warning("test_boss_scorpion: could not save muzzles (%d) to %s" % [err, MUZZLE_CFG])

func _load_muzzles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(MUZZLE_CFG) != OK:
		return
	_muzzle_pts.clear()
	if not cfg.has_section("muzzles"):
		return
	for key: String in cfg.get_section_keys("muzzles"):
		_muzzle_pts[int(key)] = cfg.get_value("muzzles", key)

## Recolour the model to match the intended look (the Blender HSV shader can't export via glTF). Overrides
## each surface with a shader that HSV-adjusts the albedo (hue/sat/value) while passing the metallic,
## roughness and normal maps straight through — so it changes the actual colours, not a white overlay.
func _style_materials(root: Node) -> void:
	if HUE_SHIFT == 0.0 and SATURATION == 1.0 and VALUE == 1.0 and METALLIC_MULT == 1.0:
		return
	for mi: MeshInstance3D in _all_mesh_instances(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
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
			mi.set_surface_override_material(s, mat)

## Give every mesh a trimesh collider (child of the mesh, so it rides the model) for click raycasts.
func _add_model_collider(root: Node) -> void:
	for mi: MeshInstance3D in _all_mesh_instances(root):
		if mi.mesh == null:
			continue
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = mi.mesh.create_trimesh_shape()
		body.add_child(col)
		mi.add_child(body)


# ── Camera / geometry helpers (from scorpion_test.gd) ─────────────────────────
func _apply_rotation() -> void:
	if _pivot != null:
		_pivot.transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _roll)), Vector3.ZERO)

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


# ── HUD ───────────────────────────────────────────────────────────────────────
func _update_label() -> void:
	if _label == null:
		return
	if _model == null:
		_label.text = "SCORPION model NOT FOUND at %s\nExport your .glb there from Blender, then reopen." % MODEL_PATH
		return
	var lines: Array[String] = []
	# clip list
	if _clips.is_empty():
		lines.append("(no animations found in the .glb)")
	else:
		var names: Array[String] = []
		for i in _clips.size():
			names.append("%d:%s" % [i + 1, _clips[i]])
		lines.append("clips  " + "  ".join(names))
	# current clip + frame readout (use this to find your strike frame)
	if _anim != null and _anim.current_animation != "":
		var fr := int(_anim.current_animation_position * ANIM_FPS)
		lines.append("playing: %s   frame: %d" % [_anim.current_animation, fr])
	lines.append("attack clip: %s   ·   strike frames: %s" % [_attack_clip, str(ATTACK_FRAMES)])
	# edit HUD
	if _edit:
		lines.append("[EDIT] slot %d/%d — 1-9 pick slot · click model to place · X clear · %s" % [_active_slot, MUZZLE_SLOTS, _status])
	else:
		lines.append("1-9 play · F attack · G fire now · P edit anchors · Z spin · R reset · drag rotate")
	_label.text = "\n".join(lines)
