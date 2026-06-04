class_name EditableObjectNode
extends Control

signal transform_ended(obj: Control)
signal transform_motion(obj: EditableObjectNode)
signal object_clicked(obj: EditableObjectNode)

const HANDLE_VISUAL := 10.0
const HANDLE_HIT    := 22.0
const MIN_SIZE := Vector2(1.0, 1.0)
const GROUP_LAYER_MARKER := "res://__group_layer__"

func is_group_layer() -> bool:
	return source_path == GROUP_LAYER_MARKER

@onready var texture_rect: TextureRect = $TextureRect

var _aspect_ratio := 1.0
var _dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO

var _gameplay_mode := false
var _price_label: Label = null
var _counter_label: Label = null
var _vps_label: Label = null
var _cps_label: Label = null
var _hover_tween: Tween = null
var _pop_tween: Tween = null
var _desc_panel: PanelContainer = null

var _gif_frames: Array = []   # Array[ImageTexture]
var _gif_delays: Array = []   # Array[float]
var _gif_idx: int = 0
var _gif_acc: float = 0.0

var screen_blend: bool = false
var gif_paused:   bool = false


var selected := false:
	set(v):
		selected = v
		queue_redraw()

var group_id := ""
var source_path := ""
var display_name := ""
var layer_visible := true

func _ready() -> void:
	_price_label = Label.new()
	_price_label.visible = false
	_price_label.z_index = 10
	_price_label.add_theme_color_override("font_color", Color.WHITE)
	_price_label.add_theme_font_size_override("font_size", 14)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_price_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _process(delta: float) -> void:
	if _gif_frames.is_empty() or gif_paused:
		return
	_gif_acc += delta
	var delay: float = _gif_delays[_gif_idx]
	if _gif_acc >= delay:
		_gif_acc -= delay
		_gif_idx = (_gif_idx + 1) % _gif_frames.size()
		texture_rect.texture = _gif_frames[_gif_idx]

func reset_gif() -> void:
	_gif_idx = 0
	_gif_acc = 0.0
	if not _gif_frames.is_empty() and texture_rect != null:
		texture_rect.texture = _gif_frames[0]

func init(tex: Texture2D, pos: Vector2, sz := Vector2.ZERO) -> void:
	texture_rect.texture = tex
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	if w > 0.0 and h > 0.0:
		_aspect_ratio = w / h
	else:
		_aspect_ratio = 1.0
	if sz == Vector2.ZERO:
		sz = Vector2(200.0, 200.0 / _aspect_ratio)
	position = pos
	size = sz
	_sync_rect_size()
	_setup_counter_label()
	_setup_price_label()
	_setup_desc_panel()
	# Tag the ship body so weapon_system.gd can anchor muzzle/aura to it.
	if group_id == "weaponry" and source_path.get_file().get_basename().to_lower() in ["view", "spaceship"]:
		add_to_group("ship_body")
	if is_group_layer():
		texture_rect.visible = false
	if tex.has_meta("gif_frames"):
		_gif_frames = tex.get_meta("gif_frames")
		_gif_delays = tex.get_meta("gif_delays")
		_gif_idx = 0
		_gif_acc = 0.0

func _setup_counter_label() -> void:
	pass

func _setup_price_label() -> void:
	if group_id != "active" or is_group_layer():
		return
	var upgrade_id := source_path.get_file().get_basename().to_lower()
	if UpgradeManager.UPGRADES.has(upgrade_id):
		var price: float = UpgradeManager.UPGRADES[upgrade_id]["cost"]
		var cost_type: String = UpgradeManager.UPGRADES[upgrade_id].get("cost_type", "metal")
		_price_label.text = "%d %s" % [int(price), cost_type.capitalize()]
		_price_label.size = Vector2(size.x, 30.0)

func _setup_desc_panel() -> void:
	if group_id != "active" or is_group_layer():
		return
	var upgrade_id := source_path.get_file().get_basename().to_lower()
	if not UpgradeManager.UPGRADES.has(upgrade_id):
		return
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]

	_desc_panel = PanelContainer.new()
	_desc_panel.visible = false
	_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.12, 0.94)
	style.corner_radius_top_left    = 4
	style.corner_radius_top_right   = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 7.0
	style.content_margin_right  = 7.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	_desc_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var price_lbl := Label.new()
	var cost_type: String = data.get("cost_type", "metal")
	price_lbl.text = "%d %s" % [int(data["cost"]), cost_type.capitalize()]
	price_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	price_lbl.add_theme_font_size_override("font_size", 11)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(price_lbl)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size = Vector2(180.0, 0.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	add_child(_desc_panel)
	_desc_panel.position = Vector2(size.x + 8.0, 0.0)

# Removed legacy counters

func set_gameplay_mode(v: bool) -> void:
	_gameplay_mode = v
	if not v:
		modulate.a = 1.0  # khôi phục nếu gun_system đã ẩn PNG bằng modulate
	if _counter_label:
		_counter_label.visible = v
	if _vps_label:
		_vps_label.visible = v
	if _cps_label:
		_cps_label.visible = v
	if not v:
		_hide_hover_immediate()
	if is_group_layer():
		visible = not v
	elif v and group_id == "stat":
		visible = false
	elif v and group_id == "equipment":
		var item_id := source_path.get_file().get_basename().to_lower()
		visible = layer_visible and EquipmentManager.get_owned(item_id) >= 1
	elif v and group_id == "screen":
		visible = false
	elif v and group_id == "weaponry":
		# WeaponManager.sync_from_canvas() sets layer_visible per purchase state.
		# gun_system.gd tự hide gun/turret/emitter/railgun via modulate.a=0.0
		visible = layer_visible
	else:
		visible = layer_visible

func get_state() -> Dictionary:
	# Spaceship stores SHIP_ASSEMBLY_Z internally for rendering; save as 0 (logical reference point)
	var save_z := z_index
	if group_id == "weaponry" and source_path.get_file().get_basename().to_lower() == "spaceship":
		save_z = 0
	return { "path": source_path, "group": group_id, "pos": global_position, "size": size, "z_index": save_z, "layer_visible": layer_visible, "flip_h": texture_rect.flip_h if texture_rect else false, "display_name": display_name, "blend_mode": 1 if screen_blend else 0 }

func set_screen_blend(enabled: bool) -> void:
	screen_blend = enabled
	if enabled:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		texture_rect.material = mat
	else:
		texture_rect.material = null

func apply_state(state: Dictionary) -> void:
	position = state["pos"]
	size = state["size"]
	_sync_rect_size()

func _sync_rect_size() -> void:
	texture_rect.position = Vector2.ZERO
	texture_rect.size = size
	custom_minimum_size = MIN_SIZE
	if _price_label:
		_price_label.size = Vector2(size.x, 30.0)
	if _counter_label:
		_counter_label.position = Vector2(size.x + 6, size.y * 0.5 - 12)
	if _vps_label:
		_vps_label.position = Vector2(size.x + 6, size.y * 0.5 + 12)
	if _cps_label:
		_cps_label.position = Vector2(size.x + 6, size.y * 0.5 + 12)
	if _desc_panel:
		_desc_panel.position = Vector2(size.x + 8.0, 0.0)
	queue_redraw()

func _draw() -> void:
	if _gameplay_mode:
		return
	if is_group_layer():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.12, 0.30), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.4, 0.6, 0.85), false, 2.0)
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, 0.35), true)

func _gui_input(event: InputEvent) -> void:
	if _gameplay_mode:
		_handle_gameplay_input(event)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			get_viewport().set_input_as_handled()
			object_clicked.emit(self)
			if selected:  # Only drag if already selected via object list
				_dragging = true
				_drag_start_mouse = get_global_mouse_position()
				_drag_start_pos = position
		else:
			if _dragging:
				transform_ended.emit(self)
			_dragging = false

	elif event is InputEventMouseMotion:
		if _dragging:
			position = _drag_start_pos + (get_global_mouse_position() - _drag_start_mouse)
			transform_motion.emit(self)

func _handle_gameplay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		object_clicked.emit(self)
		if group_id == "weaponry" and source_path.get_file().get_basename().to_lower() == "view":
			_flash_ship()
			_collect_near_asteroids()

func _on_mouse_entered() -> void:
	if not _gameplay_mode or group_id != "active" or is_group_layer():
		return
	var upgrade_id := source_path.get_file().get_basename().to_lower()
	if not UpgradeManager.UPGRADES.has(upgrade_id):
		return
	_show_hover()

func _on_mouse_exited() -> void:
	if not _gameplay_mode or group_id != "active" or is_group_layer():
		return
	_hide_hover()

func _show_hover() -> void:
	if _hover_tween:
		_hover_tween.kill()
	pivot_offset = size / 2.0
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.12)
	_hover_tween.tween_property(texture_rect, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.12)
	if _desc_panel:
		_desc_panel.visible = true
		_desc_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_hover_tween.tween_property(_desc_panel, "modulate:a", 1.0, 0.18)

func _hide_hover() -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	_hover_tween.tween_property(texture_rect, "modulate", Color.WHITE, 0.1)
	if _desc_panel:
		_hover_tween.tween_property(_desc_panel, "modulate:a", 0.0, 0.1).finished.connect(
			func(): if is_instance_valid(_desc_panel): _desc_panel.visible = false
		)

func _hide_hover_immediate() -> void:
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null
	scale = Vector2.ONE
	texture_rect.modulate = Color.WHITE
	if _price_label:
		_price_label.visible = false
	if _desc_panel:
		_desc_panel.visible = false

func _flash_ship() -> void:
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null
	pivot_offset = size / 2.0
	var t := create_tween()
	t.tween_property(texture_rect, "modulate", Color(2.5, 2.5, 2.5, 1.0), 0.07)
	t.tween_property(texture_rect, "modulate", Color.WHITE, 0.25)

func _collect_near_asteroids() -> void:
	var ship_center: Vector2 = global_position + size / 2.0
	var local: Vector2 = ship_center - Vector2(270.0, 8.0)
	for node: Node in get_tree().get_nodes_in_group("asteroid_main"):
		if node.has_method("collect_near"):
			node.collect_near(local, 10.0)

# --- Gameplay animations ---

func animate_screen_click() -> void:
	pivot_offset = size / 2.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.03, 1.03), 0.08)
	t.parallel().tween_property(texture_rect, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.08)
	t.tween_property(self, "scale", Vector2.ONE, 0.15)
	t.parallel().tween_property(texture_rect, "modulate", Color.WHITE, 0.15)

func animate_upgrade_result(success: bool) -> void:
	if success:
		var t := create_tween()
		t.tween_property(texture_rect, "modulate", Color(0.5, 1.0, 0.5, 1.0), 0.1)
		t.tween_property(texture_rect, "modulate", Color.WHITE, 0.3)
	else:
		var t := create_tween()
		t.tween_property(texture_rect, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.1)
		t.tween_property(texture_rect, "modulate", Color.WHITE, 0.3)
