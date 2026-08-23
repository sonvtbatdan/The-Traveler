extends SceneTree
## One-shot bake: renders assets/map/volcanic/temple.glb into a tilted-perspective top-down reference PNG
## with real alpha — the SAME idiom tools/bake_electric_trees.gd used for Electric's temple.png (which already
## exists; Volcanic's never got one). Not the true-orthogonal tools/bake_volcanic_landmark.gd's output
## (temple_mark_ref.png, used for smoke/flame click-marking) — this is the THUMBNAIL/pointer-icon style.
##
## 2026-08-06, on request ("temple của electric đã có, volcanic chưa có") — volcanic_temple_layer.gd doesn't
## currently wire an arena_ruin_pointer.gd arrow (it's a purely visual landmark, no combat), so this icon has
## no in-game consumer yet either — produced for asset-completeness/parity with Electric, ready if a pointer
## is ever added there too.
##
## Run non-headless (3D rendering needs a real GPU context):
##   godot --path . --script tools/bake_volcanic_temple_icon.gd
## Output: assets/map/volcanic/temple.png

const VolcanicAssetScan := preload("res://scripts/gameplay/volcanic/volcanic_asset_scan.gd")

const GLB_PATH := "res://assets/map/volcanic/landmark/temple.glb"
const OUT_PATH := "res://assets/map/volcanic/landmark/temple.png"
const ISO_DEG := 30.0   # matches bake_electric_trees.gd's TREE_ISO_DEG / bake_ruin_landmarks.gd's ISO_DEG
const VP_SIZE := 512
const SETTLE_FRAMES := 5

var _sv: SubViewport
var _cam: Camera3D
var _model: Node3D
var _rf := 0
var _needs_framing := false

func _initialize() -> void:
	if not ResourceLoader.exists(GLB_PATH):
		print("bake_volcanic_temple_icon: missing ", GLB_PATH)
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

	var packed := load(GLB_PATH) as PackedScene
	if packed == null:
		push_warning("bake_volcanic_temple_icon: failed to load " + GLB_PATH)
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
		var err := img.save_png(OUT_PATH)
		if err == OK:
			print("bake_volcanic_temple_icon: saved ", OUT_PATH)
		else:
			push_warning("bake_volcanic_temple_icon: save failed (%d) for %s" % [err, OUT_PATH])
		quit(0)

func _frame_top_down(model: Node3D) -> void:
	var aabb := VolcanicAssetScan.combined_aabb(model)
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
