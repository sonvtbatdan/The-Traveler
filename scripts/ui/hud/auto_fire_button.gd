extends Control

const COLOR_OFF := Color(0.20, 0.20, 0.20)
const COLOR_ON  := Color(0.10, 0.70, 0.25)
const FONT_PATH := "res://assets/fonts/Gameplay.ttf"

var _btn: Button = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("hud_editable")
	set_meta("hud_key", "auto_fire")
	_btn = Button.new()
	_btn.text = "AUTO-FIRE"
	_btn.custom_minimum_size = Vector2(50, 100)
	_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font := load(FONT_PATH) as FontFile
	if font:
		_btn.add_theme_font_override("font", font)
	_btn.add_theme_font_size_override("font_size", 9)
	_apply_color(false)
	add_child(_btn)
	_btn.pressed.connect(_on_pressed)
	call_deferred("_reposition")

func _reposition() -> void:
	var saved := _load_hud_rect("auto_fire")
	if saved.size != Vector2.ZERO:
		_btn.position            = saved.position
		_btn.custom_minimum_size = saved.size
		_btn.size                = saved.size
		return
	var vp := get_viewport_rect().size
	_btn.position = Vector2(vp.x - 60, 652)

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
	var ws := get_tree().get_first_node_in_group("weapon_system")
	if ws == null or not ws.has_method("get_auto_fire"):
		return
	var new_state: bool = not bool(ws.get_auto_fire())
	ws.set_auto_fire(new_state)
	_btn.text = "AUTO-FIRE: ON" if new_state else "AUTO-FIRE"
	_apply_color(new_state)

func _apply_color(active: bool) -> void:
	var c := COLOR_ON if active else COLOR_OFF
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
