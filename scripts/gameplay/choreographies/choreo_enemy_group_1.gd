extends "res://scripts/gameplay/choreography_base.gd"

## Enemy_group_1 — the first real set-piece (Phase 3). All timings/speeds are tunable constants below.
##
## • 2 Sentinels spawn + descend to their normal stationary spots, then trace a slow U at U_SPEED: up to
##   the top edge, across the top (swapping x with each other), then back down. They keep firing their
##   normal volley the whole time (their ENGAGE phase only fires — the choreography drives position).
## • Shooters: a batch of SHOOTER_PER_SIDE from EACH side slides in from the edge into a 45° line, then
##   drifts straight down at SHOOTER_DRIFT, firing as normal. A new batch every SHOOTER_INTERVAL s (or at
##   once if none are alive), up to SHOOTER_BATCHES total, then it stops.
## • Death trigger: each Sentinel death pops a visual explosion and sprays DEATH_DIVERS Divers UPWARD in
##   a tight fan from the corpse — they fly straight off the top of the map. Then DEATH_BURST_DELAY (1s)
##   later, 2 NORMAL 3-Diver bursts spawn from the top, DEATH_BURST_GAP (0.5s) apart.
##
## DONE when: all batches spawned AND both Sentinels dead AND the death-Divers are all spawned AND the
## screen is clear of normal enemies. max_time() is the backstop if the player never clears it.

# ── Sentinels + U-path ────────────────────────────────────────────────────────
const SENTINEL_X_FRAC := [0.30, 0.70]   # the two sentinels' columns (fraction of play-width)
const U_SPEED := 50.0                    # px/s along the U-path
const U_TOP_Y := 40.0                    # the top-edge y the U rises to (screen-local)
const SENTINEL_FIRE_MULT := 1        # Sentinel fire rate −20% here (interval ×1.25) — this set-piece only
# ── Fire-rate tuning (Enemy_group_1 only; the enemies' defaults elsewhere are unchanged) ──
const SHOOTER_FIRE_MULT := 4          # Shooter fire rate −50% here (interval ×2)
# ── Shooters ──────────────────────────────────────────────────────────────────
const SHOOTER_BATCHES := 6               # total spawn events (initial + 5)
const SHOOTER_INTERVAL := 10.0           # s between batches (or immediately if none alive)
const SHOOTER_PER_SIDE := 3
const SHOOTER_DRIFT := 30.0              # px/s straight-down drift once the line is formed
const SHOOTER_SLIDE_SPEED := 220.0       # px/s slide-in from the edge into the 45° line
const SHOOTER_LINE_GAP := 48.0           # spacing between the 3 along the 45° line
const SHOOTER_EDGE_INSET := 34.0         # x of the line's near end, inside the edge…
const SHOOTER_EXTRA_INSET_CM := 1.5      # …pushed this much further in (the shooters enter deeper)
const SHOOTER_TOP_Y := 70.0              # y of the topmost shooter in each line
const SHOOTER_CULL_MARGIN := 60.0        # despawn once this far below the bottom edge
const DIAG := 0.70710678                 # cos/sin 45° (the line is at 45°)
# ── Death trigger: explosion + upward Diver spray + delayed normal bursts ─────
const DEATH_DIVERS := 6                   # Divers that fire UP out of the corpse (all at once)
const DEATH_FAN_HALF_DEG := 10.0          # TIGHT upward fan (0 = perfectly straight up)
const DEATH_LAUNCH_SPEED := 520.0         # upward speed — fast enough to leave the map (px/s)
const DEATH_EXPLOSION_RADIUS := 70.0      # visual-only explosion ring at the corpse
const DEATH_BURST_DELAY := 1.0            # s after death before the first NORMAL 3-Diver burst (from top)
const DEATH_BURST_GAP := 0.5              # s between the two normal bursts
# ── Backstop ──────────────────────────────────────────────────────────────────
const MAX_TIME := 120.0

var _clock: float = 0.0
var _sentinels: Array = []      # [{node, tip:Vector2, captured:bool, wps:Array, leg:int}]
var _shooters: Array = []       # [{node, slide_to:Vector2, arrived:bool}]
var _batches: int = 0
var _batch_t: float = 0.0
var _upath_built: bool = false
var _burst_events: Array = []   # absolute _clock times to spawn one NORMAL 3-Diver burst (post-death)

func start(mgr: Node) -> void:
	super(mgr)
	_clock = 0.0
	_sentinels.clear()
	_shooters.clear()
	_burst_events.clear()
	_batches = 0
	_batch_t = 0.0
	_upath_built = false
	var screen: Vector2 = mgr.screen_size()
	for f in SENTINEL_X_FRAC:
		var node = mgr.spawn_sentinel_at(screen.x * float(f))
		if node != null:
			node.fire_interval_mult = SENTINEL_FIRE_MULT
			node.connect("died", _on_sentinel_died.bind(node))   # bind → know the corpse position
			_sentinels.append({"node": node, "tip": Vector2.ZERO, "captured": false, "wps": [], "leg": 0})
	_spawn_shooter_batch()   # first batch right as the Sentinels enter

func tick(delta: float) -> void:
	_clock += delta
	_tick_sentinels(delta)
	_tick_shooter_batches(delta)
	_tick_shooters(delta)
	_tick_bursts()

func max_time() -> float:
	return MAX_TIME

# ── Sentinel U-path ───────────────────────────────────────────────────────────
func _tick_sentinels(delta: float) -> void:
	# Capture each sentinel's stationary tip the moment it finishes descending.
	for s in _sentinels:
		var node = s["node"]
		if node == null or not is_instance_valid(node):
			continue
		if not bool(s["captured"]) and node.is_engaged():
			s["tip"] = node.center()
			s["captured"] = true
	# Build the U waypoints once every still-living sentinel has parked.
	if not _upath_built and _all_captured():
		_build_upath()
		_upath_built = true
	if not _upath_built:
		return
	# Drive each living sentinel along its waypoints (it keeps firing on its own).
	for s in _sentinels:
		var node = s["node"]
		if node == null or not is_instance_valid(node):
			continue
		var wps: Array = s["wps"]
		var leg: int = int(s["leg"])
		if leg >= wps.size():
			continue   # finished the U — holds position and keeps firing
		if _move_center_to(node, wps[leg], U_SPEED, delta):
			s["leg"] = leg + 1

## True once no living sentinel is still descending, and at least one has been captured.
func _all_captured() -> bool:
	var any := false
	for s in _sentinels:
		var node = s["node"]
		var alive: bool = node != null and is_instance_valid(node)
		if alive and not bool(s["captured"]):
			return false
		if bool(s["captured"]):
			any = true
	return any

func _build_upath() -> void:
	for i in _sentinels.size():
		var s = _sentinels[i]
		if not bool(s["captured"]):
			continue
		var tip: Vector2 = s["tip"]
		var cross_x := _cross_x_for(i, tip)
		s["wps"] = [
			Vector2(tip.x, U_TOP_Y),       # up to the top edge
			Vector2(cross_x, U_TOP_Y),     # across the top, swapping x with the other
			Vector2(cross_x, tip.y),       # back down to finish the U
		]
		s["leg"] = 0

## The x this sentinel crosses to = the OTHER captured sentinel's tip x, else the mirror across centre.
func _cross_x_for(i: int, tip: Vector2) -> float:
	for j in _sentinels.size():
		if j == i:
			continue
		var o = _sentinels[j]
		if bool(o["captured"]):
			return float((o["tip"] as Vector2).x)
	return _mgr.screen_size().x - tip.x

# ── Shooter batches + movement ────────────────────────────────────────────────
func _tick_shooter_batches(delta: float) -> void:
	if _batches >= SHOOTER_BATCHES:
		return
	_batch_t += delta
	if _batch_t >= SHOOTER_INTERVAL or _living_shooters() == 0:
		_spawn_shooter_batch()

func _living_shooters() -> int:
	var n := 0
	for sh in _shooters:
		if sh["node"] != null and is_instance_valid(sh["node"]):
			n += 1
	return n

func _spawn_shooter_batch() -> void:
	_batch_t = 0.0
	_batches += 1
	var screen: Vector2 = _mgr.screen_size()
	var inset := SHOOTER_EDGE_INSET + _cm_to_px(SHOOTER_EXTRA_INSET_CM)   # near end of each line, deeper in
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

# ── Death trigger: explosion + upward spray + delayed normal bursts ───────────
## A Sentinel died (signal bound with its node): pop a visual explosion, spray DEATH_DIVERS Divers UP in
## a tight fan (they fly off the top of the map), and schedule 2 NORMAL 3-Diver bursts 1s / 1.5s later.
func _on_sentinel_died(node) -> void:
	if _mgr == null or not is_instance_valid(_mgr):
		return
	var corpse: Vector2 = node.center() if is_instance_valid(node) else _mgr.ship_center()
	_mgr.flash_explosion(corpse, DEATH_EXPLOSION_RADIUS)
	var fan := deg_to_rad(DEATH_FAN_HALF_DEG)
	var half := float(DEATH_DIVERS - 1) * 0.5
	for i in DEATH_DIVERS:
		var frac: float = (float(i) - half) / maxf(1.0, half)   # -1 … +1 across the tight fan
		var ang := -PI * 0.5 + frac * fan                       # straight up (−90°) ± fan
		var vel := Vector2(cos(ang), sin(ang)) * DEATH_LAUNCH_SPEED
		_mgr.spawn_diver_launch(corpse, vel)
	# Then the real threat: 2 normal 3-Diver bursts from the top, 1s after death, 0.5s apart.
	_burst_events.append(_clock + DEATH_BURST_DELAY)
	_burst_events.append(_clock + DEATH_BURST_DELAY + DEATH_BURST_GAP)

func _tick_bursts() -> void:
	var i := _burst_events.size() - 1
	while i >= 0:
		if _clock >= float(_burst_events[i]):
			if _mgr != null and is_instance_valid(_mgr):
				_mgr.spawn_diver(["top"])   # one normal 3-Diver burst (lead aims, 2 followers oscillate)
			_burst_events.remove_at(i)
		i -= 1

# ── Completion ────────────────────────────────────────────────────────────────
func is_done() -> bool:
	if _batches < SHOOTER_BATCHES:
		return false
	if not _sentinels_all_dead():
		return false
	if not _burst_events.is_empty():
		return false   # a post-death normal burst is still pending
	return _living_enemies() == 0

func _sentinels_all_dead() -> bool:
	for s in _sentinels:
		var node = s["node"]
		if node != null and is_instance_valid(node):
			return false
	return true

# ── Helper ────────────────────────────────────────────────────────────────────
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
