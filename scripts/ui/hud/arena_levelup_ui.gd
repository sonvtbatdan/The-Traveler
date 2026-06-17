extends CanvasLayer
## Vampire-Survivors level-up flow. When GameManager emits `leveled_up`, pause the game and show 3 random
## upgrade cards; picking one applies a PlayerStats bonus (GameManager.add_*) and resumes. Multiple level-ups
## from one XP gain queue up (shown one after another). CanvasLayer layer 100 + PROCESS_MODE_ALWAYS so it
## runs while the tree is paused. Reuses GameManager's XP/level + stat store — no parallel progression.

const TEX_FRAME := preload("res://assets/hud/lvupframe.png")
const TEX_GREEN := preload("res://assets/hud/lvgreen.png")
const TEX_RED   := preload("res://assets/hud/lvred.png")
const TEX_BLUE  := preload("res://assets/hud/lvblue.png")

# ── UPGRADE POOL (magnitudes — balance here) ────────────────────────────────────
const UPGRADES := [
	{"id": "hp",         "name": "Max HP",        "mag": 20.0},   # flat +HP (and heal)
	{"id": "defense",    "name": "Armor Plating", "mag": 2.0},    # flat damage reduction
	{"id": "fire_rate",  "name": "Fire Rate",     "mag": 0.08},   # +%
	{"id": "move_speed", "name": "Thrusters",     "mag": 0.06},   # +%
	{"id": "damage",     "name": "Damage",        "mag": 0.10},   # +%
	{"id": "momentum",   "name": "Momentum",      "mag": 0.10},   # +%
	{"id": "hp_regen",   "name": "Repair Drones", "mag": 0.5},    # +HP/sec
	{"id": "pickup",     "name": "Magnet",        "mag": 0.15},   # +% pickup radius
]
const CHOICES := 3

# Which background texture each upgrade uses.
const CARD_BG := {
	"hp":         "green",
	"hp_regen":   "green",
	"pickup":     "green",
	"fire_rate":  "red",
	"damage":     "red",
	"defense":    "blue",
	"move_speed": "blue",
	"momentum":   "blue",
}

var _pending: int = 0
var _showing: bool = false
var _root: Control = null
var _cards_box: Control = null
var _current: Array = []   # the 3 upgrade dicts currently offered

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.hide()
	if GameManager.has_signal("leveled_up"):
		GameManager.leveled_up.connect(_on_leveled_up)

func _on_leveled_up(_level: int) -> void:
	_pending += 1
	if not _showing:
		_begin()

func _begin() -> void:
	_showing = true
	get_tree().paused = true
	_show_cards()

func _show_cards() -> void:
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	_current = pool.slice(0, CHOICES)
	for c in _cards_box.get_children():
		c.queue_free()
	for i in _current.size():
		_cards_box.add_child(_make_card(_current[i], i))
	_position_cards()
	_root.show()

# Card layout constants — keep in sync with custom_minimum_size in _make_card().
const _CW    := 160.0   # card width
const _CH    := 208.0   # card height
const _CGAP  := 10.0    # gap between cards
const _CSHIFT := 20.0   # left card shifts left / right card shifts right by this amount

func _position_cards() -> void:
	var cards := _cards_box.get_children()
	# _cards_box anchors: left=0.025, right=0.975, top=0.19, bottom=0.97 on a 720×390 panel
	var box_w := (_cards_box.anchor_right - _cards_box.anchor_left) * 720.0   # ≈ 684
	var box_h := (_cards_box.anchor_bottom - _cards_box.anchor_top)  * 390.0  # ≈ 304
	var cluster_w := _CW * cards.size() + _CGAP * (cards.size() - 1)
	var base_x    := (box_w - cluster_w) * 0.5   # left edge of unshifted cluster
	var base_y    := (box_h - _CH) * 0.5          # vertically centered
	for i in cards.size():
		var x := base_x + i * (_CW + _CGAP)
		if i == 0:
			x -= _CSHIFT
		elif i == cards.size() - 1:
			x += _CSHIFT
		(cards[i] as Control).position = Vector2(x, base_y)
		(cards[i] as Control).size     = Vector2(_CW, _CH)

func _bg_tex(id: String) -> Texture2D:
	match CARD_BG.get(id, "blue"):
		"green": return TEX_GREEN
		"red":   return TEX_RED
		_:       return TEX_BLUE

func _make_card(u: Dictionary, idx: int) -> Control:
	# Fixed size matching lvgreen/red/blue aspect ratio (~910×1185 native → 160×208 display, 80% of full)
	var card := Control.new()
	card.custom_minimum_size = Vector2(160, 208)

	# Background texture (fills entire card)
	var bg := TextureRect.new()
	bg.texture = _bg_tex(String(u["id"]))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(bg)

	# Icon — upper portion of the square area (9%–54%)
	var icon_path := "res://assets/hud/%s.png" % String(u["id"])
	if ResourceLoader.exists(icon_path):
		var icon_tex := TextureRect.new()
		icon_tex.texture = load(icon_path)
		icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_tex.anchor_left   = 0.15
		icon_tex.anchor_right  = 0.85
		icon_tex.anchor_top    = 0.09
		icon_tex.anchor_bottom = 0.54
		card.add_child(icon_tex)

	# Name label — strip at the bottom of the square area (54%–63%)
	var lbl_name := Label.new()
	lbl_name.text = "%d. %s" % [idx + 1, String(u["name"])]
	lbl_name.add_theme_font_size_override("font_size", 13)
	lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_name.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_name.anchor_left   = 0.05
	lbl_name.anchor_right  = 0.95
	lbl_name.anchor_top    = 0.54
	lbl_name.anchor_bottom = 0.63
	card.add_child(lbl_name)

	# Effect label — first text box (68%–81%)
	var lbl_effect := Label.new()
	lbl_effect.text = _effect_text(u)
	lbl_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_effect.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_effect.anchor_left   = 0.05
	lbl_effect.anchor_right  = 0.95
	lbl_effect.anchor_top    = 0.68
	lbl_effect.anchor_bottom = 0.81
	card.add_child(lbl_effect)

	# Current value label — second text box (83%–96%)
	var lbl_current := Label.new()
	lbl_current.text = _current_text(String(u["id"]))
	lbl_current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_current.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_current.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	lbl_current.anchor_left   = 0.05
	lbl_current.anchor_right  = 0.95
	lbl_current.anchor_top    = 0.83
	lbl_current.anchor_bottom = 0.96
	card.add_child(lbl_current)

	# Invisible button — full-rect click capture
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_pick.bind(idx))
	card.add_child(btn)

	return card

func _pick(idx: int) -> void:
	if idx < 0 or idx >= _current.size():
		return
	_apply(_current[idx])
	_pending -= 1
	if _pending > 0:
		_show_cards()   # next queued level-up
	else:
		_finish()

func _finish() -> void:
	_showing = false
	_root.hide()
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if not _showing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_1: _pick(0)
			KEY_2: _pick(1)
			KEY_3: _pick(2)

# ── Apply + display ─────────────────────────────────────────────────────────────
func _apply(u: Dictionary) -> void:
	var mag: float = u["mag"]
	match String(u["id"]):
		"hp":         GameManager.add_max_hp(int(mag))
		"defense":    GameManager.add_base_defense(int(mag))
		"fire_rate":  GameManager.add_fire_rate(mag)
		"move_speed": GameManager.add_move_speed(mag)
		"damage":     GameManager.add_damage(mag)
		"momentum":   GameManager.add_momentum(mag)
		"hp_regen":   GameManager.add_hp_regen(mag)
		"pickup":     GameManager.add_pickup_radius(mag)

func _effect_text(u: Dictionary) -> String:
	var mag: float = u["mag"]
	match String(u["id"]):
		"hp":       return "+%d Max HP (heal)" % int(mag)
		"defense":  return "+%d flat defense" % int(mag)
		"hp_regen": return "+%0.1f HP/sec" % mag
		_:          return "+%d%%" % int(round(mag * 100.0))

func _current_text(id: String) -> String:
	match id:
		"hp":         return "now +%d" % GameManager.upg_max_hp_bonus
		"defense":    return "now +%d" % GameManager.upg_base_defense
		"fire_rate":  return "now +%d%%" % int(round((GameManager.upg_fire_rate_mult - 1.0) * 100.0))
		"move_speed": return "now +%d%%" % int(round((GameManager.upg_move_speed_mult - 1.0) * 100.0))
		"damage":     return "now +%d%%" % int(round((GameManager.upg_damage_mult - 1.0) * 100.0))
		"momentum":   return "now +%d%%" % int(round((GameManager.upg_momentum_mult - 1.0) * 100.0))
		"hp_regen":   return "now +%0.1f/s" % GameManager.upg_hp_regen
		"pickup":     return "now +%d%%" % int(round((GameManager.upg_pickup_mult - 1.0) * 100.0))
	return ""

# ── UI build ────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	# Fixed-size panel matching lvupframe proportions (~700×384 native)
	var panel := Control.new()
	panel.custom_minimum_size = Vector2(720, 390)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	# lvupframe as panel background (full-rect)
	var panel_bg := TextureRect.new()
	panel_bg.texture = TEX_FRAME
	panel_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_bg.stretch_mode = TextureRect.STRETCH_SCALE
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(panel_bg)

	# Title label — inside the teal bar slot at the top of lvupframe (~12%–88% wide, 3.5%–15% tall)
	var title := Label.new()
	title.text = "LEVEL UP — choose an upgrade"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_font_override("font", load("res://assets/fonts/Good Old DOS.ttf"))
	title.add_theme_color_override("font_color", Color("#9bfdb0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left   = 0.0
	title.anchor_right  = 1.0
	title.anchor_top    = 0.035
	title.anchor_bottom = 0.155
	title.offset_top    = 30
	title.offset_bottom = 30
	title.offset_left   = -10
	title.offset_right  = -10
	panel.add_child(title)

	# Cards area — plain Control so we can position each card manually
	_cards_box = Control.new()
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_box.anchor_left   = 0.025
	_cards_box.anchor_right  = 0.975
	_cards_box.anchor_top    = 0.19
	_cards_box.anchor_bottom = 0.97
	panel.add_child(_cards_box)
