extends CanvasLayer

## Inventory / equipment screen (Phase 3). A toggle-able overlay built on top of
## InventoryManager. Open/close with the "I" key or the on-screen button.
## Rebuilds itself from the data layer whenever `inventory_changed` fires, so the
## display is always in sync and invalid drags simply snap back.

const CELL := 46
const PANEL_SIZE := Vector2(1100, 760)
const SLOT_PAD := 10   # px of padding around an item inside its slot
# Largest item footprint (in cells) each slot must hold at full backpack scale (no shrink).
const SLOT_MAX_CELLS := {
	"primary_weapon":   Vector2i(3, 2),
	"secondary_weapon": Vector2i(3, 2),
	"wings":            Vector2i(3, 2),
	"hull":             Vector2i(2, 3),
	"command_bridge":   Vector2i(2, 2),
	"energy_core":      Vector2i(2, 2),
	"radar":            Vector2i(2, 2),   # the "Artifact" slot — key stays "radar" (see EQUIP_SLOTS)
	"drone_1":          Vector2i(2, 2),
	"drone_2":          Vector2i(2, 2),
	"thruster":         Vector2i(2, 2),
	"relic":            Vector2i(2, 2),
}

# Preloaded (not referenced by class_name) so this works on a fresh headless run
# before the editor has registered the global class names.
const BackpackGrid    := preload("res://scripts/ui/inventory/backpack_grid.gd")
const EquipSlot       := preload("res://scripts/ui/inventory/equip_slot.gd")
const ItemWidget      := preload("res://scripts/ui/inventory/item_widget.gd")
const CharacterSheet  := preload("res://scripts/ui/inventory/character_sheet.gd")

const SLOT_LABELS := {
	"primary_weapon":   "Primary Weapon",
	"secondary_weapon": "Secondary Weapon",
	"thruster":         "Thruster",
	"command_bridge":   "Command Bridge",
	"hull":             "Hull",
	"energy_core":      "Energy Core",
	"radar":            "Artifact",   # label only — data-layer key remains "radar"
	"drone_1":          "Drone I",
	"drone_2":          "Drone II",
	"wings":            "Wings",
	"relic":            "Relic",
}
# Background images for each slot
const SLOT_ICONS := {
	"primary_weapon":   "res://assets/inventory/slotweapon1.gif",
	"secondary_weapon": "res://assets/inventory/slotweapon2.gif",
	"thruster":         "res://assets/inventory/slotthruster.gif",
	"command_bridge":   "res://assets/inventory/slotcommand.gif",
	"hull":             "res://assets/inventory/slothull.gif",
	"energy_core":      "res://assets/inventory/slotenergy.gif",
	"radar":            "res://assets/inventory/slotradar.gif",
	"drone_1":          "res://assets/inventory/slotdrone1.gif",
	"drone_2":          "res://assets/inventory/slotdrone2.gif",
	"wings":            "res://assets/inventory/slotwing.gif",
}
# Equip grid geometry (panel-local). Pitch ≥ largest slot (158px) so centred slots never overlap.
const GRID_ORIGIN := Vector2(40, 48)
const GRID_PITCH  := Vector2(176, 135)
# Where each slot sits in the equip cross (col, row).
const SLOT_LAYOUT := {
	"command_bridge":   Vector2i(1, 0),
	"primary_weapon":   Vector2i(0, 1), "hull": Vector2i(1, 1), "secondary_weapon": Vector2i(2, 1),
	"drone_2":          Vector2i(0, 2), "relic": Vector2i(1, 2), "drone_1": Vector2i(2, 2),
	"energy_core":      Vector2i(0, 3), "wings": Vector2i(1, 3), "radar": Vector2i(2, 3),
	"thruster":         Vector2i(1, 4),
}

var _font: FontFile
var _backdrop: ColorRect
var _panel: Panel
var _toggle_btn: Button
var _grid: BackpackGrid
var _sheet: CharacterSheet          # live player-stats panel, docked right of the loadout
var _slot_nodes: Dictionary = {}   # slot -> EquipSlot
var _msg_label: Label = null       # transient on-panel message (failed equip-requirement, etc.)
var _dragging: bool = false        # true while an item is being dragged (drag highlight beats hover)

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS   # stay interactive while the inventory pauses the game
	add_to_group("inventory_ui")   # weapon_system checks this to pause firing while open
	add_to_group("hud_editable")
	set_meta("hud_key", "inventory_btn")
	_font = load("res://assets/fonts/Gameplay.ttf") as FontFile
	_build_toggle_button()
	_build_panel()
	close()
	InventoryManager.inventory_changed.connect(_rebuild)
	_rebuild()

# ── Build ─────────────────────────────────────────────────────────────────────

func _build_toggle_button() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.text = "INVENTORY (I)"
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
	_panel.offset_left = -PANEL_SIZE.x * 0.5; _panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5; _panel.offset_bottom = PANEL_SIZE.y * 0.5
	_style_panel(_panel)
	add_child(_panel)
	_build_panel_contents()

	# Character Sheet — live stats panel, docks itself to the right screen edge.
	_sheet = CharacterSheet.new()
	add_child(_sheet)

# Pixel size of a slot = its largest item footprint (cells × CELL) + padding on all sides.
func _slot_size(slot: String) -> Vector2:
	var cells: Vector2i = SLOT_MAX_CELLS.get(slot, Vector2i(2, 2))
	return Vector2(cells) * CELL + Vector2(SLOT_PAD, SLOT_PAD) * 2.0

func _build_panel_contents() -> void:
	var title := Label.new()
	title.text = "SHIP LOADOUT"
	title.position = Vector2(0, 12)
	title.size = Vector2(PANEL_SIZE.x, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 18)
	_panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(PANEL_SIZE.x - 42, 10)
	close_btn.size = Vector2(32, 32)
	_style_button(close_btn)
	_apply_font(close_btn, 14)
	close_btn.pressed.connect(close)
	_panel.add_child(close_btn)

	# Equip slots (left side) — each sized to its largest item + padding, centred in a
	# uniform grid cell. Slot art identifies each slot, so there are no text labels.
	for slot: String in InventoryManager.EQUIP_SLOTS:
		if not SLOT_LAYOUT.has(slot):
			push_warning("[inventory_ui] no SLOT_LAYOUT entry for '%s' — skipping" % slot)
			continue
		var coords: Vector2i = SLOT_LAYOUT[slot]
		var ssize: Vector2 = _slot_size(slot)
		var cell_origin := GRID_ORIGIN + Vector2(coords) * GRID_PITCH
		var slot_pos := cell_origin + (GRID_PITCH - ssize) * 0.5   # centre slot in its cell
		var es := EquipSlot.new()
		es.setup(slot)
		es.tooltip_text = SLOT_LABELS.get(slot, slot)
		es.position = slot_pos
		es.size = ssize
		_style_slot(es, slot)
		_panel.add_child(es)
		_slot_nodes[slot] = es

	# Backpack (right side) — placed past the equip region (~x 600).
	var bp_label := Label.new()
	bp_label.text = "BACKPACK"
	bp_label.position = Vector2(600, 52)
	bp_label.size = Vector2(200, 20)
	_apply_font(bp_label, 13)
	_panel.add_child(bp_label)

	_grid = BackpackGrid.new()
	_grid.setup(InventoryManager.BACKPACK_COLS, InventoryManager.BACKPACK_ROWS, CELL)
	_grid.position = Vector2(600, 80)
	_panel.add_child(_grid)

	var hint := Label.new()
	hint.text = "Drag an item onto a matching slot to equip · drag back to the backpack to remove"
	hint.position = Vector2(40, PANEL_SIZE.y - 40)
	hint.size = Vector2(PANEL_SIZE.x - 80, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.78, 0.9)
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
		var uid := InventoryManager.equipped_uid(slot)
		if uid == -1:
			continue
		var def_id := String(InventoryManager.get_item(uid)["def"])
		var es: Control = _slot_nodes[slot]
		var w := ItemWidget.new()
		# Equipped items render at FULL backpack scale (def footprint × CELL — no shrink),
		# centred in the slot (which is sized to hold the largest item + padding).
		var item_cells: Vector2i = InventoryManager.def_size(def_id)
		w.size = Vector2(item_cells) * CELL
		w.position = (es.size - w.size) * 0.5
		es.add_child(w)
		w.setup(uid, def_id, CELL, slot)
		w.sell_requested.connect(_on_sell_requested)
		w.mouse_entered.connect(_on_item_hover.bind(def_id))
		w.mouse_exited.connect(_on_item_unhover)

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

func close() -> void:
	_backdrop.hide()
	_panel.hide()
	if _sheet != null:
		_sheet.hide()
	_toggle_btn.show()
	if not _was_paused:
		get_tree().paused = false   # only unpause if WE paused it

func is_open() -> bool:
	return _panel.visible

# ── Compatible-slot highlighting (hover + drag) ──────────────────────────────

## Light every equip slot this def can go into; clear the rest.
func _highlight_for_def(def_id: String) -> void:
	for slot: String in _slot_nodes:
		(_slot_nodes[slot] as InvEquipSlot).set_highlight(InventoryManager.fits_slot(def_id, slot))

func _clear_highlights() -> void:
	for slot: String in _slot_nodes:
		(_slot_nodes[slot] as InvEquipSlot).set_highlight(false)

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

# ── Sell (right-click an item) ────────────────────────────────────────────────

var _sell_dialog: ConfirmationDialog = null
var _pending_sell_uid: int = -1

func _on_sell_requested(p_uid: int, def_id: String) -> void:
	if _sell_dialog == null:
		_sell_dialog = ConfirmationDialog.new()
		_sell_dialog.title = "Sell item"
		_sell_dialog.ok_button_text = "Sell"
		_sell_dialog.confirmed.connect(_on_sell_confirmed)
		add_child(_sell_dialog)
	_pending_sell_uid = p_uid
	var item_name := String(InventoryManager.get_def(def_id).get("name", def_id))
	var price := InventoryManager.get_sell_price(p_uid)
	_sell_dialog.dialog_text = "Sell %s for $%d?" % [item_name, price]
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
		_msg_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		_panel.add_child(_msg_label)
	_msg_label.text = msg
	_msg_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_property(_msg_label, "modulate:a", 0.0, 0.6)

# ── Styling (dark navy / steel-blue, matching the rest of the game) ───────────

func _apply_font(c: Control, sz: int) -> void:
	if _font == null:
		return
	c.add_theme_font_override("font", _font)
	c.add_theme_font_size_override("font_size", sz)

func _style_panel(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.12, 0.97)
	s.set_border_width_all(2)
	s.border_color = Color(0.3, 0.4, 0.6, 0.95)
	s.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", s)

func _style_slot(p: Panel, slot_name: String = "") -> void:
	# No border — background image only
	# Add background image for the slot (GIF or PNG)
	if slot_name != "" and SLOT_ICONS.has(slot_name):
		var icon_path: String = SLOT_ICONS[slot_name]
		var tex: Texture2D = null

		# GIF files need GifLoader
		if icon_path.get_extension().to_lower() == "gif":
			tex = GifLoader.load_gif(icon_path)
			# Get first frame if it's animated
			if tex != null and tex.has_meta("gif_frames"):
				var frames: Array = tex.get_meta("gif_frames")
				if not frames.is_empty():
					tex = frames[0] as Texture2D
		else:
			tex = load(icon_path) as Texture2D

		if tex != null:
			var bg := TextureRect.new()
			bg.name = "SlotBackground_%s" % slot_name
			bg.texture = tex
			bg.stretch_mode = TextureRect.STRETCH_SCALE
			bg.expand_mode = TextureRect.EXPAND_KEEP_SIZE
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			p.add_child(bg)
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # fills the slot's real size
			p.move_child(bg, 0)  # move to back

func _style_button(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		var shade := 0.12
		if state == "hover":
			shade = 0.18
		elif state == "pressed":
			shade = 0.08
		s.bg_color = Color(shade, shade + 0.03, shade + 0.08, 0.95)
		s.set_border_width_all(2)
		s.border_color = Color(0.35, 0.45, 0.65, 0.9)
		s.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color(0.8, 0.86, 0.95))
