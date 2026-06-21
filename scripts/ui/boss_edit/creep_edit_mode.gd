extends CanvasLayer
## Creep Edit Mode — place enemy sprites, mark Fire Points and Thrust Points.
## Opened via the Creep_edit button (Devon dev panel). Saves to res://creep_layout.cfg.

const EditableObject  := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader       := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const GridOverlay     := preload("res://scripts/ui/boss_edit/grid_overlay.gd")
const LAYOUT_PATH       := "res://creep_layout.cfg"
const PLUME_STYLES_PATH := "res://plume_styles.cfg"
const ENEMIES_FOLDER    := "res://assets/enemies/"
const ASSET_PANEL_W     := 210.0
const CTRL_PANEL_W      := 224.0
const SCREEN_ORIGIN     := Vector2(15.0, 8.0)

# ── State ──────────────────────────────────────────────────────────────────────
var _is_open:          bool   = false
var _dirty:            bool   = false
var _active_creep:     String = ""
var _all_creep_names:  Array[String] = []
var _placed:           Dictionary = {}  # creep_name -> EditableObjectNode (one per creep)
var _selected_obj:     EditableObjectNode = null
var _creep_buttons:    Dictionary = {}  # creep_name -> Button
var _objects_container: Control = null

# Point state — Fire Points (FP) and Thrust Points (TP)
var _adding_firepoint:   bool = false
var _adding_thrustpoint: bool = false
var _fire_points:        Dictionary = {}  # creep_name -> Array[{pos, id, dir_angle}]
var _thrust_points:      Dictionary = {}  # creep_name -> Array[{pos, id, dir_angle}]
var _fp_id_counter:      Dictionary = {}  # creep_name -> int
var _tp_id_counter:      Dictionary = {}  # creep_name -> int
var _selected_fp_idx:     int        = -1
var _selected_tp_idx:     int        = -1   # primary (last clicked) — used for angle UI + plume editor
var _selected_tp_indices: Array[int] = []   # full multi-selection set

# ── UI ─────────────────────────────────────────────────────────────────────────
var _dim_overlay:    ColorRect     = null
var _asset_panel:    Panel         = null
var _asset_vbox:     VBoxContainer = null
var _fp_vbox:        VBoxContainer = null
var _tp_vbox:        VBoxContainer = null
var _ctrl_panel:     Panel         = null
var _creep_btn_vbox: VBoxContainer = null
var _sz_w_spin:      SpinBox       = null
var _sz_h_spin:      SpinBox       = null
var _z_spin:         SpinBox       = null
var _zoom_slider:    HSlider       = null
var _zoom_pct_lbl:   Label         = null
var _delete_btn:     Button        = null
var _grid_btn:       Button        = null
var _add_fp_btn:     Button        = null
var _add_tp_btn:     Button        = null
var _toast_label:    Label         = null
var _grid_overlay:   Control       = null
var _fp_angle_row:   Control       = null
var _fp_angle_spin:  SpinBox       = null
var _tp_angle_row:   Control       = null
var _tp_angle_spin:  SpinBox       = null
var _save_confirm_dlg: ConfirmationDialog = null

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
var _plume_styles:        Dictionary        = {}  # cname → {"tp_N": style_dict}
var _plume_tp_label:      Label             = null
var _updating_plume:      bool              = false

# Plume preview nodes (shown in edit mode so TPs can be verified visually)
var _preview_plumes:    Array[CPUParticles2D] = []

# Panel drag state
var _dragging_asset:    bool    = false
var _drag_asset_off:    Vector2 = Vector2.ZERO
var _dragging_ctrl:     bool    = false
var _drag_ctrl_off:     Vector2 = Vector2.ZERO
var _eo_drag_undo_pushed: bool  = false
var _updating_spin:    bool    = false
var _grid_mode:        bool    = false
var _undo_stack: Array[Dictionary] = []

# Zoom state
var _zoom:     float = 1.0
const ZOOM_MIN := 0.4
const ZOOM_MAX := 5.0
const ZOOM_RATIO := 1.15

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("creep_edit")
	_scan_creeps()
	_build_ui()
	_build_creep_buttons()
	_set_ui_visible(false)

func setup(objects_container: Control) -> void:
	_objects_container = objects_container
	_load_layout()
	_load_plume_styles()
	_update_gameplay_visibility()

func is_open() -> bool:
	return _is_open

# ── Folder scan ────────────────────────────────────────────────────────────────

func _scan_creeps() -> void:
	_all_creep_names.clear()
	var dir := DirAccess.open(ENEMIES_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var ext := entry.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "gif"]:
				var name := entry.get_basename()
				_all_creep_names.append(name)
		entry = dir.get_next()
	dir.list_dir_end()
	_all_creep_names.sort()

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

# ── LEFT panel: layers + points ────────────────────────────────────────────────

func _build_asset_panel() -> void:
	_asset_panel = Panel.new()
	_asset_panel.size     = Vector2(ASSET_PANEL_W, 890.0)
	_asset_panel.position = Vector2(20.0, 44.0)
	add_child(_asset_panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	_asset_panel.add_child(root)

	# LAYERS section
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
	layers_scroll.custom_minimum_size = Vector2(0.0, 60.0)
	layers_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(layers_scroll)
	_asset_vbox = VBoxContainer.new()
	_asset_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_vbox.add_theme_constant_override("separation", 2)
	layers_scroll.add_child(_asset_vbox)

	# FIRE POINTS section
	root.add_child(HSeparator.new())
	var fp_hdr := Label.new()
	fp_hdr.text = "FIRE POINTS"
	fp_hdr.add_theme_font_size_override("font_size", 11)
	fp_hdr.modulate = Color(1.0, 0.55, 0.12)
	root.add_child(fp_hdr)

	var fp_scroll := ScrollContainer.new()
	fp_scroll.custom_minimum_size = Vector2(0.0, 80.0)
	fp_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(fp_scroll)
	_fp_vbox = VBoxContainer.new()
	_fp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fp_vbox.add_theme_constant_override("separation", 2)
	fp_scroll.add_child(_fp_vbox)

	# FP angle row
	_fp_angle_row = HBoxContainer.new()
	_fp_angle_row.visible = false
	_fp_angle_row.add_theme_constant_override("separation", 4)
	root.add_child(_fp_angle_row)
	var fpal := Label.new()
	fpal.text = "Dir:"
	fpal.add_theme_font_size_override("font_size", 10)
	fpal.custom_minimum_size = Vector2(24.0, 0.0)
	_fp_angle_row.add_child(fpal)
	_fp_angle_spin = SpinBox.new()
	_fp_angle_spin.min_value = -180.0
	_fp_angle_spin.max_value = 180.0
	_fp_angle_spin.step = 1.0
	_fp_angle_spin.suffix = "°"
	_fp_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fp_angle_spin.value_changed.connect(func(_v: float) -> void: _on_fp_angle_changed())
	_fp_angle_row.add_child(_fp_angle_spin)

	# THRUST POINTS section
	root.add_child(HSeparator.new())
	var tp_hdr := Label.new()
	tp_hdr.text = "THRUST POINTS"
	tp_hdr.add_theme_font_size_override("font_size", 11)
	tp_hdr.modulate = Color(0.10, 0.90, 0.65)
	root.add_child(tp_hdr)

	var tp_scroll := ScrollContainer.new()
	tp_scroll.custom_minimum_size = Vector2(0.0, 150.0)
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

	# ── TRANSFORM section (W, H, Z + zoom slider) ──
	root.add_child(HSeparator.new())
	var xf_hdr := Label.new()
	xf_hdr.text = "TRANSFORM"
	xf_hdr.add_theme_font_size_override("font_size", 10)
	xf_hdr.modulate = Color(0.60, 0.63, 0.76)
	root.add_child(xf_hdr)

	var sz_row := HBoxContainer.new()
	sz_row.add_theme_constant_override("separation", 3)
	root.add_child(sz_row)
	_sz_w_spin = _small_spin(sz_row, "W", 1.0, 2000.0, _on_w_spin_changed)
	_sz_h_spin = _small_spin(sz_row, "H", 1.0, 2000.0, _on_h_spin_changed)

	var z_row := HBoxContainer.new()
	z_row.add_theme_constant_override("separation", 3)
	root.add_child(z_row)
	_z_spin = _small_spin(z_row, "Z", -500.0, 500.0)
	var z_spacer := Control.new()
	z_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z_row.add_child(z_spacer)

	# Zoom slider 50%–200%
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	root.add_child(zoom_row)
	var zoom_lbl := Label.new()
	zoom_lbl.text = "Zoom:"
	zoom_lbl.add_theme_font_size_override("font_size", 10)
	zoom_lbl.custom_minimum_size = Vector2(34.0, 0.0)
	zoom_row.add_child(zoom_lbl)
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 50.0
	_zoom_slider.max_value = 200.0
	_zoom_slider.step      = 1.0
	_zoom_slider.value     = 100.0
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	zoom_row.add_child(_zoom_slider)
	_zoom_pct_lbl = Label.new()
	_zoom_pct_lbl.text = "100%"
	_zoom_pct_lbl.add_theme_font_size_override("font_size", 10)
	_zoom_pct_lbl.custom_minimum_size = Vector2(36.0, 0.0)
	_zoom_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_row.add_child(_zoom_pct_lbl)

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

	# Velocity min / max
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

	# Lifetime + Spread
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

	# Scale min / max
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

	# Gradient colors: Core → Flame → Cool
	var col_row := HBoxContainer.new()
	col_row.add_theme_constant_override("separation", 3)
	root.add_child(col_row)
	_plume_col_core_btn  = _mk_pcol_vbox(col_row, "Core",  Color(1.0, 0.95, 0.7, 1.0))
	_plume_col_flame_btn = _mk_pcol_vbox(col_row, "Flame", Color(1.0, 0.6,  0.2, 1.0))
	_plume_col_cool_btn  = _mk_pcol_vbox(col_row, "Cool",  Color(0.45, 0.6, 1.0, 0.85))

	_save_confirm_dlg = ConfirmationDialog.new()
	_save_confirm_dlg.ok_button_text = "Overwrite"
	add_child(_save_confirm_dlg)

# ── RIGHT panel ────────────────────────────────────────────────────────────────

func _build_ctrl_panel() -> void:
	_ctrl_panel = Panel.new()
	var _vp_w: float = get_viewport().get_visible_rect().size.x
	_ctrl_panel.size     = Vector2(CTRL_PANEL_W, 730.0)
	_ctrl_panel.position = Vector2(_vp_w - CTRL_PANEL_W - 20.0, 44.0)
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
	tl.text = "CREEP EDIT"
	tl.add_theme_font_size_override("font_size", 13)
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tl)

	_add_section(root, "ENEMIES")
	var creep_scroll := ScrollContainer.new()
	creep_scroll.custom_minimum_size = Vector2(0.0, 240.0)
	creep_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(creep_scroll)
	_creep_btn_vbox = VBoxContainer.new()
	_creep_btn_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creep_btn_vbox.add_theme_constant_override("separation", 2)
	creep_scroll.add_child(_creep_btn_vbox)

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

	_add_tp_btn = Button.new()
	_add_tp_btn.text = "Add TP"
	_add_tp_btn.toggle_mode = true
	_add_tp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_tp_btn.pressed.connect(_toggle_adding_thrustpoint)
	mode_row.add_child(_add_tp_btn)

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
	close_btn.text = "Close"
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

func _build_creep_buttons() -> void:
	for child in _creep_btn_vbox.get_children():
		child.queue_free()
	_creep_buttons.clear()
	for creep_name: String in _all_creep_names:
		var btn := Button.new()
		btn.text = creep_name
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_set_active_creep.bind(creep_name))
		_creep_btn_vbox.add_child(btn)
		_creep_buttons[creep_name] = btn

# ── Layer list (left panel) ────────────────────────────────────────────────────

func _refresh_layer_list() -> void:
	for child in _asset_vbox.get_children():
		child.queue_free()
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo):
		_asset_vbox.add_child(_make_layer_row(eo))

func _make_layer_row(eo: EditableObjectNode) -> Control:
	var is_selected: bool = (eo == _selected_obj)
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

	var name_lbl := Label.new()
	name_lbl.text = eo.source_path.get_file().get_basename()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.clip_text = true
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var cap_eo := eo
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			_select_obj(cap_eo)
	)
	return row

func _get_eo_thumbnail(eo: EditableObjectNode) -> Texture2D:
	var t := eo.texture_rect.texture
	if t != null and t.has_meta("gif_frames"):
		var frames: Array = t.get_meta("gif_frames")
		if not frames.is_empty():
			return frames[0] as Texture2D
	return t

# ── Open / Close ───────────────────────────────────────────────────────────────

func toggle() -> void:
	if not _is_open:
		_is_open = true
		_grid_overlay.is_edit_open = true
		_set_ui_visible(true)
		get_tree().paused = true
		_reset_zoom()
		_update_all_creep_interactivity()
		if _active_creep.is_empty() and not _all_creep_names.is_empty():
			_set_active_creep(_all_creep_names[0])
		else:
			_set_active_creep(_active_creep)
	else:
		_request_close()

func _request_close() -> void:
	if _dirty:
		_save_layout()
	_close()

func _close() -> void:
	_is_open = false
	_grid_mode = false
	_adding_firepoint  = false
	_adding_thrustpoint = false
	_grid_btn.button_pressed  = false
	_add_fp_btn.button_pressed = false
	_add_tp_btn.button_pressed = false
	_grid_overlay.show_grid    = false
	_grid_overlay.is_edit_open = false
	_reset_zoom()
	_select_fp(-1)
	_select_tp(-1)
	_set_ui_visible(false)
	_select_obj(null)
	_update_all_creep_interactivity()
	_update_gameplay_visibility()
	get_tree().paused = false

func _set_ui_visible(v: bool) -> void:
	_dim_overlay.visible = v
	_asset_panel.visible = v
	_ctrl_panel.visible  = v
	if not v:
		for p: CPUParticles2D in _preview_plumes:
			if is_instance_valid(p):
				p.queue_free()
		_preview_plumes.clear()
		_dragging_asset      = false
		_dragging_ctrl       = false
		_eo_drag_undo_pushed = false

# ── Active creep ───────────────────────────────────────────────────────────────

func _set_active_creep(creep_name: String) -> void:
	if creep_name.is_empty():
		return
	_active_creep = creep_name
	if not _placed.has(creep_name) or not is_instance_valid(_placed.get(creep_name, null)):
		_load_or_create_creep(creep_name)
	if not _fire_points.has(creep_name):
		_fire_points[creep_name] = []
	if not _thrust_points.has(creep_name):
		_thrust_points[creep_name] = []
	_select_obj(null)
	_selected_fp_idx = -1
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	_eo_drag_undo_pushed = false
	_update_all_creep_interactivity()
	_update_grid_overlay()
	_refresh_fp_list()
	_refresh_tp_list()
	_refresh_fp_angle_ui()
	_refresh_tp_angle_ui()
	_refresh_layer_list()
	_refresh_transform_panel()
	_refresh_plume_editor()
	for name: String in _creep_buttons:
		(_creep_buttons[name] as Button).button_pressed = (name == creep_name)

func _load_or_create_creep(creep_name: String) -> void:
	if _placed.has(creep_name) and is_instance_valid(_placed.get(creep_name, null)):
		return
	# Try to find the file (png or gif)
	for ext: String in ["png", "gif", "jpg", "jpeg"]:
		var path: String = ENEMIES_FOLDER + creep_name + "." + ext
		var tex := _load_full_tex(path)
		if tex == null:
			continue
		var tex_w := float(tex.get_width())
		var tex_h := float(tex.get_height())
		var aspect := tex_h / tex_w if tex_w > 0.0 else 1.0
		var sz := Vector2(60.0, 60.0 * aspect)
		_place_creep_eo(creep_name, tex, path, Vector2(480.0, 380.0), sz)
		return

func _place_creep_eo(creep_name: String, tex: Texture2D, path: String,
		pos: Vector2, sz: Vector2) -> EditableObjectNode:
	if _objects_container == null:
		return null
	var eo: EditableObjectNode = EditableObject.instantiate()
	eo.group_id    = "creep_" + creep_name
	eo.source_path = path
	_objects_container.add_child(eo)
	eo.init(tex, pos, sz)
	eo.z_index     = 115
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eo.object_clicked.connect(_on_canvas_object_clicked)
	eo.transform_ended.connect(_on_transform_ended)
	eo.transform_motion.connect(_on_transform_motion)
	_placed[creep_name] = eo
	return eo

# ── Selection & transform ──────────────────────────────────────────────────────

func _select_obj(obj: EditableObjectNode) -> void:
	if is_instance_valid(_selected_obj):
		_selected_obj.selected = false
	_selected_obj = obj
	if is_instance_valid(obj):
		obj.selected = true
	_delete_btn.disabled = not is_instance_valid(obj)
	_refresh_transform_panel()
	_refresh_layer_list()

func _refresh_transform_panel() -> void:
	_updating_spin = true
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo):
		_sz_w_spin.value = eo.size.x
		_sz_h_spin.value = eo.size.y
		_z_spin.value    = eo.z_index
	else:
		_sz_w_spin.value = 0.0
		_sz_h_spin.value = 0.0
		_z_spin.value    = 0.0
	_updating_spin = false

func _on_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	_apply_spin_to_selected()

func _on_w_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo) and eo._aspect_ratio > 0.0:
		_updating_spin = true
		_sz_h_spin.value = snappedf(_sz_w_spin.value / eo._aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_selected()

func _on_h_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo) and eo._aspect_ratio > 0.0:
		_updating_spin = true
		_sz_w_spin.value = snappedf(_sz_h_spin.value * eo._aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_selected()

func _apply_spin_to_selected() -> void:
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
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

# ── Grid mode ──────────────────────────────────────────────────────────────────

func _toggle_grid_mode() -> void:
	_grid_mode = _grid_btn.button_pressed
	if _grid_mode:
		_adding_firepoint   = false
		_adding_thrustpoint = false
		_add_fp_btn.button_pressed = false
		_add_tp_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
	_update_all_creep_interactivity()
	_grid_overlay.show_grid    = _grid_mode
	_grid_overlay.is_edit_open = _is_open

func _toggle_adding_firepoint() -> void:
	_adding_firepoint = _add_fp_btn.button_pressed
	if _adding_firepoint:
		_adding_thrustpoint = false
		_add_tp_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
	_update_all_creep_interactivity()

func _toggle_adding_thrustpoint() -> void:
	_adding_thrustpoint = _add_tp_btn.button_pressed
	if _adding_thrustpoint:
		_adding_firepoint = false
		_add_fp_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
	_update_all_creep_interactivity()

# ── Fire Points ────────────────────────────────────────────────────────────────

func _add_firepoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _fire_points.has(_active_creep):
		_fire_points[_active_creep] = []
		_fp_id_counter[_active_creep] = 1
	var fp_id: int = _fp_id_counter.get(_active_creep, 1)
	_fire_points[_active_creep].append({"pos": ss_pos, "id": fp_id, "dir_angle": 0.0})
	_fp_id_counter[_active_creep] = fp_id + 1
	_dirty = true
	_refresh_fp_list()
	_update_grid_overlay()

func _select_fp(idx: int) -> void:
	_selected_fp_idx = idx
	if idx >= 0:
		_select_obj(null)
		_selected_tp_idx = -1
		_selected_tp_indices.clear()
		_refresh_plume_editor()
	_refresh_fp_list()
	_update_grid_overlay()
	_refresh_fp_angle_ui()

func _delete_selected_fp() -> void:
	var fps: Array = _fire_points.get(_active_creep, [])
	if _selected_fp_idx < 0 or _selected_fp_idx >= fps.size():
		return
	fps.remove_at(_selected_fp_idx)
	_fire_points[_active_creep] = fps
	_selected_fp_idx = -1
	_dirty = true
	_refresh_fp_list()
	_update_grid_overlay()

func _refresh_fp_angle_ui() -> void:
	var show := _selected_fp_idx >= 0
	_fp_angle_row.visible = show
	if not show:
		return
	var fps: Array = _fire_points.get(_active_creep, [])
	if _selected_fp_idx >= fps.size():
		return
	_updating_spin = true
	_fp_angle_spin.value = snappedf(rad_to_deg(float(fps[_selected_fp_idx].get("dir_angle", 0.0))), 1.0)
	_updating_spin = false

func _on_fp_angle_changed() -> void:
	if _updating_spin or _selected_fp_idx < 0:
		return
	var fps: Array = _fire_points.get(_active_creep, [])
	if _selected_fp_idx >= fps.size():
		return
	fps[_selected_fp_idx]["dir_angle"] = deg_to_rad(_fp_angle_spin.value)
	_fire_points[_active_creep] = fps
	_dirty = true
	_update_grid_overlay()

func _refresh_fp_list() -> void:
	for child in _fp_vbox.get_children():
		child.queue_free()
	var fps: Array = _fire_points.get(_active_creep, [])
	for i: int in fps.size():
		_fp_vbox.add_child(_make_point_row(fps[i], i, true))

# ── Thrust Points ──────────────────────────────────────────────────────────────

func _add_thrustpoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _thrust_points.has(_active_creep):
		_thrust_points[_active_creep] = []
		_tp_id_counter[_active_creep] = 1
	var tp_id: int = _tp_id_counter.get(_active_creep, 1)
	_thrust_points[_active_creep].append({"pos": ss_pos, "id": tp_id, "dir_angle": PI * 0.5})
	_tp_id_counter[_active_creep] = tp_id + 1
	_dirty = true
	_refresh_tp_list()
	_update_grid_overlay()

func _select_tp(idx: int) -> void:
	_selected_tp_idx = idx
	_selected_tp_indices.clear()
	if idx >= 0:
		_selected_tp_indices.append(idx)
	if idx >= 0:
		_select_obj(null)
		_selected_fp_idx = -1
	_refresh_tp_list()
	_update_grid_overlay()
	_refresh_tp_angle_ui()
	_refresh_plume_editor()

func _select_tp_add(idx: int) -> void:
	if idx < 0:
		return
	_select_obj(null)
	_selected_fp_idx = -1
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
	var tps: Array = _thrust_points.get(_active_creep, [])
	var sorted: Array[int] = _selected_tp_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for idx: int in sorted:
		if idx >= 0 and idx < tps.size():
			tps.remove_at(idx)
	_thrust_points[_active_creep] = tps
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
	var tps: Array = _thrust_points.get(_active_creep, [])
	if _selected_tp_idx >= tps.size():
		return
	_updating_spin = true
	_tp_angle_spin.value = snappedf(rad_to_deg(float(tps[_selected_tp_idx].get("dir_angle", 0.0))), 1.0)
	_updating_spin = false

func _on_tp_angle_changed() -> void:
	if _updating_spin or _selected_tp_indices.is_empty():
		return
	var tps: Array = _thrust_points.get(_active_creep, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx >= 0 and sel_idx < tps.size():
			tps[sel_idx]["dir_angle"] = deg_to_rad(_tp_angle_spin.value)
	_thrust_points[_active_creep] = tps
	_dirty = true
	_update_grid_overlay()

func _refresh_tp_list() -> void:
	for child in _tp_vbox.get_children():
		child.queue_free()
	var tps: Array = _thrust_points.get(_active_creep, [])
	for i: int in tps.size():
		_tp_vbox.add_child(_make_point_row(tps[i], i, false))

func _make_point_row(pt: Dictionary, idx: int, is_fp: bool) -> Control:
	var is_sel: bool = (idx == _selected_fp_idx) if is_fp else _selected_tp_indices.has(idx)
	var col_sel  := Color(0.25, 0.85, 1.0, 0.38) if is_fp else Color(0.10, 0.80, 0.55, 0.38)
	var col_id   := Color(0.25, 0.85, 1.0) if is_fp else Color(0.10, 0.90, 0.65)
	var id_sel   := Color(1.0, 0.55, 0.12) if is_fp else Color(0.10, 0.75, 0.55)

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
	var prefix       := "FP" if is_fp else "TP"

	var id_lbl := Label.new()
	id_lbl.text = "%s%d" % [prefix, pt_id]
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
			if is_fp:
				_select_fp(cap_idx)
			elif Input.is_key_pressed(KEY_SHIFT):
				_select_tp_add(cap_idx)
			else:
				_select_tp(cap_idx)
	)
	return row

# ── Grid overlay sync ──────────────────────────────────────────────────────────

func _reset_zoom() -> void:
	_zoom = 1.0
	if _objects_container != null and is_instance_valid(_objects_container):
		_objects_container.position = Vector2.ZERO
		_objects_container.scale    = Vector2.ONE
	if _grid_overlay != null:
		_grid_overlay.zoom          = 1.0
		_grid_overlay.canvas_offset = Vector2.ZERO
	_sync_zoom_slider()

func _apply_zoom(mouse_vp: Vector2) -> void:
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var old_offset := _objects_container.position
	var old_zoom   := _objects_container.scale.x
	_objects_container.position = mouse_vp + (old_offset - mouse_vp) * (_zoom / old_zoom)
	_objects_container.scale    = Vector2(_zoom, _zoom)
	_sync_zoom_slider()
	_update_grid_overlay()

func _sync_zoom_slider() -> void:
	if _zoom_slider == null or _updating_spin:
		return
	_updating_spin = true
	_zoom_slider.value = clampf(_zoom * 100.0, _zoom_slider.min_value, _zoom_slider.max_value)
	if _zoom_pct_lbl != null:
		_zoom_pct_lbl.text = "%d%%" % int(round(_zoom * 100.0))
	_updating_spin = false

func _on_zoom_slider_changed(value: float) -> void:
	if _updating_spin:
		return
	_zoom = value / 100.0
	var center := get_viewport().get_visible_rect().size * 0.5
	_apply_zoom(center)
	if _zoom_pct_lbl != null:
		_zoom_pct_lbl.text = "%d%%" % int(round(value))

func _update_grid_overlay() -> void:
	if _grid_overlay == null:
		return
	_grid_overlay.fire_points     = _fire_points.get(_active_creep, [])
	_grid_overlay.selected_fp_idx = _selected_fp_idx
	_grid_overlay.thrust_points   = _thrust_points.get(_active_creep, [])
	_grid_overlay.selected_tp_idx = _selected_tp_idx
	if _objects_container != null and is_instance_valid(_objects_container):
		_grid_overlay.zoom          = _zoom
		_grid_overlay.canvas_offset = _objects_container.position
	_refresh_plume_preview()

func _refresh_plume_preview() -> void:
	for p: CPUParticles2D in _preview_plumes:
		if is_instance_valid(p):
			p.queue_free()
	_preview_plumes.clear()
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var cmap: Dictionary = _plume_styles.get(_active_creep, {})
	var tps: Array = _thrust_points.get(_active_creep, [])
	for i: int in tps.size():
		var tp: Dictionary = tps[i]
		var tp_id: int = int(tp.get("id", i + 1))
		var style: Dictionary = cmap.get("tp_%d" % tp_id, _default_plume_style())
		var ss_pos: Vector2 = tp["pos"]
		var dir_angle: float = float(tp.get("dir_angle", PI * 0.5))
		var p := _make_preview_plume(ss_pos + SCREEN_ORIGIN, dir_angle, style)
		_objects_container.add_child(p)
		_preview_plumes.append(p)

func _make_preview_plume(oc_pos: Vector2, dir_angle: float, style: Dictionary = {}) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = oc_pos
	p.amount = 20
	p.lifetime  = float(style.get("lifetime", 0.35))
	p.local_coords = true
	p.emitting = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = false
	p.z_index = 200
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

func _update_all_creep_interactivity() -> void:
	var allow_select: bool = not _grid_mode and not _adding_firepoint and not _adding_thrustpoint
	for creep_name: String in _all_creep_names:
		var eo: EditableObjectNode = _placed.get(creep_name, null)
		if eo == null or not is_instance_valid(eo):
			continue
		var is_active: bool = _is_open and creep_name == _active_creep
		eo.set_gameplay_mode(not _is_open)
		eo.visible = is_active if _is_open else false
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

func _update_gameplay_visibility() -> void:
	for creep_name: String in _all_creep_names:
		var eo: EditableObjectNode = _placed.get(creep_name, null)
		if eo != null and is_instance_valid(eo):
			eo.visible = false

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
			var fps: Array = _fire_points.get(_active_creep, [])
			var tps: Array = _thrust_points.get(_active_creep, [])
			if _selected_fp_idx >= 0 and _selected_fp_idx < fps.size():
				fps[_selected_fp_idx]["pos"] = (fps[_selected_fp_idx]["pos"] as Vector2) + dir
				_fire_points[_active_creep] = fps
				_dirty = true
				_refresh_fp_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif not _selected_tp_indices.is_empty():
				for sel_idx: int in _selected_tp_indices:
					if sel_idx >= 0 and sel_idx < tps.size():
						tps[sel_idx]["pos"] = (tps[sel_idx]["pos"] as Vector2) + dir
				_thrust_points[_active_creep] = tps
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
			if _selected_fp_idx >= 0:
				_delete_selected_fp()
			elif _selected_tp_idx >= 0:
				_delete_selected_tp()
			elif is_instance_valid(_selected_obj):
				_delete_selected()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.keycode == KEY_ESCAPE:
			if _adding_firepoint:
				_adding_firepoint = false
				_add_fp_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _adding_thrustpoint:
				_adding_thrustpoint = false
				_add_tp_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			_request_close()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var in_panels := _asset_panel.get_global_rect().has_point(mb.position) \
					  or _ctrl_panel.get_global_rect().has_point(mb.position)
		# ── Scroll zoom ──
		if mb.pressed and not in_panels and \
				(mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := ZOOM_RATIO if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_RATIO)
			_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom(mb.position)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not in_panels:
			if _adding_firepoint:
				_add_firepoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
			if _adding_thrustpoint:
				_add_thrustpoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not in_panels:
			if _adding_firepoint:
				_adding_firepoint = false
				_add_fp_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _adding_thrustpoint:
				_adding_thrustpoint = false
				_add_tp_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_creep_interactivity()
			else:
				_select_obj(null)
				_select_fp(-1)
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
	var creep_name := _active_creep
	_push_undo_delete(_selected_obj, creep_name)
	_placed.erase(creep_name)
	_selected_obj.queue_free()
	_select_obj(null)
	_refresh_layer_list()
	_dirty = true

# ── Undo ───────────────────────────────────────────────────────────────────────

func _push_undo_transform(obj: EditableObjectNode) -> void:
	_undo_stack.append({"type": "transform", "obj": obj,
		"pos": obj.position, "size": obj.size})

func _push_undo_delete(obj: EditableObjectNode, creep_name: String) -> void:
	_undo_stack.append({
		"type":  "delete",
		"tex":   obj.texture_rect.texture if obj.texture_rect != null else null,
		"path":  obj.source_path,
		"creep": creep_name,
		"pos":   obj.position,
		"size":  obj.size,
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
			_place_creep_eo(entry["creep"], tex, entry["path"], entry["pos"], entry["size"])
			_refresh_layer_list()
	_dirty = not _undo_stack.is_empty()

# ── Persistence ────────────────────────────────────────────────────────────────

func _save_layout() -> void:
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_PATH)
	cfg.set_value("meta", "version", 1)
	for creep_name: String in _all_creep_names:
		var eo: EditableObjectNode = _placed.get(creep_name, null)
		if eo != null and is_instance_valid(eo):
			cfg.set_value("creeps", creep_name, {
				"path":    eo.source_path,
				"pos":     eo.position,
				"size":    eo.size,
				"z_index": eo.z_index,
			})
		# Fire points
		var fp_data: Array[Dictionary] = []
		for fp: Dictionary in _fire_points.get(creep_name, []):
			fp_data.append({"pos": fp["pos"], "id": fp.get("id", 0), "dir_angle": fp.get("dir_angle", 0.0)})
		cfg.set_value("firepoints", creep_name, fp_data)
		# Thrust points
		var tp_data: Array[Dictionary] = []
		for tp: Dictionary in _thrust_points.get(creep_name, []):
			tp_data.append({"pos": tp["pos"], "id": tp.get("id", 0), "dir_angle": tp.get("dir_angle", 0.0)})
		cfg.set_value("thrustpoints", creep_name, tp_data)
	cfg.save(LAYOUT_PATH)
	_save_plume_styles()
	_dirty = false
	show_toast("Saved creep_layout.cfg")

func _load_layout() -> void:
	if _objects_container == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	for creep_name: String in _all_creep_names:
		# EO
		if not _placed.has(creep_name) or not is_instance_valid(_placed.get(creep_name, null)):
			var entry: Dictionary = cfg.get_value("creeps", creep_name, {})
			if not entry.is_empty():
				var path: String = entry.get("path", "")
				var tex := _load_full_tex(path)
				if tex != null:
					var eo := _place_creep_eo(creep_name, tex, path,
						entry.get("pos", Vector2(480.0, 380.0)),
						entry.get("size", Vector2(60.0, 60.0)))
					if eo != null:
						eo.z_index = entry.get("z_index", 115)
		# Fire points
		_fire_points[creep_name] = []
		var max_fp_id := 0
		for fp: Dictionary in cfg.get_value("firepoints", creep_name, []):
			var fp_id: int = fp.get("id", max_fp_id + 1)
			_fire_points[creep_name].append({"pos": fp.get("pos", Vector2.ZERO), "id": fp_id, "dir_angle": fp.get("dir_angle", 0.0)})
			max_fp_id = maxi(max_fp_id, fp_id)
		_fp_id_counter[creep_name] = max_fp_id + 1
		# Thrust points
		_thrust_points[creep_name] = []
		var max_tp_id := 0
		for tp: Dictionary in cfg.get_value("thrustpoints", creep_name, []):
			var tp_id: int = tp.get("id", max_tp_id + 1)
			_thrust_points[creep_name].append({"pos": tp.get("pos", Vector2.ZERO), "id": tp_id, "dir_angle": tp.get("dir_angle", 0.0)})
			max_tp_id = maxi(max_tp_id, tp_id)
		_tp_id_counter[creep_name] = max_tp_id + 1

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
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

# ── Plume editor helpers (UI construction) ─────────────────────────────────────

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

# ── Plume style data ────────────────────────────────────────────────────────────

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
	if _active_creep.is_empty() or _selected_tp_idx < 0:
		return -1
	var tps: Array = _thrust_points.get(_active_creep, [])
	if _selected_tp_idx >= tps.size():
		return -1
	return int(tps[_selected_tp_idx].get("id", _selected_tp_idx + 1))

func _get_tp_plume_style(tp_id: int) -> Dictionary:
	if _active_creep.is_empty() or tp_id < 0:
		return _default_plume_style()
	if not _plume_styles.has(_active_creep):
		_plume_styles[_active_creep] = {}
	var cmap: Dictionary = _plume_styles[_active_creep]
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
	# Load primary TP's style into the controls
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
	if _updating_plume or _active_creep.is_empty() or _selected_tp_indices.is_empty():
		return
	if not _plume_styles.has(_active_creep):
		_plume_styles[_active_creep] = {}
	var tps: Array = _thrust_points.get(_active_creep, [])
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
		_plume_styles[_active_creep]["tp_%d" % tp_id] = s
	_refresh_plume_preview()
	_dirty = true

func _reset_plume_style() -> void:
	if _active_creep.is_empty() or _selected_tp_indices.is_empty():
		return
	if not _plume_styles.has(_active_creep):
		_plume_styles[_active_creep] = {}
	var tps: Array = _thrust_points.get(_active_creep, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx < 0 or sel_idx >= tps.size():
			continue
		var tp_id: int = int(tps[sel_idx].get("id", sel_idx + 1))
		_plume_styles[_active_creep]["tp_%d" % tp_id] = _default_plume_style()
	_refresh_plume_editor()
	_refresh_plume_preview()
	_dirty = true

# ── Plume style persistence ─────────────────────────────────────────────────────

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
	for cname: String in _plume_styles:
		cfg.set_value("styles", cname, _plume_styles[cname])
	cfg.save(PLUME_STYLES_PATH)

# ── Toast ──────────────────────────────────────────────────────────────────────

func show_toast(message: String) -> void:
	_toast_label.text    = message
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
