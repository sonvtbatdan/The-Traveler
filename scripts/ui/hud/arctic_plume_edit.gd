extends CanvasLayer
class_name ArcticPlumeEdit
## Dev-mode-only Arctic energy-beam-vent tuning — group "arctic_plume_edit", toggled from
## arena_hud_buttons.gd's PLUME EDIT button (Arctic map only). Port of mechanic_plume_edit.gd (see that file's
## header — one vent kind, flat slider list, no Wind controls since straight columns have nothing to drift
## sideways with).
##
## Applies LIVE to the running ArcticPlumes instance (group "arctic_plumes") via apply_beam_settings(...).
## SAVE persists to res://arctic_terrain.cfg via ArcticTerrainSettings — loads/saves the FULL settings dict so
## it never clobbers Terrain Edit's/Light Edit's own keys living in the same file.

const ArcticTerrainSettings := preload("res://scripts/gameplay/arctic/arctic_terrain_settings.gd")

const PANEL_W := 300.0

var _is_open: bool = false
var _panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}
var _sliders: Dictionary = {}
var _value_lbls: Dictionary = {}
var _color_btns: Dictionary = {}
var _status: Label = null

func _ready() -> void:
	layer = 61   # same tier as the other Arctic dev panels
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("arctic_plume_edit")

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's PLUME EDIT button.
func toggle() -> void:
	_is_open = not _is_open
	if _panel != null:
		_panel.visible = _is_open
	if not _is_open:
		return
	if _panel == null:
		_values = ArcticTerrainSettings.load_settings()
		_build_ui()
	_sync_ui_from_values()

func _on_panel_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		_drag_panel = _panel
		_drag_off = _panel.global_position - get_viewport().get_mouse_position()

func _input(event: InputEvent) -> void:
	if not _is_open or _drag_panel == null:
		return
	if event is InputEventMouseMotion:
		var mp := get_viewport().get_mouse_position()
		var vp := get_viewport().get_visible_rect().size
		var np := mp + _drag_off
		np.x = clampf(np.x, 0.0, maxf(0.0, vp.x - _drag_panel.size.x))
		np.y = clampf(np.y, 0.0, maxf(0.0, vp.y - 40.0))
		_drag_panel.position = np
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (event as InputEventMouseButton).pressed:
		_drag_panel = null

func _build_ui() -> void:
	_panel = Panel.new()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_panel.position = Vector2(20.0, 44.0)
	_panel.size = Vector2(PANEL_W, minf(560.0, vp_h - _panel.position.y - 20.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.10, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.60, 0.75, 0.85)
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "☁ PLUME EDIT"
	_font(title, 15, Color(0.85, 0.90, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Drag to move"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input)
	outer.add_child(title)
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	_add_slider(col, "beam_strength", "Beam Strength (thickness + glow)", 0.05, 4.0, 0.05)
	_add_slider(col, "beam_duration", "Beam Duration (seconds visible)", 0.2, 6.0, 0.1)
	_add_slider(col, "beam_density", "Vent Density % (ambient + marked)", 0.0, 100.0, 1.0)
	_add_slider(col, "beam_speed", "Fire Speed (shoot-up px/s)", 100.0, 4000.0, 50.0)
	col.add_child(HSeparator.new())
	var palette_lbl := Label.new()
	palette_lbl.text = "Beam Colors (random pick per vent)"
	_font(palette_lbl, 13, Color(0.85, 0.90, 0.95))
	col.add_child(palette_lbl)
	for i in 6:
		_add_color_row(col, "beam_color_%d" % i, "Color %d" % (i + 1))

	outer.add_child(HSeparator.new())
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)
	var save_btn := Button.new()
	save_btn.text = "SAVE"
	_font_btn(save_btn, 14)
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)
	var reset_btn := Button.new()
	reset_btn.text = "RESET"
	_font_btn(reset_btn, 14)
	reset_btn.pressed.connect(_on_reset)
	btn_row.add_child(reset_btn)
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	_font_btn(close_btn, 14)
	close_btn.pressed.connect(toggle)
	btn_row.add_child(close_btn)

	_status = Label.new()
	_font(_status, 12, Color(0.5, 0.9, 0.5))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status)

func _add_slider(parent: VBoxContainer, key: String, label_text: String, min_v: float, max_v: float, step_v: float) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	_font(lbl, 13, Color(0.85, 0.90, 0.95))
	parent.add_child(lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.custom_minimum_size = Vector2(0.0, 20.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void: _on_value_changed(key, v))
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(56.0, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_font(val_lbl, 13, Color(0.75, 0.8, 0.85))
	row.add_child(val_lbl)
	_sliders[key] = slider
	_value_lbls[key] = val_lbl

func _add_color_row(parent: VBoxContainer, key: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font(lbl, 13, Color(0.85, 0.90, 0.95))
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(70.0, 24.0)
	picker.color_changed.connect(func(c: Color) -> void: _on_color_changed(key, c))
	row.add_child(picker)
	_color_btns[key] = picker

func _sync_ui_from_values() -> void:
	for key: String in _sliders.keys():
		var slider: HSlider = _sliders[key]
		var v: float = float(_values[key])
		slider.set_value_no_signal(v)
		_value_lbls[key].text = _fmt_value(v)
	for key: String in _color_btns.keys():
		var picker: ColorPickerButton = _color_btns[key]
		picker.color = _values[key]
	if _status != null:
		_status.text = ""

func _on_value_changed(key: String, v: float) -> void:
	_values[key] = v
	_value_lbls[key].text = _fmt_value(v)
	_apply_live_beam()
	if _status != null:
		_status.text = ""

## beam_speed runs up to 4000 — "%.2f" on that reads as an overlong "4000.00" that crowds the 56px value
## label, so large values drop to whole-number formatting while the small 0..~4 sliders (strength) keep 2
## decimals of precision.
func _fmt_value(v: float) -> String:
	if absf(v) >= 100.0:
		return "%.0f" % v
	return "%.2f" % v

func _on_color_changed(key: String, c: Color) -> void:
	_values[key] = c
	_apply_live_beam()
	if _status != null:
		_status.text = ""

func _apply_live_beam() -> void:
	var plumes := get_tree().get_first_node_in_group("arctic_plumes")
	if plumes == null or not plumes.has_method("apply_beam_settings"):
		return
	var colors: Array = []
	for i in 6:
		colors.append(_values["beam_color_%d" % i])
	plumes.call("apply_beam_settings", _values["beam_strength"], colors,
		_values["beam_density"], _values["beam_speed"], _values["beam_duration"])

## Scoped save — re-reads whatever's CURRENTLY on disk and overwrites ONLY this panel's own keys.
func _on_save() -> void:
	var fresh := ArcticTerrainSettings.load_settings()
	for key: String in _sliders.keys():
		fresh[key] = _values[key]
	for key: String in _color_btns.keys():
		fresh[key] = _values[key]
	ArcticTerrainSettings.save_settings(fresh)
	if _status != null:
		_status.text = "Saved."

func _on_reset() -> void:
	_values["beam_speed"] = ArcticTerrainSettings.DEFAULT_BEAM_SPEED
	_values["beam_duration"] = ArcticTerrainSettings.DEFAULT_BEAM_DURATION
	_values["beam_density"] = ArcticTerrainSettings.DEFAULT_BEAM_DENSITY
	_values["beam_strength"] = ArcticTerrainSettings.DEFAULT_BEAM_STRENGTH
	_values["beam_color_0"] = ArcticTerrainSettings.DEFAULT_BEAM_COLOR_0
	_values["beam_color_1"] = ArcticTerrainSettings.DEFAULT_BEAM_COLOR_1
	_values["beam_color_2"] = ArcticTerrainSettings.DEFAULT_BEAM_COLOR_2
	_values["beam_color_3"] = ArcticTerrainSettings.DEFAULT_BEAM_COLOR_3
	_values["beam_color_4"] = ArcticTerrainSettings.DEFAULT_BEAM_COLOR_4
	_values["beam_color_5"] = ArcticTerrainSettings.DEFAULT_BEAM_COLOR_5
	_sync_ui_from_values()
	_apply_live_beam()
	if _status != null:
		_status.text = "Reset to defaults (not saved yet)."

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
