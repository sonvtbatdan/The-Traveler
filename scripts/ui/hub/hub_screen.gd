extends Control
## Hub — the between-run home screen. Hosts the authored "Dock" board (assets/hud/dock/, see
## board_defs.gd + dock_binder.gd) as the main view instead of a hand-built tab UI. Clicking a room with a
## real system behind it opens an overlay panel reusing the SAME tab-content builders the old hand-built
## Hub used (just triggered by a room click instead of a tab button):
##   Equipment → Loadout   Merchant → Shop   Engineer → Craft / Fragments (2 sub-tabs)
##   Constructor → Pilot Room upgrades + (once Mechanic rescued) Trading Hub + Passives — ONE combined
##     "construction" tab (2026-08-06, on request: Passives moved here entirely, out of Engineer).
## ("Merchant" is display-only, renamed from "Mechanic" 2026-08-05 — see dock_binder.gd's ROOM_NAME_OVERRIDE;
## ROOM_PANELS below keys off the OVERRIDDEN name since that's what room_clicked now actually emits.)
##   Launch    → still launches a run directly — no map-select system exists yet to gate it on
## Everything else (Codex/Trophy/Bridge/Instructor/Beacon) has no system behind it yet — clicking shows a
## "Coming Soon" toast (see dock_binder.gd's doc comment for the full room→destination map).
## All state lives in MetaManager + GameManager (coins).

const ARENA_SCENE := "res://scenes/arena.tscn"
const ArenaScript := preload("res://scripts/gameplay/arena.gd")   # for the WEAPON_TEST_MODE flag (skip this launch page)
const InventoryUIScript := preload("res://scripts/ui/inventory/inventory_ui.gd")   # equip screen (I key)
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")   # WEAPON_INFO/MAX_WEAPONS for the Loadout tab
const HudEditScript := preload("res://scripts/ui/boss_edit/hud_edit_mode.gd")
const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/mandalore/mandalore.ttf"
const COIN_ICON_PATH := "res://assets/screen/coin.png"   # 2026-08-06: real coin art, replaces the "⬤" text glyph
const COIN_ICON_SIZE := 26.0                              # header coin total — sized to sit flush with the 26pt coin label
const PREVIEW_PANEL_W   := 460.0   # Merchant detail panel, right of the item grid (260 +200px, on request)
const PREVIEW_ICON_SIZE := 128.0
const MERCHANT_GRID_COLS     := 5     # Merchant's own grid — Loadout keeps GRID_COLS (4) unchanged, on request
const MERCHANT_GRID_SCROLL_H := 460.0 # grid's own scroll viewport height (under the outer panel's 520px budget)

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
	"Equipment":   ["loadout"],
	"Merchant":    ["weapon", "hull", "thruster", "shield", "aux"],   # was one flat "shop" tab — split 2026-08-05
	"Engineer":    ["craft"],   # 2026-08-07, on request: Craft + Fragments merged into one slot-list tab (was 2 sub-tabs)
	"Constructor": ["construction"],   # Pilot Room upgrades + (once Mechanic rescued) Trading Hub + Passives —
	                                    # 2026-08-06, on request: Passives MOVED here from Engineer entirely.
}
const TAB_LABELS := {
	"loadout": "LOADOUT", "craft": "CRAFT", "passives": "PASSIVES", "mapselect": "SELECT MAP",
	"weapon": "WEAPON", "hull": "HULL", "thruster": "THRUSTER", "shield": "SHIELD", "aux": "AUX",
	"construction": "CONSTRUCTION",
}
# Merchant sub-tabs that are gear (never need a blueprint — coin only) vs. the one that does. Drives both the
# _build_gear_category() header text and _make_merchant_cell()'s blueprint-gray logic.
const MERCHANT_GEAR_TABS := ["hull", "thruster", "shield", "aux"]

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
var _merchant_selected_id: String = ""     # currently previewed Merchant item (persists across _refresh(),
var _merchant_selected_is_gear: bool = false   # cleared on tab switch — see _switch_tab)
var _scroll: ScrollContainer = null
var _mapselect_grid: GridContainer = null
var _dock_host = null   # HudEditScript surface hosting the "dock" board

func _ready() -> void:
	if ArenaScript.WEAPON_TEST_MODE:
		# Weapon-test mode: don't show the launch page — boot straight into the arena (which auto-opens F12).
		call_deferred("_goto_arena")
		return
	_build_dock_host()
	_build_panel_ui()
	_build_toast()
	_build_main_menu_button()
	add_child(InventoryUIScript.new())   # I key here too — equip Gear (hull/thruster/shield) + browse Cargo before launching
	if GameManager.has_signal("money_changed"):
		GameManager.money_changed.connect(func(_m: int) -> void: _refresh())
	if MetaManager.has_signal("meta_changed"):
		MetaManager.meta_changed.connect(_on_meta_changed)
	# Dock-interest notification (2026-08-05, on request): arena.gd's two "RETURN TO DOCK" handlers stash
	# the payout here right before the scene change; shown exactly once per dock arrival, then cleared.
	if GameManager.pending_interest_notice > 0:
		var interest_amt := GameManager.pending_interest_notice
		GameManager.pending_interest_notice = 0
		_show_interest_notification(interest_amt)
	# Room-unlock notifications queued while away from the Dock (mid-run boss kill, etc. — see
	# GameManager.pending_room_unlock_notices' doc comment). Unlocks that happen WHILE already on the
	# Dock (e.g. buying a weapon) are instead caught live by _on_meta_changed below.
	_drain_room_unlock_notices()

func _on_meta_changed() -> void:
	_refresh()
	_drain_room_unlock_notices()

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
	back.text = MandaloreText.a("◀  BACK")
	_font_btn(back, 18)
	back.pressed.connect(_close_panel)
	header.add_child(back)
	HudEditRuntime.register(back, "dock.chrome.back_btn")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_coin_row = HBoxContainer.new()
	_coin_row.add_theme_constant_override("separation", 6)
	header.add_child(_coin_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = load(COIN_ICON_PATH) as Texture2D
	coin_icon.custom_minimum_size = Vector2(COIN_ICON_SIZE, COIN_ICON_SIZE)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_row.add_child(coin_icon)
	HudEditRuntime.register(coin_icon, "dock.chrome.coin_icon")
	_coin_label = Label.new()
	_font(_coin_label, FONT_TITLE, 26, Color(1.0, 0.86, 0.3))
	_coin_row.add_child(_coin_label)
	HudEditRuntime.register(_coin_label, "dock.chrome.coin_label")
	var dbg := Button.new()
	dbg.text = MandaloreText.a("+1000 (debug)")
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
	_scroll = scroll
	_scroll.resized.connect(_on_scroll_resized)

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
		b.text = MandaloreText.a(String(TAB_LABELS.get(id, id.to_upper())))
		_font_btn(b, 16)
		b.custom_minimum_size = Vector2(130, 36)
		b.pressed.connect(_switch_tab.bind(id))
		_subtabs_row.add_child(b)
		_tab_buttons[id] = b
		HudEditRuntime.register(b, "dock.chrome.subtab." + id)

func _switch_tab(t: String) -> void:
	_tab = t
	_merchant_selected_id = ""   # forget the previous tab's preview pick — the new tab defaults to its 1st item
	_refresh()

func _refresh() -> void:
	if _coin_label != null:
		_coin_label.text = "%d" % GameManager.money   # coin icon (built in _build_panel_ui) replaces the old "⬤" glyph
	if _coin_row != null:
		_coin_row.visible = _tab in ["loadout", "weapon", "hull", "thruster", "shield", "aux"]
	for id: String in _tab_buttons.keys():
		var b: Button = _tab_buttons[id]
		b.modulate = Color(1, 1, 1) if id == _tab else Color(0.6, 0.6, 0.65)
	if _content == null or not _panel.visible:
		return
	for c in _content.get_children():
		c.queue_free()
	match _tab:
		"loadout":   _build_loadout()
		"weapon":    _build_weapon_shop()
		"hull":      _build_gear_category("hull", "Hull")
		"thruster":  _build_gear_category("thruster", "Thruster")
		"shield":    _build_gear_category("shield", "Shield")
		"aux":       _build_gear_category("aux", "Aux")
		"craft":     _build_craft()
		"passives":  _build_passives()
		"construction": _build_construction()
		"mapselect": _build_mapselect()

# ── Loadout ────────────────────────────────────────────────────────────────────
func _build_loadout() -> void:
	_header_row("Pick up to %d weapons to bring into your next run. Unlock more via Shop blueprints or Craft uniques." % ArenaWeapons.MAX_WEAPONS)
	var count_lbl := Label.new()
	_font(count_lbl, FONT_BODY, 14, Color(0.8, 0.85, 0.95))
	count_lbl.text = MandaloreText.a("%d / %d selected" % [MetaManager.loadout.size(), ArenaWeapons.MAX_WEAPONS])
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

# ── Merchant (2026-08-05: split from one flat "Shop" tab into 5 category tabs, on request) ────────────────
## Weapon tab: EVERY non-unique weapon def is shown (not just blueprint-owned ones, per explicit request) —
## no-blueprint ones render blueprint-gray. CHEST_POOL weapons (gatling_gun/death_beam/arc/gauss) are the one
## exception: MetaManager.buy_weapon() lets those be bought for coin alone, so they never show the
## blueprint-gray state (see _make_merchant_cell's needs_blueprint calc).
func _build_weapon_shop() -> void:
	_build_merchant_tab(MetaManager.shop_ids_by_tag("weapon"), false,
		"Buy any weapon you've unlocked outright. Weapons still needing a blueprint show grayed out — earn theirs from boss-drop disassembly, or buy the 4 starter-tier weapons (Gatling/Death Beam/Arc/Gauss) for coin alone.")

## Hull/Thruster/Shield/Aux tabs: never blueprint-gated (MetaManager.buy_gear() has no blueprint check at
## all) — every item just shows OWNED / affordable / too-expensive.
func _build_gear_category(tag: String, label: String) -> void:
	_build_merchant_tab(MetaManager.shop_ids_by_tag(tag), true, "%s — always in stock, no blueprint needed." % label)

## Shared by all 5 Merchant tabs (2026-08-06 rebuild, on request): item grid on the left, a fixed detail
## preview panel on the right (large icon, stats, description, price, Buy button) — replaces the old
## hover-tooltip + click-to-buy-directly design. Clicking a grid cell now just SELECTS it into the preview;
## the actual purchase happens from the preview panel's own Buy button. `_merchant_selected_id` persists
## across `_refresh()` calls within the same tab (cleared in `_switch_tab`) so buying something doesn't
## reset your place; defaults to the first item in the list if nothing (valid) is selected yet.
func _build_merchant_tab(ids: Array, is_gear: bool, header_text: String) -> void:
	_header_row(header_text)
	ids.sort_custom(_sort_by_rarity)
	if ids.is_empty():
		_note("Nothing in this category yet.")
		return
	if _merchant_selected_id == "" or not (_merchant_selected_id in ids):
		_merchant_selected_id = String(ids[0])
		_merchant_selected_is_gear = is_gear

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_content.add_child(row)

	# The grid gets ITS OWN ScrollContainer (2026-08-06, on request) — separate from the outer panel scroll
	# (`scroll`, built once in _build_panel_ui, still wraps `_content` as a whole) and, critically, separate
	# from the preview panel beside it, which must never scroll. Fixed to MERCHANT_GRID_SCROLL_H (comfortably
	# under the outer scroll's own 520px budget, leaving room for the header line above) so the outer scroll
	# never actually needs to activate for a Merchant tab — only this inner one does, once there are enough
	# items to overflow it.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.custom_minimum_size = Vector2(0, MERCHANT_GRID_SCROLL_H)
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(grid_scroll)
	var grid := GridContainer.new()
	grid.columns = MERCHANT_GRID_COLS
	grid.add_theme_constant_override("h_separation", int(CELL_GAP))
	grid.add_theme_constant_override("v_separation", int(CELL_GAP))
	grid_scroll.add_child(grid)
	for def_id: String in ids:
		grid.add_child(_make_merchant_cell(def_id, is_gear))

	var preview := _build_merchant_preview(_merchant_selected_id, _merchant_selected_is_gear)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL   # stretch to match grid_scroll's height, so its
	row.add_child(preview)                                    # own bottom-pinned Buy button lands correctly

## One Merchant grid cell. Two DIFFERENT texts now (2026-08-06, on request):
##   the always-visible persistent label on the thumbnail → the item's PRICE (or "Owned")
##   the hover-reveal button + the preview panel's own Buy button → the STATE WORD:
##     owned → "Owned" | needs a blueprint → "Blue Print Required" (gray bg + gray price)
##     too expensive → "Not Enough Coin" (red price) | affordable, unowned → "Buy"
## Clicking ANY cell (including gray/red ones) just selects it into the preview panel — it never buys
## directly anymore, so there's no toast/message here; the preview panel's Buy button owns that now.
func _make_merchant_cell(def_id: String, is_gear: bool) -> Control:
	var d := InventoryManager.get_def(def_id)
	var rarity := String(d.get("rarity", "common"))
	var group := String(d.get("group", ""))
	var owned := InventoryManager.owns_def(def_id)
	var needs_blueprint := _merchant_needs_blueprint(def_id, is_gear)
	var afford := GameManager.can_afford(MetaManager.blueprint_price(def_id))
	var cap_id := def_id
	var cap_is_gear := is_gear
	var on_press := func() -> void:
		_merchant_selected_id = cap_id
		_merchant_selected_is_gear = cap_is_gear
		_refresh()

	var price_text := "Owned" if owned else str(MetaManager.blueprint_price(def_id))
	var bg_override := Color(0.30, 0.30, 0.32, 0.65) if (not owned and needs_blueprint) else Color(0, 0, 0, 0)
	var cell := _make_grid_cell(def_id, String(d.get("name", def_id)), rarity, group, owned,
		_merchant_state_text(owned, needs_blueprint, afford), on_press, false,
		_merchant_state_color(owned, needs_blueprint, afford), bg_override, true, price_text)
	return cell

func _merchant_needs_blueprint(def_id: String, is_gear: bool) -> bool:
	return (not is_gear) and (not MetaManager.has_blueprint(def_id)) and not (def_id in ArenaWeapons.CHEST_POOL)

func _merchant_state_text(owned: bool, needs_blueprint: bool, afford: bool) -> String:
	if owned: return "Owned"
	if needs_blueprint: return "Blue Print Required"
	if not afford: return "Not Enough Coin"
	return "Buy"

func _merchant_state_color(owned: bool, needs_blueprint: bool, afford: bool) -> Color:
	if not owned and needs_blueprint: return Color(0.55, 0.55, 0.58)
	if not owned and not afford: return Color(1.0, 0.35, 0.3)
	return Color(1, 1, 1)

## Right-side detail panel: big icon, name, price (icon + number — the ONLY place a Merchant price still
## shows, since the grid cells now show state words instead), description, every scalar `stats` key/value,
## and a Buy button that dims + shows the same state word when not actually purchasable.
func _build_merchant_preview(def_id: String, is_gear: bool) -> Control:
	var d := InventoryManager.get_def(def_id)
	var rarity := String(d.get("rarity", "common"))
	var rarity_col: Color = InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = rarity_col
	sb.set_content_margin_all(14.0)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(PREVIEW_PANEL_W, 0.0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var icon_wrap := CenterContainer.new()
	vb.add_child(icon_wrap)
	var tr := TextureRect.new()
	tr.texture = InventoryManager.get_icon(def_id)
	tr.custom_minimum_size = Vector2(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_wrap.add_child(tr)
	HudEditRuntime.register(tr, "dock.merchant.preview.icon")

	# 2026-08-06, on request: this whole panel uses the engine's DEFAULT font — every label below sets only
	# size/color (_font_sz/_font_sz_btn), deliberately skipping the "font" theme override _font()/_font_btn()
	# apply everywhere else in this file (FONT_TITLE/FONT_BODY).
	var name_lbl := Label.new()
	_font_sz(name_lbl, 18, rarity_col)
	name_lbl.text = String(d.get("name", def_id))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(name_lbl)
	HudEditRuntime.register(name_lbl, "dock.merchant.preview.name")

	var owned := InventoryManager.owns_def(def_id)
	if not owned:
		var price_row := HBoxContainer.new()
		price_row.alignment = BoxContainer.ALIGNMENT_CENTER
		price_row.add_theme_constant_override("separation", 4)
		vb.add_child(price_row)
		var pic := TextureRect.new()
		pic.texture = load(COIN_ICON_PATH) as Texture2D
		pic.custom_minimum_size = Vector2(18.0, 18.0)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		price_row.add_child(pic)
		HudEditRuntime.register(pic, "dock.merchant.preview.price_icon")
		var price_lbl := Label.new()
		_font_sz(price_lbl, 16, Color(1.0, 0.86, 0.3))
		price_lbl.text = str(MetaManager.blueprint_price(def_id))
		price_row.add_child(price_lbl)
		HudEditRuntime.register(price_lbl, "dock.merchant.preview.price")

	var desc := String(d.get("desc", ""))
	if desc != "":
		var desc_lbl := Label.new()
		_font_sz(desc_lbl, 12, Color(0.75, 0.78, 0.85))
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vb.add_child(desc_lbl)
		HudEditRuntime.register(desc_lbl, "dock.merchant.preview.desc")

	var stats: Dictionary = d.get("stats", {})
	var stat_parts: Array = []
	for k: String in stats:
		var v = stats[k]
		if v is Dictionary:   # e.g. kind_bonus {"fire":30,"explosive":30} — skip, not a simple scalar
			continue
		stat_parts.append("%s: %s" % [String(k).capitalize(), str(v)])
	if not stat_parts.is_empty():
		var stats_lbl := Label.new()
		_font_sz(stats_lbl, 12, Color(0.6, 0.85, 0.95))
		stats_lbl.text = "\n".join(stat_parts)
		stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vb.add_child(stats_lbl)
		HudEditRuntime.register(stats_lbl, "dock.merchant.preview.stats")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	var needs_blueprint := _merchant_needs_blueprint(def_id, is_gear)
	var afford := GameManager.can_afford(MetaManager.blueprint_price(def_id))
	var purchasable := not owned and not needs_blueprint and afford
	var buy_btn := Button.new()
	buy_btn.text = _merchant_state_text(owned, needs_blueprint, afford)
	_font_sz_btn(buy_btn, 16)
	buy_btn.custom_minimum_size = Vector2(0, 40)
	buy_btn.disabled = not purchasable
	buy_btn.modulate.a = 1.0 if purchasable else 0.55   # "mờ đi" when not buyable, per request
	var cap_id := def_id
	var cap_is_gear := is_gear
	buy_btn.pressed.connect(func() -> void:
		if not InventoryManager.has_room_for(cap_id):
			_show_toast("Backpack is full")
			return
		if cap_is_gear: MetaManager.buy_gear(cap_id)
		else:           MetaManager.buy_weapon(cap_id))
	vb.add_child(buy_btn)
	HudEditRuntime.register(buy_btn, "dock.merchant.preview.buy_btn")

	return panel

# ── Craft (2026-08-07: merged with the old separate Fragments tab into one slot list, on request) ─────────
# Each row is a "slot": icon + name on the left, that unique's fragment checklist + a Craft button on the
# right. Bullet convention carried over unchanged from the old Fragments tab: ○ gray = not owned, ● green =
# owned. Craft button is Godot's normal `disabled` state (grays itself out via the theme) until every
# fragment is owned — same can_craft_unique() gate as before, just relocated next to its own fragment list
# instead of living in a separate tab. No manual _refresh() needed after crafting — MetaManager.meta_changed
# (emitted by craft_unique()) is already connected to _refresh directly (see _ready()).
const CRAFT_ICON_SIZE := 96.0
func _build_craft() -> void:
	_header_row("Assemble unique weapons once you've collected all their fragments. Fragments drop from bosses; owned pieces never drop again.")
	for uid: String in MetaManager.unique_ids():
		var d := InventoryManager.get_def(uid)
		var rarity := String(d.get("rarity", "unique"))
		var rcol: Color = InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)
		var box := _card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)

		# Left: icon + name — the "slot".
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 4)
		slot.custom_minimum_size = Vector2(CRAFT_ICON_SIZE + 8.0, 0.0)
		row.add_child(slot)
		var icon_wrap := CenterContainer.new()
		slot.add_child(icon_wrap)
		var tr := TextureRect.new()
		tr.texture = InventoryManager.get_icon(uid)
		tr.custom_minimum_size = Vector2(CRAFT_ICON_SIZE, CRAFT_ICON_SIZE)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_wrap.add_child(tr)
		HudEditRuntime.register(tr, "dock.craft.slot.icon." + uid)
		var name_lbl := Label.new()
		_font(name_lbl, FONT_BODY, 15, rcol)
		name_lbl.text = MandaloreText.a(String(d.get("name", uid)))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_lbl.custom_minimum_size = Vector2(CRAFT_ICON_SIZE + 8.0, 0.0)
		slot.add_child(name_lbl)
		HudEditRuntime.register(name_lbl, "dock.craft.slot.name." + uid)

		# Right: fragment checklist on top, Craft button below.
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 8)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(right)

		var frags := MetaManager.fragment_names(uid)
		var frag_list := VBoxContainer.new()
		frag_list.add_theme_constant_override("separation", 3)
		right.add_child(frag_list)
		for i in frags.size():
			var chip := Label.new()
			var owned := MetaManager.is_fragment_owned(uid, i)
			_font(chip, FONT_BODY, 14, Color(0.55, 0.95, 0.5) if owned else Color(0.55, 0.55, 0.6))
			chip.text = MandaloreText.a(("● " if owned else "○ ") + String(frags[i]))
			frag_list.add_child(chip)

		var craft := Button.new()
		craft.text = MandaloreText.a("✔ CRAFTED" if MetaManager.is_unique_crafted(uid) else "CRAFT")
		_font_btn(craft, 16)
		craft.custom_minimum_size = Vector2(140, 0)
		craft.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		craft.disabled = not MetaManager.can_craft_unique(uid)
		var cap_uid := uid
		craft.pressed.connect(func() -> void: MetaManager.craft_unique(cap_uid))
		right.add_child(craft)
		HudEditRuntime.register(craft, "dock.craft.slot.craft_btn." + uid)

# ── Map Select (Launch) ─────────────────────────────────────────────────────────
## 6-thumbnail portrait grid — a superset of MetaManager.MAP_DEFS: entries WITH a "map_id" reference a real,
## playable map (must exist in MAP_DEFS — clicking launches it); entries WITHOUT one are "coming soon"
## placeholders (clicking shows a toast instead, same convention as _on_room_clicked's un-implemented Dock
## rooms). Order here is the grid's display order. Thumbnails are pre-baked 3:4 portrait crops of each map's
## own ground art (tools/generate_map_thumbnails.py — user feedback: "Sử dụng cảnh Canopy để làm thumbnail");
## "coming soon" entries have no thumbnail, so _make_map_card() falls back to a plain "?" placeholder.
const LAUNCH_CARDS := [
	{"map_id": "default", "name": "Space", "thumb": "res://assets/hud/mapselect/space_thumb.png"},
	{"map_id": "electric", "name": "Electric", "thumb": "res://assets/hud/mapselect/electric_thumb.png"},
	{"map_id": "volcanic", "name": "Volcanic", "thumb": "res://assets/hud/mapselect/volcanic_thumb.png"},
	{"map_id": "atlantic", "name": "Atlantic", "thumb": "res://assets/hud/mapselect/atlantic_thumb.png"},   # thumb not baked yet (awaiting the 3 canopy photos) — falls back to the "?" placeholder until tools/generate_map_thumbnails.py runs for this set
	{"map_id": "mechanic", "name": "Mechanic", "thumb": "res://assets/hud/mapselect/mechanic_thumb.png"},   # 2026-08-19 fix: was pointing straight at the raw SQUARE source canopy photo, which STRETCH_SCALE then squashed into the 3:4 portrait card box ("ép dẹp") — now a properly center-cropped 480x640 bake via tools/generate_map_thumbnails.py, same as every other real map
	{"map_id": "arctic", "name": "Arctic", "thumb": "res://assets/hud/mapselect/arctic_thumb.png"},   # 2026-08-19: blend canopy/plume/cloud/river built, mirrors Mechanic — see [[traveler_rubicon_ruin_landmarks]] for the Engineer rescue tie-in still pending
	{"name": "Cosmic"},   # 2026-08-17: named (was "???") — 8-map plan (2 boss/map, semi-boss@15m + final@30m),
	{"name": "Mystic"},   # slot 7/8. Still no theme/scene/enemy set — empty assets/map/cosmic|mystic/ folders
	                      # created for sprites; needs a real MAP_DEFS entry once it's built out
]
const MAPSELECT_CARD_W := 300.0   # aspect-ratio reference only (3:4 portrait) — actual on-screen size is
const MAPSELECT_CARD_H := 400.0   # computed per-frame by _fit_mapselect_grid() to exactly fill the panel.
const MAPSELECT_COLS := 3
const MAPSELECT_GAP := 18.0
const MAPSELECT_CORNER_RADIUS := 10.0   # must match the card border's own corner_radius below — the shader
                                         # masks the thumbnail to the SAME rounded rect so its corners don't
                                         # cover the border's rounding (a plain rectangular image drawn on top
                                         # of a rounded-corner Panel hides the rounding entirely otherwise).
const MAPSELECT_HOVER_ZOOM := 1.05      # user feedback: "khi hover thì phóng to ảnh ở trong lên 5%"
                                         # ("(viền giữ nguyên kích thước)" — the border must NOT grow with it;
                                         # only the thumbnail's own node scales, and card.clip_contents crops
                                         # the zoomed image back down to the card's fixed outer rect)

## Rounded-rect alpha mask (canvas_item shader) applied to each map-card thumbnail — see MAPSELECT_CORNER_
## RADIUS above for why this exists. Standard rounded-box SDF: distance from the pixel to the nearest edge of
## a rect inset by `corner_radius`, clamped so straight edges get distance 0 (no rounding) — pixels beyond
## `corner_radius` past that inset rect are faded to transparent.
const MAPSELECT_ROUNDED_SHADER_CODE := """
shader_type canvas_item;

uniform float corner_radius = 10.0;
uniform vec2 rect_size = vec2(100.0, 100.0);

void fragment() {
	vec2 pos = UV * rect_size;
	vec2 center = rect_size * 0.5;
	vec2 half_size = max(center - corner_radius, vec2(0.0));
	vec2 d = abs(pos - center) - half_size;
	float dist = length(max(d, vec2(0.0))) - corner_radius;
	float alpha = 1.0 - smoothstep(-1.0, 1.0, dist);
	COLOR = texture(TEXTURE, UV) * alpha;
}
"""
static var _mapselect_rounded_shader: Shader = null

## User feedback: card size used to be the fixed MAPSELECT_CARD_W/H constants above, which meant the 3x2 grid
## routinely overflowed the panel and forced a scrollbar ("tính toán cho vừa với khung menu... để không phải
## cuộn"). Cards are built at the placeholder constant size (so the GridContainer has SOMETHING to lay out
## immediately), then _fit_mapselect_grid() — deferred one idle frame, once _scroll's own size has actually
## settled from its parent containers' layout pass — resizes every card to the largest 3:4 size that fits
## MAPSELECT_COLS x rows inside _scroll's real available area, both axes, so the grid exactly fills the panel
## with no scrolling needed (a leftover ScrollContainer stays as a harmless fallback for extreme window sizes).
func _build_mapselect() -> void:
	_header_row("Choose a map to launch into. Hover a thumbnail for its name.")
	var header_lbl: Label = _content.get_child(_content.get_child_count() - 1)
	var grid := GridContainer.new()
	grid.columns = MAPSELECT_COLS
	grid.add_theme_constant_override("h_separation", int(MAPSELECT_GAP))
	grid.add_theme_constant_override("v_separation", int(MAPSELECT_GAP))
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(center)
	center.add_child(grid)
	for entry: Dictionary in LAUNCH_CARDS:
		grid.add_child(_make_map_card(entry))
	_mapselect_grid = grid
	_stabilize_and_fit_mapselect_grid(grid, header_lbl)

## A single call_deferred() wasn't reliably enough — the panel was just made visible this same frame, and
## Godot's Container layout skips invisible subtrees, so margin->pc->col->scroll can take more than one idle
## pass to fully converge on their real sizes once made visible. Wait for _scroll.size to stop changing
## between consecutive frames (capped at 6 tries) before fitting.
func _stabilize_and_fit_mapselect_grid(grid: GridContainer, header_lbl: Label) -> void:
	var prev_size := Vector2(-1.0, -1.0)
	for _i in range(6):
		await get_tree().process_frame
		if not is_instance_valid(grid) or _scroll == null or not is_instance_valid(_scroll):
			return
		if _scroll.size == prev_size:
			break
		prev_size = _scroll.size
	_fit_mapselect_grid(grid, header_lbl)

## Re-fit on window/panel resize too (e.g. user resizes the game window while this tab is open) — _scroll
## persists across tabs so this signal stays connected regardless of which tab is currently active; it's a
## no-op unless the mapselect grid is the one currently built.
func _on_scroll_resized() -> void:
	if _mapselect_grid != null and is_instance_valid(_mapselect_grid) and _tab == "mapselect":
		var header_lbl: Label = _content.get_child(0)
		_fit_mapselect_grid(_mapselect_grid, header_lbl)

func _fit_mapselect_grid(grid: GridContainer, header_lbl: Label) -> void:
	if not is_instance_valid(grid) or _scroll == null or not is_instance_valid(_scroll):
		return
	var rows := int(ceil(float(LAUNCH_CARDS.size()) / float(MAPSELECT_COLS)))
	var avail: Vector2 = _scroll.size
	if avail.x <= 1.0 or avail.y <= 1.0:
		return   # container hasn't completed a layout pass yet (e.g. panel not visible) — placeholder size stands
	# The header label ABOVE the grid shares the same scrollable _content column — its rendered height (plus
	# _content's own "separation" constant, 6px) eats into the space actually left for the grid. Missing this
	# was the original bug: the grid was sized to fill _scroll's FULL height, header included, so total
	# content (header + grid) still overflowed _scroll by exactly the header's height, leaving a scrollbar.
	var header_h: float = header_lbl.size.y + 6.0 if is_instance_valid(header_lbl) else 0.0
	var avail_w: float = avail.x - MAPSELECT_GAP * float(MAPSELECT_COLS - 1)
	var avail_h: float = avail.y - header_h - MAPSELECT_GAP * float(rows - 1)
	var aspect: float = MAPSELECT_CARD_H / MAPSELECT_CARD_W   # height per unit width, 3:4 portrait
	var card_w: float = avail_w / float(MAPSELECT_COLS)
	var card_h: float = card_w * aspect
	if card_h * float(rows) > avail_h:
		# Width-driven size is too tall for the available height — height is the binding constraint instead.
		card_h = avail_h / float(rows)
		card_w = card_h / aspect
	var size := Vector2(floor(card_w), floor(card_h))
	for card in grid.get_children():
		card.custom_minimum_size = size

## One portrait map card: full-bleed thumbnail (or a "?" placeholder for coming-soon entries) + a name label
## that's fully hidden until hover (user feedback: "khi hover chuột lên thumbnail nào thì hiện tên") — same
## fade-in-on-hover idiom as _reveal_btn's grid cells, just a Label+backing Panel instead of an action Button.
## Coming-soon cards are dimmed (Control.modulate) so they read as locked even before you hover them.
func _make_map_card(entry: Dictionary) -> Control:
	var map_id := String(entry.get("map_id", ""))
	var is_real := map_id != ""
	var display_name := String(entry.get("name", map_id))

	var card := Control.new()
	card.custom_minimum_size = Vector2(MAPSELECT_CARD_W, MAPSELECT_CARD_H)
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not is_real:
		card.modulate = Color(0.55, 0.55, 0.58)   # dimmed = reads as locked even before hovering

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.75) if is_real else Color(0.35, 0.35, 0.38)
	bg.add_theme_stylebox_override("panel", sb)
	card.add_child(bg)

	# `visual` is whichever of the two (thumbnail image or "?" placeholder) actually got built below — hover
	# zoom (MAPSELECT_HOVER_ZOOM) scales THIS node only, never `card`/`bg`, so the border/frame drawn by `bg`
	# never moves; card.clip_contents (set above) crops the zoomed-in overflow back down to the card's fixed
	# outer rect, which is what keeps the border "giữ nguyên kích thước" while the art underneath zooms.
	var visual: Control = null
	var thumb_path := String(entry.get("thumb", ""))
	if thumb_path != "" and ResourceLoader.exists(thumb_path):
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.texture = load(thumb_path)
		# EXPAND_IGNORE_SIZE is required for stretch_mode=STRETCH_SCALE to actually shrink the texture to the
		# card's size instead of forcing the card to grow to the texture's native resolution — see
		# volcanic_crater_mark.gd's header for the full explanation of this exact Godot TextureRect gotcha.
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# `bg`'s rounded corners (set_corner_radius_all above) would otherwise be completely hidden — this
		# full-rect image draws OVER them with square corners. Mask the image to the same rounded rect instead
		# of just clipping it away, so the border's rounding is actually visible (user feedback: "các ô có
		# viền bo tròn" — the rounding wasn't showing through the thumbnail before this).
		var mat := _make_mapselect_rounded_material()
		tr.material = mat
		tr.resized.connect(func() -> void: mat.set_shader_parameter("rect_size", tr.size))
		card.add_child(tr)
		visual = tr
	else:
		var q := Label.new()
		q.text = "?"
		_font(q, FONT_TITLE, 72, Color(0.4, 0.4, 0.44))
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(q)
		visual = q
	visual.resized.connect(func() -> void: visual.pivot_offset = visual.size * 0.5)   # zoom from center

	var name_bg := Panel.new()
	name_bg.anchor_left = 0.0; name_bg.anchor_right = 1.0
	name_bg.anchor_top = 1.0; name_bg.anchor_bottom = 1.0
	name_bg.offset_top = -64.0
	var name_sb := StyleBoxFlat.new()
	name_sb.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	name_bg.add_theme_stylebox_override("panel", name_sb)
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bg.visible = false
	card.add_child(name_bg)

	var name_lbl := Label.new()
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_font(name_lbl, FONT_TITLE, 18, Color(1.0, 1.0, 1.0) if is_real else Color(0.8, 0.8, 0.82))
	name_lbl.text = display_name if is_real else (display_name + "\nComing soon")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bg.add_child(name_lbl)

	card.mouse_entered.connect(func() -> void:
		_reveal_panel(name_bg, true)
		_zoom_visual(visual, true))
	card.mouse_exited.connect(func() -> void:
		_reveal_panel(name_bg, false)
		_zoom_visual(visual, false))

	var cap_id := map_id
	var cap_name := display_name
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_real:
				_launch_run(cap_id)
			else:
				_show_toast(cap_name + " — Coming soon"))
	return card

## Same fade-in-on-hover idiom as _reveal_btn (line ~508), generalized to any Control (here: a Panel+Label
## name overlay instead of an action Button).
func _reveal_panel(ctrl: Control, show: bool) -> void:
	if not is_instance_valid(ctrl):
		return
	if show:
		ctrl.modulate.a = 0.0
		ctrl.visible = true
		var tw := create_tween()
		tw.tween_property(ctrl, "modulate:a", 1.0, 0.12)
	else:
		ctrl.visible = false

## Lazily compiles the shared rounded-rect mask Shader once and returns a fresh ShaderMaterial per card (each
## card's thumbnail has its own `rect_size` uniform, kept in sync with its own on-screen size via the
## `resized` connection in _make_map_card).
func _make_mapselect_rounded_material() -> ShaderMaterial:
	if _mapselect_rounded_shader == null:
		_mapselect_rounded_shader = Shader.new()
		_mapselect_rounded_shader.code = MAPSELECT_ROUNDED_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _mapselect_rounded_shader
	mat.set_shader_parameter("corner_radius", MAPSELECT_CORNER_RADIUS)
	return mat

## Hover zoom for a map card's thumbnail/placeholder — MAPSELECT_HOVER_ZOOM, from center (pivot_offset is
## kept at the node's own center via the `resized` connection in _make_map_card).
func _zoom_visual(ctrl: Control, zoom_in: bool) -> void:
	if not is_instance_valid(ctrl):
		return
	var target: float = MAPSELECT_HOVER_ZOOM if zoom_in else 1.0
	var tw := create_tween()
	tw.tween_property(ctrl, "scale", Vector2(target, target), 0.12)

# ── Constructor room ("Construction" tab, 2026-08-06, on request) ────────────────────────────────
## Combined single-tab view (no sub-tab bar — ROOM_PANELS["Constructor"] is one entry): Pilot Room's 2-stage
## purchase, the Trading Hub (shown only once the Mechanic has been rescued — is_room_unlocked("mechanic")),
## then Passives (moved here entirely from Engineer's old 3rd sub-tab).
func _build_construction() -> void:
	_header_row("The Constructor's projects — unlock new Dock facilities and oversee its permanent upgrades.")
	_build_pilot_room_section()
	if MetaManager.is_room_unlocked("mechanic"):
		_build_trading_hub_section()
	_build_passives()

func _section_title(text: String) -> void:
	var l := Label.new()
	_font(l, FONT_TITLE, 18, Color(0.90, 0.75, 0.45))
	l.text = text
	_content.add_child(l)

## Pilot Room — 2 one-time purchases (MetaManager.PILOT_UPGRADE_PRICES: 3000, then 5000 ⬤), each unlocking
## one of the "pilot"/"pilot2" Dock rooms (both display as "Pilot", see ROOM_UNLOCK_DEFS' own doc comment).
func _build_pilot_room_section() -> void:
	_section_title("Pilot Room")
	var lvl := MetaManager.pilot_upgrade_level()
	var price := MetaManager.pilot_upgrade_price()
	var row := _card()
	var top := HBoxContainer.new()
	row.add_child(top)
	var name_lbl := Label.new()
	_font(name_lbl, FONT_BODY, 18, Color(0.85, 0.9, 1.0))
	name_lbl.text = MandaloreText.a("Pilot Room   [%d/%d]" % [lvl, MetaManager.PILOT_UPGRADE_PRICES.size()])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)
	var buy := Button.new()
	if price < 0:
		buy.text = MandaloreText.a("MAX")
		buy.disabled = true
	else:
		buy.text = MandaloreText.a("%d ⬤" % price)
		buy.disabled = not GameManager.can_afford(price)
	_font_btn(buy, 16)
	buy.custom_minimum_size = Vector2(120, 0)
	buy.pressed.connect(func() -> void: MetaManager.buy_pilot_upgrade())
	top.add_child(buy)
	var desc := Label.new()
	_font(desc, FONT_BODY, 13, Color(0.6, 0.62, 0.68))
	desc.text = MandaloreText.a("Upgrade the Pilot's quarters — unlocks the Pilot room at the Dock.")
	row.add_child(desc)

## Trading Hub — flavor framing over the EXISTING Dock-interest system (MetaManager.apply_dock_interest()),
## not a separate mechanic: once the Mechanic is rescued, this just surfaces the current effective rate
## (base 5% + 2%/level of the "interest_boost" passive below, same passive, now bought right here) so the
## player can see what "bringing back profit" currently pays without digging through the Passives cards.
func _build_trading_hub_section() -> void:
	_section_title("Trading Hub")
	var rate := MetaManager.DOCK_INTEREST_BASE_RATE \
		+ float(MetaManager.passive_level("interest_boost")) * float(MetaManager.PASSIVE_DEFS["interest_boost"]["mag"])
	var row := _card()
	var desc := Label.new()
	_font(desc, FONT_BODY, 14, Color(0.85, 0.9, 1.0))
	desc.text = MandaloreText.a("The Mechanic trades your surplus gear on every Return to Dock, earning %d%% interest on your saved coin — runs of 10+ minutes only. Level up Cunning Engineer below to raise the rate." % int(round(rate * 100.0)))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)

# ── Passives ───────────────────────────────────────────────────────────────────
func _build_passives() -> void:
	_section_title("Passives")
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
		name_lbl.text = MandaloreText.a("%s   [%d/%d]" % [String(d["name"]), lvl, mx])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_lbl)
		var buy := Button.new()
		if cost < 0:
			buy.text = MandaloreText.a("MAX")
			buy.disabled = true
		else:
			buy.text = MandaloreText.a("%d ⬤" % cost)
			buy.disabled = not GameManager.can_afford(cost)
		_font_btn(buy, 16)
		buy.custom_minimum_size = Vector2(120, 0)
		buy.pressed.connect(func() -> void: MetaManager.buy_passive(id))
		top.add_child(buy)
		var desc := Label.new()
		_font(desc, FONT_BODY, 13, Color(0.6, 0.62, 0.68))
		desc.text = MandaloreText.a(String(d["desc"]))
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
		btn_text: String, on_press: Callable, btn_disabled: bool,
		btn_color: Color = Color(1, 1, 1), bg_override: Color = Color(0, 0, 0, 0),
		show_persistent_label: bool = false, persistent_text: String = "") -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
	cell.clip_contents = true
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_override if bg_override.a > 0.0 else (GRID_BG_ON if active else GRID_BG_OFF)
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
	vb.alignment = BoxContainer.ALIGNMENT_CENTER   # 2026-08-06: center the icon/text stack in the slot, on request
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
	HudEditRuntime.register(tr, "dock.grid_cell." + icon_def_id + ".icon")

	var name_lbl := Label.new()
	_font(name_lbl, FONT_BODY, 10, Color(0.92, 0.94, 0.98))
	name_lbl.text = MandaloreText.a(item_name)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(0, 24)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)
	HudEditRuntime.register(name_lbl, "dock.grid_cell." + icon_def_id + ".name")

	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 3)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tags)
	tags.add_child(_tag_chip(String(RARITY_LABEL.get(rarity, rarity)), InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)))
	if tag2 != "":
		tags.add_child(_tag_chip(tag2.capitalize(), Color(0.6, 0.65, 0.75)))

	# Always-visible price/status label (Merchant only — Loadout doesn't pass show_persistent_label, so its
	# LOAD/UNLOAD stays hover-only via `btn` below, unchanged). This is what makes the gray-blueprint / red-
	# insufficient-coin states readable at a glance instead of only on hover. `persistent_text` (2026-08-06,
	# on request) is normally the item's PRICE — a separate value from `btn_text`, which stays the Buy/Owned/
	# Blue Print Required/Not Enough Coin word shown on hover and in the preview panel's own Buy button; falls
	# back to `btn_text` if the caller doesn't pass one, so old call sites are unaffected.
	if show_persistent_label:
		var price_lbl := Label.new()
		_font(price_lbl, FONT_BODY, 11, btn_color)
		price_lbl.text = MandaloreText.a(persistent_text if persistent_text != "" else btn_text)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD   # wrap instead of overflowing the thumbnail, on request
		price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(price_lbl)
		HudEditRuntime.register(price_lbl, "dock.grid_cell." + icon_def_id + ".price")

	# Action label — purely visual now (flush with the cell's bottom edge, covering the tag row), only
	# `visible` toggles on hover. The CLICK itself is handled by `cell` below, for the whole tile: this
	# label has mouse_filter IGNORE so it never intercepts input (a Button here previously ate clicks
	# aimed at it and also caused a cell/button mouse_entered↔exited flicker that hid it mid-hover).
	var btn := Button.new()
	btn.text = MandaloreText.a(btn_text)
	_font_btn(btn, 10)
	btn.disabled = btn_disabled   # visual only (greys it out) — mouse_filter IGNORE below makes it non-interactive regardless
	if btn_color != Color(1, 1, 1):
		btn.add_theme_color_override("font_color", btn_color)
		btn.add_theme_color_override("font_disabled_color", btn_color)
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
	# Whole-tile click — not just the small label — triggers the action (LOAD/UNLOAD in Loadout, BUY in
	# Merchant). Always connected now, even when btn_disabled (2026-08-05): Merchant cells need a click to
	# fire so they can show a "need blueprint"/"need more coin" toast instead of just doing nothing — and
	# this is a safe no-op for Loadout's existing disabled case too, since MetaManager.toggle_loadout()
	# already self-guards (returns false harmlessly if the kind isn't unlocked or the loadout's full).
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
	l.text = MandaloreText.a(text)
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
	n.text = MandaloreText.a(name)
	n.custom_minimum_size = Vector2(280, 0)
	row.add_child(n)
	var meta := Label.new()
	_font(meta, FONT_BODY, 13, Color(0.55, 0.58, 0.64))
	meta.text = MandaloreText.a("%s · %s" % [String(RARITY_LABEL.get(rarity, rarity)), group.capitalize()])
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(meta)
	var rt := Label.new()
	_font(rt, FONT_BODY, 16, Color(1.0, 0.86, 0.3))
	rt.text = MandaloreText.a(right_text)
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
	l.text = MandaloreText.a(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)

func _note(text: String) -> void:
	var l := Label.new()
	_font(l, FONT_BODY, 16, Color(0.5, 0.5, 0.55))
	l.text = MandaloreText.a(text)
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

## Size/color only — deliberately does NOT set a "font" theme override, so the Control renders with whatever
## the engine's default theme font is. Used only by the Merchant preview panel (_build_merchant_preview),
## on request — every OTHER label/button in this file still goes through _font()/_font_btn() above.
func _font_sz(lbl: Label, size: int, col: Color) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)

func _font_sz_btn(btn: Button, size: int) -> void:
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

## Top-left "MAIN MENU" button (2026-08-06, on request — quick nav for testing). Always visible on top of
## everything else on the Dock screen, including an open Merchant/Loadout/Engineer panel (layer 16, above the
## toast's 14 and the overlay panel's 13), same "save first" courtesy as every other exit path in this file.
func _build_main_menu_button() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 16
	add_child(cl)
	var btn := Button.new()
	btn.text = MandaloreText.a("MAIN MENU")
	_font_btn(btn, 16)
	btn.custom_minimum_size = Vector2(140, 40)
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = 16.0
	btn.offset_top  = 16.0
	btn.pressed.connect(func() -> void:
		for mgr in [GameManager, InventoryManager, MetaManager]:
			if mgr != null and mgr.has_method("save_game"):
				mgr.save_game()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	cl.add_child(btn)
	HudEditRuntime.register(btn, "dock.chrome.main_menu_btn")

func _show_toast(message: String) -> void:
	if _toast == null:
		return
	_toast.text = MandaloreText.a(message)
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

## Dock-interest notification: small dismissible card pinned to the top-right corner. Thin wrapper over
## the shared _show_notice() below — just formats the interest-earned copy.
func _show_interest_notification(amount: int) -> void:
	_show_notice("The Engineer built and sold spare weapons, bringing you %d ⬤ in interest." % amount)

## Room-unlock notification (2026-08-06, on request — "tương tự thông báo lãi coin", same card idiom as
## the interest notice above, just different copy). Drains GameManager.pending_room_unlock_notices, which
## MetaManager.unlock_room() appends to (see its doc comment) — one card per queued room, stacked so
## several unlocks in a row (e.g. a debug "skip run" that both kills a boss and buys weapons) don't overlap.
func _drain_room_unlock_notices() -> void:
	if not ("pending_room_unlock_notices" in GameManager):
		return
	var notices: Array = GameManager.pending_room_unlock_notices
	while not notices.is_empty():
		_show_notice("%s is now accessible" % String(notices.pop_front()))

## Shared top-right dismissible card (distinct from the generic centered _toast above — this one needs a
## manual "✕" AND a timed auto-dismiss, so each instance gets its own CanvasLayer). Slides down + fades out
## after NOTICE_LIFETIME (5s) unless the player closes it first. Multiple simultaneous notices stack
## downward (_notice_layers tracks the currently-visible ones so a new card starts below them).
const NOTICE_LIFETIME := 5.0
var _notice_layers: Array = []
func _show_notice(text: String) -> void:
	_notice_layers = _notice_layers.filter(func(cl): return is_instance_valid(cl))
	var stack_index := _notice_layers.size()

	var cl := CanvasLayer.new()
	cl.layer = 15   # above the toast (14) and the overlay panel (13)
	add_child(cl)
	_notice_layers.append(cl)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.85, 0.2)
	sb.set_content_margin_all(12.0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(panel)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)

	var lbl := Label.new()
	_font(lbl, FONT_BODY, 14, Color(0.9, 0.95, 1.0))
	lbl.text = MandaloreText.a(text)
	lbl.custom_minimum_size = Vector2(260.0, 0.0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)

	var close := Button.new()
	close.text = MandaloreText.a("✕")
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	_font_btn(close, 14)
	close.custom_minimum_size = Vector2(22.0, 22.0)
	hb.add_child(close)

	panel.reset_size()
	var vp_w := get_viewport().get_visible_rect().size.x
	panel.position = Vector2(vp_w - panel.size.x - 16.0, 16.0 + float(stack_index) * (panel.size.y + 10.0))

	var dismissed := false
	var do_dismiss := func() -> void:
		if dismissed or not is_instance_valid(cl):
			return
		dismissed = true
		_notice_layers.erase(cl)
		var tw2 := create_tween()
		tw2.tween_property(panel, "position:y", panel.position.y + 50.0, 0.35)
		tw2.parallel().tween_property(panel, "modulate:a", 0.0, 0.35)
		tw2.tween_callback(cl.queue_free)
	close.pressed.connect(do_dismiss)

	get_tree().create_timer(NOTICE_LIFETIME).timeout.connect(do_dismiss)
