extends Node2D
## A single procedural asteroid — an irregular rocky chunk (NOT a sphere). The silhouette is a lumpy
## polygon (circle with per-vertex jittered radius). Shaded light-aware like the rocky planet (lit side /
## shadow side from a 2D light_dir) with a few small pits. Tumbles with a slow constant spin; lighting is
## recomputed each frame in world space so the terminator stays fixed while the rock rotates.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SIZE_RANGE  := Vector2(6.0, 18.0)     # drawn radius px (small — these whip past, don't block play)
const VERTS_RANGE := Vector2i(8, 14)        # silhouette vertices
const JAG         := 0.45                    # per-vertex radius jitter (0 = smooth circle, 1 = very jagged)
const SPIN_RANGE  := Vector2(0.2, 1.2)      # spin speed rad/s
const PIT_RANGE   := Vector2i(1, 4)         # small craters/pits per rock
const BASE_COL    := Color(0.42, 0.38, 0.32)  # grey-brown rock
const LIGHT_DIR   := Vector2(0.6, -0.5)     # same convention as the planets (light_dir.xy)

var _dirs: Array[Vector2] = []   # unit direction per vertex (local, unrotated)
var _pts := PackedVector2Array() # local vertex positions
var _pits: Array = []            # [{pos, r}]
var _spin := 0.0
var _radius := 10.0

func setup(rng: RandomNumberGenerator) -> void:
	_radius = rng.randf_range(SIZE_RANGE.x, SIZE_RANGE.y)
	var nv := rng.randi_range(VERTS_RANGE.x, VERTS_RANGE.y)
	for i in nv:
		var a := TAU * float(i) / float(nv)
		var dir := Vector2(cos(a), sin(a))
		var r := _radius * (1.0 - JAG * 0.5 + rng.randf() * JAG)
		_dirs.append(dir)
		_pts.append(dir * r)
	var np := rng.randi_range(PIT_RANGE.x, PIT_RANGE.y)
	for i in np:
		var pa := rng.randf() * TAU
		var pr := rng.randf() * _radius * 0.5
		_pits.append({"pos": Vector2(cos(pa), sin(pa)) * pr, "r": rng.randf_range(0.12, 0.26) * _radius})
	rotation = rng.randf() * TAU
	_spin = rng.randf_range(SPIN_RANGE.x, SPIN_RANGE.y) * (1.0 if rng.randf() < 0.5 else -1.0)
	queue_redraw()

func _process(delta: float) -> void:
	rotation += _spin * delta
	queue_redraw()   # re-shade so the lit side stays toward the light as the rock tumbles

func _draw() -> void:
	var ld := LIGHT_DIR.normalized()
	var cols := PackedColorArray()
	for d: Vector2 in _dirs:
		var wd := d.rotated(rotation)               # vertex world direction (node is rotated)
		var lit: float = clamp(wd.dot(ld) * 0.5 + 0.5, 0.0, 1.0)
		cols.append(BASE_COL * (0.45 + 0.75 * lit))
	draw_polygon(_pts, cols)
	# Small pits: a dark floor with a faint lit edge on the light side.
	for pit: Dictionary in _pits:
		var p: Vector2 = pit["pos"]
		var r: float = pit["r"]
		draw_circle(p, r, BASE_COL * 0.4)
		draw_circle(p - ld.rotated(-rotation) * r * 0.4, r * 0.45, BASE_COL * 0.95)
