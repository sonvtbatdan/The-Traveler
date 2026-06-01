extends Node

const ASSET_BASE := "res://assets/defense/"

var _spaceship:    EditableObjectNode = null
var _original_tex: Texture2D         = null
var _shield_rect:  TextureRect       = null

func _ready() -> void:
	DefenseManager.level_changed.connect(_on_level_changed)
	GameManager.game_loaded.connect(_setup)
	call_deferred("_setup")

func _setup() -> void:
	_find_spaceship()
	_on_level_changed(DefenseManager.current_level)

func _find_spaceship() -> void:
	var best: EditableObjectNode = null
	var best_area := 0.0
	for node in get_tree().get_nodes_in_group("view_screen"):
		var eo := node as EditableObjectNode
		if eo == null:
			continue
		var area := eo.size.x * eo.size.y
		if area > best_area:
			best_area = area
			best = eo
	if best == null:
		return
	_spaceship = best
	_original_tex = _spaceship.texture_rect.texture

	_shield_rect = TextureRect.new()
	_shield_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shield_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shield_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_shield_rect.visible      = false
	_shield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_rect.z_index      = 1
	var shield_tex := load(ASSET_BASE + "shield.png") as Texture2D
	if shield_tex:
		_shield_rect.texture = shield_tex
	_spaceship.add_child(_shield_rect)

func _on_level_changed(level: int) -> void:
	if not is_instance_valid(_spaceship):
		return
	if level == 0:
		_spaceship.texture_rect.texture = _original_tex
	else:
		var tex := load(ASSET_BASE + "lv%d.png" % level) as Texture2D
		if tex:
			_spaceship.texture_rect.texture = tex
	if is_instance_valid(_shield_rect):
		_shield_rect.visible = level >= 7
