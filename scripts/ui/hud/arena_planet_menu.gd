extends CanvasLayer
## F6 planet menu — a left side panel of live planet previews (rocky / gas / ice, several variants each).
## Drag a preview onto the map to spawn that exact planet there; Reroll regenerates the variants; Clear
## (and Shift+F6) removes manually-placed planets. Pauses the game while open (camera static for placing).

const PlanetScript := preload("res://scripts/gameplay/arena_planet.gd")
const AsteroidScript := preload("res://scripts/gameplay/arena_asteroid.gd")
const CometScript := preload("res://scripts/gameplay/arena_comet.gd")
const FONT_PATH := "res://assets/fonts/Gameplay.ttf"
const PANEL_W := 340.0
const PREVIEW := 76.0
const VARIANT_COUNT := 4          # previews per type
const TYPES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const TYPE_NAMES := ["Rocky", "Gas giant", "Ice", "Earth", "Lava", "Desert", "Ringed",
	"Ocean", "Toxic", "Jungle", "Barren", "Carbon"]

var _root: Control = null
var _grid_box: VBoxContainer = null
var _status: Label = null
var _font: FontFile = null
var _open: bool = false
var _rng := RandomNumberGenerator.new()

var _placing: bool = false
var _place_kind: String = "planet"
var _place_params: Dictionary = {}
var _ghost: Control = null
var _previews: Array = []   # [{ctrl, kind, params}]

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT_PATH) as FontFile
	_rng.randomize()
	_build_ui()
	_root.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F6:
		if (event as InputEventKey).shift_pressed:
			_clear_placed()
		else:
			_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	# Drag-to-map: detect press over a preview, ghost follows the cursor, release over the map spawns it.
	# (Handled in _input — not via Button — so the release isn't swallowed by a Control capturing the mouse.)
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and not _placing:
			var mp := get_viewport().get_mouse_position()
			for pv: Dictionary in _previews:
				var c := pv["ctrl"] as Control
				if is_instance_valid(c) and c.get_global_rect().has_point(mp):
					_start_place(String(pv["kind"]), pv["params"])
					get_viewport().set_input_as_handled()
					return
		elif not mb.pressed and _placing:
			_finish_place()
	elif event is InputEventMouseMotion and _placing and _ghost != null:
		_ghost.position = get_viewport().get_mouse_position() - Vector2(PREVIEW, PREVIEW) * 0.75

func _toggle() -> void:
	_open = not _open
	_root.visible = _open
	get_tree().paused = _open
	if _open and _grid_box.get_child_count() == 0:
		_rebuild()

# ── UI ──────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let the map receive the release for placing
	add_child(_root)

	var panel := Panel.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(PANEL_W, 760)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.97)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 0.6, 0.8, 0.95)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 10)
	vb.size = Vector2(PANEL_W - 24, 740)
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	vb.add_child(_label("PLANETS & OBJECTS  (F6 to close)", 15))
	vb.add_child(_label("Drag a tile onto the map →", 11))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.add_child(_button("Reroll", _rebuild))
	btns.add_child(_button("Clear placed", _clear_placed))
	vb.add_child(btns)

	_status = _label("", 10)
	_status.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	vb.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W - 24, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_grid_box = VBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_grid_box)

func _rebuild() -> void:
	for c in _grid_box.get_children():
		c.queue_free()
	_previews.clear()
	for ti in TYPES.size():
		var type: int = TYPES[ti]
		_grid_box.add_child(_label(TYPE_NAMES[ti], 12))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for v in VARIANT_COUNT:
			var params := PlanetScript.roll_params(type, _rng)
			row.add_child(_make_preview(params))
		_grid_box.add_child(row)
	# ── Non-planet objects: asteroid field, comet, planet + moons (same drag-drop flow). ──
	_grid_box.add_child(_label("OBJECTS", 12))
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 6)
	orow.add_child(_make_viewport_preview("asteroid_field"))
	orow.add_child(_make_viewport_preview("comet"))
	orow.add_child(_make_moon_preview(PlanetScript.roll_params(0, _rng)))
	_grid_box.add_child(orow)

## A preview = a planet-shader ColorRect (press handled in _input by hit-testing its rect).
func _make_preview(params: Dictionary) -> Control:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(PREVIEW, PREVIEW)
	rect.color = Color.WHITE
	rect.material = PlanetScript.make_material(params)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_previews.append({"ctrl": rect, "kind": "planet", "params": params})
	return rect

## Live preview of a non-planet object (asteroid field / comet) — the real Node2D rendered in a SubViewport.
func _make_viewport_preview(kind: String) -> Control:
	var vpc := SubViewportContainer.new()
	vpc.custom_minimum_size = Vector2(PREVIEW, PREVIEW)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = Vector2i(int(PREVIEW), int(PREVIEW))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(vp)
	var bg := ColorRect.new()
	bg.size = Vector2(PREVIEW, PREVIEW)
	bg.color = Color(0.03, 0.04, 0.07)
	vp.add_child(bg)
	if kind == "asteroid_field":
		for i in 5:
			var a := AsteroidScript.new()
			vp.add_child(a)
			a.setup(_rng)
			a.position = Vector2(PREVIEW, PREVIEW) * 0.5 + Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-24.0, 24.0))
			a.scale = Vector2.ONE * 1.4
	else:   # comet
		var c := CometScript.new()
		vp.add_child(c)
		c.setup(_rng)
		c.position = Vector2(PREVIEW * 0.66, PREVIEW * 0.62)
		c.scale = Vector2.ONE * 0.22
	_previews.append({"ctrl": vpc, "kind": kind, "params": {}})
	return vpc

## Planet-shader preview with a small moon in the corner → reads as "planet + moons".
func _make_moon_preview(params: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PREVIEW, PREVIEW)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.size = Vector2(PREVIEW, PREVIEW)
	rect.color = Color.WHITE
	rect.material = PlanetScript.make_material(params)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rect)
	var moon := ColorRect.new()
	moon.size = Vector2(PREVIEW, PREVIEW) * 0.28
	moon.position = Vector2(PREVIEW * 0.62, PREVIEW * 0.06)
	moon.color = Color.WHITE
	moon.material = PlanetScript.make_material(PlanetScript.roll_params(10, _rng))
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(moon)
	_previews.append({"ctrl": holder, "kind": "planet_moons", "params": params})
	return holder

# ── Drag-to-map ───────────────────────────────────────────────────────────────
func _start_place(kind: String, params: Dictionary) -> void:
	_placing = true
	_place_kind = kind
	_place_params = params
	_ghost = _make_ghost(kind, params)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.position = get_viewport().get_mouse_position() - Vector2(PREVIEW, PREVIEW) * 0.75
	_root.add_child(_ghost)

## A cursor-following ghost matching the dragged kind, ~1.5× preview size.
func _make_ghost(kind: String, params: Dictionary) -> Control:
	var sz := Vector2(PREVIEW, PREVIEW) * 1.5
	if kind == "asteroid_field" or kind == "comet":
		var g := _make_viewport_preview(kind)
		_previews.pop_back()   # ghost isn't a draggable tile; drop it from the hit-test list
		g.custom_minimum_size = sz
		g.size = sz
		return g
	if kind == "planet_moons":
		var g2 := _make_moon_preview(params)
		_previews.pop_back()
		g2.custom_minimum_size = sz
		g2.size = sz
		return g2
	var rect := ColorRect.new()
	rect.color = Color.WHITE
	rect.size = sz
	rect.material = PlanetScript.make_material(params)
	return rect

func _finish_place() -> void:
	_placing = false
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	var mouse := get_viewport().get_mouse_position()
	if mouse.x <= PANEL_W:
		return   # released over the panel, not the map → cancel
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var world := cam.global_position + (mouse - center) / cam.zoom   # world point under the cursor
	if _place_kind == "asteroid_field":
		var al := get_tree().get_first_node_in_group("arena_asteroids")
		if al != null:
			var n: int = al.spawn_field_near(world)
			_status.text = "Placed asteroid field (%d rocks)" % n
			print("[object] placed asteroid field (%d rocks)" % n)
		return
	if _place_kind == "comet":
		var cl := get_tree().get_first_node_in_group("arena_comets")
		if cl != null:
			cl.spawn_comet_near(world)
			_status.text = "Placed comet"
			print("[object] placed comet")
		return
	# planet or planet_moons → spawn into the planet layer at the cursor depth
	var layer_node := get_tree().get_first_node_in_group("arena_planets") as Node2D
	if layer_node == null:
		return
	var f: float = layer_node.PLANET_FACTOR
	var lpos := cam.global_position * f + (mouse - center) / cam.zoom
	var pl := PlanetScript.new()
	pl.add_to_group("debug_planet")
	layer_node.add_child(pl)
	pl.apply(_place_params)
	pl.position = lpos
	if _place_kind == "planet_moons" and layer_node.has_method("_add_moons"):
		layer_node._add_moons(pl, float(_place_params.get("radius", 60.0)), _rng)   # guaranteed moons
	elif layer_node.has_method("maybe_add_moons"):
		layer_node.maybe_add_moons(pl, float(_place_params.get("radius", 60.0)), _rng)
	var ti := int(_place_params.get("type", 0))
	var tname: String = PlanetScript.TYPE_NAMES[ti] if ti < PlanetScript.TYPE_NAMES.size() else str(ti)
	var moons_txt := " + moons" if _place_kind == "planet_moons" else ""
	_status.text = "Placed %s%s (r=%.0f)" % [tname, moons_txt, float(_place_params.get("radius", 0.0))]
	print("[planet] placed type %d (%s)%s" % [ti, tname, moons_txt])

func _clear_placed() -> void:
	for n in get_tree().get_nodes_in_group("debug_planet"):
		if is_instance_valid(n):
			n.queue_free()
	for grp in ["arena_asteroids", "arena_comets"]:
		var layer := get_tree().get_first_node_in_group(grp)
		if layer != null and layer.has_method("clear_debug"):
			layer.clear_debug()
	if _status != null:
		_status.text = "Cleared placed planets / asteroids / comets"

# ── Widgets ───────────────────────────────────────────────────────────────────
func _label(text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if _font:
		b.add_theme_font_override("font", _font)
	b.pressed.connect(cb)
	return b
