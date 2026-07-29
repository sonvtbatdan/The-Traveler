extends RefCounted
class_name RubiconNoise
## CPU-side noise for Rubicon. biome_value() drives grass/tree placement and wraps Godot's own
## FastNoiseLite (same primitive arena_nebula.gd already relies on for its baked seamless backgrounds) —
## NOT a hand-rolled hash/fbm. An earlier hand-rolled version showed a real banding artifact on GPU (see
## rubicon_ground.gdshader's history) that a from-scratch reimplementation risked repeating; FastNoiseLite
## is already proven in this codebase. The GPU ground/cloud shaders sample a NoiseTexture2D baked from a
## SEPARATE FastNoiseLite (see rubicon_ground.gd/_make_noise_tex) — the two aren't pixel-identical (the
## GPU bake gets seamless-tiling post-processing this raw CPU query doesn't), but for scattering decorative
## grass/trees over blotches hundreds of px wide, "roughly the same shape" is close enough; exact pixel
## agreement was over-engineering for a placeholder pass.

const RubiconConfig := preload("res://scripts/gameplay/rubicon/rubicon_config.gd")

static var _fnl: FastNoiseLite = null
static var _fnl_river: FastNoiseLite = null

static func _ensure() -> FastNoiseLite:
	if _fnl == null:
		_fnl = FastNoiseLite.new()
		_fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl.fractal_octaves = 4
		_fnl.frequency = RubiconConfig.NOISE_FREQ
		_fnl.seed = 1
	return _fnl

## 0..1 output (FastNoiseLite.get_noise_2d returns roughly -1..1) — same threshold convention the old
## hand-rolled fbm used, so RubiconConfig.BLUE_THRESHOLD/BLEND_SOFTNESS still apply unchanged.
static func biome_value(world_pos: Vector2) -> float:
	return _ensure().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

static func _ensure_river() -> FastNoiseLite:
	if _fnl_river == null:
		_fnl_river = FastNoiseLite.new()
		_fnl_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_fnl_river.fractal_type = FastNoiseLite.FRACTAL_FBM
		_fnl_river.fractal_octaves = 3
		_fnl_river.frequency = RubiconConfig.RIVER_NOISE_FREQ
		_fnl_river.seed = 5   # different from biome's seed(1) so rivers don't line up with biome edges
	return _fnl_river

## 0..1 output for the river contour field — see RubiconConfig.RIVER_LEVEL/RIVER_NOISE_FREQ.
static func river_value(world_pos: Vector2) -> float:
	return _ensure_river().get_noise_2d(world_pos.x, world_pos.y) * 0.5 + 0.5

## True if world_pos falls inside the river band (within half_width of RIVER_LEVEL) — used by
## rubicon_trees.gd to keep scattered assets off rivers.
static func is_river(world_pos: Vector2, half_width: float) -> bool:
	return absf(river_value(world_pos) - RubiconConfig.RIVER_LEVEL) < half_width

## Cheap decorrelated hash for placement dice-rolls (density chance, jitter offset, rotation, scale
## variant) — NOT used for a smooth field, so it doesn't need bilinear-interpolation quality.
static func hash21(p: Vector2) -> float:
	var s: float = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return s - floor(s)
