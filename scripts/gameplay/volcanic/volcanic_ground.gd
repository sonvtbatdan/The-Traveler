extends CanvasLayer
class_name VolcanicGround
## Screen-filling ground for the Volcanic map — real top-down cracked-lava-rock PHOTOS (assets/map/volcanic/
## maptile/<set>/), tinted per-zone and tiled at world-scale. Mirrors electric/electric_ground.gd's overall
## technique (baked seamless NoiseTexture2D level-sets, sampled + tiled via repeat wrap in
## volcanic_ground.gdshader) with one deliberate difference: the lava contour is baked from TWO textures —
## tex_river (smooth simplex, organic macro flow path) PLUS tex_river_detail (cellular/Manhattan, high
## frequency), the latter perturbing the boundary into jagged cracked-rock nicks without turning the whole
## flow into a mathematical zigzag — see VolcanicNoise's header for the full rationale (an earlier
## cellular-only version read as straight polyline segments, not a natural lava river). No landmark system yet
## (see electric_ground.gd's apply_landmarks for the pattern to port once a landmark asset exists).
##
## Sits on a negative CanvasLayer (screen-space, always covers the viewport) — set_world_offset() shifts the
## CONTENT via a shader uniform each frame, same trick as electric_ground.gd.

const GROUND_SHADER := preload("res://scripts/gameplay/volcanic/volcanic_ground.gdshader")
const VolcanicConfig := preload("res://scripts/gameplay/volcanic/volcanic_config.gd")
const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")
const VolcanicAssetScan := preload("res://scripts/gameplay/volcanic/volcanic_asset_scan.gd")

const MARGIN := 160.0
const TEX_SIZE := 1024

const GROUND_TINT_STRENGTH := 0.5
const GROUND_SPECULAR_POWER := 18.0

const ZONE_UV_SCALE := 1.0 / 4000.0
const ZONE_TILE_CYCLES := 14.0
const MOTTLE_UV_SCALE := ZONE_UV_SCALE * 5.3
const MOTTLE_TILE_CYCLES := 20.0
const RIVER_UV_SCALE := 1.0 / 4000.0
const RIVER_TILE_CYCLES := 4.0   # 4/4000 = 0.001 world-freq, matching VolcanicConfig.RIVER_NOISE_FREQ
const RIVER_DETAIL_FREQ_MULT := 7.0    # must match VolcanicNoise.RIVER_DETAIL_FREQ_MULT
const WATER_DARKEN_FACTOR := 0.4

var _rect: ColorRect
var _mat: ShaderMaterial
var _neutral_normal_tex: ImageTexture = null

func _ready() -> void:
	add_to_group("volcanic_ground")   # so the Terrain Edit panel can find this instance
	layer = -10
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	_mat.set_shader_parameter("tex_zone", _make_noise_tex(ZONE_TILE_CYCLES, 4, 31))
	_mat.set_shader_parameter("tex_mottle", _make_noise_tex(MOTTLE_TILE_CYCLES, 3, 67))
	_mat.set_shader_parameter("tex_river", _make_noise_tex(RIVER_TILE_CYCLES, 3, 8))
	_mat.set_shader_parameter("tex_river_detail", _make_cellular_detail_tex(RIVER_TILE_CYCLES * RIVER_DETAIL_FREQ_MULT, 13))
	_mat.set_shader_parameter("river_detail_uv_scale", RIVER_UV_SCALE * RIVER_DETAIL_FREQ_MULT)
	_mat.set_shader_parameter("ground_tint_strength", GROUND_TINT_STRENGTH)
	_mat.set_shader_parameter("ground_specular_power", GROUND_SPECULAR_POWER)
	_mat.set_shader_parameter("zone_uv_scale", ZONE_UV_SCALE)
	_mat.set_shader_parameter("mottle_uv_scale", MOTTLE_UV_SCALE)
	_mat.set_shader_parameter("river_uv_scale", RIVER_UV_SCALE)
	_mat.set_shader_parameter("river_level", VolcanicConfig.RIVER_LEVEL)
	_mat.set_shader_parameter("blue_threshold", VolcanicConfig.BLUE_THRESHOLD)
	_mat.set_shader_parameter("blend_softness", VolcanicConfig.BLEND_SOFTNESS)
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := VolcanicTerrainSettings.load_settings()
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
## Half-width of the lava band in noise-value space — 0 turns lava off entirely.
func apply_river_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_width", width)

## Public: called by the Terrain Edit panel's "River Bank Width" slider (live) and by this node's own
## _ready() (persisted settings). Noise-value half-width the obsidian-crust rim extends beyond river_width —
## mirrors Electric's river_bank_width uniform (electric_ground.gdshader), just exposed as a slider here
## instead of a hardcoded constant.
func apply_river_bank_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_width", width)

## Public: called by the Terrain Edit panel's "River Edge Jaggedness" slider (live) and by this node's own
## _ready() (persisted settings). GPU-only — see volcanic_ground.gdshader's river_detail_strength for the
## full mechanic (perturbs the lava/rock boundary by the cellular tex_river_detail field, as a fraction of
## river_width). Does NOT propagate to VolcanicNoise's CPU-side copy (used only by the not-yet-populated
## rock-scatter avoidance check) — that stays at its fixed default; harmless while VolcanicTrees has no .glb
## assets to place yet, but note this if a future rock scatter needs to match this slider exactly.
func apply_river_edge_jaggedness(strength: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_detail_strength", strength)

## Public: world-px spanned by one ground-photo tile.
func apply_canopy_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("ground_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: `color_a` = "dark basalt" zone, `color_b` = "ash/dust" zone — multiply-tinted over the ground photo.
func apply_terrain_colors(color_a: Color, color_b: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("col_zone_a_light", color_a)
	_mat.set_shader_parameter("col_zone_b_light", color_b)

## Public: dark obsidian crust rim between rock and lava.
func apply_river_bank_color(color: Color) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_color", color)

## Public: base lava tone — river_color_dark is derived by darkening it.
func apply_water_color(color: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("river_color_light", color)
	_mat.set_shader_parameter("river_color_dark", Color(color.r * WATER_DARKEN_FACTOR, color.g * WATER_DARKEN_FACTOR, color.b * WATER_DARKEN_FACTOR, 1.0))

## Public: world-px spanned by one wave-texture tile (lava flow shimmer).
func apply_water_wave_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("water_wave_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live) and by this node's own _ready() (persisted settings).
## World-px/sec the lava wave texture scrolls — 0 freezes the shimmer entirely.
func apply_water_wave_speed(speed: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("water_wave_speed", speed)

## Public: loads assets/map/volcanic/watertile/<set_name>/*.png as tex_water_wave.
func apply_water_tile_set(set_name: String) -> void:
	if _mat == null:
		return
	var path := VolcanicAssetScan.watertile_wave_path(set_name)
	if path == "":
		push_warning("VolcanicGround: watertile set '%s' has no image — lava wave texture left unchanged." % set_name)
		return
	_mat.set_shader_parameter("tex_water_wave", load(path))

## Public: loads the 3 ground photos from assets/map/volcanic/maptile/<set_name>/ as tex_ground_a/b/c (+
## normals, falling back to a flat neutral normal if generate_canopy_normal.py hasn't been run for this set).
func apply_maptile_set(set_name: String) -> void:
	if _mat == null:
		return
	var paths: Array = VolcanicAssetScan.maptile_set_image_paths(set_name)
	if paths.size() < 3:
		push_warning("VolcanicGround: maptile set '%s' has %d image(s), need at least 3 — ground textures left unchanged." % [set_name, paths.size()])
		return
	_mat.set_shader_parameter("tex_ground_a", load(paths[0]))
	_mat.set_shader_parameter("tex_ground_b", load(paths[1]))
	_mat.set_shader_parameter("tex_ground_c", load(paths[2]))
	_mat.set_shader_parameter("tex_ground_a_normal", _load_normal_or_flat(paths[0]))
	_mat.set_shader_parameter("tex_ground_b_normal", _load_normal_or_flat(paths[1]))
	_mat.set_shader_parameter("tex_ground_c_normal", _load_normal_or_flat(paths[2]))

func _load_normal_or_flat(color_path: String) -> Texture2D:
	var normal_path := VolcanicAssetScan.maptile_normal_path(color_path)
	if ResourceLoader.exists(normal_path):
		return load(normal_path)
	if _neutral_normal_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0))
		_neutral_normal_tex = ImageTexture.create_from_image(img)
	return _neutral_normal_tex

## Public: drives the ground's per-pixel N.L (+ specular) shading — see electric_ground.gd's
## apply_canopy_lighting for the parameter semantics (identical here, just renamed canopy->ground).
func apply_ground_lighting(angle_deg: float, height: float, ambient: float, specular: float, color: Color, contrast: float) -> void:
	if _mat == null:
		return
	var h := clampf(height, 0.0, 1.0)
	var xy_mag := sqrt(maxf(0.0, 1.0 - h * h))
	var rad := deg_to_rad(angle_deg)
	var light_dir := Vector3(cos(rad) * xy_mag, sin(rad) * xy_mag, h)
	_mat.set_shader_parameter("ground_light_dir", light_dir)
	_mat.set_shader_parameter("ground_ambient", ambient)
	_mat.set_shader_parameter("ground_specular_strength", specular)
	_mat.set_shader_parameter("ground_light_color", color)
	_mat.set_shader_parameter("ground_contrast", contrast)

func _resize() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = vp_size + Vector2(MARGIN, MARGIN) * 2.0
	_rect.size = sz
	_rect.position = Vector2(-MARGIN, -MARGIN)
	_mat.set_shader_parameter("rect_size", sz)

func set_world_offset(world_pos: Vector2) -> void:
	_mat.set_shader_parameter("world_offset", world_pos)

## Bake one seamless SIMPLEX noise texture (zone/mottle fields — mirrors electric_ground.gd's _make_noise_tex).
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

## Bake one seamless CELLULAR (Manhattan-distance Voronoi) noise texture — the high-frequency EDGE-JAG DETAIL
## field mixed into the lava contour (see volcanic_ground.gdshader's fragment()), not the macro river shape
## itself (that's tex_river, baked by _make_noise_tex like Electric's). Polygonal, faceted iso-contours are what
## make the boundary read as jagged cracked crust. See VolcanicNoise._ensure_river_detail() for the matching
## CPU-side field (river avoidance) — same distance function/return type/frequency multiplier so the two
## agree on roughly where the lava actually is.
func _make_cellular_detail_tex(freq_cycles: float, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq_cycles / float(TEX_SIZE)
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.seed = seed_v   # matches VolcanicNoise._ensure_river_detail()'s seed (13)
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex
