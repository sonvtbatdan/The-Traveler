extends CanvasLayer
## F7 in-game WAVE EDITOR for the arena. The timeline is authored on a 5-second grid: 360 rows (5s → 1800s).
## Each row is ONE moment in time that can spawn MANY things at once — up to 10 Unit/Fleet "slots" (a 2×5 grid)
## dropped in from the Type popup. Each slot carries its own Count / Pattern / Boss checkbox (Fleets ignore
## count/pattern/boss and use their authored formation, but add their own Spawn Angle + Fleet Rotate — see
## _tl_fire()'s fleet branch in arena_wave_director_v2.gd). "Boss" bypasses the alive-cap on spawn; if it's
## also the LAST entry (by time) in the WHOLE timeline, it becomes the run's final-boss finale (waits for the
## field to clear, locks off reinforcement — see arena_wave_director_v2.gd's _final_boss_entry). Toggle with
## F7: pauses the game, shows the editable row list, a NAME field, a Save/Load library (res://levels/arena/
## *.json), a live JSON readout, Apply&Restart / Reset / Sort.
##
## The wave_director timeline stays FLAT ({time,type,count,pattern,[duration],[is_boss],[angle],[fleet_rotate]})
## — this editor expands each row's filled slots into one flat entry per slot on Apply/Save, and re-groups flat
## entries (snapped to the 5s grid) back into rows on open. So old saved files + DEFAULT_TIMELINE keep working
## unchanged (both new fields are absent = random direction / no rotation, identical to today's behavior).
##
## "Generate Base on HP" (2026-08-17): the row list's "Total HP" column is a user-editable TARGET field,
## "Actual HP" next to it is a read-only live readout of the row's REAL current slot-content total (same
## math as the Type popup's own "Total HP" header), paired with a per-row "Gen" button and a top "Gen All
## (HP)" button. Gen clears the row and fills it with a random creep/fleet mix whose combined HP lands
## within GEN_HP_TOLERANCE (±10%) of the target; rows left at 0 are skipped. See
## _generate_row_hp()/_on_gen_row()/_on_gen_all(). The Type column's button is TYPE_BTN_W (50% of its
## original width).
##
## Per-map file lock (2026-08-17): electric/volcanic/atlantic are each pinned to exactly ONE file
## (MAP_FIXED_FILES) — Name becomes read-only and the file dropdown shows only that map's own file, no
## free Save-as-any-name. "default"/Space (not one of those 3) keeps the original free-form behavior.
## The Unit/Fleet pickers + Gen's candidate pool are also scoped to the current map's own roster
## (_map_enemy_ids()/_map_fleets()) — own assets/map/<name>/enemies/ folder + the shared legacy
## enemiesHD/bosses pools (some already-used ids, e.g. Electric's "shooter", still live there).

const FONT_PATH := "res://assets/fonts/mandalore/mandalore.ttf"
const LEVELS_DIR := "res://levels/arena"
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")   # for enemy_draw_width()'s canonical size lookup
func _current_map_id() -> String:
	return String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"

## Per-map "last-Loaded wave file" pointer — MUST match arena_wave_director_v2.gd's copy of this logic
## (that script is the reader; this one is the writer, via _remember_last_wave below).
func _last_wave_cfg_path() -> String:
	var map_id := _current_map_id()
	if map_id != "default" and map_id != "":
		return "res://spawn_mode_2_wave_%s.cfg" % map_id
	return "res://spawn_mode_2_wave.cfg"

## Per-map fixed wave-file lock (2026-08-17, on request: "không cho tự lưu file json nữa, mặc định
## chỉ có dropdown các file json theo tên map"). electric/volcanic/atlantic are pinned to exactly ONE
## file each — matches what spawn_mode_2_wave_<map>.cfg already remembers as "last_file" (the file
## arena_wave_director_v2.gd auto-loads at run start), so Save here can never drift from what the
## live game actually uses, and free Save-as-any-name is gone for these 3. Any OTHER map id (only
## "default"/Space today) keeps the original free Name + Save-as-any-name + Load-any-.json behavior
## — it was never tied to one map-specific roster in the first place.
const MAP_FIXED_FILES := {
	"electric": "elecforest.json",
	"volcanic": "vocalnic.json",
	"atlantic": "atlantic.json",
}

func _fixed_file_for_map() -> String:
	return String(MAP_FIXED_FILES.get(_current_map_id(), ""))

## Per-map enemy-icon folder (mirrors creep_edit_mode.gd's own MAP_REGISTRY — duplicated here as 3
## plain strings rather than preloading that whole editor). Used to scope the Unit/Fleet pickers and
## "Generate Base on HP" to "creep nội bộ của map đang chọn" — see _map_enemy_ids()/_map_fleets().
const MAP_ENEMY_FOLDERS := {
	"electric": "res://assets/map/electric/enemies/",
	"volcanic": "res://assets/map/volcanic/enemies/",
	"atlantic": "res://assets/map/atlantic/enemies/",
}
## Folders shared by EVERY map, layered on top of a map's own folder above — some ids already used by
## a map's real saved timeline still live here, not yet migrated to their own map/<name>/ folder (e.g.
## "shooter" for Electric, "magma2"/"magma5"/"magma7" for Volcanic's own V.Mag2 fleet family), and
## bosses are deliberately reusable as any map's finale. Excluding this pool would silently break
## content that already works, per explicit request to keep it merged in.
const SHARED_ENEMY_FOLDERS := [
	"res://assets/enemiesHD/",
	"res://assets/bosses/",
]

## Enemy ids "belonging" to the current map (own folder + SHARED_ENEMY_FOLDERS). Falls back to the
## full roster for any map with no MAP_ENEMY_FOLDERS entry (today: "default"/Space).
func _map_enemy_ids() -> Array:
	var own_folder := String(MAP_ENEMY_FOLDERS.get(_current_map_id(), ""))
	if own_folder == "" or _director == null:
		return _types.duplicate()
	var allowed: Array = [own_folder] + SHARED_ENEMY_FOLDERS
	var out: Array = []
	for id in _types:
		var ids := String(id)
		var icon := String((_director.ENEMY_DEFS.get(ids, {}) as Dictionary).get("icon", ""))
		for prefix in allowed:
			if icon.begins_with(String(prefix)):
				out.append(ids)
				break
	return out

## Fleet-NAME prefix → map id — the authoritative convention (2026-08-17 request: "V." fleets are
## Volcanic's, "AT." fleets are Atlantic's — and by the same convention, "A." fleets are Electric's).
## Checked longest-prefix-first so "AT.WhalePod.Guard.10" is never misread against "A." — though in
## practice a real "AT." name can never match begins_with("A.") anyway (its 2nd char is "T", not "."),
## order is kept defensive/explicit regardless.
const FLEET_PREFIX_MAP := [
	{"prefix": "AT.", "map": "atlantic"},
	{"prefix": "V.", "map": "volcanic"},
	{"prefix": "A.", "map": "electric"},
]

## Fleets "belonging" to the current map: a recognized FLEET_PREFIX_MAP prefix decides outright
## (authoritative — per request). Legacy fleets with no recognized prefix (Kingdom1/2, NebulaFleet1,
## Prosmothership — pre-dating the naming convention) fall back to the same folder rule
## _map_enemy_ids() uses: eligible if ANY of its slots' member enemy ids resolves to an allowed folder
## (so e.g. Kingdom1/2, sentinel-based, still count as Electric). Falls back to every fleet for
## "default"/unmapped maps. Only for the PICKER (Fleet tab) and Gen's candidate pool —
## _fleet_total_hp()/_refresh_pad_for_active_slot() must keep resolving ANY fleet by name regardless
## of the current map, so they still use the raw _load_fleets() unfiltered.
func _map_fleets() -> Array:
	var all_fleets := _load_fleets()
	var map_id := _current_map_id()
	if not MAP_ENEMY_FOLDERS.has(map_id):
		return all_fleets
	var allowed: Array = [String(MAP_ENEMY_FOLDERS[map_id])] + SHARED_ENEMY_FOLDERS
	var out: Array = []
	for fl in all_fleets:
		var fld: Dictionary = fl
		var nm := String(fld.get("name", ""))
		var prefix_map := ""
		for pm: Dictionary in FLEET_PREFIX_MAP:
			if nm.begins_with(String(pm["prefix"])):
				prefix_map = String(pm["map"])
				break
		if prefix_map != "":
			if prefix_map == map_id:
				out.append(fl)
			continue   # recognized prefix but for a DIFFERENT map — never falls through to the folder guess
		if _director == null:
			continue   # no recognized prefix and can't run the folder fallback — exclude, don't guess
		var eligible := false
		for s: Dictionary in (fld.get("slots", []) as Array):
			for en in (s.get("enemies", []) as Array):
				var icon := String((_director.ENEMY_DEFS.get(String(en), {}) as Dictionary).get("icon", ""))
				for prefix in allowed:
					if icon.begins_with(String(prefix)):
						eligible = true
						break
				if eligible:
					break
			if eligible:
				break
		if eligible:
			out.append(fl)
	return out
const TEST_WAVES := 20   # how many repeating time points a Quick-test builds (each spawns COUNT enemies)
const GRID_STEP := 5.0   # seconds between template rows
const GRID_ROWS := 360   # 5, 10, … , 1800
const SLOTS_PER_ROW := 10 # 2×5 spawn slots per row
const GEN_HP_TOLERANCE := 0.10   # "Generate Base on HP" aims within ±10% of the row's target field
const SHOOT_TYPE_CAP := 10   # 2026-08-17 request: ranged/"shoot"-behavior creeps capped at this many
							  # PER GENERATED WAVE (row), regardless of HP-derived count — a swarm of
							  # ranged attackers is a much bigger threat than the same HP total in
							  # melee/contact-only creeps. See _is_shoot_type().
const TYPE_BTN_FULL_W := 220   # original Type-column button width
const TYPE_BTN_W := TYPE_BTN_FULL_W / 2   # 2026-08-17 request: shorten the Type column buttons to 50%

var _director: Node = null
var _root: Control = null
var _rows_box: VBoxContainer = null
var _title: Label = null
var _name_edit: LineEdit = null
var _test_type: OptionButton = null
var _test_count: SpinBox = null
var _test_interval: SpinBox = null
var _file_opt: OptionButton = null
var _status: Label = null
var _readout: TextEdit = null
var _rows: Array = []
var _types: Array = []
var _open: bool = false
var _prev_paused: bool = false         # pause state before opening → restored on close (dev:on stays paused)
var _font: FontFile = null
var _dropdown: Control = null          # the open Type popup (Unit/Fleet picker + 2×5 slot grid)
var _slots_grid: GridContainer = null  # the 2×5 slot grid inside the open popup
var _icon_cache: Dictionary = {}
# ── Shared Fleet direction-pad (spawn-angle 8-button compass + rotate slider) — ONE panel above the slot
# grid, not per-slot; click a Fleet slot cell to make it the pad's target. See _build_fleet_dir_pad().
var _pad_row: Dictionary = {}
var _pad_slot_idx: int = -1
var _pad_thumb: Control = null   # a _FleetPreview instance
var _pad_buttons: Array = []
var _pad_dirs: Array = []        # degrees per _pad_buttons index, same order
var _pad_slider: HSlider = null
var _pad_hint: Label = null

func _ready() -> void:
	add_to_group("wave_editor")   # the dev:on Wave_edit button toggles us via this group
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# _font intentionally left null — every "if _font: ...add_theme_font_override(...)" call site in this
	# file then no-ops, so every label/button/field falls back to Godot's default theme font instead of
	# Gameplay.ttf. FONT_PATH is kept (unused) in case this needs reverting.
	_director = get_tree().get_first_node_in_group("wave_director")
	if _director != null and _director.has_method("enemy_types"):
		_types = _director.enemy_types()
	_build_ui()
	_root.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F7:
		_toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:   # public entry for the Wave_edit HUD button (same as F7)
	_toggle()

## Public — read by arena_hud_buttons.gd's centralized Esc-closes-whichever-dev-panel-is-open handler.
func is_open() -> bool:
	return _open

func _toggle() -> void:
	_open = not _open
	_root.visible = _open
	if _open:
		_prev_paused = get_tree().paused
		get_tree().paused = true
	else:
		get_tree().paused = _prev_paused   # keep dev:on paused; only the dev:on→dev:off button resumes
		_close_dropdown()
	if _open:
		if _director == null or not is_instance_valid(_director):
			_director = get_tree().get_first_node_in_group("wave_director")
		_rebuild_rows()
		_refresh_files()
		_refresh_readout()
		_sync_active_file()

## Reflects whatever file is actually driving the CURRENT run (arena_wave_director_v2.gd's own
## _load_remembered_timeline() already auto-loaded it into the live timeline at run start — this just
## syncs the Name field + file dropdown selection to match, so opening F7 doesn't show a blank "my_timeline"
## placeholder next to rows that are actually the active file's). Purely cosmetic — the rows themselves
## (_rebuild_rows(), just above) already come from _director.get_timeline() regardless.
func _sync_active_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_last_wave_cfg_path()) != OK:
		return
	var fname := String(cfg.get_value("wave", "last_file", ""))
	if fname == "":
		return
	_name_edit.text = _txt(fname.get_basename())
	for i in _file_opt.item_count:
		if _file_opt.get_item_text(i) == fname:
			_file_opt.selected = i
			return

func _process(_delta: float) -> void:
	if _open and _director != null and _director.has_method("elapsed"):
		_title.text = _txt("ARENA WAVE EDITOR   (F7 to close)    —    t = %.1fs" % _director.elapsed())

# ── UI ──────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(220, 40)
	panel.size = Vector2(1000, 700)
	_style(panel)
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 10)
	vb.size = Vector2(976, 680)
	vb.add_theme_constant_override("separation", 7)
	panel.add_child(vb)

	_title = _mk_label("ARENA WAVE EDITOR   (F7 to close)", 16)
	vb.add_child(_title)

	# Name + Save / Load library row.
	var lib := HBoxContainer.new()
	lib.add_theme_constant_override("separation", 8)
	lib.add_child(_mk_label("Name", 12))
	_name_edit = LineEdit.new()
	_name_edit.text = _txt("my_timeline")
	_name_edit.custom_minimum_size = Vector2(180, 0)
	if _font: _name_edit.add_theme_font_override("font", _font)
	lib.add_child(_name_edit)
	lib.add_child(_mk_button("Save", _on_save))
	_file_opt = OptionButton.new()
	_file_opt.custom_minimum_size = Vector2(220, 0)
	if _font: _file_opt.add_theme_font_override("font", _font)
	lib.add_child(_file_opt)
	var load_btn := _mk_button("Load", _on_load)
	load_btn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
	lib.add_child(load_btn)
	lib.add_child(_mk_button("Refresh", _refresh_files))
	_status = _mk_label("", 11)
	_status.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	lib.add_child(_status)
	vb.add_child(lib)

	# Quick-test builder: one locked type, selectable count, fixed interval → a single-type repeating timeline.
	var qt := HBoxContainer.new()
	qt.add_theme_constant_override("separation", 8)
	qt.add_child(_mk_label("Quick test:", 12))
	_test_type = OptionButton.new()
	_test_type.custom_minimum_size = Vector2(130, 0)
	if _font: _test_type.add_theme_font_override("font", _font)
	for i in _types.size():
		_test_type.add_item(String(_types[i]), i)
	qt.add_child(_test_type)
	qt.add_child(_mk_label("count", 11))
	_test_count = _mk_spin(1.0, 200.0, 1.0, 30.0, 80)
	qt.add_child(_test_count)
	qt.add_child(_mk_label("every (s)", 11))
	_test_interval = _mk_spin(0.5, 120.0, 0.5, 10.0, 80)
	qt.add_child(_test_interval)
	qt.add_child(_mk_button("Build test timeline", _on_build_test))
	vb.add_child(qt)

	vb.add_child(HSeparator.new())

	# Column header. Count / Pattern / Dur / Boss now live PER-SLOT inside the Type popup, so the table is just
	# Min + Time + Type(Blank/Set) + Total HP + Actual HP + Generate Base on HP + delete. "Min" is a minute-mark
	# ruler alongside Time(s) — see _add_row()'s minute label — not an independent editable value. "Total HP" is
	# a user-editable TARGET field (see _add_row()'s hp_spin comment); "Actual HP" is a read-only live readout
	# of the row's real current slot-content total (see _add_row()'s actual_hp_lbl); "Generate Base on HP"
	# holds this row's own Gen button. Type button width is 50% of TYPE_BTN_FULL_W (2026-08-17 request).
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	for h: Array in [["Min", 36], ["Time(s)", 90], ["Type (Blank / Set)", TYPE_BTN_W], ["Total HP", 130], ["Actual HP", 130], ["Generate Base on HP", 110], ["", 36]]:
		var l := _mk_label(String(h[0]), 11)
		l.custom_minimum_size = Vector2(float(h[1]), 0)
		hdr.add_child(l)
	vb.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(956, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	btns.add_child(_mk_button("+ Add Wave", _on_add))
	btns.add_child(_mk_button("Sort by time", _on_sort))
	var gen_all_btn := _mk_button("Gen All (HP)", _on_gen_all)
	gen_all_btn.tooltip_text = "Generate every row whose 'Total HP' field is > 0 (skips rows left at 0)"
	gen_all_btn.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	btns.add_child(gen_all_btn)
	var apply_btn := _mk_button("Apply & Restart", _on_apply)
	apply_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	btns.add_child(apply_btn)
	btns.add_child(_mk_button("Reset (blank 360 grid)", _on_reset))
	var close_btn := _mk_button("Close", _toggle)
	close_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	btns.add_child(close_btn)

	_readout = TextEdit.new()
	_readout.editable = false
	_readout.custom_minimum_size = Vector2(956, 96)
	if _font: _readout.add_theme_font_override("font", _font)
	_readout.add_theme_font_size_override("font_size", 10)
	vb.add_child(_readout)

# ── Rows ──────────────────────────────────────────────────────────────────────
## Fresh empty slot record.
func _slot_default() -> Dictionary:
	return {"type": "", "count": 5, "pattern": "ring", "is_boss": false, "duration": 0.0}

## Build the blank 5-second-grid template: GRID_ROWS rows at 5, 10, … , 1800s, all slots empty.
func _build_template_grid() -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	for i in GRID_ROWS:
		_add_row(GRID_STEP * float(i + 1))

## Open / Reset shows the 360-row template; existing timeline entries are snapped onto the nearest grid row
## (each becomes one filled slot). Lossless re-open of timelines already authored on the 5s grid.
func _rebuild_rows() -> void:
	_build_template_grid()
	if _director == null:
		return
	for entry: Dictionary in _director.get_timeline():
		var row := _grid_row_for_time(float(entry.get("time", 0.0)))
		if row.is_empty():
			continue
		var slots: Array = row["slots"]
		for j in slots.size():
			if String((slots[j] as Dictionary).get("type", "")) == "":
				slots[j] = {
					"type": String(entry.get("type", "")),
					"count": int(entry.get("count", 1)),
					"pattern": String(entry.get("pattern", "ring")),
					"is_boss": bool(entry.get("is_boss", false)),
					"duration": float(entry.get("duration", 0.0)),
					"angle": float(entry.get("angle", 0.0)),
					"angle_fixed": entry.has("angle"),
					"fleet_rotate": float(entry.get("fleet_rotate", 0.0)),
				}
				break
		_update_type_btn(row)
		_update_row_hp(row)

## Find the template row whose time matches `t` snapped to the nearest 5s grid point (clamped 5…1800).
func _grid_row_for_time(t: float) -> Dictionary:
	var snapped := clampf(round(t / GRID_STEP) * GRID_STEP, GRID_STEP, GRID_STEP * float(GRID_ROWS))
	for r: Dictionary in _rows:
		if absf(float(r["time_val"]) - snapped) < 0.01:
			return r
	return {}

func _add_row(time: float, preset_slots: Array = []) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	# Minute-mark ruler: blank on every row except the ones landing exactly on a whole minute (60, 120,
	# 180…), which show that minute number — a visual guide alongside the per-second Time column, not a
	# separate editable value. Purely a function of this row's own `time`, independent of row order/neighbors.
	var min_text := ""
	if time > 0.0 and is_equal_approx(fmod(time, 60.0), 0.0):
		min_text = "%d" % int(round(time / 60.0))
	var min_lbl := _mk_label(min_text, 11)
	min_lbl.custom_minimum_size = Vector2(36, 0)
	min_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(min_lbl)

	# Time — read-only display (2026-08-02: was an editable SpinBox; the 5s-grid template already covers
	# every authorable time slot, see _build_template_grid(), so retiming a row in place is no longer
	# offered here). The row's authoritative time now lives in `time_val` (a plain float), not a control
	# property — _grid_row_for_time()/_collect()/_on_sort() all read that instead of a SpinBox.value.
	var time_text := ("%d" % int(round(time))) if is_equal_approx(time, round(time)) else ("%.2f" % time)
	var time_lbl := _mk_label(time_text, 12)
	time_lbl.custom_minimum_size = Vector2(90, 0)
	hb.add_child(time_lbl)

	# Type — a fixed-width button showing Blank / Set; opens the picker + 2×5 slot popup.
	var type_btn := Button.new()
	type_btn.custom_minimum_size = Vector2(TYPE_BTN_W, 0)
	type_btn.clip_text = true
	if _font: type_btn.add_theme_font_override("font", _font)
	hb.add_child(type_btn)

	# Total HP — was a read-only live sum of this row's slots; now a user-editable TARGET field instead
	# ("Generate Base on HP" fills the row so its real total lands within GEN_HP_TOLERANCE of this value).
	# The row's actual live slot-content total is still shown in the Type popup's own "Total HP" header
	# (_row_total_hp(), unchanged) whenever that popup is open — this field is only ever the Gen target.
	var hp_spin := _mk_spin(0.0, 100000000.0, 100.0, 0.0, 130)
	hp_spin.tooltip_text = "Target HP for 'Generate Base on HP' — 0 = don't generate this row"
	hb.add_child(hp_spin)

	# Actual HP — read-only, display only: the row's REAL current slot-content total (same value/math
	# as the Type popup's own "Total HP" header — _row_total_hp()). Kept live by _update_row_hp().
	var actual_hp_lbl := _mk_label(_fmt_hp(0.0), 12)
	actual_hp_lbl.custom_minimum_size = Vector2(130, 0)
	actual_hp_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	hb.add_child(actual_hp_lbl)

	# Generate Base on HP — per-row Gen button; fills this row's slots with a random creep/fleet mix
	# whose combined HP lands within GEN_HP_TOLERANCE of the field above. No-op while that field is 0.
	var gen_btn := Button.new()
	gen_btn.text = _txt("Gen")
	gen_btn.custom_minimum_size = Vector2(110, 0)
	if _font: gen_btn.add_theme_font_override("font", _font)
	hb.add_child(gen_btn)

	var clr := Button.new()
	clr.text = _txt("X")
	clr.tooltip_text = "Clear this row's units/fleets (back to Blank)"
	clr.custom_minimum_size = Vector2(36, 0)
	if _font: clr.add_theme_font_override("font", _font)
	hb.add_child(clr)

	_rows_box.add_child(hb)
	var slots: Array = []
	for i in SLOTS_PER_ROW:
		slots.append(preset_slots[i] if i < preset_slots.size() else _slot_default())
	var row := {"hbox": hb, "time_val": time, "type_btn": type_btn, "hp_spin": hp_spin, "target_hp": 0.0, "actual_hp_lbl": actual_hp_lbl, "slots": slots}
	type_btn.pressed.connect(func() -> void: _open_type_dropdown(row))
	clr.pressed.connect(func() -> void: _clear_row(row))
	hp_spin.value_changed.connect(func(v: float) -> void: row["target_hp"] = v)
	gen_btn.pressed.connect(func() -> void: _on_gen_row(row))
	_update_type_btn(row)
	_update_row_hp(row)
	_rows.append(row)

## Empty every slot of a row (back to Blank). The row itself stays — X no longer deletes rows.
func _clear_row(row: Dictionary) -> void:
	var slots: Array = row["slots"]
	for i in slots.size():
		slots[i] = _slot_default()
	_update_type_btn(row)
	_update_row_hp(row)

## Sum of (base hp × count × blob) across this row's filled slots, "fleet:" slots included: a fleet slot's
## contribution is _fleet_total_hp(name) (sum of every unit in the fleet — see its own comment) × the
## slot's own "n" (count) = how many times that whole formation deploys (mirrors the Unit slot's count).
## "blob" (e.g. "swarm", blob:50)
## multiplies in too — each queued position for a blob type actually spawns `blob` creeps around it at
## runtime (_tl_queue_or_spawn()), not just 1, so `count` alone understates the real total for those types.
## Uses the RAW def "hp" — NOT the runtime-applied ENEMY_HP_TUNE (×2) or any "lvl"/Beacon/Elite-Creep
## multiplier, since those depend on player level/aux state unknowable at authoring time — read as a
## relative/base-line indicator, not the exact in-run total. Fleet deployment (incl. "count"/n) is now
## wired up in arena_wave_director_v2.gd's _deploy_fleet(), so this matches what actually spawns.
func _row_total_hp(row: Dictionary) -> float:
	var total := 0.0
	if _director == null:
		return total
	for s: Dictionary in row["slots"]:
		var ty := String(s.get("type", ""))
		if ty == "":
			continue
		if ty.begins_with("fleet:"):
			total += _fleet_total_hp(ty.substr(6)) * float(int(s.get("count", 1)))
			continue
		var d: Dictionary = _director.ENEMY_DEFS.get(ty, {})
		var hp := float(d.get("hp", 0.0))
		var blob := maxi(1, int(d.get("blob", 1)))
		total += hp * float(int(s.get("count", 1))) * float(blob)
	return total

## Total HP of fleet `fleet_name`: hp summed over EVERY unit listed in EVERY slot's "enemies" array (per
## explicit correction — the fleet's HP is the sum of all its units, full stop). Note this counts every
## entry in a multi-option slot (e.g. Kingdom1's ["sentinel2","sentinel1"] slot) even though
## arena_wave_director_v2.gd's _deploy_fleet() only rolls ONE of them at actual deploy time — this is an
## authored/planning total ("everything in the fleet"), not a probability-weighted runtime estimate.
## Deliberately NOT × blob (unlike a plain Unit slot's HP, which really does blob-expand — see
## _row_total_hp() below): _deploy_fleet()'s rigid carrier+dock formation spawns exactly ONE creep per slot
## regardless of that creep type's own "blob" stat — a blob-type unit inside a fleet does NOT multiply out.
func _fleet_total_hp(fleet_name: String) -> float:
	if _director == null:
		return 0.0
	var fleet: Dictionary = {}
	for fl in _load_fleets():
		if String((fl as Dictionary).get("name", "")) == fleet_name:
			fleet = fl
			break
	if fleet.is_empty():
		return 0.0
	var total := 0.0
	for s: Dictionary in (fleet.get("slots", []) as Array):
		for en in (s.get("enemies", []) as Array):
			var id := String(en)
			if id == "":
				continue
			var d: Dictionary = _director.ENEMY_DEFS.get(id, {})
			total += float(d.get("hp", 0.0))
	return total

# ── Generate Base on HP ──────────────────────────────────────────────────────────
## True for any enemy def with a ranged attack — the 4 classic behaviors that fire projectiles
## ("shooter"/"beamer"/"bomber"/"missile"), the "gauss_shooter" flag (pros5 — ranged bolted onto a
## "chase" behavior), or an explicit Creep Info "shoot" override (the composed move/shoot system —
## anything other than "none"). Contact-only/melee creeps (the vast majority of the roster) are false.
func _is_shoot_type(d: Dictionary) -> bool:
	if String(d.get("behavior", "")) in ["shooter", "beamer", "bomber", "missile"]:
		return true
	if bool(d.get("gauss_shooter", false)):
		return true
	if d.has("shoot") and String(d.get("shoot", "none")) != "none":
		return true
	return false

## Auto-fills `row`'s slots with a random creep/fleet mix whose combined HP lands within
## GEN_HP_TOLERANCE of `target` — clears the row first, so every Gen press is a fresh composition,
## not a patch on top of whatever was there. Returns the actually-achieved total (via the same
## _row_total_hp() every other HP readout in this file already uses, so it's always the same truth
## the Type popup's own "Total HP" header would show). No-op (row left blank) for target <= 0.
func _generate_row_hp(row: Dictionary, target: float) -> float:
	var slots: Array = row["slots"]
	for i in slots.size():
		slots[i] = _slot_default()
	if _director == null or target <= 0.0:
		_update_type_btn(row)
		_update_row_hp(row)
		return 0.0

	# Candidate pools — every enemy type / fleet BELONGING TO THE CURRENT MAP (_map_enemy_ids()/
	# _map_fleets()), minus one-off bosses (behavior "boss_stub", or "gate_waves" like the Scorpion)
	# which don't belong in a randomly-generated filler wave. Unit hp already folds in "blob" (matches
	# _row_total_hp()).
	var unit_pool: Array = []   # [{id, hp}]
	for id in _map_enemy_ids():
		var ids := String(id)
		var d: Dictionary = _director.ENEMY_DEFS.get(ids, {})
		if String(d.get("behavior", "")) == "boss_stub" or bool(d.get("gate_waves", false)):
			continue
		var hp := float(d.get("hp", 0.0)) * float(maxi(1, int(d.get("blob", 1))))
		if hp > 0.0:
			unit_pool.append({"id": ids, "hp": hp})
	var fleet_pool: Array = []   # [{name, hp}]
	for fl in _map_fleets():
		var nm := String((fl as Dictionary).get("name", ""))
		var fhp := _fleet_total_hp(nm)
		if fhp > 0.0:
			fleet_pool.append({"name": nm, "hp": fhp})
	if unit_pool.is_empty() and fleet_pool.is_empty():
		_update_type_btn(row)
		_update_row_hp(row)
		return 0.0

	var patterns: Array = _director.PATTERNS
	var slot_i := 0
	var shoot_used: Dictionary = {}   # unit id -> total count already placed in THIS row (SHOOT_TYPE_CAP applies per row, not per slot — a wave could otherwise reach the cap in slot 1 and again in slot 2)
	var iterations := 0
	# Phase 1 — greedy fill: drop picks (unit or fleet, ~35% fleet chance when both are available)
	# into empty slots, each sized to roughly absorb whatever's left of the target, until either the
	# 10 slots run out or the remainder is already small enough for Phase 2 to close exactly. Capped
	# retry budget (iterations) so an all-maxed-out-shoot-type pool can't spin forever without ever
	# advancing slot_i — see the "cap <= 0" skip below.
	while slot_i < slots.size() and iterations < slots.size() * 4:
		iterations += 1
		var achieved := _row_total_hp(row)
		var remaining := target - achieved
		if remaining <= target * 0.02:
			break
		var use_fleet := not fleet_pool.is_empty() and (unit_pool.is_empty() or randf() < 0.35)
		if use_fleet:
			var f: Dictionary = fleet_pool[randi() % fleet_pool.size()]
			var fhp: float = f["hp"]
			var n := clampi(int(round(remaining / fhp)), 1, 20)   # sane cap on how many copies of one fleet
			slots[slot_i] = {"type": "fleet:" + String(f["name"]), "count": n, "pattern": "ring", "is_boss": false, "duration": 0.0}
		else:
			var u: Dictionary = unit_pool[randi() % unit_pool.size()]
			var uhp: float = u["hp"]
			var uid: String = u["id"]
			# HP-scaled per-slot cap (cheap fry can swarm higher, pricey types stay small) — mirrors the
			# same "12000 budget" idea used to author the map wave JSONs, so a Gen'd row doesn't dump an
			# absurd single count of an expensive creep into one slot.
			var cap := clampi(int(round(12000.0 / uhp)), 5, 500)
			# Ranged/"shoot" creeps get a hard SHOOT_TYPE_CAP-per-row ceiling on top of the above,
			# regardless of HP — a swarm of shooters/beamers/missiles is far more dangerous than the
			# same HP total in melee creeps (2026-08-17 request).
			if _is_shoot_type(_director.ENEMY_DEFS.get(uid, {})):
				cap = mini(cap, SHOOT_TYPE_CAP - int(shoot_used.get(uid, 0)))
				if cap <= 0:
					continue   # this shoot type is already at cap for the row — retry with a fresh pick, don't consume a slot
			var count := clampi(int(round(remaining / uhp)), 1, cap)
			if _is_shoot_type(_director.ENEMY_DEFS.get(uid, {})):
				shoot_used[uid] = int(shoot_used.get(uid, 0)) + count
			slots[slot_i] = {"type": uid, "count": count, "pattern": String(patterns[randi() % patterns.size()]), "is_boss": false, "duration": 0.0}
		slot_i += 1

	# Phase 2 — fine-tune: solve the LAST filled slot's count exactly so the total lands as close to
	# target as its own per-slot cap allows, instead of leaving whatever Phase 1's rounding produced.
	if slot_i > 0:
		var last: Dictionary = slots[slot_i - 1]
		var lt := String(last.get("type", ""))
		var lhp := 0.0
		if lt.begins_with("fleet:"):
			lhp = _fleet_total_hp(lt.substr(6))
		elif lt != "":
			var ld: Dictionary = _director.ENEMY_DEFS.get(lt, {})
			lhp = float(ld.get("hp", 0.0)) * float(maxi(1, int(ld.get("blob", 1))))
		if lhp > 0.0:
			var others := _row_total_hp(row) - lhp * float(int(last.get("count", 1)))
			var need := target - others
			var new_count := maxi(1, int(round(need / lhp)))
			if not lt.begins_with("fleet:") and _is_shoot_type(_director.ENEMY_DEFS.get(lt, {})):
				# Cap against SHOOT_TYPE_CAP minus whatever OTHER slots of this same type already used
				# (shoot_used still includes this slot's own Phase-1 count — subtract it back out first).
				var other_shoot_use := int(shoot_used.get(lt, 0)) - int(last.get("count", 1))
				new_count = clampi(new_count, 1, maxi(1, SHOOT_TYPE_CAP - other_shoot_use))
			last["count"] = new_count

	_update_type_btn(row)
	_update_row_hp(row)
	return _row_total_hp(row)

## Per-row "Gen" button — see column "Generate Base on HP". Skips (with a status message) if the
## row's target field is 0.
func _on_gen_row(row: Dictionary) -> void:
	var target := float(row.get("target_hp", 0.0))
	if target <= 0.0:
		_set_status("t=%ds — HP is 0, skipped" % int(round(float(row["time_val"]))))
		return
	var achieved := _generate_row_hp(row, target)
	_refresh_readout()
	var pct := (achieved / target - 1.0) * 100.0
	var flag := "" if absf(pct) <= GEN_HP_TOLERANCE * 100.0 else "  (outside ±10%)"
	_set_status("Generated t=%ds — target %s, got %s (%+.1f%%)%s" % [int(round(float(row["time_val"]))), _fmt_hp(target), _fmt_hp(achieved), pct, flag])

## Top "Gen All (HP)" button — generates every row whose target field is > 0; rows left at 0 are
## skipped entirely, per request.
func _on_gen_all() -> void:
	var n := 0
	var total_target := 0.0
	var total_achieved := 0.0
	for row: Dictionary in _rows:
		var target := float(row.get("target_hp", 0.0))
		if target <= 0.0:
			continue
		total_achieved += _generate_row_hp(row, target)
		total_target += target
		n += 1
	_refresh_readout()
	if n == 0:
		_set_status("Gen All — no rows have HP set (every 'Total HP' field is 0)")
		return
	var pct := (total_achieved / total_target - 1.0) * 100.0 if total_target > 0.0 else 0.0
	_set_status("Gen All — %d row(s) generated, target %s, got %s (%+.1f%%)" % [n, _fmt_hp(total_target), _fmt_hp(total_achieved), pct])

## Exact integer HP with thousands separators (e.g. "1,234,500") — no K/M abbreviation, no precision lost.
## round() here only cancels float-multiplication noise (hp × count × blob are all whole numbers in
## practice); it is not a display-rounding of the actual total.
func _fmt_hp(v: float) -> String:
	var n := int(round(v))
	var digits := str(absi(n))
	var out := ""
	var c := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

## Refreshes the row-list's read-only "Actual HP" column, and the Type popup's own "Total HP" header
## (if open for this row) — both show the row's real, current slot-content total (_row_total_hp()).
## The row-list's "Total HP" column is a separate, user-editable TARGET field (see _add_row()'s
## hp_spin) — nothing to write there; it never reflects live slot content.
func _update_row_hp(row: Dictionary) -> void:
	var real := _row_total_hp(row)
	var actual_lbl: Variant = row.get("actual_hp_lbl")
	if actual_lbl != null and is_instance_valid(actual_lbl):
		(actual_lbl as Label).text = _txt(_fmt_hp(real))
	var popup_lbl: Variant = row.get("popup_hp_lbl")
	if popup_lbl != null and is_instance_valid(popup_lbl):
		(popup_lbl as Label).text = _txt("Total HP " + _fmt_hp(real))

## Type button label: "Set (N)" when any slot is filled (N = filled count), else "Blank".
func _update_type_btn(row: Dictionary) -> void:
	var n := 0
	for s: Dictionary in row["slots"]:
		if String(s.get("type", "")) != "":
			n += 1
	var btn := row["type_btn"] as Button
	btn.text = _txt(("Set (%d)" % n) if n > 0 else "Blank")
	btn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35) if n > 0 else Color(1.0, 1.0, 1.0))

## Expand every row's filled slots into FLAT timeline entries (one entry per slot, all sharing the row's time).
func _collect() -> Array:
	var entries: Array = []
	for r: Dictionary in _rows:
		var t: float = float(r["time_val"])
		for s: Dictionary in r["slots"]:
			var ty := String(s.get("type", ""))
			if ty == "":
				continue
			var pat := String(s.get("pattern", "ring"))
			var e := {"time": t, "type": ty, "count": int(s.get("count", 1)), "pattern": pat}
			if pat == "stream":
				e["duration"] = float(s.get("duration", 0.0))
			if bool(s.get("is_boss", false)):
				e["is_boss"] = true
			if bool(s.get("angle_fixed", false)):
				e["angle"] = float(s.get("angle", 0.0))
			if ty.begins_with("fleet:") and not is_zero_approx(float(s.get("fleet_rotate", 0.0))):
				e["fleet_rotate"] = float(s.get("fleet_rotate", 0.0))
			entries.append(e)
	return entries

# ── Actions ───────────────────────────────────────────────────────────────────
func _on_add() -> void:
	var t := GRID_STEP
	if _director != null and _director.has_method("elapsed"):
		t = clampf(round(float(_director.elapsed()) / GRID_STEP) * GRID_STEP, GRID_STEP, GRID_STEP * float(GRID_ROWS))
	_add_row(t)

## Re-order the rows by ascending time (re-arranges them in the list).
func _on_sort() -> void:
	_rows.sort_custom(func(a, b): return float(a["time_val"]) < float(b["time_val"]))
	for i in _rows.size():
		_rows_box.move_child(_rows[i]["hbox"], i)
	_set_status("Sorted %d rows by time" % _rows.size())

func _on_apply() -> void:
	if _director != null:
		_director.set_timeline(_collect())
	_rebuild_rows()
	_refresh_readout()

func _on_reset() -> void:
	_build_template_grid()
	_refresh_readout()
	_set_status("Reset to blank 360-row grid (5 → 1800s)")

## Build a single-type repeating timeline: TEST_WAVES time points, every `interval` seconds, each spawning
## COUNT enemies of the picked type. (COUNT is applied to every time point.)
func _on_build_test() -> void:
	if _types.is_empty():
		return
	var t: String = String(_types[_test_type.selected])
	var per_wave := int(_test_count.value)
	var iv: float = _test_interval.value
	var entries: Array = []
	for i in TEST_WAVES:
		entries.append({"time": float(i) * iv, "type": t, "count": per_wave, "pattern": "scatter"})
	if _director != null:
		_director.set_timeline(entries)
	if _fixed_file_for_map() == "":   # locked maps always save under their own fixed name — leave it alone
		_name_edit.text = "test_" + t   # so Save names it sensibly in the library
	_rebuild_rows()
	_refresh_readout()
	_set_status("Built %d waves × %d %s, every %.1fs" % [TEST_WAVES, per_wave, t, iv])

# ── Save / Load library (JSON in res://levels/arena/) ───────────────────────────
func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	# Locked maps (see MAP_FIXED_FILES) always save to their own ONE file, ignoring whatever's in the
	# (now read-only, for these maps) Name field — no more free Save-as-any-name for electric/volcanic/atlantic.
	var fixed := _fixed_file_for_map()
	var fname := fixed if fixed != "" else (_sanitize(_name_edit.text) + ".json")
	var display_name := fixed.get_basename() if fixed != "" else _name_edit.text
	var tl := _collect()
	var f := FileAccess.open(LEVELS_DIR + "/" + fname, FileAccess.WRITE)
	if f == null:
		_set_status("Save FAILED")
		return
	f.store_string(JSON.stringify({"name": display_name, "timeline": tl}, "  "))
	f.close()
	# Live-apply + remember, same as _on_load() does — otherwise the disk write succeeds but (a) THIS
	# panel keeps showing the director's now-stale live timeline on reopen (_rebuild_rows() reads
	# _director.get_timeline(), never the file — see its own comment) and (b) the next run's auto-load
	# (_last_wave_cfg_path()) keeps pointing at whatever was last Loaded, not this Save — together making
	# a Save-only edit look like it silently reverted (2026-08-02 bug report: reproduces on any map, not
	# just Electric — Save alone never touched the live director before this fix).
	if _director != null:
		_director.set_timeline(tl)
	_remember_last_wave(fname)
	_refresh_files()
	for i in _file_opt.item_count:
		if _file_opt.get_item_text(i) == fname:
			_file_opt.selected = i
			break
	_set_status("Saved " + fname)

func _on_load() -> void:
	if _file_opt == null or _file_opt.item_count == 0:
		_set_status("No file")
		return
	var fname := _file_opt.get_item_text(_file_opt.selected)
	var f := FileAccess.open(LEVELS_DIR + "/" + fname, FileAccess.READ)
	if f == null:
		_set_status("Load FAILED")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("timeline"):
		_set_status("Bad JSON")
		return
	_name_edit.text = _txt(String((parsed as Dictionary).get("name", fname.get_basename())))
	if _director != null:
		_director.set_timeline((parsed as Dictionary)["timeline"])
	_remember_last_wave(fname)
	_rebuild_rows()
	_refresh_readout()
	_set_status("Loaded " + fname)

## Remembers `fname` as the last-loaded wave file so spawn_mode_2 auto-loads it on the NEXT run (see
## arena_wave_director_v2.gd._load_remembered_timeline(), read at its _ready()). Harmless when spawn_mode_1
## is active — v1 has no equivalent auto-load and never reads this file, so writing it costs nothing there.
func _remember_last_wave(fname: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wave", "last_file", fname)
	cfg.save(_last_wave_cfg_path())

func _refresh_files() -> void:
	if _file_opt == null:
		return
	# Locked maps: dropdown/Name show exactly that map's own file — no directory scan, no free rename.
	var fixed := _fixed_file_for_map()
	if fixed != "":
		_name_edit.editable = false
		_name_edit.text = _txt(fixed.get_basename())
		_file_opt.clear()
		_file_opt.add_item(fixed)
		_file_opt.selected = 0
		return
	_name_edit.editable = true
	var sel := _file_opt.get_item_text(_file_opt.selected) if _file_opt.item_count > 0 else ""
	_file_opt.clear()
	var d := DirAccess.open(LEVELS_DIR)
	if d != null:
		d.list_dir_begin()
		var fn := d.get_next()
		var files: Array = []
		while fn != "":
			if not d.current_is_dir() and fn.ends_with(".json"):
				files.append(fn)
			fn = d.get_next()
		d.list_dir_end()
		files.sort()
		for file: String in files:
			_file_opt.add_item(file)
	for i in _file_opt.item_count:
		if _file_opt.get_item_text(i) == sel:
			_file_opt.selected = i
			break

func _refresh_readout() -> void:
	if _readout != null and _director != null:
		_readout.text = _txt(JSON.stringify(_director.get_timeline(), "  "))

func _set_status(t: String) -> void:
	if _status != null:
		_status.text = _txt(t)

func _sanitize(s: String) -> String:
	var r := s.strip_edges().to_lower()
	if r == "":
		return "timeline"
	var out := ""
	for i in r.length():
		var c := r[i]
		out += c if c in "abcdefghijklmnopqrstuvwxyz0123456789-_" else "_"
	return out

# ── Type popup: Unit/Fleet picker (drag source) + 2×5 spawn slots (drop targets) ─────────────────
func _enemy_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	if _director != null:
		var d: Dictionary = _director.ENEMY_DEFS.get(id, {})
		var p := String(d.get("icon", ""))
		if p != "":
			tex = load(p) as Texture2D
	_icon_cache[id] = tex
	return tex

## Canonical on-screen draw width (px) for enemy `id`, mirroring fleet_edit_mode.gd's own enemy_draw_width() —
## Creep Edit's res://creep_layout.cfg is the sole source of truth for size (fleets no longer store their own
## per-slot size; see fleet_edit_mode.gd's header for the full rationale).
func enemy_draw_width(id: String) -> float:
	if _director == null:
		return 50.0
	return EnemyScript.base_draw_width(_director.ENEMY_DEFS.get(id, {}))

func _load_fleets() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load("res://fleet_layout.cfg") != OK:
		return []
	var data = cfg.get_value("fleets", "data", [])
	return data if data is Array else []

func _close_dropdown() -> void:
	if _dropdown != null and is_instance_valid(_dropdown):
		_dropdown.queue_free()
	_dropdown = null
	_slots_grid = null
	_pad_row = {}
	_pad_slot_idx = -1
	_pad_thumb = null
	_pad_buttons = []
	_pad_dirs = []
	_pad_slider = null
	_pad_hint = null

func _open_type_dropdown(row: Dictionary) -> void:
	_close_dropdown()
	# Full-rect catcher: a real click anywhere outside the panel closes the popup (wheel events ignored so the
	# inner ScrollContainers don't snap it shut at their scroll limit).
	_dropdown = Control.new()
	_dropdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			var bi := (e as InputEventMouseButton).button_index
			if bi == MOUSE_BUTTON_LEFT or bi == MOUSE_BUTTON_RIGHT or bi == MOUSE_BUTTON_MIDDLE:
				_close_dropdown())
	_root.add_child(_dropdown)

	var panel := Panel.new()
	_style(panel)
	var psize := Vector2(1180.0, 600.0)
	var vpz := get_viewport().get_visible_rect().size
	var pos := (vpz - psize) * 0.5   # centered on screen
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vpz.x - psize.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vpz.y - psize.y - 8.0))
	panel.position = pos
	panel.size = psize
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown.add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(8.0, 8.0)
	vb.size = psize - Vector2(16.0, 16.0)
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	# OK — top-left of the popup. Slot edits (drag-drop, count/pattern/boss spinboxes) already write straight
	# into row["slots"] live, so there's no separate "commit" step; OK just refreshes the bottom JSON readout
	# to reflect what was just entered, then closes — same effect as clicking outside, but explicit.
	var ok_btn := _mk_button("OK", func() -> void: _update_row_hp(row); _refresh_readout(); _close_dropdown())
	ok_btn.custom_minimum_size = Vector2(70.0, 0.0)
	ok_btn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
	tabs.add_child(ok_btn)
	var unit_tab := _mk_button("Unit", func() -> void: pass)
	var fleet_tab := _mk_button("Fleet", func() -> void: pass)
	unit_tab.custom_minimum_size = Vector2(120.0, 0.0)
	fleet_tab.custom_minimum_size = Vector2(120.0, 0.0)
	tabs.add_child(unit_tab)
	tabs.add_child(fleet_tab)
	tabs.add_child(_mk_label("◀ drag a Unit / Fleet into a slot ▶   (spawn together at this time)", 11))

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(content)

	# Left: the Unit grid / Fleet list picker (drag sources).
	var picker := Control.new()
	picker.custom_minimum_size = Vector2(300.0, 520.0)
	content.add_child(picker)
	var unit_panel := _build_unit_tab()
	var fleet_panel := _build_fleet_tab()
	picker.add_child(unit_panel)
	picker.add_child(fleet_panel)
	fleet_panel.visible = false
	unit_tab.pressed.connect(func() -> void: unit_panel.visible = true;  fleet_panel.visible = false)
	fleet_tab.pressed.connect(func() -> void: unit_panel.visible = false; fleet_panel.visible = true)

	content.add_child(VSeparator.new())

	# Middle: the shared Fleet spawn-direction/rotate pad — ALWAYS visible (not tied to the Unit/Fleet tab
	# above), targets whichever Fleet slot was last clicked on the right (see _select_fleet_pad_slot()).
	# EXPAND_FILL: soaks up whatever width the narrower slot cells free up, so the panel grows instead of
	# just leaving blank space — the slot grid (no expand flag of its own) ends up pushed flush to the
	# popup's right edge as a result.
	_pad_row = row
	_pad_slot_idx = -1
	var pad_box := _build_fleet_dir_pad()
	pad_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(pad_box)

	content.add_child(VSeparator.new())

	# Right: the 2×5 spawn slots for this row (drop targets + per-slot config) — sized to the narrower cells
	# (see _make_slot_cell()) so it doesn't force extra width the pad panel above could otherwise use.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(370.0, 0.0)
	right.add_theme_constant_override("separation", 6)
	content.add_child(right)
	var right_hdr := HBoxContainer.new()
	right_hdr.add_theme_constant_override("separation", 10)
	right.add_child(right_hdr)
	var slots_hdr_lbl := _mk_label("Spawn slots (2 × 5)", 12)
	slots_hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_hdr.add_child(slots_hdr_lbl)
	# Total HP — same row as "Spawn slots", right-aligned; this is the row's REAL current slot-content
	# total (the row-list's own "Total HP" column is a separate, user-editable Gen-target field — see
	# _add_row()'s hp_spin). Kept live by _update_row_hp() (stashes this Label on row["popup_hp_lbl"]
	# below; every existing call site that refreshes HP — count edits, drag-drop assign/clear, the OK
	# button, Gen — refreshes this one too, no separate wiring).
	var total_hp_hdr_lbl := _mk_label("Total HP " + _fmt_hp(_row_total_hp(row)), 12)
	total_hp_hdr_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	right_hdr.add_child(total_hp_hdr_lbl)
	row["popup_hp_lbl"] = total_hp_hdr_lbl
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(370.0, 500.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	_slots_grid = GridContainer.new()
	_slots_grid.columns = 2
	_slots_grid.add_theme_constant_override("h_separation", 6)
	_slots_grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(_slots_grid)
	_populate_slots_grid(row)

func _build_unit_tab() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(290.0, 500.0)
	scroll.custom_minimum_size = Vector2(290.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for id in _map_enemy_ids():   # scoped to the current map's own roster — see _map_enemy_ids()
		var ids := String(id)
		var b := _DragSrc.new()
		b.custom_minimum_size = Vector2(50.0, 50.0)
		b.tooltip_text = ids + "  (drag → slot)"
		b.payload = {"kind": "unit", "id": ids}
		var tex := _enemy_icon(ids)
		b.ptex = tex
		b.ptext = ids
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tr)
		else:
			b.text = _txt(ids.substr(0, 4))
			if _font: b.add_theme_font_override("font", _font)
		grid.add_child(b)
	return c

## Just the fleet-name list (drag source) — the old per-hover preview panel is gone; the shared direction-pad
## (always visible next to this picker — see _build_fleet_dir_pad()) now covers "what does this fleet look
## like", driven by clicking a SLOT on the right rather than hovering a name here.
func _build_fleet_tab() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(290.0, 500.0)
	scroll.custom_minimum_size = Vector2(290.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	scroll.add_child(vb)
	for fl in _map_fleets():   # scoped to the current map's own roster — see _map_fleets()
		var fld: Dictionary = fl
		var nm := String(fld.get("name", "Fleet"))
		var lbl := _DragSrc.new()
		lbl.text = _txt(nm)
		lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.custom_minimum_size = Vector2(0.0, 24.0)
		lbl.tooltip_text = nm + "  (drag → slot)"
		lbl.payload = {"kind": "fleet", "name": nm}
		lbl.ptext = "[F] " + nm
		if _font: lbl.add_theme_font_override("font", _font)
		vb.add_child(lbl)
	return c

# ── Slot grid (drop targets + per-slot config) ──────────────────────────────────
func _populate_slots_grid(row: Dictionary) -> void:
	if _slots_grid == null or not is_instance_valid(_slots_grid):
		return
	for c in _slots_grid.get_children():
		_slots_grid.remove_child(c)
		c.queue_free()
	for i in SLOTS_PER_ROW:
		_slots_grid.add_child(_make_slot_cell(row, i))

## Drop a dragged Unit/Fleet into slot `idx` of `row`, then rebuild the grid + the row's Blank/Set label.
func _assign_slot(row: Dictionary, idx: int, data: Dictionary) -> void:
	var slots: Array = row["slots"]
	if idx < 0 or idx >= slots.size():
		return
	var slot: Dictionary = slots[idx]
	var kind := String(data.get("kind", ""))
	if kind == "unit":
		slot["type"] = String(data.get("id", ""))
	elif kind == "fleet":
		slot["type"] = "fleet:" + String(data.get("name", ""))
		slot["is_boss"] = false
		slot["count"] = 1   # 1 deployment of the whole formation by default (not the unit-count default of 5)
		slot["angle"] = 0.0
		slot["angle_fixed"] = false   # random spawn direction by default
		slot["fleet_rotate"] = 0.0
	else:
		return
	if idx == _pad_slot_idx:
		_refresh_pad_for_active_slot()   # pad was targeting this slot — reflect the new fleet/reset if now a Unit
	_populate_slots_grid(row)
	_update_type_btn(row)
	_update_row_hp(row)

func _clear_slot(row: Dictionary, idx: int) -> void:
	var slots: Array = row["slots"]
	if idx < 0 or idx >= slots.size():
		return
	slots[idx] = _slot_default()
	if idx == _pad_slot_idx:
		_refresh_pad_for_active_slot()   # pad was targeting this slot — reset to the hint state
	_populate_slots_grid(row)
	_update_type_btn(row)
	_update_row_hp(row)

func _make_slot_cell(row: Dictionary, idx: int) -> Control:
	var cell := _SlotCell.new()
	cell.editor = self
	cell.row = row
	cell.idx = idx
	cell.custom_minimum_size = Vector2(170.0, 152.0)   # +20px for the Boss checkbox row (see _make_slot_cell)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_slot(cell)

	var slot: Dictionary = row["slots"][idx]
	var ty := String(slot.get("type", ""))
	if ty.begins_with("fleet:") and idx == _pad_slot_idx:
		_style_slot_selected(cell)   # highlight the slot the shared direction-pad is currently editing

	var vb := VBoxContainer.new()
	vb.position = Vector2(6.0, 4.0)
	vb.size = Vector2(158.0, 144.0)
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(vb)

	if ty == "":
		var ph := _mk_label("slot %d\n(drag here)" % (idx + 1), 11)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
		vb.add_child(ph)
		return cell

	var is_fleet := ty.begins_with("fleet:")
	# Row 1 — icon / name + clear.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_fleet:
		var tex := _enemy_icon(ty)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(28.0, 28.0)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			head.add_child(tr)
	var nm := _mk_label(("[F] " + ty.substr(6)) if is_fleet else ty, 11)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(92.0, 0.0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nm)
	var clr := _mk_button("x", func() -> void: _clear_slot(row, idx))
	clr.custom_minimum_size = Vector2(24.0, 0.0)
	head.add_child(clr)
	vb.add_child(head)

	if is_fleet:
		# Fleets use their authored formation for POSITIONS (not user-editable here), but — like Unit slots —
		# how many TIMES that whole formation deploys is: "n" (count), defaulting to 1 (see _assign_slot()).
		var fleet_name := ty.substr(6)
		var one_fleet_hp := _fleet_total_hp(fleet_name)
		var fcfg := HBoxContainer.new()
		fcfg.add_theme_constant_override("separation", 4)
		fcfg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fcfg.add_child(_mk_label("n", 10))
		var fcsb := _mk_spin(1.0, 1000.0, 1.0, float(slot.get("count", 1)), 40)
		fcfg.add_child(fcsb)
		var fleet_hp_lbl := _mk_label("HP " + _fmt_hp(one_fleet_hp * float(slot.get("count", 1))), 9)
		fleet_hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		fcsb.value_changed.connect(func(v: float) -> void:
			slot["count"] = int(v)
			fleet_hp_lbl.text = _txt("HP " + _fmt_hp(one_fleet_hp * v))
			_update_row_hp(row))
		fcfg.add_child(fleet_hp_lbl)
		vb.add_child(fcfg)

		# Spawn Angle (8-direction pad) + Fleet Rotate (slider) are edited in the ONE shared direction-pad
		# panel above the slot grid (see _build_fleet_dir_pad()/_select_fleet_pad_slot()), not per-slot here
		# — click this cell (its background, not the n/HP/x controls) to make the pad operate on it.
		var hint := _mk_label("(click to edit dir/rotate)" if idx != _pad_slot_idx else "★ editing dir/rotate", 8)
		hint.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6) if idx == _pad_slot_idx else Color(0.45, 0.5, 0.58))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hint)
		return cell

	# Unit config: Count + Pattern.
	var cfg := HBoxContainer.new()
	cfg.add_theme_constant_override("separation", 4)
	cfg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cfg.add_child(_mk_label("n", 10))
	var csb := _mk_spin(1.0, 100000.0, 1.0, float(slot.get("count", 1)), 48)   # 200-unit cap removed
	# Per-slot HP readout (exact, no K/M — see _fmt_hp()): base hp × blob (a blob-type def like "swarm"
	# actually spawns `blob` creeps per position at runtime, see _row_total_hp()'s comment) × count, kept
	# live via the count SpinBox's own callback below — no full-grid rebuild needed just to refresh a number.
	var hp_per_unit := 0.0
	if _director != null:
		var hd: Dictionary = _director.ENEMY_DEFS.get(ty, {})
		hp_per_unit = float(hd.get("hp", 0.0)) * float(maxi(1, int(hd.get("blob", 1))))
	var slot_hp_lbl := _mk_label("HP " + _fmt_hp(hp_per_unit * float(slot.get("count", 1))), 9)
	slot_hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	csb.value_changed.connect(func(v: float) -> void:
		slot["count"] = int(v)
		slot_hp_lbl.text = _txt("HP " + _fmt_hp(hp_per_unit * v))
		_update_row_hp(row))
	cfg.add_child(csb)
	cfg.add_child(slot_hp_lbl)
	vb.add_child(cfg)

	# Pattern gets its own row (was crammed onto the n/HP row) — doesn't fit next to them anymore at the
	# narrower 158px cell content width.
	var pat_row := HBoxContainer.new()
	pat_row.add_theme_constant_override("separation", 4)
	pat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pat_row.add_child(_mk_label("pat", 10))
	var pob := OptionButton.new()
	pob.custom_minimum_size = Vector2(110.0, 0.0)
	if _font: pob.add_theme_font_override("font", _font)
	var patterns: Array = _director.PATTERNS
	for i in patterns.size():
		pob.add_item(String(patterns[i]), i)
	var pi := patterns.find(String(slot.get("pattern", "ring")))
	pob.selected = pi if pi >= 0 else 0
	pob.item_selected.connect(func(i: int) -> void:
		slot["pattern"] = String(patterns[i])
		_populate_slots_grid(row))   # re-draw so the Dur field appears/disappears for "stream"
	pat_row.add_child(pob)
	vb.add_child(pat_row)

	# Boss toggle — bypasses the alive-cap on spawn. If this slot happens to be the LAST entry (by time) in
	# the WHOLE timeline, arena_wave_director_v2.gd treats it as the run's final-boss finale (_final_boss_entry):
	# waits for the field to clear + locks off reinforcement, then spawns it alone (see BOSS FIGHT debug button).
	var boss_row := HBoxContainer.new()
	boss_row.add_theme_constant_override("separation", 4)
	boss_row.mouse_filter = Control.MOUSE_FILTER_STOP
	var boss_cb := CheckBox.new()
	boss_cb.button_pressed = bool(slot.get("is_boss", false))
	boss_cb.text = _txt("Boss")
	if _font: boss_cb.add_theme_font_override("font", _font)
	boss_cb.add_theme_font_size_override("font_size", 10)
	boss_cb.toggled.connect(func(v: bool) -> void: slot["is_boss"] = v)
	boss_row.add_child(boss_cb)
	vb.add_child(boss_row)

	# Unit config row 2: Dur, only shown for the "stream" pattern.
	if String(slot.get("pattern", "ring")) == "stream":
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 4)
		r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r2.add_child(_mk_label("dur", 10))
		var dsb := _mk_spin(0.0, 120.0, 0.5, float(slot.get("duration", 0.0)), 56)
		dsb.value_changed.connect(func(v: float) -> void: slot["duration"] = v)
		r2.add_child(dsb)
		vb.add_child(r2)
	return cell

## Drag source: a Button/Label that yields its payload dict (and a small preview) when dragged.
class _DragSrc extends Button:
	var payload: Dictionary = {}
	var ptex: Texture2D = null
	var ptext: String = ""
	func _get_drag_data(_at: Vector2) -> Variant:
		# Match the slot-cell icon size (28px). The TextureRect must be ANCHORED full-rect to a fixed-size
		# parent — EXPAND_IGNORE_SIZE renders at native size unless the rect is sized by its parent (same
		# pattern as the Unit grid buttons + slot icons). Setting .size directly does NOT work here.
		const ICON := 28.0
		var prev := Control.new()
		prev.custom_minimum_size = Vector2(ICON, ICON)
		prev.size = Vector2(ICON, ICON)
		if ptex != null:
			var tr := TextureRect.new()
			tr.texture = ptex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			prev.add_child(tr)
		else:
			var l := Label.new()
			l.text = ptext   # _DragSrc is a standalone nested class (no outer-editor ref) — but this drag
			# preview never gets a Mandalore font override applied either, so no transform is needed here;
			# see the outer class's _txt() for the actual rule.
			prev.add_child(l)
		set_drag_preview(prev)
		return payload

## Drop target: one spawn slot. Accepts a Unit/Fleet payload and hands it to the editor.
class _SlotCell extends Panel:
	var editor = null
	var row: Dictionary = {}
	var idx: int = 0
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and String((data as Dictionary).get("kind", "")) in ["unit", "fleet"]
	func _drop_data(_at: Vector2, data: Variant) -> void:
		if editor != null:
			editor._assign_slot(row, idx, data as Dictionary)
	## Click the cell's background (not the n/HP/x child controls, which consume the event themselves) to
	## make the shared Fleet direction-pad operate on this slot — no-op for Unit/empty slots.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and editor != null:
			editor._select_fleet_pad_slot(row, idx)

## Hovered-fleet formation preview: draws each non-empty slot's representative sprite at its placed
## position/size, scaled to fit the box.
class _FleetPreview extends Control:
	var editor = null
	var fleet: Dictionary = {}
	var rot: float = 0.0   # optional formation-shape rotation preview (radians) — mirrors the Fleet Rotate slider
	func set_fleet(f: Dictionary) -> void:
		fleet = f
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.95))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.40, 0.50, 0.6), false, 1.0)
		if fleet.is_empty() or editor == null:
			return
		var slots: Array = fleet.get("slots", [])
		var rects: Array = []
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for s: Dictionary in slots:
			var enemies: Array = s.get("enemies", [])
			if enemies.is_empty():
				continue
			var tex: Texture2D = editor._enemy_icon(String(enemies[0]))
			var w: float = editor.enemy_draw_width(String(enemies[0]))
			var h := w
			if tex != null and tex.get_width() > 0:
				h = w * float(tex.get_height()) / float(tex.get_width())
			var p: Vector2 = s.get("pos", Vector2.ZERO)
			rects.append({"tex": tex, "p": p, "w": w, "h": h})
			mn.x = minf(mn.x, p.x - w * 0.5); mn.y = minf(mn.y, p.y - h * 0.5)
			mx.x = maxf(mx.x, p.x + w * 0.5); mx.y = maxf(mx.y, p.y + h * 0.5)
		if rects.is_empty():
			return
		var span := mx - mn
		var avail := size - Vector2(40.0, 40.0)
		var sc := minf(avail.x / maxf(span.x, 1.0), avail.y / maxf(span.y, 1.0))
		sc = minf(sc, 1.0)
		var center := (mn + mx) * 0.5
		for r: Dictionary in rects:
			var rw: float = float(r["w"]) * sc
			var rh: float = float(r["h"]) * sc
			var p0: Vector2 = r["p"] as Vector2
			var rotp: Vector2 = (center + (p0 - center).rotated(rot)) if not is_zero_approx(rot) else p0
			var rp: Vector2 = (rotp - center) * sc + size * 0.5
			var rect := Rect2(rp - Vector2(rw, rh) * 0.5, Vector2(rw, rh))
			if r["tex"] != null:
				draw_texture_rect(r["tex"] as Texture2D, rect, false)
			else:
				draw_rect(rect, Color(0.4, 0.5, 0.7, 0.6))

# ── Widget helpers ──────────────────────────────────────────────────────────────
## MandaloreText.a() substitutes lowercase "a" for every uppercase "A" — a workaround for the
## Mandalore font's broken uppercase-A glyph (see mandalore_text.gd), only correct for text actually
## RENDERED in that font. This editor's own `_font` is intentionally always null (see its comment
## below) — every label/button here falls back to Godot's default font, which has no such glyph bug —
## so route every text assignment through this instead of calling MandaloreText.a() directly: the
## substitution only fires if `_font` (Mandalore) is ever actually in use, never for the default font.
## 2026-08-17 fix: this file used to call MandaloreText.a() unconditionally everywhere, which silently
## corrupted any "A" in real content shown here even though the default font renders it fine — e.g.
## fleet names in the Fleet-tab picker/drag-preview ("AT.WhalePod.Guard.10" → "aT.WhalePod.Guard.10")
## and the live JSON readout (any "A" in a fleet: entry) were visibly wrong.
func _txt(s: String) -> String:
	return MandaloreText.a(s) if _font else s

func _mk_label(text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = _txt(text)
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _mk_spin(lo: float, hi: float, step: float, val: float, w: int) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = val
	sb.custom_minimum_size = Vector2(float(w), 0)
	if _font:
		sb.add_theme_font_override("font", _font)
	return sb

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = _txt(text)
	if _font:
		b.add_theme_font_override("font", _font)
	b.pressed.connect(cb)
	return b

func _style(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.10, 0.97)
	s.set_border_width_all(2)
	s.border_color = Color(0.4, 0.6, 0.4, 0.95)
	s.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", s)

func _style_slot(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.11, 0.15, 0.95)
	s.set_border_width_all(1)
	s.border_color = Color(0.35, 0.5, 0.65, 0.8)
	s.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", s)

## Highlight the Fleet slot the shared direction-pad is currently editing (see _select_fleet_pad_slot()).
func _style_slot_selected(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.16, 0.12, 0.95)
	s.set_border_width_all(2)
	s.border_color = Color(0.4, 0.95, 0.5, 0.95)
	s.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", s)

# ── Shared Fleet direction-pad (spawn-angle 8-button compass + rotate slider) ────────────────────
const PAD_DIR_FRACS := [
	{"f": Vector2(0.0, 0.0), "deg": 225.0}, {"f": Vector2(0.5, 0.0), "deg": 270.0}, {"f": Vector2(1.0, 0.0), "deg": 315.0},
	{"f": Vector2(0.0, 0.5), "deg": 180.0},                                          {"f": Vector2(1.0, 0.5), "deg": 0.0},
	{"f": Vector2(0.0, 1.0), "deg": 135.0}, {"f": Vector2(0.5, 1.0), "deg": 90.0},   {"f": Vector2(1.0, 1.0), "deg": 45.0},
]

## Builds the ONE shared preview+8-direction-buttons+Rotate-slider panel shown above the slot grid. Each
## button's position on the pad IS the compass direction it fixes (e.g. top-right = spawns from the NE and
## advances toward the player out of there) — click the already-active one again to go back to random.
## The panel always exists; _refresh_pad_for_active_slot() shows a hint until a Fleet slot cell is clicked.
func _build_fleet_dir_pad() -> Control:
	var box := Panel.new()
	_style_slot(box)
	var pad_size := Vector2(320.0, 150.0)
	box.custom_minimum_size = Vector2(360.0, 520.0)

	var hdr := _mk_label("Fleet direction / rotate", 12)
	hdr.position = Vector2(14.0, 10.0)
	box.add_child(hdr)

	var pad := Control.new()
	pad.position = Vector2(14.0, 40.0)
	pad.custom_minimum_size = pad_size
	pad.size = pad_size
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pad)

	_pad_thumb = _FleetPreview.new()
	_pad_thumb.editor = self
	_pad_thumb.position = Vector2.ZERO
	_pad_thumb.size = pad_size
	_pad_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_pad_thumb)

	_pad_hint = _mk_label("Click a Fleet slot on\nthe right to edit its\nspawn direction /\nrotation here.", 11)
	_pad_hint.position = Vector2(14.0, 236.0)
	_pad_hint.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	box.add_child(_pad_hint)

	# Explicit styleboxes: this editor's base theme leaves default Button chrome nearly invisible at 16px
	# against the thumbnail's near-black background, so give the pad's direction buttons their own clearly
	# visible on/off look instead of relying on the (unstyled) engine default.
	var sb_dir_off := StyleBoxFlat.new()
	sb_dir_off.bg_color = Color(0.16, 0.22, 0.30, 0.95)
	sb_dir_off.border_color = Color(0.45, 0.6, 0.75, 0.95)
	sb_dir_off.set_border_width_all(1)
	sb_dir_off.set_corner_radius_all(3)
	var sb_dir_on := StyleBoxFlat.new()
	sb_dir_on.bg_color = Color(0.25, 0.9, 0.4, 0.95)
	sb_dir_on.border_color = Color(0.65, 1.0, 0.75, 1.0)
	sb_dir_on.set_border_width_all(1)
	sb_dir_on.set_corner_radius_all(3)

	_pad_buttons = []
	_pad_dirs = []
	for dd: Dictionary in PAD_DIR_FRACS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(16.0, 16.0)
		b.size = Vector2(16.0, 16.0)
		b.position = pad_size * (dd["f"] as Vector2) - Vector2(8.0, 8.0)
		b.add_theme_stylebox_override("normal", sb_dir_off)
		b.add_theme_stylebox_override("hover", sb_dir_off)
		b.add_theme_stylebox_override("focus", sb_dir_off)
		b.add_theme_stylebox_override("pressed", sb_dir_on)
		b.add_theme_stylebox_override("hover_pressed", sb_dir_on)
		var deg: float = float(dd["deg"])
		b.tooltip_text = "Spawn fixed from %d°" % int(deg)
		pad.add_child(b)
		_pad_buttons.append(b)
		_pad_dirs.append(deg)
	for i in _pad_buttons.size():
		var b: Button = _pad_buttons[i]
		var deg: float = float(_pad_dirs[i])
		b.toggled.connect(func(p: bool) -> void:
			var slot := _pad_active_slot()
			if slot.is_empty():
				return
			if p:
				slot["angle"] = deg
				slot["angle_fixed"] = true
				for ob: Button in _pad_buttons:
					if ob != b:
						ob.button_pressed = false
			else:
				slot["angle_fixed"] = false)

	var rot_row := HBoxContainer.new()
	rot_row.position = Vector2(14.0, 202.0)
	rot_row.size = Vector2(pad_size.x, 20.0)
	rot_row.add_theme_constant_override("separation", 4)
	box.add_child(rot_row)
	rot_row.add_child(_mk_label("Rot", 10))
	_pad_slider = HSlider.new()
	_pad_slider.min_value = 0.0
	_pad_slider.max_value = 359.0
	_pad_slider.step = 1.0
	_pad_slider.custom_minimum_size = Vector2(pad_size.x - 30.0, 0.0)
	_pad_slider.value_changed.connect(func(v: float) -> void:
		var slot := _pad_active_slot()
		if slot.is_empty():
			return
		slot["fleet_rotate"] = v
		(_pad_thumb as _FleetPreview).rot = deg_to_rad(v)
		_pad_thumb.queue_redraw())
	rot_row.add_child(_pad_slider)

	_refresh_pad_for_active_slot()
	return box

## The slot dict the pad currently targets, or {} if nothing selected / the selection is stale (slot got
## cleared/reassigned to a Unit since being picked).
func _pad_active_slot() -> Dictionary:
	if _pad_slot_idx < 0 or _pad_row.is_empty():
		return {}
	var slots: Array = _pad_row.get("slots", [])
	if _pad_slot_idx >= slots.size():
		return {}
	var s: Dictionary = slots[_pad_slot_idx]
	if not String(s.get("type", "")).begins_with("fleet:"):
		return {}
	return s

## Click target for _SlotCell — makes the shared direction-pad operate on slot `idx` of `row`. No-op for
## Unit/empty slots (only Fleet slots have a spawn-direction/rotate concept).
func _select_fleet_pad_slot(row: Dictionary, idx: int) -> void:
	var slots: Array = row.get("slots", [])
	if idx < 0 or idx >= slots.size():
		return
	if not String((slots[idx] as Dictionary).get("type", "")).begins_with("fleet:"):
		return
	_pad_row = row
	_pad_slot_idx = idx
	_refresh_pad_for_active_slot()
	_populate_slots_grid(row)   # redraw so the newly-selected cell gets its highlight border

## Sync the pad's thumbnail/8 buttons/slider to whatever _pad_active_slot() currently resolves to.
func _refresh_pad_for_active_slot() -> void:
	if _pad_thumb == null:
		return
	var slot := _pad_active_slot()
	var has := not slot.is_empty()
	_pad_hint.visible = not has
	_pad_thumb.visible = has
	for b: Button in _pad_buttons:
		b.visible = has
	_pad_slider.editable = has
	if not has:
		(_pad_thumb as _FleetPreview).set_fleet({})
		return
	var fleet_name := String(slot["type"]).substr(6)
	for fl in _load_fleets():
		if String((fl as Dictionary).get("name", "")) == fleet_name:
			(_pad_thumb as _FleetPreview).set_fleet(fl)
			break
	var rv := float(slot.get("fleet_rotate", 0.0))
	(_pad_thumb as _FleetPreview).rot = deg_to_rad(rv)
	_pad_thumb.queue_redraw()
	_pad_slider.value = rv
	var cur_deg := float(slot.get("angle", 0.0))
	var cur_fixed := bool(slot.get("angle_fixed", false))
	for i in _pad_buttons.size():
		var b: Button = _pad_buttons[i]
		b.button_pressed = cur_fixed and is_equal_approx(fmod(cur_deg + 360.0, 360.0), float(_pad_dirs[i]))
