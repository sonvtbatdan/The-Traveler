extends Panel

const ASSET_BASE := "res://assets/weaponry/"

const STAT_ICONS: Dictionary = {
	"metal":    "res://assets/stat/metal.png",
	"nonmetal": "res://assets/stat/non-metal.png",
	"organic":  "res://assets/stat/organic.png",
	"liquid":   "res://assets/stat/Liquid.png",
}
const COST_KEY_ORDER: Array = ["metal", "nonmetal", "organic", "liquid"]

var _cost_textures: Dictionary = {}

func _fmt_cost_num(n: int) -> String:
	if n < 1000: return str(n)
	if n < 1000000: return "%dk" % (n / 1000)
	if n < 1000000000: return "%dM" % (n / 1000000)
	return "%dB" % (n / 1000000000)

func _ensure_cost_textures() -> void:
	if not _cost_textures.is_empty():
		return
	for key: String in STAT_ICONS:
		var raw := load(STAT_ICONS[key]) as Texture2D
		if raw:
			var img := raw.get_image().duplicate()
			img.resize(12, 12, Image.INTERPOLATE_BILINEAR)
			_cost_textures[key] = ImageTexture.create_from_image(img)

const WEAPON_ORDER: Array[String] = [
	"gun", "turret", "lightning_emitter", "wing", "railgun",
	"left_canon_heavy_bolt", "plasma_gun", "homing_missile",
	"anti_matter_canon", "omega_system",
]

var _list_vbox: VBoxContainer = null
var _tooltip:   PanelContainer = null
var _tooltip_lbl: RichTextLabel = null

func _ready() -> void:
	_ensure_cost_textures()
	_apply_style()
	_build_tooltip()
	_build_chrome()
	WeaponManager.catalog_updated.connect(_rebuild)
	WeaponManager.weapon_purchased.connect(func(_a, _b): _refresh_all_rows())
	WeaponManager.weapons_reset.connect(_refresh_all_rows)
	MaterialManager.materials_changed.connect(_refresh_all_rows)
	if not WeaponManager.WEAPONS.is_empty():
		_rebuild()

# ── Style ──────────────────────────────────────────────────────────────────

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left = 2; s.border_width_right  = 2
	s.border_width_top  = 2; s.border_width_bottom = 2
	s.border_color = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

# ── Tooltip ────────────────────────────────────────────────────────────────

func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.z_index = 200
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.04, 0.05, 0.10, 0.96)
	ts.border_width_left = 1; ts.border_width_right  = 1
	ts.border_width_top  = 1; ts.border_width_bottom = 1
	ts.border_color = Color(0.35, 0.50, 0.75, 0.9)
	ts.corner_radius_top_left     = 5; ts.corner_radius_top_right    = 5
	ts.corner_radius_bottom_left  = 5; ts.corner_radius_bottom_right = 5
	ts.content_margin_left = 8; ts.content_margin_right  = 8
	ts.content_margin_top  = 6; ts.content_margin_bottom = 6
	_tooltip.add_theme_stylebox_override("panel", ts)
	_tooltip_lbl = RichTextLabel.new()
	_tooltip_lbl.bbcode_enabled = true
	_tooltip_lbl.fit_content = true
	_tooltip_lbl.custom_minimum_size = Vector2(180, 0)
	_tooltip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_lbl.add_theme_font_size_override("normal_font_size", 10)
	_tooltip_lbl.add_theme_font_size_override("bold_font_size", 10)
	_tooltip_lbl.add_theme_font_size_override("italics_font_size", 10)
	_tooltip_lbl.add_theme_font_size_override("bold_italics_font_size", 10)
	var _gf := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if _gf:
		_tooltip_lbl.add_theme_font_override("bold_font", _gf)
	var sys_italic := SystemFont.new()
	sys_italic.font_italic = true
	_tooltip_lbl.add_theme_font_override("italics_font", sys_italic)
	_tooltip.add_child(_tooltip_lbl)
	add_child(_tooltip)

# ── Static chrome (title + scroll wrapper) ────────────────────────────────

func _build_chrome() -> void:
	var title := Label.new()
	title.text = "WEAPONRY"
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
	scroll.offset_top  = 26
	scroll.offset_left = 4; scroll.offset_right = -4; scroll.offset_bottom = -4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(_list_vbox)

# ── Build / rebuild list ──────────────────────────────────────────────────

func _rebuild() -> void:
	for c in _list_vbox.get_children():
		c.queue_free()
	for id: String in WEAPON_ORDER:
		if WeaponManager.WEAPONS.has(id):
			_list_vbox.add_child(_make_row(id))
	for id: String in WeaponManager.WEAPONS:
		if not WEAPON_ORDER.has(id):
			_list_vbox.add_child(_make_row(id))

func _make_row(weapon_id: String) -> Control:
	var data: Dictionary = WeaponManager.WEAPONS[weapon_id]
	var side_only: String = data.get("side_only", "")
	var tiers: Array = data.get("tiers", [])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, 36)
	row.set_meta("weapon_id", weapon_id)

	# Thumbnail (tier-0 asset)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(32, 32)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not tiers.is_empty():
		var tex := load(ASSET_BASE + tiers[0]) as Texture2D
		if tex:
			thumb.texture = tex
	row.add_child(thumb)
	row.set_meta("thumb", thumb)

	var cost_box := HBoxContainer.new()
	cost_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_box.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_box.add_theme_constant_override("separation", 2)
	cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cost_box)
	row.set_meta("cost_box", cost_box)

	var cost_lbls: Dictionary = {}
	for key: String in COST_KEY_ORDER:
		var ci := TextureRect.new()
		ci.custom_minimum_size = Vector2(12, 12)
		ci.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _cost_textures.has(key):
			ci.texture = _cost_textures[key]
		cost_box.add_child(ci)
		var cl := Label.new()
		cl.add_theme_font_size_override("font_size", 8)
		cl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_box.add_child(cl)
		cost_lbls[key] = cl
	row.set_meta("cost_lbls", cost_lbls)

	if side_only == "C":
		var c_btn := _make_side_btn("C")
		row.add_child(c_btn)
		row.set_meta("c_btn", c_btn)
		c_btn.pressed.connect(_on_buy.bind(weapon_id, "C"))
	else:
		var l_btn := _make_side_btn("L")
		if side_only == "R":
			l_btn.disabled = true; l_btn.modulate.a = 0.25
		row.add_child(l_btn)
		row.set_meta("l_btn", l_btn)

		var r_btn := _make_side_btn("R")
		if side_only == "L":
			r_btn.disabled = true; r_btn.modulate.a = 0.25
		row.add_child(r_btn)
		row.set_meta("r_btn", r_btn)

		l_btn.pressed.connect(_on_buy.bind(weapon_id, "L"))
		r_btn.pressed.connect(_on_buy.bind(weapon_id, "R"))

	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(_on_row_hover.bind(weapon_id, row))
	row.mouse_exited.connect(func(): _tooltip.visible = false)

	_update_row(row, weapon_id)
	return row

func _make_side_btn(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(30, 26)
	btn.add_theme_font_size_override("font_size", 10)
	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = bc
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.content_margin_top = 2; s.content_margin_bottom = 2
		return s
	btn.add_theme_stylebox_override("normal",  mk.call(Color(0.09,0.12,0.20,0.9), Color(0.30,0.50,0.80,0.7)))
	btn.add_theme_stylebox_override("hover",   mk.call(Color(0.16,0.22,0.35,0.9), Color(0.50,0.70,1.00,0.9)))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.06,0.08,0.14,0.9), Color(0.30,0.50,0.80,0.7)))
	btn.add_theme_stylebox_override("focus",   mk.call(Color(0.09,0.12,0.20,0.9), Color(0.30,0.50,0.80,0.7)))
	return btn

# ── Row updates ───────────────────────────────────────────────────────────

func _refresh_all_rows() -> void:
	for row in _list_vbox.get_children():
		if row.has_meta("weapon_id"):
			_update_row(row, row.get_meta("weapon_id"))

func _update_row(row: Control, weapon_id: String) -> void:
	var data: Dictionary  = WeaponManager.WEAPONS.get(weapon_id, {})
	var tiers: Array      = data.get("tiers", [])
	var side_only: String = data.get("side_only", "")

	var sides: Array = ["C"] if side_only == "C" else ["L", "R"]
	for side: String in sides:
		var btn_meta: String = side.to_lower() + "_btn"
		if not row.has_meta(btn_meta):
			continue
		var btn: Button = row.get_meta(btn_meta)
		if side_only != "" and side_only != "C" and side != side_only:
			continue
		var cur: int  = WeaponManager.get_tier(weapon_id, side)
		var next: int = cur + 1
		var maxed: bool = cur >= tiers.size() - 1 and cur >= 0

		if maxed:
			btn.text     = "✓"
			btn.disabled = true
			btn.modulate = Color(0.4, 1.0, 0.5, 0.9)
		elif WeaponManager.can_purchase(weapon_id, side):
			btn.text     = ("MK%d" % (next + 1)) if next > 0 else side
			btn.disabled = false
			btn.modulate = Color.WHITE
		else:
			btn.text     = side
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0.35)

	# Thumbnail + cost display
	var hi_tier: int
	if side_only == "C":
		hi_tier = WeaponManager.get_tier(weapon_id, "C")
	else:
		hi_tier = maxi(WeaponManager.get_tier(weapon_id, "L"), WeaponManager.get_tier(weapon_id, "R"))
	if hi_tier >= 0 and hi_tier < tiers.size():
		var thumb: TextureRect = row.get_meta("thumb")
		var tex := load(ASSET_BASE + tiers[hi_tier]) as Texture2D
		if tex:
			thumb.texture = tex

	var next_tier := hi_tier + 1
	var is_maxed: bool = next_tier >= tiers.size() and hi_tier >= 0
	if row.has_meta("cost_box") and row.has_meta("cost_lbls"):
		var cost_box: Control = row.get_meta("cost_box")
		var cost_lbls: Dictionary = row.get_meta("cost_lbls")
		if is_maxed:
			cost_box.visible = false
		else:
			var next_cost := WeaponManager.get_tier_cost(weapon_id, next_tier)
			cost_box.visible = true
			for key: String in COST_KEY_ORDER:
				var cl: Label = cost_lbls[key]
				var v: int = next_cost.get(key, 0)
				cl.text = _fmt_cost_num(v)
				var has_enough: bool
				match key:
					"metal":    has_enough = MaterialManager.metal    >= v
					"nonmetal": has_enough = MaterialManager.nonmetal >= v
					"organic":  has_enough = MaterialManager.organic  >= v
					"liquid":   has_enough = MaterialManager.liquid   >= v
					_:          has_enough = true
				cl.add_theme_color_override("font_color",
					Color(0.4, 0.9, 0.45) if has_enough else Color(0.9, 0.35, 0.35))

	# Dim row if nothing can be purchased and not maxed
	var is_any_buyable := false
	for s: String in sides:
		if side_only != "" and side_only != "C" and s != side_only:
			continue
		if WeaponManager.can_purchase(weapon_id, s):
			is_any_buyable = true
			break
	row.modulate = Color.WHITE if (is_any_buyable or is_maxed) else Color(0.45, 0.45, 0.5, 0.7)


# ── Callbacks ─────────────────────────────────────────────────────────────

func _on_buy(weapon_id: String, side: String) -> void:
	WeaponManager.purchase(weapon_id, side)

func _on_row_hover(weapon_id: String, row: Control) -> void:
	var data: Dictionary = WeaponManager.WEAPONS.get(weapon_id, {})
	var name_str: String = data.get("name", weapon_id)
	var desc: String     = data.get("desc", "")
	_tooltip_lbl.text = "[color=#ffdd44][b]%s[/b][/color]" % name_str
	if not desc.is_empty():
		_tooltip_lbl.text += "\n[i]%s[/i]" % desc
	_tooltip.visible = true
	var rp := row.global_position
	_tooltip.global_position = Vector2(rp.x + row.size.x + 4, rp.y)
