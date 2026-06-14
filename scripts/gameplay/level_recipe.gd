extends RefCounted

## LevelRecipe — the editable data a level is made of. Authored in the F6 dev tool
## (level_design_panel.gd) and (later phases) consumed by the runtime wave director to roll waves.
## Saved as JSON in res://levels/. DEV-authored data; not a player-facing feature.
##
## The difficulty model: `difficulty_ceiling` is the PEAK the level ramps up to right before the boss;
## `difficulty_floor` is where the ramp starts. The director climbs floor→ceiling over `length_waves`,
## and the current value drives max enemies/wave, min spawn interval, and how many enemy types are live.

# Valid options (the F6 panel builds its controls from these; the 5 real enemy types — dummy/bomb are
# debug/sub-enemies and excluded; bombs are delivered by the Bombing_wanderer).
const ENEMY_TYPES := ["diver", "shooter", "sentinels", "bombing_wanderer", "swarm"]
# Legacy id → current id, applied on load so old saved recipes keep working after the rename.
const LEGACY_TYPE_RENAMES := {"kingfisher": "diver", "jet_fighter": "shooter"}
const EDGES := ["top", "bottom", "left", "right"]
const BOSSES := ["none", "elephant", "chromeleon", "metalfly"]

var name: String = "New Level"
var enemy_pool: Array = ["diver", "shooter"]   # subset of ENEMY_TYPES
var difficulty_floor: float = 1.0
var difficulty_ceiling: float = 10.0
var length_waves: int = 20                              # number of waves before the boss (= level length)
var entry_edges: Array = ["top"]                        # subset of EDGES
var boss: String = "elephant"
var weights: Dictionary = {}                            # type -> relative weight (Phase 3); empty = equal
# Phase 2/4 choreography model (additive — the random-roll fields above remain the "random" fallback).
var mode: String = "random"                             # "random" (legacy) | "choreography"
var waves: Array = []                                   # ordered choreography names (mode=="choreography", choreo_mode=="fixed")
var choreo_mode: String = "fixed"                       # "fixed" (play `waves` in order) | "pool" (roll from choreo_pool)
var choreo_pool: Array = []                             # allowed choreography names (choreo_mode=="pool")
var choreo_wave_count: int = 6                          # how many waves to roll (choreo_mode=="pool")

func to_dict() -> Dictionary:
	return {
		"name": name,
		"enemy_pool": enemy_pool.duplicate(),
		"difficulty_floor": difficulty_floor,
		"difficulty_ceiling": difficulty_ceiling,
		"length_waves": length_waves,
		"entry_edges": entry_edges.duplicate(),
		"boss": boss,
		"weights": weights.duplicate(),
		"mode": mode,
		"waves": waves.duplicate(),
		"choreo_mode": choreo_mode,
		"choreo_pool": choreo_pool.duplicate(),
		"choreo_wave_count": choreo_wave_count,
	}

func from_dict(d: Dictionary) -> void:
	name = String(d.get("name", name))
	enemy_pool = (d.get("enemy_pool", enemy_pool) as Array).duplicate()
	difficulty_floor = float(d.get("difficulty_floor", difficulty_floor))
	difficulty_ceiling = float(d.get("difficulty_ceiling", difficulty_ceiling))
	length_waves = int(d.get("length_waves", length_waves))
	entry_edges = (d.get("entry_edges", entry_edges) as Array).duplicate()
	boss = String(d.get("boss", boss))
	weights = (d.get("weights", weights) as Dictionary).duplicate()
	mode = String(d.get("mode", mode))                  # old recipes lack this → stays "random"
	waves = (d.get("waves", waves) as Array).duplicate()
	choreo_mode = String(d.get("choreo_mode", choreo_mode))
	choreo_pool = (d.get("choreo_pool", choreo_pool) as Array).duplicate()
	choreo_wave_count = int(d.get("choreo_wave_count", choreo_wave_count))
	_migrate_legacy_type_names()

## Translate any pre-rename enemy ids ("kingfisher"/"jet_fighter") in the loaded pool/weights to their
## current names, so old saved recipes keep working. No-op for recipes authored after the rename.
func _migrate_legacy_type_names() -> void:
	for i in enemy_pool.size():
		var old: String = String(enemy_pool[i])
		if LEGACY_TYPE_RENAMES.has(old):
			enemy_pool[i] = LEGACY_TYPE_RENAMES[old]
	for old: String in LEGACY_TYPE_RENAMES:
		if weights.has(old):
			weights[LEGACY_TYPE_RENAMES[old]] = weights[old]
			weights.erase(old)
