extends Node

## Bug flock coordinator — 16 bugs in a 4-row × 4-col grid.
## Members spawn sequentially from a single off-screen point on a circle around the player.
## After formation, rows dive with an expand-then-dive arc.

const BugMember := preload("res://scripts/gameplay/enemy_bug.gd")

const BU_ROWS: int = 4
const BU_COLS: int = 4
const BU_COL_SPACING: float = 36.0
const BU_ROW_SPACING: float = 32.0
const BU_EXPAND_SPACING: float = 60.0
const BU_CENTER_Y: float = 110.0
const BU_HOLD_TIME: float = 0.4
const BU_STAGGER: float = 0.2
const BU_SPAWN_INTERVAL: float = 0.10   # seconds between successive member spawns

enum State { SPAWNING, FORMING, HOLD, DIVE_ROW, DONE }
var _state: int = State.SPAWNING
var _mgr: Node = null
var _member_grid: Array = []   # [row][col] BugMember or null
var _spawn_queue: Array = []   # Array of {row, col, formation: Vector2}, drained one per interval
var _spawn_acc: float = 0.0
var _spawn_origin: Vector2 = Vector2.ZERO
var _center_x: float = 0.0
var _hold_acc: float = 0.0
var _current_row: int = 0
var _next_in_row: int = 0
var _stagger_acc: float = 0.0

func setup(mgr: Node) -> void:
	_mgr = mgr

func spawn_flock() -> void:
	var screen: Vector2 = _mgr.screen_size()
	var pc: Vector2 = _mgr.ship_center()
	_center_x = screen.x * 0.5
	var radius := Vector2(screen.x, screen.y).length() * 0.5 + 100.0
	var angle := randf() * TAU
	_spawn_origin = pc + Vector2(cos(angle), sin(angle)) * radius

	_spawn_queue.clear()
	_member_grid.clear()
	for _r in BU_ROWS:
		_member_grid.append([null, null, null, null])
	for row in BU_ROWS:
		for col in BU_COLS:
			var tx := _center_x + (float(col) - float(BU_COLS - 1) * 0.5) * BU_COL_SPACING
			var ty := BU_CENTER_Y + float(row) * BU_ROW_SPACING
			_spawn_queue.append({"row": row, "col": col, "formation": Vector2(tx, ty)})
	_spawn_acc = BU_SPAWN_INTERVAL   # first member releases on this tick
	_state = State.SPAWNING

func _any_alive() -> bool:
	for row in _member_grid:
		for m in row:
			if is_instance_valid(m):
				return true
	return false

func _all_in_position() -> bool:
	for row in _member_grid:
		for m in row:
			if is_instance_valid(m) and not m.is_in_position():
				return false
	return true

func _launch_row(row_idx: int, col_idx: int) -> void:
	var m = _member_grid[row_idx][col_idx]
	if not is_instance_valid(m):
		return
	var ex := _center_x + (float(col_idx) - float(BU_COLS - 1) * 0.5) * BU_EXPAND_SPACING
	var ey := BU_CENTER_Y + float(row_idx) * BU_ROW_SPACING
	m.begin_dive_from(Vector2(ex, ey))

func _process(delta: float) -> void:
	if _state != State.SPAWNING and _state != State.FORMING and not _any_alive():
		queue_free()
		return
	match _state:
		State.SPAWNING:
			_spawn_acc += delta
			while _spawn_queue.size() > 0 and _spawn_acc >= BU_SPAWN_INTERVAL:
				_spawn_acc -= BU_SPAWN_INTERVAL
				var data: Dictionary = _spawn_queue.pop_front()
				var m := BugMember.new()
				_mgr.add_child(m)
				m.set_formation_pos(data["formation"])
				m.position = _spawn_origin - m.size * 0.5
				_member_grid[data["row"]][data["col"]] = m
			if _spawn_queue.is_empty():
				_state = State.FORMING
		State.FORMING:
			if _all_in_position():
				_hold_acc = 0.0
				_state = State.HOLD
		State.HOLD:
			_hold_acc += delta
			if _hold_acc >= BU_HOLD_TIME:
				_current_row = 0
				_next_in_row = 0
				_stagger_acc = 0.0
				_state = State.DIVE_ROW
		State.DIVE_ROW:
			_stagger_acc += delta
			while _next_in_row < BU_COLS:
				if _stagger_acc >= float(_next_in_row) * BU_STAGGER:
					_launch_row(_current_row, _next_in_row)
					_next_in_row += 1
				else:
					break
			if _next_in_row >= BU_COLS:
				_current_row += 1
				if _current_row >= BU_ROWS:
					_state = State.DONE
				else:
					_stagger_acc = 0.0
					_next_in_row = 0
		State.DONE:
			pass
