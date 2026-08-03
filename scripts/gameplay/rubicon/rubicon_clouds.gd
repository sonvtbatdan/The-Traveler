extends Node2D
class_name RubiconClouds
## 3 soft procedural cloud layers drifting above the Rubicon ground — parallax via world_offset scaled by
## a per-layer factor < 1 (slower apparent motion = reads as farther away). Noise is ONE baked seamless
## NoiseTexture2D shared by all 3 layers (see rubicon_ground.gd for why baked > hand-rolled fbm here) —
## each layer gets visual variety from its own seed_offset/coverage/alpha, not a separate bake.
##
## World-space Node2D, NOT a CanvasLayer (unlike rubicon_ground.gd) — a CanvasLayer can only sit entirely
## behind or entirely in front of the whole main canvas, which would fight with wanting this drawn among the
## other world Node2Ds. So this node instead tracks the camera by setting its own global_position every
## frame (set_world_offset) — the rect stays visually screen-covering, same as before, just via node position
## instead of CanvasLayer. Ordering then falls out of normal add-order/z_index: see rubicon_trees.gd's header
## comment.
##
## Purely a decorative sky-atmosphere layer now — real occlusion of scattered assets against the clouds is
## handled by a separate, actual 3D cloud mesh living in rubicon_trees.gd's shared World3D (depth-tested
## against the assets per-pixel). This 2D parallax layer never needs to interact with assets at all anymore,
## so arena.gd only ever instantiates ONE of these.

const CLOUD_SHADER := preload("res://scripts/gameplay/rubicon/rubicon_clouds.gdshader")
const RubiconTerrainSettings := preload("res://scripts/gameplay/rubicon/rubicon_terrain_settings.gd")
const MARGIN := 220.0
const TEX_SIZE := 1024
const TILE_CYCLES := 16.0   # cycles baked per tile — kept high so wandering inside one tile shows no repeat

# [parallax_factor, uv_scale (1/world-px-per-tile), coverage, max_alpha, seed_offset]
const LAYERS := [
	[0.25, 1.0 / 6000.0, 0.58, 0.16, Vector2(0.0, 0.0)],
	[0.45, 1.0 / 5200.0, 0.52, 0.22, Vector2(900.0, -400.0)],
	[0.70, 1.0 / 4500.0, 0.50, 0.28, Vector2(-500.0, 700.0)],
]

var _rects: Array = []
var _mats: Array = []
var _tex: NoiseTexture2D
var _opacity_mult: float = 1.0
var _brightness_mult: float = 1.0
var _color: Color = RubiconTerrainSettings.DEFAULT_CLOUD_COLOR
var _clumpiness: float = RubiconTerrainSettings.DEFAULT_CLOUD_CLUMPINESS

func _ready() -> void:
	add_to_group("rubicon_clouds")   # so the Terrain Edit panel can find this instance
	_tex = _make_noise_tex()
	for spec: Array in LAYERS:
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = CLOUD_SHADER
		mat.set_shader_parameter("tex_cloud", _tex)
		mat.set_shader_parameter("uv_scale", spec[1])
		mat.set_shader_parameter("coverage", spec[2])
		rect.material = mat
		add_child(rect)
		_rects.append(rect)
		_mats.append(mat)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := RubiconTerrainSettings.load_settings()
	apply_cloud_settings(s["cloud_opacity"], s["cloud_brightness"], s["cloud_color"], s["cloud_clumpiness"])

## Public: called by the Terrain Edit panel (live, on slider/ColorPickerButton change) and by this node's own
## _ready() (persisted settings). `opacity_mult` scales each layer's own base max_alpha; `color` is the base
## cloud tint and `brightness_mult` scales its intensity toward white-out (>1) or grey/black (<1).
## `clumpiness` (0..1) morphs the look from a soft misty veil toward distinct chunky cloud masses with clear
## gaps — see rubicon_clouds.gdshader's header.
func apply_cloud_settings(opacity_mult: float, brightness_mult: float, color: Color, clumpiness: float) -> void:
	_opacity_mult = opacity_mult
	_brightness_mult = brightness_mult
	_color = color
	_clumpiness = clumpiness
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var base_alpha: float = spec[3]
		_mats[i].set_shader_parameter("max_alpha", base_alpha * _opacity_mult)
		_mats[i].set_shader_parameter("cloud_color", _color * _brightness_mult)
		_mats[i].set_shader_parameter("clumpiness", _clumpiness)

func _resize() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = vp_size + Vector2(MARGIN, MARGIN) * 2.0
	for rect: ColorRect in _rects:
		rect.size = sz
		rect.position = sz * -0.5   # centered on this node's own origin (tracks the camera via global_position)
	for mat: ShaderMaterial in _mats:
		mat.set_shader_parameter("rect_size", sz)

func set_world_offset(world_pos: Vector2) -> void:
	global_position = world_pos   # keeps the (screen-covering) rect centered on the camera every frame
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var factor: float = spec[0]
		var seed_off: Vector2 = spec[4]
		_mats[i].set_shader_parameter("world_offset", world_pos * factor + seed_off)

func _make_noise_tex() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = TILE_CYCLES / float(TEX_SIZE)
	n.fractal_octaves = 4
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 77
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex
