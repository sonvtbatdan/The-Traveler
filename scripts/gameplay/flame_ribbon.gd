extends Node2D
class_name FlameRibbon
## Textured flame ribbon — builds a triangle-strip ArrayMesh along a centerline path and renders it with
## flame_ribbon.gdshader (scrolling dual-layer flame + flicker). Optional head-burst Sprite2D at the path
## end (oriented to the tangent) and optional CPUParticles2D embers. Reusable: call build_path(points,
## width) once for a static beam, or every frame for a growing arc (the ring). All tunables are grouped
## at the top and pushed to the shader in _ready / via push_uniforms().

const SHADER_PATH := "res://scripts/gameplay/flame_ribbon.gdshader"
const BODY_TEX    := "res://assets/bosses/elephant/flame_body_tile.png"
const HEAD_TEX    := "res://assets/bosses/elephant/flame_head.png"

# ── TUNABLES ─────────────────────────────────────────────────────────────────────
@export var beam_width        := 90.0    # ribbon width (px)
@export var tile_world_length := 150.0   # world px per texture tile → stable tiling as the path grows
@export var tile_mult         := 1.0     # manual extra tiling multiplier (UV.x already = arclen/tile_world_length)
@export var scroll_speed      := 0.6
@export var scroll_speed_2    := 0.9
@export var layer2_scale      := 2.0
@export var layer_mix         := 0.4
@export var flicker_speed     := 10.0
@export var flicker_amount    := 0.12
@export var edge_falloff      := 0.12
@export var head_enabled      := true
@export var head_size         := 150.0   # head-burst height in world px
@export var head_offset       := 0.0     # push the head along the tangent (px)
@export var tint_color        := Color(1, 1, 1, 1)
@export var intensity         := 1.0
@export var ember_enabled     := false
@export var ember_rate        := 24.0

var _mi: MeshInstance2D = null
var _mat: ShaderMaterial = null
var _head: Sprite2D = null
var _embers: CPUParticles2D = null
var _t := 0.0
var _path_len := 0.0

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("flame_tex", load(BODY_TEX))
	push_uniforms()
	_mi = MeshInstance2D.new()
	_mi.material = _mat
	add_child(_mi)
	if head_enabled:
		_head = Sprite2D.new()
		_head.texture = load(HEAD_TEX)
		_head.visible = false
		add_child(_head)
	if ember_enabled:
		_build_embers()

## Re-push design tunables to the shader (call after tweaking @export values at runtime).
func push_uniforms() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("scroll_speed", scroll_speed)
	_mat.set_shader_parameter("scroll_speed_2", scroll_speed_2)
	_mat.set_shader_parameter("layer2_scale", layer2_scale)
	_mat.set_shader_parameter("layer_mix", layer_mix)
	_mat.set_shader_parameter("flicker_speed", flicker_speed)
	_mat.set_shader_parameter("flicker_amount", flicker_amount)
	_mat.set_shader_parameter("edge_falloff", edge_falloff)
	_mat.set_shader_parameter("tint_color", tint_color)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("tile_count", tile_mult)

## Build the ribbon mesh along `points` (local space) with the given width. Safe to call every frame.
func build_path(points: PackedVector2Array, width: float) -> void:
	var n := points.size()
	if n < 2:
		if _mi != null:
			_mi.mesh = null
		if _head != null:
			_head.visible = false
		return
	var hw := width * 0.5
	var lft := PackedVector2Array(); lft.resize(n)
	var rgt := PackedVector2Array(); rgt.resize(n)
	var us := PackedFloat32Array(); us.resize(n)
	var clen := 0.0
	for i in n:
		var d: Vector2
		if i == 0:
			d = points[1] - points[0]
		elif i == n - 1:
			d = points[n - 1] - points[n - 2]
		else:
			d = points[i + 1] - points[i - 1]
		d = d.normalized() if d.length() > 0.0001 else Vector2.RIGHT
		var nm := Vector2(-d.y, d.x)   # perpendicular
		if i > 0:
			clen += points[i].distance_to(points[i - 1])
		lft[i] = points[i] + nm * hw
		rgt[i] = points[i] - nm * hw
		us[i] = clen / maxf(1.0, tile_world_length)
	_path_len = clen
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in n - 1:
		verts.append(lft[i]);     uvs.append(Vector2(us[i], 0.0))
		verts.append(rgt[i]);     uvs.append(Vector2(us[i], 1.0))
		verts.append(rgt[i + 1]); uvs.append(Vector2(us[i + 1], 1.0))
		verts.append(lft[i]);     uvs.append(Vector2(us[i], 0.0))
		verts.append(rgt[i + 1]); uvs.append(Vector2(us[i + 1], 1.0))
		verts.append(lft[i + 1]); uvs.append(Vector2(us[i + 1], 0.0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _mi != null:
		_mi.mesh = mesh
	if _head != null and _head.texture != null:
		_head.visible = true
		var endp := points[n - 1]
		var tdir := (points[n - 1] - points[n - 2]).normalized()
		_head.position = endp + tdir * head_offset
		_head.rotation = tdir.angle()
		var hs := head_size / maxf(1.0, float(_head.texture.get_height()))
		_head.scale = Vector2(hs, hs)
	if _embers != null:
		_set_ember_points(points)

## Show/hide just the head-burst sprite (e.g. park vs fade at the ring closure).
func set_head_visible(v: bool) -> void:
	if _head != null:
		_head.visible = v and _head.texture != null

func _process(delta: float) -> void:
	_t += delta
	if _head != null:
		var fl := 1.0 + flicker_amount * sin(_t * flicker_speed)
		_head.modulate = Color(tint_color.r * intensity * fl, tint_color.g * intensity * fl, tint_color.b * intensity * fl, tint_color.a)

func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.amount = int(maxf(1.0, ember_rate))
	_embers.lifetime = 0.8
	_embers.local_coords = false
	_embers.direction = Vector2(0, -1)
	_embers.spread = 25.0
	_embers.gravity = Vector2(0, -50)   # drift slightly upward
	_embers.initial_velocity_min = 20.0
	_embers.initial_velocity_max = 70.0
	_embers.scale_amount_min = 1.0
	_embers.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.2, 1.0))
	ramp.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	_embers.color_ramp = ramp
	_embers.emitting = false
	add_child(_embers)

func _set_ember_points(points: PackedVector2Array) -> void:
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var pts := PackedVector2Array()
	var step := maxi(1, int(points.size() / 12))
	for i in range(0, points.size(), step):
		pts.append(points[i])
	_embers.emission_points = pts
	_embers.emitting = pts.size() > 0
