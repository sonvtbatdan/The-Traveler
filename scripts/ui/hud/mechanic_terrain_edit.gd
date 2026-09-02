extends CanvasLayer
class_name MechanicTerrainEdit
## Dev-mode-only Mechanic terrain tuning — group "mechanic_terrain_edit", toggled from
## arena_hud_buttons.gd's TERRAIN EDIT button (Mechanic map only).
##
## ONE tabbed panel (2026-08-19, on request — was previously two side-by-side panels, "Terrain" [a long
## scrolling slider list] + a separate floating "Assets" icon grid, itself a verbatim port of
## electric_terrain_edit.gd's own two-panel layout): CLOUD / RIVER / CANOPY / ASSET tabs, each its own
## VBoxContainer section built once and shown/hidden on tab switch (mirrors volcanic_plume_edit.gd's own
## smoke/flame tab pattern) inside ONE shared ScrollContainer. The former separate Assets panel's icon grid +
## per-type density/scale/bias/blur detail sliders now both live inside the ASSET tab together.
##  • CLOUD: opacity/brightness/color/clumpiness + Wind Strength/Angle (NEW — see mechanic_clouds.gd's header;
##    the parallax offset alone never drifts the clouds when the ship holds still, only wind does that).
##  • RIVER: width/bank color/water color/pattern/wave size — mechanic_ground.gdshader's river was reverted
##    to a verbatim copy of ElectricGround's own technique this same request, so the old branch/corridor/crack/
##    glow-sweep sliders that lived here are GONE, not just relabeled (see mechanic_ground.gdshader's header).
##  • CANOPY: tile set/size/blend sparseness/blend width + terrain tint colors A/B.
##  • ASSET: Jitter (global scatter placement variance — belongs here, not Canopy, since it's about scatter
##    behavior not ground texture) + the per-.glb-type icon grid/density/scale/bias/blur detail sliders. Empty
##    today (no .glb dropped into assets/map/mechanic/ yet) — shows a placeholder instead of a bare gap.
##
## Applies LIVE to the running MechanicGround / MechanicClouds / MechanicTrees instances (found via their own
## groups). SAVE persists to res://mechanic_terrain.cfg via MechanicTerrainSettings.

const MechanicTerrainSettings := preload("res://scripts/gameplay/mechanic/mechanic_terrain_settings.gd")
const MechanicAssetScan := preload("res://scripts/gameplay/mechanic/mechanic_asset_scan.gd")
const MechanicTreesScript := preload("res://scripts/gameplay/mechanic/mechanic_trees.gd")

const PANEL_W := 380.0
const ICON_SLOT_SIZE := 64.0
const ENABLE_BTN_SIZE := 18.0
const TABS := ["cloud", "river", "canopy", "asset"]
const TAB_LABELS := {"cloud": "CLOUD", "river": "RIVER", "canopy": "CANOPY", "asset": "ASSET"}

var _is_open: bool = false
var _panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}
var _sliders: Dictionary = {}
var _value_lbls: Dictionary = {}
var _color_btns: Dictionary = {}
var _dropdowns: Dictionary = {}

var _tab: String = "cloud"
var _tab_btns: Dictionary = {}      # tab name -> Button
var _tab_sections: Dictionary = {}  # tab name -> VBoxContainer

var _asset_list_btns: Dictionary = {}
var _asset_enable_btns: Dictionary = {}
var _selected_assets: Dictionary = {}
var _last_selected_asset: String = ""

var _selection_lbl: Label = null
var _density_slider: HSlider = null
var _density_val_lbl: Label = null
var _scale_min_slider: HSlider = null
var _scale_min_val_lbl: Label = null
var _scale_max_slider: HSlider = null
var _scale_max_val_lbl: Label = null
var _scale_bias_slider: HSlider = null
var _scale_bias_val_lbl: Label = null
var _blur_slider: HSlider = null
var _blur_val_lbl: Label = null
var _height_lbl: Label = null

var _status: Label = null

func _ready() -> void:
	layer = 61
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mechanic_terrain_edit")

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's TERRAIN EDIT button.
func toggle() -> void:
	_is_open = not _is_open
	if _panel != null:
		_panel.visible = _is_open
	if not _is_open:
		return
	if _panel == null:
		_values = MechanicTerrainSettings.load_settings()
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

# ── UI construction ─────────────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_panel = Panel.new()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_panel.position = Vector2(20.0, 44.0)
	_panel.size = Vector2(PANEL_W, minf(660.0, vp_h - _panel.position.y - 20.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = UiPalette.ACCENT_DIM
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	UiPalette.scanlines(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "≡ TERRAIN EDIT"
	_font(title, 15, UiPalette.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Drag to move"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input)
	outer.add_child(title)

	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 4)
	outer.add_child(tab_row)
	for t: String in TABS:
		var btn := Button.new()
		btn.text = String(TAB_LABELS[t])
		btn.toggle_mode = true
		_font_btn(btn, 12)
		btn.custom_minimum_size = Vector2(78, 26)
		btn.pressed.connect(_select_tab.bind(t))
		tab_row.add_child(btn)
		_tab_btns[t] = btn
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	for t: String in TABS:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 6)
		col.add_child(section)
		_tab_sections[t] = section
		match t:
			"cloud": _build_cloud_section(section)
			"river": _build_river_section(section)
			"canopy": _build_canopy_section(section)
			"asset": _build_asset_section(section)

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
	_font(_status, 12, UiPalette.GOOD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status)

	_select_tab(_tab)
	if not _asset_list_btns.is_empty():
		_select_asset(_asset_list_btns.keys()[0])

func _select_tab(t: String) -> void:
	_tab = t
	for k: String in TABS:
		(_tab_btns[k] as Button).set_pressed_no_signal(k == t)
		(_tab_sections[k] as VBoxContainer).visible = (k == t)

func _build_cloud_section(section: VBoxContainer) -> void:
	_add_slider(section, "cloud_opacity", "Cloud Opacity", 0.0, 2.5, 0.05)
	_add_slider(section, "cloud_brightness", "Cloud Brightness", 0.1, 2.5, 0.05)
	_add_color_row(section, "cloud_color", "Cloud Color")
	_add_slider(section, "cloud_clumpiness", "Cloud Clumpiness", 0.0, 1.0, 0.05)
	section.add_child(HSeparator.new())
	_add_slider(section, "cloud_wind_strength", "Wind Strength (px/s, blows clouds)", 0.0, 200.0, 5.0)
	_add_slider(section, "cloud_wind_angle_deg", "Wind Angle (°)", 0.0, 360.0, 5.0)

func _build_river_section(section: VBoxContainer) -> void:
	# River Width now lives in MOTTLE-value space (the river runs along the canopy blend's own seam lines,
	# 1/7≈0.143 apart — see mechanic_ground.gdshader's header), so its range is much narrower than the old
	# independent-field version's 0..0.15.
	_add_slider(section, "river_width", "River Width", 0.0, 0.07, 0.002)
	_add_slider(section, "river_count", "River Count (of 7 canopy seams)", 0.0, 6.0, 1.0)
	_add_color_row(section, "river_bank_color", "River Bank Color (sand)")
	_add_slider(section, "river_bank_width", "River Bank Width", 0.0, 0.08, 0.002)
	_add_color_row(section, "water_color", "Water Color")
	_add_dropdown(section, "water_tile_set", "Water Pattern", MechanicAssetScan.watertile_set_names())
	_add_slider(section, "water_wave_size", "Wave Size", 60.0, 800.0, 10.0)

func _build_canopy_section(section: VBoxContainer) -> void:
	_add_dropdown(section, "maptile_set", "Tile Set", MechanicAssetScan.maptile_set_names())
	_add_slider(section, "canopy_size", "Canopy Size (photo's own tiling)", 400.0, 4000.0, 25.0)
	_add_slider(section, "canopy_mottle_scale", "Canopy Blend Sparseness", 800.0, 8000.0, 100.0)
	_add_slider(section, "canopy_blend_width", "Canopy Blend Width", 0.0, 0.15, 0.005)
	section.add_child(HSeparator.new())
	_add_color_row(section, "color_a", "Terrain Color A (grass)")
	_add_color_row(section, "color_b", "Terrain Color B (sand)")

func _build_asset_section(section: VBoxContainer) -> void:
	_add_slider(section, "jitter", "Scatter Jitter", 0.0, 1.0, 0.02)
	section.add_child(HSeparator.new())

	# Icon grid — conditional on at least one .glb existing (nothing to list otherwise). The density/scale/
	# bias/blur detail sliders below, however, are built UNCONDITIONALLY regardless of glb_paths — mirrors the
	# pre-tab layout, where they lived in the always-built Terrain panel (only the icon grid was a separate,
	# conditionally-absent panel). An early `return` here before 2026-08-19's fix silently dropped those 5
	# sliders + the height label whenever Mechanic had zero scatter assets (i.e. right now) — a real regression,
	# not a deliberate removal; don't reintroduce it.
	var glb_paths: Array = MechanicAssetScan.glb_paths()
	if glb_paths.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No scatter assets found in assets/map/mechanic/ yet — drop a .glb in and reopen this panel."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_font(empty_lbl, 11, UiPalette.MUTED)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		section.add_child(empty_lbl)
	else:
		var hint := Label.new()
		hint.text = "Click = select · Shift+click = multi-select"
		_font(hint, 10, UiPalette.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		section.add_child(hint)

		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		section.add_child(flow)

		var asset_settings: Dictionary = _values["asset_settings"]
		for glb_path: String in glb_paths:
			var type_name := MechanicAssetScan.type_name(glb_path)
			if not asset_settings.has(type_name):
				asset_settings[type_name] = MechanicTerrainSettings.default_asset_entry()

			var slot := Control.new()
			slot.custom_minimum_size = Vector2(ICON_SLOT_SIZE, ICON_SLOT_SIZE)
			flow.add_child(slot)

			var icon_btn := Button.new()
			icon_btn.custom_minimum_size = Vector2(ICON_SLOT_SIZE, ICON_SLOT_SIZE)
			icon_btn.clip_text = true
			icon_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_btn.toggle_mode = true
			icon_btn.tooltip_text = type_name
			icon_btn.expand_icon = true
			icon_btn.icon = _load_asset_icon(glb_path)
			icon_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			if icon_btn.icon == null:
				icon_btn.text = type_name
				_font_btn(icon_btn, 9)
			icon_btn.pressed.connect(_select_asset.bind(type_name))
			slot.add_child(icon_btn)
			_asset_list_btns[type_name] = icon_btn

			var enable_btn := Button.new()
			enable_btn.toggle_mode = true
			enable_btn.custom_minimum_size = Vector2(ENABLE_BTN_SIZE, ENABLE_BTN_SIZE)
			enable_btn.clip_text = true
			enable_btn.anchor_left = 1.0
			enable_btn.anchor_right = 1.0
			enable_btn.offset_left = -ENABLE_BTN_SIZE
			enable_btn.offset_right = 0.0
			enable_btn.offset_top = 0.0
			enable_btn.offset_bottom = ENABLE_BTN_SIZE
			enable_btn.tooltip_text = "Enable/disable this asset on the map"
			_font_btn(enable_btn, 13)
			enable_btn.toggled.connect(_on_asset_enabled_toggled.bind(type_name))
			slot.add_child(enable_btn)
			_asset_enable_btns[type_name] = enable_btn
			_sync_enable_btn_visual(type_name)

	section.add_child(HSeparator.new())
	_selection_lbl = Label.new()
	_font(_selection_lbl, 13, UiPalette.AMBER)
	section.add_child(_selection_lbl)
	_density_slider = _make_labeled_slider(section, "Density", 0.0, 100.0, 0.5, _on_asset_density_changed)
	_density_val_lbl = _last_val_lbl
	_scale_min_slider = _make_labeled_slider(section, "Scale Min", 0.2, 3.0, 0.05, _on_asset_scale_min_changed)
	_scale_min_val_lbl = _last_val_lbl
	_scale_max_slider = _make_labeled_slider(section, "Scale Max", 0.2, 3.0, 0.05, _on_asset_scale_max_changed)
	_scale_max_val_lbl = _last_val_lbl
	_scale_bias_slider = _make_labeled_slider(section, "Size Bias (small ↔ large)", 0.0, 1.0, 0.05, _on_asset_scale_bias_changed)
	_scale_bias_val_lbl = _last_val_lbl
	_height_lbl = Label.new()
	_font(_height_lbl, 11, UiPalette.GOOD)
	section.add_child(_height_lbl)
	_blur_slider = _make_labeled_slider(section, "Blur", 0.0, 6.0, 0.1, _on_asset_blur_changed)
	_blur_val_lbl = _last_val_lbl

func _load_asset_icon(glb_path: String) -> Texture2D:
	var png_path := MechanicAssetScan.baked_png_path(glb_path)
	if not ResourceLoader.exists(png_path):
		return null
	return load(png_path) as Texture2D

func _sync_enable_btn_visual(type_name: String) -> void:
	var btn: Button = _asset_enable_btns.get(type_name)
	if btn == null:
		return
	var enabled: bool = bool(_values["asset_settings"][type_name].get("enabled", true))
	btn.set_pressed_no_signal(enabled)
	btn.text = "●" if enabled else "○"
	btn.tooltip_text = "Enabled — click to disable" if enabled else "Disabled — click to enable"
	btn.add_theme_color_override("font_color", UiPalette.GOOD if enabled else UiPalette.DANGER)

func _on_asset_enabled_toggled(on: bool, type_name: String) -> void:
	var settings: Dictionary = _values["asset_settings"]
	var entry: Dictionary = settings.get(type_name, MechanicTerrainSettings.default_asset_entry())
	entry["enabled"] = on
	settings[type_name] = entry
	_sync_enable_btn_visual(type_name)
	_apply_live_for(type_name)
	if _status != null:
		_status.text = ""

var _last_val_lbl: Label = null

func _make_labeled_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, on_change: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = label_text
	_font(lbl, 13, UiPalette.INK)
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
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(44.0, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_font(val_lbl, 13, UiPalette.AMBER)
	row.add_child(val_lbl)
	_last_val_lbl = val_lbl
	return slider

func _select_asset(type_name: String) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		if _selected_assets.has(type_name):
			_selected_assets.erase(type_name)
		else:
			_selected_assets[type_name] = true
	else:
		_selected_assets.clear()
		_selected_assets[type_name] = true
	if _selected_assets.has(type_name):
		_last_selected_asset = type_name
	elif not _selected_assets.is_empty():
		_last_selected_asset = _selected_assets.keys()[0]
	else:
		_last_selected_asset = ""
	_refresh_asset_selection_visuals()
	_sync_asset_detail_from_values()

func _refresh_asset_selection_visuals() -> void:
	for n: String in _asset_list_btns.keys():
		var b: Button = _asset_list_btns[n]
		b.set_pressed_no_signal(_selected_assets.has(n))

func _sync_asset_detail_from_values() -> void:
	if _density_slider == null:
		return
	if _selected_assets.is_empty():
		_selection_lbl.text = "No asset selected"
		return
	_selection_lbl.text = ("Editing: %s" % _last_selected_asset) if _selected_assets.size() == 1 \
		else "Editing %d assets" % _selected_assets.size()
	var anchor: String = _last_selected_asset if _last_selected_asset != "" else _selected_assets.keys()[0]
	var entry: Dictionary = _values["asset_settings"].get(anchor, MechanicTerrainSettings.default_asset_entry())
	_density_slider.set_value_no_signal(float(entry["density"]))
	_density_val_lbl.text = "%.2f" % float(entry["density"])
	_scale_min_slider.set_value_no_signal(float(entry["scale_min"]))
	_scale_min_val_lbl.text = "%.2f" % float(entry["scale_min"])
	_scale_max_slider.set_value_no_signal(float(entry["scale_max"]))
	_scale_max_val_lbl.text = "%.2f" % float(entry["scale_max"])
	_scale_bias_slider.set_value_no_signal(float(entry["scale_bias"]))
	_scale_bias_val_lbl.text = "%.2f" % float(entry["scale_bias"])
	_blur_slider.set_value_no_signal(float(entry["blur"]))
	_blur_val_lbl.text = "%.2f" % float(entry["blur"])
	_update_height_label()

func _update_height_label() -> void:
	if _last_selected_asset == "" or _height_lbl == null:
		return
	var entry: Dictionary = _values["asset_settings"][_last_selected_asset]
	var h_min: float = MechanicTreesScript.DESIRED_HEIGHT_PX * float(entry["scale_min"])
	var h_max: float = MechanicTreesScript.DESIRED_HEIGHT_PX * float(entry["scale_max"])
	var cloud: float = MechanicTreesScript.CLOUD_ALTITUDE_PX
	var suffix := ""
	var col := UiPalette.GOOD
	if h_min > cloud:
		suffix = "  — ALWAYS POKES THROUGH"
		col = UiPalette.DANGER
	elif h_max > cloud:
		suffix = "  — SOME POKE THROUGH"
		col = UiPalette.AMBER
	_height_lbl.text = "Height: %.0f–%.0fpx (cloud @ %.0fpx)%s" % [h_min, h_max, cloud, suffix]
	_height_lbl.add_theme_color_override("font_color", col)

func _set_selected_asset_field(key: String, v: float) -> void:
	if _selected_assets.is_empty():
		return
	var settings: Dictionary = _values["asset_settings"]
	for type_name: String in _selected_assets.keys():
		var entry: Dictionary = settings.get(type_name, MechanicTerrainSettings.default_asset_entry())
		entry[key] = v
		settings[type_name] = entry
		_apply_live_for(type_name)
	if _status != null:
		_status.text = ""

func _on_asset_density_changed(v: float) -> void:
	_density_val_lbl.text = "%.2f" % v
	_set_selected_asset_field("density", v)

func _on_asset_scale_min_changed(v: float) -> void:
	_scale_min_val_lbl.text = "%.2f" % v
	if v > _scale_max_slider.value:
		_scale_max_slider.value = v
	_set_selected_asset_field("scale_min", v)
	_update_height_label()

func _on_asset_scale_max_changed(v: float) -> void:
	_scale_max_val_lbl.text = "%.2f" % v
	if v < _scale_min_slider.value:
		_scale_min_slider.value = v
	_set_selected_asset_field("scale_max", v)
	_update_height_label()

func _on_asset_scale_bias_changed(v: float) -> void:
	_scale_bias_val_lbl.text = "%.2f" % v
	_set_selected_asset_field("scale_bias", v)

func _on_asset_blur_changed(v: float) -> void:
	_blur_val_lbl.text = "%.2f" % v
	_set_selected_asset_field("blur", v)

## Pushes ONE asset type's current settings to the running MechanicTrees instance.
func _apply_live_for(type_name: String) -> void:
	var entry: Dictionary = _values["asset_settings"][type_name]
	var trees := get_tree().get_first_node_in_group("mechanic_trees")
	if trees != null and trees.has_method("apply_asset_setting"):
		trees.call("apply_asset_setting", type_name, float(entry["density"]), float(entry["scale_min"]), float(entry["scale_max"]), float(entry["scale_bias"]), float(entry["blur"]), bool(entry.get("enabled", true)))

# ── Global sliders/colors (cloud + river + canopy) ──────────────────────────────────────────────────────
func _add_slider(parent: VBoxContainer, key: String, label_text: String, min_v: float, max_v: float, step_v: float) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	_font(lbl, 13, UiPalette.INK)
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
	_font(val_lbl, 13, UiPalette.AMBER)
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
	_font(lbl, 13, UiPalette.INK)
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(70.0, 24.0)
	picker.color_changed.connect(func(c: Color) -> void: _on_color_changed(key, c))
	row.add_child(picker)
	_color_btns[key] = picker

func _add_dropdown(parent: VBoxContainer, key: String, label_text: String, options: Array) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	_font(lbl, 13, UiPalette.INK)
	parent.add_child(lbl)
	var btn := OptionButton.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font_btn(btn, 13)
	for opt: String in options:
		btn.add_item(opt)
	btn.item_selected.connect(func(idx: int) -> void: _on_dropdown_changed(key, String(options[idx])))
	parent.add_child(btn)
	_dropdowns[key] = btn

func _sync_ui_from_values() -> void:
	for key: String in _sliders.keys():
		var slider: HSlider = _sliders[key]
		var v: float = float(_values[key])
		slider.set_value_no_signal(v)
		_value_lbls[key].text = "%.2f" % v
	for key: String in _color_btns.keys():
		var picker: ColorPickerButton = _color_btns[key]
		picker.color = _values[key]
	for key: String in _dropdowns.keys():
		var btn: OptionButton = _dropdowns[key]
		var value := String(_values[key])
		for i in btn.item_count:
			if btn.get_item_text(i) == value:
				btn.select(i)
				break
	for type_name: String in _asset_enable_btns.keys():
		_sync_enable_btn_visual(type_name)
	_sync_asset_detail_from_values()
	if _status != null:
		_status.text = ""

# ── Live-apply + persistence ────────────────────────────────────────────────────────────────────────
func _on_value_changed(key: String, v: float) -> void:
	_values[key] = v
	_value_lbls[key].text = "%.2f" % v
	_apply_live_global()
	if _status != null:
		_status.text = ""

func _on_dropdown_changed(key: String, value: String) -> void:
	_values[key] = value
	_apply_live_global()
	if _status != null:
		_status.text = ""

func _on_color_changed(key: String, c: Color) -> void:
	_values[key] = c
	_apply_live_global()
	if _status != null:
		_status.text = ""

func _apply_live_global() -> void:
	var ground := get_tree().get_first_node_in_group("mechanic_ground")
	if ground != null and ground.has_method("apply_terrain_colors"):
		ground.call("apply_terrain_colors", _values["color_a"], _values["color_b"])
	if ground != null and ground.has_method("apply_river_width"):
		ground.call("apply_river_width", _values["river_width"])
	if ground != null and ground.has_method("apply_river_count"):
		ground.call("apply_river_count", int(_values["river_count"]))
	if ground != null and ground.has_method("apply_canopy_size"):
		ground.call("apply_canopy_size", _values["canopy_size"])
	if ground != null and ground.has_method("apply_canopy_mottle_scale"):
		ground.call("apply_canopy_mottle_scale", _values["canopy_mottle_scale"])
	if ground != null and ground.has_method("apply_canopy_blend_width"):
		ground.call("apply_canopy_blend_width", _values["canopy_blend_width"])
	if ground != null and ground.has_method("apply_river_bank_color"):
		ground.call("apply_river_bank_color", _values["river_bank_color"])
	if ground != null and ground.has_method("apply_river_bank_width"):
		ground.call("apply_river_bank_width", _values["river_bank_width"])
	if ground != null and ground.has_method("apply_water_color"):
		ground.call("apply_water_color", _values["water_color"])
	if ground != null and ground.has_method("apply_water_wave_size"):
		ground.call("apply_water_wave_size", _values["water_wave_size"])
	if ground != null and ground.has_method("apply_canopy_images"):
		ground.call("apply_canopy_images", _values["maptile_set"])
	if ground != null and ground.has_method("apply_water_tile_set"):
		ground.call("apply_water_tile_set", _values["water_tile_set"])
	var clouds := get_tree().get_first_node_in_group("mechanic_clouds")
	if clouds != null and clouds.has_method("apply_cloud_settings"):
		clouds.call("apply_cloud_settings", _values["cloud_opacity"], _values["cloud_brightness"], _values["cloud_color"], _values["cloud_clumpiness"])
	if clouds != null and clouds.has_method("apply_wind_settings"):
		clouds.call("apply_wind_settings", _values["cloud_wind_strength"], _values["cloud_wind_angle_deg"])
	var trees := get_tree().get_first_node_in_group("mechanic_trees")
	if trees != null and trees.has_method("apply_river_width"):
		trees.call("apply_river_width", _values["river_width"])
	if trees != null and trees.has_method("apply_river_count"):
		trees.call("apply_river_count", int(_values["river_count"]))
	if trees != null and trees.has_method("apply_canopy_mottle_scale"):
		trees.call("apply_canopy_mottle_scale", _values["canopy_mottle_scale"])   # seam-based river check depends on it
	if trees != null and trees.has_method("apply_jitter"):
		trees.call("apply_jitter", _values["jitter"])
	var plumes := get_tree().get_first_node_in_group("mechanic_plumes")
	if plumes != null and plumes.has_method("apply_river_width"):
		plumes.call("apply_river_width", _values["river_width"])   # keeps energy vents off the river band
	if plumes != null and plumes.has_method("apply_river_count"):
		plumes.call("apply_river_count", int(_values["river_count"]))
	if plumes != null and plumes.has_method("apply_canopy_size"):
		plumes.call("apply_canopy_size", _values["canopy_size"])   # marked-vent replication period depends on it
	if plumes != null and plumes.has_method("apply_canopy_mottle_scale"):
		plumes.call("apply_canopy_mottle_scale", _values["canopy_mottle_scale"])   # marked-vent region check depends on it

## Scoped save — re-reads whatever's CURRENTLY on disk and overwrites ONLY this panel's own keys, instead of
## blanket-writing a possibly-stale snapshot (mirrors electric_terrain_edit.gd's own 2026-08-08 fix — see that
## file's header for the full bug rationale).
func _on_save() -> void:
	var fresh := MechanicTerrainSettings.load_settings()
	for key: String in _sliders.keys():
		fresh[key] = _values[key]
	for key: String in _color_btns.keys():
		fresh[key] = _values[key]
	for key: String in _dropdowns.keys():
		fresh[key] = _values[key]
	fresh["asset_settings"] = _values["asset_settings"]
	MechanicTerrainSettings.save_settings(fresh)
	if _status != null:
		_status.text = "Saved."

func _on_reset() -> void:
	_values["cloud_opacity"] = MechanicTerrainSettings.DEFAULT_CLOUD_OPACITY
	_values["cloud_brightness"] = MechanicTerrainSettings.DEFAULT_CLOUD_BRIGHTNESS
	_values["cloud_color"] = MechanicTerrainSettings.DEFAULT_CLOUD_COLOR
	_values["cloud_clumpiness"] = MechanicTerrainSettings.DEFAULT_CLOUD_CLUMPINESS
	_values["cloud_wind_strength"] = MechanicTerrainSettings.DEFAULT_CLOUD_WIND_STRENGTH
	_values["cloud_wind_angle_deg"] = MechanicTerrainSettings.DEFAULT_CLOUD_WIND_ANGLE_DEG
	_values["river_width"] = MechanicTerrainSettings.DEFAULT_RIVER_WIDTH
	_values["river_count"] = MechanicTerrainSettings.DEFAULT_RIVER_COUNT
	_values["river_bank_color"] = MechanicTerrainSettings.DEFAULT_RIVER_BANK_COLOR
	_values["river_bank_width"] = MechanicTerrainSettings.DEFAULT_RIVER_BANK_WIDTH
	_values["water_color"] = MechanicTerrainSettings.DEFAULT_WATER_COLOR
	_values["water_wave_size"] = MechanicTerrainSettings.DEFAULT_WATER_WAVE_SIZE
	_values["jitter"] = MechanicTerrainSettings.DEFAULT_JITTER
	_values["canopy_size"] = MechanicTerrainSettings.DEFAULT_CANOPY_SIZE
	_values["canopy_mottle_scale"] = MechanicTerrainSettings.DEFAULT_CANOPY_MOTTLE_SCALE
	_values["canopy_blend_width"] = MechanicTerrainSettings.DEFAULT_CANOPY_BLEND_WIDTH
	_values["maptile_set"] = MechanicTerrainSettings.DEFAULT_MAPTILE_SET
	_values["water_tile_set"] = MechanicTerrainSettings.DEFAULT_WATER_TILE_SET
	_values["color_a"] = MechanicTerrainSettings.DEFAULT_COLOR_A
	_values["color_b"] = MechanicTerrainSettings.DEFAULT_COLOR_B
	for type_name: String in _selected_assets.keys():
		_values["asset_settings"][type_name] = MechanicTerrainSettings.default_asset_entry()
	_sync_ui_from_values()
	_apply_live_global()
	for type_name: String in _selected_assets.keys():
		_apply_live_for(type_name)
	if _status != null:
		_status.text = "Reset globals + %d asset(s) to defaults (not saved yet)." % _selected_assets.size()

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Control, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
