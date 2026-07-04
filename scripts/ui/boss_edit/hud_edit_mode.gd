extends CanvasLayer
## BOARD Edit Mode — a generic editor that authors a "board" (HUD, Level Up, …) as ordered GROUPS of
## items (sprites) and text layers. One editor, many boards: the "Board:" dropdown swaps which layout is
## being authored. Board-specific RUNTIME behaviour lives in a per-board BoardBinder (e.g. hud_binder.gd);
## this file stays board-agnostic. See scripts/ui/boards/ (board_defs.gd registry).
##
## Model (≠ creep edit's one-EO-per-file):
##   • GROUPS panel (left): an ordered list of named groups. Top of the list = highest Z band.
##     "+" makes a new group. RMB a group → Copy / Rename / Delete / Add Text.
##     Drag groups up/down to reorder (Z). Drag a palette ITEM onto a group to add it.
##   • Each group holds an ordered list of CHILDREN — items or text layers (drag to reorder within/between).
##     RMB a child → Copy / Delete. An ITEM may appear any number of times (independent instances).
##   • ITEMS palette (right): sprite files in the active board's asset folder — drag sources.
##   • Selecting a TEXT child shows a style panel: text / font (assets/fonts) / size / color / outline / align.
##   • Items and text are dragged on-screen with the mouse; placed nodes ARE the live in-game surface.
##
## Each board saves to config/boards/<board>.cfg (HUD falls back to res://playerhud_layout.cfg until
## migrated). Opened via the Devon-panel HUD_edit button (group "hud_edit"); the arena instance's home
## board is the HUD.

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const BoardDefs      := preload("res://scripts/ui/boards/board_defs.gd")

const FONTS_FOLDER := "res://assets/fonts/"
const LEFT_W       := 248.0
const RIGHT_W      := 264.0
const Z_TOP        := 240    # highest child z; descends down the list
const BLEND_NAMES  := ["Normal", "Screen", "Hard light", "Overlay", "Color Dodge (add)", "Multiply"]
const ZOOM_MIN     := 0.4
const ZOOM_MAX     := 5.0
const ZOOM_RATIO   := 1.15
# grow_dir option order in the GROW dropdown → shader uniform int (0=L→R,1=R→L,2=B→T,3=T→B).
# (Only enabled when the active board's binder marks the selected item as a "bar band" — see BoardBinder.)
const GROW_NAMES := ["→  Left → Right", "←  Right → Left", "↑  Bottom → Top", "↓  Top → Bottom"]

# ── Data ─────────────────────────────────────────────────────────────────────────
# _groups[i] = {"name": String, "children": Array[Dictionary]}   (i=0 → top → highest z)
# child      = {"id": int, "type": "item"|"text", ...}
#   item: "file","pos":Vector2,"size":Vector2,"blend":int
#   text: "text","font","font_size","color":Color,"outline_color":Color,"outline_size":int,"align":int,"pos":Vector2
var _groups: Array = []
var _nodes: Dictionary = {}          # child id -> live node (EditableObjectNode or _HudText)
var _next_id: int = 1
var _sel_id: int = -1                 # selected child id (-1 = none)
var _sel_group: int = -1              # selected group index (-1 = none; mutually exclusive with _sel_id)
var _dirty: bool = false
var _is_open: bool = false
var _prev_paused: bool = false
var _font_names: Array[String] = []   # font file basenames in assets/fonts
var _item_files: Array[String] = []   # sprite basenames in Playerhud

var _objects_container: Control = null

# Context-menu target
var _ctx_kind: String = ""            # "group" | "child"
var _ctx_gi: int = -1
var _ctx_id: int = -1

var _updating_ui: bool = false
var _zoom: float = 1.0
var _drag_panel: Panel = null         # panel currently being dragged by its title bar
var _drag_off: Vector2 = Vector2.ZERO

# ── Board (which layout / palette / binder this surface authors + shows) ─────────────
# The editor is board-agnostic: HUD-specific runtime lives in the board's BoardBinder (e.g. hud_binder.gd).
var _board_id: String = "hud"
var _home_board: String = "hud"       # board restored to the live surface when the editor closes
var _editable: bool = true            # false = runtime-only host (no authoring UI, not in the "hud_edit" group)
var _asset_dir: String = "res://assets/hud/Playerhud/"   # palette folder for the active board
var _layout_load: String = ""         # resolved path to load from (primary, or legacy fallback)
var _layout_save: String = ""         # path to save to (always the primary location)
var _binder: BoardBinder = null       # drives the placed nodes from game state while not editing

# ── UI nodes ──────────────────────────────────────────────────────────────────────
var _dim:           ColorRect     = null
var _toast:         Label         = null
var _left_panel:    Panel         = null
var _right_panel:   Panel         = null
var _groups_vbox:   VBoxContainer = null
var _palette_grid:  GridContainer = null
var _board_opt:     OptionButton  = null   # board selector (HUD / Level Up / …)
var _ctx_menu:      PopupMenu     = null
# transform / props
var _x_spin:  SpinBox = null
var _y_spin:  SpinBox = null
var _w_spin:  SpinBox = null
var _h_spin:  SpinBox = null
var _blend_opt: OptionButton = null
var _grow_row: HBoxContainer = null    # GROW direction (bar bands only)
var _grow_opt: OptionButton = null
var _delete_btn: Button = null
var _zoom_slider: HSlider = null
var _zoom_pct_lbl: Label = null
var _opacity_slider: HSlider = null
var _opacity_pct_lbl: Label = null
# text style
var _text_section: VBoxContainer = null
var _txt_edit:   LineEdit     = null
var _font_opt:   OptionButton = null
var _txt_size:   SpinBox      = null
var _txt_color:  ColorPickerButton = null
var _out_color:  ColorPickerButton = null
var _out_size:   SpinBox      = null
var _align_opt:  OptionButton = null

# ── Lifecycle ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan_fonts()
	_scan_items()
	_build_ui()
	_set_ui_visible(false)

## Build the live surface for `board_id`. `editable`=true → the authoring editor (registers in "hud_edit"
## for the dev button; the board dropdown can author any board, restoring this one on close). `editable`
## =false → a runtime-only host that just shows one board (used e.g. for the Level-Up overlay).
func setup(objects_container: Control, board_id: String = "hud", editable: bool = true) -> void:
	_objects_container = objects_container
	# The editor pauses the tree; ALWAYS lets the placed nodes still process + receive input while editing.
	_objects_container.process_mode = Node.PROCESS_MODE_ALWAYS
	_editable = editable
	_home_board = board_id
	if editable:
		add_to_group("hud_edit")
	_apply_board(board_id)
	_load_layout()
	_rebuild_nodes()
	_reassign_z()
	_set_gameplay(true)   # show as the live surface until the editor is opened
	if _binder != null:
		_binder.build()   # wire the placed nodes to game state (macros, slots, bars, sentinels…)

## Point the surface at a board: swap the palette folder, layout paths and runtime binder. Does NOT
## load/rebuild the nodes — callers pair this with _load_layout()+_rebuild_nodes() (see _load_board_into_container).
func _apply_board(id: String) -> void:
	if not BoardDefs.has(id):
		id = "hud"
	_board_id = id
	_asset_dir = BoardDefs.assets_dir(id)
	_layout_load = BoardDefs.layout_load_path(id)
	_layout_save = BoardDefs.layout_save_path(id)
	_scan_items()
	if _palette_grid != null:
		_build_palette()
	if _binder != null and is_instance_valid(_binder):
		_binder.queue_free()
	_binder = BoardDefs.make_binder(id)
	add_child(_binder)
	_binder.setup(self)
	_sync_board_opt()

## _apply_board + reload the authored data + rebuild the canvas nodes for `id`.
func _load_board_into_container(id: String) -> void:
	_apply_board(id)
	_load_layout()
	_rebuild_nodes()
	_reassign_z()

## Dropdown: author a different board. Saves the current one if dirty, then swaps in the new board's data
## (editor stays open; the live surface for the home board is restored on close).
func _switch_board(id: String) -> void:
	if id == _board_id or not _is_open:
		return
	if _dirty:
		_save_layout()
	_select(-1)
	if _binder != null:
		_binder.clear()
	_load_board_into_container(id)
	_set_gameplay(false)   # editing the newly-loaded board
	_rebuild_groups_panel()

func _on_board_opt_selected(idx: int) -> void:
	if idx >= 0 and idx < BoardDefs.ORDER.size():
		_switch_board(String(BoardDefs.ORDER[idx]))

func _sync_board_opt() -> void:
	if _board_opt == null:
		return
	var i := BoardDefs.ORDER.find(_board_id)
	if i >= 0:
		_board_opt.select(i)

func is_open() -> bool:
	return _is_open

## The active board's runtime binder (e.g. HudBinder / LevelUpBinder). Used by callers that read board
## roles (e.g. arena_levelup_ui asks a LevelUpBinder for its slot/title rects).
func get_binder() -> BoardBinder:
	return _binder

## Re-read the current board's layout from disk + rebuild the surface. For a runtime-only host, picks up
## edits saved by the authoring editor (a separate instance writing the same cfg). No-op while an editor
## is open on this instance.
func reload() -> void:
	if _is_open:
		return
	if _binder != null:
		_binder.clear()
	_load_board_into_container(_board_id)
	_set_gameplay(true)
	if _binder != null:
		_binder.build()

## Change which board this surface shows as the live HUD when the editor is closed (e.g. the player
## picked a different HUD version in Settings). While the editor is open on some other board, just
## remember the new home — `_close()` will load it. Otherwise swap the live surface immediately.
func set_home_board(id: String) -> void:
	if not BoardDefs.has(id) or id == _home_board:
		return
	_home_board = id
	if _is_open:
		return   # _close() restores _home_board when the editor exits
	if _binder != null:
		_binder.clear()
	_load_board_into_container(id)
	_set_gameplay(true)
	if _binder != null:
		_binder.build()

func toggle() -> void:
	if _is_open:
		_request_close()
	else:
		_open()

func _open() -> void:
	if not _editable:
		return   # runtime-only host has no authoring UI
	_is_open = true
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_arena_focus(true)
	_reset_zoom()
	if _binder != null:
		_binder.clear()   # dismantle runtime extras/macros → members return to design positions for editing
	_set_ui_visible(true)
	_set_gameplay(false)
	_select(-1)
	_sync_board_opt()
	_rebuild_groups_panel()

func _request_close() -> void:
	if _dirty:
		_save_layout()
	_close()

func _close() -> void:
	_is_open = false
	_drag_panel = null
	_reset_zoom()
	# If we were authoring a different board, restore the editor's own board as the live surface.
	if _board_id != _home_board:
		if _binder != null:
			_binder.clear()
		_load_board_into_container(_home_board)
	_set_ui_visible(false)
	_select(-1)
	_set_gameplay(true)
	_arena_focus(false)
	get_tree().paused = _prev_paused
	if _binder != null:
		_binder.build()   # re-resolve node refs (editing may have rebuilt them) + rebuild runtime extras

## Hide the arena HUD + gameplay (live HUD, buttons, player, enemies) while the editor is open so only
## the editor panels + the placed HUD nodes show — also removes Controls that would eat canvas drags.
## Title-bar drag: begin moving `panel` when its title is pressed (motion/release handled in _input).
func _on_panel_drag_input(event: InputEvent, panel: Panel) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		_drag_panel = panel
		_drag_off = panel.global_position - get_viewport().get_mouse_position()

func _arena_focus(on: bool) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("set_edit_focus"):
		arena.set_edit_focus(on)

# ── Zoom (scales the objects container; reset on open/close) ─────────────────────────

func _reset_zoom() -> void:
	_zoom = 1.0
	if _objects_container != null and is_instance_valid(_objects_container):
		_objects_container.position = Vector2.ZERO
		_objects_container.scale = Vector2.ONE
	_sync_zoom_slider()

func _apply_zoom(mouse_vp: Vector2) -> void:
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var old_offset := _objects_container.position
	var old_zoom := _objects_container.scale.x
	_objects_container.position = mouse_vp + (old_offset - mouse_vp) * (_zoom / old_zoom)
	_objects_container.scale = Vector2(_zoom, _zoom)
	_sync_zoom_slider()

func _sync_zoom_slider() -> void:
	if _zoom_slider == null:
		return
	_updating_ui = true
	_zoom_slider.value = clampf(_zoom * 100.0, _zoom_slider.min_value, _zoom_slider.max_value)
	if _zoom_pct_lbl != null:
		_zoom_pct_lbl.text = "%d%%" % int(round(_zoom * 100.0))
	_updating_ui = false

func _on_zoom_slider_changed(value: float) -> void:
	if _updating_ui:
		return
	_zoom = value / 100.0
	_apply_zoom(get_viewport().get_visible_rect().size * 0.5)

# ── Folder scans ───────────────────────────────────────────────────────────────────

func _scan_fonts() -> void:
	_font_names.clear()
	var dir := DirAccess.open(FONTS_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var e := dir.get_next()
	while e != "":
		if not dir.current_is_dir() and e.get_extension().to_lower() in ["ttf", "otf", "fnt"]:
			_font_names.append(e.get_basename())
		e = dir.get_next()
	dir.list_dir_end()
	_font_names.sort()

func _scan_items() -> void:
	_item_files.clear()
	var dir := DirAccess.open(_asset_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var e := dir.get_next()
	while e != "":
		if not dir.current_is_dir() and e.get_extension().to_lower() in ["png", "jpg", "jpeg", "gif"]:
			_item_files.append(e.get_basename())
		e = dir.get_next()
	dir.list_dir_end()
	_item_files.sort()

func _font_path(fname: String) -> String:
	for ext: String in ["ttf", "otf", "fnt"]:
		var p := FONTS_FOLDER + fname + "." + ext
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""

func _load_font(fname: String) -> Font:
	var p := _font_path(fname)
	if p == "":
		return null
	return load(p) as Font

func _item_path(file: String) -> String:
	for ext: String in ["png", "gif", "jpg", "jpeg"]:
		var p := _asset_dir + file + "." + ext
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""

func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if path.get_extension().to_lower() == "gif":
		return GifLoader.load_gif(path)
	var t := load(path) as Texture2D
	if t != null:
		return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

# ── UI construction ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.30)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_toast = Label.new()
	_toast.z_index = 200
	_toast.modulate.a = 0.0
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.position = Vector2(420.0, 14.0)
	add_child(_toast)

	_build_left_panel()
	_build_right_panel()

	_ctx_menu = PopupMenu.new()
	_ctx_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_ctx_menu.id_pressed.connect(_on_ctx_id)
	add_child(_ctx_menu)

func _build_left_panel() -> void:
	_left_panel = Panel.new()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_left_panel.position = Vector2(20.0, 44.0)
	_left_panel.size = Vector2(LEFT_W, minf(820.0, vp_h - 56.0))
	add_child(_left_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 6; outer.offset_top = 6; outer.offset_right = -6; outer.offset_bottom = -6
	outer.add_theme_constant_override("separation", 5)
	_left_panel.add_child(outer)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	outer.add_child(hdr)
	var title := Label.new()
	title.text = "≡ GROUPS"
	title.tooltip_text = "Drag to move panel"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.60, 0.63, 0.76)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input.bind(_left_panel))
	hdr.add_child(title)
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "New group"
	add_btn.custom_minimum_size = Vector2(28.0, 0.0)
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.pressed.connect(_add_group)
	hdr.add_child(add_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_groups_vbox = VBoxContainer.new()
	_groups_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_groups_vbox)

func _build_right_panel() -> void:
	_right_panel = Panel.new()
	var vp := get_viewport().get_visible_rect().size
	_right_panel.position = Vector2(vp.x - RIGHT_W - 20.0, 44.0)
	_right_panel.size = Vector2(RIGHT_W, minf(860.0, vp.y - 56.0))
	add_child(_right_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 6; outer.offset_top = 6; outer.offset_right = -6; outer.offset_bottom = -6
	outer.add_theme_constant_override("separation", 5)
	_right_panel.add_child(outer)

	# Title bar = drag handle (stays pinned above the scrollable content).
	var title := Label.new()
	title.text = "≡ HUD EDIT"
	title.tooltip_text = "Drag to move panel"
	title.add_theme_font_size_override("font_size", 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_panel_drag_input.bind(_right_panel))
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 5)
	scroll.add_child(root)

	# Board selector — which board (HUD / Level Up / …) this editor is authoring.
	var board_row := HBoxContainer.new()
	board_row.add_theme_constant_override("separation", 3)
	root.add_child(board_row)
	var board_lbl := Label.new()
	board_lbl.text = "Board:"
	board_lbl.add_theme_font_size_override("font_size", 10)
	board_lbl.custom_minimum_size = Vector2(40.0, 0.0)
	board_row.add_child(board_lbl)
	_board_opt = OptionButton.new()
	for i: int in BoardDefs.ORDER.size():
		var bid: String = BoardDefs.ORDER[i]
		_board_opt.add_item(BoardDefs.display_name(bid), i)
	_board_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_opt.item_selected.connect(_on_board_opt_selected)
	board_row.add_child(_board_opt)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 3)
	root.add_child(btn_row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_font_size_override("font_size", 11)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_layout)
	btn_row.add_child(save_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.add_theme_font_size_override("font_size", 11)
	_delete_btn.disabled = true
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.pressed.connect(_delete_selected)
	btn_row.add_child(_delete_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(_request_close)
	btn_row.add_child(close_btn)
	# Reload: re-scan the active board's asset folder → add any NEW sprites to the ITEMS palette.
	var reload_btn := Button.new()
	reload_btn.text = "Reload"
	reload_btn.tooltip_text = "Scan the board's sprite folder for new items"
	reload_btn.add_theme_font_size_override("font_size", 11)
	reload_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reload_btn.pressed.connect(_reload_items)
	btn_row.add_child(reload_btn)

	# ITEMS palette
	root.add_child(HSeparator.new())
	_add_label(root, "ITEMS", Color(0.60, 0.63, 0.76))
	var pal_scroll := ScrollContainer.new()
	pal_scroll.custom_minimum_size = Vector2(0.0, 220.0)
	pal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(pal_scroll)
	_palette_grid = GridContainer.new()
	_palette_grid.columns = 4
	_palette_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_grid.add_theme_constant_override("h_separation", 4)
	_palette_grid.add_theme_constant_override("v_separation", 4)
	pal_scroll.add_child(_palette_grid)
	_build_palette()

	# TRANSFORM
	root.add_child(HSeparator.new())
	_add_label(root, "TRANSFORM", Color(0.60, 0.63, 0.76))
	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 3)
	root.add_child(pos_row)
	_x_spin = _mk_spin(pos_row, "X", -4000.0, 4000.0, _on_transform_spin)
	_y_spin = _mk_spin(pos_row, "Y", -4000.0, 4000.0, _on_transform_spin)
	var sz_row := HBoxContainer.new()
	sz_row.add_theme_constant_override("separation", 3)
	root.add_child(sz_row)
	_w_spin = _mk_spin(sz_row, "W", 1.0, 4000.0, _on_w_spin)
	_h_spin = _mk_spin(sz_row, "H", 1.0, 4000.0, _on_h_spin)

	# Zoom (canvas) — slider + mouse wheel, like creep edit
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	root.add_child(zoom_row)
	var zoom_lbl := Label.new()
	zoom_lbl.text = "Zoom:"
	zoom_lbl.add_theme_font_size_override("font_size", 10)
	zoom_lbl.custom_minimum_size = Vector2(40.0, 0.0)
	zoom_row.add_child(zoom_lbl)
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 40.0
	_zoom_slider.max_value = 500.0
	_zoom_slider.step = 1.0
	_zoom_slider.value = 100.0
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	zoom_row.add_child(_zoom_slider)
	_zoom_pct_lbl = Label.new()
	_zoom_pct_lbl.text = "100%"
	_zoom_pct_lbl.add_theme_font_size_override("font_size", 10)
	_zoom_pct_lbl.custom_minimum_size = Vector2(38.0, 0.0)
	_zoom_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_row.add_child(_zoom_pct_lbl)

	# Opacity (selected layer; for a selected group applies to all its children)
	var op_row := HBoxContainer.new()
	op_row.add_theme_constant_override("separation", 4)
	root.add_child(op_row)
	var op_lbl := Label.new()
	op_lbl.text = "Opacity:"
	op_lbl.add_theme_font_size_override("font_size", 10)
	op_lbl.custom_minimum_size = Vector2(46.0, 0.0)
	op_row.add_child(op_lbl)
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 100.0
	_opacity_slider.step = 1.0
	_opacity_slider.value = 100.0
	_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opacity_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	op_row.add_child(_opacity_slider)
	_opacity_pct_lbl = Label.new()
	_opacity_pct_lbl.text = "100%"
	_opacity_pct_lbl.add_theme_font_size_override("font_size", 10)
	_opacity_pct_lbl.custom_minimum_size = Vector2(38.0, 0.0)
	_opacity_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	op_row.add_child(_opacity_pct_lbl)

	# BLEND (image items)
	var bl_row := HBoxContainer.new()
	bl_row.add_theme_constant_override("separation", 3)
	root.add_child(bl_row)
	var bl_lbl := Label.new()
	bl_lbl.text = "Blend:"
	bl_lbl.add_theme_font_size_override("font_size", 10)
	bl_lbl.custom_minimum_size = Vector2(40.0, 0.0)
	bl_row.add_child(bl_lbl)
	_blend_opt = OptionButton.new()
	for i: int in BLEND_NAMES.size():
		_blend_opt.add_item(BLEND_NAMES[i], i)
	_blend_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blend_opt.item_selected.connect(_on_blend_selected)
	bl_row.add_child(_blend_opt)

	# GROW direction (shown only for a bar band: HPband / shieldband / levelband)
	_grow_row = HBoxContainer.new()
	_grow_row.add_theme_constant_override("separation", 3)
	root.add_child(_grow_row)
	var gr_lbl := Label.new()
	gr_lbl.text = "Grow:"
	gr_lbl.add_theme_font_size_override("font_size", 10)
	gr_lbl.custom_minimum_size = Vector2(40.0, 0.0)
	_grow_row.add_child(gr_lbl)
	_grow_opt = OptionButton.new()
	for i: int in GROW_NAMES.size():
		_grow_opt.add_item(GROW_NAMES[i], i)
	_grow_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grow_opt.item_selected.connect(_on_grow_selected)
	_grow_row.add_child(_grow_opt)
	# Always visible (like Blend) for discoverability; enabled only when a bar band is selected.

	# TEXT style (shown only for a selected text child)
	_text_section = VBoxContainer.new()
	_text_section.add_theme_constant_override("separation", 4)
	root.add_child(_text_section)
	_text_section.add_child(HSeparator.new())
	_add_label(_text_section, "TEXT", Color(0.55, 0.90, 1.0))

	_txt_edit = LineEdit.new()
	_txt_edit.placeholder_text = "text…"
	_txt_edit.text_changed.connect(func(_t: String) -> void: _on_text_field_changed())
	_text_section.add_child(_txt_edit)

	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 3)
	_text_section.add_child(font_row)
	var fl := Label.new(); fl.text = "Font:"; fl.add_theme_font_size_override("font_size", 10); fl.custom_minimum_size = Vector2(40.0, 0.0)
	font_row.add_child(fl)
	_font_opt = OptionButton.new()
	for i: int in _font_names.size():
		_font_opt.add_item(_font_names[i], i)
	_font_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font_opt.item_selected.connect(func(_i: int) -> void: _on_text_field_changed())
	font_row.add_child(_font_opt)

	var ts_row := HBoxContainer.new()
	ts_row.add_theme_constant_override("separation", 3)
	_text_section.add_child(ts_row)
	_txt_size = _mk_spin(ts_row, "Size", 4.0, 400.0, _on_text_field_changed)
	_align_opt = OptionButton.new()
	_align_opt.add_item("Left", 0)
	_align_opt.add_item("Center", 1)
	_align_opt.add_item("Right", 2)
	_align_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_align_opt.item_selected.connect(func(_i: int) -> void: _on_text_field_changed())
	ts_row.add_child(_align_opt)

	var col_row := HBoxContainer.new()
	col_row.add_theme_constant_override("separation", 3)
	_text_section.add_child(col_row)
	_txt_color = _mk_col(col_row, "Color", Color.WHITE)
	var out_row := HBoxContainer.new()
	out_row.add_theme_constant_override("separation", 3)
	_text_section.add_child(out_row)
	_out_color = _mk_col(out_row, "Outline", Color.BLACK)
	_out_size = _mk_spin(out_row, "W", 0.0, 32.0, _on_text_field_changed)

func _add_label(parent: Control, text: String, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = col
	parent.add_child(lbl)

func _mk_spin(parent: HBoxContainer, prefix: String, mn: float, mx: float, cb: Callable) -> SpinBox:
	var lbl := Label.new()
	lbl.text = prefix + ":"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.custom_minimum_size = Vector2(_pfx_w(prefix), 0.0)
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = 1.0
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	sb.value_changed.connect(func(_v: float) -> void: cb.call())
	parent.add_child(sb)
	return sb

func _pfx_w(prefix: String) -> float:
	return 34.0 if prefix.length() > 1 else 14.0

func _mk_col(parent: HBoxContainer, label_text: String, default_col: Color) -> ColorPickerButton:
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.custom_minimum_size = Vector2(50.0, 0.0)
	parent.add_child(lbl)
	var cpb := ColorPickerButton.new()
	cpb.color = default_col
	cpb.custom_minimum_size = Vector2(0.0, 22.0)
	cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpb.color_changed.connect(func(_c: Color) -> void: _on_text_field_changed())
	parent.add_child(cpb)
	return cpb

func _build_palette() -> void:
	for c in _palette_grid.get_children():
		c.queue_free()
	for file: String in _item_files:
		var cell := _PaletteCell.new()
		cell.owner_editor = self
		cell.item_file = file
		cell.custom_minimum_size = Vector2(46.0, 46.0)
		cell.tooltip_text = file
		cell.set_icon(_load_tex(_item_path(file)))
		_palette_grid.add_child(cell)

## Reload button: re-scan the active board's asset folder and rebuild the ITEMS palette so any sprites
## added to the folder while the editor was open show up. Toasts how many new sprites were picked up.
func _reload_items() -> void:
	var old := _item_files.duplicate()
	_scan_items()
	if _palette_grid != null:
		_build_palette()
	var added := 0
	for f: String in _item_files:
		if not (f in old):
			added += 1
	show_toast("Reload: +%d sprite" % added if added > 0 else "Reload: no new sprite")

func _set_ui_visible(v: bool) -> void:
	_dim.visible = v
	_left_panel.visible = v
	_right_panel.visible = v

# ── Groups panel ───────────────────────────────────────────────────────────────────

func _rebuild_groups_panel() -> void:
	if _groups_vbox == null:
		return
	for c in _groups_vbox.get_children():
		c.queue_free()
	for gi: int in _groups.size():
		var g: Dictionary = _groups[gi]
		var collapsed: bool = bool(g.get("collapsed", false))
		var locked: bool = bool(g.get("locked", false))
		var grow := _GroupRow.new()
		grow.owner_editor = self
		grow.gi = gi
		grow.locked = locked
		grow.init_row(String(g.get("name", "Group")), collapsed, locked, gi == _sel_group)
		_groups_vbox.add_child(grow)
		if collapsed:
			continue
		var children: Array = g.get("children", [])
		for ci: int in children.size():
			var ch: Dictionary = children[ci]
			var crow := _ChildRow.new()
			crow.owner_editor = self
			crow.gi = gi
			crow.ci = ci
			crow.child_id = int(ch.get("id", -1))
			crow.locked = locked
			crow.set_selected(int(ch.get("id", -1)) == _sel_id)
			crow.set_content(_child_label(ch), _child_icon(ch))
			crow.set_visible_state(bool(ch.get("visible", true)))
			_groups_vbox.add_child(crow)

func _child_label(ch: Dictionary) -> String:
	if String(ch.get("type", "")) == "text":
		return "T: " + String(ch.get("text", ""))
	return String(ch.get("file", "?"))

func _child_icon(ch: Dictionary) -> Texture2D:
	if String(ch.get("type", "")) == "item":
		return _load_tex(_item_path(String(ch.get("file", ""))))
	return null

# ── Group operations ───────────────────────────────────────────────────────────────

func _add_group() -> void:
	_groups.append({"name": "Group %d" % (_groups.size() + 1), "children": [], "collapsed": false, "locked": false})
	_dirty = true
	_rebuild_groups_panel()

func _dup_group(g: Dictionary) -> Dictionary:
	var out := {"name": String(g.get("name", "Group")) + " copy", "children": [],
		"collapsed": bool(g.get("collapsed", false)), "locked": false}
	for ch: Dictionary in g.get("children", []):
		(out["children"] as Array).append(_dup_child(ch))
	return out

## Caret: expand / collapse a group's child rows (view only — allowed even when locked).
func _toggle_group_collapsed(gi: int) -> void:
	if gi < 0 or gi >= _groups.size():
		return
	_groups[gi]["collapsed"] = not bool(_groups[gi].get("collapsed", false))
	_rebuild_groups_panel()

## Lock: a locked group can't be selected/moved/resized and its children can't be dragged on canvas.
func _toggle_group_locked(gi: int) -> void:
	if gi < 0 or gi >= _groups.size():
		return
	var now_locked := not bool(_groups[gi].get("locked", false))
	_groups[gi]["locked"] = now_locked
	_dirty = true
	# Dropping the lock on the currently-selected group/child clears the selection.
	if now_locked:
		if _sel_group == gi:
			_sel_group = -1
		elif _sel_id != -1 and _find_child(_sel_id).x == gi:
			_select(-1)
	if _is_open:
		_set_gameplay(false)   # re-applies per-lock interactivity to the canvas nodes
	_refresh_props()
	_rebuild_groups_panel()

func _dup_child(ch: Dictionary) -> Dictionary:
	var c := ch.duplicate(true)
	c["id"] = _next_id
	_next_id += 1
	return c

## Reorder: move group at `from` to sit before group at `to`.
func move_group(from: int, to: int) -> void:
	if from == to or from < 0 or from >= _groups.size():
		return
	var g: Dictionary = _groups[from]
	_groups.remove_at(from)
	if to > from:
		to -= 1
	to = clampi(to, 0, _groups.size())
	_groups.insert(to, g)
	_dirty = true
	_reassign_z()
	_rebuild_groups_panel()

func show_group_context(gi: int, screen_pos: Vector2) -> void:
	if gi < 0 or gi >= _groups.size() or bool(_groups[gi].get("locked", false)):
		return   # locked group: no edit menu (unlock via the lock icon)
	_ctx_kind = "group"
	_ctx_gi = gi
	_ctx_menu.clear()
	_ctx_menu.add_item("Copy", 0)
	_ctx_menu.add_item("Rename", 1)
	_ctx_menu.add_item("Delete", 2)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Add Text", 3)
	_ctx_menu.reset_size()
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()

func show_child_context(gi: int, child_id: int, screen_pos: Vector2) -> void:
	if gi >= 0 and gi < _groups.size() and bool(_groups[gi].get("locked", false)):
		return   # locked group: children can't be edited
	_ctx_kind = "child"
	_ctx_gi = gi
	_ctx_id = child_id
	_ctx_menu.clear()
	_ctx_menu.add_item("Copy", 0)
	_ctx_menu.add_item("Delete", 1)
	_ctx_menu.reset_size()
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()

func _on_ctx_id(id: int) -> void:
	if _ctx_kind == "group":
		if _ctx_gi < 0 or _ctx_gi >= _groups.size():
			return
		match id:
			0:  # Copy group → insert below
				_groups.insert(_ctx_gi + 1, _dup_group(_groups[_ctx_gi]))
				_dirty = true; _rebuild_nodes(); _reassign_z(); _rebuild_groups_panel()
			1:
				_rename_group(_ctx_gi)
			2:
				_delete_group(_ctx_gi)
			3:
				_add_text_to_group(_ctx_gi)
	elif _ctx_kind == "child":
		var loc := _find_child(_ctx_id)
		if loc.x < 0:
			return
		match id:
			0:  # Copy child → insert below in same group, offset
				var src: Dictionary = (_groups[loc.x]["children"] as Array)[loc.y]
				var dup := _dup_child(src)
				dup["pos"] = (dup.get("pos", Vector2.ZERO) as Vector2) + Vector2(16.0, 16.0)
				(_groups[loc.x]["children"] as Array).insert(loc.y + 1, dup)
				_dirty = true; _rebuild_nodes(); _reassign_z(); _rebuild_groups_panel()
			1:
				_delete_child(_ctx_id)

func _rename_group(gi: int) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Group name"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	var le := LineEdit.new()
	le.text = String(_groups[gi].get("name", "Group"))
	le.custom_minimum_size = Vector2(220.0, 0.0)
	dlg.add_child(le)
	dlg.register_text_enter(le)
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		var nm := le.text.strip_edges()
		_groups[gi]["name"] = nm if nm != "" else "Group"
		_dirty = true
		_rebuild_groups_panel()
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()
	le.grab_focus()
	le.select_all()

func _delete_group(gi: int) -> void:
	if gi < 0 or gi >= _groups.size():
		return
	for ch: Dictionary in _groups[gi].get("children", []):
		_free_node(int(ch.get("id", -1)))
	_groups.remove_at(gi)
	_dirty = true
	_reassign_z()
	_rebuild_groups_panel()

func _add_text_to_group(gi: int) -> void:
	var ch := {
		"id": _next_id, "type": "text",
		"text": "Text", "font": (_font_names[0] if not _font_names.is_empty() else ""),
		"font_size": 24, "color": Color.WHITE, "outline_color": Color.BLACK,
		"outline_size": 0, "align": 0, "pos": Vector2(440.0, 320.0),
	}
	_next_id += 1
	(_groups[gi]["children"] as Array).insert(0, ch)
	_dirty = true
	_make_node(ch)
	_reassign_z()
	_rebuild_groups_panel()
	_select(int(ch["id"]))

# ── Drop handling (palette → group, reorder groups/children) ────────────────────────

## Add a palette item as a new instance to group gi (at child index ci, or top if ci<0).
func drop_item_file(file: String, gi: int, ci: int) -> void:
	if gi < 0 or gi >= _groups.size():
		return
	var ch := {
		"id": _next_id, "type": "item", "file": file,
		"pos": Vector2(440.0, 320.0), "size": _default_item_size(file), "blend": 0,
	}
	_next_id += 1
	var children: Array = _groups[gi]["children"]
	if ci < 0 or ci > children.size():
		children.insert(0, ch)
	else:
		children.insert(ci, ch)
	_dirty = true
	_make_node(ch)
	_reassign_z()
	_rebuild_groups_panel()
	_select(int(ch["id"]))

func _default_item_size(file: String) -> Vector2:
	var tex := _load_tex(_item_path(file))
	if tex != null and tex.get_width() > 0:
		var w := 80.0
		return Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
	return Vector2(80.0, 80.0)

## Move a child (identified by id) so it lands in group gi before child index ci (ci<0 = append at top).
func relocate_child(child_id: int, to_gi: int, to_ci: int) -> void:
	var loc := _find_child(child_id)
	if loc.x < 0 or to_gi < 0 or to_gi >= _groups.size():
		return
	var src: Array = _groups[loc.x]["children"]
	var ch: Dictionary = src[loc.y]
	src.remove_at(loc.y)
	var dst: Array = _groups[to_gi]["children"]
	if to_gi == loc.x and loc.y < to_ci:
		to_ci -= 1
	if to_ci < 0 or to_ci > dst.size():
		dst.insert(0, ch)
	else:
		dst.insert(to_ci, ch)
	_dirty = true
	_reassign_z()
	_rebuild_groups_panel()

# ── Selection ──────────────────────────────────────────────────────────────────────

func _select(child_id: int) -> void:
	# Can't select a child inside a locked group.
	if child_id != -1 and _is_child_locked(child_id):
		return
	# Clear old highlight
	if _sel_id != -1:
		var old = _nodes.get(_sel_id, null)
		if old != null and is_instance_valid(old):
			_set_node_selected(old, false)
	_sel_group = -1
	_sel_id = child_id
	var n = _nodes.get(child_id, null)
	if n != null and is_instance_valid(n):
		_set_node_selected(n, true)
	_delete_btn.disabled = (child_id == -1)
	_refresh_props()
	_update_row_selection()

## Select a whole group (for panel-driven move/resize). No-op on a locked group.
func _select_group(gi: int) -> void:
	if gi < 0 or gi >= _groups.size() or bool(_groups[gi].get("locked", false)):
		return
	if _sel_id != -1:
		var old = _nodes.get(_sel_id, null)
		if old != null and is_instance_valid(old):
			_set_node_selected(old, false)
	_sel_id = -1
	_sel_group = gi
	_delete_btn.disabled = false
	_refresh_props()
	_update_row_selection()

## Update only the selection highlight on existing rows — does NOT rebuild/free them, so an
## in-progress press can still start a drag (rebuilding on press killed layer drag-to-reorder).
func _update_row_selection() -> void:
	for row in _groups_vbox.get_children():
		if row is _GroupRow:
			(row as _GroupRow).set_group_selected((row as _GroupRow).gi == _sel_group)
		elif row is _ChildRow:
			(row as _ChildRow).set_selected((row as _ChildRow).child_id == _sel_id)

func _is_child_locked(child_id: int) -> bool:
	var loc := _find_child(child_id)
	if loc.x < 0:
		return false
	return bool(_groups[loc.x].get("locked", false))

func _child_visible(child_id: int) -> bool:
	var loc := _find_child(child_id)
	if loc.x < 0:
		return true
	return bool((_groups[loc.x]["children"] as Array)[loc.y].get("visible", true))

## Eye toggle: show/hide a layer (persists; the node is hidden in gameplay too).
func _toggle_child_visible(child_id: int) -> void:
	var loc := _find_child(child_id)
	if loc.x < 0:
		return
	var ch: Dictionary = (_groups[loc.x]["children"] as Array)[loc.y]
	var v: bool = not bool(ch.get("visible", true))
	ch["visible"] = v
	var n = _nodes.get(child_id, null)
	if n != null and is_instance_valid(n):
		(n as CanvasItem).visible = v
	_dirty = true
	_rebuild_groups_panel()

func _apply_opacity_to_node(n: Node, op: float) -> void:
	# Items: set the TextureRect's modulate (EO resets the ROOT modulate.a in edit mode, so use the child).
	if n is EditableObjectNode:
		var tr := (n as EditableObjectNode).texture_rect
		if tr != null:
			tr.modulate.a = op
	elif n is _HudText:
		(n as _HudText).modulate.a = op

func _set_node_selected(n: Node, on: bool) -> void:
	if n is EditableObjectNode:
		(n as EditableObjectNode).selected = on
	elif n is _HudText:
		(n as _HudText).set_selected(on)

func _selected_child() -> Dictionary:
	var loc := _find_child(_sel_id)
	if loc.x < 0:
		return {}
	return (_groups[loc.x]["children"] as Array)[loc.y]

func _refresh_props() -> void:
	_updating_ui = true
	var grp_sel: bool = _sel_group >= 0 and _sel_group < _groups.size()
	var ch := _selected_child()
	var is_text: bool = String(ch.get("type", "")) == "text"
	var is_item: bool = String(ch.get("type", "")) == "item"
	var is_band: bool = is_item and _binder != null and _binder.is_band_file(String(ch.get("file", "")))
	_text_section.visible = is_text
	_blend_opt.disabled = not is_item
	_grow_opt.disabled = not is_band
	_w_spin.editable = is_item or grp_sel
	_h_spin.editable = is_item or grp_sel
	_opacity_slider.editable = grp_sel or not ch.is_empty()
	if grp_sel:
		# Group: X/Y = bounding-box top-left, W/H = box size (drives uniform move/scale of children).
		var bb := _group_bbox(_sel_group)
		_x_spin.value = snappedf(bb.position.x, 1.0)
		_y_spin.value = snappedf(bb.position.y, 1.0)
		_w_spin.value = snappedf(bb.size.x, 1.0)
		_h_spin.value = snappedf(bb.size.y, 1.0)
		_opacity_slider.value = 100.0   # bulk-apply control; per-child values may differ
		_opacity_pct_lbl.text = "100%"
		_updating_ui = false
		return
	if not ch.is_empty():
		var op: float = float(ch.get("opacity", 1.0))
		_opacity_slider.value = snappedf(op * 100.0, 1.0)
		_opacity_pct_lbl.text = "%d%%" % int(round(op * 100.0))
		var p: Vector2 = ch.get("pos", Vector2.ZERO)
		_x_spin.value = snappedf(p.x, 1.0)
		_y_spin.value = snappedf(p.y, 1.0)
		if is_item:
			var s: Vector2 = ch.get("size", Vector2(80.0, 80.0))
			_w_spin.value = snappedf(s.x, 1.0)
			_h_spin.value = snappedf(s.y, 1.0)
			_blend_opt.select(int(ch.get("blend", 0)))
			if is_band:
				_grow_opt.select(int(ch.get("grow", 0)))
		if is_text:
			_txt_edit.text = String(ch.get("text", ""))
			var fi := _font_names.find(String(ch.get("font", "")))
			if fi >= 0:
				_font_opt.select(fi)
			_txt_size.value = int(ch.get("font_size", 24))
			_align_opt.select(int(ch.get("align", 0)))
			_txt_color.color = ch.get("color", Color.WHITE)
			_out_color.color = ch.get("outline_color", Color.BLACK)
			_out_size.value = int(ch.get("outline_size", 0))
	_updating_ui = false

# ── Property edits ───────────────────────────────────────────────────────────────────

func _on_transform_spin() -> void:
	if _updating_ui:
		return
	if _sel_group != -1:
		_move_group_to(_sel_group, Vector2(_x_spin.value, _y_spin.value))
		return
	var ch := _selected_child()
	if ch.is_empty():
		return
	ch["pos"] = Vector2(_x_spin.value, _y_spin.value)
	var n = _nodes.get(_sel_id, null)
	if n != null and is_instance_valid(n):
		(n as Control).position = ch["pos"]
	_dirty = true

func _on_w_spin() -> void:
	if _updating_ui:
		return
	if _sel_group != -1:
		_scale_group_by_w(_sel_group, _w_spin.value)
		return
	var eo = _nodes.get(_sel_id, null)
	if eo is EditableObjectNode and (eo as EditableObjectNode)._aspect_ratio > 0.0:
		_updating_ui = true
		_h_spin.value = snappedf(_w_spin.value / (eo as EditableObjectNode)._aspect_ratio, 1.0)
		_updating_ui = false
	_apply_size_to_selected()

func _on_h_spin() -> void:
	if _updating_ui:
		return
	if _sel_group != -1:
		_scale_group_by_h(_sel_group, _h_spin.value)
		return
	var eo = _nodes.get(_sel_id, null)
	if eo is EditableObjectNode and (eo as EditableObjectNode)._aspect_ratio > 0.0:
		_updating_ui = true
		_w_spin.value = snappedf(_h_spin.value * (eo as EditableObjectNode)._aspect_ratio, 1.0)
		_updating_ui = false
	_apply_size_to_selected()

# ── Group move / uniform resize (via X/Y/W/H) ────────────────────────────────────────

## Bounding box of all children in group gi (from live nodes; falls back to stored pos/size).
func _group_bbox(gi: int) -> Rect2:
	if gi < 0 or gi >= _groups.size():
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var any := false
	for ch: Dictionary in _groups[gi].get("children", []):
		var n = _nodes.get(int(ch.get("id", -1)), null)
		var p: Vector2
		var sz: Vector2
		if n != null and is_instance_valid(n):
			p = (n as Control).position
			sz = (n as Control).size
		else:
			p = ch.get("pos", Vector2.ZERO)
			sz = ch.get("size", Vector2(20.0, 20.0))
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x + sz.x); mx.y = maxf(mx.y, p.y + sz.y)
		any = true
	if not any:
		return Rect2()
	return Rect2(mn, mx - mn)

func _move_group_to(gi: int, new_top_left: Vector2) -> void:
	var bb := _group_bbox(gi)
	var delta := new_top_left - bb.position
	if delta == Vector2.ZERO:
		return
	for ch: Dictionary in _groups[gi].get("children", []):
		ch["pos"] = (ch.get("pos", Vector2.ZERO) as Vector2) + delta
		var n = _nodes.get(int(ch.get("id", -1)), null)
		if n != null and is_instance_valid(n):
			(n as Control).position = ch["pos"]
	_dirty = true

func _scale_group_by_w(gi: int, new_w: float) -> void:
	var bb := _group_bbox(gi)
	if bb.size.x <= 0.0:
		return
	_scale_group(gi, new_w / bb.size.x, bb.position)

func _scale_group_by_h(gi: int, new_h: float) -> void:
	var bb := _group_bbox(gi)
	if bb.size.y <= 0.0:
		return
	_scale_group(gi, new_h / bb.size.y, bb.position)

## Uniformly scale every child (relative position + own size) about `anchor` by factor `s`.
func _scale_group(gi: int, s: float, anchor: Vector2) -> void:
	if s <= 0.0 or is_equal_approx(s, 1.0):
		return
	for ch: Dictionary in _groups[gi].get("children", []):
		ch["pos"] = anchor + ((ch.get("pos", Vector2.ZERO) as Vector2) - anchor) * s
		var n = _nodes.get(int(ch.get("id", -1)), null)
		if String(ch.get("type", "")) == "item":
			ch["size"] = (ch.get("size", Vector2(80.0, 80.0)) as Vector2) * s
			if n is EditableObjectNode:
				(n as EditableObjectNode).position = ch["pos"]
				(n as EditableObjectNode).size = ch["size"]
				(n as EditableObjectNode)._sync_rect_size()
		else:
			ch["font_size"] = maxi(1, int(round(float(ch.get("font_size", 24)) * s)))
			if n is _HudText:
				(n as _HudText).apply(ch, _load_font(String(ch.get("font", ""))))
	_dirty = true
	_refresh_props()

func _apply_size_to_selected() -> void:
	var ch := _selected_child()
	if ch.is_empty() or String(ch.get("type", "")) != "item":
		return
	ch["size"] = Vector2(_w_spin.value, _h_spin.value)
	var eo = _nodes.get(_sel_id, null)
	if eo is EditableObjectNode:
		(eo as EditableObjectNode).size = ch["size"]
		(eo as EditableObjectNode)._sync_rect_size()
	_dirty = true

func _on_opacity_changed(value: float) -> void:
	if _updating_ui:
		return
	var op: float = clampf(value / 100.0, 0.0, 1.0)
	_opacity_pct_lbl.text = "%d%%" % int(round(value))
	if _sel_group != -1 and _sel_group < _groups.size():
		for ch: Dictionary in _groups[_sel_group].get("children", []):
			ch["opacity"] = op
			var gn = _nodes.get(int(ch.get("id", -1)), null)
			if gn != null and is_instance_valid(gn):
				_apply_opacity_to_node(gn, op)
		_dirty = true
		return
	var c := _selected_child()
	if c.is_empty():
		return
	c["opacity"] = op
	var n = _nodes.get(_sel_id, null)
	if n != null and is_instance_valid(n):
		_apply_opacity_to_node(n, op)
	_dirty = true

func _on_blend_selected(idx: int) -> void:
	if _updating_ui:
		return
	var ch := _selected_child()
	if ch.is_empty() or String(ch.get("type", "")) != "item":
		return
	ch["blend"] = idx
	var eo = _nodes.get(_sel_id, null)
	if eo is EditableObjectNode:
		(eo as EditableObjectNode).set_blend_mode(idx)
	_dirty = true

## GROW dropdown (bar bands only): store the grow direction on the child; it drives the fill's
## `grow_dir` shader uniform in gameplay (fills are runtime-only, so no live editor preview).
func _on_grow_selected(idx: int) -> void:
	if _updating_ui:
		return
	var ch := _selected_child()
	if ch.is_empty() or _binder == null or not _binder.is_band_file(String(ch.get("file", ""))):
		return
	ch["grow"] = idx
	_dirty = true

func _on_text_field_changed() -> void:
	if _updating_ui:
		return
	var ch := _selected_child()
	if ch.is_empty() or String(ch.get("type", "")) != "text":
		return
	ch["text"] = _txt_edit.text
	if _font_opt.selected >= 0 and _font_opt.selected < _font_names.size():
		ch["font"] = _font_names[_font_opt.selected]
	ch["font_size"] = int(_txt_size.value)
	ch["align"] = _align_opt.selected
	ch["color"] = _txt_color.color
	ch["outline_color"] = _out_color.color
	ch["outline_size"] = int(_out_size.value)
	var n = _nodes.get(_sel_id, null)
	if n is _HudText:
		(n as _HudText).apply(ch, _load_font(String(ch.get("font", ""))))
	_dirty = true

func _delete_selected() -> void:
	if _sel_group != -1:
		var gi := _sel_group
		_sel_group = -1
		_delete_btn.disabled = true
		_delete_group(gi)
		_refresh_props()
	elif _sel_id != -1:
		_delete_child(_sel_id)

func _delete_child(child_id: int) -> void:
	var loc := _find_child(child_id)
	if loc.x < 0:
		return
	(_groups[loc.x]["children"] as Array).remove_at(loc.y)
	_free_node(child_id)
	if _sel_id == child_id:
		_select(-1)
	_dirty = true
	_reassign_z()
	_rebuild_groups_panel()

# ── Canvas nodes ─────────────────────────────────────────────────────────────────────

func _rebuild_nodes() -> void:
	for id: int in _nodes.keys():
		_free_node(id)
	_nodes.clear()
	for g: Dictionary in _groups:
		for ch: Dictionary in g.get("children", []):
			_make_node(ch)

func _make_node(ch: Dictionary) -> void:
	if _objects_container == null:
		return
	var id := int(ch.get("id", -1))
	if String(ch.get("type", "")) == "item":
		var tex := _load_tex(_item_path(String(ch.get("file", ""))))
		if tex == null:
			return
		var eo: EditableObjectNode = EditableObject.instantiate()
		eo.group_id = "hud_item"
		eo.source_path = String(ch.get("file", ""))
		_objects_container.add_child(eo)
		eo.init(tex, ch.get("pos", Vector2(440.0, 320.0)), ch.get("size", Vector2(80.0, 80.0)))
		eo.set_meta("child_id", id)
		var editable := _is_open and not _is_child_locked(id)
		eo.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
		eo.set_gameplay_mode(not editable)
		eo.set_blend_mode(int(ch.get("blend", 0)))
		eo.object_clicked.connect(_on_eo_clicked)
		eo.transform_ended.connect(_on_eo_transform_ended)
		eo.transform_motion.connect(_on_eo_transform_motion)
		eo.visible = bool(ch.get("visible", true))
		_apply_opacity_to_node(eo, float(ch.get("opacity", 1.0)))
		_nodes[id] = eo
	else:
		var t := _HudText.new()
		t.owner_editor = self
		t.child_id = id
		_objects_container.add_child(t)
		t.apply(ch, _load_font(String(ch.get("font", ""))))
		t.set_gameplay(not (_is_open and not _is_child_locked(id)))
		t.visible = bool(ch.get("visible", true))
		_apply_opacity_to_node(t, float(ch.get("opacity", 1.0)))
		_nodes[id] = t

func _free_node(child_id: int) -> void:
	var n = _nodes.get(child_id, null)
	if n != null and is_instance_valid(n):
		n.queue_free()
	_nodes.erase(child_id)

## on=true → gameplay (non-interactive); on=false → editing. A child in a LOCKED group stays
## non-interactive even while editing.
func _set_gameplay(on: bool) -> void:
	for id: int in _nodes:
		var n = _nodes[id]
		if n == null or not is_instance_valid(n):
			continue
		var editable := (not on) and not _is_child_locked(id)
		if n is EditableObjectNode:
			var eo := n as EditableObjectNode
			eo.set_gameplay_mode(not editable)
			# Bar bands are edit-only indicators (their masked fill is what shows in gameplay).
			var vis := _child_visible(id)
			if on and _binder != null and _binder.is_band_file(eo.source_path):
				vis = false
			eo.visible = vis
			eo.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
		elif n is _HudText:
			(n as _HudText).set_gameplay(not editable)
			(n as _HudText).visible = _child_visible(id)

## Top group's top child = highest z; descends down the list.
func _reassign_z() -> void:
	var z := Z_TOP
	for g: Dictionary in _groups:
		for ch: Dictionary in g.get("children", []):
			ch["z"] = z
			var n = _nodes.get(int(ch.get("id", -1)), null)
			if n != null and is_instance_valid(n):
				(n as CanvasItem).z_index = z
			z -= 1

# ── Canvas node callbacks ────────────────────────────────────────────────────────────

func _on_eo_clicked(eo: EditableObjectNode) -> void:
	if not _is_open:
		return
	_select(int(eo.get_meta("child_id", -1)))

func _on_eo_transform_ended(obj: Control) -> void:
	_sync_node_to_data(obj)
	_refresh_props()
	_dirty = true

func _on_eo_transform_motion(obj: EditableObjectNode) -> void:
	_sync_node_to_data(obj)
	_refresh_props()
	_dirty = true

func _sync_node_to_data(obj: Control) -> void:
	if not (obj is EditableObjectNode):
		return
	var id := int((obj as EditableObjectNode).get_meta("child_id", -1))
	var loc := _find_child(id)
	if loc.x < 0:
		return
	var ch: Dictionary = (_groups[loc.x]["children"] as Array)[loc.y]
	ch["pos"] = obj.position
	ch["size"] = obj.size

func _on_text_clicked(child_id: int) -> void:
	if not _is_open:
		return
	_select(child_id)

func _on_text_moved(child_id: int, pos: Vector2) -> void:
	var loc := _find_child(child_id)
	if loc.x < 0:
		return
	(_groups[loc.x]["children"] as Array)[loc.y]["pos"] = pos
	_dirty = true
	_refresh_props()

# ── Helpers ──────────────────────────────────────────────────────────────────────────

## Returns Vector2i(group_index, child_index) or (-1,-1) if not found.
func _find_child(child_id: int) -> Vector2i:
	for gi: int in _groups.size():
		var children: Array = _groups[gi].get("children", [])
		for ci: int in children.size():
			if int((children[ci] as Dictionary).get("id", -1)) == child_id:
				return Vector2i(gi, ci)
	return Vector2i(-1, -1)

func show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

# ── Persistence ───────────────────────────────────────────────────────────────────────

func _save_layout() -> void:
	# Pull live transforms back into the data before writing.
	for id: int in _nodes:
		var n = _nodes[id]
		if n == null or not is_instance_valid(n):
			continue
		var loc := _find_child(id)
		if loc.x < 0:
			continue
		var ch: Dictionary = (_groups[loc.x]["children"] as Array)[loc.y]
		ch["pos"] = (n as Control).position
		if n is EditableObjectNode:
			ch["size"] = (n as Control).size
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "next_id", _next_id)
	cfg.set_value("meta", "board", _board_id)
	cfg.set_value("hud", "groups", _groups)
	# Ensure the target folder exists (config/boards/…) before saving.
	var save_path := _layout_save if _layout_save != "" else _layout_load
	var dir := save_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	cfg.save(save_path)
	_dirty = false
	show_toast("Saved " + save_path.get_file())

func _load_layout() -> void:
	var cfg := ConfigFile.new()
	var load_path := _layout_load if _layout_load != "" else _layout_save
	if load_path == "" or cfg.load(load_path) != OK:
		_groups = []
		_next_id = 1
		return
	var data = cfg.get_value("hud", "groups", [])
	if data is Array:
		_groups = data
	_next_id = int(cfg.get_value("meta", "next_id", 1))
	# Safety: ensure unique ids / next_id is past every existing id.
	for g: Dictionary in _groups:
		for ch: Dictionary in g.get("children", []):
			_next_id = maxi(_next_id, int(ch.get("id", 0)) + 1)

# ── Input: arrow-nudge selected node ───────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Panel drag (grabbed by a title bar)
	if _drag_panel != null:
		if event is InputEventMouseMotion:
			var mp := get_viewport().get_mouse_position()
			var vp := get_viewport().get_visible_rect().size
			var np := mp + _drag_off
			np.x = clampf(np.x, 0.0, maxf(0.0, vp.x - _drag_panel.size.x))
			np.y = clampf(np.y, 0.0, maxf(0.0, vp.y - 60.0))
			_drag_panel.position = np
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_drag_panel = null
		return
	# Mouse-wheel zoom (ignore when the cursor is over a panel).
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if _left_panel.get_global_rect().has_point(mb.position) or _right_panel.get_global_rect().has_point(mb.position):
				return
			var factor := ZOOM_RATIO if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_RATIO)
			_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom(mb.position)
			get_viewport().set_input_as_handled()
		return
	if _sel_id == -1 or not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var ke := event as InputEventKey
	var dir := Vector2.ZERO
	match ke.keycode:
		KEY_UP:    dir = Vector2(0.0, -1.0)
		KEY_DOWN:  dir = Vector2(0.0,  1.0)
		KEY_LEFT:  dir = Vector2(-1.0, 0.0)
		KEY_RIGHT: dir = Vector2(1.0,  0.0)
	if dir == Vector2.ZERO:
		return
	if ke.shift_pressed:
		dir *= 10.0
	var n = _nodes.get(_sel_id, null)
	if n != null and is_instance_valid(n):
		(n as Control).position += dir
		var loc := _find_child(_sel_id)
		if loc.x >= 0:
			(_groups[loc.x]["children"] as Array)[loc.y]["pos"] = (n as Control).position
		_refresh_props()
		_dirty = true
	get_viewport().set_input_as_handled()

# ════════════════════════════════════════════════════════════════════════════════════
# RUNTIME — while NOT editing, delegate per-frame live updates to the active board's binder.
# (The placed nodes ARE the live surface; the binder makes them dynamic — see BoardBinder.)
# ════════════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if _is_open or _binder == null:
		return
	_binder.update(_delta)

# ════════════════════════════════════════════════════════════════════════════════════
# Inner UI classes
# ════════════════════════════════════════════════════════════════════════════════════

## ITEMS palette cell — a drag source carrying its sprite file name.
class _PaletteCell extends Panel:
	var owner_editor = null
	var item_file: String = ""
	var _tr: TextureRect = null
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.9)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.3, 0.4, 0.55)
		add_theme_stylebox_override("panel", sb)
	func set_icon(tex: Texture2D) -> void:
		_tr = TextureRect.new()
		_tr.texture = tex
		_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tr.offset_left = 3; _tr.offset_top = 3; _tr.offset_right = -3; _tr.offset_bottom = -3
		_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tr)
	func _get_drag_data(_pos: Vector2) -> Variant:
		var wrap := Control.new()
		if _tr != null and _tr.texture != null:
			var trp := TextureRect.new()
			trp.texture = _tr.texture
			trp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			trp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			trp.size = Vector2(40.0, 40.0)
			trp.position = Vector2(-20.0, -20.0)
			wrap.add_child(trp)
		set_drag_preview(wrap)
		return {"hud_item_file": item_file}

## A group header row in the GROUPS panel — select / drag-reorder / RMB menu, plus a lock toggle
## and a collapse caret on the right. A locked group can't be selected, dragged, or dropped onto.
class _GroupRow extends Panel:
	var owner_editor = null
	var gi: int = -1
	var locked: bool = false
	var _lbl: Label = null
	var _lock_btn: Button = null
	var _caret_btn: Button = null
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0.0, 26.0)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6; hb.offset_right = -4
		hb.add_theme_constant_override("separation", 2)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hb)
		var grip := Label.new()
		grip.text = "≡"
		grip.add_theme_font_size_override("font_size", 12)
		grip.modulate = Color(0.6, 0.7, 0.9)
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(grip)
		_lbl = Label.new()
		_lbl.add_theme_font_size_override("font_size", 12)
		_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lbl.clip_text = true
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_lbl)
		_lock_btn = _mk_icon_btn("■")
		_lock_btn.pressed.connect(func() -> void: owner_editor._toggle_group_locked(gi))
		hb.add_child(_lock_btn)
		_caret_btn = _mk_icon_btn("▾")
		_caret_btn.pressed.connect(func() -> void: owner_editor._toggle_group_collapsed(gi))
		hb.add_child(_caret_btn)
		gui_input.connect(_on_input)
	func _mk_icon_btn(txt: String) -> Button:
		var b := Button.new()
		b.text = txt
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(20.0, 0.0)
		b.add_theme_font_size_override("font_size", 12)
		return b
	var _selected: bool = false
	func init_row(name_text: String, collapsed: bool, is_locked: bool, selected: bool) -> void:
		_lbl.text = name_text
		locked = is_locked
		_selected = selected
		_caret_btn.text = "▸" if collapsed else "▾"
		_caret_btn.tooltip_text = "Mở rộng" if collapsed else "Thu gọn"
		_lock_btn.text = "■" if is_locked else "□"
		_lock_btn.modulate = Color(1.0, 0.5, 0.45) if is_locked else Color(0.6, 0.65, 0.75)
		_lock_btn.tooltip_text = "Đang khóa — bấm để mở" if is_locked else "Bấm để khóa group"
		_restyle()
	func set_group_selected(on: bool) -> void:
		_selected = on
		_restyle()
	func _restyle() -> void:
		var sb := StyleBoxFlat.new()
		if _selected:
			sb.bg_color = Color(0.28, 0.50, 0.85, 0.95)
		elif locked:
			sb.bg_color = Color(0.22, 0.16, 0.16, 0.95)
		else:
			sb.bg_color = Color(0.16, 0.20, 0.30, 0.95)
		sb.set_corner_radius_all(3)
		add_theme_stylebox_override("panel", sb)
	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				owner_editor._select_group(gi)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				owner_editor.show_group_context(gi, get_global_mouse_position())
	func _get_drag_data(_pos: Vector2) -> Variant:
		if locked:
			return null
		var prev := Label.new()
		prev.text = _lbl.text
		set_drag_preview(prev)
		return {"hud_group": gi}
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if locked:
			return false
		return data is Dictionary and ((data as Dictionary).has("hud_group") \
			or (data as Dictionary).has("hud_item_file") or (data as Dictionary).has("hud_child"))
	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var d := data as Dictionary
		if d.has("hud_group"):
			owner_editor.move_group(int(d["hud_group"]), gi)
		elif d.has("hud_item_file"):
			owner_editor.drop_item_file(String(d["hud_item_file"]), gi, -1)
		elif d.has("hud_child"):
			owner_editor.relocate_child(int(d["hud_child"]), gi, -1)

## A child row (item or text) under a group — drag source + drop target + select/RMB.
class _ChildRow extends Panel:
	var owner_editor = null
	var gi: int = -1
	var ci: int = -1
	var child_id: int = -1
	var locked: bool = false
	var _lbl: Label = null
	var _icon: TextureRect = null
	var _eye_btn: Button = null
	var _sel: bool = false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0.0, 24.0)
		_restyle()
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 8; hb.offset_right = -4
		hb.add_theme_constant_override("separation", 4)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hb)
		var grip := Label.new()
		grip.text = "≡"
		grip.tooltip_text = "Drag to reorder (Z within group)"
		grip.add_theme_font_size_override("font_size", 11)
		grip.modulate = Color(0.55, 0.65, 0.85)
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(grip)
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(18.0, 18.0)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_icon)
		_lbl = Label.new()
		_lbl.add_theme_font_size_override("font_size", 11)
		_lbl.clip_text = true
		_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_lbl)
		_eye_btn = Button.new()
		_eye_btn.flat = true
		_eye_btn.focus_mode = Control.FOCUS_NONE
		_eye_btn.custom_minimum_size = Vector2(20.0, 0.0)
		_eye_btn.add_theme_font_size_override("font_size", 11)
		_eye_btn.pressed.connect(func() -> void: owner_editor._toggle_child_visible(child_id))
		hb.add_child(_eye_btn)
		gui_input.connect(_on_input)
	func set_visible_state(vis: bool) -> void:
		_eye_btn.text = "●" if vis else "○"
		_eye_btn.tooltip_text = "Đang hiện — bấm để ẩn" if vis else "Đang ẩn — bấm để hiện"
		_eye_btn.modulate = Color(0.8, 0.9, 1.0) if vis else Color(0.45, 0.48, 0.55)
		_lbl.modulate = Color(1.0, 1.0, 1.0) if vis else Color(0.55, 0.57, 0.62)
	func _restyle() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.25, 0.55, 0.95, 0.45) if _sel else Color(0.08, 0.10, 0.14, 0.6)
		sb.set_corner_radius_all(3)
		add_theme_stylebox_override("panel", sb)
	func set_selected(on: bool) -> void:
		_sel = on
		_restyle()
	func set_content(text: String, icon: Texture2D) -> void:
		_lbl.text = text
		_icon.texture = icon
	func _on_input(event: InputEvent) -> void:
		if locked:
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				owner_editor._select(child_id)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				owner_editor.show_child_context(gi, child_id, get_global_mouse_position())
	func _get_drag_data(_pos: Vector2) -> Variant:
		if locked:
			return null
		var prev := Label.new()
		prev.text = _lbl.text
		set_drag_preview(prev)
		return {"hud_child": child_id}
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if locked:
			return false
		return data is Dictionary and ((data as Dictionary).has("hud_child") \
			or (data as Dictionary).has("hud_item_file"))
	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var d := data as Dictionary
		if d.has("hud_child"):
			owner_editor.relocate_child(int(d["hud_child"]), gi, ci)
		elif d.has("hud_item_file"):
			owner_editor.drop_item_file(String(d["hud_item_file"]), gi, ci)

## On-screen text layer — draggable Label with a selection outline.
class _HudText extends Control:
	var owner_editor = null
	var child_id: int = -1
	var _label: Label = null
	var _sel: bool = false
	var _gameplay: bool = false
	var _dragging: bool = false
	var _drag_off: Vector2 = Vector2.ZERO
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
	func apply(d: Dictionary, font: Font) -> void:
		_label.text = String(d.get("text", "Text"))
		_label.add_theme_font_size_override("font_size", int(d.get("font_size", 24)))
		if font != null:
			_label.add_theme_font_override("font", font)
		_label.add_theme_color_override("font_color", d.get("color", Color.WHITE))
		_label.add_theme_constant_override("outline_size", int(d.get("outline_size", 0)))
		_label.add_theme_color_override("font_outline_color", d.get("outline_color", Color.BLACK))
		_label.horizontal_alignment = int(d.get("align", 0))
		_label.reset_size()
		var ms := _label.get_minimum_size()
		size = ms
		_label.size = ms
		_label.position = Vector2.ZERO
		position = d.get("pos", Vector2(440.0, 320.0))
		queue_redraw()
	func set_selected(on: bool) -> void:
		_sel = on
		queue_redraw()
	## Runtime binding: change only the displayed string (keeps the current font/color/outline).
	func set_text_value(s: String) -> void:
		if _label == null:
			return
		_label.text = s
		_label.reset_size()
		var ms := _label.get_minimum_size()
		size = ms
		_label.size = ms
		_label.position = Vector2.ZERO
		queue_redraw()
	func set_gameplay(on: bool) -> void:
		_gameplay = on
		mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
		if on:
			_sel = false
		queue_redraw()
	func _draw() -> void:
		if _sel and not _gameplay:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.2), false, 2.0)
	func _gui_input(event: InputEvent) -> void:
		if _gameplay:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_off = get_global_mouse_position() - position
					owner_editor._on_text_clicked(child_id)
				elif _dragging:
					_dragging = false
					owner_editor._on_text_moved(child_id, position)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var loc: Vector2i = owner_editor._find_child(child_id)
				if loc.x >= 0:
					owner_editor.show_child_context(loc.x, child_id, get_global_mouse_position())
		elif event is InputEventMouseMotion and _dragging:
			position = get_global_mouse_position() - _drag_off
			queue_redraw()
