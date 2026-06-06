extends CanvasLayer

const EditableObject  := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader       := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const GridOverlay     := preload("res://scripts/ui/boss_edit/grid_overlay.gd")
const LAYOUT_PATH     := "res://boss_layout.cfg"
const BOSSES_FOLDER   := "res://assets/bosses/"
const ASSET_PANEL_W   := 210.0
const CTRL_PANEL_W    := 224.0
const SCREEN_ORIGIN   := Vector2(270.0, 8.0)

# ── State ──────────────────────────────────────────────────────────────────────
var _is_open:        bool    = false
var _dirty:          bool    = false
var _active_boss:    String  = ""
var _all_boss_names: Array[String] = []
var _placed:         Dictionary = {}   # boss_name -> Array[EditableObjectNode]
var _selected_obj:   EditableObjectNode = null
var _boss_buttons:   Dictionary = {}   # boss_name -> Button
var _objects_container: Control = null

# Grid + fire point state
var _grid_mode:        bool       = false
var _adding_firepoint: bool       = false
var _fire_points:      Dictionary = {}  # boss_name -> Array[{pos:Vector2, id:int}]
var _selected_fp_idx:  int        = -1
var _fp_id_counter:    Dictionary = {}  # boss_name -> int (next id)
var _weapon_fire_points: Dictionary = {}  # "{boss}_{weapon_basename}" -> Array[{pos, id}]
var _wp_fp_id_counter:   Dictionary = {}  # same composite key -> int (next id)
var _fp_target_basename: String    = ""   # "" = boss main body, else weapon EO basename
var _locked_bosses: Dictionary = {}   # boss_name -> bool

# ── UI ─────────────────────────────────────────────────────────────────────────
var _dim_overlay:     ColorRect     = null
var _asset_panel:     Panel         = null   # LEFT — layers + fire points
var _asset_vbox:      VBoxContainer = null
var _fp_vbox:         VBoxContainer = null
var _ctrl_panel:      Panel         = null   # RIGHT — boss buttons + transform
var _boss_btn_vbox:   VBoxContainer = null
var _pos_x_spin:      SpinBox       = null
var _pos_y_spin:      SpinBox       = null
var _sz_w_spin:       SpinBox       = null
var _sz_h_spin:       SpinBox       = null
var _z_spin:          SpinBox       = null
var _delete_btn:      Button        = null
var _grid_btn:        Button        = null
var _add_fp_btn:      Button        = null
var _toast_label:      Label         = null
var _grid_overlay:     Control       = null
var _fp_target_label:  Label         = null
var _lock_btn:         Button        = null
var _save_confirm_dlg: ConfirmationDialog = null

# Panel drag state — each panel tracked separately
var _dragging_asset:   bool    = false
var _drag_asset_off:   Vector2 = Vector2.ZERO
var _dragging_ctrl:    bool    = false
var _drag_ctrl_off:    Vector2 = Vector2.ZERO
var _canvas_dragging:       bool    = false
var _canvas_drag_prev:      Vector2 = Vector2.ZERO
var _canvas_drag_undo_pushed: bool  = false
var _updating_spin:         bool    = false
var _aspect_ratio:          float   = 1.0
var _undo_stack: Array[Dictionary] = []

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan_bosses()
	_build_ui()
	_build_boss_buttons()
	GameManager.boost_changed.connect(_on_boost_changed)
	_set_ui_visible(false)

func setup(objects_container: Control) -> void:
	_objects_container = objects_container
	_load_layout()
	_update_gameplay_visibility()

func is_open() -> bool:
	return _is_open

# ── Folder scan ────────────────────────────────────────────────────────────────

func _scan_bosses() -> void:
	_all_boss_names.clear()
	var dir := DirAccess.open(BOSSES_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_all_boss_names.append(entry)
			if not _placed.has(entry):
				_placed[entry] = []
		entry = dir.get_next()
	dir.list_dir_end()
	_all_boss_names.sort()


func _load_frame0_tex(path: String, is_gif: bool) -> Texture2D:
	if is_gif:
		var meta_tex := GifLoader.load_gif(path)
		if meta_tex != null and meta_tex.has_meta("gif_frames"):
			var frames: Array = meta_tex.get_meta("gif_frames")
			if not frames.is_empty():
				return frames[0] as Texture2D
		return meta_tex
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

# Returns the already-loaded thumbnail texture from an EO — no disk I/O.
func _get_eo_thumbnail(eo: EditableObjectNode) -> Texture2D:
	var t := eo.texture_rect.texture
	if t != null and t.has_meta("gif_frames"):
		var frames: Array = t.get_meta("gif_frames")
		if not frames.is_empty():
			return frames[0] as Texture2D
	return t

# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_dim_overlay = ColorRect.new()
	_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.color = Color(0.0, 0.0, 0.0, 0.35)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim_overlay)

	_toast_label = Label.new()
	_toast_label.z_index = 200
	_toast_label.modulate.a = 0.0
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_toast_label.add_theme_font_size_override("font_size", 18)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.size     = Vector2(640.0, 40.0)
	_toast_label.position = Vector2(400.0, 14.0)
	add_child(_toast_label)

	_build_asset_panel()
	_build_ctrl_panel()
	_build_grid_overlay()

func _build_grid_overlay() -> void:
	_grid_overlay = GridOverlay.new()
	_grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_overlay.z_index = 50
	add_child(_grid_overlay)

# ── LEFT panel: layers + fire points ──────────────────────────────────────────

func _build_asset_panel() -> void:
	_asset_panel = Panel.new()
	_asset_panel.size     = Vector2(ASSET_PANEL_W, 730.0)
	_asset_panel.position = Vector2(20.0, 44.0)
	add_child(_asset_panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	_asset_panel.add_child(root)

	# ── LAYERS ──
	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0.0, 32.0)
	title_bar.gui_input.connect(_on_asset_title_input)
	root.add_child(title_bar)
	var tl := Label.new()
	tl.text = "LAYERS"
	tl.add_theme_font_size_override("font_size", 12)
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tl)

	var layers_scroll := ScrollContainer.new()
	layers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(layers_scroll)

	_asset_vbox = VBoxContainer.new()
	_asset_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_vbox.add_theme_constant_override("separation", 2)
	layers_scroll.add_child(_asset_vbox)

	# ── FIRE POINTS ──
	root.add_child(HSeparator.new())

	var fp_hdr := Label.new()
	fp_hdr.text = "FIRE POINTS"
	fp_hdr.add_theme_font_size_override("font_size", 11)
	fp_hdr.modulate = Color(0.60, 0.63, 0.76)
	root.add_child(fp_hdr)

	_fp_target_label = Label.new()
	_fp_target_label.text = "Target: (boss main)"
	_fp_target_label.add_theme_font_size_override("font_size", 10)
	_fp_target_label.modulate = Color(0.85, 0.80, 0.45)
	root.add_child(_fp_target_label)

	_lock_btn = Button.new()
	_lock_btn.text = "LOCK"
	_lock_btn.custom_minimum_size = Vector2(0.0, 22.0)
	_lock_btn.add_theme_font_size_override("font_size", 10)
	_lock_btn.pressed.connect(_on_lock_pressed)
	root.add_child(_lock_btn)

	_save_confirm_dlg = ConfirmationDialog.new()
	_save_confirm_dlg.ok_button_text = "Overwrite"
	add_child(_save_confirm_dlg)

	var fp_scroll := ScrollContainer.new()
	fp_scroll.custom_minimum_size = Vector2(0.0, 130.0)
	fp_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(fp_scroll)

	_fp_vbox = VBoxContainer.new()
	_fp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fp_vbox.add_theme_constant_override("separation", 2)
	fp_scroll.add_child(_fp_vbox)

# ── RIGHT panel: boss buttons + transform + actions ────────────────────────────

func _build_ctrl_panel() -> void:
	_ctrl_panel = Panel.new()
	_ctrl_panel.size     = Vector2(CTRL_PANEL_W, 730.0)
	_ctrl_panel.position = Vector2(20.0 + ASSET_PANEL_W + 8.0, 44.0)
	add_child(_ctrl_panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	_ctrl_panel.add_child(root)

	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0.0, 34.0)
	title_bar.gui_input.connect(_on_ctrl_title_input)
	root.add_child(title_bar)
	var tl := Label.new()
	tl.text = "BOSS EDIT  [F5]"
	tl.add_theme_font_size_override("font_size", 13)
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tl)

	_add_section(root, "BOSSES")
	var boss_scroll := ScrollContainer.new()
	boss_scroll.custom_minimum_size = Vector2(0.0, 76.0)
	boss_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(boss_scroll)
	_boss_btn_vbox = VBoxContainer.new()
	_boss_btn_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_btn_vbox.add_theme_constant_override("separation", 2)
	boss_scroll.add_child(_boss_btn_vbox)

	root.add_child(HSeparator.new())
	_add_section(root, "TRANSFORM")

	var pos_row := HBoxContainer.new()
	root.add_child(pos_row)
	_pos_x_spin = _spin(pos_row, "X", -3000.0, 3000.0)
	_pos_y_spin = _spin(pos_row, "Y", -3000.0, 3000.0)

	var sz_row := HBoxContainer.new()
	root.add_child(sz_row)
	_sz_w_spin = _spin(sz_row, "W", 1.0, 2000.0, _on_w_spin_changed)
	_sz_h_spin = _spin(sz_row, "H", 1.0, 2000.0, _on_h_spin_changed)

	var z_row := HBoxContainer.new()
	root.add_child(z_row)
	_z_spin = _spin(z_row, "Z", -500.0, 500.0)

	root.add_child(HSeparator.new())

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 3)
	root.add_child(mode_row)

	_grid_btn = Button.new()
	_grid_btn.text = "Grid"
	_grid_btn.toggle_mode = true
	_grid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_btn.pressed.connect(_toggle_grid_mode)
	mode_row.add_child(_grid_btn)

	_add_fp_btn = Button.new()
	_add_fp_btn.text = "Add FP"
	_add_fp_btn.toggle_mode = true
	_add_fp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_fp_btn.pressed.connect(_toggle_adding_firepoint)
	mode_row.add_child(_add_fp_btn)

	root.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 3)
	root.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_layout)
	btn_row.add_child(save_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.disabled = true
	_delete_btn.pressed.connect(_delete_selected)
	btn_row.add_child(_delete_btn)

	var close_btn := Button.new()
	close_btn.text = "Close  [F5]"
	close_btn.pressed.connect(_request_close)
	root.add_child(close_btn)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.60, 0.63, 0.76)
	parent.add_child(lbl)

func _spin(parent: HBoxContainer, prefix: String, mn: float, mx: float, cb: Callable = Callable()) -> SpinBox:
	var lbl := Label.new()
	lbl.text = prefix + ":"
	lbl.custom_minimum_size = Vector2(18.0, 0.0)
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = 1.0
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cb.is_valid():
		sb.value_changed.connect(func(_v: float) -> void: cb.call())
	else:
		sb.value_changed.connect(func(_v: float) -> void: _on_spin_changed())
	parent.add_child(sb)
	return sb

func _build_boss_buttons() -> void:
	for child in _boss_btn_vbox.get_children():
		child.queue_free()
	_boss_buttons.clear()
	for boss_name: String in _all_boss_names:
		var btn := Button.new()
		btn.text = boss_name.capitalize()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_set_active_boss.bind(boss_name))
		_boss_btn_vbox.add_child(btn)
		_boss_buttons[boss_name] = btn

# ── Layer list (left panel — lists placed objects, click to select) ────────────

func _refresh_layer_list() -> void:
	for child in _asset_vbox.get_children():
		child.queue_free()
	for eo in _placed.get(_active_boss, []):
		if is_instance_valid(eo):
			_asset_vbox.add_child(_make_layer_row(eo))

func _make_layer_row(eo: EditableObjectNode) -> Control:
	var is_selected: bool = (eo == _selected_obj)
	var is_gif: bool = eo.source_path.get_extension().to_lower() == "gif"

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 46.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.55, 0.95, 0.45) if is_selected else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40.0, 40.0)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = _get_eo_thumbnail(eo)
	hbox.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = eo.source_path.get_file().get_basename()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.clip_text = true
	info.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = "[GIF]" if is_gif else "[PNG]"
	type_lbl.add_theme_font_size_override("font_size", 9)
	type_lbl.modulate = Color(0.55, 0.55, 0.70)
	info.add_child(type_lbl)

	var cap_eo := eo
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			_select_obj(cap_eo)
			var base_eo := _get_base_eo(_active_boss)
			if cap_eo != base_eo:
				_fp_target_basename = cap_eo.source_path.get_file().get_basename().to_lower()
			else:
				_fp_target_basename = ""
			_selected_fp_idx = -1
			_refresh_fp_list()
			_update_grid_overlay()
	)
	return row

# ── Open / Close ───────────────────────────────────────────────────────────────

func toggle() -> void:
	if not _is_open:
		_is_open = true
		_grid_overlay.is_edit_open = true
		_set_ui_visible(true)
		get_tree().paused = true
		_update_all_boss_interactivity()
		if _active_boss.is_empty() and not _all_boss_names.is_empty():
			_set_active_boss(_all_boss_names[0])
		else:
			_set_active_boss(_active_boss)
	else:
		_request_close()

func _request_close() -> void:
	if _dirty:
		_save_layout()
	_close()

func _close() -> void:
	_is_open = false
	_grid_mode = false
	_adding_firepoint = false
	_fp_target_basename = ""
	_grid_btn.button_pressed  = false
	_add_fp_btn.button_pressed = false
	_grid_overlay.show_grid    = false
	_grid_overlay.is_edit_open = false
	_select_fp(-1)
	_set_ui_visible(false)
	_select_obj(null)
	_update_all_boss_interactivity()
	_update_gameplay_visibility()
	get_tree().paused = false

func _set_ui_visible(v: bool) -> void:
	_dim_overlay.visible  = v
	_asset_panel.visible  = v
	_ctrl_panel.visible   = v
	if not v:
		_dragging_asset  = false
		_dragging_ctrl   = false
		_canvas_dragging = false

# ── Active boss ────────────────────────────────────────────────────────────────

func _set_active_boss(boss_name: String) -> void:
	if boss_name.is_empty():
		return
	_active_boss = boss_name
	_fp_target_basename = ""
	if _placed.get(boss_name, []).is_empty():
		_load_or_create_boss(boss_name)
	if not _fire_points.has(boss_name):
		_fire_points[boss_name] = []
	_select_obj(null)
	_selected_fp_idx = -1
	_update_all_boss_interactivity()
	_update_grid_overlay()
	_refresh_fp_list()
	_update_lock_btn()
	for name: String in _boss_buttons:
		(_boss_buttons[name] as Button).button_pressed = (name == boss_name)

func _load_or_create_boss(boss_name: String) -> void:
	if not _placed.get(boss_name, []).is_empty():
		return
	var folder := BOSSES_FOLDER + boss_name + "/"
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	# Collect all image files sorted alphabetically
	var files: Array[String] = []
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir():
			var ext := file.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "gif"]:
				files.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	files.sort()
	# boss_name.gif (or first file) becomes the base; all others are weapon EOs
	var base_file := boss_name + ".gif"
	if not files.has(base_file) and not files.is_empty():
		base_file = files[0]
	var base_path := folder + base_file
	var base_tex := _load_full_tex(base_path)
	if base_tex != null:
		# Calculate base size maintaining aspect ratio (120px width)
		var base_w := float(base_tex.get_width())
		var base_h := float(base_tex.get_height())
		var base_aspect := 1.0
		if base_w > 0.0 and base_h > 0.0:
			base_aspect = base_w / base_h
		var base_sz := Vector2(120.0, 120.0 / base_aspect)
		_place_base_eo(boss_name, base_tex, base_path, Vector2(570.0, 80.0), base_sz)
	var wi := 0
	for fname: String in files:
		if fname == base_file:
			continue
		var wtex := _load_full_tex(folder + fname)
		if wtex != null:
			# Calculate weapon size maintaining aspect ratio (40px width)
			var w_w := float(wtex.get_width())
			var w_h := float(wtex.get_height())
			var w_aspect := 1.0
			if w_w > 0.0 and w_h > 0.0:
				w_aspect = w_w / w_h
			var w_sz := Vector2(40.0, 40.0 / w_aspect)
			_place_weapon_eo(boss_name, wtex, folder + fname,
				Vector2(-30.0 + wi * 38.0, 10.0), w_sz)
			wi += 1

func _place_base_eo(boss_name: String, tex: Texture2D, path: String,
		pos: Vector2, sz: Vector2) -> EditableObjectNode:
	if _objects_container == null:
		return null
	var eo: EditableObjectNode = EditableObject.instantiate()
	eo.group_id    = "boss_" + boss_name
	eo.source_path = path
	_objects_container.add_child(eo)
	eo.init(tex, pos, sz)
	eo.z_index     = 110
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eo.object_clicked.connect(_on_canvas_object_clicked)
	eo.transform_ended.connect(_on_transform_ended)
	eo.transform_motion.connect(_on_transform_motion)
	_placed[boss_name].push_front(eo)
	return eo

func _place_weapon_eo(boss_name: String, tex: Texture2D, path: String,
		rel_pos: Vector2, sz: Vector2) -> EditableObjectNode:
	var base_eo := _get_base_eo(boss_name)
	if base_eo == null:
		return null
	var eo: EditableObjectNode = EditableObject.instantiate()
	eo.group_id    = "boss_" + boss_name
	eo.source_path = path
	base_eo.add_child(eo)
	eo.init(tex, Vector2.ZERO, sz)
	eo.position    = rel_pos
	eo.z_index     = 1
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eo.object_clicked.connect(_on_canvas_object_clicked)
	eo.transform_ended.connect(_on_transform_ended)
	eo.transform_motion.connect(_on_transform_motion)
	_placed[boss_name].append(eo)
	return eo

func _get_base_eo(boss_name: String) -> EditableObjectNode:
	var list: Array = _placed.get(boss_name, [])
	return list[0] as EditableObjectNode if not list.is_empty() else null

# ── Selection & transform ──────────────────────────────────────────────────────

func _select_obj(obj: EditableObjectNode) -> void:
	if is_instance_valid(_selected_obj):
		_selected_obj.selected = false
	_selected_obj = obj
	if is_instance_valid(obj):
		obj.selected = true
		_aspect_ratio = obj._aspect_ratio
	else:
		_aspect_ratio = 1.0
	_delete_btn.disabled = not is_instance_valid(obj)
	_refresh_transform_panel()
	_refresh_layer_list()

func _refresh_transform_panel() -> void:
	_updating_spin = true
	if is_instance_valid(_selected_obj):
		_pos_x_spin.value = _selected_obj.position.x
		_pos_y_spin.value = _selected_obj.position.y
		_sz_w_spin.value  = _selected_obj.size.x
		_sz_h_spin.value  = _selected_obj.size.y
		_z_spin.value     = _selected_obj.z_index
	else:
		_pos_x_spin.value = 0.0; _pos_y_spin.value = 0.0
		_sz_w_spin.value  = 0.0; _sz_h_spin.value  = 0.0
		_z_spin.value     = 0.0
	_updating_spin = false

func _on_spin_changed() -> void:
	if _updating_spin or not is_instance_valid(_selected_obj):
		return
	_apply_spin_to_selected()

func _on_w_spin_changed() -> void:
	if _updating_spin or not is_instance_valid(_selected_obj):
		return
	if _aspect_ratio > 0.0:
		_updating_spin = true
		_sz_h_spin.value = snappedf(_sz_w_spin.value / _aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_selected()

func _on_h_spin_changed() -> void:
	if _updating_spin or not is_instance_valid(_selected_obj):
		return
	if _aspect_ratio > 0.0:
		_updating_spin = true
		_sz_w_spin.value = snappedf(_sz_h_spin.value * _aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_selected()

func _apply_spin_to_selected() -> void:
	_push_undo_transform(_selected_obj)
	_selected_obj.position = Vector2(_pos_x_spin.value, _pos_y_spin.value)
	_selected_obj.size     = Vector2(_sz_w_spin.value,  _sz_h_spin.value)
	_selected_obj.z_index  = int(_z_spin.value)
	_selected_obj._sync_rect_size()
	_dirty = true

func _on_transform_ended(_obj: Control) -> void:
	if is_instance_valid(_selected_obj):
		_refresh_transform_panel()
	_dirty = true

func _on_transform_motion(obj: EditableObjectNode) -> void:
	if is_instance_valid(obj) and obj == _selected_obj:
		_refresh_transform_panel()
		_dirty = true

# ── Grid mode ──────────────────────────────────────────────────────────────────

func _toggle_grid_mode() -> void:
	_grid_mode = _grid_btn.button_pressed
	if _grid_mode:
		_adding_firepoint = false
		_add_fp_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
	_update_all_boss_interactivity()
	_grid_overlay.show_grid     = _grid_mode
	_grid_overlay.is_edit_open  = _is_open

func _toggle_adding_firepoint() -> void:
	_adding_firepoint = _add_fp_btn.button_pressed
	if _adding_firepoint:
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
	_update_all_boss_interactivity()

# ── Fire points ────────────────────────────────────────────────────────────────

func _add_firepoint_at(viewport_pos: Vector2) -> void:
	if _active_boss.is_empty():
		return
	var ss_pos := viewport_pos - SCREEN_ORIGIN
	if _fp_target_basename.is_empty():
		if not _fire_points.has(_active_boss):
			_fire_points[_active_boss] = []
			_fp_id_counter[_active_boss] = 1
		var fp_id: int = _fp_id_counter.get(_active_boss, 1)
		_fire_points[_active_boss].append({"pos": ss_pos, "id": fp_id})
		_fp_id_counter[_active_boss] = fp_id + 1
	else:
		var key := _active_boss + "_" + _fp_target_basename
		if not _weapon_fire_points.has(key):
			_weapon_fire_points[key] = []
			_wp_fp_id_counter[key] = 1
		var fp_id: int = _wp_fp_id_counter.get(key, 1)
		_weapon_fire_points[key].append({"pos": ss_pos, "id": fp_id})
		_wp_fp_id_counter[key] = fp_id + 1
	_dirty = true
	_refresh_fp_list()
	_update_grid_overlay()

func _select_fp(idx: int) -> void:
	_selected_fp_idx = idx
	if idx >= 0:
		_select_obj(null)
	_refresh_fp_list()
	_update_grid_overlay()

func _delete_selected_fp() -> void:
	if _selected_fp_idx < 0:
		return
	var fps: Array = _get_fp_array()
	if _selected_fp_idx >= fps.size():
		return
	fps.remove_at(_selected_fp_idx)
	_set_fp_array(fps)
	_selected_fp_idx = -1
	_dirty = true
	_refresh_fp_list()
	_update_grid_overlay()

func _get_fp_array() -> Array:
	if _fp_target_basename.is_empty():
		return _fire_points.get(_active_boss, [])
	return _weapon_fire_points.get(_active_boss + "_" + _fp_target_basename, [])

func _set_fp_array(fps: Array) -> void:
	if _fp_target_basename.is_empty():
		_fire_points[_active_boss] = fps
	else:
		_weapon_fire_points[_active_boss + "_" + _fp_target_basename] = fps

func _update_fp_target_label() -> void:
	if _fp_target_label == null:
		return
	if _fp_target_basename.is_empty():
		_fp_target_label.text = "Target: " + (_active_boss if not _active_boss.is_empty() else "(none)")
	else:
		_fp_target_label.text = "Target: " + _fp_target_basename

func _update_grid_overlay() -> void:
	if _grid_overlay == null:
		return
	_grid_overlay.fire_points     = _get_fp_array()
	_grid_overlay.selected_fp_idx = _selected_fp_idx

func _refresh_fp_list() -> void:
	_update_fp_target_label()
	for child in _fp_vbox.get_children():
		child.queue_free()
	var fps: Array = _get_fp_array()
	for i: int in fps.size():
		_fp_vbox.add_child(_make_fp_row(fps[i], i))

func _make_fp_row(fp: Dictionary, idx: int) -> Control:
	var is_sel: bool = (idx == _selected_fp_idx)
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 30.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.65, 1.0, 0.38) if is_sel else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)

	var fp_id: int   = fp.get("id",  idx + 1)
	var pos: Vector2 = fp.get("pos", Vector2.ZERO)

	var id_lbl := Label.new()
	id_lbl.text = "FP%d" % fp_id
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	id_lbl.modulate = Color(0.25, 0.85, 1.0) if is_sel else Color(1.0, 0.55, 0.12)
	hbox.add_child(id_lbl)

	var pos_lbl := Label.new()
	pos_lbl.text = "(%d, %d)" % [int(pos.x), int(pos.y)]
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(pos_lbl)

	var cap_idx := idx
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			_select_fp(cap_idx)
	)
	return row

# ── Interactivity + GIF animation control ─────────────────────────────────────

func _update_all_boss_interactivity() -> void:
	var allow_select: bool = not _grid_mode and not _adding_firepoint
	for boss_name: String in _all_boss_names:
		var is_active: bool = _is_open and boss_name == _active_boss
		for eo in _placed.get(boss_name, []):
			if not is_instance_valid(eo):
				continue
			eo.set_gameplay_mode(not _is_open)
			# Hide non-active boss groups during edit mode; show only active group
			eo.visible = is_active if _is_open else true
			if _is_open:
				eo.gif_paused = true
				eo.reset_gif()
			else:
				eo.gif_paused = false
			eo.mouse_filter = Control.MOUSE_FILTER_STOP \
				if (is_active and _is_open and allow_select) else Control.MOUSE_FILTER_IGNORE

func _on_canvas_object_clicked(obj: EditableObjectNode) -> void:
	if not _is_open or _grid_mode:
		return
	_select_obj(obj)
	if is_instance_valid(obj):
		var base_eo := _get_base_eo(_active_boss)
		if obj != base_eo:
			_fp_target_basename = obj.source_path.get_file().get_basename().to_lower()
		else:
			_fp_target_basename = ""
	else:
		_fp_target_basename = ""
	_selected_fp_idx = -1
	_refresh_fp_list()
	_update_grid_overlay()

# ── Gameplay visibility ────────────────────────────────────────────────────────

func _on_boost_changed(_active: bool) -> void:
	# Boss visibility is owned by each fight controller (boss_fight.start_fight /
	# chromeleon._show_only), NOT by boost. Re-showing bosses on boost revealed the
	# inactive boss during the other's fight — so do nothing here.
	pass

func _update_gameplay_visibility() -> void:
	# Keep ALL boss bases hidden during gameplay (children cascade-hide). The active
	# boss is revealed by its own fight controller when spawned. Only called at setup()
	# and _close(), where no fight is active, so always-hiding is safe.
	for boss_name: String in _all_boss_names:
		var base_eo := _get_base_eo(boss_name)
		if is_instance_valid(base_eo) and base_eo.get_parent() == _objects_container:
			base_eo.visible = false

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# ── Arrow keys: fire point (priority) or EO, blocked in grid mode ──
	if _is_open and not _grid_mode and event is InputEventKey \
			and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		var dir := Vector2.ZERO
		match ke.keycode:
			KEY_UP:    dir = Vector2( 0.0, -1.0)
			KEY_DOWN:  dir = Vector2( 0.0,  1.0)
			KEY_LEFT:  dir = Vector2(-1.0,  0.0)
			KEY_RIGHT: dir = Vector2( 1.0,  0.0)
		if dir != Vector2.ZERO:
			if ke.shift_pressed:
				dir *= 10.0
			var fps: Array = _get_fp_array()
			if _selected_fp_idx >= 0 and _selected_fp_idx < fps.size():
				# Move selected fire point
				fps[_selected_fp_idx]["pos"] = (fps[_selected_fp_idx]["pos"] as Vector2) + dir
				_set_fp_array(fps)
				_dirty = true
				_refresh_fp_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif is_instance_valid(_selected_obj):
				# Move selected EO
				if not ke.echo:
					_push_undo_transform(_selected_obj)
				_selected_obj.position += dir
				_refresh_transform_panel()
				_dirty = true
				get_viewport().set_input_as_handled()
				return

	# ── Asset panel drag ──
	if _dragging_asset:
		if event is InputEventMouseMotion:
			var mp: Vector2 = get_viewport().get_mouse_position()
			var vp: Vector2 = get_viewport().get_visible_rect().size
			var np: Vector2 = mp + _drag_asset_off
			np.x = clampf(np.x, 0.0, vp.x - ASSET_PANEL_W)
			np.y = clampf(np.y, 0.0, vp.y - 100.0)
			_asset_panel.position = np
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_dragging_asset = false
		return

	# ── Control panel drag ──
	if _dragging_ctrl:
		if event is InputEventMouseMotion:
			var mp: Vector2 = get_viewport().get_mouse_position()
			var vp: Vector2 = get_viewport().get_visible_rect().size
			var np: Vector2 = mp + _drag_ctrl_off
			np.x = clampf(np.x, 0.0, vp.x - CTRL_PANEL_W)
			np.y = clampf(np.y, 0.0, vp.y - 100.0)
			_ctrl_panel.position = np
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_dragging_ctrl = false
		return

	# ── Canvas drag ──
	if _canvas_dragging:
		if event is InputEventMouseMotion:
			var mp: Vector2    = get_viewport().get_mouse_position()
			var delta: Vector2 = mp - _canvas_drag_prev
			_canvas_drag_prev  = mp
			if is_instance_valid(_selected_obj):
				if not _canvas_drag_undo_pushed:
					_canvas_drag_undo_pushed = true
					_push_undo_transform(_selected_obj)
				_selected_obj.position += delta
				_refresh_transform_panel()
				_dirty = true
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_canvas_dragging         = false
			_canvas_drag_undo_pushed = false
			if is_instance_valid(_selected_obj):
				_selected_obj._sync_rect_size()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		if not ke.echo and ke.keycode == KEY_Z and ke.ctrl_pressed:
			_undo()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.keycode == KEY_DELETE:
			if _selected_fp_idx >= 0:
				_delete_selected_fp()
			elif is_instance_valid(_selected_obj):
				_delete_selected()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.keycode == KEY_ESCAPE:
			if _adding_firepoint:
				_adding_firepoint = false
				_add_fp_btn.button_pressed = false
				_update_all_boss_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_boss_interactivity()
				get_viewport().set_input_as_handled()
				return
			_request_close()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.is_action_pressed("toggle_boss_edit_mode"):
			_request_close()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var in_panels := _asset_panel.get_global_rect().has_point(mb.position) \
					  or _ctrl_panel.get_global_rect().has_point(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not in_panels:
			if _adding_firepoint:
				_add_firepoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not in_panels:
			_canvas_dragging         = false
			_canvas_drag_undo_pushed = false
			if _adding_firepoint:
				_adding_firepoint = false
				_add_fp_btn.button_pressed = false
				_update_all_boss_interactivity()
			elif _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_boss_interactivity()
			else:
				_select_obj(null)
				_select_fp(-1)
			get_viewport().set_input_as_handled()

func _on_asset_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_asset  = true
			_drag_asset_off  = _asset_panel.global_position - get_viewport().get_mouse_position()

func _on_ctrl_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_ctrl  = true
			_drag_ctrl_off  = _ctrl_panel.global_position - get_viewport().get_mouse_position()

# ── Delete ─────────────────────────────────────────────────────────────────────

func _delete_selected() -> void:
	if not is_instance_valid(_selected_obj):
		return
	var list: Array = _placed.get(_active_boss, [])
	var idx: int    = list.find(_selected_obj)
	if idx < 0:
		return
	_push_undo_delete(_selected_obj, _active_boss, idx)
	list.erase(_selected_obj)
	_selected_obj.queue_free()
	_select_obj(null)
	_refresh_layer_list()
	_dirty = true

# ── Undo ───────────────────────────────────────────────────────────────────────

func _push_undo_transform(obj: EditableObjectNode) -> void:
	_undo_stack.append({"type": "transform", "obj": obj,
		"pos": obj.position, "size": obj.size})

func _push_undo_delete(obj: EditableObjectNode, boss_name: String, idx: int) -> void:
	_undo_stack.append({
		"type":    "delete",
		"tex":     obj.texture_rect.texture if obj.texture_rect != null else null,
		"path":    obj.source_path,
		"boss":    boss_name,
		"idx":     idx,
		"pos":     obj.position,
		"size":    obj.size,
		"is_base": idx == 0,
	})

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	match entry["type"]:
		"transform":
			var obj = entry["obj"]
			if is_instance_valid(obj):
				obj.position = entry["pos"]
				obj.size     = entry["size"]
				obj._sync_rect_size()
				_refresh_transform_panel()
		"delete":
			var tex: Texture2D = entry["tex"]
			if tex == null:
				return
			var boss: String = entry["boss"]
			if entry.get("is_base", false):
				var eo := _place_base_eo(boss, tex, entry["path"], entry["pos"], entry["size"])
				if eo != null:
					_placed[boss].erase(eo)
					_placed[boss].push_front(eo)
			else:
				_place_weapon_eo(boss, tex, entry["path"], entry["pos"], entry["size"])
			_refresh_layer_list()
	_dirty = not _undo_stack.is_empty()

# ── Persistence ────────────────────────────────────────────────────────────────

func _on_lock_pressed() -> void:
	if _active_boss.is_empty():
		return
	var locked: bool = not _locked_bosses.get(_active_boss, false)
	_locked_bosses[_active_boss] = locked
	_update_lock_btn()
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_PATH)
	cfg.set_value("locks", _active_boss, locked)
	cfg.save(LAYOUT_PATH)

func _update_lock_btn() -> void:
	if _lock_btn == null or _active_boss.is_empty():
		return
	var locked: bool = _locked_bosses.get(_active_boss, false)
	_lock_btn.text = "LOCKED" if locked else "LOCK"
	_lock_btn.modulate = Color(1.3, 0.5, 0.5) if locked else Color.WHITE

func _save_layout() -> void:
	if not _active_boss.is_empty() and _locked_bosses.get(_active_boss, false):
		_save_confirm_dlg.dialog_text = "Overwrite locked layout for '%s'?" % _active_boss
		if _save_confirm_dlg.confirmed.is_connected(_do_save_layout):
			_save_confirm_dlg.confirmed.disconnect(_do_save_layout)
		_save_confirm_dlg.confirmed.connect(_do_save_layout, CONNECT_ONE_SHOT)
		_save_confirm_dlg.popup_centered()
		return
	_do_save_layout()

func _do_save_layout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_PATH)
	cfg.set_value("meta", "version", 1)
	for boss_name: String in _all_boss_names:
		# EO layout
		var entries: Array[Dictionary] = []
		var list: Array = _placed.get(boss_name, [])
		for i in list.size():
			var eo := list[i] as EditableObjectNode
			if not is_instance_valid(eo):
				continue
			entries.append({
				"type":    "base" if i == 0 else "weapon",
				"path":    eo.source_path,
				"pos":     eo.position,
				"size":    eo.size,
				"z_index": eo.z_index,
			})
		cfg.set_value("bosses", boss_name, entries)
		# Fire points — boss main body
		var fp_data: Array[Dictionary] = []
		for fp: Dictionary in _fire_points.get(boss_name, []):
			fp_data.append({"pos": fp["pos"], "id": fp.get("id", 0)})
		cfg.set_value("firepoints", boss_name, fp_data)
		# Fire points — weapon EOs (blueorb, tealorb, etc.)
		var wlist: Array = _placed.get(boss_name, [])
		for i: int in range(1, wlist.size()):
			var weo := wlist[i] as EditableObjectNode
			if not is_instance_valid(weo):
				continue
			var wbn := weo.source_path.get_file().get_basename().to_lower()
			var key := boss_name + "_" + wbn
			var wfp_data: Array[Dictionary] = []
			for fp: Dictionary in _weapon_fire_points.get(key, []):
				wfp_data.append({"pos": fp["pos"], "id": fp.get("id", 0)})
			if not wfp_data.is_empty():
				cfg.set_value("firepoints", key, wfp_data)
	cfg.save(LAYOUT_PATH)
	_dirty = false

func _load_layout() -> void:
	if _objects_container == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	for boss_name: String in _all_boss_names:
		# EO layout
		if not _placed.get(boss_name, []).is_empty():
			pass
		else:
			var entries: Array = cfg.get_value("bosses", boss_name, [])
			for entry: Dictionary in entries:
				var path: String = entry.get("path", "")
				var tex := _load_full_tex(path)
				if tex == null:
					continue
				var pos: Vector2 = entry.get("pos",  Vector2(570.0, 80.0))
				var sz:  Vector2 = entry.get("size", Vector2(80.0,  80.0))
				if entry.get("type", "base") == "base":
					var eo := _place_base_eo(boss_name, tex, path, pos, sz)
					if eo != null:
						eo.z_index = entry.get("z_index", 110)
				else:
					var eo := _place_weapon_eo(boss_name, tex, path, pos, sz)
					if eo != null:
						eo.z_index = entry.get("z_index", 1)
		# Fire points — boss main body
		_fire_points[boss_name] = []
		var max_id := 0
		for fp: Dictionary in cfg.get_value("firepoints", boss_name, []):
			var fp_id: int = fp.get("id", max_id + 1)
			_fire_points[boss_name].append({"pos": fp.get("pos", Vector2.ZERO), "id": fp_id})
			max_id = maxi(max_id, fp_id)
		_fp_id_counter[boss_name] = max_id + 1
		# Fire points — weapon EOs
		var placed_list: Array = _placed.get(boss_name, [])
		for i: int in range(1, placed_list.size()):
			var weo := placed_list[i] as EditableObjectNode
			if not is_instance_valid(weo):
				continue
			var wbn := weo.source_path.get_file().get_basename().to_lower()
			var key := boss_name + "_" + wbn
			_weapon_fire_points[key] = []
			var wmax_id := 0
			for fp: Dictionary in cfg.get_value("firepoints", key, []):
				var fp_id: int = fp.get("id", wmax_id + 1)
				_weapon_fire_points[key].append({"pos": fp.get("pos", Vector2.ZERO), "id": fp_id})
				wmax_id = maxi(wmax_id, fp_id)
			_wp_fp_id_counter[key] = wmax_id + 1
	# Lock states
	for boss_name: String in _all_boss_names:
		_locked_bosses[boss_name] = cfg.get_value("locks", boss_name, false)

# ── Asset loading ──────────────────────────────────────────────────────────────

func _load_full_tex(path: String) -> Texture2D:
	var ext := path.get_extension().to_lower()
	if ext == "gif":
		return GifLoader.load_gif(path)
	# Check for PNG sprite sheet with JSON metadata
	if ext == "png":
		var json_path := path.get_basename() + ".json"
		var json_file := FileAccess.open(json_path, FileAccess.READ)
		if json_file != null:
			# PNG sprite sheet with metadata — use PngSpriteLoader
			var PngSpriteLoader := preload("res://scripts/ui/edit_mode/png_sprite_loader.gd")
			return PngSpriteLoader.load_png_sprite(path)
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

func _load_tex(path: String) -> Texture2D:
	return _load_full_tex(path)

# ── Toast ──────────────────────────────────────────────────────────────────────

func show_toast(message: String) -> void:
	_toast_label.text    = message
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
