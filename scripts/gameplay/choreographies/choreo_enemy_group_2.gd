extends "res://scripts/gameplay/choreography_base.gd"

## Enemy_group_2 — "DIE in a box", then dive.
## • BOX: a single-file conga traces the rectangle perimeter and CIRCULATES continuously.
## • LETTERS: once the frame is up, each letter bead appears at a random spot in the TOP THIRD of the
##   map and ZOOMS onto its dot while SPINNING; then it's held with handwriting stroke facing (vertical
##   strokes face down, horizontal arms face right). The word shape (dot positions) is unchanged.
## • Hold BANNER_HOLD (~1s), then DIVE: the BOX peels off at the BOTTOM-MIDDLE of the frame — each bead
##   dives the moment it circulates through that point — then the LETTERS dive one-by-one (lead-first).
##   Reuses the swarm's aim-once dash (begin_zoom).
##
## TUNE: box size/pos, LETTER_CELL/GAP, the D/I/E_DOTS maps (cell + per-dot stroke facing), the zoom/spin,
## hold, and dive stagger.

# ── Box geometry ──────────────────────────────────────────────────────────────
const BANNER_CENTER_X_FRAC := 0.5
const BOX_TOP := 10.0
const BOX_W := 460.0
const BOX_H := 224.0
const BOX_SPACING := 55.0
const FORM_SPEED := 420.0           # box conga trace speed AND continuous circulation speed
const FORM_TIMEOUT := 14.0          # safety backstop if box forming stalls

# ── Letters ───────────────────────────────────────────────────────────────────
const LETTER_CELL := 30.0
const LETTER_GAP := 44.0
const LETTER_ZOOM_TIME := 1.5       # seconds for a bead to zoom from its top-third start onto its dot
const LETTER_SPIN_SPEED := 12.0     # rad/s a bead spins while zooming in
# Each entry = [cell (col,row; row 0 = top), STROKE FACING]:
#   Vector2(0,1) = down (vertical strokes), Vector2(1,0) = right (horizontal arms), Vector2.ZERO = down-default.
const D_DOTS := [
	[Vector2i(0,0), Vector2.ZERO], [Vector2i(0,1), Vector2.ZERO], [Vector2i(0,2), Vector2.ZERO],
	[Vector2i(0,3), Vector2.ZERO], [Vector2i(0,4), Vector2.ZERO], [Vector2i(1,4), Vector2.ZERO],
	[Vector2i(2,3), Vector2.ZERO], [Vector2i(2,2), Vector2.ZERO], [Vector2i(2,1), Vector2.ZERO],
	[Vector2i(1,0), Vector2.ZERO],
]
const I_DOTS := [
	[Vector2i(0,0), Vector2(1,0)], [Vector2i(1,0), Vector2(1,0)], [Vector2i(2,0), Vector2(1,0)],   # top bar → right
	[Vector2i(1,1), Vector2(0,1)], [Vector2i(1,2), Vector2(0,1)], [Vector2i(1,3), Vector2(0,1)],   # stem → down
	[Vector2i(0,4), Vector2(1,0)], [Vector2i(1,4), Vector2(1,0)], [Vector2i(2,4), Vector2(1,0)],   # bottom bar → right
]
const E_DOTS := [
	[Vector2i(2,0), Vector2(1,0)], [Vector2i(1,0), Vector2(1,0)],                                   # top arm → right
	[Vector2i(0,0), Vector2(0,1)], [Vector2i(0,1), Vector2(0,1)], [Vector2i(0,2), Vector2(0,1)],    # spine → down
	[Vector2i(1,2), Vector2(1,0)],                                                                   # middle arm → right
	[Vector2i(0,3), Vector2(0,1)], [Vector2i(0,4), Vector2(0,1)],                                    # spine → down
	[Vector2i(1,4), Vector2(1,0)], [Vector2i(2,4), Vector2(1,0)],                                    # bottom arm → right
]

# ── Timing / dive ─────────────────────────────────────────────────────────────
const BANNER_HOLD := 1.0            # seconds the finished word holds before diving
const DIVE_STAGGER := 0.1           # seconds between LETTER dives (lead-first)
const MAX_TIME := 90.0              # director backstop

enum St { FORMING, HOLD, BOX_DIVE, LETTER_DIVE }
var _st: int = St.FORMING

# Box state
var _box: Array = []
var _s_lead: float = 0.0
var _perim: float = 0.0
var _entry_len: float = 0.0
var _tl: Vector2 = Vector2.ZERO
var _form_t: float = 0.0
var _box_p_prev: Array = []     # previous perimeter position per box bead (bottom-middle crossing detect)
var _bottom_mid_t: float = 0.0  # arc-length of the bottom-middle along the perimeter

# Letter state
var _letters: Array = []
var _letter_targets: Array = []   # each bead's final dot position
var _letter_dirs: Array = []      # each dot's stroke facing
var _letter_starts: Array = []    # each bead's random top-third start
var _letter_form_t: float = 0.0
var _letters_started: bool = false

# Hold / dive
var _hold_t: float = 0.0
var _dive_idx: int = 0
var _dive_t: float = 0.0

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.FORMING
	_box.clear(); _box_p_prev.clear()
	_letters.clear(); _letter_targets.clear(); _letter_dirs.clear(); _letter_starts.clear()
	_s_lead = 0.0; _form_t = 0.0; _letter_form_t = 0.0; _hold_t = 0.0; _dive_idx = 0; _dive_t = 0.0
	_letters_started = false
	var screen: Vector2 = mgr.screen_size()
	_tl = Vector2(screen.x * BANNER_CENTER_X_FRAC - BOX_W * 0.5, BOX_TOP)
	_perim = 2.0 * (BOX_W + BOX_H)
	_entry_len = _tl.x + BOX_W
	_bottom_mid_t = 2.0 * BOX_H + 1.5 * BOX_W   # right(H)+top(W)+left(H)+half-bottom(W/2)
	var n_box := int(round(_perim / BOX_SPACING))
	for i in n_box:
		var m = mgr.spawn_swarm_member()
		if m != null:
			_box.append(m)
			_box_p_prev.append(0.0)
	_build_letter_targets()
	_update_box()

## Compute every letter dot's final position + stroke facing (word shape never changes).
func _build_letter_targets() -> void:
	var cell := LETTER_CELL
	var letter_w := 2.0 * cell   # 3 cols → span 2 cells
	var letter_h := 4.0 * cell   # 5 rows → span 4 cells
	var block_w := 3.0 * letter_w + 2.0 * LETTER_GAP
	var bx := (_tl.x + BOX_W * 0.5) - block_w * 0.5
	var by := (_tl.y + BOX_H * 0.5) - letter_h * 0.5
	var maps := [D_DOTS, I_DOTS, E_DOTS]
	for li in 3:
		var origin := Vector2(bx + float(li) * (letter_w + LETTER_GAP), by)
		for entry: Array in maps[li]:
			var c: Vector2i = entry[0]
			_letter_targets.append(origin + Vector2(float(c.x) * cell, float(c.y) * cell))
			_letter_dirs.append(entry[1])

## Spawn the letter beads once the frame is up — each at a random spot in the TOP THIRD of the map.
func _spawn_letters() -> void:
	var screen: Vector2 = _mgr.screen_size()
	for i in _letter_targets.size():
		var m = _mgr.spawn_swarm_member()
		_letters.append(m)
		_letter_starts.append(Vector2(randf() * screen.x, randf() * (screen.y / 3.0)))
	_update_letters()

func tick(delta: float) -> void:
	match _st:
		St.FORMING:
			_form_t += delta
			_s_lead += FORM_SPEED * delta
			_update_box()
			var box_formed: bool = _s_lead >= _entry_len + _perim or _form_t >= FORM_TIMEOUT
			if box_formed and not _letters_started:
				_letters_started = true
				_spawn_letters()
			if _letters_started:
				_letter_form_t += delta
				_update_letters()
				if _letter_form_t >= LETTER_ZOOM_TIME:
					_st = St.HOLD
					_hold_t = 0.0
		St.HOLD:
			_s_lead += FORM_SPEED * delta
			_update_box(); _update_letters()
			_hold_t += delta
			if _hold_t >= BANNER_HOLD:
				_begin_box_dive()
		St.BOX_DIVE:
			_s_lead += FORM_SPEED * delta
			_tick_box_dive()
			_update_box(); _update_letters()
			if _all_box_diving():
				_st = St.LETTER_DIVE
				_dive_idx = 0
				_dive_t = DIVE_STAGGER
		St.LETTER_DIVE:
			_s_lead += FORM_SPEED * delta
			_update_box(); _update_letters()
			_tick_letter_dive(delta)

# ── Dive ──────────────────────────────────────────────────────────────────────
func _begin_box_dive() -> void:
	_st = St.BOX_DIVE
	for i in _box.size():
		_box_p_prev[i] = fposmod((_s_lead - float(i) * BOX_SPACING) - _entry_len, _perim)

## As the box circulates, dive each bead the instant it passes the bottom-middle point.
func _tick_box_dive() -> void:
	for i in _box.size():
		var m = _box[i]
		if not is_instance_valid(m) or m.is_diving():
			continue
		var p := fposmod((_s_lead - float(i) * BOX_SPACING) - _entry_len, _perim)
		if _crossed(float(_box_p_prev[i]), p, _bottom_mid_t):
			m.begin_zoom()
		_box_p_prev[i] = p

## Did the forward arc prev→cur (wrapping at _perim) sweep past `target`?
func _crossed(prev: float, cur: float, target: float) -> bool:
	if cur >= prev:
		return target > prev and target <= cur
	return target > prev or target <= cur   # wrapped around the seam

func _all_box_diving() -> bool:
	for m in _box:
		if is_instance_valid(m) and not m.is_diving():
			return false
	return true

## Letters dive one-by-one, lead-first.
func _tick_letter_dive(delta: float) -> void:
	_dive_t += delta
	while _dive_idx < _letters.size() and _dive_t >= DIVE_STAGGER:
		_dive_t -= DIVE_STAGGER
		var m = _letters[_dive_idx]
		if is_instance_valid(m) and m.has_method("begin_zoom"):
			m.begin_zoom()
		_dive_idx += 1

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return not _any_alive()   # done once every bead has dived off-screen (or been shot down)

func cleanup() -> void:
	for m in _box:
		if is_instance_valid(m):
			m.despawn()
	for m in _letters:
		if is_instance_valid(m):
			m.despawn()
	_box.clear(); _letters.clear()

# ── Box path (entry → counter-clockwise perimeter, circulating) ───────────────
func _update_box() -> void:
	for i in _box.size():
		var m = _box[i]
		if not is_instance_valid(m) or m.is_diving():
			continue   # a diving bead owns its own movement
		var s := _s_lead - float(i) * BOX_SPACING
		var t := _path_point(s + 2.0) - _path_point(s)   # raw path tangent
		m.set_track_pose(_path_point(s), _ang(t), _dir(t))

func _path_point(s: float) -> Vector2:
	if s < _entry_len:
		return Vector2(s, _tl.y + BOX_H)   # slide right along the bottom to the far corner
	return _perim_point(fmod(s - _entry_len, _perim))

## Perimeter from the bottom-RIGHT, counter-clockwise: up right edge → top R→L → down left edge →
## bottom L→R (so the bottom-middle is reached last, where the dives peel off).
func _perim_point(t: float) -> Vector2:
	var bl_y := _tl.y + BOX_H
	var rx := _tl.x + BOX_W
	if t < BOX_H:
		return Vector2(rx, bl_y - t)                          # right edge, BR → TR
	t -= BOX_H
	if t < BOX_W:
		return Vector2(rx - t, _tl.y)                          # top edge, TR → TL
	t -= BOX_W
	if t < BOX_H:
		return Vector2(_tl.x, _tl.y + t)                       # left edge, TL → BL
	t -= BOX_H
	return Vector2(_tl.x + t, bl_y)                            # bottom edge, BL → BR

# ── Letters: zoom-in (spinning) → held with stroke facing ─────────────────────
func _update_letters() -> void:
	if _letters.is_empty():
		return
	var t := clampf(_letter_form_t / LETTER_ZOOM_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - t, 2.0)   # ease-out: zoom in and settle onto the dot
	for i in _letters.size():
		var m = _letters[i]
		if not is_instance_valid(m) or m.is_diving():
			continue
		if t < 1.0:
			var pos := (_letter_starts[i] as Vector2).lerp(_letter_targets[i], e)
			m.set_track_pose(pos, _letter_form_t * LETTER_SPIN_SPEED, Vector2.ZERO)   # spinning while it flies in
		else:
			var d: Vector2 = _letter_dirs[i]
			if d == Vector2.ZERO:
				d = Vector2(0, 1)   # default downward (D dots)
			m.set_track_pose(_letter_targets[i], _ang(d), _dir(d))

# ── Helpers ───────────────────────────────────────────────────────────────────
## Rotation from a direction vector: angle + 90° (triangle art points UP at rotation 0).
func _ang(d: Vector2) -> float:
	return d.angle() + PI * 0.5 if d.length() > 0.001 else 0.0

func _dir(d: Vector2) -> Vector2:
	return d.normalized() if d.length() > 0.001 else Vector2.ZERO

func _any_alive() -> bool:
	for m in _box:
		if is_instance_valid(m):
			return true
	for m in _letters:
		if is_instance_valid(m):
			return true
	return false
