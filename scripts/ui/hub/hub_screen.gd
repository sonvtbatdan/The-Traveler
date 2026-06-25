extends Control
## Hub / Dock-Workshop (Phase 2) — the between-run home screen and the game's launch scene. Four tabs:
##   Shop      — buy clean copies of weapons whose blueprint you know (spend coins)
##   Craft     — assemble unique weapons once you own all their fragments
##   Fragments — track your unique-fragment collection progress
##   Passives  — buy permanent meta upgrades (applied at the start of every run)
## "LAUNCH RUN" loads the arena; the arena returns here when the run ends. All state lives in MetaManager
## + GameManager (coins). UI is built in code, matching the project's conventions.

const ARENA_SCENE := "res://scenes/arena.tscn"
const ArenaScript := preload("res://scripts/gameplay/arena.gd")   # for the WEAPON_TEST_MODE flag (skip this launch page)
const InventoryUIScript := preload("res://scripts/ui/inventory/inventory_ui.gd")   # equip screen (I key)
const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/Gameplay.ttf"

const RARITY_LABEL := {
	"common": "Common", "uncommon": "Uncommon", "rare": "Rare",
	"very_rare": "Very Rare", "unique": "Unique", "legendary": "Legendary",
}

var _tab: String = "shop"
var _coin_label: Label = null
var _content: VBoxContainer = null
var _tab_buttons: Dictionary = {}

func _ready() -> void:
	if ArenaScript.WEAPON_TEST_MODE:
		# Weapon-test mode: don't show the launch page — boot straight into the arena (which auto-opens F12).
		call_deferred("_goto_arena")
		return
	_build_ui()

## Forward directly into the arena (weapon-test mode skips the hub UI entirely).
func _goto_arena() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
	add_child(InventoryUIScript.new())   # equip what you buy before launching (toggle with the I key)
	if GameManager.has_signal("money_changed"):
		GameManager.money_changed.connect(func(_m: int) -> void: _refresh())
	if MetaManager.has_signal("meta_changed"):
		MetaManager.meta_changed.connect(_refresh)
	_refresh()

# ── Layout ───────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 40)
	root.add_theme_constant_override("margin_right", 40)
	root.add_theme_constant_override("margin_top", 24)
	root.add_theme_constant_override("margin_bottom", 24)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)

	# Header row: title + coins
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "DOCK · WORKSHOP"
	_font(title, FONT_TITLE, 34, Color("#E5792A"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coin_label = Label.new()
	_font(_coin_label, FONT_TITLE, 28, Color(1.0, 0.86, 0.3))
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_coin_label)
	# Debug coin grant (handy until runs reliably pay out) — clearly labelled.
	var dbg := Button.new()
	dbg.text = "+1000 (debug)"
	_font_btn(dbg, 14)
	dbg.pressed.connect(func() -> void: GameManager.add_money(1000))
	header.add_child(dbg)

	# Tab bar
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	for t in [["shop", "SHOP"], ["craft", "CRAFT"], ["fragments", "FRAGMENTS"], ["passives", "PASSIVES"]]:
		var b := Button.new()
		b.text = String(t[1])
		_font_btn(b, 18)
		b.custom_minimum_size = Vector2(150, 40)
		b.pressed.connect(_switch_tab.bind(String(t[0])))
		tabs.add_child(b)
		_tab_buttons[String(t[0])] = b

	# Scrollable content
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	# Launch button
	var launch := Button.new()
	launch.text = "▶  LAUNCH RUN"
	_font_btn(launch, 26)
	launch.custom_minimum_size = Vector2(0, 64)
	launch.pressed.connect(_launch_run)
	col.add_child(launch)

func _switch_tab(t: String) -> void:
	_tab = t
	_refresh()

func _refresh() -> void:
	if _coin_label != null:
		_coin_label.text = "⬤ %d" % GameManager.money
	for id: String in _tab_buttons.keys():
		var b: Button = _tab_buttons[id]
		b.modulate = Color(1, 1, 1) if id == _tab else Color(0.6, 0.6, 0.65)
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	match _tab:
		"shop":      _build_shop()
		"craft":     _build_craft()
		"fragments": _build_fragments()
		"passives":  _build_passives()

# ── Shop ───────────────────────────────────────────────────────────────────────
func _build_shop() -> void:
	_header_row("Buy weapons you've unlocked. Disassemble boss drops to learn more blueprints.")
	var ids: Array = MetaManager.blueprints.duplicate()
	ids.sort_custom(_sort_by_rarity)
	if ids.is_empty():
		_note("No blueprints known yet.")
		return
	for def_id: String in ids:
		var d := InventoryManager.get_def(def_id)
		if d.is_empty():
			continue
		var price := MetaManager.blueprint_price(def_id)
		var row := _item_row(String(d.get("name", def_id)), String(d.get("rarity", "common")), String(d.get("group", "")), "%d ⬤" % price)
		var buy := Button.new()
		buy.text = "BUY"
		_font_btn(buy, 16)
		buy.custom_minimum_size = Vector2(90, 0)
		buy.disabled = not GameManager.can_afford(price) or not InventoryManager.has_room_for(def_id)
		buy.pressed.connect(func() -> void: MetaManager.buy_weapon(def_id))
		row.add_child(buy)

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

func _launch_run() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
