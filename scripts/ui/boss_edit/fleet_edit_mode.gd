extends CanvasLayer
## Fleet Edit (dev:on) — define named FLEETS of units for later spawn/backup wiring.
##
## A fleet has SLOT_COUNT unit slots. Each slot holds either one enemy or a RANDOM POOL (up to SLOT_COUNT
## enemies → shown as "R"; one is rolled when the fleet deploys). Each slot has a screen POSITION + SIZE
## (per-slot: the random alternatives share the slot's transform). Enemies are dragged from the right-hand
## palette into Unit / Random slots; a static placeholder for each slot is shown on screen and can be dragged
## to position it. Editor-only: Save writes res://fleet_layout.cfg (consuming fleets in-game is a later task).

const WaveDir   := preload("res://scripts/gameplay/arena_wave_director.gd")
const CFG_PATH  := "res://fleet_layout.cfg"
const SLOT_COUNT := 10          # unit slots per fleet / random pool max
const UNIT_COLS  := 5
const ENEMY_COLS := 5
const ENEMY_ROWS := 5
const CELL       := 50.0        # slot square px
const PANEL_W    := 250.0
const FONT_PATH  := "res://assets/fonts/Gameplay.ttf"
const ZOOM_MIN   := 0.4
const ZOOM_MAX   := 5.0
const ZOOM_RATIO := 1.15        # per wheel notch

var _oc: Control = null
var _open: bool = false
var _prev_paused: bool = false

# Canvas view transform (screen = world * _zoom + _pan). Placeholders are drawn manually, so zoom
# is applied in _draw_canvas / _slot_at / drag rather than by scaling a node (cf. Creep Edit).
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO

# ── Data ──────────────────────────────────────────────────────────────────────
# _fleets: [ { "name": String, "slots": [ { "enemies": [id,...], "pos": Vector2, "size": float } x SLOT_COUNT ] } ]
var _fleets: Array = []
var _active_fleet: int = -1     # LMB-selected fleet (drives Unit table + on-screen)
var _active_unit: int = -1      # selected Unit slot (0..SLOT_COUNT-1) or -1 (drives Random table)
var _active_rand: int = -1      # selected Random alternative or -1
var _sel_slots: Array = []      # slot indices selected for drag / transform
var _clip_fleet: Dictionary = {}

# ── UI ────────────────────────────────────────────────────────────────────────
var _root: Control = null
var _canvas: Control = null               # full-rect placeholder layer (behind the panels)
var _fleet_vbox: VBoxContainer = null
var _unit_grid: GridContainer = null
var _rand_grid: GridContainer = null
var _enemy_grid: GridContainer = null
var _w_spin: SpinBox = null
var _x_spin: SpinBox = null
var _y_spin: SpinBox = null
var _rot_spin: SpinBox = null
var _ctx_menu: PopupMenu = null
var _ctx_fleet: int = -1
var _font: Font = null
var _preview: Control = null              # 500×500 formation preview shown while hovering a FLEET row

# on-screen drag
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO

var _enemy_ids: Array = []
var _icon_cache: Dictionary = {}

func setup(oc: Control) -> void:
	_oc = oc

func _ready() -> void:
	add_to_group("fleet_edit")
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT_PATH) as Font
	visible = false
	# _collect_enemy_ids()/_load_cfg()/_build_ui() moved to _ensure_built(), lazily run on first toggle()
	# instead of here — _build_ui() → _build_enemy_palette() loads a thumbnail for every non-boss enemy
	# (100+ textures) even though this editor is dev-only and starts hidden; that cost was previously
	# masked because _setup_creep_edit() (fixed the same way) happened to warm the same sprite files first.

func is_open() -> bool:
	return _open

var _lazy_built := false
func _ensure_built() -> void:
	if _lazy_built:
		return
	_lazy_built = true
	_collect_enemy_ids()
	_load_cfg()
	_build_ui()

func toggle() -> void:
	_ensure_built()
	if _open:
		_close()
	else:
		_open_panel()

func _open_panel() -> void:
	_open = true
	visible = true
	_zoom = 1.0
	_pan = Vector2.ZERO
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_arena_focus(true)
	_rebuild_fleet_list()
	_rebuild_unit_table()
	_rebuild_rand_table()
	_refresh_transform()
	queue_redraw_canvas()

func _close() -> void:
	_open = false
	visible = false
	_arena_focus(false)
	get_tree().paused = _prev_paused

## Hide the arena HUD + gameplay while the editor is open (only the panels + edit placeholders show).
func _arena_focus(on: bool) -> void:
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("set_edit_focus"):
		arena.set_edit_focus(on)

## Arrow keys ALWAYS nudge the selected slot(s) (Shift = ×10) — even while a transform field is
## focused (they never reach the SpinBox). Delete clears the selection, but only when NOT editing text.
func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var ke := event as InputEventKey
	# Arrow keys: move selected object, regardless of focus.
	var dir := Vector2.ZERO
	match ke.keycode:
		KEY_UP:    dir = Vector2(0.0, -1.0)
		KEY_DOWN:  dir = Vector2(0.0,  1.0)
		KEY_LEFT:  dir = Vector2(-1.0, 0.0)
		KEY_RIGHT: dir = Vector2(1.0,  0.0)
	if dir != Vector2.ZERO:
		if _sel_slots.is_empty():
			return
		if ke.shift_pressed:
			dir *= 10.0
		var slots := _active_slots()
		for si in _sel_slots:
			if si >= 0 and si < slots.size():
				slots[si]["pos"] = (slots[si]["pos"] as Vector2) + dir
		_refresh_transform()
		queue_redraw_canvas()
		get_viewport().set_input_as_handled()
		return
	# Delete key → clear the selected Random alternative, else the selected Unit slot(s). Works even
	# while a transform field is focused: only swallow the key if something was actually deleted,
	# otherwise let the focused LineEdit handle Delete for text editing.
	if ke.keycode == KEY_DELETE:
		if _delete_selected_slot():
			get_viewport().set_input_as_handled()
		return

# ── Enemy palette source ───────────────────────────────────────────────────────
func _collect_enemy_ids() -> void:
	_enemy_ids.clear()
	for id: String in WaveDir.ENEMY_DEFS.keys():
		var d: Dictionary = WaveDir.ENEMY_DEFS[id]
		if String(d.get("behavior", "")) == "boss_stub":
			continue   # fleets are made of normal units, not bosses
		_enemy_ids.append(id)

func _enemy_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	var d: Dictionary = WaveDir.ENEMY_DEFS.get(id, {})
	var path := String(d.get("icon", ""))
	if path != "":
		tex = load(path) as Texture2D
	_icon_cache[id] = tex
	return tex

# ── UI construction ────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# On-screen placeholder canvas (full rect, behind the panels).
	_canvas = _Canvas.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.owner_editor = self
	_root.add_child(_canvas)

	_build_left_panel()
	_build_right_panel()

	# Hover preview (added last → drawn above the panels). Sits just right of the widened left panel.
	_preview = _FleetPreview.new()
	_preview.editor = self
	_preview.position = Vector2(8.0 + PANEL_W + 50.0 + 12.0, 44.0)
	_preview.size = Vector2(500.0, 500.0)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_root.add_child(_preview)

	_ctx_menu = PopupMenu.new()
	_ctx_menu.add_item("Rename", 0)
	_ctx_menu.add_item("Copy", 1)
	_ctx_menu.add_item("Paste", 2)
	_ctx_menu.add_item("Delete", 3)
	_ctx_menu.id_pressed.connect(_on_ctx_id)
	add_child(_ctx_menu)

func _mk_panel(x: float, width: float = PANEL_W) -> VBoxContainer:
	var panel := Panel.new()
	panel.position = Vector2(x, 44.0)
	panel.custom_minimum_size = Vector2(width, 0.0)
	panel.size = Vector2(width, 760.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 6; vb.offset_top = 6; vb.offset_right = -6; vb.offset_bottom = -6
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)
	return vb

func _hdr(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.55, 0.90, 1.0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _font: lbl.add_theme_font_override("font", _font)
	row.add_child(lbl)
	return row

func _build_left_panel() -> void:
	var vb := _mk_panel(8.0, PANEL_W + 50.0)   # background extended 50px to the right

	# FLEET table
	var fh := _hdr(vb, "FLEET")
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(26.0, 22.0)
	add_btn.pressed.connect(_on_add_fleet)
	fh.add_child(add_btn)
	var fscroll := ScrollContainer.new()
	fscroll.custom_minimum_size = Vector2(0.0, 260.0)   # show ~10 fleet rows (24px + 2px sep) before scrolling
	fscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(fscroll)
	_fleet_vbox = VBoxContainer.new()
	_fleet_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_vbox.add_theme_constant_override("separation", 2)
	fscroll.add_child(_fleet_vbox)

	vb.add_child(HSeparator.new())

	# UNIT table (2 rows × 5)
	_hdr(vb, "UNIT")
	_unit_grid = GridContainer.new()
	_unit_grid.columns = UNIT_COLS
	_unit_grid.add_theme_constant_override("h_separation", 4)
	_unit_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_unit_grid)

	vb.add_child(HSeparator.new())

	# RANDOM table (2 rows × 5)
	_hdr(vb, "RANDOM")
	_rand_grid = GridContainer.new()
	_rand_grid.columns = UNIT_COLS
	_rand_grid.add_theme_constant_override("h_separation", 4)
	_rand_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_rand_grid)

func _build_right_panel() -> void:
	var vp_w := get_viewport().get_visible_rect().size.x
	var vb := _mk_panel(vp_w - PANEL_W - 28.0)   # 8px margin + 20px shifted left

	# ENEMIES palette (5×5, scrollable)
	_hdr(vb, "ENEMIES")
	var escroll := ScrollContainer.new()
	escroll.custom_minimum_size = Vector2(0.0, ENEMY_ROWS * (CELL + 4.0))
	escroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(escroll)
	_enemy_grid = GridContainer.new()
	_enemy_grid.columns = ENEMY_COLS
	_enemy_grid.add_theme_constant_override("h_separation", 4)
	_enemy_grid.add_theme_constant_override("v_separation", 4)
	escroll.add_child(_enemy_grid)
	_build_enemy_palette()

	vb.add_child(HSeparator.new())

	# TRANSFORM
	_hdr(vb, "TRANSFORM")
	_w_spin = _mk_tspin(vb, "W", 4.0, 400.0, 1.0, _on_w_changed)
	_x_spin = _mk_tspin(vb, "X", -4000.0, 4000.0, 1.0, _on_xy_changed)
	_y_spin = _mk_tspin(vb, "Y", -4000.0, 4000.0, 1.0, _on_xy_changed)
	_rot_spin = _mk_tspin(vb, "Rot", -180.0, 180.0, 1.0, _on_rot_changed)
	_rot_spin.suffix = "°"

	vb.add_child(HSeparator.new())

	# SAVE
	_hdr(vb, "SAVE")
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	vb.add_child(srow)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save)
	srow.add_child(save_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(_close)
	srow.add_child(close_btn)

func _mk_tspin(parent: Control, label: String, mn: float, mx: float, step: float, cb: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(18.0, 0.0)
	row.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(_v: float) -> void: cb.call())
	row.add_child(sb)
	return sb

func _build_enemy_palette() -> void:
	for c in _enemy_grid.get_children():
		c.queue_free()
	for id: String in _enemy_ids:
		var cell := _PaletteCell.new()
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.owner_editor = self
		cell.enemy_id = id
		cell.tooltip_text = id
		cell.set_icon(_enemy_icon(id))
		_enemy_grid.add_child(cell)

# ── Fleet table ────────────────────────────────────────────────────────────────
func _on_add_fleet() -> void:
	var slots: Array = []
	for i in SLOT_COUNT:
		slots.append({"enemies": [], "pos": Vector2(400.0 + float(i) * 70.0, 300.0), "size": 50.0, "rot": 0.0})
	_fleets.append({"name": "New Fleet", "slots": slots})
	_active_fleet = _fleets.size() - 1
	_active_unit = -1
	_active_rand = -1
	_sel_slots = []
	_rebuild_fleet_list()
	_rebuild_unit_table()
	_rebuild_rand_table()
	queue_redraw_canvas()
	# Let the player rename immediately.
	_begin_rename(_active_fleet)

func _rebuild_fleet_list() -> void:
	if _fleet_vbox == null:
		return
	for c in _fleet_vbox.get_children():
		c.queue_free()
	for fi in _fleets.size():
		var fl: Dictionary = _fleets[fi]
		var lbl := _FleetLabel.new()
		lbl.owner_editor = self
		lbl.fleet_index = fi
		lbl.text = String(fl.get("name", "Fleet"))
		lbl.custom_minimum_size = Vector2(0.0, 24.0)
		lbl.set_active(fi == _active_fleet)
		_fleet_vbox.add_child(lbl)

## Hover a FLEET row → show its formation in the 500×500 preview (mirrors the Wave Editor preview).
func _show_fleet_preview(fi: int) -> void:
	if _preview == null or fi < 0 or fi >= _fleets.size():
		return
	_preview.set_fleet(_fleets[fi])
	_preview.visible = true

func _hide_fleet_preview() -> void:
	if _preview != null:
		_preview.visible = false

func _select_fleet(fi: int) -> void:
	_active_fleet = fi
	_active_unit = -1
	_active_rand = -1
	# Fleet select → all non-empty slots selected.
	_sel_slots = []
	if fi >= 0 and fi < _fleets.size():
		var slots: Array = _fleets[fi]["slots"]
		for si in slots.size():
			if not (slots[si]["enemies"] as Array).is_empty():
				_sel_slots.append(si)
	_rebuild_fleet_list()
	_rebuild_unit_table()
	_rebuild_rand_table()
	_refresh_transform()
	queue_redraw_canvas()

func _begin_rename(fi: int) -> void:
	if fi < 0 or fi >= _fleets.size():
		return
	# Inline rename via a LineEdit dialog.
	var dlg := AcceptDialog.new()
	dlg.title = "Fleet name"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	var le := LineEdit.new()
	le.text = String(_fleets[fi].get("name", "New Fleet"))
	le.custom_minimum_size = Vector2(220.0, 0.0)
	dlg.add_child(le)
	dlg.register_text_enter(le)
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		var nm := le.text.strip_edges()
		_fleets[fi]["name"] = nm if nm != "" else "New Fleet"
		_rebuild_fleet_list()
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()
	le.grab_focus()
	le.select_all()

func show_fleet_context(fi: int, screen_pos: Vector2) -> void:
	_ctx_fleet = fi
	_ctx_menu.set_item_disabled(2, _clip_fleet.is_empty())   # Paste disabled if nothing copied
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()

func _on_ctx_id(id: int) -> void:
	var fi := _ctx_fleet
	if fi < 0 or fi >= _fleets.size():
		return
	match id:
		0: _begin_rename(fi)
		1: _clip_fleet = _dup_fleet(_fleets[fi])
		2:
			if not _clip_fleet.is_empty():
				var nf := _dup_fleet(_clip_fleet)
				nf["name"] = String(nf.get("name", "Fleet")) + " copy"
				_fleets.append(nf)
				_select_fleet(_fleets.size() - 1)
		3:
			_fleets.remove_at(fi)
			_active_fleet = clampi(_active_fleet, -1, _fleets.size() - 1)
			if _active_fleet >= _fleets.size(): _active_fleet = _fleets.size() - 1
			_active_unit = -1; _active_rand = -1; _sel_slots = []
			_rebuild_fleet_list(); _rebuild_unit_table(); _rebuild_rand_table(); queue_redraw_canvas()

func _dup_fleet(fl: Dictionary) -> Dictionary:
	var slots: Array = []
	for s: Dictionary in fl["slots"]:
		slots.append({"enemies": (s["enemies"] as Array).duplicate(), "pos": s["pos"], "size": s["size"], "rot": s.get("rot", 0.0)})
	return {"name": String(fl.get("name", "Fleet")), "slots": slots}

# ── Unit table ─────────────────────────────────────────────────────────────────
func _active_slots() -> Array:
	if _active_fleet < 0 or _active_fleet >= _fleets.size():
		return []
	return _fleets[_active_fleet]["slots"]

func _rebuild_unit_table() -> void:
	if _unit_grid == null:
		return
	for c in _unit_grid.get_children():
		c.queue_free()
	var slots := _active_slots()
	for si in SLOT_COUNT:
		var cell := _SlotCell.new()
		cell.owner_editor = self
		cell.slot_index = si
		cell.is_random_table = false
		cell.custom_minimum_size = Vector2(CELL, CELL)
		if si < slots.size():
			var enemies: Array = slots[si]["enemies"]
			if enemies.size() >= 2:
				cell.set_text("R")
			elif enemies.size() == 1:
				cell.set_icon(_enemy_icon(String(enemies[0])))
		cell.set_selected(si in _sel_slots)
		_unit_grid.add_child(cell)

func _rebuild_rand_table() -> void:
	if _rand_grid == null:
		return
	for c in _rand_grid.get_children():
		c.queue_free()
	var slots := _active_slots()
	var pool: Array = []
	if _active_unit >= 0 and _active_unit < slots.size():
		pool = slots[_active_unit]["enemies"]
	for ri in SLOT_COUNT:
		var cell := _SlotCell.new()
		cell.owner_editor = self
		cell.slot_index = ri
		cell.is_random_table = true
		cell.custom_minimum_size = Vector2(CELL, CELL)
		if ri < pool.size():
			cell.set_icon(_enemy_icon(String(pool[ri])))
		cell.set_selected(ri == _active_rand)
		_rand_grid.add_child(cell)

## Called by a palette drag dropping `enemy_id` onto a slot in the Unit (is_random=false) or Random table.
func drop_enemy(enemy_id: String, slot_index: int, is_random: bool) -> void:
	var slots := _active_slots()
	if slots.is_empty():
		return
	if is_random:
		# Build/replace the active Unit slot's random pool, 1 enemy per random slot.
		if _active_unit < 0 or _active_unit >= slots.size():
			return
		var pool: Array = slots[_active_unit]["enemies"]
		while pool.size() <= slot_index:
			pool.append("")
		pool[slot_index] = enemy_id
		# strip trailing empties
		while not pool.is_empty() and String(pool[-1]) == "":
			pool.remove_at(pool.size() - 1)
		slots[_active_unit]["enemies"] = pool
	else:
		if slot_index >= slots.size():
			return
		var enemies: Array = slots[slot_index]["enemies"]
		if enemies.size() >= SLOT_COUNT:
			return
		# Dragging onto a slot ADDS the enemy (1 → single, 2+ → random pool "R").
		enemies.append(enemy_id)
		slots[slot_index]["enemies"] = enemies
		_active_unit = slot_index
		_active_rand = -1
		_sel_slots = [slot_index]
	_rebuild_unit_table()
	_rebuild_rand_table()
	_refresh_transform()
	queue_redraw_canvas()

## LMB on a Unit slot → select the slot. Shift+LMB on the Unit table → add/remove from a multi-selection.
## On a Random slot → select that one unit (no multi-select).
func click_slot(slot_index: int, is_random: bool, additive: bool = false) -> void:
	var slots := _active_slots()
	if is_random:
		if _active_unit < 0 or _active_unit >= slots.size():
			return
		_active_rand = slot_index
		_sel_slots = [_active_unit]          # transform/drag is per-slot
	else:
		if slot_index >= slots.size():
			return
		_active_unit = slot_index
		_active_rand = -1
		if additive:
			if slot_index in _sel_slots:
				_sel_slots.erase(slot_index)   # Shift toggles this slot off
			else:
				_sel_slots.append(slot_index)
		else:
			_sel_slots = [slot_index]
	_rebuild_unit_table()
	_rebuild_rand_table()
	_refresh_transform()
	queue_redraw_canvas()

## Delete key handler. If a Random alternative is selected, remove just that one from the active
## Unit's pool; otherwise clear the selected Unit slot(s). Returns true if anything was deleted.
func _delete_selected_slot() -> bool:
	var slots := _active_slots()
	if slots.is_empty():
		return false
	if _active_rand >= 0 and _active_unit >= 0 and _active_unit < slots.size():
		var pool: Array = slots[_active_unit]["enemies"]
		if _active_rand < pool.size():
			pool.remove_at(_active_rand)
			slots[_active_unit]["enemies"] = pool
		_active_rand = -1
	elif not _sel_slots.is_empty():
		for si in _sel_slots:
			if si >= 0 and si < slots.size():
				slots[si]["enemies"] = []
		_active_rand = -1
	else:
		return false
	_rebuild_unit_table()
	_rebuild_rand_table()
	_refresh_transform()
	queue_redraw_canvas()
	return true

# ── Transform ──────────────────────────────────────────────────────────────────
func _refresh_transform() -> void:
	if _w_spin == null:
		return
	var single := _sel_slots.size() == 1
	for sb: SpinBox in [_w_spin, _x_spin, _y_spin, _rot_spin]:
		sb.editable = single
	if not single:
		return
	var slots := _active_slots()
	var si: int = _sel_slots[0]
	if si < 0 or si >= slots.size():
		return
	var s: Dictionary = slots[si]
	_w_spin.set_value_no_signal(float(s["size"]))
	_x_spin.set_value_no_signal((s["pos"] as Vector2).x)
	_y_spin.set_value_no_signal((s["pos"] as Vector2).y)
	_rot_spin.set_value_no_signal(float(s.get("rot", 0.0)))

func _on_w_changed() -> void:
	var slots := _active_slots()
	if _sel_slots.size() != 1:
		return
	var si: int = _sel_slots[0]
	if si >= 0 and si < slots.size():
		slots[si]["size"] = _w_spin.value
		queue_redraw_canvas()

func _on_xy_changed() -> void:
	var slots := _active_slots()
	if _sel_slots.size() != 1:
		return
	var si: int = _sel_slots[0]
	if si >= 0 and si < slots.size():
		slots[si]["pos"] = Vector2(_x_spin.value, _y_spin.value)
		queue_redraw_canvas()

func _on_rot_changed() -> void:
	var slots := _active_slots()
	if _sel_slots.size() != 1:
		return
	var si: int = _sel_slots[0]
	if si >= 0 and si < slots.size():
		slots[si]["rot"] = _rot_spin.value
		queue_redraw_canvas()

# ── On-screen placeholders + drag ──────────────────────────────────────────────
func queue_redraw_canvas() -> void:
	if _canvas != null:
		_canvas.queue_redraw()

## A representative sprite id for a slot (the highlighted random alternative, else the first).
func _slot_repr(si: int) -> String:
	var slots := _active_slots()
	if si < 0 or si >= slots.size():
		return ""
	var enemies: Array = slots[si]["enemies"]
	if enemies.is_empty():
		return ""
	if si == _active_unit and _active_rand >= 0 and _active_rand < enemies.size():
		return String(enemies[_active_rand])
	return String(enemies[0])

func _draw_canvas(c: Control) -> void:
	var slots := _active_slots()
	for si in slots.size():
		var id := _slot_repr(si)
		if id == "":
			continue
		var s: Dictionary = slots[si]
		var w: float = float(s["size"]) * _zoom
		var tex := _enemy_icon(id)
		var h := w
		if tex != null and tex.get_width() > 0:
			h = w * float(tex.get_height()) / float(tex.get_width())
		var center: Vector2 = (s["pos"] as Vector2) * _zoom + _pan
		var rot := deg_to_rad(float(s.get("rot", 0.0)))
		# Draw in the slot's rotated frame: origin at its center, rect centered on origin.
		c.draw_set_transform(center, rot, Vector2.ONE)
		var rect := Rect2(-Vector2(w, h) * 0.5, Vector2(w, h))
		if tex != null:
			c.draw_texture_rect(tex, rect, false)
		else:
			c.draw_rect(rect, Color(0.4, 0.5, 0.7, 0.5))
		if si in _sel_slots:
			c.draw_rect(rect, Color(1.0, 0.85, 0.2, 0.9), false, 2.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _canvas_input(c: Control, event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Mouse wheel → zoom toward the cursor (like Creep Edit).
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := ZOOM_RATIO if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_RATIO)
			var old_zoom := _zoom
			_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			_pan = mb.position - (mb.position - _pan) * (_zoom / old_zoom)
			queue_redraw_canvas()
			c.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var si := _slot_at(mb.position)
				if si >= 0:
					# Only SELECTED slots drag; clicking an unselected placeholder selects it first.
					if not (si in _sel_slots):
						_active_unit = si; _active_rand = -1; _sel_slots = [si]
						_rebuild_unit_table(); _rebuild_rand_table(); _refresh_transform()
					_dragging = true
					_drag_last = mb.position
					c.accept_event()
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta := (mm.position - _drag_last) / _zoom   # screen → world
		_drag_last = mm.position
		var slots := _active_slots()
		for si2 in _sel_slots:
			if si2 >= 0 and si2 < slots.size():
				slots[si2]["pos"] = (slots[si2]["pos"] as Vector2) + delta
		_refresh_transform()
		queue_redraw_canvas()

func _slot_at(p: Vector2) -> int:
	var slots := _active_slots()
	# topmost first → iterate reverse
	for i in range(slots.size() - 1, -1, -1):
		var id := _slot_repr(i)
		if id == "":
			continue
		var s: Dictionary = slots[i]
		var w: float = float(s["size"]) * _zoom
		var tex := _enemy_icon(id)
		var h := w
		if tex != null and tex.get_width() > 0:
			h = w * float(tex.get_height()) / float(tex.get_width())
		var center: Vector2 = (s["pos"] as Vector2) * _zoom + _pan
		var rot := deg_to_rad(float(s.get("rot", 0.0)))
		# Test in the slot's local (un-rotated) frame so rotated sprites hit-test correctly.
		var local := (p - center).rotated(-rot)
		if Rect2(-Vector2(w, h) * 0.5, Vector2(w, h)).has_point(local):
			return i
	return -1

# ── Persistence ────────────────────────────────────────────────────────────────
func _on_save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("fleets", "data", _fleets)
	cfg.save(CFG_PATH)

func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	var data = cfg.get_value("fleets", "data", [])
	if data is Array:
		_fleets = data

# ── Inner UI classes ───────────────────────────────────────────────────────────

## One fleet entry in the FLEET list. LMB selects; RMB opens the context menu.
class _FleetLabel extends Label:
	var owner_editor = null
	var fleet_index: int = -1
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_font_size_override("font_size", 12)
		gui_input.connect(_on_input)
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)
	func _on_enter() -> void:
		if owner_editor != null:
			owner_editor._show_fleet_preview(fleet_index)
	func _on_exit() -> void:
		if owner_editor != null:
			owner_editor._hide_fleet_preview()
	func set_active(on: bool) -> void:
		modulate = Color(1.0, 0.9, 0.4) if on else Color(0.85, 0.88, 0.95)
	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				owner_editor._select_fleet(fleet_index)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				owner_editor.show_fleet_context(fleet_index, get_global_mouse_position())

## A 50px slot in the ENEMIES palette — a drag SOURCE carrying its enemy id.
class _PaletteCell extends Panel:
	var owner_editor = null
	var enemy_id: String = ""
	var _tr: TextureRect = null
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.12, 0.16, 0.9)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.3, 0.4, 0.55)
		add_theme_stylebox_override("panel", sb)
	func set_icon(tex: Texture2D) -> void:
		_tr = TextureRect.new()
		_tr.texture = tex
		_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tr.offset_left = 3; _tr.offset_top = 3; _tr.offset_right = -3; _tr.offset_bottom = -3
		_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tr)
	func _get_drag_data(_pos: Vector2) -> Variant:
		var tex: Texture2D = _tr.texture if _tr != null else null
		# Match the in-slot display: keep aspect, fit within (CELL - 6) px.
		var maxd := CELL - 6.0
		var w := maxd
		var h := maxd
		if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			if tw >= th:
				h = maxd * th / tw
			else:
				w = maxd * tw / th
		# Wrap so the preview is CENTERED on the cursor.
		var wrap := Control.new()
		var trp := TextureRect.new()
		trp.texture = tex
		trp.stretch_mode = TextureRect.STRETCH_SCALE
		trp.size = Vector2(w, h)
		trp.position = Vector2(-w * 0.5, -h * 0.5)
		wrap.add_child(trp)
		set_drag_preview(wrap)
		return {"enemy_id": enemy_id}

## A 50px slot in the UNIT / RANDOM tables — a drop TARGET + click handler.
class _SlotCell extends Panel:
	var owner_editor = null
	var slot_index: int = -1
	var is_random_table: bool = false
	var _selected: bool = false
	var _tr: TextureRect = null
	var _lbl: Label = null
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_input)
		_restyle()
	func _restyle() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.10, 0.14, 0.9)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2 if _selected else 1)
		sb.border_color = Color(1.0, 0.85, 0.2) if _selected else Color(0.28, 0.36, 0.5)
		add_theme_stylebox_override("panel", sb)
	func set_selected(on: bool) -> void:
		_selected = on
		_restyle()
	func set_icon(tex: Texture2D) -> void:
		_tr = TextureRect.new()
		_tr.texture = tex
		_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tr.offset_left = 3; _tr.offset_top = 3; _tr.offset_right = -3; _tr.offset_bottom = -3
		_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tr)
	func set_text(t: String) -> void:
		_lbl = Label.new()
		_lbl.text = t
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.add_theme_font_size_override("font_size", 20)
		_lbl.modulate = Color(1.0, 0.7, 0.2)
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lbl)
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("enemy_id")
	func _drop_data(_pos: Vector2, data: Variant) -> void:
		owner_editor.drop_enemy(String((data as Dictionary)["enemy_id"]), slot_index, is_random_table)
	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			owner_editor.click_slot(slot_index, is_random_table, (event as InputEventMouseButton).shift_pressed)

## Full-rect layer that draws + drags the on-screen placeholders (forwards to the editor).
class _Canvas extends Control:
	var owner_editor = null
	func _draw() -> void:
		if owner_editor != null:
			owner_editor._draw_canvas(self)
	func _gui_input(event: InputEvent) -> void:
		if owner_editor != null:
			owner_editor._canvas_input(self, event)

## Hovered-fleet formation preview: draws each non-empty slot's representative sprite at its placed
## position/size, scaled to fit the 500px box. Mirrors arena_wave_editor.gd's _FleetPreview.
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
