extends SceneTree
## One-shot THUMBNAIL bake: render each tree/temple .glb in assets/map/rubicon/ into a top-down reference
## PNG with real alpha. NOT used for in-game scattering any more — rubicon_trees.gd renders the live .glb
## directly in a shared 3D scene so panning the camera actually reveals new angles (a static 2D bake, no
## matter how it's rotated in-plane, can't do that — rotating a flat perspective-baked image in 2D just made
## trees look like they were tipping over). This tool is now purely a quick visual-reference/thumbnail step
## (e.g. to sanity-check a new .glb imported correctly) — see docs/vfx.md's "3D→2D bridge" note if this
## ever needs reviving for something that genuinely should be a static baked sprite.
##
## Camera is PERSPECTIVE, tilted TREE_ISO_DEG off straight-down — same convention arena.gd's SHIP_ISO_DEG
## uses for the player ship (30°: mostly top-down but with enough forward tilt to read side/volume detail).
##
## Run non-headless (mirrors tools/bake_death_explosion.gd — 3D rendering needs a real GPU context):
##   godot --path . --script tools/bake_rubicon_trees.gd
## Output: assets/map/rubicon/<model_name>.png, alongside each source .glb. Models are AUTO-DISCOVERED
## (RubiconAssetScan.glb_paths() — every .glb directly in assets/map/rubicon/) — just drop a new .glb in
## that folder and re-run; no path list to maintain here.

const RubiconAssetScan := preload("res://scripts/gameplay/rubicon/rubicon_asset_scan.gd")

const TREE_ISO_DEG := 30.0
const VP_SIZE := 512
const SETTLE_FRAMES := 5   # frames to let the renderer settle before capture — no animation to time, unlike the explosion sheet

var _sv: SubViewport
var _cam: Camera3D
var _model: Node3D
var _queue: Array = []
var _pending_path: String = ""
var _rf := 0
var _needs_framing := false   # true for the frame right after add_child — global_transform isn't valid until the node has actually entered the tree via a render pass

func _initialize() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(VP_SIZE, VP_SIZE)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(_sv)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-100.0, 20.0, 0.0)   # mostly overhead, slight angle for shading form
	key.light_energy = 1.6
	_sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-80.0, -160.0, 0.0)
	fill.light_energy = 0.7
	_sv.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)   # transparent — trees composite over the ground shader
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 0.98)
	env.ambient_light_energy = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)

	_cam = Camera3D.new()
	_sv.add_child(_cam)

	_queue = RubiconAssetScan.glb_paths()
	if _queue.is_empty():
		print("bake_rubicon_trees: no .glb found in ", RubiconAssetScan.FOLDER)
		quit(0)
		return
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_start_next()

func _start_next() -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	if _queue.is_empty():
		quit(0)
		return
	var path: String = _queue.pop_front()
	if not ResourceLoader.exists(path):
		push_warning("bake_rubicon_trees: missing " + path)
		call_deferred("_start_next")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("bake_rubicon_trees: failed to load " + path)
		call_deferred("_start_next")
		return
	_model = packed.instantiate() as Node3D
	_sv.add_child(_model)
	_pending_path = path
	_needs_framing = true
	_rf = 0

func _on_post_draw() -> void:
	if _model == null:
		return
	if _needs_framing:
		# Deferred one frame: querying global_transform synchronously right after add_child() (still
		# inside _initialize()'s call stack) errors "!is_inside_tree()" — the node isn't fully live until
		# the tree has actually processed a frame. Waiting for the first frame_post_draw sidesteps that.
		_needs_framing = false
		_frame_top_down(_model)
		return
	_rf += 1
	if _rf == SETTLE_FRAMES:
		var img := _sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var out_path := RubiconAssetScan.baked_png_path(_pending_path)
		var err := img.save_png(out_path)
		if err == OK:
			print("bake_rubicon_trees: saved ", out_path)
		else:
			push_warning("bake_rubicon_trees: save failed (%d) for %s" % [err, out_path])
		call_deferred("_start_next")

func _frame_top_down(model: Node3D) -> void:
	var aabb := RubiconAssetScan.combined_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= Vector3(center.x, aabb.position.y, center.z)   # center XZ, rest the base on y=0
	var radius: float = maxf(Vector2(aabb.size.x, aabb.size.z).length() * 0.5, aabb.size.y * 0.5)
	radius = maxf(radius, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(TREE_ISO_DEG)
	# Same formula as arena.gd._frame_ship_cam: mostly overhead (+Y) with a bit of forward tilt (+Z) —
	# perspective (Camera3D's default projection; NOT set to orthogonal) so the tilt actually reveals form.
	_cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	_cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far = dist + radius * 2.0
