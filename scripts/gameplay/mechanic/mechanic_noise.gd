extends RefCounted
class_name MechanicNoise
## CPU-side noise for Mechanic — verbatim port of electric_noise.gd (see that file's header for the full
## FastNoiseLite rationale). biome_value() drives zone tint / asset placement; is_river() keeps scattered
## assets off the river band.

const MechanicConfig := preload("res://scripts/gameplay/mechanic/mechanic_config.gd")

static var _fnl: FastNoiseLite = null
static var _fnl_corridor: FastNoiseLite = null

static func _ensure() -> FastNoiseLite:
	if _fnl == null:
		_fnl = FastNoiseLite.new()
		_fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl.fractal_octaves = 4
		_fnl.frequency = MechanicConfig.NOISE_FREQ
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
		_fnl_corridor.frequency = MechanicConfig.RIVER_CORRIDOR_FREQ
		_fnl_corridor.seed = 5   # different from biome's seed(1)/mottle's seed(47) — see MechanicConfig
	return _fnl_corridor

## 0..1 output for the river CORRIDOR gate — see MechanicConfig.RIVER_CORRIDOR_FREQ's header and
## mechanic_ground.gdshader's tex_river (5th redesign).
static func river_corridor_value(world_pos: Vector2) -> float:
	return _ensure_corridor().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## The 6 canopy-blend seam levels (k/7, k=1..6) in mottle-value space — must match
## mechanic_ground.gdshader's river_dist computation exactly (same 6 levels, just computed inline there one
## `if (river_count >= k)` at a time instead of as a constant array).
const SEAM_LEVELS := [1.0 / 7.0, 2.0 / 7.0, 3.0 / 7.0, 4.0 / 7.0, 5.0 / 7.0, 6.0 / 7.0]

## True if world_pos falls inside the river band — used by mechanic_trees.gd/mechanic_plumes.gd to keep
## scattered assets/vents off rivers. 2026-08-19, 2 redesigns: the river runs along `river_count` of the
## canopy blend's own 6 seam lines (mechanic_ground.gdshader's river_dist) instead of an independent noise
## field, AND only within a much-lower-frequency CORRIDOR band (else the seam network's own small closed loops
## would count as "river" here too) — this CPU-side check mirrors BOTH exactly: same `mottle_value` sample
## (already used elsewhere in this file for the ground-photo region classifier) tested against the first
## `river_count` seam levels, gated by the same corridor test the shader applies.
static func is_river(world_pos: Vector2, half_width: float, mottle_uv_scale: float, river_count: int) -> bool:
	if river_count <= 0 or half_width <= 0.0:
		return false
	if absf(river_corridor_value(world_pos) - MechanicConfig.RIVER_CORRIDOR_LEVEL) >= MechanicConfig.RIVER_CORRIDOR_HALF_WIDTH:
		return false   # outside the long winding corridor — matches the shader's own gating
	var m := mottle_value(world_pos, mottle_uv_scale)
	var n: int = clampi(river_count, 0, SEAM_LEVELS.size())
	for i in n:
		if absf(m - SEAM_LEVELS[i]) < half_width:
			return true
	return false

## Cheap decorrelated hash for placement dice-rolls — NOT used for a smooth field.
static func hash21(p: Vector2) -> float:
	var s: float = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return s - floor(s)

# ── Ground-photo region classifier (for mechanic_vent_mark.gd / mechanic_plumes.gd) ────────────────────────
## A vent the user marks on the reference maptile photo (mechanic_vent_mark.gd) only actually shows on screen
## wherever THAT photo (a..g) is the one mechanic_ground.gdshader picked for a given world position — see its
## fragment()'s mottle/t1..t6 region split. These are a CPU-side approximation of that same split (raw
## FastNoiseLite vs the shader's baked-and-wrapped NoiseTexture2D — "roughly the same shape," not pixel-exact,
## same tolerance VolcanicNoise.ground_region() documents) so mechanic_plumes.gd can decide, for each candidate
## repetition of a mark, whether that photo is actually the one showing there before spawning a vent.
##
## Unlike Volcanic (fixed baked mottle frequency), Mechanic's mottle_uv_scale is a LIVE Terrain Edit slider
## ("Canopy Blend Sparseness") — mottle_value()/ground_region() take it as a PARAMETER instead of a hardcoded
## const; mechanic_plumes.gd tracks the current value (synced via apply_canopy_mottle_scale) and passes it in.
const MOTTLE_TILE_CYCLES := 10.0   # must match mechanic_ground.gd's MOTTLE_TILE_CYCLES
const MOTTLE_OCTAVES := 2          # must match mechanic_ground.gd's MOTTLE_OCTAVES
const MOTTLE_SEED := 47            # must match mechanic_ground.gd's _make_noise_tex(... 47) call
## Per-texture UV scale multiplier / offset — must match mechanic_ground.gdshader's uv_a..uv_g formulas
## exactly (tex index 0=a..6=g, matching MechanicAssetScan.maptile_set_image_paths()' positional order).
const GROUND_UV_MULT := [1.0, 1.18, 0.87, 1.32, 0.79, 1.24, 0.72]
const GROUND_UV_OFFSET := [Vector2.ZERO, Vector2(311.0, -173.0), Vector2(-197.0, 421.0), Vector2(157.0, 289.0), Vector2(-421.0, -89.0), Vector2(233.0, -311.0), Vector2(-113.0, 197.0)]

static var _fnl_mottle: FastNoiseLite = null

static func _ensure_mottle() -> FastNoiseLite:
	if _fnl_mottle == null:
		_fnl_mottle = FastNoiseLite.new()
		_fnl_mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl_mottle.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_mottle.fractal_octaves = MOTTLE_OCTAVES
		_fnl_mottle.seed = MOTTLE_SEED
	return _fnl_mottle

## 0..1 output for the ground-photo REGION field — see mechanic_ground.gdshader's `mottle`. `mottle_uv_scale`
## is the CURRENT live value (mechanic_ground.gd's apply_canopy_mottle_scale) — frequency is derived fresh
## each call (cheap; FastNoiseLite has no per-query allocation) since it can change live via the panel.
static func mottle_value(world_pos: Vector2, mottle_uv_scale: float) -> float:
	var n := _ensure_mottle()
	n.frequency = MOTTLE_TILE_CYCLES * mottle_uv_scale
	return n.get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## Which of the 7 maptile photos (0=a..6=g) mechanic_ground.gdshader would pick at world_pos — ignores the
## shader's soft blend band at each threshold (canopy_blend_width) since a mark is either clearly on one
## photo's turf or it isn't; not worth the extra complexity for a placement heuristic.
static func ground_region(world_pos: Vector2, mottle_uv_scale: float) -> int:
	var m := mottle_value(world_pos, mottle_uv_scale)
	return clampi(int(m * 7.0), 0, 6)
