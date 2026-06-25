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
const LIGHT_GAIN  := 1.7                     # how strongly the player's weapon lights brighten the rock
const LIGHT_MAX   := 1.6                     # clamp per-channel added brightness
const SPECK_RANGE := Vector2i(10, 22)       # random surface flecks per rock (mineral specks that catch the light)
const SPECK_SIZE  := Vector2(0.05, 0.15)    # fleck radius as a fraction of the rock radius
const SPECK_TWINKLE := 2.5                  # twinkle speed when lit

var _dirs: Array[Vector2] = []   # unit direction per vertex (local, unrotated)
var _pts := PackedVector2Array() # local vertex positions
var _pits: Array = []            # [{pos, r}]
var _spin := 0.0
var _radius := 10.0
var _layer: Node = null          # arena_asteroids — source of the shared weapon-light list
var _lit_add: Color = Color(0, 0, 0)   # this frame's reflected weapon light (added to the rock colour)
var _specks: Array = []          # [{pos, r, b, ph}] surface flecks — only drawn when the rock is lit
var _t: float = 0.0              # clock for the speck twinkle

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
	var nsp := rng.randi_range(SPECK_RANGE.x, SPECK_RANGE.y)
	for i in nsp:
		var sa := rng.randf() * TAU
		var sr := sqrt(rng.randf()) * _radius * 0.85   # sqrt → uniform over the disc area
		var rad := maxf(0.6, rng.randf_range(SPECK_SIZE.x, SPECK_SIZE.y) * _radius)
		_specks.append({"pos": Vector2(cos(sa), sin(sa)) * sr, "r": rad, "b": rng.randf_range(0.6, 1.5), "ph": rng.randf() * TAU})
	rotation = rng.randf() * TAU
	_spin = rng.randf_range(SPIN_RANGE.x, SPIN_RANGE.y) * (1.0 if rng.randf() < 0.5 else -1.0)
	queue_redraw()

func set_layer(l: Node) -> void:
	_layer = l

func _process(delta: float) -> void:
	rotation += _spin * delta
	_t += delta
	_update_weapon_light()
	queue_redraw()   # re-shade so the lit side stays toward the light as the rock tumbles

## Sum the player's weapon lights that reach this rock → the colour the rock reflects this frame.
func _update_weapon_light() -> void:
	_lit_add = Color(0, 0, 0)
	if _layer == null or not is_instance_valid(_layer) or not _layer.has_method("current_lights"):
		return
	var wp := global_position
	for l: Dictionary in _layer.call("current_lights"):
		var reach: float = l["reach"]
		if reach <= 0.0:
			continue
		var dd := wp.distance_to(l["pos"])
		if dd >= reach:
			continue
		var fall := (1.0 - dd / reach) * float(l["val"]) * LIGHT_GAIN
		var c: Color = l["col"]
		_lit_add.r += c.r * fall
		_lit_add.g += c.g * fall
		_lit_add.b += c.b * fall
	_lit_add.r = minf(_lit_add.r, LIGHT_MAX)
	_lit_add.g = minf(_lit_add.g, LIGHT_MAX)
	_lit_add.b = minf(_lit_add.b, LIGHT_MAX)

func _draw() -> void:
	var ld := LIGHT_DIR.normalized()
	var cols := PackedColorArray()
	for d: Vector2 in _dirs:
		var wd := d.rotated(rotation)               # vertex world direction (node is rotated)
		var lit: float = clamp(wd.dot(ld) * 0.5 + 0.5, 0.0, 1.0)
		var c := BASE_COL * (0.45 + 0.75 * lit)
		c.r += _lit_add.r                            # reflect the player's weapon lights
		c.g += _lit_add.g
		c.b += _lit_add.b
		cols.append(c)
	draw_polygon(_pts, cols)
	# Small pits: a dark floor with a faint lit edge on the light side.
	for pit: Dictionary in _pits:
		var p: Vector2 = pit["pos"]
		var r: float = pit["r"]
		draw_circle(p, r, BASE_COL * 0.4)
		draw_circle(p - ld.rotated(-rotation) * r * 0.4, r * 0.45, BASE_COL * 0.95)
	# Surface flecks — invisible until a weapon light hits the rock, then they sparkle in that light's colour.
	if _lit_add.r + _lit_add.g + _lit_add.b > 0.02:
		for s: Dictionary in _specks:
			var tw := 0.7 + 0.3 * sin(_t * SPECK_TWINKLE + float(s["ph"]))
			var b := float(s["b"]) * tw
			draw_circle(s["pos"], float(s["r"]), Color(_lit_add.r * b, _lit_add.g * b, _lit_add.b * b))
