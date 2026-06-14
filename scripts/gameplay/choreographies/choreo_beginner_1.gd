extends "res://scripts/gameplay/choreography_base.gd"

## Beginner_1 — a gentle 3-phase warm-up:
##   Phase 1: 6 Shooters (3 per side) slide in to 45° lines and fire at the player (normal fire rate).
##            When they're all gone →
##   Phase 2: 1 Sentinel descends to the TOP-MIDDLE (SENTINEL_TOP_CM from the top) and fires (normal rate).
##            When it dies →
##   Phase 3: both at once — the 6 Shooters AND the Sentinel together. Cleared → done.
##
## The Shooter 45° lines reuse Enemy_group_1's geometry/movement; fire rates are NORMAL here (mult 1.0).

# ── Fire rates: NORMAL (no scaling) ───────────────────────────────────────────
const SHOOTER_FIRE_MULT := 1.0
const SENTINEL_FIRE_MULT := 1.0
# ── Shooter 45° lines (geometry reused from Enemy_group_1) ─────────────────────
const SHOOTER_PER_SIDE := 3
const SHOOTER_DRIFT := 30.0              # px/s straight-down drift once the line is formed
const SHOOTER_SLIDE_SPEED := 220.0       # px/s slide-in from the edge into the 45° line
const SHOOTER_LINE_GAP := 48.0           # spacing between the 3 along the 45° line
const SHOOTER_EDGE_INSET := 34.0         # x of the line's near end, inside the edge…
const SHOOTER_EXTRA_INSET_CM := 1.5      # …pushed this much further in
const SHOOTER_TOP_Y := 70.0              # y of the topmost shooter in each line
const SHOOTER_CULL_MARGIN := 60.0        # despawn once this far below the bottom edge
const DIAG := 0.70710678                 # cos/sin 45°
# ── Sentinel ──────────────────────────────────────────────────────────────────
const SENTINEL_TOP_CM := 4.0             # parks this far from the top edge (top-middle)
const SENTINEL_MOVE_SPEED := 50.0        # px/s max horizontal speed tracking the player
const SENTINEL_ACCEL := 150.0            # px/s² — how fast it changes velocity (lower = more inertia/lag)
const MAX_TIME := 120.0

enum St { P1, P2, P3, DONE }
var _st: int = St.P1
var _shooters: Array = []   # [{node, slide_to:Vector2, arrived:bool}]
var _sentinel: Node = null
var _sent_vx: float = 0.0   # Sentinel's current horizontal velocity (carries momentum → inertia)

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.P1
	_shooters.clear()
	_sentinel = null
	_spawn_shooters()

func tick(delta: float) -> void:
	match _st:
		St.P1:
			_tick_shooters(delta)
			if _living_shooters() == 0:
				_begin_phase2()
		St.P2:
			_tick_sentinel(delta)
			if not _sentinel_alive():
				_begin_phase3()
		St.P3:
			_tick_shooters(delta)
			_tick_sentinel(delta)
			if _living_shooters() == 0 and not _sentinel_alive():
				_st = St.DONE
		St.DONE:
			pass

func _begin_phase2() -> void:
	_st = St.P2
	_spawn_sentinel()

func _begin_phase3() -> void:
	_st = St.P3
	_spawn_shooters()
	_spawn_sentinel()

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return _st == St.DONE

func cleanup() -> void:
	for sh in _shooters:
		if sh["node"] != null and is_instance_valid(sh["node"]):
			sh["node"].despawn()
	_shooters.clear()
	if _sentinel != null and is_instance_valid(_sentinel):
		_sentinel.despawn()
	_sentinel = null

# ── Sentinel ──────────────────────────────────────────────────────────────────
func _spawn_sentinel() -> void:
	var screen: Vector2 = _mgr.screen_size()
	_sent_vx = 0.0
	_sentinel = _mgr.spawn_sentinel_at_pos(Vector2(screen.x * 0.5, _cm_to_px(SENTINEL_TOP_CM)))
	if _sentinel != null:
		_sentinel.fire_interval_mult = SENTINEL_FIRE_MULT

func _sentinel_alive() -> bool:
	return _sentinel != null and is_instance_valid(_sentinel)

## Once parked (engaged), the Sentinel slides horizontally to stay vertically aligned with the player,
## holding its top y. Velocity is acceleration-limited so quick player wiggles don't snap it sharply —
## it has a bit of momentum. (ENGAGE never self-moves, so the choreography owns its position.)
func _tick_sentinel(delta: float) -> void:
	if not _sentinel_alive() or not _sentinel.is_engaged():
		return
	var sc: Vector2 = _mgr.ship_center()
	var cur: Vector2 = _sentinel.center()
	var dx := sc.x - cur.x
	var desired_vx := clampf(dx, -SENTINEL_MOVE_SPEED, SENTINEL_MOVE_SPEED)   # ease off near the target
	_sent_vx = move_toward(_sent_vx, desired_vx, SENTINEL_ACCEL * delta)      # ramp velocity → inertia
	_drive_x(_sentinel, _sent_vx, delta)

## Move a node horizontally by `vx·delta`, holding its current y. (untyped node → safe dynamic access)
func _drive_x(node, vx: float, delta: float) -> void:
	var c: Vector2 = node.center()
	node.position = Vector2(c.x + vx * delta, c.y) - node.size * 0.5

# ── Shooters: one batch of SHOOTER_PER_SIDE per side into 45° lines (reused from Enemy_group_1) ─
func _spawn_shooters() -> void:
	var screen: Vector2 = _mgr.screen_size()
	var inset := SHOOTER_EDGE_INSET + _cm_to_px(SHOOTER_EXTRA_INSET_CM)
	for i in SHOOTER_PER_SIDE:
		var step := float(i) * SHOOTER_LINE_GAP * DIAG
		# Left line: 45° down-right, slides in from off the left edge.
		var l_to := Vector2(inset + step, SHOOTER_TOP_Y + step)
		_spawn_external_shooter(Vector2(-40.0, l_to.y), l_to)
		# Right line: mirrored 45° down-left, slides in from off the right edge.
		var r_to := Vector2(screen.x - inset - step, SHOOTER_TOP_Y + step)
		_spawn_external_shooter(Vector2(screen.x + 40.0, r_to.y), r_to)

func _spawn_external_shooter(spawn_center: Vector2, slide_to: Vector2) -> void:
	var node = _mgr.spawn_shooter_external(spawn_center)
	if node != null:
		node.fire_interval_mult = SHOOTER_FIRE_MULT
		_shooters.append({"node": node, "slide_to": slide_to, "arrived": false})

func _living_shooters() -> int:
	var n := 0
	for sh in _shooters:
		if sh["node"] != null and is_instance_valid(sh["node"]):
			n += 1
	return n

func _tick_shooters(delta: float) -> void:
	var screen: Vector2 = _mgr.screen_size()
	var i := _shooters.size() - 1
	while i >= 0:
		var sh = _shooters[i]
		var node = sh["node"]
		if node == null or not is_instance_valid(node):
			_shooters.remove_at(i)
			i -= 1
			continue
		if not bool(sh["arrived"]):
			if _move_center_to(node, sh["slide_to"], SHOOTER_SLIDE_SPEED, delta):
				sh["arrived"] = true
		else:
			node.position += Vector2(0.0, SHOOTER_DRIFT * delta)   # drift straight down
		if node.center().y > screen.y + SHOOTER_CULL_MARGIN:
			node.despawn()
			_shooters.remove_at(i)
		i -= 1

## Move a node's CENTER toward `target` at `speed`; returns true the frame it arrives (snaps exactly).
func _move_center_to(node, target: Vector2, speed: float, delta: float) -> bool:
	var c: Vector2 = node.center()
	var to: Vector2 = target - c
	var step := speed * delta
	if to.length() <= step or to.length() < 0.5:
		node.position = target - node.size * 0.5
		return true
	node.position += to.normalized() * step
	return false
