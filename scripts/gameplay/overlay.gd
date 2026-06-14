extends Control

const OV_PATH := "res://assets/screen/overlay.png"
const SPEED   := 20.0

var _rects:      Array[TextureRect] = []
var _rects_r:    Array[TextureRect] = []   # mirrored right strip (flip_h)
var _source_img: Image      = null
var _tex:        Texture2D  = null
var _tile_w:     float = 0.0
var _tile_h:     float = 0.0
var _tile_x:     float = 0.0
var _tile_x_r:   float = 0.0
var _offset:     float = 0.0
var _cols:       int   = 0
var _screen_w:   float = 0.0
var _screen_h:   float = 0.0
var _tile_scale:  float = 1.0
var _speed_mult:  float = 1.0
var _saved_tile_scale: float = -1.0
var _saved_tile_x:     float = -1.0
var _ov_blobs:         Array = []

func set_speed_mult(m: float) -> void:
	_speed_mult = m

func setup(screen_w: float, screen_h: float) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	z_index       = 1
	_screen_w = screen_w
	_screen_h = screen_h
	var raw := load(OV_PATH) as Texture2D
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
	var ih   := int(_tile_h)
	var ioff := int(_offset)
	var ix   := int(_tile_x)
	var ixr  := int(_tile_x_r)
	for row in _rects.size():
		_rects[row].position = Vector2(ix, ioff + (row - 1) * ih)
	for row in _rects_r.size():
		_rects_r[row].position = Vector2(ixr, ioff + (row - 1) * ih)

func swap_texture(img_path: String, target_width: float = -1.0, tile_x: float = NAN) -> void:
	var raw := load(img_path) as Texture2D
	if raw == null:
		return
	_saved_tile_scale = _tile_scale
	_saved_tile_x     = _tile_x
	_source_img = raw.get_image()
	if target_width > 0.0 and _screen_w > 0.0:
		_tile_scale = target_width / _screen_w
	_rebuild()
	if not is_nan(tile_x):
		_tile_x = tile_x
		_apply_positions()

## Spawn a mirrored (flip_h) copy of the current strip at x_pos.
## Must be called after swap_texture() so _tex and _tile_h are ready.
func attach_right_strip(x_pos: float) -> void:
	for r in _rects_r:
		if is_instance_valid(r):
			r.queue_free()
	_rects_r.clear()
	if _tex == null or _tile_h <= 0.0:
		return
	_tile_x_r = x_pos
	var n_rows: int = ceili(_screen_h / _tile_h) + 1
	for _row in n_rows:
		var tr := TextureRect.new()
		tr.texture      = _tex
		tr.size         = Vector2(_tile_w, _tile_h)
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.flip_h       = true
		add_child(tr)
		_rects_r.append(tr)
	_apply_positions()

func restore_texture() -> void:
	for r in _rects_r:
		if is_instance_valid(r):
			r.queue_free()
	_rects_r.clear()
	clear_blobs()
	var raw := load(OV_PATH) as Texture2D
	if raw == null:
		return
	_source_img = raw.get_image()
	if _saved_tile_scale >= 0.0:
		_tile_scale = _saved_tile_scale
		_saved_tile_scale = -1.0
	_rebuild()
	if _saved_tile_x >= 0.0:
		_tile_x = _saved_tile_x
		_saved_tile_x = -1.0
		_apply_positions()

func attach_blob(frames: Array, delays: Array, bx: float, start_y: float, bw: float, bh: float, flip_h: bool = false) -> void:
	if frames.is_empty():
		return
	var tr := TextureRect.new()
	tr.texture      = frames[0]
	tr.size         = Vector2(bw, bh)
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.expand_mode  = TextureRect.EXPAND_KEEP_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.flip_h       = flip_h
	tr.position     = Vector2(bx, start_y)
	add_child(tr)
	_ov_blobs.append({
		"tr": tr, "frames": frames, "delays": delays,
		"frame": 0, "acc": randf() * (delays[0] if delays.size() > 0 else 0.1), "h": bh,
	})

func clear_blobs() -> void:
	for blob: Dictionary in _ov_blobs:
		var tr := blob["tr"] as TextureRect
		if is_instance_valid(tr):
			tr.queue_free()
	_ov_blobs.clear()

func _process(delta: float) -> void:
	if _tile_h <= 0.0:
		return
	_offset += SPEED * _speed_mult * delta
	if _offset >= _tile_h:
		_offset -= _tile_h
	_apply_positions()
	for blob: Dictionary in _ov_blobs:
		var tr := blob["tr"] as TextureRect
		if not is_instance_valid(tr):
			continue
		tr.position.y += SPEED * _speed_mult * delta
		if tr.position.y > _screen_h:
			tr.position.y = -blob["h"]
		blob["acc"] += delta
		var delays: Array = blob["delays"]
		var cur_delay: float = delays[blob["frame"]] if delays.size() > blob["frame"] else 0.1
		if blob["acc"] >= cur_delay:
			blob["acc"] -= cur_delay
			blob["frame"] = (blob["frame"] + 1) % (blob["frames"] as Array).size()
			tr.texture = (blob["frames"] as Array)[blob["frame"]]
