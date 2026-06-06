extends Panel
class_name InvEquipSlot

## One of the 10 equip slots. Accepts a dropped item only if its type matches.

var slot_name: String = ""

func setup(p_slot: String) -> void:
	slot_name = p_slot
	mouse_filter = Control.MOUSE_FILTER_STOP

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("def_id"):
		return false
	return InventoryManager.fits_slot(String((data as Dictionary)["def_id"]), slot_name)

func _drop_data(_at: Vector2, data: Variant) -> void:
	InventoryManager.equip(int((data as Dictionary)["uid"]), slot_name)
