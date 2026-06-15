extends Control

const COLOR_AUTO   := Color(0.2, 0.5, 1.0)
const COLOR_BOOST  := Color(0.9, 0.2, 0.2)
const FONT_PATH    := "res://assets/fonts/Gameplay.ttf"

var _btn: Button = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("hud_editable")
	set_meta("hud_key", "boost_button")
	_btn = Button.new()
	_btn.text = "AUTO-DRIVE"
	_btn.custom_minimum_size = Vector2(50, 100)
	_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font := load(FONT_PATH) as FontFile
	if font:
		_btn.add_theme_font_override("font", font)
	_btn.add_theme_font_size_override("font_size", 9)
	_apply_color(false)
	add_child(_btn)
	_btn.pressed.connect(_on_pressed)
	GameManager.boost_changed.connect(_on_boost_changed)
	GameManager.boss_spawned.connect(_on_boss_spawned)
	GameManager.boss_killed.connect(_on_boss_killed_signal)
	# Position after entering tree so viewport rect is valid
	call_deferred("_reposition")

func _reposition() -> void:
	var saved := _load_hud_rect("boost_button")
	if saved.size != Vector2.ZERO:
		_btn.position           = saved.position
		_btn.custom_minimum_size = saved.size
		_btn.size               = saved.size
		return
	var vp := get_viewport_rect().size
	_btn.position = Vector2(vp.x - 60, 550)

func get_hud_rect() -> Rect2:
	return Rect2(_btn.position, _btn.custom_minimum_size)

func apply_hud_rect(rect: Rect2) -> void:
	_btn.position            = rect.position
	_btn.custom_minimum_size = rect.size
	_btn.size                = rect.size

static func _load_hud_rect(key: String) -> Rect2:
	var cfg := ConfigFile.new()
	if cfg.load("user://hud_layout.cfg") != OK:
		return Rect2()
	if not cfg.has_section_key("hud", key + "/pos"):
		return Rect2()
	return Rect2(
		cfg.get_value("hud", key + "/pos",  Vector2.ZERO) as Vector2,
		cfg.get_value("hud", key + "/size", Vector2.ZERO) as Vector2
	)

func _on_pressed() -> void:
	GameManager.set_boost(not GameManager.manual_boost)

func _on_boost_changed(active: bool) -> void:
	_btn.text = "MANUAL BOOST" if active else "AUTO-DRIVE"
	_apply_color(active)

func _on_boss_spawned() -> void:
	_btn.disabled = true
	_btn.modulate.a = 0.45

func _on_boss_killed_signal() -> void:
	_btn.disabled = false
	_btn.modulate.a = 1.0

func _apply_color(active: bool) -> void:
	var c := COLOR_BOOST if active else COLOR_AUTO
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.corner_radius_top_left     = 4; s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4; s.corner_radius_bottom_right = 4
	_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = c.lightened(0.15)
	_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = c.darkened(0.15)
	_btn.add_theme_stylebox_override("pressed", sp)
	_btn.add_theme_color_override("font_color", Color.WHITE)
