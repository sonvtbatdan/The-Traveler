extends CanvasLayer

## Level-design dev tool (Phase 1-2) — edits the "current level recipe", shows it live, and saves/loads
## a library of recipes to res://levels/*.json. DEV/DEBUG ONLY (just for the designer). Toggle with F7
## (F6 is taken by gun_system's in-gameplay drag mode). Phase 3 adds Test Play + difficulty preview +
## per-type weights. Function over polish — ugly is fine.

const LevelRecipeScript := preload("res://scripts/gameplay/level_recipe.gd")
const WaveDirectorScript := preload("res://scripts/gameplay/wave_director.gd")   # for the difficulty preview + Test Play
const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const LEVELS_DIR := "res://levels"

var _recipe                       # LevelRecipe (untyped to avoid a cross-file class_name dependency)
var _font: FontFile
var _panel: Panel
var _form: VBoxContainer
var _readout: TextEdit
var _file_opt: OptionButton
var _status: Label
var _preview: Label

func _ready() -> void:
	layer = 90
	_font = load(FONT_PATH) as FontFile
	_recipe = LevelRecipeScript.new()
	_panel = Panel.new()
	_panel.position = Vector2(16, 20)
	_panel.size = Vector2(440, 748)
	_style(_panel)
	add_child(_panel)
	_form = VBoxContainer.new()
	_form.position = Vector2(10, 10)
	_form.size = Vector2(420, 728)
	_form.add_theme_constant_override("separation", 5)
	_panel.add_child(_form)
	_build_form()
	_panel.visible = false   # start hidden; F7 toggles

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F7:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()

# ── Build / rebuild the form from the current recipe ──────────────────────────
func _build_form() -> void:
	for c in _form.get_children():
		c.queue_free()

	_form.add_child(_title("LEVEL DESIGN  —  F7 (dev)"))

	var tp_row := HBoxContainer.new()
	tp_row.add_theme_constant_override("separation", 8)
	var tp_btn := _btn("▶ Test Play")
	tp_btn.pressed.connect(_on_testplay_pressed)
	tp_row.add_child(tp_btn)
	var stop_btn := _btn("■ Stop")
	stop_btn.pressed.connect(_on_stop_pressed)
	tp_row.add_child(stop_btn)
	_form.add_child(tp_row)

	var name_edit := LineEdit.new()
	name_edit.text = String(_recipe.name)
	_apply_font(name_edit, 12)
	name_edit.text_changed.connect(_on_name_changed)
	_form.add_child(_row("Name", name_edit))

	var floor_sb := _spin(0.0, 50.0, 0.5, float(_recipe.difficulty_floor))
	floor_sb.value_changed.connect(_on_floor_changed)
	_form.add_child(_row("Difficulty floor", floor_sb))

	var ceil_sb := _spin(0.0, 50.0, 0.5, float(_recipe.difficulty_ceiling))
	ceil_sb.value_changed.connect(_on_ceiling_changed)
	_form.add_child(_row("Difficulty ceiling", ceil_sb))

	var len_sb := _spin(1.0, 200.0, 1.0, float(_recipe.length_waves))
	len_sb.value_changed.connect(_on_length_changed)
	_form.add_child(_row("Length (waves)", len_sb))

	var boss_opt := OptionButton.new()
	for b: String in LevelRecipeScript.BOSSES:
		boss_opt.add_item(b)
	boss_opt.selected = maxi(0, (LevelRecipeScript.BOSSES as Array).find(String(_recipe.boss)))
	boss_opt.item_selected.connect(_on_boss_selected)
	_form.add_child(_row("Boss", boss_opt))

	_preview = _label("")
	_preview.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(420, 0)
	_form.add_child(_preview)

	_form.add_child(_label("Enemy pool  (check = allowed · number = spawn weight):"))
	for t: String in LevelRecipeScript.ENEMY_TYPES:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var c := CheckBox.new()
		c.text = t
		c.button_pressed = (_recipe.enemy_pool as Array).has(t)
		c.custom_minimum_size = Vector2(195, 0)
		_apply_font(c, 12)
		c.toggled.connect(_on_pool_toggled.bind(t))
		hb.add_child(c)
		var wsb := _spin(0.0, 10.0, 0.5, float((_recipe.weights as Dictionary).get(t, 1.0)))
		wsb.custom_minimum_size = Vector2(90, 0)
		wsb.value_changed.connect(_on_weight_changed.bind(t))
		hb.add_child(wsb)
		_form.add_child(hb)

	_form.add_child(_label("Entry edges:"))
	var edge_box := HBoxContainer.new()
	for e: String in LevelRecipeScript.EDGES:
		var c := CheckBox.new()
		c.text = e
		c.button_pressed = (_recipe.entry_edges as Array).has(e)
		_apply_font(c, 12)
		c.toggled.connect(_on_edge_toggled.bind(e))
		edge_box.add_child(c)
	_form.add_child(edge_box)

	# ── Save / load library ───────────────────────────────────────────────────
	_form.add_child(HSeparator.new())
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	var save_btn := _btn("Save to library")
	save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(save_btn)
	_status = _label("")
	_status.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	save_row.add_child(_status)
	_form.add_child(save_row)

	_form.add_child(_label("Saved recipes (res://levels/):"))
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	_file_opt = OptionButton.new()
	_file_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(_file_opt, 11)
	load_row.add_child(_file_opt)
	var load_btn := _btn("Load")
	load_btn.pressed.connect(_on_load_pressed)
	load_row.add_child(load_btn)
	var refresh_btn := _btn("Refresh")
	refresh_btn.pressed.connect(_refresh_file_list)
	load_row.add_child(refresh_btn)
	_form.add_child(load_row)

	_form.add_child(_label("Current recipe (live):"))
	_readout = TextEdit.new()
	_readout.editable = false
	_readout.custom_minimum_size = Vector2(420, 150)
	_apply_font(_readout, 11)
	_form.add_child(_readout)

	_refresh_file_list()
	_refresh()

# ── Field handlers ──────────────────────────────────────────────────────────────
func _on_name_changed(t: String) -> void:
	_recipe.name = t
	_refresh()

func _on_floor_changed(v: float) -> void:
	_recipe.difficulty_floor = v
	_refresh()

func _on_ceiling_changed(v: float) -> void:
	_recipe.difficulty_ceiling = v
	_refresh()

func _on_length_changed(v: float) -> void:
	_recipe.length_waves = int(v)
	_refresh()

func _on_boss_selected(idx: int) -> void:
	_recipe.boss = String(LevelRecipeScript.BOSSES[idx])
	_refresh()

func _on_pool_toggled(pressed: bool, t: String) -> void:
	var pool: Array = _recipe.enemy_pool
	if pressed:
		if not pool.has(t):
			pool.append(t)
	else:
		pool.erase(t)
	_refresh()

func _on_edge_toggled(pressed: bool, e: String) -> void:
	var edges: Array = _recipe.entry_edges
	if pressed:
		if not edges.has(e):
			edges.append(e)
	else:
		edges.erase(e)
	_refresh()

func _on_weight_changed(v: float, t: String) -> void:
	(_recipe.weights as Dictionary)[t] = v
	_refresh()

func _on_testplay_pressed() -> void:
	var dir := get_tree().get_first_node_in_group("wave_director")
	if dir != null and dir.has_method("start"):
		dir.start(_recipe.to_dict())
		_panel.visible = false   # hide so you can play; press F7 to reopen
	else:
		_set_status("No wave director found")

func _on_stop_pressed() -> void:
	var dir := get_tree().get_first_node_in_group("wave_director")
	if dir != null and dir.has_method("stop"):
		dir.stop()
		_set_status("Stopped")

## Project the recipe's numbers using the director's exact (static) difficulty math.
func _difficulty_preview() -> String:
	var floor_d := float(_recipe.difficulty_floor)
	var ceil_d := float(_recipe.difficulty_ceiling)
	var length := maxi(1, int(_recipe.length_waves))
	var pool_size := (_recipe.enemy_pool as Array).size()
	var start_spawns := WaveDirectorScript.max_spawns(floor_d)
	var peak_spawns := WaveDirectorScript.max_spawns(ceil_d)
	var min_int := WaveDirectorScript.spawn_interval(ceil_d)
	var peak_types := WaveDirectorScript.active_types(ceil_d, pool_size)
	var est := 0.0
	for w in length:
		var d := ceil_d if length <= 1 else lerpf(floor_d, ceil_d, float(w) / float(length - 1))
		est += minf(float(WaveDirectorScript.max_spawns(d)) * WaveDirectorScript.spawn_interval(d) + 3.0, WaveDirectorScript.WAVE_MAX_TIME)
	return "PREVIEW: %d→%d spawns/wave · min interval %.2fs · %d waves · types at peak %d/%d · est ~%.1f min · boss: %s" % [
		start_spawns, peak_spawns, min_int, length, peak_types, pool_size, est / 60.0, String(_recipe.boss)]

func _refresh() -> void:
	if _readout != null:
		_readout.text = JSON.stringify(_recipe.to_dict(), "  ")
	if _preview != null:
		_preview.text = _difficulty_preview()

# ── Save / load ─────────────────────────────────────────────────────────────────
func _on_save_pressed() -> void:
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	var fname := _sanitize(String(_recipe.name)) + ".json"
	var path := LEVELS_DIR + "/" + fname
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("Save FAILED: " + path)
		return
	f.store_string(JSON.stringify(_recipe.to_dict(), "  "))
	f.close()
	_refresh_file_list()
	# Re-select the just-saved file in the dropdown.
	for i in _file_opt.item_count:
		if _file_opt.get_item_text(i) == fname:
			_file_opt.selected = i
			break
	_set_status("Saved " + fname)

func _on_load_pressed() -> void:
	if _file_opt == null or _file_opt.item_count == 0:
		_set_status("No recipe to load")
		return
	var fname := _file_opt.get_item_text(_file_opt.selected)
	var f := FileAccess.open(LEVELS_DIR + "/" + fname, FileAccess.READ)
	if f == null:
		_set_status("Load FAILED: " + fname)
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("Bad JSON: " + fname)
		return
	_recipe.from_dict(parsed)
	_build_form()                       # rebuild controls to reflect the loaded recipe
	_set_status("Loaded " + fname)

func _list_recipes() -> Array:
	var out: Array = []
	var d := DirAccess.open(LEVELS_DIR)
	if d != null:
		d.list_dir_begin()
		var fn := d.get_next()
		while fn != "":
			if not d.current_is_dir() and fn.ends_with(".json"):
				out.append(fn)
			fn = d.get_next()
		d.list_dir_end()
	out.sort()
	return out

func _refresh_file_list() -> void:
	if _file_opt == null:
		return
	var sel := _file_opt.get_item_text(_file_opt.selected) if _file_opt.item_count > 0 else ""
	_file_opt.clear()
	for fn: String in _list_recipes():
		_file_opt.add_item(fn)
	for i in _file_opt.item_count:
		if _file_opt.get_item_text(i) == sel:
			_file_opt.selected = i
			break

func _sanitize(s: String) -> String:
	var r := s.strip_edges()
	if r == "":
		r = "level"
	var out := ""
	for i in r.length():
		var c := r[i]
		if c == " ":
			out += "_"
		elif c.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			out += c
		else:
			out += "_"
	return out

func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t

# ── Widgets ─────────────────────────────────────────────────────────────────────
func _spin(mn: float, mx: float, step: float, val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn
	sb.max_value = mx
	sb.step = step
	sb.value = val
	sb.custom_minimum_size = Vector2(120, 0)
	return sb

func _btn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	_apply_font(b, 12)
	return b

func _row(label_text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label(label_text)
	l.custom_minimum_size = Vector2(150, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	_apply_font(l, 12)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	_apply_font(l, 15)
	l.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	return l

func _apply_font(c: Control, sz: int) -> void:
	if _font != null:
		c.add_theme_font_override("font", _font)
	c.add_theme_font_size_override("font_size", sz)

func _style(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.10, 0.97)
	s.set_border_width_all(2)
	s.border_color = Color(0.4, 0.6, 0.4, 0.95)   # green-ish so it reads as a dev tool
	s.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", s)
