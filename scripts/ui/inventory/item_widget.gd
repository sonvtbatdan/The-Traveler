extends Control
class_name InvItemWidget

## One placed item (in the backpack or an equip slot). Source of a drag, and —
## when equipped — also a drop target so you can swap items directly onto a slot.

signal sell_requested(uid: int, def_id: String)

var uid: int = -1
var def_id: String = ""
var slot_name: String = ""   # "" = in backpack; otherwise the equip slot it sits in
var cell_size: int = 46

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
	var rarity := String(def.get("rarity", "common"))
	var col: Color = InventoryManager.RARITY_COLORS.get(rarity, Color(0.6, 0.6, 0.6))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.18, 0.95)
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

	tooltip_text = _make_tooltip(def)

## A centered, outlined name label sized to fill its parent. Used both on the
## placeholder widget and on the drag preview.
func _make_name_label(def: Dictionary) -> Label:
	var lbl := Label.new()
	lbl.text = String(def.get("name", def_id))
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

func _make_tooltip(def: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(String(def.get("name", def_id)))
	lines.append("Rarity: " + String(def.get("rarity", "common")).capitalize())
	var desc := String(def.get("desc", ""))
	if desc != "":
		lines.append(desc)
	var stats: Dictionary = def.get("stats", {})
	for k: String in stats:
		var label := k.replace("_sec", "").replace("_pct", "").replace("_", " ")
		if k.ends_with("_pct"):
			lines.append("+%s%% %s" % [str(stats[k]), label])
		else:
			lines.append("%s: %s" % [label.capitalize(), str(stats[k])])
	return "\n".join(lines)

# ── Drag source ──────────────────────────────────────────────────────────────

func _get_drag_data(at_position: Vector2) -> Variant:
	var size: Vector2i = InventoryManager.def_size(def_id)
	var grab := Vector2i.ZERO
	if slot_name == "":
		grab = Vector2i(int(at_position.x / cell_size), int(at_position.y / cell_size))
		grab.x = clampi(grab.x, 0, size.x - 1)
		grab.y = clampi(grab.y, 0, size.y - 1)

	var preview := TextureRect.new()
	preview.texture = InventoryManager.get_icon(def_id)
	preview.size = Vector2(size.x * cell_size, size.y * cell_size)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.7)
	var def: Dictionary = InventoryManager.get_def(def_id)
	if String(def.get("icon", "")) == "":
		preview.add_child(_make_name_label(def))
	var wrap := Control.new()
	wrap.add_child(preview)
	preview.position = -Vector2(grab.x * cell_size + cell_size * 0.5, grab.y * cell_size + cell_size * 0.5)
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
	InventoryManager.equip(int((data as Dictionary)["uid"]), slot_name)
