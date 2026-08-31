extends Panel
class_name InvLiveSlot

## One WEAPONS/AUX row slot in the Inventory screen. Icon/level content is filled in by
## inventory_ui.gd (_fill_readonly_slot); this script only adds drag-drop: dropping a Cargo item here
## swaps it into the live arena_weapons/arena_aux run state at this slot index. An empty slot (index
## >= the live count) just acquires the dropped kind; an occupied weapon slot replaces it outright.
## Occupied AUX slots can't be replaced — arena_aux.gd's effects are additive deltas with no "undo",
## so swapping OUT an owned aux would leave its old stats stuck. Cargo items reaching this slot come from
## level-ups, the start-of-run chest, Elite/Champion drops (arena_item_drop.gd) and boss salvage — the old
## silent creep-kill field drop is disabled, see MetaManager.roll_field_drop's header.

var row_kind: String = ""   # "weapon" | "aux"
var slot_index: int = -1
var _hl: Panel = null

func setup(p_row_kind: String, p_index: int) -> void:
	row_kind = p_row_kind
	slot_index = p_index
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hl = Panel.new()
	_hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.z_index = 2
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	sb.border_color = Color(0.3, 1.0, 0.4, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_hl.add_theme_stylebox_override("panel", sb)
	_hl.visible = false
	add_child(_hl)

func set_highlight(on: bool) -> void:
	if _hl != null and is_instance_valid(_hl):
		_hl.visible = on

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if GameManager.is_in_battle():
		return false
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("def_id"):
		return false
	var def_id := String((data as Dictionary)["def_id"])
	if row_kind == "weapon":
		return _kind_for_weapon_def(def_id) != ""
	return def_id.begins_with("aux_")

func _drop_data(_at: Vector2, data: Variant) -> void:
	var def_id := String((data as Dictionary)["def_id"])
	var uid := int((data as Dictionary)["uid"])
	if row_kind == "weapon":
		_drop_weapon(def_id, uid)
	else:
		_drop_aux(def_id, uid)

func _kind_for_weapon_def(def_id: String) -> String:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw == null or not aw.has_method("kind_for_def_id"):
		return ""
	return String(aw.call("kind_for_def_id", def_id))

func _drop_weapon(def_id: String, uid: int) -> void:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw == null:
		return
	var kind := _kind_for_weapon_def(def_id)
	if kind == "":
		return
	var acquired: Array = aw.call("acquired_weapons")
	if kind in acquired:
		_notify("Already carrying that weapon")
		return
	var ok: bool
	if slot_index < acquired.size():
		ok = bool(aw.call("replace_weapon_at", slot_index, kind))
	else:
		ok = bool(aw.call("acquire_weapon", kind))
	if ok:
		InventoryManager.remove_item(uid)

func _drop_aux(def_id: String, uid: int) -> void:
	var ax := get_tree().get_first_node_in_group("arena_aux")
	if ax == null:
		return
	var id := def_id.substr(4)   # strip the "aux_" def_id prefix
	var owned: Array = ax.call("owned_aux")
	if id in owned:
		_notify("Already carrying that aux")
		return
	if slot_index < owned.size():
		_notify("Can't replace an owned aux — drop it into an empty AUX slot instead")
		return
	if bool(ax.call("acquire_aux", id)):
		InventoryManager.remove_item(uid)

func _notify(msg: String) -> void:
	var ui := get_tree().get_first_node_in_group("inventory_ui")
	if ui != null and ui.has_method("flash_message"):
		ui.flash_message(msg)
