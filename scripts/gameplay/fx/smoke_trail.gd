extends Node2D
## SmokeTrail — a burning-wreck wake built to read like hand-authored 2D VFX (Hades / Dead Cells family)
## WITHOUT any baked flipbook art: the quality lives in the draw shaders, not in sprite sheets.
##
## Layers (all world-space `CPUParticles2D` — `local_coords = false` — so puffs stay put and the creep's
## motion strings them into a tail; + one pulsing glow `Sprite2D`):
##   • smoke  — smoke_trail.gdshader: domain-warped, TIME-evolving fractal noise ("boil"), relief lighting
##              from the noise gradient (fake volumetric read, lit from the fire side), age-driven erosion.
##   • ash    — fine dark turbulent motes, a few cinder-tinted.
##   • embers — smoke_ember.gdshader: flickering additive HDR sparks that streak along their motion.
##   • flame  — smoke_flame.gdshader: a soft flame blob eroded into licking tongues at the source.
##   • glow   — additive Sprite2D, alpha + scale pulsed by layered sines.
##
## Per-particle decorrelation: a random seed is packed into the smoke's colour as COLOR.r/COLOR.g (a neutral
## grey `color_ramp` × a `color_initial_ramp` that only scales RED 0.5→1.5), recovered in the shader.
##
## Attached as a child of an arena_enemy (arena_enemy.gd `_setup_smoke()` / def flag "smoke_trail"). `_die()`
## calls detach() so the wake already in the air finishes dissipating.
##
## NOTE: no `class_name` — preload + .new(), type the var Node2D, call setup() dynamically.

const SMOKE_SHADER := "res://scripts/gameplay/fx/smoke_trail.gdshader"
const EMBER_SHADER := "res://scripts/gameplay/fx/smoke_ember.gdshader"
const FLAME_SHADER := "res://scripts/gameplay/fx/smoke_flame.gdshader"

const PUFF_TEX_N  := 64
const NOISE_TEX_N := 192   # seamless FBM for the shaders (baked once, shared, synchronous)
const EMBER_TEX_N := 24
const ASH_TEX_N   := 8
const FLAME_TEX_N := 96
const GLOW_TEX_N  := 128

# Shared — baked once, identical for every instance.
static var _puff_tex: Texture2D = null
static var _fbm_tex: Texture2D = null
static var _ember_tex: Texture2D = null
static var _ash_tex: Texture2D = null
static var _flame_tex: Texture2D = null
static var _glow_tex: Texture2D = null
static var _smoke_shader: Shader = null
static var _ember_shader: Shader = null
static var _flame_shader: Shader = null

var _smoke: CPUParticles2D = null
var _ash: CPUParticles2D = null
var _embers: CPUParticles2D = null
var _flame: CPUParticles2D = null
var _glow: Sprite2D = null

## Live SmokeTrail count — crowd LOD (a full fleet of ash creeps each with a 5-layer composite is heavy, so
## the effect thins itself the more of them are on the field).
static var _active: int = 0

var _life: float = 3.0
var _dir_rot: float = 0.0   # radians — style "dir": rotates every layer's emission direction/gravity.
                            # 0 = the stock "billow downward" wake; a smoke POINT on a 3D boss sets this
                            # from its authored `dir_rot` so the plume sprays the way the editor showed.
var _follow: bool = false   # style "follow": layers ride the emitter node (local_coords) so the cloud tracks it
var _emitting_on: bool = true
var _detaching: bool = false
var _detach_t: float = 0.0
var _t: float = 0.0
var _lod_acc: float = 0.3
var _lod_tier: int = -1
var _slot: int = 0          # spawn order among live SmokeTrails — used as a VFX budget rank when crowded
var _over_budget: bool = false
var _glow_a: float = 0.0
var _glow_cur: float = 0.0
var _glow_base_scale: Vector2 = Vector2.ONE

## width_px — the creep's on-screen draw width; scales sizes + particle counts. `style` overrides tunables.
func setup(width_px: float, style: Dictionary = {}) -> void:
	var w: float = maxf(width_px, 8.0)
	_life = float(style.get("lifetime", 3.0))
	_dir_rot = float(style.get("dir", 0.0))
	# style "follow" (2026-09-02): every layer rides the emitter node instead of hanging in world space, so
	# the cloud stays CENTRED on whatever it's parented to even as that thing moves. Nautilus's Move 4
	# smokescreen needs this — a world-space cloud trails behind the boss the moment it starts retreating and
	# stops hiding it ("khói xì ra chưa bao được hết nautilus khi nó chạy lùi").
	_follow = bool(style.get("follow", false))
	_ensure_assets()
	_build_smoke(w, style)
	_build_ash(w, style)
	# style "no_fire" (2026-09-02): drop the three FIRE-coloured layers. Nautilus's Move 4 smokescreen is a
	# cold white-blue coolant cloud — orange embers/flame/glow would read completely wrong on it.
	if not bool(style.get("no_fire", false)):
		_build_embers(w, style)
		_build_flame(w, style)
		_build_glow(w, style)
	_slot = _active
	_active += 1
	set_process(true)

func _exit_tree() -> void:
	_active = maxi(0, _active - 1)

## Crowd LOD: a full ash fleet is many 5-layer composites at once. As more SmokeTrails go live, drop the
## cheaper accent layers and switch the smoke shader to its `cheap` path (no relief-lighting texture reads).
## `CPUParticles2D` has no `amount_ratio` and setting `amount` restarts the sim (visible pop) — so we toggle
## whole layers + a shader flag instead of thinning particle counts. Throttled (~3×/s from _process).
func _apply_detail() -> void:
	var tier := 0
	if _active > 16:   tier = 3
	elif _active > 9:  tier = 2
	elif _active > 4:  tier = 1
	if tier == _lod_tier:
		return
	_lod_tier = tier
	# Fill-rate + CPU particle sim is the real cost with a big stacked fleet. VFX-budget style: past a rank
	# among live SmokeTrails, the lower-ranked ones keep ONLY the glow sprite (the "this thing is on fire"
	# tell — 1 cheap additive quad); everything else is hidden + stops simulating. Re-revealed monotonically
	# as the crowd thins (tier drops).
	var budget: int = [999, 999, 12, 7][tier]
	_over_budget = tier >= 2 and _slot >= budget
	if _smoke != null and is_instance_valid(_smoke):
		_smoke.visible = not _over_budget
		if _smoke.material is ShaderMaterial:
			(_smoke.material as ShaderMaterial).set_shader_parameter("cheap", tier >= 2)
	if _ash != null and is_instance_valid(_ash):
		_ash.visible = not _over_budget
	if _embers != null and is_instance_valid(_embers):
		_embers.visible = tier < 3 and not _over_budget
	if _flame != null and is_instance_valid(_flame):
		_flame.visible = tier <= 1 and not _over_budget
	_reconcile_emitters()

## Single place that turns emitters on/off — honours both the caller's intent (_emitting_on), the death
## state (_detaching), and the crowd-LOD tier.
func _reconcile_emitters() -> void:
	var e := _emitting_on and not _detaching
	for p in [_smoke, _ash, _embers, _flame]:
		if p != null and is_instance_valid(p):
			p.emitting = e and p.visible   # hidden (LOD budget / tier) → also stop simulating

# ── Smoke ────────────────────────────────────────────────────────────────────
func _build_smoke(w: float, style: Dictionary) -> void:
	var p := CPUParticles2D.new()
	p.local_coords = _follow
	p.emitting = true
	p.z_as_relative = true
	p.z_index = -3
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.lifetime = _life
	p.lifetime_randomness = 0.45
	p.randomness = 0.7
	p.amount = clampi(int(w / 1.5), 26, 84)
	p.gravity = Vector2.ZERO
	p.direction = Vector2(0.0, 1.0).rotated(_dir_rot)
	p.spread = float(style.get("spread", 42.0))
	p.initial_velocity_min = float(style.get("vel_min", 2.0))
	p.initial_velocity_max = float(style.get("vel_max", 13.0))
	p.tangential_accel_min = -26.0
	p.tangential_accel_max = 26.0
	p.radial_accel_min = -8.0
	p.radial_accel_max = 5.0
	p.damping_min = 5.0
	p.damping_max = 15.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -18.0
	p.angular_velocity_max = 18.0

	var base := w / float(PUFF_TEX_N)
	p.scale_amount_min = base * float(style.get("scale_min", 1.0))
	p.scale_amount_max = base * float(style.get("scale_max", 2.3))
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.34))
	grow.add_point(Vector2(0.4, 1.0))
	grow.add_point(Vector2(1.0, 2.3))
	p.scale_amount_curve = grow

	# NEUTRAL grey value fade — the shader does all tinting/lighting. Alpha monotonic after the brief fade-in
	# so the shader reads (1 - a/peak) as age.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.05, 0.45, 0.78, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.95),
		Color(1, 1, 1, 0.78),
		Color(1, 1, 1, 0.40),
		Color(1, 1, 1, 0.0),
	])
	p.color_ramp = g
	# Per-particle seed: scale ONLY red 0.5→1.5, so COLOR.r/COLOR.g recovers a 0..1 random in the shader.
	var ig := Gradient.new()
	ig.colors = PackedColorArray([Color(0.5, 1.0, 1.0, 1.0), Color(1.5, 1.0, 1.0, 1.0)])
	p.color_initial_ramp = ig

	p.texture = _puff_tex
	var mat := ShaderMaterial.new()
	mat.shader = _smoke_shader
	mat.set_shader_parameter("fbm_tex", _fbm_tex)
	mat.set_shader_parameter("peak_alpha", 0.95)
	# The shader owns ALL the tinting (the particle ramp above is neutral grey) — so a caller recolours the
	# smoke by overriding its 3-tone palette here, not by modulating. 2026-09-02: Nautilus's Move 4 passes a
	# white-blue set; omitting them keeps the stock volcanic soot.
	for k: String in ["c_shadow", "c_body", "c_lit"]:
		if style.has(k):
			var c: Color = style[k]
			mat.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
	p.material = mat
	add_child(p)
	_smoke = p

# ── Ash motes ────────────────────────────────────────────────────────────────
func _build_ash(w: float, _style: Dictionary) -> void:
	var p := CPUParticles2D.new()
	p.local_coords = _follow
	p.emitting = true
	p.z_as_relative = true
	p.z_index = -1
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.lifetime = _life * 0.7
	p.lifetime_randomness = 0.6
	p.randomness = 0.9
	p.amount = clampi(int(w / 3.4), 12, 40)
	p.gravity = Vector2(0.0, -4.0).rotated(_dir_rot)
	p.direction = Vector2(0.0, 1.0).rotated(_dir_rot)
	p.spread = 180.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 34.0
	p.tangential_accel_min = -42.0
	p.tangential_accel_max = 42.0
	p.radial_accel_min = -14.0
	p.radial_accel_max = 20.0
	p.damping_min = 2.0
	p.damping_max = 9.0
	p.angular_velocity_min = -160.0
	p.angular_velocity_max = 160.0
	var base := w / float(ASH_TEX_N)
	p.scale_amount_min = base * 0.3
	p.scale_amount_max = base * 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.45))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(0.13, 0.12, 0.12, 0.0),
		Color(0.15, 0.14, 0.13, 0.75),
		Color(0.3, 0.28, 0.27, 0.4),
		Color(0.42, 0.4, 0.38, 0.0),
	])
	p.color_ramp = g
	var ig := Gradient.new()
	ig.offsets = PackedFloat32Array([0.0, 0.74, 0.9, 1.0])
	ig.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 1),
		Color(2.0, 0.8, 0.3, 1), Color(2.6, 1.0, 0.35, 1),
	])
	p.color_initial_ramp = ig
	p.texture = _ash_tex
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	p.material = cm
	add_child(p)
	_ash = p

# ── Embers ───────────────────────────────────────────────────────────────────
func _build_embers(w: float, _style: Dictionary) -> void:
	var p := CPUParticles2D.new()
	p.local_coords = _follow
	p.emitting = true
	p.z_as_relative = true
	p.z_index = 0
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.lifetime = 1.2
	p.lifetime_randomness = 0.55
	p.randomness = 0.85
	p.amount = clampi(int(w / 5.5), 6, 22)
	p.gravity = Vector2(0.0, -14.0).rotated(_dir_rot)
	p.direction = Vector2(0.0, -1.0).rotated(_dir_rot)
	p.spread = 80.0
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 78.0
	p.tangential_accel_min = -70.0
	p.tangential_accel_max = 70.0
	p.damping_min = 12.0
	p.damping_max = 40.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.particle_flag_align_y = true
	var base := w / float(EMBER_TEX_N)
	p.scale_amount_min = base * 0.22
	p.scale_amount_max = base * 0.62
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.9))
	sc.add_point(Vector2(0.45, 1.0))
	sc.add_point(Vector2(1.0, 0.12))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 0.8, 1.0])
	g.colors = PackedColorArray([
		Color(2.2, 1.7, 1.0, 1.0),
		Color(2.0, 0.9, 0.30, 1.0),
		Color(1.25, 0.36, 0.09, 1.0),
		Color(0.55, 0.09, 0.0, 0.7),
		Color(0.2, 0.0, 0.0, 0.0),
	])
	p.color_ramp = g
	var ig := Gradient.new()
	ig.colors = PackedColorArray([Color(0.5, 0.5, 0.5, 1), Color(1.4, 1.35, 1.3, 1)])
	p.color_initial_ramp = ig
	p.texture = _ember_tex
	var mat := ShaderMaterial.new()
	mat.shader = _ember_shader
	p.material = mat
	add_child(p)
	_embers = p

# ── Source flame ─────────────────────────────────────────────────────────────
func _build_flame(w: float, _style: Dictionary) -> void:
	var p := CPUParticles2D.new()
	p.local_coords = _follow
	p.emitting = true
	p.z_as_relative = true
	p.z_index = -1
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	p.lifetime = 0.55
	p.lifetime_randomness = 0.5
	p.randomness = 0.6
	p.amount = clampi(int(w / 3.6), 9, 28)
	p.explosiveness = 0.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = w * 0.11
	p.gravity = Vector2(0.0, -26.0).rotated(_dir_rot)
	p.direction = Vector2(0.0, -1.0).rotated(_dir_rot)
	p.spread = 30.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 50.0
	p.damping_min = 9.0
	p.damping_max = 28.0
	p.angle_min = -25.0
	p.angle_max = 25.0
	var base := w / float(FLAME_TEX_N)
	p.scale_amount_min = base * 0.42
	p.scale_amount_max = base * 0.9
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.35))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	g.colors = PackedColorArray([
		Color(2.4, 1.9, 1.1, 1.0),
		Color(2.2, 1.0, 0.32, 1.0),
		Color(1.3, 0.32, 0.06, 0.9),
		Color(0.5, 0.05, 0.0, 0.0),
	])
	p.color_ramp = g
	p.texture = _flame_tex
	var mat := ShaderMaterial.new()
	mat.shader = _flame_shader
	mat.set_shader_parameter("fbm_tex", _fbm_tex)
	p.material = mat
	add_child(p)
	_flame = p

# ── Source glow ──────────────────────────────────────────────────────────────
func _build_glow(w: float, _style: Dictionary) -> void:
	var s := Sprite2D.new()
	s.texture = _glow_tex
	s.z_as_relative = true
	s.z_index = -2
	s.modulate = Color(1.5, 0.6, 0.22, 1.0)
	s.self_modulate = Color(1, 1, 1, 0.0)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = cm
	_glow_base_scale = Vector2.ONE * (w * 1.15 / float(GLOW_TEX_N))
	s.scale = _glow_base_scale
	_glow_a = 0.5
	add_child(s)
	_glow = s

# ── Public API ───────────────────────────────────────────────────────────────
func set_emitting(on: bool) -> void:
	_emitting_on = on
	_reconcile_emitters()

## arena_enemy._die(): reparent (keep world xform), stop emitters, fade the glow, free after the last puff dies.
func detach(new_parent: Node) -> void:
	_detaching = true
	_reconcile_emitters()
	if new_parent != null and is_instance_valid(new_parent) and get_parent() != new_parent:
		var gx := global_position
		get_parent().remove_child(self)
		new_parent.add_child(self)
		global_position = gx

func _process(delta: float) -> void:
	_t += delta
	_lod_acc += delta
	if _lod_acc >= 0.33:
		_lod_acc = 0.0
		_apply_detail()
	if _glow != null and is_instance_valid(_glow):
		var target: float = _glow_a if (_emitting_on and not _detaching) else 0.0
		_glow_cur = move_toward(_glow_cur, target, delta * (2.0 if target > 0.0 else 3.5))
		var flick: float = 0.64 + 0.22 * sin(_t * 10.7) + 0.14 * sin(_t * 26.9 + 1.3)
		_glow.self_modulate.a = _glow_cur * clampf(flick, 0.2, 1.1)
		_glow.scale = _glow_base_scale * (0.92 + 0.08 * sin(_t * 5.1))
	if _detaching:
		_detach_t += delta
		if _detach_t >= _life + 0.6:
			queue_free()

# ── Baked assets ─────────────────────────────────────────────────────────────
## Public static accessors so other VFX (e.g. volcanic_clouds.gd's ground plumes) can reuse the exact same
## shaders + baked FBM/puff textures without instancing a whole SmokeTrail node.
static func shared_smoke_shader() -> Shader:
	if _smoke_shader == null: _smoke_shader = load(SMOKE_SHADER) as Shader
	return _smoke_shader
static func shared_flame_shader() -> Shader:
	if _flame_shader == null: _flame_shader = load(FLAME_SHADER) as Shader
	return _flame_shader
static func shared_ember_shader() -> Shader:
	if _ember_shader == null: _ember_shader = load(EMBER_SHADER) as Shader
	return _ember_shader
static func shared_fbm_tex() -> Texture2D:
	if _fbm_tex == null: _fbm_tex = _bake_fbm2(0.018, 0.030, 5, 1337, 5501)
	return _fbm_tex
static func shared_puff_tex() -> Texture2D:
	if _puff_tex == null: _puff_tex = _bake_puff()
	return _puff_tex
## A per-particle-seed gradient — scales only RED 0.5→1.5. Put on a CPUParticles2D's `color_initial_ramp`
## so the smoke_trail shader can recover a per-particle random from COLOR.r/COLOR.g (see its header).
static func seed_initial_ramp() -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.5, 1.0, 1.0, 1.0), Color(1.5, 1.0, 1.0, 1.0)])
	return g

func _ensure_assets() -> void:
	if _smoke_shader == null:
		_smoke_shader = load(SMOKE_SHADER) as Shader
	if _ember_shader == null:
		_ember_shader = load(EMBER_SHADER) as Shader
	if _flame_shader == null:
		_flame_shader = load(FLAME_SHADER) as Shader
	if _fbm_tex == null:
		_fbm_tex = _bake_fbm2(0.018, 0.030, 5, 1337, 5501)
	if _puff_tex == null:
		_puff_tex = _bake_puff()
	if _ember_tex == null:
		_ember_tex = _bake_dot(EMBER_TEX_N, 2.0, 0.0)
	if _ash_tex == null:
		_ash_tex = _bake_dot(ASH_TEX_N, 1.3, 0.0)
	if _flame_tex == null:
		_flame_tex = _bake_dot(FLAME_TEX_N, 1.5, 0.15)
	if _glow_tex == null:
		_glow_tex = _bake_dot(GLOW_TEX_N, 2.6, 0.0)

## TWO independent seamless FBM fields packed into .r / .g of one ImageTexture (so the shader gets a 2D
## domain-warp vector from a single sample). Synchronous → ready frame 1; wrap-blended → tiles without a seam.
static func _bake_fbm2(freq_r: float, freq_g: float, octaves: int, seed_r: int, seed_g: int) -> Texture2D:
	var N := NOISE_TEX_N
	var chan_r := _fbm_field(freq_r, octaves, seed_r, N)
	var chan_g := _fbm_field(freq_g, octaves, seed_g, N)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			img.set_pixel(x, y, Color(chan_r[y * N + x], chan_g[y * N + x], 0.0, 1.0))
	return ImageTexture.create_from_image(img)

## One normalized, wrap-blended (seamless) FBM field as a PackedFloat32Array of N×N values in [0,1].
static func _fbm_field(freq: float, octaves: int, seed: int, N: int) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = freq
	n.seed = seed
	var raw := PackedFloat32Array()
	raw.resize(N * N)
	var lo := 999.0
	var hi := -999.0
	for y in N:
		for x in N:
			var s := n.get_noise_2d(float(x), float(y))
			raw[y * N + x] = s
			lo = minf(lo, s)
			hi = maxf(hi, s)
	var inv := 1.0 / maxf(0.0001, hi - lo)
	var out := PackedFloat32Array()
	out.resize(N * N)
	for y in N:
		for x in N:
			var fx := float(x) / float(N)
			var fy := float(y) / float(N)
			var xw := (x + N / 2) % N
			var yw := (y + N / 2) % N
			var e: float = (raw[y * N + x] - lo) * inv
			var a: float = (raw[y * N + xw] - lo) * inv
			var b: float = (raw[yw * N + x] - lo) * inv
			var c: float = (raw[yw * N + xw] - lo) * inv
			out[y * N + x] = e * (1.0 - fx) * (1.0 - fy) + a * fx * (1.0 - fy) \
					+ b * (1.0 - fx) * fy + c * fx * fy
	return out

## FBM "cauliflower" puff: radial falloff × fractal noise → turbulent internal structure, not a gaussian.
static func _bake_puff() -> Texture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.frequency = 0.045
	n.seed = 91
	var N := PUFF_TEX_N
	var c := float(N) * 0.5
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var fall := clampf(1.0 - d, 0.0, 1.0)
			fall = fall * fall
			var fb := clampf(n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)
			var a := clampf(fall * (0.4 + 0.9 * pow(fb, 1.2)), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## Soft radial dot (white / alpha only). `core` = flat-bright centre fraction before the falloff begins.
static func _bake_dot(size: int, pow_falloff: float, core: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5 - c) / c
			var dy := (float(y) + 0.5 - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var t := clampf((1.0 - d - core) / maxf(0.001, 1.0 - core), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, pow(t, pow_falloff)))
	return ImageTexture.create_from_image(img)
