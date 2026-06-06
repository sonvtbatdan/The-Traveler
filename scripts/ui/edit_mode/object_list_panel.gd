extends Panel

signal row_selected(canvas_obj: EditableObjectNode)
signal order_changed(from_idx: int, to_idx: int)
signal file_dropped(path: String)
signal z_indices_changed
signal group_layer_visibility_toggled(group_id: String, visible: bool)
signal row_context_action(action: String, canvas_obj: EditableObjectNode)
signal display_name_changed(canvas_obj: EditableObjectNode)

const ROW_HEIGHT := 56.0
const THUMB_SIZE := 48.0
const GROUP_LAYER_MARKER := "res://__group_layer__"

@onready var title_label: Label = $VBox/TitleLabel
@onready var item_vbox: VBoxContainer = $VBox/Scroll/ItemList

var current_group := ""
var _rows: Array = []       # [{row, canvas_obj, ?is_spaceship}]
var _selected_row: Control = null
var _dragging_row: Control = null
var _is_assembly_mode: bool = false

var _context_menu: PopupMenu = null

func _ready() -> void:
	_build_context_menu()

func _build_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Mirror", 0)
	_context_menu.add_item("Rename", 1)
	_context_menu.add_item("Copy", 2)
	_context_menu.add_separator()
	_context_menu.add_item("Delete", 3)
	_context_menu.id_pressed.connect(_on_context_item_pressed)
	call_deferred("add_child", _context_menu)

func _on_context_item_pressed(id: int) -> void:
	# Lấy object từ row hiện tại khi context menu show
	var obj: EditableObjectNode = null
	if _selected_row != null:
		for entry in _rows:
			if entry["row"] == _selected_row:
				obj = entry["canvas_obj"] as EditableObjectNode
				break

	if obj == null or not is_instance_valid(obj):
		return

	match id:
		0:  # Mirror
			if obj.texture_rect:
				obj.texture_rect.flip_h = not obj.texture_rect.flip_h
		1:  # Rename
			_show_rename_dialog(obj)
		2:  # Copy
			row_context_action.emit("copy", obj)
		3:  # Delete
			row_context_action.emit("delete", obj)

func _show_rename_dialog(obj: EditableObjectNode) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Rename Layer"
	dialog.size = Vector2i(320, 140)
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

	var label := Label.new()
	label.text = "Enter new name:"
	vbox.add_child(label)

	var text_edit := LineEdit.new()
	text_edit.text = obj.display_name if not obj.display_name.is_empty() else obj.source_path.get_file().get_basename()
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.focus_mode = Control.FOCUS_ALL
	vbox.add_child(text_edit)

	dialog.confirmed.connect(func():
		var new_name := text_edit.text.strip_edges()
		if not new_name.is_empty():
			obj.display_name = new_name
			for entry in _rows:
				if entry["canvas_obj"] == obj:
					var row: Control = entry["row"]
					var hbox := row.get_child(0) as HBoxContainer
					if hbox and hbox.get_child_count() > 1:
						var lbl := hbox.get_child(1) as Label
						if lbl:
							lbl.text = new_name
					break
			display_name_changed.emit(obj)
	)

	dialog.popup_centered()
	text_edit.grab_focus()
	text_edit.select_all()

# --- OS drag-drop (import) ---

func _can_drop_data(_pos: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("files")

func _drop_data(_pos: Vector2, data) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		for path in data["files"]:
			file_dropped.emit(path)

# --- Public API ---

func set_group_label(group: String) -> void:
	current_group = group
	title_label.text = "OBJECT LIST  [%s]" % group.to_upper()

func refresh(placed_objects: Array) -> void:
	_clear()
	# Pin the Group Layer row at the top.
	var pinned: EditableObjectNode = null
	for obj in placed_objects:
		if is_instance_valid(obj) and _is_pinned(obj):
			pinned = obj
			break
	if pinned != null:
		_append_row(pinned)
	# Sort non-pinned by z_index descending so the list order always matches
	# the saved visual layer order, regardless of _placed[] array order.
	var non_pinned: Array = []
	for obj in placed_objects:
		if is_instance_valid(obj) and not _is_pinned(obj):
			non_pinned.append(obj)
	non_pinned.sort_custom(func(a, b): return a.z_index > b.z_index)
	for obj in non_pinned:
		_append_row(obj)
	# Only normalize if there are duplicate z_indices (e.g. newly added objects with z=0).
	# Skipping normalization preserves z_indices of hidden objects not in this list.
	var _z_seen: Dictionary = {}
	var _has_dupes := false
	for entry: Dictionary in _rows:
		var o: EditableObjectNode = entry["canvas_obj"]
		if is_instance_valid(o):
			if _z_seen.has(o.z_index):
				_has_dupes = true
				break
			_z_seen[o.z_index] = true
	if _has_dupes:
		_update_z_indices()

func add_placed_object(obj: EditableObjectNode) -> void:
	if _is_assembly_mode and not _is_pinned(obj):
		_append_assembly_row(obj)
	else:
		_append_row(obj)
		if not _is_pinned(obj):
			_move_pinned_to_top()
	_update_z_indices()

func _is_pinned(obj: EditableObjectNode) -> bool:
	return obj != null and obj.source_path == GROUP_LAYER_MARKER

func _move_pinned_to_top() -> void:
	for i in _rows.size():
		var obj: EditableObjectNode = _rows[i]["canvas_obj"]
		if is_instance_valid(obj) and _is_pinned(obj) and i != 0:
			item_vbox.move_child(_rows[i]["row"], 0)
			var entry: Dictionary = _rows[i]
			_rows.remove_at(i)
			_rows.insert(0, entry)
			return

func remove_object(obj: EditableObjectNode) -> void:
	for i in _rows.size():
		if _rows[i]["canvas_obj"] == obj:
			_rows[i]["row"].queue_free()
			_rows.remove_at(i)
			break
	_update_z_indices()

func select_object(obj: EditableObjectNode) -> void:
	highlight_objects([obj])

func highlight_objects(objects: Array) -> void:
	for entry in _rows:
		_set_row_highlight(entry["row"], entry["canvas_obj"] in objects)
	_selected_row = null
	for entry in _rows:
		if entry["canvas_obj"] in objects:
			_selected_row = entry["row"]
			break

# --- Build rows ---

func _append_row(obj: EditableObjectNode) -> void:
	var tex: Texture2D = obj.texture_rect.texture if obj.texture_rect.texture else null
	var row := _make_row(obj, tex)
	item_vbox.add_child(row)
	var hbox_ref := row.get_child(0) as HBoxContainer
	var eye_ref := hbox_ref.get_child(hbox_ref.get_child_count() - 1) as Button
	_rows.append({"row": row, "canvas_obj": obj, "eye_btn": eye_ref})

func _make_row(obj: EditableObjectNode, tex: Texture2D) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var thumb := TextureRect.new()
	thumb.texture = tex
	thumb.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(thumb)

	var lbl := Label.new()
	var _display_name: String
	if not obj.display_name.is_empty():
		_display_name = obj.display_name
	elif obj.source_path == GROUP_LAYER_MARKER:
		_display_name = "Group Layer"
	elif obj.source_path != "":
		_display_name = obj.source_path.get_file().get_basename()
	else:
		_display_name = "object"
	lbl.text = _display_name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	var eye_btn := Button.new()
	eye_btn.toggle_mode = true
	eye_btn.button_pressed = obj.layer_visible
	eye_btn.text = "👁"
	eye_btn.flat = true
	eye_btn.custom_minimum_size = Vector2(30, 0)
	eye_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	eye_btn.modulate = Color.WHITE if obj.layer_visible else Color(1.0, 1.0, 1.0, 0.3)
	if obj.is_group_layer():
		eye_btn.toggled.connect(func(pressed: bool) -> void:
			obj.layer_visible = pressed
			eye_btn.modulate = Color.WHITE if pressed else Color(1.0, 1.0, 1.0, 0.3)
			group_layer_visibility_toggled.emit(obj.group_id, pressed)
		)
	else:
		eye_btn.toggled.connect(func(pressed: bool) -> void:
			obj.layer_visible = pressed
			obj.visible = pressed
			eye_btn.modulate = Color.WHITE if pressed else Color(1.0, 1.0, 1.0, 0.3)
		)
	hbox.add_child(eye_btn)

	panel.gui_input.connect(_on_row_gui_input.bind(panel))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel

# --- Drag reorder (tracked at Panel level so mouse can leave the row) ---

func _input(event: InputEvent) -> void:
	if not visible or _dragging_row == null:
		return
	if event is InputEventMouseMotion:
		_check_swap()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_row = null

func _on_row_gui_input(event: InputEvent, row: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_drag(row)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var obj := _canvas_obj_for_row(row)
		if obj != null and not obj.is_group_layer():
			_select_row_node(row)
			row_selected.emit(obj)
			var mp := DisplayServer.mouse_get_position()
			_context_menu.popup(Rect2i(mp.x, mp.y, 0, 0))
			get_viewport().set_input_as_handled()

func _start_drag(row: Control) -> void:
	_dragging_row = row
	# Select the canvas object
	var canvas_obj := _canvas_obj_for_row(row)
	if canvas_obj:
		_select_row_node(row)
		row_selected.emit(canvas_obj)

func _check_swap() -> void:
	var cur_idx := _row_index(_dragging_row)
	if cur_idx < 0:
		return
	# The pinned Group Layer row never moves; spaceship row is locked in assembly mode.
	if _is_pinned(_rows[cur_idx]["canvas_obj"]):
		return
	if _rows[cur_idx].get("is_spaceship", false):
		return
	var mouse_y := get_global_mouse_position().y

	if cur_idx > 0:
		var above_idx := cur_idx - 1
		if not _is_pinned(_rows[above_idx]["canvas_obj"]):
			var above_row: Control = _rows[above_idx]["row"]
			var center := above_row.global_position.y + above_row.size.y * 0.5
			if mouse_y < center:
				_swap(cur_idx, above_idx)
				return

	if cur_idx < _rows.size() - 1:
		var below_row: Control = _rows[cur_idx + 1]["row"]
		var center := below_row.global_position.y + below_row.size.y * 0.5
		if mouse_y > center:
			_swap(cur_idx, cur_idx + 1)

func _swap(a: int, b: int) -> void:
	item_vbox.move_child(_rows[a]["row"], b)
	var tmp: Dictionary = _rows[a]
	_rows[a] = _rows[b]
	_rows[b] = tmp
	_update_z_indices()
	order_changed.emit(a, b)

# --- Z-index sync ---

func _update_z_indices() -> void:
	if _is_assembly_mode:
		_update_z_indices_assembly()
		return
	var top := _rows.size() - 1
	for i in _rows.size():
		var obj: EditableObjectNode = _rows[i]["canvas_obj"]
		if is_instance_valid(obj):
			obj.z_index = top - i   # row 0 (top of list) = highest z
	z_indices_changed.emit()

func _update_z_indices_assembly() -> void:
	var ship_idx := -1
	for i in _rows.size():
		if _rows[i].get("is_spaceship", false):
			ship_idx = i
			break
	if ship_idx < 0:
		_is_assembly_mode = false
		_update_z_indices()
		return
	# Spaceship = z_index 0 (reference, locked).
	# Items above spaceship row (i < ship_idx): local z = ship_idx - i → positive
	# Items below spaceship row (i > ship_idx): local z = ship_idx - i → negative
	# Effective render z = SHIP_ASSEMBLY_Z (100) + local_z → always above background (z=0,1)
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		if row.get("is_spaceship", false):
			continue  # locked — spaceship luôn là z=0 (SHIP_ASSEMBLY_Z handled in code)
		var obj: EditableObjectNode = row.get("canvas_obj")
		if not is_instance_valid(obj):
			continue
		obj.z_index = ship_idx - i
	z_indices_changed.emit()

# --- Selection highlight ---

func _select_row_node(row: Control) -> void:
	for entry in _rows:
		_set_row_highlight(entry["row"], entry["row"] == row)
	_selected_row = row

func _set_row_highlight(row: Control, active: bool) -> void:
	if active:
		row.add_theme_stylebox_override("panel", _highlight_style())
	else:
		row.remove_theme_stylebox_override("panel")

func _highlight_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.3, 0.6, 1.0, 0.35)
	return s

# --- Helpers ---

func _canvas_obj_for_row(row: Control) -> EditableObjectNode:
	for entry in _rows:
		if entry["row"] == row:
			return entry["canvas_obj"]
	return null

func _row_index(row: Control) -> int:
	for i in _rows.size():
		if _rows[i]["row"] == row:
			return i
	return -1

func get_selected_object() -> EditableObjectNode:
	if _selected_row == null:
		return null
	return _canvas_obj_for_row(_selected_row)

# --- Assembly mode (all 3 groups shown together) ---

func refresh_assembly(ship_eo: EditableObjectNode, all_objs: Array) -> void:
	_clear()
	_is_assembly_mode = true
	# Sort all non-ship objects by z_index descending
	var above_ship: Array = []
	var below_ship: Array = []
	for obj in all_objs:
		if not is_instance_valid(obj):
			continue
		if obj.z_index >= 0:
			above_ship.append(obj)
		else:
			below_ship.append(obj)
	above_ship.sort_custom(func(a: EditableObjectNode, b: EditableObjectNode) -> bool:
		return a.z_index > b.z_index)
	below_ship.sort_custom(func(a: EditableObjectNode, b: EditableObjectNode) -> bool:
		return a.z_index > b.z_index)
	for obj in above_ship:
		_append_assembly_row(obj)
	if ship_eo != null and is_instance_valid(ship_eo):
		_append_ship_row(ship_eo)
	for obj in below_ship:
		_append_assembly_row(obj)

func _append_ship_row(obj: EditableObjectNode) -> void:
	var tex: Texture2D = obj.texture_rect.texture if obj.texture_rect.texture else null
	var row := _make_row(obj, tex)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.20, 0.04, 0.75)
	style.border_width_left = 3
	style.border_color = Color(1.0, 0.85, 0.2, 0.9)
	row.add_theme_stylebox_override("panel", style)
	item_vbox.add_child(row)
	var hbox_ref := row.get_child(0) as HBoxContainer
	var eye_ref := hbox_ref.get_child(hbox_ref.get_child_count() - 1) as Button
	var lock_lbl := Label.new()
	lock_lbl.text = "HULL"
	lock_lbl.modulate = Color(1.0, 0.85, 0.2, 0.8)
	lock_lbl.add_theme_font_size_override("font_size", 10)
	lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox_ref.add_child(lock_lbl)
	_rows.append({"row": row, "canvas_obj": obj, "eye_btn": eye_ref, "is_spaceship": true})

func _append_assembly_row(obj: EditableObjectNode) -> void:
	var tex: Texture2D = obj.texture_rect.texture if obj.texture_rect.texture else null
	var row := _make_row(obj, tex)
	var border_color: Color
	match obj.group_id:
		"weaponry":    border_color = Color(0.3, 0.55, 1.0, 0.7)
		"defense":     border_color = Color(0.3, 1.0, 0.5, 0.7)
		"power_core":  border_color = Color(1.0, 0.6, 0.2, 0.7)
		_:             border_color = Color(0.5, 0.5, 0.5, 0.4)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(border_color.r, border_color.g, border_color.b, 0.12)
	style.border_width_left = 3
	style.border_color = border_color
	row.add_theme_stylebox_override("panel", style)
	item_vbox.add_child(row)
	var hbox_ref := row.get_child(0) as HBoxContainer
	var eye_ref := hbox_ref.get_child(hbox_ref.get_child_count() - 1) as Button
	_rows.append({"row": row, "canvas_obj": obj, "eye_btn": eye_ref})

func update_visibility_buttons() -> void:
	for entry in _rows:
		var obj: EditableObjectNode = entry["canvas_obj"]
		if not is_instance_valid(obj):
			continue
		var btn: Button = entry.get("eye_btn")
		if btn == null or not is_instance_valid(btn):
			continue
		btn.set_pressed_no_signal(obj.layer_visible)
		btn.modulate = Color.WHITE if obj.layer_visible else Color(1.0, 1.0, 1.0, 0.3)

func _clear() -> void:
	for c in item_vbox.get_children():
		c.queue_free()
	_rows.clear()
	_selected_row = null
	_dragging_row = null
	_is_assembly_mode = false
