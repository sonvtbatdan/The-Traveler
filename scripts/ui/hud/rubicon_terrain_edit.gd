extends CanvasLayer
class_name RubiconTerrainEdit
## Dev-mode-only Rubicon terrain tuning panel — group "rubicon_terrain_edit", toggled from
## arena_hud_buttons.gd's TERRAIN EDIT button (Rubicon map only, sits above the Simplified button). Applies
## LIVE to the running RubiconGround / RubiconClouds / RubiconTrees instances (found via their own groups —
## "rubicon_ground"/"rubicon_clouds"/"rubicon_trees") as sliders/pickers change. SAVE persists to
## res://rubicon_terrain.cfg via RubiconTerrainSettings so the look survives the next session (mirrors
## creep_info_panel.gd's persistence convention); closing without Save keeps the live look for the rest of
## THIS run but won't survive a reload.
##
## Assets (one per discovered .glb — RubiconAssetScan) get their OWN independent Density/Scale/Size-Bias/Blur,
## picked via the button list; Cloud Opacity/Brightness, River Width, and the 2 terrain colors stay global.
## The Scale row shows a live "Height" readout against CLOUD_ALTITUDE_PX so you can see whether the current
## asset renders above or below the cloud layer before it visibly pops there.
##
## Uses the engine's default font (no custom Font resource) and tight spacing throughout — the asset list can
## grow (density/scale/bias/blur per discovered .glb), so the whole middle section sits in a height-capped
## ScrollContainer (SCROLL_HEIGHT) with SAVE/RESET/CLOSE pinned below it, and the panel is repositioned/
## clamped to the current viewport on open + resize — so those buttons stay reachable no matter how tall the
## asset list gets or what resolution the game runs at (a fixed screen-relative position/size broke exactly
## this way once already).

const RubiconTerrainSettings := preload("res://scripts/gameplay/rubicon/rubicon_terrain_settings.gd")
const RubiconAssetScan := preload("res://scripts/gameplay/rubicon/rubicon_asset_scan.gd")
const RubiconTreesScript := preload("res://scripts/gameplay/rubicon/rubicon_trees.gd")

const PANEL_WIDTH := 400.0
const SCROLL_HEIGHT_MAX := 420.0   # bounded — keeps total panel height predictable regardless of asset count
const SCROLL_HEIGHT_MIN := 200.0   # never shrink the scroll area below this even on a tiny viewport

var _is_open: bool = false
var _root: Control = null
var _panel: PanelContainer = null
var _values: Dictionary = {}
var _sliders: Dictionary = {}      # global key -> HSlider (cloud_opacity/cloud_brightness/river_width)
var _value_lbls: Dictionary = {}   # global key -> Label
var _color_btns: Dictionary = {}   # global key -> ColorPickerButton

var _asset_list_btns: Dictionary = {}   # type_name -> Button
var _selected_asset: String = ""
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
	layer = 61   # same tier as creep_info_panel.gd (above the HUD dev-column buttons)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("rubicon_terrain_edit")
	visible = false

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's TERRAIN EDIT button.
func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if not _is_open:
		return
	if _root == null:
		_values = RubiconTerrainSettings.load_settings()
		_build_ui()
	_sync_ui_from_values()
	call_deferred("_reposition_panel")

# ── UI ───────────────────────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.75)
	sb.set_content_margin_all(14.0)
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)
	_panel.resized.connect(_reposition_panel)
	get_viewport().size_changed.connect(_reposition_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "TERRAIN EDIT"
	_font(title, 20, Color(0.9, 0.93, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	outer.add_child(HSeparator.new())

	# Scroll height scales down on short viewports (~45% of viewport height, clamped) instead of a flat
	# constant — on a small window a fixed 420px could itself be taller than the screen, defeating the
	# whole point of capping this section so SAVE/RESET/CLOSE stay reachable.
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var scroll_h: float = clampf(vp_h * 0.45, SCROLL_HEIGHT_MIN, SCROLL_HEIGHT_MAX)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, scroll_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	_add_slider(col, "cloud_opacity", "Cloud Opacity", 0.0, 2.5, 0.05)
	_add_slider(col, "cloud_brightness", "Cloud Brightness", 0.1, 2.5, 0.05)
	_add_slider(col, "river_width", "River Width", 0.0, 0.15, 0.005)
	col.add_child(HSeparator.new())
	_add_color_row(col, "color_a", "Terrain Color A (grass)")
	_add_color_row(col, "color_b", "Terrain Color B (sand)")
	col.add_child(HSeparator.new())

	_build_asset_section(col)

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

## Keeps the panel centered but clamped fully inside the current viewport — called after building the UI,
## whenever the panel's own size changes (e.g. first layout pass), and on viewport resize. Without this a
## screen-relative fixed offset can push SAVE/RESET/CLOSE below the visible area on smaller viewports or once
## the asset list/section grows (see class doc comment).
func _reposition_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var psize: Vector2 = _panel.size
	var pos: Vector2 = (vp_size - psize) * 0.5
	pos.x = clampf(pos.x, 10.0, maxf(10.0, vp_size.x - psize.x - 10.0))
	pos.y = clampf(pos.y, 10.0, maxf(10.0, vp_size.y - psize.y - 10.0))
	_panel.position = pos

# ── Asset list + per-asset Density/Scale/Bias/Blur ─────────────────────────────────────────────────────
func _build_asset_section(col: VBoxContainer) -> void:
	var glb_paths: Array = RubiconAssetScan.glb_paths()
	if glb_paths.is_empty():
		return

	var asset_title := Label.new()
	asset_title.text = "Assets — click one to edit it"
	_font(asset_title, 13, Color(0.8, 0.85, 0.95))
	col.add_child(asset_title)

	var list_row := HFlowContainer.new()
	list_row.add_theme_constant_override("h_separation", 6)
	list_row.add_theme_constant_override("v_separation", 6)
	col.add_child(list_row)

	var asset_settings: Dictionary = _values["asset_settings"]
	var first_name := ""
	for glb_path: String in glb_paths:
		var type_name := RubiconAssetScan.type_name(glb_path)
		if first_name == "":
			first_name = type_name
		if not asset_settings.has(type_name):
			asset_settings[type_name] = RubiconTerrainSettings.default_asset_entry()
		var b := Button.new()
		b.text = type_name
		_font_btn(b, 12)
		b.custom_minimum_size = Vector2(0.0, 22.0)
		b.toggle_mode = true
		b.pressed.connect(_select_asset.bind(type_name))
		list_row.add_child(b)
		_asset_list_btns[type_name] = b

	col.add_child(HSeparator.new())
	_density_slider = _make_labeled_slider(col, "Density", 0.0, 2.5, 0.05, _on_asset_density_changed)
	_density_val_lbl = _last_val_lbl
	_scale_min_slider = _make_labeled_slider(col, "Scale Min", 0.2, 3.0, 0.05, _on_asset_scale_min_changed)
	_scale_min_val_lbl = _last_val_lbl
	_scale_max_slider = _make_labeled_slider(col, "Scale Max", 0.2, 3.0, 0.05, _on_asset_scale_max_changed)
	_scale_max_val_lbl = _last_val_lbl
	_scale_bias_slider = _make_labeled_slider(col, "Size Bias (small ↔ large)", 0.0, 1.0, 0.05, _on_asset_scale_bias_changed)
	_scale_bias_val_lbl = _last_val_lbl
	_height_lbl = Label.new()
	_font(_height_lbl, 11, Color(0.6, 0.9, 0.6))
	col.add_child(_height_lbl)
	_blur_slider = _make_labeled_slider(col, "Blur", 0.0, 6.0, 0.1, _on_asset_blur_changed)
	_blur_val_lbl = _last_val_lbl

	_select_asset(first_name)

## _make_labeled_slider stashes its value-label here so callers can grab it right after — avoids a 6th
## return value / an output Array just to hand back two widgets.
var _last_val_lbl: Label = null

func _make_labeled_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, on_change: Callable) -> HSlider:
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
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(44.0, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_font(val_lbl, 13, Color(1.0, 0.86, 0.3))
	row.add_child(val_lbl)
	_last_val_lbl = val_lbl
	return slider

func _select_asset(type_name: String) -> void:
	_selected_asset = type_name
	for n: String in _asset_list_btns.keys():
		var b: Button = _asset_list_btns[n]
		b.button_pressed = (n == type_name)
	_sync_asset_detail_from_values()

func _sync_asset_detail_from_values() -> void:
	if _selected_asset == "" or _density_slider == null:
		return
	var entry: Dictionary = _values["asset_settings"].get(_selected_asset, RubiconTerrainSettings.default_asset_entry())
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

## Shows the FULL possible height range (every scattered instance rolls its own random scale somewhere in
## [scale_min, scale_max]) against CLOUD_ALTITUDE_PX. Clipping is real per-pixel depth testing against the
## cloud occluder mesh now (rubicon_trees.gd), so even a tall instance still has its base hidden under the
## cloud — this readout just tells you whether ANY part of it ever pokes through the top: green = never,
## orange = only the taller rolls in this scale range poke through, red = every roll pokes through.
func _update_height_label() -> void:
	if _selected_asset == "" or _height_lbl == null:
		return
	var entry: Dictionary = _values["asset_settings"][_selected_asset]
	var h_min: float = RubiconTreesScript.DESIRED_HEIGHT_PX * float(entry["scale_min"])
	var h_max: float = RubiconTreesScript.DESIRED_HEIGHT_PX * float(entry["scale_max"])
	var cloud: float = RubiconTreesScript.CLOUD_ALTITUDE_PX
	var suffix := ""
	var col := Color(0.55, 0.9, 0.55)
	if h_min > cloud:
		suffix = "  — ALWAYS POKES THROUGH"
		col = Color(1.0, 0.4, 0.3)
	elif h_max > cloud:
		suffix = "  — SOME POKE THROUGH"
		col = Color(1.0, 0.7, 0.3)
	_height_lbl.text = "Height: %.0f–%.0fpx (cloud @ %.0fpx)%s" % [h_min, h_max, cloud, suffix]
	_height_lbl.add_theme_color_override("font_color", col)

func _set_selected_asset_field(key: String, v: float) -> void:
	if _selected_asset == "":
		return
	var settings: Dictionary = _values["asset_settings"]
	var entry: Dictionary = settings.get(_selected_asset, RubiconTerrainSettings.default_asset_entry())
	entry[key] = v
	settings[_selected_asset] = entry
	_apply_live_for_selected()
	if _status != null:
		_status.text = ""

func _on_asset_density_changed(v: float) -> void:
	_density_val_lbl.text = "%.2f" % v
	_set_selected_asset_field("density", v)

func _on_asset_scale_min_changed(v: float) -> void:
	_scale_min_val_lbl.text = "%.2f" % v
	if v > _scale_max_slider.value:
		_scale_max_slider.value = v   # keep min <= max — fires _on_asset_scale_max_changed too
	_set_selected_asset_field("scale_min", v)
	_update_height_label()

func _on_asset_scale_max_changed(v: float) -> void:
	_scale_max_val_lbl.text = "%.2f" % v
	if v < _scale_min_slider.value:
		_scale_min_slider.value = v   # keep min <= max — fires _on_asset_scale_min_changed too
	_set_selected_asset_field("scale_max", v)
	_update_height_label()

func _on_asset_scale_bias_changed(v: float) -> void:
	_scale_bias_val_lbl.text = "%.2f" % v
	_set_selected_asset_field("scale_bias", v)

func _on_asset_blur_changed(v: float) -> void:
	_blur_val_lbl.text = "%.2f" % v
	_set_selected_asset_field("blur", v)

func _apply_live_for_selected() -> void:
	if _selected_asset == "":
		return
	var entry: Dictionary = _values["asset_settings"][_selected_asset]
	var trees := get_tree().get_first_node_in_group("rubicon_trees")
	if trees != null and trees.has_method("apply_asset_setting"):
		trees.call("apply_asset_setting", _selected_asset, float(entry["density"]), float(entry["scale_min"]), float(entry["scale_max"]), float(entry["scale_bias"]), float(entry["blur"]))

# ── Global sliders/colors (cloud + river + terrain color) ──────────────────────────────────────────────
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

func _on_color_changed(key: String, c: Color) -> void:
	_values[key] = c
	_apply_live_global()
	if _status != null:
		_status.text = ""

func _apply_live_global() -> void:
	var ground := get_tree().get_first_node_in_group("rubicon_ground")
	if ground != null and ground.has_method("apply_terrain_colors"):
		ground.call("apply_terrain_colors", _values["color_a"], _values["color_b"])
	if ground != null and ground.has_method("apply_river_width"):
		ground.call("apply_river_width", _values["river_width"])
	var clouds := get_tree().get_first_node_in_group("rubicon_clouds")
	if clouds != null and clouds.has_method("apply_cloud_settings"):
		clouds.call("apply_cloud_settings", _values["cloud_opacity"], _values["cloud_brightness"])
	var trees := get_tree().get_first_node_in_group("rubicon_trees")
	if trees != null and trees.has_method("apply_cloud_settings"):
		trees.call("apply_cloud_settings", _values["cloud_opacity"], _values["cloud_brightness"])
	if trees != null and trees.has_method("apply_river_width"):
		trees.call("apply_river_width", _values["river_width"])

func _on_save() -> void:
	RubiconTerrainSettings.save_settings(_values)
	if _status != null:
		_status.text = "Saved."

## Resets the GLOBAL knobs (cloud/river/terrain color) plus whichever asset is currently selected — NOT every
## asset, so resetting doesn't silently wipe tuning on types you aren't even looking at.
func _on_reset() -> void:
	_values["cloud_opacity"] = RubiconTerrainSettings.DEFAULT_CLOUD_OPACITY
	_values["cloud_brightness"] = RubiconTerrainSettings.DEFAULT_CLOUD_BRIGHTNESS
	_values["river_width"] = RubiconTerrainSettings.DEFAULT_RIVER_WIDTH
	_values["color_a"] = RubiconTerrainSettings.DEFAULT_COLOR_A
	_values["color_b"] = RubiconTerrainSettings.DEFAULT_COLOR_B
	if _selected_asset != "":
		_values["asset_settings"][_selected_asset] = RubiconTerrainSettings.default_asset_entry()
	_sync_ui_from_values()
	_apply_live_global()
	_apply_live_for_selected()
	if _status != null:
		_status.text = "Reset globals + %s to defaults (not saved yet)." % _selected_asset

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
