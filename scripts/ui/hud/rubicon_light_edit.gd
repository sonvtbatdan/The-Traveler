extends CanvasLayer
class_name RubiconLightEdit
## Dev-mode-only Rubicon canopy LIGHTING tuning — group "rubicon_light_edit", toggled from
## arena_hud_buttons.gd's LIGHT EDIT button (Rubicon map only, sits directly above TERRAIN EDIT).
##
## Split out of RubiconTerrainEdit's own panel into its own small floating panel (same title-bar-drag pattern)
## so the canopy normal-map lighting knobs (tools/generate_canopy_normal.py's real per-pixel N.L + specular —
## see rubicon_ground.gdshader) have a focused home instead of living buried in the middle of the big terrain
## panel's slider list.
##
## Applies LIVE to the running RubiconGround instance (group "rubicon_ground"). SAVE persists to
## res://rubicon_terrain.cfg via RubiconTerrainSettings — loads/saves the FULL settings dict (not just these 4
## keys) so it never clobbers Terrain Edit's own settings living in the same file.

const RubiconTerrainSettings := preload("res://scripts/gameplay/rubicon/rubicon_terrain_settings.gd")

const PANEL_W := 300.0

var _is_open: bool = false
var _panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}
var _sliders: Dictionary = {}      # key -> HSlider
var _value_lbls: Dictionary = {}   # key -> Label
var _color_btns: Dictionary = {}   # key -> ColorPickerButton
var _status: Label = null

func _ready() -> void:
	layer = 61   # same tier as rubicon_terrain_edit.gd / creep_info_panel.gd
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("rubicon_light_edit")

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's LIGHT EDIT button.
func toggle() -> void:
	_is_open = not _is_open
	if _panel != null:
		_panel.visible = _is_open
	if not _is_open:
		return
	if _panel == null:
		_values = RubiconTerrainSettings.load_settings()
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
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.55, 0.20)   # warm border — visually distinct from Terrain Edit's blue
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "☀ LIGHT EDIT"
	_font(title, 15, Color(1.0, 0.92, 0.75))
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

	_add_slider(col, "canopy_light_angle_deg", "Light Angle", 0.0, 360.0, 5.0)
	_add_slider(col, "canopy_light_height", "Light Height (grazing ↔ overhead)", 0.0, 1.0, 0.02)
	_add_slider(col, "canopy_ambient", "Ambient (shadow-side floor)", 0.0, 1.0, 0.02)
	_add_slider(col, "canopy_contrast", "Contrast (highlight ↔ shadow)", 0.0, 3.0, 0.05)
	_add_slider(col, "canopy_specular", "Specular (glossy highlight)", 0.0, 1.0, 0.02)
	_add_color_row(col, "canopy_light_color", "Light Color (sun)")
	col.add_child(HSeparator.new())
	_add_slider(col, "spark_amount", "Spark Amount", 0.0, 150.0, 5.0)
	_add_slider(col, "spark_speed", "Spark Speed (px/s)", 0.0, 100.0, 1.0)
	_add_slider(col, "spark_size", "Spark Size (px)", 0.0, 100.0, 1.0)
	_add_slider(col, "spark_direction_deg", "Spark Direction", 0.0, 360.0, 5.0)
	_add_slider(col, "spark_brightness", "Spark Brightness", 0.0, 3.0, 0.05)
	_add_slider(col, "spark_opacity", "Spark Opacity", 0.0, 1.0, 0.02)
	_add_color_row(col, "spark_color", "Spark Color")

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
	_font(lbl, 13, Color(0.8, 0.85, 0.95))
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
	val_lbl.custom_minimum_size = Vector2(44.0, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_font(val_lbl, 13, Color(1.0, 0.86, 0.3))
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
	_font(lbl, 13, Color(0.8, 0.85, 0.95))
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
		_value_lbls[key].text = "%.2f" % v
	for key: String in _color_btns.keys():
		var picker: ColorPickerButton = _color_btns[key]
		picker.color = _values[key]
	if _status != null:
		_status.text = ""

func _on_value_changed(key: String, v: float) -> void:
	_values[key] = v
	_value_lbls[key].text = "%.2f" % v
	_apply_live()
	if _status != null:
		_status.text = ""

func _on_color_changed(key: String, c: Color) -> void:
	_values[key] = c
	_apply_live()
	if _status != null:
		_status.text = ""

func _apply_live() -> void:
	var ground := get_tree().get_first_node_in_group("rubicon_ground")
	if ground != null and ground.has_method("apply_canopy_lighting"):
		ground.call("apply_canopy_lighting", _values["canopy_light_angle_deg"], _values["canopy_light_height"], _values["canopy_ambient"], _values["canopy_specular"], _values["canopy_light_color"], _values["canopy_contrast"])
	var sparks := get_tree().get_first_node_in_group("rubicon_sparks")
	if sparks != null and sparks.has_method("apply_spark_settings"):
		sparks.call("apply_spark_settings", _values["spark_amount"], _values["spark_color"], _values["spark_speed"], _values["spark_size"], _values["spark_direction_deg"], _values["spark_brightness"], _values["spark_opacity"])

## Scoped save — re-reads whatever's CURRENTLY on disk and overwrites ONLY this panel's own keys, instead of
## blanket-writing this panel's own possibly-stale `_values` snapshot (taken once, back when the panel was
## opened). 2026-08-08 bug fix (found via the Atlantic port — the very "Electric map" recurrence the user
## flagged): with the old blanket save, opening this panel and clicking SAVE at any later point silently
## reverted every OTHER panel's changes since (e.g. rubicon_terrain_edit.gd's) back to whatever they were when
## THIS panel was first opened.
func _on_save() -> void:
	var fresh := RubiconTerrainSettings.load_settings()
	for key: String in _sliders.keys():
		fresh[key] = _values[key]
	for key: String in _color_btns.keys():
		fresh[key] = _values[key]
	RubiconTerrainSettings.save_settings(fresh)
	if _status != null:
		_status.text = "Saved."

func _on_reset() -> void:
	_values["canopy_light_angle_deg"] = RubiconTerrainSettings.DEFAULT_CANOPY_LIGHT_ANGLE_DEG
	_values["canopy_light_height"] = RubiconTerrainSettings.DEFAULT_CANOPY_LIGHT_HEIGHT
	_values["canopy_ambient"] = RubiconTerrainSettings.DEFAULT_CANOPY_AMBIENT
	_values["canopy_contrast"] = RubiconTerrainSettings.DEFAULT_CANOPY_CONTRAST
	_values["canopy_specular"] = RubiconTerrainSettings.DEFAULT_CANOPY_SPECULAR
	_values["canopy_light_color"] = RubiconTerrainSettings.DEFAULT_CANOPY_LIGHT_COLOR
	_values["spark_amount"] = RubiconTerrainSettings.DEFAULT_SPARK_AMOUNT
	_values["spark_color"] = RubiconTerrainSettings.DEFAULT_SPARK_COLOR
	_values["spark_speed"] = RubiconTerrainSettings.DEFAULT_SPARK_SPEED
	_values["spark_size"] = RubiconTerrainSettings.DEFAULT_SPARK_SIZE
	_values["spark_direction_deg"] = RubiconTerrainSettings.DEFAULT_SPARK_DIRECTION_DEG
	_values["spark_brightness"] = RubiconTerrainSettings.DEFAULT_SPARK_BRIGHTNESS
	_values["spark_opacity"] = RubiconTerrainSettings.DEFAULT_SPARK_OPACITY
	_sync_ui_from_values()
	_apply_live()
	if _status != null:
		_status.text = "Reset to defaults (not saved yet)."

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
