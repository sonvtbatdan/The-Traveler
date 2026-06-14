extends CanvasLayer

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const LAYOUT_PATH        := "res://default_layout.cfg"
const PRESET_LAYOUT_PATH := "res://preset_layout.cfg"
const GROUPS          := ["screen", "weaponry", "hud"]   # "weaponry" holds the spaceship + wings + gun mounts
const ASSEMBLY_GROUPS := []  # kept for locked _save_layout / _load_layout — no assembly groups remain
const GROUP_FOLDERS := {
	"screen":   "screen",
	"weaponry": "weaponry",
	"hud":      "hud",
}
# SpaceScreen position and default tile size (2048×2048 image at scale 1.0 → 700×700px tile)
const SCREEN_ORIGIN  := Vector2(15.0, 8.0)
const SCREEN_TILE_SZ := 700.0

# Sentinel source_path for the synthetic Group Layer object.
# Pinned at the top of each group's list; moving/resizing it propagates to
# all other objects in the group. Texture is generated procedurally.
const GROUP_LAYER_MARKER       := "res://__group_layer__"
const GROUP_LAYER_DEFAULT_SIZE := 120.0
const GROUP_LAYER_DEFAULT_POS  := Vector2(20.0, 20.0)

# Kept for _load_tex() path guard — never populated after assembly groups removed.
const SHELF_START_PREFIX := "res://__shelf_start_"
const SHELF_END_PREFIX   := "res://__shelf_end_"

@onready var objects_container: Control = $ObjectsContainer
@onready var dim_overlay: ColorRect     = $DimOverlay
@onready var side_panel: Panel          = $SidePanel
@onready var title_bar: Panel           = $SidePanel/VBox/TitleBar
@onready var object_list_panel: Panel   = $SidePanel/VBox/TopHBox/ObjectListPanel
@onready var file_dialog: FileDialog    = $FileDialog
@onready var unsaved_dialog: Window     = $UnsavedDialog

@onready var btn_screen: Button = $SidePanel/VBox/TopHBox/ButtonsColumn/ScreenGroupBtn
@onready var btn_hud: Button    = $SidePanel/VBox/TopHBox/ButtonsColumn/HudBtn
@onready var btn_save: Button   = $SidePanel/VBox/TopHBox/ButtonsColumn/SaveBtn
@onready var transform_panel    = $SidePanel/VBox/TransformPanel

signal gameplay_mode_changed(is_gameplay: bool)

var _active_group := "screen"
var _shelf_node: Node = null  # referenced by locked _close() — kept as null
var _is_open := false
var _dirty := false
var _pending_object: Texture2D = null
var _pending_path := ""
var _last_gp_emit: bool = true
var _selected_objects: Array = []

var _undo_stack: Array[Dictionary] = []
var _placed: Dictionary = {}  # group -> Array[EditableObjectNode]
var _group_layer_prev_state: Dictionary = {}  # group -> {pos, size}
var _group_drag_started: Dictionary = {}      # group -> bool

# SidePanel drag-to-move state.
var _dragging_panel: bool  = false
var _drag_offset: Vector2  = Vector2.ZERO
var _selection_locked      := false

var _canvas_dragging         := false
var _canvas_drag_mouse_prev  := Vector2.ZERO
var _canvas_drag_undo_pushed := false
var _layout_loaded           := false
var _layout_version: int     = 1
var _pre_drag_states: Dictionary = {}

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("edit_mode_ctrl")
	for g in GROUPS:
		_placed[g] = []
	object_list_panel.row_selected.connect(_on_list_row_selected)
	object_list_panel.file_dropped.connect(_on_file_dropped)
	object_list_panel.z_indices_changed.connect(_sort_canvas_z_order)
	object_list_panel.order_changed.connect(func(_a: int, _b: int) -> void: _dirty = true)
	title_bar.gui_input.connect(_on_title_bar_input)
	object_list_panel.group_layer_visibility_toggled.connect(_on_group_layer_visibility_toggled)
	object_list_panel.row_context_action.connect(_on_context_action)
	object_list_panel.display_name_changed.connect(func(_obj: EditableObjectNode): _dirty = true)
	btn_save.pressed.connect(_on_save_pressed)
	btn_screen.pressed.connect(func() -> void: _set_group("screen"))
	btn_hud.pressed.connect(func() -> void: _set_group("hud"))
	unsaved_dialog.get_node("VBox/BtnRow/SaveBtn").pressed.connect(_on_dialog_save)
	unsaved_dialog.get_node("VBox/BtnRow/DiscardBtn").pressed.connect(_on_dialog_discard)
	unsaved_dialog.get_node("VBox/BtnRow/CancelBtn").pressed.connect(_on_dialog_cancel)
	file_dialog.files_selected.connect(_on_file_dialog_files_selected)
	transform_panel.connect("transform_changed", _on_transform_live)
	_set_edit_ui_visible(false)
	_load_layout()
	_auto_load_all_groups()

func _set_edit_ui_visible(v: bool) -> void:
	dim_overlay.visible = v
	side_panel.visible = v
	if not v:
		_dragging_panel = false
		_canvas_dragging = false

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
				if not event.echo:
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
		_set_edit_ui_visible(true)
		for child in objects_container.get_children():
			if child.has_method("reset_to_origin"):
				child.reset_to_origin()
		_set_group(_active_group)
		get_tree().paused = true
	else:
		_request_close()

# --- Group ---

func _set_group(group: String) -> void:
	_selection_locked = false
	_active_group = group
	_auto_load_group(group)
	object_list_panel.set_group_label(group)
	object_list_panel.refresh(_placed.get(group, []))
	_update_group_buttons()
	_update_object_interactivity()
	_pending_object = null
	_select_objects([])

func _auto_load_all_groups() -> void:
	if _layout_loaded:
		_pin_group_layers_to_top()
	else:
		_init_group_z_indices()
	_update_object_interactivity()
	_sort_canvas_z_order()

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
	for y in side:
		for x in side:
			if x < 2 or x >= side - 2 or y < 2 or y >= side - 2:
				img.set_pixel(x, y, border)
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

func _auto_load_group(_group: String) -> void:
	return  # DISABLED: autoload from folders entirely — rely on config files only

## Returns the center position of an object matching source_path. Used by upgrade_shelf.
func get_stat_object_pos(source_path: String) -> Vector2:
	for group in GROUPS:
		for obj in _placed.get(group, []):
			if is_instance_valid(obj) and obj.source_path == source_path:
				return obj.position + obj.size * 0.5
	return Vector2.ZERO

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
	btn_screen.button_pressed = (_active_group == "screen")
	btn_hud.button_pressed    = (_active_group == "hud")

func _update_object_interactivity() -> void:
	var is_gp := not _is_open
	if is_gp != _last_gp_emit:
		_last_gp_emit = is_gp
		gameplay_mode_changed.emit(is_gp)
	for group in GROUPS:
		for obj in _placed[group]:
			if not is_instance_valid(obj):
				continue
			if _is_open:
				obj.set_gameplay_mode(false)
				var active: bool = (group == _active_group) or obj.is_group_layer()
				obj.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
			else:
				obj.set_gameplay_mode(true)
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
		return
	_select_objects([obj])
	if obj in _selected_objects:
		_pre_drag_states[obj] = {"pos": obj.position, "size": obj.size}

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
	_dirty = true

# Sync ObjectsContainer's tree order to match every object's z_index.
func _sort_canvas_z_order() -> void:
	var top_objs: Array = []
	for group in ["screen", "hud"]:
		for obj in _placed.get(group, []):
			if is_instance_valid(obj) and obj.get_parent() == objects_container:
				top_objs.append(obj)
	top_objs.sort_custom(func(a: EditableObjectNode, b: EditableObjectNode) -> bool:
		var ka: int = GROUPS.find(a.group_id) * 10000 + a.z_index
		var kb: int = GROUPS.find(b.group_id) * 10000 + b.z_index
		return ka < kb
	)
	for i in top_objs.size():
		objects_container.move_child(top_objs[i], i)

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
			if obj.position != pre["pos"] or obj.size != pre["size"]:
				_undo_stack.append({"type": "transform", "obj": obj, "pos": pre["pos"], "size": pre["size"]})
			_pre_drag_states.erase(obj)
	_dirty = true
	if obj in _selected_objects:
		transform_panel.refresh(_primary_selected())

func _on_group_layer_motion(obj: EditableObjectNode) -> void:
	if not obj.is_group_layer():
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
			restored.position = entry["pos"]
			_active_group = prev_group
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
	# Only normalize z_indices for non-assembly groups (screen, hud).
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

func _reparent_assembly_objects() -> void:
	pass  # assembly groups removed

func _load_tex(res_path: String) -> Texture2D:
	if res_path == GROUP_LAYER_MARKER:
		return _make_group_layer_texture()
	if res_path.get_extension().to_lower() == "gif":
		return GifLoader.load_gif(res_path)
	if res_path.begins_with(SHELF_START_PREFIX) or res_path.begins_with(SHELF_END_PREFIX):
		return null
	var tex := load(res_path) as Texture2D
	if tex:
		return tex
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs_path)
	if img:
		return ImageTexture.create_from_image(img)
	return null

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
