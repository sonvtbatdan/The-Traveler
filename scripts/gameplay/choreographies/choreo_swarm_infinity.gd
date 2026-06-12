extends "res://scripts/gameplay/choreography_base.gd"

## Swarm_infinity — the follow-the-leader swarm traces a horizontal INFINITY sign (∞), one continuous
## closed figure-eight. Once drawn, the beads keep FLOWING around the loop (energy through the symbol),
## hold for a bit, then strike — diving one-by-one, lead-first. Reuses the swarm bead (enemy_swarm.gd):
## set_track_pose for the formation, begin_zoom for the aim-once dive.
##
## SHAPE: Gerono lemniscate  x = RX·cos t,  y = RY·sin t·cos t,  t ∈ [0, 2π)  → a clean horizontal ∞ that
## crosses itself in the centre. TUNE everything via the consts below.

const CENTER_X_FRAC := 0.5
const CENTER_Y_FRAC := 0.42
const RX := 180.0              # half-width of the ∞ (px)
const RY := 140.0              # lobe height factor (the ∞ spans ±RY/2 vertically)
const BEAD_SPACING := 40.0     # spacing of beads along the curve → enemy count (~24)
const NUM_ENTRY := 6           # off-screen lead-in nodes (stream in from above)
const ENTRY_STEP := 42.0
const FORM_SPEED := 400.0      # px/s the lead traces the ∞ AND flows around it during the hold
const HOLD_TIME := 3.0         # seconds the ∞ keeps flowing before striking
const HEAD_DISTINCT := false   # ∞ is symmetric/headless → off by default (tint/enlarge lead if on)
const HEAD_TINT := Color(1.5, 0.45, 0.45)
const HEAD_SCALE := 1.6
const DIVE_STAGGER := 0.09     # seconds between each bead's dive (lead-first)
const MAX_TIME := 90.0

enum St { FORMING, HOLD, DIVE }
var _st: int = St.FORMING
var _beads: Array = []
var _path: Array = []          # entry nodes + the ∞'s even-spaced points (one bead per point)
var _entry_n: int = 0
var _lead: float = 0.0
var _circulating: bool = false
var _hold_t: float = 0.0
var _dive_idx: int = 0
var _dive_t: float = 0.0

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.FORMING
	_beads.clear(); _path.clear()
	_lead = 0.0; _circulating = false; _hold_t = 0.0; _dive_idx = 0; _dive_t = 0.0
	_build_path(mgr.screen_size())
	for i in _path.size() - _entry_n:   # one bead per curve point
		var m = mgr.spawn_swarm_member()
		if m != null:
			_beads.append(m)
	if HEAD_DISTINCT and not _beads.is_empty() and is_instance_valid(_beads[0]):
		_beads[0].modulate = HEAD_TINT
		_beads[0].scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	_update()

## Build the ∞: sample the lemniscate finely, arc-length resample at BEAD_SPACING (closed), + entry.
func _build_path(screen: Vector2) -> void:
	var center := Vector2(screen.x * CENTER_X_FRAC, screen.y * CENTER_Y_FRAC)
	var fine: Array = []
	var steps := 480
	for j in steps:
		var t := float(j) / float(steps) * TAU
		fine.append(center + Vector2(RX * cos(t), RY * sin(t) * cos(t)))
	var shape := _resample_closed(fine, BEAD_SPACING)
	# Entry lead-in: stream in from above the first curve point.
	var p0: Vector2 = shape[0]
	_entry_n = NUM_ENTRY
	for k in NUM_ENTRY:
		_path.append(Vector2(p0.x, p0.y - float(NUM_ENTRY - k) * ENTRY_STEP))
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
				_dive_idx = 0
				_dive_t = DIVE_STAGGER
		St.DIVE:
			_lead += (FORM_SPEED / BEAD_SPACING) * delta   # the un-struck part keeps flowing
			_update()
			_tick_dive(delta)

func _tick_dive(delta: float) -> void:
	_dive_t += delta
	while _dive_idx < _beads.size() and _dive_t >= DIVE_STAGGER:
		_dive_t -= DIVE_STAGGER
		var m = _beads[_dive_idx]   # bead 0 = lead → lead-first
		if is_instance_valid(m) and m.has_method("begin_zoom"):
			m.begin_zoom()
		_dive_idx += 1

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return not _any_alive()

func cleanup() -> void:
	for m in _beads:
		if is_instance_valid(m):
			m.despawn()
	_beads.clear()

# ── Follow-the-leader along the ∞ (wraps once formed → continuous flow) ────────
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
		var loop := n - _entry_n   # the closed ∞ portion (skip the off-screen entry nodes)
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
