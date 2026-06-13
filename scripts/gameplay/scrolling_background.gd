extends Control

const BG_PATH := "res://assets/screen/background.png"
const SPEED   := 20.0

var _rects:      Array[TextureRect] = []
var _source_img: Image      = null
var _tex:        Texture2D  = null
var _tile_w:     float = 0.0
var _tile_h:     float = 0.0
var _tile_x:     float = 0.0
var _offset:     float = 0.0
var _cols:       int   = 0
var _screen_w:   float = 0.0
var _screen_h:   float = 0.0
var _tile_scale:  float = 1.0
var _speed_mult:  float = 1.0

func set_speed_mult(m: float) -> void:
	_speed_mult = m

func setup(screen_w: float, screen_h: float) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	z_index       = 0
	_screen_w = screen_w
	_screen_h = screen_h
	var raw := load(BG_PATH) as Texture2D
	if raw:
		_source_img = raw.get_image()
	_rebuild()

func set_tile_scale(scale: float) -> void:
	_tile_scale = clampf(scale, 0.1, 10.0)
	_rebuild()

func _rebuild() -> void:
	for r in _rects:
		if is_instance_valid(r):
			r.queue_free()
	_rects.clear()

	if _source_img == null or _screen_w <= 0.0:
		return

	_tile_w = floorf(_screen_w * _tile_scale)
	_tile_h = floorf(float(_source_img.get_height()) * (_tile_w / float(_source_img.get_width())))
	if _tile_h <= 0.0:
		return

	var img := _source_img.duplicate()
	img.resize(int(_tile_w), int(_tile_h), Image.INTERPOLATE_BILINEAR)
	_tex = ImageTexture.create_from_image(img)

	_cols = 1
	_tile_x = floorf((_screen_w - _tile_w) * 0.5)
	var n_rows: int = ceili(_screen_h / _tile_h) + 1
	for _row in n_rows:
		var tr := TextureRect.new()
		tr.texture      = _tex
		tr.size         = Vector2(_tile_w, _tile_h)
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		_rects.append(tr)

	_offset = 0.0
	_apply_positions()

func apply_layout_rect(rel_pos: Vector2, sz: Vector2) -> void:
	_tile_x = rel_pos.x
	_tile_w  = sz.x
	_tile_h  = sz.y
	if _screen_w > 0.0:
		_tile_scale = clampf(_tile_w / _screen_w, 0.1, 10.0)
	for r in _rects:
		if is_instance_valid(r):
			r.queue_free()
	_rects.clear()
	_cols = 1
	if _source_img == null or _tile_h <= 0.0:
		return
	var img := _source_img.duplicate()
	img.resize(int(_tile_w), int(_tile_h), Image.INTERPOLATE_BILINEAR)
	_tex = ImageTexture.create_from_image(img)
	var n_rows: int = ceili(_screen_h / _tile_h) + 1
	for _row in n_rows:
		var tr := TextureRect.new()
		tr.texture      = _tex
		tr.size         = Vector2(_tile_w, _tile_h)
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		_rects.append(tr)
	_offset = 0.0
	_apply_positions()

func _apply_positions() -> void:
	if _rects.is_empty():
		return
	var ih  := int(_tile_h)
	var ioff := int(_offset)
	var ix   := int(_tile_x)
	for row in _rects.size():
		_rects[row].position = Vector2(ix, ioff + (row - 1) * ih)

func swap_texture(img_path: String) -> void:
	var raw := load(img_path) as Texture2D
	if raw == null:
		return
	_source_img = raw.get_image()
	_rebuild()

func restore_texture() -> void:
	var raw := load(BG_PATH) as Texture2D
	if raw == null:
		return
	_source_img = raw.get_image()
	_rebuild()

func _process(delta: float) -> void:
	if _tile_h <= 0.0:
		return
	_offset += SPEED * _speed_mult * delta
	if _offset >= _tile_h:
		_offset -= _tile_h
	_apply_positions()
