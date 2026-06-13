class_name NormalEnemy
extends Control

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
var contact_explodes: bool = false   # die on player contact (kingfisher / swarm / bomb)
var body_color: Color = Color(0.8, 0.4, 0.4)
var shape_kind: String = "circle"    # "circle" | "triangle" | "diamond" | "square"
var icon_path: String = ""       # res:// path to PNG; leave "" to keep the placeholder shapes
var size_mult: float  = 1.0     # set in _configure() to scale the HP-derived diameter
# Set false in _configure() to delay becoming damageable until the enemy calls _register() itself
# (e.g. the Kingfisher is only a warning sign for 1s before it actually enters).
var auto_register: bool = true
var contact_active: bool = true  # gate player-contact checks (off during a warning/telegraph phase)

# ── Runtime ───────────────────────────────────────────────────────────────────
var hp: float = 30.0
var _mgr: Node = null            # EnemyManager (ship position + bullets + explosions)
var _ws: Node = null             # weapon_system (target registration)
var _tex: Texture2D = null       # loaded from icon_path in _ready(); null = use placeholder shapes
var _flash: float = 0.0
var _dead: bool = false
var _registered: bool = false

## Global HP multiplier for ALL normal enemies (bosses are separate). 3.0 = +200% HP.
const ENEMY_HP_MULT := 3.0

func _ready() -> void:
	_configure()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("normal_enemy")
	# Size scales with the CONFIGURED max HP (bigger HP = bigger shape) — computed BEFORE the global
	# HP multiplier so tripling HP doesn't change the shape size.
	var d := _diameter_for_hp(hp_max) * size_mult
	size = Vector2(d, d)
	pivot_offset = size * 0.5
	hp_max *= ENEMY_HP_MULT   # +200% HP
	hp = hp_max
	if icon_path != "":
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

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _dead:
		return
	_tick(delta)
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
