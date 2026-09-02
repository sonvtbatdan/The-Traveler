extends CanvasLayer
class_name VolcanicTerrainEdit
## Dev-mode-only Volcanic terrain tuning — group "volcanic_terrain_edit", toggled from
## arena_hud_buttons.gd's TERRAIN EDIT button (Volcanic map only). Mirrors
## scripts/ui/hud/electric_terrain_edit.gd (same two-panel ASSETS + TERRAIN EDIT layout, same drag/multi-select
## asset-editing behavior — see that file's header for the full rationale). Deltas: reads/writes
## VolcanicAssetScan/VolcanicTerrainSettings/volcanic_terrain.cfg instead, labels reworded for the volcanic
## palette (basalt/ash/obsidian/lava instead of grass/sand/water), and no Landmark Ring Width row — Volcanic
## has no landmark system yet (see volcanic_ground.gd's header).

const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")
const VolcanicAssetScan := preload("res://scripts/gameplay/volcanic/volcanic_asset_scan.gd")
const VolcanicTreesScript := preload("res://scripts/gameplay/volcanic/volcanic_trees.gd")

const TERRAIN_PANEL_W := 360.0
const ASSET_PANEL_W := 300.0
const ICON_SLOT_SIZE := 64.0
const ENABLE_BTN_SIZE := 18.0

var _is_open: bool = false
var _terrain_panel: Panel = null
var _asset_panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}
var _sliders: Dictionary = {}
var _value_lbls: Dictionary = {}
var _color_btns: Dictionary = {}
var _dropdowns: Dictionary = {}

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
	layer = 61   # same tier as electric_terrain_edit.gd / creep_info_panel.gd
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("volcanic_terrain_edit")

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's TERRAIN EDIT button.
func toggle() -> void:
	_is_open = not _is_open
	if _terrain_panel != null:
		_terrain_panel.visible = _is_open
	if _asset_panel != null:
		_asset_panel.visible = _is_open
	if not _is_open:
		return
	if _terrain_panel == null:
		_values = VolcanicTerrainSettings.load_settings()
		_build_ui()
	_sync_ui_from_values()

func _on_panel_drag_input(event: InputEvent, panel: Panel) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		_drag_panel = panel
		_drag_off = panel.global_position - get_viewport().get_mouse_position()

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
	_build_terrain_panel()
	var first_name := _build_asset_panel()
	if first_name != "":
		_select_asset(first_name)

func _new_panel_shell(pos: Vector2, w: float, max_h: float, title_text: String) -> Dictionary:
	var panel := Panel.new()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	panel.position = pos
	panel.size = Vector2(w, minf(max_h, vp_h - pos.y - 20.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.35, 0.15)   # warm ember border — visually distinct from Electric's blue
	sb.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	UiPalette.scanlines(panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)

	var title := Label.new()
	title.text = title_text
	_font(title, 15, Color(1.0, 0.9, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Drag to move"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input.bind(panel))
	outer.add_child(title)

	return {"panel": panel, "outer": outer}

func _build_terrain_panel() -> void:
	var shell := _new_panel_shell(Vector2(20.0, 44.0), TERRAIN_PANEL_W, 600.0, "≡ TERRAIN EDIT")
	_terrain_panel = shell["panel"]
	var outer: VBoxContainer = shell["outer"]
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	_add_slider(col, "river_width", "Lava Width", 0.0, 0.15, 0.005)
	_add_slider(col, "river_bank_width", "River Bank Width", 0.0, 0.05, 0.001)
	_add_slider(col, "river_edge_jaggedness", "River Edge Jaggedness", 0.0, 1.5, 0.02)
	_add_color_row(col, "water_color", "Lava Color")
	_add_dropdown(col, "water_tile_set", "Lava Pattern", VolcanicAssetScan.watertile_set_names())
	_add_slider(col, "water_wave_size", "Lava Flow Size", 60.0, 800.0, 10.0)
	_add_slider(col, "water_wave_speed", "Lava Flow Speed", 0.0, 60.0, 1.0)
	_add_color_row(col, "river_bank_color", "Obsidian Crust Color")
	_add_slider(col, "jitter", "Jitter", 0.0, 1.0, 0.02)
	_add_dropdown(col, "maptile_set", "Tile Set", VolcanicAssetScan.maptile_set_names())
	_add_slider(col, "canopy_size", "Ground Tile Size", 400.0, 4000.0, 25.0)
	col.add_child(HSeparator.new())
	_add_color_row(col, "color_a", "Terrain Color A (basalt)")
	_add_color_row(col, "color_b", "Terrain Color B (ash)")
	col.add_child(HSeparator.new())

	_selection_lbl = Label.new()
	_font(_selection_lbl, 13, UiPalette.AMBER)
	col.add_child(_selection_lbl)
	_density_slider = _make_labeled_slider(col, "Density", 0.0, 100.0, 0.5, _on_asset_density_changed)
	_density_val_lbl = _last_val_lbl
	_scale_min_slider = _make_labeled_slider(col, "Scale Min", 0.2, 3.0, 0.05, _on_asset_scale_min_changed)
	_scale_min_val_lbl = _last_val_lbl
	_scale_max_slider = _make_labeled_slider(col, "Scale Max", 0.2, 3.0, 0.05, _on_asset_scale_max_changed)
	_scale_max_val_lbl = _last_val_lbl
	_scale_bias_slider = _make_labeled_slider(col, "Size Bias (small ↔ large)", 0.0, 1.0, 0.05, _on_asset_scale_bias_changed)
	_scale_bias_val_lbl = _last_val_lbl
	_height_lbl = Label.new()
	_font(_height_lbl, 11, UiPalette.GOOD)
	col.add_child(_height_lbl)
	_blur_slider = _make_labeled_slider(col, "Blur", 0.0, 6.0, 0.1, _on_asset_blur_changed)
	_blur_val_lbl = _last_val_lbl

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

## Returns the first discovered type_name (auto-selected once both panels exist), or "" if none found —
## assets/map/volcanic/ currently has no .glb files, so this returns "" and _build_asset_panel() itself
## returns without creating a panel (mirrors electric_terrain_edit.gd's empty-folder handling).
func _build_asset_panel() -> String:
	var glb_paths: Array = VolcanicAssetScan.glb_paths()
	if glb_paths.is_empty():
		return ""

	var shell := _new_panel_shell(Vector2(20.0 + TERRAIN_PANEL_W + 16.0, 44.0), ASSET_PANEL_W, 460.0, "≡ ASSETS")
	_asset_panel = shell["panel"]
	var outer: VBoxContainer = shell["outer"]

	var hint := Label.new()
	hint.text = "Click = select · Shift+click = multi-select"
	_font(hint, 10, Color(0.65, 0.55, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	scroll.add_child(flow)

	var asset_settings: Dictionary = _values["asset_settings"]
	var first_name := ""
	for glb_path: String in glb_paths:
		var type_name := VolcanicAssetScan.type_name(glb_path)
		if first_name == "":
			first_name = type_name
		if not asset_settings.has(type_name):
			asset_settings[type_name] = VolcanicTerrainSettings.default_asset_entry()

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

	return first_name

func _load_asset_icon(glb_path: String) -> Texture2D:
	var png_path := VolcanicAssetScan.baked_png_path(glb_path)
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
	var entry: Dictionary = settings.get(type_name, VolcanicTerrainSettings.default_asset_entry())
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
	var entry: Dictionary = _values["asset_settings"].get(anchor, VolcanicTerrainSettings.default_asset_entry())
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
	var h_min: float = VolcanicTreesScript.DESIRED_HEIGHT_PX * float(entry["scale_min"])
	var h_max: float = VolcanicTreesScript.DESIRED_HEIGHT_PX * float(entry["scale_max"])
	var cloud: float = VolcanicTreesScript.CLOUD_ALTITUDE_PX
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
		var entry: Dictionary = settings.get(type_name, VolcanicTerrainSettings.default_asset_entry())
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

func _apply_live_for(type_name: String) -> void:
	var entry: Dictionary = _values["asset_settings"][type_name]
	var trees := get_tree().get_first_node_in_group("volcanic_trees")
	if trees != null and trees.has_method("apply_asset_setting"):
		trees.call("apply_asset_setting", type_name, float(entry["density"]), float(entry["scale_min"]), float(entry["scale_max"]), float(entry["scale_bias"]), float(entry["blur"]), bool(entry.get("enabled", true)))

# ── Global sliders/colors (cloud + lava + terrain color) ────────────────────────────────────────────────
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
	var ground := get_tree().get_first_node_in_group("volcanic_ground")
	if ground != null and ground.has_method("apply_terrain_colors"):
		ground.call("apply_terrain_colors", _values["color_a"], _values["color_b"])
	if ground != null and ground.has_method("apply_river_width"):
		ground.call("apply_river_width", _values["river_width"])
	if ground != null and ground.has_method("apply_river_bank_width"):
		ground.call("apply_river_bank_width", _values["river_bank_width"])
	if ground != null and ground.has_method("apply_river_edge_jaggedness"):
		ground.call("apply_river_edge_jaggedness", _values["river_edge_jaggedness"])
	if ground != null and ground.has_method("apply_canopy_size"):
		ground.call("apply_canopy_size", _values["canopy_size"])
	if ground != null and ground.has_method("apply_river_bank_color"):
		ground.call("apply_river_bank_color", _values["river_bank_color"])
	if ground != null and ground.has_method("apply_water_color"):
		ground.call("apply_water_color", _values["water_color"])
	if ground != null and ground.has_method("apply_water_wave_size"):
		ground.call("apply_water_wave_size", _values["water_wave_size"])
	if ground != null and ground.has_method("apply_water_wave_speed"):
		ground.call("apply_water_wave_speed", _values["water_wave_speed"])
	if ground != null and ground.has_method("apply_maptile_set"):
		ground.call("apply_maptile_set", _values["maptile_set"])
	if ground != null and ground.has_method("apply_water_tile_set"):
		ground.call("apply_water_tile_set", _values["water_tile_set"])
	var clouds := get_tree().get_first_node_in_group("volcanic_clouds")
	if clouds != null and clouds.has_method("apply_canopy_size"):
		clouds.call("apply_canopy_size", _values["canopy_size"])   # marked-crater replication period depends on it
	if clouds != null and clouds.has_method("apply_river_width"):
		clouds.call("apply_river_width", _values["river_width"])   # keeps plume/flame vents off the lava band
	var trees := get_tree().get_first_node_in_group("volcanic_trees")
	if trees != null and trees.has_method("apply_river_width"):
		trees.call("apply_river_width", _values["river_width"])
	if trees != null and trees.has_method("apply_jitter"):
		trees.call("apply_jitter", _values["jitter"])

## Scoped save — re-reads whatever's CURRENTLY on disk and overwrites ONLY this panel's own keys (plus
## asset_settings), instead of blanket-writing this panel's own possibly-stale `_values` snapshot (taken once,
## back when the panel was opened). 2026-08-08 bug fix (found via the Atlantic port): with the old blanket save,
## opening this panel and clicking SAVE at any later point silently reverted every OTHER panel's changes since —
## e.g. Crater Mark's vent marks — back to whatever they were when THIS panel was first opened. Mirrors
## volcanic_crater_mark.gd's _save_marks_only()/volcanic_landmark_mark.gd's own scoped save.
func _on_save() -> void:
	var fresh := VolcanicTerrainSettings.load_settings()
	for key: String in _sliders.keys():
		fresh[key] = _values[key]
	for key: String in _color_btns.keys():
		fresh[key] = _values[key]
	for key: String in _dropdowns.keys():
		fresh[key] = _values[key]
	fresh["asset_settings"] = _values["asset_settings"]
	VolcanicTerrainSettings.save_settings(fresh)
	if _status != null:
		_status.text = "Saved."

func _on_reset() -> void:
	_values["river_width"] = VolcanicTerrainSettings.DEFAULT_RIVER_WIDTH
	_values["river_bank_width"] = VolcanicTerrainSettings.DEFAULT_RIVER_BANK_WIDTH
	_values["river_edge_jaggedness"] = VolcanicTerrainSettings.DEFAULT_RIVER_EDGE_JAGGEDNESS
	_values["river_bank_color"] = VolcanicTerrainSettings.DEFAULT_RIVER_BANK_COLOR
	_values["water_color"] = VolcanicTerrainSettings.DEFAULT_WATER_COLOR
	_values["water_wave_size"] = VolcanicTerrainSettings.DEFAULT_WATER_WAVE_SIZE
	_values["water_wave_speed"] = VolcanicTerrainSettings.DEFAULT_WATER_WAVE_SPEED
	_values["jitter"] = VolcanicTerrainSettings.DEFAULT_JITTER
	_values["canopy_size"] = VolcanicTerrainSettings.DEFAULT_CANOPY_SIZE
	_values["maptile_set"] = VolcanicTerrainSettings.DEFAULT_MAPTILE_SET
	_values["water_tile_set"] = VolcanicTerrainSettings.DEFAULT_WATER_TILE_SET
	_values["color_a"] = VolcanicTerrainSettings.DEFAULT_COLOR_A
	_values["color_b"] = VolcanicTerrainSettings.DEFAULT_COLOR_B
	for type_name: String in _selected_assets.keys():
		_values["asset_settings"][type_name] = VolcanicTerrainSettings.default_asset_entry()
	_sync_ui_from_values()
	_apply_live_global()
	for type_name: String in _selected_assets.keys():
		_apply_live_for(type_name)
	if _status != null:
		_status.text = "Reset globals + %d asset(s) to defaults (not saved yet)." % _selected_assets.size()

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
