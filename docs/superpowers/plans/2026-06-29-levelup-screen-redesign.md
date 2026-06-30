# Level-Up Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the centered level-up panel in `scripts/ui/hud/arena_levelup_ui.gd` with a full-screen layout: left column of 3 offered choices (sprite + name), center showing the selected item big + its 3 options (or a single Confirm / a Fusion composition), right column of curated read-only global stats — reusing all existing selection/pool/capstone/fusion/apply logic.

**Architecture:** One file changes (`arena_levelup_ui.gd`). The state model splits into `_choices` (left, the tier-1 offered items, persistent per screen) and `_current` (the bottom options row that `_pick()` acts on — pool upgrades / capstones / a single confirm / a destroy list). Selecting a left item routes to the right options via `_route_options()`. All choice-generation (`_generate_choices`, `_gen_pool_choices`, `_gen_aux_pool_choices`, `_show_capstone`, `_show_aux_capstone`, `_show_destroy_choice`), apply (`_pick`, `_apply`, `_advance`, `_pick_fusion`), and SFX functions are reused unchanged or with their render target swapped from the old card row to the new options box.

**Tech Stack:** Godot 4 GDScript; Control/CanvasLayer UI built in code; `InventoryManager.get_icon(def_id)` for sprites; `GameManager` getters for stats.

## Global Constraints

- Static typing throughout; tabs for indentation (match the file).
- No test suite — verification is `godot --headless --check-only --path . --quit` (exit 0 = parse clean) plus manual F5. State this explicitly; never claim runtime success from a parse check alone.
- Aspect ratio: never stretch sprites — use `TextureRect` `STRETCH_KEEP_ASPECT_CENTERED` (or compute size from texture ratio). Sprites are centered in their box.
- Pivot/scale rules and pause-safe nodes per CLAUDE.md (`PROCESS_MODE_ALWAYS` is already on this CanvasLayer).
- `arena_levelup_ui.gd` is NOT a locked file — editing it is allowed. Do not touch locked files.
- Shell is PowerShell; the Bash tool is available for the headless check.

## File Structure

- **Modify:** `scripts/ui/hud/arena_levelup_ui.gd` — only this file.
  - Replaced: `_build_ui()` (old `lvupframe` centered panel), `_render_current()`, `_make_card()`, `_position_cards()`, `_bg_tex()`, `_show_pool()`, `_show_aux_pool()`, `_back_to_tier1()`, `_back()`, card layout consts (`_CW/_CH/_CGAP/_CSHIFT`), `_make_icon`/`_icon_rect` (folded into new sprite helper), hover handlers.
  - Added: `_refresh_stats()` + `_make_stat_row()`, `_render_left()` + `_make_slot()`, `_select_item()` + `_set_selected_display()`, `_route_options()`, `_render_options()` + `_make_option_box()`, `_select_fusion()` + `_render_fusion()`, `_sprite_or_swatch()`.
  - Reused unchanged: `_generate_choices`, `_weapon_choice`, `_aux_choice`, `_fusion_choice`, `_weighted_pick`, `_gen_pool_choices`, `_gen_aux_pool_choices`, `_weapon_pool`, `_aux_pool`, `_pick`, `_pick_capstone`, `_pick_fusion`, `_apply`, `_advance`, `_finish`, `_default_text`, `_current_text`, `_play_sfx`, `_on_leveled_up`, `grant_reward`, `_begin`.
  - Reused with render-target swap only: `_show_capstone`, `_show_aux_capstone`, `_show_destroy_choice` (call `_render_options()` not `_render_current()`).

New/changed member variables (top of file, near the existing `var _pending` block):

```gdscript
var _choices: Array = []        # left-column offered items (tier-1), persistent for this screen
var _selected_idx: int = -1     # which left slot is currently selected
var _options_back: bool = false # true while the All-In "destroy a weapon" sub-view is showing (offers a back affordance)
# REUSED: _pending, _showing, _current (now = the OPTIONS-row array that _pick() acts on), _capstone_weapon
# REMOVED: _tier1, _back_target, _back_btn
```

New node references (replace the old `_root/_cards_box` refs; keep `_title`):

```gdscript
var _root: Control = null
var _slot_nodes: Array = []        # the 3 left-column slot Controls
var _selected_box: Control = null  # center-top big-sprite panel
var _options_box: Control = null   # center-bottom options container
var _stats_box: VBoxContainer = null
var _title: Label = null
```

Layout constants (add near the top, replacing the old card consts):

```gdscript
# Full-screen layout fractions (symmetric: left/right columns equal, centered main column).
const COL_L_LEFT  := 0.02
const COL_L_RIGHT := 0.23
const COL_C_LEFT  := 0.25
const COL_C_RIGHT := 0.75
const COL_R_LEFT  := 0.77
const COL_R_RIGHT := 0.98
const CONTENT_TOP    := 0.085   # below the title strip
const CONTENT_BOTTOM := 0.98
const SEL_BOTTOM := 0.55        # selected-item panel bottom (center column)
const OPT_TOP    := 0.60        # options row top (center column)
const SLOT_GAP   := 0.015       # vertical gap between the 3 left slots (fraction)
const FONT_PATH := "res://assets/fonts/Good Old DOS.ttf"
const RING_COL  := Color(1.0, 0.85, 0.2)   # fusion source-box yellow ring
```

---

### Task 1: Full-screen scaffold + stats panel

Rewrite `_build_ui()` to build the full-screen layout and add the read-only stats panel. After this task the screen renders its frame (backdrop, title, empty columns, stats) even though choices aren't wired yet — so keep `_show_cards()` compiling by temporarily pointing its render at a stub (fixed in Task 2).

**Files:**
- Modify: `scripts/ui/hud/arena_levelup_ui.gd`

**Interfaces:**
- Produces: `_build_ui()`, `_refresh_stats()`, `_make_stat_row(label: String, value: String) -> Control`, member nodes `_root/_slot_nodes/_selected_box/_options_box/_stats_box/_title`.

- [ ] **Step 1: Replace the member-var + consts block** as listed in *File Structure* above (remove `_tier1`, `_back_target`, `_back_btn`, `_cards_box`, the `_CW/_CH/_CGAP/_CSHIFT` consts; add the new vars/consts).

- [ ] **Step 2: Replace `_build_ui()`** with the full-screen scaffold:

```gdscript
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.06, 0.97)   # near-opaque: the level-up takes the whole screen
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	# Title strip (full width, top).
	_title = Label.new()
	_title.text = "LEVEL UP — choose an item"
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_font_override("font", load(FONT_PATH))
	_title.add_theme_color_override("font_color", Color("#E5792A"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.anchor_left = 0.0; _title.anchor_right = 1.0
	_title.anchor_top = 0.012; _title.anchor_bottom = 0.07
	_root.add_child(_title)

	# Left column: 3 stacked slots.
	_slot_nodes.clear()
	var avail := CONTENT_BOTTOM - CONTENT_TOP
	var slot_h := (avail - SLOT_GAP * 2.0) / 3.0
	for i in 3:
		var slot := _make_panel()
		slot.anchor_left = COL_L_LEFT; slot.anchor_right = COL_L_RIGHT
		slot.anchor_top = CONTENT_TOP + float(i) * (slot_h + SLOT_GAP)
		slot.anchor_bottom = slot.anchor_top + slot_h
		_root.add_child(slot)
		_slot_nodes.append(slot)

	# Center column: selected-item panel (top) + options box (bottom).
	_selected_box = _make_panel()
	_selected_box.anchor_left = COL_C_LEFT; _selected_box.anchor_right = COL_C_RIGHT
	_selected_box.anchor_top = CONTENT_TOP; _selected_box.anchor_bottom = SEL_BOTTOM
	_root.add_child(_selected_box)

	_options_box = Control.new()
	_options_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options_box.anchor_left = COL_C_LEFT; _options_box.anchor_right = COL_C_RIGHT
	_options_box.anchor_top = OPT_TOP; _options_box.anchor_bottom = CONTENT_BOTTOM
	_root.add_child(_options_box)

	# Right column: curated stats list.
	var stats_panel := _make_panel()
	stats_panel.anchor_left = COL_R_LEFT; stats_panel.anchor_right = COL_R_RIGHT
	stats_panel.anchor_top = CONTENT_TOP; stats_panel.anchor_bottom = CONTENT_BOTTOM
	_root.add_child(stats_panel)
	var stats_head := Label.new()
	stats_head.text = "STATS"
	stats_head.add_theme_font_override("font", load(FONT_PATH))
	stats_head.add_theme_font_size_override("font_size", 20)
	stats_head.add_theme_color_override("font_color", Color("#E5792A"))
	stats_head.anchor_left = 0.0; stats_head.anchor_right = 1.0
	stats_head.anchor_top = 0.01; stats_head.anchor_bottom = 0.07
	stats_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_panel.add_child(stats_head)
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	_stats_box.anchor_left = 0.06; _stats_box.anchor_right = 0.94
	_stats_box.anchor_top = 0.08; _stats_box.anchor_bottom = 0.98
	stats_panel.add_child(_stats_box)
```

- [ ] **Step 3: Add the panel + stat-row helpers** (anywhere in the UI-build section):

```gdscript
## A bordered translucent panel used for slots / the selected box / the stats column.
func _make_panel() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.70, 0.9)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p

## Build the curated, read-only global-stat rows. Each entry is rendered only if its value resolves
## (so stats not yet wired in GameManager are omitted rather than shown as 0). Refreshed on every open.
func _refresh_stats() -> void:
	if _stats_box == null:
		return
	for c in _stats_box.get_children():
		c.free()
	var gm := GameManager
	if gm.has_method("get_damage_mult"):
		_stats_box.add_child(_make_stat_row("Damage", "x%.2f" % gm.get_damage_mult()))
	if gm.has_method("get_fire_rate_mult"):
		_stats_box.add_child(_make_stat_row("Fire rate", "x%.2f" % gm.get_fire_rate_mult()))
	if gm.has_method("get_crit_chance"):
		_stats_box.add_child(_make_stat_row("Crit chance", "%d%%" % int(round(gm.get_crit_chance() * 100.0))))
	if gm.has_method("get_crit_damage"):
		_stats_box.add_child(_make_stat_row("Crit damage", "x%.2f" % gm.get_crit_damage()))
	if gm.has_method("get_move_speed_mult"):
		_stats_box.add_child(_make_stat_row("Move speed", "x%.2f" % gm.get_move_speed_mult()))
	if gm.has_method("get_pickup_radius"):
		_stats_box.add_child(_make_stat_row("Pickup", "%d" % int(round(gm.get_pickup_radius()))))
	if gm.has_method("get_base_defense"):
		_stats_box.add_child(_make_stat_row("Armor (flat)", "%d" % gm.get_base_defense()))
	if gm.has_method("get_momentum_mult"):
		_stats_box.add_child(_make_stat_row("Momentum", "x%.2f" % gm.get_momentum_mult()))
	# Probe optional stats that may not exist yet (HP, regen, AOE, armor pen %, masteries). Add rows only if present.
	if gm.has_method("get_max_hp"):
		_stats_box.add_child(_make_stat_row("HP", "%d" % int(gm.get_max_hp())))
	if gm.has_method("get_aoe_mult"):
		_stats_box.add_child(_make_stat_row("AOE", "x%.2f" % gm.get_aoe_mult()))
	if gm.has_method("get_armor_pen_pct"):
		_stats_box.add_child(_make_stat_row("Armor pen %", "%d%%" % int(round(gm.get_armor_pen_pct() * 100.0))))
	if gm.has_method("get_armor_pen_flat"):
		_stats_box.add_child(_make_stat_row("Armor pen flat", "%d" % int(gm.get_armor_pen_flat())))

func _make_stat_row(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_override("font", load(FONT_PATH))
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", load(FONT_PATH))
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row
```

- [ ] **Step 4: Keep the file compiling** — temporarily make the old render path a no-op so nothing references removed nodes. Replace the body of `_render_current()` with `pass` and delete `_position_cards()`, `_make_card()`, `_bg_tex()`, `_make_icon()`, `_icon_rect()`, `_show_pool()`, `_show_aux_pool()`, `_back_to_tier1()`, `_back()`, `_on_card_hover()`, `_on_card_unhover()`. In `_show_cards()` leave the existing calls (they'll be rewired in Task 2); change any `_back_btn`/`_title.text` lines that reference the removed `_back_btn` to drop the `_back_btn` references. (Search the file for `_back_btn`, `_cards_box`, `_tier1`, `_back_target`, `_position_cards`, `_make_card`, `_render_current` and remove/neutralize each.)

- [ ] **Step 5: Parse check**

Run: `godot --headless --check-only --path . --quit`
Expected: exit 0, no SCRIPT/parse errors for `arena_levelup_ui.gd` (pre-existing `lasgun_ani_1.gd` texture-load runtime lines are unrelated — ignore).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/hud/arena_levelup_ui.gd
git commit -m "Level-up redesign: full-screen scaffold + stats panel"
```

---

### Task 2: Left column — render the 3 offered choices with centered sprites

**Files:**
- Modify: `scripts/ui/hud/arena_levelup_ui.gd`

**Interfaces:**
- Consumes: `_generate_choices(n)` (returns the choice dicts with keys `cat/key/action/name/def_id/color/level/...`), `InventoryManager.get_icon(def_id)`.
- Produces: `_render_left()`, `_make_slot(c, idx)`, `_sprite_or_swatch(def_id, color)`, and a rewritten `_show_cards()` that fills the left column and auto-selects slot 0.

- [ ] **Step 1: Add the sprite helper** (reused by slots + the selected panel):

```gdscript
## A centered sprite for a weapon/fusion def_id, or a colour swatch fallback (aux items have no art).
## size_px is the box's shorter side; the TextureRect keeps the texture's aspect (never stretched).
func _sprite_or_swatch(def_id: String, color: Color) -> Control:
	var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var sw := ColorRect.new()
	sw.color = color
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sw
```

- [ ] **Step 2: Add `_render_left()` + `_make_slot()`.** Fusion handling: if a fusion choice is present in `_choices`, its two source weapons occupy slots 0 and 1 (ringed + rainbow-pulsed) and both select the fusion; the remaining non-fusion choices fill the rest.

```gdscript
## Fill the 3 left slots from _choices. A fusion choice expands into its two source weapons (slots 0 & 1).
func _render_left() -> void:
	for slot: Control in _slot_nodes:
		for c in slot.get_children():
			c.free()
		slot.visible = false
	# Find a fusion (if any) — it claims slots 0 & 1 with the two source weapons.
	var fusion: Dictionary = {}
	var rest: Array = []
	for c: Dictionary in _choices:
		if String(c.get("cat", "")) == "fusion" and fusion.is_empty():
			fusion = c
		else:
			rest.append(c)
	var slot_specs: Array = []   # each: {def_id, name, color, action_idx (index into _choices), fusion}
	if not fusion.is_empty():
		slot_specs.append({"def": String(fusion.get("def_a", "")), "name": fusion["name"], "color": fusion.get("color", Color.GRAY), "idx": _choices.find(fusion), "fusion": true})
		slot_specs.append({"def": String(fusion.get("def_b", "")), "name": fusion["name"], "color": fusion.get("color", Color.GRAY), "idx": _choices.find(fusion), "fusion": true})
	for c: Dictionary in rest:
		if slot_specs.size() >= 3:
			break
		slot_specs.append({"def": String(c.get("def_id", "")), "name": c["name"], "color": c.get("color", Color.GRAY), "idx": _choices.find(c), "fusion": false})
	for i in mini(slot_specs.size(), 3):
		_make_slot(_slot_nodes[i], slot_specs[i])

func _make_slot(slot: Control, spec: Dictionary) -> void:
	slot.visible = true
	var idx := int(spec["idx"])
	var is_fusion := bool(spec["fusion"])
	# Centered sprite (upper ~62% of the slot).
	var spr := _sprite_or_swatch(String(spec["def"]), spec.get("color", Color.GRAY))
	spr.anchor_left = 0.12; spr.anchor_right = 0.88
	spr.anchor_top = 0.08; spr.anchor_bottom = 0.66
	slot.add_child(spr)
	# Name label (lower band).
	var lbl := Label.new()
	lbl.text = String(spec["name"])
	lbl.add_theme_font_override("font", load(FONT_PATH))
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.anchor_left = 0.04; lbl.anchor_right = 0.96
	lbl.anchor_top = 0.70; lbl.anchor_bottom = 0.96
	slot.add_child(lbl)
	# Click target.
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_select_item.bind(idx))
	slot.add_child(btn)
	# Fusion source boxes get a yellow ring + a rainbow pulse.
	if is_fusion:
		var sb := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			var sb2 := sb.duplicate() as StyleBoxFlat
			sb2.set_border_width_all(3)
			sb2.border_color = RING_COL
			slot.add_theme_stylebox_override("panel", sb2)
			var pulse := slot.create_tween().set_loops()
			pulse.tween_property(slot, "modulate", Color(1.4, 0.7, 1.4), 0.5).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(slot, "modulate", Color(0.7, 1.4, 1.4), 0.5).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(slot, "modulate", Color(1.4, 1.4, 0.7), 0.5).set_trans(Tween.TRANS_SINE)
```

- [ ] **Step 3: Rewrite `_show_cards()`** to fill the left column, refresh stats, and auto-select slot 0 (keep the empty-pool skip + the title set):

```gdscript
func _show_cards() -> void:
	_choices = _generate_choices(CHOICES)
	if _choices.is_empty():
		_pending -= 1
		if _pending > 0:
			_show_cards()
		else:
			_finish()
		return
	_title.text = "LEVEL UP — choose an item"
	_options_back = false
	_render_left()
	_refresh_stats()
	_root.show()
	_play_sfx("res://assets/audio/sfx/uialert.wav")
	_select_item(0)
```

- [ ] **Step 4: Add a temporary `_select_item()` stub** so Step 3 compiles (replaced in Task 3): `func _select_item(idx: int) -> void: _selected_idx = idx`.

- [ ] **Step 5: Parse check** — Run `godot --headless --check-only --path . --quit`; expected exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/hud/arena_levelup_ui.gd
git commit -m "Level-up redesign: left column choices with centered sprites + fusion source slots"
```

---

### Task 3: Selected-item panel + options routing (pool / confirm / capstone)

**Files:**
- Modify: `scripts/ui/hud/arena_levelup_ui.gd`

**Interfaces:**
- Consumes: `_choices`, `_gen_pool_choices(kind)`, `_gen_aux_pool_choices(id)`, `_weapon_pool(kind)`, `_aux_pool(id)`, `_show_capstone(kind)`, `_show_aux_capstone(id)`, `_pick(idx)`, `_default_text(c)`, `_current_text(c)`, `ArenaWeapons.WEAPON_INFO`.
- Produces: `_select_item(idx)`, `_set_selected_display(def_id, name, color)`, `_route_options(c)`, `_render_options()`, `_make_option_box(c, idx, total)`. Sets `_current` to the options array `_pick()` consumes.

- [ ] **Step 1: Replace the `_select_item()` stub** with the real one + the selected-panel display:

```gdscript
func _select_item(idx: int) -> void:
	if idx < 0 or idx >= _choices.size():
		return
	_selected_idx = idx
	_options_back = false
	var c: Dictionary = _choices[idx]
	if String(c.get("cat", "")) == "fusion":
		_select_fusion(c)   # bespoke A-top / FUSION / B-bottom view (Task 4)
		return
	_set_selected_display(String(c.get("def_id", "")), String(c["name"]), c.get("color", Color.GRAY))
	_title.text = String(c["name"])
	_route_options(c)
	_play_sfx("res://assets/audio/sfx/uiclick.wav")

## Fill the center-top panel with a big centered sprite + the item name.
func _set_selected_display(def_id: String, item_name: String, color: Color) -> void:
	for ch in _selected_box.get_children():
		ch.free()
	var spr := _sprite_or_swatch(def_id, color)
	spr.anchor_left = 0.2; spr.anchor_right = 0.8
	spr.anchor_top = 0.06; spr.anchor_bottom = 0.78
	_selected_box.add_child(spr)
	var lbl := Label.new()
	lbl.text = item_name
	lbl.add_theme_font_override("font", load(FONT_PATH))
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.05; lbl.anchor_right = 0.95
	lbl.anchor_top = 0.80; lbl.anchor_bottom = 0.97
	_selected_box.add_child(lbl)
```

- [ ] **Step 2: Add `_route_options()`** — decide what fills the bottom row for the selected item:

```gdscript
## Decide the bottom-row content for the selected choice and render it. Sets _current = the array _pick() acts on.
func _route_options(c: Dictionary) -> void:
	var cat := String(c.get("cat", ""))
	var key := String(c.get("key", ""))
	if cat == "weapon" and not _weapon_pool(key).is_empty():
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		# Maxed weapon → its capstones become the options (EVOLVE). _show_capstone sets _current + renders.
		if aw != null and bool(aw.call("weapon_needs_capstone", key)):
			_show_capstone(key)
			return
		var pool_choices := _gen_pool_choices(key)
		if pool_choices.is_empty():
			_current = [c]   # nothing left to pick in the pool → a plain confirm (spends the level)
		else:
			_current = pool_choices
		_render_options()
		return
	if cat == "aux" and not _aux_pool(key).is_empty():
		var ax := get_tree().get_first_node_in_group("arena_aux")
		if ax != null and bool(ax.call("aux_needs_capstone", key)):
			_show_aux_capstone(key)
			return
		var aux_choices := _gen_aux_pool_choices(key)
		_current = aux_choices if not aux_choices.is_empty() else [c]
		_render_options()
		return
	# New weapon / poolless weapon / simple aux → a single Confirm panel.
	_current = [c]
	_render_options()
```

- [ ] **Step 3: Add `_render_options()` + `_make_option_box()`.** Renders `_current` into `_options_box`: 1 item → full-width confirm; N items → N equal boxes; if `_options_back` is set (All-In destroy sub-view), prepend a Back box that returns to the capstones.

```gdscript
func _render_options() -> void:
	for ch in _options_box.get_children():
		ch.free()
	var n := _current.size()
	for i in n:
		var box := _make_option_box(_current[i], i, n)
		_options_box.add_child(box)
	if _options_back:
		var back := Button.new()
		back.text = "← back"
		back.add_theme_font_override("font", load(FONT_PATH))
		back.focus_mode = Control.FOCUS_NONE
		back.anchor_left = 0.0; back.anchor_right = 0.18
		back.anchor_top = -0.16; back.anchor_bottom = -0.02
		back.pressed.connect(func() -> void: _show_capstone(_capstone_weapon))
		_options_box.add_child(back)

## One option/confirm box: bold big name + small italic detail + full-rect click → _pick(idx).
func _make_option_box(c: Dictionary, idx: int, total: int) -> Control:
	var box := _make_panel()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	if total <= 1:
		box.anchor_left = 0.0; box.anchor_right = 1.0
	else:
		var step := 1.0 / float(total)
		box.anchor_left = float(idx) * step + 0.01
		box.anchor_right = float(idx + 1) * step - 0.01
	box.anchor_top = 0.0; box.anchor_bottom = 1.0
	# Bold name (top).
	var name_lbl := Label.new()
	name_lbl.text = String(c.get("name", ""))
	name_lbl.add_theme_font_override("font", load(FONT_PATH))
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.anchor_left = 0.06; name_lbl.anchor_right = 0.94
	name_lbl.anchor_top = 0.06; name_lbl.anchor_bottom = 0.34
	box.add_child(name_lbl)
	# Italic small detail (bottom): the effect/desc text (already carries burn/bleed/etc. keywords).
	var detail := Label.new()
	detail.text = _default_text(c) + ("\n" + String(c.get("desc", "")) if String(c.get("desc", "")) != "" else "")
	detail.add_theme_font_override("font", load(FONT_PATH))
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.anchor_left = 0.06; detail.anchor_right = 0.94
	detail.anchor_top = 0.40; detail.anchor_bottom = 0.94
	box.add_child(detail)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_pick.bind(idx))
	box.add_child(btn)
	return box
```

- [ ] **Step 4: Re-point the reused sub-view functions** to the new render path. In `_show_capstone()`, `_show_aux_capstone()`, and `_show_destroy_choice()`: change the final `_render_current()` call to `_render_options()`, delete the `_back_btn`/`_back_target` lines, and in `_show_destroy_choice()` set `_options_back = true` (and set it back to `false` at the top of `_show_capstone`/`_show_aux_capstone`). Leave their `_current = [...]` construction and titles intact. (The center panel keeps showing the weapon being evolved, set when its slot was selected.)

- [ ] **Step 5: Confirm `_pick()` is unaffected** — it reads `_current[idx]` and dispatches by `cat` (`pool`/`aux_pool`/`capstone`/`destroy`/`fusion`/weapon|aux new+level). It still calls `_advance()`/`_finish()` which hide `_root` and unpause. No change needed. (The dead tier-1 branches in `_pick` — "weapon with pool → `_show_pool`" — are now unreachable from the left path; remove them in Task 5 cleanup.)

- [ ] **Step 6: Parse check** — Run `godot --headless --check-only --path . --quit`; expected exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/hud/arena_levelup_ui.gd
git commit -m "Level-up redesign: selected panel + options routing (pool/confirm/capstone)"
```

---

### Task 4: Fusion composition view

**Files:**
- Modify: `scripts/ui/hud/arena_levelup_ui.gd`

**Interfaces:**
- Consumes: a fusion choice dict (`def_a`, `def_b`, `def_id`, `name`, `key`), `_pick_fusion(c)`, `InventoryManager.get_icon`.
- Produces: `_select_fusion(c)` — source A big in the selected panel, source B in the options box, a FUSION button between them.

- [ ] **Step 1: Add `_select_fusion()`**:

```gdscript
## Fusion view: source A big (center-top), source B in the options area, a FUSION button between them.
func _select_fusion(c: Dictionary) -> void:
	_selected_idx = _choices.find(c)
	_title.text = "FUSE — %s" % String(c["name"])
	_set_selected_display(String(c.get("def_a", "")), String(c["name"]), c.get("color", Color.GRAY))
	for ch in _options_box.get_children():
		ch.free()
	# Source B sprite (fills the options box, leaving room for the button on top).
	var spr := _sprite_or_swatch(String(c.get("def_b", "")), c.get("color", Color.GRAY))
	spr.anchor_left = 0.3; spr.anchor_right = 0.7
	spr.anchor_top = 0.28; spr.anchor_bottom = 0.96
	_options_box.add_child(spr)
	# FUSION button, centered above source B (visually between A and B).
	var btn := Button.new()
	btn.text = "✦ FUSION ✦"
	btn.add_theme_font_override("font", load(FONT_PATH))
	btn.add_theme_font_size_override("font_size", 22)
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = 0.3; btn.anchor_right = 0.7
	btn.anchor_top = 0.02; btn.anchor_bottom = 0.22
	btn.pressed.connect(func() -> void: _pick_fusion(c))
	_options_box.add_child(btn)
	_play_sfx("res://assets/audio/sfx/uialert.wav")
```

- [ ] **Step 2: Parse check** — Run `godot --headless --check-only --path . --quit`; expected exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/hud/arena_levelup_ui.gd
git commit -m "Level-up redesign: fusion composition view (A / FUSION / B)"
```

---

### Task 5: Remove dead code + keyboard input + final cleanup

**Files:**
- Modify: `scripts/ui/hud/arena_levelup_ui.gd`

- [ ] **Step 1: Delete now-unused code** if any remains: `_render_current()` (the `pass` stub), `_show_pool()`, `_show_aux_pool()`, `_back_to_tier1()`, `_back()`, `_gen_*` only if unused (KEEP `_gen_pool_choices`/`_gen_aux_pool_choices` — Task 3 uses them), the `TEX_FRAME/TEX_GREEN/TEX_RED/TEX_BLUE` consts and `lvupframe` references, and the dead tier-1 branches inside `_pick()` (the `cat=="weapon"/"aux"` blocks that call `_show_pool`/`_show_aux_pool`). Grep to confirm nothing else references a removed symbol:

Run: search the file for `_render_current`, `_show_pool`, `_back_btn`, `_tier1`, `TEX_FRAME`, `_make_card`, `_position_cards`. Expected: no remaining references.

- [ ] **Step 2: Confirm `_input()` keyboard mapping** still picks the bottom options (1/2/3 → `_pick(0..2)`). It already does; verify it isn't gated on a removed var. Leave it.

- [ ] **Step 3: Parse check** — Run `godot --headless --check-only --path . --quit`; expected exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/hud/arena_levelup_ui.gd
git commit -m "Level-up redesign: remove dead card-UI code"
```

---

### Task 6: Manual verification (no automated tests)

**Files:** none (verification only).

- [ ] **Step 1: Launch the arena.** With `WEAPON_TEST_MODE = true` ([arena.gd](../../../scripts/gameplay/arena.gd)) the game boots straight into the arena. Run `godot --path .` (non-headless), open the F12 palette, drag in a couple of weapons, and gain XP (kill enemies / open a reward chest) to trigger a level-up.

- [ ] **Step 2: Verify the layout** — full-screen; left column shows up to 3 offered items each with a centered sprite + name; center shows the selected item big; bottom shows its options; right shows the stats list. Slot 0 is auto-selected on open.

- [ ] **Step 3: Verify each item type** — a pooled weapon shows 3 options (pick one applies + the game resumes or shows the next queued level-up); a brand-new weapon / aux shows a single Confirm; a maxed pooled weapon shows its EVOLVE capstones (and All-In opens the destroy sub-view with a working Back).

- [ ] **Step 4: Verify fusion** — when a fusion is ready, its two sources occupy left slots 1 & 2 with a yellow ring + rainbow pulse; clicking either shows source A on top, source B below, FUSION between; pressing FUSION plays the cutscene and fuses.

- [ ] **Step 5: Verify input + queue** — keyboard 1/2/3 picks the bottom options; multiple level-ups from one XP gain queue correctly; the screen pauses on open and unpauses on finish.

- [ ] **Step 6: Report results honestly** — note any layout nudges needed (anchor tweaks are expected for UI). Fix and re-commit if needed.

---

## Self-Review

**Spec coverage:** full-screen 100% (Task 1 backdrop full-rect) ✓; left 3 choices with sprites (Task 2) ✓; center big selected sprite (Task 3) ✓; bottom 3 options / confirm / capstone (Task 3) ✓; fusion 2-source view (Task 4) ✓; curated read-only stats, omit-absent (Task 1 `_refresh_stats`) ✓; symmetric proportions (Task 1 consts) ✓; auto-select slot 0 (Task 2 `_show_cards`) ✓; keyboard 1/2/3 (Task 5) ✓; reuse all logic (Tasks 3–4 call existing fns) ✓; pause/queue (reused `_begin`/`_advance`/`_finish`) ✓.

**Placeholder scan:** no TBD/TODO; every code step shows complete functions. UI anchor values are concrete (tuning expected at F5, flagged in Task 6).

**Type consistency:** `_choices` (left), `_current` (options `_pick` reads), `_selected_idx`, `_options_back` used consistently; `_render_options`/`_render_left`/`_select_item`/`_route_options`/`_set_selected_display`/`_sprite_or_swatch`/`_make_panel`/`_make_slot`/`_make_option_box`/`_make_stat_row`/`_refresh_stats`/`_select_fusion` names match across tasks. `_show_capstone`/`_show_aux_capstone`/`_show_destroy_choice` render via `_render_options` (Task 3 Step 4). `_pick` reused unchanged.
