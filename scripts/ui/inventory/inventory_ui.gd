extends CanvasLayer

## Inventory / equipment screen (Phase 3). A toggle-able overlay built on top of
## InventoryManager. Open/close with the "I" key or the on-screen button.
## Rebuilds itself from the data layer whenever `inventory_changed` fires, so the
## display is always in sync and invalid drags simply snap back.

const SYSTEM1_ENABLED := true
const CELL := 46
const PANEL_SIZE := Vector2(1100, 760)
const PANEL_X_SHIFT := 50.0   # px the whole panel is nudged left of dead-center

# Preloaded (not referenced by class_name) so this works on a fresh headless run
# before the editor has registered the global class names.
const BackpackGrid    := preload("res://scripts/ui/inventory/backpack_grid.gd")
const EquipSlot       := preload("res://scripts/ui/inventory/equip_slot.gd")
const ExtractSlot     := preload("res://scripts/ui/inventory/extract_slot.gd")   # "Extract & Dispose" drop target
const BringHomeSlot   := preload("res://scripts/ui/inventory/bring_home_slot.gd")   # "Bring Home" drop target
const LiveSlot        := preload("res://scripts/ui/inventory/live_slot.gd")
const ItemWidget      := preload("res://scripts/ui/inventory/item_widget.gd")
const CharacterSheet  := preload("res://scripts/ui/inventory/character_sheet.gd")
const ArenaWeapons    := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaAux        := preload("res://scripts/gameplay/arena_aux.gd")

const SLOT_LABELS := {
	"secondary_weapon": "Shield",
	"thruster":         "Thruster",
	"hull":             "Hull",
}
# Read-only WEAPONS/AUX row geometry — mirrors the live in-run HUD slot bars (arena_weapon_slots.gd /
# arena_aux_slots.gd), just laid out horizontally inside the panel instead of pinned to a screen edge.
const RS_SLOT := 60.0
const RS_GAP  := 10.0
# Slot tint per row (all flat colour squares now — no more per-slot sprite art). 50% fill + a brighter
# same-hue border, so the three rows read as distinct categories at a glance.
const WEAPON_SLOT_COLOR := Color(1.0, 0.55, 0.15, 0.5)   # orange
const AUX_SLOT_COLOR    := Color(0.2, 0.5, 1.0, 0.5)     # blue
const GEAR_SLOT_COLOR   := Color(1.0, 0.2, 0.2, 0.5)     # red — GEAR slots only show this fill when occupied

var _font: FontFile
var _backdrop: ColorRect
var _panel: Panel
var _toggle_btn: Button
var _grid: BackpackGrid
var _sheet: CharacterSheet          # live player-stats panel, docked right of the loadout
var _slot_nodes: Dictionary = {}   # slot -> EquipSlot
var _weapon_row: Control = null    # 5 read-only slots, live from the arena_weapons group
var _aux_row: Control = null       # 5 read-only slots, live from the arena_aux group
var _msg_label: Label = null       # transient on-panel message (failed equip-requirement, etc.)
var _dragging: bool = false        # true while an item is being dragged (drag highlight beats hover)
var _extract_slot = null           # "Extract & Dispose" drop target (extract_slot.gd)
var _bring_home_slot = null        # "Bring Home" drop target (bring_home_slot.gd)

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS   # stay interactive while the inventory pauses the game
	add_to_group("inventory_ui")   # weapon_system checks this to pause firing while open
	add_to_group("hud_editable")
	set_meta("hud_key", "inventory_btn")
	_font = load("res://assets/fonts/mandalore/mandalore.ttf") as FontFile
	_build_toggle_button()
	_build_panel()
	close()
	_toggle_btn.hide()   # HUD button (arena_hud_buttons) is the entry point; text button stays hidden
	InventoryManager.inventory_changed.connect(_rebuild)
	_rebuild()

# ── Build ─────────────────────────────────────────────────────────────────────

func _build_toggle_button() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.text = MandaloreText.a("INVENTORY (I)")
	_toggle_btn.position = Vector2(1240, 310)
	_toggle_btn.size = Vector2(192, 30)
	_style_button(_toggle_btn)
	_apply_font(_toggle_btn, 12)
	_toggle_btn.pressed.connect(toggle)
	add_child(_toggle_btn)
	var saved := _load_hud_rect("inventory_btn")
	if saved.size != Vector2.ZERO:
		_toggle_btn.position = saved.position
		_toggle_btn.size     = saved.size

func get_hud_rect() -> Rect2:
	if is_instance_valid(_toggle_btn):
		return Rect2(_toggle_btn.position, _toggle_btn.size)
	return Rect2(Vector2(1240, 310), Vector2(192, 30))

func apply_hud_rect(rect: Rect2) -> void:
	if is_instance_valid(_toggle_btn):
		_toggle_btn.position = rect.position
		_toggle_btn.size     = rect.size

static func _load_hud_rect(key: String) -> Rect2:
	var cfg := ConfigFile.new()
	if cfg.load("user://hud_layout.cfg") != OK:
		return Rect2()
	if not cfg.has_section_key("hud", key + "/pos"):
		return Rect2()
	return Rect2(
		cfg.get_value("hud", key + "/pos",  Vector2.ZERO) as Vector2,
		cfg.get_value("hud", key + "/size", Vector2.ZERO) as Vector2
	)

func _build_panel() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.55)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_panel = Panel.new()
	_panel.size = PANEL_SIZE
	_panel.anchor_left = 0.5; _panel.anchor_top = 0.5
	_panel.anchor_right = 0.5; _panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_SIZE.x * 0.5 - PANEL_X_SHIFT; _panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5 - PANEL_X_SHIFT; _panel.offset_bottom = PANEL_SIZE.y * 0.5
	_style_panel(_panel)
	add_child(_panel)
	UiPalette.scanlines(_panel)
	_build_panel_contents()

	# Character Sheet — live stats panel, docks itself to the right screen edge.
	_sheet = CharacterSheet.new()
	add_child(_sheet)

func _build_panel_contents() -> void:
	var title := Label.new()
	title.text = MandaloreText.a("INVENTORY")
	title.position = Vector2(0, 12)
	title.size = Vector2(PANEL_SIZE.x, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 18)
	_panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = MandaloreText.a("X")
	close_btn.position = Vector2(PANEL_SIZE.x - 42, 10)
	close_btn.size = Vector2(32, 32)
	_style_button(close_btn)
	_apply_font(close_btn, 14)
	close_btn.pressed.connect(close)
	_panel.add_child(close_btn)

	# WEAPONS (top) — 5 read-only slots mirroring the live in-run HUD bar (arena_weapons).
	var weap_label := Label.new()
	weap_label.text = MandaloreText.a("WEAPONS")
	weap_label.position = Vector2(40, 48)
	weap_label.size = Vector2(300, 20)
	_apply_font(weap_label, 13)
	_panel.add_child(weap_label)
	_weapon_row = Control.new()
	_weapon_row.position = Vector2(40, 74)
	_panel.add_child(_weapon_row)

	# AUX (below weapons) — 5 read-only slots mirroring the live in-run HUD bar (arena_aux).
	var aux_label := Label.new()
	aux_label.text = MandaloreText.a("AUX")
	aux_label.position = Vector2(40, 150)
	aux_label.size = Vector2(300, 20)
	_apply_font(aux_label, 13)
	_panel.add_child(aux_label)
	_aux_row = Control.new()
	_aux_row.position = Vector2(40, 176)
	_panel.add_child(_aux_row)

	# GEAR (below aux) — the 3 remaining real equip slots (shield / thruster / hull), simple row.
	var gear_label := Label.new()
	gear_label.text = MandaloreText.a("GEAR")
	gear_label.position = Vector2(40, 252)
	gear_label.size = Vector2(300, 20)
	_apply_font(gear_label, 13)
	_panel.add_child(gear_label)
	var gx := 40.0
	for slot: String in InventoryManager.EQUIP_SLOTS:
		var es := EquipSlot.new()
		es.setup(slot)
		es.tooltip_text = SLOT_LABELS.get(slot, slot)
		es.position = Vector2(gx, 278)
		es.size = Vector2(RS_SLOT, RS_SLOT)   # same footprint as WEAPONS/AUX slots
		_style_slot(es, false)
		_panel.add_child(es)
		_slot_nodes[slot] = es
		gx += RS_SLOT + RS_GAP

	# EXTRACT & DISPOSE (below gear) — drop an item here to destroy it for InventoryManager.get_sell_price()
	# gold. Sits in the left column under GEAR, deliberately apart from the equip slots since it is
	# destructive (its own red styling; see extract_slot.gd).
	var ext_label := Label.new()
	ext_label.text = MandaloreText.a("EXTRACT")
	ext_label.position = Vector2(40, 354)
	ext_label.size = Vector2(300, 20)
	_apply_font(ext_label, 13)
	_panel.add_child(ext_label)
	_extract_slot = ExtractSlot.new()
	_extract_slot.setup()
	_extract_slot.position = Vector2(40, 380)
	_extract_slot.size = Vector2(RS_SLOT * 2.0 + RS_GAP, RS_SLOT)   # double-wide so the two-line label fits
	_panel.add_child(_extract_slot)

	# BRING HOME (2026-08-29, on request) — right next to EXTRACT, opposite intent (green, not destructive):
	# drop a weapon here to stage it (and its blueprint) for MetaManager.resolve_bring_home() at run end. See
	# bring_home_slot.gd's own header for the full risk framing.
	var bh_x := 40.0 + (RS_SLOT * 2.0 + RS_GAP) + RS_GAP
	var bh_label := Label.new()
	bh_label.text = MandaloreText.a("BRING HOME")
	bh_label.position = Vector2(bh_x, 354)
	bh_label.size = Vector2(300, 20)
	_apply_font(bh_label, 13)
	_panel.add_child(bh_label)
	_bring_home_slot = BringHomeSlot.new()
	_bring_home_slot.setup()
	_bring_home_slot.position = Vector2(bh_x, 380)
	_bring_home_slot.size = Vector2(RS_SLOT * 2.0 + RS_GAP, RS_SLOT)   # double-wide so the two-line label fits
	_panel.add_child(_bring_home_slot)

	# Cargo (right side) — placed past the WEAPONS/AUX/GEAR column (~x 600). Items picked up during play.
	var bp_label := Label.new()
	bp_label.text = MandaloreText.a("CARGO")
	bp_label.position = Vector2(600, 52)
	bp_label.size = Vector2(200, 20)
	_apply_font(bp_label, 13)
	_panel.add_child(bp_label)

	_grid = BackpackGrid.new()
	_grid.setup(InventoryManager.BACKPACK_COLS, InventoryManager.BACKPACK_ROWS, CELL)
	_grid.position = Vector2(600, 80)
	_panel.add_child(_grid)

	var hint := Label.new()
	hint.text = MandaloreText.a("Drag an item onto a matching slot to equip · drag back to the backpack to remove")
	hint.position = Vector2(40, PANEL_SIZE.y - 40)
	hint.size = Vector2(PANEL_SIZE.x - 80, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = UiPalette.MUTED
	_apply_font(hint, 10)
	_panel.add_child(hint)

# ── Rebuild from data ───────────────────────────────────────────────────────

func _rebuild() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		if c is ItemWidget:
			c.queue_free()
	for slot: String in _slot_nodes:
		for c in (_slot_nodes[slot] as Control).get_children():
			if c is ItemWidget:
				c.queue_free()
	if _bring_home_slot != null and is_instance_valid(_bring_home_slot):
		for c in (_bring_home_slot as Control).get_children():
			if c is ItemWidget:
				c.queue_free()

	# Backpack items
	for uid: int in InventoryManager.backpack_uids():
		var it: Dictionary = InventoryManager.get_item(uid)
		var def_id := String(it["def"])
		var cell: Vector2i = it["cell"]
		var size: Vector2i = InventoryManager.def_size(def_id)
		var w := ItemWidget.new()
		w.position = Vector2(cell) * CELL
		w.size = Vector2(size) * CELL
		_grid.add_child(w)
		w.setup(uid, def_id, CELL, "")
		w.sell_requested.connect(_on_sell_requested)
		w.mouse_entered.connect(_on_item_hover.bind(def_id))
		w.mouse_exited.connect(_on_item_unhover)

	# Equipped items
	for slot: String in _slot_nodes:
		var es: Control = _slot_nodes[slot]
		var uid := InventoryManager.equipped_uid(slot)
		_style_slot(es as Panel, uid != -1)
		if uid == -1:
			continue
		var def_id := String(InventoryManager.get_item(uid)["def"])
		var w := ItemWidget.new()
		# GEAR slots are now RS_SLOT-sized like WEAPONS/AUX — the item renders shrunk to fit (ItemWidget
		# is fully size-driven, see its _build()), not at full backpack cell scale.
		w.size = Vector2(RS_SLOT, RS_SLOT) - Vector2(6, 6)
		w.position = (es.size - w.size) * 0.5
		es.add_child(w)
		w.setup(uid, def_id, CELL, slot)
		w.sell_requested.connect(_on_sell_requested)
		w.mouse_entered.connect(_on_item_hover.bind(def_id))
		w.mouse_exited.connect(_on_item_unhover)

	# Bring Home occupant (2026-08-29) — same render shape as an equip slot above: InventoryManager's own
	# "bring_home" where already keeps it out of backpack_uids(), so this is the only place it's drawn.
	# Dragging it back out reuses backpack_grid.gd's existing generic move_item() drop — no extra code needed
	# there, since move_item() already treats every non-"backpack" where identically.
	if _bring_home_slot != null and is_instance_valid(_bring_home_slot):
		var bh_uid := InventoryManager.equipped_uid("bring_home")
		if bh_uid != -1:
			var bh_def_id := String(InventoryManager.get_item(bh_uid)["def"])
			var bw := ItemWidget.new()
			bw.size = Vector2(RS_SLOT, RS_SLOT) - Vector2(6, 6)
			bw.position = (_bring_home_slot.size - bw.size) * 0.5
			_bring_home_slot.add_child(bw)
			bw.setup(bh_uid, bh_def_id, CELL, "bring_home")
			bw.sell_requested.connect(_on_sell_requested)
			bw.mouse_entered.connect(_on_item_hover.bind(bh_def_id))
			bw.mouse_exited.connect(_on_item_unhover)

	_rebuild_weapons_aux()

## Read-only WEAPONS/AUX rows. WEAPONS reflects the live run (arena_weapons) when open mid-run, or falls
## back to the Hub's saved Loadout pick (MetaManager.loadout, no level — the run hasn't started yet) when
## opened from the Dock. AUX has no meta equivalent (it's purely per-run) so it's just empty outside a run.
func _rebuild_weapons_aux() -> void:
	if _weapon_row != null:
		for c in _weapon_row.get_children():
			c.queue_free()
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		var live := aw != null and aw.has_method("acquired_weapons")
		var acquired: Array = aw.call("acquired_weapons") if live else MetaManager.loadout
		for i in ArenaWeapons.MAX_WEAPONS:
			var slot := _make_readonly_slot(WEAPON_SLOT_COLOR, "weapon", i)
			slot.position = Vector2(float(i) * (RS_SLOT + RS_GAP), 0.0)
			_weapon_row.add_child(slot)
			if i < acquired.size():
				var kind := String(acquired[i])
				var lvl := int(aw.call("weapon_level", kind)) if live and aw.has_method("weapon_level") else 0
				_fill_readonly_slot(slot, _weapon_icon(kind), Color(0, 0, 0, 0), _weapon_label(kind), lvl)
	if _aux_row != null:
		for c in _aux_row.get_children():
			c.queue_free()
		var aux := get_tree().get_first_node_in_group("arena_aux")
		var owned: Array = aux.call("owned_aux") if aux != null and aux.has_method("owned_aux") else []
		for i in ArenaAux.MAX_AUX:
			var slot := _make_readonly_slot(AUX_SLOT_COLOR, "aux", i)
			slot.position = Vector2(float(i) * (RS_SLOT + RS_GAP), 0.0)
			_aux_row.add_child(slot)
			if i < owned.size():
				var id := String(owned[i])
				var d: Dictionary = aux.call("def_for", id)
				var lvl := int(aux.call("aux_level", id)) if aux.has_method("aux_level") else 0
				var tex := _aux_icon(d)
				_fill_readonly_slot(slot, tex, Color(d.get("color", Color.GRAY)), String(d.get("name", id)), lvl)

func _make_readonly_slot(bg_color: Color, row_kind: String, index: int) -> Panel:
	var p := LiveSlot.new()
	p.setup(row_kind, index)
	p.size = Vector2(RS_SLOT, RS_SLOT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_border_width_all(2)
	sb.border_color = Color(bg_color.r, bg_color.g, bg_color.b, 0.95)
	sb.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", sb)
	return p

## Fills an (already-empty) read-only slot with an icon (or a colour swatch if `tex` is null and
## `fallback_color` has alpha) + a small level number in the corner.
func _fill_readonly_slot(slot: Panel, tex: Texture2D, fallback_color: Color, item_name: String, level: int) -> void:
	slot.tooltip_text = "%s (Lv %d)" % [item_name, level]
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left += 4.0; tr.offset_top += 4.0; tr.offset_right -= 4.0; tr.offset_bottom -= 4.0
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tr)
	elif fallback_color.a > 0.0:
		var cr := ColorRect.new()
		cr.color = fallback_color
		cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cr.offset_left += 8.0; cr.offset_top += 8.0; cr.offset_right -= 8.0; cr.offset_bottom -= 8.0
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cr)
	var lvl_lbl := Label.new()
	lvl_lbl.text = MandaloreText.a(str(level))
	lvl_lbl.position = Vector2(2.0, RS_SLOT - 16.0)
	lvl_lbl.size = Vector2(RS_SLOT - 4.0, 14.0)
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(lvl_lbl, 10)
	lvl_lbl.add_theme_color_override("font_color", UiPalette.AMBER)
	slot.add_child(lvl_lbl)

## Registry entry for a weapon kind from either the base weapon map or the fusion map (mirrors
## arena_weapon_slots.gd's _info_for so the icon/label always match the in-run HUD).
func _weapon_info(kind: String) -> Dictionary:
	var wi: Dictionary = ArenaWeapons.WEAPON_INFO
	if wi.has(kind):
		return wi[kind]
	return (ArenaWeapons.FUSION_DEFS as Dictionary).get(kind, {})

func _weapon_icon(kind: String) -> Texture2D:
	var info := _weapon_info(kind)
	var icon_path := String(info.get("icon", ""))
	if icon_path != "":
		return load(icon_path) as Texture2D
	return InventoryManager.get_icon(String(info.get("def_id", "")))

func _weapon_label(kind: String) -> String:
	var info := _weapon_info(kind)
	return String(info.get("label", info.get("name", kind)))

func _aux_icon(d: Dictionary) -> Texture2D:
	var path := String(d.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

# ── Open / close ────────────────────────────────────────────────────────────

var _was_paused: bool = false   # restore the prior pause state on close (plays nice w/ level-up overlays)

func open() -> void:
	_backdrop.show()
	_panel.show()
	if _sheet != null:
		_sheet.show()
	_toggle_btn.hide()
	_was_paused = get_tree().paused
	get_tree().paused = true   # opening the inventory pauses the game
	_rebuild_weapons_aux()     # refresh WEAPONS/AUX rows (they don't fire inventory_changed)

func close() -> void:
	_backdrop.hide()
	_panel.hide()
	if _sheet != null:
		_sheet.hide()
	if not _was_paused:
		get_tree().paused = false   # only unpause if WE paused it

func is_open() -> bool:
	return _panel.visible

# ── Compatible-slot highlighting (hover + drag) ──────────────────────────────

## Light every equip/WEAPONS/AUX slot this def can go into; clear the rest.
func _highlight_for_def(def_id: String) -> void:
	for slot: String in _slot_nodes:
		(_slot_nodes[slot] as InvEquipSlot).set_highlight(InventoryManager.fits_slot(def_id, slot))
	for row: Control in [_weapon_row, _aux_row]:
		if row == null:
			continue
		for c in row.get_children():
			if c is LiveSlot:
				(c as LiveSlot).set_highlight((c as LiveSlot)._can_drop_data(Vector2.ZERO, {"def_id": def_id, "uid": -1}))
	# Extract & Dispose takes ANY item, so it lights up for every def — no compatibility test to run.
	if _extract_slot != null and is_instance_valid(_extract_slot):
		_extract_slot.set_highlight(true)
	# Bring Home only takes non-unique weapons — _is_eligible() is the same check its own _can_drop_data()
	# runs, just decoupled from needing a real uid (hover-preview only ever has the def_id, same convention
	# as the WEAPONS/AUX LiveSlot check right above).
	if _bring_home_slot != null and is_instance_valid(_bring_home_slot):
		_bring_home_slot.set_highlight(_bring_home_slot._is_eligible(def_id))

func _clear_highlights() -> void:
	for slot: String in _slot_nodes:
		(_slot_nodes[slot] as InvEquipSlot).set_highlight(false)
	for row: Control in [_weapon_row, _aux_row]:
		if row == null:
			continue
		for c in row.get_children():
			if c is LiveSlot:
				(c as LiveSlot).set_highlight(false)
	if _extract_slot != null and is_instance_valid(_extract_slot):
		_extract_slot.set_highlight(false)
	if _bring_home_slot != null and is_instance_valid(_bring_home_slot):
		_bring_home_slot.set_highlight(false)

func _on_item_hover(def_id: String) -> void:
	if _dragging:
		return   # an active drag owns the highlight
	_highlight_for_def(def_id)

func _on_item_unhover() -> void:
	if _dragging:
		return
	_clear_highlights()

## Poll the viewport drag state so picking up an item lights matching slots for the whole drag.
func _process(_delta: float) -> void:
	if not is_open():
		if _dragging:
			_dragging = false
			_clear_highlights()
		return
	var vp := get_viewport()
	var now: bool = vp.gui_is_dragging()
	if now == _dragging:
		return
	_dragging = now
	if now:
		var data: Variant = vp.gui_get_drag_data() if vp.has_method("gui_get_drag_data") else null
		if typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("def_id"):
			_highlight_for_def(String((data as Dictionary)["def_id"]))
	else:
		_clear_highlights()

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# ── Sell (right-click an item, or drop onto Extract & Dispose) ───────────────────

var _sell_dialog: ConfirmationDialog = null
var _pending_sell_uid: int = -1

## Shared by BOTH sell entry points — right-click (item_widget.gd's sell_requested signal) and dropping onto
## the Extract & Dispose slot (extract_slot.gd, 2026-08-29, on request: "khi kéo vào sẽ hiện bảng prompt:
## 'This will destroy item' và tùy chọn Yes / No"). Confirming here is the ONLY place either route actually
## calls InventoryManager.sell_item() — extract_slot.gd used to sell immediately on drop with no confirm at
## all; it now just calls this the same as a right-click would. Cancel/close does nothing at all, which is
## exactly "No, put it back" — the item was never touched until Yes actually fires.
func _on_sell_requested(p_uid: int, def_id: String) -> void:
	if _sell_dialog == null:
		_sell_dialog = ConfirmationDialog.new()
		_sell_dialog.title = "This will destroy item"
		_sell_dialog.ok_button_text = "Yes"
		_sell_dialog.cancel_button_text = "No"
		_sell_dialog.confirmed.connect(_on_sell_confirmed)
		add_child(_sell_dialog)
	_pending_sell_uid = p_uid
	var item_name := String(InventoryManager.get_def(def_id).get("name", def_id))
	var price := InventoryManager.get_sell_price(p_uid)
	# Wording + payout match the Extract & Dispose drop slot (2026-08-25, on request) — both read
	# InventoryManager.get_sell_price(), so the two routes can never quote different numbers.
	_sell_dialog.dialog_text = "This will destroy item.\n\nExtract %s for %d$?" % [item_name, price]
	_sell_dialog.popup_centered()

func _on_sell_confirmed() -> void:
	if _pending_sell_uid != -1:
		InventoryManager.sell_item(_pending_sell_uid)
		_pending_sell_uid = -1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_I or k == KEY_C:   # I = inventory, C = character sheet (both open this panel)
			toggle()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and is_open():
			close()
			get_viewport().set_input_as_handled()

## Transient on-panel message (e.g. a failed equip-requirement). Called by equip_slot.gd.
func flash_message(msg: String) -> void:
	if _msg_label == null:
		_msg_label = Label.new()
		_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_msg_label.size = Vector2(PANEL_SIZE.x, 28)
		_msg_label.position = Vector2(0, 44)
		_msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_font(_msg_label, 16)
		_msg_label.add_theme_color_override("font_color", UiPalette.DANGER)
		_panel.add_child(_msg_label)
	_msg_label.text = MandaloreText.a(msg)
	_msg_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_property(_msg_label, "modulate:a", 0.0, 0.6)

# ── Styling (CRT phosphor console — UiPalette tokens) ────────────────────────

func _apply_font(c: Control, sz: int) -> void:
	if _font == null:
		return
	c.add_theme_font_override("font", _font)
	c.add_theme_font_size_override("font_size", sz)

func _style_panel(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = UiPalette.SURFACE
	s.set_border_width_all(2)
	s.border_color = UiPalette.ACCENT_DIM
	s.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", s)

## GEAR slots are flat colour squares like WEAPONS/AUX (no more per-slot sprite art) — but only show
## their red fill/border when they actually hold a meta item; an empty gear slot draws nothing (per
## design: "chỉ được draw nếu có item meta"). Still a real drop target either way (equip_slot.gd).
func _style_slot(p: Panel, occupied: bool) -> void:
	if not occupied:
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # truly invisible, not just "no override"
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = GEAR_SLOT_COLOR
	sb.set_border_width_all(2)
	sb.border_color = Color(GEAR_SLOT_COLOR.r, GEAR_SLOT_COLOR.g, GEAR_SLOT_COLOR.b, 0.95)
	sb.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", sb)

func _style_button(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = UiPalette.SURFACE_2
		if state == "hover":
			s.bg_color = UiPalette.SURFACE_3
		elif state == "pressed":
			s.bg_color = UiPalette.ACCENT_DIM
		s.set_border_width_all(2)
		s.border_color = UiPalette.WIRE_2
		s.set_corner_radius_all(0)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", UiPalette.INK)
