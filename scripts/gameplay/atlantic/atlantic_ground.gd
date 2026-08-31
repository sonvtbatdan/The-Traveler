extends CanvasLayer
class_name AtlanticGround
## Screen-filling ground for the Atlantic map — real top-down seabed/ruin-floor PHOTOS (assets/map/atlantic/
## maptile/<set>/, user-supplied "canopy" textures), tinted per-zone and tiled at world-scale. Mirrors
## volcanic/volcanic_ground.gd's overall technique exactly (baked seamless NoiseTexture2D level-sets, sampled +
## tiled via repeat wrap in atlantic_ground.gdshader), just re-themed: the "river" fields stay a winding
## CURRENT channel instead of a lava flow — see AtlanticNoise's header for the full rationale.
##
## Sits on a negative CanvasLayer (screen-space, always covers the viewport) — set_world_offset() shifts the
## CONTENT via a shader uniform each frame, same trick as volcanic_ground.gd/electric_ground.gd.

const GROUND_SHADER := preload("res://scripts/gameplay/atlantic/atlantic_ground.gdshader")
const AtlanticConfig := preload("res://scripts/gameplay/atlantic/atlantic_config.gd")
const AtlanticTerrainSettings := preload("res://scripts/gameplay/atlantic/atlantic_terrain_settings.gd")
const AtlanticAssetScan := preload("res://scripts/gameplay/atlantic/atlantic_asset_scan.gd")

const MARGIN := 160.0
const TEX_SIZE := 1024

const GROUND_TINT_STRENGTH := 0.5
const GROUND_SPECULAR_POWER := 18.0

const ZONE_UV_SCALE := 1.0 / 4000.0
const ZONE_TILE_CYCLES := 14.0
const MOTTLE_UV_SCALE := ZONE_UV_SCALE * 5.3
const MOTTLE_TILE_CYCLES := 20.0
const RIVER_UV_SCALE := 1.0 / 4000.0
const RIVER_TILE_CYCLES := 4.0   # 4/4000 = 0.001 world-freq, matching AtlanticConfig.RIVER_NOISE_FREQ
const RIVER_DETAIL_FREQ_MULT := 7.0    # must match AtlanticNoise.RIVER_DETAIL_FREQ_MULT
const WATER_DARKEN_FACTOR := 0.4

var _rect: ColorRect
var _mat: ShaderMaterial
# Cached copy of the light_dir this function just computed (2026-08-28) - the single "sun" the player ship's
# and VIPER's own key lights orient off via arena_enemy_manager.gd's sun_dir(), instead of each guessing its
# own independent light direction. See sun_dir()'s own doc comment just below.
var _sun_dir: Vector3 = Vector3(0.6, 0.6, 0.6)   # matches the shader uniform's own default
var _neutral_normal_tex: ImageTexture = null

func _ready() -> void:
	add_to_group("atlantic_ground")   # so the Terrain Edit panel can find this instance
	layer = -10
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	_mat.set_shader_parameter("tex_zone", _make_noise_tex(ZONE_TILE_CYCLES, 4, 51))
	_mat.set_shader_parameter("tex_mottle", _make_noise_tex(MOTTLE_TILE_CYCLES, 3, 67))
	_mat.set_shader_parameter("tex_river", _make_noise_tex(RIVER_TILE_CYCLES, 3, 28))
	_mat.set_shader_parameter("tex_river_detail", _make_cellular_detail_tex(RIVER_TILE_CYCLES * RIVER_DETAIL_FREQ_MULT, 33))
	_mat.set_shader_parameter("river_detail_uv_scale", RIVER_UV_SCALE * RIVER_DETAIL_FREQ_MULT)
	_mat.set_shader_parameter("ground_tint_strength", GROUND_TINT_STRENGTH)
	_mat.set_shader_parameter("ground_specular_power", GROUND_SPECULAR_POWER)
	_mat.set_shader_parameter("zone_uv_scale", ZONE_UV_SCALE)
	_mat.set_shader_parameter("mottle_uv_scale", MOTTLE_UV_SCALE)
	_mat.set_shader_parameter("river_uv_scale", RIVER_UV_SCALE)
	_mat.set_shader_parameter("river_level", AtlanticConfig.RIVER_LEVEL)
	_mat.set_shader_parameter("blue_threshold", AtlanticConfig.BLUE_THRESHOLD)
	_mat.set_shader_parameter("blend_softness", AtlanticConfig.BLEND_SOFTNESS)
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := AtlanticTerrainSettings.load_settings()
	apply_terrain_colors(s["color_a"], s["color_b"])
	apply_river_width(s["river_width"])
	apply_river_bank_width(s["river_bank_width"])
	apply_river_edge_jaggedness(s["river_edge_jaggedness"])
	apply_canopy_size(s["canopy_size"])
	apply_river_bank_color(s["river_bank_color"])
	apply_water_color(s["water_color"])
	apply_water_wave_size(s["water_wave_size"])
	apply_water_wave_speed(s["water_wave_speed"])
	apply_maptile_set(s["maptile_set"])
	apply_water_tile_set(s["water_tile_set"])
	apply_ground_lighting(s["ground_light_angle_deg"], s["ground_light_height"], s["ground_ambient"], s["ground_specular"], s["ground_light_color"], s["ground_contrast"])

## Public: called by the Terrain Edit panel (live) and by this node's own _ready() (persisted settings).
## Half-width of the current band in noise-value space — 0 turns the current off entirely.
func apply_river_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_width", width)

## Public: called by the Terrain Edit panel's "Current Bank Width" slider (live) and by this node's own
## _ready() (persisted settings). Noise-value half-width the pale-sand rim extends beyond river_width.
func apply_river_bank_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_width", width)

## Public: called by the Terrain Edit panel's "Current Edge Scour" slider (live) and by this node's own
## _ready() (persisted settings). GPU-only — see atlantic_ground.gdshader's river_detail_strength for the
## full mechanic (perturbs the current/floor boundary by the cellular tex_river_detail field, as a fraction
## of river_width).
func apply_river_edge_jaggedness(strength: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_detail_strength", strength)

## Public: world-px spanned by one ground-photo tile.
func apply_canopy_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("ground_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: `color_a` = "dark silt" zone, `color_b` = "pale sand" zone — multiply-tinted over the ground photo.
func apply_terrain_colors(color_a: Color, color_b: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("col_zone_a_light", color_a)
	_mat.set_shader_parameter("col_zone_b_light", color_b)

## Public: pale current-swept sand rim between ruin floor and current.
func apply_river_bank_color(color: Color) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_color", color)

## Public: base current tone — river_color_dark is derived by darkening it.
func apply_water_color(color: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("river_color_light", color)
	_mat.set_shader_parameter("river_color_dark", Color(color.r * WATER_DARKEN_FACTOR, color.g * WATER_DARKEN_FACTOR, color.b * WATER_DARKEN_FACTOR, 1.0))

## Public: world-px spanned by one wave-texture tile (current shimmer).
func apply_water_wave_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("water_wave_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live) and by this node's own _ready() (persisted settings).
## World-px/sec the current-shimmer texture scrolls — 0 freezes it entirely.
func apply_water_wave_speed(speed: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("water_wave_speed", speed)

## Public: loads assets/map/atlantic/watertile/<set_name>/*.png as tex_water_wave.
func apply_water_tile_set(set_name: String) -> void:
	if _mat == null:
		return
	var path := AtlanticAssetScan.watertile_wave_path(set_name)
	if path == "":
		push_warning("AtlanticGround: watertile set '%s' has no image — current wave texture left unchanged." % set_name)
		return
	_mat.set_shader_parameter("tex_water_wave", load(path))

## Public: loads the 3 ground photos from assets/map/atlantic/maptile/<set_name>/ as tex_ground_a/b/c (+
## normals, falling back to a flat neutral normal if generate_canopy_normal.py hasn't been run for this set).
## Returns silently (a warning only) if the set doesn't have 3 images yet — expected until the user drops the
## "canopy" seabed/ruin-floor photos into that folder.
func apply_maptile_set(set_name: String) -> void:
	if _mat == null:
		return
	var paths: Array = AtlanticAssetScan.maptile_set_image_paths(set_name)
	if paths.size() < 3:
		push_warning("AtlanticGround: maptile set '%s' has %d image(s), need at least 3 — ground textures left unchanged." % [set_name, paths.size()])
		return
	_mat.set_shader_parameter("tex_ground_a", load(paths[0]))
	_mat.set_shader_parameter("tex_ground_b", load(paths[1]))
	_mat.set_shader_parameter("tex_ground_c", load(paths[2]))
	_mat.set_shader_parameter("tex_ground_a_normal", _load_normal_or_flat(paths[0]))
	_mat.set_shader_parameter("tex_ground_b_normal", _load_normal_or_flat(paths[1]))
	_mat.set_shader_parameter("tex_ground_c_normal", _load_normal_or_flat(paths[2]))

func _load_normal_or_flat(color_path: String) -> Texture2D:
	var normal_path := AtlanticAssetScan.maptile_normal_path(color_path)
	if ResourceLoader.exists(normal_path):
		return load(normal_path)
	if _neutral_normal_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0))
		_neutral_normal_tex = ImageTexture.create_from_image(img)
	return _neutral_normal_tex

## Public: drives the ground's per-pixel N.L (+ specular) shading — see volcanic_ground.gd's
## apply_ground_lighting for the parameter semantics (identical here).
func apply_ground_lighting(angle_deg: float, height: float, ambient: float, specular: float, color: Color, contrast: float) -> void:
	if _mat == null:
		return
	var h := clampf(height, 0.0, 1.0)
	var xy_mag := sqrt(maxf(0.0, 1.0 - h * h))
	var rad := deg_to_rad(angle_deg)
	var light_dir := Vector3(cos(rad) * xy_mag, sin(rad) * xy_mag, h)
	_mat.set_shader_parameter("ground_light_dir", light_dir)
	_sun_dir = light_dir
	_mat.set_shader_parameter("ground_ambient", ambient)
	_mat.set_shader_parameter("ground_specular_strength", specular)
	_mat.set_shader_parameter("ground_light_color", color)
	_mat.set_shader_parameter("ground_contrast", contrast)

## Public: the live "sun" direction this ground is currently lit by - Vector3(x, y, height), same convention
## as the shader's own ground_light_dir uniform (screen-space XY toward the light, Z = how overhead it is, 0 = grazing
## / 1 = straight down). Read by arena_enemy_manager.gd's _tick_sun() so the player ship's and VIPER's own
## key lights orient off the SAME direction as THIS map's own Light Edit setting instead of each inventing
## its own - see that function's header for the full "one sun" rationale (2026-08-28, user report: "neu la 2
## nguon sang doc lap thi ban dang lam sai, toi can 1 mat troi thoi").
func sun_dir() -> Vector3:
	return _sun_dir

func _resize() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = vp_size + Vector2(MARGIN, MARGIN) * 2.0
	_rect.size = sz
	_rect.position = Vector2(-MARGIN, -MARGIN)
	_mat.set_shader_parameter("rect_size", sz)

func set_world_offset(world_pos: Vector2) -> void:
	_mat.set_shader_parameter("world_offset", world_pos)

## Bake one seamless SIMPLEX noise texture (zone/mottle fields — mirrors volcanic_ground.gd's _make_noise_tex).
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

## Bake one seamless CELLULAR (Manhattan-distance Voronoi) noise texture — the high-frequency EDGE-SCOUR DETAIL
## field mixed into the current contour (see atlantic_ground.gdshader's fragment()), not the macro current
## shape itself (that's tex_river, baked by _make_noise_tex). See AtlanticNoise._ensure_river_detail() for the
## matching CPU-side field (current avoidance) — same distance function/return type/frequency multiplier so
## the two agree on roughly where the current actually is.
func _make_cellular_detail_tex(freq_cycles: float, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq_cycles / float(TEX_SIZE)
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.seed = seed_v   # matches AtlanticNoise._ensure_river_detail()'s seed (33)
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex
