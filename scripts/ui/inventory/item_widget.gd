extends Control
class_name InvItemWidget

## One placed item (in the backpack or an equip slot). Source of a drag, and —
## when equipped — also a drop target so you can swap items directly onto a slot.

signal sell_requested(uid: int, def_id: String)

var uid: int = -1
var def_id: String = ""
var slot_name: String = ""   # "" = in backpack; otherwise the equip slot it sits in
var cell_size: int = 46

# ── D2 hover tooltip — colours / sizes / which stats (tweak here) ──────────────
const TT_NAME_COLOR  := Color(0.95, 0.86, 0.50)   # name fallback (overridden by rarity colour)
const TT_BASE_COLOR  := Color(0.86, 0.89, 0.95)   # base-stat lines (white-ish)
const TT_AFFIX_COLOR := Color(0.45, 0.65, 1.00)   # affix lines (D2 blue)
const TT_SEP_COLOR   := Color(0.35, 0.40, 0.52)
const TT_BG          := Color(0.05, 0.06, 0.09, 0.97)
const TT_BORDER      := Color(0.30, 0.40, 0.60)
const TT_NAME_SIZE   := 14
const TT_TEXT_SIZE   := 12
const TT_MIN_WIDTH   := 190.0
# Affix id → human label for the effect lines (fallback = prettified id).
const TT_AFFIX_LABEL := {
	"damage_flat": "Damage", "damage_percentage": "Damage", "fire_rate": "Fire Rate",
	"crit_chance": "Crit Chance", "crit_damage": "Crit Damage", "armor_penetration": "Armor Pen",
	"poison": "Poison DPS", "slow": "Slow", "freeze": "Freeze", "burn": "Burn DPS",
	"multishot": "Multishot", "pierce": "Pierce", "ricochet": "Ricochet",
	"splash_radius": "Splash Radius", "knockback": "Knockback", "projectile_speed": "Projectile Speed",
	"energy_consumption_percentage": "Energy Cost", "energy_leech": "Energy Leech",
	"hp_leech": "Life Leech", "shield_leech": "Shield Leech",
	"energy_regen_flat": "Energy Regen", "energy_regen_percentage": "Energy Regen",
}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		sell_requested.emit(uid, def_id)
		accept_event()

func setup(p_uid: int, p_def_id: String, p_cell_size: int, p_slot: String = "") -> void:
	uid = p_uid
	def_id = p_def_id
	cell_size = p_cell_size
	slot_name = p_slot
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var def: Dictionary = InventoryManager.get_def(def_id)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = InventoryManager.item_display_color(uid)   # white = no affixes, blue = affixed
	var sb := StyleBoxFlat.new()
	var tags: Array = def.get("tags", [])
	sb.bg_color = Color("#e4712a") if "weapon" in tags else Color("#4e5568")
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	bg.add_theme_stylebox_override("panel", sb)
	add_child(bg)

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3; icon.offset_top = 3
	icon.offset_right = -3; icon.offset_bottom = -3
	icon.texture = InventoryManager.get_icon(def_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

	# No real art → write the item's name on the placeholder so the blocks are
	# distinguishable. (Once "icon" points at real art, this label is skipped.)
	if String(def.get("icon", "")) == "":
		add_child(_make_name_label(def))

	# Non-empty so the hover fires; the actual box is built in _make_custom_tooltip().
	tooltip_text = _display_name()

## Rolled display name ("[Prefix] Base [After-fix]") if this instance has affixes,
## else the plain base name.
func _display_name() -> String:
	var n := InventoryManager.item_display_name(uid)
	return n if n != "" else String(InventoryManager.get_def(def_id).get("name", def_id))

## A centered, outlined name label sized to fill its parent. Used both on the
## placeholder widget and on the drag preview.
func _make_name_label(def: Dictionary) -> Label:
	var lbl := Label.new()
	lbl.text = _display_name()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.clip_text = true
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl

# ── Diablo-2 styled hover tooltip ─────────────────────────────────────────────
## Godot calls this on hover (because tooltip_text is non-empty) and shows the
## returned Control near the cursor, hiding it on move-off. Layout: rolled name →
## base stats (this item's real Damage after the hidden ±20% roll + Fire rate) →
## separator → affix lines (blue). No affixes → just name + base stats.
func _make_custom_tooltip(_for_text: String) -> Object:
	var def: Dictionary = InventoryManager.get_def(def_id)
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	var disp_col: Color = InventoryManager.item_display_color(uid)   # white = no affixes, blue = affixed

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TT_BG
	sb.border_color = disp_col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.custom_minimum_size = Vector2(TT_MIN_WIDTH, 0)
	panel.add_child(vb)

	# Name (white = no affixes, blue = affixed)
	vb.add_child(_tt_label(_display_name(), disp_col, TT_NAME_SIZE, font))

	# Base stats — this item's real numbers (damage already includes the hidden ±20%).
	var bm := InventoryManager.item_base_mult(uid)
	var dmg_line := _tt_damage_line(def, bm)
	if dmg_line != "":
		vb.add_child(_tt_label(dmg_line, TT_BASE_COLOR, TT_TEXT_SIZE, font))
	var cad_line := _tt_cadence_line(def)
	if cad_line != "":
		vb.add_child(_tt_label(cad_line, TT_BASE_COLOR, TT_TEXT_SIZE, font))
	var hull_line := _tt_hull_line(def)
	if hull_line != "":
		vb.add_child(_tt_label(hull_line, TT_BASE_COLOR, TT_TEXT_SIZE, font))

	# Attribute requirement — red when the character doesn't meet it, green when met.
	var req := InventoryManager.item_requirement(def_id)
	if String(req["attr"]) != "":
		var req_ok := InventoryManager.meets_requirement(def_id)
		var req_col := Color(0.55, 1.0, 0.55) if req_ok else Color(1.0, 0.40, 0.40)
		vb.add_child(_tt_label("Requires %s %d" % [String(req["attr"]).capitalize(), int(req["value"])], req_col, TT_TEXT_SIZE, font))

	# Affixes (one per line, blue), with a separator above them.
	var affixes: Array = InventoryManager.item_affixes(uid)
	if not affixes.is_empty():
		var sep := HSeparator.new()
		var ss := StyleBoxLine.new()
		ss.color = TT_SEP_COLOR
		ss.thickness = 1
		sep.add_theme_stylebox_override("separator", ss)
		vb.add_child(sep)
		for a: Dictionary in affixes:
			vb.add_child(_tt_label(_tt_affix_text(a), TT_AFFIX_COLOR, TT_TEXT_SIZE, font))
	return panel

func _tt_label(text: String, color: Color, size: int, font: FontFile) -> Label:
	var l := Label.new()
	l.text = text
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Base-damage line for the weapon's real damage stat × the hidden base roll.
func _tt_damage_line(def: Dictionary, bm: float) -> String:
	var s: Dictionary = def.get("stats", {})
	if s.has("damage"):
		return "Damage: %d" % roundi(float(s["damage"]) * bm)
	if s.has("damage_min") and s.has("damage_max"):
		return "Damage: %d–%d /tick" % [roundi(float(s["damage_min"]) * bm), roundi(float(s["damage_max"]) * bm)]
	if s.has("damage_per_tick"):
		return "Damage: %d /tick" % roundi(float(s["damage_per_tick"]) * bm)
	if s.has("dps"):
		return "DPS: %d" % roundi(float(s["dps"]) * bm)
	return ""

## Hull bonus-HP / armor line (this instance's rolled ±20% values). "" for non-hulls.
func _tt_hull_line(def: Dictionary) -> String:
	if not Array(def.get("tags", [])).has("hull"):
		return ""
	var parts: Array[String] = []
	var hp := InventoryManager.hull_bonus_hp(uid)
	if hp != 0:
		parts.append("Bonus HP: +%d" % hp)
	var armor := InventoryManager.hull_armor(uid)
	if armor != 0:
		parts.append("Armor: %d" % armor)
	return "  ·  ".join(parts)

## Fire-rate / cadence line (omitted for always-on weapons with no cadence stat).
func _tt_cadence_line(def: Dictionary) -> String:
	var s: Dictionary = def.get("stats", {})
	if s.has("cooldown_sec") and float(s["cooldown_sec"]) > 0.0:
		return "Fire rate: %.1f/s" % (1.0 / float(s["cooldown_sec"]))
	if s.has("tick_interval_sec") and float(s["tick_interval_sec"]) > 0.0:
		return "Tick rate: %.1f/s" % (1.0 / float(s["tick_interval_sec"]))
	return ""

## One affix effect line, e.g. "+45% Damage", "-30% Energy Cost", "+30/s Poison DPS".
func _tt_affix_text(a: Dictionary) -> String:
	var id := String(a.get("id", ""))
	var val := float(a.get("value", 0.0))
	var ad: Dictionary = AffixManager.get_affix(id)
	var unit := String(ad.get("unit", ""))
	var label := String(TT_AFFIX_LABEL.get(id, id.replace("_", " ").capitalize()))
	var us := "%" if unit == "%" else ("/s" if unit == "flat/s" else "")
	return "%+d%s %s" % [roundi(val), us, label]

# ── Drag source ──────────────────────────────────────────────────────────────

func _get_drag_data(at_position: Vector2) -> Variant:
	var size: Vector2i = InventoryManager.def_size(def_id)
	var grab := Vector2i.ZERO
	if slot_name == "":
		grab = Vector2i(int(at_position.x / cell_size), int(at_position.y / cell_size))
		grab.x = clampi(grab.x, 0, size.x - 1)
		grab.y = clampi(grab.y, 0, size.y - 1)

	var padding := 3
	var box := Vector2(size.x * cell_size - padding * 2, size.y * cell_size - padding * 2)
	var def: Dictionary = InventoryManager.get_def(def_id)
	var tex: Texture2D = InventoryManager.get_icon(def_id)

	# Reproduce exactly how the placeholder shows the art: the icon TextureRect uses
	# KEEP_ASPECT_CENTERED inside the padded cell box, so the visible image is the
	# texture aspect-fitted (NOT the full box). Compute that displayed size + offset
	# and bake it into the preview so the drag ghost matches the placeholder 1:1.
	var disp := box
	if tex != null and String(def.get("icon", "")) != "":
		var ts := tex.get_size()
		if ts.x > 0 and ts.y > 0:
			var s := minf(box.x / ts.x, box.y / ts.y)
			disp = ts * s
	var img_pos := Vector2(padding, padding) + (box - disp) * 0.5  # image top-left within widget

	var preview := TextureRect.new()
	preview.texture = tex
	# expand_mode MUST be set before size: with the default EXPAND_KEEP_SIZE the
	# control's minimum size = the texture's native size, and the size setter
	# clamps to that minimum — large icons would lock the preview at full size.
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.size = disp
	preview.modulate = Color(1, 1, 1, 0.7)
	if String(def.get("icon", "")) == "":
		preview.add_child(_make_name_label(def))

	var wrap := Control.new()
	wrap.add_child(preview)
	# Offset so the cursor stays exactly where it grabbed the item (at_position in widget space).
	preview.position = img_pos - at_position
	set_drag_preview(wrap)

	modulate = Color(1, 1, 1, 0.35)
	return {"uid": uid, "def_id": def_id, "grab": grab, "slot": slot_name}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate = Color(1, 1, 1, 1)

# ── Drop target (only when equipped — enables swapping onto an occupied slot) ──

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if slot_name == "":
		return false  # backpack items: let the grid underneath handle the drop
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("def_id"):
		return false
	return InventoryManager.fits_slot(String((data as Dictionary)["def_id"]), slot_name)

func _drop_data(_at: Vector2, data: Variant) -> void:
	var def_id := String((data as Dictionary)["def_id"])
	if not InventoryManager.meets_requirement(def_id):
		var r := InventoryManager.item_requirement(def_id)
		var ui := get_tree().get_first_node_in_group("inventory_ui")
		if ui != null and ui.has_method("flash_message"):
			var attr := String(r["attr"])
			var label := attr.capitalize() if attr != "" else "an attribute"
			ui.flash_message("Requires %s %d" % [label, int(r["value"])])
		return
	InventoryManager.equip(int((data as Dictionary)["uid"]), slot_name)
