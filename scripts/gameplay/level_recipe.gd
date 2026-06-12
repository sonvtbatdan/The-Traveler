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
const ENEMY_TYPES := ["kingfisher", "jet_fighter", "sentinels", "bombing_wanderer", "swarm"]
const EDGES := ["top", "bottom", "left", "right"]
const BOSSES := ["none", "elephant", "chromeleon", "metalfly"]

var name: String = "New Level"
var enemy_pool: Array = ["kingfisher", "jet_fighter"]   # subset of ENEMY_TYPES
var difficulty_floor: float = 1.0
var difficulty_ceiling: float = 10.0
var length_waves: int = 20                              # number of waves before the boss (= level length)
var entry_edges: Array = ["top"]                        # subset of EDGES
var boss: String = "elephant"
var weights: Dictionary = {}                            # type -> relative weight (Phase 3); empty = equal

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
