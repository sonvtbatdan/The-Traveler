extends Node2D
## Fast near parallax layer for asteroid fields (sells speed — closer than the planets, so they whip past).
## Manual parallax (position = camera*(1-factor)). Streams sparse CLUSTERS deterministically by world cell:
## most cells are empty, occasionally a dense drifting field of varied irregular rocks. F5 spawns a field
## near the player (group "debug_asteroid", cleared by Shift+F5).

const AsteroidScript := preload("res://scripts/gameplay/arena_asteroid.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const ASTEROID_FACTOR := 0.7        # parallax: faster than planets (0.40) → strong speed cue
const ASTEROID_Z      := -10        # just behind gameplay (player/enemies/projectiles at z >= 0)
const FIELD_DENSITY   := 0.06       # chance a coarse cell holds a field (sparse)
const FIELD_CELL      := 1100.0     # world px per field cell
const FIELD_SPREAD    := Vector2(120.0, 320.0)   # scatter radius of a field
const PER_CLUSTER     := Vector2i(6, 16)         # asteroids per field
const FIELD_DRIFT     := Vector2(6.0, 18.0)      # slow constant drift px/s (so clusters move even when idle)

var _fields: Dictionary = {}   # Vector2i cell → field Node2D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("arena_asteroids")
	z_index = ASTEROID_Z
	_rng.randomize()

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	position = cam.global_position * (1.0 - ASTEROID_FACTOR)
	# Drift every field (parallax + drift + per-rock spin = lively motion even when the player is still).
	for f in get_children():
		var fn := f as Node2D
		if fn != null:
			fn.position += fn.get_meta("drift", Vector2.ZERO) * delta
	# Stream fields around the layer-space view centre.
	var vc := cam.global_position * ASTEROID_FACTOR
	var vp := get_viewport().get_visible_rect().size / cam.zoom
	var half := vp * 0.5 + Vector2(FIELD_CELL, FIELD_CELL)
	var cx0 := int(floor((vc.x - half.x) / FIELD_CELL))
	var cx1 := int(ceil((vc.x + half.x) / FIELD_CELL))
	var cy0 := int(floor((vc.y - half.y) / FIELD_CELL))
	var cy1 := int(ceil((vc.y + half.y) / FIELD_CELL))
	var needed := {}
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cy)
			if _has_field(key):
				needed[key] = true
				if not _fields.has(key):
					_spawn_cell(key)
	for key: Vector2i in _fields.keys():
		if not needed.has(key):
			if is_instance_valid(_fields[key]):
				_fields[key].queue_free()
			_fields.erase(key)

func _cell_rng(key: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(key.x * 92837111, key.y * 689287499))
	return rng

func _has_field(key: Vector2i) -> bool:
	return _cell_rng(key).randf() < FIELD_DENSITY

func _spawn_cell(key: Vector2i) -> void:
	var rng := _cell_rng(key)
	rng.randf()   # consume the density value so the rest of the stream matches _has_field
	var jitter := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * FIELD_CELL
	var centre := Vector2(key) * FIELD_CELL + Vector2(FIELD_CELL, FIELD_CELL) * 0.5 + jitter
	_fields[key] = _make_field(centre, rng, false)

## Build a field (a Node2D holding N scattered asteroids) at a layer-local centre.
func _make_field(local_centre: Vector2, rng: RandomNumberGenerator, debug: bool) -> Node2D:
	var field := Node2D.new()
	add_child(field)
	field.position = local_centre
	var spread := rng.randf_range(FIELD_SPREAD.x, FIELD_SPREAD.y)
	var n := rng.randi_range(PER_CLUSTER.x, PER_CLUSTER.y)
	for i in n:
		var a := AsteroidScript.new()
		field.add_child(a)
		a.setup(rng)
		a.position = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * spread
	var ds := rng.randf_range(FIELD_DRIFT.x, FIELD_DRIFT.y)
	field.set_meta("drift", Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * ds)
	if debug:
		field.add_to_group("debug_asteroid")
	return field

## F5: spawn a field near a world point (converted to this layer's local space).
func spawn_field_near(world_centre: Vector2) -> int:
	var field := _make_field(to_local(world_centre), _rng, true)
	return field.get_child_count()

func clear_debug() -> void:
	for n in get_tree().get_nodes_in_group("debug_asteroid"):
		if is_instance_valid(n):
			n.queue_free()
