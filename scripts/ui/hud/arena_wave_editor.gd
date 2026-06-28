extends CanvasLayer
## F7 in-game WAVE EDITOR for the arena — modelled on the legacy level-design dev tool, but driving the
## arena's time-keyed timeline (add wave → set time, type, count, pattern, duration, boss). Toggle with F7:
## pauses the game, shows the editable wave list, a NAME field, a Save/Load library (res://levels/arena/*.json),
## a live JSON readout, and Apply&Restart / Reset. Reads/writes the live wave_director via its editor API.

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const LEVELS_DIR := "res://levels/arena"
const TEST_WAVES := 20   # how many repeating time points a Quick-test builds (each spawns COUNT enemies)

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
var _font: FontFile = null
var _dropdown: Control = null          # the open Type 2-tab dropdown (Unit / Fleet)
var _dropdown_row: Dictionary = {}     # the row whose type is being picked
var _icon_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("wave_editor")   # the dev:on Wave_edit button toggles us via this group
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT_PATH) as FontFile
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
	get_tree().paused = _open
	if _open:
		if _director == null or not is_instance_valid(_director):
			_director = get_tree().get_first_node_in_group("wave_director")
		_rebuild_rows()
		_refresh_files()
		_refresh_readout()

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
	lib.add_child(_mk_button("Load", _on_load))
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

	# Column header.
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	for h: Array in [["Time(s)", 90], ["Type", 130], ["Count", 80], ["Pattern", 110], ["Dur(s)", 80], ["Boss", 50], ["", 36]]:
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
	btns.add_child(_mk_button("Apply & Restart", _on_apply))
	btns.add_child(_mk_button("Reset to Default", _on_reset))
	btns.add_child(_mk_button("Close", _toggle))

	_readout = TextEdit.new()
	_readout.editable = false
	_readout.custom_minimum_size = Vector2(956, 96)
	if _font: _readout.add_theme_font_override("font", _font)
	_readout.add_theme_font_size_override("font_size", 10)
	vb.add_child(_readout)

func _rebuild_rows() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	_rows.clear()
	if _director == null:
		return
	for entry: Dictionary in _director.get_timeline():
		_add_row(entry)

func _add_row(entry: Dictionary) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var time_sb := _mk_spin(0.0, 3600.0, 1.0, float(entry.get("time", 0.0)), 90)
	hb.add_child(time_sb)

	# Type — a fixed-width button (clips long names so columns stay aligned) that opens the 2-tab dropdown.
	var type_val := String(entry.get("type", "fly"))
	var type_btn := Button.new()
	type_btn.custom_minimum_size = Vector2(130, 0)
	type_btn.clip_text = true
	type_btn.text = _type_label(type_val)
	if _font: type_btn.add_theme_font_override("font", _font)
	hb.add_child(type_btn)

	var count_sb := _mk_spin(1.0, 200.0, 1.0, float(int(entry.get("count", 1))), 80)
	hb.add_child(count_sb)

	var pat_ob := OptionButton.new()
	pat_ob.custom_minimum_size = Vector2(110, 0)
	if _font: pat_ob.add_theme_font_override("font", _font)
	var patterns: Array = _director.PATTERNS
	for i in patterns.size():
		pat_ob.add_item(String(patterns[i]), i)
	var pi := patterns.find(String(entry.get("pattern", "ring")))
	pat_ob.selected = pi if pi >= 0 else 0
	hb.add_child(pat_ob)

	var dur_sb := _mk_spin(0.0, 120.0, 0.5, float(entry.get("duration", 0.0)), 80)
	hb.add_child(dur_sb)

	var boss_cb := CheckButton.new()
	boss_cb.button_pressed = bool(entry.get("is_boss", false))
	boss_cb.custom_minimum_size = Vector2(50, 0)
	hb.add_child(boss_cb)

	var del := _mk_button("X", func(): _remove_row(hb))
	del.custom_minimum_size = Vector2(36, 0)
	hb.add_child(del)

	_rows_box.add_child(hb)
	var row := {"hbox": hb, "time": time_sb, "type_btn": type_btn, "type_value": type_val,
		"count": count_sb, "pattern": pat_ob, "dur": dur_sb, "boss": boss_cb}
	type_btn.pressed.connect(func() -> void: _open_type_dropdown(row, type_btn))
	_rows.append(row)

func _remove_row(hb: HBoxContainer) -> void:
	for i in range(_rows.size() - 1, -1, -1):
		if _rows[i]["hbox"] == hb:
			_rows.remove_at(i)
	hb.queue_free()

## Collect the current rows into a timeline entries array.
func _collect() -> Array:
	var entries: Array = []
	var patterns: Array = _director.PATTERNS
	for r: Dictionary in _rows:
		var pat: String = String(patterns[(r["pattern"] as OptionButton).selected])
		var e := {
			"time": (r["time"] as SpinBox).value,
			"type": String(r["type_value"]),
			"count": int((r["count"] as SpinBox).value),
			"pattern": pat,
		}
		if pat == "stream":
			e["duration"] = (r["dur"] as SpinBox).value
		if (r["boss"] as CheckButton).button_pressed:
			e["is_boss"] = true
		entries.append(e)
	return entries

# ── Actions ───────────────────────────────────────────────────────────────────
func _on_add() -> void:
	_add_row({"time": _director.elapsed() if _director.has_method("elapsed") else 0.0,
		"type": _types[0] if not _types.is_empty() else "fly", "count": 5, "pattern": "ring"})

func _on_apply() -> void:
	if _director != null:
		_director.set_timeline(_collect())
	_rebuild_rows()
	_refresh_readout()

func _on_reset() -> void:
	if _director != null:
		_director.set_timeline((_director.DEFAULT_TIMELINE as Array).duplicate(true))
	_rebuild_rows()
	_refresh_readout()

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
	_rebuild_rows()
	_refresh_readout()
	_set_status("Loaded " + fname)

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

# ── Widget helpers ──────────────────────────────────────────────────────────────
# ── Type dropdown (2 tabs: Unit grid + Fleet list with formation preview) ───────
func _type_label(v: String) -> String:
	return ("[F] " + v.substr(6)) if v.begins_with("fleet:") else v

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

func _pick_type(v: String) -> void:
	if not _dropdown_row.is_empty():
		_dropdown_row["type_value"] = v
		(_dropdown_row["type_btn"] as Button).text = _type_label(v)
	_close_dropdown()

func _close_dropdown() -> void:
	if _dropdown != null and is_instance_valid(_dropdown):
		_dropdown.queue_free()
	_dropdown = null
	_dropdown_row = {}

func _open_type_dropdown(row: Dictionary, btn: Button) -> void:
	_close_dropdown()
	_dropdown_row = row
	# Full-rect catcher: a click anywhere outside the panel closes the dropdown.
	_dropdown = Control.new()
	_dropdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_dropdown())
	_root.add_child(_dropdown)

	var panel := Panel.new()
	_style(panel)
	var psize := Vector2(760.0, 560.0)
	var vpz := get_viewport().get_visible_rect().size
	var pos := btn.global_position + Vector2(0.0, btn.size.y)
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
	var unit_tab := _mk_button("Unit", func() -> void: pass)
	var fleet_tab := _mk_button("Fleet", func() -> void: pass)
	unit_tab.custom_minimum_size = Vector2(120.0, 0.0)
	fleet_tab.custom_minimum_size = Vector2(120.0, 0.0)
	tabs.add_child(unit_tab)
	tabs.add_child(fleet_tab)

	var content := Control.new()
	content.custom_minimum_size = Vector2(0.0, 500.0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(content)
	var unit_panel := _build_unit_tab()
	var fleet_panel := _build_fleet_tab()
	content.add_child(unit_panel)
	content.add_child(fleet_panel)
	fleet_panel.visible = false
	unit_tab.pressed.connect(func() -> void: unit_panel.visible = true;  fleet_panel.visible = false)
	fleet_tab.pressed.connect(func() -> void: unit_panel.visible = false; fleet_panel.visible = true)

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
	for id in _types:
		var ids := String(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(50.0, 50.0)
		b.tooltip_text = ids
		var tex := _enemy_icon(ids)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tr)
		b.pressed.connect(func() -> void: _pick_type(ids))
		grid.add_child(b)
	return c

func _build_fleet_tab() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var preview := _FleetPreview.new()
	preview.editor = self
	preview.position = Vector2(228.0, 0.0)
	preview.size = Vector2(500.0, 500.0)
	preview.custom_minimum_size = Vector2(500.0, 500.0)
	c.add_child(preview)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(210.0, 500.0)
	scroll.custom_minimum_size = Vector2(210.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	scroll.add_child(vb)
	for fl in _load_fleets():
		var fld: Dictionary = fl
		var nm := String(fld.get("name", "Fleet"))
		var lbl := Button.new()
		lbl.text = nm
		lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.custom_minimum_size = Vector2(0.0, 24.0)
		if _font: lbl.add_theme_font_override("font", _font)
		lbl.mouse_entered.connect(func() -> void: preview.set_fleet(fld))
		lbl.pressed.connect(func() -> void: _pick_type("fleet:" + nm))
		vb.add_child(lbl)
	return c

## Hovered-fleet formation preview: draws each non-empty slot's representative sprite at its placed
## position/size, scaled to fit the 500px box.
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
