extends CanvasLayer
## Boss-defeated salvage screen (Phase 3). When GameManager.boss_defeated fires, roll this boss's loot —
## a few weapons whose rarity is capped by the boss's level (so early bosses can't yield top gear) plus a
## chance at a unique FRAGMENT (drawn only from pieces you don't own; rank-gated by boss level). For each
## weapon the player chooses EQUIP (run-temporary — lost at run end) or DISASSEMBLE (unlock its permanent
## blueprint for the hub shop). Fragments are auto-recovered. Pause-safe (layer 110 + PROCESS_MODE_ALWAYS).

const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/mandalore/mandalore.ttf"
const SHOW_DELAY := 1.1   # let the boss death FX play before the salvage screen pops

var _boss_index: int = 0
var _root: Control = null
var _list: VBoxContainer = null
var _continue: Button = null
var _pending: int = 0       # weapons still awaiting an Equip/Disassemble choice
var _prev_paused: bool = false   # tree's paused state from just before we showed — restored on Continue instead of a blind unpause

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.hide()
	if GameManager.has_signal("boss_defeated"):
		GameManager.boss_defeated.connect(_on_boss_defeated)

func _on_boss_defeated() -> void:
	_boss_index += 1
	# Defer so the boss death explosion plays first (timer ticks even though we pause later).
	var t := get_tree().create_timer(SHOW_DELAY, true, false, true)
	t.timeout.connect(_present_drops)

func _present_drops() -> void:
	var weapon_cap := clampi(_boss_index, 1, 2)            # boss 1 → uncommon, boss 2+ → rare (standards cap at rare)
	var n_weapons := clampi(_boss_index, 1, 3)             # more loot from deeper bosses
	var frag_ranks: Array = [3] if _boss_index <= 1 else ([3, 4] if _boss_index == 2 else [3, 4, 5])

	var weapons: Array = []
	for _i in n_weapons:
		var id := MetaManager.roll_boss_weapon(weapon_cap)
		if id != "":
			weapons.append(id)
	# One fragment at 70% (scaled by luck: Cursed Hull lowers it, Lucky drones raise it), drawn from the
	# unowned, rank-gated pool (marks it owned immediately).
	var fragment: Dictionary = {}
	var frag_chance := 0.70
	if GameManager.has_method("hull_luck_mult"):
		frag_chance *= GameManager.hull_luck_mult()
	frag_chance += GameManager.run_luck if "run_luck" in GameManager else 0.0
	if randf() < clampf(frag_chance, 0.0, 1.0):
		fragment = MetaManager.roll_fragment_drop(frag_ranks)

	if weapons.is_empty() and fragment.is_empty():
		return   # nothing to show

	# Clear previous content.
	for c in _list.get_children():
		c.queue_free()
	_pending = weapons.size()

	if not fragment.is_empty():
		_add_fragment_notice(fragment)
	for def_id: String in weapons:
		_add_weapon_choice(def_id)

	_continue.disabled = _pending > 0
	# Capture/restore instead of a blind force (2026-08-02: forcing false on Continue could clobber an outer
	# pause some other panel/HUD button set — see arena_hud_buttons.gd's _on_pause() for the "needs 2 clicks"
	# class of bug this caused).
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_root.show()

# ── Rows ─────────────────────────────────────────────────────────────────────────
func _add_fragment_notice(fragment: Dictionary) -> void:
	var uid := String(fragment["unique_id"])
	var d := InventoryManager.get_def(uid)
	var row := _card()
	var l := Label.new()
	_font(l, FONT_BODY, 18, Color(0.55, 0.95, 0.5))
	l.text = MandaloreText.a("✦ Recovered fragment: %s  —  %s (%d/%d)" % [
		String(fragment["name"]), String(d.get("name", uid)),
		MetaManager.owned_fragment_count(uid), MetaManager.fragment_count(uid)])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	if MetaManager.is_unique_complete(uid) and not MetaManager.is_unique_crafted(uid):
		var hint := Label.new()
		_font(hint, FONT_BODY, 14, Color(1.0, 0.86, 0.3))
		hint.text = MandaloreText.a("All fragments collected — craft %s at the Dock!" % String(d.get("name", uid)))
		row.add_child(hint)

func _add_weapon_choice(def_id: String) -> void:
	MetaManager.run_weapon_drop_seen = true   # 2026-08-06: lets the RUN OVER screen tell "no boss fought" apart from "fought one, disassembled nothing"
	var d := InventoryManager.get_def(def_id)
	var row := _card()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	row.add_child(top)
	var name_lbl := Label.new()
	var rcol: Color = InventoryManager.RARITY_COLORS.get(String(d.get("rarity", "common")), Color.WHITE)
	_font(name_lbl, FONT_BODY, 18, rcol)
	name_lbl.text = MandaloreText.a("%s  ·  %s" % [String(d.get("name", def_id)), String(d.get("group", "")).capitalize()])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)

	var equip_btn := Button.new()
	equip_btn.text = MandaloreText.a("EQUIP (run)")
	_font_btn(equip_btn, 15)
	equip_btn.custom_minimum_size = Vector2(140, 0)
	var dis_btn := Button.new()
	dis_btn.text = MandaloreText.a("DISASSEMBLE")
	_font_btn(dis_btn, 15)
	dis_btn.custom_minimum_size = Vector2(140, 0)
	var status := Label.new()
	_font(status, FONT_BODY, 13, Color(0.6, 0.62, 0.68))
	status.text = MandaloreText.a("Equip for this run, or break down for a permanent blueprint.")

	equip_btn.pressed.connect(func() -> void:
		_equip_drop(def_id)
		status.text = MandaloreText.a("Equipped — this copy is lost at the end of the run.")
		status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		_resolve(equip_btn, dis_btn))
	dis_btn.pressed.connect(func() -> void:
		# 2026-08-06, on request: no longer an instant unlock — staged, becomes a real blueprint only if this
		# run ends in victory (arena.gd's _show_run_over → MetaManager.commit_pending_blueprints()). Dying
		# first loses it, same risk as an uncollected rescue-landmark character.
		MetaManager.stage_blueprint(def_id)
		status.text = MandaloreText.a("Blueprint secured — permanent only if you make it back to the Dock.")
		status.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
		_resolve(equip_btn, dis_btn))

	top.add_child(equip_btn)
	top.add_child(dis_btn)
	row.add_child(status)

func _resolve(b1: Button, b2: Button) -> void:
	b1.disabled = true
	b2.disabled = true
	_pending = maxi(0, _pending - 1)
	if _pending == 0:
		_continue.disabled = false

func _equip_drop(def_id: String) -> void:
	var uid := InventoryManager.add_to_backpack(def_id)
	if uid == -1:
		return   # backpack full — nothing to equip (shouldn't normally happen)
	MetaManager.mark_run_temp(uid)
	for slot: String in ["primary_weapon", "secondary_weapon"]:
		if InventoryManager.equipped_uid(slot) != -1:
			continue
		if not InventoryManager.fits_slot(def_id, slot):
			continue
		if InventoryManager.has_method("meets_requirement") and not InventoryManager.meets_requirement(def_id):
			continue
		InventoryManager.equip(uid, slot)
		break

# ── UI scaffold ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.13, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := Label.new()
	title.text = "BOSS DEFEATED — SALVAGE"
	_font(title, FONT_TITLE, 30, Color("#E5792A"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)

	_continue = Button.new()
	_continue.text = MandaloreText.a("CONTINUE RUN")
	_font_btn(_continue, 22)
	_continue.custom_minimum_size = Vector2(0, 52)
	_continue.pressed.connect(func() -> void:
		_root.hide()
		get_tree().paused = _prev_paused)
	col.add_child(_continue)

func _card() -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.13, 0.19)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	_list.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	return v

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
