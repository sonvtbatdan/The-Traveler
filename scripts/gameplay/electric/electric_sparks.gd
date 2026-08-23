extends Node2D
class_name ElectricSparks
## Small glowing dust-mote/firefly sparks drifting through the Electric jungle — a lightweight atmospheric
## flourish, independently tunable via the Light Edit panel (electric_light_edit.gd's Spark Amount/Speed/Size/
## Direction/Color/Brightness sliders). Not tied to any actual light source (this map's 2D layers stay unlit —
## see electric_ground.gdshader's header).
##
## World-space Node2D (not a CanvasLayer), same "tracks the camera via its own global_position every frame"
## convention as electric_clouds.gd. Uses a single CPUParticles2D with local_coords=false so already-emitted
## sparks stay anchored to their own world position (drifting independently) even as this node's position
## keeps recentering on the camera to seed new spawns near wherever the player currently is — NOT particles
## rigidly glued to the screen/camera.

const ElectricTerrainSettings := preload("res://scripts/gameplay/electric/electric_terrain_settings.gd")
const MARGIN := 200.0    # spawn rect extends this far beyond the viewport so drift never reveals a bare edge
const LIFETIME := 5.0
const SPREAD_DEG := 70.0   # angular scatter around the drift direction, not user-tunable (kept fixed)
const SPEED_VARIANCE := 3.0   # +/- px/s band around the exact `speed` setting (keeps 0 == truly stationary)
const SIZE_VARIANCE_PX := 5.0   # +/- 5px band around the exact `size_px` slider value (fixed px, not a %)

const SPARK_TEX_PX := 24.0   # _make_spark_tex's native width/height — CPUParticles2D's scale_amount is a
                              # multiplier on this, so size_px / SPARK_TEX_PX converts a target on-screen
                              # pixel size into the scale value the node actually needs

var _particles: CPUParticles2D

func _ready() -> void:
	add_to_group("electric_sparks")   # so the Light Edit panel can find this instance
	_particles = CPUParticles2D.new()
	_particles.texture = _make_spark_tex()
	_particles.local_coords = false   # decouples already-emitted sparks from this node's later position changes
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.lifetime = LIFETIME
	_particles.lifetime_randomness = 0.4
	_particles.gravity = Vector2.ZERO   # CPUParticles2D defaults to a real downward gravity (98 px/s²) — left
	                                     # at that default, it overpowers the small initial_velocity and every
	                                     # spark ends up falling straight down regardless of `direction`
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

	var s := ElectricTerrainSettings.load_settings()
	apply_spark_settings(s["spark_amount"], s["spark_color"], s["spark_speed"], s["spark_size"], s["spark_direction_deg"], s["spark_brightness"], s["spark_opacity"])

func _resize() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_particles.emission_rect_extents = vp * 0.5 + Vector2(MARGIN, MARGIN)

## Call every frame with the camera's world-space focus — mirrors electric_clouds.gd's set_world_offset.
func set_world_offset(world_pos: Vector2) -> void:
	global_position = world_pos

## Public: called by the Light Edit panel (live, on slider/ColorPickerButton change) and by this node's own
## _ready() (persisted settings). `amount` is the spark count (0 turns them off entirely); `speed` is a DIRECT
## px/s value (0 == truly stationary, 100 == ~100px/s — see SPEED_VARIANCE for the small +/- band around it);
## `size_px` is a DIRECT on-screen pixel size (0 == invisible, 100 == ~100px, +/- SIZE_VARIANCE_PX per spark —
## see SPARK_TEX_PX for how that's converted to CPUParticles2D's own scale_amount); `direction_deg` is a
## screen-angle (0=right/horizontal, 90=down, 180=left, 270=up — Y+ is down) the sparks drift toward;
## `color`/`brightness` set their tint (brightness can exceed 1 for an HDR glow via the arena's existing bloom
## pipeline — see arena.gd's _make_glow_world_env, glow_hdr_threshold 1.0 — multiplied into rgb only); `opacity`
## is an overall max-alpha cap (0 = invisible, 1 = full) layered on top of the fade-in/out color_ramp.
func apply_spark_settings(amount: float, color: Color, speed: float, size_px: float, direction_deg: float, brightness: float, opacity: float) -> void:
	var n := maxi(0, int(round(amount)))
	_particles.emitting = n > 0
	_particles.amount = maxi(1, n)   # CPUParticles2D rejects amount=0 — emitting=false already hides them
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
