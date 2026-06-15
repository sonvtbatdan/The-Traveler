extends CharacterBody2D
## World-space arena enemy — the port of the legacy NormalEnemy roster as ONE data-driven script. The
## wave_director configures each instance from its enemy table (behavior + stats); this script runs the
## behavior each frame, takes damage via the universal take_damage(amount) contract (so arena_weapons hit
## it), deals contact damage to the player via GameManager, and grants XP on death.
##
## Behaviours ported (shmup-directional ones reinterpreted player-relative for the top-down arena):
##   chase, centipede, dash(diver), orbit(dragonfly), jump(octopus), jump_diag(spider), scatter(fly),
##   swarm_dive(bee/bug/swarm), shooter, sentinel, beamer, bomber(bombing-wanderer), missile, bomb,
##   dummy, boss_stub(elephant/chromeleon/metalfly). Uses the real enemy sprites (def "icon") when present,
##   falling back to placeholder shapes.

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const ICON_DRAW_SCALE := 2.6   # drawn sprite width = _radius × this (sprites read a bit bigger than the hit circle)
const RETURN_DIST := 900.0          # dive group re-aims at the player once it gets this far away (loops back)
const THROWN_BOMB_SPEED := 460.0    # bomber's thrown bombs travel this fast (straight, aimed at the player)
const THROWN_BOMB_RANGE := 1200.0   # a thrown bomb despawns after travelling this far (projectile, not an enemy)

# Fallbacks so the enemy is self-sufficient if configured without a def (e.g. manager.spawn_bomb).
const FALLBACK := {
	"chase": {"behavior": "chase", "hp": 30.0, "speed": 95.0, "size": 16.0, "contact": 6, "xp": 5, "shape": "diamond", "tint": Color(0.95, 0.35, 0.30)},
	"bomb":  {"behavior": "bomb",  "hp": 50.0, "speed": 120.0, "size": 18.0, "contact": 0, "explodes": true, "xp": 0, "shape": "circle", "tint": Color(0.9, 0.5, 0.2)},
	"thrown_bomb": {"behavior": "thrown_bomb", "hp": 12.0, "speed": THROWN_BOMB_SPEED, "size": 13.0, "contact": 0, "explodes": true, "xp": 0, "shape": "circle", "tint": Color(1.0, 0.55, 0.2), "icon": "res://assets/enemies/bomb.png"},
}

var _type: String = "chase"
var behavior: String = "chase"
var hp_max: float = 30.0
var hp: float = 30.0
var armor: float = 0.0
var speed: float = 95.0
var _radius: float = 16.0
var contact_damage: int = 6
var contact_explodes: bool = false
var xp: int = 5
var _color: Color = Color(0.95, 0.35, 0.30)
var shape_kind: String = "diamond"
var _icon: String = ""
var _tex: Texture2D = null
var _frames: Array = []
var _delays: Array = []
var _anim_acc: float = 0.0
var _anim_frame: int = 0
var _draw_size: Vector2 = Vector2.ZERO

var _mgr: Node = null
var _target: Node2D = null
var _flash: float = 0.0
var _dead: bool = false
# behavior state
var _t: float = 0.0
var _phase: int = 0
var _timer: float = 0.0
var _fire_t: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _orbit_r: float = 180.0
var _orbit_ang: float = 0.0
var _scatter_target: Vector2 = Vector2.ZERO
var _init_done: bool = false
var _beam_on: bool = false
var _beam_dir: Vector2 = Vector2.RIGHT

## Configure from the director's enemy table (or a fallback). Call before add_child.
func configure(type_id: String, mgr: Node, def: Dictionary = {}) -> void:
	_type = type_id
	_mgr = mgr
	var d: Dictionary = def if not def.is_empty() else FALLBACK.get(type_id, FALLBACK["chase"])
	behavior         = String(d.get("behavior", "chase"))
	hp_max           = float(d.get("hp", 30.0))
	hp               = hp_max
	armor            = float(d.get("armor", 0.0))
	speed            = float(d.get("speed", 95.0))
	_radius          = float(d.get("size", 16.0))
	contact_damage   = int(d.get("contact", 6))
	contact_explodes = bool(d.get("explodes", false))
	xp               = int(d.get("xp", 5))
	_color           = d.get("tint", Color(0.95, 0.35, 0.30))
	shape_kind       = String(d.get("shape", "diamond"))
	_icon            = String(d.get("icon", ""))

func _ready() -> void:
	add_to_group("arena_enemy")
	add_to_group("normal_enemy")
	collision_layer = 0
	collision_mask = 0
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_target = get_tree().get_first_node_in_group("player")
	z_index = 1
	_load_icon()

## Load the sprite (PNG or animated GIF via GifLoader) and compute the drawn size from its aspect ratio.
func _load_icon() -> void:
	if _icon == "":
		return
	if _icon.ends_with(".gif"):
		var g := GifLoader.load_gif(_icon)
		if g != null and g.has_meta("gif_frames"):
			_frames = g.get_meta("gif_frames")
			_delays = g.get_meta("gif_delays") if g.has_meta("gif_delays") else []
			_tex = _frames[0] as Texture2D if not _frames.is_empty() else g
		else:
			_tex = g
	else:
		_tex = load(_icon) as Texture2D
	if _tex != null:
		var ts := _tex.get_size()
		var w := _radius * ICON_DRAW_SCALE
		var h := w * (ts.y / ts.x) if ts.x > 0.0 else w
		_draw_size = Vector2(w, h)

# ── Universal damage contract ──────────────────────────────────────────────────
func take_damage(amount: float) -> void:
	if _dead:
		return
	var dr := 0.0
	if GameManager.has_method("armor_damage_reduction"):
		dr = GameManager.armor_damage_reduction(armor)
	hp -= amount * (1.0 - dr)
	_flash = 0.12
	queue_redraw()
	if hp <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	if xp > 0 and GameManager.has_method("add_xp"):
		GameManager.add_xp(xp)
	queue_free()

func _player_pos() -> Vector2:
	if _target != null and is_instance_valid(_target):
		return _target.global_position
	_target = get_tree().get_first_node_in_group("player")
	return _target.global_position if _target != null else global_position

# ── Per-frame ───────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
		if _target == null:
			return
	_t += delta
	if not _init_done:
		_init_behavior()
		_init_done = true
	_tick_behavior(delta)
	if not _frames.is_empty():
		_anim_acc += delta
		var fd: float = float(_delays[_anim_frame]) if _anim_frame < _delays.size() else 0.1
		if _anim_acc >= fd:
			_anim_acc -= fd
			_anim_frame = (_anim_frame + 1) % _frames.size()
			_tex = _frames[_anim_frame] as Texture2D
			queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()
	_check_contact()

func _init_behavior() -> void:
	var to := _player_pos() - global_position
	_aim = to.normalized() if to.length() > 0.01 else Vector2.UP
	match behavior:
		"orbit":
			_orbit_r = global_position.distance_to(_player_pos())
			_orbit_ang = (global_position - _player_pos()).angle()
		"scatter", "bomber":
			_scatter_target = _player_pos() + _rand_offset(_view().length() * 0.35)

func _tick_behavior(delta: float) -> void:
	var pp := _player_pos()
	var to := pp - global_position
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector2.UP
	match behavior:
		"chase", "boss_stub":
			velocity = dir * speed
			move_and_slide()
		"centipede":
			_spin += TAU / 3.0 * delta
			velocity = dir * speed
			move_and_slide()
			queue_redraw()
		"dash":   # diver — dive along the captured aim; once it flies off-view, re-aim and dive back
			if dist > RETURN_DIST:
				_aim = dir
			velocity = _aim * speed
			move_and_slide()
		"orbit":  # dragonfly — orbit + tighten, then dive (loops back when it overshoots off-view)
			if _phase == 0:
				_orbit_ang += (speed / maxf(20.0, _orbit_r)) * delta
				_orbit_r = maxf(28.0, _orbit_r - 28.0 * delta)
				global_position = pp + Vector2(cos(_orbit_ang), sin(_orbit_ang)) * _orbit_r
				if _orbit_r <= 32.0:
					_phase = 1
					_aim = dir
			else:
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * (speed * 1.7)
				move_and_slide()
		"jump":   # octopus — wait, then leap toward the player, repeat
			_jump_tick(delta, dir, false)
		"jump_diag":   # spider — leap along the nearest 45° diagonal
			_jump_tick(delta, dir, true)
		"scatter":   # fly — wander to random points around the player
			if global_position.distance_to(_scatter_target) < 24.0 or _t - _timer > 1.0:
				_scatter_target = pp + _rand_offset(_view().length() * 0.35)
				_timer = _t
			velocity = (_scatter_target - global_position).normalized() * speed
			move_and_slide()
		"swarm_dive":   # bee/bug/swarm — drift toward the player, pause, then dive through
			if _phase == 0:
				if _t < 1.2:
					velocity = dir * speed * 0.6
					move_and_slide()
				else:
					_phase = 1
					_aim = dir
			else:
				if dist > RETURN_DIST:
					_aim = dir
				velocity = _aim * speed * 1.6
				move_and_slide()
		"shooter":
			_standoff(dist, dir, 340.0)
			if _fire_ready(1.0):
				_mgr.spawn_bullet(global_position, dir * 280.0, 5)
		"sentinel":   # hold, fire a fan TOWARD the player
			_standoff(dist, dir, 420.0)
			if _fire_ready(2.0):
				var base := dir.angle()
				for k in 5:
					var a := base + deg_to_rad(lerpf(-24.0, 24.0, float(k) / 4.0))
					_mgr.spawn_bullet(global_position, Vector2(cos(a), sin(a)) * 260.0, 5)
		"beamer":
			_standoff(dist, dir, 380.0)
			_beamer_tick(delta, dir)
		"bomber":   # bombing-wanderer — roam near the player, drop bombs
			if global_position.distance_to(_scatter_target) < 30.0 or _t - _timer > 1.5:
				_scatter_target = pp + _rand_offset(260.0)
				_timer = _t
			velocity = (_scatter_target - global_position).normalized() * speed
			move_and_slide()
			if _fire_ready(3.0) and _mgr != null and _mgr.has_method("throw_bomb"):
				_mgr.throw_bomb(global_position)   # fast bomb aimed straight at the player
		"missile":   # launcher — periodic spread burst at the player
			_standoff(dist, dir, 460.0)
			if _fire_ready(2.5):
				var ba := dir.angle()
				for k in 4:
					var a := ba + deg_to_rad(lerpf(-18.0, 18.0, float(k) / 3.0))
					_mgr.spawn_bullet(global_position, Vector2(cos(a), sin(a)) * 230.0, 8)
		"bomb":   # falls toward the player; explodes on contact/death
			velocity = dir * speed
			move_and_slide()
		"thrown_bomb":   # fast straight projectile aimed at the player; explodes on contact, fizzles at range
			velocity = _aim * speed
			move_and_slide()
			_orbit_r += speed * delta
			if _orbit_r >= THROWN_BOMB_RANGE:
				_die()
		"dummy":
			pass

## Octopus/spider shared leap engine.
func _jump_tick(delta: float, dir: Vector2, diagonal: bool) -> void:
	if _phase == 0:   # wait, then aim
		_timer += delta
		if _timer >= 1.0:
			_timer = 0.0
			_phase = 1
			var d := dir
			if diagonal:
				var a := (roundf(dir.angle() / (PI * 0.5) - 0.5) + 0.5) * (PI * 0.5)
				d = Vector2(cos(a), sin(a))
			_aim = d
			_orbit_r = 0.0   # reuse as jump-distance accumulator
	else:   # leap
		var step := speed * 2.2 * delta
		global_position += _aim * step
		_orbit_r += step
		if _orbit_r >= 200.0:
			_phase = 0

## Move to a standoff ring around the player (used by ranged enemies).
func _standoff(dist: float, dir: Vector2, want: float) -> void:
	if dist > want + 40.0:
		velocity = dir * speed
	elif dist < want - 40.0:
		velocity = -dir * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

func _fire_ready(interval: float) -> bool:
	if _t - _fire_t >= interval:
		_fire_t = _t
		return true
	return false

func _beamer_tick(delta: float, dir: Vector2) -> void:
	# IDLE 0.6 → CHARGE 1.0 → FIRE 3.0 → COOLDOWN 1.5, beam aimed at the player when it starts.
	_timer += delta
	match _phase:
		0:
			_beam_on = false
			if _timer >= 0.6:
				_phase = 1
				_timer = 0.0
		1:
			if _timer >= 1.0:
				_phase = 2
				_timer = 0.0
				_beam_dir = dir
				_beam_on = true
		2:
			if _timer >= 3.0:
				_phase = 3
				_timer = 0.0
				_beam_on = false
			else:
				var pp := _player_pos()
				var proj := (pp - global_position).dot(_beam_dir)
				if proj > 0.0:
					var closest := global_position + _beam_dir * proj
					if closest.distance_to(pp) <= 30.0 and fmod(_timer, 0.5) < delta:
						GameManager.ship_take_damage(5)
		3:
			if _timer >= 1.5:
				_phase = 0
				_timer = 0.0
	queue_redraw()

func _view() -> Vector2:
	if _mgr != null and _mgr.has_method("screen_size"):
		return _mgr.screen_size()
	return Vector2(1440, 780)

func _rand_offset(r: float) -> Vector2:
	var a := randf() * TAU
	return Vector2(cos(a), sin(a)) * randf_range(r * 0.4, r)

# ── Contact ─────────────────────────────────────────────────────────────────────
func _check_contact() -> void:
	if contact_damage <= 0 and not contact_explodes:
		return
	if global_position.distance_to(_player_pos()) <= 16.0 + _radius:
		if contact_damage > 0:
			GameManager.ship_take_damage(contact_damage)
		if contact_explodes:
			_on_contact_death()

func _on_contact_death() -> void:
	if (behavior == "bomb" or behavior == "thrown_bomb") and _mgr != null and _mgr.has_method("explode"):
		_mgr.explode(global_position, 100.0, 20, self)
	_die()

# ── Draw: placeholder shape + flash + HP bar ───────────────────────────────────
func _draw() -> void:
	var col := _color
	if _flash > 0.0:
		col = col.lerp(Color.WHITE, 0.7)
	if _tex != null:
		# Centipede spins; rotate only the sprite (reset transform before the HP bar).
		if _spin != 0.0:
			draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-_draw_size * 0.5, _draw_size), false)
		if _flash > 0.0:
			draw_texture_rect(_tex, Rect2(-_draw_size * 0.5, _draw_size), false, Color(1, 1, 1, 0.6))
		if _spin != 0.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_shape(_radius, col)
	if _beam_on:
		var end := _beam_dir * 2000.0
		draw_line(Vector2.ZERO, end, Color(1.0, 0.3, 0.3, 0.85), 8.0)
		draw_line(Vector2.ZERO, end, Color(1.0, 1.0, 1.0, 0.9), 3.0)
	if hp < hp_max:
		var ratio := clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
		var w := _radius * 2.0
		draw_rect(Rect2(-_radius, -_radius - 8.0, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-_radius, -_radius - 8.0, w * ratio, 3.0), Color(0.4, 0.95, 0.4))

func _draw_shape(r: float, col: Color) -> void:
	var pts: PackedVector2Array
	match shape_kind:
		"triangle":
			pts = PackedVector2Array([Vector2(0, -r), Vector2(-r * 0.87, r * 0.6), Vector2(r * 0.87, r * 0.6)])
		"square":
			draw_rect(Rect2(Vector2(-r, -r) * 0.8, Vector2(r, r) * 1.6), col)
			return
		"circle":
			draw_circle(Vector2.ZERO, r, col)
			return
		_:   # diamond (optionally spun, for centipede)
			pts = PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	if _spin != 0.0:
		var out := PackedVector2Array()
		for p: Vector2 in pts:
			out.append(p.rotated(_spin))
		pts = out
	draw_colored_polygon(pts, col)
