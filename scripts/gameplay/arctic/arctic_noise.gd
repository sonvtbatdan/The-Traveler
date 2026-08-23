extends RefCounted
class_name ArcticNoise
## CPU-side noise for Arctic — port of mechanic_noise.gd (see that file's header for the full FastNoiseLite
## rationale). biome_value() drives zone tint / asset placement; is_river() keeps scattered assets off the
## river band.
##
## 2026-08-19, on request ("hệ thống blend dynamic tự động phát hiện và blend dựa trên số ảnh có trong
## folder"): unlike Mechanic's FIXED 7-photo blend, Arctic's canopy blend is DYNAMIC — however many photos
## ArcticAssetScan finds in the current maptile set (currently 4, "sau này có thể sẽ bổ sung thêm") drives the
## split, up to MAX_CANOPY. Every function that used to assume "7 photos, 6 fixed seams" here now takes the
## LIVE `canopy_count` as a parameter instead — see arctic_ground.gd/arctic_ground.gdshader's own headers for
## the shader-side half of this (a fixed MAX_CANOPY uniform slots + a `canopy_count` uniform that gates how
## many of them are actually blended, rather than a hardcoded 7-way chain).

const ArcticConfig := preload("res://scripts/gameplay/arctic/arctic_config.gd")

## Hard cap on how many canopy photos the shader/blend chain supports — see arctic_ground.gdshader's header.
## Raise this (and add matching uniform slots to the shader) if the map ever needs more than this many photos
## blended at once; 10 is a generous headroom over the 4 currently shipped.
const MAX_CANOPY := 10

static var _fnl: FastNoiseLite = null
static var _fnl_corridor: FastNoiseLite = null

static func _ensure() -> FastNoiseLite:
	if _fnl == null:
		_fnl = FastNoiseLite.new()
		_fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl.fractal_octaves = 4
		_fnl.frequency = ArcticConfig.NOISE_FREQ
		_fnl.seed = 1
	return _fnl

## 0..1 output (FastNoiseLite.get_noise_2d returns roughly -1..1).
static func biome_value(world_pos: Vector2) -> float:
	return _ensure().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

static func _ensure_corridor() -> FastNoiseLite:
	if _fnl_corridor == null:
		_fnl_corridor = FastNoiseLite.new()
		_fnl_corridor.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl_corridor.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_corridor.fractal_octaves = 3
		_fnl_corridor.frequency = ArcticConfig.RIVER_CORRIDOR_FREQ
		_fnl_corridor.seed = 5   # different from biome's seed(1)/mottle's seed(47) — see ArcticConfig
	return _fnl_corridor

## 0..1 output for the river CORRIDOR gate — see ArcticConfig.RIVER_CORRIDOR_FREQ's header and
## arctic_ground.gdshader's tex_river.
static func river_corridor_value(world_pos: Vector2) -> float:
	return _ensure_corridor().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## The `canopy_count - 1` canopy-blend seam levels (k/canopy_count, k=1..canopy_count-1) in mottle-value
## space — must match arctic_ground.gdshader's river_dist computation exactly (same levels, just computed
## there via a per-slot ternary gated on canopy_count instead of an array here).
static func seam_levels(canopy_count: int) -> Array:
	var n: int = clampi(canopy_count, 1, MAX_CANOPY)
	var out: Array = []
	for k in range(1, n):
		out.append(float(k) / float(n))
	return out

## True if world_pos falls inside the river band — used by arctic_trees.gd/arctic_plumes.gd to keep scattered
## assets/vents off rivers. The river runs along `river_count` of the canopy blend's own seam lines
## (arctic_ground.gdshader's river_dist) instead of an independent noise field, gated by the same low-
## frequency CORRIDOR band the shader applies — mirrors mechanic_noise.gd's own is_river() exactly, just with
## `canopy_count` threaded through instead of a fixed 7.
static func is_river(world_pos: Vector2, half_width: float, mottle_uv_scale: float, river_count: int, canopy_count: int) -> bool:
	if river_count <= 0 or half_width <= 0.0:
		return false
	if absf(river_corridor_value(world_pos) - ArcticConfig.RIVER_CORRIDOR_LEVEL) >= ArcticConfig.RIVER_CORRIDOR_HALF_WIDTH:
		return false   # outside the long winding corridor — matches the shader's own gating
	var m := mottle_value(world_pos, mottle_uv_scale)
	var levels := seam_levels(canopy_count)
	var n: int = mini(river_count, levels.size())
	for i in n:
		if absf(m - float(levels[i])) < half_width:
			return true
	return false

## Cheap decorrelated hash for placement dice-rolls — NOT used for a smooth field.
static func hash21(p: Vector2) -> float:
	var s: float = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return s - floor(s)

# ── Ground-photo region classifier (for arctic_vent_mark.gd / arctic_plumes.gd) ────────────────────────────
## A vent the user marks on the reference maptile photo (arctic_vent_mark.gd) only actually shows on screen
## wherever THAT photo is the one arctic_ground.gdshader picked for a given world position — see its
## fragment()'s mottle/region split. These are a CPU-side approximation of that same split (raw FastNoiseLite
## vs the shader's baked-and-wrapped NoiseTexture2D — "roughly the same shape," not pixel-exact) so
## arctic_plumes.gd can decide, for each candidate repetition of a mark, whether that photo is actually the
## one showing there before spawning a vent.
##
## mottle_uv_scale is a LIVE Terrain Edit slider ("Canopy Blend Sparseness") — mottle_value()/ground_region()
## take it as a PARAMETER instead of a hardcoded const; arctic_plumes.gd tracks the current value (synced via
## apply_canopy_mottle_scale) and passes it in. canopy_count is likewise live (auto-detected from the maptile
## set's image count) and passed in by the same callers.
const MOTTLE_TILE_CYCLES := 10.0   # must match arctic_ground.gd's MOTTLE_TILE_CYCLES
const MOTTLE_OCTAVES := 2          # must match arctic_ground.gd's MOTTLE_OCTAVES
const MOTTLE_SEED := 47            # must match arctic_ground.gd's _make_noise_tex(... 47) call

## Per-texture UV scale multiplier / offset, one entry per MAX_CANOPY slot — must match
## arctic_ground.gdshader's uv_0..uv_9 formulas exactly (positional, matching ArcticAssetScan.
## maptile_set_image_paths()' order). Slots beyond however many photos actually exist are simply never
## selected (ground_region()/the shader's region split both clamp to canopy_count), so their values here are
## inert placeholders reserved for future photos, not currently-live tuning.
const GROUND_UV_MULT := [1.0, 1.18, 0.87, 1.32, 0.79, 1.24, 0.72, 1.41, 0.65, 1.09]
const GROUND_UV_OFFSET := [
	Vector2.ZERO, Vector2(311.0, -173.0), Vector2(-197.0, 421.0), Vector2(157.0, 289.0), Vector2(-421.0, -89.0),
	Vector2(233.0, -311.0), Vector2(-113.0, 197.0), Vector2(389.0, 101.0), Vector2(-271.0, -347.0), Vector2(97.0, -433.0),
]

static var _fnl_mottle: FastNoiseLite = null

static func _ensure_mottle() -> FastNoiseLite:
	if _fnl_mottle == null:
		_fnl_mottle = FastNoiseLite.new()
		_fnl_mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl_mottle.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_mottle.fractal_octaves = MOTTLE_OCTAVES
		_fnl_mottle.seed = MOTTLE_SEED
	return _fnl_mottle

## 0..1 output for the ground-photo REGION field — see arctic_ground.gdshader's `mottle`. `mottle_uv_scale`
## is the CURRENT live value (arctic_ground.gd's apply_canopy_mottle_scale) — frequency is derived fresh each
## call (cheap; FastNoiseLite has no per-query allocation) since it can change live via the panel.
static func mottle_value(world_pos: Vector2, mottle_uv_scale: float) -> float:
	var n := _ensure_mottle()
	n.frequency = MOTTLE_TILE_CYCLES * mottle_uv_scale
	return n.get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## Which of the currently-active `canopy_count` maptile photos (0-based) arctic_ground.gdshader would pick at
## world_pos — ignores the shader's soft blend band at each threshold (canopy_blend_width) since a mark is
## either clearly on one photo's turf or it isn't.
static func ground_region(world_pos: Vector2, mottle_uv_scale: float, canopy_count: int) -> int:
	var n: int = clampi(canopy_count, 1, MAX_CANOPY)
	var m := mottle_value(world_pos, mottle_uv_scale)
	return clampi(int(m * float(n)), 0, n - 1)
