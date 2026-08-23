extends CanvasLayer
class_name ElectricGround
## Screen-filling ground for the Electric map — real top-down jungle-canopy PHOTOS (assets/map/electric/maptile/
## <set>/), tinted per-zone and tiled at world-scale, sitting under the scattered real 3D trees (ElectricTrees).
## Which SET of 3 photos is active (ElectricAssetScan.maptile_set_names(), e.g. "green"/"grey") is picked via
## the Terrain Edit panel's "Tile Set" dropdown / persisted "maptile_set" — see apply_maptile_set(). Zone
## split / river contour are still pure noise, BAKED into seamless NoiseTexture2D at load (arena_nebula.gd's
## proven technique) and sampled + tiled via repeat wrap. The canopy photos are NOT themselves seamless —
## see electric_ground.gdshader's header for how that's made acceptable (same precedent already used for the
## noise textures: an occasional seam at long-flight distance, not periodic within normal play movement).
## Rivers get a golden sand fringe (river_bank_color/river_bank_width) between the canopy and the water so
## the jungle doesn't run straight into the riverbed — see the shader's fragment() for the ring composition.
## Sits on a negative CanvasLayer (screen-space, always covers the viewport) — set_world_offset() shifts
## the CONTENT via a shader uniform each frame, same "rect stays put, uniform scrolls" trick as arena_nebula.

const GROUND_SHADER := preload("res://scripts/gameplay/electric/electric_ground.gdshader")
const ElectricConfig := preload("res://scripts/gameplay/electric/electric_config.gd")
const ElectricTerrainSettings := preload("res://scripts/gameplay/electric/electric_terrain_settings.gd")
const ElectricAssetScan := preload("res://scripts/gameplay/electric/electric_asset_scan.gd")
## assets/map/electric/watertile/<B|C|D>/water_wave.png are copies of SeaWaterMaterial's Sea_Water_B/C/D
## Water_Wave_basecolor.png — that asset pack ships its own nested project.godot, so Godot's importer ignores
## that whole subfolder entirely (verified: "Detected another project.godot ... folder will be ignored");
## copying the textures out here is simpler and safer than restructuring a vendored third-party pack. Its own
## .material/.gdshader are shader_type SPATIAL (real 3D mesh displacement + depth-buffer shoreline detection),
## incompatible with this flat canvas_item ground shader regardless — only the textures themselves are
## reusable. All 3 are genuinely seamless (edge SAD = 0.0, verified), so they tile at any scale for free.
## Sea_Water_A has no dedicated texture (procedural-only via BaseNoise.tres/SimplexNoise.tres, itself a
## Godot-3.x-format resource) so it's not offered as a 4th choice. Picked via the Terrain Edit panel's "Water
## Pattern" dropdown / persisted "water_tile_set" — see apply_water_tile_set().

const MARGIN := 160.0   # extra px beyond the viewport so a resize/rotation never shows a bare edge
const TEX_SIZE := 1024

# Each maptile set's 3 canopy photos are ~2048px; the world-px tile span (Terrain Edit panel's "Canopy Size"
# slider, ElectricTerrainSettings.DEFAULT_CANOPY_SIZE=1600) controls how big individual leaf clusters read
# relative to the scattered 3D trees on top of them (ElectricTrees.DESIRED_HEIGHT_PX = 110) — too small and it
# looks microscopic, too big and it looks like a few giant blown-up blobs.
const CANOPY_TINT_STRENGTH := 0.5
const CANOPY_SPECULAR_POWER := 18.0   # glossy highlight tightness — not exposed as a slider (canopy_specular
                                       # strength is); a fixed "how tight" pairs with a tunable "how bright"

# The baked texture tiles every 1/UV_SCALE world px — TILE_CYCLES worth of blotch wavelengths are packed
# into each tile so wandering around inside one tile never shows an obvious repeat; only flying ~4000px in
# one direction would reveal the seam, which reads as "infinite" for a top-down flight map at this speed.
const ZONE_UV_SCALE := 1.0 / 4000.0
const ZONE_TILE_CYCLES := 14.0
const MOTTLE_UV_SCALE := ZONE_UV_SCALE * 5.3
const MOTTLE_TILE_CYCLES := 20.0
const RIVER_UV_SCALE := 1.0 / 4000.0
const RIVER_TILE_CYCLES := 4.0   # 4/4000 = 0.001 world-freq, matching ElectricConfig.RIVER_NOISE_FREQ
const RIVER_BANK_WIDTH := 0.022     # noise-value half-width the bank extends beyond river_width
const LANDMARK_PATCH_RADIUS := 320.0     # world-px the guaranteed-dry ground patch extends beyond a landmark's
                                          # own ring (landmark_ring_width) — see electric_ground.gdshader
const LANDMARK_PATCH_EDGE_NOISE := 70.0  # wobble amplitude (world px) on the patch's outer edge, so it reads
                                          # as an organic land shape instead of a smooth rounded box
const WATER_WAVE_SPEED := 26.0             # world-px/sec the wave texture scrolls (flow direction below)
const WATER_DARKEN_FACTOR := 0.4           # river_color_dark = water_color * this (see apply_water_color)
const MAX_LANDMARKS := 8            # must match electric_ground.gdshader's landmark_pos/landmark_half_extent/
                                     # landmark_yaw array size

var _rect: ColorRect
var _mat: ShaderMaterial
var _neutral_normal_tex: ImageTexture = null

func _ready() -> void:
	add_to_group("electric_ground")   # so the Terrain Edit panel can find this instance
	layer = -10
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	_mat.set_shader_parameter("tex_zone", _make_noise_tex(ZONE_TILE_CYCLES, 4, 11))
	_mat.set_shader_parameter("tex_mottle", _make_noise_tex(MOTTLE_TILE_CYCLES, 3, 47))
	_mat.set_shader_parameter("tex_river", _make_noise_tex(RIVER_TILE_CYCLES, 3, 5))
	_mat.set_shader_parameter("canopy_tint_strength", CANOPY_TINT_STRENGTH)
	_mat.set_shader_parameter("canopy_specular_power", CANOPY_SPECULAR_POWER)
	_mat.set_shader_parameter("zone_uv_scale", ZONE_UV_SCALE)
	_mat.set_shader_parameter("mottle_uv_scale", MOTTLE_UV_SCALE)
	_mat.set_shader_parameter("river_uv_scale", RIVER_UV_SCALE)
	_mat.set_shader_parameter("river_level", ElectricConfig.RIVER_LEVEL)
	_mat.set_shader_parameter("blue_threshold", ElectricConfig.BLUE_THRESHOLD)
	_mat.set_shader_parameter("blend_softness", ElectricConfig.BLEND_SOFTNESS)
	_mat.set_shader_parameter("river_bank_width", RIVER_BANK_WIDTH)
	_mat.set_shader_parameter("water_wave_speed", WATER_WAVE_SPEED)
	_mat.set_shader_parameter("landmark_patch_radius", LANDMARK_PATCH_RADIUS)
	_mat.set_shader_parameter("landmark_patch_edge_noise", LANDMARK_PATCH_EDGE_NOISE)
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)

	var s := ElectricTerrainSettings.load_settings()
	apply_terrain_colors(s["color_a"], s["color_b"])
	apply_river_width(s["river_width"])
	apply_canopy_size(s["canopy_size"])
	apply_river_bank_color(s["river_bank_color"])
	apply_water_color(s["water_color"])
	apply_water_wave_size(s["water_wave_size"])
	apply_maptile_set(s["maptile_set"])
	apply_water_tile_set(s["water_tile_set"])
	apply_landmark_ring_width(s["landmark_ring_width"])
	apply_canopy_lighting(s["canopy_light_angle_deg"], s["canopy_light_height"], s["canopy_ambient"], s["canopy_specular"], s["canopy_light_color"], s["canopy_contrast"])

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). Half-width of the river band in noise-value space — 0 turns rivers off entirely.
func apply_river_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_width", width)

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). World-px spanned by one canopy-photo tile — bigger = bigger-looking leaf clusters
## (the same 2048px photo gets stretched over more world space), smaller = denser/finer clusters.
func apply_canopy_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("canopy_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live, on ColorPickerButton change) and by this node's own
## _ready() (persisted settings). `color_a` = "blue" grass zone, `color_b` = "sand" zone — multiply-tinted
## over the canopy photo textures (see electric_ground.gdshader's canopy_tint_strength), not a flat fill.
func apply_terrain_colors(color_a: Color, color_b: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("col_blue_light", color_a)
	_mat.set_shader_parameter("col_sand_light", color_b)

## Public: called by the Terrain Edit panel (live, on ColorPickerButton change) and by this node's own
## _ready() (persisted settings). Golden sand fringe between the canopy and the water — see
## electric_ground.gdshader's bank_mask.
func apply_river_bank_color(color: Color) -> void:
	if _mat != null:
		_mat.set_shader_parameter("river_bank_color", color)

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). World-px width of the worn-clearing ring band around each landmark (temple boss
## etc, see apply_landmarks) — same river_bank_color, just how far it extends past the model's base footprint.
func apply_landmark_ring_width(width: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("landmark_ring_width", width)

## Public: called by the Terrain Edit panel (live, on ColorPickerButton change) and by this node's own
## _ready() (persisted settings). Base river water tone — river_color_dark is derived by darkening it, so one
## picker controls the whole wave-crest gradient (see electric_ground.gdshader's wave_mix blend).
func apply_water_color(color: Color) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("river_color_light", color)
	_mat.set_shader_parameter("river_color_dark", Color(color.r * WATER_DARKEN_FACTOR, color.g * WATER_DARKEN_FACTOR, color.b * WATER_DARKEN_FACTOR, 1.0))

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). World-px spanned by one wave-texture tile — bigger = bigger-looking individual wave
## crests (the same texture stretched over more world space), smaller = finer, tighter ripples.
func apply_water_wave_size(size_px: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("water_wave_uv_scale", 1.0 / maxf(size_px, 1.0))

## Public: called by the Terrain Edit panel (live, on dropdown change) and by this node's own _ready()
## (persisted settings). Loads assets/map/electric/watertile/<set_name>/water_wave.png as tex_water_wave. Falls
## back to leaving whatever's already loaded if the set has no image yet.
func apply_water_tile_set(set_name: String) -> void:
	if _mat == null:
		return
	var path := ElectricAssetScan.watertile_wave_path(set_name)
	if path == "":
		push_warning("ElectricGround: watertile set '%s' has no image — water texture left unchanged." % set_name)
		return
	_mat.set_shader_parameter("tex_water_wave", load(path))

## Public: called by whatever spawns/despawns landmark objects (electric_temple_layer.gd's temple boss,
## electric_ruin_layer.gd's rescue-character ruins) every time one appears or is removed — rebuilds the full
## ring set from scratch each time (cheap; landmarks are rare, at most MAX_LANDMARKS). `landmarks` is an
## Array of {"pos": Vector2, "half_extent": Vector2, "yaw": float} (world-space — same coordinate system as
## world_offset/set_world_offset; half_extent/yaw come straight from ElectricTrees.spawn_landmark's return
## value — the model's actual base footprint, an oriented box, not a circle). Extra entries beyond
## MAX_LANDMARKS (combined across every source below) are ignored; unused array slots are pushed far away so
## they never contribute to the ring — see the shader's fragment().
##
## `source` (2026-08-06, on request — added when electric_ruin_layer.gd joined electric_temple_layer.gd as a
## second independent landmark spawner): each caller passes its OWN distinct id and its OWN full current list
## — this just replaces that source's slice in `_landmark_sources` and re-flattens everyone's lists before
## pushing to the shader, so two spawners calling independently never stomp each other's ring set the way a
## single un-keyed list would. Default "" preserves old single-caller behavior for any other future caller
## that doesn't care about sharing.
var _landmark_sources: Dictionary = {}   # source id -> Array (that source's own current landmark list)
func apply_landmarks(landmarks: Array, source: String = "") -> void:
	if _mat == null:
		return
	_landmark_sources[source] = landmarks
	var flat: Array = []
	for src: String in _landmark_sources:
		flat.append_array(_landmark_sources[src] as Array)
	var positions := PackedVector2Array()
	var half_extents := PackedVector2Array()
	var yaws := PackedFloat32Array()
	for i in MAX_LANDMARKS:
		if i < flat.size():
			positions.append(flat[i]["pos"])
			half_extents.append(flat[i]["half_extent"])
			yaws.append(flat[i]["yaw"])
		else:
			positions.append(Vector2(1.0e9, 1.0e9))
			half_extents.append(Vector2.ZERO)
			yaws.append(0.0)
	_mat.set_shader_parameter("landmark_pos", positions)
	_mat.set_shader_parameter("landmark_half_extent", half_extents)
	_mat.set_shader_parameter("landmark_yaw", yaws)
	_mat.set_shader_parameter("landmark_count", mini(flat.size(), MAX_LANDMARKS))

## Public: called by the Terrain Edit panel (live, on dropdown change) and by this node's own _ready()
## (persisted settings). Loads the 3 canopy photos from assets/map/electric/maptile/<set_name>/ (positionally —
## see ElectricAssetScan.maptile_set_image_paths, sets aren't required to share a filename convention) as
## tex_canopy_a/b/c. Falls back to leaving whatever's already loaded if the set has fewer than 3 images (e.g.
## mid-edit while the user is still dropping files in) rather than clearing textures out from under the shader.
func apply_maptile_set(set_name: String) -> void:
	if _mat == null:
		return
	var paths: Array = ElectricAssetScan.maptile_set_image_paths(set_name)
	if paths.size() < 3:
		push_warning("ElectricGround: maptile set '%s' has %d image(s), need at least 3 — canopy textures left unchanged." % [set_name, paths.size()])
		return
	_mat.set_shader_parameter("tex_canopy_a", load(paths[0]))
	_mat.set_shader_parameter("tex_canopy_b", load(paths[1]))
	_mat.set_shader_parameter("tex_canopy_c", load(paths[2]))
	_mat.set_shader_parameter("tex_canopy_a_normal", _load_normal_or_flat(paths[0]))
	_mat.set_shader_parameter("tex_canopy_b_normal", _load_normal_or_flat(paths[1]))
	_mat.set_shader_parameter("tex_canopy_c_normal", _load_normal_or_flat(paths[2]))

## tools/generate_canopy_normal.py may not have been run yet for a given set (or a future set someone drops in
## without running it) — fall back to a flat neutral (0,0,1 -> RGB 128,128,255, "no relief" = the shader's
## N.L reduces to a constant) 1x1 texture rather than erroring or leaving a stale normal map from whatever set
## was active before.
func _load_normal_or_flat(color_path: String) -> Texture2D:
	var normal_path := ElectricAssetScan.maptile_normal_path(color_path)
	if ResourceLoader.exists(normal_path):
		return load(normal_path)
	if _neutral_normal_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0))
		_neutral_normal_tex = ImageTexture.create_from_image(img)
	return _neutral_normal_tex

## Public: called by the Light Edit panel (live, on slider/ColorPickerButton change) and by this node's own
## _ready() (persisted settings). Drives the canopy's per-pixel N.L (+ specular) shading against
## tex_canopy_*_normal (see tools/generate_canopy_normal.py) — `angle_deg` is the light's compass direction
## across the ground plane, `height` is 0 (fully grazing, dramatic long shadows) to 1 (fully overhead, flat/no
## shading), `ambient` is the floor brightness on the shadow side (0 = can go pure black, 1 = no shading at
## all), `specular` is the glossy-highlight strength (0 = none), `color` tints the lit side + specular (the
## "sun" color — see the shader's light_tint), `contrast` pushes the diffuse term away from (>1) or toward
## (<1) a pivot of 0.5 — the highlight/shadow separation knob.
func apply_canopy_lighting(angle_deg: float, height: float, ambient: float, specular: float, color: Color, contrast: float) -> void:
	if _mat == null:
		return
	var h := clampf(height, 0.0, 1.0)
	var xy_mag := sqrt(maxf(0.0, 1.0 - h * h))
	var rad := deg_to_rad(angle_deg)
	var light_dir := Vector3(cos(rad) * xy_mag, sin(rad) * xy_mag, h)
	_mat.set_shader_parameter("canopy_light_dir", light_dir)
	_mat.set_shader_parameter("canopy_ambient", ambient)
	_mat.set_shader_parameter("canopy_specular_strength", specular)
	_mat.set_shader_parameter("canopy_light_color", color)
	_mat.set_shader_parameter("canopy_contrast", contrast)

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
