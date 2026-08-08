extends SceneTree
## One-shot BAKE: renders the REUSED Rubicon/Electric temple.glb from a true top-down ORTHOGONAL camera into a
## reference PNG that scripts/ui/hud/atlantic_landmark_mark.gd shows for clicking bubble/whirlpool attachment
## points. Verbatim port of tools/bake_volcanic_landmark.gd — see that file's header for the full rationale on
## the explicit camera basis / local-space math. Atlantic reuses Rubicon's temple.glb directly (2026-08-06, on
## request: "sử dụng temple của electric") rather than shipping its own copy, so this bakes straight from
## assets/map/rubicon/temple.glb into assets/map/atlantic/temple_mark_ref.png — the ONE Atlantic-local asset
## this reuse still needs (a reference image for the mark-editor UI, not a new 3D model).
##
## Run non-headless (3D rendering needs a real GPU context):
##   godot --path . --script tools/bake_atlantic_landmark.gd
## Output: assets/map/atlantic/temple_mark_ref.png

const AtlanticAssetScan := preload("res://scripts/gameplay/atlantic/atlantic_asset_scan.gd")

const TEMPLE_GLB_PATH := "res://assets/map/rubicon/temple.glb"   # reused directly, not copied
const OUT_PATH := "res://assets/map/atlantic/temple_mark_ref.png"
const VP_SIZE := 768
const SETTLE_FRAMES := 5

## Must match atlantic_temple_layer.gd's own copy exactly — see that file's header for why.
const LANDMARK_MARK_FRAME_MARGIN := 1.15

var _sv: SubViewport
var _cam: Camera3D
var _model: Node3D
var _rf := 0
var _needs_framing := false

func _initialize() -> void:
	if not ResourceLoader.exists(TEMPLE_GLB_PATH):
		print("bake_atlantic_landmark: no temple.glb at ", TEMPLE_GLB_PATH)
		quit(0)
		return

	_sv = SubViewport.new()
	_sv.size = Vector2i(VP_SIZE, VP_SIZE)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(_sv)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # straight overhead — flat reference diagram
	key.light_energy = 1.4
	_sv.add_child(key)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 0.98)
	env.ambient_light_energy = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_sv.add_child(_cam)

	var packed := load(TEMPLE_GLB_PATH) as PackedScene
	if packed == null:
		push_warning("bake_atlantic_landmark: failed to load " + TEMPLE_GLB_PATH)
		quit(0)
		return
	_model = packed.instantiate() as Node3D
	_sv.add_child(_model)
	_needs_framing = true
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	if _needs_framing:
		_needs_framing = false
		_frame_top_down(_model)
		return
	_rf += 1
	if _rf == SETTLE_FRAMES:
		var img := _sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
		var err := img.save_png(OUT_PATH)
		if err == OK:
			print("bake_atlantic_landmark: saved ", OUT_PATH)
		else:
			push_warning("bake_atlantic_landmark: save failed (%d) for %s" % [err, OUT_PATH])
		quit(0)

func _frame_top_down(model: Node3D) -> void:
	var aabb := AtlanticAssetScan.combined_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= Vector3(center.x, aabb.position.y, center.z)   # center XZ, rest the base on y=0

	var half_extent := Vector2(aabb.size.x, aabb.size.z) * 0.5   # SAME formula spawn_landmark()/
	                                                                # atlantic_temple_layer.gd use
	var frame_span: float = maxf(half_extent.x, half_extent.y) * 2.0 * LANDMARK_MARK_FRAME_MARGIN
	_cam.size = frame_span

	var cam_basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var cam_height: float = maxf(aabb.size.y * 2.0, 20.0) + frame_span
	_cam.global_transform = Transform3D(cam_basis, Vector3(0.0, cam_height, 0.0))
	_cam.near = 0.05
	_cam.far = cam_height + frame_span
