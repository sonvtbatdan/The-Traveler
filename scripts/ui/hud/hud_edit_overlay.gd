extends CanvasLayer

## HUD Edit Overlay — toggle with F6.
## Widgets register by: add_to_group("hud_editable"), set_meta("hud_key", "key_name")
## and exposing: get_hud_rect() -> Rect2,  apply_hud_rect(Rect2) -> void

const SAVE_PATH := "user://hud_layout.cfg"
const GRIP_SZ   := 8.0
const MIN_SZ    := Vector2(24.0, 24.0)

# ── Inner struct ──────────────────────────────────────────────────────────────

class HudItem:
	var node:  Node
	var key:   String
	var rect:  Rect2
	var frame: Panel
	var label: Label
	var grips: Array   # 8 Panel nodes [n,s,w,e,nw,ne,sw,se]

# ── State ─────────────────────────────────────────────────────────────────────

var _items:   Array   = []
var _toolbar: Control = null

var _drag_item:        HudItem = null
var _drag_mode:        String  = ""   # "move" | "n" | "s" | "e" | "w" | "nw" | "ne" | "sw" | "se"
var _drag_start_mouse: Vector2
var _drag_start_rect:  Rect2

var _selected_item:  HudItem = null
var _props_panel:    Panel   = null
var _props_name_lbl: Label   = null
var _pe_x: LineEdit          = null
var _pe_y: LineEdit          = null
var _pe_w: LineEdit          = null
var _pe_h: LineEdit          = null

const _DIRS := ["n", "s", "w", "e", "nw", "ne", "sw", "se"]

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer   = 100
	visible = false

func open() -> void:
	_build()
	visible = true

func close() -> void:
	visible = false
	_clear()

# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_clear()

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.30)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	for node: Node in get_tree().get_nodes_in_group("hud_editable"):
		if not node.has_method("get_hud_rect") or not node.has_method("apply_hud_rect"):
			continue
		var item   := HudItem.new()
		item.node  = node
		item.key   = str(node.get_meta("hud_key", node.name))
		item.rect  = node.call("get_hud_rect") as Rect2
		item.frame = _make_frame(item)
		item.grips = _make_grips(item)
		_update_layout(item)
		_items.append(item)

	_toolbar = _make_toolbar()
	add_child(_toolbar)
	_props_panel = _make_props_panel()
	add_child(_props_panel)

func _make_frame(item: HudItem) -> Panel:
	var frame := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.25, 0.55, 1.0, 0.10)
	s.set_border_width_all(2)
	s.border_color = Color(0.45, 0.75, 1.0, 0.95)
	s.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", s)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_MOVE

	item.label = Label.new()
	item.label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	item.label.add_theme_font_size_override("font_size", 10)
	item.label.add_theme_color_override("font_color", Color(0.6, 0.82, 1.0, 0.85))
	item.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(item.label)

	frame.gui_input.connect(func(e: InputEvent) -> void: _on_frame_input(item, e))
	add_child(frame)
	return frame

func _make_grips(item: HudItem) -> Array:
	var grips: Array = []
	for dir: String in _DIRS:
		var g := Panel.new()
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(0.45, 0.75, 1.0, 1.0)
		g.add_theme_stylebox_override("panel", gs)
		g.size         = Vector2(GRIP_SZ, GRIP_SZ)
		g.z_index      = 2
		g.mouse_filter = Control.MOUSE_FILTER_STOP
		g.mouse_default_cursor_shape = _cursor_for(dir)
		g.gui_input.connect(func(e: InputEvent) -> void: _on_grip_input(item, dir, e))
		add_child(g)
		grips.append(g)
	return grips

func _update_layout(item: HudItem) -> void:
	if not is_instance_valid(item.frame):
		return
	item.frame.position = item.rect.position
	item.frame.size     = item.rect.size

	var r  := item.rect
	var hs := GRIP_SZ * 0.5
	var cx := r.position.x + r.size.x * 0.5 - hs
	var cy := r.position.y + r.size.y * 0.5 - hs
	var x0 := r.position.x - hs;   var x1 := r.position.x + r.size.x - hs
	var y0 := r.position.y - hs;   var y1 := r.position.y + r.size.y - hs
	var gpos := [
		Vector2(cx, y0), Vector2(cx, y1),   # n, s
		Vector2(x0, cy), Vector2(x1, cy),   # w, e
		Vector2(x0, y0), Vector2(x1, y0),   # nw, ne
		Vector2(x0, y1), Vector2(x1, y1),   # sw, se
	]
	for i in item.grips.size():
		(item.grips[i] as Control).position = gpos[i]

	if is_instance_valid(item.label):
		item.label.text = "%s\n(%d, %d)  %d × %d" % [
			item.key,
			int(r.position.x), int(r.position.y),
			int(r.size.x), int(r.size.y)
		]
	if item == _selected_item:
		_update_props_display()

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_frame_input(item: HudItem, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select_item(item)
			_drag_item        = item
			_drag_mode        = "move"
			_drag_start_mouse = get_viewport().get_mouse_position()
			_drag_start_rect  = item.rect
			get_viewport().set_input_as_handled()

func _on_grip_input(item: HudItem, dir: String, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_drag_item        = item
			_drag_mode        = dir
			_drag_start_mouse = get_viewport().get_mouse_position()
			_drag_start_rect  = item.rect
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.keycode == KEY_F6 and ke.pressed and not ke.echo:
			if visible:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
			return
	if not visible or _drag_item == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_drag_item = null
			_drag_mode = ""
	elif event is InputEventMouseMotion:
		var delta := get_viewport().get_mouse_position() - _drag_start_mouse
		if _drag_mode == "move":
			_drag_item.rect.position = _drag_start_rect.position + delta
		else:
			_drag_item.rect = _apply_resize(_drag_start_rect, _drag_mode, delta)
		_update_layout(_drag_item)
		get_viewport().set_input_as_handled()

func _apply_resize(orig: Rect2, dir: String, delta: Vector2) -> Rect2:
	var r := orig
	if "n" in dir:
		var new_h := orig.size.y - delta.y
		if new_h >= MIN_SZ.y:
			r.position.y = orig.position.y + delta.y
			r.size.y     = new_h
	if "s" in dir:
		r.size.y = maxf(orig.size.y + delta.y, MIN_SZ.y)
	if "w" in dir:
		var new_w := orig.size.x - delta.x
		if new_w >= MIN_SZ.x:
			r.position.x = orig.position.x + delta.x
			r.size.x     = new_w
	if "e" in dir:
		r.size.x = maxf(orig.size.x + delta.x, MIN_SZ.x)
	return r

func _cursor_for(dir: String) -> Control.CursorShape:
	match dir:
		"n", "s":   return Control.CURSOR_VSIZE
		"e", "w":   return Control.CURSOR_HSIZE
		"nw", "se": return Control.CURSOR_FDIAGSIZE
		"ne", "sw": return Control.CURSOR_BDIAGSIZE
	return Control.CURSOR_ARROW

# ── Toolbar ───────────────────────────────────────────────────────────────────

func _make_toolbar() -> Control:
	var tb := Panel.new()
	tb.size     = Vector2(230.0, 40.0)
	tb.position = Vector2(605.0, 8.0)
	tb.z_index  = 10
	tb.mouse_filter = Control.MOUSE_FILTER_STOP

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.10, 0.16, 0.97)
	s.set_border_width_all(2)
	s.border_color = Color(0.35, 0.55, 0.85, 0.9)
	s.set_corner_radius_all(6)
	tb.add_theme_stylebox_override("panel", s)

	var title := Label.new()
	title.text     = "HUD EDIT  [F6]"
	title.position = Vector2(8.0, 10.0)
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(title)

	var save_btn := _mk_btn("Save", Color(0.12, 0.48, 0.22))
	save_btn.position = Vector2(136.0, 6.0)
	save_btn.size     = Vector2(42.0, 28.0)
	save_btn.pressed.connect(_on_save)
	tb.add_child(save_btn)

	var close_btn := _mk_btn("Close", Color(0.42, 0.12, 0.12))
	close_btn.position = Vector2(182.0, 6.0)
	close_btn.size     = Vector2(42.0, 28.0)
	close_btn.pressed.connect(close)
	tb.add_child(close_btn)

	return tb

func _mk_btn(txt: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color.WHITE)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.15)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sp)
	return b

# ── Save / Load ───────────────────────────────────────────────────────────────

func _on_save() -> void:
	var cfg := ConfigFile.new()
	for item: HudItem in _items:
		if not is_instance_valid(item.node):
			continue
		item.node.call("apply_hud_rect", item.rect)
		cfg.set_value("hud", item.key + "/pos",  item.rect.position)
		cfg.set_value("hud", item.key + "/size", item.rect.size)
	cfg.save(SAVE_PATH)

## Static helper — each widget can call this in its own startup to restore layout.
static func load_rect(key: String) -> Rect2:
	var cfg := ConfigFile.new()
	if cfg.load("user://hud_layout.cfg") != OK:
		return Rect2()
	if not cfg.has_section_key("hud", key + "/pos"):
		return Rect2()
	return Rect2(
		cfg.get_value("hud", key + "/pos",  Vector2.ZERO) as Vector2,
		cfg.get_value("hud", key + "/size", Vector2.ZERO) as Vector2
	)

# ── Selection + Properties panel ──────────────────────────────────────────────

func _select_item(item: HudItem) -> void:
	if _selected_item != null and _selected_item != item:
		_set_frame_selected(_selected_item, false)
	_selected_item = item
	_set_frame_selected(item, true)
	_update_props_display()

func _set_frame_selected(item: HudItem, sel: bool) -> void:
	if not is_instance_valid(item.frame):
		return
	var s := item.frame.get_theme_stylebox("panel") as StyleBoxFlat
	if s == null:
		return
	if sel:
		s.border_color = Color(1.0, 0.90, 0.15, 1.0)
		s.bg_color     = Color(0.28, 0.26, 0.08, 0.18)
	else:
		s.border_color = Color(0.45, 0.75, 1.0, 0.95)
		s.bg_color     = Color(0.25, 0.55, 1.0, 0.10)

func _make_props_panel() -> Panel:
	var pp := Panel.new()
	pp.size     = Vector2(230.0, 72.0)
	pp.position = Vector2(605.0, 56.0)
	pp.z_index  = 10
	pp.mouse_filter = Control.MOUSE_FILTER_STOP

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.10, 0.16, 0.97)
	s.set_border_width_all(2)
	s.border_color = Color(0.35, 0.55, 0.85, 0.9)
	s.set_corner_radius_all(6)
	pp.add_theme_stylebox_override("panel", s)

	var title := Label.new()
	title.text     = "COORDS / SIZE"
	title.position = Vector2(6.0, 5.0)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.55, 0.72, 0.95))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pp.add_child(title)

	_props_name_lbl = Label.new()
	_props_name_lbl.text = "—"
	_props_name_lbl.position = Vector2(80.0, 5.0)
	_props_name_lbl.size    = Vector2(144.0, 14.0)
	_props_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_props_name_lbl.add_theme_font_size_override("font_size", 9)
	_props_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.20))
	_props_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pp.add_child(_props_name_lbl)

	pp.add_child(_mk_prop_label("X:", Vector2(4.0, 26.0)))
	_pe_x = _mk_line_edit(Vector2(22.0, 24.0), Vector2(87.0, 18.0))
	_pe_x.text_submitted.connect(func(v: String) -> void: _apply_prop("x", v))
	pp.add_child(_pe_x)

	pp.add_child(_mk_prop_label("Y:", Vector2(115.0, 26.0)))
	_pe_y = _mk_line_edit(Vector2(133.0, 24.0), Vector2(87.0, 18.0))
	_pe_y.text_submitted.connect(func(v: String) -> void: _apply_prop("y", v))
	pp.add_child(_pe_y)

	pp.add_child(_mk_prop_label("W:", Vector2(4.0, 52.0)))
	_pe_w = _mk_line_edit(Vector2(22.0, 50.0), Vector2(87.0, 18.0))
	_pe_w.text_submitted.connect(func(v: String) -> void: _apply_prop("w", v))
	pp.add_child(_pe_w)

	pp.add_child(_mk_prop_label("H:", Vector2(115.0, 52.0)))
	_pe_h = _mk_line_edit(Vector2(133.0, 50.0), Vector2(87.0, 18.0))
	_pe_h.text_submitted.connect(func(v: String) -> void: _apply_prop("h", v))
	pp.add_child(_pe_h)

	return pp

func _mk_line_edit(pos: Vector2, sz: Vector2) -> LineEdit:
	var le := LineEdit.new()
	le.position            = pos
	le.size                = sz
	le.custom_minimum_size = sz
	le.add_theme_font_size_override("font_size", 9)
	return le

func _mk_prop_label(txt: String, pos: Vector2) -> Label:
	var l := Label.new()
	l.text     = txt
	l.position = pos
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _update_props_display() -> void:
	if _selected_item == null or _pe_x == null:
		return
	var r := _selected_item.rect
	if is_instance_valid(_props_name_lbl):
		_props_name_lbl.text = "[ %s ]" % _selected_item.key
	_pe_x.text = str(int(r.position.x))
	_pe_y.text = str(int(r.position.y))
	_pe_w.text = str(int(r.size.x))
	_pe_h.text = str(int(r.size.y))

func _apply_prop(prop: String, val_str: String) -> void:
	if _selected_item == null:
		return
	var v := val_str.to_float()
	match prop:
		"x": _selected_item.rect.position.x = v
		"y": _selected_item.rect.position.y = v
		"w": _selected_item.rect.size.x = maxf(v, MIN_SZ.x)
		"h": _selected_item.rect.size.y = maxf(v, MIN_SZ.y)
	_update_layout(_selected_item)

# ── Cleanup ───────────────────────────────────────────────────────────────────

func _clear() -> void:
	_drag_item      = null
	_drag_mode      = ""
	_selected_item  = null
	_props_panel    = null
	_props_name_lbl = null
	_pe_x = null; _pe_y = null; _pe_w = null; _pe_h = null
	_items.clear()
	_toolbar = null
	for c in get_children():
		c.queue_free()
