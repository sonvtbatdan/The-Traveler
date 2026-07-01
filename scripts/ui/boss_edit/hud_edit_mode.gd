extends CanvasLayer
## HUD Edit Mode — author the Player HUD as ordered GROUPS of items (sprites) and text layers.
##
## Model (≠ creep edit's one-EO-per-file):
##   • GROUPS panel (left): an ordered list of named groups. Top of the list = highest Z band.
##     "+" makes a new group. RMB a group → Copy / Rename / Delete / Add Text.
##     Drag groups up/down to reorder (Z). Drag a palette ITEM onto a group to add it.
##   • Each group holds an ordered list of CHILDREN — items or text layers (drag to reorder within/between).
##     RMB a child → Copy / Delete. An ITEM may appear any number of times (independent instances).
##   • ITEMS palette (right): sprite files in assets/hud/Playerhud — drag sources.
##   • Selecting a TEXT child shows a style panel: text / font (assets/fonts) / size / color / outline / align.
##   • Items and text are dragged on-screen with the mouse; placed nodes ARE the live in-game HUD.
##
## Saves res://playerhud_layout.cfg. Opened via the Devon-panel HUD_edit button (group "hud_edit").

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const ArenaWeapons   := preload("res://scripts/gameplay/arena_weapons.gd")
const BAR_FILL_SHADER   := "res://assets/shaders/bar_fill.gdshader"
const HUD_BLEND_SHADER  := "res://assets/shaders/hud_blend.gdshader"
const INVENTORY_DIR     := "res://assets/inventory/"
# Weapons whose cooldown frac stays 1.0 (continuous fire / always-on) — mirror of arena_weapons'
# weapon_cooldown_frac match: these never light btnred/btngreen.
const CONTINUOUS_WEAPONS := {
	"gatling": true, "orbital": true, "striker": true, "chemtrail": true, "ionize": true,
	"moroboshi": true, "yari_jaeger": true, "swarm": true, "snake": true, "boomerang": true,
}

const HUD_FOLDER   := "res://assets/hud/Playerhud/"
const FONTS_FOLDER := "res://assets/fonts/"
const LAYOUT_PATH  := "res://playerhud_layout.cfg"
const LEFT_W       := 248.0
const RIGHT_W      := 264.0
const Z_TOP        := 240    # highest child z; descends down the list
const BLEND_NAMES  := ["Normal", "Screen", "Hard light", "Overlay", "Color Dodge (add)", "Multiply"]
const ZOOM_MIN     := 0.4
const ZOOM_MAX     := 5.0
const ZOOM_RATIO   := 1.15

# Bar VFX: band sprite files that act as crop frames, + the fill/glow tones per bar.
# All three reuse level_fill.gdshader (green default); HP + Shield just override the colors.
const LV_FILL_COL := Color(0.18, 0.85, 0.32, 1.0)   # matches shader default (level = green)
const LV_GLOW_COL := Color(0.45, 1.00, 0.55, 1.0)
const HP_FILL_COL := Color(0.86, 0.15, 0.13, 1.0)   # HP = red
const HP_GLOW_COL := Color(1.00, 0.42, 0.34, 1.0)
const SH_FILL_COL := Color(0.13, 0.48, 0.86, 1.0)   # Shield = ocean blue
const SH_GLOW_COL := Color(0.40, 0.78, 1.00, 1.0)
# Band sprites act as the crop-frame/mask for their bar VFX; they only show in the editor (indicators).
const BAR_BAND_FILES := {"levelband": true, "HPband": true, "shieldband": true}
const SLOT_ICON_FIT   := 0.72   # weapon/aux icon box = this fraction of the btn (leaves the frame visible)
const SLOT_ICON_BLEND := 6      # weapon/aux icon blend mode → "Lighten" (hud_blend.gdshader mode 3)

# ── Macro groups (gameplay-only): 4 screen-edge regions built from the editor groups ────────────────
# Each region reparents its member nodes into one Control container that is anchored to a screen edge
# (centered on the perpendicular axis) and scaled as one unit for the pulse/shrink animations.
const MACRO_KEYS     := ["Weapon", "Aux", "KillCoin", "LV"]
const MACRO_EDGE     := {"Weapon": "left", "Aux": "right", "KillCoin": "top", "LV": "bottom"}
const MACRO_BEHAVIOR := {"Weapon": "shrink", "Aux": "shrink", "KillCoin": "pulse", "LV": "static"}
# Editor group name → macro key. (The "Text" group is split by sentinel: KILL/COIN → KillCoin, rest → LV.)
const GROUP_MACRO := {
	"Button1": "Weapon", "Button2": "Weapon", "Button3": "Weapon", "Button4": "Weapon", "Button5": "Weapon", "ActiveBar": "Weapon",
	"Button6": "Aux", "Button7": "Aux", "Button8": "Aux", "Button9": "Aux", "Button10": "Aux", "PassiveBar": "Aux",
	"KillBar": "KillCoin",
	"INV": "LV", "MENU": "LV", "LevelBarBg": "LV", "Level": "LV", "LevelBar": "LV",
}
const KILLCOIN_TEXTS := {"KILL": true, "COIN": true}   # Text-group sentinels that belong to KillCoin (rest → LV)
const MACRO_MARGIN := 6.0        # gap between a region's outer edge and the screen edge
const SHRINK_SCALE := 0.70       # Weapon/Aux resting size after a change settles
const SHRINK_DELAY := 5.0        # seconds at full size before shrinking back
const SHRINK_DUR   := 0.30       # shrink tween duration
const PULSE_SCALE  := 1.03       # KillCoin pop size on a value change
const PULSE_DUR    := 0.05       # each half of the 0.1s pop
# grow_dir option order in the GROW dropdown → shader uniform int (0=L→R,1=R→L,2=B→T,3=T→B).
const GROW_NAMES := ["→  Left → Right", "←  Right → Left", "↑  Bottom → Top", "↓  Top → Bottom"]
# Unique-role sprite files resolved by filename anywhere in the layout (bar bands + press-button pairs).
const ROLE_FILES := {
	"levelband": true, "HPband": true, "shieldband": true,
	"menubtn": true, "menubtnpress": true, "invbtn": true, "invbtnpress": true,
	"inventory": true, "inventorypress": true,
}

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

# ── Runtime HUD binding (active in gameplay, i.e. while the editor is NOT open) ──────
var _bindings_ready: bool = false
var _text_bindings: Array = []        # [{node, kind, align, left, center, right, y}]
var _wslots: Array = []               # [{btn, red, green, icon}] index 0..4 → weapon slots 1..5
var _aslots: Array = []               # [{btn, yellow, icon}]      index 0..4 → aux slots 6..10
# Bar VFX: a shader "fill" TextureRect masked by a band sprite (level = green xp, HP = red, shield = blue).
var _level_fill: TextureRect = null
var _hp_fill: TextureRect = null
var _shield_fill: TextureRect = null
var _runtime_extras: Array = []        # runtime-only nodes (weapon/aux icons, bar fills, press buttons) to free on edit
var _weapons_node: Node = null
var _aux_node: Node = null
var _weapon_icon_cache: Dictionary = {}
var _aux_icon_cache: Dictionary = {}
# Macro regions (gameplay-only): key -> {container, edge, behavior, tween}. Cleared while editing.
var _macros: Dictionary = {}
var _last_acquired_n: int = -1   # weapon-count baseline for detecting a new weapon (→ Weapon pop)
var _last_owned_n: int = -1      # aux-count baseline (→ Aux pop)
var _signals_hooked: bool = false

# ── UI nodes ──────────────────────────────────────────────────────────────────────
var _dim:           ColorRect     = null
var _toast:         Label         = null
var _left_panel:    Panel         = null
var _right_panel:   Panel         = null
var _groups_vbox:   VBoxContainer = null
var _palette_grid:  GridContainer = null
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
	add_to_group("hud_edit")
	_scan_fonts()
	_scan_items()
	_build_ui()
	_set_ui_visible(false)
	_hook_stat_signals()

func setup(objects_container: Control) -> void:
	_objects_container = objects_container
	# The editor pauses the tree; ALWAYS lets the placed nodes still process + receive input while editing.
	_objects_container.process_mode = Node.PROCESS_MODE_ALWAYS
	_load_layout()
	_rebuild_nodes()
	_reassign_z()
	_set_gameplay(true)   # show as live HUD until the editor is opened
	_build_runtime_bindings()   # wire the placed nodes to live game state + build the edge-anchored macro regions

## Live-stat signals that drive the macro-region animations (connected once; handlers no-op if the
## targeted region isn't built, e.g. while the editor is open).
func _hook_stat_signals() -> void:
	if _signals_hooked:
		return
	_signals_hooked = true
	if GameManager.has_signal("kills_changed"):
		GameManager.kills_changed.connect(func(_k: int) -> void: _pulse_macro("KillCoin"))
	if GameManager.has_signal("money_changed"):
		GameManager.money_changed.connect(func(_m: int) -> void: _pulse_macro("KillCoin"))
	if GameManager.has_signal("player_stats_changed"):
		GameManager.player_stats_changed.connect(func() -> void: _trigger_shrink("Weapon"); _trigger_shrink("Aux"))

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open:
		_request_close()
	else:
		_open()

func _open() -> void:
	_is_open = true
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_arena_focus(true)
	_reset_zoom()
	_clear_macros()           # dismantle edge regions → members return to design positions for editing
	_clear_runtime_extras()   # remove runtime-only nodes; stop binding while editing
	_bindings_ready = false
	_restore_design_text()    # show the design sentinels ("200", "KILL", …) while editing
	_set_ui_visible(true)
	_set_gameplay(false)
	_select(-1)
	_rebuild_groups_panel()

func _request_close() -> void:
	if _dirty:
		_save_layout()
	_close()

func _close() -> void:
	_is_open = false
	_drag_panel = null
	_reset_zoom()
	_set_ui_visible(false)
	_select(-1)
	_set_gameplay(true)
	_arena_focus(false)
	get_tree().paused = _prev_paused
	_build_runtime_bindings()   # re-resolve node refs (editing may have rebuilt them) + rebuild macro regions

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
	var dir := DirAccess.open(HUD_FOLDER)
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
		var p := HUD_FOLDER + file + "." + ext
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

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 3)
	root.add_child(btn_row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_layout)
	btn_row.add_child(save_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.disabled = true
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.pressed.connect(_delete_selected)
	btn_row.add_child(_delete_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(_request_close)
	btn_row.add_child(close_btn)

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
	var is_band: bool = is_item and BAR_BAND_FILES.has(String(ch.get("file", "")))
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
	if ch.is_empty() or not BAR_BAND_FILES.has(String(ch.get("file", ""))):
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
			if on and _is_band_node(eo):
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
	cfg.set_value("hud", "groups", _groups)
	cfg.save(LAYOUT_PATH)
	_dirty = false
	show_toast("Saved " + LAYOUT_PATH.get_file())

func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
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
# RUNTIME HUD BINDING — drives the placed nodes from live game state while NOT editing.
# (The editor's gameplay nodes ARE the player HUD; this layer makes them dynamic.)
# ════════════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if _is_open or not _bindings_ready:
		return
	_update_bindings()

## Resolve role nodes from the loaded layout and create the runtime-only extras (weapon/aux icons,
## bar fills, menu/inv press-buttons). Called on first setup and whenever the editor closes
## (editing may have rebuilt nodes).
func _build_runtime_bindings() -> void:
	_clear_runtime_extras()
	_bindings_ready = false
	_text_bindings.clear()
	_wslots.clear(); _wslots.resize(5)
	_aslots.clear(); _aslots.resize(5)
	_weapons_node = get_tree().get_first_node_in_group("arena_weapons")
	_aux_node = get_tree().get_first_node_in_group("arena_aux")
	# First occurrence of each unique-role sprite file (bar bands + press-button pairs), any group.
	var roles: Dictionary = {}
	for g: Dictionary in _groups:
		var gname := String(g.get("name", ""))
		var children: Array = g.get("children", [])
		if gname == "Text":
			for ch: Dictionary in children:
				if String(ch.get("type", "")) == "text":
					_bind_text(ch)
		elif gname.begins_with("Button"):
			var num := int(gname.substr(6))
			var brk := {}
			for ch: Dictionary in children:
				if String(ch.get("type", "")) == "item":
					brk[String(ch.get("file", ""))] = _nodes.get(int(ch.get("id", -1)))
			if num >= 1 and num <= 5:
				var wbtn = brk.get("btn")
				_wslots[num - 1] = {"btn": wbtn, "red": brk.get("btnred"), "green": brk.get("btngreen"), "icon": _make_slot_icon(wbtn, "Weapon")}
			elif num >= 6 and num <= 10:
				var abtn = brk.get("btn")
				_aslots[num - 6] = {"btn": abtn, "yellow": brk.get("btnyellow"), "icon": _make_slot_icon(abtn, "Aux")}
		# Collect unique-role item CHILDREN (bands / buttons) from every group, regardless of group name.
		for ch: Dictionary in children:
			if String(ch.get("type", "")) == "item":
				var f := String(ch.get("file", ""))
				if ROLE_FILES.has(f) and not roles.has(f):
					roles[f] = ch
	# Bar VFX — a masked shader fill in each band silhouette (level = green, HP = red, shield = blue).
	if roles.has("levelband"):
		_level_fill = _make_bar_fill(roles["levelband"], LV_FILL_COL, LV_GLOW_COL)
	if roles.has("HPband"):
		_hp_fill = _make_bar_fill(roles["HPband"], HP_FILL_COL, HP_GLOW_COL)
	if roles.has("shieldband"):
		_shield_fill = _make_bar_fill(roles["shieldband"], SH_FILL_COL, SH_GLOW_COL)
	# Menu / Inv buttons — normal sprite, "…press" while held, action on release.
	_setup_press_pair(_role_node(roles, "menubtn"), _role_node(roles, "menubtnpress"), _open_menu, "LV")
	_setup_press_pair(_role_node(roles, "invbtn"),  _role_node(roles, "invbtnpress"),  _open_inventory, "LV")
	# Legacy Equip pair (kept harmless if the layout still uses inventory/inventorypress sprites).
	_setup_press_pair(_role_node(roles, "inventory"), _role_node(roles, "inventorypress"), _open_inventory, "LV")
	_build_macros()   # reparent everything into the 4 edge-anchored regions (gameplay only)
	_bindings_ready = true

## Live node for a role child dict stored in `roles`, or null.
func _role_node(roles: Dictionary, key: String) -> Node:
	var ch = roles.get(key)
	if ch == null:
		return null
	return _nodes.get(int((ch as Dictionary).get("id", -1)))

func _is_band_node(eo: EditableObjectNode) -> bool:
	return BAR_BAND_FILES.has(eo.source_path)

## A press-toggle button pair over a HUD sprite: show `normal`; while held show `press`; fire `action`
## on release inside. A transparent Button catches the input (the sprites themselves stay non-interactive).
func _setup_press_pair(normal, press, action: Callable, macro_key: String = "") -> void:
	if normal == null or not is_instance_valid(normal):
		return
	var nc := normal as Control
	_set_press_pair(normal, press, false)   # default: show normal, hide press
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	b.position = nc.position
	b.size = nc.size
	b.z_index = (normal as CanvasItem).z_index + 1
	b.button_down.connect(func() -> void: _set_press_pair(normal, press, true))
	b.button_up.connect(func() -> void: _set_press_pair(normal, press, false))
	if action.is_valid():
		b.pressed.connect(action)
	b.set_meta("macro_key", macro_key)   # ride along with its region (e.g. LV) when reparented
	_objects_container.add_child(b)
	_runtime_extras.append(b)

func _set_press_pair(normal, press, pressed: bool) -> void:
	if normal != null and is_instance_valid(normal):
		(normal as CanvasItem).visible = not pressed
	if press != null and is_instance_valid(press):
		(press as CanvasItem).visible = pressed

## Menu button → open the shared Settings/Menu panel (instanced by arena_hud_buttons, group "settings_panel").
func _open_menu() -> void:
	var s := get_tree().get_first_node_in_group("settings_panel")
	if s != null and is_instance_valid(s) and s.has_method("open"):
		s.call("open")

## Inv button → open the inventory (the panel itself is implemented later; no-ops until then).
func _open_inventory() -> void:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and is_instance_valid(inv) and inv.has_method("toggle"):
		inv.call("toggle")

func _bind_text(ch: Dictionary) -> void:
	var node = _nodes.get(int(ch.get("id", -1)))
	if node == null or not is_instance_valid(node):
		return
	var kind := ""
	match String(ch.get("text", "")):
		"200": kind = "hp_cur"
		"300": kind = "hp_max"
		"50":  kind = "sh_cur"
		"100": kind = "sh_max"
		"KILL": kind = "kill"
		"COIN": kind = "coin"
		"LV. 3": kind = "level"
	if kind == "":
		return
	if node is _HudText:
		(node as _HudText).apply(ch, _load_font(String(ch.get("font", ""))))   # design text → measure anchor
	var pos: Vector2 = (node as Control).position
	var sz: Vector2 = (node as Control).size
	_text_bindings.append({
		"node": node, "kind": kind, "align": int(ch.get("align", 0)),
		"left": pos.x, "center": pos.x + sz.x * 0.5, "right": pos.x + sz.x, "y": pos.y,
	})

func _update_bindings() -> void:
	for b: Dictionary in _text_bindings:
		_set_text_binding(b, _text_value(String(b["kind"])))
	_update_weapons()
	_update_aux()
	var need := GameManager.xp_to_next(GameManager.player_level)
	_set_fill_progress(_level_fill, float(GameManager.player_xp), float(need))
	_set_fill_progress(_hp_fill, float(GameManager.ship_hp), float(GameManager.ship_max_hp))
	_set_fill_progress(_shield_fill, GameManager.ship_shield, GameManager.shield_capacity_total())

## Drive a bar fill's shader `progress` from cur/maxv (clamped 0..1; 0 when maxv <= 0).
func _set_fill_progress(fill: TextureRect, cur: float, maxv: float) -> void:
	if fill == null or not is_instance_valid(fill):
		return
	var mat := fill.material as ShaderMaterial
	if mat == null:
		return
	var frac := clampf(cur / maxv, 0.0, 1.0) if maxv > 0.0 else 0.0
	mat.set_shader_parameter("progress", frac)

func _text_value(kind: String) -> String:
	match kind:
		"hp_cur": return str(GameManager.ship_hp)
		"hp_max": return str(GameManager.ship_max_hp)
		"sh_cur": return str(int(round(GameManager.ship_shield)))
		"sh_max": return str(int(round(GameManager.shield_capacity_total())))
		"kill":   return str(GameManager.run_kills)
		"coin":   return str(GameManager.money)
		"level":  return "LV. %d" % GameManager.player_level
	return ""

func _set_text_binding(b: Dictionary, s: String) -> void:
	var node = b["node"]
	if node == null or not is_instance_valid(node) or not (node is _HudText):
		return
	(node as _HudText).set_text_value(s)
	var w: float = (node as Control).size.x
	var x: float
	match int(b["align"]):
		1: x = float(b["center"]) - w * 0.5
		2: x = float(b["right"]) - w
		_: x = float(b["left"])
	(node as Control).position = Vector2(x, float(b["y"]))

func _update_weapons() -> void:
	if _weapons_node == null or not is_instance_valid(_weapons_node):
		_weapons_node = get_tree().get_first_node_in_group("arena_weapons")
	var acquired: Array = []
	if _weapons_node != null and is_instance_valid(_weapons_node) and _weapons_node.has_method("acquired_weapons"):
		acquired = _weapons_node.call("acquired_weapons")
	if _last_acquired_n >= 0 and acquired.size() > _last_acquired_n:
		_trigger_shrink("Weapon")   # a new weapon → pop the Weapon region to full, then re-shrink
	_last_acquired_n = acquired.size()
	for i in _wslots.size():
		var s = _wslots[i]
		if s == null:
			continue
		var has: bool = i < acquired.size()
		_set_vis(s.get("btn"), has)
		var icon = s.get("icon")
		if has:
			var kind := String(acquired[i])
			if icon != null and is_instance_valid(icon):
				var tex := _weapon_icon_tex(kind)
				(icon as TextureRect).texture = tex
				(icon as TextureRect).visible = tex != null
			var cont: bool = CONTINUOUS_WEAPONS.has(kind)
			var firing: bool = _weapons_node.has_method("weapon_is_firing") and bool(_weapons_node.call("weapon_is_firing", kind))
			var frac := 1.0
			if _weapons_node.has_method("weapon_cooldown_frac"):
				frac = float(_weapons_node.call("weapon_cooldown_frac", kind))
			if cont:
				_set_vis(s.get("red"), false)
				_set_vis(s.get("green"), false)
			else:
				_set_vis(s.get("green"), firing)
				_set_vis(s.get("red"), frac < 0.999 and not firing)
		else:
			_set_vis(s.get("red"), false)
			_set_vis(s.get("green"), false)
			if icon != null and is_instance_valid(icon):
				(icon as CanvasItem).visible = false

func _update_aux() -> void:
	if _aux_node == null or not is_instance_valid(_aux_node):
		_aux_node = get_tree().get_first_node_in_group("arena_aux")
	var owned: Array = []
	if _aux_node != null and is_instance_valid(_aux_node) and _aux_node.has_method("owned_aux"):
		owned = _aux_node.call("owned_aux")
	if _last_owned_n >= 0 and owned.size() > _last_owned_n:
		_trigger_shrink("Aux")   # a new aux → pop the Aux region to full, then re-shrink
	_last_owned_n = owned.size()
	for i in _aslots.size():
		var s = _aslots[i]
		if s == null:
			continue
		_set_vis(s.get("yellow"), false)   # btnyellow unused → always hidden
		var has: bool = i < owned.size()
		_set_vis(s.get("btn"), has)
		var icon = s.get("icon")
		if has:
			var id := String(owned[i])
			var d: Dictionary = {}
			if _aux_node.has_method("def_for"):
				d = _aux_node.call("def_for", id)
			if icon != null and is_instance_valid(icon):
				var tex := _aux_icon_tex(id, d)
				(icon as TextureRect).texture = tex
				(icon as TextureRect).visible = tex != null
		elif icon != null and is_instance_valid(icon):
			(icon as CanvasItem).visible = false

func _set_vis(n, v: bool) -> void:
	if n != null and is_instance_valid(n):
		(n as CanvasItem).visible = v

## A weapon/aux icon TextureRect over `btn`: sized to SLOT_ICON_FIT of the btn (leaves the button frame
## visible), aspect-kept + centered so no weapon sprite is ever stretched, Lighten blend so the icon
## reads as part of the button without darkening it, z just above the btn (below btnred/btngreen higher z).
func _make_slot_icon(btn, macro_key: String) -> TextureRect:
	if btn == null or not is_instance_valid(btn):
		return null
	var bc := btn as Control
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := bc.size * SLOT_ICON_FIT
	tr.size = box
	tr.position = bc.position + (bc.size - box) * 0.5   # centered inside the btn
	tr.z_index = (btn as CanvasItem).z_index
	tr.visible = false
	tr.set_meta("macro_key", macro_key)   # follow its btn's region (Weapon/Aux)
	_apply_blend_to(tr, SLOT_ICON_BLEND)   # Lighten
	_objects_container.add_child(tr)
	_runtime_extras.append(tr)
	return tr

func _apply_blend_to(tr: TextureRect, blend_id: int) -> void:
	match blend_id:
		4:
			var ma := CanvasItemMaterial.new()
			ma.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			tr.material = ma
		5:
			var mm := CanvasItemMaterial.new()
			mm.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
			tr.material = mm
		1, 2, 3:
			var sm := ShaderMaterial.new()
			sm.shader = load(HUD_BLEND_SHADER)
			sm.set_shader_parameter("mode", blend_id - 1)   # 1→Screen(0), 2→HardLight(1), 3→Overlay(2)
			tr.material = sm
		6:
			var sl := ShaderMaterial.new()
			sl.shader = load(HUD_BLEND_SHADER)
			sl.set_shader_parameter("mode", 3)               # Lighten
			tr.material = sl
		_:
			tr.material = null

func _weapon_icon_tex(kind: String) -> Texture2D:
	if _weapon_icon_cache.has(kind):
		return _weapon_icon_cache[kind]
	var info: Dictionary = ArenaWeapons.WEAPON_INFO.get(kind, ArenaWeapons.FUSION_DEFS.get(kind, {}))
	var tex: Texture2D = null
	var icon_path := String(info.get("icon", ""))
	if icon_path != "":
		tex = load(icon_path) as Texture2D
	if tex == null:
		tex = InventoryManager.get_icon(String(info.get("def_id", "")))
	_weapon_icon_cache[kind] = tex
	return tex

func _aux_icon_tex(id: String, d: Dictionary) -> Texture2D:
	if _aux_icon_cache.has(id):
		return _aux_icon_cache[id]
	var tex: Texture2D = null
	var path := String(d.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_aux_icon_cache[id] = tex
	return tex

## A shader "fill" TextureRect that occupies the band's exact rect and is MASKED by the band texture's
## alpha (bar_fill.gdshader), so the fill paints only the band silhouette and never spills past it. The
## band itself is edit-only (hidden in gameplay); this masked fill is the visible bar. `grow` (per band)
## sets the direction the wave grows. fill/glow tones = the bar color (level=green, HP=red, shield=blue).
func _make_bar_fill(ch: Dictionary, fill_col: Color, glow_col: Color) -> TextureRect:
	var id := int(ch.get("id", -1))
	var band = _nodes.get(id)
	if band == null or not is_instance_valid(band):
		return null
	var bc := band as Control
	var tr := TextureRect.new()
	tr.texture = _load_tex(_item_path(String(ch.get("file", ""))))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE   # texture fills the rect → shader UV spans 0..1 over the band
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = bc.position
	tr.size = bc.size
	tr.z_index = (band as CanvasItem).z_index
	tr.visible = _child_visible(id)   # follow the band's eye-toggle (design intent), not its edit-only hide
	tr.set_meta("macro_key", "LV")    # bars live in the bottom LV region
	var mat := ShaderMaterial.new()
	mat.shader = load(BAR_FILL_SHADER)
	mat.set_shader_parameter("fill_color", fill_col)
	mat.set_shader_parameter("glow_color", glow_col)
	mat.set_shader_parameter("grow_dir", int(ch.get("grow", 0)))
	tr.material = mat
	_objects_container.add_child(tr)
	_runtime_extras.append(tr)
	return tr

# ── Macro regions (gameplay only): edge-anchored, uniformly-scalable groups ──────────────────────────
# Gathers each region's member nodes (design items/texts + their runtime extras), reparents them under
# one Control container, then anchors that container to a screen edge (centered on the other axis). The
# container is the single unit that the pulse/shrink tweens scale — about its edge anchor, so it stays
# glued to the edge. Built in gameplay (_build_runtime_bindings); torn down while editing (_clear_macros).

func _build_macros() -> void:
	_clear_macros()
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var vp := get_viewport().get_visible_rect().size
	var members: Dictionary = {}
	for k: String in MACRO_KEYS:
		members[k] = []
	# Design nodes → region by their editor group (Text group split by sentinel).
	for id in _nodes:
		var n = _nodes[id]
		if n == null or not is_instance_valid(n):
			continue
		var mk := _macro_for_child(int(id))
		if members.has(mk):
			(members[mk] as Array).append(n)
	# Runtime extras (icons/fills/buttons) → region by the tag set when they were created.
	for ex in _runtime_extras:
		if ex == null or not is_instance_valid(ex):
			continue
		var mk2 := String((ex as Node).get_meta("macro_key", ""))
		if members.has(mk2):
			(members[mk2] as Array).append(ex)
	for k: String in MACRO_KEYS:
		var mem: Array = members[k]
		if mem.is_empty():
			continue
		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_objects_container.add_child(container)
		# Container starts at identity, so keep_global_transform=true makes local pos == design pos.
		for n in mem:
			(n as Node).reparent(container, true)
		var bbox := _members_local_bbox(mem)
		var edge := String(MACRO_EDGE[k])
		var anchor_local := _edge_anchor_local(bbox, edge)
		var base: float = SHRINK_SCALE if String(MACRO_BEHAVIOR[k]) == "shrink" else 1.0
		# pivot = anchor point → scaling holds it fixed; position maps the anchor onto the screen edge.
		container.pivot_offset = anchor_local
		container.scale = Vector2(base, base)
		container.position = _edge_anchor_screen(vp, edge) - anchor_local
		_macros[k] = {"container": container, "edge": edge, "behavior": String(MACRO_BEHAVIOR[k]), "tween": null}
	# Reset change-detect baselines so the first gameplay frame doesn't fire a spurious pop.
	_last_acquired_n = _weapon_count()
	_last_owned_n = _aux_count()

## Take every container's children back to the objects_container at their design positions (keep_global
## =false preserves the local/design coords), then free the containers. Restores the editing layout.
func _clear_macros() -> void:
	for k in _macros:
		var m: Dictionary = _macros[k]
		var tw = m.get("tween")
		if tw != null and is_instance_valid(tw):
			(tw as Tween).kill()
		var c = m.get("container")
		if c == null or not is_instance_valid(c):
			continue
		for kid in (c as Node).get_children():
			(kid as Node).reparent(_objects_container, false)
		(c as Node).queue_free()
	_macros.clear()

## Which macro region a design child belongs to ("" = none). The "Text" group is split by sentinel.
func _macro_for_child(child_id: int) -> String:
	var loc := _find_child(child_id)
	if loc.x < 0:
		return ""
	var g: Dictionary = _groups[loc.x]
	var gname := String(g.get("name", ""))
	if gname == "Text":
		var ch: Dictionary = (g["children"] as Array)[loc.y]
		return "KillCoin" if KILLCOIN_TEXTS.has(String(ch.get("text", ""))) else "LV"
	return String(GROUP_MACRO.get(gname, ""))

## Union rect of member nodes in their (design) local coords; individual node scale is 1 here.
func _members_local_bbox(mem: Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for n in mem:
		var c := n as Control
		if c == null:
			continue
		var p := c.position
		var sz := c.size * c.scale
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x + sz.x); mx.y = maxf(mx.y, p.y + sz.y)
	if mn.x == INF:
		return Rect2()
	return Rect2(mn, mx - mn)

## The bbox point that pins to the screen edge (outer edge on the anchor axis, centre on the other).
func _edge_anchor_local(b: Rect2, edge: String) -> Vector2:
	match edge:
		"left":   return Vector2(b.position.x, b.position.y + b.size.y * 0.5)
		"right":  return Vector2(b.position.x + b.size.x, b.position.y + b.size.y * 0.5)
		"top":    return Vector2(b.position.x + b.size.x * 0.5, b.position.y)
		_:        return Vector2(b.position.x + b.size.x * 0.5, b.position.y + b.size.y)   # bottom

## Where that anchor lands on screen: flush to the edge (minus margin), centred on the other axis.
func _edge_anchor_screen(vp: Vector2, edge: String) -> Vector2:
	match edge:
		"left":   return Vector2(MACRO_MARGIN, vp.y * 0.5)
		"right":  return Vector2(vp.x - MACRO_MARGIN, vp.y * 0.5)
		"top":    return Vector2(vp.x * 0.5, MACRO_MARGIN)
		_:        return Vector2(vp.x * 0.5, vp.y - MACRO_MARGIN)   # bottom

## Weapon/Aux: snap to full size, hold 5s, then ease back to SHRINK_SCALE. Restarts on each trigger.
func _trigger_shrink(key: String) -> void:
	var m = _macros.get(key)
	if m == null or String((m as Dictionary).get("behavior", "")) != "shrink":
		return
	var c = (m as Dictionary).get("container")
	if c == null or not is_instance_valid(c):
		return
	var old = (m as Dictionary).get("tween")
	if old != null and is_instance_valid(old):
		(old as Tween).kill()
	(c as Control).scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_interval(SHRINK_DELAY)
	tw.tween_property(c, "scale", Vector2(SHRINK_SCALE, SHRINK_SCALE), SHRINK_DUR)
	(m as Dictionary)["tween"] = tw

## KillCoin: quick 0.1s pop to PULSE_SCALE and back on each value change.
func _pulse_macro(key: String) -> void:
	var m = _macros.get(key)
	if m == null:
		return
	var c = (m as Dictionary).get("container")
	if c == null or not is_instance_valid(c):
		return
	var old = (m as Dictionary).get("tween")
	if old != null and is_instance_valid(old):
		(old as Tween).kill()
	(c as Control).scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(PULSE_SCALE, PULSE_SCALE), PULSE_DUR)
	tw.tween_property(c, "scale", Vector2.ONE, PULSE_DUR)
	(m as Dictionary)["tween"] = tw

func _weapon_count() -> int:
	if _weapons_node != null and is_instance_valid(_weapons_node) and _weapons_node.has_method("acquired_weapons"):
		return (_weapons_node.call("acquired_weapons") as Array).size()
	return 0

func _aux_count() -> int:
	if _aux_node != null and is_instance_valid(_aux_node) and _aux_node.has_method("owned_aux"):
		return (_aux_node.call("owned_aux") as Array).size()
	return 0

func _clear_runtime_extras() -> void:
	for n in _runtime_extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_runtime_extras.clear()
	_level_fill = null
	_hp_fill = null
	_shield_fill = null

## Re-show the design sentinel text ("200", "KILL", …) on the text nodes while editing.
func _restore_design_text() -> void:
	for g: Dictionary in _groups:
		if String(g.get("name", "")) != "Text":
			continue
		for ch: Dictionary in g.get("children", []):
			if String(ch.get("type", "")) == "text":
				var n = _nodes.get(int(ch.get("id", -1)))
				if n != null and is_instance_valid(n) and n is _HudText:
					(n as _HudText).apply(ch, _load_font(String(ch.get("font", ""))))

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
