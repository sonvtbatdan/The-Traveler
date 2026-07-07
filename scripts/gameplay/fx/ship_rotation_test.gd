extends Control
## Interactive 3D rotation test for the player ship model.
##
## MOUSE-TRACK mode (default): the ship's nose points toward the mouse, and it rolls about its
## nose–tail axis so you see the TOP at vertical headings and the FLANK at horizontal ones:
##     12 o'clock → top-down, nose up      3 o'clock → right side (nose right)
##      6 o'clock → top-down, nose down     9 o'clock → left  side (nose left)
##   Roll = 90° × sin(clock angle). The motion stays in the plane perpendicular to the nose,
##   so the belly and the front/back are NEVER shown — that falls out of the math.
##
## FREE-LOOK mode (Tab): keyboard/​drag manual rotation for inspecting the model from any angle.
##   ←→/AD yaw · ↑↓/WS pitch · Q/E roll · drag orbit
## Always:  R reset · Space play/pause baked animation · Tab switch mode
##
## MUZZLE-EDIT mode (P): place named muzzle anchor points 1–5 on the model.
##   Enter with P (freezes into keyboard free-look so the ship holds still).
##   1–5 = pick the active slot   ·   Left-click on the ship = place/move that slot's point
##   X/Del = clear the active slot   ·   rotate with the free-look keys to reach other faces.
##   Points are stored in MODEL-LOCAL space (so they ride the ship's rotation) and auto-saved to
##   MUZZLE_CFG. The arena loads the same file to anchor each weapon's muzzle to a point.
##
## Model orientation (from AABB + the user's front/back/side reference shots):
##   up = +Y · nose–tail = X (nose = −X) · flanks = ±Z.
## Sign knobs if a view comes out wrong:
##   INVERT_SIDES  — roll direction; flip if the 3/9 side views are upside-down (dorsal down).
##   INVERT_NOSE   — flip nose/tail (if the tail points at the mouse instead of the nose).

const MODEL_PATH := "res://assets/defense/Ship_model_1.glb"

# ── Mouse-track tuning ──
const ROLL_MAX_DEG  := 90.0   # roll at the 3 / 9 o'clock extremes (full side view)
const INVERT_SIDES  := -1.0   # roll direction: sets dorsal UP (right-side-up) vs down in the side views
							  #   (and, coupled, which flank faces the camera). Flip if the sides go upside-down.
const INVERT_NOSE   := 1.0    # +1 or -1: which end points at the mouse
const TRACK_SMOOTH  := 12.0   # how fast orientation eases toward the mouse target

# ── Free-look tuning ──
const YAW_SPEED   := 1.8      # rad/s while a key is held
const PITCH_SPEED := 1.8
const ROLL_SPEED  := 1.8
const MOUSE_SENS  := 0.01     # rad per pixel dragged

# ── Muzzle editor ──
const MUZZLE_CFG      := "res://ship_muzzles.cfg"   # saved muzzle points (shared with the arena)
const MUZZLE_SLOTS    := 20                         # points 1..20
const MUZZLE_MARKER_R := 0.06                       # marker sphere radius (model spans ~2 units)

var _pivot: Node3D
var _cam: Camera3D
var _sv: SubViewport
var _model: Node3D
var _label: Label
var _anim: AnimationPlayer

var _mouse_track: bool = true
var _cur_q: Quaternion = Quaternion.IDENTITY   # smoothed orientation in mouse-track mode

# free-look state
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _dragging: bool = false

# muzzle editor state
var _edit_muzzles: bool = false
var _active_slot: int = 1
var _muzzle_pts: Dictionary = {}       # int slot -> Vector3 (model-local)
var _muzzle_markers: Dictionary = {}   # int slot -> Node3D holder (marker sphere + label)
var _place_pending: bool = false       # click queued; raycast runs in _physics_process
var _place_pos: Vector2 = Vector2.ZERO
var _status: String = ""               # last-action note shown in the edit HUD (e.g. "saved ✓")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(svc)

	var sv := SubViewport.new()
	sv.own_world_3d = true
	svc.add_child(sv)
	_sv = sv

	# Key light + soft fill so the far side isn't pure black as it turns away.
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-40.0), 0.0)
	light.light_energy = 1.2
	sv.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.38, 0.45)
	e.ambient_light_energy = 1.0
	env.environment = e
	sv.add_child(env)

	_cam = Camera3D.new()
	sv.add_child(_cam)

	_pivot = Node3D.new()
	_pivot.name = "ShipPivot"
	sv.add_child(_pivot)

	# Load the real ship model and center it on the pivot so it spins about its middle.
	var packed := load(MODEL_PATH) as PackedScene
	var ship: Node3D = null
	if packed != null:
		ship = packed.instantiate() as Node3D
	if ship != null:
		_pivot.add_child(ship)
		_model = ship
		_anim = _find_anim_player(ship)
		_frame_camera(ship)
		_add_model_collider(ship)   # so muzzle-edit clicks can raycast onto the hull
		_load_muzzles()
		_refresh_muzzle_markers()
	else:
		push_warning("ship_rotation_test: could not load model at " + MODEL_PATH)
		_cam.position = Vector3(0.0, 0.0, 5.0)
		_cam.look_at(Vector3.ZERO, Vector3.UP)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.80, 0.90, 1.00))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 14)
	_label.position = Vector2(12.0, 10.0)
	add_child(_label)

	_cur_q = _base_topdown().get_rotation_quaternion()
	_apply_rotation()

func _process(delta: float) -> void:
	if _mouse_track:
		var target := _mouse_orientation().get_rotation_quaternion()
		_cur_q = _cur_q.slerp(target, clampf(TRACK_SMOOTH * delta, 0.0, 1.0))
		_apply_rotation()
		return

	# Free-look: accumulate held-key rotation. In muzzle-edit the arrows cycle slots instead of rotating,
	# so rotation there is WASD + Q/E only.
	var arrows := not _edit_muzzles
	var changed := false
	if Input.is_key_pressed(KEY_A) or (arrows and Input.is_key_pressed(KEY_LEFT)):
		_yaw -= YAW_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_D) or (arrows and Input.is_key_pressed(KEY_RIGHT)):
		_yaw += YAW_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_W) or (arrows and Input.is_key_pressed(KEY_UP)):
		_pitch -= PITCH_SPEED * delta; changed = true
	if Input.is_key_pressed(KEY_S) or (arrows and Input.is_key_pressed(KEY_DOWN)):
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
		if kev.keycode == KEY_P:
			_toggle_muzzle_edit()
		elif _edit_muzzles and kev.keycode >= KEY_1 and kev.keycode <= KEY_9 and (kev.keycode - KEY_0) <= MUZZLE_SLOTS:
			_active_slot = kev.keycode - KEY_0        # quick-jump to slots 1-9
			_refresh_muzzle_markers()
			_update_label()
		elif _edit_muzzles and (kev.keycode == KEY_LEFT or kev.keycode == KEY_DOWN):
			_cycle_slot(-1)
		elif _edit_muzzles and (kev.keycode == KEY_RIGHT or kev.keycode == KEY_UP):
			_cycle_slot(1)
		elif _edit_muzzles and (kev.keycode == KEY_ENTER or kev.keycode == KEY_KP_ENTER):
			_save_muzzles()
			_update_label()
		elif _edit_muzzles and (kev.keycode == KEY_X or kev.keycode == KEY_DELETE):
			_muzzle_pts.erase(_active_slot)
			_refresh_muzzle_markers()
			_save_muzzles()
			_update_label()
		elif kev.keycode == KEY_R:
			_yaw = 0.0; _pitch = 0.0; _roll = 0.0
			_cur_q = _base_topdown().get_rotation_quaternion()
			_apply_rotation()
		elif kev.keycode == KEY_TAB and not _edit_muzzles:
			_mouse_track = not _mouse_track
			if _mouse_track:
				_cur_q = _mouse_orientation().get_rotation_quaternion()   # snap, avoid a wild slerp
			_apply_rotation()
		elif kev.keycode == KEY_SPACE and _anim != null:
			if _anim.is_playing():
				_anim.pause()
			else:
				_play_first_anim()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _edit_muzzles:
				if mb.pressed:
					_place_pos = mb.position         # raycast deferred to _physics_process
					_place_pending = true
			else:
				_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging and not _mouse_track and not _edit_muzzles:
		var mm := event as InputEventMouseMotion
		_yaw   += mm.relative.x * MOUSE_SENS
		_pitch += mm.relative.y * MOUSE_SENS
		_apply_rotation()

func _physics_process(_delta: float) -> void:
	if _place_pending:
		_place_pending = false
		_place_muzzle_at(_place_pos)

func _apply_rotation() -> void:
	if _pivot != null:
		if _mouse_track:
			_pivot.transform = Transform3D(Basis(_cur_q), Vector3.ZERO)
		else:
			_pivot.transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, _roll)), Vector3.ZERO)
	_update_label()

## Rest orientation: top (+Y) toward the camera, nose (−X) pointing up-screen. This is the
## "12 o'clock / dead-center" pose. Built from unambiguous axis rotations to avoid Basis-column gotchas.
func _base_topdown() -> Basis:
	return Basis(Vector3(0, 0, 1), deg_to_rad(-90.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(90.0))

## Full mouse-track orientation:
##   1. base (top-down, nose up)
##   2. roll about the nose axis (world +Y here) by 90°·sin(clock angle) → reveals a flank
##   3. heading spin about the view axis (world +Z) so the nose points at the mouse
func _mouse_orientation() -> Basis:
	var rect := get_viewport().get_visible_rect()
	var d := get_viewport().get_mouse_position() - rect.size * 0.5
	var len := d.length()
	if len < 1.0:
		return _base_topdown()   # dead-center → clean top-down
	var dir := d / len
	var alpha := atan2(dir.x, -dir.y)   # clock angle: 0 at 12, +90° at 3 (clockwise, screen y-down)
	var roll := deg_to_rad(ROLL_MAX_DEG) * sin(alpha) * INVERT_SIDES
	var heading := Basis(Vector3(0, 0, 1), -alpha * INVERT_NOSE)
	var roll_b := Basis(Vector3(0, 1, 0), roll)
	return heading * roll_b * _base_topdown()

func _update_label() -> void:
	if _label == null:
		return
	if _edit_muzzles:
		var filled_list: Array = []
		for i in range(1, MUZZLE_SLOTS + 1):
			if _muzzle_pts.has(i):
				filled_list.append(str(i))
		var filled := ", ".join(filled_list) if filled_list.size() > 0 else "none"
		var here := "(placed)" if _muzzle_pts.has(_active_slot) else "(empty)"
		_label.text = "MUZZLE-EDIT   ·   slot %d/%d %s   %s\nfilled: %s\nclick=place · ←→ cycle slot · 1-9 jump · X clear · Enter save · WASD/QE rotate · P exit" % [
			_active_slot, MUZZLE_SLOTS, here, _status, filled,
		]
		return
	if _mouse_track:
		var d := get_viewport().get_mouse_position() - get_viewport().get_visible_rect().size * 0.5
		var roll_deg := 0.0
		if d.length() >= 1.0:
			roll_deg = ROLL_MAX_DEG * (d.x / d.length()) * INVERT_SIDES
		var face := "top-down"
		if roll_deg > 5.0:
			face = "right side"
		elif roll_deg < -5.0:
			face = "left side"
		var anim_hint := "   ·   Space anim" if _anim != null else ""
		_label.text = "MOUSE-TRACK   ·   %s   (roll %+d°)\nnose follows mouse: 12=top 3=right 6=top 9=left   ·   Tab free-look   ·   R reset%s" % [
			face, int(round(roll_deg)), anim_hint,
		]
	else:
		var anim_hint2 := "   ·   Space anim" if _anim != null else ""
		_label.text = "FREE-LOOK   ·   Yaw %d°  Pitch %d°  Roll %d°\n←→/AD ↑↓/WS Q/E · drag orbit · Tab mouse-track · R reset%s" % [
			int(round(rad_to_deg(_yaw))),
			int(round(rad_to_deg(_pitch))),
			int(round(rad_to_deg(_roll))),
			anim_hint2,
		]

## Position the camera to fit the model, and recenter the model so it rotates about its own middle.
func _frame_camera(ship: Node3D) -> void:
	var aabb := _combined_aabb(ship)
	var center := aabb.position + aabb.size * 0.5
	ship.position -= center   # model center now sits at the pivot origin
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	_cam.position = Vector3(0.0, 0.0, dist)   # straight-on → clean top-down / side profiles
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far  = dist + radius * 2.0

## Combined AABB of every MeshInstance3D under `root`, expressed in the pivot's space.
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
	return acc if has else AABB()

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
	if list.size() > 0:
		_anim.play(list[0])

# ── Muzzle editor ───────────────────────────────────────────────────────────────

func _toggle_muzzle_edit() -> void:
	_edit_muzzles = not _edit_muzzles
	if _edit_muzzles:
		# Freeze into keyboard free-look so the ship holds still while you click.
		_mouse_track = false
		_yaw = 0.0; _pitch = 0.0; _roll = 0.0
		_status = ""
	else:
		_mouse_track = true
		_cur_q = _mouse_orientation().get_rotation_quaternion()
	_refresh_muzzle_markers()
	_apply_rotation()

## Step the active slot by ±1, wrapping around 1..MUZZLE_SLOTS.
func _cycle_slot(step: int) -> void:
	_active_slot = (_active_slot - 1 + step + MUZZLE_SLOTS) % MUZZLE_SLOTS + 1
	_refresh_muzzle_markers()
	_update_label()

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
		return
	_muzzle_pts[_active_slot] = _model.to_local(hit.position)   # rotation-independent
	_refresh_muzzle_markers()
	_save_muzzles()
	_update_label()

## Rebuild the on-model marker spheres + number labels (active slot highlighted green).
func _refresh_muzzle_markers() -> void:
	for id: int in _muzzle_markers.keys():
		var n: Node = _muzzle_markers[id]
		if is_instance_valid(n):
			n.queue_free()
	_muzzle_markers.clear()
	if _model == null:
		return
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
		push_warning("ship_rotation_test: could not save muzzles (%d) to %s" % [err, MUZZLE_CFG])

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
