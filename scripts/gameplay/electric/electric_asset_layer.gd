extends Node2D
class_name ElectricAssetLayer
## THE single 3D render pass for the Electric map's scattered assets — electric_trees.gd adds every scattered
## instance AND the real 3D cloud-occluder mesh into ONE shared World3D (see that script's header comment),
## and this class renders that whole world with ONE Camera3D into ONE composited TextureRect. Because
## everything (trees, temples, the cloud box) lives in the SAME pass, the engine's normal per-pixel depth
## test clips tall assets against the cloud correctly for free — no more whole-object above/below routing.
##
## Per-asset independent Blur (Terrain Edit panel) can no longer be "blur this type's OWN separate composite"
## (there's only one composite now) — instead a SECOND pass renders lightweight proxy copies of every
## instance (ElectricAssetScan.set_flat_material + set_instance_blur_param, built by electric_trees.gd) whose
## pixels encode that instance's own blur amount. electric_asset_composite.gdshader reads both textures and
## applies a per-pixel variable blur radius — so two asset types standing right next to each other can still
## have completely different blur amounts even though they share one color pass.
##
## Camera math (orthogonal, tilted, _z_comp-compensated) is unchanged from the old per-type-pass version —
## see CAM_ISO_DEG's comment below for why the tilt needs _z_comp at all.

const COLOR_BIT := 1 << 0   # real scattered instances + the cloud occluder mesh
const BLUR_BIT  := 1 << 1   # flat blur-id proxies (electric_blur_mask.gdshader)

const VP_DOWNSCALE := 1.5
const MASK_VP_DOWNSCALE := 3.0   # blur mask only needs a rough silhouette, not crisp edges — cheaper is fine
const CAM_ISO_DEG := 30.0    # matches arena.gd's SHIP_ISO_DEG — visual consistency across the whole map
const CAM_DIST := 1000.0    # orthogonal — only affects near/far clipping, not visual scale
const COMPOSITE_SHADER := "res://scripts/gameplay/electric/electric_asset_composite.gdshader"

var _color_vp: SubViewport
var _color_cam: Camera3D
var _mask_vp: SubViewport
var _mask_cam: Camera3D
var _composite: TextureRect
var _composite_mat: ShaderMaterial
var _z_comp: float = 1.0
var _view_size: Vector2 = Vector2(1440.0, 780.0)

## `world`: the shared World3D (electric_trees.gd.get_world_3d()).
func setup(world: World3D) -> void:
	_z_comp = 1.0 / cos(deg_to_rad(CAM_ISO_DEG))

	_color_vp = _make_viewport(world, COLOR_BIT)
	add_child(_color_vp)
	_color_cam = _color_vp.get_child(0)

	_mask_vp = _make_viewport(world, BLUR_BIT)
	add_child(_mask_vp)
	_mask_cam = _mask_vp.get_child(0)

	_composite = TextureRect.new()
	_composite.texture = _color_vp.get_texture()
	_composite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_composite.stretch_mode = TextureRect.STRETCH_SCALE
	_composite_mat = ShaderMaterial.new()
	_composite_mat.shader = load(COMPOSITE_SHADER)
	_composite_mat.set_shader_parameter("tex_blur_mask", _mask_vp.get_texture())
	_composite.material = _composite_mat
	add_child(_composite)
	_resize()
	get_viewport().size_changed.connect(_resize)

func _make_viewport(world: World3D, cull_mask_bit: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.world_3d = world
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED   # full-screen every frame — MSAA here would be expensive for little gain
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.cull_mask = cull_mask_bit
	vp.add_child(cam)
	return vp

func _resize() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_color_vp.size = Vector2i(maxi(1, int(vp_size.x / VP_DOWNSCALE)), maxi(1, int(vp_size.y / VP_DOWNSCALE)))
	_mask_vp.size = Vector2i(maxi(1, int(vp_size.x / MASK_VP_DOWNSCALE)), maxi(1, int(vp_size.y / MASK_VP_DOWNSCALE)))
	_composite.size = vp_size
	_composite.position = vp_size * -0.5   # centered on this node's own origin (tracks the camera via global_position)

## Call every frame with the camera's world-space focus and the viewport size.
func update_view(center: Vector2, view_size: Vector2) -> void:
	_view_size = view_size
	if _color_cam == null:
		return
	global_position = center   # composite rect stays screen-covering, same trick as electric_clouds.gd
	var look_at_point := Vector3(center.x, 0.0, center.y * _z_comp)
	var iso := deg_to_rad(CAM_ISO_DEG)
	var cam_pos: Vector3 = look_at_point + Vector3(0.0, cos(iso), sin(iso)) * CAM_DIST
	for cam: Camera3D in [_color_cam, _mask_cam]:
		cam.position = cam_pos
		cam.look_at(look_at_point, Vector3(0.0, 1.0, 0.0))
		cam.size = _view_size.y   # orthogonal: 1 world unit == 1 screen px everywhere, matching the flat 2D ground
		cam.near = maxf(0.05, CAM_DIST * 0.1)
		cam.far = CAM_DIST * 4.0
