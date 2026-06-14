extends "res://scripts/gameplay/choreography_base.gd"

## Swarm_border — the follow-the-leader swarm streams in from the MIDDLE OF THE BOTTOM EDGE, turns LEFT,
## and hugs the map edges until a full rectangular border (the whole perimeter) is covered with beads.
## It keeps flowing around the border for HOLD_TIME, then the ring KEEPS ROTATING and each bead PEELS off
## to dive at the player only when it reaches the 6 o'clock point (bottom-middle) — beads feed off the seam
## one at a time as the ring carries them there. Reuses the bare swarm bead (enemy_swarm.gd): set_track_pose
## for the formation, begin_zoom for the aim-once dive. Same engine as Swarm_infinity, rectangular path.

const BORDER_MARGIN_CM := 1.0   # how far the border sits in from the screen edges
const BEAD_SPACING := 90.0      # spacing of beads around the perimeter → enemy count (lower = denser)
const NUM_ENTRY := 6            # off-screen lead-in nodes (stream up from below the bottom edge)
const ENTRY_STEP := 42.0
const FORM_SPEED := 450.0       # px/s the lead traces the border AND flows around it (also paces the peel)
const HOLD_TIME := 1.0          # seconds the border keeps flowing before beads start peeling at 6 o'clock
const MAX_TIME := 90.0

enum St { FORMING, HOLD, DIVE }
var _st: int = St.FORMING
var _beads: Array = []
var _path: Array = []           # entry nodes + the border's even-spaced points (one bead per point)
var _entry_n: int = 0
var _lead: float = 0.0
var _circulating: bool = false
var _hold_t: float = 0.0
var _dive_idx: int = 0
var _dive_start: int = 0        # first bead to reach the 6 o'clock seam (peel order anchor)
var _dive_next_lead: float = 0.0   # _lead value at which the next bead reaches the seam

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.FORMING
	_beads.clear(); _path.clear()
	_lead = 0.0; _circulating = false; _hold_t = 0.0; _dive_idx = 0
	_build_path(mgr.screen_size())
	for i in _path.size() - _entry_n:   # one bead per border point
		var m = mgr.spawn_swarm_member()
		if m != null:
			_beads.append(m)
	_update()

## Build the border: trace the rectangle from the bottom-middle going LEFT, resample (closed) at
## BEAD_SPACING, then prepend the entry lead-in streaming up from below the bottom edge into the seam.
func _build_path(screen: Vector2) -> void:
	var m := _cm_to_px(BORDER_MARGIN_CM)
	var left := m
	var right := screen.x - m
	var top := m
	var bot := screen.y - m
	var midx := (left + right) * 0.5
	# Seam at bottom-middle; traverse LEFT first: bottom-mid → bottom-left → top-left → top-right →
	# bottom-right → back to bottom-mid (closed loop).
	var waypoints := [
		Vector2(midx, bot),
		Vector2(left, bot),
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bot),
		Vector2(midx, bot),
	]
	var fine: Array = []
	var steps_per := 60
	for w in waypoints.size() - 1:
		var a: Vector2 = waypoints[w]
		var b: Vector2 = waypoints[w + 1]
		for s in steps_per:
			fine.append(a.lerp(b, float(s) / float(steps_per)))
	var shape := _resample_closed(fine, BEAD_SPACING)
	# Entry lead-in: stream UP from below the bottom edge into the seam (bottom-middle).
	var p0: Vector2 = shape[0]
	_entry_n = NUM_ENTRY
	for k in NUM_ENTRY:
		_path.append(Vector2(p0.x, p0.y + float(NUM_ENTRY - k) * ENTRY_STEP))
	_path.append_array(shape)

## Evenly-spaced points (by arc length) around a CLOSED fine polyline — no duplicate at the seam.
func _resample_closed(fine: Array, spacing: float) -> Array:
	var m := fine.size()
	var cum: Array = []
	cum.resize(m + 1)
	cum[0] = 0.0
	for j in m:
		cum[j + 1] = float(cum[j]) + (fine[j] as Vector2).distance_to(fine[(j + 1) % m])
	var total: float = cum[m]
	var n := maxi(8, int(round(total / spacing)))
	var step := total / float(n)
	var out: Array = []
	var seg := 0
	for k in n:
		var target := float(k) * step
		while seg < m - 1 and float(cum[seg + 1]) < target:
			seg += 1
		var f := (target - float(cum[seg])) / maxf(float(cum[seg + 1]) - float(cum[seg]), 0.0001)
		out.append((fine[seg] as Vector2).lerp(fine[(seg + 1) % m], f))
	return out

func tick(delta: float) -> void:
	match _st:
		St.FORMING:
			_lead = minf(_lead + (FORM_SPEED / BEAD_SPACING) * delta, float(_path.size() - 1))
			_update()
			if _lead >= float(_path.size() - 1):
				_circulating = true   # closed loop → keep flowing seamlessly
				_st = St.HOLD
				_hold_t = 0.0
		St.HOLD:
			_lead += (FORM_SPEED / BEAD_SPACING) * delta
			_update()
			_hold_t += delta
			if _hold_t >= HOLD_TIME:
				_st = St.DIVE
				_setup_dive()   # peel anchored to the 6 o'clock seam, paced by actual arrivals
		St.DIVE:
			_lead += (FORM_SPEED / BEAD_SPACING) * delta   # the un-struck part keeps flowing
			_update()
			_tick_dive(delta)

## A bead peels off ONLY when it reaches the 6 o'clock seam: the ring keeps rotating and each bead dives
## as _lead carries it to the seam — one BEAD_SPACING (1 unit) apart, in arrival order from _dive_start.
func _tick_dive(_delta: float) -> void:
	var n := _beads.size()
	while _dive_idx < n and _lead >= _dive_next_lead:
		var m = _beads[(_dive_start + _dive_idx) % n]
		if is_instance_valid(m) and m.has_method("begin_zoom"):
			m.begin_zoom()
		_dive_idx += 1
		_dive_next_lead += 1.0   # the next bead reaches the seam one unit of travel later

## Find the next bead to reach the 6 o'clock seam (smallest forward travel), and the _lead value when it
## gets there. The seam = first border point (ru == _entry_n); beads then arrive in +1 index order.
func _setup_dive() -> void:
	var loop := float(_path.size() - _entry_n)
	var best_i := 0
	var best_delta := loop
	for i in _beads.size():
		if not is_instance_valid(_beads[i]):
			continue
		var delta := fposmod(float(i) + float(_entry_n) - _lead, loop)   # travel until bead i hits the seam
		if delta < best_delta:
			best_delta = delta
			best_i = i
	_dive_start = best_i
	_dive_idx = 0
	_dive_next_lead = _lead + best_delta

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return not _any_alive()

func cleanup() -> void:
	for m in _beads:
		if is_instance_valid(m):
			m.despawn()
	_beads.clear()

# ── Follow-the-leader along the border (wraps once formed → continuous flow) ───
func _update() -> void:
	for i in _beads.size():
		var m = _beads[i]
		if not is_instance_valid(m) or m.is_diving():
			continue
		var u := _lead - float(i)
		m.set_track_pose(_path_point(u), _facing(u), Vector2.ZERO)

func _path_point(u: float) -> Vector2:
	var n := _path.size()
	if _circulating:
		var loop := n - _entry_n   # the closed border portion (skip the off-screen entry nodes)
		var ru := float(_entry_n) + fposmod(u - float(_entry_n), float(loop))
		var iu := int(floor(ru))
		var nxt := iu + 1
		if nxt >= n:
			nxt = _entry_n
		return (_path[iu] as Vector2).lerp(_path[nxt], ru - float(iu))
	if u <= 0.0:
		return _path[0]
	if u >= float(n - 1):
		return _path[n - 1]
	var iu := int(floor(u))
	return (_path[iu] as Vector2).lerp(_path[iu + 1], u - float(iu))

func _facing(u: float) -> float:
	var d := _path_point(u + 0.5) - _path_point(u - 0.5)
	return d.angle() + PI * 0.5 if d.length() > 0.001 else 0.0

func _any_alive() -> bool:
	for m in _beads:
		if is_instance_valid(m):
			return true
	return false
