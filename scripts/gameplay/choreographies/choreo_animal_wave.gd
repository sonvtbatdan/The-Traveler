extends "res://scripts/gameplay/choreography_base.gd"

## Animal_wave — a 2-minute progressive timeline for the Animal enemy group.
## Designed around the Animal tab: Flies/Bug early → Bee/Swarm/Spider mid → Dragonfly/Diver/Centipede/Octopus late.
## Scripted events fire at exact second marks regardless of the current pool.
##
## Timeline (4 phases × 30 s):
##   0–30 s  : cap 80,  rate 1.0s  — Flies + Bug
##   30–60 s : cap 150, rate 0.8s  — Flies/Bug/Bee/Swarm/Spider  (+Diver at t=45)
##   60–90 s : cap 250, rate 0.5s  — Bee/Swarm/Dragonfly/Spider/Octopus  (+BombingWanderer at t=75)
##   90–120 s: cap 400, rate 0.3s  — Flies/Dragonfly/Diver/Centipede/Octopus/BombingWanderer

const TIMELINE := [
	{
		"sec_start": 0, "sec_end": 30, "spawn_cap": 80, "spawn_rate": 1.0,
		"pool": [["flies", 60], ["bug", 40]],
		"events": []
	},
	{
		"sec_start": 30, "sec_end": 60, "spawn_cap": 150, "spawn_rate": 0.8,
		"pool": [["flies", 30], ["bug", 30], ["bee", 20], ["swarm", 10], ["spider", 10]],
		"events": [{"t": 45, "type": "diver", "count": 1}]
	},
	{
		"sec_start": 60, "sec_end": 90, "spawn_cap": 250, "spawn_rate": 0.5,
		"pool": [["bee", 40], ["swarm", 30], ["dragonfly", 15], ["spider", 10], ["octopus", 5]],
		"events": [{"t": 75, "type": "bombing_wanderer", "count": 1}]
	},
	{
		"sec_start": 90, "sec_end": 120, "spawn_cap": 400, "spawn_rate": 0.3,
		"pool": [["flies", 50], ["dragonfly", 20], ["diver", 15], ["centipede", 5],
				 ["octopus", 5], ["bombing_wanderer", 5]],
		"events": []
	},
]

var _elapsed: float = 0.0
var _spawn_acc: float = 0.0
var _fired: Dictionary = {}   # event_id → true, prevents re-triggering

func start(mgr: Node) -> void:
	super(mgr)
	_elapsed = 0.0
	_spawn_acc = 0.0
	_fired.clear()

func tick(delta: float) -> void:
	_elapsed += delta
	var phase := _current_phase()
	if phase.is_empty():
		return

	# Scripted events — fire at exact second marks
	for ev: Dictionary in phase.get("events", []):
		var eid := str(int(ev["t"])) + String(ev["type"])
		if _elapsed >= float(ev["t"]) and not _fired.has(eid):
			_fired[eid] = true
			for _i in range(int(ev.get("count", 1))):
				_mgr.spawn_type(String(ev["type"]))

	# Weighted pool spawn, respecting spawn_cap
	_spawn_acc += delta
	var rate: float = float(phase.get("spawn_rate", 1.0))
	if _spawn_acc >= rate:
		_spawn_acc -= rate
		var cap: int = int(phase.get("spawn_cap", 80))
		if _living_enemies() < cap:
			_spawn_from_pool(phase.get("pool", []))

func _current_phase() -> Dictionary:
	for p: Dictionary in TIMELINE:
		if _elapsed >= float(p["sec_start"]) and _elapsed < float(p["sec_end"]):
			return p
	return {}

func _spawn_from_pool(pool: Array) -> void:
	var total := 0.0
	for entry: Array in pool:
		total += float(entry[1])
	if total <= 0.0:
		return
	var r := randf() * total
	var cum := 0.0
	for entry: Array in pool:
		cum += float(entry[1])
		if r < cum:
			_mgr.spawn_type(String(entry[0]))
			return

func is_done() -> bool:
	return _elapsed >= 120.0   # 2 minutes

func max_time() -> float:
	return 140.0
