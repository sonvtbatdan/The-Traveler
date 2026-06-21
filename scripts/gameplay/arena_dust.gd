extends CanvasLayer
## Dark space-dust field. A screen-filling shader paints sparse dust motes that live in WORLD space and
## are INVISIBLE until lit by a light source. Each frame this gathers the active lights — the ship plus the
## weapons' projectiles/beams (via arena_weapons.get_lights()) — and feeds them to the shader. A weapon's
## "light value" (Gatling = 1, small) is converted to a reach radius here.

const SHADER := "res://assets/shaders/dust.gdshader"
const MAX_LIGHTS := 48

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const DUST_CANVAS_LAYER := -5      # above the nebula (-10), behind the world (0) — dust glows behind ships
const DUST_DENSITY  := 0.12        # fraction of cells with a mote (higher = denser dust)
const DUST_CELL     := 50.0        # world px per dust cell (bigger = sparser)
const MOTE_SIZE     := 2.6         # mote radius (px)
const DUST_COLOR    := Color(0.62, 0.70, 0.95)
const LIGHT_RADIUS_UNIT := 70.0    # a light "value" of 1 → this reach in px (Gatling=1 → 70px, small)
# The ship itself is a soft light so it reveals dust around it.
const SHIP_LIGHT_VALUE  := 2.0
const SHIP_LIGHT_COLOR  := Color(0.80, 0.86, 1.0)

var _rect: ColorRect = null
var _player: Node2D = null
var _weapons: Node = null

func _ready() -> void:
	layer = DUST_CANVAS_LAYER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter("dust_density", DUST_DENSITY)
	mat.set_shader_parameter("dust_cell", DUST_CELL)
	mat.set_shader_parameter("mote_size", MOTE_SIZE)
	mat.set_shader_parameter("dust_color", DUST_COLOR)
	_rect.material = mat
	add_child(_rect)
	get_viewport().size_changed.connect(_resize)
	call_deferred("_resize")
	_player = get_tree().get_first_node_in_group("player")
	_weapons = get_tree().get_first_node_in_group("arena_weapons")

func _resize() -> void:
	if _rect != null:
		_rect.position = Vector2.ZERO
		_rect.size = get_viewport().get_visible_rect().size

func _process(_delta: float) -> void:
	if _rect == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var mat := _rect.material as ShaderMaterial
	var vp := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("cam_world", cam.global_position)
	mat.set_shader_parameter("view_size", Vector2(vp.x / maxf(0.01, cam.zoom.x), vp.y / maxf(0.01, cam.zoom.y)))

	# ── Gather lights (capped at MAX_LIGHTS, padded so the uniform arrays stay fixed-size). ──
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	var inten := PackedFloat32Array()
	var col := PackedVector3Array()

	if _player != null and is_instance_valid(_player):
		_add_light(pos, rad, inten, col, _player.global_position, SHIP_LIGHT_VALUE, SHIP_LIGHT_COLOR)

	if _weapons == null or not is_instance_valid(_weapons):
		_weapons = get_tree().get_first_node_in_group("arena_weapons")
	if _weapons != null and _weapons.has_method("get_lights"):
		for l: Dictionary in _weapons.get_lights():
			if pos.size() >= MAX_LIGHTS:
				break
			_add_light(pos, rad, inten, col, l["pos"], float(l["value"]), l["color"])

	var n := pos.size()
	pos.resize(MAX_LIGHTS); rad.resize(MAX_LIGHTS); inten.resize(MAX_LIGHTS); col.resize(MAX_LIGHTS)
	mat.set_shader_parameter("light_count", n)
	mat.set_shader_parameter("light_pos", pos)
	mat.set_shader_parameter("light_radius", rad)
	mat.set_shader_parameter("light_intensity", inten)
	mat.set_shader_parameter("light_color", col)

func _add_light(pos: PackedVector2Array, rad: PackedFloat32Array, inten: PackedFloat32Array,
		col: PackedVector3Array, p: Vector2, value: float, c: Color) -> void:
	pos.append(p)
	rad.append(value * LIGHT_RADIUS_UNIT)
	inten.append(value)
	col.append(Vector3(c.r, c.g, c.b))
