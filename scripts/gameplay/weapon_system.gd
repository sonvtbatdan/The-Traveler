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
const HOMING_TURN := 6.0              # (legacy) how fast old homing bullets bent toward their target
# Homing Missile — cinematic 4-phase launch: eject → curve up → hang & aim → accelerate → strike+explode.
# Phase durations (s):
const MISSILE_EJECT_T := 0.2         # phase 1: pop off the back/underside
const MISSILE_CURVE_T := 0.4         # phase 2: swoop upward (ease-out)
const MISSILE_HANG_T  := 0.6         # phase 3: hover & rotate to lock on (longer = more dramatic)
# Shape of the launch:
const MISSILE_EJECT_DIST := 85.0     # how far it pops out during eject (wider peel-out)
const MISSILE_ARC_WIDTH := 95.0      # how far out to the side the swoop/hang point sits
const MISSILE_ARC_HEIGHT := 72.0     # height of the top-of-arc / hang point above the ship
const MISSILE_FACE_TURN := 14.0      # how fast the nose rotates to match travel / lock target
# Strike (phase 4):
const MISSILE_SEEK_START := 40.0     # speed at the start of the strike (slow creep)
const MISSILE_ACCEL := 900.0         # base acceleration toward the target
const MISSILE_ACCEL_RAMP := 9.0      # acceleration grows ×this per second → slow start, hard whip
const MISSILE_SPEED := 1400.0        # max strike speed
const MISSILE_EXPLODE_DIST := 14.0   # "touched the cursor"
const MISSILE_AOE_RADIUS := 44.0
const MISSILE_MAX_LIFE := 4.0

# ── Lasgun BEAM look (tunable — core stays white, colour lives in the glow) ───
const BEAM_GLOW_COLOR   := Color(0.45, 0.7, 1.0)  # cool blue (the haze/inner-glow colour)
const BEAM_CORE_COLOR   := Color(1.0, 1.0, 1.0)   # pure white core (always)
const BEAM_CORE_FRAC    := 0.10   # core width  = this × beam width (thin & sharp)
const BEAM_INNER_FRAC   := 0.20   # inner glow width (−50%)
const BEAM_HAZE_FRAC    := 0.75   # outer haze width (−50%)
const BEAM_INNER_ALPHA  := 0.50   # inner glow opacity
const BEAM_HAZE_ALPHA   := 0.16   # outer haze opacity (kept low; additive stacks it)
const BEAM_FLICKER      := 0.12   # brightness shimmer amount (0 = steady)
const BEAM_FLICKER_SPEED:= 28.0   # shimmer speed

# ── Stylized-laser layers (each animates at its own rate → feels alive) ────────
# Wobble / distortion (energy turbulence rippling down the beam)
const BEAM_WOBBLE_AMP    := 4.0    # perpendicular ripple amplitude (px); 0 = perfectly straight
const BEAM_WOBBLE_FREQ   := 0.05   # ripples per px along the beam
const BEAM_WOBBLE_SPEED  := 7.0    # how fast the ripple scrolls down the beam
# Scrolling energy pulses (bright dashes running gun→impact)
const BEAM_PULSE_COUNT   := 5
const BEAM_PULSE_SPEED   := 620.0  # px/s
const BEAM_PULSE_LEN     := 46.0   # length of each pulse streak (px)
# Electric / lightning crackle (subtle, fast flicker)
const BEAM_ELEC_INTENSITY:= 0.5    # 0..1 opacity (0 = off)
const BEAM_ELEC_SEGMENTS := 9
const BEAM_ELEC_AMP      := 6.0    # jaggedness (px)
const BEAM_ELEC_SPEED    := 22.0   # re-jag / flicker rate per second
# Stretched particles streaming down the beam
const BEAM_PARTICLE_RATE := 26.0   # spawned per second
const BEAM_PARTICLE_SPEED:= 900.0  # px/s
const BEAM_PARTICLE_LEN  := 18.0   # streak length (px)
const BEAM_PARTICLE_LIFE := 0.6    # seconds
# Bright flash at the muzzle the instant the beam turns on
const BEAM_FIRE_FLASH_SIZE := 42.0 # radius (px)
const BEAM_FIRE_FLASH_TIME := 0.12 # seconds

# ── Lasgun IMPACT — cutting-torch / welding-arc burst (tunable) ───────────────
const FLARE_CORE_COLOR     := Color(1.0, 1.0, 1.0)    # blinding white-hot center
const FLARE_SPARK_COLOR    := Color(1.0, 0.55, 0.15)  # hot-orange sparks / debris
const FLARE_GLOW_COLOR     := Color(1.0, 0.35, 0.10)  # tight hot glow around the hit
const FLARE_CENTER_SIZE    := 4.0    # hard hot center radius (small & sharp)
const FLARE_GLOW_SIZE      := 16.0   # tight glow radius (hot, not a soft halo)
const FLARE_SPARKS         := 12     # spark streaks per frame (count jitters)
const FLARE_SPARK_LEN      := 34.0   # max streak length (randomized per spark)
const FLARE_SPARK_SPREAD   := 1.7    # cone half-angle (rad) around "back toward the gun"
const FLARE_SPARK_WIDTH    := 2.0    # streak thickness
# Flying molten debris flecks (persist + arc + die)
const FLARE_DEBRIS_RATE    := 40.0   # spawned per second
const FLARE_DEBRIS_SPEED   := 260.0  # px/s
const FLARE_DEBRIS_LIFE    := 0.35   # seconds
const FLARE_DEBRIS_GRAVITY := 600.0  # px/s² (arc downward)
const FLARE_DEBRIS_SIZE    := 2.5    # px
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

# Auto-fire toggle
var _auto_fire := false

# Transient FX (all in StreamScreen-local space)
var _bullets: Array = []   # {pos, vel, dmg, big, life}
var _missiles: Array = []  # Homing Missile choreography: {pos, vel, dmg, target, phase, angle, orbit_t, life}
var _impacts: Array = []   # {pos, age, max_age, radius, color}
var _arcs: Array = []      # {a, b, age, max_age}

# Additive draw layer for the beam glow + impact flare (light, not paint)
var _glow: Node2D = null
var _beam_hit := false     # true when the beam is touching something (draw the flare)
var _beam_time := 0.0      # accumulator for the beam flicker / flare shimmer
var _beam_particles: Array = []   # streaks streaming down the beam: {along, off, life}
var _beam_part_acc := 0.0  # particle spawn accumulator
var _beam_was_active := false   # edge-detect the moment the beam turns on (fire flash)
var _fire_flash_t := 0.0   # remaining fire-flash time
var _flare_debris: Array = []   # molten flecks off the hit: {pos, vel, life, max_life}
var _flare_debris_acc := 0.0

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

func set_auto_fire(enabled: bool) -> void:
	_auto_fire = enabled

func get_auto_fire() -> bool:
	return _auto_fire

func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Input is read by polling in _process (so firing works even when the click lands
	# on a sprite in a higher CanvasLayer, e.g. the boss). Stay transparent to mouse.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_gauss_full_diam_px = clampf(_cm_to_px(GAUSS_FULL_DIAMETER_CM), 40.0, 120.0)
	add_to_group("weapon_system")

	# Additive glow layer for the beam + impact flare (makes it read as light, not paint).
	_glow = Node2D.new()
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = gm
	_glow.z_as_relative = false
	_glow.z_index = z_index   # same depth as the rest of the weapon FX
	add_child(_glow)
	_glow.draw.connect(_draw_beam_fx)

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
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _auto_fire
	if _inventory_open():
		_trigger_down = false
		_charge = 0.0
	else:
		var can_fire := (down and not _mouse_was_down) or (_auto_fire and not _trigger_down)
		if can_fire and _cursor_in_play() and not _primary_def().is_empty():
			_begin_trigger()
		elif _trigger_down and not down:
			_release_trigger()
	_mouse_was_down = down

	_update_primary(delta)
	_update_secondary(delta)
	_update_bullets(delta)
	_update_missiles(delta)
	_tick_fx(_impacts, delta)
	_tick_fx(_arcs, delta)
	_beam_time += delta
	_tick_beam_fx(delta)
	if _glow != null:
		_glow.queue_redraw()   # additive beam glow + flare
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
		var bf := get_tree().get_first_node_in_group("chromeleon_fight")
		if bf != null and bf.has_method("flash_boss_hit"):
			bf.flash_boss_hit()
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
				var bf := get_tree().get_first_node_in_group("chromeleon_fight")
				if bf != null and bf.has_method("flash_boss_hit"):
					bf.flash_boss_hit()
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
				var bf := get_tree().get_first_node_in_group("chromeleon_fight")
				if bf != null and bf.has_method("flash_boss_hit"):
					bf.flash_boss_hit()
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
const WEAPONS_USE_ENERGY := false   # global master; individual weapons opt in via def "uses_energy"

## Spend this weapon's energy; true if paid (or free). Per-shot weapons spend the
## full "energy" stat; beam weapons list "energy" as a per-SECOND rate, so they
## spend this tick's share (energy × tick_interval).
func _spend_weapon_energy(def: Dictionary) -> bool:
	if not (WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false))):
		return true
	var cost := get_weapon_stat(def, "energy", 0.0)
	if String(def.get("fire_mode", "")) == "beam":
		cost *= maxf(0.02, get_weapon_stat(def, "tick_interval_sec", 0.15))
	if cost <= 0.0:
		return true
	return GameManager.try_spend_energy(cost)

func _fire_homing(def: Dictionary) -> void:
	# Cinematic launch: eject off the back → swoop up (ease-out) → hang & aim → rocket to cursor → explode.
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var ship_c := _ship_center()
	var nose := _muzzle() - ship_c
	if nose.length() < 0.01:
		nose = Vector2.UP
	nose = nose.normalized()
	var half_ship := maxf(_muzzle().distance_to(ship_c), 24.0)
	var down := -nose                                   # toward the back/underside
	var side := 1.0 if randf() < 0.5 else -1.0          # peel off to one side
	var p0 := ship_c + down * half_ship * 0.5           # spawn at the back/underside
	var eject_dir := (down * 0.5 + Vector2(side, 0.0) * 1.0).normalized()   # out & slightly down
	var p1 := p0 + eject_dir * MISSILE_EJECT_DIST       # eject end
	var p2 := ship_c + Vector2(side * MISSILE_ARC_WIDTH, -MISSILE_ARC_HEIGHT)  # top-of-arc / hang point
	var ctrl := Vector2(p2.x, p1.y)                     # bezier control → swoop out then up
	_missiles.append({
		"pos": p0, "vel": Vector2.ZERO, "dmg": dmg, "target": get_local_mouse_position(),
		"phase": "eject", "pt": 0.0, "speed": 0.0, "seek_t": 0.0, "life": 0.0, "facing": eject_dir.angle(),
		"p0": p0, "p1": p1, "p2": p2, "ctrl": ctrl,
	})
	_spawn_impact(p0, false)

func _qbezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + b * (2.0 * u * t) + c * (t * t)

func _update_missiles(delta: float) -> void:
	var i: int = _missiles.size() - 1
	while i >= 0:
		var m: Dictionary = _missiles[i]
		m["life"] = float(m["life"]) + delta
		var pos: Vector2 = m["pos"]
		var explode := false
		match String(m["phase"]):
			"eject":  # phase 1 — pop off the back/underside
				m["pt"] = float(m["pt"]) + delta
				var t := clampf(float(m["pt"]) / MISSILE_EJECT_T, 0.0, 1.0)
				var np: Vector2 = (m["p0"] as Vector2).lerp(m["p1"], t)
				m["vel"] = np - pos
				m["pos"] = np
				if float(m["pt"]) >= MISSILE_EJECT_T:
					m["phase"] = "curve"; m["pt"] = 0.0
			"curve":  # phase 2 — swoop upward, ease-out (slows at the top)
				m["pt"] = float(m["pt"]) + delta
				var t := clampf(float(m["pt"]) / MISSILE_CURVE_T, 0.0, 1.0)
				var te := 1.0 - pow(1.0 - t, 2.0)
				var np := _qbezier(m["p1"], m["ctrl"], m["p2"], te)
				m["vel"] = np - pos
				m["pos"] = np
				if float(m["pt"]) >= MISSILE_CURVE_T:
					m["phase"] = "hang"; m["pt"] = 0.0
			"hang":  # phase 3 — nearly stop, rotate to lock onto the cursor
				m["pt"] = float(m["pt"]) + delta
				var drift := -10.0 * clampf(float(m["pt"]) / MISSILE_HANG_T, 0.0, 1.0)
				m["pos"] = (m["p2"] as Vector2) + Vector2(0.0, drift)
				m["vel"] = Vector2.ZERO
				if float(m["pt"]) >= MISSILE_HANG_T:
					m["phase"] = "seek"; m["speed"] = MISSILE_SEEK_START; m["seek_t"] = 0.0
			_:  # phase 4 — accelerate (ease-in) to the cursor, explode on touch.
				# Acceleration grows over time → very slow creep, then a hard whip.
				m["seek_t"] = float(m["seek_t"]) + delta
				var accel := MISSILE_ACCEL * (1.0 + MISSILE_ACCEL_RAMP * float(m["seek_t"]))
				m["speed"] = minf(MISSILE_SPEED, float(m["speed"]) + accel * delta)
				var to_t: Vector2 = (m["target"] as Vector2) - pos
				var step := float(m["speed"]) * delta
				if to_t.length() <= maxf(step, MISSILE_EXPLODE_DIST):
					m["pos"] = m["target"]
					explode = true
				else:
					var dir := to_t.normalized()
					m["vel"] = dir * float(m["speed"])
					m["pos"] = pos + dir * step
		# Rotation: match travel during eject/curve/seek; lock onto the target during hang.
		var desired: float
		if String(m["phase"]) == "hang":
			desired = ((m["target"] as Vector2) - (m["pos"] as Vector2)).angle()
		else:
			var v: Vector2 = m["vel"]
			desired = v.angle() if v.length() > 0.5 else float(m["facing"])
		m["facing"] = lerp_angle(float(m["facing"]), desired, clampf(MISSILE_FACE_TURN * delta, 0.0, 1.0))
		if not explode and float(m["life"]) > MISSILE_MAX_LIFE:
			explode = true
		if explode:
			_missile_explode(m["pos"], float(m["dmg"]))
			_missiles.remove_at(i)
		else:
			_missiles[i] = m
		i -= 1

## AoE blast: damage every target whose center is within MISSILE_AOE_RADIUS.
func _missile_explode(pos: Vector2, dmg: float) -> void:
	for t: Dictionary in _collect_targets():
		if (t["center"] as Vector2).distance_to(pos) <= MISSILE_AOE_RADIUS + float(t["radius"]):
			_apply_to(t, dmg)
	_spawn_impact(pos, true)   # big flash

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

## First target a ray (origin, dir) hits within max_len. Returns {"target": <dict or {}>,
## "along": <distance along the ray to that target's center, or max_len if none>}.
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
	return {"target": best, "along": best_along}

# ── Beam weapons (hitscan_beam / tether) ──────────────────────────────────────

func _update_beam(def: Dictionary) -> void:
	var ft := String(def.get("fire_type", ""))
	var muzzle := _muzzle()
	var dmg := get_weapon_stat(def, "damage", 1.0)
	var do_tick := _primary_cd <= 0.0
	var interval := maxf(0.02, get_weapon_stat(def, "tick_interval_sec", 0.15))
	_beam_width = get_weapon_stat(def, "beam_width", 8.0)
	# Energy-gated beams cut out when the bar is empty (and resume as it regens).
	if (WEAPONS_USE_ENERGY or bool(def.get("uses_energy", false))) and GameManager.ship_energy <= 0.0:
		_beam_active = false
		return
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
		_beam_hit = true
		if do_tick and _spend_weapon_energy(def):
			_apply_to(anchor, dmg)
			_primary_cd = interval
	else:  # hitscan_beam
		var max_len := get_weapon_stat(def, "range_px", 760.0)
		var dir := Vector2.UP   # fire straight forward (ship faces up); never tilts toward targets
		var res := _beam_first_hit(muzzle, dir, max_len, _beam_width * 0.5)
		var hit: Dictionary = res["target"]
		_beam_active = true
		_beam_color = BEAM_GLOW_COLOR   # cool-blue glow (core stays white in _draw_beam_fx)
		_beam_from = muzzle
		_beam_hit = not hit.is_empty()
		if not hit.is_empty():
			# Terminate the (straight) beam at the contact point — the near edge of the
			# first obstacle along the ray — instead of bending to its center.
			var edge := maxf(0.0, float(res["along"]) - float(hit["radius"]))
			_beam_to = muzzle + dir * edge
		else:
			_beam_to = muzzle + dir * max_len
		if do_tick and _spend_weapon_energy(def):
			if not hit.is_empty():
				_apply_to(hit, dmg)
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

	# (Beam glow + impact flare are drawn additively in _draw_beam_fx on the _glow node.)

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

	# Homing missiles — big orange rounds, oriented to their facing (nose rotates per phase)
	for m: Dictionary in _missiles:
		var mp: Vector2 = m["pos"]
		var f := float(m["facing"])
		var fwd := Vector2(cos(f), sin(f))
		var sd := Vector2(-fwd.y, fwd.x)
		draw_line(mp - fwd * 12.0, mp - fwd * 32.0, Color(1.0, 0.7, 0.2, 0.7), 6.0)   # exhaust streak
		draw_colored_polygon(PackedVector2Array([
			mp + fwd * 16.0, mp - fwd * 11.0 + sd * 6.0, mp - fwd * 11.0 - sd * 6.0,
		]), Color(1.0, 0.5, 0.1))
		draw_circle(mp, 4.0, Color(1.0, 0.9, 0.5))

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

## Deterministic pseudo-random in -1..1 from two seeds (for the electric jag flicker).
func _pseudo(a: float, b: float) -> float:
	var v := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (v - floor(v)) * 2.0 - 1.0

## Per-frame beam FX bookkeeping (fire flash + streak particles). Visuals only.
func _tick_beam_fx(delta: float) -> void:
	# Muzzle flash the instant the beam turns on.
	if _beam_active and not _beam_was_active:
		_fire_flash_t = BEAM_FIRE_FLASH_TIME
	_beam_was_active = _beam_active
	_fire_flash_t = maxf(0.0, _fire_flash_t - delta)

	# Spawn + advance streak particles streaming gun → impact along the beam.
	var beam_len := _beam_from.distance_to(_beam_to)
	if _beam_active:
		_beam_part_acc += BEAM_PARTICLE_RATE * delta
		while _beam_part_acc >= 1.0:
			_beam_part_acc -= 1.0
			_beam_particles.append({
				"along": 0.0,
				"off": randf_range(-_beam_width * 0.35, _beam_width * 0.35),
				"life": 0.0,
			})
	var i := _beam_particles.size() - 1
	while i >= 0:
		var p: Dictionary = _beam_particles[i]
		p["along"] = float(p["along"]) + BEAM_PARTICLE_SPEED * delta
		p["life"] = float(p["life"]) + delta
		if float(p["along"]) > beam_len or float(p["life"]) > BEAM_PARTICLE_LIFE:
			_beam_particles.remove_at(i)
		else:
			_beam_particles[i] = p
		i -= 1

	# Molten debris flecks sprayed back toward the gun off the contact point.
	if _beam_active and _beam_hit:
		var bdir := _beam_to - _beam_from
		bdir = bdir.normalized() if bdir.length() > 0.001 else Vector2.UP
		var back_ang := (-bdir).angle()
		_flare_debris_acc += FLARE_DEBRIS_RATE * delta
		while _flare_debris_acc >= 1.0:
			_flare_debris_acc -= 1.0
			var ang := back_ang + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
			var spd := FLARE_DEBRIS_SPEED * randf_range(0.5, 1.0)
			_flare_debris.append({
				"pos": _beam_to, "vel": Vector2.from_angle(ang) * spd,
				"life": 0.0, "max_life": FLARE_DEBRIS_LIFE * randf_range(0.6, 1.0),
			})
	var di := _flare_debris.size() - 1
	while di >= 0:
		var fb: Dictionary = _flare_debris[di]
		fb["life"] = float(fb["life"]) + delta
		if float(fb["life"]) >= float(fb["max_life"]):
			_flare_debris.remove_at(di)
			di -= 1
			continue
		var v: Vector2 = fb["vel"]
		v.y += FLARE_DEBRIS_GRAVITY * delta   # arc down like molten flecks
		fb["vel"] = v
		fb["pos"] = (fb["pos"] as Vector2) + v * delta
		_flare_debris[di] = fb
		di -= 1

## Drawn on the ADDITIVE _glow node (blend = ADD) → reads as light, not paint.
func _draw_beam_fx() -> void:
	if _glow == null:
		return
	_draw_flare_debris()   # molten flecks (keep flying even after the beam stops)
	if not _beam_active:
		return
	var a := _beam_from
	var b := _beam_to
	var flick := 1.0 + sin(_beam_time * BEAM_FLICKER_SPEED) * BEAM_FLICKER   # subtle shimmer
	var w := _beam_width
	var g := _beam_color   # glow colour (blue for the Lasgun, teal for the tether)
	# Outer haze — stacked soft lines → smooth blue falloff, no hard edge
	_glow.draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * 0.4 * flick), w * BEAM_HAZE_FRAC * 1.8)
	_glow.draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * 0.7 * flick), w * BEAM_HAZE_FRAC * 1.25)
	_glow.draw_line(a, b, Color(g.r, g.g, g.b, BEAM_HAZE_ALPHA * flick),       w * BEAM_HAZE_FRAC)
	# Inner glow — glow colour blended halfway to white
	var iw := Color((g.r + 1.0) * 0.5, (g.g + 1.0) * 0.5, (g.b + 1.0) * 0.5, BEAM_INNER_ALPHA * flick)
	_glow.draw_line(a, b, iw, maxf(2.0, w * BEAM_INNER_FRAC))

	# Beam axis
	var seg := b - a
	var L := seg.length()
	var dir := (seg / L) if L > 0.001 else Vector2.UP
	var perp := Vector2(-dir.y, dir.x)

	# (1) Energy wobble layer — rippling bright polyline (heat-haze / turbulence)
	if BEAM_WOBBLE_AMP > 0.0 and L > 1.0:
		var wprev := a
		for s in range(1, 17):
			var alo := L * float(s) / 16.0
			var woff := sin(alo * BEAM_WOBBLE_FREQ - _beam_time * BEAM_WOBBLE_SPEED) * BEAM_WOBBLE_AMP
			var wpt := a + dir * alo + perp * woff
			_glow.draw_line(wprev, wpt, Color(g.r, g.g, g.b, 0.30 * flick), maxf(2.0, w * 0.16))
			wprev = wpt

	# (2) Scrolling energy pulses — bright dashes racing gun → impact
	if L > 1.0:
		for k in BEAM_PULSE_COUNT:
			var phase := fmod(_beam_time * BEAM_PULSE_SPEED + float(k) * (L / float(maxi(1, BEAM_PULSE_COUNT))), L)
			var pc := a + dir * phase
			var pt := pc - dir * minf(BEAM_PULSE_LEN, phase)
			_glow.draw_line(pt, pc, Color(1.0, 1.0, 1.0, 0.45 * flick), maxf(2.0, w * 0.22))

	# (3) Electric crackle — jagged polyline, fast flicker (re-jags ELEC_SPEED×/sec)
	if BEAM_ELEC_INTENSITY > 0.0 and L > 1.0:
		var eseed := floorf(_beam_time * BEAM_ELEC_SPEED)
		var ec := Color(0.75, 0.9, 1.0, BEAM_ELEC_INTENSITY * flick)
		var eprev := a
		for s in range(1, BEAM_ELEC_SEGMENTS + 1):
			var alo := L * float(s) / float(BEAM_ELEC_SEGMENTS)
			var eoff := 0.0
			if s < BEAM_ELEC_SEGMENTS:
				eoff = _pseudo(float(s), eseed) * BEAM_ELEC_AMP
			var ept := a + dir * alo + perp * eoff
			_glow.draw_line(eprev, ept, ec, 1.5)
			eprev = ept

	# Core — thin pure white, straight, on top
	_glow.draw_line(a, b, Color(BEAM_CORE_COLOR.r, BEAM_CORE_COLOR.g, BEAM_CORE_COLOR.b, flick), maxf(1.5, w * BEAM_CORE_FRAC))

	# (4) Stretched particles streaming down the beam
	for p: Dictionary in _beam_particles:
		var alo := float(p["along"])
		if alo > L:
			continue
		var ppos := a + dir * alo + perp * float(p["off"])
		var ptail := ppos - dir * BEAM_PARTICLE_LEN
		var pl := clampf(1.0 - float(p["life"]) / BEAM_PARTICLE_LIFE, 0.0, 1.0)
		_glow.draw_line(ptail, ppos, Color(1.0, 1.0, 1.0, 0.55 * pl), 2.0)

	# (5) Fire flash at the muzzle the instant the beam turns on
	if _fire_flash_t > 0.0:
		var ft := _fire_flash_t / BEAM_FIRE_FLASH_TIME   # 1 → 0
		var fr := BEAM_FIRE_FLASH_SIZE * (1.0 + (1.0 - ft) * 0.8)
		_glow.draw_circle(a, fr, Color(g.r, g.g, g.b, 0.25 * ft))
		_glow.draw_circle(a, fr * 0.4, Color(1.0, 1.0, 1.0, 0.7 * ft))

	if _beam_hit:
		_draw_flare(b, dir, flick)

## Cutting-torch / welding-arc burst at the contact point. `dir` = beam direction
## (sparks spray back toward the gun). Re-randomized every frame → crackles & alive.
func _draw_flare(at: Vector2, dir: Vector2, _flick: float) -> void:
	var back_ang := (-dir).angle()   # toward the gun
	# Tight hot glow (small & hot, not a soft halo)
	var gc := FLARE_GLOW_COLOR
	_glow.draw_circle(at, FLARE_GLOW_SIZE, Color(gc.r, gc.g, gc.b, 0.20))
	_glow.draw_circle(at, FLARE_GLOW_SIZE * 0.55, Color(gc.r, gc.g, gc.b, 0.35))
	# Chaotic spark spray — short streaks in a backward+outward cone, jittered each frame
	var n := maxi(1, FLARE_SPARKS + randi_range(-3, 3))
	var sc := FLARE_SPARK_COLOR
	for _i in n:
		var ang := back_ang + randf_range(-FLARE_SPARK_SPREAD, FLARE_SPARK_SPREAD)
		var d := Vector2.from_angle(ang)
		var perp := Vector2(-d.y, d.x)
		var ln := FLARE_SPARK_LEN * randf_range(0.35, 1.0)
		var tip := at + d * ln
		var br := randf_range(0.5, 1.0)   # per-spark brightness jitter
		_glow.draw_polygon(
			PackedVector2Array([at + perp * FLARE_SPARK_WIDTH * 0.5, at - perp * FLARE_SPARK_WIDTH * 0.5, tip]),
			PackedColorArray([
				Color(1.0, 0.85, 0.5, br),     # bright hot base
				Color(1.0, 0.85, 0.5, br),
				Color(sc.r, sc.g, sc.b, 0.0),  # fade to transparent tip
			]))
	# Hard hot center — tiny, blinding, brightness jitters every frame
	_glow.draw_circle(at, FLARE_CENTER_SIZE * randf_range(0.8, 1.2), Color(1.0, 1.0, 1.0, randf_range(0.7, 1.0)))
	_glow.draw_circle(at, FLARE_CENTER_SIZE * 0.45, Color(FLARE_CORE_COLOR.r, FLARE_CORE_COLOR.g, FLARE_CORE_COLOR.b, 1.0))

## Persistent molten flecks (drawn even after the beam stops, so they finish their arc).
func _draw_flare_debris() -> void:
	for fb: Dictionary in _flare_debris:
		var t := clampf(1.0 - float(fb["life"]) / float(fb["max_life"]), 0.0, 1.0)
		var p: Vector2 = fb["pos"]
		var v: Vector2 = fb["vel"]
		var tail := p - v.normalized() * FLARE_DEBRIS_SIZE * 2.2
		_glow.draw_line(tail, p, Color(1.0, 0.75, 0.35, 0.7 * t), maxf(1.0, FLARE_DEBRIS_SIZE * 0.7))
		_glow.draw_circle(p, FLARE_DEBRIS_SIZE * t, Color(1.0, 0.85, 0.5, t))

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
