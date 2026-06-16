extends SceneTree
## Render warped dens with gradient vs simplex noise across many offsets to catch the facets.
var _f := 0
var _vps: Array = []
var _offsets := [120.0, 333.0, 777.0, 1009.0, 1500.0, 1900.0]

func _add(shader: Shader, off: float, simplex: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(560, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cr := ColorRect.new()
	cr.size = Vector2(560, 360)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("world_offset", Vector2(off, off))
	mat.set_shader_parameter("use_simplex", simplex)
	cr.material = mat
	vp.add_child(cr)
	root.add_child(vp)
	_vps.append([vp, off, simplex])

func _initialize() -> void:
	var shader: Shader = load("res://tools/noise_cmp.gdshader")
	for off in _offsets:
		_add(shader, off, 0)
		_add(shader, off, 1)

func _process(_d: float) -> bool:
	_f += 1
	if _f < 6:
		return false
	for e in _vps:
		var tag := "simplex" if int(e[2]) == 1 else "gnoise"
		(e[0] as SubViewport).get_texture().get_image().save_png("res://_cmp_%d_%s.png" % [int(e[1]), tag])
		print("[cmp] _cmp_%d_%s.png" % [int(e[1]), tag])
	return true
