extends Node

## Swarm flock coordinator (NOT an enemy itself). It owns ONE shared track and marches all SW_COUNT
## members along it single-file, like beads on a wire:
##   • a horizontal conga line enters from a side edge,
##   • travels just SW_ENTER_CM inward, then bends UP at the bottom of a circle and drives around it,
##   • every follower rides the EXACT same track, offset by SW_LINE_SPACING, so they end up evenly
##     strung around the full ring (which forms right next to the entry point).
## The ring never pauses — once formed it keeps rotating and does ONE full extra revolution, then each
## member DIVES the instant it reaches the 6 o'clock (bottom) point — one-by-one, lead first. A dive is
## an aim-once dash at the player's position captured at that moment (see enemy_swarm.gd).
##
## A "slot" (assigned by EnemyManager) places each concurrent swarm at a distinct, symmetric station so
## they don't overlap: slot 0 = left/top, 1 = right/top, 2 = left/row2, 3 = right/row2, … (left/right
## pairs descending in rows). Members are children of the EnemyManager (live in the play area + are
## shootable the whole time); this node only orchestrates and frees itself once none remain.

const SwarmMember := preload("res://scripts/gameplay/enemy_swarm.gd")

# ── Tunable constants (Swarm formation) ───────────────────────────────────────
const SW_COUNT: int = 8
const SW_CIRCLE_RADIUS: float = 90.0
const SW_LINE_SPACING: float = 70.0           # gap between beads along the track (≈ ring/8 → even ring)
const SW_ENTER_CM: float = 1.5                # straight travel from the edge before the circle forms
const SW_ROW_SPACING: float = 200.0           # vertical gap between stations (slots 2+ go lower)
const SW_MAX_ROWS: int = 3                    # how many rows of stations before wrapping
const SW_ENTER_SPEED: float = 400.0           # travel speed of the conga, the forming ring, AND the dive feed
const SW_FORM_TIMEOUT: float = 8.0            # safety backstop if forming somehow stalls

enum State { FORMING, DIVE, DONE }
var _mgr: Node = null
var _slot: int = 0
var _members: Array = []      # in entry order; entries may go invalid (shot down) — never re-indexed
var _state: int = State.FORMING
var _form_timeout: float = 0.0
var _next: int = 0            # next member (entry order) to launch in the DIVE phase

# Shared-track parameters (set in spawn_flock).
var _s_lead: float = 0.0      # distance the lead has travelled along the track
var _s0: float = 0.0          # _s_lead when the dives begin (lead exactly at 6 o'clock)
var _center: Vector2 = Vector2.ZERO
var _edge: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _spin: float = -1.0
var _l_entry: float = 0.0
var _circ: float = 0.0

func setup(mgr: Node, slot: int) -> void:
	_mgr = mgr
	_slot = slot

func spawn_flock() -> void:
	var screen: Vector2 = _mgr.screen_size()
	var from_left := (_slot % 2) == 0
	var row := (_slot / 2) % SW_MAX_ROWS
	var enter_dist := _cm_to_px(SW_ENTER_CM)
	var edge_x := 0.0 if from_left else screen.x
	_dir = Vector2(1.0, 0.0) if from_left else Vector2(-1.0, 0.0)
	_spin = -1.0 if from_left else 1.0                       # left → curve up the right side, vice-versa
	var entry_y := 2.0 * SW_CIRCLE_RADIUS + float(row) * SW_ROW_SPACING   # circle top at screen top for row 0
	_edge = Vector2(edge_x, entry_y)
	_center = Vector2(edge_x + _dir.x * enter_dist, entry_y - SW_CIRCLE_RADIUS)   # ring sits just inside the edge
	_l_entry = enter_dist
	_circ = TAU * SW_CIRCLE_RADIUS
	_s_lead = 0.0
	for i in SW_COUNT:
		var m := SwarmMember.new()
		_mgr.add_child(m)
		_members.append(m)
	_update_followers()

func _cm_to_px(cm: float) -> float:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

## World position at arc-length `s` along the shared track: straight entry, then around the circle
## (entered at 6 o'clock = PI/2 in screen coords). Valid for s<0 too (queues members off-screen).
func path_point(s: float) -> Vector2:
	if s < _l_entry:
		return _edge + _dir * s
	var ang := PI * 0.5 + _spin * (s - _l_entry) / SW_CIRCLE_RADIUS
	return _center + SW_CIRCLE_RADIUS * Vector2(cos(ang), sin(ang))

func _facing(s: float) -> float:
	var d := path_point(s + 2.0) - path_point(s)
	if d.length() < 0.001:
		return 0.0
	return d.angle() + PI * 0.5

func _update_followers() -> void:
	for i in _members.size():
		var m = _members[i]
		if not is_instance_valid(m) or m.is_diving():
			continue
		var s := _s_lead - float(i) * SW_LINE_SPACING
		m.set_track_pose(path_point(s), _facing(s))

func _any_alive() -> bool:
	for m in _members:
		if is_instance_valid(m):
			return true
	return false

func _process(delta: float) -> void:
	if not _any_alive():
		queue_free()
		return
	match _state:
		State.FORMING:
			_form_timeout += delta
			_s_lead += SW_ENTER_SPEED * delta
			if _s_lead >= _l_entry + 2.0 * _circ:
				_s_lead = _l_entry + 2.0 * _circ   # ring forms (1 lap) + one full extra revolution
				_s0 = _s_lead                       # lead sits exactly at 6 o'clock
				_state = State.DIVE                 # no pause — flow straight into the rotating dives
				_next = 0
			elif _form_timeout >= SW_FORM_TIMEOUT:
				_s0 = _s_lead
				_state = State.DIVE
				_next = 0
			_update_followers()
		State.DIVE:
			# Keep rotating the ring at the travel speed; a bead crosses 6 o'clock every spacing/speed sec.
			_s_lead += SW_ENTER_SPEED * delta
			while _next < SW_COUNT and _s_lead >= _s0 + float(_next) * SW_LINE_SPACING:
				var m = _members[_next]
				if is_instance_valid(m):
					m.begin_zoom()   # this member is exactly at the bottom now
				_next += 1
			_update_followers()
			if _next >= SW_COUNT:
				_state = State.DONE
		State.DONE:
			pass   # members dash in independently; freed at the top once all are gone
