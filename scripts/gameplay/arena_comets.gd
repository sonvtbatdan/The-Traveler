extends Node2D
## Mid parallax layer for comets (rare, dramatic, cheap). Manual parallax (~planet depth). Streams very
## sparse comets deterministically by world cell. F9 spawns one near the player (group "debug_comet",
## cleared by Shift+F9).

const CometScript := preload("res://scripts/gameplay/arena_comet.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const COMET_FACTOR  := 0.4        # mid depth, like the planets → distant-but-present
const COMET_Z       := -48        # just in front of the planets (-50)
const COMET_DENSITY := 0.015      # chance a coarse cell holds a comet (very rare)
const COMET_CELL    := 2600.0     # world px per comet cell (big = very sparse)

var _comets: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("arena_comets")
	z_index = COMET_Z
	_rng.randomize()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	position = cam.global_position * (1.0 - COMET_FACTOR)
	var vc := cam.global_position * COMET_FACTOR
	var vp := get_viewport().get_visible_rect().size / cam.zoom
	var half := vp * 0.5 + Vector2(COMET_CELL, COMET_CELL)
	var cx0 := int(floor((vc.x - half.x) / COMET_CELL))
	var cx1 := int(ceil((vc.x + half.x) / COMET_CELL))
	var cy0 := int(floor((vc.y - half.y) / COMET_CELL))
	var cy1 := int(ceil((vc.y + half.y) / COMET_CELL))
	var needed := {}
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cy)
			if _has_comet(key):
				needed[key] = true
				if not _comets.has(key):
					_spawn_cell(key)
	for key: Vector2i in _comets.keys():
		if not needed.has(key):
			if is_instance_valid(_comets[key]):
				_comets[key].queue_free()
			_comets.erase(key)

func _cell_rng(key: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(key.x * 40503131, key.y * 326437))
	return rng

func _has_comet(key: Vector2i) -> bool:
	return _cell_rng(key).randf() < COMET_DENSITY

func _spawn_cell(key: Vector2i) -> void:
	var rng := _cell_rng(key)
	rng.randf()
	var jitter := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * COMET_CELL
	var centre := Vector2(key) * COMET_CELL + Vector2(COMET_CELL, COMET_CELL) * 0.5 + jitter
	var c := CometScript.new()
	add_child(c)
	c.setup(rng)
	c.position = centre
	_comets[key] = c

## F9: spawn a comet near a world point (converted to this layer's local space).
func spawn_comet_near(world_centre: Vector2) -> void:
	var c := CometScript.new()
	c.add_to_group("debug_comet")
	add_child(c)
	c.setup(_rng)
	c.position = to_local(world_centre)

func clear_debug() -> void:
	for n in get_tree().get_nodes_in_group("debug_comet"):
		if is_instance_valid(n):
			n.queue_free()
