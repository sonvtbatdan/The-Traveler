extends Control

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_W     := 135.0

var _fill:  ColorRect = null
var _label: Label     = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load(FONT_PATH) as FontFile

	_label = Label.new()
	_label.text = "HP  100 / 100"
	if font:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 2)
	add_child(_label)

	var track := ColorRect.new()
	track.color = Color(0.15, 0.15, 0.15, 0.8)
	track.size  = Vector2(BAR_W, 10)
	add_child(track)

	_fill = ColorRect.new()
	_fill.color = Color(0.2, 0.9, 0.3)
	_fill.size  = Vector2(BAR_W, 10)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)

	GameManager.ship_hp_changed.connect(_on_hp_changed)
	GameManager.ship_destroyed.connect(_on_destroyed)
	call_deferred("_reposition")

func _reposition() -> void:
	var vp := get_viewport_rect().size
	_label.position = Vector2(vp.x - 145, vp.y - 96)
	# track is a sibling of label; reposition it too
	for child in get_children():
		if child is ColorRect:
			child.position = Vector2(vp.x - 145, vp.y - 82)
			break

func _on_hp_changed(hp: int) -> void:
	var ratio := clampf(float(hp) / GameManager.SHIP_MAX_HP, 0.0, 1.0)
	_fill.size.x = BAR_W * ratio
	_fill.color  = _hp_color(ratio)
	_label.text  = "HP  %d / %d" % [hp, GameManager.SHIP_MAX_HP]

func _on_destroyed() -> void:
	_fill.size.x = 0.0
	_label.text  = "HP  DESTROYED"
	_label.add_theme_color_override("font_color", Color.RED)

func _hp_color(r: float) -> Color:
	if r > 0.5:  return Color(0.2, 0.9, 0.3)
	if r > 0.25: return Color(1.0, 0.75, 0.1)
	return Color(0.9, 0.15, 0.15)
