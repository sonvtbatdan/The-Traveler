extends Control
## Drop-in 3D-model icon control — a live SubViewport render of a .glb, sized/used like a TextureRect but
## with a real spinning/rotatable model instead of a flat PNG. 2026-08-19, on request ("thay cho file sprite
## trong bảng levelup... áp dụng logic xoay xoay giống như chest / nắm vào object và xoay để xem các chiều").
##
## Framing reuses arena_chest.gd's exact recipe: SubViewport (own_world_3d, transparent) + 2 DirectionalLight3D
## + Camera3D fixed at a tilted ISO_DEG, model centered on a pivot via its own AABB so it fits/spins about its
## middle (see _frame_cam/_model_aabb below — duplicated rather than shared, matching how arena_chest.gd and
## ship_rotation_test.gd each already keep their own copy of this same math).
##
## Two modes, picked by `interactive` in setup():
##   false (default) — passive spin only, about the model's own Y axis at ROT_RPM (same idea as arena_chest.
##     gd/electric_ruin_layer.gd/volcanic_ruin_layer.gd's ROT_RPM landmarks, just slower — see const below).
##     mouse_filter stays IGNORE so this NEVER steals input — safe to sit under a covering Button (e.g. the
##     levelup board's pick-1-of-3 cards, which own click-to-select via their own Button on top).
##   true — no auto-spin; left-drag orbits it YAW-ONLY (mirrors a turntable, not ship_rotation_test.gd's full
##     free-look — 2026-08-19, on request: "có thể nắm để xoay tròn, không xoay thoải mái mọi hướng được")
##     and it holds wherever released. Only for a stand-alone preview spot with nothing covering it (the
##     levelup board's big WeaponDisplay frame — the one spot the user can "cầm vào object và xoay").
##
## Render resolution is intentionally modest and MSAA is off — unlike the chest (one per run), several of
## these can be alive at once (levelup board: 3 small cards + 1 big preview, all at the same moment).
##
## Sizing: 2026-08-20 — unlike a PNG's CONTAIN-fit (which keeps the texture's own aspect and can leave the
## box smaller than its frame on one axis), this control fills the FULL (max_w × max_h) rectangle the caller
## passes — there's no fixed 2D aspect to preserve for a 3D model, and every board frame in
## arena_levelup_ui.gd is itself non-square, so forcing a square (the old side = min(max_w, max_h) behaviour)
## left the control visibly smaller than its frame on the longer axis. _frame_cam fits the model tightly
## against this same (max_w, max_h) aspect (see _aspect below) instead of assuming square.
##
## Camera: 2026-08-19, on request ("góc nhìn... nhìn ngang vào item", "model đang nhỏ... fit gần hết khung") —
## ISO_DEG raised from 30° (near top-down, matching arena_chest.gd's own iso convention) to 90° (fully level,
## camera at the same height as the model's own center) for a horizontal "product shot" angle, AND _frame_cam
## fits much tighter than before: since rotation is now YAW-ONLY everywhere (both this control's own passive
## spin and the interactive drag above), the camera never needs to worry about the model pitching toward it —
## the worst case across every yaw angle is the model's own horizontal FOOTPRINT diagonal (X-Z), not its full
## 3D diagonal including height, which is what the old (pre-2026-08-19) framing used and left ~50-65% of the
## frame empty as a result.
##
## 2026-08-20, same-day follow-up ("viewport nhỏ hơn frame khá nhiều... fisheye khi xoay... set orthographic...
## viewport mở rộng ra bằng với frame"): two more fixes on top of the pass above:
##   1. This control used to force a SQUARE (side = min(max_w, max_h)) regardless of the caller's actual
##      (max_w, max_h) box — every board frame in arena_levelup_ui.gd is itself non-square, so the control was
##      genuinely smaller than its frame on the longer axis (not just the rendered model inside it). Now sizes
##      to the FULL (max_w, max_h) rectangle and the SubViewport's own render resolution matches that aspect
##      too (VP_MAX_SIDE caps the longer edge, was a fixed 160×160 square).
##   2. Camera3D defaulted to PERSPECTIVE, whose short focal length (default fov) visibly fisheyes a tightly-
##      framed model while it turntables. Switched to PROJECTION_ORTHOGONAL — apparent size no longer depends
##      on distance, so _frame_cam now fits by solving for the camera's `size` (view-volume diameter) instead
##      of a fov-based distance; distance is now free to just clear the model comfortably.

const ROT_RPM     := 8.0                                  # slower than the chest's 12 — static UI, not
                                                           # scrolling arena space; less distracting to sit near
const ROT_SPEED   := deg_to_rad(ROT_RPM * 360.0 / 60.0)    # rad/s
const ISO_DEG     := 90.0                                  # camera tilt off top-down — 90° = fully horizontal/level, see this file's header
const VP_MAX_SIDE := 200                                   # render resolution cap on the render target's LONGER edge — the shorter edge follows the control's own (max_w, max_h) aspect (was a fixed 160×160 square)
const FIT_MARGIN  := 0.15                                  # extra headroom beyond the tight fit, as a fraction of the larger axis — keeps the silhouette off the frame edge
const MOUSE_SENS  := 0.01                                  # rad per pixel dragged — matches ship_rotation_test.gd

var _interactive: bool = false
var _vp: SubViewport = null
var _cam: Camera3D = null
var _pivot: Node3D = null
var _dragging: bool = false
var _yaw: float = 0.0
var _aspect: float = 1.0   # (max_w / max_h) passed to setup() — drives both the SubViewport's render-target shape and _frame_cam's ortho `size` solve, see this file's header (2026-08-20)

# ══ Warm cache — the level-up board's anti-hitch preload (2026-08-24) ═══════════════════════════════════
# A weapon .glb costs ~300ms to load COLD (measured across assets/inventory/*.glb: 280-345ms each, and the
# level-up board builds 3 small cards + 1 big preview at once — so opening the board froze the game for the
# better part of a second). Godot's own resource cache only holds WEAK references, so the PackedScene is
# dropped again the moment the last icon is freed and the NEXT level-up pays the full cost all over again.
# arena_glb_preloader.gd warms these in the background during play and parks the PackedScene here, where a
# real (strong) reference keeps it resident; a cached re-load then measures ~0.02ms, i.e. gone.
# Static so the preloader and every icon share one table without a node lookup between them.
static var _warm: Dictionary = {}   # glb path -> PackedScene (strong ref)

## Park an already-loaded PackedScene so later setup() calls for `path` skip the disk hit. Called by
## arena_glb_preloader.gd once its threaded request for `path` completes.
static func warm_store(path: String, scene: PackedScene) -> void:
	if path != "" and scene != null:
		_warm[path] = scene

static func is_warm(path: String) -> bool:
	return _warm.has(path)

## The PackedScene for `path`, from the warm table when the preloader already parked it, otherwise loaded
## now AND parked (so the next caller is instant either way). The one entry point every 3D-art consumer
## should use instead of a bare load() — arena_weapon_pickup.gd goes through this too, which is what keeps
## a 54 MB orbital model from cold-loading in the middle of a fight just because it dropped as loot.
static func warm_scene(path: String) -> PackedScene:
	if path == "":
		return null
	var cached: PackedScene = _warm.get(path) as PackedScene
	if cached != null:
		return cached
	var packed := load(path) as PackedScene
	if packed != null:
		_warm[path] = packed
	return packed

## Drop every parked scene (called when the arena tears down — no reason to hold ~75MB of weapon models
## resident while the player sits in the main menu; the next run just warms them again in the background).
## Already-instantiated icons are unaffected: an instantiated node doesn't reference its PackedScene.
static func warm_clear() -> void:
	_warm.clear()

## Safe to call fully detached (before this control is parented anywhere) — the AABB-fit framing below only
## reads global_transform across the Node3D chain built right here (SubViewport → pivot → model), which
## composes independent of whether the outer Control tree is live; the SubViewport itself only needs to be
## live once actually on-screen, which happens naturally when the caller parents this control like any other
## icon. Returns false (and leaves this control empty) if `glb_path` fails to load — caller should fall back
## to a plain TextureRect in that case.
func setup(glb_path: String, max_w: float, max_h: float, interactive: bool = false) -> bool:
	_interactive = interactive
	_aspect = (max_w / max_h) if max_h > 0.001 else 1.0
	custom_minimum_size = Vector2(max_w, max_h)
	size = Vector2(max_w, max_h)
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_PASS if interactive else Control.MOUSE_FILTER_IGNORE
	add_child(svc)

	_vp = SubViewport.new()
	# Render-target shape matches the control's own (possibly non-square) aspect — see this file's header
	# (2026-08-20) — instead of the old fixed 160×160 square, which is what actually made the rendered model
	# look "smaller than the frame" on a non-square board slot even after the tight AABB fit.
	var vp_w := VP_MAX_SIDE if _aspect >= 1.0 else int(round(VP_MAX_SIDE * _aspect))
	var vp_h := VP_MAX_SIDE if _aspect <= 1.0 else int(round(VP_MAX_SIDE / _aspect))
	_vp.size = Vector2i(maxi(vp_w, 1), maxi(vp_h, 1))
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	# 2026-08-19, bugfix ("Lightning mất hẳn hình ảnh"): no WorldEnvironment here meant zero ambient light —
	# project.godot has no default environment either, so any face the 2 directional lights above don't
	# directly hit rendered pure black. Fine for simple/bright models, but KM-FC-A-Alt.glb (Arc/"Lightning")
	# is dark-material + deeply concave (tripod cannon) and came out ~95% black pixels in a real render test
	# (see tools/_diag_render.gd — screenshot confirmed it, not a loading failure). Matches ship_rotation_
	# test.gd's own ambient recipe; BG_CLEAR_COLOR keeps the viewport transparent (own_world_3d + transparent_
	# bg above), only the ambient TERM changes.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.48)
	e.ambient_light_energy = 1.2
	env.environment = e
	_vp.add_child(env)

	_cam = Camera3D.new()
	_vp.add_child(_cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	# Warm cache first (see warm_scene above) — a cold load() here is ~300ms of hard freeze, and this runs
	# while the level-up board is being built, i.e. exactly when the player is watching.
	var packed := warm_scene(glb_path)
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model == null:
		push_warning("item_3d_icon: could not load " + glb_path)
		return false
	_pivot.add_child(model)
	_frame_cam(model)

	if interactive:
		set_process(false)
		set_process_input(false)   # driven by _gui_input only
	else:
		set_process(true)
	return true

func _process(delta: float) -> void:
	if _interactive or _pivot == null:
		return
	_pivot.rotation.y += ROT_SPEED * delta

## Yaw-only — only horizontal mouse movement (mm.relative.x) turns the model; vertical movement is ignored,
## on request (see this file's header). A turntable, not a free-look orbit.
func _gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * MOUSE_SENS
		_apply_drag_rotation()
		accept_event()

func _apply_drag_rotation() -> void:
	if _pivot != null:
		_pivot.rotation = Vector3(0.0, _yaw, 0.0)

## Center `model` on its own AABB (so it spins/orbits about its middle) and place an ORTHOGONAL camera at a
## fixed ISO_DEG tilt, sized to fit the whole model TIGHTLY — see this file's header (2026-08-19) for why this
## fits by the model's horizontal footprint diagonal + its own height separately instead of arena_chest.gd's
## own full-3D-diagonal radius (safe here because rotation is yaw-only everywhere in this file), and the
## header's 2026-08-20 note for why the camera is orthogonal (no fisheye) and solved via `_cam.size` rather
## than a fov-based distance (apparent size is distance-independent under an orthogonal projection).
func _frame_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	# Worst case across every YAW angle: the footprint's own diagonal (X-Z plane) sets the required
	# horizontal fit; the model's height (Y) never changes with yaw, so it's fit separately. Whichever axis
	# needs more of the view volume wins — the other axis ends up with some unavoidable extra headroom (a
	# model whose proportions don't match the frame's own aspect can never perfectly fill both axes at once).
	var footprint_radius: float = maxf(Vector2(aabb.size.x, aabb.size.z).length() * 0.5, 0.001)
	var half_height: float = maxf(aabb.size.y * 0.5, 0.001)
	var margin_scale := 1.0 + FIT_MARGIN
	var radius := maxf(footprint_radius, half_height) * margin_scale   # for distance/near/far below — generous, not the tight fit
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Camera3D's default keep_aspect is KEEP_HEIGHT: `size` is the view volume's full vertical diameter, and
	# the horizontal diameter is derived as `size * viewport_aspect` — so solve for whichever of the two
	# required diameters (vertical = model height, horizontal = footprint diagonal ÷ our own _aspect) is
	# larger, same "whichever axis needs more room wins" logic as the old fov-based fit above.
	var need_v := half_height * 2.0 * margin_scale
	var need_h := footprint_radius * 2.0 * margin_scale
	_cam.size = maxf(need_v, need_h / maxf(_aspect, 0.001))
	var dist := radius * 3.0   # orthogonal apparent size doesn't depend on distance — just clear the model comfortably so near/far has room either side
	var iso := deg_to_rad(ISO_DEG)
	# 2026-08-19, bugfix ("Lightning mất cả thumbnail và preview" — actually every weapon icon, not model-
	# specific): look_at() requires the node to already be inside the SceneTree (Godot prints "Node not
	# inside tree. Use look_at_from_position() instead." and silently no-ops otherwise) — but setup() is
	# explicitly documented/used to work fully DETACHED (arena_levelup_ui.gd's _make_weapon_icon() calls
	# setup() BEFORE the caller ever adds this control to the board). The camera's rotation was silently
	# never getting set, so it rendered facing its default orientation — nowhere near the model — while
	# arena_chest.gd's/arena_ruin_pointer.gd's OWN look_at() calls happen to be safe only because THEIR
	# callers add the node to the tree before calling setup(), an ordering this file never actually required.
	# look_at_from_position() sets position + orientation in one call with no tree dependency — fixes this
	# at the root instead of demanding every caller re-order its add_child/setup calls.
	_cam.look_at_from_position(Vector3(0.0, cos(iso), sin(iso)) * dist, Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far  = dist + radius * 2.0
	# 2026-08-19, bugfix ("Lightning mất hẳn hình ảnh") continued: the fixed key/fill lights above are
	# world-space, so how well they light THIS particular model's camera-facing surface depends on that
	# model's own geometry/normals — KM-FC-A-Alt.glb (dark gunmetal, deeply concave tripod) caught almost
	# none of it. A "headlamp" copying the camera's own look direction guarantees whatever the camera
	# actually sees is lit, regardless of the model — same fix class as the ambient add above, this one
	# targets the camera-facing side specifically instead of a general floor.
	var headlamp := DirectionalLight3D.new()
	headlamp.rotation = _cam.rotation
	headlamp.light_energy = 1.6
	_vp.add_child(headlamp)

## Composes each mesh's transform relative to `root` from LOCAL `.transform` values only (_relative_
## transform below) instead of global_transform — 2026-08-19, bugfix (same root cause as the look_at() fix
## above): Node3D.get_global_transform() ALSO requires is_inside_tree() (prints "Condition '!is_inside_
## tree()' is true. Returning: Transform3D()" and silently returns identity otherwise), so this control's own
## doc-commented "safe to call fully detached" claim was wrong until both this and the look_at() fix — every
## mesh's composed transform was silently coming back as identity, which happened to still look plausible for
## simple single-level hierarchies but would have been outright wrong for anything nested deeper.
func _model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	# 2026-08-23: `mi.get_aabb()` is the BIND-space box for a SKINNED mesh, not what gets drawn — the bones
	# place the geometry, and for Yari Jeager (armature scaled 0.01 against ~100x bone rests) the two differ
	# by about 100x. Framing off it put the camera around a box a hundredth of the model, so the card
	# rendered blank. `glb_topdown_rig.instance_aabb()` already solves this (skins each vertex at the rest
	# pose, cached per mesh); shared rather than copied a third time because the fix is ~50 lines, not the
	# one-liner the rest of this file's duplicated framing math is.
	var rig := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	for mi: MeshInstance3D in _model_meshes(root):
		var box: AABB = _relative_transform(root, mi) * rig.instance_aabb(mi)
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

## `node`'s transform expressed relative to `root` (an ancestor of `node`), composed purely from each
## intermediate node's LOCAL `.transform` — walking `get_parent()` up from `node` to `root` needs no
## SceneTree membership at all (unlike global_transform), so this works whether `root` is attached or not.
func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		xform = n.transform * xform
		n = n.get_parent() as Node3D
	return xform

func _model_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_model_meshes(c))
	return out
