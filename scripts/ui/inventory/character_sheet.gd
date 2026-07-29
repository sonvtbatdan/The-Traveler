extends Panel

## Character Sheet — a compact, live read-out of the player's stats, shown beside the inventory
## (docked to the right screen edge). The stat rows are READ-ONLY (they read GameManager's effective
## getters, so they reflect equipped-gear affixes AND attribute bonuses live). The ATTRIBUTES section
## at the bottom is INTERACTIVE: [+] buttons spend unspent points (GameManager.spend_point) and a
## RESET button refunds them all (GameManager.reset_points).

const PANEL_W := 200.0
const PANEL_H := 760.0   # matches inventory_ui.gd's PANEL_SIZE.y — same vertical span, top-aligned
const EDGE_GAP := 6.0

const COL_TITLE := Color(0.75, 0.88, 1.0)
const COL_LABEL := Color(0.62, 0.70, 0.86)
const COL_VALUE := Color(0.82, 0.95, 0.85)
const COL_NOTE  := Color(0.55, 0.61, 0.74)
const COL_ATTR  := Color(1.0, 0.85, 0.55)   # attribute values (warm gold)

const ROW_PITCH := 32.0   # vertical px per stat row

# (key, display label) in display order.
const ROWS := [
	["hp",           "HP"],
	["ammo",         "Ammo"],
	["energy",       "Energy"],
	["armor",        "Armor"],
	["dr",           "Damage Reduction"],
	["hp_regen",     "HP Regen"],
	["energy_regen", "Energy Regen"],
	["shield",       "Shield"],
	["speed",        "Flying Speed"],
	["dash_cd",      "Dash Cooldown"],
	["dash_range",   "Dash Range"],
	["dmg_l",        "Damage/hit · Left"],
	["dmg_r",        "Damage/hit · Right"],
]

# (attribute key, display label) in display order.
const ATTR_ROWS := [
	["marksmanship",    "Marksmanship"],
	["engineering",     "Engineering"],
	["biotech",         "Biotech"],
	["maneuverability", "Maneuverability"],
]

var _font: FontFile
var _values: Dictionary = {}        # stat key -> value Label
var _attr_values: Dictionary = {}   # attribute key -> value Label
var _attr_btns: Dictionary = {}     # attribute key -> [+] Button
var _level_lbl: Label = null
var _unspent_lbl: Label = null

func _ready() -> void:
	_font = load("res://assets/fonts/Gameplay.ttf") as FontFile
	# Dock to the right screen edge, vertically centred — resolution-independent.
	anchor_left = 1.0; anchor_right = 1.0
	anchor_top = 0.5;  anchor_bottom = 0.5
	offset_left = -PANEL_W - EDGE_GAP
	offset_right = -EDGE_GAP
	offset_top = -PANEL_H * 0.5
	offset_bottom = PANEL_H * 0.5
	_style()
	_build()

func _style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.12, 0.97)
	s.set_border_width_all(2)
	s.border_color = Color(0.3, 0.4, 0.6, 0.95)
	s.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", s)

func _mk_label(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

func _mk_btn(txt: String, sz: int) -> Button:
	var b := Button.new()
	b.text = txt
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", sz)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		var shade := 0.16
		if state == "hover": shade = 0.24
		elif state == "pressed": shade = 0.10
		elif state == "disabled": shade = 0.08
		s.bg_color = Color(shade, shade + 0.03, shade + 0.08, 0.95)
		s.set_border_width_all(1)
		s.border_color = Color(0.35, 0.45, 0.65, 0.7)
		s.set_corner_radius_all(4)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.45, 0.55))
	return b

func _build() -> void:
	var title := _mk_label("CHARACTER", 14, COL_TITLE)
	title.position = Vector2(0, 8)
	title.size = Vector2(PANEL_W, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_level_lbl = _mk_label("Level 1", 11, COL_TITLE)
	_level_lbl.position = Vector2(0, 28)
	_level_lbl.size = Vector2(PANEL_W, 16)
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_level_lbl)

	# Stat rows (read-only).
	var y := 50.0
	for r: Array in ROWS:
		var lbl := _mk_label(String(r[1]), 10, COL_LABEL)
		lbl.position = Vector2(12, y)
		lbl.size = Vector2(PANEL_W - 24, 13)
		add_child(lbl)
		var val := _mk_label("—", 12, COL_VALUE)
		val.position = Vector2(12, y + 13)
		val.size = Vector2(PANEL_W - 24, 16)
		add_child(val)
		_values[String(r[0])] = val
		y += ROW_PITCH

	# ── ATTRIBUTES (interactive) ───────────────────────────────────────────────
	y += 4.0
	var ahdr := _mk_label("ATTRIBUTES", 12, COL_ATTR)
	ahdr.position = Vector2(12, y)
	ahdr.size = Vector2(110, 18)
	add_child(ahdr)
	_unspent_lbl = _mk_label("Unspent: 0", 10, COL_TITLE)
	_unspent_lbl.position = Vector2(PANEL_W - 90, y + 2)
	_unspent_lbl.size = Vector2(82, 16)
	_unspent_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_unspent_lbl)
	y += 24.0

	for r: Array in ATTR_ROWS:
		var key := String(r[0])
		var lbl := _mk_label(String(r[1]), 10, COL_LABEL)
		lbl.position = Vector2(12, y + 4)
		lbl.size = Vector2(118, 16)
		add_child(lbl)
		var val := _mk_label("0", 13, COL_ATTR)
		val.position = Vector2(132, y + 2)
		val.size = Vector2(28, 18)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(val)
		_attr_values[key] = val
		var btn := _mk_btn("+", 14)
		btn.position = Vector2(PANEL_W - 32, y)
		btn.size = Vector2(24, 22)
		btn.pressed.connect(_on_spend.bind(key))
		add_child(btn)
		_attr_btns[key] = btn
		y += 30.0

	var reset_btn := _mk_btn("RESET POINTS", 10)
	reset_btn.position = Vector2(40, y + 4)
	reset_btn.size = Vector2(PANEL_W - 80, 24)
	reset_btn.pressed.connect(GameManager.reset_points)
	add_child(reset_btn)

func _on_spend(attr: String) -> void:
	GameManager.spend_point(attr)
	_refresh()

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh()

func _refresh() -> void:
	_values["hp"].text           = "%d / %d" % [GameManager.ship_hp, GameManager.ship_max_hp]
	_values["ammo"].text         = "%d / %d" % [int(round(GameManager.ship_ammo)), int(round(GameManager.max_ammo()))]
	_values["energy"].text       = "%d / %d" % [int(round(GameManager.ship_energy)), int(round(GameManager.max_energy()))]
	_values["armor"].text        = str(GameManager.total_armor())
	_values["dr"].text           = "%.1f%%" % (GameManager.player_total_dr() * 100.0)
	_values["hp_regen"].text     = "%.1f /s" % GameManager.hp_regen_rate()
	_values["energy_regen"].text = "%.1f /s" % GameManager.energy_regen_rate()
	_values["shield"].text       = "%d" % int(round(GameManager.shield_capacity_total()))
	_values["speed"].text        = "%d px/s" % int(round(GameManager.effective_move_speed()))
	_values["dash_cd"].text      = "%.2f s" % GameManager.effective_dash_cd()
	_values["dash_range"].text   = "%d px" % int(round(GameManager.effective_dash_range()))
	_values["dmg_l"].text        = _dmg_text("primary_weapon")
	_values["dmg_r"].text        = _dmg_text("secondary_weapon")
	# Level + attributes.
	_level_lbl.text   = "Level %d" % GameManager.player_level
	_unspent_lbl.text = "Unspent: %d" % GameManager.unspent_points
	var has_pts: bool = GameManager.unspent_points > 0
	for key: String in _attr_values:
		_attr_values[key].text = str(GameManager.attr(key))
		(_attr_btns[key] as Button).disabled = not has_pts

## Damage per hit as a "min - max" range (same number twice for single-damage weapons). "—" if empty.
func _dmg_text(slot: String) -> String:
	var ws := get_tree().get_first_node_in_group("weapon_system")
	if ws == null or not ws.has_method("damage_per_hit"):
		return "—"
	var r: Dictionary = ws.damage_per_hit(slot)
	if not bool(r.get("valid", false)):
		return "—"   # empty slot / not a damage weapon
	return "%d - %d" % [int(round(float(r.get("min", 0.0)))), int(round(float(r.get("max", 0.0)))) ]
