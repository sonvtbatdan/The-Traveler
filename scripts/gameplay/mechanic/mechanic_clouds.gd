extends Node2D
class_name MechanicClouds
## 3 soft procedural cloud layers drifting above the Mechanic ground — originally a verbatim port of
## electric_clouds.gd's parallax technique (see that file's header for the full World2D-vs-CanvasLayer
## rationale), REDESIGNED 2026-08-19 same day on request: "cloud là asset thuộc về terrain nên sẽ di chuyển
## tương đối so với terrain do gió thổi, chứ ko di chuyển theo player" (cloud is a terrain-owned asset, so it
## moves relative to the TERRAIN via wind, not by following the player). The original per-layer
## `parallax_factor` (0.25/0.45/0.70, one screen-space camera-parallax depth illusion) meant the cloud pattern
## only PARTLY canceled camera motion, so relative to the ground it visibly drifted along with however the
## player moved — exactly the bug reported. Fixed by using the SAME technique the ground already uses
## (world_offset = world_pos, no fractional scaling): every layer's noise sampling now shifts by the FULL
## camera movement, so the pattern is 100% static relative to the world/ground — the 3 layers still differ in
## scale/coverage/alpha for visual richness, they just no longer scroll at different relative rates.
##
## WIND: `_wind_accum` is the ONLY thing that moves the cloud pattern relative to the ground now — a direct
## strength (px/s) + angle (°) pair (NOT rolled random like mechanic_plumes.gd's old wind system — direct
## control here, not chance), continuously accumulated in _process() and added equally to all 3 layers (wind
## blows the whole sky at once).

const CLOUD_SHADER := preload("res://scripts/gameplay/mechanic/mechanic_clouds.gdshader")
const MechanicTerrainSettings := preload("res://scripts/gameplay/mechanic/mechanic_terrain_settings.gd")
const MARGIN := 220.0
const TEX_SIZE := 1024
const TILE_CYCLES := 16.0

# [uv_scale (1/world-px-per-tile), coverage, max_alpha, seed_offset] — no parallax_factor any more, see header.
const LAYERS := [
	[1.0 / 6000.0, 0.58, 0.16, Vector2(0.0, 0.0)],
	[1.0 / 5200.0, 0.52, 0.22, Vector2(900.0, -400.0)],
	[1.0 / 4500.0, 0.50, 0.28, Vector2(-500.0, 700.0)],
]

var _rects: Array = []
var _mats: Array = []
var _tex: NoiseTexture2D
var _opacity_mult: float = 1.0
var _brightness_mult: float = 1.0
var _color: Color = MechanicTerrainSettings.DEFAULT_CLOUD_COLOR
var _clumpiness: float = MechanicTerrainSettings.DEFAULT_CLOUD_CLUMPINESS

var _wind_strength: float = MechanicTerrainSettings.DEFAULT_CLOUD_WIND_STRENGTH   # px/s
var _wind_angle_deg: float = MechanicTerrainSettings.DEFAULT_CLOUD_WIND_ANGLE_DEG
var _wind_accum: Vector2 = Vector2.ZERO   # continuously-advancing drift offset — see _process()

func _ready() -> void:
	add_to_group("mechanic_clouds")   # so the Terrain Edit panel can find this instance
	_tex = _make_noise_tex()
	for spec: Array in LAYERS:
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = CLOUD_SHADER
		mat.set_shader_parameter("tex_cloud", _tex)
		mat.set_shader_parameter("uv_scale", spec[0])
		mat.set_shader_parameter("coverage", spec[1])
		rect.material = mat
		add_child(rect)
		_rects.append(rect)
		_mats.append(mat)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := MechanicTerrainSettings.load_settings()
	apply_cloud_settings(s["cloud_opacity"], s["cloud_brightness"], s["cloud_color"], s["cloud_clumpiness"])
	apply_wind_settings(s["cloud_wind_strength"], s["cloud_wind_angle_deg"])

func apply_cloud_settings(opacity_mult: float, brightness_mult: float, color: Color, clumpiness: float) -> void:
	_opacity_mult = opacity_mult
	_brightness_mult = brightness_mult
	_color = color
	_clumpiness = clumpiness
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var base_alpha: float = spec[2]
		_mats[i].set_shader_parameter("max_alpha", base_alpha * _opacity_mult)
		_mats[i].set_shader_parameter("cloud_color", _color * _brightness_mult)
		_mats[i].set_shader_parameter("clumpiness", _clumpiness)

## Public: called by the Terrain Edit panel's Cloud tab (live, on slider change) and by this node's own
## _ready() (persisted settings). `strength` is px/s the wind drifts the clouds; `angle_deg` is its compass
## direction (0 = +X/east, 90 = +Y/south — screen-space, matches every other angle slider in this codebase).
## Purely live — no regen needed, just changes how fast/which way _wind_accum grows from here on.
func apply_wind_settings(strength: float, angle_deg: float) -> void:
	_wind_strength = strength
	_wind_angle_deg = angle_deg

## Advances the wind drift every frame, independent of camera movement — see this file's header.
func _process(delta: float) -> void:
	if _wind_strength == 0.0:
		return
	var rad := deg_to_rad(_wind_angle_deg)
	_wind_accum += Vector2(cos(rad), sin(rad)) * _wind_strength * delta

func _resize() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = vp_size + Vector2(MARGIN, MARGIN) * 2.0
	for rect: ColorRect in _rects:
		rect.size = sz
		rect.position = sz * -0.5
	for mat: ShaderMaterial in _mats:
		mat.set_shader_parameter("rect_size", sz)

## The ColorRects stay screen-anchored (global_position tracks the camera every frame, same as
## mechanic_ground.gd's CanvasLayer trick, just via node position instead of a shader rect uniform) while the
## SAMPLED noise content shifts by the FULL world_pos — not a fraction of it — so the pattern is 100% static
## relative to the ground/world; only _wind_accum (see header) moves it from here on.
func set_world_offset(world_pos: Vector2) -> void:
	global_position = world_pos
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var seed_off: Vector2 = spec[3]
		_mats[i].set_shader_parameter("world_offset", world_pos + seed_off + _wind_accum)

func _make_noise_tex() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = TILE_CYCLES / float(TEX_SIZE)
	n.fractal_octaves = 4
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 88   # different from Electric's 77 so the two maps' clouds don't look pixel-identical
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex
