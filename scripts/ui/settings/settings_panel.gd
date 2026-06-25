extends CanvasLayer
## Shared Settings panel — opened from the Setting button in BOTH the Arena and the Main Menu.
##
##   Volume  : master volume slider → the "Master" audio bus, i.e. the WHOLE game (music + all
##             SFX) in every scene including the Main Menu.
##   Graphic : Windowed / Fullscreen — sets the window mode the game runs/starts in.
##   Save    : persist to user://settings.cfg + close.
##   Reset   : restore defaults (Volume 100%, Windowed) live (persisted only if you then Save).
##   Cancel  : revert any live change to the snapshot taken on open + close (no save).
##
## Persistence lives in user://settings.cfg ([audio] sfx_volume, [display] fullscreen).
## `SettingsPanel.apply_saved()` (static) applies the saved values at startup — call it from
## the entry points (main_menu / arena_hud_buttons) since AudioManager is a locked autoload.

const CFG_PATH   := "user://settings.cfg"
const ASSET_DIR  := "res://assets/hud/mainmenu/"
const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/Gameplay.ttf"
const DEF_VOLUME := 1.0
const DEF_FULLSCREEN := false

# ── Static load / apply (used at startup + by this panel) ────────────────────────
static func load_cfg() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)   # ok if missing → defaults below
	return {
		"volume": float(cfg.get_value("audio", "sfx_volume", DEF_VOLUME)),
		"fullscreen": bool(cfg.get_value("display", "fullscreen", DEF_FULLSCREEN)),
	}

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
var _snap_vol: float = DEF_VOLUME
var _snap_fs:  bool = DEF_FULLSCREEN
var _was_paused: bool = false
var _updating: bool = false

var _root: Control = null
var _slider: HSlider = null
var _pct_lbl: Label = null
var _win_btn: Button = null
var _full_btn: Button = null

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
	_snap_vol = _cur_vol
	_snap_fs  = _cur_fs
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

func _sync_controls() -> void:
	_updating = true
	_slider.value = _cur_vol * 100.0
	_pct_lbl.text = "%d%%" % int(round(_cur_vol * 100.0))
	_update_mode_highlight()
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
	cfg.save(CFG_PATH)
	_close()

func _on_reset() -> void:
	_cur_vol = DEF_VOLUME
	_cur_fs  = DEF_FULLSCREEN
	_sync_controls()
	_apply_volume(_cur_vol)
	_apply_fullscreen(_cur_fs)

func _on_cancel() -> void:
	# Revert live changes to the snapshot taken on open, then close without saving.
	_apply_volume(_snap_vol)
	_apply_fullscreen(_snap_fs)
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
