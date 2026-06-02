extends CanvasLayer

## Inventory / equipment screen (Phase 3). A toggle-able overlay built on top of
## InventoryManager. Open/close with the "I" key or the on-screen button.
## Rebuilds itself from the data layer whenever `inventory_changed` fires, so the
## display is always in sync and invalid drags simply snap back.

const CELL := 46
const PANEL_SIZE := Vector2(920, 600)
const SLOT_BOX := 64

# Preloaded (not referenced by class_name) so this works on a fresh headless run
# before the editor has registered the global class names.
const BackpackGrid := preload("res://scripts/ui/inventory/backpack_grid.gd")
const EquipSlot    := preload("res://scripts/ui/inventory/equip_slot.gd")
const ItemWidget   := preload("res://scripts/ui/inventory/item_widget.gd")

const SLOT_LABELS := {
	"primary_weapon":   "Primary Weapon",
	"secondary_weapon": "Secondary Weapon",
	"thruster":         "Thruster",
	"command_bridge":   "Command Bridge",
	"hull":             "Hull",
	"energy_core":      "Energy Core",
	"radar":            "Radar",
	"drone_1":          "Drone I",
	"drone_2":          "Drone II",
	"wings":            "Wings",
}
# Where each slot sits in the equip layout grid (col, row).
const SLOT_LAYOUT := {
	"command_bridge":   Vector2i(1, 0),
	"radar":            Vector2i(0, 1), "hull": Vector2i(1, 1), "energy_core": Vector2i(2, 1),
	"primary_weapon":   Vector2i(0, 2), "wings": Vector2i(1, 2), "secondary_weapon": Vector2i(2, 2),
	"thruster":         Vector2i(0, 3), "drone_1": Vector2i(1, 3), "drone_2": Vector2i(2, 3),
}

var _font: FontFile
var _backdrop: ColorRect
var _panel: Panel
var _toggle_btn: Button
var _grid: BackpackGrid
var _slot_nodes: Dictionary = {}   # slot -> EquipSlot

func _ready() -> void:
	layer = 60
	add_to_group("inventory_ui")   # weapon_system checks this to pause firing while open
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
	_toggle_btn.position = Vector2(20, 12)
	_toggle_btn.size = Vector2(170, 34)
	_style_button(_toggle_btn)
	_apply_font(_toggle_btn, 12)
	_toggle_btn.pressed.connect(toggle)
	add_child(_toggle_btn)

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

	# Equip slots (left side)
	var base := Vector2(60, 86)
	for slot: String in InventoryManager.EQUIP_SLOTS:
		var coords: Vector2i = SLOT_LAYOUT[slot]
		var sx := base.x + coords.x * 112.0
		var sy := base.y + coords.y * 100.0
		var es := EquipSlot.new()
		es.setup(slot)
		es.position = Vector2(sx, sy)
		es.size = Vector2(SLOT_BOX, SLOT_BOX)
		_style_slot(es)
		_panel.add_child(es)
		_slot_nodes[slot] = es

		var lbl := Label.new()
		lbl.text = SLOT_LABELS.get(slot, slot)
		lbl.position = Vector2(sx - 24, sy + SLOT_BOX + 1)
		lbl.size = Vector2(SLOT_BOX + 48, 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_font(lbl, 9)
		_panel.add_child(lbl)

	# Backpack (right side)
	var bp_label := Label.new()
	bp_label.text = "BACKPACK"
	bp_label.position = Vector2(430, 52)
	bp_label.size = Vector2(200, 20)
	_apply_font(bp_label, 13)
	_panel.add_child(bp_label)

	_grid = BackpackGrid.new()
	_grid.setup(InventoryManager.BACKPACK_COLS, InventoryManager.BACKPACK_ROWS, CELL)
	_grid.position = Vector2(430, 80)
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

	# Equipped items
	for slot: String in _slot_nodes:
		var uid := InventoryManager.equipped_uid(slot)
		if uid == -1:
			continue
		var def_id := String(InventoryManager.get_item(uid)["def"])
		var es: Control = _slot_nodes[slot]
		var w := ItemWidget.new()
		w.position = Vector2(4, 4)
		w.size = es.size - Vector2(8, 8)
		es.add_child(w)
		w.setup(uid, def_id, CELL, slot)

# ── Open / close ────────────────────────────────────────────────────────────

func open() -> void:
	_backdrop.show()
	_panel.show()
	_toggle_btn.hide()

func close() -> void:
	_backdrop.hide()
	_panel.hide()
	_toggle_btn.show()

func is_open() -> bool:
	return _panel.visible

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_I:
			toggle()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and is_open():
			close()
			get_viewport().set_input_as_handled()

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

func _style_slot(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	s.set_border_width_all(2)
	s.border_color = Color(0.35, 0.45, 0.65, 0.8)
	s.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", s)

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
