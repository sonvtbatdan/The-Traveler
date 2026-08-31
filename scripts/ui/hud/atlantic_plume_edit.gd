extends CanvasLayer
class_name AtlanticPlumeEdit
## Dev-mode-only Atlantic bubble/whirlpool-plume tuning — group "atlantic_plume_edit", toggled from
## arena_hud_buttons.gd's PLUME EDIT button (Atlantic map only). Port of scripts/ui/hud/volcanic_plume_edit.gd
## (same two-tab layout, "SMOKE"/"FLAME" -> "BUBBLE"/"WHIRLPOOL" — see that file's header for the full
## rationale on why both kinds are built once and just shown/hidden on tab switch). "Wind" is relabeled
## "Current" throughout (shared direction/strength affecting both kinds together, per
## atlantic_clouds.gd's header) — REROLL WIND -> REROLL CURRENT.

const AtlanticTerrainSettings := preload("res://scripts/gameplay/atlantic/atlantic_terrain_settings.gd")

const PANEL_W := 320.0
const KINDS := ["bubble", "whirlpool"]
const SPEED_LABEL := {"bubble": "Rise Speed (px/s)", "whirlpool": "Spin Speed (px/s)"}
const HEIGHT_LABEL := {"bubble": "Lifetime (seconds aloft)", "whirlpool": "Lifetime (seconds per cycle)"}

var _is_open: bool = false
var _panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}
var _sliders: Dictionary = {}      # key -> HSlider (keys already distinct per kind, e.g. "bubble_speed")
var _value_lbls: Dictionary = {}
var _color_btns: Dictionary = {}
var _status: Label = null

var _kind: String = "bubble"
var _tab_btns: Dictionary = {}     # kind -> Button
var _kind_sections: Dictionary = {}   # kind -> VBoxContainer

func _ready() -> void:
	layer = 61   # same tier as the other Atlantic dev panels
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("atlantic_plume_edit")

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
	_panel.size = Vector2(PANEL_W, minf(660.0, vp_h - _panel.position.y - 20.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.SURFACE
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.2, 0.55, 0.65)
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "🫧 PLUME EDIT"
	_font(title, 15, Color(0.8, 0.92, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Drag to move"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input)
	outer.add_child(title)

	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 6)
	outer.add_child(tab_row)
	for kind: String in KINDS:
		var btn := Button.new()
		btn.text = kind.to_upper()
		btn.toggle_mode = true
		_font_btn(btn, 13)
		btn.custom_minimum_size = Vector2(100, 28)
		btn.pressed.connect(_select_kind.bind(kind))
		tab_row.add_child(btn)
		_tab_btns[kind] = btn
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	for kind: String in KINDS:
		_kind_sections[kind] = _build_kind_section(col, kind)

	col.add_child(HSeparator.new())
	_add_slider(col, "wind_strength_max", "Current Strength (ceiling, shared)", 0.0, 80.0, 1.0)
	var wind_hint := Label.new()
	wind_hint.text = "Direction + actual strength are ROLLED RANDOMLY — affects bubbles AND whirlpools together"
	_font(wind_hint, 10, Color(0.55, 0.68, 0.7))
	wind_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(wind_hint)
	var reroll_btn := Button.new()
	reroll_btn.text = "REROLL CURRENT"
	_font_btn(reroll_btn, 13)
	reroll_btn.pressed.connect(_on_reroll_wind)
	col.add_child(reroll_btn)

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

	_select_kind(_kind)

## Builds one kind's full slider/palette section (own VBoxContainer, added to `parent`) — key names already
## carry the kind prefix (e.g. "bubble_speed"/"whirlpool_speed"), so _apply_live()/_on_reset() can tell which
## kind a changed key belongs to just from its prefix, no separate per-kind widget bookkeeping needed.
func _build_kind_section(parent: VBoxContainer, kind: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var label_kind := kind.capitalize()
	_add_slider(section, "%s_speed" % kind, SPEED_LABEL.get(kind, "%s Speed" % label_kind), 0.0, 100.0, 1.0)
	_add_slider(section, "%s_height" % kind, HEIGHT_LABEL.get(kind, "%s Height" % label_kind), 0.2, 8.0, 0.1)
	if kind == "bubble":
		# 2026-08-09 unification (on request): ONE master rate for EVERY bubble on screen — 100 = 10/sec — whether
		# it spawns at a pure-random point or at one of the Crater Mark panel's placed positions (each rate-tick
		# picks a mark 50% of the time, if any exist). 0 now means EXACTLY zero bubbles, marks included — there's
		# no separate "Marked Vent Reveal %" for bubble anymore (Landmark/temple bubbles are still a separate,
		# always-on source — see atlantic_clouds.gd's header). See atlantic_clouds.gd's BUBBLE_RATE_DIVISOR.
		_add_slider(section, "bubble_density", "Bubble Rate — ambient + marked (100 = 10/sec)", 0.0, 100.0, 1.0)
	else:
		# This only gates AMBIENT whirlpools — Marked/Landmark ones are separate (see "Marked Vent Reveal %" below).
		_add_slider(section, "%s_density" % kind, "%s Density — AMBIENT only" % label_kind, 0.0, 1.0, 0.05)
	_add_slider(section, "%s_opacity" % kind, "%s Opacity" % label_kind, 0.0, 2.5, 0.05)
	_add_slider(section, "%s_brightness" % kind, "%s Brightness" % label_kind, 0.1, 2.5, 0.05)
	if kind == "whirlpool":
		# Bubble has no equivalent slider anymore — see the Bubble Rate comment above (2026-08-09 unification).
		_add_slider(section, "%s_mark_reveal_percent" % kind, "Marked Vent Reveal % (0 = hide all Crater Marks)", 0.0, 100.0, 1.0)
		# 2026-08-08, on request: each whirlpool independently rolls a random size MULTIPLIER between these two
		# (1.0 = the base Mouth/Throat/Height dimensions below, as-is) — see atlantic_clouds.gd's
		# apply_whirlpool_size().
		_add_slider(section, "whirlpool_size_min", "Size Min (multiplier)", 0.3, 3.0, 0.05)
		_add_slider(section, "whirlpool_size_max", "Size Max (multiplier)", 0.3, 3.0, 0.05)
		# 2026-08-09, on request: direct control of the funnel's own base shape — see atlantic_clouds.gd's
		# apply_whirlpool_dimensions().
		_add_slider(section, "whirlpool_mouth_radius", "Mouth Radius (px)", 10.0, 300.0, 5.0)
		_add_slider(section, "whirlpool_throat_radius", "Throat Radius (px)", 2.0, 150.0, 2.0)
		_add_slider(section, "whirlpool_height_px", "Funnel Height (px)", 10.0, 400.0, 5.0)
		# 2026-08-09: <1 stays flared near the mouth, pinching sharply only near the throat (a real whirlpool's
		# shape); 1.0 = a straight-walled cone; >1 narrows fast then trails a long thin neck.
		_add_slider(section, "whirlpool_profile_exp", "Funnel Curve (<1 flared, 1 cone, >1 neck)", 0.2, 2.0, 0.05)
		# 2026-08-08, on request: ONE shared orientation for every whirlpool funnel — see
		# atlantic_clouds.gd's apply_whirlpool_tilt().
		_add_slider(section, "whirlpool_rot_x_deg", "Tilt X", -180.0, 180.0, 1.0)
		_add_slider(section, "whirlpool_rot_y_deg", "Tilt Y (spin phase)", -180.0, 180.0, 1.0)
		_add_slider(section, "whirlpool_rot_z_deg", "Tilt Z", -180.0, 180.0, 1.0)
	section.add_child(HSeparator.new())
	var palette_lbl := Label.new()
	palette_lbl.text = "%s Colors (random pick per plume)" % label_kind
	_font(palette_lbl, 13, Color(0.8, 0.92, 0.95))
	section.add_child(palette_lbl)
	for i in 6:
		_add_color_row(section, "%s_color_%d" % [kind, i], "Color %d" % (i + 1))
	return section

func _select_kind(kind: String) -> void:
	_kind = kind
	for k: String in KINDS:
		(_tab_btns[k] as Button).set_pressed_no_signal(k == kind)
		(_kind_sections[k] as VBoxContainer).visible = (k == kind)

func _add_slider(parent: VBoxContainer, key: String, label_text: String, min_v: float, max_v: float, step_v: float) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	_font(lbl, 13, Color(0.8, 0.92, 0.95))
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
	_font(val_lbl, 13, Color(0.65, 0.85, 0.9))
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
	_font(lbl, 13, Color(0.8, 0.92, 0.95))
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

## Returns "bubble" or "whirlpool" if `key` belongs to one of those kinds' prefixed settings, else "" (e.g.
## the shared "wind_strength_max").
func _kind_of_key(key: String) -> String:
	for kind: String in KINDS:
		if key.begins_with(kind + "_"):
			return kind
	return ""

func _on_value_changed(key: String, v: float) -> void:
	_values[key] = v
	_value_lbls[key].text = "%.2f" % v
	_apply_live_for_key(key)
	if _status != null:
		_status.text = ""

func _on_color_changed(key: String, c: Color) -> void:
	_values[key] = c
	_apply_live_for_key(key)
	if _status != null:
		_status.text = ""

func _apply_live_for_key(key: String) -> void:
	if key == "whirlpool_size_min" or key == "whirlpool_size_max":
		_apply_live_whirlpool_size()
		return
	if key == "whirlpool_rot_x_deg" or key == "whirlpool_rot_y_deg" or key == "whirlpool_rot_z_deg":
		_apply_live_whirlpool_tilt()
		return
	if key == "whirlpool_mouth_radius" or key == "whirlpool_throat_radius" or key == "whirlpool_height_px" or key == "whirlpool_profile_exp":
		_apply_live_whirlpool_dimensions()
		return
	var kind := _kind_of_key(key)
	if kind != "":
		_apply_live_kind(kind)
	else:
		_apply_live_wind()

func _apply_live_whirlpool_size() -> void:
	var clouds := get_tree().get_first_node_in_group("atlantic_clouds")
	if clouds != null and clouds.has_method("apply_whirlpool_size"):
		clouds.call("apply_whirlpool_size", _values["whirlpool_size_min"], _values["whirlpool_size_max"])

func _apply_live_whirlpool_tilt() -> void:
	var clouds := get_tree().get_first_node_in_group("atlantic_clouds")
	if clouds != null and clouds.has_method("apply_whirlpool_tilt"):
		clouds.call("apply_whirlpool_tilt", _values["whirlpool_rot_x_deg"], _values["whirlpool_rot_y_deg"], _values["whirlpool_rot_z_deg"])

func _apply_live_whirlpool_dimensions() -> void:
	var clouds := get_tree().get_first_node_in_group("atlantic_clouds")
	if clouds != null and clouds.has_method("apply_whirlpool_dimensions"):
		clouds.call("apply_whirlpool_dimensions", _values["whirlpool_mouth_radius"], _values["whirlpool_throat_radius"], _values["whirlpool_height_px"], _values["whirlpool_profile_exp"])

func _apply_live_kind(kind: String) -> void:
	var clouds := get_tree().get_first_node_in_group("atlantic_clouds")
	if clouds == null or not clouds.has_method("apply_kind_settings"):
		return
	var colors: Array = []
	for i in 6:
		colors.append(_values["%s_color_%d" % [kind, i]])
	clouds.call("apply_kind_settings", kind,
		_values["%s_opacity" % kind], _values["%s_brightness" % kind], colors,
		_values["%s_density" % kind], _values["%s_speed" % kind], _values["%s_height" % kind],
		_values["%s_mark_reveal_percent" % kind])

func _apply_live_wind() -> void:
	var clouds := get_tree().get_first_node_in_group("atlantic_clouds")
	if clouds != null and clouds.has_method("apply_wind_strength_max"):
		clouds.call("apply_wind_strength_max", _values["wind_strength_max"])

func _on_reroll_wind() -> void:
	var clouds := get_tree().get_first_node_in_group("atlantic_clouds")
	if clouds != null and clouds.has_method("reroll_current"):
		clouds.call("reroll_current")

## Scoped save — re-reads whatever's CURRENTLY on disk and overwrites ONLY this panel's own keys (its
## registered slider/color-picker keys), instead of blanket-writing this panel's own possibly-stale `_values`
## snapshot (taken once, back when the panel was opened). 2026-08-08 bug fix: with the old blanket save, opening
## this panel and clicking SAVE at any later point silently reverted every OTHER panel's changes since — e.g.
## Crater Mark's vent marks — back to whatever they were when THIS panel was first opened (recurrence of a bug
## already hit once on the Electric/Electric map's own Terrain/Light Edit pair). Mirrors atlantic_crater_mark.gd's
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
	_values["wind_strength_max"] = AtlanticTerrainSettings.DEFAULT_WIND_STRENGTH_MAX
	_values["bubble_speed"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_SPEED
	_values["bubble_height"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_HEIGHT
	_values["bubble_density"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_DENSITY
	_values["bubble_opacity"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_OPACITY
	_values["bubble_brightness"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_BRIGHTNESS
	_values["bubble_mark_reveal_percent"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_MARK_REVEAL_PERCENT
	_values["bubble_color_0"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_COLOR_0
	_values["bubble_color_1"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_COLOR_1
	_values["bubble_color_2"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_COLOR_2
	_values["bubble_color_3"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_COLOR_3
	_values["bubble_color_4"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_COLOR_4
	_values["bubble_color_5"] = AtlanticTerrainSettings.DEFAULT_BUBBLE_COLOR_5
	_values["whirlpool_speed"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_SPEED
	_values["whirlpool_height"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_HEIGHT
	_values["whirlpool_density"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_DENSITY
	_values["whirlpool_opacity"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_OPACITY
	_values["whirlpool_brightness"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_BRIGHTNESS
	_values["whirlpool_mark_reveal_percent"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_MARK_REVEAL_PERCENT
	_values["whirlpool_color_0"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_COLOR_0
	_values["whirlpool_color_1"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_COLOR_1
	_values["whirlpool_color_2"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_COLOR_2
	_values["whirlpool_color_3"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_COLOR_3
	_values["whirlpool_color_4"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_COLOR_4
	_values["whirlpool_color_5"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_COLOR_5
	_values["whirlpool_size_min"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_SIZE_MIN
	_values["whirlpool_size_max"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_SIZE_MAX
	_values["whirlpool_rot_x_deg"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_ROT_X_DEG
	_values["whirlpool_rot_y_deg"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_ROT_Y_DEG
	_values["whirlpool_rot_z_deg"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_ROT_Z_DEG
	_values["whirlpool_mouth_radius"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_MOUTH_RADIUS
	_values["whirlpool_throat_radius"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_THROAT_RADIUS
	_values["whirlpool_height_px"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_HEIGHT_PX
	_values["whirlpool_profile_exp"] = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_PROFILE_EXP
	_sync_ui_from_values()
	_apply_live_kind("bubble")
	_apply_live_kind("whirlpool")
	_apply_live_whirlpool_size()
	_apply_live_whirlpool_tilt()
	_apply_live_whirlpool_dimensions()
	_apply_live_wind()
	if _status != null:
		_status.text = "Reset to defaults (not saved yet)."

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
