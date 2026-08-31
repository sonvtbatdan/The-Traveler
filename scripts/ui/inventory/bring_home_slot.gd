extends Panel
class_name InvBringHomeSlot

## "Bring Home" — a drop target in the inventory panel (2026-08-29, on request: "làm thêm 1 ô bên cạnh ô
## extract... Đặt tên là 'Bring Home'... Kéo vũ khí vào đây sẽ mang được về dock").
##
## Weapon-only (blueprints/Merchant purchase are a weapon-tab concept — staging one for a gear item would be
## a no-op, since hub_screen.gd's gear tabs never blueprint-gate at all) and excludes craft-only uniques
## (fragment-assembled, no blueprint/buy_weapon path to unlock in the first place). Drop calls
## MetaManager.stage_bring_home(uid, def_id), which pulls the item out of Cargo into
## InventoryManager's own "bring_home" where (see that function's doc comment for the swap-one-at-a-time
## shape, same as an equip slot) and stages its blueprint. The actual item display + drag-back-out support is
## handled centrally by inventory_ui.gd's _rebuild(), the same way it renders the 3 GEAR equip slots — this
## slot is only the drop target, not the renderer.
##
## Risk framing lives entirely in MetaManager/arena.gd: the item (and its blueprint) only truly comes home if
## this run ends in victory; dying first loses the physical item too, not just the blueprint. See
## bring_home_uid's own doc comment in meta_manager.gd.

const LABEL_TEXT := "Bring\nHome"

var _hl: Panel = null
var _lbl: Label = null

func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drop a weapon here to bring it (and its blueprint) home — only if you finish the run."

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.16, 0.07, 0.9)      # dim green — mirrors extract_slot.gd's red, opposite intent
	sb.border_color = Color(0.25, 0.8, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)

	_lbl = Label.new()
	_lbl.text = LABEL_TEXT
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl.add_theme_font_size_override("font_size", 11)
	_lbl.add_theme_color_override("font_color", Color(0.7, 0.95, 0.65))
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_lbl)

	_hl = Panel.new()
	_hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.z_index = 1
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.2, 1.0, 0.3, 0.18)
	hsb.border_color = Color(0.3, 1.0, 0.45, 0.95)
	hsb.set_border_width_all(2)
	hsb.set_corner_radius_all(4)
	_hl.add_theme_stylebox_override("panel", hsb)
	_hl.visible = false
	add_child(_hl)

## Lit whenever a drag is in flight AND the dragged item is a real, non-unique weapon — called by
## inventory_ui's own drag-highlight sweep, same convention as every other slot type.
func set_highlight(on: bool) -> void:
	if _hl != null and is_instance_valid(_hl):
		_hl.visible = on

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	if not d.has("uid") or int(d["uid"]) == -1 or not d.has("def_id"):
		return false
	return _is_eligible(String(d["def_id"]))

func _drop_data(_at: Vector2, data: Variant) -> void:
	var d: Dictionary = data
	var uid := int(d["uid"])
	var def_id := String(d["def_id"])
	if uid == -1 or not _is_eligible(def_id):
		return
	MetaManager.stage_bring_home(uid, def_id)

## Weapon-tagged, non-unique — the only defs blueprint_price()/has_blueprint()/the Merchant's Weapon tab
## actually gate on. Gear (hull/thruster/shield/aux) is "always in stock, no blueprint needed" per
## hub_screen.gd's own gear-tab doc comment, so staging one here would unlock nothing.
func _is_eligible(def_id: String) -> bool:
	var d := InventoryManager.get_def(def_id)
	if d.is_empty() or bool(d.get("unique", false)):
		return false
	return (d.get("tags", []) as Array).has("weapon")
