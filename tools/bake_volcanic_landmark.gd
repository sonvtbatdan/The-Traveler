extends SceneTree
## One-shot BAKE: renders temple.glb from a true top-down ORTHOGONAL camera (not the tilted-perspective
## convention tools/bake_electric_trees.gd uses for thumbnails) into a reference PNG that
## scripts/ui/hud/volcanic_landmark_mark.gd shows for clicking smoke/flame attachment points. A true top-down
## ortho shot (not tilted, not perspective) is what makes clicked pixels convert to local model-space offsets
## with plain linear math (see volcanic_temple_layer.gd's header) — no perspective distortion to account for.
##
## Camera basis is constructed EXPLICITLY (not via look_at, whose exact axis mapping is easy to get subtly
## wrong) so the image orientation is know: image RIGHT = model local +X, image DOWN = model local +Z — this
## matches the project's "2D Y+ is down" screen convention (2D world_pos.y maps to 3D Z via *_z_comp
## everywhere else in this map's code), so the reference image reads the same "north-up" way the in-game 2D
## top-down view does.
##
## Run non-headless (mirrors tools/bake_electric_trees.gd — 3D rendering needs a real GPU context):
##   godot --path . --script tools/bake_volcanic_landmark.gd
## Output: assets/map/volcanic/temple_mark_ref.png

const VolcanicAssetScan := preload("res://scripts/gameplay/volcanic/volcanic_asset_scan.gd")

const TEMPLE_GLB_PATH := "res://assets/map/volcanic/landmark/temple.glb"
const OUT_PATH := "res://assets/map/volcanic/landmark/temple_mark_ref.png"
const VP_SIZE := 768
const SETTLE_FRAMES := 5

## Must match volcanic_temple_layer.gd's own copy exactly — see that file's header for why.
const LANDMARK_MARK_FRAME_MARGIN := 1.15

var _sv: SubViewport
var _cam: Camera3D
var _model: Node3D
var _rf := 0
var _needs_framing := false

func _initialize() -> void:
	if not ResourceLoader.exists(TEMPLE_GLB_PATH):
		print("bake_volcanic_landmark: no temple.glb at ", TEMPLE_GLB_PATH)
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
	key.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # straight overhead — this is a flat reference diagram,
	                                                    # not a moody hero shot; even, shadowless lighting reads
	                                                    # the model's outline/silhouette most clearly for marking
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
		push_warning("bake_volcanic_landmark: failed to load " + TEMPLE_GLB_PATH)
		quit(0)
		return
	_model = packed.instantiate() as Node3D
	_sv.add_child(_model)
	_needs_framing = true
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	if _needs_framing:
		# Deferred one frame: global_transform isn't valid until the node has actually rendered once.
		_needs_framing = false
		_frame_top_down(_model)
		return
	_rf += 1
	if _rf == SETTLE_FRAMES:
		var img := _sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var err := img.save_png(OUT_PATH)
		if err == OK:
			print("bake_volcanic_landmark: saved ", OUT_PATH)
		else:
			push_warning("bake_volcanic_landmark: save failed (%d) for %s" % [err, OUT_PATH])
		quit(0)

func _frame_top_down(model: Node3D) -> void:
	var aabb := VolcanicAssetScan.combined_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= Vector3(center.x, aabb.position.y, center.z)   # center XZ, rest the base on y=0

	var half_extent := Vector2(aabb.size.x, aabb.size.z) * 0.5   # SAME formula spawn_landmark()/
	                                                                # volcanic_temple_layer.gd use
	var frame_span: float = maxf(half_extent.x, half_extent.y) * 2.0 * LANDMARK_MARK_FRAME_MARGIN
	_cam.size = frame_span

	# Explicit basis (see this file's header) — right = model +X, "up" (image top) = model -Z, so image DOWN
	# = model +Z, matching the project's 2D "Y+ is down" convention.
	var cam_basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var cam_height: float = maxf(aabb.size.y * 2.0, 20.0) + frame_span
	_cam.global_transform = Transform3D(cam_basis, Vector3(0.0, cam_height, 0.0))
	_cam.near = 0.05
	_cam.far = cam_height + frame_span
