extends Node

## Flies flock coordinator — 20 flies in two concentric rings (inner 8, outer 12).
## Members spawn sequentially from a single off-screen point on a circle around the player,
## then each fly self-drives to a random scatter target within the screen.

const FlyMember := preload("res://scripts/gameplay/enemy_fly.gd")

const FL_COUNT_INNER: int = 8
const FL_COUNT_OUTER: int = 12
const FL_RADIUS_INNER: float = 55.0
const FL_RADIUS_OUTER: float = 110.0
const FL_CENTER_Y: float = 150.0
const FL_SPAWN_INTERVAL: float = 0.08   # seconds between successive spawns

var _mgr: Node = null
var _members: Array = []
var _spawn_queue: Array = []   # Array of Vector2 (ring position as initial scatter anchor)
var _spawn_acc: float = 0.0
var _spawn_origin: Vector2 = Vector2.ZERO
var _spawning: bool = false

func setup(mgr: Node) -> void:
	_mgr = mgr

func spawn_flock() -> void:
	var screen: Vector2 = _mgr.screen_size()
	var pc: Vector2 = _mgr.ship_center()
	var cx := screen.x * 0.5
	var radius := Vector2(screen.x, screen.y).length() * 0.5 + 100.0
	var angle := randf() * TAU
	_spawn_origin = pc + Vector2(cos(angle), sin(angle)) * radius

	_spawn_queue.clear()
	_members.clear()
	for i in FL_COUNT_INNER:
		var a := TAU * float(i) / float(FL_COUNT_INNER)
		_spawn_queue.append(Vector2(cx + FL_RADIUS_INNER * cos(a), FL_CENTER_Y + FL_RADIUS_INNER * sin(a)))
	for i in FL_COUNT_OUTER:
		var a := TAU * float(i) / float(FL_COUNT_OUTER)
		_spawn_queue.append(Vector2(cx + FL_RADIUS_OUTER * cos(a), FL_CENTER_Y + FL_RADIUS_OUTER * sin(a)))
	_spawn_acc = FL_SPAWN_INTERVAL
	_spawning = true

func _any_alive() -> bool:
	for m in _members:
		if is_instance_valid(m):
			return true
	return false

func _process(delta: float) -> void:
	if _spawning:
		_spawn_acc += delta
		while _spawn_queue.size() > 0 and _spawn_acc >= FL_SPAWN_INTERVAL:
			_spawn_acc -= FL_SPAWN_INTERVAL
			var ring_pos: Vector2 = _spawn_queue.pop_front()
			var m := FlyMember.new()
			_mgr.add_child(m)
			# set_initial_pos sets scatter_acc stagger; we then override position to off-screen origin
			m.set_initial_pos(ring_pos)
			m.position = _spawn_origin - m.size * 0.5
			_members.append(m)
		if _spawn_queue.is_empty():
			_spawning = false
	elif _members.size() > 0 and not _any_alive():
		queue_free()
