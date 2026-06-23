extends Node2D
## Test/preview driver for the Z-Sword slash (ZSlash) — counterpart to test_fire.tscn / test_explosion.tscn.
## ZSlash is driven each frame across a sweep (it isn't self-contained), and its bloom needs a glow
## WorldEnvironment while its layer-4 distortion needs background DETAIL to be visible — so this driver supplies
## both: a glow env + a white line grid. It plays a full sweep, replays every `replay_every`, and on "ui_accept"
## (Space/Enter). Run this scene directly (F6).

const ZSlash := preload("res://scripts/gameplay/fx/z_slash.gd")

@export var sweep_time: float = 0.6      # matches ZSWORD_SWEEP_TIME
@export var reach: float = 175.0         # slash radius
@export var replay_every: float = 1.6    # pause between sweeps
@export var grid_step: float = 40.0
@export var grid_extent: float = 1600.0

var _slash: Node2D = null
var _sweeping: bool = false
var _t: float = 0.0
var _cooldown: float = 0.0
var _start_ang: float = -1.2
var _sparked: int = 0

func _ready() -> void:
	add_child(_make_glow_world_env())
	queue_redraw()
	_slash = ZSlash.new()
	add_child(_slash)
	_begin_sweep()

func _process(delta: float) -> void:
	if _sweeping:
		_t += delta
		var lead := _start_ang + TAU * (_t / sweep_time)
		_slash.call("set_sweep", Vector2.ZERO, reach, _start_ang, lead)
		# a couple of impact sparks partway through, to show the hit feedback
		if _sparked < 2 and _t > sweep_time * (0.35 + 0.3 * float(_sparked)):
			_sparked += 1
			var dl := Vector2(cos(lead), sin(lead))
			_slash.call("add_spark", dl * reach)
		if _t >= sweep_time:
			_sweeping = false
			_cooldown = replay_every
			_slash.call("fade_out")
	else:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_begin_sweep()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_begin_sweep()

func _begin_sweep() -> void:
	_sweeping = true
	_t = 0.0
	_sparked = 0
	# vary the start angle each sweep so it's not identical every time
	_start_ang = -1.2 + float((Engine.get_process_frames() % 8)) * 0.3

## Dark background + white grid (feeds the distortion's screen-texture sample) + a ship marker at the centre.
func _draw() -> void:
	var e := grid_extent
	draw_rect(Rect2(-e, -e, e * 2.0, e * 2.0), Color(0.05, 0.05, 0.07))
	var col := Color(1.0, 1.0, 1.0, 0.20)
	var x := -e
	while x <= e:
		draw_line(Vector2(x, -e), Vector2(x, e), col, 1.0)
		x += grid_step
	var y := -e
	while y <= e:
		draw_line(Vector2(-e, y), Vector2(e, y), col, 1.0)
		y += grid_step
	draw_rect(Rect2(-14, -14, 28, 28), Color(0.5, 0.4, 0.3))   # ship marker at the slash centre

## Same glow/bloom env as arena.gd._make_glow_world_env — only HDR (>1) pixels bloom (the slash's hot core/edge).
func _make_glow_world_env() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 1.0
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	return we
