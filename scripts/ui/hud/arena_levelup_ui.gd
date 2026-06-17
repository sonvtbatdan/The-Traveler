extends CanvasLayer
## Vampire-Survivors level-up flow. When GameManager emits `leveled_up`, pause the game and show 3 random
## upgrade cards; picking one applies a PlayerStats bonus (GameManager.add_*) and resumes. Multiple level-ups
## from one XP gain queue up (shown one after another). CanvasLayer layer 100 + PROCESS_MODE_ALWAYS so it
## runs while the tree is paused. Reuses GameManager's XP/level + stat store — no parallel progression.

# ── UPGRADE POOL (magnitudes — balance here) ────────────────────────────────────
const UPGRADES := [
	{"id": "hp",         "name": "Max HP",        "mag": 20.0},   # flat +HP (and heal)
	{"id": "defense",    "name": "Armor Plating", "mag": 2.0},    # flat damage reduction
	{"id": "fire_rate",  "name": "Fire Rate",     "mag": 0.08},   # +%
	{"id": "move_speed", "name": "Thrusters",     "mag": 0.06},   # +%
	{"id": "damage",     "name": "Damage",        "mag": 0.10},   # +%
	{"id": "momentum",   "name": "Momentum",      "mag": 0.10},   # +%
	{"id": "hp_regen",    "name": "Repair Drones",   "mag": 0.5},   # +HP/sec
	{"id": "pickup",      "name": "Magnet",          "mag": 0.15},  # +% pickup radius
	{"id": "crit_chance", "name": "Critical Strike", "mag": 0.05},  # +5% crit chance
	{"id": "crit_damage", "name": "Lethality",       "mag": 0.25},  # +25% crit damage multiplier
]
const CHOICES := 3

var _pending: int = 0
var _showing: bool = false
var _root: Control = null
var _cards_box: HBoxContainer = null
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
	# Pick CHOICES distinct upgrades.
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	_current = pool.slice(0, CHOICES)
	for c in _cards_box.get_children():
		c.queue_free()
	var i := 0
	for u: Dictionary in _current:
		var idx := i
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 130)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.text = "%d. %s\n\n%s\n%s" % [idx + 1, String(u["name"]), _effect_text(u), _current_text(String(u["id"]))]
		b.pressed.connect(_pick.bind(idx))
		_cards_box.add_child(b)
		i += 1
	_root.show()

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
		"crit_chance": GameManager.add_crit_chance(mag)
		"crit_damage": GameManager.add_crit_damage(mag)

func _effect_text(u: Dictionary) -> String:
	var mag: float = u["mag"]
	match String(u["id"]):
		"hp":          return "+%d Max HP (heal)" % int(mag)
		"defense":     return "+%d flat defense" % int(mag)
		"hp_regen":    return "+%0.1f HP/sec" % mag
		"crit_chance": return "+%d%% crit chance" % int(round(mag * 100.0))
		"crit_damage": return "+%d%% crit damage" % int(round(mag * 100.0))
		_:             return "+%d%%" % int(round(mag * 100.0))

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
		"crit_chance": return "now %d%%" % int(round(GameManager.get_crit_chance() * 100.0))
		"crit_damage": return "now %d%% dmg" % int(round(GameManager.upg_crit_damage * 100.0))
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
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to the (paused) game behind
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "LEVEL UP — choose an upgrade"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 12)
	vb.add_child(_cards_box)
