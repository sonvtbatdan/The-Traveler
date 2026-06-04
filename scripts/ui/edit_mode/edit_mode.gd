extends CanvasLayer

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const LAYOUT_PATH        := "res://default_layout.cfg"
const PRESET_LAYOUT_PATH := "res://preset_layout.cfg"
const GROUPS := ["screen", "weaponry", "defense", "power_core", "user"]
const ASSEMBLY_GROUPS := ["weaponry", "defense", "power_core"]
# Spaceship z_index in ObjectsContainer — high enough so children at negative local z stay above background (z=0,1)
const SHIP_ASSEMBLY_Z := 100
const SCREEN_FIT_W := 1440.0
const SCREEN_FIT_H := 780.0
const GROUP_FOLDERS := {
	"screen":     "screen",
	"weaponry":   "weaponry",
	"defense":    "defense",
	"power_core": "sprites/thrust",
	"user":       "user",
}
# SpaceScreen position and default tile size (2048×2048 image at scale 1.0 → 700×700px tile)
const SCREEN_ORIGIN := Vector2(270.0, 8.0)
const SCREEN_TILE_SZ := 700.0

# Sentinel source_path for the synthetic Group Layer object.
# Pinned at the top of each group's list; moving/resizing it propagates to
# all other objects in the group. Texture is generated procedurally.
const GROUP_LAYER_MARKER := "res://__group_layer__"
const GROUP_LAYER_DEFAULT_SIZE := 120.0
const GROUP_LAYER_DEFAULT_POS := Vector2(20.0, 20.0)

# Virtual source-path prefixes for upgrade-shelf start/end markers.
const SHELF_START_PREFIX := "res://__shelf_start_"
const SHELF_END_PREFIX   := "res://__shelf_end_"

@onready var objects_container: Control = $ObjectsContainer
@onready var dim_overlay: ColorRect = $DimOverlay
@onready var side_panel: Panel = $SidePanel
@onready var title_bar: Panel = $SidePanel/VBox/TitleBar
@onready var object_list_panel: Panel = $SidePanel/VBox/TopHBox/ObjectListPanel
@onready var file_dialog: FileDialog = $FileDialog
@onready var unsaved_dialog: Window = $UnsavedDialog

@onready var btn_screen: Button      = $SidePanel/VBox/TopHBox/ButtonsColumn/ScreenGroupBtn
@onready var btn_weaponry: Button    = $SidePanel/VBox/TopHBox/ButtonsColumn/EquipmentBtn
@onready var btn_defense: Button     = $SidePanel/VBox/TopHBox/ButtonsColumn/ScreenBtn
@onready var btn_power_core: Button  = $SidePanel/VBox/TopHBox/ButtonsColumn/StatBtn
@onready var btn_user: Button        = $SidePanel/VBox/TopHBox/ButtonsColumn/UserBtn
@onready var btn_reset_screen: Button     = $SidePanel/VBox/TopHBox/ButtonsColumn/ResetScreenBtn
@onready var btn_symmetric: Button        = $SidePanel/VBox/TopHBox/ButtonsColumn/SymmetricBtn
@onready var btn_save: Button             = $SidePanel/VBox/TopHBox/ButtonsColumn/SaveBtn
@onready var transform_panel         = $SidePanel/VBox/TransformPanel

var _active_group := "weaponry"
var _user_panel: Node = null
var _shelf_node: Node = null
var _is_open := false
var _dirty := false
var _pending_object: Texture2D = null
var _pending_path := ""
var _selected_objects: Array = []

var _undo_stack: Array[Dictionary] = []
var _placed: Dictionary = {}  # group -> Array[EditableObjectNode]
var _group_layer_prev_state: Dictionary = {}  # group -> {pos, size}
var _group_drag_started: Dictionary = {}     # group -> bool

# SidePanel drag-to-move state. Started by clicking the TitleBar; the
# subsequent motion + release events are caught in _input() because they
# travel faster than the panel moves and won't always land on the title bar.
var _dragging_panel: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _selection_locked := false

var _canvas_dragging := false
var _canvas_drag_mouse_prev := Vector2.ZERO
var _canvas_drag_undo_pushed := false
var _layout_loaded := false
var _layout_version: int = 1  # 1=old global z_index, 2=new local z_index (post-reparent)
var _pre_drag_states: Dictionary = {}  # obj -> {pos, size} recorded at drag-start
var _symmetric: bool = false

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	for g in GROUPS:
		_placed[g] = []
	object_list_panel.row_selected.connect(_on_list_row_selected)
	object_list_panel.file_dropped.connect(_on_file_dropped)
	object_list_panel.z_indices_changed.connect(_sort_canvas_z_order)
	object_list_panel.order_changed.connect(func(_a: int, _b: int) -> void: _dirty = true)
	title_bar.gui_input.connect(_on_title_bar_input)
	_user_panel = get_parent().get_node_or_null("UserPanel")
	_shelf_node = get_parent().get_node_or_null("UpgradeShelf")
	object_list_panel.group_layer_visibility_toggled.connect(_on_group_layer_visibility_toggled)
	object_list_panel.row_context_action.connect(_on_context_action)
	object_list_panel.display_name_changed.connect(func(_obj: EditableObjectNode): _dirty = true)
	btn_reset_screen.pressed.connect(_reset_screen_group)
	btn_symmetric.pressed.connect(func(): _symmetric = btn_symmetric.button_pressed)
	# Removed: btn_fit_screen, btn_reset_equipment, btn_show_weapon, btn_delete, btn_upload
	btn_save.pressed.connect(_on_save_pressed)
	btn_screen.pressed.connect(func() -> void: _set_group("screen"))
	btn_weaponry.pressed.connect(func() -> void: _set_group("weaponry"))
	btn_defense.pressed.connect(func() -> void: _set_group("defense"))
	btn_power_core.pressed.connect(func() -> void: _set_group("power_core"))
	btn_user.pressed.connect(func() -> void: _set_group("user"))
	unsaved_dialog.get_node("VBox/BtnRow/SaveBtn").pressed.connect(_on_dialog_save)
	unsaved_dialog.get_node("VBox/BtnRow/DiscardBtn").pressed.connect(_on_dialog_discard)
	unsaved_dialog.get_node("VBox/BtnRow/CancelBtn").pressed.connect(_on_dialog_cancel)
	file_dialog.files_selected.connect(_on_file_dialog_files_selected)
	transform_panel.connect("transform_changed", _on_transform_live)
	EquipmentManager.item_purchased.connect(_on_equipment_item_purchased)
	_set_edit_ui_visible(false)
	_load_layout()
	_auto_load_all_groups()

func _set_edit_ui_visible(v: bool) -> void:
	dim_overlay.visible = v
	side_panel.visible = v
	if not v:
		_dragging_panel = false
		_canvas_dragging = false

func refresh_weaponry_gameplay() -> void:
	for obj in _placed.get("weaponry", []):
		if is_instance_valid(obj) and not _is_open:
			obj.set_gameplay_mode(true)

func _is_spaceship(obj: EditableObjectNode) -> bool:
	return obj.group_id == "weaponry" and \
		obj.source_path.get_file().get_basename().to_lower() == "spaceship"

func _is_weapon(obj: EditableObjectNode) -> bool:
	return obj.group_id == "weaponry" and \
		not _is_spaceship(obj) and \
		not obj.is_group_layer() and \
		not obj.source_path.begins_with(SHELF_START_PREFIX) and \
		not obj.source_path.begins_with(SHELF_END_PREFIX)

func _find_ship_eo_in_placed() -> EditableObjectNode:
	for obj in _placed.get("weaponry", []):
		if is_instance_valid(obj) and _is_spaceship(obj):
			return obj
	return null

# ── Symmetric helpers ─────────────────────────────────────────────────────────

func _obj_label_name(obj: EditableObjectNode) -> String:
	return obj.display_name if not obj.display_name.is_empty() \
		else obj.source_path.get_file().get_basename()

func _get_symmetry_axis_x() -> float:
	var ship := _find_ship_eo_in_placed()
	if ship == null or not is_instance_valid(ship):
		return 0.0
	return ship.size.x * 0.5

func _find_symmetric_partner(obj: EditableObjectNode) -> EditableObjectNode:
	if not _symmetric or _active_group not in ASSEMBLY_GROUPS:
		return null
	var label := _obj_label_name(obj)
	var partner_label: String
	if label.begins_with("L"):
		partner_label = "R" + label.substr(1)
	elif label.begins_with("R"):
		partner_label = "L" + label.substr(1)
	else:
		return null
	for g in ASSEMBLY_GROUPS:
		for o: EditableObjectNode in _placed.get(g, []):
			if is_instance_valid(o) and o != obj and _obj_label_name(o) == partner_label:
				return o
	return null

func _apply_symmetric(changed: EditableObjectNode) -> void:
	var partner := _find_symmetric_partner(changed)
	if partner == null:
		return
	var ax := _get_symmetry_axis_x()
	partner.position = Vector2(2.0 * ax - changed.position.x - changed.size.x, changed.position.y)
	partner.size = changed.size
	partner._sync_rect_size()
	_dirty = true

func _refresh_assembly_list() -> void:
	var ship_eo := _find_ship_eo_in_placed()
	var all_objs: Array = []
	var groups_to_show: Array = [_active_group] if _active_group in ASSEMBLY_GROUPS else ASSEMBLY_GROUPS
	for g in groups_to_show:
		for obj in _placed.get(g, []):
			if is_instance_valid(obj) and not obj.is_group_layer() and not _is_spaceship(obj):
				all_objs.append(obj)
	object_list_panel.refresh_assembly(ship_eo, all_objs)

func _reparent_assembly_objects() -> void:
	var ship_eo := _find_ship_eo_in_placed()
	if ship_eo == null or not is_instance_valid(ship_eo):
		return
	# ship_z là z_index hiện tại của spaceship trong ObjectsContainer (sau khi _load_layout renumber)
	# Dùng để convert global z → local z: local_z = global_z - ship_z
	# Kết quả: spaceship display = 0, trên hull = dương, dưới hull = âm
	var ship_z := ship_eo.z_index
	for g in ASSEMBLY_GROUPS:
		for obj in _placed.get(g, []):
			if not is_instance_valid(obj) or obj == ship_eo or obj.is_group_layer():
				continue
			if obj.get_parent() == objects_container:
				var global_pos: Vector2 = obj.global_position
				objects_container.remove_child(obj)
				ship_eo.add_child(obj)
				obj.position = global_pos - ship_eo.global_position
				obj.z_index -= ship_z       # convert to local: 0=hull level, positive=above, negative=below
				obj.z_as_relative = true    # effective z = SHIP_ASSEMBLY_Z + local_z → always above background
	# Set spaceship's actual render z high enough for children at most-negative local z to stay above background
	ship_eo.z_index = SHIP_ASSEMBLY_Z
	_layout_version = 2

func _apply_weapons_visibility() -> void:
	if _active_group in ASSEMBLY_GROUPS:
		_refresh_assembly_list()
	elif _active_group == "weaponry":
		object_list_panel.refresh(_get_weaponry_list_objects())

func _get_weaponry_list_objects() -> Array:
	var result: Array = []
	for obj in _placed.get("weaponry", []):
		if not is_instance_valid(obj):
			continue
		result.append(obj)
	return result

func _move_weapons_by_delta(delta: Vector2) -> void:
	for obj in _placed.get("weaponry", []):
		if is_instance_valid(obj) and _is_weapon(obj):
			obj.position += delta

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging_panel = true
		_drag_offset = side_panel.global_position - get_viewport().get_mouse_position()

func _input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed:
		if not event.echo and event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()
			get_viewport().set_input_as_handled()
			return
		if not event.echo and event.keycode == KEY_DELETE and not _selected_objects.is_empty():
			for obj in _selected_objects.duplicate():
				_delete_object(obj)
			get_viewport().set_input_as_handled()
			return
		if not _selected_objects.is_empty():
			var dir := Vector2.ZERO
			match event.keycode:
				KEY_UP:    dir = Vector2(0.0, -1.0)
				KEY_DOWN:  dir = Vector2(0.0,  1.0)
				KEY_LEFT:  dir = Vector2(-1.0, 0.0)
				KEY_RIGHT: dir = Vector2( 1.0, 0.0)
			if dir != Vector2.ZERO:
				if event.shift_pressed:
					dir *= 10.0
				var spaceship_selected := false
				for obj in _selected_objects:
					if is_instance_valid(obj) and _is_spaceship(obj):
						spaceship_selected = true
						break
				if not event.echo:
					if spaceship_selected:
						_push_undo_group_transform("weaponry")
					else:
						for obj in _selected_objects:
							if obj is EditableObjectNode and (obj as EditableObjectNode).is_group_layer():
								_push_undo_group_transform(obj.group_id)
							else:
								_push_undo_transform(obj)
				for obj in _selected_objects:
					obj.position += dir
					if obj is EditableObjectNode and (obj as EditableObjectNode).is_group_layer():
						_propagate_group_layer(obj.group_id, dir, obj.size.x, obj.size.x)
						_group_layer_prev_state[obj.group_id] = {"pos": obj.position, "size": obj.size}
				# Children of spaceship move automatically via parent-child — no explicit loop needed
				if _symmetric:
					for obj in _selected_objects:
						if obj is EditableObjectNode:
							_apply_symmetric(obj as EditableObjectNode)
				transform_panel.refresh(_primary_selected())
				_dirty = true
				get_viewport().set_input_as_handled()
				return

	if _dragging_panel:
		if event is InputEventMouseMotion:
			var new_pos: Vector2 = get_viewport().get_mouse_position() + _drag_offset
			var vp_size: Vector2 = get_viewport().get_visible_rect().size
			var vis_w := side_panel.size.x * side_panel.scale.x
			var vis_h := side_panel.size.y * side_panel.scale.y
			new_pos.x = clampf(new_pos.x, 0.0, vp_size.x - vis_w)
			new_pos.y = clampf(new_pos.y, 0.0, vp_size.y - vis_h)
			side_panel.position = new_pos
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_panel = false
		return

	if not _canvas_dragging:
		return
	if event is InputEventMouseMotion:
		var mouse_pos := get_viewport().get_mouse_position()
		var delta := mouse_pos - _canvas_drag_mouse_prev
		_canvas_drag_mouse_prev = mouse_pos
		if not _canvas_drag_undo_pushed:
			_canvas_drag_undo_pushed = true
			for obj in _selected_objects:
				if is_instance_valid(obj):
					if obj.is_group_layer():
						_push_undo_group_transform(obj.group_id)
					else:
						_push_undo_transform(obj)
		for obj in _selected_objects:
			if not is_instance_valid(obj):
				continue
			obj.position += delta
			if obj.is_group_layer():
				_propagate_group_layer(obj.group_id, delta, obj.size.x, obj.size.x)
				_group_layer_prev_state[obj.group_id] = {"pos": obj.position, "size": obj.size}
		if _symmetric:
			for obj in _selected_objects:
				if is_instance_valid(obj) and obj is EditableObjectNode:
					_apply_symmetric(obj as EditableObjectNode)
		transform_panel.refresh(_primary_selected())
		_dirty = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_canvas_dragging = false
		_canvas_drag_undo_pushed = false
		for obj in _selected_objects:
			if is_instance_valid(obj) and obj.is_group_layer():
				_group_drag_started[obj.group_id] = false

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventKey and event.pressed:
		if not event.echo and event.is_action_pressed("toggle_edit_mode"):
			_request_close()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not side_panel.get_global_rect().has_point(event.position):
			_canvas_dragging = false
			_canvas_drag_undo_pushed = false
			_selection_locked = false
			_select_objects([])
			object_list_panel.highlight_objects([])
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not side_panel.get_global_rect().has_point(event.position):
			if _pending_object:
				var mp := objects_container.get_local_mouse_position()
				_place_object(_pending_object, mp, Vector2.ZERO, _pending_path)
				_pending_object = null
				_pending_path = ""
				get_viewport().set_input_as_handled()
			elif _selection_locked and not _selected_objects.is_empty():
				_canvas_dragging = true
				_canvas_drag_mouse_prev = get_viewport().get_mouse_position()
				_canvas_drag_undo_pushed = false
				get_viewport().set_input_as_handled()
			elif not _selection_locked:
				_select_objects([])
				object_list_panel.highlight_objects([])

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if not _is_open:
		_is_open = true
		_symmetric = false
		btn_symmetric.button_pressed = false
		_set_edit_ui_visible(true)
		for child in objects_container.get_children():
			if child.has_method("reset_to_origin"):
				child.reset_to_origin()
		_set_group(_active_group)
		_apply_weapons_visibility()
		get_tree().paused = true
	else:
		_request_close()

# --- Group ---

func _set_group(group: String) -> void:
	_selection_locked = false
	_active_group = group
	if group in ASSEMBLY_GROUPS:
		for g in ASSEMBLY_GROUPS:
			_auto_load_group(g)
		object_list_panel.set_group_label("ship assembly")
		_refresh_assembly_list()
	else:
		_auto_load_group(group)
		object_list_panel.set_group_label(group)
		object_list_panel.refresh(_placed.get(group, []))
	_update_group_buttons()
	_update_object_interactivity()
	_pending_object = null
	_select_objects([])
	if _shelf_node and _shelf_node.has_method("set_edit_mode"):
		_shelf_node.set_edit_mode(group == "weaponry")

func _auto_load_all_groups() -> void:
	var prev := _active_group
	for g in GROUPS:
		_active_group = g
		_auto_load_group(g)
	_active_group = prev
	if _layout_loaded:
		_pin_group_layers_to_top()
	else:
		_init_group_z_indices()
	_update_object_interactivity()
	_sort_canvas_z_order()

# When layout is loaded, z_indices are already correct — only push each group
# layer above the highest non-layer object so it doesn't block mouse picking.
func _pin_group_layers_to_top() -> void:
	for group in GROUPS:
		var max_z := 0
		for obj in _placed[group]:
			if is_instance_valid(obj) and not obj.is_group_layer():
				max_z = maxi(max_z, obj.z_index)
		for obj in _placed[group]:
			if is_instance_valid(obj) and obj.is_group_layer():
				obj.z_index = max_z + 1
	_undo_stack.clear()
	_dirty = false

# Assign z_indices so each group's Group Layer sits on top of its siblings.
# Called after auto-load when the object list panel hasn't set z_indices yet.
func _init_group_z_indices() -> void:
	for group in GROUPS:
		var objs: Array = _placed[group]
		var n := objs.size()
		var layer_idx := -1
		for i in n:
			if is_instance_valid(objs[i]) and objs[i].is_group_layer():
				layer_idx = i
				break
		if layer_idx < 0:
			continue
		objs[layer_idx].z_index = n - 1
		var z := 0
		for i in n:
			if i == layer_idx:
				continue
			if is_instance_valid(objs[i]):
				objs[i].z_index = z
				z += 1
	_undo_stack.clear()
	_dirty = false

func _ensure_group_layer(_group: String) -> void:
	pass  # Group layers removed — each object is positioned independently

# 3x3 grid glyph: nine rounded squares on a dark backdrop.
func _make_group_layer_texture() -> Texture2D:
	var side := 128
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var bg := Color(0.08, 0.10, 0.14, 1.0)
	var border := Color(0.55, 0.65, 0.85, 1.0)
	var cell_color := Color(0.85, 0.90, 1.0, 1.0)
	img.fill(bg)
	# Outer border (2px ring).
	for y in side:
		for x in side:
			if x < 2 or x >= side - 2 or y < 2 or y >= side - 2:
				img.set_pixel(x, y, border)
	# 3x3 inner cells. Inset 12px, gutter 6px between cells.
	var inset := 16
	var gutter := 6
	var inner := side - inset * 2
	var cell_size := (inner - gutter * 2) / 3
	for row in 3:
		for col in 3:
			var x0 := inset + col * (cell_size + gutter)
			var y0 := inset + row * (cell_size + gutter)
			for dy in cell_size:
				for dx in cell_size:
					img.set_pixel(x0 + dx, y0 + dy, cell_color)
	return ImageTexture.create_from_image(img)

func _auto_load_screen_group() -> void:
	var folder := "res://assets/screen/"
	var files: Array[String] = ["background.png", "overlay.png"]
	var placed_paths: Dictionary = {}
	for obj in _placed["screen"]:
		if is_instance_valid(obj):
			placed_paths[obj.source_path] = true
	for file: String in files:
		var full_path: String = folder + file
		if placed_paths.has(full_path):
			continue
		var tex := _load_tex(full_path)
		if tex == null:
			continue
		var obj := _place_object(tex, Vector2.ZERO, Vector2(SCREEN_TILE_SZ, SCREEN_TILE_SZ), full_path, true)
		obj.position = SCREEN_ORIGIN
		obj.size     = Vector2(SCREEN_TILE_SZ, SCREEN_TILE_SZ)
		obj._sync_rect_size()

func _auto_load_group(group: String) -> void:
	if group == "screen":
		_auto_load_screen_group()
		return
	_ensure_group_layer(group)
	var folder := "res://assets/" + (GROUP_FOLDERS.get(group, group) as String) + "/"
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	var placed_paths: Dictionary = {}
	for obj in _placed[group]:
		if is_instance_valid(obj):
			placed_paths[obj.source_path] = true
	dir.list_dir_begin()
	var file := dir.get_next()
	var slot := 0
	while file != "":
		if not dir.current_is_dir():
			var ext := file.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp", "gif"]:
				var full_path := folder + file
				if not placed_paths.has(full_path):
					var tex := _load_tex(full_path)
					if tex:
						var col := slot % 4
						var row := slot / 4
						var pos := Vector2(20.0 + col * 220.0, 20.0 + row * 220.0)
						_place_object(tex, pos, Vector2.ZERO, full_path, true)
						slot += 1
		file = dir.get_next()
	dir.list_dir_end()
	if group == "weaponry":
		_ensure_shelf_markers()

## Returns the center position (in ObjectsContainer space) of a weaponry-group object
## with the given source_path. Returns Vector2.ZERO if not found.
func get_stat_object_pos(source_path: String) -> Vector2:
	for obj in _placed.get("weaponry", []):
		if is_instance_valid(obj) and obj.source_path == source_path:
			return obj.position + obj.size * 0.5
	return Vector2.ZERO

## Ensure every upgrade type has a start and end marker in the weaponry group.
## Markers are placed at default positions only if not already in the layout.
func _ensure_shelf_markers() -> void:
	var placed_paths: Dictionary = {}
	for obj in _placed.get("weaponry", []):
		if is_instance_valid(obj):
			placed_paths[obj.source_path] = true

	var prev_group := _active_group
	_active_group = "weaponry"
	var ids := UpgradeManager.UPGRADES.keys()
	for i: int in ids.size():
		var upgrade_id: String = ids[i]
		var start_path := SHELF_START_PREFIX + upgrade_id + "__"
		var end_path   := SHELF_END_PREFIX   + upgrade_id + "__"
		var def_y := 445.0 + i * 20.0
		if not placed_paths.has(start_path):
			var tex := _load_tex(start_path)
			if tex:
				var obj := _place_object(tex, Vector2(290.0, def_y), Vector2(22.0, 22.0), start_path, true)
				obj.position = Vector2(290.0, def_y)
		if not placed_paths.has(end_path):
			var tex := _load_tex(end_path)
			if tex:
				var obj := _place_object(tex, Vector2(930.0, def_y), Vector2(22.0, 22.0), end_path, true)
				obj.position = Vector2(930.0, def_y)
	_active_group = prev_group


func _on_context_action(action: String, obj: EditableObjectNode) -> void:
	if not is_instance_valid(obj):
		return
	match action:
		"copy":
			_copy_object(obj)
		"delete":
			_delete_object(obj)
			_select_objects([])
			object_list_panel.highlight_objects([])
			_dirty = true

func _copy_object(obj: EditableObjectNode) -> void:
	if obj.source_path == GROUP_LAYER_MARKER:
		return
	var tex := _load_tex(obj.source_path)
	if tex == null:
		return
	var prev_group := _active_group
	_active_group = obj.group_id
	var new_obj := _place_object(tex, obj.position + Vector2(20.0, 20.0), obj.size, obj.source_path)
	new_obj.layer_visible = obj.layer_visible
	new_obj.visible = obj.layer_visible
	if new_obj.texture_rect and obj.texture_rect:
		new_obj.texture_rect.flip_h = obj.texture_rect.flip_h
	new_obj.set_screen_blend(obj.screen_blend)
	_active_group = prev_group
	_select_objects([new_obj])
	object_list_panel.select_object(new_obj)
	_update_object_interactivity()

func _on_group_layer_visibility_toggled(group_id: String, vis: bool) -> void:
	for obj in _placed[group_id]:
		if is_instance_valid(obj):
			obj.layer_visible = vis
			if not obj.is_group_layer():
				obj.visible = vis
	object_list_panel.update_visibility_buttons()
	_dirty = true

func _update_group_buttons() -> void:
	var in_assembly: bool = _active_group in ASSEMBLY_GROUPS
	btn_screen.button_pressed     = (_active_group == "screen")
	btn_weaponry.button_pressed   = in_assembly
	btn_defense.button_pressed    = in_assembly
	btn_power_core.button_pressed = in_assembly
	btn_user.button_pressed       = (_active_group == "user")
	btn_reset_screen.visible = in_assembly

func _update_object_interactivity() -> void:
	for group in GROUPS:
		for obj in _placed[group]:
			if not is_instance_valid(obj):
				continue
			if _is_open:
				obj.set_gameplay_mode(false)
				var active: bool = (group == _active_group) or \
					(_active_group in ASSEMBLY_GROUPS and group in ASSEMBLY_GROUPS) or \
					obj.is_group_layer()
				obj.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
			else:
				obj.set_gameplay_mode(true)
				var is_frame: bool = "frame" in obj.source_path.get_file().to_lower()
				if group == "weaponry" and not is_frame:
					var is_ref_png: bool = obj.source_path.get_extension().to_lower() == "png" \
						and obj.source_path.get_file().get_basename().to_lower() != "spaceship"
					obj.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_ref_png \
						else Control.MOUSE_FILTER_STOP
				else:
					obj.mouse_filter = Control.MOUSE_FILTER_IGNORE

# --- Object placement ---

func _on_list_row_selected(canvas_obj: EditableObjectNode) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		var new_sel := _selected_objects.duplicate()
		if canvas_obj in new_sel:
			new_sel.erase(canvas_obj)
		else:
			new_sel.append(canvas_obj)
		_select_objects(new_sel)
		object_list_panel.highlight_objects(new_sel)
	else:
		_select_objects([canvas_obj])
		object_list_panel.highlight_objects([canvas_obj])
	_selection_locked = true

func _on_canvas_object_clicked(obj: EditableObjectNode) -> void:
	if not _is_open:
		_handle_gameplay_click(obj)
		return
	# Click to select object
	_select_objects([obj])
	# Prepare for dragging if object is selected
	if obj in _selected_objects:
		if _is_spaceship(obj):
			# Capture entire weaponry group (ship + all weapons) for single-step undo.
			_push_undo_group_transform("weaponry")
			_pre_drag_states[obj] = {"pos": obj.position, "size": obj.size, "undo_group": true}
		else:
			_pre_drag_states[obj] = {"pos": obj.position, "size": obj.size}

func _on_equipment_item_purchased(_id: String) -> void:
	_update_object_interactivity()

func _handle_gameplay_click(obj: EditableObjectNode) -> void:
	match obj.group_id:
		"weaponry":
			GameManager.on_view_clicked()
			_animate_screen_objects()

func _animate_screen_objects() -> void:
	for obj in _placed["weaponry"]:
		if not is_instance_valid(obj) or obj.is_group_layer():
			continue
		var base: String = obj.source_path.get_file().get_basename().to_lower()
		if "frame" in base or base in ["view", "sub", "screen", "base", "bg", "background", "spaceship"]:
			continue
		obj.animate_screen_click()

func _primary_selected() -> EditableObjectNode:
	return _selected_objects[0] if not _selected_objects.is_empty() else null

func _select_objects(objects: Array) -> void:
	for group in GROUPS:
		for obj in _placed[group]:
			if is_instance_valid(obj):
				obj.selected = (obj in objects)
	_selected_objects.clear()
	for obj in objects:
		if is_instance_valid(obj):
			_selected_objects.append(obj as EditableObjectNode)
	transform_panel.refresh(_primary_selected())

func _on_transform_live(pos: Vector2, sz: Vector2) -> void:
	var primary := _primary_selected()
	if not primary or not is_instance_valid(primary):
		return
	var prev_pos := primary.position
	var prev_sz  := primary.size
	primary.position = pos
	primary.size = sz
	primary._sync_rect_size()
	if primary.is_group_layer():
		_propagate_group_layer(primary.group_id, pos - prev_pos, prev_sz.x, sz.x)
		_group_layer_prev_state[primary.group_id] = {"pos": pos, "size": sz}
	elif _symmetric:
		_apply_symmetric(primary)
	_dirty = true

# Sync ObjectsContainer's tree order to match every object's z_index. Godot
# routes GUI input by tree order (later siblings get input first), not by
# z_index, so without this sync a visually-on-top object can be unclickable
# because an underneath sibling absorbs the click.
func _sort_canvas_z_order() -> void:
	# Sort direct ObjectsContainer children (screen, spaceship, user)
	var top_objs: Array = []
	for group in ["screen", "user"]:
		for obj in _placed.get(group, []):
			if is_instance_valid(obj) and obj.get_parent() == objects_container:
				top_objs.append(obj)
	var ship_eo := _find_ship_eo_in_placed()
	if ship_eo != null and is_instance_valid(ship_eo):
		top_objs.append(ship_eo)
	top_objs.sort_custom(func(a: EditableObjectNode, b: EditableObjectNode) -> bool:
		var ka: int = GROUPS.find(a.group_id) * 10000 + a.z_index
		var kb: int = GROUPS.find(b.group_id) * 10000 + b.z_index
		return ka < kb
	)
	for i in top_objs.size():
		objects_container.move_child(top_objs[i], i)
	# Sort spaceship's children (assembly objects) by local z_index
	if ship_eo != null and is_instance_valid(ship_eo):
		var assembly_objs: Array = []
		for g in ASSEMBLY_GROUPS:
			for obj in _placed.get(g, []):
				if is_instance_valid(obj) and obj != ship_eo and obj.get_parent() == ship_eo:
					assembly_objs.append(obj)
		assembly_objs.sort_custom(func(a: EditableObjectNode, b: EditableObjectNode) -> bool:
			return a.z_index < b.z_index
		)
		for i in assembly_objs.size():
			ship_eo.move_child(assembly_objs[i], i)

# Move and/or resize all non-group-layer objects in a group by the same delta/scale.
func _propagate_group_layer(group: String, delta_pos: Vector2, prev_w: float, new_w: float) -> void:
	var scale := new_w / prev_w if prev_w > 0.0 else 1.0
	for obj in _placed[group]:
		if not is_instance_valid(obj) or obj.is_group_layer():
			continue
		obj.position += delta_pos
		if scale != 1.0:
			obj.size = Vector2(obj.size.x * scale, obj.size.y * scale)
			obj._sync_rect_size()

func _on_transform_apply() -> void:
	_save_layout()

func _place_object(tex: Texture2D, pos: Vector2, sz := Vector2.ZERO, path := "", silent := false) -> EditableObjectNode:
	var obj: EditableObjectNode = EditableObject.instantiate()
	obj.transform_ended.connect(notify_transform_changed)
	obj.transform_motion.connect(_on_group_layer_motion)
	obj.object_clicked.connect(_on_canvas_object_clicked)
	objects_container.add_child(obj)
	obj.group_id = _active_group
	obj.source_path = path
	obj.mouse_filter = Control.MOUSE_FILTER_STOP if obj.group_id == _active_group else Control.MOUSE_FILTER_IGNORE
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var aspect := 1.0
	if w > 0.0 and h > 0.0:
		aspect = w / h
	var offset := Vector2(100.0, 100.0 / aspect) / 2.0
	obj.init(tex, pos - offset, sz)
	if tex.get_width() == 2754 and tex.get_height() == 1536 and sz == Vector2.ZERO:
		obj.position = Vector2(10.0, 7.0)
		obj.size = Vector2(767.0, 428.0)
		obj._sync_rect_size()
	_placed[_active_group].append(obj)
	# Reparent assembly objects (non-spaceship) to be children of spaceship EO.
	# Only for interactive placement (not silent=true which is used during load;
	# load reparenting is handled by _reparent_assembly_objects() at end of _load_layout).
	if not silent and _active_group in ASSEMBLY_GROUPS and not _is_spaceship(obj) and not obj.is_group_layer():
		var ship_eo := _find_ship_eo_in_placed()
		if ship_eo != null and is_instance_valid(ship_eo):
			var gpos: Vector2 = obj.global_position
			objects_container.remove_child(obj)
			ship_eo.add_child(obj)
			obj.position = gpos - ship_eo.global_position
			obj.z_as_relative = true
	if not silent:
		object_list_panel.add_placed_object(obj)
	_push_undo_add(obj)
	_dirty = true
	return obj

func notify_transform_changed(obj: Control) -> void:
	if obj is EditableObjectNode and (obj as EditableObjectNode).is_group_layer():
		var eobj := obj as EditableObjectNode
		_group_drag_started[eobj.group_id] = false
		_group_layer_prev_state[eobj.group_id] = {"pos": obj.position, "size": obj.size}
	else:
		if _pre_drag_states.has(obj):
			var pre: Dictionary = _pre_drag_states[obj]
			var already_grouped: bool = pre.get("undo_group", false)
			if not already_grouped and (obj.position != pre["pos"] or obj.size != pre["size"]):
				_undo_stack.append({"type": "transform", "obj": obj, "pos": pre["pos"], "size": pre["size"]})
			# Children of spaceship move automatically via parent-child — no explicit _move_weapons_by_delta needed
			_pre_drag_states.erase(obj)
		if _symmetric and obj is EditableObjectNode:
			_apply_symmetric(obj as EditableObjectNode)
	_dirty = true
	if obj in _selected_objects:
		transform_panel.refresh(_primary_selected())

func _on_group_layer_motion(obj: EditableObjectNode) -> void:
	if not obj.is_group_layer():
		if _symmetric:
			_apply_symmetric(obj)
		return
	var group := obj.group_id
	if not _group_drag_started.get(group, false):
		_group_drag_started[group] = true
		_push_undo_group_transform(group)
		_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
		return
	if not _group_layer_prev_state.has(group):
		_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
		return
	var prev: Dictionary = _group_layer_prev_state[group]
	var delta_pos: Vector2 = obj.position - (prev["pos"] as Vector2)
	var prev_w: float = (prev["size"] as Vector2).x
	_propagate_group_layer(group, delta_pos, prev_w, obj.size.x)
	_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
	_dirty = true

# --- Delete ---

func _on_delete_pressed() -> void:
	for obj in _selected_objects.duplicate():
		_delete_object(obj)

func _delete_object(obj: EditableObjectNode) -> void:
	if not is_instance_valid(obj):
		return
	var group := obj.group_id
	_push_undo_delete(obj)
	_placed[group].erase(obj)
	object_list_panel.remove_object(obj)
	_selected_objects.erase(obj)
	obj.queue_free()
	transform_panel.refresh(_primary_selected())
	_dirty = true

# --- Undo ---

func _push_undo_add(obj: EditableObjectNode) -> void:
	_undo_stack.append({ "type": "add", "obj": obj, "group": _active_group })

func _push_undo_transform(obj: Control) -> void:
	_undo_stack.append({ "type": "transform", "obj": obj, "pos": obj.position, "size": obj.size })

func _push_undo_group_transform(group: String) -> void:
	var states: Array = []
	for obj in _placed[group]:
		if is_instance_valid(obj):
			states.append({ "obj": obj, "pos": obj.position, "size": obj.size })
	_undo_stack.append({ "type": "group_transform", "states": states })

func _push_undo_delete(obj: EditableObjectNode) -> void:
	_undo_stack.append({
		"type": "delete",
		"tex": obj.texture_rect.texture,
		"path": obj.source_path,
		"group": obj.group_id,
		"pos": obj.position,
		"size": obj.size,
	})

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	match entry["type"]:
		"add":
			var obj: EditableObjectNode = entry["obj"]
			if is_instance_valid(obj):
				_placed[entry["group"]].erase(obj)
				object_list_panel.remove_object(obj)
				obj.queue_free()
			_selected_objects.erase(obj)
			transform_panel.refresh(_primary_selected())
		"transform":
			var obj = entry["obj"]
			if is_instance_valid(obj):
				obj.position = entry["pos"]
				obj.size = entry["size"]
				obj._sync_rect_size()
		"group_transform":
			for state in entry["states"]:
				var gobj = state["obj"]
				if is_instance_valid(gobj):
					gobj.position = state["pos"]
					gobj.size = state["size"]
					gobj._sync_rect_size()
			transform_panel.refresh(_primary_selected())
		"delete":
			var prev_group := _active_group
			_active_group = entry["group"]
			var restored := _place_object(entry["tex"], entry["pos"], entry["size"], entry["path"])
			_active_group = prev_group
			# _place_object already set correct local position for assembly children
			var parent_ctrl := restored.get_parent() as Control
			if parent_ctrl == objects_container:
				restored.position = entry["pos"]
			elif parent_ctrl != null:
				restored.position = (entry["pos"] as Vector2) - parent_ctrl.global_position
			_update_object_interactivity()
	_dirty = not _undo_stack.is_empty()

# --- Upload ---

func _on_save_pressed() -> void:
	_save_layout()

func _on_file_dialog_files_selected(paths: PackedStringArray) -> void:
	for path in paths:
		_on_file_dropped(path)

func _on_file_dropped(os_path: String) -> void:
	var ext := os_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp", "gif"]:
		return
	var filename := os_path.get_file()
	var dest_dir := "res://assets/" + (GROUP_FOLDERS.get(_active_group, _active_group) as String) + "/"
	var dest_res := dest_dir + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir))
	if ext == "gif":
		DirAccess.copy_absolute(os_path, ProjectSettings.globalize_path(dest_res))
		var tex := GifLoader.load_gif(dest_res)
		if tex == null:
			return
		_pending_object = tex
		_pending_path = dest_res
	else:
		var img := Image.load_from_file(os_path)
		if img == null:
			return
		img.save_png(ProjectSettings.globalize_path(dest_res))
		_pending_object = ImageTexture.create_from_image(img)
		_pending_path = dest_res

# --- Open/Close ---

func _request_close() -> void:
	if _dirty:
		unsaved_dialog.popup_centered()
	else:
		_close()

func _close() -> void:
	_selection_locked = false
	_is_open = false
	_set_edit_ui_visible(false)
	_pending_object = null
	_select_objects([])
	_update_object_interactivity()
	if _shelf_node and _shelf_node.has_method("set_edit_mode"):
		_shelf_node.set_edit_mode(false)
	for child in objects_container.get_children():
		if child.has_method("refresh_layout"):
			child.refresh_layout()
	get_tree().paused = false

func _on_dialog_save() -> void:
	_save_layout()
	unsaved_dialog.hide()
	_close()

func _on_dialog_discard() -> void:
	_dirty = false
	unsaved_dialog.hide()
	_close()

func _on_dialog_cancel() -> void:
	unsaved_dialog.hide()

# --- Persistence ---

func _save_layout() -> void:
	# Only normalize z_indices for non-assembly groups (screen, user).
	# Assembly groups (weaponry/defense/power_core) use explicit local z_index:
	# spaceship=0, above hull=positive, below hull=negative — must be preserved as-is.
	for group in GROUPS:
		if group in ASSEMBLY_GROUPS:
			continue
		var indexed: Array = []
		for i in _placed[group].size():
			if is_instance_valid(_placed[group][i]):
				indexed.append({"obj": _placed[group][i], "i": i})
		indexed.sort_custom(func(a, b) -> bool:
			if a["obj"].z_index != b["obj"].z_index:
				return a["obj"].z_index > b["obj"].z_index
			return a["i"] < b["i"]
		)
		for k in indexed.size():
			(indexed[k]["obj"] as EditableObjectNode).z_index = indexed.size() - 1 - k
	_sort_canvas_z_order()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 2)
	for group in GROUPS:
		var list: Array[Dictionary] = []
		for obj in _placed[group]:
			if is_instance_valid(obj):
				# Skip thrust objects (thrust.png, auto.gif, manual.gif) in weaponry — they belong in power_core
				var base: String = obj.source_path.get_file().get_basename().to_lower()
				if group == "weaponry" and base in ["thrust", "auto", "manual"]:
					continue
				list.append(obj.get_state())
		cfg.set_value("layout", group, list)
	if cfg.save(LAYOUT_PATH) == OK:
		_dirty = false

func _reset_screen_group() -> void:
	# Xóa toàn bộ assembly groups
	for g in ASSEMBLY_GROUPS:
		for obj in _placed[g].duplicate():
			if is_instance_valid(obj):
				object_list_panel.remove_object(obj)
				obj.queue_free()
		_placed[g].clear()
	var new_sel: Array = []
	for o in _selected_objects:
		if is_instance_valid(o) and o.group_id not in ASSEMBLY_GROUPS:
			new_sel.append(o)
	_selected_objects = new_sel

	# Reload từ preset (vị trí đã căn chỉnh kỹ, không bị ghi đè bởi Save thường)
	var cfg := ConfigFile.new()
	var prev_group := _active_group
	if cfg.load(PRESET_LAYOUT_PATH) == OK:
		for g in ASSEMBLY_GROUPS:
			_active_group = g
			for entry in cfg.get_value("layout", g, []):
				if entry.get("path", "") == GROUP_LAYER_MARKER:
					continue
				var tex := _load_tex(entry["path"])
				if tex:
					var obj := _place_object(tex, Vector2.ZERO, entry["size"], entry["path"], true)
					obj.position = entry["pos"]
					obj.z_index = entry.get("z_index", 0)
					obj.layer_visible = entry.get("layer_visible", true)
					obj.visible = obj.layer_visible
					if obj.texture_rect:
						obj.texture_rect.flip_h = entry.get("flip_h", false)
					obj.display_name = entry.get("display_name", "")
					if entry.get("blend_mode", 0) == 1:
						obj.set_screen_blend(true)
	else:
		for g in ASSEMBLY_GROUPS:
			_active_group = g
			_auto_load_group(g)
	_active_group = prev_group

	_reparent_assembly_objects()
	_undo_stack.clear()
	_dirty = false
	_apply_weapons_visibility()
	transform_panel.refresh(null)
	_update_object_interactivity()

func _load_tex(res_path: String) -> Texture2D:
	if res_path == GROUP_LAYER_MARKER:
		return _make_group_layer_texture()
	if res_path.get_extension().to_lower() == "gif":
		return GifLoader.load_gif(res_path)
	if res_path.begins_with(SHELF_START_PREFIX) or res_path.begins_with(SHELF_END_PREFIX):
		return _load_shelf_marker_tex(res_path)
	var tex := load(res_path) as Texture2D
	if tex:
		return tex
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs_path)
	if img:
		return ImageTexture.create_from_image(img)
	return null

## Loads the upgrade icon for a shelf start/end marker path.
## End markers are tinted red so they're visually distinct in the object list.
func _load_shelf_marker_tex(marker_path: String) -> Texture2D:
	var is_end := marker_path.begins_with(SHELF_END_PREFIX)
	var prefix := SHELF_END_PREFIX if is_end else SHELF_START_PREFIX
	var upgrade_id: String = marker_path.trim_prefix(prefix).trim_suffix("__")
	if not UpgradeManager.UPGRADES.has(upgrade_id):
		return null
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]
	var tab: String = data.get("tab", "weaponry")
	var folder: String = "res://assets/sprites/comments/" if tab == "defense" \
						 else "res://assets/sprites/upgrades/"
	var icon_tex := load(folder + String(data["icon"])) as Texture2D
	if icon_tex == null:
		return null
	if not is_end:
		return icon_tex
	var img := icon_tex.get_image()
	if img == null:
		return icon_tex
	img = img.duplicate()
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r, c.g * 0.2, c.b * 0.2, c.a * 0.55))
	return ImageTexture.create_from_image(img)

func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	_layout_version = int(cfg.get_value("meta", "version", 1))
	var prev_group := _active_group
	for group in GROUPS:
		var list = cfg.get_value("layout", group, [])
		_active_group = group
		for entry in list:
			if entry.get("path", "") == GROUP_LAYER_MARKER:
				continue  # Skip old group layer objects
			var tex := _load_tex(entry["path"])
			if tex:
				var obj := _place_object(tex, Vector2.ZERO, entry["size"], entry["path"], true)
				obj.position = entry["pos"]
				obj.z_index = entry.get("z_index", 0)
				obj.layer_visible = entry.get("layer_visible", true)
				obj.visible = obj.layer_visible
				if obj.texture_rect:
					obj.texture_rect.flip_h = entry.get("flip_h", false)
				obj.display_name = entry.get("display_name", "")
				if entry.get("blend_mode", 0) == 1:
					obj.set_screen_blend(true)
		_placed[group].sort_custom(func(a, b): return a.z_index > b.z_index)
		var n: int = _placed[group].size()
		for i in n:
			if is_instance_valid(_placed[group][i]):
				_placed[group][i].z_index = n - 1 - i
	_active_group = prev_group
	_update_object_interactivity()
	_reparent_assembly_objects()
	_sort_canvas_z_order()
	_undo_stack.clear()
	_dirty = false
	_layout_loaded = true
	WeaponManager.sync_from_canvas(_placed.get("weaponry", []))
