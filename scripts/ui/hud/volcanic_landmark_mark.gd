extends CanvasLayer
class_name VolcanicLandmarkMark
## Dev-mode-only Volcanic LANDMARK plume marking tool — group "volcanic_landmark_mark", toggled from
## arena_hud_buttons.gd's LANDMARK MARK button (Volcanic map only). User feedback: "Landmark cũng có cơ chế
## đánh dấu điểm plume flame và smoke". Shows a true top-down reference render of temple.glb
## (tools/bake_volcanic_landmark.gd's output, assets/map/volcanic/temple_mark_ref.png) so the user can click
## points ON THE MODEL ITSELF — same click-to-mark interaction as volcanic_crater_mark.gd, but the coordinate
## system is LOCAL to the model (normalized fx/fz, -0.5..0.5 each axis, within the bake's own reference frame
## — see volcanic_temple_layer.gd's header for the exact conversion math) instead of a UV tied to an
## infinitely-tiled ground photo, because a landmark is a handful of individually-placed instances (random
## position AND yaw), not a repeating texture — volcanic_temple_layer.gd re-derives each instance's actual
## world attach points from these same local marks every time it (re)spawns or this panel edits live.
##
## TWO TABS — "SMOKE" / "FLAME" (same split as volcanic_crater_mark.gd) — independent mark lists
## (`landmark_marks_smoke`/`landmark_marks_flame`), only the active tab's dots show.
##
## Left-click = add a mark for the active tab. Right-click near an existing mark (active tab) = remove it.
## Applies LIVE by calling volcanic_temple_layer.gd's refresh_landmark_marks() (which re-registers plumes on
## every CURRENTLY SPAWNED landmark instance — a mark added here does nothing until at least one landmark
## exists, same as every other Volcanic mark tool needing its target system already running). SAVE persists
## to res://volcanic_terrain.cfg via VolcanicTerrainSettings — every add/remove auto-saves immediately (same
## fix as volcanic_crater_mark.gd's own "marks vanished without pressing Save" bug), scoped to ONLY the
## landmark_marks_* keys so it never clobbers other panels' unsaved edits.

const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")

const REF_IMAGE_PATH := "res://assets/map/volcanic/landmark/temple_mark_ref.png"
const PANEL_W := 900.0
const IMAGE_SIZE := 860.0
const MARK_DOT_SIZE := 12.0
const REMOVE_CLICK_RADIUS := 0.05   # normalized frame-fraction distance — right-click must land within this
                                     # of a mark to remove it (same scale as volcanic_crater_mark.gd's UV space)
const SCREEN_MARGIN := 20.0
const KINDS := ["smoke", "flame"]
const DOT_COLOR := {"smoke": Color(1.0, 0.2, 0.15, 0.9), "flame": Color(1.0, 0.65, 0.05, 0.9)}

var _is_open: bool = false
var _panel: Panel = null
var _drag_panel: Panel = null
var _drag_off: Vector2 = Vector2.ZERO

var _values: Dictionary = {}   # full settings dict — we mutate _values["landmark_marks_smoke"/"_flame"]
var _image_rect: TextureRect = null
var _marker_layer: Control = null
var _kind: String = "smoke"
var _tab_btns: Dictionary = {}
var _count_lbl: Label = null
var _status: Label = null
var _missing_lbl: Label = null

func _ready() -> void:
	layer = 61   # same tier as the other Volcanic dev panels
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("volcanic_landmark_mark")

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's LANDMARK MARK button.
func toggle() -> void:
	_is_open = not _is_open
	if _panel != null:
		_panel.visible = _is_open
	if not _is_open:
		return
	if _panel == null:
		_values = VolcanicTerrainSettings.load_settings()
		_build_ui()
	_select_kind("smoke")

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
	_panel.position = ((vp_size - _panel.size) * 0.5).round()   # centered on screen — same reasoning as
	                                                              # volcanic_crater_mark.gd's header
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.SURFACE
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.55, 0.35, 0.75)   # violet border — distinct from the other 4 Volcanic panels
	sb.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "⛩ LANDMARK MARK"
	_font(title, 15, Color(0.9, 0.8, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Drag to move"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input)
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Click = mark plume point on the temple  ·  Right-click near a mark = remove it"
	_font(hint, 10, Color(0.6, 0.6, 0.65))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)

	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 6)
	outer.add_child(tab_row)
	for kind: String in KINDS:
		var tab_btn := Button.new()
		tab_btn.text = kind.to_upper()
		tab_btn.toggle_mode = true
		_font_btn(tab_btn, 13)
		tab_btn.custom_minimum_size = Vector2(100, 28)
		tab_btn.pressed.connect(_select_kind.bind(kind))
		tab_row.add_child(tab_btn)
		_tab_btns[kind] = tab_btn
	outer.add_child(HSeparator.new())

	if not ResourceLoader.exists(REF_IMAGE_PATH):
		_missing_lbl = Label.new()
		_missing_lbl.text = "No reference image yet.\nRun: godot --path . --script tools/bake_volcanic_landmark.gd"
		_font(_missing_lbl, 13, Color(1.0, 0.6, 0.5))
		_missing_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_missing_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		outer.add_child(_missing_lbl)
	else:
		var image_scroll := ScrollContainer.new()
		image_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		image_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		image_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(image_scroll)

		var image_holder := Control.new()
		image_holder.custom_minimum_size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
		image_holder.size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
		image_scroll.add_child(image_holder)

		_image_rect = TextureRect.new()
		_image_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		# EXPAND_IGNORE_SIZE required for stretch_mode=STRETCH_SCALE to actually shrink the texture instead of
		# forcing the card to grow to native resolution — see volcanic_crater_mark.gd's header for the full
		# explanation of this exact Godot TextureRect gotcha.
		_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_image_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_image_rect.texture = load(REF_IMAGE_PATH) as Texture2D
		_image_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_image_rect.gui_input.connect(_on_image_input)
		image_holder.add_child(_image_rect)

		var checker := ColorRect.new()
		checker.set_anchors_preset(Control.PRESET_FULL_RECT)
		checker.color = Color(0.2, 0.2, 0.22)
		checker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		checker.z_index = -1
		image_holder.add_child(checker)   # flat backdrop so a transparent bake still reads clearly

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

func _select_kind(kind: String) -> void:
	_kind = kind
	for k: String in KINDS:
		var btn: Button = _tab_btns.get(k)
		if btn != null:
			btn.set_pressed_no_signal(k == kind)
	_refresh_markers()

func _marks_key() -> String:
	return "landmark_marks_%s" % _kind

func _on_image_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb := event as InputEventMouseButton
	var uv: Vector2 = (mb.position / Vector2(IMAGE_SIZE, IMAGE_SIZE)).clamp(Vector2.ZERO, Vector2.ONE)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_add_mark(uv - Vector2(0.5, 0.5))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_remove_nearest_mark(uv - Vector2(0.5, 0.5))
	get_viewport().set_input_as_handled()

func _add_mark(f: Vector2) -> void:
	var marks: Array = _values[_marks_key()]
	marks.append({"fx": f.x, "fz": f.y})
	_refresh_markers()
	_commit()

func _remove_nearest_mark(f: Vector2) -> void:
	var marks: Array = _values[_marks_key()]
	var best_i := -1
	var best_d := INF
	for i in marks.size():
		var m: Dictionary = marks[i]
		var d: float = Vector2(float(m.get("fx", 0.0)), float(m.get("fz", 0.0))).distance_to(f)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i >= 0 and best_d < REMOVE_CLICK_RADIUS:
		marks.remove_at(best_i)
		_refresh_markers()
		_commit()

func _on_undo() -> void:
	var marks: Array = _values[_marks_key()]
	if marks.is_empty():
		return
	marks.pop_back()
	_refresh_markers()
	_commit()

func _on_clear_all() -> void:
	_values[_marks_key()] = []
	_refresh_markers()
	_commit()

func _refresh_markers() -> void:
	if _marker_layer == null:
		if _count_lbl != null:
			_count_lbl.text = ""
		return
	for c: Node in _marker_layer.get_children():
		c.queue_free()
	var marks: Array = _values.get(_marks_key(), [])
	for m: Dictionary in marks:
		var f := Vector2(float(m.get("fx", 0.0)), float(m.get("fz", 0.0)))
		var dot := _make_dot()
		dot.position = (f + Vector2(0.5, 0.5)) * IMAGE_SIZE - Vector2(MARK_DOT_SIZE, MARK_DOT_SIZE) * 0.5
		_marker_layer.add_child(dot)
	if _count_lbl != null:
		_count_lbl.text = "%s: %d mark(s)" % [_kind.capitalize(), marks.size()]

func _make_dot() -> Control:
	var p := Panel.new()
	p.size = Vector2(MARK_DOT_SIZE, MARK_DOT_SIZE)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = DOT_COLOR.get(_kind, Color(1.0, 0.2, 0.15, 0.9))
	sb.set_corner_radius_all(int(MARK_DOT_SIZE))
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _push_live() -> void:
	var layer := get_tree().get_first_node_in_group("volcanic_temple_layer")
	if layer != null and layer.has_method("refresh_landmark_marks"):
		layer.call("refresh_landmark_marks")

## Marking is a discrete, deliberate click — same reasoning/fix as volcanic_crater_mark.gd's _commit(): every
## add/remove both applies live AND writes to disk immediately, scoped to ONLY the landmark_marks_* keys (re-
## read fresh from disk first) so it can't clobber another panel's unsaved edit.
func _commit() -> void:
	_push_live()
	_save_marks_only()
	if _status != null:
		_status.text = "Saved."

func _save_marks_only() -> void:
	var fresh := VolcanicTerrainSettings.load_settings()
	for kind: String in KINDS:
		var key := "landmark_marks_%s" % kind
		fresh[key] = _values[key]
	VolcanicTerrainSettings.save_settings(fresh)

func _on_save() -> void:
	_save_marks_only()
	if _status != null:
		_status.text = "Saved."

func _font(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	btn.add_theme_font_size_override("font_size", size)
