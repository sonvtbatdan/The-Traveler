extends Node2D
## Test/preview driver for the clap-mech (ClapMech) — counterpart to test_slash.tscn / test_explosion.tscn.
## Loops the hand-clap so the animation + hands-only after-image + 120° shockwave can be eyeballed in
## isolation. Replays every `replay_every`, on "ui_accept" (Space/Enter), and dumps the bright fists into a
## glow WorldEnvironment so the clap reads punchy. Run directly with F6.

const ClapMech := preload("res://scripts/gameplay/fx/clap_mech.gd")

@export var replay_every: float = 1.1
@export var grid_step: float = 40.0
@export var grid_extent: float = 1600.0

var _mech: Node2D = null
var _cooldown: float = 0.0

func _ready() -> void:
	add_child(_make_glow_world_env())
	_mech = ClapMech.new()
	_mech.set("display_width", 220.0)   # big so the clap is easy to watch
	_mech.set("facing", -PI * 0.5)      # claps upward
	add_child(_mech)
	_mech.call("play_clap")
	queue_redraw()

func _process(delta: float) -> void:
	if not _mech.call("is_clapping"):
		_cooldown -= delta
		if _cooldown <= 0.0:
			_cooldown = replay_every
			_mech.call("play_clap")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_mech.call("play_clap")

func _draw() -> void:
	var e := grid_extent
	draw_rect(Rect2(-e, -e, e * 2.0, e * 2.0), Color(0.05, 0.05, 0.07))
	var col := Color(1.0, 1.0, 1.0, 0.18)
	var x := -e
	while x <= e:
		draw_line(Vector2(x, -e), Vector2(x, e), col, 1.0)
		x += grid_step
	var y := -e
	while y <= e:
		draw_line(Vector2(-e, y), Vector2(e, y), col, 1.0)
		y += grid_step

func _make_glow_world_env() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.15
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	return we
