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

const MODEL_PATH  := "res://assets/3D models/Scorpion.glb"
const MUZZLE_CFG  := "res://scorpion_muzzles.cfg"   # authored here, loadable by a future boss script
const MUZZLE_SLOTS    := 20
const MUZZLE_MARKER_R := 0.06

# ── Frame-synced attack ──
const ANIM_FPS := 30.0                        # must match the .glb import fps (Ship_model_1 uses 30)
const ATTACK_CLIP := "attack"                 # preferred clip for F / frame-sync (falls back to a match)
const ATTACK_SLOT := 1                        # which anchor the strike fires from
const ATTACK_FRAMES := { "attack": [18] }     # clip name → frame(s) that spawn the projectile — TUNE THIS
const PROJ_SPEED := 520.0                     # test projectile speed (px/s), fired downward = mock "at player"

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
	key.light_energy = 1.2
	_sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_sv.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.34, 0.42)
	e.ambient_light_energy = 1.0
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
		_add_model_collider(_model)
		_load_muzzles()
		_load_muzzle_anchors()
		_refresh_muzzle_markers()
		_anim = _find_anim_player(_model)
		_clips = _anim.get_animation_list() if _anim != null else PackedStringArray()
		_resolve_attack_clip()
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
				_status = "edit ON — click model to place slot %d" % _active_slot if _edit else ""
				_refresh_muzzle_markers()
			KEY_BRACKETLEFT:
				if _edit: _cycle_slot(-1)
			KEY_BRACKETRIGHT:
				if _edit: _cycle_slot(1)
			KEY_X:
				if _edit: _clear_slot()
			_:
				if k.keycode >= KEY_1 and k.keycode <= KEY_9:
					var idx := k.keycode - KEY_1
					if idx < _clips.size(): _play_clip(_clips[idx])
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
		lines.append("[EDIT] slot %d/%d — click model to place · [ ] cycle · X clear · %s" % [_active_slot, MUZZLE_SLOTS, _status])
	else:
		lines.append("1-9 play · F attack · G fire now · P edit anchors · Z spin · R reset · drag rotate")
	_label.text = "\n".join(lines)
