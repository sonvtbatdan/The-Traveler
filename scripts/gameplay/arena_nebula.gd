extends CanvasLayer
## Arena nebula background — hosts a procedural nebula on a screen-filling ColorRect rendered into a
## half-res SubViewport (upscaled; soft gas hides the blur, GPU cheap). Sits on a NEGATIVE CanvasLayer so
## it draws BEHIND the world. The shader scrolls by a world_offset uniform fed from the camera each frame
## → infinite, deterministic, never-repeating. Adds an optional near "hero star" Parallax2D on top.
##
## TWO variants, picked by ACTIVE_BACKGROUND:
##   1 = background_1: live domain-warped gradient-noise fBm (cached look from the previous pass).
##   2 = background_2: "Luna's Wandering Stars" — noise BAKED into seamless textures at load; the shader
##       just samples+scrolls them and multiplies a warm colour by a high-contrast mask over a navy void
##       (big dark voids + glowing filaments, not uniform soup). Cheap because nothing is computed live.

# ── SELECTOR ──────────────────────────────────────────────────────────────────
const ACTIVE_BACKGROUND := 1         # 1 = background_1 (cached fBm), 2 = background_2 (baked), 3 = background_blue (teal+purple)

# ── SHARED TUNABLES ───────────────────────────────────────────────────────────
const NEBULA_CANVAS_LAYER := -10     # negative → renders behind the world (star dots are at layer 0, z -100)
const NEBULA_DOWNSCALE    := 1       # 1 = full res (half-res bilinear upscale was averaging out the anti-band dither → banding/facets)
# Hero stars (bright 4-point cross-flares). Set HERO_STAR_COUNT = 0 to disable. Shared by both variants.
const HERO_STAR_COUNT := 7
const HERO_PARALLAX   := 0.16        # deep (nearest background layer, but far from surface speed)
const HERO_TILE       := 1024
const HERO_Z          := -90
const HERO_CORE_SIZE  := 3.0
const HERO_FLARE_LEN  := 60.0
const HERO_COLOR      := Color(0.85, 0.92, 1.0)

# ── BACKGROUND_1 (cached) TUNABLES ────────────────────────────────────────────
const BG1_SHADER       := "res://assets/shaders/nebula_bg.gdshader"
# On-screen drift ratio ≈ SCROLL_FACTOR × screen_width / BASE_SCALE. At 0.00002 × 1440 / 3 ≈ 0.0096,
# the nebula moves at ~1% of camera speed — barely at all, and the FURTHEST layer (slowest star = 0.03).
const BG1_SCROLL_FACTOR := 0.000104
const BG1_TIME_DRIFT   := 0.005
const BG1_OCTAVES      := 6           # original
const BG1_BASE_SCALE   := 2.0         # original
const BG1_WARP_STRENGTH := 3.0        # original
const BG1_CLOUD_COVERAGE := 0.42
const BG1_CLOUD_SOFTNESS := 0.45      # original (the "smokier" tune is reverted; simplex noise swap kept)
const BG1_COV_FADE_LO    := 0.15      # gas starts fading in this far BELOW coverage (wider = softer onset)
const BG1_COV_FADE_HI    := 0.6       # gas reaches full this far ABOVE coverage (wider = no silhouette rim)
const BG1_BRIGHTNESS   := 0.9         # base gas brightness (× gas_brightness below)
const BG1_GAS_BRIGHTNESS := 2.2       # gas is the HERO — much brighter than the old thin wash
const BG1_GAS_OPACITY    := 1.25      # softened so cloud edges don't posterize into hard facets
# Brightness heatmap (smooth clusters of similar "temperature"). Tempered range + wide remap = no edges.
const BG1_BRIGHT_VAR_MIN   := 0.35
const BG1_BRIGHT_VAR_MAX   := 2.4
const BG1_BRIGHT_VAR_SCALE := 0.5
# Macro biome regions (huge-scale void ↔ dense nebula; the "sense of place").
const BG1_BIOME_SCALE       := 0.05   # SMALL = huge regions (one cycle ≈ many screens)
const BG1_BIOME_WARP        := 1.2    # medium-freq domain warp → region boundaries snake (no straight edge)
const BG1_VOID_THRESHOLD    := 0.35   # below → empty void
const BG1_DENSE_THRESHOLD   := 0.72   # above → dense nebula (wide band = soft fade)
const BG1_CLUSTER_STRENGTH  := 2.2    # star-density multiplier in dense regions
const BG1_REGION_COLOR_SCALE := 0.07  # slow field for dominant region hue (big colour blocks)
const BG1_LANDMARK_SCALE     := 0.8   # coarse grid for rare landmarks (low = big, far apart)
const BG1_LANDMARK_RARITY    := 0.05  # fraction of coarse cells with a landmark
const BG1_LANDMARK_SIZE      := 0.35  # nebula-core glow radius
const BG1_LANDMARK_INTENSITY := 1.6
# HDR tone curve: crush voids toward black, lift cores toward white. (Eased so brighter gas doesn't blow out.)
const BG1_CONTRAST     := 1.05       # eased from 1.15 so the pow curve stops re-sharpening the cloud-edge fade
const BG1_EXPOSURE     := 1.0
# Glowing cores.
const BG1_CORE_THRESHOLD := 0.78
const BG1_CORE_INTENSITY := 2.2
# Stars — tier A (tiny pinpoints) + tier B (big colored bloom/flare).
const BG1_STAR_DENSITY        := 0.07
const BG1_STAR_BRIGHTNESS     := 0.4    # faint pinprick texture (stars are quiet; gas is the drama)
const BG1_BRIGHT_STAR_DENSITY := 0.07   # total bright stars (mostly small/faint)
const BG1_BRIGHT_STAR_SCALE   := 2.2
const BG1_BIG_STAR_RARITY     := 0.07   # fraction that are big/showy
const BG1_HALO_SIZE           := 0.14   # soft halo radius (contained gaussian → no boxes)
const BG1_MAX_FLARE           := 0.5    # max cross-flare arm length (only used if flares enabled below)
const BG1_BLOOM_STRENGTH      := 0.6    # colored light bleed into surrounding gas
const BG1_STAR_SIZE_MULT      := 0.6    # shrinks bright-star core + halo (turn stars down)
const BG1_BLOOM_MULT          := 0.4    # cuts bright-star gas-bleed
const BG1_STARW_BLUE          := 0.18   # colour weights (most stars white = remainder)
const BG1_STARW_GOLD          := 0.12
const BG1_STARW_RED           := 0.05
const BG1_FLAREMIX_NONE       := 1.0    # flare-shape mix: none / 4-point / 6-point — default ALL none (no beams)
const BG1_FLAREMIX_FOUR       := 0.0
const BG1_BRIGHT_STAR_BRIGHTNESS := 0.5   # turned down — stars are quiet texture
# Colours.
const BG1_COL_VOID  := Color(0.012, 0.012, 0.03)   # near-black navy void
const BG1_WARM_LO   := Color(0.32, 0.05, 0.06)     # warm ramp: deep red → orange → gold
const BG1_WARM_MID  := Color(0.85, 0.30, 0.10)
const BG1_WARM_HI   := Color(1.00, 0.78, 0.42)
const BG1_COOL_LO   := Color(0.10, 0.10, 0.34)     # cool ramp: indigo → blue → cyan-white
const BG1_COOL_MID  := Color(0.18, 0.34, 0.78)
const BG1_COOL_HI   := Color(0.70, 0.92, 1.00)
const BG1_CORE_COLOR := Color(1.00, 0.95, 0.88)    # hot emission tint for cores

# ── BACKGROUND_2 (baked mask × colour) TUNABLES ───────────────────────────────
const BG2_SHADER        := "res://assets/shaders/nebula_baked.gdshader"
const BG2_SCROLL_FACTOR := 0.0014    # smallest of all layers → DEEPEST (crawls slower than every star layer)
const BG2_TEX_SIZE      := 512       # baked seamless texture resolution
const BG2_SCALE_A       := 1.5       # tiles of cloud layer A across the screen
const BG2_SCALE_B       := 2.3       # cloud layer B (finer)
const BG2_SCALE_MASK    := 1.1       # void/filament mask
const BG2_SCROLL_A      := 1.0       # per-layer scroll-rate multipliers (depth)
const BG2_SCROLL_B      := 1.4
const BG2_COVERAGE      := 0.46      # void threshold (higher = more empty)
const BG2_MASK_CONTRAST := 0.28      # smaller = sharper, snakier filaments
const BG2_BRIGHTNESS    := 0.38      # dimmed further so it stays well behind gameplay
const BG2_STAR_DENSITY  := 0.06
const BG2_STAR_BRIGHTNESS := 0.7
const BG2_COL_VOID  := Color(0.02, 0.035, 0.09)  # dimmer deep navy-blue base (still lets warm pop)
const BG2_COL_WARM1 := Color(0.55, 0.16, 0.07)   # dim red filament
const BG2_COL_WARM2 := Color(0.95, 0.45, 0.16)   # bright orange filament
const BG2_COL_CORE  := Color(0.70, 0.85, 1.00)   # blue-white hottest cores
# Baked-noise params: [freq, octaves, fractal_type, noise_type, seed]
const BG2_NOISE_A    := [0.012, 4, FastNoiseLite.FRACTAL_FBM,    FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1]
const BG2_NOISE_B    := [0.022, 5, FastNoiseLite.FRACTAL_FBM,    FastNoiseLite.TYPE_PERLIN,         7]
const BG2_NOISE_MASK := [0.009, 4, FastNoiseLite.FRACTAL_RIDGED, FastNoiseLite.TYPE_SIMPLEX,        13]

# ── BACKGROUND_BLUE (teal + purple, structured, spiral galaxies) TUNABLES ─────
const BGB_SHADER        := "res://assets/shaders/nebula_blue.gdshader"
const BGB_SCROLL_FACTOR := 0.0001    # deep parallax (slow drift)
const BGB_OCTAVES       := 5         # fewer = softer, less shimmery fine detail
const BGB_BASE_SCALE    := 2.0       # bigger, softer features
const BGB_WARP_STRENGTH := 2.0       # gentler warp (3.2 folded the gas into shimmering veins)
const BGB_RIDGED_AMOUNT := 0.10      # mostly smooth gas with only faint filaments (was 0.30 → veiny)
const BGB_REGION_SCALE  := 0.45      # teal↔violet region size (lower = bigger blocks)
const BGB_COVERAGE      := 0.42
const BGB_GAS_BRIGHTNESS := 0.72     # 70% dimmer (was 2.4)
const BGB_GAS_OPACITY   := 1.1       # softer cloud edge (was 1.5 → posterized facets)
const BGB_CONTRAST      := 1.05      # gentler tone curve (was 1.2)
const BGB_EXPOSURE      := 1.1
const BGB_CORE_THRESHOLD := 0.74
const BGB_CORE_INTENSITY := 2.4
const BGB_STAR_DENSITY  := 0.10      # dense pinpoint stars
const BGB_STAR_BRIGHTNESS := 0.9
const BGB_BRIGHT_STAR_DENSITY := 0.12
const BGB_GALAXY_RARITY := 0.06      # spiral galaxies (sparse)
const BGB_GALAXY_INTENSITY := 1.3
const BGB_CLUSTER_RARITY := 0.08
const BGB_CLUSTER_INTENSITY := 1.5
const BGB_COL_VOID   := Color(0.02, 0.03, 0.10)
const BGB_TEAL_LO    := Color(0.03, 0.20, 0.22)
const BGB_TEAL_MID   := Color(0.10, 0.78, 0.66)
const BGB_TEAL_HI    := Color(0.70, 1.00, 0.92)
const BGB_VIOLET_LO  := Color(0.12, 0.08, 0.34)
const BGB_VIOLET_MID := Color(0.48, 0.20, 0.82)
const BGB_VIOLET_HI  := Color(0.88, 0.42, 0.95)
const BGB_COL_CORE   := Color(0.78, 0.96, 1.00)
const BGB_GALAXY_COLOR  := Color(0.65, 0.95, 1.00)
const BGB_CLUSTER_COLOR := Color(0.70, 0.90, 1.00)

# ── Runtime ───────────────────────────────────────────────────────────────────
const SPAWN_VARIETY := 2000.0   # random noise-units offset each load → a different patch of sky every time

var _container: SubViewportContainer = null
var _sub: SubViewport = null
var _rect: ColorRect = null
var _scroll_factor: float = 0.0025
var _spawn_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = NEBULA_CANVAS_LAYER
	# Random base sampling offset (arena._ready() calls randomize() before adding us) → each load shows a
	# different region of the deterministic nebula, without moving the player to imprecise huge coordinates.
	_spawn_offset = Vector2(randf_range(-SPAWN_VARIETY, SPAWN_VARIETY), randf_range(-SPAWN_VARIETY, SPAWN_VARIETY))

	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.stretch_shrink = NEBULA_DOWNSCALE
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_sub = SubViewport.new()
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # shader animates → render every frame
	_sub.disable_3d = true
	_sub.transparent_bg = false                                 # opaque backdrop
	_container.add_child(_sub)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match ACTIVE_BACKGROUND:
		2: _rect.material = _make_bg2_material()
		3: _rect.material = _make_bgblue_material()
		_: _rect.material = _make_bg1_material()
	_sub.add_child(_rect)

	# Anchors don't resolve against a CanvasLayer at _ready, so size the container explicitly to the
	# viewport (stretch then forces the SubViewport size; the full-rect ColorRect follows). Re-run on resize.
	get_viewport().size_changed.connect(_resize)
	call_deferred("_resize")

	if HERO_STAR_COUNT > 0:
		_build_hero_stars()

func _resize() -> void:
	if _container == null:
		return
	_container.position = Vector2.ZERO
	_container.size = get_viewport().get_visible_rect().size

# ── background_1: cached live domain-warped fBm shader ────────────────────────
func _make_bg1_material() -> ShaderMaterial:
	_scroll_factor = BG1_SCROLL_FACTOR
	var mat := ShaderMaterial.new()
	mat.shader = load(BG1_SHADER)
	mat.set_shader_parameter("world_offset", Vector2.ZERO)
	mat.set_shader_parameter("octaves", BG1_OCTAVES)
	mat.set_shader_parameter("base_scale", BG1_BASE_SCALE)
	mat.set_shader_parameter("time_drift", BG1_TIME_DRIFT)
	mat.set_shader_parameter("warp_strength", BG1_WARP_STRENGTH)
	mat.set_shader_parameter("cloud_coverage", BG1_CLOUD_COVERAGE)
	mat.set_shader_parameter("cloud_softness", BG1_CLOUD_SOFTNESS)
	mat.set_shader_parameter("cov_fade_lo", BG1_COV_FADE_LO)
	mat.set_shader_parameter("cov_fade_hi", BG1_COV_FADE_HI)
	mat.set_shader_parameter("brightness", BG1_BRIGHTNESS)
	mat.set_shader_parameter("gas_brightness", BG1_GAS_BRIGHTNESS)
	mat.set_shader_parameter("gas_opacity", BG1_GAS_OPACITY)
	mat.set_shader_parameter("bright_var_min", BG1_BRIGHT_VAR_MIN)
	mat.set_shader_parameter("bright_var_max", BG1_BRIGHT_VAR_MAX)
	mat.set_shader_parameter("bright_var_scale", BG1_BRIGHT_VAR_SCALE)
	mat.set_shader_parameter("biome_scale", BG1_BIOME_SCALE)
	mat.set_shader_parameter("biome_warp", BG1_BIOME_WARP)
	mat.set_shader_parameter("void_threshold", BG1_VOID_THRESHOLD)
	mat.set_shader_parameter("dense_threshold", BG1_DENSE_THRESHOLD)
	mat.set_shader_parameter("cluster_strength", BG1_CLUSTER_STRENGTH)
	mat.set_shader_parameter("region_color_scale", BG1_REGION_COLOR_SCALE)
	mat.set_shader_parameter("landmark_scale", BG1_LANDMARK_SCALE)
	mat.set_shader_parameter("landmark_rarity", BG1_LANDMARK_RARITY)
	mat.set_shader_parameter("landmark_size", BG1_LANDMARK_SIZE)
	mat.set_shader_parameter("landmark_intensity", BG1_LANDMARK_INTENSITY)
	mat.set_shader_parameter("contrast", BG1_CONTRAST)
	mat.set_shader_parameter("exposure", BG1_EXPOSURE)
	mat.set_shader_parameter("core_threshold", BG1_CORE_THRESHOLD)
	mat.set_shader_parameter("core_intensity", BG1_CORE_INTENSITY)
	mat.set_shader_parameter("star_density", BG1_STAR_DENSITY)
	mat.set_shader_parameter("star_brightness", BG1_STAR_BRIGHTNESS)
	mat.set_shader_parameter("bright_star_density", BG1_BRIGHT_STAR_DENSITY)
	mat.set_shader_parameter("bright_star_scale", BG1_BRIGHT_STAR_SCALE)
	mat.set_shader_parameter("big_star_rarity", BG1_BIG_STAR_RARITY)
	mat.set_shader_parameter("halo_size", BG1_HALO_SIZE)
	mat.set_shader_parameter("max_flare", BG1_MAX_FLARE)
	mat.set_shader_parameter("bloom_strength", BG1_BLOOM_STRENGTH)
	mat.set_shader_parameter("starw_blue", BG1_STARW_BLUE)
	mat.set_shader_parameter("starw_gold", BG1_STARW_GOLD)
	mat.set_shader_parameter("starw_red", BG1_STARW_RED)
	mat.set_shader_parameter("flaremix_none", BG1_FLAREMIX_NONE)
	mat.set_shader_parameter("flaremix_four", BG1_FLAREMIX_FOUR)
	mat.set_shader_parameter("bright_star_brightness", BG1_BRIGHT_STAR_BRIGHTNESS)
	mat.set_shader_parameter("star_size_mult", BG1_STAR_SIZE_MULT)
	mat.set_shader_parameter("bloom_mult", BG1_BLOOM_MULT)
	mat.set_shader_parameter("col_void", BG1_COL_VOID)
	mat.set_shader_parameter("warm_lo", BG1_WARM_LO)
	mat.set_shader_parameter("warm_mid", BG1_WARM_MID)
	mat.set_shader_parameter("warm_hi", BG1_WARM_HI)
	mat.set_shader_parameter("cool_lo", BG1_COOL_LO)
	mat.set_shader_parameter("cool_mid", BG1_COOL_MID)
	mat.set_shader_parameter("cool_hi", BG1_COOL_HI)
	mat.set_shader_parameter("core_color", BG1_CORE_COLOR)
	return mat

# ── background_2: baked seamless noise textures, sampled + scrolled (cheap) ────
func _make_bg2_material() -> ShaderMaterial:
	_scroll_factor = BG2_SCROLL_FACTOR
	var mat := ShaderMaterial.new()
	mat.shader = load(BG2_SHADER)
	mat.set_shader_parameter("tex_a", _make_noise_tex(BG2_NOISE_A))
	mat.set_shader_parameter("tex_b", _make_noise_tex(BG2_NOISE_B))
	mat.set_shader_parameter("tex_mask", _make_noise_tex(BG2_NOISE_MASK))
	mat.set_shader_parameter("world_offset", Vector2.ZERO)
	mat.set_shader_parameter("scale_a", BG2_SCALE_A)
	mat.set_shader_parameter("scale_b", BG2_SCALE_B)
	mat.set_shader_parameter("scale_mask", BG2_SCALE_MASK)
	mat.set_shader_parameter("scroll_a", BG2_SCROLL_A)
	mat.set_shader_parameter("scroll_b", BG2_SCROLL_B)
	mat.set_shader_parameter("coverage", BG2_COVERAGE)
	mat.set_shader_parameter("mask_contrast", BG2_MASK_CONTRAST)
	mat.set_shader_parameter("brightness", BG2_BRIGHTNESS)
	mat.set_shader_parameter("star_density", BG2_STAR_DENSITY)
	mat.set_shader_parameter("star_brightness", BG2_STAR_BRIGHTNESS)
	mat.set_shader_parameter("col_void", BG2_COL_VOID)
	mat.set_shader_parameter("col_warm1", BG2_COL_WARM1)
	mat.set_shader_parameter("col_warm2", BG2_COL_WARM2)
	mat.set_shader_parameter("col_core", BG2_COL_CORE)
	return mat

## Bake one seamless noise texture from a [freq, octaves, fractal_type, noise_type, seed] spec.
## NoiseTexture2D generates on a thread at load → no per-frame cost; the runtime shader only samples it.
func _make_noise_tex(spec: Array) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = float(spec[0])
	n.fractal_octaves = int(spec[1])
	n.fractal_type = spec[2]
	n.noise_type = spec[3]
	n.seed = int(spec[4])
	var tex := NoiseTexture2D.new()
	tex.width = BG2_TEX_SIZE
	tex.height = BG2_TEX_SIZE
	tex.seamless = true        # tiles forever → infinite scroll with no visible repeat
	tex.normalize = true       # map output to 0..1
	tex.noise = n
	return tex

# ── background_blue: live teal+purple structured nebula with spiral galaxies + clusters ───────
func _make_bgblue_material() -> ShaderMaterial:
	_scroll_factor = BGB_SCROLL_FACTOR
	var mat := ShaderMaterial.new()
	mat.shader = load(BGB_SHADER)
	mat.set_shader_parameter("world_offset", Vector2.ZERO)
	mat.set_shader_parameter("octaves", BGB_OCTAVES)
	mat.set_shader_parameter("base_scale", BGB_BASE_SCALE)
	mat.set_shader_parameter("warp_strength", BGB_WARP_STRENGTH)
	mat.set_shader_parameter("ridged_amount", BGB_RIDGED_AMOUNT)
	mat.set_shader_parameter("region_scale", BGB_REGION_SCALE)
	mat.set_shader_parameter("coverage", BGB_COVERAGE)
	mat.set_shader_parameter("gas_brightness", BGB_GAS_BRIGHTNESS)
	mat.set_shader_parameter("gas_opacity", BGB_GAS_OPACITY)
	mat.set_shader_parameter("contrast", BGB_CONTRAST)
	mat.set_shader_parameter("exposure", BGB_EXPOSURE)
	mat.set_shader_parameter("core_threshold", BGB_CORE_THRESHOLD)
	mat.set_shader_parameter("core_intensity", BGB_CORE_INTENSITY)
	mat.set_shader_parameter("star_density", BGB_STAR_DENSITY)
	mat.set_shader_parameter("star_brightness", BGB_STAR_BRIGHTNESS)
	mat.set_shader_parameter("bright_star_density", BGB_BRIGHT_STAR_DENSITY)
	mat.set_shader_parameter("galaxy_rarity", BGB_GALAXY_RARITY)
	mat.set_shader_parameter("galaxy_intensity", BGB_GALAXY_INTENSITY)
	mat.set_shader_parameter("cluster_rarity", BGB_CLUSTER_RARITY)
	mat.set_shader_parameter("cluster_intensity", BGB_CLUSTER_INTENSITY)
	mat.set_shader_parameter("col_void", BGB_COL_VOID)
	mat.set_shader_parameter("teal_lo", BGB_TEAL_LO)
	mat.set_shader_parameter("teal_mid", BGB_TEAL_MID)
	mat.set_shader_parameter("teal_hi", BGB_TEAL_HI)
	mat.set_shader_parameter("violet_lo", BGB_VIOLET_LO)
	mat.set_shader_parameter("violet_mid", BGB_VIOLET_MID)
	mat.set_shader_parameter("violet_hi", BGB_VIOLET_HI)
	mat.set_shader_parameter("col_core", BGB_COL_CORE)
	mat.set_shader_parameter("galaxy_color", BGB_GALAXY_COLOR)
	mat.set_shader_parameter("cluster_color", BGB_CLUSTER_COLOR)
	return mat

## A near layer of bright cross-flare stars, added to the arena world (layer 0) so it parallax-scrolls.
func _build_hero_stars() -> void:
	var px := Parallax2D.new()
	px.scroll_scale = Vector2(HERO_PARALLAX, HERO_PARALLAX)
	px.repeat_size = Vector2(float(HERO_TILE), float(HERO_TILE))
	px.repeat_times = 3
	px.z_index = HERO_Z
	var spr := Sprite2D.new()
	spr.texture = _make_hero_tex()
	spr.centered = false
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive glow
	spr.material = cm
	px.add_child(spr)
	get_parent().add_child(px)   # sibling of the player in the arena world

## Procedural hero-star texture: a few bright cores each with a 4-point cross-flare, on a transparent tile.
func _make_hero_tex() -> Texture2D:
	var img := Image.create(HERO_TILE, HERO_TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var margin := int(ceil(HERO_FLARE_LEN)) + 2
	for _k in HERO_STAR_COUNT:
		var cx := randi_range(margin, HERO_TILE - 1 - margin)
		var cy := randi_range(margin, HERO_TILE - 1 - margin)
		var bright := randf_range(0.7, 1.0)
		var arm := int(HERO_FLARE_LEN)
		for d in range(1, arm + 1):
			var f := 1.0 - float(d) / float(arm)
			var a := bright * f * f * 0.8
			_add_px(img, cx + d, cy, HERO_COLOR, a)
			_add_px(img, cx - d, cy, HERO_COLOR, a)
			_add_px(img, cx, cy + d, HERO_COLOR, a)
			_add_px(img, cx, cy - d, HERO_COLOR, a)
		var r := int(ceil(HERO_CORE_SIZE))
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				var dist := Vector2(ox, oy).length()
				if dist <= HERO_CORE_SIZE:
					var a := bright * (1.0 - dist / HERO_CORE_SIZE)
					_add_px(img, cx + ox, cy + oy, Color(1, 1, 1, 1), a)
	return ImageTexture.create_from_image(img)

## Additively blend a colour onto a pixel (clamped), so overlapping flares accumulate brightness.
func _add_px(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= HERO_TILE or y >= HERO_TILE or a <= 0.0:
		return
	var cur := img.get_pixel(x, y)
	var out := Color(
		minf(1.0, cur.r + col.r * a),
		minf(1.0, cur.g + col.g * a),
		minf(1.0, cur.b + col.b * a),
		minf(1.0, cur.a + a))
	img.set_pixel(x, y, out)

func _process(_delta: float) -> void:
	if _rect == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var mat := _rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("world_offset", cam.global_position * _scroll_factor + _spawn_offset)
