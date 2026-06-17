extends Node
## Depth-of-field for the arena background. Hosts a downscaled SubViewport whose Camera2D is synced to the
## main camera every frame; arena.gd parents all NON-gameplay layers (nebula, dust, stars, planets, comets,
## structures, asteroids) into it via background_parent(). Their parallax + deterministic streaming are
## unchanged because, inside the SubViewport, get_viewport().get_camera_2d() returns the synced camera. The
## SubViewport's texture is then composited full-screen BEHIND the gameplay plane through dof_blur.gdshader
## (gaussian blur + dim + desaturate). Gameplay (player/enemies/projectiles/weapons) and the UI stay in the
## main viewport — sharp + full-brightness.

const BLUR_SHADER := "res://assets/shaders/dof_blur.gdshader"

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const ENABLED       := true    # blur/dim/desaturate the background (everything except the excluded nebula)
const DOWNSCALE     := 3.0     # background render res = viewport / this (higher = blurrier + cheaper; 3 = 1/9 the pixels)
const BLUR_RADIUS   := 1.6     # extra gaussian blur on top of the downscale (source texels)
const DIM           := 0.62    # global background brightness multiply (<1 = darker)
const DESATURATION  := 0.55    # 0 = full colour, 1 = greyscale
const COMPOSITE_LAYER := -5    # CanvasLayer for the composite: behind gameplay (default layer 0), but IN
                              # FRONT of the excluded sharp nebula (CL -10) so the nebula stays the backdrop
# Per-layer depth dim (applied to the world Node2D layers by arena.gd): far recedes more than mid.
const FAR_MODULATE  := Color(0.55, 0.56, 0.62)   # stars + structures (deepest)
const MID_MODULATE  := Color(0.82, 0.83, 0.88)   # planets + comets + asteroids

var _dof_vp: SubViewport = null
var _dof_cam: Camera2D = null
var _composite_layer: CanvasLayer = null
var _composite: TextureRect = null

func _ready() -> void:
	if not ENABLED:
		return   # mask off → arena.gd parents the background into the main viewport instead (see background_parent)
	_dof_vp = SubViewport.new()
	_dof_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_dof_vp.disable_3d = true
	_dof_vp.transparent_bg = true
	_dof_vp.gui_disable_input = true
	add_child(_dof_vp)

	_dof_cam = Camera2D.new()
	_dof_cam.enabled = true
	_dof_vp.add_child(_dof_cam)
	_dof_cam.make_current()   # current within the SubViewport only (independent of the main camera)

	_composite_layer = CanvasLayer.new()
	_composite_layer.layer = COMPOSITE_LAYER
	add_child(_composite_layer)

	_composite = TextureRect.new()
	_composite.texture = _dof_vp.get_texture()
	_composite.set_anchors_preset(Control.PRESET_FULL_RECT)
	_composite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # smooth upscale of the downscaled texture
	_composite.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = load(BLUR_SHADER)
	mat.set_shader_parameter("blur_radius", BLUR_RADIUS)
	mat.set_shader_parameter("dim", DIM)
	mat.set_shader_parameter("desaturation", DESATURATION)
	_composite.material = mat
	_composite_layer.add_child(_composite)

	get_viewport().size_changed.connect(_resize)
	call_deferred("_resize")

## Where background layers should be parented: the DoF SubViewport when enabled, else the arena itself
## (main viewport) so they render normally with no blur/dim.
func background_parent() -> Node:
	if not ENABLED or _dof_vp == null:
		return get_parent()
	return _dof_vp

func _resize() -> void:
	if _dof_vp == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_dof_vp.size = Vector2i(maxi(1, int(vp.x / DOWNSCALE)), maxi(1, int(vp.y / DOWNSCALE)))

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()   # the main viewport's (player) camera
	if cam == null or _dof_cam == null:
		return
	# Same world view as the main viewport at lower resolution: smaller buffer → zoom scaled by 1/DOWNSCALE.
	_dof_cam.global_position = cam.global_position
	_dof_cam.zoom = cam.zoom / DOWNSCALE
