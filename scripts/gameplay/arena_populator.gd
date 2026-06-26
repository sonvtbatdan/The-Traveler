extends RefCounted
## Unified procedural placement for all non-surface celestial layers (planets, comets, structures, asteroids;
## galaxies/black holes later). One deterministic, streamable algorithm shared by every spawner:
##   1. Jittered grid       — per-cell seeded RNG (the existing hash), object at a randomized in-cell offset.
##   2. Biome density mask   — a low-frequency FastNoiseLite modulates each cell's spawn chance (regional
##                             variation: rich clusters vs empty voids), instead of a flat per-cell chance.
##   3. Per-type rarity weight — base spawn chance per type (common pass often, rare rarely).
##   4. Min-distance reject  — blue-noise: a candidate is kept only if no higher-priority candidate sits
##                             within its min-distance (checked in O(neighbour cells); "highest-priority-in-
##                             radius wins" → order-independent, so it's deterministic with no global state).
## Stateless static helper — determinism comes purely from cell coords + the fixed-seed noise field, so
## chunks load independently and flying back reproduces the same layout. Managers keep their own parallax/z/
## visuals; only the where/whether decision lives here.

enum { PLANET, COMET, STRUCTURE, ASTEROID }

# ── TUNABLES (all placement knobs live here) ────────────────────────────────────
const GLOBAL_DENSITY := 1.0        # global multiplier on every type's spawn chance
const BIOME_FREQ     := 0.00008    # biome noise frequency (low → regions span many screens)
const BIOME_SEED     := 1337       # fixed → deterministic regional field
const HOME_RADIUS    := 5000.0     # suppress ALL streamed bodies within this of the home (origin) — the curated
                                   # authored solar system owns the start area; procedural content only appears beyond it

# Per type: cell (px), weight (rarity = base per-cell chance), min_distance (px blue-noise spacing; 0 = off),
# hash_a/hash_b (deterministic per-type cell hash), jitter (± fraction of a cell), biome_strength (0..1 how
# strongly the biome modulates this type), group (setpiece exclusion group; types sharing a group AND a
# parallax factor mutually reject — -1 = none).
const CFG := {
	PLANET:    {"cell": 1500.0, "weight": 0.07,  "min_distance": 700.0,  "hash_a": 73856093,  "hash_b": 19349663,  "jitter": 0.30, "biome_strength": 0.70, "group": -1},
	COMET:     {"cell": 2600.0, "weight": 0.015, "min_distance": 0.0,    "hash_a": 40503131,  "hash_b": 326437,    "jitter": 0.40, "biome_strength": 0.50, "group": -1},
	STRUCTURE: {"cell": 3000.0, "weight": 0.05,  "min_distance": 2600.0, "hash_a": 374761393, "hash_b": 668265263, "jitter": 0.30, "biome_strength": 0.90, "group": 0},
	ASTEROID:  {"cell": 1100.0, "weight": 0.07,  "min_distance": 500.0,  "hash_a": 92837111,  "hash_b": 689287499, "jitter": 0.30, "biome_strength": 0.85, "group": -1},
}

static var _biome: FastNoiseLite = null
static var _scratch := RandomNumberGenerator.new()   # reused for neighbour evals (no per-call allocation)

static func _get_biome() -> FastNoiseLite:
	if _biome == null:
		_biome = FastNoiseLite.new()
		_biome.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_biome.seed = BIOME_SEED
		_biome.frequency = BIOME_FREQ
	return _biome

## Biome density at a world-ish position → 0..1 (low = void, high = cluster).
static func biome_at(pos: Vector2) -> float:
	return _get_biome().get_noise_2d(pos.x, pos.y) * 0.5 + 0.5

## Cell size for a type — managers use this to size their streaming loop (single source of truth).
static func cell_size(type: int) -> float:
	return CFG[type]["cell"]

## Evaluate a cell's candidate into `rng` (reseeded). Returns {has, pos, pri}; leaves `rng` positioned past
## the placement rolls so an accepted cell's rng can continue with the manager's type-specific rolls.
static func _eval(type: int, cell: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = CFG[type]
	var cs: float = cfg["cell"]
	rng.seed = hash(Vector2i(cell.x * int(cfg["hash_a"]), cell.y * int(cfg["hash_b"])))
	var pri := rng.randf()
	var jit: float = cfg["jitter"]
	var off := Vector2(rng.randf_range(-jit, jit), rng.randf_range(-jit, jit)) * cs
	var pos := Vector2(cell) * cs + Vector2(cs, cs) * 0.5 + off
	var bstr: float = cfg["biome_strength"]
	var bmod := lerpf(1.0 - bstr, 1.0 + bstr, biome_at(pos))
	var chance: float = float(cfg["weight"]) * GLOBAL_DENSITY * bmod
	var has := rng.randf() < chance
	return {"has": has, "pos": pos, "pri": pri}

static func _tiebreak(cell: Vector2i) -> int:
	return hash(cell)

## Decide whether (and where) `type` places an object in `cell`. Returns {} (nothing) or {pos, rng} where rng
## is ready for the manager's type-specific rolls. Deterministic + O(neighbour cells).
static func place_in_cell(type: int, cell: Vector2i) -> Dictionary:
	var c := _eval(type, cell, _scratch)
	if not c["has"]:
		return {}
	if (c["pos"] as Vector2).length() < HOME_RADIUS:
		return {}   # inside the home zone — leave it to the authored solar system
	var cpos: Vector2 = c["pos"]
	var cpri: float = c["pri"]
	var cfg: Dictionary = CFG[type]
	var self_min: float = cfg["min_distance"]
	var group: int = int(cfg["group"])
	# Reject if a higher-priority candidate (this type, or a same-group setpiece peer) sits within min-distance.
	for peer_type in CFG.keys():
		var pcfg: Dictionary = CFG[peer_type]
		var is_self: bool = peer_type == type
		var is_peer: bool = group >= 0 and not is_self and int(pcfg["group"]) == group
		if not is_self and not is_peer:
			continue
		var d: float = maxf(self_min, float(pcfg["min_distance"]))
		if d <= 0.0:
			continue
		var pcs: float = pcfg["cell"]
		var r := int(ceil(d / pcs)) + 1
		var base := Vector2i(int(floor(cpos.x / pcs)), int(floor(cpos.y / pcs)))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nk := base + Vector2i(dx, dy)
				if is_self and nk == cell:
					continue
				var nc := _eval(peer_type, nk, _scratch)
				if not nc["has"]:
					continue
				if cpos.distance_to(nc["pos"]) < d:
					var npri: float = nc["pri"]
					if npri > cpri or (npri == cpri and _tiebreak(nk) > _tiebreak(cell)):
						return {}   # a higher-priority neighbour claims this spot
	# Accepted: hand back a fresh rng positioned past the placement rolls for the manager to continue.
	var out := RandomNumberGenerator.new()
	_eval(type, cell, out)
	return {"pos": cpos, "rng": out}
