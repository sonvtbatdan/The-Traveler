extends "res://scripts/gameplay/choreography_base.gd"

## Swarm_pentagram — the swarm traces a five-pointed star in ONE unbroken stroke (the classic
## "without lifting the pen" pentagram), optionally inside a ring (an occult sigil), holds with a glow
## pulse, then dives one-by-one. Reuses the swarm bead (enemy_swarm.gd): set_track_pose() for the
## follow-the-leader formation, begin_zoom() for the aim-once dive.
##
## STAR PATH: 5 points evenly on a circle (top point up), connected in SKIP-ONE order
## (p0→p2→p4→p1→p3→p0) so the 5 chords cross in the centre and form the star. With RING_ENABLED the
## path is: circle (one loop) → short connector → star, all one connected stroke.
##
## TUNE everything via the consts below.

const CENTER_X_FRAC := 0.5
const TOP_MARGIN := 12.0       # the top of the sigil sits this many px from the top edge
const STAR_R := 90.0           # star radius (px) — 40% smaller
const BEAD_SPACING := 66.0     # spacing of beads along the path (~60% of the old density → fewer divers)
const RING_ENABLED := true     # outer ring around the star (the sigil look)
const RING_R := 123.0          # ring radius (px) — 40% smaller
const NUM_ENTRY := 6           # off-screen lead-in nodes (stream in from above)
const ENTRY_STEP := 42.0
const FORM_SPEED := 400.0      # px/s the lead traces the shape (slow, ominous)
const HOLD_TIME := 2.5         # seconds to hold the sigil before diving
const PULSE_ENABLED := true    # ominous glow pulse during the hold
const PULSE_SPEED := 4.0       # rad/s of the pulse
const PULSE_MIN := 0.55
const PULSE_MAX := 1.35
const DIVE_STAGGER := 0.09     # seconds between each bead's dive
const MAX_TIME := 90.0

enum St { FORMING, HOLD, DIVE }
var _st: int = St.FORMING
var _beads: Array = []
var _path: Array = []          # entry nodes + the shape's even-spaced points (one bead per shape point)
var _entry_n: int = 0
var _lead: float = 0.0
var _hold_t: float = 0.0
var _pulse_t: float = 0.0
var _dive_order: Array = []
var _dive_idx: int = 0
var _dive_t: float = 0.0

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.FORMING
	_beads.clear(); _path.clear(); _dive_order.clear()
	_lead = 0.0; _hold_t = 0.0; _pulse_t = 0.0; _dive_idx = 0; _dive_t = 0.0
	_build_path(mgr.screen_size())
	for i in _path.size() - _entry_n:   # one bead per shape point
		var m = mgr.spawn_swarm_member()
		if m != null:
			_beads.append(m)
	_update()

## Build the single continuous path: [entry lead-in] + [ring + connector if enabled] + [star skip-one].
func _build_path(screen: Vector2) -> void:
	# Anchor the sigil so its topmost extent (ring top, or the upper star points) is TOP_MARGIN from the edge.
	var r_top := RING_R if RING_ENABLED else STAR_R * 0.809   # 0.809 = cos36° = inverted star's top extent
	var center := Vector2(screen.x * CENTER_X_FRAC, TOP_MARGIN + r_top)
	var sp: Array = []   # the 5 star points — PI/2 puts the first point DOWN → upside-down (inverted) pentagram
	for k in 5:
		var a := PI * 0.5 + float(k) * TAU / 5.0
		sp.append(center + STAR_R * Vector2(cos(a), sin(a)))
	var order := [0, 2, 4, 1, 3]   # skip-one
	var shape: Array = []
	if RING_ENABLED:
		var n_ring := maxi(8, int(round(TAU * RING_R / BEAD_SPACING)))
		for j in n_ring:
			var a := -PI * 0.5 + float(j) * TAU / float(n_ring)
			shape.append(center + RING_R * Vector2(cos(a), sin(a)))
		shape.append_array(_sample(shape[shape.size() - 1], sp[order[0]], BEAD_SPACING))   # connector ring→star
	if shape.is_empty():
		shape.append(sp[order[0]])   # first star point (no ring)
	var prev: Vector2 = sp[order[0]]
	for idx in range(1, order.size()):
		var v: Vector2 = sp[order[idx]]
		shape.append_array(_sample(prev, v, BEAD_SPACING))
		prev = v
	shape.append_array(_sample(prev, sp[order[0]], BEAD_SPACING))   # close back to p0
	# Entry lead-in: stream in from above the first shape point.
	var p0: Vector2 = shape[0]
	_entry_n = NUM_ENTRY
	for k in NUM_ENTRY:
		_path.append(Vector2(p0.x, p0.y - float(NUM_ENTRY - k) * ENTRY_STEP))
	_path.append_array(shape)

## Points from a (exclusive) to b (inclusive), spaced ~`spacing`.
func _sample(a: Vector2, b: Vector2, spacing: float) -> Array:
	var pts: Array = []
	var n := maxi(1, int(round(a.distance_to(b) / spacing)))
	for k in range(1, n + 1):
		pts.append(a.lerp(b, float(k) / float(n)))
	return pts

func tick(delta: float) -> void:
	match _st:
		St.FORMING:
			_lead = minf(_lead + (FORM_SPEED / BEAD_SPACING) * delta, float(_path.size() - 1))
			_update()
			if _lead >= float(_path.size() - 1):
				_st = St.HOLD
				_hold_t = 0.0; _pulse_t = 0.0
		St.HOLD:
			_update()
			if PULSE_ENABLED:
				_apply_pulse(delta)
			_hold_t += delta
			if _hold_t >= HOLD_TIME:
				_begin_dive()
		St.DIVE:
			_update()
			_tick_dive(delta)

func _begin_dive() -> void:
	_st = St.DIVE
	_dive_idx = 0
	_dive_t = DIVE_STAGGER
	_dive_order.clear()
	for m in _beads:
		if is_instance_valid(m):
			m.modulate = Color.WHITE   # clear the pulse glow before diving
	# Ring on → ring beads (path start) dive first, then the star: that's descending bead index.
	# No ring → lead-first (the head, bead 0, peels off the star): ascending.
	if RING_ENABLED:
		for i in range(_beads.size() - 1, -1, -1):
			_dive_order.append(_beads[i])
	else:
		for m in _beads:
			_dive_order.append(m)

func _tick_dive(delta: float) -> void:
	_dive_t += delta
	while _dive_idx < _dive_order.size() and _dive_t >= DIVE_STAGGER:
		_dive_t -= DIVE_STAGGER
		var m = _dive_order[_dive_idx]
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

# ── Follow-the-leader along the single path ───────────────────────────────────
func _update() -> void:
	for i in _beads.size():
		var m = _beads[i]
		if not is_instance_valid(m) or m.is_diving():
			continue
		var u := _lead - float(i)
		m.set_track_pose(_path_point(u), _facing(u), Vector2.ZERO)

func _apply_pulse(delta: float) -> void:
	_pulse_t += delta
	var v := PULSE_MIN + (PULSE_MAX - PULSE_MIN) * 0.5 * (1.0 + sin(_pulse_t * PULSE_SPEED))
	for m in _beads:
		if is_instance_valid(m) and not m.is_diving():
			m.modulate = Color(v, v, v)

func _path_point(u: float) -> Vector2:
	var n := _path.size()
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
