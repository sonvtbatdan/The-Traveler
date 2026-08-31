extends CanvasLayer
class_name MechanicGround
## Screen-filling ground for the Mechanic map — real top-down canopy PHOTOS (assets/map/mechanic/maptile/
## default/), tinted per-zone and tiled at world-scale — ported from electric_ground.gd (see that file's
## header for the full baked-noise-texture / seamless-tiling rationale, identical here). Sits on a negative
## CanvasLayer (screen-space, always covers the viewport) — set_world_offset() shifts the CONTENT via a
## shader uniform each frame, same "rect stays put, uniform scrolls" trick as Electric/arena_nebula.
##
## Two deliberate differences from ElectricGround (see mechanic_ground.gdshader's header for the shader-side
## half of these):
##  1. All 7 of assets/map/mechanic/maptile/default/'s canopy photos are loaded and blended together with
##     Electric's OWN technique (mottle-field region split, see mechanic_ground.gdshader), just extended from
##     3 to 7 textures — not a 3-of-N swappable "Tile Set" pick like Electric itself uses. apply_canopy_images()
##     replaces apply_maptile_set(). How far apart the 6 region transitions land is a live slider
##     (apply_canopy_mottle_scale) rather than a fixed baked frequency.
##  2. No landmark ring/patch system yet — no landmark .glb exists for this map (see MechanicAssetScan's
##     empty SCATTER_EXCLUDED); apply_landmarks() can be ported back from electric_ground.gd once one does.
##
## River (2026-08-19, 3 redesigns same day): reverted to ElectricGround's own river implementation verbatim,
## then made to run ALONG the canopy blend's own 6 seam lines instead of an independent field crossing them at
## random angles, then (still same day) had a low-frequency CORRIDOR gate added back on top so the seam-
## following river reads as one long path instead of the whole seam mesh (which includes small closed loops
## around local mottle extrema — "sai quy tắc river trong thực tế"). See mechanic_ground.gdshader's header for
## the full blow-by-blow and MechanicNoise.is_river() for the matching CPU-side avoidance formula.

const GROUND_SHADER := preload("res://scripts/gameplay/mechanic/mechanic_ground.gdshader")
const MechanicConfig := preload("res://scripts/gameplay/mechanic/mechanic_config.gd")
const MechanicTerrainSettings := preload("res://scripts/gameplay/mechanic/mechanic_terrain_settings.gd")
const MechanicAssetScan := preload("res://scripts/gameplay/mechanic/mechanic_asset_scan.gd")

const MARGIN := 160.0   # extra px beyond the viewport so a resize/rotation never shows a bare edge
const TEX_SIZE := 1024

const CANOPY_TINT_STRENGTH := 0.5
const CANOPY_SPECULAR_POWER := 18.0

const ZONE_UV_SCALE := 1.0 / 4000.0
const ZONE_TILE_CYCLES := 14.0
const MOTTLE_TILE_CYCLES := 10.0   # baked-in noise detail for tex_mottle — the actual world-space "how far
                                     # apart do transitions land" is mottle_uv_scale (apply_canopy_mottle_scale),
                                     # a separate LIVE-tunable stretch on top of this fixed bake, same split as
                                     # canopy_size elsewhere in this file
const MOTTLE_OCTAVES := 2
const RIVER_TILE_CYCLES := 4.0   # baked-in cycles for tex_river's CORRIDOR gate (NOT the river shape itself
                                  # any more — see mechanic_ground.gdshader's header) — a low frequency so the
                                  # corridor reads as one slow, long-winding band
const WATER_WAVE_SPEED := 26.0
const WATER_DARKEN_FACTOR := 0.4

var _rect: ColorRect
var _mat: ShaderMaterial
# Cached copy of the light_dir this function just computed (2026-08-28) - the single "sun" the player ship's
# and VIPER's own key lights orient off via arena_enemy_manager.gd's sun_dir(), instead of each guessing its
# own independent light direction. See sun_dir()'s own doc comment just below.
var _sun_dir: Vector3 = Vector3(0.6, 0.6, 0.6)   # matches the shader uniform's own default
var _neutral_normal_tex: ImageTexture = null

# tex_canopy_a..g — matches mechanic_ground.gdshader's 7 uniform names.
const CANOPY_SLOTS := ["a", "b", "c", "d", "e", "f", "g"]

func _ready() -> void:
	add_to_group("mechanic_ground")   # so the Terrain Edit panel can find this instance
	layer = -10
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	_mat.set_shader_parameter("tex_zone", _make_noise_tex(ZONE_TILE_CYCLES, 4, 11))
	_mat.set_shader_parameter("tex_mottle", _make_noise_tex(MOTTLE_TILE_CYCLES, MOTTLE_OCTAVES, 47))
	_mat.set_shader_parameter("tex_river", _make_noise_tex(RIVER_TILE_CYCLES, 3, 5))
	_mat.set_shader_parameter("canopy_tint_strength", CANOPY_TINT_STRENGTH)
	_mat.set_shader_parameter("canopy_specular_power", CANOPY_SPECULAR_POWER)
	_mat.set_shader_parameter("zone_uv_scale", ZONE_UV_SCALE)
	_mat.set_shader_parameter("blue_threshold", MechanicConfig.BLUE_THRESHOLD)
	_mat.set_shader_parameter("blend_softness", MechanicConfig.BLEND_SOFTNESS)
	_mat.set_shader_parameter("water_wave_speed", WATER_WAVE_SPEED)
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := MechanicTerrainSettings.load_settings()
	apply_terrain_colors(s["color_a"], s["color_b"])
	apply_river_width(s["river_width"])
	apply_river_count(int(s["river_count"]))
	apply_canopy_size(s["canopy_size"])
	apply_canopy_mottle_scale(s["canopy_mottle_scale"])
	apply_canopy_blend_width(s["canopy_blend_width"])
	apply_river_bank_color(s["river_bank_color"])
	apply_river_bank_width(s["river_bank_width"])
	apply_water_color(s["water_color"])
	apply_water_wave_size(s["water_wave_size"])
	apply_canopy_images(s["maptile_set"])
	apply_water_tile_set(s["water_tile_set"])
	apply_canopy_lighting(s["canopy_light_angle_deg"], s["canopy_light_height"], s["canopy_ambient"], s["canopy_specular"], s["canopy_light_color"], s["canopy_contrast"])

func apply_river_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_width", width)

## Public: called by the Terrain Edit panel's River tab (live, on slider change) and by this node's own
## _ready() (persisted settings). 0..6 — how many of the 7-way canopy blend's 6 seam lines carry a river; see
## mechanic_ground.gdshader's header for the full rationale.
func apply_river_count(count: int) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_count", clampi(count, 0, 6))

## World-px spanned by one repeat of whichever photo is currently showing (its OWN internal tiling scale) —
## unrelated to how far apart REGION transitions land, see apply_canopy_mottle_scale.
func apply_canopy_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("canopy_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live) and by this node's own _ready() (persisted settings).
## "Canopy Blend Sparseness" — world-px stretch on tex_mottle's baked pattern. Bigger = the 6 region
## transitions land farther apart in world space, so more of any one photo shows intact between them; smaller
## = transitions come more often, a finer/busier mix of all 7. Same "size slider -> 1/size UV scale" pattern
## as apply_canopy_size/apply_water_wave_size.
func apply_canopy_mottle_scale(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("mottle_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live) and by this node's own _ready() (persisted settings).
## Smoothstep half-width (mottle-value space) around each of the 6 region-threshold crossings — see
## mechanic_ground.gdshader's nested-mix comment. Keep this NARROW (mirrors Electric's own fixed 0.04); it's
## NOT the right knob for "less shattered-looking" — that's apply_canopy_mottle_scale (sparseness) above.
## Widening this one past the region spacing brings back the exact nested-mix ordering artifact the Voronoi
## detour (2026-08-19, since reverted) was built to avoid.
func apply_canopy_blend_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("canopy_blend_width", width)

func apply_terrain_colors(color_a: Color, color_b: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("col_blue_light", color_a)
	_mat.set_shader_parameter("col_sand_light", color_b)

func apply_river_bank_color(color: Color) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_color", color)

## Public: called by the Terrain Edit panel's River tab (live, on slider change) and by this node's own
## _ready() (persisted settings). Extra noise-value half-width the golden sand fringe extends beyond
## river_width — 0 = canopy runs straight into the water with no fringe at all, bigger = a wider sandy bank.
## Was a fixed const (RIVER_BANK_WIDTH) until 2026-08-19, on request — exposed live to match river_bank_color's
## own tunability (was already possible in principle, just never wired to a slider).
func apply_river_bank_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_width", width)

func apply_water_color(color: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("river_color_light", color)
	_mat.set_shader_parameter("river_color_dark", Color(color.r * WATER_DARKEN_FACTOR, color.g * WATER_DARKEN_FACTOR, color.b * WATER_DARKEN_FACTOR, 1.0))

func apply_water_wave_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("water_wave_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live, on dropdown change) and by this node's own _ready()
## (persisted settings). Loads assets/map/mechanic/watertile/<set_name>/water_wave.png as tex_water_wave.
## No-ops on "" (no watertile set exists yet — MechanicAssetScan.watertile_set_names() returns []) or if the
## set has no image, leaving whatever's already loaded (matches ElectricGround's own graceful-empty fallback).
func apply_water_tile_set(set_name: String) -> void:
	if _mat == null or set_name == "":
		return
	var path := MechanicAssetScan.watertile_wave_path(set_name)
	if path == "":
		push_warning("MechanicGround: watertile set '%s' has no image — water texture left unchanged." % set_name)
		return
	_mat.set_shader_parameter("tex_water_wave", load(path))

## Public: called by the Terrain Edit panel (live, on dropdown change) and by this node's own _ready()
## (persisted settings). Loads ALL images from assets/map/mechanic/maptile/<set_name>/ (positionally, up to
## the 7 mechanic_ground.gdshader has slots for) as tex_canopy_a..g. Falls back to leaving whatever's already
## loaded if the set has fewer than 7 images (e.g. mid-edit) rather than clearing textures out from under the
## shader — mirrors ElectricGround.apply_maptile_set's same fewer-than-N guard, just against 7 instead of 3.
func apply_canopy_images(set_name: String) -> void:
	if _mat == null:
		return
	var paths: Array = MechanicAssetScan.maptile_set_image_paths(set_name)
	if paths.size() < CANOPY_SLOTS.size():
		push_warning("MechanicGround: maptile set '%s' has %d image(s), need at least %d — canopy textures left unchanged." % [set_name, paths.size(), CANOPY_SLOTS.size()])
		return
	for i in CANOPY_SLOTS.size():
		var slot: String = CANOPY_SLOTS[i]
		_mat.set_shader_parameter("tex_canopy_%s" % slot, load(paths[i]))
		_mat.set_shader_parameter("tex_canopy_%s_normal" % slot, _load_normal_or_flat(paths[i]))

## tools/generate_canopy_normal.py may not have been run yet for a given image — fall back to a flat neutral
## (0,0,1 -> RGB 128,128,255, "no relief") 1x1 texture. Mirrors ElectricGround's own fallback.
func _load_normal_or_flat(color_path: String) -> Texture2D:
	var normal_path := MechanicAssetScan.maptile_normal_path(color_path)
	if ResourceLoader.exists(normal_path):
		return load(normal_path)
	if _neutral_normal_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0))
		_neutral_normal_tex = ImageTexture.create_from_image(img)
	return _neutral_normal_tex

## Public: called by the Light Edit panel (live) and by this node's own _ready() (persisted settings). See
## ElectricGround.apply_canopy_lighting for the full parameter rationale — identical here.
func apply_canopy_lighting(angle_deg: float, height: float, ambient: float, specular: float, color: Color, contrast: float) -> void:
	if _mat == null:
		return
	var h := clampf(height, 0.0, 1.0)
	var xy_mag := sqrt(maxf(0.0, 1.0 - h * h))
	var rad := deg_to_rad(angle_deg)
	var light_dir := Vector3(cos(rad) * xy_mag, sin(rad) * xy_mag, h)
	_mat.set_shader_parameter("canopy_light_dir", light_dir)
	_sun_dir = light_dir
	_mat.set_shader_parameter("canopy_ambient", ambient)
	_mat.set_shader_parameter("canopy_specular_strength", specular)
	_mat.set_shader_parameter("canopy_light_color", color)
	_mat.set_shader_parameter("canopy_contrast", contrast)

## Public: the live "sun" direction this ground is currently lit by - Vector3(x, y, height), same convention
## as the shader's own canopy_light_dir uniform (screen-space XY toward the light, Z = how overhead it is, 0 = grazing
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

