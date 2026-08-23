extends CanvasLayer
class_name MechanicVentMark
## Dev-mode-only Mechanic vent-marking tool — group "mechanic_vent_mark", toggled from arena_hud_buttons.gd's
## CRATER MARK button (Mechanic map only; button/group name kept generic across maps — Atlantic's own vent
## panel is titled "VENT MARK" under the same shared button too, see atlantic_crater_mark.gd's header).
## 2026-08-19, on request ("có plume nhưng không có plume mark thì đánh dấu plume kiểu gì") — the first plume
## pass shipped only the ambient-grid spawn tier with no way to place a vent at a DELIBERATE spot (e.g. right
## on one of the canopy art's own pipe/vent details); this is that missing piece. Port of
## volcanic_crater_mark.gd (see that file's header for the full rationale — shows the maptile set's reference
## photos so the user can click directly on a vent they see IN THE PHOTO; a mark is a normalized (u, v)
## position on ONE specific photo, replicated at EVERY world-space repetition of that photo by
## mechanic_plumes.gd, not a single world position).
##
## NO TABS — unlike Volcanic/Atlantic's 2-kind split, Mechanic has only ONE vent kind (energy beam, see
## mechanic_plumes.gd's header for why), so there's just one flat mark list (`beam_marks`). SEVEN reference
## photos (0=a..6=g, MechanicAssetScan.maptile_set_image_paths("default")) instead of Volcanic/Atlantic's 3 —
## all 7 of Mechanic's canopy photos are used together (see mechanic_ground.gdshader), not a 3-of-N pick.
##
## Left-click on the photo = add a mark. Right-click near an existing mark = remove it. Applies LIVE to the
## running MechanicPlumes instance (apply_vent_marks) on every add/remove. SAVE persists to
## res://mechanic_terrain.cfg via MechanicTerrainSettings — loads/saves the FULL settings dict so it never
## clobbers Terrain/Light/Plume Edit's own keys living in the same file.
##
## The reference photo displays at a fixed IMAGE_SIZE (1000x1000, for precise clicking) inside a
## ScrollContainer, and the whole panel is centered on screen (not corner-docked like the other 3 Mechanic
## panels) — same "doesn't fully fit the base 1440x780 viewport otherwise" reasoning as volcanic_crater_mark.gd.

const MechanicTerrainSettings := preload("res://scripts/gameplay/mechanic/mechanic_terrain_settings.gd")
const MechanicAssetScan := preload("res://scripts/gameplay/mechanic/mechanic_asset_scan.gd")

const PANEL_W := 1040.0
const IMAGE_SIZE := 1000.0
const THUMB_SIZE := 56.0
const MARK_DOT_SIZE := 10.0
const REMOVE_CLICK_RADIUS := 0.05   # normalized UV distance — right-click must land within this of a mark to remove it
const SCREEN_MARGIN := 20.0         # min gap kept between the centered panel and the viewport edges
const DOT_COLOR := Color(0.35, 0.85, 0.95, 0.9)   # energy-cyan — distinct from Volcanic's crater-red/flame-orange

var _is_open: bool = false
var _panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}     # full settings dict — we mutate _values["beam_marks"]
var _tex_paths: Array = []       # positional a..g, from MechanicAssetScan.maptile_set_image_paths()
var _tex_buttons: Array = []
var _image_rect: TextureRect = null
var _marker_layer: Control = null
var _selected_tex: int = 0
var _count_lbl: Label = null
var _status: Label = null

func _ready() -> void:
	layer = 61   # same tier as the other Mechanic dev panels
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mechanic_vent_mark")

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's CRATER MARK button.
func toggle() -> void:
	_is_open = not _is_open
	if _panel != null:
		_panel.visible = _is_open
	if not _is_open:
		return
	if _panel == null:
		_values = MechanicTerrainSettings.load_settings()
		_tex_paths = MechanicAssetScan.maptile_set_image_paths(String(_values["maptile_set"]))
		_build_ui()
	_select_tex(0)

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
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.size = Vector2(minf(PANEL_W, vp_size.x - SCREEN_MARGIN * 2.0), vp_size.y - SCREEN_MARGIN * 2.0)
	_panel.position = ((vp_size - _panel.size) * 0.5).round()   # centered on screen — see header
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.08, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.70, 0.80)   # energy-cyan border — distinct from the other 3 Mechanic panels
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "♨ VENT MARK"
	_font(title, 15, Color(0.75, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Drag to move"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input)
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Click = mark vent  ·  Right-click near a mark = remove it"
	_font(hint, 10, Color(0.6, 0.6, 0.65))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)
	outer.add_child(HSeparator.new())

	var tex_row := HBoxContainer.new()
	tex_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tex_row.add_theme_constant_override("separation", 8)
	outer.add_child(tex_row)
	var labels := ["A", "B", "C", "D", "E", "F", "G"]
	for i in _tex_paths.size():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
		btn.expand_icon = true
		btn.icon = _make_thumb(_tex_paths[i])
		btn.tooltip_text = "Photo %s" % (labels[i] if i < labels.size() else str(i))
		btn.pressed.connect(_select_tex.bind(i))
		tex_row.add_child(btn)
		_tex_buttons.append(btn)

	# The image area scrolls (both axes, auto) instead of the panel overflowing the screen — see header.
	var image_scroll := ScrollContainer.new()
	image_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	image_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	image_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(image_scroll)

	# Square display at IMAGE_SIZE — source photos are themselves square (2048x2048), so uniform STRETCH_SCALE
	# here never distorts aspect ratio, just downsizes.
	var image_holder := Control.new()
	image_holder.custom_minimum_size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
	image_holder.size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
	image_scroll.add_child(image_holder)

	_image_rect = TextureRect.new()
	_image_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# EXPAND_IGNORE_SIZE is the actual fix for the "image overflows the screen" bug — see
	# volcanic_crater_mark.gd's header for the full explanation of this exact Godot TextureRect gotcha.
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_image_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_image_rect.gui_input.connect(_on_image_input)
	image_holder.add_child(_image_rect)

	_marker_layer = Control.new()
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_holder.add_child(_marker_layer)

	_count_lbl = Label.new()
	_font(_count_lbl, 12, Color(0.8, 0.85, 0.9))
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_count_lbl)

	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 10)
	edit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(edit_row)
	var undo_btn := Button.new()
	undo_btn.text = "UNDO LAST"
	_font_btn(undo_btn, 13)
	undo_btn.pressed.connect(_on_undo)
	edit_row.add_child(undo_btn)
	var clear_btn := Button.new()
	clear_btn.text = "CLEAR ALL"
	_font_btn(clear_btn, 13)
	clear_btn.pressed.connect(_on_clear_all)
	edit_row.add_child(clear_btn)

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
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	_font_btn(close_btn, 14)
	close_btn.pressed.connect(toggle)
	btn_row.add_child(close_btn)

	_status = Label.new()
	_font(_status, 12, Color(0.5, 0.9, 0.5))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_status)

## CPU-resized thumbnail for a maptile photo's Button icon — see volcanic_crater_mark.gd's own _make_thumb
## for why (minifying the raw 2048px source directly reads as noisy static at THUMB_SIZE).
func _make_thumb(path: String) -> ImageTexture:
	var img: Image = (load(path) as Texture2D).get_image()
	img.resize(int(THUMB_SIZE), int(THUMB_SIZE), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)

func _select_tex(idx: int) -> void:
	if idx < 0 or idx >= _tex_paths.size():
		return
	_selected_tex = idx
	_image_rect.texture = load(_tex_paths[idx]) as Texture2D
	for i in _tex_buttons.size():
		(_tex_buttons[i] as Button).set_pressed_no_signal(i == idx)
	_refresh_markers()

func _on_image_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb := event as InputEventMouseButton
	var uv: Vector2 = (mb.position / Vector2(IMAGE_SIZE, IMAGE_SIZE)).clamp(Vector2.ZERO, Vector2.ONE)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_add_mark(uv)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_remove_nearest_mark(uv)
	get_viewport().set_input_as_handled()

func _add_mark(uv: Vector2) -> void:
	var marks: Array = _values["beam_marks"]
	marks.append({"tex": _selected_tex, "u": uv.x, "v": uv.y})
	_refresh_markers()
	_commit()

func _remove_nearest_mark(uv: Vector2) -> void:
	var marks: Array = _values["beam_marks"]
	var best_i := -1
	var best_d := INF
	for i in marks.size():
		var m: Dictionary = marks[i]
		if int(m.get("tex", 0)) != _selected_tex:
			continue
		var d: float = Vector2(float(m["u"]), float(m["v"])).distance_to(uv)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i >= 0 and best_d < REMOVE_CLICK_RADIUS:
		marks.remove_at(best_i)
		_refresh_markers()
		_commit()

func _on_undo() -> void:
	var marks: Array = _values["beam_marks"]
	if marks.is_empty():
		return
	marks.pop_back()
	_refresh_markers()
	_commit()

func _on_clear_all() -> void:
	_values["beam_marks"] = []
	_refresh_markers()
	_commit()

func _refresh_markers() -> void:
	if _marker_layer == null:
		return
	for c: Node in _marker_layer.get_children():
		c.queue_free()
	var marks: Array = _values.get("beam_marks", [])
	var count_here := 0
	for m: Dictionary in marks:
		if int(m.get("tex", 0)) != _selected_tex:
			continue
		count_here += 1
		var dot := _make_dot()
		dot.position = Vector2(float(m["u"]), float(m["v"])) * IMAGE_SIZE - Vector2(MARK_DOT_SIZE, MARK_DOT_SIZE) * 0.5
		_marker_layer.add_child(dot)
	if _count_lbl != null:
		_count_lbl.text = "Beam: %d mark(s) on this photo · %d total" % [count_here, marks.size()]

func _make_dot() -> Control:
	var p := Panel.new()
	p.size = Vector2(MARK_DOT_SIZE, MARK_DOT_SIZE)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = DOT_COLOR
	sb.set_corner_radius_all(int(MARK_DOT_SIZE))
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _push_live() -> void:
	var plumes := get_tree().get_first_node_in_group("mechanic_plumes")
	if plumes != null and plumes.has_method("apply_vent_marks"):
		plumes.call("apply_vent_marks", _values["beam_marks"])

## Marking a vent is a discrete, deliberate click — unlike a slider you might be mid-drag-experimenting with,
## there's no reason to also require a separate SAVE click before it survives a restart. Every add/remove/
## undo/clear both applies live AND writes to disk immediately (mirrors volcanic_crater_mark.gd's own
## 2026-08-08 fix — see that file's header for the full bug rationale: marks silently vanishing on next launch
## because nothing had called save_settings() yet).
##
## Saves ONLY the "beam_marks" key, re-read against whatever's CURRENTLY on disk rather than this panel's own
## `_values` snapshot (taken once, back when the panel first opened) — otherwise every mark click would also
## re-write every OTHER setting to its possibly-stale open-time value, silently clobbering an unsaved live edit
## made meanwhile in Terrain/Light/Plume Edit.
func _commit() -> void:
	_push_live()
	_save_marks_only()
	if _status != null:
		_status.text = "Saved."

func _save_marks_only() -> void:
	var fresh := MechanicTerrainSettings.load_settings()
	fresh["beam_marks"] = _values["beam_marks"]
	MechanicTerrainSettings.save_settings(fresh)

func _on_save() -> void:
	_save_marks_only()
	if _status != null:
		_status.text = "Saved."

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
