extends CanvasLayer
## Main Menu Edit Mode — place menu layers (background, logo, the four buttons), set
## their position (X/Y) / size (W/H, aspect-locked) / Z-index, and attach Thrust Points
## with per-TP plume styles. Opened with F4 on the Main Menu.
##
## The placed EditableObjectNodes ARE the live menu (static in gameplay, draggable /
## resizable while F4 is open — the editor only lays a dim overlay over them, the objects
## stay in place). Layout persists to res://mainmenu_layout.cfg; plume styles to
## res://mainmenu_plume_styles.cfg. Thrust-point plumes are also rendered on the live menu.
##
## Adapted from scripts/ui/boss_edit/creep_edit_mode.gd (Fire-Points dropped; Thrust-Points
## + plume editor kept).

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const GridOverlay    := preload("res://scripts/ui/boss_edit/grid_overlay.gd")
const LAYOUT_PATH       := "res://mainmenu_layout.cfg"
const PLUME_STYLES_PATH := "res://mainmenu_plume_styles.cfg"
const MENU_FOLDER       := "res://assets/hud/mainmenu/"
const ASSET_PANEL_W     := 210.0
const CTRL_PANEL_W      := 224.0
const SCREEN_ORIGIN     := Vector2(15.0, 8.0)
# Layer basenames that act as clickable buttons in the live (gameplay) menu.
const BUTTON_LAYERS := ["resume", "setting", "codex", "quit"]

# Default geometry per known layer (viewport coords) — used only when the cfg has no
# entry yet (first launch). Kept in sync with main_menu.gd's DEFAULT_GEOM.
const DEFAULT_GEOM := {
	"background": {"pos": Vector2(0.0, -12.0),  "size": Vector2(1440.0, 804.0), "z": 0},
	"space":      {"pos": Vector2(0.0, -12.0),  "size": Vector2(1440.0, 804.0), "z": 1},
	"Logo":       {"pos": Vector2(515.5, 40.0), "size": Vector2(409.0, 228.0),  "z": 5},
	"resume":     {"pos": Vector2(600.0, 280.0),"size": Vector2(240.0, 119.0),  "z": 10},
	"setting":    {"pos": Vector2(600.0, 402.0),"size": Vector2(240.0, 119.0),  "z": 10},
	"codex":      {"pos": Vector2(600.0, 524.0),"size": Vector2(240.0, 119.0),  "z": 10},
	"quit":       {"pos": Vector2(600.0, 646.0),"size": Vector2(240.0, 119.0),  "z": 10},
}

# ── State ──────────────────────────────────────────────────────────────────────
var _is_open:          bool   = false
var _dirty:            bool   = false
var _active_layer:     String = ""
var _all_layer_names:  Array[String] = []
var _placed:           Dictionary = {}   # layer_name -> EditableObjectNode
var _deleted:          Dictionary = {}   # layer_name -> true (persisted; deleted layers never respawn)
var _selected_obj:     EditableObjectNode = null
var _layer_buttons:    Dictionary = {}   # layer_name -> Button
var _objects_container: Control = null

# Callbacks set by main_menu.gd
var on_closed: Callable = Callable()     # after the editor closes
var on_button: Callable = Callable()     # button layer clicked in the live menu (legacy path; unused)

# Thrust Points
var _adding_thrustpoint: bool = false
var _thrust_points:      Dictionary = {}  # layer_name -> Array[{pos, id, dir_angle}]
var _tp_id_counter:      Dictionary = {}  # layer_name -> int
var _selected_tp_idx:     int        = -1
var _selected_tp_indices: Array[int] = []

# ── UI ─────────────────────────────────────────────────────────────────────────
var _dim_overlay:    ColorRect     = null
var _asset_panel:    Panel         = null
var _tp_vbox:        VBoxContainer = null
var _ctrl_panel:     Panel         = null
var _layer_btn_vbox: VBoxContainer = null
var _x_spin:         SpinBox       = null
var _y_spin:         SpinBox       = null
var _sz_w_spin:      SpinBox       = null
var _sz_h_spin:      SpinBox       = null
var _z_spin:         SpinBox       = null
var _delete_btn:     Button        = null
var _grid_btn:       Button        = null
var _add_tp_btn:     Button        = null
var _toast_label:    Label         = null
var _grid_overlay:   Control       = null
var _tp_angle_row:   Control       = null
var _tp_angle_spin:  SpinBox       = null

# Plume editor UI
var _plume_vel_min_spin:  SpinBox           = null
var _plume_vel_max_spin:  SpinBox           = null
var _plume_life_spin:     SpinBox           = null
var _plume_spread_spin:   SpinBox           = null
var _plume_sc_min_spin:   SpinBox           = null
var _plume_sc_max_spin:   SpinBox           = null
var _plume_col_core_btn:  ColorPickerButton = null
var _plume_col_flame_btn: ColorPickerButton = null
var _plume_col_cool_btn:  ColorPickerButton = null
var _plume_styles:        Dictionary        = {}  # layer_name -> {"tp_N": style_dict}
var _plume_tp_label:      Label             = null
var _updating_plume:      bool              = false

# Plume render nodes
var _preview_plumes: Array[CPUParticles2D] = []   # active layer's TPs while editing
var _live_plumes:    Array[CPUParticles2D] = []   # all TPs in the live menu

# Panel drag state
var _dragging_asset:    bool    = false
var _drag_asset_off:    Vector2 = Vector2.ZERO
var _dragging_ctrl:     bool    = false
var _drag_ctrl_off:     Vector2 = Vector2.ZERO
var _eo_drag_undo_pushed: bool  = false
var _updating_spin:    bool    = false
var _grid_mode:        bool    = false
var _undo_stack: Array[Dictionary] = []

# Zoom state (scroll-wheel only — slider removed)
var _zoom:     float = 1.0
const ZOOM_MIN := 0.4
const ZOOM_MAX := 5.0
const ZOOM_RATIO := 1.15

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mainmenu_edit")
	_scan_layers()
	_build_ui()
	_build_layer_buttons()
	_set_ui_visible(false)

func setup(objects_container: Control) -> void:
	_objects_container = objects_container
	# Build every layer up front: these EditableObjectNodes ARE the live menu.
	_load_plume_styles()
	_load_layout()                       # also loads the persisted _deleted set
	for layer_name: String in _all_layer_names:
		_load_or_create_layer(layer_name)
		if not _thrust_points.has(layer_name):
			_thrust_points[layer_name] = []
	_build_layer_buttons()               # rebuild the OBJECTS table now that _deleted is known
	_update_all_layer_interactivity()   # closed → gameplay mode, button layers clickable
	_rebuild_live_plumes()

func is_open() -> bool:
	return _is_open

# ── Folder scan ────────────────────────────────────────────────────────────────

func _scan_layers() -> void:
	_all_layer_names.clear()
	var dir := DirAccess.open(MENU_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var ext := entry.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "gif"]:
				_all_layer_names.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	_all_layer_names.sort()

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

	_grid_overlay = GridOverlay.new()
	_grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_overlay.z_index = 50
	add_child(_grid_overlay)

# ── LEFT panel: thrust points + plume style ──────────────────────────────────────

func _build_asset_panel() -> void:
	_asset_panel = Panel.new()
	_asset_panel.size     = Vector2(ASSET_PANEL_W, 560.0)
	_asset_panel.position = Vector2(20.0, 44.0)
	add_child(_asset_panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	_asset_panel.add_child(root)

	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0.0, 30.0)
	title_bar.gui_input.connect(_on_asset_title_input)
	root.add_child(title_bar)
	var tbl := Label.new()
	tbl.text = "THRUST"
	tbl.add_theme_font_size_override("font_size", 12)
	tbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tbl)

	var tp_hdr := Label.new()
	tp_hdr.text = "THRUST POINTS"
	tp_hdr.add_theme_font_size_override("font_size", 11)
	tp_hdr.modulate = Color(0.10, 0.90, 0.65)
	root.add_child(tp_hdr)

	var tp_scroll := ScrollContainer.new()
	tp_scroll.custom_minimum_size = Vector2(0.0, 130.0)
	tp_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(tp_scroll)
	_tp_vbox = VBoxContainer.new()
	_tp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_vbox.add_theme_constant_override("separation", 2)
	tp_scroll.add_child(_tp_vbox)

	# TP angle row
	_tp_angle_row = HBoxContainer.new()
	_tp_angle_row.visible = false
	_tp_angle_row.add_theme_constant_override("separation", 4)
	root.add_child(_tp_angle_row)
	var tpal := Label.new()
	tpal.text = "Dir:"
	tpal.add_theme_font_size_override("font_size", 10)
	tpal.custom_minimum_size = Vector2(24.0, 0.0)
	_tp_angle_row.add_child(tpal)
	_tp_angle_spin = SpinBox.new()
	_tp_angle_spin.min_value = -180.0
	_tp_angle_spin.max_value = 180.0
	_tp_angle_spin.step = 1.0
	_tp_angle_spin.suffix = "°"
	_tp_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_angle_spin.value_changed.connect(func(_v: float) -> void: _on_tp_angle_changed())
	_tp_angle_row.add_child(_tp_angle_spin)

	# ── PLUME STYLE section ──
	root.add_child(HSeparator.new())
	var pe_hdr_row := HBoxContainer.new()
	pe_hdr_row.add_theme_constant_override("separation", 4)
	root.add_child(pe_hdr_row)
	var pe_lbl := Label.new()
	pe_lbl.text = "PLUME STYLE"
	pe_lbl.add_theme_font_size_override("font_size", 10)
	pe_lbl.modulate = Color(0.55, 0.90, 1.0)
	pe_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pe_hdr_row.add_child(pe_lbl)
	var pe_reset := Button.new()
	pe_reset.text = "Reset"
	pe_reset.add_theme_font_size_override("font_size", 9)
	pe_reset.pressed.connect(_reset_plume_style)
	pe_hdr_row.add_child(pe_reset)

	_plume_tp_label = Label.new()
	_plume_tp_label.text = "– select a TP –"
	_plume_tp_label.add_theme_font_size_override("font_size", 10)
	_plume_tp_label.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(_plume_tp_label)

	var vel_row := HBoxContainer.new()
	vel_row.add_theme_constant_override("separation", 3)
	root.add_child(vel_row)
	var vel_lbl := Label.new()
	vel_lbl.text = "Vel:"
	vel_lbl.add_theme_font_size_override("font_size", 10)
	vel_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	vel_row.add_child(vel_lbl)
	_plume_vel_min_spin = _mk_pspin(vel_row, 0.0, 600.0, 5.0)
	_plume_vel_max_spin = _mk_pspin(vel_row, 0.0, 600.0, 5.0)

	var ls_row := HBoxContainer.new()
	ls_row.add_theme_constant_override("separation", 3)
	root.add_child(ls_row)
	var life_lbl := Label.new()
	life_lbl.text = "Life:"
	life_lbl.add_theme_font_size_override("font_size", 10)
	life_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	ls_row.add_child(life_lbl)
	_plume_life_spin = _mk_pspin(ls_row, 0.05, 3.0, 0.05)
	var spr_lbl := Label.new()
	spr_lbl.text = "Spr:"
	spr_lbl.add_theme_font_size_override("font_size", 10)
	ls_row.add_child(spr_lbl)
	_plume_spread_spin = _mk_pspin(ls_row, 0.0, 90.0, 1.0)

	var sc_row := HBoxContainer.new()
	sc_row.add_theme_constant_override("separation", 3)
	root.add_child(sc_row)
	var sc_lbl := Label.new()
	sc_lbl.text = "Sc:"
	sc_lbl.add_theme_font_size_override("font_size", 10)
	sc_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	sc_row.add_child(sc_lbl)
	_plume_sc_min_spin = _mk_pspin(sc_row, 0.1, 8.0, 0.1)
	_plume_sc_max_spin = _mk_pspin(sc_row, 0.1, 8.0, 0.1)

	var col_row := HBoxContainer.new()
	col_row.add_theme_constant_override("separation", 3)
	root.add_child(col_row)
	_plume_col_core_btn  = _mk_pcol_vbox(col_row, "Core",  Color(1.0, 0.95, 0.7, 1.0))
	_plume_col_flame_btn = _mk_pcol_vbox(col_row, "Flame", Color(1.0, 0.6,  0.2, 1.0))
	_plume_col_cool_btn  = _mk_pcol_vbox(col_row, "Cool",  Color(0.45, 0.6, 1.0, 0.85))

# ── RIGHT panel: objects + transform + actions ───────────────────────────────────

func _build_ctrl_panel() -> void:
	_ctrl_panel = Panel.new()
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_ctrl_panel.size     = Vector2(CTRL_PANEL_W, 560.0)
	_ctrl_panel.position = Vector2(vp_w - CTRL_PANEL_W - 20.0, 44.0)
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
	tl.text = "MAIN MENU EDIT"
	tl.add_theme_font_size_override("font_size", 13)
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tl)

	# ── OBJECTS table (the layer list) ──
	_add_section(root, "OBJECTS")
	var layer_scroll := ScrollContainer.new()
	layer_scroll.custom_minimum_size = Vector2(0.0, 180.0)
	layer_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(layer_scroll)
	_layer_btn_vbox = VBoxContainer.new()
	_layer_btn_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_btn_vbox.add_theme_constant_override("separation", 2)
	layer_scroll.add_child(_layer_btn_vbox)

	root.add_child(HSeparator.new())

	# ── TRANSFORM (X / Y / W / H / Z) ──
	_add_section(root, "TRANSFORM")
	var xy_row := HBoxContainer.new()
	xy_row.add_theme_constant_override("separation", 3)
	root.add_child(xy_row)
	_x_spin = _small_spin(xy_row, "X", -4000.0, 4000.0, _on_x_spin_changed)
	_y_spin = _small_spin(xy_row, "Y", -4000.0, 4000.0, _on_y_spin_changed)

	var sz_row := HBoxContainer.new()
	sz_row.add_theme_constant_override("separation", 3)
	root.add_child(sz_row)
	_sz_w_spin = _small_spin(sz_row, "W", 1.0, 4000.0, _on_w_spin_changed)
	_sz_h_spin = _small_spin(sz_row, "H", 1.0, 4000.0, _on_h_spin_changed)

	var z_row := HBoxContainer.new()
	z_row.add_theme_constant_override("separation", 3)
	root.add_child(z_row)
	_z_spin = _small_spin(z_row, "Z", -500.0, 500.0)
	var z_spacer := Control.new()
	z_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z_row.add_child(z_spacer)

	root.add_child(HSeparator.new())

	# ── Mode + actions ──
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 3)
	root.add_child(mode_row)
	_grid_btn = Button.new()
	_grid_btn.text = "Grid"
	_grid_btn.toggle_mode = true
	_grid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_btn.pressed.connect(_toggle_grid_mode)
	mode_row.add_child(_grid_btn)
	_add_tp_btn = Button.new()
	_add_tp_btn.text = "Add TP"
	_add_tp_btn.toggle_mode = true
	_add_tp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_tp_btn.pressed.connect(_toggle_adding_thrustpoint)
	mode_row.add_child(_add_tp_btn)

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
	close_btn.text = "Close"
	close_btn.pressed.connect(_request_close)
	root.add_child(close_btn)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.60, 0.63, 0.76)
	parent.add_child(lbl)

func _small_spin(parent: HBoxContainer, prefix: String, mn: float, mx: float, cb: Callable = Callable()) -> SpinBox:
	var lbl := Label.new()
	lbl.text = prefix + ":"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.custom_minimum_size = Vector2(14.0, 0.0)
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = 1.0
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	if cb.is_valid():
		sb.value_changed.connect(func(_v: float) -> void: cb.call())
	else:
		sb.value_changed.connect(func(_v: float) -> void: _on_spin_changed())
	parent.add_child(sb)
	return sb

func _mk_pspin(parent: HBoxContainer, mn: float, mx: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	sb.value_changed.connect(func(_v: float) -> void: _on_plume_changed())
	parent.add_child(sb)
	return sb

func _mk_pcol_vbox(parent: HBoxContainer, lbl_text: String, default_col: Color) -> ColorPickerButton:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vb)
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var cpb := ColorPickerButton.new()
	cpb.color = default_col
	cpb.custom_minimum_size = Vector2(0.0, 22.0)
	cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpb.color_changed.connect(func(_c: Color) -> void: _on_plume_changed())
	vb.add_child(cpb)
	return cpb

func _build_layer_buttons() -> void:
	for child in _layer_btn_vbox.get_children():
		child.queue_free()
	_layer_buttons.clear()
	for layer_name: String in _all_layer_names:
		if _deleted.has(layer_name):
			continue   # deleted layers are hidden from the OBJECTS table
		var btn := Button.new()
		btn.text = layer_name
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_set_active_layer.bind(layer_name))
		_layer_btn_vbox.add_child(btn)
		_layer_buttons[layer_name] = btn

# ── Open / Close ───────────────────────────────────────────────────────────────

func toggle() -> void:
	if not _is_open:
		_is_open = true
		_grid_overlay.is_edit_open = true
		_set_ui_visible(true)
		get_tree().paused = true
		_reset_zoom()
		_clear_live_plumes()                # live plumes off while editing (preview takes over)
		_update_all_layer_interactivity()
		if _active_layer.is_empty() or _deleted.has(_active_layer):
			_set_active_layer(_first_live_layer())
		else:
			_set_active_layer(_active_layer)
	else:
		_request_close()

func _first_live_layer() -> String:
	for layer_name: String in _all_layer_names:
		if not _deleted.has(layer_name):
			return layer_name
	return ""

func _request_close() -> void:
	if _dirty:
		_save_layout()
	_close()

func _close() -> void:
	_is_open = false
	_grid_mode = false
	_adding_thrustpoint = false
	_grid_btn.button_pressed   = false
	_add_tp_btn.button_pressed  = false
	_grid_overlay.show_grid    = false
	_grid_overlay.is_edit_open = false
	_reset_zoom()
	_select_tp(-1)
	_set_ui_visible(false)
	_select_obj(null)
	_update_all_layer_interactivity()   # back to gameplay mode; button layers live again
	_rebuild_live_plumes()
	get_tree().paused = false
	if on_closed.is_valid():
		on_closed.call()

func _set_ui_visible(v: bool) -> void:
	_dim_overlay.visible = v
	_asset_panel.visible = v
	_ctrl_panel.visible  = v
	if not v:
		_clear_preview_plumes()
		_dragging_asset      = false
		_dragging_ctrl       = false
		_eo_drag_undo_pushed = false

# ── Active layer ───────────────────────────────────────────────────────────────

func _set_active_layer(layer_name: String) -> void:
	if layer_name.is_empty():
		return
	_active_layer = layer_name
	if not _placed.has(layer_name) or not is_instance_valid(_placed.get(layer_name, null)):
		_load_or_create_layer(layer_name)
	if not _thrust_points.has(layer_name):
		_thrust_points[layer_name] = []
	_eo_drag_undo_pushed = false
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	var eo: EditableObjectNode = _placed.get(layer_name, null)
	_select_obj(eo if is_instance_valid(eo) else null)
	_update_grid_overlay()
	_refresh_tp_list()
	_refresh_tp_angle_ui()
	_refresh_plume_editor()
	for name: String in _layer_buttons:
		(_layer_buttons[name] as Button).button_pressed = (name == layer_name)

func _name_of(obj: EditableObjectNode) -> String:
	for layer_name: String in _placed:
		if _placed[layer_name] == obj:
			return layer_name
	return ""

func _load_or_create_layer(layer_name: String) -> void:
	if _deleted.has(layer_name):
		return   # user deleted it in F4 — never auto-respawn
	if _placed.has(layer_name) and is_instance_valid(_placed.get(layer_name, null)):
		return
	for ext: String in ["png", "gif", "jpg", "jpeg"]:
		var path: String = MENU_FOLDER + layer_name + "." + ext
		var _t0 := Time.get_ticks_usec()   # TEMP DIAGNOSTIC — menu startup freeze investigation
		var tex := _load_full_tex(path)
		var _dt := (Time.get_ticks_usec() - _t0) / 1000.0
		if tex != null and _dt >= 1.0:
			print("[menu-startup]     layer '%s' texture load: %.1fms" % [layer_name, _dt])
		if tex == null:
			continue
		var geom: Dictionary = _default_geom(layer_name, tex)
		var eo := _place_layer_eo(layer_name, tex, path, geom["pos"], geom["size"])
		if eo != null:
			eo.z_index = int(geom["z"])
		return

func _default_geom(layer_name: String, tex: Texture2D) -> Dictionary:
	if DEFAULT_GEOM.has(layer_name):
		return DEFAULT_GEOM[layer_name].duplicate()
	var tex_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	var aspect := tex_h / tex_w if tex_w > 0.0 else 1.0
	return {"pos": Vector2(600.0, 380.0), "size": Vector2(240.0, 240.0 * aspect), "z": 10}

func _place_layer_eo(layer_name: String, tex: Texture2D, path: String,
		pos: Vector2, sz: Vector2) -> EditableObjectNode:
	if _objects_container == null:
		return null
	var eo: EditableObjectNode = EditableObject.instantiate()
	eo.group_id    = "mainmenu"
	eo.source_path = path
	_objects_container.add_child(eo)
	eo.init(tex, pos, sz)
	eo.z_index     = 10
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eo.object_clicked.connect(_on_canvas_object_clicked)
	eo.transform_ended.connect(_on_transform_ended)
	eo.transform_motion.connect(_on_transform_motion)
	_placed[layer_name] = eo
	return eo

## Live-menu button hit-test (gameplay only): basename of the button under `vp_pos`, or "".
func live_button_at(vp_pos: Vector2) -> String:
	if _is_open:
		return ""
	for layer_name: String in _placed:
		var base := layer_name.to_lower()
		if base in BUTTON_LAYERS:
			var eo: EditableObjectNode = _placed[layer_name]
			if is_instance_valid(eo) and eo.visible and eo.get_global_rect().has_point(vp_pos):
				return base
	return ""

## Apply/clear the hover look (brighten + grow 3% from center) on a button layer.
func set_button_hover(base: String, on: bool) -> void:
	for layer_name: String in _placed:
		if layer_name.to_lower() == base:
			var eo: EditableObjectNode = _placed[layer_name]
			if is_instance_valid(eo):
				if on:
					eo.pivot_offset = eo.size / 2.0
					eo.scale = Vector2(1.03, 1.03)
					eo.modulate = Color(1.25, 1.25, 1.25)
				else:
					eo.scale = Vector2.ONE
					eo.modulate = Color(1.0, 1.0, 1.0)
			return

# ── Selection & transform ──────────────────────────────────────────────────────

func _select_obj(obj: EditableObjectNode) -> void:
	if is_instance_valid(_selected_obj):
		_selected_obj.selected = false
	_selected_obj = obj
	if is_instance_valid(obj):
		obj.selected = true
	_delete_btn.disabled = not is_instance_valid(obj)
	_refresh_transform_panel()

func _refresh_transform_panel() -> void:
	_updating_spin = true
	var eo: EditableObjectNode = _placed.get(_active_layer, null)
	if eo != null and is_instance_valid(eo):
		_x_spin.value    = eo.position.x
		_y_spin.value    = eo.position.y
		_sz_w_spin.value = eo.size.x
		_sz_h_spin.value = eo.size.y
		_z_spin.value    = eo.z_index
	else:
		_x_spin.value    = 0.0
		_y_spin.value    = 0.0
		_sz_w_spin.value = 0.0
		_sz_h_spin.value = 0.0
		_z_spin.value    = 0.0
	_updating_spin = false

func _on_spin_changed() -> void:
	if _updating_spin or _active_layer.is_empty():
		return
	_apply_spin_to_active()

func _on_x_spin_changed() -> void:
	if _updating_spin or _active_layer.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_layer, null)
	if eo == null or not is_instance_valid(eo):
		return
	_push_undo_transform(eo)
	eo.position.x = _x_spin.value
	_dirty = true

func _on_y_spin_changed() -> void:
	if _updating_spin or _active_layer.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_layer, null)
	if eo == null or not is_instance_valid(eo):
		return
	_push_undo_transform(eo)
	eo.position.y = _y_spin.value
	_dirty = true

func _on_w_spin_changed() -> void:
	if _updating_spin or _active_layer.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_layer, null)
	if eo != null and is_instance_valid(eo) and eo._aspect_ratio > 0.0:
		_updating_spin = true
		_sz_h_spin.value = snappedf(_sz_w_spin.value / eo._aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_active()

func _on_h_spin_changed() -> void:
	if _updating_spin or _active_layer.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_layer, null)
	if eo != null and is_instance_valid(eo) and eo._aspect_ratio > 0.0:
		_updating_spin = true
		_sz_w_spin.value = snappedf(_sz_h_spin.value * eo._aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_active()

func _apply_spin_to_active() -> void:
	var eo: EditableObjectNode = _placed.get(_active_layer, null)
	if eo == null or not is_instance_valid(eo):
		return
	_push_undo_transform(eo)
	eo.size    = Vector2(_sz_w_spin.value, _sz_h_spin.value)
	eo.z_index = int(_z_spin.value)
	eo._sync_rect_size()
	_dirty = true

func _on_transform_ended(_obj: Control) -> void:
	_eo_drag_undo_pushed = false
	_refresh_transform_panel()
	_dirty = true

func _on_transform_motion(obj: EditableObjectNode) -> void:
	if not is_instance_valid(obj):
		return
	if not _eo_drag_undo_pushed:
		_eo_drag_undo_pushed = true
		_push_undo_transform(obj)
	_refresh_transform_panel()
	_dirty = true

# ── Grid / Add-TP modes ──────────────────────────────────────────────────────────

func _toggle_grid_mode() -> void:
	_grid_mode = _grid_btn.button_pressed
	if _grid_mode:
		_adding_thrustpoint = false
		_add_tp_btn.button_pressed = false
		_select_obj(null)
		_select_tp(-1)
	_update_all_layer_interactivity()
	_grid_overlay.show_grid    = _grid_mode
	_grid_overlay.is_edit_open = _is_open

func _toggle_adding_thrustpoint() -> void:
	_adding_thrustpoint = _add_tp_btn.button_pressed
	if _adding_thrustpoint:
		_grid_mode = false
		_grid_btn.button_pressed = false
		_grid_overlay.show_grid = false
		_select_obj(null)
		_select_tp(-1)
	_update_all_layer_interactivity()

# ── Thrust Points ────────────────────────────────────────────────────────────────

func _add_thrustpoint_at(viewport_pos: Vector2) -> void:
	if _active_layer.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _thrust_points.has(_active_layer):
		_thrust_points[_active_layer] = []
		_tp_id_counter[_active_layer] = 1
	var tp_id: int = _tp_id_counter.get(_active_layer, 1)
	_thrust_points[_active_layer].append({"pos": ss_pos, "id": tp_id, "dir_angle": PI * 0.5})
	_tp_id_counter[_active_layer] = tp_id + 1
	_dirty = true
	_refresh_tp_list()
	_update_grid_overlay()

func _select_tp(idx: int) -> void:
	_selected_tp_idx = idx
	_selected_tp_indices.clear()
	if idx >= 0:
		_selected_tp_indices.append(idx)
	_refresh_tp_list()
	_update_grid_overlay()
	_refresh_tp_angle_ui()
	_refresh_plume_editor()

func _select_tp_add(idx: int) -> void:
	if idx < 0:
		return
	if _selected_tp_indices.has(idx):
		_selected_tp_indices.erase(idx)
		if _selected_tp_idx == idx:
			_selected_tp_idx = _selected_tp_indices.back() if not _selected_tp_indices.is_empty() else -1
	else:
		_selected_tp_indices.append(idx)
		_selected_tp_idx = idx
	_refresh_tp_list()
	_update_grid_overlay()
	_refresh_tp_angle_ui()
	_refresh_plume_editor()

func _delete_selected_tp() -> void:
	if _selected_tp_indices.is_empty():
		return
	var tps: Array = _thrust_points.get(_active_layer, [])
	var sorted: Array[int] = _selected_tp_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for idx: int in sorted:
		if idx >= 0 and idx < tps.size():
			tps.remove_at(idx)
	_thrust_points[_active_layer] = tps
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	_dirty = true
	_refresh_tp_list()
	_update_grid_overlay()
	_refresh_plume_editor()

func _refresh_tp_angle_ui() -> void:
	var show := not _selected_tp_indices.is_empty()
	_tp_angle_row.visible = show
	if not show or _selected_tp_idx < 0:
		return
	var tps: Array = _thrust_points.get(_active_layer, [])
	if _selected_tp_idx >= tps.size():
		return
	_updating_spin = true
	_tp_angle_spin.value = snappedf(rad_to_deg(float(tps[_selected_tp_idx].get("dir_angle", 0.0))), 1.0)
	_updating_spin = false

func _on_tp_angle_changed() -> void:
	if _updating_spin or _selected_tp_indices.is_empty():
		return
	var tps: Array = _thrust_points.get(_active_layer, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx >= 0 and sel_idx < tps.size():
			tps[sel_idx]["dir_angle"] = deg_to_rad(_tp_angle_spin.value)
	_thrust_points[_active_layer] = tps
	_dirty = true
	_update_grid_overlay()

func _refresh_tp_list() -> void:
	for child in _tp_vbox.get_children():
		child.queue_free()
	var tps: Array = _thrust_points.get(_active_layer, [])
	for i: int in tps.size():
		_tp_vbox.add_child(_make_point_row(tps[i], i))

func _make_point_row(pt: Dictionary, idx: int) -> Control:
	var is_sel: bool = _selected_tp_indices.has(idx)
	var col_sel  := Color(0.10, 0.80, 0.55, 0.38)
	var col_id   := Color(0.10, 0.90, 0.65)
	var id_sel   := Color(0.10, 0.75, 0.55)

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 30.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = col_sel if is_sel else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)

	var pt_id: int   = pt.get("id",  idx + 1)
	var pos: Vector2 = pt.get("pos", Vector2.ZERO)
	var angle_deg    := int(round(rad_to_deg(float(pt.get("dir_angle", 0.0)))))

	var id_lbl := Label.new()
	id_lbl.text = "TP%d" % pt_id
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	id_lbl.modulate = col_id if is_sel else id_sel
	hbox.add_child(id_lbl)

	var pos_lbl := Label.new()
	pos_lbl.text = "(%d,%d) %d°" % [int(pos.x), int(pos.y), angle_deg]
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(pos_lbl)

	var cap_idx := idx
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			if Input.is_key_pressed(KEY_SHIFT):
				_select_tp_add(cap_idx)
			else:
				_select_tp(cap_idx)
	)
	return row

# ── Plume editor ───────────────────────────────────────────────────────────────

func _default_plume_style() -> Dictionary:
	return {
		"vel_min":   80.0,
		"vel_max":   130.0,
		"lifetime":  0.35,
		"spread":    12.0,
		"sc_min":    1.0,
		"sc_max":    2.2,
		"col_core":  Color(1.0, 0.95, 0.7, 1.0),
		"col_flame": Color(1.0, 0.6,  0.2, 1.0),
		"col_cool":  Color(0.45, 0.6, 1.0, 0.85),
	}

func _get_selected_tp_id() -> int:
	if _active_layer.is_empty() or _selected_tp_idx < 0:
		return -1
	var tps: Array = _thrust_points.get(_active_layer, [])
	if _selected_tp_idx >= tps.size():
		return -1
	return int(tps[_selected_tp_idx].get("id", _selected_tp_idx + 1))

func _get_tp_plume_style(tp_id: int) -> Dictionary:
	if _active_layer.is_empty() or tp_id < 0:
		return _default_plume_style()
	if not _plume_styles.has(_active_layer):
		_plume_styles[_active_layer] = {}
	var cmap: Dictionary = _plume_styles[_active_layer]
	var key := "tp_%d" % tp_id
	if not cmap.has(key):
		cmap[key] = _default_plume_style()
	return cmap[key]

func _refresh_plume_editor() -> void:
	if _plume_vel_min_spin == null:
		return
	var n := _selected_tp_indices.size()
	var has_tp := n > 0
	var tp_id := _get_selected_tp_id()
	if _plume_tp_label != null:
		if not has_tp:
			_plume_tp_label.text    = "– select a TP –"
			_plume_tp_label.modulate = Color(0.55, 0.55, 0.55)
		elif n == 1:
			_plume_tp_label.text    = "TP %d" % tp_id
			_plume_tp_label.modulate = Color(0.55, 0.90, 1.0)
		else:
			_plume_tp_label.text    = "%d TPs selected" % n
			_plume_tp_label.modulate = Color(0.75, 0.90, 1.0)
	for spin: SpinBox in [_plume_vel_min_spin, _plume_vel_max_spin,
			_plume_life_spin, _plume_spread_spin,
			_plume_sc_min_spin, _plume_sc_max_spin]:
		spin.editable = has_tp
	for cpb: ColorPickerButton in [_plume_col_core_btn, _plume_col_flame_btn, _plume_col_cool_btn]:
		cpb.disabled = not has_tp
	if not has_tp or tp_id < 0:
		return
	_updating_plume = true
	var s := _get_tp_plume_style(tp_id)
	_plume_vel_min_spin.value  = float(s.get("vel_min",  80.0))
	_plume_vel_max_spin.value  = float(s.get("vel_max",  130.0))
	_plume_life_spin.value     = float(s.get("lifetime", 0.35))
	_plume_spread_spin.value   = float(s.get("spread",   12.0))
	_plume_sc_min_spin.value   = float(s.get("sc_min",   1.0))
	_plume_sc_max_spin.value   = float(s.get("sc_max",   2.2))
	_plume_col_core_btn.color  = s.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	_plume_col_flame_btn.color = s.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	_plume_col_cool_btn.color  = s.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	_updating_plume = false

func _on_plume_changed() -> void:
	if _updating_plume or _active_layer.is_empty() or _selected_tp_indices.is_empty():
		return
	if not _plume_styles.has(_active_layer):
		_plume_styles[_active_layer] = {}
	var tps: Array = _thrust_points.get(_active_layer, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx < 0 or sel_idx >= tps.size():
			continue
		var tp_id: int = int(tps[sel_idx].get("id", sel_idx + 1))
		var s := _get_tp_plume_style(tp_id)
		s["vel_min"]   = _plume_vel_min_spin.value
		s["vel_max"]   = _plume_vel_max_spin.value
		s["lifetime"]  = _plume_life_spin.value
		s["spread"]    = _plume_spread_spin.value
		s["sc_min"]    = _plume_sc_min_spin.value
		s["sc_max"]    = _plume_sc_max_spin.value
		s["col_core"]  = _plume_col_core_btn.color
		s["col_flame"] = _plume_col_flame_btn.color
		s["col_cool"]  = _plume_col_cool_btn.color
		_plume_styles[_active_layer]["tp_%d" % tp_id] = s
	_refresh_plume_preview()
	_dirty = true

func _reset_plume_style() -> void:
	if _active_layer.is_empty() or _selected_tp_indices.is_empty():
		return
	if not _plume_styles.has(_active_layer):
		_plume_styles[_active_layer] = {}
	var tps: Array = _thrust_points.get(_active_layer, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx < 0 or sel_idx >= tps.size():
			continue
		var tp_id: int = int(tps[sel_idx].get("id", sel_idx + 1))
		_plume_styles[_active_layer]["tp_%d" % tp_id] = _default_plume_style()
	_refresh_plume_editor()
	_refresh_plume_preview()
	_dirty = true

# ── Plume rendering (preview while editing + live on the menu) ───────────────────

func _clear_preview_plumes() -> void:
	for p: CPUParticles2D in _preview_plumes:
		if is_instance_valid(p):
			p.queue_free()
	_preview_plumes.clear()

func _refresh_plume_preview() -> void:
	_clear_preview_plumes()
	if not _is_open or _objects_container == null or not is_instance_valid(_objects_container):
		return
	var cmap: Dictionary = _plume_styles.get(_active_layer, {})
	var tps: Array = _thrust_points.get(_active_layer, [])
	for i: int in tps.size():
		var tp: Dictionary = tps[i]
		var tp_id: int = int(tp.get("id", i + 1))
		var style: Dictionary = cmap.get("tp_%d" % tp_id, _default_plume_style())
		var p := _make_plume(tp["pos"] + SCREEN_ORIGIN, float(tp.get("dir_angle", PI * 0.5)), style)
		_objects_container.add_child(p)
		_preview_plumes.append(p)

func _clear_live_plumes() -> void:
	for p: CPUParticles2D in _live_plumes:
		if is_instance_valid(p):
			p.queue_free()
	_live_plumes.clear()

func _rebuild_live_plumes() -> void:
	_clear_live_plumes()
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	for layer_name: String in _all_layer_names:
		var cmap: Dictionary = _plume_styles.get(layer_name, {})
		for i: int in _thrust_points.get(layer_name, []).size():
			var tp: Dictionary = _thrust_points[layer_name][i]
			var tp_id: int = int(tp.get("id", i + 1))
			var style: Dictionary = cmap.get("tp_%d" % tp_id, _default_plume_style())
			var p := _make_plume(tp["pos"] + SCREEN_ORIGIN, float(tp.get("dir_angle", PI * 0.5)), style)
			_objects_container.add_child(p)
			_live_plumes.append(p)

func _make_plume(oc_pos: Vector2, dir_angle: float, style: Dictionary = {}) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = oc_pos
	p.amount = 20
	p.lifetime  = float(style.get("lifetime", 0.35))
	p.local_coords = true
	p.emitting = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = false
	p.z_index = 8
	p.gravity = Vector2.ZERO
	p.direction = Vector2.RIGHT.rotated(dir_angle)
	p.spread              = float(style.get("spread",   12.0))
	p.initial_velocity_min = float(style.get("vel_min", 50.0))
	p.initial_velocity_max = float(style.get("vel_max", 90.0))
	p.scale_amount_min    = float(style.get("sc_min",  1.0))
	p.scale_amount_max    = float(style.get("sc_max",  2.0))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = taper
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	p.texture = ImageTexture.create_from_image(img)
	var col_core:  Color = style.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	var col_flame: Color = style.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	var col_fade           := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	return p

# ── Interactivity ──────────────────────────────────────────────────────────────

func _update_all_layer_interactivity() -> void:
	# Every layer stays visible in BOTH modes — the menu objects are never swapped out.
	var allow_select: bool = not _grid_mode and not _adding_thrustpoint
	for layer_name: String in _all_layer_names:
		var eo: EditableObjectNode = _placed.get(layer_name, null)
		if eo == null or not is_instance_valid(eo):
			continue
		eo.set_gameplay_mode(not _is_open)
		eo.visible = true
		if _is_open:
			eo.gif_paused = true
			eo.reset_gif()
			eo.mouse_filter = Control.MOUSE_FILTER_STOP if allow_select else Control.MOUSE_FILTER_IGNORE
		else:
			eo.gif_paused = false
			# In gameplay the live menu objects never grab the mouse — main_menu.gd drives
			# button hover/click by hit-testing their rects directly (robust regardless of how
			# Control picking orders the full-rect container + Node2D enemy backdrop).
			eo.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_canvas_object_clicked(obj: EditableObjectNode) -> void:
	var layer_name := _name_of(obj)
	if _is_open:
		if _grid_mode or _adding_thrustpoint:
			return
		if not layer_name.is_empty():
			_set_active_layer(layer_name)
	else:
		var base := layer_name.to_lower()
		if base in BUTTON_LAYERS and on_button.is_valid():
			on_button.call(base)

# ── Grid / zoom sync ─────────────────────────────────────────────────────────────

func _reset_zoom() -> void:
	_zoom = 1.0
	if _objects_container != null and is_instance_valid(_objects_container):
		_objects_container.position = Vector2.ZERO
		_objects_container.scale    = Vector2.ONE
	if _grid_overlay != null:
		_grid_overlay.zoom          = 1.0
		_grid_overlay.canvas_offset = Vector2.ZERO

func _apply_zoom(mouse_vp: Vector2) -> void:
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var old_offset := _objects_container.position
	var old_zoom   := _objects_container.scale.x
	_objects_container.position = mouse_vp + (old_offset - mouse_vp) * (_zoom / old_zoom)
	_objects_container.scale    = Vector2(_zoom, _zoom)
	_update_grid_overlay()

func _update_grid_overlay() -> void:
	if _grid_overlay == null:
		return
	_grid_overlay.thrust_points   = _thrust_points.get(_active_layer, [])
	_grid_overlay.selected_tp_idx = _selected_tp_idx
	if _objects_container != null and is_instance_valid(_objects_container):
		_grid_overlay.zoom          = _zoom
		_grid_overlay.canvas_offset = _objects_container.position
	_refresh_plume_preview()

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
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
			var tps: Array = _thrust_points.get(_active_layer, [])
			if not _selected_tp_indices.is_empty():
				for sel_idx: int in _selected_tp_indices:
					if sel_idx >= 0 and sel_idx < tps.size():
						tps[sel_idx]["pos"] = (tps[sel_idx]["pos"] as Vector2) + dir
				_thrust_points[_active_layer] = tps
				_dirty = true
				_refresh_tp_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif is_instance_valid(_selected_obj):
				if not ke.echo:
					_push_undo_transform(_selected_obj)
				_selected_obj.position += dir
				_refresh_transform_panel()
				_dirty = true
				get_viewport().set_input_as_handled()
				return

	# Asset panel drag
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

	# Control panel drag
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
			if _selected_tp_idx >= 0:
				_delete_selected_tp()
			elif is_instance_valid(_selected_obj):
				_delete_selected()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.keycode == KEY_ESCAPE:
			if _adding_thrustpoint:
				_adding_thrustpoint = false
				_add_tp_btn.button_pressed = false
				_update_all_layer_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_layer_interactivity()
				get_viewport().set_input_as_handled()
				return
			_request_close()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var in_panels := _asset_panel.get_global_rect().has_point(mb.position) \
					  or _ctrl_panel.get_global_rect().has_point(mb.position)
		if mb.pressed and not in_panels and \
				(mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := ZOOM_RATIO if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_RATIO)
			_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom(mb.position)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not in_panels:
			if _adding_thrustpoint:
				_add_thrustpoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not in_panels:
			if _adding_thrustpoint:
				_adding_thrustpoint = false
				_add_tp_btn.button_pressed = false
				_update_all_layer_interactivity()
			elif _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_layer_interactivity()
			else:
				_select_obj(null)
				_select_tp(-1)
			get_viewport().set_input_as_handled()

func _on_asset_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_asset = true
			_drag_asset_off = _asset_panel.global_position - get_viewport().get_mouse_position()

func _on_ctrl_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_ctrl = true
			_drag_ctrl_off = _ctrl_panel.global_position - get_viewport().get_mouse_position()

# ── Delete ─────────────────────────────────────────────────────────────────────

func _delete_selected() -> void:
	if not is_instance_valid(_selected_obj):
		return
	var layer_name := _active_layer
	_push_undo_delete(_selected_obj, layer_name)
	_deleted[layer_name] = true          # persist the deletion — never auto-respawn
	_placed.erase(layer_name)
	_selected_obj.queue_free()
	_select_obj(null)
	_build_layer_buttons()               # drop it from the OBJECTS table
	_active_layer = ""
	_set_active_layer(_first_live_layer())
	_dirty = true

# ── Undo ───────────────────────────────────────────────────────────────────────

func _push_undo_transform(obj: EditableObjectNode) -> void:
	_undo_stack.append({"type": "transform", "obj": obj,
		"pos": obj.position, "size": obj.size, "z": obj.z_index})

func _push_undo_delete(obj: EditableObjectNode, layer_name: String) -> void:
	_undo_stack.append({
		"type":  "delete",
		"tex":   obj.texture_rect.texture if obj.texture_rect != null else null,
		"path":  obj.source_path,
		"layer": layer_name,
		"pos":   obj.position,
		"size":  obj.size,
		"z":     obj.z_index,
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
				obj.z_index  = int(entry["z"])
				obj._sync_rect_size()
				_refresh_transform_panel()
		"delete":
			var tex: Texture2D = entry["tex"]
			if tex == null:
				return
			_deleted.erase(entry["layer"])   # un-delete (restore)
			var eo := _place_layer_eo(entry["layer"], tex, entry["path"], entry["pos"], entry["size"])
			if eo != null:
				eo.z_index = int(entry["z"])
				_update_all_layer_interactivity()
				_build_layer_buttons()
	_dirty = not _undo_stack.is_empty()

# ── Persistence ────────────────────────────────────────────────────────────────

func _save_layout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_PATH)
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "deleted", _deleted.keys())
	for layer_name: String in _all_layer_names:
		if _deleted.has(layer_name):
			# Purge any stale entries so a deleted layer can't be revived from the cfg.
			if cfg.has_section_key("layers", layer_name):
				cfg.erase_section_key("layers", layer_name)
			if cfg.has_section_key("thrustpoints", layer_name):
				cfg.erase_section_key("thrustpoints", layer_name)
			continue
		var eo: EditableObjectNode = _placed.get(layer_name, null)
		if eo != null and is_instance_valid(eo):
			cfg.set_value("layers", layer_name, {
				"path":    eo.source_path,
				"pos":     eo.position,
				"size":    eo.size,
				"z_index": eo.z_index,
			})
		var tp_data: Array[Dictionary] = []
		for tp: Dictionary in _thrust_points.get(layer_name, []):
			tp_data.append({"pos": tp["pos"], "id": tp.get("id", 0), "dir_angle": tp.get("dir_angle", 0.0)})
		cfg.set_value("thrustpoints", layer_name, tp_data)
	cfg.save(LAYOUT_PATH)
	_save_plume_styles()
	_dirty = false
	show_toast("Saved mainmenu_layout.cfg")

func _load_layout() -> void:
	if _objects_container == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	_deleted.clear()
	for dn in cfg.get_value("meta", "deleted", []):
		_deleted[String(dn)] = true
	for layer_name: String in _all_layer_names:
		if _deleted.has(layer_name):
			continue   # stay deleted — don't recreate from cfg
		# EO
		if not _placed.has(layer_name) or not is_instance_valid(_placed.get(layer_name, null)):
			var entry: Dictionary = cfg.get_value("layers", layer_name, {})
			if not entry.is_empty():
				var path: String = entry.get("path", MENU_FOLDER + layer_name + ".png")
				var tex := _load_full_tex(path)
				if tex != null:
					var eo := _place_layer_eo(layer_name, tex, path,
						entry.get("pos", Vector2(600.0, 380.0)),
						entry.get("size", Vector2(240.0, 119.0)))
					if eo != null:
						eo.z_index = int(entry.get("z_index", 10))
		# Thrust points
		_thrust_points[layer_name] = []
		var max_tp_id := 0
		for tp: Dictionary in cfg.get_value("thrustpoints", layer_name, []):
			var tp_id: int = tp.get("id", max_tp_id + 1)
			_thrust_points[layer_name].append({"pos": tp.get("pos", Vector2.ZERO), "id": tp_id, "dir_angle": tp.get("dir_angle", 0.0)})
			max_tp_id = maxi(max_tp_id, tp_id)
		_tp_id_counter[layer_name] = max_tp_id + 1

func _load_plume_styles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PLUME_STYLES_PATH) != OK:
		return
	if not cfg.has_section("styles"):
		return
	for key: String in cfg.get_section_keys("styles"):
		_plume_styles[key] = cfg.get_value("styles", key, _default_plume_style())

func _save_plume_styles() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PLUME_STYLES_PATH)
	for lname: String in _plume_styles:
		cfg.set_value("styles", lname, _plume_styles[lname])
	cfg.save(PLUME_STYLES_PATH)

# ── Asset loading ──────────────────────────────────────────────────────────────

func _load_full_tex(path: String) -> Texture2D:
	var ext := path.get_extension().to_lower()
	if ext == "gif":
		return GifLoader.load_gif(path)
	if ext == "png":
		var json_path := path.get_basename() + ".json"
		if FileAccess.open(json_path, FileAccess.READ) != null:
			var PngSpriteLoader := preload("res://scripts/ui/edit_mode/png_sprite_loader.gd")
			return PngSpriteLoader.load_png_sprite(path)
	# Read straight off disk first (works whether or not Godot imported it — the mainmenu
	# PNGs may not have .import files yet); fall back to the resource loader otherwise.
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return load(path) as Texture2D

# ── Toast ──────────────────────────────────────────────────────────────────────

func show_toast(message: String) -> void:
	_toast_label.text    = message
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
