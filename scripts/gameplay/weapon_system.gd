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
const GAUSS_FULL_DIAMETER_CM := 2.0  # full-charge ball ≈ this physical size (approx; tweak freely)

var _gauss_full_diam_px: float = 76.0
var _ship: Control = null

# Primary trigger state
var _trigger_down := false
var _repeat_acc := 0.0
var _charge := 0.0

# Secondary aura state
var _aura_acc := 0.0
var _aura_time := 0.0

# Transient FX (all in StreamScreen-local space)
var _bullets: Array = []   # {pos, vel, dmg, big, life}
var _impacts: Array = []   # {pos, age, max_age, radius, color}
var _arcs: Array = []      # {a, b, age, max_age}

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS   # fire on click but let asteroids/UI below still get it
	z_index = 50
	_gauss_full_diam_px = clampf(_cm_to_px(GAUSS_FULL_DIAMETER_CM), 40.0, 120.0)

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Press started inside the play area and wasn't eaten by UI above → begin firing.
	var def := _primary_def()
	if def.is_empty() or _inventory_open():
		return
	_trigger_down = true
	if String(def.get("fire_mode", "")) == "charge":
		_charge = 0.0
	else:
		_fire_primary(def)   # repeat weapons fire immediately, then on cooldown
		_repeat_acc = 0.0

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
	# Robust release: covers the button being let go outside this control.
	if _trigger_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_release_trigger()
	if _inventory_open():
		_trigger_down = false
		_charge = 0.0

	_update_primary(delta)
	_update_secondary(delta)
	_update_bullets(delta)
	_tick_fx(_impacts, delta)
	_tick_fx(_arcs, delta)
	queue_redraw()

func _update_primary(delta: float) -> void:
	if not _trigger_down:
		return
	var def := _primary_def()
	if def.is_empty():
		_trigger_down = false
		return
	var mode := String(def.get("fire_mode", ""))
	if mode == "repeat":
		var cd: float = maxf(0.02, float(_stat(def, "cooldown_sec", 0.2)))
		_repeat_acc += delta
		while _repeat_acc >= cd:
			_repeat_acc -= cd
			_fire_primary(def)
	elif mode == "charge":
		var maxc: float = maxf(0.1, float(_stat(def, "cooldown_sec", 3.0)))
		_charge = minf(_charge + delta, maxc)

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
			elif ast != null and ast.has_method("pierce_at"):
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
	_spawn_bullet(float(_stat(def, "damage", 1.0)), false)

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
	# This control sits at StreamScreen's origin, so global → local is a subtraction.
	return (s.global_position + s.size * 0.5) - global_position

func _muzzle() -> Vector2:
	var s := _ship_node()
	if s == null:
		return Vector2(size.x * 0.5, size.y * 0.6)
	return (s.global_position + Vector2(s.size.x * 0.5, 0.0)) - global_position
