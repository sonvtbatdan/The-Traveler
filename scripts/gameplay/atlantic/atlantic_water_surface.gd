extends CanvasLayer
class_name AtlanticWaterSurface
## World-locked "underwater" overlay for the Atlantic map — continuous whole-terrain refraction + procedural
## caustic sparkle, on request: "layer sóng nước làm biến dạng nhẹ toàn bộ không gian, có ánh sáng lấp lánh".
## Same fullscreen-ColorRect-reads-hint_screen_texture technique as scripts/gameplay/fx/z_slash_distort.gdshader
## / explosion_shockwave.gdshader, but always-on, and its noise fields are sampled in WORLD space via
## set_world_offset() (same trick atlantic_ground.gd uses) so the ripple/sparkle pattern is pinned to the
## terrain and pans as the player moves, instead of sitting fixed on the screen — see the shader's own header
## for the 2026-08-08 fix ("Ripple đính kèm theo terrain, không di chuyển theo người chơi").
##
## Sits BELOW the base/default canvas (layer 0, where the ship/enemies/plumes live) — layer -1, just above the
## ground CanvasLayer (-10) — so it only warps the ground/current, never the ship, enemies, or bubble/whirlpool
## particles (2026-08-08 fix: "Z_index của ripple thấp hơn player và enemies").

const SHADER := preload("res://scripts/gameplay/atlantic/atlantic_water_surface.gdshader")
const TEX_SIZE := 512

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	add_to_group("atlantic_water_surface")   # so the Terrain Edit panel can find this instance
	layer = -1   # above the ground CanvasLayer (-10), below the base canvas (0 = ship/enemies/plumes) and HUD — see class header
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("tex_distort", _make_noise_tex(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.DISTANCE_EUCLIDEAN, 3, 71))
	_mat.set_shader_parameter("tex_caustic_a", _make_noise_tex(FastNoiseLite.TYPE_CELLULAR, FastNoiseLite.DISTANCE_EUCLIDEAN, 6, 81))
	_mat.set_shader_parameter("tex_caustic_b", _make_noise_tex(FastNoiseLite.TYPE_CELLULAR, FastNoiseLite.DISTANCE_EUCLIDEAN, 6, 89))
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := AtlanticTerrainSettingsScript.load_settings()
	apply_water_surface_settings(s["water_distort_strength"], s["water_distort_speed"],
		s["water_sparkle_intensity"], s["water_sparkle_color"], s["water_sparkle_speed"])

const AtlanticTerrainSettingsScript := preload("res://scripts/gameplay/atlantic/atlantic_terrain_settings.gd")

## Public: called every frame by arena.gd with the camera's world-space focus (mirrors atlantic_ground.gd's own
## set_world_offset) — keeps the noise fields pinned to the terrain instead of the screen.
func set_world_offset(world_pos: Vector2) -> void:
	if _mat != null:
		_mat.set_shader_parameter("world_offset", world_pos)

func _resize() -> void:
	if _mat != null:
		_mat.set_shader_parameter("rect_size", get_viewport().get_visible_rect().size)

## Public: called by the Terrain Edit panel (live) and by this node's own _ready() (persisted settings).
func apply_water_surface_settings(distort_strength: float, distort_speed: float, sparkle_intensity: float, sparkle_color: Color, sparkle_speed: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("distort_strength", distort_strength)
	_mat.set_shader_parameter("distort_speed", distort_speed)
	_mat.set_shader_parameter("sparkle_intensity", sparkle_intensity)
	_mat.set_shader_parameter("sparkle_color", sparkle_color)
	_mat.set_shader_parameter("sparkle_speed", sparkle_speed)

## Bakes one seamless noise texture. `distance_func` is only read when noise_type is CELLULAR — the caustic
## fields want smooth ROUND Voronoi cells (DISTANCE_EUCLIDEAN), unlike atlantic_ground.gd's Manhattan-faceted
## current-scour detail field.
func _make_noise_tex(noise_type: FastNoiseLite.NoiseType, distance_func: FastNoiseLite.CellularDistanceFunction, freq_cycles: float, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = noise_type
	n.frequency = freq_cycles / float(TEX_SIZE)
	n.seed = seed_v
	if noise_type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_distance_function = distance_func
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex
