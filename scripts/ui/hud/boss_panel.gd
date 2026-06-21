extends Panel

const FONT_PATH      := "res://assets/fonts/Gameplay.ttf"
const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const CoordGridScript := preload("res://scripts/ui/hud/coord_grid.gd")

var _elephant_btn:   Button = null
var _chromeleon_btn: Button = null
var _metalfly_btn:   Button = null
var _nautilus_btn:   Button = null
var _coord_btn:      Button = null
var _coord_grid:     CanvasLayer = null

func _ready() -> void:
	custom_minimum_size = Vector2(192.0, 320.0)
	_apply_style()
	_build_ui()
	GameManager.boss_spawned.connect(_on_boss_spawned)
	GameManager.boss_killed.connect(_on_boss_killed)
	_coord_grid = CoordGridScript.new()
	add_child(_coord_grid)

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

func _build_ui() -> void:
	var font := load(FONT_PATH) as FontFile

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "BOSS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	vbox.add_child(title)

	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var st := StyleBoxFlat.new()
		st.bg_color = bg
		st.border_width_left = 1; st.border_width_right  = 1
		st.border_width_top  = 1; st.border_width_bottom = 1
		st.border_color = bc
		st.corner_radius_top_left    = 4; st.corner_radius_top_right    = 4
		st.corner_radius_bottom_left = 4; st.corner_radius_bottom_right = 4
		return st

	# ── Elephant ──
	_elephant_btn = Button.new()
	_elephant_btn.text = "Elephant"
	_elephant_btn.custom_minimum_size = Vector2(50.0, 50.0)
	_elephant_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_elephant_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font: _elephant_btn.add_theme_font_override("font", font)
	_elephant_btn.add_theme_font_size_override("font_size", 11)
	_elephant_btn.add_theme_color_override("font_color", Color.WHITE)
	_elephant_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elephant_btn.expand_icon    = true
	_elephant_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var tex := GifLoader.load_gif("res://assets/bosses/elephant/elephant.gif")
	if tex != null:
		var frames: Array = tex.get_meta("gif_frames") if tex.has_meta("gif_frames") else []
		_elephant_btn.icon = (frames[0] as Texture2D) if not frames.is_empty() else (tex as Texture2D)
	_elephant_btn.add_theme_stylebox_override("normal",   mk.call(Color(0.10, 0.14, 0.22, 0.9), Color(0.35, 0.45, 0.65, 0.8)))
	_elephant_btn.add_theme_stylebox_override("hover",    mk.call(Color(0.16, 0.22, 0.34, 0.9), Color(0.55, 0.70, 0.95, 0.9)))
	_elephant_btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.07, 0.09, 0.14, 0.9), Color(0.35, 0.45, 0.65, 0.8)))
	_elephant_btn.add_theme_stylebox_override("disabled", mk.call(Color(0.07, 0.08, 0.11, 0.6), Color(0.20, 0.25, 0.35, 0.5)))
	_elephant_btn.pressed.connect(_on_elephant_pressed)
	vbox.add_child(_elephant_btn)

	# ── Chromeleon ──
	_chromeleon_btn = Button.new()
	_chromeleon_btn.text = "Chromeleon"
	_chromeleon_btn.custom_minimum_size = Vector2(50.0, 50.0)
	_chromeleon_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_chromeleon_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font: _chromeleon_btn.add_theme_font_override("font", font)
	_chromeleon_btn.add_theme_font_size_override("font_size", 11)
	_chromeleon_btn.add_theme_color_override("font_color", Color.WHITE)
	_chromeleon_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chromeleon_btn.expand_icon    = true
	_chromeleon_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var ctex := GifLoader.load_gif("res://assets/bosses/chromeleon/chromeleon.gif")
	if ctex != null:
		var cframes: Array = ctex.get_meta("gif_frames") if ctex.has_meta("gif_frames") else []
		_chromeleon_btn.icon = (cframes[0] as Texture2D) if not cframes.is_empty() else (ctex as Texture2D)
	_chromeleon_btn.add_theme_stylebox_override("normal",   mk.call(Color(0.08, 0.14, 0.14, 0.9), Color(0.25, 0.65, 0.65, 0.8)))
	_chromeleon_btn.add_theme_stylebox_override("hover",    mk.call(Color(0.12, 0.22, 0.22, 0.9), Color(0.40, 0.85, 0.85, 0.9)))
	_chromeleon_btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.05, 0.09, 0.09, 0.9), Color(0.25, 0.55, 0.55, 0.8)))
	_chromeleon_btn.add_theme_stylebox_override("disabled", mk.call(Color(0.06, 0.08, 0.08, 0.6), Color(0.15, 0.30, 0.30, 0.5)))
	_chromeleon_btn.pressed.connect(_on_chromeleon_pressed)
	vbox.add_child(_chromeleon_btn)

	# ── Metalfly ──
	_metalfly_btn = Button.new()
	_metalfly_btn.text = "Metalfly"
	_metalfly_btn.custom_minimum_size = Vector2(50.0, 50.0)
	_metalfly_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_metalfly_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font: _metalfly_btn.add_theme_font_override("font", font)
	_metalfly_btn.add_theme_font_size_override("font_size", 11)
	_metalfly_btn.add_theme_color_override("font_color", Color.WHITE)
	_metalfly_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_metalfly_btn.expand_icon    = true
	_metalfly_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var mtex := GifLoader.load_gif("res://assets/bosses/metalfly/cocoon.gif")
	if mtex != null:
		var mframes: Array = mtex.get_meta("gif_frames") if mtex.has_meta("gif_frames") else []
		_metalfly_btn.icon = (mframes[0] as Texture2D) if not mframes.is_empty() else (mtex as Texture2D)
	_metalfly_btn.add_theme_stylebox_override("normal",   mk.call(Color(0.08, 0.12, 0.16, 0.9), Color(0.40, 0.55, 0.75, 0.8)))
	_metalfly_btn.add_theme_stylebox_override("hover",    mk.call(Color(0.12, 0.18, 0.26, 0.9), Color(0.60, 0.80, 1.00, 0.9)))
	_metalfly_btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.05, 0.08, 0.12, 0.9), Color(0.35, 0.50, 0.70, 0.8)))
	_metalfly_btn.add_theme_stylebox_override("disabled", mk.call(Color(0.06, 0.08, 0.10, 0.6), Color(0.20, 0.28, 0.38, 0.5)))
	_metalfly_btn.pressed.connect(_on_metalfly_pressed)
	vbox.add_child(_metalfly_btn)

	# ── Nautilus ──
	_nautilus_btn = Button.new()
	_nautilus_btn.text = "Nautilus"
	_nautilus_btn.custom_minimum_size = Vector2(50.0, 50.0)
	_nautilus_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_nautilus_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font: _nautilus_btn.add_theme_font_override("font", font)
	_nautilus_btn.add_theme_font_size_override("font_size", 11)
	_nautilus_btn.add_theme_color_override("font_color", Color.WHITE)
	_nautilus_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nautilus_btn.expand_icon    = true
	_nautilus_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var ntex := GifLoader.load_gif("res://assets/bosses/nautilus/broken.gif")
	if ntex != null:
		var nframes: Array = ntex.get_meta("gif_frames") if ntex.has_meta("gif_frames") else []
		_nautilus_btn.icon = (nframes[0] as Texture2D) if not nframes.is_empty() else (ntex as Texture2D)
	_nautilus_btn.add_theme_stylebox_override("normal",   mk.call(Color(0.06, 0.10, 0.14, 0.9), Color(0.25, 0.55, 0.75, 0.8)))
	_nautilus_btn.add_theme_stylebox_override("hover",    mk.call(Color(0.10, 0.17, 0.24, 0.9), Color(0.40, 0.75, 0.95, 0.9)))
	_nautilus_btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.04, 0.07, 0.11, 0.9), Color(0.22, 0.48, 0.68, 0.8)))
	_nautilus_btn.add_theme_stylebox_override("disabled", mk.call(Color(0.05, 0.07, 0.09, 0.6), Color(0.15, 0.28, 0.38, 0.5)))
	_nautilus_btn.pressed.connect(_on_nautilus_pressed)
	vbox.add_child(_nautilus_btn)

	# ── Coord grid toggle ──
	vbox.add_child(HSeparator.new())
	_coord_btn = Button.new()
	_coord_btn.text = "Coords OFF"
	_coord_btn.toggle_mode = true
	_coord_btn.custom_minimum_size = Vector2(0.0, 28.0)
	_coord_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coord_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_coord_btn.add_theme_font_size_override("font_size", 11)
	_coord_btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_coord_btn.add_theme_stylebox_override("normal",   mk.call(Color(0.08, 0.10, 0.14, 0.9), Color(0.30, 0.40, 0.55, 0.8)))
	_coord_btn.add_theme_stylebox_override("hover",    mk.call(Color(0.14, 0.18, 0.26, 0.9), Color(0.50, 0.65, 0.85, 0.9)))
	_coord_btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.06, 0.20, 0.12, 0.9), Color(0.30, 0.80, 0.50, 0.9)))
	_coord_btn.add_theme_stylebox_override("disabled", mk.call(Color(0.05, 0.07, 0.09, 0.6), Color(0.15, 0.22, 0.30, 0.5)))
	_coord_btn.toggled.connect(_on_coords_toggled)
	vbox.add_child(_coord_btn)

func _on_coords_toggled(pressed: bool) -> void:
	if is_instance_valid(_coord_grid):
		_coord_grid.visible = pressed
	if is_instance_valid(_coord_btn):
		_coord_btn.text = "Coords ON" if pressed else "Coords OFF"

func _on_elephant_pressed()   -> void: _spawn("elephant")
func _on_chromeleon_pressed() -> void: _spawn("chromeleon")
func _on_metalfly_pressed()   -> void: _spawn("metalfly")
func _on_nautilus_pressed()   -> void: _spawn("nautilus")

func _spawn(id: String) -> void:
	var mgr := get_tree().get_first_node_in_group("boss_fight")
	if mgr != null and mgr.has_method("spawn_boss"):
		mgr.call("spawn_boss", id)

func _on_boss_spawned() -> void:
	if _elephant_btn:   _elephant_btn.disabled   = true
	if _chromeleon_btn: _chromeleon_btn.disabled  = true
	if _metalfly_btn:   _metalfly_btn.disabled    = true
	if _nautilus_btn:   _nautilus_btn.disabled    = true

func _on_boss_killed() -> void:
	if _elephant_btn:   _elephant_btn.disabled   = false
	if _chromeleon_btn: _chromeleon_btn.disabled  = false
	if _metalfly_btn:   _metalfly_btn.disabled    = false
	if _nautilus_btn:   _nautilus_btn.disabled    = false
