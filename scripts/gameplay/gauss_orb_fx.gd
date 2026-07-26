extends Node2D
## Dumb draw node for the Gauss plasma ball — arena_weapons.gd owns position/lifetime/damage and just
## pushes `diameter` + world position each tick (same "dumb node" pattern as lasgun_ani_5's children).
## Used for BOTH the small projectile orb AND the bigger impact-explosion burst (same shader, arena_weapons
## just drives it to a larger diameter + intro/outro alpha fade for the explosion) — same procedural plasma
## look at any size, replacing both the 24-frame gauss24_XX.png orb flipbook and the 12-frame explosion
## flipbook. `.modulate` still works for the Orb of Annihilation red recolor (Node2D is a CanvasItem).

const OrbShader := preload("res://scripts/gameplay/gauss_orb_fx.gdshader")

@export var time_scale := 1.0   # explosion instance sets this ~10x higher so its internal crackle/flicker reads as a frantic burst, not the calm flying-orb pace
@export var spin_rps := 3.0     # sprite self-rotation (revolutions/sec) — the whole plasma ball spins while flying AND exploding

@export_group("Size pulse")
@export var size_pulse_enabled := true   # small flying orb breathes 80-100% size; the explosion (own pop-in/fade already) disables this
@export var size_pulse_min := 0.8
@export var size_pulse_max := 1.0
@export var size_pulse_period := 0.2    # seconds per full small->big->small cycle

@export_group("Look")
@export var cell_freq := 5.0
@export var cell_edge_width := 0.14
@export var crack_mix := 0.55
@export var warp_amount := 0.4
@export var warp_speed := 0.5
@export var crack_jitter_rate := 11.0
@export var crack_dim := 0.32
@export var flash_rate := 26.0
@export var arc_flash_chance := 0.09
@export var arc_flash_boost := 6.0
@export var sphere_radius := 0.78
@export var rim_width := 0.04
@export var rim_boost := 1.4
@export var rim_jitter := 0.02
@export var core_radius := 0.20
@export var core_jitter := 0.12
@export var spike_count := 18.0
@export var spike_sharpness := 2.6
@export var spike_len := 0.16
@export var spike_min := 0.02
@export var halo_softness := 0.38
@export var halo_amount := 0.6
@export var ambient_falloff := 1.6
@export var flicker_amount := 0.08
@export var flicker_speed := 14.0

@export_group("Palette")
@export var core_color := Color(1.0, 1.0, 1.0)
@export var body_color := Color(0.05, 0.15, 0.55)
@export var edge_color := Color(0.35, 0.75, 1.0)
@export var rim_color  := Color(0.4, 0.85, 1.0)
@export var halo_color := Color(0.75, 0.85, 1.0)

var diameter := 10.0

func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = OrbShader
	m.set_shader_parameter("seed", randf() * 1000.0)
	m.set_shader_parameter("time_scale", time_scale)
	m.set_shader_parameter("cell_freq", cell_freq)
	m.set_shader_parameter("cell_edge_width", cell_edge_width)
	m.set_shader_parameter("crack_mix", crack_mix)
	m.set_shader_parameter("warp_amount", warp_amount)
	m.set_shader_parameter("warp_speed", warp_speed)
	m.set_shader_parameter("crack_jitter_rate", crack_jitter_rate)
	m.set_shader_parameter("crack_dim", crack_dim)
	m.set_shader_parameter("flash_rate", flash_rate)
	m.set_shader_parameter("arc_flash_chance", arc_flash_chance)
	m.set_shader_parameter("arc_flash_boost", arc_flash_boost)
	m.set_shader_parameter("sphere_radius", sphere_radius)
	m.set_shader_parameter("rim_width", rim_width)
	m.set_shader_parameter("rim_boost", rim_boost)
	m.set_shader_parameter("rim_jitter", rim_jitter)
	m.set_shader_parameter("core_radius", core_radius)
	m.set_shader_parameter("core_jitter", core_jitter)
	m.set_shader_parameter("spike_count", spike_count)
	m.set_shader_parameter("spike_sharpness", spike_sharpness)
	m.set_shader_parameter("spike_len", spike_len)
	m.set_shader_parameter("spike_min", spike_min)
	m.set_shader_parameter("halo_softness", halo_softness)
	m.set_shader_parameter("halo_amount", halo_amount)
	m.set_shader_parameter("ambient_falloff", ambient_falloff)
	m.set_shader_parameter("flicker_amount", flicker_amount)
	m.set_shader_parameter("flicker_speed", flicker_speed)
	m.set_shader_parameter("core_color", core_color)
	m.set_shader_parameter("body_color", body_color)
	m.set_shader_parameter("edge_color", edge_color)
	m.set_shader_parameter("rim_color", rim_color)
	m.set_shader_parameter("halo_color", halo_color)
	material = m

## Self-spin: rotate the whole node (the shader pattern lives in the rect's UVs, so the spikes/rim spin with it).
## arena_weapons pushes only position + diameter each tick (never rotation), so this isn't clobbered.
func _process(delta: float) -> void:
	if spin_rps != 0.0:
		rotation += TAU * spin_rps * delta

func _draw() -> void:
	if diameter <= 0.0:
		return
	var pulse := 1.0
	if size_pulse_enabled:
		var phase := fmod(Time.get_ticks_msec() / 1000.0, size_pulse_period) / size_pulse_period
		pulse = lerpf(size_pulse_min, size_pulse_max, 0.5 + 0.5 * sin(phase * TAU))
	var d := diameter * pulse
	var h := d * 0.5
	draw_rect(Rect2(Vector2(-h, -h), Vector2(d, d)), Color.WHITE)
