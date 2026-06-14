extends Control

const FONT_PATH     := "res://assets/fonts/Gameplay.ttf"
const LAYOUT_PATH   := "res://default_layout.cfg"
const HP_FRAMES     := 40
const SHIELD_FRAMES := 20

var _bg:           TextureRect = null
var _hp_clip:      Control     = null
var _shield_clip:  Control     = null
var _hp_label:     Label       = null
var _shield_label: Label       = null

var _hpbar_rect:      Rect2 = Rect2()
var _hpshield_rect:   Rect2 = Rect2()
var _hpsheet_rect:    Rect2 = Rect2()
var _shieldsheet_rect: Rect2 = Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_init_from_layout")

func _init_from_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	var entries: Array = cfg.get_value("layout", "hud", [])
	for e: Dictionary in entries:
		var path: String = e.get("path", "")
		var pos: Vector2  = e.get("pos",  Vector2.ZERO)
		var sz: Vector2   = e.get("size", Vector2.ONE)
		if path.ends_with("hpbar.png"):
			_hpbar_rect = Rect2(pos, sz)
		elif path.ends_with("hpshield.png"):
			_hpshield_rect = Rect2(pos, sz)
		elif path.ends_with("HPsheet.png"):
			_hpsheet_rect = Rect2(pos, sz)
		elif path.ends_with("shieldsheet.png"):
			_shieldsheet_rect = Rect2(pos, sz)
	_build_display()

func _build_display() -> void:
	var has_shield: bool = GameManager.shield_capacity_total() > 0.0
	var font       := load(FONT_PATH) as FontFile

	# Background frame image
	var bg_path := "res://assets/hud/hpshield.png" if has_shield else "res://assets/hud/hpbar.png"
	var bg_rect := _hpshield_rect if has_shield else _hpbar_rect
	_bg = TextureRect.new()
	_bg.texture      = load(bg_path)
	_bg.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.position     = bg_rect.position
	_bg.size         = bg_rect.size
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# HP segment bar — clip container reveals left portion of the stretched sheet
	if _hpsheet_rect.size.x > 0:
		_hp_clip = Control.new()
		_hp_clip.clip_contents = true
		_hp_clip.position     = _hpsheet_rect.position
		_hp_clip.size         = _hpsheet_rect.size
		_hp_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hp_tr := TextureRect.new()
		hp_tr.texture      = load("res://assets/hud/HPsheet.png")
		hp_tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		hp_tr.stretch_mode = TextureRect.STRETCH_SCALE
		hp_tr.position     = Vector2.ZERO
		hp_tr.size         = _hpsheet_rect.size
		hp_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_clip.add_child(hp_tr)
		add_child(_hp_clip)

	# Shield segment bar
	if has_shield and _shieldsheet_rect.size.x > 0:
		_shield_clip = Control.new()
		_shield_clip.clip_contents = true
		_shield_clip.position     = _shieldsheet_rect.position
		_shield_clip.size         = _shieldsheet_rect.size
		_shield_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shield_tr := TextureRect.new()
		shield_tr.texture      = load("res://assets/hud/shieldsheet.png")
		shield_tr.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		shield_tr.stretch_mode = TextureRect.STRETCH_SCALE
		shield_tr.position     = Vector2.ZERO
		shield_tr.size         = _shieldsheet_rect.size
		shield_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shield_clip.add_child(shield_tr)
		add_child(_shield_clip)

	# HP text label — anchored just above the segment bar
	_hp_label = _make_label(font, Color("#FBF662"))
	_hp_label.position = Vector2(_hpsheet_rect.position.x, _hpsheet_rect.position.y - 16)
	add_child(_hp_label)

	# Shield text label — anchored just above the shield bar, hidden when shield is empty
	if has_shield:
		_shield_label = _make_label(font, Color("#84F9FE"))
		_shield_label.position = Vector2(_shieldsheet_rect.position.x, _shieldsheet_rect.position.y - 16)
		add_child(_shield_label)

	GameManager.ship_hp_changed.connect(_on_hp_changed)
	GameManager.ship_shield_changed.connect(_on_shield_changed)
	_on_hp_changed(GameManager.ship_hp)
	if has_shield:
		_on_shield_changed(GameManager.ship_shield)

func _make_label(font: FontFile, color: Color) -> Label:
	var lbl := Label.new()
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _on_hp_changed(hp: int) -> void:
	var pct     := clampf(float(hp) / float(maxi(1, GameManager.ship_max_hp)), 0.0, 1.0)
	var n_frames := int(round(pct * HP_FRAMES))
	if _hp_clip:
		_hp_clip.size.x = _hpsheet_rect.size.x * float(n_frames) / float(HP_FRAMES)
	if _hp_label:
		_hp_label.text = "%d / %d" % [hp, GameManager.ship_max_hp]

func _on_shield_changed(shield: float) -> void:
	var pct     := clampf(shield / maxf(1.0, GameManager.shield_capacity_total()), 0.0, 1.0)
	var n_frames := int(round(pct * SHIELD_FRAMES))
	if _shield_clip:
		_shield_clip.size.x = _shieldsheet_rect.size.x * float(n_frames) / float(SHIELD_FRAMES)
	if _shield_label:
		_shield_label.visible = shield > 0.0
		_shield_label.text    = "%d / %d" % [int(round(shield)), int(round(GameManager.shield_capacity_total()))]
