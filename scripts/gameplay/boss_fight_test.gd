extends Node2D
## Boss-fight sandbox (scenes/boss_fight_test.tscn).
##  • WASD / arrows move your ship (the real 3D model); it faces the mouse. A Gatling auto-fires at the boss.
##  • Number keys pick which boss to spawn (HUD list). R restarts the current boss.
##  • A world grid gives depth/perspective reference.
## Mirrors player_2_test's player + single-weapon setup, but renders the ship in 3D like the real arena.

const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
const BossScorpionScript := preload("res://scripts/gameplay/boss_scorpion.gd")
const MOVE_SPEED := 260.0

# 3D ship render (ported from arena.gd)
const SHIP_MODEL        := "res://assets/defense/Ship_model_1.glb"
const VP_SIZE           := 256
const SHIP_DISPLAY_GAIN := 3.5
const SHIP_ISO_DEG      := 30.0
const SHIP_LEAN_MAX_DEG := 18.0
const SHIP_YAW_SIGN     := 1.0
const SHIP_INVERT_SIDES := -1.0
const PLAYER_SIZE_PX    := 48.0
const SHIP_Z            := 100

# Registry of selectable bosses — add more scripts here as you build them.
const BOSSES := [
	{ "name": "Scorpion", "script": BossScorpionScript },
]

var _player: Node2D = null
var _weapons: Node = null
var _hud: Label = null
var _boss: Node2D = null
var _boss_idx: int = 0

var _ship_vp: SubViewport
var _ship_cam: Camera3D
var _ship_pivot: Node3D
var _ship_spr: Sprite2D

var _panel_layer: CanvasLayer
var _panel: PanelContainer
var _move_enabled: Dictionary = {}   # id -> bool, persisted across boss respawns


func _ready() -> void:
	position = Vector2.ZERO
	process_mode = Node.PROCESS_MODE_ALWAYS   # root keeps handling input while paused (to close the panel)
	var grid := GridBg.new()
	grid.z_index = -100
	add_child(grid)
	_build_player()
	_build_hud()
	_build_move_panel()
	_weapons = ArenaWeaponsScript.new()
	(_weapons as Node2D).position = Vector2.ZERO
	_weapons.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_weapons)
	_weapons.call_deferred("acquire_weapon", "gatling_gun")
	_spawn_boss(0)


func _build_player() -> void:
	_player = Node2D.new()
	_player.add_to_group("player")
	_player.global_position = Vector2.ZERO
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	var cam := Camera2D.new()
	cam.enabled = true   # Camera2D ignores parent rotation by default, so aiming won't spin the view
	_player.add_child(cam)
	add_child(_player)
	cam.make_current()
	_build_ship_viewport()
	var spr := Sprite2D.new()
	spr.texture = _ship_vp.get_texture()
	spr.z_index = SHIP_Z
	var s := PLAYER_SIZE_PX * SHIP_DISPLAY_GAIN / float(VP_SIZE)
	spr.scale = Vector2(s, s)
	_ship_spr = spr
	_player.add_child(spr)
	_update_ship_3d()

func _build_ship_viewport() -> void:
	_ship_vp = SubViewport.new()
	_ship_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_ship_vp.transparent_bg = true
	_ship_vp.own_world_3d = true
	_ship_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_ship_vp.msaa_3d = Viewport.MSAA_4X
	_player.add_child(_ship_vp)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_ship_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_ship_vp.add_child(fill)
	_ship_cam = Camera3D.new()
	_ship_vp.add_child(_ship_cam)
	_ship_pivot = Node3D.new()
	_ship_vp.add_child(_ship_pivot)
	var packed := load(SHIP_MODEL) as PackedScene
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model != null:
		_ship_pivot.add_child(model)
		_frame_ship_cam(model)
	else:
		push_warning("boss_fight_test: could not load ship model at " + SHIP_MODEL)
		_ship_cam.position = Vector3(0.0, 0.0, 5.0)
		_ship_cam.look_at(Vector3.ZERO, Vector3.UP)

func _frame_ship_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_ship_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(SHIP_ISO_DEG)
	_ship_cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	_ship_cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_ship_cam.near = maxf(0.05, dist - radius * 2.0)
	_ship_cam.far  = dist + radius * 2.0

func _model_aabb(root: Node) -> AABB:
	var acc := AABB()
	var has := false
	var inv := _ship_pivot.global_transform.affine_inverse()
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

## Yaw the 3D ship to the aim heading with a gentle bank; keep the display sprite screen-fixed.
func _update_ship_3d() -> void:
	if _ship_pivot == null or _player == null:
		return
	var yaw := -_player.rotation * SHIP_YAW_SIGN
	var lean := deg_to_rad(SHIP_LEAN_MAX_DEG) * sin(_player.rotation) * SHIP_INVERT_SIDES
	var base := Basis(Vector3(0, 1, 0), deg_to_rad(-90.0))
	var lean_b := Basis(Vector3(1, 0, 0), lean)
	var heading := Basis(Vector3(0, 1, 0), yaw)
	_ship_pivot.transform = Transform3D(heading * base * lean_b, Vector3.ZERO)
	if _ship_spr != null:
		_ship_spr.rotation = -_player.rotation


func _spawn_boss(idx: int) -> void:
	if idx < 0 or idx >= BOSSES.size():
		return
	if _boss != null and is_instance_valid(_boss):
		_boss.queue_free()
	_boss_idx = idx
	var script: GDScript = BOSSES[idx]["script"]
	_boss = script.new() as Node2D
	_boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	var px := _player.global_position if _player != null else Vector2.ZERO
	_boss.global_position = Vector2(px.x, px.y - 340.0)
	add_child(_boss)
	_apply_move_enabled()
	_update_hud()

## Push the persisted move-enable selection onto the (freshly spawned) boss; seed it from the boss defaults once.
func _apply_move_enabled() -> void:
	if _boss == null or not is_instance_valid(_boss) or not _boss.has_method("get_move_meta"):
		return
	if _move_enabled.is_empty():
		for m: Dictionary in _boss.get_move_meta():
			_move_enabled[m["id"]] = _boss.is_move_enabled(m["id"])
	for id: String in _move_enabled.keys():
		_boss.set_move_enabled(id, _move_enabled[id])


func _process(delta: float) -> void:
	if _player == null or get_tree().paused:
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  v.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
	if v.length() > 0.0:
		_player.global_position += v.normalized() * MOVE_SPEED * delta
	var to_mouse := get_global_mouse_position() - _player.global_position
	if to_mouse.length() > 1.0:
		_player.rotation = to_mouse.angle() + PI * 0.5
	_update_ship_3d()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_P:
			_toggle_panel()
		elif k.keycode == KEY_ESCAPE and _panel != null and _panel.visible:
			_toggle_panel()
		elif k.keycode == KEY_R:
			_spawn_boss(_boss_idx)
		elif k.keycode >= KEY_1 and k.keycode <= KEY_9:
			var i := k.keycode - KEY_1
			if i < BOSSES.size():
				_spawn_boss(i)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)
	_update_hud()

func _update_hud() -> void:
	if _hud == null:
		return
	var list := ""
	for i in BOSSES.size():
		list += "  [%d] %s" % [i + 1, BOSSES[i]["name"]]
	var cur: String = BOSSES[_boss_idx]["name"] if _boss_idx < BOSSES.size() else "-"
	_hud.text = "BOSS FIGHT TEST\nWASD move · mouse aim · Gatling auto-fires\nPick boss:%s   ·   R = restart   ·   P = moves panel\nCurrent: %s" % [list, cur]


func _build_move_panel() -> void:
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 80
	_panel_layer.process_mode = Node.PROCESS_MODE_ALWAYS   # stays interactive while the game is paused
	add_child(_panel_layer)
	_panel = PanelContainer.new()
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.hide()
	_panel_layer.add_child(_panel)

func _toggle_panel() -> void:
	if _panel == null:
		return
	if _panel.visible:
		_panel.hide()
		get_tree().paused = false
		_spawn_boss(_boss_idx)   # restart the fight with the current move selection
	else:
		_populate_panel()
		_panel.show()
		_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
		get_tree().paused = true

func _populate_panel() -> void:
	for c in _panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "MOVES — tick to enable   ·   P to close"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	if _boss == null or not is_instance_valid(_boss) or not _boss.has_method("get_move_meta"):
		var none := Label.new()
		none.text = "(no boss / no moves)"
		vb.add_child(none)
		return
	for m: Dictionary in _boss.get_move_meta():
		var id: String = m["id"]
		var cb := CheckBox.new()
		cb.process_mode = Node.PROCESS_MODE_ALWAYS
		cb.text = String(m["name"])
		cb.button_pressed = bool(_move_enabled.get(id, true))
		cb.toggled.connect(_on_move_toggled.bind(id))
		vb.add_child(cb)
		var desc := Label.new()
		desc.text = "      " + String(m["desc"])
		desc.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(560, 0)
		vb.add_child(desc)

func _on_move_toggled(pressed: bool, id: String) -> void:
	_move_enabled[id] = pressed
	if _boss != null and is_instance_valid(_boss):
		_boss.set_move_enabled(id, pressed)


## Static world grid for depth/perspective reference (scrolls under the camera as you move).
class GridBg extends Node2D:
	func _draw() -> void:
		var ext := 3000.0
		var step := 100.0
		var minor := Color(0.16, 0.18, 0.24, 0.7)
		var axis := Color(0.35, 0.40, 0.55, 0.9)
		var x := -ext
		while x <= ext:
			draw_line(Vector2(x, -ext), Vector2(x, ext), axis if absf(x) < 0.5 else minor, 1.0)
			x += step
		var y := -ext
		while y <= ext:
			draw_line(Vector2(-ext, y), Vector2(ext, y), axis if absf(y) < 0.5 else minor, 1.0)
			y += step
