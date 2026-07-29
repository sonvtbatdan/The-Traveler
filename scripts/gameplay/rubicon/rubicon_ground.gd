extends CanvasLayer
class_name RubiconGround
## Screen-filling procedural ground for the Rubicon map — blue-grass / dark-sand blotches. Noise is BAKED
## into seamless NoiseTexture2D at load (arena_nebula.gd's proven technique), sampled + tiled in the
## shader via repeat wrap — infinite because the texture is seamless, not because it's computed live.
## Sits on a negative CanvasLayer (screen-space, always covers the viewport) — set_world_offset() shifts
## the CONTENT via a shader uniform each frame, same "rect stays put, uniform scrolls" trick as arena_nebula.

const GROUND_SHADER := preload("res://scripts/gameplay/rubicon/rubicon_ground.gdshader")
const RubiconConfig := preload("res://scripts/gameplay/rubicon/rubicon_config.gd")
const RubiconTerrainSettings := preload("res://scripts/gameplay/rubicon/rubicon_terrain_settings.gd")

const MARGIN := 160.0   # extra px beyond the viewport so a resize/rotation never shows a bare edge
const TEX_SIZE := 1024
const DARKEN_FACTOR := 0.45   # "dark" mottle variant = picked color darkened by this much

# The baked texture tiles every 1/UV_SCALE world px — TILE_CYCLES worth of blotch wavelengths are packed
# into each tile so wandering around inside one tile never shows an obvious repeat; only flying ~4000px in
# one direction would reveal the seam, which reads as "infinite" for a top-down flight map at this speed.
const ZONE_UV_SCALE := 1.0 / 4000.0
const ZONE_TILE_CYCLES := 14.0
const MOTTLE_UV_SCALE := ZONE_UV_SCALE * 5.3
const MOTTLE_TILE_CYCLES := 20.0
const RIVER_UV_SCALE := 1.0 / 4000.0
const RIVER_TILE_CYCLES := 4.0   # 4/4000 = 0.001 world-freq, matching RubiconConfig.RIVER_NOISE_FREQ

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	add_to_group("rubicon_ground")   # so the Terrain Edit panel can find this instance
	layer = -10
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	_mat.set_shader_parameter("tex_zone", _make_noise_tex(ZONE_TILE_CYCLES, 4, 11))
	_mat.set_shader_parameter("tex_mottle", _make_noise_tex(MOTTLE_TILE_CYCLES, 3, 47))
	_mat.set_shader_parameter("tex_river", _make_noise_tex(RIVER_TILE_CYCLES, 3, 5))
	_mat.set_shader_parameter("zone_uv_scale", ZONE_UV_SCALE)
	_mat.set_shader_parameter("mottle_uv_scale", MOTTLE_UV_SCALE)
	_mat.set_shader_parameter("river_uv_scale", RIVER_UV_SCALE)
	_mat.set_shader_parameter("river_level", RubiconConfig.RIVER_LEVEL)
	_mat.set_shader_parameter("blue_threshold", RubiconConfig.BLUE_THRESHOLD)
	_mat.set_shader_parameter("blend_softness", RubiconConfig.BLEND_SOFTNESS)
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := RubiconTerrainSettings.load_settings()
	apply_terrain_colors(s["color_a"], s["color_b"])
	apply_river_width(s["river_width"])

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). Half-width of the river band in noise-value space — 0 turns rivers off entirely.
func apply_river_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_width", width)

## Public: called by the Terrain Edit panel (live, on ColorPickerButton change) and by this node's own
## _ready() (persisted settings). `color_a` = "blue" grass zone, `color_b` = "sand" zone — the shader's own
## 4-color mottle (dark/light per zone) is derived here so the panel only needs 2 pickers.
func apply_terrain_colors(color_a: Color, color_b: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("col_blue_light", color_a)
	_mat.set_shader_parameter("col_blue_dark", _darken(color_a))
	_mat.set_shader_parameter("col_sand_light", color_b)
	_mat.set_shader_parameter("col_sand_dark", _darken(color_b))

func _darken(c: Color) -> Color:
	return Color(c.r * DARKEN_FACTOR, c.g * DARKEN_FACTOR, c.b * DARKEN_FACTOR, 1.0)

func _resize() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = vp_size + Vector2(MARGIN, MARGIN) * 2.0
	_rect.size = sz
	_rect.position = Vector2(-MARGIN, -MARGIN)
	_mat.set_shader_parameter("rect_size", sz)

func set_world_offset(world_pos: Vector2) -> void:
	_mat.set_shader_parameter("world_offset", world_pos)

## Bake one seamless noise texture (mirrors arena_nebula._make_noise_tex). `freq_cycles` = roughly how many
## full noise wavelengths fit across the texture — kept low (2-4) for big soft blotches.
func _make_noise_tex(freq_cycles: float, octaves: int, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq_cycles / float(TEX_SIZE)
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_v
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex
