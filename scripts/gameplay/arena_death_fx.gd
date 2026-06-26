extends Node2D
## LIGHTWEIGHT enemy-death explosion: plays the pre-baked `death_explosion` sprite sheet as an ADDITIVE flipbook
## (1 node + 1 draw call/frame), scaled to the enemy + random rotation — instead of the live composite Explosion
## (~4 particle nodes/death) which tanked the frame rate when a whole wave died at once. The sheet was baked from
## that same composite (tools/bake_death_explosion.gd) so it looks the same, just free to replay.

const SHEET := "res://assets/fx/death_explosion/death_explosion.png"
const JSONP := "res://assets/fx/death_explosion/death_explosion.json"
const DISPLAY_SCALE := 3.2   # drawn frame size = enemy size × this (the burst fills the centre of the frame)

# Shared across all instances — load the sheet/metadata once.
static var _atlas: Texture2D = null
static var _cols: int = 18
static var _fw: int = 256
static var _fh: int = 256
static var _delays: Array = []

var _frame: int = 0
var _acc: float = 0.0
var _size: Vector2 = Vector2.ZERO

func _ready() -> void:
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive: the black-bg sheet adds only its bright pixels
	material = cm
	z_index = 6

func setup(world_pos: Vector2, size_px: float) -> void:
	global_position = world_pos
	rotation = randf() * TAU                            # cheap per-death variation
	_ensure_loaded()
	var d := maxf(8.0, size_px * DISPLAY_SCALE)
	_size = Vector2(d, d)

static func _ensure_loaded() -> void:
	if _atlas != null:
		return
	_atlas = load(SHEET) as Texture2D
	if FileAccess.file_exists(JSONP):
		var f := FileAccess.open(JSONP, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if data is Dictionary:
				_cols = int(data.get("cols", _cols))
				_fw = int(data.get("w", _fw))
				_fh = int(data.get("h", _fh))
				_delays = data.get("delays", _delays)

func _process(delta: float) -> void:
	if _atlas == null:
		queue_free()
		return
	_acc += delta
	var fd: float = float(_delays[_frame]) if _frame < _delays.size() else 0.05
	if _acc >= fd:
		_acc -= fd
		_frame += 1
		if _frame >= _cols:
			queue_free()
			return
		queue_redraw()

func _draw() -> void:
	if _atlas == null or _frame >= _cols:
		return
	draw_texture_rect_region(_atlas, Rect2(-_size * 0.5, _size), Rect2((_frame % _cols) * _fw, 0, _fw, _fh))
