extends Node2D
## Arena weapons — the first two REAL weapons ported into world space: the Gatling gun (rapid golden
## tracer bolts) and the Gauss cannon (auto-charging heavy plasma orb with converging charge rings).
##
## Self-contained: it does NOT pull in the Control/InventoryManager weapon machinery. It only reuses the
## VISUAL code (tracer capsule, plasma-orb shader, comet trail, tail sparks, charge rings) from
## weapon_system.gd, adapted to a Node2D so it can draw in world space. It auto-fires both weapons toward
## the ship's current facing (Vampire-Survivors style) and damages enemies via the take_damage contract.
##
## Drawing: this Node2D sits at the world origin, so its _draw() coordinates ARE world coordinates. The
## Gauss orb is a ColorRect child positioned in world space (renders on top of the _draw() trail/sparks).

# ── TUNABLES: Gatling gun (rapid tracer stream) ───────────────────────────────
const GAT_ENABLED       := true
const GAT_FIRE_INTERVAL := 0.09     # s between shots (hold-to-fire feel)
const GAT_SPEED         := 900.0    # px/s
const GAT_DAMAGE        := 6.0      # per hit
const GAT_LIFETIME      := 1.2      # s before despawn
const GAT_MAX_DIST      := 1300.0   # px travelled before despawn
const GAT_HIT_RADIUS    := 16.0     # bullet↔enemy hit distance (px)
const GAT_SPREAD_DEG    := 3.0      # ± random spray on each shot (0 = laser-straight)
const GAT_STAGGER       := 0.1      # s the enemy is staggered (movement/attacks frozen) per Gatling hit
const GAT_LIGHT         := 1.0      # dust-light "value" per Gatling bullet (low → lights up nearby dust only)
const GAT_WING_SPACING  := 26.0     # px between the two wing muzzles (twin parallel streams)
const GAT_WING_FWD      := 22.0     # forward offset of the wing muzzles from ship centre (px)

# ── TUNABLES: Gauss cannon (auto-charge → heavy piercing orb) ─────────────────
const GAUSS_ENABLED     := false    # disabled for now
const GAUSS_STAGGER     := 0.35     # s the enemy is staggered per Gauss hit (heavier weapon = more)
const GAUSS_LIGHT       := 5.0      # dust-light "value" per Gauss orb (heavy → big bright light)
const GAUSS_CHARGE_TIME := 1.4      # s to fully charge between shots (charge rings ramp up over this)
const GAUSS_SPEED       := 520.0    # px/s (heavy + slow so you watch it plough through)
const GAUSS_DAMAGE      := 55.0     # damage dealt to EACH enemy it pierces
const GAUSS_PIERCE      := 6        # how many enemies one orb punches through before despawning
const GAUSS_RADIUS      := 30.0     # orb ball radius (drives orb size + hit radius)
const GAUSS_LIFETIME    := 2.5      # s before despawn
const GAUSS_MAX_DIST    := 1700.0   # px travelled before despawn

const MUZZLE_OFFSET     := 22.0     # how far ahead of the ship centre shots spawn (px)

# ── TUNABLES: Lasgun (continuous tick-based beam — gained from a pickup, off until then) ──────────────────
const LASGUN_RANGE   := 1400.0   # beam length px
const LASGUN_DAMAGE  := 22.0     # damage PER TICK
const LASGUN_TICK    := 0.10     # s between damage ticks (≈ damage/sec = LASGUN_DAMAGE / this)
const LASGUN_STAGGER := 0.15     # s stagger per tick
const LASGUN_WIDTH   := 14.0     # beam hit width (px) — matches the beam visual
const LASGUN_HIT_PAD := 16.0     # enemy-radius padding for the distance-to-line hit test
const LASGUN_CYCLE    := 5.0     # full period (s): the beam fires once every CYCLE
const LASGUN_DURATION := 3.0     # beam-on time within each cycle (s) → fires 3s out of every 5s
const LASGUN_CHARGE   := 1.5     # charge telegraph (s) before each burst — the orb light-gather plays over this

const BeamScript   := preload("res://scripts/gameplay/arena_lasgun_beam.gd")
const PickupScript := preload("res://scripts/gameplay/arena_weapon_pickup.gd")
const OrbChargeScript := preload("res://scripts/gameplay/arena_orb_charge_fx.gd")

# ── Gatling tracer bolt look (copied from weapon_system.gd — visuals only) ────
const GAT_TRACER_LEN   := 16.0
const GAT_TRACER_WIDTH := 6.0
const GAT_TRACER_SCALE := 1.0
const GAT_CORE_COL := Color(1.0, 1.0, 0.85)
const GAT_BODY_COL := Color(1.0, 0.82, 0.25)
const GAT_EDGE_COL := Color(1.0, 0.5, 0.12)
const GAT_GLOW_SIZE := 2.4
const GAT_GLOW_INTENSITY := 0.30
const GAT_TAIL_LEN := 12.0

# ── Gauss plasma orb look (copied from weapon_system.gd — visuals only) ───────
const GAUSS_ORB_CORE_COL      := Color(0.85, 0.95, 1.0)
const GAUSS_ORB_LIGHT_COL     := Color(0.25, 0.65, 1.0)
const GAUSS_ORB_HAZE_COL      := Color(0.20, 0.50, 1.0)
const GAUSS_ORB_TEAR_WIDTH    := 0.62
const GAUSS_ORB_CORE_WIDTH    := 0.10
const GAUSS_ORB_CORE_BRIGHT   := 1.3
const GAUSS_ORB_LIGHT_DENSITY := 5.0
const GAUSS_ORB_CRACKLE_SPEED := 6.0
const GAUSS_ORB_HAZE_SIZE     := 0.5
const GAUSS_ORB_GLOW          := 1.4
const GAUSS_ORB_QUAD          := 2.0    # quad half-size = ball radius × this
const GAUSS_ORB_STRETCH       := 1.4    # elongation along travel
const GAUSS_TRAIL_LEN         := 10
const GAUSS_TRAIL_WIDTH       := 1.15
const GAUSS_TRAIL_ALPHA       := 0.5
const GAUSS_TRAIL_COL         := Color(0.4, 0.7, 1.0)
const GAUSS_LAUNCH_FLASH      := 48.0
const GAUSS_SPARK_RATE        := 26.0
const GAUSS_SPARK_SPEED       := 95.0
const GAUSS_SPARK_LIFE        := 0.4
const GAUSS_SPARK_LEN         := 7.0
const GAUSS_SPARK_COL         := Color(0.5, 0.85, 1.0)
const GAUSS_SPARK_ALPHA       := 0.9

# ── Gauss charge-up rings converging onto the ship (copied — visuals only) ────
const GC_START_RADIUS   := 150.0
const GC_RING_SIZE      := 13.0
const GC_COL_OUT        := Color(1.0, 0.30, 0.45)
const GC_COL_IN         := Color(1.0, 1.0, 0.95)
const GC_SPEED_EMPTY    := 130.0
const GC_SPEED_FULL     := 340.0
const GC_INTERVAL_EMPTY := 0.5
const GC_INTERVAL_FULL  := 0.05
const GC_RAMP_CURVE     := 1.6
const GC_SPAWN_COUNT    := 1
const GC_BRIGHT         := 0.9
const GC_FLASH_R        := 7.0
const GC_RELEASE_FLASH  := 60.0

const GAUSS_ORB_SHADER := """
shader_type canvas_item;
render_mode blend_add;

uniform vec4  core_color   : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform vec4  light_color  : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform vec4  haze_color   : source_color = vec4(0.20, 0.50, 1.0, 1.0);
uniform float tear_width    = 0.62;
uniform float core_width    = 0.10;
uniform float core_bright   = 1.3;
uniform float light_density = 5.0;
uniform float crackle_speed = 6.0;
uniform float haze_size     = 0.5;
uniform float glow          = 1.4;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p){
	float v = 0.0; float amp = 0.5;
	for(int k = 0; k < 5; k++){ v += amp * vnoise(p); p *= 2.0; amp *= 0.5; }
	return v;
}

void fragment(){
	vec2 p = (UV - 0.5) * 2.0;
	float t = clamp((p.x + 1.0) * 0.5, 0.0, 1.0);
	float hw = tear_width * pow(t, 0.6) * (1.0 - smoothstep(0.78, 1.0, t));
	float d = abs(p.y) - hw;
	float inside = step(d, 0.0);

	vec3 col = vec3(0.0);

	float along = smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(0.85, 1.0, t));
	float core = exp(-pow(p.y / max(core_width, 0.001), 2.0)) * along;
	col += core_color.rgb * core * core_bright;

	vec2 np = vec2(p.x * light_density * 0.6 + TIME * crackle_speed * 0.35,
	               p.y * light_density + TIME * crackle_speed);
	float n = fbm(np);
	float arc = smoothstep(0.05, 0.0, abs(fract(n * 3.0) - 0.5) - 0.02);
	float rim = exp(-pow(d / 0.06, 2.0));
	float light = (arc * inside + rim) * (0.5 + 0.5 * fbm(np * 1.7 + 13.0));
	col += light_color.rgb * light * 1.6;

	float haze = exp(-pow(max(d, 0.0) / max(haze_size * 0.5, 0.001), 2.0)) * (1.0 - inside);
	col += haze_color.rgb * haze * 0.6;

	float a = clamp(core + light + haze + inside * 0.12, 0.0, 1.0);
	COLOR = vec4(col * glow, a);
}
"""

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player: Node2D = null
var _gat_acc: float = 0.0
var _gauss_charge: float = 0.0
var _dmg_mult: float = 1.0    # GameManager.get_damage_mult(), refreshed each frame (Damage upgrade cards)
var _rate_mult: float = 1.0   # GameManager.get_fire_rate_mult() (Fire Rate upgrade cards)
var _bullets: Array = []         # Gatling: {pos, vel, life, start}
var _orbs: Array = []            # Gauss: {pos, vel, life, start, orb_node, trail, spark_acc, pierce_left, hit}
var _sparks: Array = []          # Gauss tail sparks: {pos, vel, life, ttl}
var _charge_rings: Array = []    # {ang, r}
var _charge_spawn_acc: float = 0.0
var _flashes: Array = []         # {pos, age, max_age, radius}
var _orb_shader: Shader = null
var _lasgun_active: bool = false   # turned on by the Lasgun pickup (auto-equip, accumulates with the Gatling)
var _beam_cd: float = 0.0          # Lasgun damage-tick cooldown
var _beam: Node2D = null           # additive beam VFX child (gameplay plane → sharp)
var _las_t: float = 0.0            # Lasgun cycle clock (advances while active)
var _charge_fx: Node2D = null      # Chromeleon-orb light-gather charge telegraph (ported _ChannelFX)
var _las_charge_started: bool = false   # one-shot guard so the charge FX triggers once per cycle

func _ready() -> void:
	add_to_group("arena_weapons")   # arena_dust queries get_lights() each frame
	_player = get_tree().get_first_node_in_group("player")
	_beam = BeamScript.new()
	add_child(_beam)
	_charge_fx = OrbChargeScript.new()
	add_child(_charge_fx)

## Light sources this weapon currently emits, for the dust field: one per live projectile/beam.
## Each: {pos: world Vector2, value: float (light strength), color: Color}.
func get_lights() -> Array:
	var lights: Array = []
	if GAT_ENABLED:
		for b: Dictionary in _bullets:
			lights.append({"pos": b["pos"], "value": GAT_LIGHT, "color": GAT_BODY_COL})
	if GAUSS_ENABLED:
		for o: Dictionary in _orbs:
			lights.append({"pos": o["pos"], "value": GAUSS_LIGHT, "color": GAUSS_ORB_LIGHT_COL})
	return lights

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# Player-stat multipliers (base values 1.0 → identical to before).
	_dmg_mult = GameManager.get_damage_mult() if GameManager.has_method("get_damage_mult") else 1.0
	_rate_mult = maxf(0.01, GameManager.get_fire_rate_mult()) if GameManager.has_method("get_fire_rate_mult") else 1.0
	if GAT_ENABLED:
		_gat_acc += delta
		var gat_interval := GAT_FIRE_INTERVAL / _rate_mult
		while _gat_acc >= gat_interval:
			_gat_acc -= gat_interval
			_fire_gatling()
	if GAUSS_ENABLED:
		_gauss_charge += delta
		if _gauss_charge >= GAUSS_CHARGE_TIME / _rate_mult:
			_gauss_charge = 0.0
			_fire_gauss()
	if _lasgun_active:
		_fire_lasgun(delta)
	elif _beam != null:
		_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
	_tick_bullets(delta)
	_tick_orbs(delta)
	_update_charge_rings(delta)
	_update_sparks(delta)
	_update_flashes(delta)
	queue_redraw()

# ── Aim helpers ───────────────────────────────────────────────────────────────
func _forward() -> Vector2:
	return Vector2.UP.rotated(_player.rotation)

func _muzzle() -> Vector2:
	return _player.global_position + _forward() * MUZZLE_OFFSET

# ── Gatling — twin wing streams ─────────────────────────────────────────────────
func _fire_gatling() -> void:
	# Two parallel streams from the left/right wing muzzles. Offsets are in the ship's local frame (fwd/perp),
	# so they rotate with the aim. Both fire in the facing direction (not converging) → twin wing guns.
	var fwd := _forward()
	var perp := Vector2(-fwd.y, fwd.x)   # right-perpendicular (rotates with the ship)
	var base := _player.global_position + fwd * GAT_WING_FWD
	for side: float in [-1.0, 1.0]:
		var dir := fwd
		if GAT_SPREAD_DEG > 0.0:
			dir = fwd.rotated(deg_to_rad(randf_range(-GAT_SPREAD_DEG, GAT_SPREAD_DEG)))   # independent per-stream spray
		var start: Vector2 = base + perp * (side * GAT_WING_SPACING * 0.5)
		_bullets.append({"pos": start, "vel": dir * GAT_SPEED, "life": 0.0, "start": start})

# ── Lasgun (tick-based hitscan beam — fires along the ship facing = toward the cursor) ───────────────────
func _fire_lasgun(delta: float) -> void:
	# Duty cycle: fire for LASGUN_DURATION out of every LASGUN_CYCLE seconds, with a charge telegraph in the
	# last LASGUN_CHARGE seconds before each burst.
	_las_t += delta
	var phase := fmod(_las_t, LASGUN_CYCLE)
	var firing := phase < LASGUN_DURATION
	if not firing:
		# Charge telegraph (Chromeleon orb light-gather) in the last LASGUN_CHARGE seconds before the burst.
		var charge_start := LASGUN_CYCLE - LASGUN_CHARGE
		if phase >= charge_start and _charge_fx != null:
			_charge_fx.position = _muzzle()   # follow the moving nose
			if not _las_charge_started:
				_charge_fx.start(LASGUN_CHARGE)
				_las_charge_started = true
		if _beam != null:
			_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
		_beam_cd = 0.0   # so the first damage tick lands the instant the burst starts
		return
	# Firing: kill the charge FX and arm the next cycle's telegraph.
	_las_charge_started = false
	if _charge_fx != null:
		_charge_fx.stop()
	var from := _muzzle()
	var dir := _forward()
	# Nearest enemy along the beam line (distance-to-line within range), like the legacy first-hit beam.
	var best_along := LASGUN_RANGE
	var best: Node = null
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var to_e: Vector2 = (en as Node2D).global_position - from
		var along := to_e.dot(dir)
		if along < 0.0 or along > LASGUN_RANGE:
			continue
		var perp_d := (to_e - dir * along).length()
		if perp_d <= LASGUN_WIDTH * 0.5 + LASGUN_HIT_PAD and along < best_along:
			best_along = along
			best = en
	var hit := best != null
	var end_along: float = (best_along - LASGUN_HIT_PAD) if hit else LASGUN_RANGE   # terminate at the surface
	var to_pt := from + dir * maxf(0.0, end_along)
	if _beam != null:
		_beam.set_beam(from, to_pt, true, hit)
	# Tick damage (one apply per interval → no per-frame double-hit; damage_mult + fire_rate_mult both apply).
	_beam_cd -= delta
	if _beam_cd <= 0.0:
		if hit and best.has_method("take_damage"):
			best.take_damage(LASGUN_DAMAGE * _dmg_mult, LASGUN_STAGGER)
		_beam_cd = LASGUN_TICK / _rate_mult

## Called by the Lasgun pickup on collection — adds the beam to the active loadout (accumulates with Gatling).
func activate_lasgun() -> void:
	_lasgun_active = true
	_las_t = LASGUN_CYCLE - LASGUN_CHARGE   # begin in the charge window → telegraph, then the first burst

## Debug (F12): drop a Lasgun pickup at a world position on the gameplay plane.
func spawn_lasgun_pickup_near(world_pos: Vector2) -> void:
	var p := PickupScript.new()
	p.add_to_group("debug_weapon_pickup")
	get_parent().add_child(p)
	p.setup(world_pos, "lasgun")

func _tick_bullets(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var p: Vector2 = b["pos"]
		var dead := float(b["life"]) >= GAT_LIFETIME or p.distance_to(b["start"]) >= GAT_MAX_DIST
		if not dead:
			for en in enemies:
				if is_instance_valid(en) and p.distance_to((en as Node2D).global_position) <= GAT_HIT_RADIUS:
					if en.has_method("take_damage"):
						en.take_damage(GAT_DAMAGE * _dmg_mult, GAT_STAGGER)
					dead = true
					break
		if dead:
			_bullets.remove_at(i)
		i -= 1

# ── Gauss ─────────────────────────────────────────────────────────────────────
func _fire_gauss() -> void:
	var dir := _forward()
	var start := _muzzle()
	var orb := _make_orb()
	var o := {
		"pos": start, "vel": dir * GAUSS_SPEED, "life": 0.0, "start": start,
		"orb_node": orb, "trail": [], "spark_acc": 0.0, "pierce_left": GAUSS_PIERCE, "hit": [],
	}
	_orbs.append(o)
	_update_orb_node(o)
	_flashes.append({"pos": start, "age": 0.0, "max_age": 0.30, "radius": GAUSS_LAUNCH_FLASH})
	# Clear the converging rings and pop the release flash (charge cycle restarts).
	_charge_rings.clear()
	_charge_spawn_acc = 0.0
	if GC_RELEASE_FLASH > 0.0:
		_flashes.append({"pos": _muzzle(), "age": 0.0, "max_age": 0.30, "radius": GC_RELEASE_FLASH})

func _tick_orbs(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var i := _orbs.size() - 1
	while i >= 0:
		var o: Dictionary = _orbs[i]
		o["pos"] = (o["pos"] as Vector2) + (o["vel"] as Vector2) * delta
		o["life"] = float(o["life"]) + delta
		_update_orb_node(o)
		_shed_sparks(o, delta)
		var p: Vector2 = o["pos"]
		var dead := float(o["life"]) >= GAUSS_LIFETIME or p.distance_to(o["start"]) >= GAUSS_MAX_DIST
		# Pierce: damage each enemy once, decrementing the pierce budget.
		if not dead:
			var hit: Array = o["hit"]
			for en in enemies:
				if not is_instance_valid(en):
					continue
				var id := (en as Node2D).get_instance_id()
				if id in hit:
					continue
				if p.distance_to((en as Node2D).global_position) <= GAUSS_RADIUS + 8.0:
					if en.has_method("take_damage"):
						en.take_damage(GAUSS_DAMAGE * _dmg_mult, GAUSS_STAGGER)
					hit.append(id)
					o["pierce_left"] = int(o["pierce_left"]) - 1
					if int(o["pierce_left"]) <= 0:
						dead = true
						break
		if dead:
			_free_orb(o)
			_orbs.remove_at(i)
		i -= 1

func _make_orb() -> ColorRect:
	if _orb_shader == null:
		_orb_shader = Shader.new()
		_orb_shader.code = GAUSS_ORB_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _orb_shader
	mat.set_shader_parameter("core_color", GAUSS_ORB_CORE_COL)
	mat.set_shader_parameter("light_color", GAUSS_ORB_LIGHT_COL)
	mat.set_shader_parameter("haze_color", GAUSS_ORB_HAZE_COL)
	mat.set_shader_parameter("tear_width", GAUSS_ORB_TEAR_WIDTH)
	mat.set_shader_parameter("core_width", GAUSS_ORB_CORE_WIDTH)
	mat.set_shader_parameter("core_bright", GAUSS_ORB_CORE_BRIGHT)
	mat.set_shader_parameter("light_density", GAUSS_ORB_LIGHT_DENSITY)
	mat.set_shader_parameter("crackle_speed", GAUSS_ORB_CRACKLE_SPEED)
	mat.set_shader_parameter("haze_size", GAUSS_ORB_HAZE_SIZE)
	mat.set_shader_parameter("glow", GAUSS_ORB_GLOW)
	var cr := ColorRect.new()
	cr.material = mat
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cr)
	return cr

func _update_orb_node(o: Dictionary) -> void:
	var trail: Array = o.get("trail", [])
	trail.push_front(o["pos"])
	if trail.size() > GAUSS_TRAIL_LEN:
		trail.resize(GAUSS_TRAIL_LEN)
	o["trail"] = trail
	var cr := o.get("orb_node") as ColorRect
	if cr == null or not is_instance_valid(cr):
		return
	var qhalf := GAUSS_RADIUS * GAUSS_ORB_QUAD
	var w := qhalf * 2.0 * GAUSS_ORB_STRETCH
	var h := qhalf * 2.0
	cr.size = Vector2(w, h)
	cr.pivot_offset = Vector2(w, h) * 0.5
	var v: Vector2 = o["vel"]
	cr.rotation = v.angle() if v.length() > 0.01 else 0.0
	cr.position = (o["pos"] as Vector2) - Vector2(w, h) * 0.5

func _free_orb(o: Dictionary) -> void:
	var cr := o.get("orb_node") as ColorRect
	if cr != null and is_instance_valid(cr):
		cr.queue_free()
	o["orb_node"] = null

func _shed_sparks(o: Dictionary, delta: float) -> void:
	var v: Vector2 = o["vel"]
	if v.length() < 0.01:
		return
	var dir := v.normalized()
	var tail: Vector2 = (o["pos"] as Vector2) - dir * (GAUSS_RADIUS * GAUSS_ORB_QUAD * GAUSS_ORB_STRETCH * 0.85)
	o["spark_acc"] = float(o.get("spark_acc", 0.0)) + GAUSS_SPARK_RATE * delta
	while float(o["spark_acc"]) >= 1.0:
		o["spark_acc"] = float(o["spark_acc"]) - 1.0
		var jit := Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
		var sv := (-dir + jit).normalized() * GAUSS_SPARK_SPEED * randf_range(0.6, 1.25)
		_sparks.append({"pos": tail, "vel": sv, "life": 0.0, "ttl": GAUSS_SPARK_LIFE * randf_range(0.7, 1.2)})

func _update_sparks(delta: float) -> void:
	var i := _sparks.size() - 1
	while i >= 0:
		var s: Dictionary = _sparks[i]
		s["life"] = float(s["life"]) + delta
		if float(s["life"]) >= float(s["ttl"]):
			_sparks.remove_at(i)
		else:
			s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		i -= 1

# ── Gauss charge rings (auto-charge: charging is always true between shots) ────
func _update_charge_rings(delta: float) -> void:
	if not GAUSS_ENABLED:
		return
	var frac := clampf(_gauss_charge / maxf(0.01, GAUSS_CHARGE_TIME), 0.0, 1.0)
	var focal := _muzzle()
	var interval := lerpf(GC_INTERVAL_EMPTY, GC_INTERVAL_FULL, pow(frac, GC_RAMP_CURVE))
	_charge_spawn_acc += delta
	while _charge_spawn_acc >= interval:
		_charge_spawn_acc -= interval
		for _k in GC_SPAWN_COUNT:
			_charge_rings.append({"ang": randf() * TAU, "r": GC_START_RADIUS * randf_range(0.85, 1.12)})
	var spd := lerpf(GC_SPEED_EMPTY, GC_SPEED_FULL, frac)
	var i := _charge_rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _charge_rings[i]
		ring["r"] = float(ring["r"]) - spd * delta
		if float(ring["r"]) <= GC_FLASH_R:
			_flashes.append({"pos": focal, "age": 0.0, "max_age": 0.16, "radius": GC_FLASH_R * 2.2})
			_charge_rings.remove_at(i)
		i -= 1

func _update_flashes(delta: float) -> void:
	var i := _flashes.size() - 1
	while i >= 0:
		var f: Dictionary = _flashes[i]
		f["age"] = float(f["age"]) + delta
		if float(f["age"]) >= float(f["max_age"]):
			_flashes.remove_at(i)
		i -= 1

# ── Drawing (world-space; this node sits at the origin) ────────────────────────
func _draw() -> void:
	# Charge rings + comet trails + sparks draw UNDER the orb ColorRect children.
	_draw_charge_rings()
	for o: Dictionary in _orbs:
		_draw_gauss_trail(o)
	_draw_sparks()
	for b: Dictionary in _bullets:
		_draw_tracer(b["pos"], b["vel"])
	_draw_flashes()

func _draw_tracer(p: Vector2, vel: Vector2) -> void:
	var dir := (vel as Vector2).normalized() if (vel as Vector2).length() > 0.01 else Vector2.UP
	var ca := dir.x
	var sa := dir.y
	var s := GAT_TRACER_SCALE
	var hl := GAT_TRACER_LEN * 0.5 * s
	var hw := GAT_TRACER_WIDTH * 0.5 * s
	var tail_steps := 5
	for i in range(tail_steps, 0, -1):
		var f := float(i) / float(tail_steps)
		var tp := p - dir * (GAT_TAIL_LEN * s * f)
		var ta := GAT_GLOW_INTENSITY * (1.0 - f) * 0.7
		draw_circle(tp, hw * (1.0 - 0.6 * f), Color(GAT_EDGE_COL.r, GAT_EDGE_COL.g, GAT_EDGE_COL.b, ta))
	draw_colored_polygon(_oblong(p, hl * GAT_GLOW_SIZE, hw * GAT_GLOW_SIZE, ca, sa, 20),
		Color(GAT_EDGE_COL.r, GAT_EDGE_COL.g, GAT_EDGE_COL.b, GAT_GLOW_INTENSITY * 0.5))
	draw_colored_polygon(_oblong(p, hl * GAT_GLOW_SIZE * 0.6, hw * GAT_GLOW_SIZE * 0.6, ca, sa, 20),
		Color(GAT_BODY_COL.r, GAT_BODY_COL.g, GAT_BODY_COL.b, GAT_GLOW_INTENSITY))
	draw_colored_polygon(_oblong(p, hl, hw, ca, sa, 18), GAT_EDGE_COL)
	draw_colored_polygon(_oblong(p, hl * 0.72, hw * 0.72, ca, sa, 18), GAT_BODY_COL)
	var head := p + dir * (hl * 0.28)
	draw_colored_polygon(_oblong(head, hl * 0.42, hw * 0.5, ca, sa, 16), GAT_CORE_COL)

func _oblong(c: Vector2, rx: float, ry: float, ca: float, sa: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segs)
	for i in segs:
		var t := TAU * float(i) / float(segs)
		var x := rx * cos(t)
		var y := ry * sin(t)
		pts[i] = c + Vector2(x * ca - y * sa, x * sa + y * ca)
	return pts

func _draw_gauss_trail(o: Dictionary) -> void:
	var trail: Array = o.get("trail", [])
	var n := trail.size()
	if n < 2:
		return
	var base_w := GAUSS_RADIUS * GAUSS_TRAIL_WIDTH
	var c := GAUSS_TRAIL_COL
	for i in range(n - 1, 0, -1):
		var f := float(i) / float(n - 1)
		var fade := 1.0 - f
		var w := base_w * (0.3 + 0.7 * fade)
		if w < 0.5:
			continue
		var pa: Vector2 = trail[i]
		draw_circle(pa, w * 1.6, Color(c.r, c.g, c.b, GAUSS_TRAIL_ALPHA * 0.22 * fade))
		draw_circle(pa, w, Color(c.r, c.g, c.b, GAUSS_TRAIL_ALPHA * 0.55 * fade))
		draw_circle(pa, w * 0.45, Color(1.0, 0.88, 0.9, GAUSS_TRAIL_ALPHA * 0.7 * fade))

func _draw_sparks() -> void:
	var c := GAUSS_SPARK_COL
	for s: Dictionary in _sparks:
		var t := clampf(1.0 - float(s["life"]) / maxf(0.01, float(s["ttl"])), 0.0, 1.0)
		var p: Vector2 = s["pos"]
		var v: Vector2 = s["vel"]
		var tail := p - (v.normalized() * GAUSS_SPARK_LEN if v.length() > 0.01 else Vector2.ZERO)
		draw_line(tail, p, Color(c.r, c.g, c.b, GAUSS_SPARK_ALPHA * t), 2.0)
		draw_circle(p, 1.6 * t + 0.5, Color(1.0, 1.0, 1.0, GAUSS_SPARK_ALPHA * t))

func _draw_charge_rings() -> void:
	if _charge_rings.is_empty():
		return
	var focal := _muzzle()
	for ring: Dictionary in _charge_rings:
		var r: float = ring["r"]
		var t := clampf(1.0 - r / GC_START_RADIUS, 0.0, 1.0)
		var pos := focal + Vector2(cos(float(ring["ang"])), sin(float(ring["ang"]))) * r
		var col := GC_COL_OUT.lerp(GC_COL_IN, t)
		var a := GC_BRIGHT * (0.12 + 0.88 * t)
		var rs := GC_RING_SIZE * (0.3 + 0.7 * (1.0 - t))
		draw_arc(pos, rs * 1.4, 0.0, TAU, 16, Color(col.r, col.g, col.b, a * 0.3), 2.0)
		draw_arc(pos, rs, 0.0, TAU, 16, Color(col.r, col.g, col.b, a), 2.0)
		draw_circle(pos, rs * 0.35, Color(col.r, col.g, col.b, a * 0.5))

func _draw_flashes() -> void:
	for f: Dictionary in _flashes:
		var t := clampf(1.0 - float(f["age"]) / maxf(0.01, float(f["max_age"])), 0.0, 1.0)
		var pos: Vector2 = f["pos"]
		var r := float(f["radius"]) * (0.4 + 0.6 * (1.0 - t))   # expands as it fades
		draw_circle(pos, r, Color(0.7, 0.85, 1.0, 0.25 * t))
		draw_circle(pos, r * 0.5, Color(1.0, 1.0, 1.0, 0.5 * t))
