extends "res://scripts/gameplay/choreography_base.gd"

## Beginner_2 — three phases, each waiting for the screen to FULLY clear before advancing:
##   Phase 1: 3 diver 3-bursts from the TOP, 0.8s apart. Clear →
##   Phase 2: 2 wandering bombers + diver 3-bursts from the LEFT/RIGHT — one at the start, then +1 every
##            3s while either bomber lives. Both bombers dead + screen clear →
##   Phase 3: 1s later, 5 diver 3-bursts from a RANDOM edge, 1s apart. Clear → done.
## Reuses spawn_diver([edges]) (empty = random of all 4 edges) and a node-returning bomber spawn.

const P1_DIVER_COUNT := 3
const P1_DIVER_GAP := 2.0        # s between the top bursts
const P2_BOMBER_COUNT := 3
const P2_BOMBER_SIDES := ["left", "right", "left"]   # entry edge per bomber (opposite sides)
const P2_DIVER_INTERVAL := 3.0   # s between left/right diver bursts (while bombers live)
const P3_DIVER_COUNT := 5
const P3_DIVER_GAP := 2.0        # s between the random-edge bursts
const HORIZ_DIVER_SLOWER := 100.0   # divers from left/right edges dash this many px/s slower (this choreo only)
const P3_START_DELAY := 1.0      # s after the Phase-2 clear before Phase 3 begins
const MAX_TIME := 180.0

enum St { P1, P2, P3_DELAY, P3, DONE }
var _st: int = St.P1
var _t: float = 0.0          # per-phase timer
var _spawned: int = 0        # diver instances spawned this phase
var _bombers: Array = []     # phase-2 bomber nodes

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.P1
	_t = 0.0
	_bombers.clear()
	_mgr.spawn_diver(["top"], -HORIZ_DIVER_SLOWER)   # first top burst immediately
	_spawned = 1

func tick(delta: float) -> void:
	match _st:
		St.P1:
			if _spawned < P1_DIVER_COUNT:
				_t += delta
				if _t >= P1_DIVER_GAP:
					_t -= P1_DIVER_GAP
					_mgr.spawn_diver(["top"], -HORIZ_DIVER_SLOWER)
					_spawned += 1
			elif _living_enemies() == 0:
				_begin_phase2()
		St.P2:
			if _bombers_alive():
				_t += delta
				if _t >= P2_DIVER_INTERVAL:
					_t -= P2_DIVER_INTERVAL
					_mgr.spawn_diver(["left", "right"], -HORIZ_DIVER_SLOWER)
			elif _living_enemies() == 0:
				_st = St.P3_DELAY
				_t = 0.0
		St.P3_DELAY:
			_t += delta
			if _t >= P3_START_DELAY:
				_begin_phase3()
		St.P3:
			if _spawned < P3_DIVER_COUNT:
				_t += delta
				if _t >= P3_DIVER_GAP:
					_t -= P3_DIVER_GAP
					_mgr.spawn_diver([], -HORIZ_DIVER_SLOWER)   # random edge (all 4)
					_spawned += 1
			elif _living_enemies() == 0:
				_st = St.DONE
		St.DONE:
			pass

func _begin_phase2() -> void:
	_st = St.P2
	_t = 0.0
	_bombers.clear()
	for side: String in P2_BOMBER_SIDES:   # bombers enter from opposite sides
		var b = _mgr.spawn_bombing_wanderer_node(side)
		if b != null:
			_bombers.append(b)
	_mgr.spawn_diver(["left", "right"], -HORIZ_DIVER_SLOWER)   # one instance at the start

func _begin_phase3() -> void:
	_st = St.P3
	_t = 0.0
	_spawned = 1
	_mgr.spawn_diver([], -HORIZ_DIVER_SLOWER)   # first of 5 (the "1s after clear" burst), random edge

func _bombers_alive() -> bool:
	for b in _bombers:
		if is_instance_valid(b):
			return true
	return false

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return _st == St.DONE

func cleanup() -> void:
	_bombers.clear()   # bombers + divers are normal enemies — they despawn on their own / director clear
