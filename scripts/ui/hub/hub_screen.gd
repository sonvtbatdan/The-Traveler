extends Control
## Hub — the between-run home screen. Hosts the authored "Dock" board (assets/hud/dock/, see
## board_defs.gd + dock_binder.gd) as the main view instead of a hand-built tab UI. Clicking a room with a
## real system behind it opens an overlay panel reusing the SAME tab-content builders the old hand-built
## Hub used (just triggered by a room click instead of a tab button):
##   Equipment → Loadout   Mechanic → Shop   Engineer → Passives / Craft / Fragments (3 sub-tabs)
##   Launch    → still launches a run directly — no map-select system exists yet to gate it on
## Everything else (Constructor/Codex/Trophy/Bridge/Instructor/Pilot/Beacon) has no system behind it yet —
## clicking shows a "Coming Soon" toast (see dock_binder.gd's doc comment for the full room→destination map).
## All state lives in MetaManager + GameManager (coins).

const ARENA_SCENE := "res://scenes/arena.tscn"
const ArenaScript := preload("res://scripts/gameplay/arena.gd")   # for the WEAPON_TEST_MODE flag (skip this launch page)
const InventoryUIScript := preload("res://scripts/ui/inventory/inventory_ui.gd")   # equip screen (I key)
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")   # WEAPON_INFO/MAX_WEAPONS for the Loadout tab
const HudEditScript := preload("res://scripts/ui/boss_edit/hud_edit_mode.gd")
const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/Gameplay.ttf"

const RARITY_LABEL := {
	"common": "Common", "uncommon": "Uncommon", "rare": "Rare",
	"very_rare": "Very Rare", "unique": "Unique", "legendary": "Legendary",
}

# ── Thumbnail grid (Loadout / Shop tabs) — cells at 70% of the original size ─────────
const GRID_COLS       := 4
const CELL_W           := 118.0
const CELL_H           := 133.0
const CELL_GAP         := 7.0
const ICON_SIZE        := 52.0   # < CELL_W/CELL_H minus label/tag/margin room, so it never crowds the text
const REVEAL_BTN_H     := 24.0
const GRID_BG_OFF  := Color(0.10, 0.22, 0.42, 0.65)   # blue  — not loaded / not owned yet
const GRID_BG_ON   := Color(0.55, 0.30, 0.06, 0.70)   # orange — loaded / owned

# room_clicked name → sub-tab ids to show in the overlay panel (order = tab order; first = default).
const ROOM_PANELS := {
	"Equipment": ["loadout"],
	"Mechanic":  ["shop"],
	"Engineer":  ["passives", "craft", "fragments"],
}
const TAB_LABELS := {"loadout": "LOADOUT", "shop": "SHOP", "craft": "CRAFT", "fragments": "FRAGMENTS", "passives": "PASSIVES", "mapselect": "SELECT MAP"}

var _tab: String = "loadout"
var _available_tabs: Array = []
var _coin_label: Label = null
var _content: VBoxContainer = null
var _tab_buttons: Dictionary = {}
var _panel: Control = null
var _panel_dim: ColorRect = null
var _subtabs_row: HBoxContainer = null
var _coin_row: Control = null
var _toast: Label = null
var _dock_host = null   # HudEditScript surface hosting the "dock" board

func _ready() -> void:
	if ArenaScript.WEAPON_TEST_MODE:
		# Weapon-test mode: don't show the launch page — boot straight into the arena (which auto-opens F12).
		call_deferred("_goto_arena")
		return
	_build_dock_host()
	_build_panel_ui()
	_build_toast()
	add_child(InventoryUIScript.new())   # I key here too — equip Gear (hull/thruster/shield) + browse Cargo before launching
	if GameManager.has_signal("money_changed"):
		GameManager.money_changed.connect(func(_m: int) -> void: _refresh())
	if MetaManager.has_signal("meta_changed"):
		MetaManager.meta_changed.connect(_refresh)

## Forward directly into the arena (weapon-test mode skips the hub UI entirely).
func _goto_arena() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
	add_child(InventoryUIScript.new())   # equip what you buy before launching (toggle with the I key)
	if GameManager.has_signal("money_changed"):
		GameManager.money_changed.connect(func(_m: int) -> void: _refresh())
	if MetaManager.has_signal("meta_changed"):
		MetaManager.meta_changed.connect(_refresh)
	_refresh()

# ── Dock board host ────────────────────────────────────────────────────────────────
func _build_dock_host() -> void:
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(oc)
	_dock_host = HudEditScript.new()
	add_child(_dock_host)
	_dock_host.setup(oc, "dock", false)   # editable=false: runtime-only host, same pattern as the Level Up overlay
	var binder = _dock_host._binder
	if binder != null and binder.has_signal("room_clicked"):
		binder.room_clicked.connect(_on_room_clicked)

func _on_room_clicked(room: String) -> void:
	if room == "Launch":
		_open_panel(["mapselect"])
		return
	if ROOM_PANELS.has(room):
		_open_panel(ROOM_PANELS[room] as Array)
		return
	_show_toast(room + " — Coming soon")

func _launch_run(map_id: String = "default") -> void:
	MetaManager.selected_map_id = map_id
	var scene_path := String(MetaManager.MAP_DEFS.get(map_id, {}).get("scene", ARENA_SCENE))
	get_tree().change_scene_to_file(scene_path)

# ── Overlay panel (Loadout / Shop / Engineer's Passives·Craft·Fragments) ────────────
func _build_panel_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 13   # above the Dock host's own CanvasLayer (12)
	add_child(cl)

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	cl.add_child(_panel)

	_panel_dim = ColorRect.new()
	_panel_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_panel_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks/hover to the Dock board underneath
	_panel.add_child(_panel_dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	_panel.add_child(margin)

	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.75)
	sb.set_content_margin_all(20.0)
	pc.add_theme_stylebox_override("panel", sb)
	margin.add_child(pc)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pc.add_child(col)

	# Header: Back + coin/debug (Equipment/Shop only)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	col.add_child(header)
	var back := Button.new()
	back.text = "◀  BACK"
	_font_btn(back, 18)
	back.pressed.connect(_close_panel)
	header.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_coin_row = HBoxContainer.new()
	_coin_row.add_theme_constant_override("separation", 10)
	header.add_child(_coin_row)
	_coin_label = Label.new()
	_font(_coin_label, FONT_TITLE, 26, Color(1.0, 0.86, 0.3))
	_coin_row.add_child(_coin_label)
	var dbg := Button.new()
	dbg.text = "+1000 (debug)"
	_font_btn(dbg, 14)
	dbg.pressed.connect(func() -> void: GameManager.add_money(1000))
	_coin_row.add_child(dbg)

	# Sub-tab row (only populated/shown when a room has more than one tab, e.g. Engineer)
	_subtabs_row = HBoxContainer.new()
	_subtabs_row.add_theme_constant_override("separation", 8)
	col.add_child(_subtabs_row)

	# Scrollable content — same builders as before (_build_loadout/_build_shop/…)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

func _open_panel(tabs: Array) -> void:
	_available_tabs = tabs
	_tab = String(tabs[0])
	_rebuild_subtabs()
	_panel.visible = true
	_refresh()

func _close_panel() -> void:
	_panel.visible = false

func _rebuild_subtabs() -> void:
	for c in _subtabs_row.get_children():
		c.queue_free()
	_tab_buttons.clear()
	_subtabs_row.visible = _available_tabs.size() > 1
	if _available_tabs.size() <= 1:
		return
	for t in _available_tabs:
		var id := String(t)
		var b := Button.new()
		b.text = String(TAB_LABELS.get(id, id.to_upper()))
		_font_btn(b, 16)
		b.custom_minimum_size = Vector2(130, 36)
		b.pressed.connect(_switch_tab.bind(id))
		_subtabs_row.add_child(b)
		_tab_buttons[id] = b

func _switch_tab(t: String) -> void:
	_tab = t
	_refresh()

func _refresh() -> void:
	if _coin_label != null:
		_coin_label.text = "⬤ %d" % GameManager.money
	if _coin_row != null:
		_coin_row.visible = _tab in ["loadout", "shop"]
	for id: String in _tab_buttons.keys():
		var b: Button = _tab_buttons[id]
		b.modulate = Color(1, 1, 1) if id == _tab else Color(0.6, 0.6, 0.65)
	if _content == null or not _panel.visible:
		return
	for c in _content.get_children():
		c.queue_free()
	match _tab:
		"loadout":   _build_loadout()
		"shop":      _build_shop()
		"craft":     _build_craft()
		"fragments": _build_fragments()
		"passives":  _build_passives()
		"mapselect": _build_mapselect()

# ── Loadout ────────────────────────────────────────────────────────────────────
func _build_loadout() -> void:
	_header_row("Pick up to %d weapons to bring into your next run. Unlock more via Shop blueprints or Craft uniques." % ArenaWeapons.MAX_WEAPONS)
	var count_lbl := Label.new()
	_font(count_lbl, FONT_BODY, 14, Color(0.8, 0.85, 0.95))
	count_lbl.text = "%d / %d selected" % [MetaManager.loadout.size(), ArenaWeapons.MAX_WEAPONS]
	_content.add_child(count_lbl)

	var grid := _make_grid()
	var kinds: Array = MetaManager.unlocked_weapon_kinds()
	kinds.sort_custom(_sort_kind_by_rarity)
	for kind: String in kinds:
		var info: Dictionary = ArenaWeapons.WEAPON_INFO.get(kind, {})
		var def_id := String(info.get("def_id", ""))
		var d := InventoryManager.get_def(def_id) if def_id != "" else {}
		var wname := String(info.get("name", info.get("label", kind.capitalize())))
		var rarity := String(d.get("rarity", "common"))
		var group := String(d.get("group", ""))
		var picked := MetaManager.is_in_loadout(kind)
		var disabled := (not picked) and MetaManager.loadout_full()
		var cap_kind := kind
		grid.add_child(_make_grid_cell(def_id, wname, rarity, group, picked,
			"UNLOAD" if picked else "LOAD",
			func() -> void: MetaManager.toggle_loadout(cap_kind),
			disabled))

func _sort_kind_by_rarity(a: String, b: String) -> bool:
	var order := ["common", "uncommon", "rare", "very_rare", "unique", "legendary"]
	var da := String(ArenaWeapons.WEAPON_INFO.get(a, {}).get("def_id", ""))
	var db := String(ArenaWeapons.WEAPON_INFO.get(b, {}).get("def_id", ""))
	var ra := order.find(String(InventoryManager.get_def(da).get("rarity", "common")))
	var rb := order.find(String(InventoryManager.get_def(db).get("rarity", "common")))
	if ra != rb:
		return ra < rb
	return a < b

# ── Shop ───────────────────────────────────────────────────────────────────────
func _build_shop() -> void:
	_header_row("Buy weapons you've unlocked. Disassemble boss drops to learn more blueprints.")
	var ids: Array = MetaManager.blueprints.duplicate()
	ids.sort_custom(_sort_by_rarity)
	if ids.is_empty():
		_note("No blueprints known yet.")
	else:
		var grid := _make_grid()
		for def_id: String in ids:
			if InventoryManager.get_def(def_id).is_empty():
				continue
			var cap_id := def_id
			grid.add_child(_make_shop_cell(cap_id, func() -> void: MetaManager.buy_weapon(cap_id)))

	_header_row("Gear — hull, thruster, shield. Always in stock, no blueprint needed.")
	var gear: Array = MetaManager.gear_ids()
	gear.sort_custom(_sort_by_rarity)
	var ggrid := _make_grid()
	for def_id: String in gear:
		if InventoryManager.get_def(def_id).is_empty():
			continue
		var cap_id := def_id
		ggrid.add_child(_make_shop_cell(cap_id, func() -> void: MetaManager.buy_gear(cap_id)))

## One Shop grid cell: price button (or "OWNED" once at least one copy exists in the inventory).
func _make_shop_cell(def_id: String, on_buy: Callable) -> Control:
	var d := InventoryManager.get_def(def_id)
	var rarity := String(d.get("rarity", "common"))
	var group := String(d.get("group", ""))
	var price := MetaManager.blueprint_price(def_id)
	var owned := InventoryManager.owns_def(def_id)
	var afford := GameManager.can_afford(price) and InventoryManager.has_room_for(def_id)
	return _make_grid_cell(def_id, String(d.get("name", def_id)), rarity, group, owned,
		"OWNED" if owned else "%d ⬤" % price,
		on_buy,
		owned or not afford)

# ── Craft (assemble uniques) ──────────────────────────────────────────────────────
func _build_craft() -> void:
	_header_row("Assemble unique weapons once you've collected all their fragments.")
	for uid: String in MetaManager.unique_ids():
		var d := InventoryManager.get_def(uid)
		var have := MetaManager.owned_fragment_count(uid)
		var total := MetaManager.fragment_count(uid)
		var status := "%d / %d fragments" % [have, total]
		if MetaManager.is_unique_crafted(uid):
			status = "✔ crafted"
		var row := _item_row(String(d.get("name", uid)), String(d.get("rarity", "unique")), String(d.get("group", "")), status)
		var craft := Button.new()
		craft.text = "CRAFT"
		_font_btn(craft, 16)
		craft.custom_minimum_size = Vector2(90, 0)
		craft.disabled = not MetaManager.can_craft_unique(uid)
		craft.pressed.connect(func() -> void: MetaManager.craft_unique(uid))
		row.add_child(craft)

# ── Fragments (collection tracker) ────────────────────────────────────────────────
func _build_fragments() -> void:
	_header_row("Your unique-fragment collection. Fragments drop from bosses; owned pieces never drop again.")
	for uid: String in MetaManager.unique_ids():
		var d := InventoryManager.get_def(uid)
		var box := _card()
		var head := Label.new()
		var col: Color = InventoryManager.RARITY_COLORS.get(String(d.get("rarity", "unique")), Color.WHITE)
		_font(head, FONT_BODY, 18, col)
		head.text = "%s  (%d/%d)" % [String(d.get("name", uid)), MetaManager.owned_fragment_count(uid), MetaManager.fragment_count(uid)]
		box.add_child(head)
		var frags := MetaManager.fragment_names(uid)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		box.add_child(line)
		for i in frags.size():
			var chip := Label.new()
			var owned := MetaManager.is_fragment_owned(uid, i)
			_font(chip, FONT_BODY, 14, Color(0.55, 0.95, 0.5) if owned else Color(0.4, 0.4, 0.45))
			chip.text = ("● " if owned else "○ ") + String(frags[i])
			line.add_child(chip)

# ── Map Select (Launch) ─────────────────────────────────────────────────────────
func _build_mapselect() -> void:
	_header_row("Choose a map to launch into.")
	for map_id: String in MetaManager.MAP_DEFS.keys():
		var d: Dictionary = MetaManager.MAP_DEFS[map_id]
		var box := _card()
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		box.add_child(top)
		var name_lbl := Label.new()
		_font(name_lbl, FONT_TITLE, 20, Color(0.88, 0.92, 1.0))
		name_lbl.text = String(d.get("name", map_id))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var btn := Button.new()
		btn.text = "LAUNCH"
		_font_btn(btn, 16)
		btn.custom_minimum_size = Vector2(110, 0)
		var cap_id := map_id
		btn.pressed.connect(func() -> void: _launch_run(cap_id))
		top.add_child(btn)
		var desc := Label.new()
		_font(desc, FONT_BODY, 13, Color(0.6, 0.62, 0.68))
		desc.text = String(d.get("desc", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)

# ── Passives ───────────────────────────────────────────────────────────────────
func _build_passives() -> void:
	_header_row("Permanent upgrades — applied at the start of every run.")
	for id: String in MetaManager.PASSIVE_DEFS.keys():
		var d: Dictionary = MetaManager.PASSIVE_DEFS[id]
		var lvl := MetaManager.passive_level(id)
		var mx := MetaManager.passive_max(id)
		var cost := MetaManager.passive_cost(id)
		var row := _card()
		var top := HBoxContainer.new()
		row.add_child(top)
		var name_lbl := Label.new()
		_font(name_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
		name_lbl.text = "%s   [%d/%d]" % [String(d["name"]), lvl, mx]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var buy := Button.new()
		if cost < 0:
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = "%d ⬤" % cost
			buy.disabled = not GameManager.can_afford(cost)
		_font_btn(buy, 16)
		buy.custom_minimum_size = Vector2(120, 0)
		buy.pressed.connect(func() -> void: MetaManager.buy_passive(id))
		top.add_child(buy)
		var desc := Label.new()
		_font(desc, FONT_BODY, 13, Color(0.6, 0.62, 0.68))
		desc.text = String(d["desc"])
		row.add_child(desc)

# ── Thumbnail grid cells (Loadout / Shop) ─────────────────────────────────────────────
func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", int(CELL_GAP))
	grid.add_theme_constant_override("v_separation", int(CELL_GAP))
	_content.add_child(grid)
	return grid

## One thumbnail cell: icon + name + rarity/type tags, with a hover-reveal action button that slides up
## from the bottom edge (clipped out of view until hovered). `active` drives the blue/orange background
## (not-loaded/not-owned vs loaded/owned) — Loadout uses it for "in loadout", Shop uses it for "owned a copy".
func _make_grid_cell(icon_def_id: String, item_name: String, rarity: String, tag2: String, active: bool,
		btn_text: String, on_press: Callable, btn_disabled: bool) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
	cell.clip_contents = true
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GRID_BG_ON if active else GRID_BG_OFF
	sb.set_corner_radius_all(8)
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top  = 1; sb.border_width_bottom = 1
	sb.border_color = InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)
	bg.add_theme_stylebox_override("panel", sb)
	cell.add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 6.0; vb.offset_right = -6.0
	vb.offset_top  = 7.0; vb.offset_bottom = -7.0
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(vb)

	var icon_wrap := CenterContainer.new()
	icon_wrap.custom_minimum_size = Vector2(0, ICON_SIZE)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon_wrap)
	var tr := TextureRect.new()
	tr.texture = InventoryManager.get_icon(icon_def_id)
	tr.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # scale the source icon DOWN to fit the slot instead of clipping it
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(tr)

	var name_lbl := Label.new()
	_font(name_lbl, FONT_BODY, 10, Color(0.92, 0.94, 0.98))
	name_lbl.text = item_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(0, 24)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 3)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tags)
	tags.add_child(_tag_chip(String(RARITY_LABEL.get(rarity, rarity)), InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)))
	if tag2 != "":
		tags.add_child(_tag_chip(tag2.capitalize(), Color(0.6, 0.65, 0.75)))

	# Action label — purely visual now (flush with the cell's bottom edge, covering the tag row), only
	# `visible` toggles on hover. The CLICK itself is handled by `cell` below, for the whole tile: this
	# label has mouse_filter IGNORE so it never intercepts input (a Button here previously ate clicks
	# aimed at it and also caused a cell/button mouse_entered↔exited flicker that hid it mid-hover).
	var btn := Button.new()
	btn.text = btn_text
	_font_btn(btn, 10)
	btn.disabled = btn_disabled   # visual only (greys it out) — mouse_filter IGNORE below makes it non-interactive regardless
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.anchor_left = 0.0; btn.anchor_right = 1.0
	btn.anchor_top  = 1.0; btn.anchor_bottom = 1.0
	btn.offset_left = 0.0; btn.offset_right = 0.0
	btn.offset_top    = -REVEAL_BTN_H
	btn.offset_bottom = 0.0
	btn.visible = false
	cell.add_child(btn)

	cell.mouse_entered.connect(func() -> void: _reveal_btn(btn, true))
	cell.mouse_exited.connect(func() -> void: _reveal_btn(btn, false))
	# Whole-tile click — not just the small label — triggers the action (LOAD/UNLOAD in Loadout, BUY in Shop).
	if not btn_disabled:
		cell.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_press.call())
	return cell

## Reveal/hide the hover action button. `visible` (not a clipped offset) drives the input-relevant state;
## the modulate tween is purely cosmetic (a quick fade so it doesn't just pop).
func _reveal_btn(btn: Button, show: bool) -> void:
	if not is_instance_valid(btn):
		return
	if show:
		btn.modulate.a = 0.0
		btn.visible = true
		var tw := create_tween()
		tw.tween_property(btn, "modulate:a", 1.0, 0.12)
	else:
		btn.visible = false

func _tag_chip(text: String, col: Color) -> Label:
	var l := Label.new()
	_font(l, FONT_BODY, 8, col)
	l.text = text
	return l

# ── Small UI builders ─────────────────────────────────────────────────────────────
func _item_row(name: String, rarity: String, group: String, right_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var panel := _card()
	panel.add_child(row)
	var n := Label.new()
	var rcol: Color = InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)
	_font(n, FONT_BODY, 18, rcol)
	n.text = name
	n.custom_minimum_size = Vector2(280, 0)
	row.add_child(n)
	var meta := Label.new()
	_font(meta, FONT_BODY, 13, Color(0.55, 0.58, 0.64))
	meta.text = "%s · %s" % [String(RARITY_LABEL.get(rarity, rarity)), group.capitalize()]
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(meta)
	var rt := Label.new()
	_font(rt, FONT_BODY, 16, Color(1.0, 0.86, 0.3))
	rt.text = right_text
	rt.custom_minimum_size = Vector2(120, 0)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(rt)
	return row

func _card() -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.18)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	_content.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	return v

func _header_row(text: String) -> void:
	var l := Label.new()
	_font(l, FONT_BODY, 14, Color(0.6, 0.65, 0.72))
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)

func _note(text: String) -> void:
	var l := Label.new()
	_font(l, FONT_BODY, 16, Color(0.5, 0.5, 0.55))
	l.text = text
	_content.add_child(l)

func _font(lbl: Label, path: String, size: int, col: Color) -> void:
	var f := load(path) as Font
	if f != null:
		lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_btn(btn: Button, size: int) -> void:
	var f := load(FONT_BODY) as Font
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", size)

func _sort_by_rarity(a: String, b: String) -> bool:
	var order := ["common", "uncommon", "rare", "very_rare", "unique", "legendary"]
	var ra := order.find(String(InventoryManager.get_def(a).get("rarity", "common")))
	var rb := order.find(String(InventoryManager.get_def(b).get("rarity", "common")))
	if ra != rb:
		return ra < rb
	return a < b

# ── Toast ("Coming soon" for rooms with no system yet) ─────────────────────────────
func _build_toast() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 14   # above the overlay panel (13) too, so it's readable even if a panel is open
	add_child(cl)
	_toast = Label.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_font(_toast, FONT_BODY, 24, Color(1.0, 0.85, 0.2))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left   = -220.0
	_toast.offset_right  = 220.0
	_toast.offset_top    = -120.0
	_toast.offset_bottom = -80.0
	cl.add_child(_toast)

func _show_toast(message: String) -> void:
	if _toast == null:
		return
	_toast.text = message
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
