class_name UserTodoList
extends Panel

const SAVE_PATH  := "user://todo.cfg"
const NUM_TASKS  := 4
const PANEL_W    := 460.0
const PANEL_H    := 220.0

var _panel_style: StyleBoxFlat
var _checks:      Array[CheckBox]  = []
var _inputs:      Array[TextEdit]  = []
var _title_lbl:   Label            = null

var _expanded:    bool  = false
var _target_h:    float = PANEL_H

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)
	_apply_style()
	_build_ui()
	_load()
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_panel_input)
	UiPalette.scanlines(self)

func _apply_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color            = UiPalette.SURFACE
	_panel_style.border_width_left   = 1
	_panel_style.border_width_right  = 1
	_panel_style.border_width_top    = 1
	_panel_style.border_width_bottom = 1
	_panel_style.border_color        = UiPalette.WIRE_2
	_panel_style.corner_radius_top_left     = 0
	_panel_style.corner_radius_top_right    = 0
	_panel_style.corner_radius_bottom_left  = 0
	_panel_style.corner_radius_bottom_right = 0
	add_theme_stylebox_override("panel", _panel_style)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   = 14
	root.offset_top    = 10
	root.offset_right  = -14
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ── Title (click to expand/collapse) ──────────────────────────────────────
	_title_lbl = Label.new()
	_title_lbl.text = "▶ To-Do"
	_title_lbl.add_theme_color_override("font_color", UiPalette.AMBER)
	_title_lbl.add_theme_font_size_override("font_size", 15)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title_lbl)

	root.add_child(HSeparator.new())

	# ── Task rows ─────────────────────────────────────────────────────────────
	var chk_border := func() -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color          = UiPalette.SURFACE
		s.border_color      = UiPalette.INK
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.corner_radius_top_left     = 0; s.corner_radius_top_right    = 0
		s.corner_radius_bottom_left  = 0; s.corner_radius_bottom_right = 0
		return s

	var te_style := StyleBoxFlat.new()
	te_style.bg_color          = UiPalette.SURFACE_2
	te_style.border_color      = UiPalette.WIRE_2
	te_style.border_width_left = 1; te_style.border_width_right  = 1
	te_style.border_width_top  = 1; te_style.border_width_bottom = 1
	te_style.corner_radius_top_left     = 0; te_style.corner_radius_top_right    = 0
	te_style.corner_radius_bottom_left  = 0; te_style.corner_radius_bottom_right = 0
	te_style.content_margin_left = 4; te_style.content_margin_right  = 4
	te_style.content_margin_top  = 3; te_style.content_margin_bottom = 3

	var te_focus := StyleBoxFlat.new()
	te_focus.bg_color          = UiPalette.SURFACE_2
	te_focus.border_color      = UiPalette.ACCENT
	te_focus.border_width_left = 1; te_focus.border_width_right  = 1
	te_focus.border_width_top  = 1; te_focus.border_width_bottom = 1
	te_focus.corner_radius_top_left     = 0; te_focus.corner_radius_top_right    = 0
	te_focus.corner_radius_bottom_left  = 0; te_focus.corner_radius_bottom_right = 0
	te_focus.content_margin_left = 4; te_focus.content_margin_right  = 4
	te_focus.content_margin_top  = 3; te_focus.content_margin_bottom = 3

	for i in NUM_TASKS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(row)

		# Checkbox with white border via wrapper Panel
		var wrapper := Panel.new()
		wrapper.custom_minimum_size = Vector2(22, 22)
		wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wrapper.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		wrapper.add_theme_stylebox_override("panel", chk_border.call())
		row.add_child(wrapper)

		var chk := CheckBox.new()
		chk.text = ""
		chk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chk.add_theme_stylebox_override("normal",  StyleBoxEmpty.new())
		chk.add_theme_stylebox_override("hover",   StyleBoxEmpty.new())
		chk.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		chk.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
		chk.toggled.connect(func(_p: bool) -> void: _save())
		wrapper.add_child(chk)
		_checks.append(chk)

		# TextEdit with word wrap
		var inp := TextEdit.new()
		inp.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
		inp.placeholder_text         = "Task %d…" % (i + 1)
		inp.wrap_mode                = TextEdit.LINE_WRAPPING_BOUNDARY
		inp.scroll_fit_content_height = true
		inp.custom_minimum_size      = Vector2(0, 28)
		inp.add_theme_color_override("font_color",             UiPalette.INK)
		inp.add_theme_color_override("font_placeholder_color", UiPalette.FAINT)
		inp.add_theme_stylebox_override("normal",    te_style)
		inp.add_theme_stylebox_override("focus",     te_focus)
		inp.add_theme_stylebox_override("read_only", te_style)
		inp.text_changed.connect(func() -> void: _save())
		row.add_child(inp)
		_inputs.append(inp)

# ── Expand / collapse ─────────────────────────────────────────────────────────

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if get_local_mouse_position().y <= 36.0:
			_set_expanded(not _expanded)
			get_viewport().set_input_as_handled()

func _set_expanded(val: bool) -> void:
	_expanded = val
	z_index   = 5 if val else 0
	_target_h = _calc_expanded_h() if val else PANEL_H
	_title_lbl.text = "▼ To-Do" if val else "▶ To-Do"

func _calc_expanded_h() -> float:
	var p := get_parent()
	if p and p.size.y > 1.0:
		return p.size.y - position.y - 18.0
	return 712.0

func _process(delta: float) -> void:
	if absf(size.y - _target_h) > 0.5:
		var new_h := lerpf(size.y, _target_h, delta * 14.0)
		custom_minimum_size.y = new_h
		size.y = new_h
	elif size.y != _target_h:
		custom_minimum_size.y = _target_h
		size.y = _target_h

# ── Persistence ───────────────────────────────────────────────────────────────

func _save() -> void:
	var cfg := ConfigFile.new()
	for i in NUM_TASKS:
		cfg.set_value("tasks", "check_%d" % i, _checks[i].button_pressed)
		cfg.set_value("tasks", "text_%d"  % i, _inputs[i].text)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for i in NUM_TASKS:
		_checks[i].button_pressed = cfg.get_value("tasks", "check_%d" % i, false)
		_inputs[i].text           = cfg.get_value("tasks", "text_%d"  % i, "")

# ── Public API (used by chatbot integration) ──────────────────────────────────

func add_task(text: String) -> bool:
	for i in NUM_TASKS:
		if _inputs[i].text.is_empty():
			_inputs[i].text = text
			_save()
			return true
	return false

func set_task(index: int, text: String) -> void:
	if index >= 0 and index < NUM_TASKS:
		_inputs[index].text = text
		_save()

func clear_task(index: int) -> void:
	if index >= 0 and index < NUM_TASKS:
		_inputs[index].text = ""
		_checks[index].button_pressed = false
		_save()

func get_tasks() -> Array[String]:
	var result: Array[String] = []
	for i in NUM_TASKS:
		result.append(_inputs[i].text)
	return result
