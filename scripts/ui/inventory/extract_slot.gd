extends Panel
class_name InvExtractSlot

## "Extract & Dispose" — a drop target in the inventory panel (2026-08-25, on request: "làm một ô slot có
## tên là Extract & Dispose. Kéo vũ khí vào đây sẽ xóa vũ khí đó và +5 gold").
##
## Drop any item on it and — since 2026-08-29 (on request: "khi kéo vào sẽ hiện bảng prompt: 'This will
## destroy item' và tùy chọn Yes / No. Chọn Yes sẽ extract lấy coin... Chọn No thì đặt vũ khí về vị trí cũ") —
## a confirm dialog pops up before anything actually happens. Routed through inventory_ui.gd's
## _on_sell_requested()/_sell_dialog, the SAME confirm the right-click path already used — so wording and the
## payout (InventoryManager.get_sell_price(), no longer a flat amount) can never disagree between the two
## routes. "No"/closing the dialog does nothing at all: the drop never touched the item in the first place
## (Godot's own drag-drop preview just resets), so it's already exactly "back where it was" with zero code
## needed for that half.
##
## Deliberately NOT gated on GameManager.is_in_battle() the way InvEquipSlot is: that gate exists to stop
## loadout changes mid-boss-fight, and scrapping an item doesn't alter the loadout — it only removes a
## backpack item. Dropping an EQUIPPED item still works (sell_item unequips first), which mirrors the
## right-click path exactly.

const LABEL_TEXT := "Extract\n& Dispose"

var _hl: Panel = null      # hover highlight, same treatment InvEquipSlot uses
var _lbl: Label = null

func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drop an item here to destroy it for %d$." % InventoryManager.EXTRACT_PAYOUT

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.06, 0.06, 0.9)      # dim red — a destructive target, visually distinct from equip slots
	sb.border_color = Color(0.75, 0.25, 0.2, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", sb)

	_lbl = Label.new()
	_lbl.text = LABEL_TEXT
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl.add_theme_font_size_override("font_size", 11)
	_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.65))
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_lbl)

	_hl = Panel.new()
	_hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.z_index = 1
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(1.0, 0.3, 0.2, 0.18)
	hsb.border_color = Color(1.0, 0.45, 0.3, 0.95)
	hsb.set_border_width_all(2)
	hsb.set_corner_radius_all(0)
	_hl.add_theme_stylebox_override("panel", hsb)
	_hl.visible = false
	add_child(_hl)

## Lit whenever a drag is in flight — every item is a valid target here, so unlike an equip slot there is no
## per-item compatibility test to run. Called by inventory_ui's own drag-highlight sweep.
func set_highlight(on: bool) -> void:
	if _hl != null and is_instance_valid(_hl):
		_hl.visible = on

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY \
		and (data as Dictionary).has("uid") \
		and int((data as Dictionary)["uid"]) != -1

func _drop_data(_at: Vector2, data: Variant) -> void:
	var d: Dictionary = data
	var uid := int(d["uid"])
	if uid == -1:
		return
	var def_id := String(d.get("def_id", ""))
	var ui := get_tree().get_first_node_in_group("inventory_ui")
	if ui == null or not ui.has_method("_on_sell_requested"):
		return   # can't confirm — refuse rather than silently destroying without asking
	ui._on_sell_requested(uid, def_id)
