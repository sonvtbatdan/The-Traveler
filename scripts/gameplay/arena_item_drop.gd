extends Node2D
## A collectible INVENTORY-ITEM drop — what an Elite/Champion Creep leaves behind on death (2026-08-25, on
## request: "khi bắn chết elite / champion, tôi cần icon weapon drop ra trên màn hình").
##
## Distinct from arena_weapon_pickup.gd, which grants one of the bespoke 5-slot ARENA weapons (`acquire_
## weapon(kind)`) and is keyed by weapon KIND. This one is keyed by an `InventoryManager` **def_id** and goes
## into the BACKPACK — which is why its pickup notice says "Press I to view" (I opens the inventory panel).
##
## Art, per the request ("nếu trong inventory có glb thì drop object glb xoay tròn, ko có thì fallback png"):
##   • `InventoryManager.get_glb(def_id)` returns a model → live SubViewport render, spinning at MODEL_RPM.
##     Same recipe as arena_loot.gd/arena_weapon_pickup.gd (SubViewport + 2 DirectionalLight3D + ambient +
##     Camera3D at ISO_DEG, model centred on its own AABB), and it goes through
##     `item_3d_icon.warm_scene()` so a big model is served from the shared warm cache instead of
##     cold-loading mid-fight.
##   • otherwise → the item's flat PNG icon (`InventoryManager.get_icon`), drawn aspect-correct.
##   • neither → a plain rarity-coloured diamond, so a drop is never invisible.
##
## Collected by flying within COLLECT_RANGE (its own fixed range — like a weapon pickup, it does NOT
## magnetise across the screen the way an XP orb does).

const Item3DIcon := preload("res://scripts/ui/hud/item_3d_icon.gd")   # warm_scene() only — no Control is made here
const ArenaToastScript := preload("res://scripts/ui/hud/arena_toast.gd")

const COLLECT_RANGE := 52.0
const BOB_AMP       := 4.0
const BOB_SPEED     := 2.2
const GLOW          := 1.0
const ICON_W        := 44.0     # on-screen width of the flat-PNG form (height follows the texture's ratio)
const VP_SIZE       := 64       # 3D render resolution — small on purpose, matches arena_loot.gd's
const ISO_DEG       := 30.0
const MODEL_WIDTH   := 48.0
const MODEL_RPM     := 10.0
const MODEL_SPIN    := deg_to_rad(MODEL_RPM * 360.0 / 60.0)
const FALLBACK_R    := 13.0     # radius of the no-art diamond

var _def_id: String = ""
var _t := 0.0
var _player: Node2D = null
var _popping := false
var _pop_t := 0.0
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2(ICON_W, ICON_W)
var _col: Color = Color(0.85, 0.85, 0.9)
var _vp: SubViewport = null
var _cam: Camera3D = null
var _pivot: Node3D = null
var _spr3d: Sprite2D = null
var _is_3d := false

func setup(world_pos: Vector2, def_id: String) -> void:
	global_position = world_pos
	_def_id = def_id
	_t = randf() * TAU
	var d: Dictionary = InventoryManager.get_def(def_id)
	var rarity := String(d.get("rarity", "common"))
	_col = InventoryManager.RARITY_COLORS.get(rarity, _col)
	var glb := String(InventoryManager.get_glb(def_id)) if InventoryManager.has_method("get_glb") else ""
	if glb != "" and ResourceLoader.exists(glb) and _build_model_viewport(glb):
		return
	_tex = InventoryManager.get_icon(def_id)
	if _tex != null:
		var tw := float(_tex.get_width())
		var th := float(_tex.get_height())
		if tw > 0.0:
			_draw_size = Vector2(ICON_W, ICON_W * th / tw)   # never stretched — ratio from the texture

func _process(delta: float) -> void:
	_t += delta
	if _is_3d and _spr3d != null:
		_pivot.rotation.y += MODEL_SPIN * delta
		_spr3d.position = Vector2(0.0, sin(_t * BOB_SPEED) * BOB_AMP)
		_spr3d.visible = not _popping
	if _popping:
		_pop_t += delta
		queue_redraw()
		if _pop_t >= 0.25:
			queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and global_position.distance_to(_player.global_position) <= COLLECT_RANGE:
		_collect()
	queue_redraw()

## Into the BACKPACK, flagged run-temp exactly like meta_manager's own field drops, so it behaves as
## in-run loot (purged at the start of the next run) rather than silently becoming permanent profile gear.
## A full backpack is reported rather than swallowed — otherwise the pickup would just vanish on contact.
func _collect() -> void:
	_popping = true
	_pop_t = 0.0
	# The toast must be hosted by something that OUTLIVES this drop: ArenaToast parents its CanvasLayer (and
	# its fade tween) to `host`, and this node queue_free()s itself 0.25s into the pop — hosting it on `self`
	# would kill the notice a quarter-second in, long before its 3s lifetime. Parent (the Arena) is stable.
	var host: Node = get_parent()
	if host == null or not is_instance_valid(host):
		host = get_tree().current_scene
	var nm := String(InventoryManager.get_def(_def_id).get("name", _def_id))
	if not InventoryManager.has_room_for(_def_id):
		ArenaToastScript.show(host, "%s dropped — inventory FULL" % nm, "bottom_right")
		return
	var uid := InventoryManager.add_to_backpack(_def_id)
	if uid == -1:
		ArenaToastScript.show(host, "%s dropped — inventory FULL" % nm, "bottom_right")
		return
	if MetaManager.has_method("mark_run_temp"):
		MetaManager.mark_run_temp(uid)
	ArenaToastScript.show(host, "%s has been acquired. Press I to view" % nm, "bottom_right")

## See this file's header. Returns false (nothing changed) if the model won't load, so setup() falls through
## to the flat-PNG path.
func _build_model_viewport(glb_path: String) -> bool:
	var packed := Item3DIcon.warm_scene(glb_path)   # shared warm table — see that function's comment
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model == null:
		push_warning("arena_item_drop: could not load " + glb_path)
		return false
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	# Ambient — project.godot has no default environment, so faces the two lights miss render pure black on a
	# dark-material model (the same fix item_3d_icon.gd's header documents).
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
	_pivot.add_child(model)
	_frame_cam(model)
	_spr3d = Sprite2D.new()
	_spr3d.texture = _vp.get_texture()
	_spr3d.scale = Vector2.ONE * (MODEL_WIDTH / float(VP_SIZE))
	add_child(_spr3d)
	_is_3d = true
	return true

## Centre `model` on its own AABB and back the camera off far enough to fit it — same as
## arena_weapon_pickup.gd/_frame_cam and arena_loot.gd's.
func _frame_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	model.position -= aabb.position + aabb.size * 0.5
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) + radius
	var iso := deg_to_rad(ISO_DEG)
	# look_at_from_position, not position + look_at: look_at silently no-ops unless is_inside_tree()
	# (see item_3d_icon.gd's own bugfix note).
	_cam.look_at_from_position(Vector3(0.0, cos(iso), sin(iso)) * dist, Vector3.ZERO, Vector3(0.0, 1.0, 0.0))

func _model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	for mi: MeshInstance3D in _model_meshes(root):
		var box: AABB = mi.transform * mi.get_aabb()   # local: the chain isn't in the main tree yet
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

func _draw() -> void:
	if _popping:
		var pt := clampf(_pop_t / 0.25, 0.0, 1.0)
		draw_arc(Vector2.ZERO, (ICON_W * 0.5) * (1.0 + pt * 3.0), 0.0, TAU, 24,
				Color(_col.r, _col.g, _col.b, (1.0 - pt) * 0.8), 3.0)
		return
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.8 + 0.2 * sin(_t * BOB_SPEED * 1.6)
	# Rarity-tinted glow halo, drawn for BOTH art paths so the drop reads as loot at a glance.
	draw_circle(c, ICON_W * 0.95 * pulse, Color(_col.r, _col.g, _col.b, 0.12 * GLOW))
	draw_circle(c, ICON_W * 0.62 * pulse, Color(_col.r, _col.g, _col.b, 0.22 * GLOW))
	if _is_3d:
		return   # the live model IS the art — the halo above frames it
	if _tex != null:
		draw_texture_rect(_tex, Rect2(c - _draw_size * 0.5, _draw_size), false)
		return
	# No art at all — a rarity-coloured diamond so the drop is never invisible.
	var r := FALLBACK_R
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
		Color(_col.r, _col.g, _col.b, 0.9))
