extends Node2D
## Authored, finite solar system around world origin: a central sun (rendered SHARP in the main viewport),
## inner rocky planets → asteroid belt → outer gas giants, all slowly orbiting. Built once with a fixed seed
## (identical landmarks every run); orbits in place — no per-cell streaming. Lives on its own mid-distance
## parallax layer (factor 0.40) inside the DoF background, so planets + belt get depth + blur; the sun is
## excluded from the blur (sharp) and tracked in the main viewport so it lines up with this layer's origin.
##
## Reuses arena_planet.gd (visual + set_orbit polar motion) for planets AND moons, and arena_asteroid.gd for
## the belt rocks. Orbit is nested for free: a moon's set_orbit(parent=planet) reads the planet's live
## position each frame, and the planet itself orbits the fixed _anchor.

const PlanetScript := preload("res://scripts/gameplay/arena_planet.gd")
const AsteroidScript := preload("res://scripts/gameplay/arena_asteroid.gd")
const SUN_SHADER := "res://assets/shaders/sun.gdshader"

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const LAYER_FACTOR := 0.40          # parallax depth (matches the old planet layer)
const LAYER_Z      := -50
const SYSTEM_SEED  := 20260616      # fixed → identical landmarks every run
const GLOBAL_ORBIT_MULT := 0.02     # very slow — barely perceptible over a run (scales every planet orbit)

const SUN_RADIUS := 240.0           # drawn sun radius px
const SUN_Z      := -50             # sharp, behind gameplay, in front of the blurred composite

# Authored bodies (compressed distances — order/feel kept, gaps squished). type = arena_planet type id.
const PLANETS := [
	{"name": "Mercury", "orbit": 520.0,  "radius": 26.0,  "type": 0, "moons": 0, "speed": 0.95},  # rocky
	{"name": "Venus",   "orbit": 700.0,  "radius": 40.0,  "type": 8, "moons": 0, "speed": 0.72},  # toxic
	{"name": "Earth",   "orbit": 900.0,  "radius": 44.0,  "type": 3, "moons": 1, "speed": 0.60},  # earth
	{"name": "Mars",    "orbit": 1120.0, "radius": 34.0,  "type": 5, "moons": 2, "speed": 0.48},  # desert
	{"name": "Jupiter", "orbit": 1850.0, "radius": 120.0, "type": 1, "moons": 3, "speed": 0.28},  # gas giant
	{"name": "Saturn",  "orbit": 2350.0, "radius": 100.0, "type": 6, "moons": 2, "speed": 0.22},  # ringed
	{"name": "Uranus",  "orbit": 2820.0, "radius": 66.0,  "type": 2, "moons": 1, "speed": 0.17},  # ice
	{"name": "Neptune", "orbit": 3300.0, "radius": 64.0,  "type": 2, "moons": 1, "speed": 0.14},  # ice
]
const BELT_RADIUS := 1480.0         # between Mars (1120) and Jupiter (1850)
const BELT_WIDTH  := 240.0
const BELT_COUNT  := 90             # belt rocks (frozen after spawn — see below — so this is mostly node count)
const BELT_ORBIT_SPEED := 0.05      # whole-belt revolution rad/s (× GLOBAL_ORBIT_MULT)

# Moons (orbit their planet; kept lively but gentle — local motion doesn't affect navigation).
const MOON_SIZE_RATIO  := Vector2(0.12, 0.22)   # moon radius as a fraction of the planet's
const MOON_SURFACE_GAP := Vector2(0.4, 0.9)     # moon-surface→planet-surface gap (× planet radius)
const MOON_SPEED       := Vector2(0.05, 0.15)   # rad/s
const MOON_TYPES       := [0, 10]               # rocky / barren

var sun_host: Node = null           # main-viewport node to host the (sharp) sun — set BEFORE add_child
var _anchor: Node2D = null          # fixed orbit centre at layer-local (0,0)
var _belt: Node2D = null
var _sun: Sprite2D = null

static var _white_tex: Texture2D = null

func _ready() -> void:
	add_to_group("arena_solar_system")
	z_index = LAYER_Z
	var rng := RandomNumberGenerator.new()
	rng.seed = SYSTEM_SEED

	_anchor = Node2D.new()
	add_child(_anchor)   # planets orbit this fixed point

	_sun = _make_sun()
	if sun_host != null:
		sun_host.add_child(_sun)   # main viewport → sharp (excluded from the blur)
	else:
		add_child(_sun)            # fallback

	for def: Dictionary in PLANETS:
		var p := PlanetScript.new()
		add_child(p)
		var params := PlanetScript.roll_params(int(def["type"]), rng)
		params["radius"] = float(def["radius"])
		p.apply(params)
		p.set_orbit(_anchor, float(def["orbit"]), float(def["speed"]) * GLOBAL_ORBIT_MULT, rng.randf() * TAU)
		_add_moons(p, float(def["radius"]), int(def["moons"]), rng)

	_belt = Node2D.new()
	add_child(_belt)
	for i in BELT_COUNT:
		var a := AsteroidScript.new()
		_belt.add_child(a)
		a.setup(rng)   # draws once
		var ang := rng.randf() * TAU
		var rad := BELT_RADIUS + rng.randf_range(-0.5, 0.5) * BELT_WIDTH
		a.position = Vector2(cos(ang), sin(ang)) * rad
		a.set_process(false)   # stop per-frame tumble/redraw — the whole belt revolves as one (perf); distant
		                       # + blurred, so the lost per-rock spin is imperceptible

func _make_sun() -> Sprite2D:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	var s := Sprite2D.new()
	s.texture = _white_tex
	s.centered = true
	s.z_index = SUN_Z
	s.scale = Vector2.ONE * (SUN_RADIUS * 2.0 / float(_white_tex.get_width()))
	var m := ShaderMaterial.new()
	m.shader = load(SUN_SHADER)
	m.set_shader_parameter("seed", float(SYSTEM_SEED % 1000))
	s.material = m
	return s

func _add_moons(planet: Node2D, planet_radius: float, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var mtype: int = MOON_TYPES[rng.randi() % MOON_TYPES.size()]
		var mp := PlanetScript.roll_params(mtype, rng)
		mp["radius"] = planet_radius * rng.randf_range(MOON_SIZE_RATIO.x, MOON_SIZE_RATIO.y)
		var moon := PlanetScript.new()
		add_child(moon)
		moon.apply(mp)
		# Centre-to-centre orbit = planet radius + surface gap + the moon's own radius.
		var gap: float = planet_radius * rng.randf_range(MOON_SURFACE_GAP.x, MOON_SURFACE_GAP.y)
		var orbit_r: float = planet_radius + gap + float(mp["radius"])
		var spd: float = rng.randf_range(MOON_SPEED.x, MOON_SPEED.y) * (1.0 if rng.randf() < 0.5 else -1.0)
		moon.set_orbit(planet, orbit_r, spd, rng.randf() * TAU)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	position = cam.global_position * (1.0 - LAYER_FACTOR)
	# Keep the sharp sun lined up with this layer's local origin (main-viewport world space).
	if _sun != null and is_instance_valid(_sun):
		_sun.position = cam.global_position * (1.0 - LAYER_FACTOR)
	if _belt != null:
		_belt.rotation += BELT_ORBIT_SPEED * GLOBAL_ORBIT_MULT * delta
