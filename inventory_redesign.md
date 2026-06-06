
Prompt for Claude Code:
Task
Rework the ship-loadout equip-slot layout in inventory_ui.gd so equipped items display at full backpack scale (no shrinking), each slot is sized to its largest possible item plus padding, the radar slot is renamed to artifact, and slots are arranged in a specific cross layout. Touch only the inventory UI files. Do not modify gameplay, projectile, or the separate EquipmentManager shop code (equipment_item.gd, equipment_list.gd are unrelated — leave them alone).
Files

Primary edits: scripts/ui/inventory/inventory_ui.gd
Read for reference, likely no edits: scripts/ui/inventory/item_widget.gd, scripts/ui/inventory/equip_slot.gd, scripts/ui/inventory/backpack_grid.gd
Read-only investigation: wherever InventoryManager is defined (search the project).

Read all of these before editing.
Step 0 — Investigate the radar→artifact rename (do this first, report before proceeding)
The slot keys are owned by the data layer, not the UI. Search the whole project for radar and for EQUIP_SLOTS:

grep -rn "radar" --include=*.gd .
grep -rn "EQUIP_SLOTS" --include=*.gd .

inventory_ui.gd iterates InventoryManager.EQUIP_SLOTS (line 119: for slot: String in InventoryManager.EQUIP_SLOTS:) and calls InventoryManager.equipped_uid(slot) (line 192). So the string key "radar" almost certainly lives in InventoryManager and may be persisted in save data.
Decision rule:

If "radar" is ONLY a UI label/icon and the data layer uses a different scheme: rename fully to artifact.
If "radar" is a key in InventoryManager.EQUIP_SLOTS or save/equip data: do NOT rename the key. Renaming it would desync equipped items and break saves. Instead, keep the underlying key "radar" and change only the user-visible label to "Artifact".

Report what you found and which path you're taking before making the rename edits. If unsure, take the safe path (label-only) and flag it.
Constants (top of inventory_ui.gd, currently lines 8–11)
Current:
gdscriptconst CELL := 46
const PANEL_SIZE := Vector2(920, 600)
const SLOT_BOX := 60
const EQUIP_ICON_SCALE := 1.0

Keep CELL := 46.
Remove SLOT_BOX and EQUIP_ICON_SCALE (they're being replaced). Verify with grep they aren't used elsewhere before removing; they currently appear only in _rebuild() (lines 198–203), _build_panel_contents() (lines 126, 138, 139), and _style_slot via SLOT_BOX (lines 308, 310-ish). Update all those call sites as described below.
Add:

gdscriptconst SLOT_PAD := 10   # px of padding around an item inside its slot
# Largest item footprint (in cells) each slot must hold without shrinking.
const SLOT_MAX_CELLS := {
    "primary_weapon":   Vector2i(3, 2),
    "secondary_weapon": Vector2i(3, 2),
    "wings":            Vector2i(3, 2),
    "hull":             Vector2i(2, 3),
    "command_bridge":   Vector2i(2, 2),
    "energy_core":      Vector2i(2, 2),
    "radar":            Vector2i(2, 2),   # NOTE: keep key matching EQUIP_SLOTS — see Step 0
    "drone_1":          Vector2i(2, 2),
    "drone_2":          Vector2i(2, 2),
    "thruster":         Vector2i(2, 2),
}
(If Step 0 says rename the key to artifact, use artifact here and everywhere below instead of radar. If Step 0 says label-only, keep the key radar here.)
Add a helper to compute a slot's pixel size:
gdscriptfunc _slot_size(slot: String) -> Vector2:
    var cells: Vector2i = SLOT_MAX_CELLS.get(slot, Vector2i(2, 2))
    return Vector2(cells) * CELL + Vector2(SLOT_PAD, SLOT_PAD) * 2.0
Resulting sizes (verify by hand): 3×2 → (138+20, 92+20) = 158×112; 2×3 → 112×158; 2×2 → 112×112.
Layout map (replace SLOT_LAYOUT, currently lines 44–50)
Use a uniform grid. Define grid geometry constants near the layout:
gdscriptconst GRID_ORIGIN := Vector2(48, 80)   # top-left of the equip area inside the panel; tune if needed
const GRID_PITCH  := Vector2(182, 182) # 158 (largest slot) + 24 gap, square cells keep cross aligned
Replace SLOT_LAYOUT with this cell-coordinate map (col, row), matching the user's sketch tidied up:
gdscriptconst SLOT_LAYOUT := {
    "command_bridge":   Vector2i(1, 0),
    "primary_weapon":   Vector2i(0, 1),
    "hull":             Vector2i(1, 1),
    "secondary_weapon": Vector2i(2, 1),
    "drone_2":          Vector2i(0, 2),
    "drone_1":          Vector2i(2, 2),
    "energy_core":      Vector2i(0, 3),
    "wings":            Vector2i(1, 3),
    "radar":            Vector2i(2, 3),   # the "Artifact" slot — keep key per Step 0
    "thruster":         Vector2i(1, 4),
}
Layout intent (achieve this look, tidy not jittery): command_bridge centered on top; primary/hull/secondary across row 1 with hull being the tall 112×158 slot; drones flank on row 2 (center column left empty there so the tall hull occupies it visually); energy_core / wings(wide) / artifact across row 3; thruster centered below on row 4. Because hull is taller than the other row-1 slots, when you center each slot in its cell the hull will visually extend toward row 2 — that's intended and matches the sketch.
_build_panel_contents() — slot creation loop (currently lines 117–141)
Current loop computes sx/sy from base + coords*112/100 and sets es.size = Vector2(SLOT_BOX, SLOT_BOX). Replace the per-slot geometry with:
gdscriptfor slot: String in InventoryManager.EQUIP_SLOTS:
    var coords: Vector2i = SLOT_LAYOUT[slot]
    var ssize: Vector2 = _slot_size(slot)
    var cell_origin := GRID_ORIGIN + Vector2(coords) * GRID_PITCH
    var slot_pos := cell_origin + (GRID_PITCH - ssize) * 0.5  # center slot in its cell
    var es := EquipSlot.new()
    es.setup(slot)
    es.position = slot_pos
    es.size = ssize
    _style_slot(es, slot)
    _panel.add_child(es)
    _slot_nodes[slot] = es

    var lbl := Label.new()
    lbl.text = SLOT_LABELS.get(slot, slot)
    _apply_font(lbl, 8)
    _panel.add_child(lbl)
    var text_size := lbl.get_minimum_size()
    var slot_center_x := slot_pos.x + ssize.x * 0.5
    lbl.position = Vector2(slot_center_x - text_size.x * 0.5, slot_pos.y + ssize.y + 6)
    lbl.size = text_size
Guard against a missing layout key: if SLOT_LAYOUT doesn't have slot, skip with a push_warning rather than crashing.
_rebuild() — equipped item widget (currently lines 191–206)
Current code forces box := Vector2(SLOT_BOX, SLOT_BOX) and sizes/positions from that. Replace the sizing block (the part after var es: Control = _slot_nodes[slot] and var w := ItemWidget.new()) with footprint-based sizing centered in the actual slot:
gdscriptvar es: Control = _slot_nodes[slot]
var w := ItemWidget.new()
var item_cells: Vector2i = InventoryManager.def_size(def_id)
var ssize: Vector2 = es.size                       # actual slot pixel size
w.size = Vector2(item_cells) * CELL                # full backpack scale, no shrink
w.position = (ssize - w.size) * 0.5                # center in the slot
es.add_child(w)
w.setup(uid, def_id, CELL, slot)
w.sell_requested.connect(_on_sell_requested)
Note: this is the actual bug fix — equipped items are now the same pixel size as in the backpack. Keep everything else in _rebuild() (backpack loop lines 177–188) unchanged.
_style_slot() — slot background image (currently lines 282–311)
It uses SLOT_BOX for custom_minimum_size (line 308) and relies on set_anchors_and_offsets_preset(PRESET_FULL_RECT) (line 310). Since the background uses FULL_RECT it will already stretch to the slot's real size, so remove the hardcoded custom_minimum_size = Vector2(SLOT_BOX, SLOT_BOX) line (or set it to the slot's size). The slot's size is set by the caller before _style_slot runs in the new loop, so FULL_RECT is sufficient. Verify the background still fills the (now larger, non-square) slots correctly.
Panel size (currently PANEL_SIZE, line 9, and contents at lines 99–162)
The equip grid now spans 3 columns × up to 5 rows of 182px pitch ≈ 546 wide × 910 tall — taller than the current 600 panel. Recompute:

Left equip region width ≈ GRID_ORIGIN.x + 3 * GRID_PITCH.x ≈ 48 + 546 = ~594.
Total height needs to fit 5 rows: GRID_ORIGIN.y + 5 * GRID_PITCH.y + label/margin ≈ 80 + 910 + 60 ≈ ~1050. That's very tall — consider reducing GRID_PITCH.y to ~150 (tall hull 158 + small gap) and using square-ish but shorter rows, OR scale the whole panel. Pause and tell me the computed dimensions before committing to a giant panel — we may want to shrink the vertical pitch since only hull is tall. Propose a PANEL_SIZE and GRID_PITCH that fits cleanly and wait for confirmation if the panel would exceed ~720px tall (typical screen).
Move the BACKPACK label (line 145, currently x=430) and _grid (line 152, currently x=430) to the right of the new equip region so they don't overlap — set their x to about equip_region_width + 40.
Reposition title (line 102), close button (line 110: PANEL_SIZE.x - 42), and hint (line 156–157) relative to the new PANEL_SIZE. These already reference PANEL_SIZE so they mostly self-adjust, but verify the close button stays in the top-right corner and the hint stays at the bottom.

Validation after editing

grep -n "SLOT_BOX\|EQUIP_ICON_SCALE" scripts/ui/inventory/inventory_ui.gd returns nothing (fully removed).
Re-read the edited regions and confirm: slot sizes match 158×112 / 112×158 / 112×112; each slot centered in its 182 (or chosen) pitch cell; equipped widget size = def_size × 46; no two slots overlap given the pitch ≥ largest slot; panel bounds contain all slots + labels + backpack.
Confirm radar/artifact handling matches the Step 0 decision consistently across SLOT_LABELS, SLOT_ICONS, SLOT_LAYOUT, SLOT_MAX_CELLS.
Don't run the game (headless), just verify the code is internally consistent and report the final PANEL_SIZE, GRID_PITCH, and per-slot sizes.

