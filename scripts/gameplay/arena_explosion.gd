extends Node2D
## One-shot animated explosion using Gun-Impact50.sheet.png (7 frames, 0.1s each → 0.7s total).
## Spawned at a world position, scaled to match the destroyed object's visual size, then auto-frees.

var _frames: Array = []
var _delays: Array = []
var _anim_frame: int = 0
var _anim_acc: float = 0.0
var _draw_size: Vector2 = Vector2.ZERO

func setup(world_pos: Vector2, size_px: float) -> void:
	global_position = world_pos
	_load_frames()
	var scale_f := size_px / 100.0
	_draw_size = Vector2(100.0 * scale_f, 113.0 * scale_f)

func _load_frames() -> void:
	var path      := "res://assets/sprites/weapons/Gun-Impact50.sheet.png"
	var json_path := "res://assets/sprites/weapons/Gun-Impact50.sheet.json"
	var atlas := load(path) as Texture2D
	if atlas == null:
		return
	var cols := 7
	var fw   := 100
	var fh   := 113
	var raw_delays: Array = [0.1]
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file != null:
			var data = JSON.parse_string(file.get_as_text())
			file.close()
			if data is Dictionary:
				cols       = int(data.get("cols", cols))
				fw         = int(data.get("w", fw))
				fh         = int(data.get("h", fh))
				raw_delays = data.get("delays", raw_delays)
	var rows  := atlas.get_height() / fh if fh > 0 else 1
	var count := rows * cols
	_frames.clear()
	_delays.clear()
	for i in count:
		var at := AtlasTexture.new()
		at.atlas  = atlas
		at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
		_frames.append(at)
		var d: float = float(raw_delays[i]) if i < raw_delays.size() else float(raw_delays[-1])
		_delays.append(d)

func _process(delta: float) -> void:
	if _frames.is_empty():
		queue_free()
		return
	_anim_acc += delta
	var fd: float = float(_delays[_anim_frame]) if _anim_frame < _delays.size() else 0.1
	if _anim_acc >= fd:
		_anim_acc -= fd
		_anim_frame += 1
		if _anim_frame >= _frames.size():
			queue_free()
			return
		queue_redraw()

func _draw() -> void:
	if _frames.is_empty() or _anim_frame >= _frames.size():
		return
	draw_texture_rect(_frames[_anim_frame] as Texture2D, Rect2(-_draw_size * 0.5, _draw_size), false)
