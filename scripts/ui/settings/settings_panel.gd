extends CanvasLayer
## Shared Settings panel — opened from the Setting button in BOTH the Arena and the Main Menu.
##
##   Volume  : master volume slider → the "Master" audio bus, i.e. the WHOLE game (music + all
##             SFX) in every scene including the Main Menu.
##   Graphic : Windowed / Fullscreen — sets the window mode the game runs/starts in.
##   HUD     : which authored HUD layout (board_defs.gd's `hud_version` boards, e.g. "HUD 1.0" /
##             "HUD 1.1") drives in-arena rendering. Applied live if an arena HUD surface (group
##             "hud_edit") is already in the tree, via HudEditScript.set_home_board().
##   Language: which translated text variant is shown (currently English / Tiếng Việt — see
##             LANGUAGES). Only text with a `desc_<lang_id>` field (so far: aux perk descriptions in
##             arena_aux.gd's AUX_POOL) actually changes; anything untranslated just falls back to
##             English. Read via `SettingsScript.load_cfg()["language"]` wherever localized text is
##             rendered (e.g. arena_levelup_ui.gd) — no live surface to swap, so no _apply_ needed.
##   Dev Mode: switch replacing the (now-hidden) Devon button in arena_hud_buttons.gd — live-only, NOT
##             persisted to disk (dev mode has always reset to off on every arena load; this keeps that).
##             Applied via the "arena_hud_buttons" group, no-op in the Main Menu (no arena instance there).
##   FPS     : switch showing/hiding perf_overlay.gd's top-right readout — same live-only pattern as Dev
##             Mode (group "perf_overlay"), off by default, no-op in the Main Menu.
##   Save    : persist to user://settings.cfg + close.
##   Reset   : restore defaults (Volume 100%, Windowed, HUD 1.0, English) live (persisted only if you then Save).
##   Cancel  : revert any live change to the snapshot taken on open + close (no save).
##
## Persistence lives in user://settings.cfg ([audio] sfx_volume, [display] fullscreen, [hud] version,
## [game] language).
## `SettingsPanel.apply_saved()` (static) applies the saved values at startup — call it from
## the entry points (main_menu / arena_hud_buttons) since AudioManager is a locked autoload. HUD
## version isn't applied there (no arena HUD exists yet at that point) — `arena.gd._setup_hud_edit()`
## reads it directly when it builds the HUD surface.

const BoardDefs  := preload("res://scripts/ui/boards/board_defs.gd")

const CFG_PATH   := "user://settings.cfg"
const ASSET_DIR  := "res://assets/hud/mainmenu/"
const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/Gameplay.ttf"
const DEF_VOLUME := 1.0
const DEF_FULLSCREEN := false
const DEF_HUD_VERSION := "hud"   # board_defs.gd id for "HUD 1.0"
const DEF_LANGUAGE := "en"

# Supported UI languages. `id` is the suffix used for localized-text fields (e.g. `desc_vi`) —
# add an entry here to expose a new language in the dropdown once its text data exists.
const LANGUAGES := [
	{"id": "en", "label": "English"},
	{"id": "vi", "label": "Tiếng Việt"},
]

# ── Static load / apply (used at startup + by this panel) ────────────────────────
static func load_cfg() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)   # ok if missing → defaults below
	var hud_version := String(cfg.get_value("hud", "version", DEF_HUD_VERSION))
	if not BoardDefs.hud_version_ids().has(hud_version):
		hud_version = DEF_HUD_VERSION   # saved id no longer exists (removed board) — fall back
	var language := String(cfg.get_value("game", "language", DEF_LANGUAGE))
	if not _language_ids().has(language):
		language = DEF_LANGUAGE   # saved id no longer supported — fall back
	return {
		"volume": float(cfg.get_value("audio", "sfx_volume", DEF_VOLUME)),
		"fullscreen": bool(cfg.get_value("display", "fullscreen", DEF_FULLSCREEN)),
		"hud_version": hud_version,
		"language": language,
	}

static func _language_ids() -> Array:
	var out: Array = []
	for l: Dictionary in LANGUAGES:
		out.append(String(l["id"]))
	return out

static func _apply_volume(v: float) -> void:
	# Master bus = the whole game's audio (music + every SFX bus routes here), so the slider
	# affects all scenes including the Main Menu.
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		idx = 0
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))

static func _apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

## Apply the persisted settings — call once at startup (entry scene _ready).
static func apply_saved() -> void:
	var s := load_cfg()
	_apply_volume(float(s["volume"]))
	_apply_fullscreen(bool(s["fullscreen"]))

# ── Instance state ───────────────────────────────────────────────────────────────
var _cur_vol: float = DEF_VOLUME
var _cur_fs:  bool = DEF_FULLSCREEN
var _cur_hud: String = DEF_HUD_VERSION
var _cur_lang: String = DEF_LANGUAGE
var _cur_dev: bool = false
var _cur_fps: bool = false
var _snap_vol: float = DEF_VOLUME
var _snap_fs:  bool = DEF_FULLSCREEN
var _snap_hud: String = DEF_HUD_VERSION
var _snap_lang: String = DEF_LANGUAGE
var _snap_dev: bool = false
var _snap_fps: bool = false
var _was_paused: bool = false
var _updating: bool = false

var _root: Control = null
var _slider: HSlider = null
var _pct_lbl: Label = null
var _win_btn: Button = null
var _full_btn: Button = null
var _hud_opt: OptionButton = null
var _lang_opt: OptionButton = null
var _dev_chk: CheckButton = null
var _fps_chk: CheckButton = null

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func is_open() -> bool:
	return visible

# ── Open / close ─────────────────────────────────────────────────────────────────
func open() -> void:
	var s := load_cfg()
	_cur_vol = float(s["volume"])
	_cur_fs  = bool(s["fullscreen"])
	_cur_hud = String(s["hud_version"])
	_cur_lang = String(s["language"])
	_cur_dev = _read_dev_mode()
	_cur_fps = _read_fps_shown()
	_snap_vol = _cur_vol
	_snap_fs  = _cur_fs
	_snap_hud = _cur_hud
	_snap_lang = _cur_lang
	_snap_dev = _cur_dev
	_snap_fps = _cur_fps
	_sync_controls()
	_apply_volume(_cur_vol)
	_apply_fullscreen(_cur_fs)
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true

func _close() -> void:
	get_tree().paused = _was_paused
	visible = false

# ── UI ───────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to whatever is behind
	_root.add_child(dim)

	# CenterContainer fills the screen and centers the panel both axes (PRESET_CENTER alone only
	# puts the panel's top-left at the middle, so it looked offset down-right).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480.0, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.12, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.75)
	sb.set_content_margin_all(22.0)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	var title := Label.new()
	title.text = "SETTINGS"
	_font(title, FONT_TITLE, 30, Color("#E5792A"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(HSeparator.new())

	# ── Volume ──
	var vol_lbl := Label.new()
	vol_lbl.text = "Volume"
	_font(vol_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	col.add_child(vol_lbl)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	col.add_child(vol_row)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 1.0
	_slider.custom_minimum_size = Vector2(0.0, 24.0)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_slider)
	vol_row.add_child(_slider)
	_pct_lbl = Label.new()
	_pct_lbl.custom_minimum_size = Vector2(54.0, 0.0)
	_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_font(_pct_lbl, FONT_BODY, 16, Color(1.0, 0.86, 0.3))
	vol_row.add_child(_pct_lbl)

	# ── Graphic ──
	var gfx_lbl := Label.new()
	gfx_lbl.text = "Graphic"
	_font(gfx_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	col.add_child(gfx_lbl)
	var gfx_row := HBoxContainer.new()
	gfx_row.add_theme_constant_override("separation", 12)
	col.add_child(gfx_row)
	_win_btn = _mode_btn("Windowed")
	_win_btn.pressed.connect(_on_mode.bind(false))
	gfx_row.add_child(_win_btn)
	_full_btn = _mode_btn("Fullscreen")
	_full_btn.pressed.connect(_on_mode.bind(true))
	gfx_row.add_child(_full_btn)

	# ── HUD ──
	var hud_lbl := Label.new()
	hud_lbl.text = "HUD"
	_font(hud_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	col.add_child(hud_lbl)
	_hud_opt = OptionButton.new()
	_hud_opt.custom_minimum_size = Vector2(0.0, 42.0)
	_font_btn(_hud_opt, 16)
	for id in BoardDefs.hud_version_ids():
		_hud_opt.add_item(BoardDefs.display_name(id))
		_hud_opt.set_item_metadata(_hud_opt.item_count - 1, id)
	_hud_opt.item_selected.connect(_on_hud_selected)
	col.add_child(_hud_opt)

	# ── Language ──
	var lang_lbl := Label.new()
	lang_lbl.text = "Language"
	_font(lang_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	col.add_child(lang_lbl)
	_lang_opt = OptionButton.new()
	_lang_opt.custom_minimum_size = Vector2(0.0, 42.0)
	_font_btn(_lang_opt, 16)
	for l: Dictionary in LANGUAGES:
		_lang_opt.add_item(String(l["label"]))
		_lang_opt.set_item_metadata(_lang_opt.item_count - 1, String(l["id"]))
	_lang_opt.item_selected.connect(_on_language_selected)
	col.add_child(_lang_opt)

	# ── Dev Mode ──
	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 10)
	col.add_child(dev_row)
	var dev_lbl := Label.new()
	dev_lbl.text = "Dev Mode"
	dev_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font(dev_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	dev_row.add_child(dev_lbl)
	_dev_chk = CheckButton.new()
	_dev_chk.toggled.connect(_on_dev_toggled)
	dev_row.add_child(_dev_chk)

	# ── FPS ──
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 10)
	col.add_child(fps_row)
	var fps_lbl := Label.new()
	fps_lbl.text = "FPS"
	fps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font(fps_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	fps_row.add_child(fps_lbl)
	_fps_chk = CheckButton.new()
	_fps_chk.toggled.connect(_on_fps_toggled)
	fps_row.add_child(_fps_chk)

	col.add_child(HSeparator.new())

	# ── Save / Reset / Cancel (image buttons, equal width in a row) ──
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)
	btn_row.add_child(_img_btn("save.png",   _on_save))
	btn_row.add_child(_img_btn("reset.png",  _on_reset))
	btn_row.add_child(_img_btn("cancel.png", _on_cancel))

func _mode_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = false
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, 42.0)
	_font_btn(b, 16)
	return b

func _img_btn(file: String, cb: Callable) -> TextureButton:
	var tex := _load_tex(ASSET_DIR + file)
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	var w := 138.0
	var h := w
	if tex != null and tex.get_width() > 0:
		h = w * float(tex.get_height()) / float(tex.get_width())
	b.custom_minimum_size = Vector2(w, h)
	b.pressed.connect(cb)
	return b

# ── Live edits ───────────────────────────────────────────────────────────────────
func _on_slider(v: float) -> void:
	if _updating:
		return
	_cur_vol = clampf(v / 100.0, 0.0, 1.0)
	_pct_lbl.text = "%d%%" % int(round(v))
	_apply_volume(_cur_vol)

func _on_mode(fullscreen: bool) -> void:
	_cur_fs = fullscreen
	_apply_fullscreen(_cur_fs)
	_update_mode_highlight()

func _on_hud_selected(idx: int) -> void:
	if _updating:
		return
	_cur_hud = String(_hud_opt.get_item_metadata(idx))
	_apply_hud_version(_cur_hud)

## Live-swap the arena's HUD surface (if one exists — e.g. Settings opened mid-run). No-op in the
## Main Menu, where there's no "hud_edit" node yet; the choice still gets picked up from cfg the
## next time `arena.gd._setup_hud_edit()` builds one.
func _apply_hud_version(id: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud_edit")
	if hud != null and hud.has_method("set_home_board"):
		hud.set_home_board(id)

func _on_language_selected(idx: int) -> void:
	if _updating:
		return
	_cur_lang = String(_lang_opt.get_item_metadata(idx))

func _on_dev_toggled(v: bool) -> void:
	if _updating:
		return
	_cur_dev = v
	_apply_dev_mode(_cur_dev)

## Read the live dev-mode state from the arena's arena_hud_buttons instance (false if none — e.g. Main Menu).
func _read_dev_mode() -> bool:
	var hb := get_tree().get_first_node_in_group("arena_hud_buttons")
	if hb != null and hb.has_method("is_dev_mode"):
		return bool(hb.call("is_dev_mode"))
	return false

## Live-toggle the arena's dev mode (if an arena instance exists). No-op in the Main Menu.
func _apply_dev_mode(v: bool) -> void:
	var hb := get_tree().get_first_node_in_group("arena_hud_buttons")
	if hb != null and hb.has_method("set_dev_mode"):
		hb.call("set_dev_mode", v)

func _on_fps_toggled(v: bool) -> void:
	if _updating:
		return
	_cur_fps = v
	_apply_fps_shown(_cur_fps)

## Read the live FPS-overlay visibility (false if none — e.g. Main Menu).
func _read_fps_shown() -> bool:
	var po := get_tree().get_first_node_in_group("perf_overlay")
	if po != null and po.has_method("is_shown"):
		return bool(po.call("is_shown"))
	return false

## Live-toggle the arena's FPS overlay (if an arena instance exists). No-op in the Main Menu.
func _apply_fps_shown(v: bool) -> void:
	var po := get_tree().get_first_node_in_group("perf_overlay")
	if po != null and po.has_method("set_shown"):
		po.call("set_shown", v)

func _sync_controls() -> void:
	_updating = true
	_slider.value = _cur_vol * 100.0
	_pct_lbl.text = "%d%%" % int(round(_cur_vol * 100.0))
	_update_mode_highlight()
	for i in _hud_opt.item_count:
		if String(_hud_opt.get_item_metadata(i)) == _cur_hud:
			_hud_opt.select(i)
			break
	for i in _lang_opt.item_count:
		if String(_lang_opt.get_item_metadata(i)) == _cur_lang:
			_lang_opt.select(i)
			break
	_dev_chk.button_pressed = _cur_dev
	_fps_chk.button_pressed = _cur_fps
	_updating = false

func _update_mode_highlight() -> void:
	var on := Color(0.30, 0.55, 0.95)
	var off := Color(0.6, 0.6, 0.65)
	_win_btn.modulate  = on if not _cur_fs else off
	_full_btn.modulate = on if _cur_fs else off

# ── Buttons ──────────────────────────────────────────────────────────────────────
func _on_save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("audio", "sfx_volume", _cur_vol)
	cfg.set_value("display", "fullscreen", _cur_fs)
	cfg.set_value("hud", "version", _cur_hud)
	cfg.set_value("game", "language", _cur_lang)
	cfg.save(CFG_PATH)
	_close()

func _on_reset() -> void:
	_cur_vol = DEF_VOLUME
	_cur_fs  = DEF_FULLSCREEN
	_cur_hud = DEF_HUD_VERSION
	_cur_lang = DEF_LANGUAGE
	_cur_dev = false
	_cur_fps = false
	_sync_controls()
	_apply_volume(_cur_vol)
	_apply_fullscreen(_cur_fs)
	_apply_hud_version(_cur_hud)
	_apply_dev_mode(_cur_dev)
	_apply_fps_shown(_cur_fps)

func _on_cancel() -> void:
	# Revert live changes to the snapshot taken on open, then close without saving.
	_apply_volume(_snap_vol)
	_apply_fullscreen(_snap_fs)
	_apply_hud_version(_snap_hud)
	_apply_dev_mode(_snap_dev)
	_apply_fps_shown(_snap_fps)
	_cur_lang = _snap_lang   # no live surface to revert — just drop the unsaved pick
	_close()

# ── Helpers ──────────────────────────────────────────────────────────────────────
func _load_tex(path: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return load(path) as Texture2D

func _font(lbl: Label, path: String, size: int, col: Color) -> void:
	var f := load(path) as Font
	if f != null:
		lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	var f := load(FONT_BODY) as Font
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", size)
