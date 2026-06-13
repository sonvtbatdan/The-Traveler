extends "res://scripts/gameplay/choreography_base.gd"

## Beginner_3 — three phases, each waiting for the screen to FULLY clear before advancing. Every phase
## flies 8 Shooters in fast then eases them into formation (the shared home_to() mover), holding their
## fire until each is parked (fire_enabled), so they FORM UP then start shooting.
##   Phase 1: 8 Shooters drop from the TOP into an arc across the top third.       Clear →
##   Phase 2: 8 Shooters rise from the BOTTOM into an arc across the bottom third.  Clear →
##   Phase 3: 8 Shooters home into the 4 corners (2 each).                          Clear → done.

# ── Tunables (Beginner_3) ──────────────────────────────────────────────────────
const B3_COUNT: int = 8             # shooters per arc phase (phases 1 & 2)
# Phase 1 & 2 arcs lie on a big circle centred on the MAP CENTRE, so they bulge OUTWARD toward the edge.
const B3_ARC_APEX_INSET: float = 0.06   # the arc's apex sits this fraction of the screen height from the edge
const B3_ARC_SPAN_DEG: float = 120.0    # angular width of the arc on that circle (wider = flatter/longer arc)
# Phase 3 corners lie on a larger circle whose circumference passes just inside the 4 corners.
const B3_CORNER_R_FRAC: float = 0.85    # corner-circle radius as a fraction of the half-diagonal (→ near the corners)
const B3_CORNER_INSET_CM: float = 2.0   # pull each corner shooter this far toward the centre (stops edge-clipping)
const B3_CORNER_PER: int = 3            # shooters per corner (×4 corners = 12 total)
const B3_CORNER_SPREAD_DEG: float = 26.0   # angular fan of the cluster at each corner
# Phase-3 firing: slower rate + a clockwise round-robin starting at the upper-left corner's leftmost shooter.
const B3_P3_FIRE_MULT: float = 1.0 / 0.75   # interval ×1.333 → fire rate 0.75× normal
const B3_P3_FIRE_STAGGER: float = 0.12      # s between successive shooters being armed (the clockwise ripple)
const B3_CORNER_ENTRY: float = 240.0   # px outside the corner each one flies in from
const B3_OFFSCREEN: float = 60.0    # px beyond the top/bottom edge the arc shooters start from
const B3_HOME_SPEED: float = 700.0  # home-in speed cap (px/s)
const B3_HOME_APPROACH: float = 5.0 # home-in braking (higher = snappier settle)
const B3_FIRE_MULT: float = 1.0     # shooter fire-rate scaler (1.0 = normal)
const MAX_TIME: float = 150.0

enum St { P1, P2, P3, DONE }
var _st: int = St.P1
var _shooters: Array = []   # [{node, target:Vector2, arrived:bool}]
# Phase-3 clockwise fire sequencing (the corner shooters are appended in clockwise order already).
var _seq_fire: bool = false   # when true, arrival does NOT arm guns — the sequencer does
var _seq_t: float = 0.0
var _seq_idx: int = 0

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.P1
	_seq_fire = false
	_seq_t = 0.0
	_seq_idx = 0
	_begin_top_arc()

func tick(delta: float) -> void:
	match _st:
		St.P1:
			_drive(delta)
			if _living_shooters() == 0:
				_st = St.P2
				_begin_bottom_arc()
		St.P2:
			_drive(delta)
			if _living_shooters() == 0:
				_st = St.P3
				_begin_corners()
		St.P3:
			_drive(delta)
			_tick_fire_sequence(delta)   # arm the corner shooters one-by-one, clockwise
			if _living_shooters() == 0:
				_st = St.DONE
		St.DONE:
			pass

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return _st == St.DONE

func cleanup() -> void:
	for sh in _shooters:
		if sh["node"] != null and is_instance_valid(sh["node"]):
			sh["node"].despawn()
	_shooters.clear()

# ── Per-frame: fly each shooter in (fast→ease), arm its guns once parked ───────
func _drive(delta: float) -> void:
	for sh in _shooters:
		var n = sh["node"]
		if n == null or not is_instance_valid(n):
			continue
		if not bool(sh["arrived"]):
			if home_to(n, sh["target"], delta, B3_HOME_SPEED, B3_HOME_APPROACH):
				sh["arrived"] = true
				if not _seq_fire:
					n.fire_enabled = true   # formed up → start shooting (phases 1 & 2)
				# Phase 3: guns stay OFF here; _tick_fire_sequence arms them clockwise.

func _living_shooters() -> int:
	var c := 0
	for sh in _shooters:
		if sh["node"] != null and is_instance_valid(sh["node"]):
			c += 1
	return c

# ── Phase setups ───────────────────────────────────────────────────────────────
## Top & bottom arcs: shooters sit ON a big circle centred on the map centre, so the arc bulges OUTWARD
## toward the edge (apex closest to the edge in the middle, sides curving back in). `edge_sign` = -1 for
## the top (apex points up at -90°), +1 for the bottom (apex points down at +90°).
func _begin_arc(edge_sign: float) -> void:
	_seq_fire = false   # phases 1 & 2: each shooter arms itself on arrival
	var s: Vector2 = _mgr.screen_size()
	var c := s * 0.5
	var r := c.y - s.y * B3_ARC_APEX_INSET          # radius so the apex sits B3_ARC_APEX_INSET from the edge
	var base := edge_sign * PI * 0.5                # -90° (up) for top, +90° (down) for bottom
	var span := deg_to_rad(B3_ARC_SPAN_DEG)
	var targets: Array = []
	var starts: Array = []
	for i in B3_COUNT:
		var t := 0.0 if B3_COUNT <= 1 else float(i) / float(B3_COUNT - 1)
		var theta := base + lerpf(-span * 0.5, span * 0.5, t)
		var tgt := c + Vector2(cos(theta), sin(theta)) * r
		targets.append(tgt)
		var start_y := -B3_OFFSCREEN if edge_sign < 0.0 else s.y + B3_OFFSCREEN
		starts.append(Vector2(tgt.x, start_y))      # fly in from beyond the near edge at the target's x
	_spawn(targets, starts)

func _begin_top_arc() -> void:
	_begin_arc(-1.0)

func _begin_bottom_arc() -> void:
	_begin_arc(1.0)

## Corners: shooters sit on a larger circle centred on the map centre whose circumference passes just
## inside the 4 corners. Each corner is a cluster of B3_CORNER_PER fanned around the diagonal direction.
func _begin_corners() -> void:
	_seq_fire = true   # phase 3: hold fire on arrival; arm clockwise via _tick_fire_sequence
	_seq_t = 0.0
	_seq_idx = 0
	var s: Vector2 = _mgr.screen_size()
	var c := s * 0.5
	var r := B3_CORNER_R_FRAC * c.length() - _cm_to_px(B3_CORNER_INSET_CM)   # near the corners, pulled 1cm in
	var spread := deg_to_rad(B3_CORNER_SPREAD_DEG)
	var diagonals := [-PI * 0.75, -PI * 0.25, PI * 0.25, PI * 0.75]   # TL, TR, BR, BL (y-down angles)
	var targets: Array = []
	var starts: Array = []
	for base: float in diagonals:
		for j in B3_CORNER_PER:
			var t := 0.0 if B3_CORNER_PER <= 1 else float(j) / float(B3_CORNER_PER - 1) - 0.5   # -0.5..0.5
			var theta := base + t * spread
			var tgt := c + Vector2(cos(theta), sin(theta)) * r
			targets.append(tgt)
			var outward := (tgt - c).normalized()    # fly in from outside that corner
			starts.append(tgt + outward * B3_CORNER_ENTRY)
	_spawn(targets, starts, B3_P3_FIRE_MULT)   # phase-3 shooters fire at 0.75× rate

## Spawn one shooter per target at its off-screen start, fire held until it homes into place.
func _spawn(targets: Array, starts: Array, fire_mult: float = B3_FIRE_MULT) -> void:
	_shooters.clear()
	for i in targets.size():
		var n = _mgr.spawn_shooter_external(starts[i])
		if n != null:
			n.fire_enabled = false
			n.fire_interval_mult = fire_mult
			_shooters.append({"node": n, "target": targets[i], "arrived": false})

## Phase 3: once all corner shooters have parked, arm them one at a time in clockwise order (the
## _shooters array is already TL-leftmost → clockwise), every B3_P3_FIRE_STAGGER seconds.
func _tick_fire_sequence(delta: float) -> void:
	if _seq_idx >= _shooters.size():
		return
	if not _all_arrived():
		return
	_seq_t += delta
	while _seq_idx < _shooters.size() and _seq_t >= float(_seq_idx) * B3_P3_FIRE_STAGGER:
		var n = _shooters[_seq_idx]["node"]
		if n != null and is_instance_valid(n):
			n.fire_enabled = true
		_seq_idx += 1

func _all_arrived() -> bool:
	for sh in _shooters:
		var n = sh["node"]
		if n != null and is_instance_valid(n) and not bool(sh["arrived"]):
			return false
	return true
