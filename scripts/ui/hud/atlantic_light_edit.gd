extends CanvasLayer
class_name AtlanticLightEdit
## Dev-mode-only Atlantic ground LIGHTING tuning — group "atlantic_light_edit", toggled from
## arena_hud_buttons.gd's LIGHT EDIT button (Atlantic map only). Verbatim port of
## scripts/ui/hud/volcanic_light_edit.gd (same focused small panel split out from Terrain Edit — see that
## file's header for the full rationale). Deltas: reads/writes AtlanticTerrainSettings/atlantic_terrain.cfg,
## applies to groups "atlantic_ground"/"atlantic_sparks", "Ember"->"Spark" (bioluminescent motes) relabeling.

const AtlanticTerrainSettings := preload("res://scripts/gameplay/atlantic/atlantic_terrain_settings.gd")

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
	layer = 61   # same tier as atlantic_terrain_edit.gd / volcanic_light_edit.gd
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("atlantic_light_edit")

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
		_values = AtlanticTerrainSettings.load_settings()
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
	sb.bg_color = Color(0.03, 0.06, 0.08, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.25, 0.75, 0.85)   # bright cyan-teal border — visually distinct from Terrain Edit's
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "☀ LIGHT EDIT"
	_font(title, 15, Color(0.75, 0.95, 1.0))
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

	_add_slider(col, "ground_light_angle_deg", "Light Angle", 0.0, 360.0, 5.0)
	_add_slider(col, "ground_light_height", "Light Height (grazing ↔ overhead)", 0.0, 1.0, 0.02)
	_add_slider(col, "ground_ambient", "Ambient (shadow-side floor)", 0.0, 1.0, 0.02)
	_add_slider(col, "ground_contrast", "Contrast (highlight ↔ shadow)", 0.0, 3.0, 0.05)
	_add_slider(col, "ground_specular", "Specular (glossy highlight)", 0.0, 1.0, 0.02)
	_add_color_row(col, "ground_light_color", "Light Color (caustic sun)")
	col.add_child(HSeparator.new())
	_add_slider(col, "spark_amount", "Mote Amount", 0.0, 150.0, 5.0)
	_add_slider(col, "spark_speed", "Mote Speed (px/s)", 0.0, 100.0, 1.0)
	_add_slider(col, "spark_size", "Mote Size (px)", 0.0, 100.0, 1.0)
	_add_slider(col, "spark_direction_deg", "Mote Direction", 0.0, 360.0, 5.0)
	_add_slider(col, "spark_brightness", "Mote Brightness", 0.0, 3.0, 0.05)
	_add_slider(col, "spark_opacity", "Mote Opacity", 0.0, 1.0, 0.02)
	_add_color_row(col, "spark_color", "Mote Color (bioluminescence)")

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
	_font(lbl, 13, Color(0.8, 0.9, 0.92))
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
	_font(val_lbl, 13, Color(0.4, 0.9, 1.0))
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
	_font(lbl, 13, Color(0.8, 0.9, 0.92))
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
	var ground := get_tree().get_first_node_in_group("atlantic_ground")
	if ground != null and ground.has_method("apply_ground_lighting"):
		ground.call("apply_ground_lighting", _values["ground_light_angle_deg"], _values["ground_light_height"], _values["ground_ambient"], _values["ground_specular"], _values["ground_light_color"], _values["ground_contrast"])
	var sparks := get_tree().get_first_node_in_group("atlantic_sparks")
	if sparks != null and sparks.has_method("apply_spark_settings"):
		sparks.call("apply_spark_settings", _values["spark_amount"], _values["spark_color"], _values["spark_speed"], _values["spark_size"], _values["spark_direction_deg"], _values["spark_brightness"], _values["spark_opacity"])

## Scoped save — re-reads whatever's CURRENTLY on disk and overwrites ONLY this panel's own keys (its
## registered slider/color-picker keys), instead of blanket-writing this panel's own possibly-stale `_values`
## snapshot (taken once, back when the panel was opened). 2026-08-08 bug fix: with the old blanket save, opening
## this panel and clicking SAVE at any later point silently reverted every OTHER panel's changes since — e.g.
## Crater Mark's vent marks — back to whatever they were when THIS panel was first opened (recurrence of a bug
## already hit once on the Electric/Rubicon map's own Terrain/Light Edit pair). Mirrors atlantic_crater_mark.gd's
## _save_marks_only()/atlantic_landmark_mark.gd's own scoped save.
func _on_save() -> void:
	var fresh := AtlanticTerrainSettings.load_settings()
	for key: String in _sliders.keys():
		fresh[key] = _values[key]
	for key: String in _color_btns.keys():
		fresh[key] = _values[key]
	AtlanticTerrainSettings.save_settings(fresh)
	if _status != null:
		_status.text = "Saved."

func _on_reset() -> void:
	_values["ground_light_angle_deg"] = AtlanticTerrainSettings.DEFAULT_GROUND_LIGHT_ANGLE_DEG
	_values["ground_light_height"] = AtlanticTerrainSettings.DEFAULT_GROUND_LIGHT_HEIGHT
	_values["ground_ambient"] = AtlanticTerrainSettings.DEFAULT_GROUND_AMBIENT
	_values["ground_contrast"] = AtlanticTerrainSettings.DEFAULT_GROUND_CONTRAST
	_values["ground_specular"] = AtlanticTerrainSettings.DEFAULT_GROUND_SPECULAR
	_values["ground_light_color"] = AtlanticTerrainSettings.DEFAULT_GROUND_LIGHT_COLOR
	_values["spark_amount"] = AtlanticTerrainSettings.DEFAULT_SPARK_AMOUNT
	_values["spark_color"] = AtlanticTerrainSettings.DEFAULT_SPARK_COLOR
	_values["spark_speed"] = AtlanticTerrainSettings.DEFAULT_SPARK_SPEED
	_values["spark_size"] = AtlanticTerrainSettings.DEFAULT_SPARK_SIZE
	_values["spark_direction_deg"] = AtlanticTerrainSettings.DEFAULT_SPARK_DIRECTION_DEG
	_values["spark_brightness"] = AtlanticTerrainSettings.DEFAULT_SPARK_BRIGHTNESS
	_values["spark_opacity"] = AtlanticTerrainSettings.DEFAULT_SPARK_OPACITY
	_sync_ui_from_values()
	_apply_live()
	if _status != null:
		_status.text = "Reset to defaults (not saved yet)."

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
