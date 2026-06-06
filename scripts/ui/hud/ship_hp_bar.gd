extends Control

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const BAR_W     := 135.0

var _fill:         ColorRect = null
var _label:        Label     = null
var _shield_fill:  ColorRect = null   # yellow overlay on top of the green fill
var _shield_label: Label     = null   # yellow shield number
var _energy_track: ColorRect = null   # cyan dash-energy bar, below the HP bar
var _energy_fill:  ColorRect = null
var _energy_label: Label     = null

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

	# Yellow shield overlay — added AFTER _fill so it draws on top of the green.
	_shield_fill = ColorRect.new()
	_shield_fill.color = Color(1.0, 0.9, 0.2, 0.9)
	_shield_fill.size  = Vector2(0.0, 10)
	_shield_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_shield_fill)

	_shield_label = Label.new()
	_shield_label.text = "0"
	if font:
		_shield_label.add_theme_font_override("font", font)
	_shield_label.add_theme_font_size_override("font_size", 9)
	_shield_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_shield_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_shield_label.add_theme_constant_override("outline_size", 2)
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shield_label.size = Vector2(60.0, 14.0)
	add_child(_shield_label)

	# Energy (dash) bar — sits just below the HP bar.
	_energy_track = ColorRect.new()
	_energy_track.color = Color(0.15, 0.15, 0.15, 0.8)
	_energy_track.size  = Vector2(BAR_W, 8)
	add_child(_energy_track)

	_energy_fill = ColorRect.new()
	_energy_fill.color = Color(0.25, 0.65, 1.0)
	_energy_fill.size  = Vector2(BAR_W, 8)
	_energy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_track.add_child(_energy_fill)

	_energy_label = Label.new()
	_energy_label.text = "EN  100 / 100"
	if font:
		_energy_label.add_theme_font_override("font", font)
	_energy_label.add_theme_font_size_override("font_size", 9)
	_energy_label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	_energy_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_energy_label.add_theme_constant_override("outline_size", 2)
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_energy_label.size = Vector2(120.0, 12.0)
	add_child(_energy_label)

	GameManager.ship_hp_changed.connect(_on_hp_changed)
	GameManager.ship_shield_changed.connect(_on_shield_changed)
	GameManager.ship_energy_changed.connect(_on_energy_changed)
	GameManager.ship_destroyed.connect(_on_destroyed)
	_on_shield_changed(GameManager.ship_shield)
	_on_energy_changed(GameManager.ship_energy)
	call_deferred("_reposition")

func _reposition() -> void:
	var vp := get_viewport_rect().size
	_label.position = Vector2(vp.x - 145, vp.y - 96)
	# shield number, right-aligned to the bar's right edge
	_shield_label.position = Vector2(vp.x - 145 + BAR_W - 60.0, vp.y - 96)
	# track is a sibling of label; reposition it too
	for child in get_children():
		if child is ColorRect:
			child.position = Vector2(vp.x - 145, vp.y - 82)
			break
	if _energy_track != null:
		_energy_track.position = Vector2(vp.x - 145, vp.y - 66)
	if _energy_label != null:
		_energy_label.position = Vector2(vp.x - 145 + BAR_W - 120.0, vp.y - 68)

func _on_hp_changed(hp: int) -> void:
	var ratio := clampf(float(hp) / GameManager.SHIP_MAX_HP, 0.0, 1.0)
	_fill.size.x = BAR_W * ratio
	_fill.color  = _hp_color(ratio)
	_label.text  = "HP  %d / %d" % [hp, GameManager.SHIP_MAX_HP]
	if hp > 0:   # clear the red "DESTROYED" tint after respawn
		_label.add_theme_color_override("font_color", Color.WHITE)

func _on_shield_changed(shield: float) -> void:
	# Overlay width is scaled against MAX HP and capped at the bar; the number is the true value.
	var ratio := clampf(shield / float(GameManager.SHIP_MAX_HP), 0.0, 1.0)
	if _shield_fill != null:
		_shield_fill.size.x = BAR_W * ratio
	if _shield_label != null:
		_shield_label.text = str(int(round(shield)))

func _on_energy_changed(energy: float) -> void:
	var ratio := clampf(energy / GameManager.SHIP_MAX_ENERGY, 0.0, 1.0)
	if _energy_fill != null:
		_energy_fill.size.x = BAR_W * ratio
	if _energy_label != null:
		_energy_label.text = "EN  %d / %d" % [int(round(energy)), int(GameManager.SHIP_MAX_ENERGY)]

func _on_destroyed() -> void:
	_fill.size.x = 0.0
	_label.text  = "HP  DESTROYED"
	_label.add_theme_color_override("font_color", Color.RED)

func _hp_color(r: float) -> Color:
	if r > 0.5:  return Color(0.2, 0.9, 0.3)
	if r > 0.25: return Color(1.0, 0.75, 0.1)
	return Color(0.9, 0.15, 0.15)
