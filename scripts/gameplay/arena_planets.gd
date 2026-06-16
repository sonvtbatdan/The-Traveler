extends Node2D
## Mid-distance planet layer. Manual parallax (position = camera*(1-factor)) since planets are discrete
## (Parallax2D tiles a texture). Streams sparse planets deterministically by world cell: each coarse cell
## hashes to maybe-a-planet with a type/palette derived from its seed, so flying back finds the same planet
## in the same place. z_index keeps them behind gameplay, in front of the nebula/stars.

const PlanetScript := preload("res://scripts/gameplay/arena_planet.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const PLANET_FACTOR  := 0.40    # parallax: 0 = static far, 1 = surface speed (mid-distance)
const PLANET_Z       := -50     # behind player/enemies/projectiles, in front of nebula/stars
const PLANET_DENSITY := 0.07    # chance a coarse cell holds a planet (LOW = sparse, < 1/screen)
const PLANET_CELL    := 1500.0  # world px per planet cell (big = sparse)
# Moons orbiting a planet (sells scale).
const MOON_CHANCE     := 0.45   # chance a planet gets any moons
const MOON_TWO_CHANCE := 0.35   # of those, chance of a second moon
const MOON_SIZE_RATIO := Vector2(0.18, 0.32)   # moon radius as a fraction of the parent's
const MOON_ORBIT_MULT := Vector2(1.5, 2.4)     # orbit radius as a multiple of the parent's radius
const MOON_ORBIT_SPEED := Vector2(0.15, 0.5)   # radians/sec
const MOON_TYPES       := [0, 10]              # rocky or barren

var _planets: Dictionary = {}   # Vector2i cell → planet node

func _ready() -> void:
	add_to_group("arena_planets")
	z_index = PLANET_Z

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	position = cam.global_position * (1.0 - PLANET_FACTOR)
	var vc := cam.global_position * PLANET_FACTOR     # layer-space view centre
	var vp := get_viewport().get_visible_rect().size / cam.zoom
	var half := vp * 0.5 + Vector2(PLANET_CELL, PLANET_CELL)
	var cx0 := int(floor((vc.x - half.x) / PLANET_CELL))
	var cx1 := int(ceil((vc.x + half.x) / PLANET_CELL))
	var cy0 := int(floor((vc.y - half.y) / PLANET_CELL))
	var cy1 := int(ceil((vc.y + half.y) / PLANET_CELL))
	var needed := {}
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cy)
			if _has_planet(key):
				needed[key] = true
				if not _planets.has(key):
					_spawn_cell(key)
	for key: Vector2i in _planets.keys():
		if not needed.has(key):
			if is_instance_valid(_planets[key]):
				_planets[key].despawn()   # frees the planet + its moons
			_planets.erase(key)

func _cell_rng(key: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(key.x * 73856093, key.y * 19349663))
	return rng

func _has_planet(key: Vector2i) -> bool:
	return _cell_rng(key).randf() < PLANET_DENSITY

func _spawn_cell(key: Vector2i) -> void:
	var rng := _cell_rng(key)
	rng.randf()   # consume the same density value so the rest matches _has_planet's stream
	# Weighted type pick across all 12 (common rock/ice; Earth/ringed/carbon rare).
	var t := rng.randf()
	var type := 0
	if t < 0.20: type = 0        # rocky
	elif t < 0.34: type = 5      # desert
	elif t < 0.46: type = 2      # ice
	elif t < 0.56: type = 10     # barren
	elif t < 0.64: type = 4      # lava
	elif t < 0.72: type = 1      # gas giant
	elif t < 0.79: type = 8      # toxic
	elif t < 0.86: type = 7      # ocean
	elif t < 0.92: type = 9      # jungle
	elif t < 0.96: type = 3      # earth (rare)
	elif t < 0.985: type = 11    # carbon (rare)
	else: type = 6               # ringed (rarest)
	var params := PlanetScript.roll_params(type, rng)
	var jitter := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * PLANET_CELL
	var pl := PlanetScript.new()
	add_child(pl)
	pl.apply(params)
	pl.position = Vector2(key) * PLANET_CELL + Vector2(PLANET_CELL, PLANET_CELL) * 0.5 + jitter
	if rng.randf() < MOON_CHANCE:
		_add_moons(pl, float(params.get("radius", 60.0)), rng)
	_planets[key] = pl

## Roll the moon chance, then give `parent` moons if it wins (used by the F6 menu drag-spawn).
func maybe_add_moons(parent: Node2D, parent_radius: float, rng: RandomNumberGenerator) -> void:
	if rng.randf() < MOON_CHANCE:
		_add_moons(parent, parent_radius, rng)

## Give `parent` 1-2 orbiting moons (siblings on this layer so they don't inherit the parent's scale).
func _add_moons(parent: Node2D, parent_radius: float, rng: RandomNumberGenerator) -> void:
	var n := 2 if rng.randf() < MOON_TWO_CHANCE else 1
	for i in n:
		var mtype: int = MOON_TYPES[rng.randi() % MOON_TYPES.size()]
		var mp := PlanetScript.roll_params(mtype, rng)
		mp["radius"] = parent_radius * rng.randf_range(MOON_SIZE_RATIO.x, MOON_SIZE_RATIO.y)
		var moon := PlanetScript.new()
		add_child(moon)
		moon.apply(mp)
		var orbit_r := parent_radius * rng.randf_range(MOON_ORBIT_MULT.x, MOON_ORBIT_MULT.y) + parent_radius
		var spd := rng.randf_range(MOON_ORBIT_SPEED.x, MOON_ORBIT_SPEED.y) * (1.0 if rng.randf() < 0.5 else -1.0)
		moon.set_orbit(parent, orbit_r, spd, rng.randf() * TAU)
		moon.position = parent.position + Vector2(cos(moon.orbit_angle), sin(moon.orbit_angle)) * orbit_r
		if parent.is_in_group("debug_planet"):
			moon.add_to_group("debug_planet")
		parent._moons.append(moon)

## F10: spawn a planet WITH moons at a world position (debug). Returns the planet.
func spawn_planet_with_moons(world_pos: Vector2, rng: RandomNumberGenerator) -> Node2D:
	var type: int = [0, 1, 3, 5, 7][rng.randi() % 5]   # types that look good with moons
	var params := PlanetScript.roll_params(type, rng)
	var pl := PlanetScript.new()
	pl.add_to_group("debug_planet")
	add_child(pl)
	pl.apply(params)
	pl.position = to_local(world_pos)
	_add_moons(pl, float(params.get("radius", 60.0)), rng)   # guaranteed moons for inspection
	return pl
