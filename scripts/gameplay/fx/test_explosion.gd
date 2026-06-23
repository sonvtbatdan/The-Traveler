extends Node2D
## Test/preview driver for the Explosion FX primitive (counterpart to scenes/test_fire.tscn for DynamicFire).
## Explosion is one-shot + auto-frees, and its HDR core only blooms under a glow WorldEnvironment — so this
## driver supplies both, PLUS a white line grid so the screen-space shockwave DISTORTION is visible (it ripples
## the background; on a flat colour you'd see nothing). Spawns an Explosion at the centre, replays every
## replay_every seconds and on "ui_accept" (Space/Enter). Run this scene directly (F6).

const Explosion := preload("res://scripts/gameplay/fx/explosion.gd")

@export var replay_every: float = 2.0
@export var size_px: float = 160.0
@export var grid_step: float = 40.0
@export var grid_extent: float = 1600.0

var _t: float = 0.0

func _ready() -> void:
	add_child(_make_glow_world_env())
	queue_redraw()
	_spawn()

func _process(delta: float) -> void:
	_t += delta
	if _t >= replay_every:
		_t = 0.0
		_spawn()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_t = 0.0
		_spawn()

func _spawn() -> void:
	var ex: Node2D = Explosion.new()
	add_child(ex)
	ex.call("setup", Vector2.ZERO, size_px)

## Dark background + white line grid. Drawn in the root's _draw → renders BEHIND the spawned explosions (children)
## and feeds the shockwave's screen-texture sample, so the distortion ring visibly warps the grid lines.
func _draw() -> void:
	var e := grid_extent
	draw_rect(Rect2(-e, -e, e * 2.0, e * 2.0), Color(0.05, 0.05, 0.07))
	var col := Color(1.0, 1.0, 1.0, 0.22)
	var x := -e
	while x <= e:
		draw_line(Vector2(x, -e), Vector2(x, e), col, 1.0)
		x += grid_step
	var y := -e
	while y <= e:
		draw_line(Vector2(-e, y), Vector2(e, y), col, 1.0)
		y += grid_step

## Same glow/bloom env as arena.gd._make_glow_world_env — only HDR (>1) pixels bloom (the hot explosion core).
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
