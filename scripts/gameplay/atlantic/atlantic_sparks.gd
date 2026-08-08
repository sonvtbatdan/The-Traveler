extends Node2D
class_name AtlanticSparks
## Small glowing bioluminescent motes/plankton drifting through the Atlantic water — verbatim port of
## volcanic/volcanic_sparks.gd (see that file's header for the full rationale — single world-space
## CPUParticles2D, independently tunable via the Light Edit panel). Only the default tint/speed/direction
## (AtlanticTerrainSettings' DEFAULT_SPARK_* — cyan-teal, slow drift) differ from Volcanic's rising-ember
## defaults.

const AtlanticTerrainSettings := preload("res://scripts/gameplay/atlantic/atlantic_terrain_settings.gd")
const MARGIN := 200.0
const LIFETIME := 5.0
const SPREAD_DEG := 70.0
const SPEED_VARIANCE := 3.0
const SIZE_VARIANCE_PX := 5.0

const SPARK_TEX_PX := 24.0

var _particles: CPUParticles2D

func _ready() -> void:
	add_to_group("atlantic_sparks")   # so the Light Edit panel can find this instance
	_particles = CPUParticles2D.new()
	_particles.texture = _make_spark_tex()
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.lifetime = LIFETIME
	_particles.lifetime_randomness = 0.4
	_particles.gravity = Vector2.ZERO
	_particles.spread = SPREAD_DEG
	_particles.angular_velocity_min = -30.0
	_particles.angular_velocity_max = 30.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	_particles.color_ramp = ramp
	add_child(_particles)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := AtlanticTerrainSettings.load_settings()
	apply_spark_settings(s["spark_amount"], s["spark_color"], s["spark_speed"], s["spark_size"], s["spark_direction_deg"], s["spark_brightness"], s["spark_opacity"])

func _resize() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_particles.emission_rect_extents = vp * 0.5 + Vector2(MARGIN, MARGIN)

## Call every frame with the camera's world-space focus — mirrors atlantic_clouds.gd's set_world_offset.
func set_world_offset(world_pos: Vector2) -> void:
	global_position = world_pos

## Public: called by the Light Edit panel (live) and by this node's own _ready() (persisted settings) — see
## volcanic_sparks.gd's apply_spark_settings for full parameter semantics.
func apply_spark_settings(amount: float, color: Color, speed: float, size_px: float, direction_deg: float, brightness: float, opacity: float) -> void:
	var n := maxi(0, int(round(amount)))
	_particles.emitting = n > 0
	_particles.amount = maxi(1, n)
	_particles.initial_velocity_min = maxf(0.0, speed - SPEED_VARIANCE)
	_particles.initial_velocity_max = speed + SPEED_VARIANCE
	_particles.scale_amount_min = maxf(0.0, size_px - SIZE_VARIANCE_PX) / SPARK_TEX_PX
	_particles.scale_amount_max = (size_px + SIZE_VARIANCE_PX) / SPARK_TEX_PX
	var rad := deg_to_rad(direction_deg)
	_particles.direction = Vector2(cos(rad), sin(rad))
	_particles.color = Color(color.r * brightness, color.g * brightness, color.b * brightness, opacity)

func _make_spark_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 24
	tex.height = 24
	return tex
