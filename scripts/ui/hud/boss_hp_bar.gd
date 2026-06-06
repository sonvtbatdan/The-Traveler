extends Control

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_W     := 135.0

var _fill:      ColorRect = null
var _track:     ColorRect = null
var _label:     Label     = null
var _move_lbl:  Label     = null
var _auto_fire_slider: HSlider = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load(FONT_PATH) as FontFile

	# Auto-fire toggle (above move label)
	_auto_fire_slider = HSlider.new()
	_auto_fire_slider.min_value = 0
	_auto_fire_slider.max_value = 1
	_auto_fire_slider.step = 1
	_auto_fire_slider.value = 0
	_auto_fire_slider.custom_minimum_size = Vector2(60, 16)
	_auto_fire_slider.size = Vector2(60, 16)
	_auto_fire_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_auto_fire_slider.value_changed.connect(_on_auto_fire_changed)
	add_child(_auto_fire_slider)
	_on_auto_fire_changed(0)  # Ensure auto-fire is OFF on startup

	_label = Label.new()
	_label.text = ""
	if font:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 2)
	add_child(_label)

	_track = ColorRect.new()
	_track.color = Color(0.15, 0.15, 0.15, 0.8)
	_track.size  = Vector2(BAR_W, 10)
	add_child(_track)

	_fill = ColorRect.new()
	_fill.color = Color(0.9, 0.35, 0.1)
	_fill.size  = Vector2(BAR_W, 10)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_fill)

	_move_lbl = Label.new()
	_move_lbl.text = ""
	if font:
		_move_lbl.add_theme_font_override("font", font)
	_move_lbl.add_theme_font_size_override("font_size", 9)
	_move_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_move_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_move_lbl)

	visible = false   # hidden until boss spawns

	GameManager.boss_spawned.connect(_on_boss_spawned)
	GameManager.boss_hp_changed.connect(_on_boss_hp_changed)
	GameManager.boss_killed.connect(_on_boss_killed)
	call_deferred("_reposition")

func _reposition() -> void:
	var vp := get_viewport_rect().size
	# Positioned above the player HP bar (player label at vp.y-96, bar at vp.y-82)
	_auto_fire_slider.position = Vector2(vp.x - 145, vp.y - 150)
	_auto_fire_slider.size = Vector2(60, 14)
	_move_lbl.position = Vector2(vp.x - 145, vp.y - 134)
	_move_lbl.size     = Vector2(BAR_W, 14.0)
	_label.position    = Vector2(vp.x - 145, vp.y - 120)
	_track.position    = Vector2(vp.x - 145, vp.y - 106)

func _process(_delta: float) -> void:
	if not visible or _move_lbl == null:
		return
	var name_str := ""
	var cf := get_tree().get_first_node_in_group("chromeleon_fight")
	if cf != null and cf.has_method("get_move_name"):
		var s: String = cf.call("get_move_name")
		if s != "":
			name_str = s
	if name_str == "":
		var mf := get_tree().get_first_node_in_group("metalfly_fight")
		if mf != null and mf.has_method("get_move_name"):
			var s: String = mf.call("get_move_name")
			if s != "":
				name_str = s
	_move_lbl.text = name_str

func _on_boss_spawned() -> void:
	visible = true
	_label.text  = "HP BOSS  %d / %d" % [GameManager.boss_hp, GameManager.boss_max_hp]
	_fill.size.x = BAR_W
	_fill.color  = _bar_color(1.0)

func _on_boss_hp_changed(hp: int) -> void:
	if GameManager.boss_max_hp <= 0:
		return
	var ratio := clampf(float(hp) / float(GameManager.boss_max_hp), 0.0, 1.0)
	_fill.size.x = BAR_W * ratio
	_fill.color  = _bar_color(ratio)
	_label.text  = "HP BOSS  %d / %d" % [hp, GameManager.boss_max_hp]

func _on_boss_killed() -> void:
	visible = false

func _on_auto_fire_changed(value: float) -> void:
	var enabled := bool(int(value))
	var ws := get_tree().get_first_node_in_group("weapon_system")
	if ws != null and ws.has_method("set_auto_fire"):
		ws.set_auto_fire(enabled)

func _bar_color(r: float) -> Color:
	if r > 0.5:  return Color(0.9, 0.35, 0.1)
	if r > 0.25: return Color(1.0, 0.75, 0.1)
	return Color(0.9, 0.15, 0.15)
