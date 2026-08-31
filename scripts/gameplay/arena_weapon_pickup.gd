extends Node2D
## A collectible weapon pickup (Gatling / Gauss / Lasgun / Arc). Floats in place with a bob + pulsing glow so
## it reads as "grab me". Collected when the player flies within COLLECT_RANGE (its OWN fixed range — a weapon
## shouldn't magnetize across the screen like an XP orb). On collection it auto-equips the weapon by telling
## arena_weapons to activate it (activate_<kind>), pops, and frees. Gameplay plane (sharp, not blurred).
##
## 2026-08-24: a weapon listed in `arena_weapons.ARENA_PICKUP_GLB` shows a LIVE 3D model, slowly spinning,
## in place of the procedural crate diamond + emblem; the glow halo and the pop-on-collect stay exactly as
## they were, so it still reads as a pickup at a glance. `arena_weapons.spawn_weapon_pickup()` resolves the
## path and passes it to setup() — that table is curated BY HAND, one weapon at a time, and deliberately
## NOT derived from the level-up board's icon resolution (InventoryManager.glb_for()): several weapons'
## sibling .glb is their AMMO/PROJECTILE model (the in-flight shot), not the gun, and would look wrong sitting
## in a "grab me" crate. Anything not in that table keeps drawing the procedural crate, as before.
##
## Recipe is arena_loot.gd's `_build_model_viewport()` — SubViewport + 2 DirectionalLight3D + Camera3D at a
## fixed ISO_DEG, model centred on its own AABB — kept as its own copy here for the same reason
## arena_loot/arena_chest/item_3d_icon each keep one.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
## 2026-08-28, on request ("cac icon drop (divinity, cac weapon, magnetic, coin...) cho to len 300% so voi hien tai"): every on-screen display size below (SIZE/MODEL_WIDTH) is x3 its old value. VP_SIZE (the 3D SubViewport render resolution, for types with a .glb - heart/magnetic/divinity here) is bumped x2, not x3, alongside it: at the OLD size the model was rendered SMALLER than its render target (a downscale, always sharp), so a flat x3 display bump with an unchanged VP_SIZE would upscale the render by 2-3x and read visibly blurry. x2 keeps the render close to 1:1 with the new display size without tripling the per-instance GPU cost for cosmetic-only sharpness. Every glow/halo already reads off these same constants (SIZE/_draw_size/ICON_W), so it scales for free - COLLECT_RANGE/RADIUS (the actual pickup gameplay) is untouched, this is purely visual.
const SIZE          := 42.0                       # 14 x3 — icon radius px
const GLOW          := 1.0                        # glow intensity
const COLLECT_RANGE := 46.0                        # fly within this to grab it
const BOB_AMP       := 4.0
const BOB_SPEED     := 2.2

# Per-kind look: crate/ring colour + an emblem style drawn across the crate. emblem: "beam" | "bolt" | "orb" | "tracer".
const KIND_STYLE := {
	"death_beam":  {"color": Color(1.0, 0.55, 0.22), "ring": Color(1.0, 0.8, 0.4),  "emblem": "beam"},
	"arc":     {"color": Color(0.55, 0.8, 1.0),  "ring": Color(0.7, 0.9, 1.0),  "emblem": "bolt"},
	"gauss":   {"color": Color(0.4, 0.7, 1.0),   "ring": Color(0.7, 0.9, 1.0),  "emblem": "orb"},
	"gatling": {"color": Color(1.0, 0.82, 0.25), "ring": Color(1.0, 0.9, 0.5),  "emblem": "tracer"},
	"defensive_orbitals": {"color": Color(0.65, 0.78, 0.95), "ring": Color(0.8, 0.9, 1.0), "emblem": "orb"},
	"striker": {"color": Color(1.0, 0.45, 0.15),  "ring": Color(1.0, 0.68, 0.45), "emblem": "orb"},
	"shooter": {"color": Color(1.0, 0.66, 0.22),  "ring": Color(1.0, 0.82, 0.45), "emblem": "orb"},
	"rift_maker":    {"color": Color(0.7, 0.4, 1.0),    "ring": Color(0.85, 0.7, 1.0), "emblem": "orb"},
	"dragons_breath":   {"color": Color(1.0, 0.35, 0.3),   "ring": Color(1.0, 0.6, 0.5),  "emblem": "bolt"},
	"chemtrail": {"color": Color(0.6, 0.95, 0.45),"ring": Color(0.8, 1.0, 0.6),  "emblem": "orb"},
	"little_man":    {"color": Color(1.0, 0.75, 0.35),  "ring": Color(1.0, 0.9, 0.6),  "emblem": "orb"},
	"ultrasonicator":   {"color": Color(0.55, 0.85, 1.0),  "ring": Color(0.75, 0.95, 1.0),"emblem": "orb"},
	"z_sword":  {"color": Color(0.7, 1.0, 0.85),   "ring": Color(0.85, 1.0, 0.95),"emblem": "beam"},
	"ionizing_field":  {"color": Color(0.6, 0.9, 1.0),    "ring": Color(0.8, 0.97, 1.0), "emblem": "bolt"},
	"aliwa": {"color": Color(0.95, 0.85, 0.5),"ring": Color(1.0, 0.95, 0.7), "emblem": "tracer"},
	"venomancer":  {"color": Color(0.6, 0.95, 0.45),"ring": Color(0.8, 1.0, 0.6),  "emblem": "orb"},
	"yari":   {"color": Color(0.8, 0.7, 1.0),  "ring": Color(0.9, 0.85, 1.0), "emblem": "orb"},
	"yari_jaeger": {"color": Color(0.9, 0.65, 1.0), "ring": Color(0.95, 0.8, 1.0), "emblem": "beam"},
	"swarm":       {"color": Color(0.95, 0.6, 0.85), "ring": Color(1.0, 0.8, 0.95), "emblem": "tracer"},
	"viper":       {"color": Color(1.0, 0.6, 0.3),   "ring": Color(1.0, 0.8, 0.5),  "emblem": "beam"},
}
const DEFAULT_STYLE := {"color": Color(0.8, 0.8, 0.8), "ring": Color(0.95, 0.95, 0.95), "emblem": "beam"}

const Item3DIcon := preload("res://scripts/ui/hud/item_3d_icon.gd")   # warm_scene() only — no Control is made here

const VP_SIZE      := 128       # 3D render resolution — x2 alongside the x3 display bump, see NOTE above
const ISO_DEG      := 30.0      # camera tilt — matches arena_loot.gd / arena_chest.gd
const MODEL_WIDTH  := 120.0     # 40 x3 — on-screen px for the model (bigger than the SIZE*2 crate — a weapon drop
                                # is a bigger deal than a heart, and the silhouette needs the room to read)
const MODEL_RPM    := 10.0      # idle spin
const MODEL_SPIN   := deg_to_rad(MODEL_RPM * 360.0 / 60.0)   # rad/s

var _kind: String = "death_beam"
var _t := 0.0
var _player: Node2D = null
var _popping := false
var _pop_t := 0.0
var _vp: SubViewport = null
var _cam: Camera3D = null
var _pivot: Node3D = null
var _spr3d: Sprite2D = null
var _is_3d := false

func setup(world_pos: Vector2, kind: String, glb_path: String = "") -> void:
	global_position = world_pos
	_kind = kind
	_t = randf() * TAU
	if glb_path != "" and ResourceLoader.exists(glb_path):
		_build_model_viewport(glb_path)

## See this file's header. Returns false (nothing changed) if the model won't load, so the procedural crate
## in _draw() simply stands as before.
func _build_model_viewport(glb_path: String) -> bool:
	var packed := Item3DIcon.warm_scene(glb_path)   # shared warm table — see that function's comment
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model == null:
		push_warning("arena_weapon_pickup: could not load " + glb_path)
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
	# Ambient, same reason item_3d_icon.gd needed it: project.godot has no default environment, so any face
	# the two directional lights miss renders pure black on a dark-material model.
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

## Centre `model` on its own AABB and back the camera off far enough to fit it — same as arena_loot._frame_cam.
func _frame_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	model.position -= aabb.position + aabb.size * 0.5
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) + radius
	var iso := deg_to_rad(ISO_DEG)
	# look_at_from_position, not position + look_at: look_at needs is_inside_tree() and silently no-ops
	# otherwise (the bug item_3d_icon.gd's own header documents), and _cam IS parented by now but this is
	# the form that can't regress if that ever changes.
	_cam.look_at_from_position(Vector3(0.0, cos(iso), sin(iso)) * dist, Vector3.ZERO, Vector3(0.0, 1.0, 0.0))

func _model_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	for mi: MeshInstance3D in _model_meshes(root):
		# Local transform, not global: the chain isn't in the main tree yet when this runs.
		var box: AABB = mi.transform * mi.get_aabb()
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

func _process(delta: float) -> void:
	_t += delta
	if _is_3d and _spr3d != null:
		_pivot.rotation.y += MODEL_SPIN * delta
		_spr3d.position = Vector2(0.0, sin(_t * BOB_SPEED) * BOB_AMP)   # same bob as the crate
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

func _style() -> Dictionary:
	return KIND_STYLE.get(_kind, DEFAULT_STYLE)

func _collect() -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons != null and weapons.has_method("acquire_weapon"):
		weapons.call("acquire_weapon", _kind)   # fills a slot (cap-respecting) + activates the weapon
	elif weapons != null and weapons.has_method("activate_" + _kind):
		weapons.call("activate_" + _kind)        # fallback
	_popping = true
	_pop_t = 0.0

func _draw() -> void:
	var st := _style()
	var col: Color = st["color"]
	var ring: Color = st["ring"]
	if _popping:
		var pt := clampf(_pop_t / 0.25, 0.0, 1.0)
		var r := SIZE * (1.0 + pt * 3.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(ring.r, ring.g, ring.b, (1.0 - pt) * 0.8), 3.0)
		return
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.8 + 0.2 * sin(_t * BOB_SPEED * 1.6)
	# Glow halo.
	draw_circle(c, SIZE * 2.0 * pulse, Color(col.r, col.g, col.b, 0.12 * GLOW))
	draw_circle(c, SIZE * 1.35 * pulse, Color(col.r, col.g, col.b, 0.25 * GLOW))
	if _is_3d:
		return   # the live model IS the art — glow halo above still frames it, crate/emblem would occlude it
	# Crate diamond.
	var d := SIZE
	var pts := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
	draw_colored_polygon(pts, Color(0.12, 0.10, 0.14, 0.9))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), ring, 2.0)
	_draw_emblem(c, d, col, pulse, String(st["emblem"]))

## Weapon-flavoured glyph across the crate face.
func _draw_emblem(c: Vector2, d: float, col: Color, pulse: float, emblem: String) -> void:
	var bright := Color(col.r, col.g, col.b, 0.9)
	match emblem:
		"bolt":
			# Zig-zag lightning bolt (Arc).
			var pp := PackedVector2Array([
				c + Vector2(-d * 0.35, -d * 0.55), c + Vector2(d * 0.1, -d * 0.1),
				c + Vector2(-d * 0.1, d * 0.1),    c + Vector2(d * 0.35, d * 0.55)])
			draw_polyline(pp, bright, 3.0 * pulse)
			draw_polyline(pp, Color(1, 1, 1, 0.9), 1.0)
		"orb":
			# Filled plasma ball (Gauss).
			draw_circle(c, d * 0.45 * pulse, bright)
			draw_circle(c, d * 0.22 * pulse, Color(1, 1, 1, 0.9))
		"tracer":
			# Twin vertical tracer streaks (Gatling).
			for sx: float in [-0.3, 0.3]:
				draw_line(c + Vector2(d * sx, -d * 0.55), c + Vector2(d * sx, d * 0.55), bright, 3.0 * pulse)
		_:
			# "beam": a short bright horizontal streak (Lasgun).
			draw_line(c + Vector2(-d * 0.6, 0), c + Vector2(d * 0.6, 0), bright, 3.0 * pulse)
			draw_line(c + Vector2(-d * 0.6, 0), c + Vector2(d * 0.6, 0), Color(1, 1, 1, 0.9), 1.0)
