extends Node2D
## Restored legacy small-ruin prop (spawn_mode_2 only — see arena_small_ruin_layer.gd). Ships drift at
## 20–50 px/s and rotate at 15 RPM; death drops a random loot item directly. Joins group "arena_ruin" so
## arena_weapons and explode() hit it for free — nothing needs to change there. This is the original
## pre-giant-wreck ruin design (see git history, commit ade3fd1), reintroduced as a distinct small/frequent
## counterpart to the giant wrecks that used to also exist (arena_ruin_layer.gd/arena_ruin.gd — REMOVED
## 2026-08-06, on request: "loại bỏ các ruin dùng assets\ruin (loại lớn, nằm ở xa, có chỉ hướng)" — the giant
## dead-ship wrecks, 10,000-15,000px away with their own edge-of-screen pointer, are gone; this small/nearby/
## no-pointer type dropping small loot directly is now the ONLY "ruin" prop left in the Default map. See git
## history if the giant wrecks are ever wanted back).
##
## 2026-08-06, on request ("bỏ cơ chế bắn ruin ra box, giờ đây bắn ruin vỡ thì drop loot luôn"): used to be a
## two-phase ship (200 HP) → box (50 HP) → loot life, the ship spawning its own box on death instead of
## dropping loot itself. That box phase is now gone — a ship drops loot directly on death, one hit-to-death
## chain instead of two. box1-4.png/BOX_WIDTH/BOX_HP/setup_as_box removed with it (no other caller referenced
## them — see git history if the box phase is ever wanted back).

## 2026-08-29, on request ("khi bắn nổ ruin, loại bỏ hình gif animation, sử dụng vfx nổ giống như khi bắn
## enemies") — was arena_explosion.gd (a raw 7-frame Gun-Impact50.sheet.png flipbook), now arena_death_fx.gd,
## the SAME baked-composite explosion arena_enemy.gd's own _spawn_explosion() uses for every creep death (see
## that file's own doc comment: "the live composite Explosion... tanked the frame rate... the flipbook looks
## the same for ~zero cost" — a pre-baked bake of a real particle composite, not the older raw sprite sheet).
const DeathFX := preload("res://scripts/gameplay/arena_death_fx.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SHIP_WIDTH  := 70.0
const SHIP_HP     := 200.0
const ROT_SPEED   := deg_to_rad(90.0)   # 15 RPM
const SPEED_MIN   := 20.0
const SPEED_MAX   := 50.0
const HIT_FLASH_T := 0.12               # seconds of white flash per hit

# "shield" was dropped out of this pool when the old shield-visual path was retired (arena_shield_visual.gd
# became orphaned), then added back 2026-08-29 on request ("shield cũng là dạng drop như heal, hồi 20 shield.
# bắn ruin rơi ra") now that arena_loot.gd's _collect() has a real "shield" case (GameManager.add_shield(20))
# to route it to — see that file's own doc comment.
const LOOT_POOL := ["coin", "diamond", "heart", "magnetic", "divinity", "shield"]

# ── State ─────────────────────────────────────────────────────────────────────
var _variant: int = 1         # 1–4 (which ship texture)
var hp: float = SHIP_HP
var hp_max: float = SHIP_HP
var hit_radius: float = 0.0   # circular hitbox radius; set in setup()
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
	hp = SHIP_HP
	hp_max = SHIP_HP
	hit_radius = SHIP_WIDTH * 0.45   # ~31.5px; covers most of the 70px sprite
	_load_tex()
	_randomize_vel()

func _load_tex() -> void:
	var path := "res://assets/ruin/ship%d.png" % _variant
	_tex = load(path) as Texture2D
	if _tex == null:
		return
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	_draw_size = Vector2(SHIP_WIDTH, SHIP_WIDTH * th / tw)

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
# 2026-08-29 crash fix ("Invalid call to function 'take_damage'... Expected 3 argument(s)", arena_weapons.gd:
# 1141/3489 — Hivemind's take_damage(dmg, stagger, knock, ignore_armor, bleeds, was_crit) call, but ANY weapon
## calling the fuller form would have hit the same crash the moment it targeted a ruin) — this only ever
# accepted 3 positional args while arena_enemy.gd's own take_damage() (what every weapon is really written
# against) accepts up to 7. Widened to match that exact signature so no caller can ever over-argument this
# again; the ruin still only cares about `dmg` — every extra param is accepted and ignored, same as `_stagger`/
# `_knock` already were.
func take_damage(dmg: float, _stagger: float = 0.0, _knock: float = 0.0, _ignore_armor: bool = false, _bleeds: bool = false, _was_crit: bool = false, _kind: String = "") -> void:
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
	_drop_loot()
	queue_free()

func _spawn_explosion(size_px: float) -> void:
	var ex: Node2D = DeathFX.new()
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

const DIAMOND_COIN_COUNT := 5     # 2026-08-06, on request: a "diamond" roll no longer drops one 50-value
const DIAMOND_COIN_VALUE := 10    # diamond pickup — it scatters DIAMOND_COIN_COUNT individual coin pickups
                                   # instead (same total value: 5×10 = the old diamond's 50, just visually as
                                   # a handful of coins rather than one gem). Each arena_loot.gd instance rolls
                                   # its own random drift angle/speed in its own setup(), so spawning several
                                   # at the same origin already scatters them naturally — no extra code needed.

func _drop_loot() -> void:
	if _mgr == null or not _mgr.has_method("spawn_loot"):
		return
	var t: String = LOOT_POOL[randi() % LOOT_POOL.size()]
	if t == "diamond":
		for _c in DIAMOND_COIN_COUNT:
			_mgr.spawn_loot(global_position, "coin", DIAMOND_COIN_VALUE)
	else:
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
