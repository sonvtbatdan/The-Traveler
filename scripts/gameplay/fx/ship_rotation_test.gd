extends Control
## Interactive 3D rotation test for the player ship model.
##
## Run this scene (F6) to spin the ship in a SubViewport and inspect how every side
## (top / belly / far side) reveals as it pitches, yaws and rolls — the thing a flat
## top-down sprite can never do. Because it renders the real .glb, the reveal is true
## perspective, not a fake.
##
## Controls:  ←→ / A D = yaw   ·   ↑↓ / W S = pitch   ·   Q E = roll
##            left-drag = orbit   ·   R = reset   ·   Space = play/pause baked animation
##
## Later follow-up: the same SubViewport render can be composited onto the arena
## SpaceScreen to replace the live 2D ship sprite.

const MODEL_PATH := "res://assets/defense/Ship_model_1.glb"

const YAW_SPEED   := 1.8    # rad/s while a key is held
const PITCH_SPEED := 1.8
const ROLL_SPEED  := 1.8
const MOUSE_SENS  := 0.01   # rad per pixel dragged

var _pivot: Node3D
var _cam: Camera3D
var _label: Label
var _anim: AnimationPlayer

var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _dragging: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(svc)

	var sv := SubViewport.new()
	sv.own_world_3d = true
	svc.add_child(sv)

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
		_anim = _find_anim_player(ship)
		_frame_camera(ship)
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
	_update_label()

func _process(delta: float) -> void:
	var changed := false
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
		_pivot.rotation = Vector3(_pitch, _yaw, _roll)
	_update_label()

func _update_label() -> void:
	if _label == null:
		return
	var anim_hint := "   ·   Space play/pause anim" if _anim != null else ""
	_label.text = "Yaw %d°   Pitch %d°   Roll %d°\n←→/AD yaw   ↑↓/WS pitch   Q/E roll   ·   drag orbit   ·   R reset%s" % [
		int(round(rad_to_deg(_yaw))),
		int(round(rad_to_deg(_pitch))),
		int(round(rad_to_deg(_roll))),
		anim_hint,
	]

## Position the camera to fit the model, and recenter the model so it rotates about its own middle.
func _frame_camera(ship: Node3D) -> void:
	var aabb := _combined_aabb(ship)
	var center := aabb.position + aabb.size * 0.5
	ship.position -= center   # model center now sits at the pivot origin
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	_cam.position = Vector3(0.0, radius * 0.25, dist)
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
