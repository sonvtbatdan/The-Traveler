extends Node2D
## Clap-mech visual (reusable, like ZSlash): plays a fast 12-frame hand-clap with a HANDS-ONLY after-image
## trail (so the fists blur but the body stays crisp → reads faster/punchier), and emits a 120° shockwave
## cone when the fists meet. Driven by the test scene (scenes/test_moroboshi.tscn) and, later, by the real
## arena weapon. Body is bullseye-anchored at this node's origin; rotate the node to aim.
##
## Frames live in assets/weaponry/clapper/: body_00..body_11.png (full mech) + hands_00..hands_11.png (just
## the two orange fists, same registration) + clapper.json ({width,height,anchor}).

const FRAME_COUNT := 12
const ASSET_DIR := "res://assets/weaponry/clapper/"

# ── Tunables ──────────────────────────────────────────────────────────────────────
@export var display_width: float = 96.0      # on-screen mech width (px); height aspect-locked
@export var clap_delay: float = 0.028         # seconds per frame on the CLAP (fast)
@export var open_delay: float = 0.05          # seconds per frame on the RE-OPEN (a touch slower)
@export var hold_time: float = 0.10           # pause at full clap before re-opening
@export var ghost_count: int = 3              # how many trailing hand after-images
@export var ghost_alpha: float = 0.40         # alpha of the first (closest) ghost; later ones fade
@export var ghost_gap: int = 1                # frames between each ghost sample (bigger = longer trail)
@export var cone_half_deg: float = 60.0       # half-angle of the shockwave cone (60 → 120° total)
@export var shock_reach: float = 240.0        # how far the shockwave travels
@export var shock_time: float = 0.30          # shockwave life (expand + fade)
@export var shock_col: Color = Color(1.0, 0.55, 0.2)   # warm shockwave tint (HDR-ish → blooms)
@export var facing: float = -PI * 0.5         # world angle the clap/shockwave points (default = up)

# ── State ─────────────────────────────────────────────────────────────────────────
enum { IDLE, CLAP, HOLD, OPEN }
var _body: Array[Texture2D] = []
var _hands: Array[Texture2D] = []
var _fw: float = 1.0
var _fh: float = 1.0
var _anchor: Vector2 = Vector2.ZERO
var _phase: int = IDLE
var _frame: int = 0
var _acc: float = 0.0
var _hold_t: float = 0.0
var _shocks: Array = []   # [{age:float}] — expanding cones, aimed along `facing` at emit time
var _shock_aims: Array = []

func _ready() -> void:
	_load_frames()

func _load_frames() -> void:
	var meta_txt := FileAccess.get_file_as_string(ASSET_DIR + "clapper.json")
	if meta_txt != "":
		var m = JSON.parse_string(meta_txt)
		if m is Dictionary:
			_fw = float(m.get("width", 1))
			_fh = float(m.get("height", 1))
			var a: Array = m.get("anchor", [0, 0])
			_anchor = Vector2(float(a[0]), float(a[1]))
	for i in FRAME_COUNT:
		_body.append(load(ASSET_DIR + "body_%02d.png" % i) as Texture2D)
		_hands.append(load(ASSET_DIR + "hands_%02d.png" % i) as Texture2D)
	if _fw <= 1.0 and not _body.is_empty() and _body[0] != null:
		_fw = float(_body[0].get_width()); _fh = float(_body[0].get_height())
		_anchor = Vector2(_fw, _fh) * 0.5

## Start a clap. Optionally aim it (world angle the fists/shockwave face).
func play_clap(aim: float = NAN) -> void:
	if not is_nan(aim):
		facing = aim
	_phase = CLAP
	_frame = 0
	_acc = 0.0

func is_clapping() -> bool:
	return _phase != IDLE

func _process(delta: float) -> void:
	match _phase:
		CLAP:
			_acc += delta
			while _acc >= clap_delay:
				_acc -= clap_delay
				_frame += 1
				if _frame >= FRAME_COUNT - 1:
					_frame = FRAME_COUNT - 1
					_emit_shock()
					_phase = HOLD
					_hold_t = hold_time
					break
		HOLD:
			_hold_t -= delta
			if _hold_t <= 0.0:
				_phase = OPEN
				_acc = 0.0
		OPEN:
			_acc += delta
			while _acc >= open_delay:
				_acc -= open_delay
				_frame -= 1
				if _frame <= 0:
					_frame = 0
					_phase = IDLE
					break
	# advance shockwaves
	for s in _shocks:
		s["age"] += delta
	for i in range(_shocks.size() - 1, -1, -1):
		if _shocks[i]["age"] >= shock_time:
			_shocks.remove_at(i)
			_shock_aims.remove_at(i)
	queue_redraw()

func _emit_shock() -> void:
	_shocks.append({"age": 0.0})
	_shock_aims.append(facing)

func _draw() -> void:
	var scale := display_width / maxf(_fw, 1.0)
	var sz := Vector2(_fw, _fh) * scale
	var topleft := -_anchor * scale       # puts the body bullseye at this node's origin
	# Sprite's natural axis is UP; rotate so "up" aligns to `facing`.
	draw_set_transform(Vector2.ZERO, facing + PI * 0.5, Vector2.ONE)
	# 1) HANDS-ONLY after-image trail (drawn first, behind the body) — only while clapping.
	if _phase == CLAP and not _hands.is_empty():
		for g in range(ghost_count, 0, -1):
			var gi := _frame - g * ghost_gap
			if gi < 0:
				continue
			var a := ghost_alpha * (1.0 - float(g - 1) / float(maxi(ghost_count, 1)))
			if _hands[gi] != null:
				draw_texture_rect(_hands[gi], Rect2(topleft, sz), false, Color(1, 1, 1, a))
	# 2) Current body frame (crisp).
	if not _body.is_empty() and _body[_frame] != null:
		draw_texture_rect(_body[_frame], Rect2(topleft, sz), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 3) Shockwave cones (world-local; aimed where the clap pointed).
	var cone_half := deg_to_rad(cone_half_deg)
	for i in _shocks.size():
		var t: float = float(_shocks[i]["age"]) / shock_time
		var aim: float = _shock_aims[i]
		var r := shock_reach * ease(t, 0.45)            # fast-out expansion
		var a := (1.0 - t) * 0.9
		var seg := maxi(10, int(cone_half / PI * 96.0))
		draw_arc(Vector2.ZERO, r, aim - cone_half, aim + cone_half, seg,
			Color(shock_col.r, shock_col.g, shock_col.b, a), 6.0, true)
		draw_arc(Vector2.ZERO, r, aim - cone_half, aim + cone_half, seg,
			Color(1.0, 0.9, 0.7, a * 0.6), 2.5, true)
