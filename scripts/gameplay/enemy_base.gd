class_name NormalEnemy
extends Control

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")

## Shared base for all normal (non-boss) enemies. Lives as a child of EnemyManager (itself a child of
## SpaceScreen), so position/size are in SpaceScreen-local coords — the same space as weapon_system
## bullets, the boss, and asteroids.
##
## Damage integration: on _ready the enemy registers with weapon_system via add_hit_target(), so
## EVERY player weapon (and the acid gun's armor-shred) hits it for free. It applies its OWN armor→DR
## inside on_weapon_hit(), mirroring asteroid_layer._apply_damage / GameManager.take_boss_damage.
##
## Subclasses override _configure() (set the tunable stats + look) and _tick(delta) (movement/attacks).

const ARMOR_FLOOR := -400.0   # acid can shred armor this far negative (caps damage amplification)

# ── Config — subclasses set these in _configure() ─────────────────────────────
var hp_max: float = 30.0
var armor: float = 0.0           # 0 = no damage reduction; negative (acid-shredded) = amplified
var xp_reward: int = 5           # XP granted to the player on death (0 = none, e.g. bombs)
var contact_damage: int = 0      # damage dealt to the SHIP on contact (0 = never touches the player)
var contact_explodes: bool = false   # die on player contact (diver / swarm / bomb)
var body_color: Color = Color(0.8, 0.4, 0.4)
var shape_kind: String = "circle"    # "circle" | "triangle" | "diamond" | "square"
var icon_path: String = ""       # res:// path to PNG; leave "" to keep the placeholder shapes
var size_mult: float  = 1.0     # set in _configure() to scale the HP-derived diameter
# Set false in _configure() to delay becoming damageable until the enemy calls _register() itself
# (e.g. the Diver is only a warning sign for 1s before it actually enters).
var auto_register: bool = true
var contact_active: bool = true  # gate player-contact checks (off during a warning/telegraph phase)
var invulnerable: bool = false   # still a hit target (blocks/consumes shots) but takes NO damage

# ── Runtime ───────────────────────────────────────────────────────────────────
var hp: float = 30.0
var _mgr: Node = null            # EnemyManager (ship position + bullets + explosions)
var _ws: Node = null             # weapon_system (target registration)
var _tex: Texture2D = null       # loaded from icon_path in _ready(); null = use placeholder shapes
var _frames: Array = []          # GIF animation frames (empty = static texture)
var _delays: Array = []          # GIF frame delays (seconds)
var _anim_acc: float = 0.0
var _anim_frame: int = 0
var _flash: float = 0.0
var _dead: bool = false
var _registered: bool = false

## Emitted when this enemy is KILLED by the player (via die()), NOT when culled via despawn(). Used by
## choreographies for death triggers (e.g. Enemy_group_1 spawns Divers when a Sentinel dies).
signal died

## Global HP multiplier for ALL normal enemies (bosses are separate). 1.5 = +50% HP (halved from 3.0).
const ENEMY_HP_MULT := 1.5
## Set > 0 in _configure() to override the global multiplier for this enemy type.
var _hp_mult: float = -1.0

# ── Fire-point positions ──────────────────────────────────────────────────────
static var _fp_fracs_cache: Dictionary = {}
var _fp_fracs: Array = []   # Array[{frac:Vector2, dir_angle:float, id:int}]

# ── Thrust-point plume VFX ────────────────────────────────────────────────────
# Cache: basename → Array[{frac:Vector2, dir_angle:float}] — loaded once per type per session.
static var _tp_fracs_cache: Dictionary = {}

var _plumes: Array[CPUParticles2D] = []

func _ready() -> void:
	_configure()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("normal_enemy")
	# Size scales with the CONFIGURED max HP (bigger HP = bigger shape) — computed BEFORE the global
	# HP multiplier so tripling HP doesn't change the shape size.
	var d := _diameter_for_hp(hp_max) * size_mult
	size = Vector2(d, d)
	pivot_offset = size * 0.5
	hp_max *= (_hp_mult if _hp_mult > 0.0 else ENEMY_HP_MULT)
	hp = hp_max
	if icon_path != "":
		if icon_path.ends_with(".gif"):
			var gtex := GifLoader.load_gif(icon_path)
			if gtex != null:
				if gtex.has_meta("gif_frames"):
					_frames = gtex.get_meta("gif_frames")
					_delays = gtex.get_meta("gif_delays") if gtex.has_meta("gif_delays") else []
					_tex = _frames[0] as Texture2D
				else:
					_tex = gtex
		else:
			_tex = load(icon_path) as Texture2D
		if _tex != null:
			var ts := _tex.get_size()
			if ts.x > 0.0:
				size.y = size.x * ts.y / ts.x   # keep width from HP, scale height to texture ratio
				pivot_offset = size * 0.5
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_ws = get_tree().get_first_node_in_group("weapon_system")
	if auto_register:
		_register()
	_setup_plumes()
	_setup_fire_points()
	queue_redraw()

## Register as a weapon target so player weapons + acid shred can hit this enemy. Idempotent.
func _register() -> void:
	if _registered:
		return
	if _ws == null or not is_instance_valid(_ws):
		_ws = get_tree().get_first_node_in_group("weapon_system")
	if _ws != null and _ws.has_method("add_hit_target"):
		_ws.add_hit_target(get_hit_rect, on_weapon_hit, on_shred, self)
		_registered = true

## Override: set hp_max / armor / xp_reward / contact_* / body_color / shape_kind.
func _configure() -> void:
	pass

## Override: per-frame movement and attacks.
func _tick(_delta: float) -> void:
	pass

## Override: what to do when the enemy touches the ship (base deals contact_damage + optional death).
func on_player_contact() -> void:
	if contact_damage > 0:
		GameManager.ship_take_damage(contact_damage)
	if contact_explodes:
		_on_contact_death()

## How a contact-exploding enemy dies when it rams the player. Default: vanish with NO XP (the player
## got hit, not a kill). Bombs override this to trigger their area explosion.
func _on_contact_death() -> void:
	despawn()

func _diameter_for_hp(h: float) -> float:
	return clampf(20.0 + h * 0.35, 24.0, 110.0)

## Convert centimetres to pixels using the screen DPI (shared by enemies whose spec is in cm).
func cm_to_px(cm: float) -> float:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

# ── Geometry ──────────────────────────────────────────────────────────────────
func get_hit_rect() -> Rect2:
	return Rect2(position, size)

func center() -> Vector2:
	return position + size * 0.5

func radius() -> float:
	return size.x * 0.5

# ── Damage (called by weapon_system through the registered callbacks) ──────────
## Apply one weapon hit. `raw` is post-affix/crit weapon damage; armor DR is applied here.
func on_weapon_hit(raw: float) -> void:
	if _dead:
		return
	if invulnerable:
		_flash = 0.12   # show the block, but take no damage and never die
		queue_redraw()
		return
	var dmg := raw * (1.0 - GameManager.armor_damage_reduction(armor))
	hp -= dmg
	_flash = 0.12
	queue_redraw()
	if hp <= 0.0:
		die()

## Acid armor-shred — drives armor down (and negative → amplified damage), floored.
func on_shred(amount: float) -> void:
	armor = maxf(ARMOR_FLOOR, armor - amount)

func die() -> void:
	if _dead:
		return
	_dead = true
	if xp_reward > 0:
		GameManager.add_xp(xp_reward)
	died.emit()
	_unregister()
	queue_free()

## Remove without granting XP (used by CLEAR ENEMIES / off-screen culling).
func despawn() -> void:
	if _dead:
		return
	_dead = true
	_unregister()
	queue_free()

func _unregister() -> void:
	if _ws != null and is_instance_valid(_ws) and _ws.has_method("remove_hit_target"):
		_ws.remove_hit_target(self)

func _exit_tree() -> void:
	_unregister()

# ── Fire-point helpers ─────────────────────────────────────────────────────────
func _setup_fire_points() -> void:
	var cname := icon_path.get_file().get_basename().to_lower()
	if cname.is_empty():
		return
	if not _fp_fracs_cache.has(cname):
		_fp_fracs_cache[cname] = _load_fp_fracs(cname)
	_fp_fracs = _fp_fracs_cache[cname]

static func _load_fp_fracs(cname: String) -> Array:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := ConfigFile.new()
	if cfg.load("res://creep_layout.cfg") != OK:
		return []
	var eo: Dictionary = cfg.get_value("creeps", cname, {})
	if eo.is_empty():
		return []
	var eo_pos: Vector2  = eo.get("pos",  Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0,  60.0))
	if eo_size.x <= 0.0 or eo_size.y <= 0.0:
		return []
	var fps: Array = cfg.get_value("firepoints", cname, [])
	var result: Array = []
	for i: int in fps.size():
		var fp: Dictionary = fps[i]
		var fp_oc: Vector2 = (fp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (fp_oc - eo_pos) / eo_size
		result.append({"frac": frac, "dir_angle": float(fp.get("dir_angle", 0.0)), "id": int(fp.get("id", i + 1))})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return result

## World position of fire-point `idx`. Falls back to center() if FP not configured.
func _muzzle(idx: int = 0) -> Vector2:
	if idx < _fp_fracs.size():
		return position + (_fp_fracs[idx]["frac"] as Vector2) * size
	return center()

# ── Thrust-point plume VFX ────────────────────────────────────────────────────
func _setup_plumes() -> void:
	var cname := icon_path.get_file().get_basename().to_lower()
	if cname.is_empty():
		return
	if not _tp_fracs_cache.has(cname):
		_tp_fracs_cache[cname] = _load_tp_fracs(cname)
	var fracs: Array = _tp_fracs_cache[cname]
	if fracs.is_empty():
		return
	var amount := maxi(1, int(size.x / 5.0))
	var all_styles := _load_plume_styles_for(cname)
	for i: int in fracs.size():
		var fd: Dictionary = fracs[i]
		var tp_id: int = int(fd.get("id", i + 1))
		var style: Dictionary = all_styles.get("tp_%d" % tp_id, {})
		var p := _make_enemy_plume(amount, fd["frac"] as Vector2, float(fd["dir_angle"]), style)
		add_child(p)
		_plumes.append(p)

static func _load_plume_styles_for(cname: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("res://plume_styles.cfg") != OK:
		return {}
	return cfg.get_value("styles", cname, {})

static func _load_tp_fracs(cname: String) -> Array:
	# TP positions are saved in SS space; EO pos is saved in OC-local space.
	# OC-local = SS + SCREEN_ORIGIN (15, 8) — convert TP to OC-local before computing fraction.
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := ConfigFile.new()
	if cfg.load("res://creep_layout.cfg") != OK:
		return []
	var eo: Dictionary = cfg.get_value("creeps", cname, {})
	if eo.is_empty():
		return []
	var eo_pos: Vector2 = eo.get("pos", Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0, 60.0))
	if eo_size.x <= 0.0 or eo_size.y <= 0.0:
		return []
	var tps: Array = cfg.get_value("thrustpoints", cname, [])
	var result: Array = []
	for i: int in tps.size():
		var tp: Dictionary = tps[i]
		var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (tp_oc - eo_pos) / eo_size
		result.append({"frac": frac, "dir_angle": float(tp.get("dir_angle", PI * 0.5)), "id": int(tp.get("id", i + 1))})
	return result

func _make_enemy_plume(amount: int, frac: Vector2, dir_angle: float, style: Dictionary = {}) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = frac * size
	p.amount = amount
	p.lifetime             = float(style.get("lifetime", 0.35))
	p.emitting = true
	p.local_coords = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = true
	p.z_index = 1
	p.gravity = Vector2.ZERO
	p.direction = Vector2.RIGHT.rotated(dir_angle)
	p.spread               = float(style.get("spread",   12.0))
	p.initial_velocity_min = float(style.get("vel_min",  80.0))
	p.initial_velocity_max = float(style.get("vel_max",  130.0))
	p.scale_amount_min     = float(style.get("sc_min",   1.0))
	p.scale_amount_max     = float(style.get("sc_max",   2.2))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.05))
	p.scale_amount_curve = taper
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	p.texture = ImageTexture.create_from_image(img)
	var col_core:  Color = style.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	var col_flame: Color = style.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	var col_fade           := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	return p

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _dead:
		return
	_tick(delta)
	if not _frames.is_empty():
		_anim_acc += delta
		var fd: float = _delays[_anim_frame] if _anim_frame < _delays.size() else 0.1
		if _anim_acc >= fd:
			_anim_acc -= fd
			_anim_frame = (_anim_frame + 1) % _frames.size()
			_tex = _frames[_anim_frame] as Texture2D
			queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()
	_check_player_contact()

func _check_player_contact() -> void:
	if not contact_active:
		return   # disabled during a warning/telegraph phase
	if _mgr == null or not is_instance_valid(_mgr):
		return
	if contact_damage <= 0 and not contact_explodes:
		return
	var sc: Vector2 = _mgr.ship_center()
	var sr: float = _mgr.ship_radius()
	if center().distance_to(sc) <= sr + radius():
		on_player_contact()

# ── Draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if _tex != null:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
		if _flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.7))
	else:
		var c := size * 0.5
		var r := size.x * 0.5
		var col := body_color
		if _flash > 0.0:
			col = col.lerp(Color.WHITE, 0.7)
		_draw_shape(c, r, col)
	# HP bar above the body.
	var ratio := clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
	draw_rect(Rect2(0.0, -6.0, size.x, 3.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(0.0, -6.0, size.x * ratio, 3.0), Color(0.4, 0.95, 0.4))

func _draw_shape(c: Vector2, r: float, col: Color) -> void:
	match shape_kind:
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(-r * 0.87, r * 0.6), c + Vector2(r * 0.87, r * 0.6)]), col)
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r, 0.0), c + Vector2(0.0, r), c + Vector2(-r, 0.0)]), col)
		"square":
			draw_rect(Rect2(c - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), col)
		_:
			draw_circle(c, r, col)
	draw_arc(c, r, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 2.0)
