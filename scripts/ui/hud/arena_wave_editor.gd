extends CanvasLayer
## F7 in-game WAVE EDITOR for the arena. The timeline is authored on a 5-second grid: 360 rows (5s → 1800s).
## Each row is ONE moment in time that can spawn MANY things at once — up to 10 Unit/Fleet "slots" (a 2×5 grid)
## dropped in from the Type popup. Each slot carries its own Count / Pattern / Boss (Fleets ignore count/pattern
## and use their authored formation). Toggle with F7: pauses the game, shows the editable row list, a NAME field,
## a Save/Load library (res://levels/arena/*.json), a live JSON readout, Apply&Restart / Reset / Sort.
##
## The wave_director timeline stays FLAT ({time,type,count,pattern,[duration],[is_boss]}) — this editor expands
## each row's filled slots into one flat entry per slot on Apply/Save, and re-groups flat entries (snapped to the
## 5s grid) back into rows on open. So old saved files + DEFAULT_TIMELINE keep working unchanged.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const LEVELS_DIR := "res://levels/arena"
## Per-map "last-Loaded wave file" pointer — MUST match arena_wave_director_v2.gd's copy of this logic
## (that script is the reader; this one is the writer, via _remember_last_wave below).
func _last_wave_cfg_path() -> String:
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	if map_id != "default" and map_id != "":
		return "res://spawn_mode_2_wave_%s.cfg" % map_id
	return "res://spawn_mode_2_wave.cfg"
const TEST_WAVES := 20   # how many repeating time points a Quick-test builds (each spawns COUNT enemies)
const GRID_STEP := 5.0   # seconds between template rows
const GRID_ROWS := 360   # 5, 10, … , 1800
const SLOTS_PER_ROW := 10 # 2×5 spawn slots per row

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
	_name_edit.text = fname.get_basename()
	for i in _file_opt.item_count:
		if _file_opt.get_item_text(i) == fname:
			_file_opt.selected = i
			return

func _process(_delta: float) -> void:
	if _open and _director != null and _director.has_method("elapsed"):
		_title.text = "ARENA WAVE EDITOR   (F7 to close)    —    t = %.1fs" % _director.elapsed()

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
	_name_edit.text = "my_timeline"
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
	# Time + Type(Blank/Set) + Total HP + delete.
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	for h: Array in [["Time(s)", 90], ["Type (Blank / Set)", 220], ["Total HP", 130], ["", 36]]:
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
				}
				break
		_update_type_btn(row)
		_update_row_hp(row)

## Find the template row whose time matches `t` snapped to the nearest 5s grid point (clamped 5…1800).
func _grid_row_for_time(t: float) -> Dictionary:
	var snapped := clampf(round(t / GRID_STEP) * GRID_STEP, GRID_STEP, GRID_STEP * float(GRID_ROWS))
	for r: Dictionary in _rows:
		if absf((r["time"] as SpinBox).value - snapped) < 0.01:
			return r
	return {}

func _add_row(time: float, preset_slots: Array = []) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var time_sb := _mk_spin(0.0, 3600.0, 1.0, time, 90)
	hb.add_child(time_sb)

	# Type — a fixed-width button showing Blank / Set; opens the picker + 2×5 slot popup.
	var type_btn := Button.new()
	type_btn.custom_minimum_size = Vector2(220, 0)
	type_btn.clip_text = true
	if _font: type_btn.add_theme_font_override("font", _font)
	hb.add_child(type_btn)

	# Total HP — sum of (base hp × count) across this row's filled, non-fleet slots. See _row_total_hp().
	var hp_lbl := _mk_label("HP 0", 12)
	hp_lbl.custom_minimum_size = Vector2(130, 0)
	hb.add_child(hp_lbl)

	var clr := Button.new()
	clr.text = "X"
	clr.tooltip_text = "Clear this row's units/fleets (back to Blank)"
	clr.custom_minimum_size = Vector2(36, 0)
	if _font: clr.add_theme_font_override("font", _font)
	hb.add_child(clr)

	_rows_box.add_child(hb)
	var slots: Array = []
	for i in SLOTS_PER_ROW:
		slots.append(preset_slots[i] if i < preset_slots.size() else _slot_default())
	var row := {"hbox": hb, "time": time_sb, "type_btn": type_btn, "hp_lbl": hp_lbl, "slots": slots}
	type_btn.pressed.connect(func() -> void: _open_type_dropdown(row))
	clr.pressed.connect(func() -> void: _clear_row(row))
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
## Uses the RAW def "hp" — NOT the runtime-applied ENEMY_HP_TUNE (×2) or any "lvl"/Beacon/Champion
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

## Total HP of fleet `fleet_name`: hp × blob summed over EVERY unit listed in EVERY slot's "enemies" array
## (per explicit correction — the fleet's HP is the sum of all its units, full stop). Note this counts every
## entry in a multi-option slot (e.g. Kingdom1's ["sentinel2","sentinel1"] slot) even though
## arena_wave_director.gd's _deploy_fleet() only rolls ONE of them at actual deploy time — this is an
## authored/planning total ("everything in the fleet"), not a probability-weighted runtime estimate.
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
			total += float(d.get("hp", 0.0)) * float(maxi(1, int(d.get("blob", 1))))
	return total

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

func _update_row_hp(row: Dictionary) -> void:
	var txt := _fmt_hp(_row_total_hp(row))
	(row["hp_lbl"] as Label).text = "HP " + txt
	# Also refresh the Type popup's own "Total HP" header, if it's currently open for this row.
	var popup_lbl: Variant = row.get("popup_hp_lbl")
	if popup_lbl != null and is_instance_valid(popup_lbl):
		(popup_lbl as Label).text = "Total HP " + txt

## Type button label: "Set (N)" when any slot is filled (N = filled count), else "Blank".
func _update_type_btn(row: Dictionary) -> void:
	var n := 0
	for s: Dictionary in row["slots"]:
		if String(s.get("type", "")) != "":
			n += 1
	var btn := row["type_btn"] as Button
	btn.text = ("Set (%d)" % n) if n > 0 else "Blank"
	btn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35) if n > 0 else Color(1.0, 1.0, 1.0))

## Expand every row's filled slots into FLAT timeline entries (one entry per slot, all sharing the row's time).
func _collect() -> Array:
	var entries: Array = []
	for r: Dictionary in _rows:
		var t: float = (r["time"] as SpinBox).value
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
	_rows.sort_custom(func(a, b): return (a["time"] as SpinBox).value < (b["time"] as SpinBox).value)
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
	_name_edit.text = "test_" + t   # so Save names it sensibly in the library
	_rebuild_rows()
	_refresh_readout()
	_set_status("Built %d waves × %d %s, every %.1fs" % [TEST_WAVES, per_wave, t, iv])

# ── Save / Load library (JSON in res://levels/arena/) ───────────────────────────
func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	var fname := _sanitize(_name_edit.text) + ".json"
	var f := FileAccess.open(LEVELS_DIR + "/" + fname, FileAccess.WRITE)
	if f == null:
		_set_status("Save FAILED")
		return
	f.store_string(JSON.stringify({"name": _name_edit.text, "timeline": _collect()}, "  "))
	f.close()
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
	_name_edit.text = String((parsed as Dictionary).get("name", fname.get_basename()))
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
		_readout.text = JSON.stringify(_director.get_timeline(), "  ")

func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t

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
	picker.custom_minimum_size = Vector2(600.0, 520.0)
	content.add_child(picker)
	var unit_panel := _build_unit_tab()
	var fleet_panel := _build_fleet_tab()
	picker.add_child(unit_panel)
	picker.add_child(fleet_panel)
	fleet_panel.visible = false
	unit_tab.pressed.connect(func() -> void: unit_panel.visible = true;  fleet_panel.visible = false)
	fleet_tab.pressed.connect(func() -> void: unit_panel.visible = false; fleet_panel.visible = true)

	content.add_child(VSeparator.new())

	# Right: the 2×5 spawn slots for this row (drop targets + per-slot config).
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(540.0, 0.0)
	right.add_theme_constant_override("separation", 6)
	content.add_child(right)
	var right_hdr := HBoxContainer.new()
	right_hdr.add_theme_constant_override("separation", 10)
	right.add_child(right_hdr)
	var slots_hdr_lbl := _mk_label("Spawn slots (2 × 5)", 12)
	slots_hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_hdr.add_child(slots_hdr_lbl)
	# Total HP — same row as "Spawn slots", right-aligned. Kept live by _update_row_hp() (stashes this Label
	# on row["popup_hp_lbl"] below; every existing call site that refreshes the table's Total HP column
	# — count edits, drag-drop assign/clear, the OK button — refreshes this one too, no separate wiring).
	var total_hp_hdr_lbl := _mk_label("Total HP " + _fmt_hp(_row_total_hp(row)), 12)
	total_hp_hdr_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	right_hdr.add_child(total_hp_hdr_lbl)
	row["popup_hp_lbl"] = total_hp_hdr_lbl
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(540.0, 500.0)
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
	scroll.size = Vector2(580.0, 500.0)   # widened to use the picker's full 600px (was 290 — left a wide empty gap before the VSeparator)
	scroll.custom_minimum_size = Vector2(580.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 10   # was 5 — more columns to actually fill the widened scroll area instead of just leaving blank space
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for id in _types:
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
			b.text = ids.substr(0, 4)
			if _font: b.add_theme_font_override("font", _font)
		grid.add_child(b)
	return c

func _build_fleet_tab() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var preview := _FleetPreview.new()
	preview.editor = self
	preview.position = Vector2(218.0, 0.0)
	preview.size = Vector2(380.0, 500.0)
	preview.custom_minimum_size = Vector2(380.0, 500.0)
	c.add_child(preview)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(206.0, 500.0)
	scroll.custom_minimum_size = Vector2(206.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	scroll.add_child(vb)
	for fl in _load_fleets():
		var fld: Dictionary = fl
		var nm := String(fld.get("name", "Fleet"))
		var lbl := _DragSrc.new()
		lbl.text = nm
		lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.custom_minimum_size = Vector2(0.0, 24.0)
		lbl.tooltip_text = nm + "  (drag → slot)"
		lbl.payload = {"kind": "fleet", "name": nm}
		lbl.ptext = "[F] " + nm
		if _font: lbl.add_theme_font_override("font", _font)
		lbl.mouse_entered.connect(func() -> void: preview.set_fleet(fld))
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
	else:
		return
	_populate_slots_grid(row)
	_update_type_btn(row)
	_update_row_hp(row)

func _clear_slot(row: Dictionary, idx: int) -> void:
	var slots: Array = row["slots"]
	if idx < 0 or idx >= slots.size():
		return
	slots[idx] = _slot_default()
	_populate_slots_grid(row)
	_update_type_btn(row)
	_update_row_hp(row)

func _make_slot_cell(row: Dictionary, idx: int) -> Control:
	var cell := _SlotCell.new()
	cell.editor = self
	cell.row = row
	cell.idx = idx
	cell.custom_minimum_size = Vector2(252.0, 104.0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_slot(cell)

	var slot: Dictionary = row["slots"][idx]
	var ty := String(slot.get("type", ""))

	var vb := VBoxContainer.new()
	vb.position = Vector2(6.0, 4.0)
	vb.size = Vector2(240.0, 96.0)
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
	nm.custom_minimum_size = Vector2(160.0, 0.0)
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
		var fcsb := _mk_spin(1.0, 1000.0, 1.0, float(slot.get("count", 1)), 56)
		fcfg.add_child(fcsb)
		var fleet_hp_lbl := _mk_label("HP " + _fmt_hp(one_fleet_hp * float(slot.get("count", 1))), 9)
		fleet_hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		fcsb.value_changed.connect(func(v: float) -> void:
			slot["count"] = int(v)
			fleet_hp_lbl.text = "HP " + _fmt_hp(one_fleet_hp * v)
			_update_row_hp(row))
		fcfg.add_child(fleet_hp_lbl)
		vb.add_child(fcfg)

		var fb := HBoxContainer.new()
		fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fb.add_child(_mk_label("Boss", 10))
		var bcb := CheckButton.new()
		bcb.button_pressed = bool(slot.get("is_boss", false))
		bcb.toggled.connect(func(p: bool) -> void: slot["is_boss"] = p)
		fb.add_child(bcb)
		vb.add_child(fb)
		return cell

	# Unit config: Count + Pattern.
	var cfg := HBoxContainer.new()
	cfg.add_theme_constant_override("separation", 4)
	cfg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cfg.add_child(_mk_label("n", 10))
	var csb := _mk_spin(1.0, 100000.0, 1.0, float(slot.get("count", 1)), 56)   # 200-unit cap removed
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
		slot_hp_lbl.text = "HP " + _fmt_hp(hp_per_unit * v)
		_update_row_hp(row))
	cfg.add_child(csb)
	cfg.add_child(slot_hp_lbl)
	var pob := OptionButton.new()
	pob.custom_minimum_size = Vector2(78.0, 0.0)   # shrunk from 92 to make room for the per-slot HP readout
	if _font: pob.add_theme_font_override("font", _font)
	var patterns: Array = _director.PATTERNS
	for i in patterns.size():
		pob.add_item(String(patterns[i]), i)
	var pi := patterns.find(String(slot.get("pattern", "ring")))
	pob.selected = pi if pi >= 0 else 0
	pob.item_selected.connect(func(i: int) -> void:
		slot["pattern"] = String(patterns[i])
		_populate_slots_grid(row))   # re-draw so the Dur field appears/disappears for "stream"
	cfg.add_child(pob)
	vb.add_child(cfg)

	# Unit config row 2: Boss + (Dur only for the "stream" pattern).
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 4)
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r2.add_child(_mk_label("Boss", 10))
	var bcb2 := CheckButton.new()
	bcb2.button_pressed = bool(slot.get("is_boss", false))
	bcb2.toggled.connect(func(p: bool) -> void: slot["is_boss"] = p)
	r2.add_child(bcb2)
	if String(slot.get("pattern", "ring")) == "stream":
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
			l.text = ptext
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

## Hovered-fleet formation preview: draws each non-empty slot's representative sprite at its placed
## position/size, scaled to fit the box.
class _FleetPreview extends Control:
	var editor = null
	var fleet: Dictionary = {}
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
			var w: float = float(s.get("size", 50.0))
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
			var rp: Vector2 = (r["p"] as Vector2 - center) * sc + size * 0.5
			var rect := Rect2(rp - Vector2(rw, rh) * 0.5, Vector2(rw, rh))
			if r["tex"] != null:
				draw_texture_rect(r["tex"] as Texture2D, rect, false)
			else:
				draw_rect(rect, Color(0.4, 0.5, 0.7, 0.6))

# ── Widget helpers ──────────────────────────────────────────────────────────────
func _mk_label(text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = text
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
	b.text = text
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
