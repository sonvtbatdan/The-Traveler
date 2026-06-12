extends "res://scripts/gameplay/choreography_base.gd"

## Test_Divers — the trivial pipeline-proof choreography (Phase 2). Spawns a Diver burst from the top at
## t=0 and again at t=1.5s, then reports done once both spawns have fired AND the screen is clear. Proves
## registry → director → start/tick/is_done → wave advance. Replace/extend in Phase 3 with real set-pieces.

const SPAWN_TIMES := [0.0, 1.5]   # spawn a Diver burst from the top at each of these times (seconds)

var _t: float = 0.0
var _next: int = 0     # index of the next spawn in SPAWN_TIMES

func start(mgr: Node) -> void:
	super(mgr)
	_t = 0.0
	_next = 0
	_maybe_spawn()

func tick(delta: float) -> void:
	_t += delta
	_maybe_spawn()

func _maybe_spawn() -> void:
	while _next < SPAWN_TIMES.size() and _t >= float(SPAWN_TIMES[_next]):
		if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_type"):
			_mgr.spawn_type("diver", ["top"])
		_next += 1

func is_done() -> bool:
	return _next >= SPAWN_TIMES.size() and _living_enemies() == 0
