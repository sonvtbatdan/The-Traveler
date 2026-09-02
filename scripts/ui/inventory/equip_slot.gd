extends Panel
class_name InvEquipSlot

## One of the 10 equip slots. Accepts a dropped item only if its type matches.

var slot_name: String = ""
var _hl: Panel = null   # highlight overlay: thin white fill + green border, shown for compatible items

func setup(p_slot: String) -> void:
	slot_name = p_slot
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hl = Panel.new()
	_hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.z_index = 1   # sit over any equipped item in this slot
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.12)     # thin white mask
	sb.border_color = Color(0.3, 1.0, 0.4, 0.95) # green border hugging the slot
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	_hl.add_theme_stylebox_override("panel", sb)
	_hl.visible = false
	add_child(_hl)

## Light up (or clear) this slot — called by inventory_ui when an item is hovered/picked up.
func set_highlight(on: bool) -> void:
	if _hl != null and is_instance_valid(_hl):
		_hl.visible = on

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if GameManager.is_in_battle():
		return false   # no equipping during a boss fight
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("def_id"):
		return false
	return InventoryManager.fits_slot(String((data as Dictionary)["def_id"]), slot_name)

func _drop_data(_at: Vector2, data: Variant) -> void:
	var def_id := String((data as Dictionary)["def_id"])
	# Attribute equip-gate: block + explain (fits_slot already passed in _can_drop_data).
	if not InventoryManager.meets_requirement(def_id):
		var r := InventoryManager.item_requirement(def_id)
		_notify("Requires %s %d" % [_attr_label(String(r["attr"])), int(r["value"])])
		return
	InventoryManager.equip(int((data as Dictionary)["uid"]), slot_name)

## Surface a transient message through the owning inventory UI (group "inventory_ui").
func _notify(msg: String) -> void:
	var ui := get_tree().get_first_node_in_group("inventory_ui")
	if ui != null and ui.has_method("flash_message"):
		ui.flash_message(msg)

func _attr_label(attr: String) -> String:
	return attr.capitalize() if attr != "" else "an attribute"
