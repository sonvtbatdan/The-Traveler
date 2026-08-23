extends SceneTree
## One-shot bake: render each rescue-character .glb in assets/ruin/ (Scholar/constructor/engineer/mechanic/
## psyker — the Electric-map ruin landmarks, see electric_ruin_layer.gd) into a top-down reference PNG with
## real alpha, same idiom as tools/bake_electric_trees.gd's temple bake. Unlike that tool, these ARE actually
## used at runtime: electric_ruin_layer.gd renders the live .glb via ElectricTrees.spawn_landmark() same as the
## temple, but arena_ruin_pointer.gd's edge-of-screen arrow needs a flat 2D icon to borrow — that's what this
## produces (mirrors temple.png's role exactly).
##
## assets/ruin/ is shared with the flat-sprite dead-ship wreck pool (arena_ruin_layer.gd's ship/box/alien
## PNGs) — this tool only touches the 5 hardcoded RUIN_GLB stems below, not a folder scan, so it can't ever
## clobber those or pick up something unrelated.
##
## Run non-headless (3D rendering needs a real GPU context):
##   godot --path . --script tools/bake_ruin_landmarks.gd
## Output: assets/ruin/<name>.png, alongside each source .glb.

const ElectricAssetScan := preload("res://scripts/gameplay/electric/electric_asset_scan.gd")

const FOLDER := "res://assets/ruin/"
const RUIN_GLB := ["Scholar", "constructor", "engineer", "mechanic", "psyker"]   # filename stems, case-sensitive

const ISO_DEG := 30.0   # same convention as bake_electric_trees.gd's TREE_ISO_DEG / arena.gd's SHIP_ISO_DEG
const VP_SIZE := 512
const SETTLE_FRAMES := 5

var _sv: SubViewport
var _cam: Camera3D
var _model: Node3D
var _queue: Array = []
var _pending_path: String = ""
var _rf := 0
var _needs_framing := false

func _initialize() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(VP_SIZE, VP_SIZE)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(_sv)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-100.0, 20.0, 0.0)
	key.light_energy = 1.6
	_sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-80.0, -160.0, 0.0)
	fill.light_energy = 0.7
	_sv.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 0.98)
	env.ambient_light_energy = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)

	_cam = Camera3D.new()
	_sv.add_child(_cam)

	for stem: String in RUIN_GLB:
		_queue.append(FOLDER + stem + ".glb")
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
		push_warning("bake_ruin_landmarks: missing " + path)
		call_deferred("_start_next")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("bake_ruin_landmarks: failed to load " + path)
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
		_needs_framing = false
		_frame_top_down(_model)
		return
	_rf += 1
	if _rf == SETTLE_FRAMES:
		var img := _sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var out_path := ElectricAssetScan.baked_png_path(_pending_path)
		var err := img.save_png(out_path)
		if err == OK:
			print("bake_ruin_landmarks: saved ", out_path)
		else:
			push_warning("bake_ruin_landmarks: save failed (%d) for %s" % [err, out_path])
		call_deferred("_start_next")

func _frame_top_down(model: Node3D) -> void:
	var aabb := ElectricAssetScan.combined_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= Vector3(center.x, aabb.position.y, center.z)
	var radius: float = maxf(Vector2(aabb.size.x, aabb.size.z).length() * 0.5, aabb.size.y * 0.5)
	radius = maxf(radius, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(ISO_DEG)
	_cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	_cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far = dist + radius * 2.0
