extends Node2D
## Giant dead-ship wreck for the arena. Stationary, 4× the old ruin size (280 px wide), 10,000 HP,
## rotates slowly in place. On death it drops a single "orb of light" (no box phase). Joins group
## "arena_ruin" so arena_weapons and explode() can hit it without counting toward the enemy cap.
## Spawned two-per-run by arena_ruin_layer.gd.

const ArenaExplosion := preload("res://scripts/gameplay/arena_explosion.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SHIP_WIDTH  := 280.0              # 4× the old 70 px ruin
const SHIP_HP     := 10000.0
const ROT_SPEED   := deg_to_rad(8.0)    # slow idle spin
const HIT_FLASH_T := 0.12               # seconds of white flash per hit

const ORB_TYPE := "orb_of_light"        # loot dropped on death

# ── State ─────────────────────────────────────────────────────────────────────
var _variant: int = 1         # 1–4 (which ship texture)
var hp: float = SHIP_HP
var hp_max: float = SHIP_HP
var hit_radius: float = 0.0   # circular hitbox radius; set in setup()
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2.ZERO
var _mgr: Node = null
var _dead: bool = false
var _hit_flash: float = 0.0   # counts down; > 0 → draw white overlay

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(variant: int, mgr: Node) -> void:
	add_to_group("arena_ruin")
	_variant = clampi(variant, 1, 4)
	_mgr = mgr
	hp = SHIP_HP
	hp_max = SHIP_HP
	hit_radius = SHIP_WIDTH * 0.45   # ~126px; covers most of the 280px sprite
	_load_tex()

func _load_tex() -> void:
	var path := "res://assets/ruin/ship%d.png" % _variant
	_tex = load(path) as Texture2D
	if _tex == null:
		return
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	_draw_size = Vector2(SHIP_WIDTH, SHIP_WIDTH * th / tw)

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _dead:
		return
	rotation += ROT_SPEED * delta   # stationary but slowly rotating
	_hit_flash = maxf(0.0, _hit_flash - delta)
	queue_redraw()

# ── Damage ────────────────────────────────────────────────────────────────────
func take_damage(dmg: float, _stagger: float = 0.0, _knock: float = 0.0) -> void:
	if _dead:
		return
	hp -= dmg
	_hit_flash = HIT_FLASH_T
	queue_redraw()
	if hp <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	_spawn_explosion(_draw_size.x)
	_play_boom()
	_drop_orb()
	queue_free()

func _spawn_explosion(size_px: float) -> void:
	var ex: Node2D = ArenaExplosion.new()
	get_parent().add_child(ex)
	ex.call("setup", global_position, size_px)

func _play_boom() -> void:
	var stream := load("res://assets/audio/sfx/gunboom%d.wav" % randi_range(1, 5)) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(0.7)
	get_parent().add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _drop_orb() -> void:
	if _mgr != null and _mgr.has_method("spawn_loot"):
		_mgr.spawn_loot(global_position, ORB_TYPE)

# ── Draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if _tex == null or _dead:
		return
	var r := Rect2(-_draw_size * 0.5, _draw_size)
	draw_texture_rect(_tex, r, false)
	if _hit_flash > 0.0:
		draw_texture_rect(_tex, r, false, Color(1.0, 1.0, 1.0, 0.55))
	# HP bar drawn in un-rotated local space (same as arena_enemy.gd)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp < hp_max:
		var ratio := clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
		var w := _draw_size.x
		var bx := -w * 0.5
		var by := -_draw_size.y * 0.5 - 12.0
		draw_rect(Rect2(bx, by, w, 5.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx, by, w * ratio, 5.0), Color(0.4, 0.95, 0.4))
