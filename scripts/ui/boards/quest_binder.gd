extends BoardBinder
class_name QuestBinder
## RUNTIME for the "Quest" board — the panel opened from the Dock's "Bridge" room (hub_screen.gd's
## _on_room_clicked → _open_quest). Self-contained (like DockBinder): it owns the whole interaction, there
## is no external UI driver.
##
## Authored layout (config/boards/quest.cfg, edited in the board editor — Board: "Quest"):
##   "quest board"  — full frame art (static)
##   "quest grid"   — the 6×5 slot area; the binder generates 30 clickable cells over its rect at runtime
##   "quest tv"     — a screen the green CRT scan-line VFX (same shader pair as the Level Up board) plays over
##   "btn quest"    — ONE placed sprite used only as the cell art reference (hidden at runtime)
##   "btn track"    — the Track / Untrack toggle button
##   "btn close"    — the Close button (→ back to the Dock)
##
## Cell states (sprite per state, `assets/hud/quest/`):
##   idle        → "btn quest"
##   selected    → "btn quest pressed"   (radio — only one cell selected at a time)
##   tracked     → "btn quest track"     (up to 3 at once; wins over "selected" visually)
##   done        → "btn quest done"      (quest complete — not clickable; no trigger yet, see _done)
##
## Track button: shows "btn track" normally, "btn untrack" when the currently-selected cell is tracked.
##   click "btn track"  → track the selected cell (no-op if nothing selected; toast if already 3 tracked)
##   click "btn untrack"→ untrack the selected cell
## Close button: swaps to "btn close press" on hover; click emits close_requested (hub_screen closes the board).
##
## Map selector: "btn back" / "btn forward" cycle MetaManager.QUEST_MAP_ORDER (press → "…press" art, release
## → step); the "Map Name" text shows MetaManager.quest_map_name() and the choice is persisted. "mapname"
## sprite gets its own ORANGE CRT scan-line ("quest tv" keeps the green one).
##
## The whole board is re-centred in the game window at build() (and on resize).

const SFX_CLICK := preload("res://assets/audio/sfx/uiclick.wav")
const FONT_BODY := "res://assets/fonts/mandalore/mandalore.ttf"
const SCAN_SHADER := "res://assets/shaders/selection_scan.gdshader"
const SWEEP_SHADER := "res://assets/shaders/selection_sweep.gdshader"
const SCAN_GREEN := Color(0.35, 1.0, 0.45, 0.5)    # "quest tv" — same green as the Level Up board
const SCAN_ORANGE := Color(1.0, 0.58, 0.16, 0.5)   # "mapname"

const GRID_COLS := 6
const GRID_ROWS := 5
const CELL_GAP := 3.0
const CELL_W := 53.0
const CELL_H := 55.0
const MAX_TRACKED := 3
## Per-quest icons — filename == QuestManager.QUESTS[qid].name. Rendered inside each slot at ICON_FIT of
## the cell, aspect kept (GPU stretch, not CPU resize — see CLAUDE.md rendering rules).
const ICON_DIR := "res://assets/hud/quest/Electric/"
const ICON_FIT := 0.80
const ICON_SHRINK := 4.0   # px taken off the icon fit-box (each dimension), on request
# Runtime nodes take their z from the authored sprite they sit on (its group's position in the editor's
# Z-order list), NOT a fixed value — so re-ordering the "Quest Tivi" group below "Quest Board" in the
# editor actually pushes the TV scan-line behind the board frame too.

## Emitted when the Close button is clicked — hub_screen.gd connects this to _close_quest.
signal close_requested

const HOVER_DELAY := 0.3

## Cell 0..11 → QuestManager.ORDER[i] (eq01..eq12); 12..29 are empty. Done/available/locked/tracked all
## come from QuestManager now; only "which quest is being viewed in the TV panel" is board-local (and
## static so it survives the host's fresh-binder-per-reload()).
static var _selected_qid: String = ""

var _cell_btns: Array = []           # 30 TextureButton, row-major (r*GRID_COLS + c)
var _tex_cache: Dictionary = {}      # sprite basename → Texture2D
var _track_eo = null                 # authored "btn track" EditableObjectNode
var _close_eo = null                 # authored "btn close" EditableObjectNode
var _mapname_text = null             # authored "Map Name" _HudText node
var _info_labels: Dictionary = {}    # sentinel ("Quest name"/…) → runtime wrapped Label filling that slot
var _tooltip: Label = null           # hover name tooltip (near the cell)
var _hover_timer: SceneTreeTimer = null
var _toast: Label = null
var _toast_tween: Tween = null
var _click_player: AudioStreamPlayer = null
var _runtime: Array = []             # everything build() spawns — freed in clear()
var _center_offset: Vector2 = Vector2.ZERO   # applied to authored nodes by _center_board() (undone on re-run)

func has_layout() -> bool:
	if _ed == null:
		return false
	for g: Dictionary in (_ed._groups as Array):
		if not (g.get("children", []) as Array).is_empty():
			return true
	return false

func build() -> void:
	clear()
	if _ed == null or container() == null:
		return
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = SFX_CLICK
	_click_player.bus = "SFX"
	_ed.add_child(_click_player)
	_runtime.append(_click_player)

	# The lone authored "btn quest" is only a placement/art reference — hide it; the grid is generated below.
	var tmpl = _item_node("btn quest")
	if tmpl != null:
		(tmpl as CanvasItem).visible = false

	_center_board()
	_build_grid()
	_wire_track_button()
	_wire_close_button()
	_wire_map_nav()
	_build_tv_vfx()
	_build_mapname_vfx()
	_build_info_panel()
	_build_tooltip()
	_build_toast()
	if QuestManager.has_signal("quest_changed") and not QuestManager.quest_changed.is_connected(_refresh):
		QuestManager.quest_changed.connect(_refresh)
	if _selected_qid == "" or QuestManager.state_of(_selected_qid) == "locked":
		_selected_qid = _first_viewable_qid()
	_refresh()
	_render_info()
	_update_map_name()

func _first_viewable_qid() -> String:
	for qid: String in QuestManager.ORDER:
		if QuestManager.state_of(qid) != "locked":
			return qid
	return ""

	var vp: Viewport = _ed.get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_vp_resize):
		vp.size_changed.connect(_on_vp_resize)

func _on_vp_resize() -> void:
	if _ed != null and not _ed.is_open():
		build()

func clear() -> void:
	var vp: Viewport = _ed.get_viewport() if _ed != null else null
	if vp != null and vp.size_changed.is_connected(_on_vp_resize):
		vp.size_changed.disconnect(_on_vp_resize)
	if QuestManager.has_signal("quest_changed") and QuestManager.quest_changed.is_connected(_refresh):
		QuestManager.quest_changed.disconnect(_refresh)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = null
	_hover_timer = null
	for n in _runtime:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_runtime.clear()
	_cell_btns.clear()
	_info_labels.clear()
	_track_eo = null
	_close_eo = null
	_mapname_text = null
	_tooltip = null
	_toast = null
	_click_player = null

# ── Authored-node lookup (by filename, any group) ───────────────────────────────────────────
func _item_node(file: String):
	if _ed == null:
		return null
	for g: Dictionary in (_ed._groups as Array):
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) == "item" and String(ch.get("file", "")) == file:
				var n = _ed._nodes.get(int(ch.get("id", -1)))
				if n != null and is_instance_valid(n):
					return n
	return null

func _item_rect(file: String) -> Rect2:
	var n = _item_node(file)
	if n == null:
		return Rect2()
	return Rect2((n as Control).position, (n as Control).size)

func _tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = _ed._load_tex(_ed._item_path(name))
	return _tex_cache[name]

func _play_click() -> void:
	if _click_player != null and is_instance_valid(_click_player):
		_click_player.play()

# ── Re-centre the whole board in the game window ───────────────────────────────────────────
## Restores every authored node to its cfg position (so a re-run on resize doesn't compound), then shifts
## them all so the union bounding-box is centred in the viewport. Runtime nodes are placed AFTER this from
## the shifted authored positions, so they follow automatically.
func _center_board() -> void:
	var oc := container()
	if oc == null or _ed == null:
		return
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	var nodes: Array = []
	for id: int in _ed._nodes:
		var n = _ed._nodes[id]
		if n == null or not is_instance_valid(n):
			continue
		var loc: Vector2i = _ed._find_child(id)
		if loc.x < 0:
			continue
		var ch: Dictionary = (_ed._groups[loc.x]["children"] as Array)[loc.y]
		var p: Vector2 = ch.get("pos", (n as Control).position)
		(n as Control).position = p   # undo any prior centre offset
		nodes.append(n)
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		var e: Vector2 = p + (n as Control).size
		mx.x = maxf(mx.x, e.x); mx.y = maxf(mx.y, e.y)
	if nodes.is_empty():
		return
	var vp: Vector2 = oc.get_viewport_rect().size
	_center_offset = (((vp - (mx - mn)) * 0.5) - mn).round()
	for n in nodes:
		(n as Control).position += _center_offset

# ── Grid of 30 cells over the "quest grid" rect ─────────────────────────────────────────────
## Fixed CELL_W×CELL_H (53×55) cells, 3 px apart, the 6×5 block centred within the "quest grid" rect.
func _build_grid() -> void:
	_cell_btns = []
	var grid_node = _item_node("quest grid")
	if grid_node == null:
		return
	var grid := Rect2((grid_node as Control).position, (grid_node as Control).size)
	if grid.size.x <= 0.0:
		return
	var gz := (grid_node as CanvasItem).z_index + 1   # the interactive layer sits just over the grid art
	var block := Vector2(GRID_COLS * CELL_W + (GRID_COLS - 1) * CELL_GAP, GRID_ROWS * CELL_H + (GRID_ROWS - 1) * CELL_GAP)
	var origin := grid.position + (grid.size - block) * 0.5
	for r: int in GRID_ROWS:
		for c: int in GRID_COLS:
			var i := r * GRID_COLS + c
			var b := TextureButton.new()
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			b.position = origin + Vector2(c * (CELL_W + CELL_GAP), r * (CELL_H + CELL_GAP))
			b.custom_minimum_size = Vector2(CELL_W, CELL_H)
			b.size = Vector2(CELL_W, CELL_H)
			b.z_index = gz
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_on_cell_pressed.bind(i))
			b.mouse_entered.connect(_on_cell_hover.bind(i, true))
			b.mouse_exited.connect(_on_cell_hover.bind(i, false))
			container().add_child(b)
			_runtime.append(b)
			_cell_btns.append(b)
			_add_cell_icon(b, _qid_for(i))

## The quest's icon, centred inside the slot at ICON_FIT of the cell, aspect preserved. Child of the
## slot button so it moves + inherits the button's modulate (dim when the quest is locked). Clicks pass
## through (mouse IGNORE).
func _add_cell_icon(btn: TextureButton, qid: String) -> void:
	if qid == "":
		return
	var tex := _quest_icon(qid)
	if tex == null:
		return
	var box := (Vector2(CELL_W, CELL_H) * ICON_FIT - Vector2(ICON_SHRINK, ICON_SHRINK)).max(Vector2(4, 4))
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = box
	tr.position = (Vector2(CELL_W, CELL_H) - box) * 0.5
	tr.z_index = 1
	btn.add_child(tr)

func _quest_icon(qid: String) -> Texture2D:
	var name := "%s%s.png" % [ICON_DIR, String(QuestManager.QUESTS.get(qid, {}).get("name", ""))]
	if _tex_cache.has(name):
		return _tex_cache[name]
	var t: Texture2D = load(name) as Texture2D if ResourceLoader.exists(name) else null
	if t == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(name))
		if img != null:
			t = ImageTexture.create_from_image(img)
	_tex_cache[name] = t
	return t

## Cell index → quest id ("" for the 18 empty cells past the 12 quests).
func _qid_for(i: int) -> String:
	return String(QuestManager.ORDER[i]) if i >= 0 and i < QuestManager.ORDER.size() else ""

func _on_cell_pressed(i: int) -> void:
	var qid := _qid_for(i)
	if qid == "":
		return
	# Every quest cell (locked / available / done) is clickable — clicking VIEWS it in the TV panel.
	# Locked just can't be tracked or completed; done just can't be tracked. Only the 18 empty cells are inert.
	_selected_qid = qid
	_play_click()
	_refresh()
	_render_info()

func _cell_sprite(i: int) -> String:
	var qid := _qid_for(i)
	if qid == "":
		return "btn quest"
	match QuestManager.state_of(qid):
		"done":
			return "btn quest done"
		"available":
			if QuestManager.is_tracked(qid): return "btn quest track"
			if qid == _selected_qid:         return "btn quest pressed"
			return "btn quest"
		_:   # locked — dimmed idle; shows the pressed frame while it's the one being viewed
			return "btn quest pressed" if qid == _selected_qid else "btn quest"

func _refresh() -> void:
	for i: int in _cell_btns.size():
		var b: TextureButton = _cell_btns[i]
		if b == null or not is_instance_valid(b):
			continue
		var qid := _qid_for(i)
		var st: String = QuestManager.state_of(qid) if qid != "" else "empty"
		b.texture_normal = _tex(_cell_sprite(i))
		b.disabled = (qid == "")           # only the empty cells are inert
		b.modulate = Color(0.5, 0.5, 0.5) if st == "locked" else Color.WHITE
	# Track button reflects whether the SELECTED quest is currently tracked.
	if _track_eo != null and is_instance_valid(_track_eo):
		var trk := _selected_qid != "" and QuestManager.is_tracked(_selected_qid)
		_track_eo.texture_rect.texture = _tex("btn untrack" if trk else "btn track")

func _on_track_pressed() -> void:
	var st: String = QuestManager.state_of(_selected_qid) if _selected_qid != "" else ""
	if st != "available":
		return   # nothing trackable selected (empty / locked / already done) → no effect, per spec
	if not QuestManager.is_tracked(_selected_qid) and QuestManager.tracked_count() >= MAX_TRACKED:
		_show_toast("Maximum 3 quest tracking allowed")
		return
	QuestManager.toggle_tracked(_selected_qid)
	_play_click()
	_refresh()

# ── Hover: quest-name tooltip near the cell, after HOVER_DELAY ───────────────────────────────
func _on_cell_hover(i: int, inside: bool) -> void:
	var qid := _qid_for(i)
	if not inside or qid == "":
		if _tooltip != null and is_instance_valid(_tooltip):
			_tooltip.visible = false
		_hover_timer = null
		return
	var b: Control = _cell_btns[i]
	_hover_timer = _ed.get_tree().create_timer(HOVER_DELAY)
	var this_timer := _hover_timer
	_hover_timer.timeout.connect(func() -> void:
		if this_timer != _hover_timer or _tooltip == null or not is_instance_valid(_tooltip) or not is_instance_valid(b):
			return
		_tooltip.text = MandaloreText.a(String(QuestManager.QUESTS[qid]["name"]))
		_tooltip.reset_size()
		_tooltip.position = b.position + Vector2((b.size.x - _tooltip.size.x) * 0.5, b.size.y + 3.0)
		_tooltip.visible = true)

func _build_tooltip() -> void:
	_tooltip = Label.new()
	_tooltip.z_index = 320
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := load(FONT_BODY) as Font
	if f != null:
		_tooltip.add_theme_font_override("font", f)
	_tooltip.add_theme_font_size_override("font_size", 16)
	_tooltip.add_theme_color_override("font_color", Color(0.27, 0.91, 0.45))
	_tooltip.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tooltip.add_theme_constant_override("outline_size", 5)
	container().add_child(_tooltip)
	_runtime.append(_tooltip)

# ── TV info panel — fill the authored "Quest name / …Description / Trivia" text slots ────────
## The 4 dynamic sentinel texts ("Quest name", "Objective Description", "Reward Description", "Trivia")
## are hidden and replaced by wrapped runtime Labels using each one's authored style + position; the width
## wraps to the right edge of "quest tv". "Objective" / "Reward" (green headers) are left untouched.
const INFO_SENTINELS := ["Quest name", "Objective Description", "Reward Description", "Trivia"]

func _build_info_panel() -> void:
	var tv := _item_rect("quest tv")
	var right_edge := (tv.position.x + tv.size.x - 14.0) if tv.size.x > 0.0 else 1140.0
	for sent: String in INFO_SENTINELS:
		var src = _text_node(sent)
		if src == null:
			continue
		(src as CanvasItem).visible = false   # authored node = style + position template only
		var d: Dictionary = _text_child_dict(sent)
		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.position = (src as Control).position
		lbl.size = Vector2(maxf(60.0, right_edge - (src as Control).position.x), 0.0)
		lbl.z_index = (src as CanvasItem).z_index
		var fp := String(d.get("font", ""))
		if fp != "":
			var fnt: Font = _ed._load_font(fp)
			if fnt != null:
				lbl.add_theme_font_override("font", fnt)
		lbl.add_theme_font_size_override("font_size", int(d.get("font_size", 15)))
		lbl.add_theme_color_override("font_color", d.get("color", Color.WHITE))
		lbl.add_theme_color_override("font_outline_color", d.get("outline_color", Color.BLACK))
		lbl.add_theme_constant_override("outline_size", int(d.get("outline_size", 0)))
		container().add_child(lbl)
		_runtime.append(lbl)
		_info_labels[sent] = lbl

## The authored text child dict for a sentinel (font/size/colour template).
func _text_child_dict(sentinel: String) -> Dictionary:
	var want := sentinel.strip_edges().to_lower().replace(" ", "")
	for g: Dictionary in (_ed._groups as Array):
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) == "text" \
					and String(ch.get("text", "")).strip_edges().to_lower().replace(" ", "") == want:
				return ch
	return {}

func _render_info() -> void:
	var q: Dictionary = QuestManager.QUESTS.get(_selected_qid, {})
	var vals := {
		"Quest name": String(q.get("name", "")),
		"Objective Description": String(q.get("objective", "")),
		"Reward Description": String(q.get("reward", "")),
		"Trivia": String(q.get("trivia", "")),
	}
	for sent: String in INFO_SENTINELS:
		var lbl: Label = _info_labels.get(sent)
		if lbl != null and is_instance_valid(lbl):
			lbl.text = String(vals[sent])

# ── Track / Close: a transparent Button over the authored sprite (same idiom as DockBinder) ─────────
func _overlay_button(over: Control) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.position = over.position
	btn.size = over.size
	btn.z_index = over.z_index + 1
	container().add_child(btn)
	_runtime.append(btn)
	return btn

func _wire_track_button() -> void:
	_track_eo = _item_node("btn track")
	if _track_eo == null:
		return
	_overlay_button(_track_eo as Control).pressed.connect(_on_track_pressed)

func _wire_close_button() -> void:
	_close_eo = _item_node("btn close")
	if _close_eo == null:
		return
	var btn := _overlay_button(_close_eo as Control)
	btn.mouse_entered.connect(_on_close_hover.bind(true))
	btn.mouse_exited.connect(_on_close_hover.bind(false))
	btn.pressed.connect(_on_close_pressed)

func _on_close_hover(inside: bool) -> void:
	if _close_eo != null and is_instance_valid(_close_eo):
		_close_eo.texture_rect.texture = _tex("btn close press" if inside else "btn close")

func _on_close_pressed() -> void:
	_play_click()
	close_requested.emit()

# ── Map selector: "Map Name" text + "btn back" / "btn forward" ──────────────────────────────
func _text_node(sentinel: String):
	if _ed == null:
		return null
	var want := sentinel.strip_edges().to_lower().replace(" ", "")
	for g: Dictionary in (_ed._groups as Array):
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) == "text" \
					and String(ch.get("text", "")).strip_edges().to_lower().replace(" ", "") == want:
				var n = _ed._nodes.get(int(ch.get("id", -1)))
				if n != null and is_instance_valid(n):
					return n
	return null

func _wire_map_nav() -> void:
	_mapname_text = _text_node("Map Name")
	_wire_nav_button("btn back", "btn back press", -1)
	_wire_nav_button("btn forward", "btn forward press", 1)

## Press-and-hold shows the "…press" art; releasing restores the normal art AND steps the map.
func _wire_nav_button(file: String, press_file: String, step: int) -> void:
	var eo = _item_node(file)
	if eo == null:
		return
	var btn := _overlay_button(eo as Control)
	btn.button_down.connect(func() -> void:
		if is_instance_valid(eo):
			eo.texture_rect.texture = _tex(press_file))
	btn.button_up.connect(func() -> void:
		if is_instance_valid(eo):
			eo.texture_rect.texture = _tex(file))
	btn.pressed.connect(_step_map.bind(step))

func _step_map(step: int) -> void:
	MetaManager.quest_map_step(step)
	_play_click()
	_update_map_name()

func _update_map_name() -> void:
	if _mapname_text != null and is_instance_valid(_mapname_text) and _mapname_text.has_method("set_text_value"):
		_mapname_text.set_text_value(MetaManager.quest_map_name())

# ── CRT scan-line VFX (green over "quest tv", orange over "mapname") ────────────────────────
## Drawn at the source sprite's OWN z_index (added to the container after every authored node, so tree
## order still puts it just over that sprite) — so re-ordering the sprite's group in the editor takes the
## scan-line with it (e.g. "Quest Tivi" moved below "Quest Board" → scan-line goes behind the board frame).
## quest tv: only the fine CRT scan-lines, at 50% — no border ring, no big top-to-bottom sweep band.
func _build_tv_vfx() -> void:
	_scanlines_over("quest tv", SCAN_GREEN, 90.0, false, false, 0.5)

## mapname: the full treatment (fine lines + border + sweep) on a short orange strip.
func _build_mapname_vfx() -> void:
	# lower scanline frequency — "mapname" is a short strip, at freq 90 the lines collapse into a flat tint
	_scanlines_over("mapname", SCAN_ORANGE, 22.0, true, true, 1.0)

func _scanlines_over(file: String, col: Color, scan_freq: float, with_sweep: bool, with_border: bool, opacity: float) -> void:
	var node = _item_node(file)
	if node == null:
		return
	var rect := Rect2((node as Control).position, (node as Control).size)
	if rect.size.x <= 0.0:
		return
	var z := (node as CanvasItem).z_index
	_runtime.append(_make_scan_rect(rect, z, col, scan_freq, with_border, opacity))
	if with_sweep:
		_runtime.append(_make_sweep_rect(rect, z, col, opacity))

func _make_scan_rect(rect: Rect2, z: int, col: Color, scan_freq: float, with_border: bool, opacity: float) -> ColorRect:
	var cr := ColorRect.new()
	cr.position = rect.position
	cr.size = rect.size
	cr.z_index = z
	cr.modulate.a = opacity
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SCAN_SHADER)
	mat.set_shader_parameter("scan_color", col)
	mat.set_shader_parameter("scanline_freq", scan_freq)
	mat.set_shader_parameter("border_strength", 1.0 if with_border else 0.0)
	cr.material = mat
	container().add_child(cr)
	return cr

func _make_sweep_rect(rect: Rect2, z: int, col: Color, opacity: float) -> ColorRect:
	var cr := ColorRect.new()
	cr.position = rect.position
	cr.size = rect.size
	cr.z_index = z
	cr.modulate.a = opacity
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SWEEP_SHADER)
	mat.set_shader_parameter("sweep_color", col)
	cr.material = mat
	container().add_child(cr)
	return cr

# ── Toast ("Maximum 3 quest tracking allowed") ─────────────────────────────────────────────
func _build_toast() -> void:
	_toast = Label.new()
	_toast.z_index = 300
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	var f := load(FONT_BODY) as Font
	if f != null:
		_toast.add_theme_font_override("font", f)
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.42, 0.35))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var board := _item_rect("quest board")
	if board.size.x > 0.0:
		_toast.position = Vector2(board.position.x, board.position.y + 12.0)
		_toast.size = Vector2(board.size.x, 30.0)
	container().add_child(_toast)
	_runtime.append(_toast)

func _show_toast(msg: String) -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	_toast.text = MandaloreText.a(msg)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
