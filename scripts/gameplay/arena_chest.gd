extends Node2D
## A reward chest spawned far from the player at run start (one per run). Flying into it grants ONE level-up
## choice (the pick-1-of-3 card) WITHOUT increasing the player's level — then it despawns. An off-screen
## pointer (arena_chest_pointer.gd) guides the player to it. Group "arena_chest".
##
## 2026-08-06, on request ("thay Chest.glb cho chest đang vẽ bằng code hiện tại... cho xoay giống như các
## landmark rescue xoay"): the placeholder procedural crate is replaced by the real assets/ruin/Chest.glb model,
## rendered into a small SubViewport (own Camera3D + 2 DirectionalLight3D) exactly like arena.gd's own ship
## viewport (_build_ship_viewport/_frame_ship_cam) — same fit-to-fov framing math, same fixed ISO_DEG tilt — and
## shown on a Sprite2D. The model spins continuously about its own vertical axis at ROT_RPM, matching the spin
## rate electric_ruin_layer.gd/volcanic_ruin_layer.gd use for their rescue-character landmarks ("xoay giống như
## các landmark rescue xoay").
##
## This is a SELF-CONTAINED SubViewport (not one of the per-map *_trees shared-World3D scatter systems) because
## the chest spawns on EVERY map, including Default/Space, which has no 3D scatter host at all — mirrors why
## the ship gets its own dedicated viewport instead of borrowing a map's trees system too.
##
## 2026-08-28, on request ("voi chest hien dang co hinh tron vang lam nen, hay thay no bang cac vong tron toa
## ra lien tuc, radius=100px"): the static pulsing gold disc this used to draw in _draw() is gone, replaced by
## arena_beacon_rings.gd parented under the chest sprite - see that file's header. _draw() itself is now empty
## of chrome, so this node no longer needs a per-frame queue_redraw().
##
## icon_texture() exposes this same live, already-spinning SubViewport render so arena_chest_pointer.gd's edge
## indicator can just display it directly — ONE rendered model drives both the in-world sprite and the edge
## icon, no separate static indicator image file needed at all ("dùng nó thay cho file ảnh indicator luôn").

const CHEST_MODEL   := "res://assets/ruin/Chest.glb"
const COLLECT_RANGE := 72.0
const VP_SIZE        := 128           # SubViewport render resolution — small (icon-scale), so this stays cheap
const DISPLAY_PX     := 46.0          # on-screen width/height of the in-world sprite
const ISO_DEG         := 30.0         # camera tilt off top-down — matches arena.gd's SHIP_ISO_DEG / the
                                       # project's other iso-rendered 3D-in-2D elements
const ROT_RPM         := 12.0         # matches electric_ruin_layer.gd/volcanic_ruin_layer.gd's ROT_RPM exactly
const ROT_SPEED       := deg_to_rad(ROT_RPM * 360.0 / 60.0)   # rad/s
const BeaconRingsScript := preload("res://scripts/gameplay/arena_beacon_rings.gd")

var _player: Node2D = null
var _taken: bool = false
var _vp: SubViewport = null
var _cam: Camera3D = null
var _pivot: Node3D = null
var _spr: Sprite2D = null

func _ready() -> void:
	add_to_group("arena_chest")
	z_index = 50   # above weapon FX (≤6), below the ship (100)
	_build_model_viewport()
	_build_beacon()

func _process(delta: float) -> void:
	if _taken:
		return
	if _pivot != null:
		_pivot.rotation.y += ROT_SPEED * delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and global_position.distance_to(_player.global_position) <= COLLECT_RANGE:
		_collect()
		return

func _collect() -> void:
	_taken = true
	var ui := get_tree().get_first_node_in_group("levelup_ui")
	if ui != null and ui.has_method("grant_reward"):
		ui.call("grant_reward")   # reward WITHOUT a real level-up
	queue_free()

## Public: the live, already-spinning render of the chest model — reused as-is by arena_chest_pointer.gd's
## edge-of-screen icon (see this file's header). null until the model finishes loading (or if it's missing).
func icon_texture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null

## Renders assets/ruin/Chest.glb into a small SubViewport, framed via its AABB exactly like arena.gd's own
## _build_ship_viewport()/_frame_ship_cam() (fit-to-fov distance, fixed ISO_DEG tilt) — see this file's header.
func _build_model_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_vp.add_child(_cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	var packed := load(CHEST_MODEL) as PackedScene
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model == null:
		push_warning("arena_chest: could not load " + CHEST_MODEL)
		_cam.position = Vector3(0.0, 0.0, 5.0)
		_cam.look_at(Vector3.ZERO, Vector3.UP)
	else:
		_pivot.add_child(model)
		_frame_cam(model)

	_spr = Sprite2D.new()
	_spr.texture = _vp.get_texture()
	_spr.scale = Vector2.ONE * (DISPLAY_PX / float(VP_SIZE))
	add_child(_spr)

## Center `model` on its own AABB (so it spins about its middle, not some off-origin pivot) and place the
## camera at a fixed ISO_DEG tilt, backed off just far enough (given its fov) to fit the whole model.
func _frame_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(ISO_DEG)
	_cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	_cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far  = dist + radius * 2.0

## Uses GLOBAL transforms (root must already be inside the tree — it is, by the time this runs: chest's own
## _ready() only fires after arena.gd's add_child(chest), and every node here was add_child()'d synchronously
## down the chain before this call) so nested mesh instances at any depth resolve correctly, not just direct
## children — mirrors arena.gd's own _model_aabb() exactly.
func _model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in _model_meshes(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _model_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_model_meshes(c))
	return out

## Expanding gold rings beneath the model sprite - the "fly here" beacon, replacing the old static pulsing
## disc (see this file's header, 2026-08-28). z_index -1 is RELATIVE to this node's own 50, i.e. absolute 49:
## just under the chest sprite, still above the creeps at z 1.
func _build_beacon() -> void:
	var beacon: Node2D = BeaconRingsScript.new()
	beacon.z_index = -1
	add_child(beacon)
	beacon.call("setup", BeaconRingsScript.GOLD)
