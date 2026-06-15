extends Node

## Bee hive flock coordinator — 12 bees in a 4-row × 3-col grid.
## Members spawn sequentially from a single off-screen point on a circle around the player,
## then fly to their formation slots.  Once all are in position, rows dive top-to-bottom.

const BeeMember := preload("res://scripts/gameplay/enemy_bee.gd")

const BE_ROWS: int = 4
const BE_COLS: int = 3
const BE_COL_SPACING: float = 40.0
const BE_ROW_SPACING: float = 35.0
const BE_CENTER_Y: float = 115.0
const BE_HOLD_TIME: float = 0.4
const BE_STAGGER: float = 0.2
const BE_SPAWN_INTERVAL: float = 0.12   # seconds between successive member spawns

enum State { SPAWNING, FORMING, HOLD, DIVE_ROW, DONE }
var _state: int = State.SPAWNING
var _mgr: Node = null
var _members: Array = []            # flat, row-major: index = row * BE_COLS + col
var _spawn_queue: Array = []        # Array of Vector2 (formation slot), drained one per interval
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
	_members.clear()
	for row in BE_ROWS:
		for col in BE_COLS:
			var tx := _center_x + (float(col) - float(BE_COLS - 1) * 0.5) * BE_COL_SPACING
			var ty := BE_CENTER_Y + float(row) * BE_ROW_SPACING
			_spawn_queue.append(Vector2(tx, ty))
	_spawn_acc = BE_SPAWN_INTERVAL   # first member releases on this tick
	_state = State.SPAWNING

func _any_alive() -> bool:
	for m in _members:
		if is_instance_valid(m):
			return true
	return false

func _all_in_position() -> bool:
	for m in _members:
		if is_instance_valid(m) and not m.is_in_position():
			return false
	return true

func _process(delta: float) -> void:
	if _state != State.SPAWNING and _state != State.FORMING and not _any_alive():
		queue_free()
		return
	match _state:
		State.SPAWNING:
			_spawn_acc += delta
			while _spawn_queue.size() > 0 and _spawn_acc >= BE_SPAWN_INTERVAL:
				_spawn_acc -= BE_SPAWN_INTERVAL
				var formation: Vector2 = _spawn_queue.pop_front()
				var m := BeeMember.new()
				_mgr.add_child(m)
				m.set_formation_pos(formation)
				m.position = _spawn_origin - m.size * 0.5
				_members.append(m)
			if _spawn_queue.is_empty():
				_state = State.FORMING
		State.FORMING:
			if _all_in_position():
				_hold_acc = 0.0
				_state = State.HOLD
		State.HOLD:
			_hold_acc += delta
			if _hold_acc >= BE_HOLD_TIME:
				_current_row = 0
				_next_in_row = 0
				_stagger_acc = 0.0
				_state = State.DIVE_ROW
		State.DIVE_ROW:
			_stagger_acc += delta
			while _next_in_row < BE_COLS:
				if _stagger_acc >= float(_next_in_row) * BE_STAGGER:
					var idx := _current_row * BE_COLS + _next_in_row
					if idx < _members.size():
						var m = _members[idx]
						if is_instance_valid(m):
							m.begin_dive()
					_next_in_row += 1
				else:
					break
			if _next_in_row >= BE_COLS:
				_current_row += 1
				if _current_row >= BE_ROWS:
					_state = State.DONE
				else:
					_stagger_acc = 0.0
					_next_in_row = 0
		State.DONE:
			pass
