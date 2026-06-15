extends CanvasLayer

## Coordinate grid debug overlay. Toggle via boss_panel. Draws a 100 px grid over the game world
## and shows the current mouse position next to the cursor.

const GRID_STEP  := 100
const LINE_CLR   := Color(1.0, 1.0, 1.0, 0.10)
const MAJOR_CLR  := Color(1.0, 1.0, 1.0, 0.28)   # every 200 px
const LABEL_CLR  := Color(1.0, 1.0, 1.0, 0.55)
const LABEL_SIZE := 9

var _draw_ctrl: Control
var _mouse_lbl:  Label
var _vp: Vector2

func _ready() -> void:
	layer   = 48
	visible = false
	_vp     = get_viewport().get_visible_rect().size

	_draw_ctrl = Control.new()
	_draw_ctrl.position     = Vector2.ZERO
	_draw_ctrl.size         = _vp
	_draw_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_ctrl.draw.connect(_on_draw)
	add_child(_draw_ctrl)

	_mouse_lbl = Label.new()
	_mouse_lbl.z_index      = 10
	_mouse_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mouse_lbl.add_theme_font_size_override("font_size", 11)
	_mouse_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2, 0.95))
	add_child(_mouse_lbl)

func _process(_dt: float) -> void:
	if not visible:
		return
	var mp := get_viewport().get_mouse_position()
	_mouse_lbl.position = mp + Vector2(12.0, -20.0)
	_mouse_lbl.text     = "(%d, %d)" % [int(mp.x), int(mp.y)]

func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var w    := _vp.x
	var h    := _vp.y

	# Vertical lines — x-labels along top edge
	var xi := 0.0
	while xi <= w + 0.5:
		var major := (int(xi) % 200 == 0)
		_draw_ctrl.draw_line(Vector2(xi, 0), Vector2(xi, h), MAJOR_CLR if major else LINE_CLR, 1.0)
		if xi > 0.5:
			_draw_ctrl.draw_string(font, Vector2(xi + 2, 11),
				str(int(xi)), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_CLR)
		xi += float(GRID_STEP)

	# Horizontal lines — y-labels along left edge
	var yi := 0.0
	while yi <= h + 0.5:
		var major := (int(yi) % 200 == 0)
		_draw_ctrl.draw_line(Vector2(0, yi), Vector2(w, yi), MAJOR_CLR if major else LINE_CLR, 1.0)
		if yi > 0.5:
			_draw_ctrl.draw_string(font, Vector2(2, yi + 10),
				str(int(yi)), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_CLR)
		yi += float(GRID_STEP)
