extends Sprite2D
## A single procedural planet — a quad (this Sprite2D + a flat white texture so the shader's UV spans 0..1)
## running planet.gdshader. Configure it with a params Dictionary (rolled within a type so each planet is
## unique): type, radius, palette, light_dir, rotation_speed, atmo. The streamer and the F6 menu both build
## params via roll_params() so a dragged planet matches its preview thumbnail.

const SHADER := "res://assets/shaders/planet.gdshader"
const TYPE_NAMES := ["rocky", "gas", "ice", "earth", "lava", "desert", "ringed",
	"ocean", "toxic", "jungle", "barren", "carbon"]

# Per-type size ranges (drawn radius px).
const SIZE_RANGE := {
	0: Vector2(40, 95), 1: Vector2(80, 160), 2: Vector2(40, 95),
	3: Vector2(50, 100), 4: Vector2(45, 95), 5: Vector2(45, 95), 6: Vector2(80, 150),
	7: Vector2(50, 100), 8: Vector2(60, 120), 9: Vector2(50, 100), 10: Vector2(40, 90), 11: Vector2(40, 90),
}

static var _white_tex: Texture2D = null
static var _shader: Shader = null

# Optional moon orbit: when orbit_parent is set, this planet (a moon) revolves around it each frame.
var orbit_parent: Node2D = null
var orbit_radius: float = 0.0
var orbit_speed: float = 0.0      # radians/sec
var orbit_angle: float = 0.0
var _moons: Array = []            # child moons spawned alongside this planet (freed together)

## Roll a unique planet of `type` (0 rocky / 1 gas / 2 ice) using `rng` (deterministic if seeded).
static func roll_params(type: int, rng: RandomNumberGenerator) -> Dictionary:
	var sr: Vector2 = SIZE_RANGE.get(type, Vector2(50, 100))
	# Light direction on the camera-facing hemisphere.
	var ld := Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7), rng.randf_range(0.4, 0.9)).normalized()
	var p := {
		"type": type,
		"radius": rng.randf_range(sr.x, sr.y),
		"seed": rng.randf() * 100.0,
		"light_dir": ld,
		"rotation_speed": rng.randf_range(0.02, 0.07) * (1.0 if rng.randf() < 0.5 else -1.0),
		"terminator_softness": rng.randf_range(0.25, 0.45),
	}
	match type:
		0:   # rocky
			var g := rng.randf_range(0.32, 0.5)
			p["base_color"] = Color(g + rng.randf_range(0.0, 0.12), g, g - rng.randf_range(0.0, 0.08))
			p["base_color2"] = Color(g * 0.6, g * 0.58, g * 0.5)
			p["crater_density"] = rng.randf_range(0.3, 0.85)
			p["crater_depth"] = rng.randf_range(0.45, 0.7)
			p["crater_rim"] = rng.randf_range(0.24, 0.40)
			p["maria_coverage"] = rng.randf_range(0.35, 0.55)
			p["maria_darkness"] = rng.randf_range(0.40, 0.62)
			p["crater_rays"] = rng.randf_range(0.45, 0.8)
			p["crater_ray_rarity"] = rng.randf_range(0.10, 0.22)
			p["crater_ray_soft"] = rng.randf_range(2.5, 3.5)
			p["surface_contrast"] = rng.randf_range(1.15, 1.45)
			p["atmo_color"] = Color(0.55, 0.55, 0.6)
			p["atmo_strength"] = rng.randf_range(0.1, 0.3)
		1:   # gas giant
			var hue := rng.randf_range(0.0, 1.0)
			p["band_a"] = Color(0.85, 0.78, 0.62).lerp(Color(0.8, 0.85, 0.78), hue)
			p["band_b"] = Color(0.74, 0.50, 0.30).lerp(Color(0.55, 0.62, 0.78), hue)
			p["band_c"] = Color(0.55, 0.33, 0.20).lerp(Color(0.35, 0.42, 0.62), hue)
			p["storm_on"] = 1.0 if rng.randf() < 0.6 else 0.0
			p["band_count"] = rng.randf_range(10.0, 16.0)
			p["turbulence"] = rng.randf_range(0.4, 0.7)
			p["atmo_color"] = Color(0.95, 0.65, 0.35).lerp(Color(0.5, 0.7, 1.0), hue)
			p["atmo_strength"] = rng.randf_range(0.5, 0.85)
		2:   # ice
			p["ice_color"] = Color(0.86, 0.92, 1.0)
			p["ice_tint"] = Color(0.5, 0.72, 0.95).lerp(Color(0.7, 0.85, 0.95), rng.randf())
			p["crack_intensity"] = rng.randf_range(0.4, 0.85)
			p["atmo_color"] = Color(0.6, 0.8, 1.0)
			p["atmo_strength"] = rng.randf_range(0.4, 0.7)
		3:   # Earth-like
			p["land_threshold"] = rng.randf_range(0.48, 0.58)
			p["ocean_color"] = Color(0.04, 0.18, 0.42).lerp(Color(0.06, 0.26, 0.52), rng.randf())
			p["land_lo"] = Color(0.13, 0.42, 0.16).lerp(Color(0.20, 0.46, 0.22), rng.randf())
			p["land_hi"] = Color(0.45, 0.38, 0.22)
			p["cloud_amount"] = rng.randf_range(0.35, 0.6)
			p["cloud_speed"] = rng.randf_range(0.025, 0.05) * (1.0 if rng.randf() < 0.5 else -1.0)
			p["ice_cap_size"] = rng.randf_range(0.12, 0.22)
			p["atmo_color"] = Color(0.35, 0.6, 1.0)
			p["atmo_strength"] = rng.randf_range(0.55, 0.85)
		4:   # lava
			p["crust_color"] = Color(0.07, 0.06, 0.06).lerp(Color(0.13, 0.08, 0.07), rng.randf())
			p["crack_density"] = rng.randf_range(0.4, 0.8)
			p["crack_threshold"] = rng.randf_range(0.5, 0.62)
			p["vein_width"] = rng.randf_range(0.14, 0.26)
			p["glow_lo"] = Color(0.5, 0.05, 0.0)
			p["glow_mid"] = Color(1.0, 0.35, 0.0)
			p["glow_hi"] = Color(1.0, 0.9, 0.35)
			p["glow_intensity"] = rng.randf_range(1.2, 2.1)
			p["atmo_color"] = Color(0.9, 0.25, 0.1)
			p["atmo_strength"] = rng.randf_range(0.3, 0.55)
		5:   # desert / Mars
			var dt := rng.randf()
			p["desert_lo"] = Color(0.5, 0.26, 0.14).lerp(Color(0.6, 0.38, 0.22), dt)
			p["desert_hi"] = Color(0.78, 0.55, 0.34).lerp(Color(0.85, 0.66, 0.45), dt)
			p["canyon_intensity"] = rng.randf_range(0.3, 0.7)
			p["cap_size"] = rng.randf_range(0.05, 0.1)
			p["dust_amount"] = rng.randf_range(0.1, 0.3)
			p["atmo_color"] = Color(0.85, 0.55, 0.3)
			p["atmo_strength"] = rng.randf_range(0.25, 0.45)
		6:   # ringed gas giant — gas surface + a tilted ring
			var hue := rng.randf()
			p["band_a"] = Color(0.85, 0.78, 0.62).lerp(Color(0.8, 0.85, 0.78), hue)
			p["band_b"] = Color(0.74, 0.50, 0.30).lerp(Color(0.55, 0.62, 0.78), hue)
			p["band_c"] = Color(0.55, 0.33, 0.20).lerp(Color(0.35, 0.42, 0.62), hue)
			p["storm_on"] = 1.0 if rng.randf() < 0.5 else 0.0
			p["atmo_color"] = Color(0.95, 0.65, 0.35).lerp(Color(0.5, 0.7, 1.0), hue)
			p["atmo_strength"] = rng.randf_range(0.5, 0.8)
			p["disc_frac"] = 0.42   # sphere fills 42% of the quad → ring has room (quad ≈ 2.4× the planet)
			p["ring_inner"] = rng.randf_range(0.52, 0.60)
			p["ring_outer"] = rng.randf_range(0.85, 0.94)
			p["ring_angle"] = rng.randf_range(-0.6, 0.6)
			p["ring_squash"] = rng.randf_range(0.25, 0.45)
			p["ring_color"] = Color(0.82, 0.76, 0.62).lerp(Color(0.70, 0.72, 0.80), rng.randf())
			p["gap_pos"] = rng.randf_range(0.68, 0.78)
			p["gap_width"] = rng.randf_range(0.03, 0.06)
		7:   # ocean / water world (earth-like, high threshold -> mostly ocean)
			p["land_threshold"] = rng.randf_range(0.70, 0.80)   # high -> only tiny scattered islands
			p["ocean_color"] = Color(0.02, 0.13, 0.40).lerp(Color(0.03, 0.34, 0.46), rng.randf())  # deep blue -> teal
			p["land_lo"] = Color(0.20, 0.42, 0.22)
			p["land_hi"] = Color(0.52, 0.48, 0.32)
			p["cloud_amount"] = rng.randf_range(0.55, 0.85)     # heavier storm cloud cover
			p["cloud_speed"] = rng.randf_range(0.03, 0.06) * (1.0 if rng.randf() < 0.5 else -1.0)
			p["cloud_storm"] = rng.randf_range(0.8, 1.6)        # spiral storm swirl
			p["ice_cap_size"] = rng.randf_range(0.08, 0.16)
			p["atmo_color"] = Color(0.3, 0.55, 1.0)
			p["atmo_strength"] = rng.randf_range(0.6, 0.9)
		8:   # toxic / Venus-like (gas-giant haze, no bands)
			var tt := rng.randf()
			p["band_a"] = Color(0.78, 0.74, 0.30).lerp(Color(0.72, 0.55, 0.20), tt)  # yellow-green -> ochre
			p["band_b"] = Color(0.64, 0.62, 0.24).lerp(Color(0.58, 0.44, 0.16), tt)
			p["turbulence"] = rng.randf_range(0.8, 1.4)
			p["atmo_color"] = Color(0.7, 0.8, 0.3)
			p["atmo_strength"] = rng.randf_range(0.4, 0.7)
		9:   # jungle / verdant (earth-like, low threshold -> mostly land)
			p["land_threshold"] = rng.randf_range(0.30, 0.40)   # low -> minimal ocean
			p["ocean_color"] = Color(0.06, 0.22, 0.30).lerp(Color(0.08, 0.28, 0.24), rng.randf())
			var gt := rng.randf()
			p["land_lo"] = Color(0.06, 0.26, 0.10).lerp(Color(0.10, 0.34, 0.12), gt)  # deep jungle green
			p["land_hi"] = Color(0.30, 0.46, 0.16).lerp(Color(0.40, 0.40, 0.20), gt)  # lighter green / brown
			p["cloud_amount"] = rng.randf_range(0.20, 0.40)     # thin wispy clouds
			p["cloud_speed"] = rng.randf_range(0.02, 0.045) * (1.0 if rng.randf() < 0.5 else -1.0)
			p["cloud_storm"] = rng.randf_range(0.0, 0.2)
			p["ice_cap_size"] = rng.randf_range(0.05, 0.12)
			p["atmo_color"] = Color(0.4, 0.8, 0.4)
			p["atmo_strength"] = rng.randf_range(0.4, 0.7)
		10:  # barren dead rock (no craters / water / rust)
			var bg := rng.randf_range(0.28, 0.42)
			p["base_color"] = Color(bg + 0.05, bg, bg - 0.03)        # muted grey-brown
			p["base_color2"] = Color(bg * 0.6, bg * 0.58, bg * 0.52)
			p["terrain_roughness"] = rng.randf_range(0.3, 0.8)
			p["atmo_color"] = Color(0.5, 0.5, 0.5)
			p["atmo_strength"] = rng.randf_range(0.0, 0.12)          # faint / none
		11:  # carbon / obsidian (dark with subtle sheen)
			var dk := rng.randf_range(0.04, 0.10)
			p["carbon_lo"] = Color(dk, dk, dk + 0.02)
			p["carbon_hi"] = Color(dk * 2.0, dk * 2.0, dk * 2.2 + 0.03)
			var st := rng.randf()
			p["sheen_color"] = Color(0.55, 0.58, 0.65).lerp(Color(0.35, 0.45, 0.78), st)  # metallic grey -> bluish
			p["sheen_strength"] = rng.randf_range(0.3, 0.7)
			p["atmo_color"] = Color(0.4, 0.5, 0.7)
			p["atmo_strength"] = rng.randf_range(0.05, 0.2)
	return p

## Build a configured planet ShaderMaterial from a params dict (used by the node AND the F6 menu previews).
static func make_material(p: Dictionary) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("planet_type", int(p.get("type", 0)))
	m.set_shader_parameter("seed", float(p.get("seed", 0.0)))
	m.set_shader_parameter("light_dir", p.get("light_dir", Vector3(0.6, -0.5, 0.6)))
	m.set_shader_parameter("rotation_speed", float(p.get("rotation_speed", 0.05)))
	m.set_shader_parameter("terminator_softness", float(p.get("terminator_softness", 0.35)))
	m.set_shader_parameter("atmo_color", p.get("atmo_color", Color(0.6, 0.7, 1.0)))
	m.set_shader_parameter("atmo_strength", float(p.get("atmo_strength", 0.5)))
	m.set_shader_parameter("planet_radius", float(p.get("disc_frac", 1.0)))
	for key: String in ["base_color", "base_color2", "crater_density", "band_a", "band_b", "band_c",
			"storm_on", "ice_color", "ice_tint", "crack_intensity",
			"land_threshold", "ocean_color", "land_lo", "land_hi", "cloud_amount", "cloud_speed", "ice_cap_size",
			"crack_density", "crack_threshold", "vein_width", "glow_lo", "glow_mid", "glow_hi", "glow_intensity", "crust_color",
			"desert_lo", "desert_hi", "canyon_intensity", "cap_size", "dust_amount",
			"crater_depth", "crater_rim", "maria_coverage", "maria_darkness", "crater_rays",
			"crater_ray_rarity", "crater_ray_soft", "surface_contrast",
			"band_count", "turbulence",
			"cloud_storm", "terrain_roughness", "carbon_lo", "carbon_hi", "sheen_color", "sheen_strength",
			"ring_inner", "ring_outer", "ring_angle", "ring_squash", "ring_color", "gap_pos", "gap_width"]:
		if p.has(key):
			m.set_shader_parameter(key, p[key])
	return m

func _ready() -> void:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	if _shader == null:
		_shader = load(SHADER)
	texture = _white_tex
	centered = true
	if material == null:
		var m := ShaderMaterial.new()
		m.shader = _shader
		material = m

## Apply a params dict (from roll_params) to the shader + size. Call AFTER add_child.
func apply(p: Dictionary) -> void:
	if _white_tex == null:
		var wimg := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		wimg.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(wimg)
	texture = _white_tex
	centered = true
	material = make_material(p)
	var radius := float(p.get("radius", 60.0))
	# disc_frac < 1 (ringed) → the sphere fills only part of the quad, so the quad must be bigger.
	var disc := maxf(0.05, float(p.get("disc_frac", 1.0)))
	scale = Vector2.ONE * (radius * 2.0 / disc / float(_white_tex.get_width()))

## A moon orbiting `parent` revolves around it each frame (polar position). Call after add_child + apply.
func set_orbit(parent: Node2D, radius_px: float, speed: float, start_angle: float) -> void:
	orbit_parent = parent
	orbit_radius = radius_px
	orbit_speed = speed
	orbit_angle = start_angle

func _process(delta: float) -> void:
	if orbit_parent == null:
		return
	if not is_instance_valid(orbit_parent):
		queue_free()   # parent gone → the moon goes with it
		return
	orbit_angle += orbit_speed * delta
	position = orbit_parent.position + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius

## Free this planet and any moons attached to it (used by the streamer cull + clears).
func despawn() -> void:
	for m in _moons:
		if is_instance_valid(m):
			m.queue_free()
	_moons.clear()
	queue_free()
