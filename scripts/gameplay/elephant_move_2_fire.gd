extends Node2D
class_name ElephantMove2Fire
## Stylized cel-fire VFX for the Elephant's M2 attack. ONE polar quad (MeshInstance2D + QuadMesh +
## ShaderMaterial elephant_move_2_fire.gdshader) centred on the fire-field origin; the shader draws the
## radial jet spoke + the coiling ring together, clipped to `sweep`. Normal alpha blend keeps the dark
## cel outline visible. The boss (arena_elephant.gd) owns the geometry/timing/collision and drives this
## node each frame via set_frame(); this node is purely visual. One instance per active fire field.

const SHADER_PATH := "res://scripts/gameplay/elephant_move_2_fire.gdshader"

# ── TUNABLES ─────────────────────────────────────────────────────────────────────
# Colours
@export var core_color        := Color(1.0, 0.957, 0.753)   # #fff4c0 pale core
@export var body_color        := Color(1.0, 0.824, 0.290)   # yellow
@export var body_orange_color := Color(1.0, 0.541, 0.118)   # #ff8a1e
@export var outline_color     := Color(0.776, 0.227, 0.078) # #c63a14 dark rim
# Geometry (normalised; quad half-size = 1, ring band at ring_frac)
@export var ring_frac      := 0.80    # also sizes the quad: half-size = radius / ring_frac
@export var band_half      := 0.085   # half-thickness of the fire band
@export var jet_half_angle := 0.30    # radians: angular half-width of the jet spoke
# Cel band split (heat fractions, outer→inner)
@export var outline_thickness := 0.16
@export var orange_share      := 0.30
@export var yellow_share      := 0.28
# Flame breakup / motion
@export var tongue_height      := 0.7
@export var tongue_density     := 16.0
@export var tongue_lean        := 0.6
@export var noise_scale        := 3.0
@export var noise_scroll_speed := 1.3
@export var flicker_speed      := 24.0
@export var flicker_amount     := 0.12
@export var overall_intensity  := 1.0
# Optional embers (CPUParticles2D, matches the project's gun_system plume pattern)
@export var ember_enabled := false
@export var ember_rate    := 28.0

var _quad: MeshInstance2D = null
var _mat: ShaderMaterial = null
var _embers: CPUParticles2D = null
var _radius: float = 1.0

func _ready() -> void:
	z_index = 1   # above the arena floor, just under the boss body (z_index 2)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_quad = MeshInstance2D.new()
	_quad.mesh = mesh
	_quad.material = _mat
	add_child(_quad)
	_apply_static_uniforms()
	if ember_enabled:
		_build_embers()

## Place + size the field. center = world origin of the coil, radius = FIRE_RING_RADIUS (world px).
func setup(center: Vector2, radius: float) -> void:
	global_position = center
	_radius = maxf(1.0, radius)
	var half := _radius / maxf(0.05, ring_frac)   # world half-size of the quad
	_quad.scale = Vector2(half * 2.0, half * 2.0)

## Drive per frame from the boss. aim_angle/sweep in radians, beam_active = jet emitting, alpha = ramp/fade.
func set_frame(aim_angle: float, sweep: float, beam_active: bool, alpha: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("aim_angle", aim_angle)
	_mat.set_shader_parameter("sweep", sweep)
	_mat.set_shader_parameter("beam_active", 1.0 if beam_active else 0.0)
	_mat.set_shader_parameter("activation", clampf(alpha, 0.0, 1.0))
	if _embers != null:
		_embers.emitting = beam_active and ember_enabled

func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.amount = int(maxf(1.0, ember_rate))
	_embers.lifetime = 0.7
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = _radius * 0.6
	_embers.direction = Vector2(0.0, -1.0)
	_embers.spread = 40.0
	_embers.gravity = Vector2(0.0, -60.0)   # drift slightly up
	_embers.initial_velocity_min = 30.0
	_embers.initial_velocity_max = 90.0
	_embers.scale_amount_min = 1.0
	_embers.scale_amount_max = 2.5
	_embers.color = body_orange_color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(body_color.r, body_color.g, body_color.b, 1.0))
	ramp.set_color(1, Color(outline_color.r, outline_color.g, outline_color.b, 0.0))
	_embers.color_ramp = ramp   # CPUParticles2D.color_ramp is a Gradient
	_embers.emitting = false
	add_child(_embers)

func _apply_static_uniforms() -> void:
	_mat.set_shader_parameter("core_color", core_color)
	_mat.set_shader_parameter("body_color", body_color)
	_mat.set_shader_parameter("body_orange_color", body_orange_color)
	_mat.set_shader_parameter("outline_color", outline_color)
	_mat.set_shader_parameter("ring_frac", ring_frac)
	_mat.set_shader_parameter("band_half", band_half)
	_mat.set_shader_parameter("jet_half_angle", jet_half_angle)
	_mat.set_shader_parameter("outline_thickness", outline_thickness)
	_mat.set_shader_parameter("orange_share", orange_share)
	_mat.set_shader_parameter("yellow_share", yellow_share)
	_mat.set_shader_parameter("tongue_height", tongue_height)
	_mat.set_shader_parameter("tongue_density", tongue_density)
	_mat.set_shader_parameter("tongue_lean", tongue_lean)
	_mat.set_shader_parameter("noise_scale", noise_scale)
	_mat.set_shader_parameter("noise_scroll_speed", noise_scroll_speed)
	_mat.set_shader_parameter("flicker_speed", flicker_speed)
	_mat.set_shader_parameter("flicker_amount", flicker_amount)
	_mat.set_shader_parameter("overall_intensity", overall_intensity)
	_mat.set_shader_parameter("activation", 0.0)
	_mat.set_shader_parameter("sweep", 0.0)
	_mat.set_shader_parameter("aim_angle", 0.0)
	_mat.set_shader_parameter("beam_active", 1.0)
