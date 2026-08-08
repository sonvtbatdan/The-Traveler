extends RefCounted
class_name VolcanicNoise
## CPU-side noise for Volcanic. Mirrors rubicon/rubicon_noise.gd (same FastNoiseLite-based approach, not a
## hand-rolled hash/fbm — see that file for the full rationale). The lava-flow field is TWO noises combined,
## not one:
##   1. A macro path from smooth SIMPLEX noise (river_value) — same technique/frequency as Rubicon's river,
##      giving an organic, naturally meandering flow instead of a mathematically straight shape.
##   2. A small perturbation from CELLULAR/Manhattan-distance noise, much higher frequency (river_detail_value)
##      — added to the macro distance in is_river()/the shader to roughen the BOUNDARY into jagged cracked-rock
##      nicks without altering the overall path.
## An earlier version used cellular noise ALONE as the macro field — Voronoi cell edges are literally straight
## line segments meeting at sharp vertices, so the whole river read as a mathematical zigzag polyline instead
## of a natural lava flow (user feedback: "như những đường thẳng gấp khúc"). Domain-warping a smooth macro
## curve with a small high-frequency detail term is the standard fix: natural large-scale flow, jagged
## small-scale edge — see volcanic_ground.gdshader's fragment() for the GPU-side mirror of this same math.
## biome_value() (the zone-tint split, unrelated to the lava border) stays simplex/soft, same as Rubicon.

const VolcanicConfig := preload("res://scripts/gameplay/volcanic/volcanic_config.gd")

## Detail field frequency = macro field frequency * this — high enough to read as small jagged nicks along
## the bank, low enough to still look like cracked rock rather than uniform static. Must match
## volcanic_ground.gd's RIVER_DETAIL_FREQ_MULT (GPU bake uses the same multiplier so CPU avoidance and GPU
## paint agree on roughly where the lava is — "roughly," not pixel-exact, same tolerance Rubicon documents
## for its own baked-vs-raw noise mismatch).
const RIVER_DETAIL_FREQ_MULT := 7.0
## Detail perturbation amplitude, as a fraction of river_width. Must match volcanic_ground.gdshader's
## river_detail_strength uniform.
const RIVER_DETAIL_STRENGTH := 0.55

static var _fnl: FastNoiseLite = null
static var _fnl_river: FastNoiseLite = null
static var _fnl_river_detail: FastNoiseLite = null

static func _ensure() -> FastNoiseLite:
	if _fnl == null:
		_fnl = FastNoiseLite.new()
		_fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl.fractal_octaves = 4
		_fnl.frequency = VolcanicConfig.NOISE_FREQ
		_fnl.seed = 21
	return _fnl

## 0..1 output — see RubiconNoise.biome_value(); same convention so VolcanicConfig.BLUE_THRESHOLD/
## BLEND_SOFTNESS apply unchanged.
static func biome_value(world_pos: Vector2) -> float:
	return _ensure().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

static func _ensure_river() -> FastNoiseLite:
	if _fnl_river == null:
		_fnl_river = FastNoiseLite.new()
		_fnl_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH   # organic macro path — see header
		_fnl_river.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_river.fractal_octaves = 3
		_fnl_river.frequency = VolcanicConfig.RIVER_NOISE_FREQ
		_fnl_river.seed = 8   # different from biome's seed(21) so the lava flow doesn't line up with zone edges
	return _fnl_river

static func _ensure_river_detail() -> FastNoiseLite:
	if _fnl_river_detail == null:
		_fnl_river_detail = FastNoiseLite.new()
		_fnl_river_detail.noise_type = FastNoiseLite.TYPE_CELLULAR
		_fnl_river_detail.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN   # diamond-faceted nicks
		_fnl_river_detail.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		_fnl_river_detail.fractal_type = FastNoiseLite.FRACTAL_NONE
		_fnl_river_detail.frequency = VolcanicConfig.RIVER_NOISE_FREQ * RIVER_DETAIL_FREQ_MULT
		_fnl_river_detail.seed = 13
	return _fnl_river_detail

## 0..1 output for the lava-flow MACRO contour field — see VolcanicConfig.RIVER_LEVEL/RIVER_NOISE_FREQ.
static func river_value(world_pos: Vector2) -> float:
	return _ensure_river().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## 0..1 output for the high-frequency edge-jag DETAIL field — see this file's header.
static func river_detail_value(world_pos: Vector2) -> float:
	return _ensure_river_detail().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## True if world_pos falls inside the lava band (within half_width of RIVER_LEVEL, after the same
## detail-jag perturbation volcanic_ground.gdshader applies) — used to keep scattered assets off the lava,
## same convention as RubiconNoise.is_river.
static func is_river(world_pos: Vector2, half_width: float) -> bool:
	var dist := absf(river_value(world_pos) - VolcanicConfig.RIVER_LEVEL)
	dist -= (river_detail_value(world_pos) - 0.5) * half_width * RIVER_DETAIL_STRENGTH
	return dist < half_width

## Cheap decorrelated hash for placement dice-rolls — identical to RubiconNoise.hash21.
static func hash21(p: Vector2) -> float:
	var s: float = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return s - floor(s)

# ── Ground-photo region classifier (for volcanic_crater_mark.gd / volcanic_clouds.gd) ─────────────────────
## A crater the user marks on the reference maptile photo (volcanic_crater_mark.gd) only actually shows on
## screen wherever THAT photo (a/b/c) is the one volcanic_ground.gdshader picked for a given world position —
## see its fragment()'s mottle/t_ab/t_bc region split. These constants/functions are a CPU-side approximation
## of that same split (raw FastNoiseLite vs the shader's baked-and-wrapped NoiseTexture2D — "roughly the same
## shape," not pixel-exact, same tolerance already established for river_value()/biome_value() vs their GPU
## counterparts) so volcanic_clouds.gd can decide, for each candidate repetition of a mark, whether that photo
## is actually the one showing there before spawning a vent.
const MOTTLE_TILE_CYCLES := 20.0                    # must match volcanic_ground.gd's MOTTLE_TILE_CYCLES
const MOTTLE_UV_SCALE := (1.0 / 4000.0) * 5.3       # must match volcanic_ground.gd's MOTTLE_UV_SCALE
const MOTTLE_SEED := 67                             # must match volcanic_ground.gd's _make_noise_tex(... 67) call
## Per-texture UV scale multiplier / offset — must match volcanic_ground.gdshader's uv_a/uv_b/uv_c formulas
## exactly (tex index 0=a/1=b/2=c, matching VolcanicAssetScan.maptile_set_image_paths()' positional order).
const GROUND_UV_MULT := [1.0, 1.37, 0.79]
const GROUND_UV_OFFSET := [Vector2.ZERO, Vector2(311.0, -173.0), Vector2(-197.0, 421.0)]

static var _fnl_mottle: FastNoiseLite = null

static func _ensure_mottle() -> FastNoiseLite:
	if _fnl_mottle == null:
		_fnl_mottle = FastNoiseLite.new()
		_fnl_mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl_mottle.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_mottle.fractal_octaves = 3
		_fnl_mottle.frequency = MOTTLE_TILE_CYCLES * MOTTLE_UV_SCALE
		_fnl_mottle.seed = MOTTLE_SEED
	return _fnl_mottle

## 0..1 output for the ground-photo REGION field — see volcanic_ground.gdshader's `mottle`.
static func mottle_value(world_pos: Vector2) -> float:
	return _ensure_mottle().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## Which of the 3 maptile photos (0=a/1=b/2=c) volcanic_ground.gdshader would pick at world_pos — ignores the
## shader's soft blend band at each threshold (region_softness = 0.04) since a mark is either clearly on one
## photo's turf or it isn't; not worth the extra complexity for a placement heuristic.
static func ground_region(world_pos: Vector2) -> int:
	var m := mottle_value(world_pos)
	if m < 1.0 / 3.0:
		return 0
	elif m < 2.0 / 3.0:
		return 1
	return 2
