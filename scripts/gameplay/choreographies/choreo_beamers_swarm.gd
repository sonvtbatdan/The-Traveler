extends "res://scripts/gameplay/choreography_base.gd"

## Beamers_swarm — a large multi-stage set-piece: 4 externally-controlled beamers + interleaved swarms.
## This file currently implements the ENTRANCE stage only (Stages 2 & 3 come later).
##
## ENTRANCE: 4 beamers slide in from the sides into a trapezoid — the top 2 settle TOP_INSET_CM in and
## fire straight DOWN, the bottom 2 settle BOTTOM_INSET_CM in and fire straight UP. Simultaneously the
## Enemy_group_2 "DIE-in-a-box" word-speller runs wholesale. When it finishes + INTER_STAGE_GAP, the
## stage ends. The beamers are driven via their external_control hooks (no change to beamer combat).
##
## NOTE on the trapezoid: with TOP_INSET_CM (1) < BOTTOM_INSET_CM (2) the shape is WIDER at the top /
## narrower at the bottom. Swap the two inset consts to flip it.

const ChoreoEnemyGroup2 := preload("res://scripts/gameplay/choreographies/choreo_enemy_group_2.gd")

# ── Tunables (cm → px via _cm_to_px; the DPI helper the other choreographies use) ──
const TOP_INSET_CM := 1.0          # top beamers settle this far in from their side edge
const BOTTOM_INSET_CM := 2.0       # bottom beamers settle this far in from their side edge
const TOP_Y_CM := 1.0              # top beamers' y, measured from the TOP edge
const BOTTOM_Y_CM := 1.0           # bottom beamers' y, measured from the BOTTOM edge
const ENTRY_MARGIN_CM := 2.0       # how far off-screen (past the side edge) the beamers start
const MOVE_SETTLE_TIME := 1.2      # seconds per eased move (all 4 arrive together)
const EASE_POW := 3.0              # ease-out exponent: higher = faster start, softer settle
const INTER_STAGE_GAP := 0.0       # pause after a swarm element finishes before the next stage (tunable)
const MAX_TIME := 120.0
# Stage 2
const BOX_SIZE_CM := 6.0           # the beamers form a BOX_SIZE_CM × BOX_SIZE_CM square on the map centre
const CIRCLE_CENTER_Y_CM := 3.0    # the mid-top swarm circle's ring centre, measured from the TOP edge
# Stage 3 — the box keeps spinning while it grows outward until every beamer leaves the map (no swarms).
const ROT_PERIOD := 5.0            # seconds for one full counter-clockwise box rotation
const S3_DURATION := 10.0          # seconds the box grows/spins before all beamers are off-map → end
const S3_EXIT_MARGIN := 80.0       # px past the screen's corner radius that counts as "fully off-map"

enum St { ENTER, FIRE_HOLD, GAP, S2_MOVE, S2_FIRE, S2_GAP, S3, DONE }
var _st: int = St.ENTER
var _beamers: Array = []   # [{node, settle:Vector2, dir:Vector2, arrived:bool}]  index 0=TL 1=TR 2=BL 3=BR
var _dead: Node = null
var _circle: Node = null
var _rot_angle: float = 0.0
var _box_units: Array = []     # unit corner directions (±1,±1) — scaled by the growing half each frame
var _box_dirs: Array = []      # base inward fire dir per beamer
var _move_t: float = 0.0       # eased-move timer (ENTER + S2_MOVE)
var _s3_t: float = 0.0         # Stage-3 elapsed (drives the outward growth + the 10s end)
var _start_half: float = 0.0   # box half-extent at Stage-3 start
var _end_half: float = 0.0     # box half-extent that puts every beamer off-map
var _gap_t: float = 0.0

func start(mgr: Node) -> void:
	super(mgr)
	_st = St.ENTER
	_beamers.clear()
	_dead = null
	_gap_t = 0.0
	var screen: Vector2 = mgr.screen_size()
	var w := screen.x
	var h := screen.y
	var top_y := _cm_to_px(TOP_Y_CM)
	var bot_y := h - _cm_to_px(BOTTOM_Y_CM)
	var top_in := _cm_to_px(TOP_INSET_CM)
	var bot_in := _cm_to_px(BOTTOM_INSET_CM)
	var margin := _cm_to_px(ENTRY_MARGIN_CM)
	# 4 beamers: top-left, top-right (fire DOWN); bottom-left, bottom-right (fire UP).
	_add_beamer(mgr, Vector2(-margin, top_y),     Vector2(top_in, top_y),       Vector2.DOWN)
	_add_beamer(mgr, Vector2(w + margin, top_y),  Vector2(w - top_in, top_y),   Vector2.DOWN)
	_add_beamer(mgr, Vector2(-margin, bot_y),     Vector2(bot_in, bot_y),       Vector2.UP)
	_add_beamer(mgr, Vector2(w + margin, bot_y),  Vector2(w - bot_in, bot_y),   Vector2.UP)
	_begin_move()   # ease the entrance slide-in (start fast → settle into the trapezoid)

## Spawn one externally-controlled beamer, dormant, parked off-screen at `start_c`.
func _add_beamer(mgr: Node, start_c: Vector2, settle_c: Vector2, dir: Vector2) -> void:
	var b = mgr.spawn_beamer_node()
	if b == null:
		return
	b.external_control = true
	b.fire_enabled = false
	b.continuous_fire = true   # once charged, hold the beam ON through the whole swarm attack
	b.invulnerable = true      # blocks shots but takes no damage for the whole choreography
	b.position = start_c - b.size * 0.5
	_beamers.append({"node": b, "settle": settle_c, "dir": dir, "start": start_c})

func tick(delta: float) -> void:
	match _st:
		St.ENTER:
			if _tick_move(delta):
				_begin_fire_hold()
		St.FIRE_HOLD:
			if _dead != null and is_instance_valid(_dead):
				_dead.tick(delta)
				if _dead.is_done():
					_end_dead()
					_st = St.GAP
					_gap_t = 0.0
			else:
				_st = St.GAP
				_gap_t = 0.0
		St.GAP:
			_gap_t += delta   # beamers keep firing through the gap
			if _gap_t >= INTER_STAGE_GAP:
				_begin_stage2_move()
		St.S2_MOVE:
			if _tick_move(delta):
				_begin_stage2_fire()
		St.S2_FIRE:
			if _circle == null or not is_instance_valid(_circle):
				_st = St.S2_GAP
				_gap_t = 0.0
		St.S2_GAP:
			_gap_t += delta
			if _gap_t >= INTER_STAGE_GAP:
				_begin_stage3()
		St.S3:
			_s3_t += delta
			_rot_angle += (TAU / ROT_PERIOD) * delta   # keep spinning (counter-clockwise)
			var f := clampf(_s3_t / S3_DURATION, 0.0, 1.0)
			_apply_box_rotation(lerpf(_start_half, _end_half, f))   # grow the box outward as it spins
			if _s3_t >= S3_DURATION:
				_st = St.DONE   # all beamers are off-map → attack ends (cleanup despawns them)
		St.DONE:
			pass

## Beamers are in position → aim them, switch firing on, and launch the DIE-in-a-box swarm wholesale.
func _begin_fire_hold() -> void:
	_st = St.FIRE_HOLD
	for bm in _beamers:
		var b = bm["node"]
		if is_instance_valid(b):
			b.aim(bm["dir"])
			b.fire_enabled = true
	_dead = ChoreoEnemyGroup2.new()
	add_child(_dead)
	_dead.start(_mgr)

func _end_dead() -> void:
	if _dead != null and is_instance_valid(_dead):
		_dead.cleanup()
		_dead.queue_free()
	_dead = null

# ── Stage 2: re-form into a 4×4cm box on the map centre, fire inward, + one mid-top swarm circle ──
## Stop firing and retarget each beamer to its box corner (index 0=TL 1=TR 2=BL 3=BR → box corners).
func _begin_stage2_move() -> void:
	_st = St.S2_MOVE
	var screen: Vector2 = _mgr.screen_size()
	var cx := screen.x * 0.5
	var cy := screen.y * 0.5
	var half := _cm_to_px(BOX_SIZE_CM) * 0.5
	# Box corner per beamer, and the inward fire direction the spec assigns to each.
	var corners := [
		Vector2(cx - half, cy - half),  # 0 top-left     → fires DOWN
		Vector2(cx + half, cy - half),  # 1 top-right    → fires LEFT
		Vector2(cx - half, cy + half),  # 2 bottom-left  → fires RIGHT
		Vector2(cx + half, cy + half),  # 3 bottom-right → fires UP
	]
	var dirs := [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	for i in _beamers.size():
		var bm = _beamers[i]
		var b = bm["node"]
		if is_instance_valid(b):
			b.fire_enabled = false   # stop firing before moving (charges fresh on arrival)
		bm["settle"] = corners[i]
		bm["dir"] = dirs[i]
	_begin_move()   # ease into the box (start fast → settle), all four arriving together

## Beamers are at the box → aim inward, fire fresh, and send in one swarm circle at middle-top.
func _begin_stage2_fire() -> void:
	_st = St.S2_FIRE
	for bm in _beamers:
		var b = bm["node"]
		if is_instance_valid(b):
			b.aim(bm["dir"])
			b.fire_enabled = true   # IDLE → charge → continuous beam
	var screen: Vector2 = _mgr.screen_size()
	var ring_center := Vector2(screen.x * 0.5, _cm_to_px(CIRCLE_CENTER_Y_CM))
	_circle = _mgr.spawn_swarm_at(ring_center, true)

# ── Stage 3: the box keeps its shape + inward fire dirs, spins CCW, and GROWS outward over S3_DURATION ──
## until every beamer is off the map, then the attack ends. No swarms.
func _begin_stage3() -> void:
	_st = St.S3
	_rot_angle = 0.0
	_s3_t = 0.0
	_box_units = [
		Vector2(-1.0, -1.0),  # 0 top-left     → DOWN
		Vector2(1.0, -1.0),   # 1 top-right    → LEFT
		Vector2(-1.0, 1.0),   # 2 bottom-left  → RIGHT
		Vector2(1.0, 1.0),    # 3 bottom-right → UP
	]
	_box_dirs = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	_start_half = _cm_to_px(BOX_SIZE_CM) * 0.5
	# A beamer sits at corner-offset half·√2 from centre; once that exceeds the screen's corner radius
	# (+ margin) every beamer is off-map at any spin angle. Reach that exactly at S3_DURATION.
	var screen: Vector2 = _mgr.screen_size()
	_end_half = (screen.length() * 0.5 + S3_EXIT_MARGIN) / sqrt(2.0)

## Place the box at the given half-extent: rotate each corner offset + fire dir by -_rot_angle (CCW).
func _apply_box_rotation(half: float) -> void:
	var screen: Vector2 = _mgr.screen_size()
	var c := screen * 0.5
	var a := -_rot_angle
	for i in _beamers.size():
		var b = _beamers[i]["node"]
		if not is_instance_valid(b):
			continue
		var off: Vector2 = (_box_units[i] * half).rotated(a)
		var dir: Vector2 = _box_dirs[i].rotated(a)
		b.position = (c + off) - b.size * 0.5
		b.aim(dir)

func max_time() -> float:
	return MAX_TIME

func is_done() -> bool:
	return _st == St.DONE

func cleanup() -> void:
	_end_dead()
	if _circle != null and is_instance_valid(_circle):
		_circle.queue_free()
	_circle = null
	for bm in _beamers:
		var b = bm["node"]
		if is_instance_valid(b):
			b.despawn()
	_beamers.clear()

## Snapshot each beamer's current centre as the move origin and reset the settle timer.
func _begin_move() -> void:
	_move_t = 0.0
	for bm in _beamers:
		var b = bm["node"]
		if is_instance_valid(b):
			bm["start"] = b.position + b.size * 0.5

## Ease every beamer start→settle over MOVE_SETTLE_TIME (fast start, slow settle). True when all arrived.
func _tick_move(delta: float) -> bool:
	_move_t += delta
	var t := clampf(_move_t / MOVE_SETTLE_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - t, EASE_POW)   # ease-out: quick off the line, decelerating into place
	for bm in _beamers:
		var b = bm["node"]
		if not is_instance_valid(b):
			continue
		var p: Vector2 = (bm["start"] as Vector2).lerp(bm["settle"], e)
		b.position = p - b.size * 0.5
	return t >= 1.0
