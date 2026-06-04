extends Control

## Phase 5 — equipped-weapon behaviour + visual effects.
##
## Lives INSIDE StreamScreen, so its local coordinates match the asteroid layer
## (get_asteroid_centers) and the mouse (get_local_mouse_position).
##
## Reads what's equipped from InventoryManager each frame:
##   Primary slot  → left-click fires toward the cursor.
##       fire_mode "repeat" (Gatling): hold to fire every cooldown_sec.
##       fire_mode "charge" (Gauss):   hold to charge up to cooldown_sec; a bar at
##           the bottom shows charge; release fires once, damage ∝ charge.
##   Secondary slot → fire_mode "aura" (Ionizing Field): while equipped, damages
##       every asteroid within radius_px every tick_interval_sec.
##
## Damage is routed through the "asteroid_main" group (asteroids own their HP).
## Any future enemy type can reuse the same damage_point / damage_area contract.

const BULLET_SPEED := 720.0
const GAUSS_SPEED := 700.0           # heavy lumpy ball — slower so you can see it plough through
const BULLET_HIT_RADIUS := 6.0
const HOMING_TURN := 6.0              # how fast homing missiles bend toward their target
const GAUSS_FULL_DIAMETER_CM := 2.0  # full-charge ball ≈ this physical size (approx; tweak freely)

var _gauss_full_diam_px: float = 76.0
var _ship: Control = null

# Primary trigger state
var _trigger_down := false
var _mouse_was_down := false   # for press/release edge detection via polling
var _primary_cd := 0.0   # time (s) until the primary weapon may fire again; ticks down every frame
var _charge := 0.0

# Secondary aura state
var _aura_acc := 0.0
var _aura_time := 0.0

# Transient FX (all in StreamScreen-local space)
var _bullets: Array = []   # {pos, vel, dmg, big, life}
var _impacts: Array = []   # {pos, age, max_age, radius, color}
var _arcs: Array = []      # {a, b, age, max_age}

# Beam state (Lasgun hitscan_beam / Plasma drill tether) — recomputed each frame while held
var _beam_active := false
var _beam_from := Vector2.ZERO
var _beam_to := Vector2.ZERO
var _beam_color := Color(1.0, 0.3, 0.3)
var _beam_width := 8.0

# Extra damageable targets registered by fight controllers (e.g. orb sub-bosses).
# Each entry: {get_rect: Callable → Rect2 (stream-local), on_hit: Callable(dmg:float)}
var _extra_targets: Array = []

# Provider for dynamic multi-targets (e.g. shielded bullets). fn() → Array[{rect,on_hit}]
var _multi_hit_provider: Callable = Callable()

func add_hit_target(get_rect: Callable, on_hit: Callable) -> void:
	_extra_targets.append({"get_rect": get_rect, "on_hit": on_hit})

func clear_extra_targets() -> void:
	_extra_targets.clear()

func set_multi_hit_provider(fn: Callable) -> void:
	_multi_hit_provider = fn

func clear_multi_hit_provider() -> void:
	_multi_hit_provider = Callable()

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Input is read by polling in _process (so firing works even when the click lands
	# on a sprite in a higher CanvasLayer, e.g. the boss). Stay transparent to mouse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_gauss_full_diam_px = clampf(_cm_to_px(GAUSS_FULL_DIAMETER_CM), 40.0, 120.0)
	add_to_group("weapon_system")

# ── Input ─────────────────────────────────────────────────────────────────────

func _begin_trigger() -> void:
	var def := _primary_def()
	if def.is_empty():
		return
	_trigger_down = true
	if String(def.get("fire_mode", "")) == "charge":
		_charge = 0.0
	# Repeat/other weapons fire from _update_primary, which respects the shared
	# cooldown timer — so a click only fires if the cooldown has elapsed.

## Cursor inside the play area (this control fills StreamScreen). Clicks on side
## panels / the inventory button (outside the screen) won't start firing.
func _cursor_in_play() -> bool:
	var m := get_local_mouse_position()
	return m.x >= 0.0 and m.y >= 0.0 and m.x <= size.x and m.y <= size.y

func _release_trigger() -> void:
	if not _trigger_down:
		return
	var def := _primary_def()
	if not def.is_empty() and String(def.get("fire_mode", "")) == "charge" and _charge > 0.0:
		_fire_primary_charged(def, _charge)
	_trigger_down = false
	_charge = 0.0

# ── Frame update ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Primary cooldown ticks down in real time (not per-click), so rapid clicking
	# can't fire faster than the weapon's cooldown allows.
	_primary_cd = maxf(0.0, _primary_cd - delta)
	# Mouse trigger by polling (works regardless of what control is under the cursor).
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _inventory_open():
		_trigger_down = false
		_charge = 0.0
	else:
		if down and not _mouse_was_down and _cursor_in_play() and not _primary_def().is_empty():
			_begin_trigger()
		elif _trigger_down and not down:
			_release_trigger()
	_mouse_was_down = down

	_update_primary(delta)
	_update_secondary(delta)
	_update_bullets(delta)
	_tick_fx(_impacts, delta)
	_tick_fx(_arcs, delta)
	queue_redraw()

func _update_primary(delta: float) -> void:
	if not _trigger_down:
		_beam_active = false
		return
	var def := _primary_def()
	if def.is_empty():
		_trigger_down = false
		_beam_active = false
		return
	var mode := String(def.get("fire_mode", ""))
	if mode != "beam":
		_beam_active = false   # any non-beam weapon clears the beam visual
	if mode == "repeat":
		# Fire only when the shared cooldown has elapsed (covers both click and hold).
		if _primary_cd <= 0.0 and _fire_by_type(def):
			_primary_cd = maxf(0.02, get_weapon_stat(def, "cooldown_sec", 0.2))
	elif mode == "charge":
		var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 3.0)))
		_charge = minf(_charge + delta, maxc)
	elif mode == "beam":
		_update_beam(def)

func _update_secondary(delta: float) -> void:
	var def := _secondary_def()
	if def.is_empty() or String(def.get("fire_mode", "")) != "aura":
		return
	_aura_time += delta
	var interval: float = maxf(0.05, float(_stat(def, "tick_interval_sec", 0.25)))
	var radius: float = float(_stat(def, "radius_px", 140.0))
	var dmg: float = float(_stat(def, "damage_per_tick", 1.0))
	_aura_acc += delta
	while _aura_acc >= interval:
		_aura_acc -= interval
		_aura_tick(radius, dmg)

func _aura_tick(radius: float, dmg: float) -> void:
	var center := _ship_center()
	var ast := _ast()
	if ast != null and ast.has_method("damage_area"):
		var hits: Array = ast.damage_area(center, radius, dmg)
		for p: Vector2 in hits:
			_arcs.append({"a": center, "b": p, "age": 0.0, "max_age": 0.18})
	# Boss also takes aura damage if within range.
	var boss_rect := _boss_rect_local()
	if boss_rect.has_area() and _circle_hits_rect(center, radius, boss_rect):
		GameManager.take_boss_damage(int(dmg))
		_arcs.append({"a": center, "b": boss_rect.position + boss_rect.size * 0.5, "age": 0.0, "max_age": 0.18})

func _update_bullets(delta: float) -> void:
	var ast := _ast()
	var boss_rect := _boss_rect_local()
	var i: int = _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		# Homing: bend the velocity toward the nearest target, keeping speed constant.
		if b.get("homing", false):
			var tgt := _nearest_target(b["pos"])
			if tgt != Vector2.ZERO:
				var cur: Vector2 = b["vel"]
				var spd := cur.length()
				if spd > 0.01:
					var desired := (tgt - (b["pos"] as Vector2)).normalized() * spd
					var steer := cur.lerp(desired, clampf(HOMING_TURN * delta, 0.0, 1.0))
					if steer.length() > 0.01:
						b["vel"] = steer.normalized() * spd
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var pos: Vector2 = b["pos"]
		var big: bool = b["big"]
		var remove := false
		if big:
			# Piercing: spend damage equal to each rock's HP; leftover keeps flying.
			var r: float = _ball_radius(b)
			if boss_rect.has_area() and _circle_hits_rect(pos, maxf(r, 4.0), boss_rect):
				GameManager.take_boss_damage(int(b["dmg"]))
				_spawn_impact(pos, true)
				b["dmg"] = 0.0   # boss absorbs the whole ball
			else:
				for et: Dictionary in _extra_targets:
					var er: Rect2 = (et["get_rect"] as Callable).call()
					if er.has_area() and _circle_hits_rect(pos, maxf(r, 4.0), er):
						(et["on_hit"] as Callable).call(float(b["dmg"]))
						_spawn_impact(pos, true)
						b["dmg"] = 0.0
						break
			if ast != null and ast.has_method("pierce_at") and float(b["dmg"]) > 0.0:
				var absorbed: float = ast.pierce_at(pos, maxf(r, 4.0), float(b["dmg"]))
				if absorbed > 0.0:
					_spawn_impact(pos, true)
					b["dmg"] = float(b["dmg"]) - absorbed
			if float(b["dmg"]) <= 0.5:
				remove = true
		else:
			if ast != null and ast.has_method("damage_point") and ast.damage_point(pos, BULLET_HIT_RADIUS, float(b["dmg"])):
				_spawn_impact(pos, false)
				remove = true
			elif boss_rect.has_area() and boss_rect.has_point(pos):
				GameManager.take_boss_damage(int(b["dmg"]))
				_spawn_impact(pos, false)
				remove = true
			else:
				for et: Dictionary in _extra_targets:
					var er: Rect2 = (et["get_rect"] as Callable).call()
					if er.has_area() and er.has_point(pos):
						(et["on_hit"] as Callable).call(float(b["dmg"]))
						_spawn_impact(pos, false)
						remove = true
						break
				if not remove and _multi_hit_provider.is_valid():
					for mh: Dictionary in _multi_hit_provider.call():
						var mr: Rect2 = mh["rect"]
						if mr.has_area() and mr.has_point(pos):
							(mh["on_hit"] as Callable).call(float(b["dmg"]))
							_spawn_impact(pos, false)
							remove = true
							break
		# Cone pellets: vanish once they've travelled their max range.
		if not remove and b.has("max_dist"):
			b["travel"] = float(b.get("travel", 0.0)) + (b["vel"] as Vector2).length() * delta
			if float(b["travel"]) >= float(b["max_dist"]):
				remove = true
		var off: bool = pos.x < -48.0 or pos.x > size.x + 48.0 or pos.y < -48.0 or pos.y > size.y + 48.0
		if remove or off or float(b["life"]) > 4.0:
			_bullets.remove_at(i)
		i -= 1

func _tick_fx(arr: Array, delta: float) -> void:
	var i: int = arr.size() - 1
	while i >= 0:
		var e: Dictionary = arr[i]
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) >= float(e["max_age"]):
			arr.remove_at(i)
		i -= 1

# ── Firing ────────────────────────────────────────────────────────────────────

func _fire_primary(def: Dictionary) -> void:
	_spawn_bullet(float(get_weapon_stat(def, "damage", 1.0)), false)

## Data-driven fire dispatch: one shot of the weapon, branched on its fire_type.
## Returns false if the shot couldn't happen (e.g. not enough energy) so the
## caller stops spamming the cooldown loop this frame.
func _fire_by_type(def: Dictionary) -> bool:
	match String(def.get("fire_type", "projectile")):
		"homing":
			if not _spend_weapon_energy(def):
				return false
			_fire_homing(def)
		"cone":
			if not _spend_weapon_energy(def):
				return false
			_fire_cone(def)
		"chain":
			if not _spend_weapon_energy(def):
				return false
			_fire_chain(def)
		_:  # "projectile" and anything not yet implemented → a plain bullet
			_fire_primary(def)
	return true

## Energy consumption is OFF for now (user will re-enable later). Flip this to true
## to make weapons spend their "energy" stat per shot again.
const WEAPONS_USE_ENERGY := false

## Spend this weapon's per-shot energy (stat "energy"); true if paid (or free).
func _spend_weapon_energy(def: Dictionary) -> bool:
	if not WEAPONS_USE_ENERGY:
		return true
	var cost := get_weapon_stat(def, "energy", 0.0)
	if cost <= 0.0:
		return true
	return GameManager.try_spend_energy(cost)

func _fire_homing(def: Dictionary) -> void:
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var muzzle := _muzzle()
	var tgt := _nearest_target(muzzle)
	var dir := (tgt - muzzle) if tgt != Vector2.ZERO else (get_local_mouse_position() - muzzle)
	if dir.length() < 0.01:
		dir = Vector2.UP
	dir = dir.normalized()
	_bullets.append({
		"pos": muzzle, "vel": dir * BULLET_SPEED, "dmg": dmg, "big": false,
		"life": 0.0, "dmg_ref": dmg, "homing": true,
	})
	_spawn_impact(muzzle, false)

func _fire_cone(def: Dictionary) -> void:
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var pellets := int(get_weapon_stat(def, "pellets", 5.0))
	var spread := deg_to_rad(get_weapon_stat(def, "spread_deg", 30.0))
	var rng := get_weapon_stat(def, "range_px", 180.0)
	var muzzle := _muzzle()
	var aim := get_local_mouse_position() - muzzle
	if aim.length() < 0.01:
		aim = Vector2.UP
	var base := aim.angle()
	for i in maxi(1, pellets):
		var t := 0.0 if pellets <= 1 else (float(i) / float(pellets - 1) - 0.5)
		var ang := base + t * spread
		var dir := Vector2(cos(ang), sin(ang))
		_bullets.append({
			"pos": muzzle, "vel": dir * BULLET_SPEED, "dmg": dmg, "big": false,
			"life": 0.0, "dmg_ref": dmg, "max_dist": rng, "travel": 0.0,
		})
	_spawn_impact(muzzle, false)

## Nearest live target's center in this control's local space (asteroids, then the
## boss, then registered sub-boss targets). Vector2.ZERO if there is nothing.
func _nearest_target(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var ast := _ast()
	if ast != null and ast.has_method("get_asteroid_centers"):
		for c: Vector2 in ast.get_asteroid_centers():
			var d := from.distance_to(c)
			if d < best_d:
				best_d = d; best = c
	var br := _boss_rect_local()
	if br.has_area():
		var bc := br.position + br.size * 0.5
		var d := from.distance_to(bc)
		if d < best_d:
			best_d = d; best = bc
	for et: Dictionary in _extra_targets:
		var er: Rect2 = (et["get_rect"] as Callable).call()
		if er.has_area():
			var ec := er.position + er.size * 0.5
			var d := from.distance_to(ec)
			if d < best_d:
				best_d = d; best = ec
	return best

# ── Shared targeting (beam / tether / chain) ──────────────────────────────────

## Every live target as {center, radius, kind, on_hit}. kind ∈ rock/boss/extra/multi.
func _collect_targets() -> Array:
	var out: Array = []
	var ast := _ast()
	if ast != null and ast.has_method("get_asteroid_centers"):
		var centers: Array = ast.get_asteroid_centers()
		var sizes: Array = ast.get_asteroid_sizes() if ast.has_method("get_asteroid_sizes") else []
		for i in centers.size():
			var rad := 16.0
			if i < sizes.size():
				rad = maxf((sizes[i] as Vector2).x, (sizes[i] as Vector2).y) * 0.5
			out.append({"center": centers[i], "radius": rad, "kind": "rock", "on_hit": Callable()})
	var br := _boss_rect_local()
	if br.has_area():
		out.append({"center": br.position + br.size * 0.5, "radius": maxf(br.size.x, br.size.y) * 0.5,
			"kind": "boss", "on_hit": Callable()})
	for et: Dictionary in _extra_targets:
		var er: Rect2 = (et["get_rect"] as Callable).call()
		if er.has_area():
			out.append({"center": er.position + er.size * 0.5, "radius": maxf(er.size.x, er.size.y) * 0.5,
				"kind": "extra", "on_hit": et["on_hit"]})
	if _multi_hit_provider.is_valid():
		for mh: Dictionary in _multi_hit_provider.call():
			var mr: Rect2 = mh["rect"]
			if mr.has_area():
				out.append({"center": mr.position + mr.size * 0.5, "radius": maxf(mr.size.x, mr.size.y) * 0.5,
					"kind": "multi", "on_hit": mh["on_hit"]})
	return out

## Apply damage to one target dict (routes by kind).
func _apply_to(t: Dictionary, dmg: float) -> void:
	match String(t.get("kind", "")):
		"rock":
			var ast := _ast()
			if ast != null and ast.has_method("damage_point"):
				ast.damage_point(t["center"], BULLET_HIT_RADIUS, dmg)
		"boss":
			GameManager.take_boss_damage(int(dmg))
		_:
			var oh: Callable = t.get("on_hit", Callable())
			if oh.is_valid():
				oh.call(dmg)

## Nearest target dict to `from` within `max_dist`, skipping any whose center is in
## `exclude`. Returns {} if none.
func _nearest_target_dict(from: Vector2, targets: Array, max_dist: float, exclude: Array = []) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for t: Dictionary in targets:
		var c: Vector2 = t["center"]
		if exclude.has(c):
			continue
		var d := from.distance_to(c)
		if d <= best_d + float(t["radius"]) and d < best_d:
			best_d = d; best = t
	return best

## First target a ray (origin, dir) hits within max_len; {} if none.
func _beam_first_hit(origin: Vector2, dir: Vector2, max_len: float, width: float) -> Dictionary:
	var best := {}
	var best_along := max_len
	for t: Dictionary in _collect_targets():
		var to_t: Vector2 = (t["center"] as Vector2) - origin
		var along := to_t.dot(dir)
		if along < 0.0 or along > max_len:
			continue
		var perp := (to_t - dir * along).length()
		if perp <= width + float(t["radius"]) and along < best_along:
			best_along = along; best = t
	return best

# ── Beam weapons (hitscan_beam / tether) ──────────────────────────────────────

func _update_beam(def: Dictionary) -> void:
	var ft := String(def.get("fire_type", ""))
	var muzzle := _muzzle()
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var do_tick := _primary_cd <= 0.0
	var interval := maxf(0.02, get_weapon_stat(def, "tick_interval_sec", 0.15))
	_beam_width = get_weapon_stat(def, "beam_width", 8.0)
	if ft == "tether":
		var rng := get_weapon_stat(def, "range_px", 170.0)
		var anchor := _nearest_target_dict(muzzle, _collect_targets(), rng)
		if anchor.is_empty():
			_beam_active = false
			return
		_beam_active = true
		_beam_color = Color(0.4, 1.0, 0.85)
		_beam_from = muzzle
		_beam_to = anchor["center"]
		if do_tick and _spend_weapon_energy(def):
			_apply_to(anchor, dmg)
			_spawn_impact(_beam_to, false)
			_primary_cd = interval
	else:  # hitscan_beam
		var max_len := get_weapon_stat(def, "range_px", 760.0)
		var aim := get_local_mouse_position() - muzzle
		if aim.length() < 0.01:
			aim = Vector2.UP
		var dir := aim.normalized()
		var hit := _beam_first_hit(muzzle, dir, max_len, _beam_width * 0.5)
		_beam_active = true
		_beam_color = Color(1.0, 0.3, 0.3)
		_beam_from = muzzle
		_beam_to = (hit["center"] as Vector2) if not hit.is_empty() else muzzle + dir * max_len
		if do_tick and _spend_weapon_energy(def):
			if not hit.is_empty():
				_apply_to(hit, dmg)
				_spawn_impact(_beam_to, false)
			_primary_cd = interval

# ── Chain weapon (Arc) ────────────────────────────────────────────────────────

func _fire_chain(def: Dictionary) -> void:
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var jumps := int(get_weapon_stat(def, "chain_jumps", 4.0))
	var rng := get_weapon_stat(def, "chain_range_px", 200.0)
	var muzzle := _muzzle()
	var targets := _collect_targets()
	# First link: the target nearest the cursor.
	var cursor := get_local_mouse_position()
	var cur := _nearest_target_dict(cursor, targets, INF)
	if cur.is_empty():
		return
	var hit_centers: Array = []
	var prev := muzzle
	for _j in range(maxi(1, jumps)):
		if cur.is_empty():
			break
		var c: Vector2 = cur["center"]
		_apply_to(cur, dmg)
		_arcs.append({"a": prev, "b": c, "age": 0.0, "max_age": 0.22})
		hit_centers.append(c)
		_spawn_impact(c, false)
		prev = c
		cur = _nearest_target_dict(c, targets, rng, hit_centers)

func _fire_primary_charged(def: Dictionary, charge: float) -> void:
	var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 1.5)))
	var max_dmg: float = float(_stat(def, "damage", 1.0))
	var dmg: float = max_dmg * clampf(charge / maxc, 0.0, 1.0)
	_spawn_bullet(dmg, true, max_dmg)

func _spawn_bullet(dmg: float, big: bool, dmg_ref: float = 0.0) -> void:
	var muzzle := _muzzle()
	var dir := (get_local_mouse_position() - muzzle)
	if dir.length() < 0.01:
		dir = Vector2.UP
	dir = dir.normalized()
	var b: Dictionary = {
		"pos": muzzle,
		"vel": dir * (GAUSS_SPEED if big else BULLET_SPEED),
		"dmg": dmg,
		"big": big,
		"life": 0.0,
		"dmg_ref": dmg_ref if dmg_ref > 0.0 else dmg,   # damage that maps to "full size"
	}
	if big:
		# Fixed per-ball lumpiness so the metal ball keeps its shape as it shrinks.
		var lumps: Array = []
		for _k in range(12):
			lumps.append(randf_range(0.82, 1.14))
		b["lumps"] = lumps
	_bullets.append(b)
	_spawn_impact(muzzle, big)   # muzzle flash

## Visual + hit radius of a gauss ball: proportional to its remaining damage.
func _ball_radius(b: Dictionary) -> float:
	var frac: float = clampf(float(b["dmg"]) / maxf(1.0, float(b["dmg_ref"])), 0.0, 1.0)
	return _gauss_full_diam_px * 0.5 * frac

func _spawn_impact(pos: Vector2, big: bool) -> void:
	_impacts.append({
		"pos": pos,
		"age": 0.0,
		"max_age": 0.32 if big else 0.20,
		"radius": 30.0 if big else 12.0,
	})

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Secondary aura ring
	var sdef := _secondary_def()
	if not sdef.is_empty() and String(sdef.get("fire_mode", "")) == "aura":
		var c := _ship_center()
		var r: float = float(_stat(sdef, "radius_px", 140.0))
		var pulse: float = 0.5 + 0.5 * sin(_aura_time * 6.0)
		draw_circle(c, r, Color(0.3, 0.7, 1.0, 0.05 + 0.05 * pulse))
		_draw_ring(c, r, Color(0.5, 0.85, 1.0, 0.45 + 0.35 * pulse), 2.0)

	# Beam (Lasgun / Plasma drill) — wide translucent outer + bright inner line
	if _beam_active:
		draw_line(_beam_from, _beam_to, Color(_beam_color.r, _beam_color.g, _beam_color.b, 0.25), _beam_width)
		draw_line(_beam_from, _beam_to, Color(_beam_color.r, _beam_color.g, _beam_color.b, 0.95), maxf(2.0, _beam_width * 0.35))
		draw_circle(_beam_to, _beam_width * 0.5, Color(1.0, 1.0, 1.0, 0.7))

	# Lightning arcs
	for a: Dictionary in _arcs:
		var t: float = clampf(1.0 - float(a["age"]) / float(a["max_age"]), 0.0, 1.0)
		_draw_lightning(a["a"], a["b"], Color(0.75, 0.9, 1.0, t))

	# Bullets
	for b: Dictionary in _bullets:
		if b["big"]:
			_draw_metal_ball(b)
		else:
			var p: Vector2 = b["pos"]
			var col := Color(1.0, 0.95, 0.55)
			var tail: Vector2 = p - (b["vel"] as Vector2).normalized() * 10.0
			draw_line(tail, p, col, 2.5)
			draw_circle(p, 2.5, col)

	# Impacts (expanding fading ring)
	for im: Dictionary in _impacts:
		var f: float = float(im["age"]) / float(im["max_age"])
		_draw_ring(im["pos"], float(im["radius"]) * f, Color(1.0, 0.85, 0.4, clampf(1.0 - f, 0.0, 1.0)), 2.0)

	# Asteroid HP bars
	var ast := _ast()
	if ast != null and ast.has_method("get_damaged_asteroids"):
		for d: Dictionary in ast.get_damaged_asteroids():
			var p2: Vector2 = d["pos"]
			var w: float = maxf(float(d["w"]), 16.0)
			var frac: float = d["frac"]
			var bx: float = p2.x - w * 0.5
			var by: float = p2.y - float(d["w"]) * 0.5 - 8.0
			draw_rect(Rect2(bx, by, w, 3.0), Color(0, 0, 0, 0.6), true)
			draw_rect(Rect2(bx, by, w * frac, 3.0),
				Color(0.4, 0.9, 0.4).lerp(Color(0.9, 0.3, 0.3), 1.0 - frac), true)

	# Charge bar (Gauss)
	var pdef := _primary_def()
	if _trigger_down and not pdef.is_empty() and String(pdef.get("fire_mode", "")) == "charge":
		_draw_charge_bar(pdef)

func _draw_metal_ball(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var r: float = _ball_radius(b)
	if r < 1.0:
		return
	var lumps: Array = b.get("lumps", [])
	var n: int = lumps.size()
	if n < 3:
		draw_circle(pos, r, Color(0.58, 0.60, 0.65))
		return
	var pts := PackedVector2Array()
	for k in range(n):
		var ang: float = TAU * float(k) / n
		var rr: float = r * float(lumps[k])
		pts.append(pos + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, Color(0.55, 0.57, 0.62))   # metal body
	var rim := pts
	rim.append(pts[0])
	draw_polyline(rim, Color(0.28, 0.30, 0.35), 2.0)      # dark rim
	draw_circle(pos - Vector2(r * 0.3, r * 0.35), maxf(r * 0.28, 1.0), Color(0.85, 0.88, 0.92, 0.8))  # highlight

func _draw_ring(center: Vector2, radius: float, col: Color, width: float) -> void:
	if radius <= 0.5:
		return
	draw_arc(center, radius, 0.0, TAU, 48, col, width)

func _draw_lightning(a: Vector2, b: Vector2, col: Color) -> void:
	var segs := 5
	var perp := (b - a).normalized().rotated(PI * 0.5)
	var prev := a
	for i in range(1, segs + 1):
		var base := a.lerp(b, float(i) / segs)
		if i < segs:
			base += perp * randf_range(-6.0, 6.0)
		draw_line(prev, base, col, 1.5)
		prev = base

func _draw_charge_bar(def: Dictionary) -> void:
	var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 3.0)))
	var frac: float = clampf(_charge / maxc, 0.0, 1.0)
	var bw: float = size.x * 0.4
	var bh := 12.0
	var x: float = (size.x - bw) * 0.5
	var y: float = size.y - 30.0
	draw_rect(Rect2(x, y, bw, bh), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(x, y, bw * frac, bh), Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.3, 0.2), frac), true)
	draw_rect(Rect2(x, y, bw, bh), Color(0.7, 0.8, 1.0, 0.85), false, 1.5)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Approximate physical-cm → pixels using the monitor DPI (best-effort; display
## scaling/stretch means it's only roughly cm). Falls back to 96 DPI.
func _cm_to_px(cm: float) -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

func _stat(def: Dictionary, key: String, fallback: float) -> float:
	var stats: Dictionary = def.get("stats", {})
	return float(stats.get(key, fallback))

## AFFIX HOOK — all firing code reads weapon stats through here. Today it just
## returns the base value; rolled affix bonuses (e.g. +% damage, -cooldown) will
## be applied at this single point later. Do not scatter stat math elsewhere.
func get_weapon_stat(def: Dictionary, key: String, fallback: float) -> float:
	return _stat(def, key, fallback)

func _primary_def() -> Dictionary:
	return _equipped_def("primary_weapon")

func _secondary_def() -> Dictionary:
	return _equipped_def("secondary_weapon")

func _equipped_def(slot: String) -> Dictionary:
	var uid: int = InventoryManager.equipped_uid(slot)
	if uid == -1:
		return {}
	var item: Dictionary = InventoryManager.get_item(uid)
	return InventoryManager.get_def(String(item.get("def", "")))

func _ast() -> Node:
	return get_tree().get_first_node_in_group("asteroid_main")

## The boss's hit rect in this layer's local space (empty Rect2 if no live boss).
## get_boss_hit_rect() is global; this control sits at StreamScreen's origin.
func _boss_rect_local() -> Rect2:
	if GameManager.boss_max_hp <= 0:
		return Rect2()
	var bf := get_tree().get_first_node_in_group("boss_fight")
	if bf == null or not bf.has_method("get_boss_hit_rect"):
		return Rect2()
	var r: Rect2 = bf.get_boss_hit_rect()
	if not r.has_area():
		return Rect2()
	return Rect2(r.position - global_position, r.size)

func _circle_hits_rect(c: Vector2, radius: float, rect: Rect2) -> bool:
	var nearest := Vector2(
		clampf(c.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(c.y, rect.position.y, rect.position.y + rect.size.y))
	return c.distance_to(nearest) <= radius

func _inventory_open() -> bool:
	var ui := get_tree().get_first_node_in_group("inventory_ui")
	return ui != null and ui.has_method("is_open") and ui.is_open()

func _ship_node() -> Control:
	if is_instance_valid(_ship):
		return _ship
	_ship = get_tree().get_first_node_in_group("ship_body") as Control
	return _ship

func _ship_center() -> Vector2:
	var s := _ship_node()
	if s == null:
		return Vector2(size.x * 0.5, size.y * 0.6)
	# Map through the ship's real transform so scale/pivot (0.5× during boss fights) are baked in.
	# This control sits at StreamScreen's origin, so global → local is a subtraction.
	return (s.get_global_transform() * (s.size * 0.5)) - global_position

func _muzzle() -> Vector2:
	var s := _ship_node()
	if s == null:
		return Vector2(size.x * 0.5, size.y * 0.6)
	# Top-center of the ship, through its real transform (handles the boss-fight 0.5× scale).
	return (s.get_global_transform() * Vector2(s.size.x * 0.5, 0.0)) - global_position
