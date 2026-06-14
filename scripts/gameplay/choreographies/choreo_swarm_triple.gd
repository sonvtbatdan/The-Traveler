extends "res://scripts/gameplay/choreography_base.gd"

## Swarm_triple — three sequential waves, each waiting for the previous to FULLY clear (no gap by default):
##   1) one swarm circle at TOP-MIDDLE,
##   2) two swarm circles from the TOP-LEFT and TOP-RIGHT corners (each entering from its own side edge),
##   3) the Swarm_border set-piece — swarms enter from the bottom-middle, hug the edges into a full map
##      border, flow for ~1s, then peel from the bottom-middle and dive at the player.
## Reuses the swarm flock (spawn_swarm_at) + the Swarm_border choreography wholesale — no new combat.

const ChoreoSwarmBorder := preload("res://scripts/gameplay/choreographies/choreo_swarm_border.gd")

# ── Tunables (cm → px via _cm_to_px) ──────────────────────────────────────────
const CIRCLE_CENTER_Y_CM := 3.0    # swarm rings' centre y, measured from the top edge
const CORNER_X_CM := 2.5           # stage-2 corner rings' x, in from their side edge
const INTER_STAGE_GAP := 0.0       # breather after a stage clears before the next (tunable)
const MAX_TIME := 120.0

enum St { S1, S2, S3, DONE }
var _st: int = St.S1
var _flocks: Array = []   # live flock coordinators (for cleanup)
var _border: Node = null  # Stage-3 Swarm_border sub-choreography
var _gap_t: float = 0.0
var _spawned: bool = false   # guards the clear-check until the current stage's enemies exist

func start(mgr: Node) -> void:
	super(mgr)
	_flocks.clear()
	_begin_stage(St.S1)

func tick(delta: float) -> void:
	match _st:
		St.S1, St.S2:
			# A stage completes once it has spawned AND no normal enemies remain (its swarm dived).
			if _spawned and _living_enemies() == 0:
				_gap_t += delta
				if _gap_t >= INTER_STAGE_GAP:
					_advance()
		St.S3:
			if _border != null and is_instance_valid(_border):
				_border.tick(delta)
				if _border.is_done():
					_end_border()
					_st = St.DONE
			else:
				_st = St.DONE
		St.DONE:
			pass

func _advance() -> void:
	match _st:
		St.S1: _begin_stage(St.S2)
		St.S2: _begin_stage(St.S3)

## Spawn one stage's enemies. Each spawn is synchronous, so they're counted by next tick's clear-check.
func _begin_stage(stage: int) -> void:
	_st = stage
	_gap_t = 0.0
	_spawned = false
	var screen: Vector2 = _mgr.screen_size()
	var yc := _cm_to_px(CIRCLE_CENTER_Y_CM)
	match stage:
		St.S1:
			_flocks.append(_mgr.spawn_swarm_at(Vector2(screen.x * 0.5, yc), true))   # top-middle
		St.S2:
			var xin := _cm_to_px(CORNER_X_CM)
			_flocks.append(_mgr.spawn_swarm_at(Vector2(xin, yc), true))              # top-left, from the left
			_flocks.append(_mgr.spawn_swarm_at(Vector2(screen.x - xin, yc), false))  # top-right, from the right
		St.S3:
			_border = ChoreoSwarmBorder.new()   # the full-map border peel set-piece
			add_child(_border)
			_border.start(_mgr)
	_spawned = true

func _end_border() -> void:
	if _border != null and is_instance_valid(_border):
		_border.cleanup()
		_border.queue_free()
	_border = null

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return _st == St.DONE

func cleanup() -> void:
	_end_border()
	for f in _flocks:
		if is_instance_valid(f):
			f.queue_free()
	_flocks.clear()
