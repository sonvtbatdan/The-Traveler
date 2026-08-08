extends RefCounted
class_name AtlanticNoise
## CPU-side noise for Atlantic. Mirrors volcanic/volcanic_noise.gd (same FastNoiseLite-based approach, same
## "smooth macro path + high-frequency detail perturbation" trick for the current's edge) — see that file for
## the full rationale. Renamed lava-flow -> current throughout; biome_value() (the zone-tint split) stays
## simplex/soft, same as Volcanic/Rubicon.

const AtlanticConfig := preload("res://scripts/gameplay/atlantic/atlantic_config.gd")

## Detail field frequency = macro field frequency * this. Must match atlantic_ground.gd's
## RIVER_DETAIL_FREQ_MULT (GPU bake uses the same multiplier so CPU avoidance and GPU paint agree on roughly
## where the current is).
const RIVER_DETAIL_FREQ_MULT := 7.0
## Detail perturbation amplitude, as a fraction of river_width. Must match atlantic_ground.gdshader's
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
		_fnl.frequency = AtlanticConfig.NOISE_FREQ
		_fnl.seed = 41   # distinct from Rubicon(?)/Volcanic(21)'s own seeds
	return _fnl

## 0..1 output — see RubiconNoise/VolcanicNoise.biome_value(); same convention so AtlanticConfig.BLUE_THRESHOLD/
## BLEND_SOFTNESS apply unchanged.
static func biome_value(world_pos: Vector2) -> float:
	return _ensure().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

static func _ensure_river() -> FastNoiseLite:
	if _fnl_river == null:
		_fnl_river = FastNoiseLite.new()
		_fnl_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH   # organic macro path
		_fnl_river.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_river.fractal_octaves = 3
		_fnl_river.frequency = AtlanticConfig.RIVER_NOISE_FREQ
		_fnl_river.seed = 28   # different from biome's seed(41) so the current doesn't line up with zone edges
	return _fnl_river

static func _ensure_river_detail() -> FastNoiseLite:
	if _fnl_river_detail == null:
		_fnl_river_detail = FastNoiseLite.new()
		_fnl_river_detail.noise_type = FastNoiseLite.TYPE_CELLULAR
		_fnl_river_detail.cellular_distance_function = FastNoiseLite.DISTANCE_MANHATTAN   # diamond-faceted scour nicks
		_fnl_river_detail.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		_fnl_river_detail.fractal_type = FastNoiseLite.FRACTAL_NONE
		_fnl_river_detail.frequency = AtlanticConfig.RIVER_NOISE_FREQ * RIVER_DETAIL_FREQ_MULT
		_fnl_river_detail.seed = 33
	return _fnl_river_detail

## 0..1 output for the current MACRO contour field — see AtlanticConfig.RIVER_LEVEL/RIVER_NOISE_FREQ.
static func river_value(world_pos: Vector2) -> float:
	return _ensure_river().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## 0..1 output for the high-frequency edge-jag DETAIL field — see this file's header.
static func river_detail_value(world_pos: Vector2) -> float:
	return _ensure_river_detail().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## True if world_pos falls inside the current band (within half_width of RIVER_LEVEL, after the same
## detail-jag perturbation atlantic_ground.gdshader applies) — used to keep scattered assets off the current,
## same convention as VolcanicNoise.is_river.
static func is_river(world_pos: Vector2, half_width: float) -> bool:
	var dist := absf(river_value(world_pos) - AtlanticConfig.RIVER_LEVEL)
	dist -= (river_detail_value(world_pos) - 0.5) * half_width * RIVER_DETAIL_STRENGTH
	return dist < half_width

## Cheap decorrelated hash for placement dice-rolls — identical to RubiconNoise/VolcanicNoise.hash21.
static func hash21(p: Vector2) -> float:
	var s: float = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return s - floor(s)

# ── Ground-photo region classifier (for atlantic_crater_mark.gd / atlantic_clouds.gd) ─────────────────────
## A vent/source mark on the reference maptile photo (atlantic_crater_mark.gd) only actually shows on screen
## wherever THAT photo (a/b/c) is the one atlantic_ground.gdshader picked for a given world position — see its
## fragment()'s mottle/t_ab/t_bc region split. These constants/functions are a CPU-side approximation of that
## same split — see VolcanicNoise's own header for the full rationale (same tolerance).
const MOTTLE_TILE_CYCLES := 20.0                    # must match atlantic_ground.gd's MOTTLE_TILE_CYCLES
const MOTTLE_UV_SCALE := (1.0 / 4000.0) * 5.3       # must match atlantic_ground.gd's MOTTLE_UV_SCALE
const MOTTLE_SEED := 67                             # must match atlantic_ground.gd's _make_noise_tex(... 67) call
## Per-texture UV scale multiplier / offset — must match atlantic_ground.gdshader's uv_a/uv_b/uv_c formulas
## exactly (tex index 0=a/1=b/2=c, matching AtlanticAssetScan.maptile_set_image_paths()' positional order).
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

## 0..1 output for the ground-photo REGION field — see atlantic_ground.gdshader's `mottle`.
static func mottle_value(world_pos: Vector2) -> float:
	return _ensure_mottle().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## Which of the 3 maptile photos (0=a/1=b/2=c) atlantic_ground.gdshader would pick at world_pos — ignores the
## shader's soft blend band at each threshold (region_softness = 0.04), same as VolcanicNoise.ground_region.
static func ground_region(world_pos: Vector2) -> int:
	var m := mottle_value(world_pos)
	if m < 1.0 / 3.0:
		return 0
	elif m < 2.0 / 3.0:
		return 1
	return 2
