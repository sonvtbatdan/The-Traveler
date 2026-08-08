extends CanvasLayer

## Level-design dev tool (Phase 1-2) — edits the "current level recipe", shows it live, and saves/loads
## a library of recipes to res://levels/*.json. DEV/DEBUG ONLY (just for the designer). Toggle with F7
## (F6 is taken by gun_system's in-gameplay drag mode). Phase 3 adds Test Play + difficulty preview +
## per-type weights. Function over polish — ugly is fine.

const LevelRecipeScript := preload("res://scripts/gameplay/level_recipe.gd")
const WaveDirectorScript := preload("res://scripts/gameplay/wave_director.gd")   # for the difficulty preview + Test Play
const ChoreographyRegistry := preload("res://scripts/gameplay/choreography_registry.gd")   # Phase 2 choreography list
const FONT_PATH := "res://assets/fonts/mandalore/mandalore.ttf"
const LEVELS_DIR := "res://levels"

var _recipe                       # LevelRecipe (untyped to avoid a cross-file class_name dependency)
var _font: FontFile
var _panel: Panel
var _form: VBoxContainer
var _readout: TextEdit
var _file_opt: OptionButton
var _status: Label
var _preview: Label
var _choreo_opt: OptionButton      # Phase 2: pick a registered choreography to test-play
var _choreo_waves_sb: SpinBox      # Phase 2: how many waves of it to play
var _help_panel: Panel             # right-side box: every choreography + what it does
var _help_scroll: ScrollContainer  # scroll viewport holding the description rows (for auto-scroll)
var _help_box: VBoxContainer       # holds the per-choreography description rows
var _selected_choreo: String = ""  # the Quick-test pick, highlighted in the help box

func _ready() -> void:
	layer = 90
	_font = load(FONT_PATH) as FontFile
	_recipe = LevelRecipeScript.new()
	_recipe.mode = "choreography"   # F7 opens in choreography mode by default
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

	# Help box to the RIGHT of the main panel: lists every choreography and what it does.
	_help_panel = Panel.new()
	_help_panel.position = Vector2(_panel.position.x + _panel.size.x + 12.0, 20)
	_help_panel.size = Vector2(440, 748)
	_style(_help_panel)
	add_child(_help_panel)
	var help_title := _title("CHOREOGRAPHIES  —  what each does")
	help_title.position = Vector2(10, 8)
	help_title.size = Vector2(420, 22)
	_help_panel.add_child(help_title)
	_help_scroll = ScrollContainer.new()
	_help_scroll.position = Vector2(10, 36)
	_help_scroll.size = Vector2(420, 702)
	_help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_help_panel.add_child(_help_scroll)
	_help_box = VBoxContainer.new()
	_help_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_box.add_theme_constant_override("separation", 6)
	_help_scroll.add_child(_help_box)
	_build_help()

	_panel.visible = false   # start hidden; F7 toggles
	_help_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F7:
		_panel.visible = not _panel.visible
		if _help_panel != null:
			_help_panel.visible = _panel.visible   # the help box shows/hides with the tool
		get_viewport().set_input_as_handled()

## Hide the whole tool (main panel + help box) — used by Test Play / Play so nothing lingers in-game.
func _hide_tool() -> void:
	_panel.visible = false
	if _help_panel != null:
		_help_panel.visible = false

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
	name_edit.text = MandaloreText.a(String(_recipe.name))
	_apply_font(name_edit, 12)
	name_edit.text_changed.connect(_on_name_changed)
	_form.add_child(_row("Name", name_edit))

	# Boss (common to both modes)
	var boss_opt := OptionButton.new()
	for b: String in LevelRecipeScript.BOSSES:
		boss_opt.add_item(b)
	boss_opt.selected = maxi(0, (LevelRecipeScript.BOSSES as Array).find(String(_recipe.boss)))
	boss_opt.item_selected.connect(_on_boss_selected)
	_form.add_child(_row("Boss", boss_opt))

	# Level mode (common): random difficulty-roll (legacy) vs choreography set-pieces (Phase 2/4)
	var mode_opt := OptionButton.new()
	for m: String in ["random", "choreography"]:
		mode_opt.add_item(m)
	mode_opt.selected = 1 if String(_recipe.mode) == "choreography" else 0
	mode_opt.item_selected.connect(_on_mode_selected)
	_form.add_child(_row("Level mode", mode_opt))

	_preview = _label("")
	_preview.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(420, 0)
	_form.add_child(_preview)

	if String(_recipe.mode) == "choreography":
		_build_choreography_section()
	else:
		_build_random_section()

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

# ── Mode sections ─────────────────────────────────────────────────────────────────
## Legacy random difficulty-roll controls (difficulty floor/ceiling/length + enemy pool + edges).
func _build_random_section() -> void:
	var floor_sb := _spin(0.0, 50.0, 0.5, float(_recipe.difficulty_floor))
	floor_sb.value_changed.connect(_on_floor_changed)
	_form.add_child(_row("Difficulty floor", floor_sb))

	var ceil_sb := _spin(0.0, 50.0, 0.5, float(_recipe.difficulty_ceiling))
	ceil_sb.value_changed.connect(_on_ceiling_changed)
	_form.add_child(_row("Difficulty ceiling", ceil_sb))

	var len_sb := _spin(1.0, 200.0, 1.0, float(_recipe.length_waves))
	len_sb.value_changed.connect(_on_length_changed)
	_form.add_child(_row("Length (waves)", len_sb))

	_form.add_child(_label("Enemy pool  (check = allowed · number = spawn weight):"))
	for t: String in LevelRecipeScript.ENEMY_TYPES:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var c := CheckBox.new()
		c.text = MandaloreText.a(t)
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
		c.text = MandaloreText.a(e)
		c.button_pressed = (_recipe.entry_edges as Array).has(e)
		_apply_font(c, 12)
		c.toggled.connect(_on_edge_toggled.bind(e))
		edge_box.add_child(c)
	_form.add_child(edge_box)

## Choreography composition (Phase 4): a sub-mode (fixed list vs random pool) + its editor + a quick test.
func _build_choreography_section() -> void:
	var sub_opt := OptionButton.new()
	for m: String in ["fixed", "pool"]:
		sub_opt.add_item(m)
	sub_opt.selected = 1 if String(_recipe.choreo_mode) == "pool" else 0
	sub_opt.item_selected.connect(_on_choreo_mode_selected)
	_form.add_child(_row("Choreo mode", sub_opt))

	if String(_recipe.choreo_mode) == "pool":
		_build_choreo_pool_editor()
	else:
		_build_choreo_fixed_editor()

	# Quick test (play one choreography N times) — handy without composing a full level.
	_form.add_child(HSeparator.new())
	_form.add_child(_label("Quick test (one choreography):"))
	var choreo_row := HBoxContainer.new()
	choreo_row.add_theme_constant_override("separation", 8)
	_choreo_opt = OptionButton.new()
	_choreo_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(_choreo_opt, 11)
	for nm: String in ChoreographyRegistry.names():
		_choreo_opt.add_item(nm)
	# Reflect (or seed) the current Quick-test pick so the help box highlights the matching entry.
	if _choreo_opt.item_count > 0:
		if _selected_choreo == "":
			_selected_choreo = _choreo_opt.get_item_text(0)
		for i in _choreo_opt.item_count:
			if _choreo_opt.get_item_text(i) == _selected_choreo:
				_choreo_opt.selected = i
				break
	_choreo_opt.item_selected.connect(_on_quicktest_choreo_selected)
	choreo_row.add_child(_choreo_opt)
	_choreo_waves_sb = _spin(1.0, 10.0, 1.0, 2.0)
	_choreo_waves_sb.custom_minimum_size = Vector2(70, 0)
	choreo_row.add_child(_choreo_waves_sb)
	var play_choreo := _btn("▶ Play")
	play_choreo.pressed.connect(_on_play_choreo_pressed)
	choreo_row.add_child(play_choreo)
	_form.add_child(choreo_row)

## Fixed mode: an ordered, editable list of waves (each a choreography dropdown) with +/- buttons.
func _build_choreo_fixed_editor() -> void:
	_form.add_child(_label("Waves (play in this order):"))
	var names: Array = ChoreographyRegistry.names()
	for idx in (_recipe.waves as Array).size():
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var l := _label("Wave %d" % (idx + 1))
		l.custom_minimum_size = Vector2(64, 0)
		hb.add_child(l)
		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_font(opt, 11)
		for nm: String in names:
			opt.add_item(nm)
		opt.selected = maxi(0, names.find(String((_recipe.waves as Array)[idx])))
		opt.item_selected.connect(_on_wave_choreo_selected.bind(idx))
		hb.add_child(opt)
		var rm := _btn("✕")
		rm.pressed.connect(_on_wave_removed.bind(idx))
		hb.add_child(rm)
		_form.add_child(hb)
	var add_btn := _btn("+ Add wave")
	add_btn.pressed.connect(_on_wave_added)
	_form.add_child(add_btn)

## Pool mode: checkboxes for the allowed choreographies + a wave count to roll.
func _build_choreo_pool_editor() -> void:
	_form.add_child(_label("Pool (allowed choreographies — each wave is rolled from these):"))
	for nm: String in ChoreographyRegistry.names():
		var c := CheckBox.new()
		c.text = MandaloreText.a(nm)
		c.button_pressed = (_recipe.choreo_pool as Array).has(nm)
		_apply_font(c, 12)
		c.toggled.connect(_on_choreo_pool_toggled.bind(nm))
		_form.add_child(c)
	var cnt := _spin(1.0, 50.0, 1.0, float(_recipe.choreo_wave_count))
	cnt.value_changed.connect(_on_choreo_wave_count_changed)
	_form.add_child(_row("Wave count", cnt))

# ── Field handlers ──────────────────────────────────────────────────────────────
func _on_mode_selected(idx: int) -> void:
	_recipe.mode = "choreography" if idx == 1 else "random"
	_build_form()

func _on_choreo_mode_selected(idx: int) -> void:
	_recipe.choreo_mode = "pool" if idx == 1 else "fixed"
	_build_form()

func _on_wave_choreo_selected(sel_idx: int, wave_idx: int) -> void:
	var names: Array = ChoreographyRegistry.names()
	if wave_idx < (_recipe.waves as Array).size() and sel_idx < names.size():
		(_recipe.waves as Array)[wave_idx] = String(names[sel_idx])
		_refresh()

func _on_wave_removed(wave_idx: int) -> void:
	if wave_idx < (_recipe.waves as Array).size():
		(_recipe.waves as Array).remove_at(wave_idx)
		_build_form()

func _on_wave_added() -> void:
	var names: Array = ChoreographyRegistry.names()
	(_recipe.waves as Array).append(String(names[0]) if names.size() > 0 else "")
	_build_form()

func _on_choreo_pool_toggled(pressed: bool, nm: String) -> void:
	var pool: Array = _recipe.choreo_pool
	if pressed:
		if not pool.has(nm):
			pool.append(nm)
	else:
		pool.erase(nm)
	_refresh()

func _on_choreo_wave_count_changed(v: float) -> void:
	_recipe.choreo_wave_count = int(v)
	_refresh()


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
		_hide_tool()   # hide panel + help box so you can play; press F7 to reopen
	else:
		_set_status("No wave director found")

func _on_stop_pressed() -> void:
	var dir := get_tree().get_first_node_in_group("wave_director")
	if dir != null and dir.has_method("stop"):
		dir.stop()
		_set_status("Stopped")

## Phase 2: play a choreography-mode level made of `count` copies of the picked choreography, so the
## pipeline + wave-advance is testable now (the full per-wave editor is Phase 4). Uses the current boss.
## Quick-test dropdown changed → remember the pick, re-highlight it, and scroll the help box to it.
func _on_quicktest_choreo_selected(idx: int) -> void:
	if _choreo_opt != null and idx >= 0 and idx < _choreo_opt.item_count:
		_selected_choreo = _choreo_opt.get_item_text(idx)
		_build_help()
		call_deferred("_scroll_to_selected")   # deferred so the rebuilt rows have a resolved layout

## Scroll the help box so the highlighted (selected) choreography entry is in view.
func _scroll_to_selected() -> void:
	if _help_scroll == null or _help_box == null:
		return
	var idx: int = ChoreographyRegistry.names().find(_selected_choreo)
	if idx < 0 or idx >= _help_box.get_child_count():
		return
	var entry := _help_box.get_child(idx) as Control
	if entry != null:
		_help_scroll.scroll_vertical = int(entry.position.y)

# ── Help box: every choreography + what it does (highlights the current Quick-test pick) ──────────
func _build_help() -> void:
	if _help_box == null:
		return
	for c in _help_box.get_children():
		c.queue_free()
	for nm: String in ChoreographyRegistry.names():
		_help_box.add_child(_help_entry(nm, nm == _selected_choreo))

func _help_entry(nm: String, highlighted: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	if highlighted:
		sb.bg_color = Color(0.16, 0.30, 0.20, 0.96)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.5, 0.95, 0.6, 0.95)   # bright green = the selected one
	else:
		sb.bg_color = Color(0.08, 0.11, 0.15, 0.9)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.25, 0.35, 0.5, 0.6)
	pc.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	pc.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	margin.add_child(vb)

	var name_l := Label.new()
	name_l.text = MandaloreText.a(nm)
	_apply_font(name_l, 13)
	name_l.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75) if highlighted else Color(0.7, 0.85, 1.0))
	vb.add_child(name_l)

	var desc_l := Label.new()
	desc_l.text = MandaloreText.a(ChoreographyRegistry.describe(nm))
	_apply_font(desc_l, 11)
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(376, 0)   # bound the width so the text wraps inside the scroll box
	desc_l.add_theme_color_override("font_color", Color(0.80, 0.86, 0.95))
	vb.add_child(desc_l)
	return pc

func _on_play_choreo_pressed() -> void:
	var dir := get_tree().get_first_node_in_group("wave_director")
	if dir == null or not dir.has_method("start"):
		_set_status("No wave director found")
		return
	if _choreo_opt == null or _choreo_opt.item_count == 0:
		_set_status("No choreographies registered")
		return
	var nm := _choreo_opt.get_item_text(_choreo_opt.selected)
	var count := int(_choreo_waves_sb.value)
	var wave_list: Array = []
	for i in count:
		wave_list.append(nm)
	dir.start({
		"name": "Choreo Test",
		"mode": "choreography",
		"waves": wave_list,
		"boss": String(_recipe.boss),
	})
	_hide_tool()   # hide panel + help box so you can play; press F7 to reopen
	_set_status("Playing %d× %s" % [count, nm])

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
		_readout.text = MandaloreText.a(JSON.stringify(_recipe.to_dict(), "  "))
	if _preview != null:
		_preview.text = MandaloreText.a(_choreo_preview() if String(_recipe.mode) == "choreography" else _difficulty_preview())

## One-line summary of a choreography-mode level (shown in place of the difficulty preview).
func _choreo_preview() -> String:
	if String(_recipe.choreo_mode) == "pool":
		return "CHOREOGRAPHY · pool of %d → %d waves rolled · boss: %s" % [
			(_recipe.choreo_pool as Array).size(), int(_recipe.choreo_wave_count), String(_recipe.boss)]
	var ws := PackedStringArray(_recipe.waves as Array)
	return "CHOREOGRAPHY · fixed · %d waves: %s · boss: %s" % [
		ws.size(), ", ".join(ws), String(_recipe.boss)]

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
		_status.text = MandaloreText.a(t)

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
	b.text = MandaloreText.a(t)
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
	l.text = MandaloreText.a(t)
	_apply_font(l, 12)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _title(t: String) -> Label:
	var l := Label.new()
	l.text = MandaloreText.a(t)
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
