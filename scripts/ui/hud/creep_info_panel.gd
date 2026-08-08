extends CanvasLayer
## Dev-mode-only enemy stat/behavior editor — group "creep_info", toggled from arena_hud_buttons.gd's
## Creep Info button (between Boss Edit and Creep Edit). Lists every type in arena_wave_director.gd's
## ENEMY_DEFS (the full v1 roster — v2's 4 test types are just remapped subsets of these, see
## arena_wave_director_v2.gd's TEST_ROSTER) with editable HP + XP Drop fields and independent Move/Shoot
## dropdowns. Uses the default theme font throughout (no custom font override).
##
## Move/Shoot are a NEW, separate system from the classic single `behavior` string (which still tightly
## couples movement + attack per enemy, e.g. "shooter" = hold-range AND burst-fire together) — see
## arena_enemy.gd's MOVE_LOGICS/SHOOT_LOGICS consts and _tick_move_logic()/_tick_shoot_logic(). Leaving a
## row's Move at "(default)" AND Shoot at "None" keeps that unit's original bespoke behavior untouched.
## IMPORTANT caveat: the classic system and the composed one can't be mixed — overriding ONLY Shoot (Move
## left "(default)") does NOT keep the original movement, it falls back to "stationary" (composed mode fully
## replaces the classic dispatch); same in reverse (Move overridden, Shoot left "None" → no ranged attack,
## even if the original behavior used to fire). This is disclosed in the panel's own header label too.
##
## Persisted to res://creep_info_overrides.cfg on Save — takes effect from the NEXT arena load: each wave
## director applies saved overrides to its OWN ENEMY_DEFS once, at its own _ready() (apply_overrides() is
## static so both arena_wave_director.gd and arena_wave_director_v2.gd can call it without an instance).

const WaveDir := preload("res://scripts/gameplay/arena_wave_director.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const CFG_PATH := "res://creep_info_overrides.cfg"

var _is_open: bool = false
var _root: Control = null
var _rows_box: VBoxContainer = null
var _rows: Array = []   # {id, hbox, hp_spin, xp_spin, move_opt, shoot_opt}
var _icon_cache: Dictionary = {}
var _status: Label = null

# ── Sortable headers (Unit/HP) ── _sort_key picks which one actually orders the rows; each button
# remembers its OWN arrow/direction independently, so switching columns doesn't lose the other's state.
# Name's arrow meaning is intentionally reversed from HP's, per spec: ▲ = Z→A, ▼ = A→Z (HP: ▲ = low→high).
var _sort_key: String = "name"
var _name_sort_up: bool = false   # ▼ = A→Z — matches _populate()'s initial ENEMY_DEFS.keys().sort() order
var _hp_sort_up: bool = true
var _name_hdr_btn: Button = null
var _hp_hdr_btn: Button = null

func _ready() -> void:
	layer = 61   # above the HUD dev-column buttons, same tier as arena_debug_spawn.gd's Quick Spawn panels
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("creep_info")
	visible = false

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's Creep Info button.
func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		if _root == null:
			_build_ui()   # lazy — pay the ~60-icon thumbnail-load cost only on first open
		_populate()

# ── Persistence (static — also called by both wave directors' own _ready()) ──────────────────────────
static func load_overrides() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return {}
	var data = cfg.get_value("overrides", "data", {})
	return data if data is Dictionary else {}

## Mutates `defs` IN PLACE (Dictionary is a reference type) — call once per director, on its OWN ENEMY_DEFS,
## from that director's _ready(). Each director applies independently rather than relying on instantiation
## order, since only ONE of v1/v2 is ever actually instantiated (per arena.gd's USE_SPAWN_MODE_2 flag).
static func apply_overrides(defs: Dictionary) -> void:
	var ov := load_overrides()
	for id in ov.keys():
		if not defs.has(id):
			continue
		var o: Dictionary = ov[id]
		var entry: Dictionary = defs[id]
		if o.has("hp"):
			entry["hp"] = float(o["hp"])
		if o.has("xp"):
			entry["xp"] = float(o["xp"])
		if o.has("move"):
			entry["move"] = String(o["move"])
		if o.has("shoot"):
			entry["shoot"] = String(o["shoot"])

# ── UI ───────────────────────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.75)
	sb.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", sb)
	var psize := Vector2(760.0, 620.0)
	var vpz := get_viewport().get_visible_rect().size
	panel.position = ((vpz - psize) * 0.5).clamp(Vector2(8, 8), vpz)
	panel.size = psize
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(8.0, 8.0)
	vb.size = psize - Vector2(16.0, 16.0)
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := _mk_label("CREEP INFO", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vb.add_child(title)
	var hint := _mk_label("Move \"(default)\" + Shoot \"None\" = untouched (keeps original behavior). Overriding only ONE of the two does NOT keep the other's original pattern — the unit falls back to stationary / no shooting for whichever side is left default.", 10)
	hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	hint.custom_minimum_size = Vector2(psize.x - 16.0, 0.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vb.add_child(btn_row)
	var save_btn := _mk_button("Save", _on_save)
	save_btn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
	btn_row.add_child(save_btn)
	var close_btn := _mk_button("Close", toggle)
	close_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	btn_row.add_child(close_btn)
	_status = _mk_label("", 11)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	btn_row.add_child(_status)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	var icon_hdr := _mk_label("", 11)
	icon_hdr.custom_minimum_size = Vector2(32.0, 0.0)
	hdr.add_child(icon_hdr)
	_name_hdr_btn = _mk_button("", _on_sort_name)
	_name_hdr_btn.custom_minimum_size = Vector2(150.0, 0.0)
	_name_hdr_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.add_child(_name_hdr_btn)
	_hp_hdr_btn = _mk_button("", _on_sort_hp)
	_hp_hdr_btn.custom_minimum_size = Vector2(74.0, 0.0)
	_hp_hdr_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.add_child(_hp_hdr_btn)
	# Master HP→XP auto-fill: same formula as each row's own "→" button, applied to EVERY row at once.
	var hp_to_xp_hdr_btn := _mk_button("→", _on_recalc_all_xp)
	hp_to_xp_hdr_btn.custom_minimum_size = Vector2(30.0, 0.0)
	hp_to_xp_hdr_btn.tooltip_text = "Set EVERY row's XP Drop = round(HP / 10), minimum 10"
	hdr.add_child(hp_to_xp_hdr_btn)
	for h: Array in [["XP Drop", 74], ["Move", 150], ["Shoot", 110]]:
		var l := _mk_label(String(h[0]), 11)
		l.custom_minimum_size = Vector2(float(h[1]), 0)
		hdr.add_child(l)
	vb.add_child(hdr)
	_update_sort_headers()

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(psize.x - 16.0, psize.y - 150.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)

func _populate() -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	var overrides := load_overrides()
	var ids := WaveDir.ENEMY_DEFS.keys()
	ids.sort()
	for id: String in ids:
		_rows_box.add_child(_make_row(String(id), WaveDir.ENEMY_DEFS[id], overrides.get(id, {})))
	_apply_sort()
	_status.text = ""

func _make_row(id: String, def: Dictionary, ov: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(32.0, 32.0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = _icon(String(def.get("icon", "")))
	hb.add_child(tr)

	var nm := _mk_label(id, 11)
	nm.custom_minimum_size = Vector2(150.0, 0.0)
	nm.clip_text = true
	nm.tooltip_text = "behavior: %s" % String(def.get("behavior", ""))
	hb.add_child(nm)

	var hp_spin := SpinBox.new()
	hp_spin.min_value = 0.0
	hp_spin.max_value = 50000.0
	hp_spin.step = 1.0
	hp_spin.value = float(ov.get("hp", def.get("hp", 0.0)))
	hp_spin.custom_minimum_size = Vector2(74.0, 0.0)
	hb.add_child(hp_spin)

	var xp_spin := SpinBox.new()
	xp_spin.min_value = 0.0
	xp_spin.max_value = 5000.0
	xp_spin.step = 1.0   # every xp value in ENEMY_DEFS is a whole number now (2026-07-28 ×10 pass — see game_manager.gd)
	xp_spin.value = float(ov.get("xp", def.get("xp", 0.0)))
	xp_spin.custom_minimum_size = Vector2(74.0, 0.0)

	# HP→XP auto-fill: XP = round(HP / 10). Between the HP and XP Drop columns.
	# (2026-08-05: ×10'd along with every other XP-drop source, on request — was round(HP / 100), min 1.)
	var hp_to_xp_btn := _mk_button("→", func() -> void: xp_spin.value = maxf(10.0, round(hp_spin.value / 10.0)))
	hp_to_xp_btn.custom_minimum_size = Vector2(30.0, 0.0)
	hp_to_xp_btn.tooltip_text = "Set XP Drop = round(HP / 10), minimum 10"
	hb.add_child(hp_to_xp_btn)

	hb.add_child(xp_spin)

	var move_opt := OptionButton.new()
	move_opt.custom_minimum_size = Vector2(150.0, 0.0)
	move_opt.add_item("(default)")
	for m: String in EnemyScript.MOVE_LOGICS:
		move_opt.add_item(m)
	var move_ov := String(ov.get("move", ""))
	var move_idx := EnemyScript.MOVE_LOGICS.find(move_ov)
	move_opt.selected = (move_idx + 1) if move_idx >= 0 else 0
	hb.add_child(move_opt)

	# "(default)" is a DIFFERENT state from "None": default = keep whatever the original `behavior` does
	# (may or may not fire — e.g. "shooter"/"sentinel" DO fire, but via the classic system, not this one, so
	# this dropdown has no way to show that — it only reflects composed-mode overrides). Explicit "None" is
	# a real override: forces this unit into composed mode with no ranged attack, even overriding a classic
	# behavior that normally fires.
	var shoot_opt := OptionButton.new()
	shoot_opt.custom_minimum_size = Vector2(110.0, 0.0)
	shoot_opt.add_item("(default)")
	for s: String in EnemyScript.SHOOT_LOGICS:
		shoot_opt.add_item("None" if s == "none" else s)
	var shoot_has_ov := ov.has("shoot")
	var shoot_idx := EnemyScript.SHOOT_LOGICS.find(String(ov.get("shoot", "")))
	shoot_opt.selected = (shoot_idx + 1) if (shoot_has_ov and shoot_idx >= 0) else 0
	hb.add_child(shoot_opt)

	_rows.append({"id": id, "hbox": hb, "hp_spin": hp_spin, "xp_spin": xp_spin, "move_opt": move_opt, "shoot_opt": shoot_opt})
	return hb

## Reorders the already-built row rows in place (Control.move_child on each row's hbox) instead of
## rebuilding via _populate() — rebuilding would discard any unsaved in-progress edits sitting in the
## SpinBoxes/dropdowns. Sort keys read the CURRENT live value (e.g. hp_spin.value), not the original def.
func _apply_sort() -> void:
	var sorted: Array = _rows.duplicate()
	if _sort_key == "hp":
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var av: float = (a["hp_spin"] as SpinBox).value
			var bv: float = (b["hp_spin"] as SpinBox).value
			return av < bv if _hp_sort_up else av > bv)
	else:
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var an: String = String(a["id"])
			var bn: String = String(b["id"])
			return an > bn if _name_sort_up else an < bn)   # ▲ = Z→A, ▼ = A→Z (per spec — reversed from HP)
	for i in sorted.size():
		_rows_box.move_child(sorted[i]["hbox"] as Control, i)

func _update_sort_headers() -> void:
	if _name_hdr_btn != null:
		_name_hdr_btn.text = "Unit %s" % ("▲" if _name_sort_up else "▼")
	if _hp_hdr_btn != null:
		_hp_hdr_btn.text = "HP %s" % ("▲" if _hp_sort_up else "▼")

func _on_sort_name() -> void:
	_sort_key = "name"
	_name_sort_up = not _name_sort_up
	_update_sort_headers()
	_apply_sort()

func _on_sort_hp() -> void:
	_sort_key = "hp"
	_hp_sort_up = not _hp_sort_up
	_update_sort_headers()
	_apply_sort()

func _icon(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex := load(path) as Texture2D
	_icon_cache[path] = tex
	return tex

## Master HP→XP auto-fill (header button, next to the per-row "→" column): reapplies the SAME formula
## (round(HP / 10), minimum 10) to every row's XP Drop SpinBox in one click. Only touches the live SpinBox
## values — nothing is persisted until Save.
func _on_recalc_all_xp() -> void:
	for r: Dictionary in _rows:
		var hp_spin := r["hp_spin"] as SpinBox
		var xp_spin := r["xp_spin"] as SpinBox
		xp_spin.value = maxf(10.0, round(hp_spin.value / 10.0))
	_status.text = "Recalculated XP from HP for all %d creep(s) — remember to Save." % _rows.size()

func _on_save() -> void:
	var ov: Dictionary = {}
	for r: Dictionary in _rows:
		var id: String = r["id"]
		var base: Dictionary = WaveDir.ENEMY_DEFS.get(id, {})
		var hp: float = (r["hp_spin"] as SpinBox).value
		var xp: float = (r["xp_spin"] as SpinBox).value
		var move_i: int = (r["move_opt"] as OptionButton).selected
		var shoot_i: int = (r["shoot_opt"] as OptionButton).selected
		var move_s := "" if move_i == 0 else String(EnemyScript.MOVE_LOGICS[move_i - 1])
		var shoot_s := "" if shoot_i == 0 else String(EnemyScript.SHOOT_LOGICS[shoot_i - 1])
		var entry := {}
		if not is_equal_approx(hp, float(base.get("hp", 0.0))):
			entry["hp"] = hp
		if not is_equal_approx(xp, float(base.get("xp", 0.0))):
			entry["xp"] = xp
		if move_s != "":
			entry["move"] = move_s
		if shoot_s != "":   # "(default)" (index 0) writes nothing; explicit "None" (SHOOT_LOGICS[0]) DOES write "shoot":"none"
			entry["shoot"] = shoot_s
		if not entry.is_empty():
			ov[id] = entry
	var cfg := ConfigFile.new()
	cfg.set_value("overrides", "data", ov)
	cfg.save(CFG_PATH)
	# Live-apply to the CURRENTLY RUNNING director too (2026-08-02: previously only took effect on the next
	# arena load, since apply_overrides() was only ever called once, at the director's own _ready() — the
	# Wave Editor's Total HP column reads _director.ENEMY_DEFS live with no cache of its own, so re-applying
	# here is sufficient; apply_overrides() only assigns values (never multiplies/accumulates), so re-running
	# it is safe/idempotent even if Save is clicked repeatedly).
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null:
		apply_overrides(wd.ENEMY_DEFS)
	_status.text = "Saved %d override(s) — applied live" % ov.size()

# ── Widget helpers ──────────────────────────────────────────────────────────────────────────────────
func _mk_label(text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
