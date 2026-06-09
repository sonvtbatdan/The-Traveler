extends Panel

## Character Sheet — a compact, live read-out of the player's stats, shown beside the inventory
## (docked to the right screen edge so it never overlaps the centred loadout panel). READ-ONLY:
## it only reads existing data — GameManager (HP / armor / DR), gun_system movement constants, and
## weapon_system.estimate_dps() — and refreshes every frame while visible. It never alters anything.
## Movement/dash/regen/shield/DR rows all read GameManager's effective getters, so they reflect
## the affixes on equipped gear live.

const PANEL_W := 160.0
const PANEL_H := 620.0
const EDGE_GAP := 6.0

const COL_TITLE := Color(0.75, 0.88, 1.0)
const COL_LABEL := Color(0.62, 0.70, 0.86)
const COL_VALUE := Color(0.82, 0.95, 0.85)
const COL_NOTE  := Color(0.55, 0.61, 0.74)

# (key, display label) in display order.
const ROWS := [
	["hp",           "HP"],
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

var _font: FontFile
var _values: Dictionary = {}   # key -> value Label

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

func _build() -> void:
	var title := _mk_label("CHARACTER", 14, COL_TITLE)
	title.position = Vector2(0, 12)
	title.size = Vector2(PANEL_W, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var y := 46.0
	for r: Array in ROWS:
		var lbl := _mk_label(String(r[1]), 10, COL_LABEL)
		lbl.position = Vector2(12, y)
		lbl.size = Vector2(PANEL_W - 24, 14)
		add_child(lbl)
		var val := _mk_label("—", 13, COL_VALUE)
		val.position = Vector2(12, y + 14)
		val.size = Vector2(PANEL_W - 24, 18)
		add_child(val)
		_values[String(r[0])] = val
		y += 40.0

	var foot := _mk_label("Stats include equipped-gear affixes. Damage = per hit (min - max).", 8, COL_NOTE)
	foot.position = Vector2(10, PANEL_H - 56)
	foot.size = Vector2(PANEL_W - 20, 48)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(foot)

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh()

func _refresh() -> void:
	_values["hp"].text           = "%d / %d" % [GameManager.ship_hp, GameManager.ship_max_hp]
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

## Damage per hit as a "min - max" range (same number twice for single-damage weapons). "—" if empty.
func _dmg_text(slot: String) -> String:
	var ws := get_tree().get_first_node_in_group("weapon_system")
	if ws == null or not ws.has_method("damage_per_hit"):
		return "—"
	var r: Dictionary = ws.damage_per_hit(slot)
	if not bool(r.get("valid", false)):
		return "—"   # empty slot / not a damage weapon
	return "%d - %d" % [int(round(float(r.get("min", 0.0)))), int(round(float(r.get("max", 0.0)))) ]
