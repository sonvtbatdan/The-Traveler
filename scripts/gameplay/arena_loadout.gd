extends Node2D
## Equipment-driven arena firing engine (Phase 1 of the roguelite overhaul). This is the bridge that
## makes the arena fire whatever the player has EQUIPPED in InventoryManager — one source of truth with
## the main scene. Each frame it resolves the primary_weapon + secondary_weapon slots through the shared
## WeaponStats resolver (so damage / cadence / affixes / attribute scaling are identical to weapon_system.gd)
## and auto-fires them in world-space, Vampire-Survivors style, toward the ship's facing / nearest enemy.
##
## It sits at the world origin, so _draw() coordinates ARE world coordinates. Visuals here are clean and
## functional (the bespoke shader VFX in arena_weapons.gd are a later polish pass); the point of Phase 1 is
## that every one of the 30 weapons fires correctly with the shared stat model. Run-card multipliers
## (GameManager.get_damage_mult / fire_rate / crit / group_damage_mult / kind_damage_mult) all fold in here.
##
## fire_mode  : repeat | charge | beam | channel | aura | orbital
## fire_type  : projectile | cone | homing | chain | radial | splash_melee | hitscan_beam | tether |
##              growing_zone | minion | orbital | parasite_blob | acid_cloud

const PROJ_SPEED       := 820.0    # px/s for standard bolts
const CHARGE_SPEED     := 640.0    # px/s for heavy charge orbs (slower, readable)
const PROJ_LIFETIME    := 1.6      # s
const PROJ_MAX_DIST    := 1500.0   # px
const BOLT_RADIUS      := 8.0      # bullet↔enemy hit padding (added to enemy hit_radius)
const BASE_CRIT_CHANCE := 0.10     # arena base crit before Lethality/crit cards (matches old arena_weapons)
const ENEMY_GROUP      := "arena_enemy"
const RUIN_GROUP       := "arena_ruin"

# Default fallbacks per stat key (used when a def omits one).
const DEF_COOLDOWN := 0.4
const CROSS_DEBUG_DRAW := false   # debug: draw the 4 X-arm wedge edges to verify the hitbox (visual is DynamicFire)
const LOADOUT_ENABLED := false    # System 1 (inventory-equipped weapon firing) disabled for now — see inventory_ui

var _player: Node2D = null
var _bullets: Array = []      # {pos, vel, life, start, dmg, crit, radius, col, pierce, hit, ricochet, rico_range, splash, splash_dmg, homing, max_life, max_dist}
var _chains: Array = []       # {pts, age, max_age, col}
var _slots: Dictionary = {}   # slot name → per-slot runtime context
var _drones: Dictionary = {}  # drone slot → {angle, cd, pos, dtype, active, col}
var _enemy_mgr: Node = null   # arena_enemy_manager (for the defend drone's bullet-push)
var _repair_acc: float = 0.0  # fractional HP accumulator for repair drones
var _crit_layer: CanvasLayer = null
var _crit_host: Control = null
var _cross_fx: DynamicFire = null   # pooled Red X fire-flash (recycled per shot to avoid recreating GPU particles)

func _ready() -> void:
	add_to_group("arena_loadout")
	_player = get_tree().get_first_node_in_group("player")
	for slot: String in ["primary_weapon", "secondary_weapon"]:
		_slots[slot] = {
			"cd": 0.0, "charge": 0.0, "beam_tick": 0.0,
			"beam_from": Vector2.ZERO, "beam_to": Vector2.ZERO, "beam_on": false, "beam_col": Color.WHITE, "beam_w": 8.0,
			"zone_on": false, "zone_pos": Vector2.ZERO, "zone_age": 0.0, "zone_tick": 0.0,
			"orb_ang": 0.0, "minions": [], "aura_tick": 0.0,
		}
	for slot: String in ["drone_1", "drone_2"]:
		_drones[slot] = {"angle": randf() * TAU, "cd": 0.0, "pos": Vector2.ZERO, "dtype": "", "active": false, "col": Color.WHITE}
	_crit_layer = CanvasLayer.new()
	_crit_layer.layer = 12
	add_child(_crit_layer)
	_crit_host = Control.new()
	_crit_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crit_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crit_layer.add_child(_crit_host)

## True when this engine is driving the primary slot (so arena_weapons.gd can stand down its default gun).
func has_primary_weapon() -> bool:
	if not LOADOUT_ENABLED:
		return false   # dormant → don't make arena_weapons stand down its default Gatling
	return not WeaponStats.resolve_def("primary_weapon").is_empty()

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	if not LOADOUT_ENABLED:
		return   # System 1 firing disabled — HUD-slot weapons (arena_weapons.gd) are the live system
	var enemy_visible := _has_enemy_on_screen()
	for slot: String in _slots.keys():
		var def := WeaponStats.resolve_def(slot)
		var ctx: Dictionary = _slots[slot]
		if def.is_empty() or not Array(def.get("tags", [])).has("weapon"):
			_quiet_slot(ctx)
			continue
		_tick_slot(ctx, def, delta, enemy_visible)
	_tick_drones(delta)
	_tick_bullets(delta)
	_tick_chains(delta)
	queue_redraw()

# ── Drones (drone_1 / drone_2 equip slots) ──────────────────────────────────────
func _tick_drones(delta: float) -> void:
	var total_luck := 0.0
	var idx := 0
	for slot: String in ["drone_1", "drone_2"]:
		var ctx: Dictionary = _drones[slot]
		var uid: int = InventoryManager.equipped_uid(slot)
		if uid == -1:
			ctx["active"] = false
			continue
		var def: Dictionary = InventoryManager.get_def(String(InventoryManager.get_item(uid).get("def", "")))
		if not Array(def.get("tags", [])).has("drone"):
			ctx["active"] = false
			continue
		ctx["active"] = true
		var dtype := String(def.get("stats", {}).get("drone_type", ""))
		ctx["dtype"] = dtype
		ctx["angle"] = fmod(float(ctx["angle"]) + delta * 1.9, TAU)
		var orbit_r := 56.0 + float(idx) * 20.0
		ctx["pos"] = _player.global_position + Vector2(cos(float(ctx["angle"])), sin(float(ctx["angle"]))) * orbit_r
		match dtype:
			"combat":  _drone_combat(ctx, def, delta)
			"defend":  _drone_defend(def, ctx["pos"])
			"repair":  _drone_repair(def, delta)
			"collect": _drone_collect(def)
			"lucky":
				total_luck += float(def.get("stats", {}).get("luck", 0.0))
				ctx["col"] = Color(0.55, 0.95, 0.5)
		idx += 1
	GameManager.run_luck = total_luck   # live luck from equipped Lucky drones

func _drone_combat(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	ctx["col"] = _kind_color(def)
	ctx["cd"] = float(ctx["cd"]) - delta
	if float(ctx["cd"]) > 0.0:
		return
	var stats: Dictionary = def.get("stats", {})
	var rng := float(stats.get("range_px", 420.0))
	var target := _nearest_enemy(ctx["pos"], rng, [])
	if target == null:
		return
	ctx["cd"] = maxf(0.05, float(stats.get("fire_interval_sec", 0.5)))
	var dmg := float(stats.get("damage", 6.0))
	if GameManager.has_method("drone_damage_mult"):
		dmg *= GameManager.drone_damage_mult()
	if GameManager.has_method("kind_damage_mult"):
		dmg *= GameManager.kind_damage_mult(def.get("damage_kind", []))
	var dir := ((target as Node2D).global_position - (ctx["pos"] as Vector2)).normalized()
	_bullets.append({
		"pos": ctx["pos"], "vel": dir * PROJ_SPEED, "life": 0.0, "start": ctx["pos"],
		"dmg": dmg, "crit": false, "radius": BOLT_RADIUS + 2.0, "col": ctx["col"], "big": false,
		"pierce": 0, "ricochet": 0, "rico_range": 0.0, "splash": 0.0, "splash_dmg": 0.0,
		"homing": false, "hit": [], "max_life": PROJ_LIFETIME, "max_dist": PROJ_MAX_DIST,
	})

func _drone_defend(def: Dictionary, pos: Vector2) -> void:
	if _enemy_mgr == null or not is_instance_valid(_enemy_mgr):
		_enemy_mgr = get_tree().get_first_node_in_group("enemy_manager")
	if _enemy_mgr != null and _enemy_mgr.has_method("push_bullets_away"):
		var stats: Dictionary = def.get("stats", {})
		_enemy_mgr.push_bullets_away(pos, float(stats.get("push_radius", 110.0)), float(stats.get("push_force", 320.0)))

func _drone_repair(def: Dictionary, delta: float) -> void:
	if GameManager.ship_hp <= 0:
		return
	_repair_acc += float(def.get("stats", {}).get("heal_per_sec", 1.5)) * delta
	if _repair_acc >= 1.0:
		var n := int(_repair_acc)
		_repair_acc -= float(n)
		if GameManager.has_method("heal"):
			GameManager.heal(n)

func _drone_collect(def: Dictionary) -> void:
	var rng := float(def.get("stats", {}).get("radius_px", 240.0))
	var center := _player.global_position
	for orb in get_tree().get_nodes_in_group("arena_xp_orb"):
		if is_instance_valid(orb) and orb.has_method("force_magnetize") and center.distance_to((orb as Node2D).global_position) <= rng:
			orb.force_magnetize()

# ── Per-slot firing ─────────────────────────────────────────────────────────────
func _tick_slot(ctx: Dictionary, def: Dictionary, delta: float, enemy_visible: bool) -> void:
	var mode := String(def.get("fire_mode", "repeat"))
	match mode:
		"repeat":
			ctx["beam_on"] = false
			ctx["cd"] = maxf(0.0, float(ctx["cd"]) - delta)
			if enemy_visible and float(ctx["cd"]) <= 0.0:
				_fire_by_type(def, 1.0)
				ctx["cd"] = _cooldown(def)
		"charge":
			ctx["beam_on"] = false
			ctx["charge"] = float(ctx["charge"]) + delta
			if enemy_visible and float(ctx["charge"]) >= _cooldown(def):
				ctx["charge"] = 0.0
				_fire_by_type(def, 1.0)   # auto-charge always releases at full power
		"beam":
			_tick_beam(ctx, def, delta, enemy_visible)
		"channel":
			ctx["beam_on"] = false
			match String(def.get("fire_type", "")):
				"growing_zone": _tick_zone(ctx, def, delta, enemy_visible)
				"minion":       _tick_minions(ctx, def, delta)
				_:              _tick_zone(ctx, def, delta, enemy_visible)
		"aura":
			ctx["beam_on"] = false
			_tick_aura(ctx, def, delta)
		"orbital":
			ctx["beam_on"] = false
			_tick_orbital(ctx, def, delta)
		_:
			ctx["beam_on"] = false

## Spawn the per-shot effect for a repeat/charge weapon. `power` scales charge weapons (1.0 = full).
func _fire_by_type(def: Dictionary, power: float) -> void:
	match String(def.get("fire_type", "projectile")):
		"projectile": _fire_projectile(def, power)
		"cone":       _fire_cone(def)
		"homing":     _fire_projectile(def, power, true)
		"chain":      _fire_chain(def)
		"radial":     _fire_radial(def)
		"splash_melee": _fire_splash_melee(def)
		"parasite_blob": _fire_projectile(def, 1.0)   # Phase 1: blob = splash bolt (parasite DoT later)
		"acid_cloud":  _fire_radial(def)              # Phase 1: settle as a one-shot pulse (cloud DoT later)
		"cross":       _fire_cross(def)               # X-shaped detonation (Red X)
		_:            _fire_projectile(def, power)

# ── Projectiles (projectile / homing / parasite_blob; pierce / ricochet / splash aware) ──
func _fire_projectile(def: Dictionary, power: float, homing: bool = false) -> void:
	var dir := _forward()
	var start := _muzzle()
	var charge_mode := String(def.get("fire_mode", "")) == "charge"
	var base_key := "damage"
	var r := _shot_damage(def, base_key, 10.0)
	var dmg := float(r["dmg"]) * power
	var splash := WeaponStats.raw_stat(def, "splash_radius", 0.0)
	if splash > 0.0:
		splash += _mech("splash_radius")   # Overpressure-style cards widen weapons that already splash
	var b := {
		"pos": start, "vel": dir * (CHARGE_SPEED if charge_mode else PROJ_SPEED),
		"life": 0.0, "start": start, "dmg": dmg, "crit": bool(r["crit"]),
		"radius": (16.0 if charge_mode else BOLT_RADIUS) + 4.0,
		"col": _kind_color(def), "big": charge_mode,
		"pierce": int(WeaponStats.raw_stat(def, "pierce", 0.0) + _mech("pierce")),
		"ricochet": int(WeaponStats.raw_stat(def, "ricochet", 0.0) + _mech("ricochet")),
		"rico_range": WeaponStats.raw_stat(def, "ricochet_range_px", 220.0) + _mech("ricochet_range"),
		"splash": splash, "splash_dmg": dmg * 0.7,
		"homing": homing, "hit": [],
		"max_life": PROJ_LIFETIME, "max_dist": PROJ_MAX_DIST,
	}
	_bullets.append(b)

func _fire_cone(def: Dictionary) -> void:
	var fwd := _forward()
	var start := _muzzle()
	var pellets := int(WeaponStats.raw_stat(def, "pellets", 5.0))
	var spread := WeaponStats.raw_stat(def, "spread_deg", 30.0)
	var rng := WeaponStats.raw_stat(def, "range_px", 240.0)
	var splash := WeaponStats.raw_stat(def, "splash_radius", 0.0)
	if splash > 0.0:
		splash += _mech("splash_radius")
	for i in pellets:
		var a := deg_to_rad(randf_range(-spread, spread))
		var dir := fwd.rotated(a)
		var r := _shot_damage(def, "damage", 12.0)
		_bullets.append({
			"pos": start, "vel": dir * PROJ_SPEED, "life": 0.0, "start": start,
			"dmg": float(r["dmg"]), "crit": bool(r["crit"]), "radius": BOLT_RADIUS + 3.0,
			"col": _kind_color(def), "big": false, "pierce": 0, "ricochet": 0, "rico_range": 0.0,
			"splash": splash, "splash_dmg": float(r["dmg"]) * 0.7, "homing": false, "hit": [],
			"max_life": rng / PROJ_SPEED, "max_dist": rng,
		})

## Instant chain lightning: strike nearest, then jump to nearest un-hit within chain_range.
func _fire_chain(def: Dictionary) -> void:
	var jumps := int(WeaponStats.raw_stat(def, "chain_jumps", 4.0) + _mech("chain_jumps"))
	var rng := WeaponStats.raw_stat(def, "chain_range_px", 200.0)
	var hit: Array = []
	var cur := _nearest_enemy(_player.global_position, 700.0, hit)
	if cur == null:
		return
	var pts := PackedVector2Array([_muzzle()])
	for _j in range(1 + maxi(0, jumps)):
		if cur == null:
			break
		var c: Vector2 = (cur as Node2D).global_position
		var r := _shot_damage(def, "damage", 20.0)
		_damage_node(cur, float(r["dmg"]), 0.12, bool(r["crit"]), c)
		pts.append(c)
		hit.append(cur)
		cur = _nearest_enemy(c, rng, hit)
	if pts.size() >= 2:
		_chains.append({"pts": pts, "age": 0.0, "max_age": 0.45, "col": _kind_color(def)})
	# Thunderhead-style weapons also pulse a ring (radius_px present alongside chain).
	if WeaponStats.raw_stat(def, "radius_px", 0.0) > 0.0:
		_fire_radial(def)

## Omnidirectional pulse around the ship (radial / shockwave / acid settle): one-shot AoE in radius_px.
func _fire_radial(def: Dictionary) -> void:
	var radius := WeaponStats.raw_stat(def, "radius_px", maxf(WeaponStats.raw_stat(def, "cloud_radius", 120.0), 120.0)) + _mech("radius")
	var center := _player.global_position
	var dmg_key := "damage"
	if not (def.get("stats", {}) as Dictionary).has("damage"):
		dmg_key = "tick_damage"
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= radius + _node_radius(en):
			var r := _shot_damage(def, dmg_key, 20.0)
			_damage_node(en, float(r["dmg"]), 0.1, bool(r["crit"]), (en as Node2D).global_position)
	_chains.append({"ring": true, "pos": center, "r": radius, "age": 0.0, "max_age": 0.32, "col": _kind_color(def)})

## Periodic X-shaped detonation centered on the ship (Red X): damages enemies near the 4 diagonal arms.
## Mirrors _fire_radial (player-centered, _mech("radius") reach, _shot_damage→_damage_node) but swaps the
## circular test for a 4-fold diagonal-arm test so only enemies along the X take damage.
func _fire_cross(def: Dictionary) -> void:
	var reach := WeaponStats.raw_stat(def, "radius_px", 160.0) + _mech("radius")
	var arm_half := deg_to_rad(WeaponStats.raw_stat(def, "arm_half_deg", 14.0))
	var center := _player.global_position
	var dmg_key := "damage"
	if not (def.get("stats", {}) as Dictionary).has("damage"):
		dmg_key = "tick_damage"
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		var off := ep - center
		var dist := off.length()
		if dist > reach + _node_radius(en):
			continue                                   # outside arm reach
		# Fold the angle into 4-fold symmetry, then measure nearness to the nearest 45° diagonal.
		var a := fposmod(off.angle(), PI / 2.0)        # 0..PI/2
		var d_to_diag := absf(a - PI / 4.0)            # 0 on a diagonal, PI/4 on an axis
		if d_to_diag <= arm_half or dist <= 28.0:      # small center disc always hits
			var r := _shot_damage(def, dmg_key, 20.0)
			_damage_node(en, float(r["dmg"]), 0.1, bool(r["crit"]), ep)
	_spawn_cross_fire(center, reach)
	if CROSS_DEBUG_DRAW:
		_chains.append({"cross": true, "pos": center, "r": reach, "arm": arm_half, "age": 0.0, "max_age": 0.25, "col": _kind_color(def)})

## Red X fire VISUAL: a short X-shaped flash (DynamicFire shape="cross"). Pooled + retriggered per shot so
## we don't rebuild the GPU particle system / textures every second.
func _spawn_cross_fire(center: Vector2, reach: float) -> void:
	if _cross_fx == null or not is_instance_valid(_cross_fx):
		_cross_fx = DynamicFire.new()
		_cross_fx.shape             = "cross"
		_cross_fx.arm_count         = 4
		_cross_fx.ring_start_angle  = PI / 4.0      # X diagonals (matches the ±45° hit test)
		_cross_fx.z_index           = 6
		_cross_fx.particle_lifetime = 0.35          # short → a flash of fire
		_cross_fx.draw_duration     = 0.12          # arms shoot out fast
		_cross_fx.draw_ease         = 1.0
		_cross_fx.hold_duration     = 0.05
		_cross_fx.burnout_duration  = 0.20
		_cross_fx.particle_amount   = 400
		_cross_fx.particle_size_min = 34.0
		_cross_fx.particle_size_max = 78.0
		_cross_fx.loop              = false
		_cross_fx.free_on_done      = false         # pooled: kept alive and reused
		_cross_fx.arm_length        = reach
		add_child(_cross_fx)
		_cross_fx.global_position = center
	else:
		_cross_fx.arm_length = reach
		_cross_fx.retrigger(center)

## Short-range arc swing in front of the ship: damages enemies within range_px and ±arc_deg of facing.
func _fire_splash_melee(def: Dictionary) -> void:
	var rng := WeaponStats.raw_stat(def, "range_px", 130.0)
	var arc := deg_to_rad(WeaponStats.raw_stat(def, "arc_deg", 120.0)) * 0.5
	var fwd := _forward()
	var origin := _player.global_position
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var to_e: Vector2 = (en as Node2D).global_position - origin
		if to_e.length() <= rng + _node_radius(en) and absf(to_e.angle_to(fwd)) <= arc:
			var r := _shot_damage(def, "damage", 28.0)
			_damage_node(en, float(r["dmg"]), 0.15, bool(r["crit"]), (en as Node2D).global_position)
	_chains.append({"swing": true, "pos": origin, "dir": fwd, "r": rng, "arc": arc, "age": 0.0, "max_age": 0.22, "col": _kind_color(def)})

# ── Beam (hitscan_beam / tether) ────────────────────────────────────────────────
func _tick_beam(ctx: Dictionary, def: Dictionary, delta: float, enemy_visible: bool) -> void:
	if not enemy_visible:
		ctx["beam_on"] = false
		ctx["beam_tick"] = 0.0
		return
	var from := _muzzle()
	var dir := _forward()
	var rng := WeaponStats.raw_stat(def, "range_px", 760.0)
	var width := WeaponStats.raw_stat(def, "beam_width", 24.0)
	var best_along := rng
	var best: Node = null
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var to_e: Vector2 = (en as Node2D).global_position - from
		var along := to_e.dot(dir)
		if along < 0.0 or along > rng:
			continue
		var perp := (to_e - dir * along).length()
		if perp <= width * 0.5 + _node_radius(en) and along < best_along:
			best_along = along
			best = en
	var hit := best != null
	ctx["beam_on"] = true
	ctx["beam_from"] = from
	ctx["beam_to"] = from + dir * (best_along if hit else rng)
	ctx["beam_col"] = _kind_color(def)
	ctx["beam_w"] = width
	ctx["beam_tick"] = float(ctx["beam_tick"]) - delta
	if float(ctx["beam_tick"]) <= 0.0:
		if hit:
			var r := _shot_damage(def, "damage", 20.0)
			_damage_node(best, float(r["dmg"]), 0.12, bool(r["crit"]), (best as Node2D).global_position)
		ctx["beam_tick"] = _tick_interval(def)

# ── Growing zone (rift / graviton / event horizon) + acid cloud settle ──────────
func _tick_zone(ctx: Dictionary, def: Dictionary, delta: float, enemy_visible: bool) -> void:
	if not enemy_visible:
		ctx["zone_on"] = false
		ctx["zone_age"] = 0.0
		return
	if not bool(ctx["zone_on"]):
		ctx["zone_on"] = true
		ctx["zone_age"] = 0.0
		ctx["zone_pos"] = _aim_point(360.0)
	ctx["zone_age"] = float(ctx["zone_age"]) + delta
	var ramp := WeaponStats.raw_stat(def, "ramp_sec", 2.5)
	var f := clampf(float(ctx["zone_age"]) / maxf(0.01, ramp), 0.0, 1.0)
	var radius := lerpf(WeaponStats.raw_stat(def, "radius_min", 40.0), WeaponStats.raw_stat(def, "radius_max", 120.0), f) + _mech("radius")
	ctx["zone_r"] = radius
	var pull := WeaponStats.raw_stat(def, "pull", 0.0)
	ctx["zone_tick"] = float(ctx["zone_tick"]) - delta
	var do_dmg := float(ctx["zone_tick"]) <= 0.0
	if do_dmg:
		ctx["zone_tick"] = _tick_interval(def)
	var center: Vector2 = ctx["zone_pos"]
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var node := en as Node2D
		var d := center.distance_to(node.global_position)
		if d <= radius + _node_radius(en):
			if do_dmg:
				var base := lerpf(WeaponStats.get_stat(def, "damage_min", 20.0), WeaponStats.get_stat(def, "damage_max", 100.0), f) * _run_mult(def)
				var cr := _crit_roll(def, base)
				_damage_node(en, float(cr["dmg"]), 0.0, bool(cr["crit"]), node.global_position)
			if pull > 0.0 and d > 1.0:
				node.global_position += (center - node.global_position).normalized() * pull * delta

# ── Aura (always-on ring DoT — ionizing field) ──────────────────────────────────
func _tick_aura(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	var radius := WeaponStats.raw_stat(def, "radius_px", 140.0) + _mech("radius")
	ctx["aura_r"] = radius
	ctx["aura_tick"] = float(ctx["aura_tick"]) - delta
	if float(ctx["aura_tick"]) > 0.0:
		return
	ctx["aura_tick"] = _tick_interval(def)
	var center := _player.global_position
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= radius + _node_radius(en):
			var r := _shot_damage(def, "damage_per_tick", 14.0)
			_damage_node(en, float(r["dmg"]), 0.0, bool(r["crit"]), (en as Node2D).global_position)

# ── Orbital (orbitals / omega swarm) ────────────────────────────────────────────
func _tick_orbital(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	var n := maxi(1, int(WeaponStats.raw_stat(def, "orbs", 3.0)))
	ctx["orb_n"] = n
	ctx["orb_r"] = 78.0
	ctx["orb_ang"] = fmod(float(ctx["orb_ang"]) + delta * 2.6, TAU)
	ctx["orb_col"] = _kind_color(def)
	var center := _player.global_position
	for i in n:
		var a := float(ctx["orb_ang"]) + TAU * float(i) / float(n)
		var op := center + Vector2(cos(a), sin(a)) * float(ctx["orb_r"])
		for en in _enemies():
			if not is_instance_valid(en):
				continue
			if op.distance_to((en as Node2D).global_position) <= 18.0 + _node_radius(en):
				var cd_key := "_orb_cd_%d_%d" % [(en as Node2D).get_instance_id(), i]
				if float(ctx.get(cd_key, 0.0)) > 0.0:
					continue
				var r := _shot_damage(def, "damage", 38.0)
				_damage_node(en, float(r["dmg"]), 0.1, bool(r["crit"]), op)
				ctx[cd_key] = 0.35
	# decay per-target orbital cooldowns
	for k in ctx.keys():
		if String(k).begins_with("_orb_cd_"):
			ctx[k] = maxf(0.0, float(ctx[k]) - delta)

# ── Minions (swarm host / hivemind) ─────────────────────────────────────────────
func _tick_minions(ctx: Dictionary, def: Dictionary, delta: float) -> void:
	var want := maxi(1, int(WeaponStats.raw_stat(def, "bats", 4.0)))
	var minions: Array = ctx["minions"]
	while minions.size() < want:
		minions.append({"pos": _player.global_position, "atk": 0.0})
	var rng := WeaponStats.raw_stat(def, "bat_range_px", 260.0)
	var atk_int := maxf(0.05, WeaponStats.raw_stat(def, "attack_interval_sec", 0.4))
	for m: Dictionary in minions:
		var target := _nearest_enemy(m["pos"], rng, [])
		var goal: Vector2 = (target as Node2D).global_position if target != null else _player.global_position
		m["pos"] = (m["pos"] as Vector2).lerp(goal, clampf(6.0 * delta, 0.0, 1.0))
		m["atk"] = float(m["atk"]) - delta
		if target != null and float(m["atk"]) <= 0.0 and (m["pos"] as Vector2).distance_to(goal) <= 28.0 + _node_radius(target):
			var r := _shot_damage(def, "damage", 5.0)
			_damage_node(target, float(r["dmg"]), 0.0, bool(r["crit"]), goal)
			m["atk"] = atk_int
	ctx["minions"] = minions
	ctx["minion_col"] = _kind_color(def)

# ── Bullet stepping (pierce / ricochet / splash / homing) ───────────────────────
func _tick_bullets(delta: float) -> void:
	var enemies := _enemies()
	var ruins := _ruins()
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		if bool(b.get("homing", false)):
			var tgt := _nearest_enemy(b["pos"], 600.0, [])
			if tgt != null:
				var want := ((tgt as Node2D).global_position - (b["pos"] as Vector2)).normalized() * (b["vel"] as Vector2).length()
				b["vel"] = (b["vel"] as Vector2).lerp(want, clampf(5.0 * delta, 0.0, 1.0))
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var p: Vector2 = b["pos"]
		var dead := float(b["life"]) >= float(b["max_life"]) or p.distance_to(b["start"]) >= float(b["max_dist"])
		if not dead:
			var hit_node: Node = null
			for en in enemies:
				if not is_instance_valid(en) or (en as Node2D).get_instance_id() in b["hit"]:
					continue
				if p.distance_to((en as Node2D).global_position) <= float(b["radius"]) + _node_radius(en):
					hit_node = en
					break
			if hit_node == null:
				for ruin in ruins:
					if not is_instance_valid(ruin) or (ruin as Node2D).get_instance_id() in b["hit"]:
						continue
					if p.distance_to((ruin as Node2D).global_position) <= float(b["radius"]) + _node_radius(ruin):
						hit_node = ruin
						break
			if hit_node != null:
				_damage_node(hit_node, float(b["dmg"]), 0.1, bool(b["crit"]), p)
				b["hit"].append((hit_node as Node2D).get_instance_id())
				if float(b["splash"]) > 0.0:
					_splash(p, float(b["splash"]), float(b["splash_dmg"]), b["hit"])
				if int(b["pierce"]) > 0:
					b["pierce"] = int(b["pierce"]) - 1
				elif int(b["ricochet"]) > 0:
					var nxt := _nearest_enemy(p, float(b["rico_range"]), b["hit"])
					if nxt != null:
						b["vel"] = ((nxt as Node2D).global_position - p).normalized() * (b["vel"] as Vector2).length()
						b["ricochet"] = int(b["ricochet"]) - 1
					else:
						dead = true
				else:
					dead = true
		if dead:
			_bullets.remove_at(i)
		i -= 1

func _splash(center: Vector2, radius: float, dmg: float, exclude: Array) -> void:
	for en in _enemies():
		if not is_instance_valid(en) or (en as Node2D).get_instance_id() in exclude:
			continue
		if center.distance_to((en as Node2D).global_position) <= radius + _node_radius(en):
			_damage_node(en, dmg, 0.0, false, (en as Node2D).global_position)
	_chains.append({"ring": true, "pos": center, "r": radius, "age": 0.0, "max_age": 0.22, "col": Color(1.0, 0.6, 0.2)})

func _tick_chains(delta: float) -> void:
	var i := _chains.size() - 1
	while i >= 0:
		var c: Dictionary = _chains[i]
		c["age"] = float(c["age"]) + delta
		if float(c["age"]) >= float(c["max_age"]):
			_chains.remove_at(i)
		i -= 1

# ── Damage application + crit feedback ──────────────────────────────────────────
func _damage_node(node: Node, dmg: float, stagger: float, crit: bool, pos: Vector2) -> void:
	if node == null or not is_instance_valid(node) or not node.has_method("take_damage"):
		return
	node.call("take_damage", dmg, stagger)
	if crit:
		_spawn_crit_number(pos, dmg)

## Base stat × run multipliers, then a crit roll. Returns {dmg, crit}.
func _shot_damage(def: Dictionary, key: String, fallback: float) -> Dictionary:
	var base := WeaponStats.get_stat(def, key, fallback) * _run_mult(def)
	return _crit_roll(def, base)

## Flat run bonus for a firing-mechanic key from the level-up cards (chain_jumps/ricochet/pierce/…).
func _mech(key: String) -> float:
	return GameManager.mech_bonus(key) if GameManager.has_method("mech_bonus") else 0.0

func _run_mult(def: Dictionary) -> float:
	var m := 1.0
	if GameManager.has_method("get_damage_mult"):
		m *= GameManager.get_damage_mult()
	if GameManager.has_method("group_damage_mult"):
		m *= GameManager.group_damage_mult(String(def.get("group", "")))
	if GameManager.has_method("kind_damage_mult"):
		m *= GameManager.kind_damage_mult(def.get("damage_kind", []))
	return m

func _crit_roll(def: Dictionary, base: float) -> Dictionary:
	var chance := BASE_CRIT_CHANCE
	if GameManager.has_method("get_crit_chance"):
		chance += GameManager.get_crit_chance()
	if GameManager.has_method("hull_luck_mult"):
		chance *= GameManager.hull_luck_mult()   # Cursed Hull curses your crit luck
	var crit := chance > 0.0 and randf() < chance
	var dmg := base
	if crit:
		dmg *= (GameManager.get_crit_damage() if GameManager.has_method("get_crit_damage") else 1.5)
	return {"dmg": dmg, "crit": crit}

func _cooldown(def: Dictionary) -> float:
	var cd := WeaponStats.get_stat(def, "cooldown_sec", DEF_COOLDOWN)
	var rate := maxf(0.01, GameManager.get_fire_rate_mult()) if GameManager.has_method("get_fire_rate_mult") else 1.0
	return cd / rate

func _tick_interval(def: Dictionary) -> float:
	var t := WeaponStats.get_stat(def, "tick_interval_sec", 0.2)
	var rate := maxf(0.01, GameManager.get_fire_rate_mult()) if GameManager.has_method("get_fire_rate_mult") else 1.0
	return t / rate

# ── Helpers ─────────────────────────────────────────────────────────────────────
func _forward() -> Vector2:
	return Vector2.UP.rotated(_player.rotation)

func _muzzle() -> Vector2:
	return _player.global_position + _forward() * 22.0

## A point in the aim direction at `dist` px — where placed zones land.
func _aim_point(dist: float) -> Vector2:
	var tgt := _nearest_enemy(_player.global_position, dist, [])
	if tgt != null:
		return (tgt as Node2D).global_position
	return _player.global_position + _forward() * dist

func _enemies() -> Array:
	return get_tree().get_nodes_in_group(ENEMY_GROUP)

func _ruins() -> Array:
	return get_tree().get_nodes_in_group(RUIN_GROUP)

func _node_radius(n: Node) -> float:
	var r = n.get("hit_radius")
	return float(r) if r != null else 16.0

func _nearest_enemy(from: Vector2, max_dist: float, exclude: Array) -> Node:
	var best: Node = null
	var best_d := max_dist
	for en in _enemies():
		if not is_instance_valid(en) or en in exclude:
			continue
		var d := (en as Node2D).global_position.distance_to(from)
		if d <= best_d:
			best_d = d
			best = en
	return best

func _has_enemy_on_screen() -> bool:
	if GameManager.has_method("is_boss_alive") and GameManager.is_boss_alive():
		return true
	var enemies := _enemies()
	if enemies.is_empty():
		return false
	var canvas_xform := get_viewport().get_canvas_transform()
	var vp := get_viewport().get_visible_rect().size
	var rect := Rect2(Vector2.ZERO, vp).grow_individual(vp.x * 0.5, vp.y * 0.5, vp.x * 0.5, vp.y * 0.5)
	for en in enemies:
		if is_instance_valid(en) and rect.has_point(canvas_xform * (en as Node2D).global_position):
			return true
	return false

## Pick a clean colour from the weapon's damage_kind tags (fire warm, energy cyan, bio green, …).
func _kind_color(def: Dictionary) -> Color:
	var kinds: Array = def.get("damage_kind", [])
	if "fire" in kinds:     return Color(1.0, 0.5, 0.15)
	if "light" in kinds:    return Color(0.85, 0.8, 1.0)
	if "energy" in kinds:   return Color(0.4, 0.85, 1.0)
	if "bio" in kinds:      return Color(0.55, 0.95, 0.45)
	if "explosive" in kinds: return Color(1.0, 0.65, 0.2)
	return Color(1.0, 0.82, 0.3)   # kinetic default (gold)

func _quiet_slot(ctx: Dictionary) -> void:
	ctx["beam_on"] = false
	ctx["zone_on"] = false
	if ctx.has("aura_r"):
		ctx["aura_r"] = 0.0
	if ctx.has("orb_n"):
		ctx["orb_n"] = 0
	if ctx.has("minions"):
		(ctx["minions"] as Array).clear()

func _spawn_crit_number(world_pos: Vector2, amount: float) -> void:
	if _crit_host == null:
		return
	var lbl := Label.new()
	lbl.text = str(roundi(amount))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.reset_size()
	lbl.position = get_viewport().get_canvas_transform() * world_pos + Vector2(randf_range(-10.0, 10.0), -16.0) - lbl.size * 0.5
	lbl.scale = Vector2.ONE * 1.5
	_crit_host.add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 44.0, 0.8)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: lbl.queue_free())

# ── Drawing (world space — node sits at origin) ─────────────────────────────────
func _draw() -> void:
	for b: Dictionary in _bullets:
		_draw_bolt(b)
	for c: Dictionary in _chains:
		_draw_effect(c)
	for slot: String in _slots.keys():
		_draw_slot_persistent(_slots[slot])
	for slot: String in _drones.keys():
		_draw_drone(_drones[slot])

func _draw_drone(ctx: Dictionary) -> void:
	if not bool(ctx.get("active", false)):
		return
	var p: Vector2 = ctx["pos"]
	var c: Color = ctx.get("col", Color(0.8, 0.85, 1.0))
	draw_circle(p, 9.0, Color(c.r, c.g, c.b, 0.25))
	draw_circle(p, 5.0, c)
	draw_circle(p, 2.0, Color(1, 1, 1, 0.9))

func _draw_bolt(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var col: Color = b["col"]
	var rad := float(b["radius"])
	if bool(b.get("big", false)):
		draw_circle(p, rad * 1.8, Color(col.r, col.g, col.b, 0.18))
		draw_circle(p, rad, col)
		draw_circle(p, rad * 0.45, Color(1, 1, 1, 0.9))
	else:
		var dir := (b["vel"] as Vector2).normalized() if (b["vel"] as Vector2).length() > 0.01 else Vector2.UP
		var tail := p - dir * 14.0
		draw_line(tail, p, Color(col.r, col.g, col.b, 0.5), rad * 0.9)
		draw_line(tail, p, Color(1, 1, 1, 0.85), rad * 0.4)
		draw_circle(p, rad * 0.5, Color(1, 1, 1, 0.9))

func _draw_effect(c: Dictionary) -> void:
	var t := clampf(1.0 - float(c["age"]) / maxf(0.01, float(c["max_age"])), 0.0, 1.0)
	var col: Color = c["col"]
	if bool(c.get("ring", false)):
		var r := float(c["r"]) * (0.5 + 0.5 * (1.0 - t))
		draw_arc(c["pos"], r, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.7 * t), 4.0, true)
	elif bool(c.get("swing", false)):
		var dir: Vector2 = c["dir"]
		var a0 := dir.angle() - float(c["arc"])
		draw_arc(c["pos"], float(c["r"]), a0, a0 + 2.0 * float(c["arc"]), 24, Color(col.r, col.g, col.b, 0.8 * t), 6.0, true)
	elif bool(c.get("cross", false)):
		# Stage 1 debug: each of the 4 diagonals → bright center line + faint wedge-edge lines (the hit test).
		var center: Vector2 = c["pos"]
		var reach := float(c["r"])
		var arm := float(c.get("arm", deg_to_rad(14.0)))
		for k in 4:
			var da := PI / 4.0 + float(k) * (PI / 2.0)   # 45° / 135° / 225° / 315°
			draw_line(center, center + Vector2.from_angle(da) * reach, Color(col.r, col.g, col.b, 0.75 * t), 3.0)
			draw_line(center, center + Vector2.from_angle(da - arm) * reach, Color(col.r, col.g, col.b, 0.3 * t), 1.0)
			draw_line(center, center + Vector2.from_angle(da + arm) * reach, Color(col.r, col.g, col.b, 0.3 * t), 1.0)
	else:
		var pts: PackedVector2Array = c["pts"]
		if pts.size() >= 2:
			var glow := PackedColorArray()
			for _i in pts.size():
				glow.append(Color(col.r, col.g, col.b, 0.35 * t))
			draw_polyline_colors(pts, glow, 8.0)
			var core := PackedColorArray()
			for _i in pts.size():
				core.append(Color(1, 1, 1, 0.9 * t))
			draw_polyline_colors(pts, core, 2.5)

## Always-on visuals: beams, zones, auras, orbitals, minions.
func _draw_slot_persistent(ctx: Dictionary) -> void:
	if bool(ctx.get("beam_on", false)):
		var col: Color = ctx["beam_col"]
		var w := float(ctx["beam_w"])
		draw_line(ctx["beam_from"], ctx["beam_to"], Color(col.r, col.g, col.b, 0.45), w)
		draw_line(ctx["beam_from"], ctx["beam_to"], Color(1, 1, 1, 0.9), w * 0.35)
	if bool(ctx.get("zone_on", false)):
		var center: Vector2 = ctx["zone_pos"]
		var r := float(ctx.get("zone_r", 40.0))
		draw_circle(center, r, Color(0.4, 0.2, 0.7, 0.22))
		draw_arc(center, r, 0.0, TAU, 48, Color(0.7, 0.5, 1.0, 0.7), 3.0, true)
	if float(ctx.get("aura_r", 0.0)) > 0.0:
		draw_arc(_player.global_position, float(ctx["aura_r"]), 0.0, TAU, 48, Color(0.4, 0.85, 1.0, 0.5), 3.0, true)
	if int(ctx.get("orb_n", 0)) > 0:
		var n := int(ctx["orb_n"])
		var oc: Color = ctx.get("orb_col", Color(1.0, 0.82, 0.3))
		for i in n:
			var a := float(ctx["orb_ang"]) + TAU * float(i) / float(n)
			var op := _player.global_position + Vector2(cos(a), sin(a)) * float(ctx.get("orb_r", 78.0))
			draw_circle(op, 9.0, oc)
			draw_circle(op, 4.0, Color(1, 1, 1, 0.9))
	for m in ctx.get("minions", []):
		var mc: Color = ctx.get("minion_col", Color(0.55, 0.95, 0.45))
		draw_circle((m as Dictionary)["pos"], 6.0, mc)
