extends Panel

const ASSET_BASE := "res://assets/defense/"
const ITEMS: Array[Dictionary] = [
	{"name": "Reinforced Titanium Hull",  "icon": "lv1.png"},
	{"name": "Ablative Plating",          "icon": "lv2.png"},
	{"name": "Nano-Repair Swarm",         "icon": "lv3.png"},
	{"name": "Kinetic Shield Generator",  "icon": "lv4.png"},
	{"name": "Magnetic Deflector Layer",  "icon": "lv5.png"},
	{"name": "Heavy Alloy Cockpit",       "icon": "lv6.png"},
	{"name": "Energy Shield Matrix",      "icon": "lv7.png"},
	{"name": "Phase Shift",               "icon": "lv8.png"},
]

var _list_vbox:    VBoxContainer = null
var _rows:         Array[Button] = []
var _name_labels:  Array[Label]  = []

func _ready() -> void:
	_apply_style()
	_build_chrome()
	_build_items()
	DefenseManager.level_changed.connect(func(_l: int) -> void: _refresh())

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

func _build_chrome() -> void:
	var title := Label.new()
	title.text = "DEFENSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if font:
		title.add_theme_font_override("font", font)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 3.0
	title.offset_bottom = 24.0
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 26.0
	scroll.offset_left   = 4.0
	scroll.offset_right  = -4.0
	scroll.offset_bottom = -4.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(_list_vbox)

func _build_items() -> void:
	_rows.clear()
	_name_labels.clear()
	for i in ITEMS.size():
		var btn := _make_row(i)
		_list_vbox.add_child(btn)
		_rows.append(btn)
	_refresh()

func _make_row(level: int) -> Button:
	var data: Dictionary = ITEMS[level]

	var btn := Button.new()
	btn.custom_minimum_size   = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_stylebox_override("normal",   _style(Color(0.07, 0.09, 0.13, 0.95), Color(0.35, 0.45, 0.65, 0.90)))
	btn.add_theme_stylebox_override("hover",    _style(Color(0.10, 0.13, 0.20, 0.95), Color(0.50, 0.65, 0.85, 0.95)))
	btn.add_theme_stylebox_override("pressed",  _style(Color(0.05, 0.07, 0.10, 0.95), Color(0.35, 0.45, 0.65, 0.80)))
	btn.add_theme_stylebox_override("disabled", _style(Color(0.05, 0.06, 0.09, 0.70), Color(0.22, 0.28, 0.42, 0.45)))
	btn.add_theme_stylebox_override("focus",    _style(Color(0.07, 0.09, 0.13, 0.95), Color(0.35, 0.45, 0.65, 0.90)))
	btn.pressed.connect(func() -> void: _on_row_pressed(level))

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left  = 4
	hbox.offset_right = -4
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(28, 28)
	icon_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	var tex := load(ASSET_BASE + String(data["icon"])) as Texture2D
	if tex:
		icon_rect.texture = tex
	hbox.add_child(icon_rect)

	var name_lbl := Label.new()
	name_lbl.text                    = String(data["name"])
	name_lbl.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)
	_name_labels.append(name_lbl)

	return btn

func _refresh() -> void:
	var cur: int = DefenseManager.current_level
	for i in _rows.size():
		var btn: Button  = _rows[i]
		var lbl: Label   = _name_labels[i]
		var level: int   = i + 1
		if level <= cur:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
			btn.disabled = true
		elif level == cur + 1:
			lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
			btn.disabled = false
		else:
			lbl.add_theme_color_override("font_color", Color(0.80, 0.20, 0.20, 1.0))
			btn.disabled = true

func _on_row_pressed(level: int) -> void:
	DefenseManager.try_purchase(level)

func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color          = bg
	s.border_width_left = 1; s.border_width_right  = 1
	s.border_width_top  = 1; s.border_width_bottom = 1
	s.border_color      = border
	s.corner_radius_top_left    = 4; s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	return s
