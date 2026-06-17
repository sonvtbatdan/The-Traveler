extends Sprite2D
class_name ArenaStructure
## A single enormous gas/dust structure — a quad (this Sprite2D + a flat white texture so the shader's UV
## spans 0..1) running one of four structure shaders. Mirrors arena_planet.gd: roll_params() (RNG-seeded,
## per type) → make_material() → apply() sizes the quad. Four types, each with its own .gdshader:
##   0 planetary nebula (ring/eye) · 1 reflection nebula · 2 dark nebula · 3 emission pillars.

const SHADERS := ["res://assets/shaders/structure_planetary_nebula.gdshader",
	"res://assets/shaders/structure_reflection_nebula.gdshader",
	"res://assets/shaders/structure_dark_nebula.gdshader",
	"res://assets/shaders/structure_emission_pillars.gdshader"]
const TYPE_NAMES := ["planetary_nebula", "reflection_nebula", "dark_nebula", "emission_pillars"]

# Per-type drawn half-size (px). These are huge set-pieces.
const SIZE_RANGE := {
	0: Vector2(400, 700), 1: Vector2(350, 650), 2: Vector2(450, 800), 3: Vector2(400, 750),
}

static var _white_tex: Texture2D = null
static var _shaders: Array = [null, null, null, null]

## Roll a unique structure of `type` (0..3) using `rng` (deterministic if seeded).
static func roll_params(type: int, rng: RandomNumberGenerator) -> Dictionary:
	var sr: Vector2 = SIZE_RANGE.get(type, Vector2(400, 700))
	var p := {
		"type": type,
		"radius": rng.randf_range(sr.x, sr.y),
		"seed": rng.randf() * 100.0,
	}
	match type:
		0:   # planetary nebula (ring / eye)
			p["look"] = 1.0 if rng.randf() < 0.45 else 0.0
			p["shell_radius"] = rng.randf_range(0.52, 0.72)
			p["shell_thickness"] = rng.randf_range(0.10, 0.20)
			# Inner hot (teal/green/blue) → outer cool (red/orange), with hue variation.
			var ih := rng.randf()
			p["inner_color"] = Color(0.15, 0.95, 0.80).lerp(Color(0.25, 0.70, 1.0), ih)
			p["outer_color"] = Color(0.95, 0.35, 0.15).lerp(Color(0.85, 0.20, 0.45), rng.randf())
			p["star_brightness"] = rng.randf_range(1.2, 2.2)
			p["turbulence"] = rng.randf_range(0.14, 0.30)
			p["halo_strength"] = rng.randf_range(0.15, 0.35)
		1:   # reflection nebula
			p["star_brightness"] = rng.randf_range(1.8, 2.8)
			p["star_offset"] = Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
			p["cloud_size"] = rng.randf_range(0.55, 0.9)
			var bt := rng.randf()
			p["tint_color"] = Color(0.30, 0.50, 1.0).lerp(Color(0.45, 0.65, 1.0), bt)
			p["falloff_rate"] = rng.randf_range(1.8, 3.2)
			p["turbulence"] = rng.randf_range(0.35, 0.7)
		2:   # dark nebula
			p["darkness"] = rng.randf_range(0.78, 0.95)
			p["max_opacity"] = rng.randf_range(0.88, 0.98)
			p["size"] = rng.randf_range(0.7, 0.95)
			p["edge_softness"] = rng.randf_range(0.4, 0.7)
			var dh := rng.randf()
			p["brown_tint"] = Color(0.18, 0.10, 0.06).lerp(Color(0.12, 0.08, 0.07), dh)
			p["fg_star_count"] = rng.randf_range(0.06, 0.16)
			p["rim_color"] = Color(0.45, 0.22, 0.10)
			p["rim_strength"] = rng.randf_range(0.2, 0.4)
		3:   # emission pillars
			p["column_count"] = float(rng.randi_range(2, 4))
			p["column_width"] = rng.randf_range(0.3, 0.6)
			p["column_height"] = rng.randf_range(0.7, 0.92)
			p["erosion"] = rng.randf_range(0.5, 1.0)
			p["backlight_dir"] = Vector2(rng.randf_range(-0.4, 0.4), -1.0).normalized()
			var bh := rng.randf()
			p["backlight_color"] = Color(0.5, 0.65, 1.0).lerp(Color(0.7, 0.8, 1.0), bh)
			p["rim_brightness"] = rng.randf_range(0.8, 1.3)
			var gh := rng.randf()
			p["gas_color"] = Color(0.45, 0.28, 0.14).lerp(Color(0.5, 0.34, 0.12), gh)
			p["baby_stars"] = rng.randf_range(0.25, 0.5)
	return p

## Build a configured structure ShaderMaterial from a params dict.
static func make_material(p: Dictionary) -> ShaderMaterial:
	var type := int(p.get("type", 0))
	if _shaders[type] == null:
		_shaders[type] = load(SHADERS[type])
	var m := ShaderMaterial.new()
	m.shader = _shaders[type]
	m.set_shader_parameter("seed", float(p.get("seed", 0.0)))
	for key: String in ["look", "shell_radius", "shell_thickness", "inner_color", "outer_color",
			"star_brightness", "turbulence", "halo_strength",
			"star_offset", "cloud_size", "tint_color", "falloff_rate",
			"darkness", "max_opacity", "size", "edge_softness", "brown_tint", "fg_star_count",
			"rim_color", "rim_strength",
			"column_count", "column_width", "column_height", "erosion", "backlight_dir",
			"backlight_color", "rim_brightness", "gas_color", "baby_stars"]:
		if p.has(key):
			m.set_shader_parameter(key, p[key])
	return m

func _ready() -> void:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	texture = _white_tex
	centered = true

## Apply a params dict (from roll_params) to the shader + size. Call AFTER add_child.
func apply(p: Dictionary) -> void:
	if _white_tex == null:
		var wimg := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		wimg.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(wimg)
	texture = _white_tex
	centered = true
	material = make_material(p)
	var type := int(p.get("type", 0))
	var radius := float(p.get("radius", 500.0))
	var tw := float(_white_tex.get_width())
	if type == 3:   # pillars: taller-than-wide quad
		scale = Vector2(radius * 1.6, radius * 2.4) / tw
	else:
		scale = Vector2.ONE * (radius * 2.0 / tw)

## Free this structure (used by the streamer cull + debug clears).
func despawn() -> void:
	queue_free()
