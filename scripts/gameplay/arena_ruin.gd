extends Node2D
## Breakable ruin prop for the arena. Two-phase life: ship (200 HP, 70 px wide) → box (50 HP, 40 px wide).
## Ships drift at 20–50 px/s and rotate at 15 RPM. On death the ship spawns its matching box; the box
## drops a random loot item. Joins group "arena_ruin" so arena_weapons and explode() can hit it without
## counting toward the enemy cap.

const ArenaExplosion := preload("res://scripts/gameplay/arena_explosion.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SHIP_WIDTH  := 70.0
const BOX_WIDTH   := 40.0
const SHIP_HP     := 200.0
const BOX_HP      := 50.0
const ROT_SPEED   := deg_to_rad(90.0)   # 15 RPM
const SPEED_MIN   := 20.0
const SPEED_MAX   := 50.0
const HIT_FLASH_T := 0.12               # seconds of white flash per hit

const LOOT_POOL := ["coin", "diamond", "heart", "magnetic", "shield"]

# ── State ─────────────────────────────────────────────────────────────────────
var _phase: String = "ship"   # "ship" | "box"
var _variant: int = 1         # 1–4 (which ship/box texture)
var hp: float = SHIP_HP
var hp_max: float = SHIP_HP
var hit_radius: float = 0.0   # circular hitbox radius; set in setup() based on phase
var _vel: Vector2 = Vector2.ZERO
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
	_phase = "ship"
	hp = SHIP_HP
	hp_max = SHIP_HP
	hit_radius = SHIP_WIDTH * 0.45   # ~31.5px; covers most of the 70px sprite
	_load_tex()
	_randomize_vel()

func setup_as_box(variant: int, mgr: Node) -> void:
	add_to_group("arena_ruin")
	_variant = clampi(variant, 1, 4)
	_mgr = mgr
	_phase = "box"
	hp = BOX_HP
	hp_max = BOX_HP
	hit_radius = BOX_WIDTH * 0.45   # ~18px; covers most of the 40px sprite
	_load_tex()
	_randomize_vel()

func _load_tex() -> void:
	var path := "res://assets/ruin/%s%d.png" % [_phase, _variant]
	_tex = load(path) as Texture2D
	if _tex == null:
		return
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	var target_w := SHIP_WIDTH if _phase == "ship" else BOX_WIDTH
	_draw_size = Vector2(target_w, target_w * th / tw)

func _randomize_vel() -> void:
	var speed := randf_range(SPEED_MIN, SPEED_MAX)
	var angle := randf() * TAU
	_vel = Vector2(cos(angle), sin(angle)) * speed

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _dead:
		return
	position += _vel * delta
	rotation += ROT_SPEED * delta
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
	if _phase == "ship":
		var box: Node2D = get_script().new()
		get_parent().add_child(box)
		box.setup_as_box(_variant, _mgr)
		box.global_position = global_position
	else:
		_drop_loot()
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

func _drop_loot() -> void:
	var t: String = LOOT_POOL[randi() % LOOT_POOL.size()]
	if _mgr != null and _mgr.has_method("spawn_loot"):
		_mgr.spawn_loot(global_position, t)

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
		var by := -_draw_size.y * 0.5 - 8.0
		draw_rect(Rect2(bx, by, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx, by, w * ratio, 3.0), Color(0.4, 0.95, 0.4))
