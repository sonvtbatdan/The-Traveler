extends Node2D
class_name Explosion
## Standalone one-shot 2D explosion VFX (see CLAUDE.md "Explosion"). Models explosion anatomy: a HOT WHITE point
## that visibly expands outward and reddens, throwing debris, raising smoke across the whole area, and punching a
## refraction SHOCKWAVE through the background. Layers (back→front), all under this node, then queue_free():
##   • STREAKS  (CPUParticles2D, additive, z 0) — radial debris spikes.
##   • SMOKE    (GPUParticles2D, MIX/alpha, z 1) — gray puffs from across the WHOLE blast area; lingers.
##   • PUFFS    (GPUParticles2D, additive HDR, z 2) — red/orange fireball volume (mottled, NO stipple holes).
##   • CORE     (Sprite2D, additive HDR, z 3) — the hot-white starting point that grows white→orange→red. The
##              clearly-visible expansion.
##   • SHOCKWAVE (screen-space distortion on a CanvasLayer) — the tutorial's donut UV-displacement ring; ripples
##              the background (needs detail behind it to be seen — stars/nebula in game, the grid in the test).
## All textures procedural. API mirrors arena_explosion: setup(world_pos, size_px); add to tree; auto-frees.
## STANDALONE — does not touch arena_explosion.gd or any caller.

const FIRE_SHADER_PATH   := "res://scripts/gameplay/fx/explosion.gdshader"
const SMOKE_SHADER_PATH  := "res://scripts/gameplay/fx/explosion_smoke.gdshader"
const SHOCK_SHADER_PATH  := "res://scripts/gameplay/fx/explosion_shockwave.gdshader"
const STREAK_SHADER_PATH := "res://scripts/gameplay/fx/explosion_streak.gdshader"
const PUFF_TEX_SIZE      := 256
const STREAK_TEX_W       := 32
const STREAK_TEX_H       := 128
const NOISE_TEX_SIZE     := 256
const BASE_SIZE          := 100.0

# ── TUNABLES: overall ────────────────────────────────────────────────────────────
@export var size_px: float = 100.0
@export var glow: float = 2.9                  # HDR boost on the hot layers → bloom (+60% intensity)
@export var intensity: float = 1.9             # (+60% intensity)
@export var time_scale: float = 0.667          # whole-effect playback speed (0.667 = 50% slower / 1.5× duration).
                                                # Applied to particle speed_scale + the code timeline → true slow-mo.

# ── TUNABLES: core (the hot-white starting point that expands) ────────────────────
@export var core_grow: float = 0.4             # seconds to expand from the point to full radius (visible growth)
@export var core_life: float = 0.75            # total core lifetime
@export var core_size: float = 1.15            # final core radius as a fraction of size_px (+60% spread)
@export var core_hot  := Color(5.5, 5.0, 4.5)  # HDR hot white at the very start
@export var core_mid  := Color(3.2, 0.9, 0.25) # orange as it grows
@export var core_red  := Color(2.2, 0.22, 0.07) # deep red at full size (the explosion is RED)

# ── TUNABLES: fireball puffs (red volume around the core) ─────────────────────────
@export var fireball_amount: int = 35           # (+60% intensity = density)
@export var fireball_lifetime: float = 0.7
@export var fireball_delay: float = 0.08        # puffs wait this long → the bare core expands first (visible)
@export var fireball_explosiveness: float = 0.7   # <1 → puffs bloom out over time (fire grows from the core)
@export var fireball_size_min: float = 0.48    # fraction of size_px (+60% spread)
@export var fireball_size_max: float = 0.96
@export var fireball_vel_min: float = 112.0    # px/s @ BASE_SIZE — scaled by size_px/100 (+60% spread)
@export var fireball_vel_max: float = 304.0
@export var fireball_spawn_radius: float = 0.08  # tiny → erupts from the point (+60% spread)
@export var puff_hot  := Color(3.4, 1.1, 0.35) # orange
@export var puff_red  := Color(1.7, 0.2, 0.05) # red
@export var puff_burn := Color(0.22, 0.03, 0.0) # dark cooling

# ── TUNABLES: smoke (from the WHOLE area, alpha-blended so it reads) ──────────────
@export var smoke_enabled: bool = true
@export var smoke_amount: int = 74              # (+60% intensity = density)
@export var smoke_lifetime: float = 1.45        # the long tail → the whole explosion lasts ~1.5s
@export var smoke_size_min: float = 0.64        # (+60% spread)
@export var smoke_size_max: float = 1.36
@export var smoke_vel_min: float = 32.0         # (+60% spread)
@export var smoke_vel_max: float = 112.0
@export var smoke_spawn_radius: float = 0.8     # LARGE → smoke rises across the whole blast footprint (+60% spread)
@export var smoke_color_lit := Color(0.6, 0.48, 0.4)
@export var smoke_color_dim := Color(0.22, 0.2, 0.2)
@export var smoke_opacity: float = 0.9
@export var smoke_sim_fps: int = 16             # LOW vs the fire's 30 → "stepped" dissipation (tutorial: smoke
                                                # drawn on twos/threes/fours while the fire is on ones)

# ── TUNABLES: shockwave (screen-space distortion — the tutorial) ─────────────────
@export var shockwave_enabled: bool = true
@export var shockwave_waves: int = 4            # number of ripples emitted (max 4 — shader array size)
@export var shockwave_travel: float = 1.0       # time for a wave to cross the screen to the edge (s)
@export var shockwave_stagger: float = 0.16     # delay between successive ripples (s)
@export var shockwave_max_radius: float = 1.15  # ring radius (screen-height units) that reaches the edge
@export var shockwave_force: float = 0.05       # peak UV displacement per wave
@export var shockwave_thickness: float = 0.05   # ring band width (screen-height units)
@export var shockwave_aberration: float = 0.6   # chromatic split
@export var shockwave_layer: int = 80           # CanvasLayer for the fullscreen distortion rect

# ── TUNABLES: streaks / debris ───────────────────────────────────────────────────
@export var streaks_enabled: bool = true
@export var streak_amount: int = 38             # (+60% intensity = density)
@export var streak_lifetime: float = 0.65
@export var streak_vel_min: float = 544.0       # (+60% spread)
@export var streak_vel_max: float = 1088.0
@export var streak_len: float = 1.5             # (+60% spread)
@export var streak_color := Color(4.2, 1.4, 0.5)  # HDR orange-red → blooms
@export var streak_use_4cell: bool = false

# ── Layer noise look ─────────────────────────────────────────────────────────────
@export var noise_scale: float = 0.55
@export var noise_frequency: float = 0.05

var _core: Sprite2D = null
var _puffs: GPUParticles2D = null
var _smoke: GPUParticles2D = null
var _streaks: CPUParticles2D = null
var _shock_layer: CanvasLayer = null
var _shock_rect: ColorRect = null
var _shock_mat: ShaderMaterial = null
var _fire_mat: ShaderMaterial = null
var _smoke_mat: ShaderMaterial = null
var _puffs_pm: ParticleProcessMaterial = null
var _smoke_pm: ParticleProcessMaterial = null
var _core_grad: Gradient = null
var _noise_tex: NoiseTexture2D = null
var _t: float = 0.0
var _max_life: float = 0.0
var _scale_f: float = 1.0
var _built: bool = false
var _puffs_started: bool = false

## Public entry point — API-compatible with arena_explosion.setup(). Call after add_child().
func setup(world_pos: Vector2, p_size_px: float) -> void:
	global_position = world_pos
	size_px = maxf(8.0, p_size_px)
	if _built:
		_apply_scale_params()
		_restart()

func _ready() -> void:
	_scale_f = size_px / BASE_SIZE
	_noise_tex = _make_noise_tex()
	_build_shaders()
	_build_core_gradient()
	_build_streaks()      # z 0
	_build_smoke()        # z 1
	_build_puffs()        # z 2
	_build_core()         # z 3
	_build_shockwave()    # CanvasLayer
	_built = true
	var shock_total := _shockwave_total_time() if shockwave_enabled else 0.0
	_max_life = 0.05 + maxf(maxf(core_life, fireball_delay + fireball_lifetime), \
			maxf(smoke_lifetime if smoke_enabled else 0.0, \
			maxf(shock_total, streak_lifetime if streaks_enabled else 0.0)))
	_apply_scale_params()
	_restart()

## Total time until the last-born ripple finishes its travel.
func _shockwave_total_time() -> float:
	var n := clampi(shockwave_waves, 1, 4)
	return float(n - 1) * shockwave_stagger + shockwave_travel

func _build_shaders() -> void:
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = load(FIRE_SHADER_PATH)
	_fire_mat.set_shader_parameter("noise_tex", _noise_tex)
	_fire_mat.set_shader_parameter("noise_scale", noise_scale)
	_fire_mat.set_shader_parameter("intensity", intensity)
	_fire_mat.set_shader_parameter("glow", glow)
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = load(SMOKE_SHADER_PATH)
	_smoke_mat.set_shader_parameter("noise_tex", _noise_tex)
	_smoke_mat.set_shader_parameter("noise_scale", noise_scale * 0.7)
	_smoke_mat.set_shader_parameter("erosion_softness", 0.38)

func _build_core_gradient() -> void:
	_core_grad = Gradient.new()
	_core_grad.set_color(0, core_hot)
	_core_grad.set_color(1, core_red)
	_core_grad.add_point(0.45, core_mid)

func _build_core() -> void:
	_core = Sprite2D.new()
	_core.texture = _make_soft_puff(PUFF_TEX_SIZE)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_core.material = cm
	_core.z_index = 3
	add_child(_core)

func _build_puffs() -> void:
	_puffs_pm = _make_puffs_pm()
	_puffs = GPUParticles2D.new()
	_puffs.amount = maxi(1, fireball_amount)
	_puffs.lifetime = fireball_lifetime
	_puffs.fixed_fps = 30
	_puffs.one_shot = true
	_puffs.explosiveness = clampf(fireball_explosiveness, 0.0, 1.0)
	_puffs.local_coords = false
	_puffs.visibility_rect = Rect2(-1500, -1500, 3000, 3000)
	_puffs.texture = _make_soft_puff(PUFF_TEX_SIZE)
	_puffs.material = _fire_mat
	_puffs.process_material = _puffs_pm
	_puffs.speed_scale = maxf(0.05, time_scale)   # slow-mo: run the sim slower without changing the spatial look
	_puffs.z_index = 2
	add_child(_puffs)

func _build_smoke() -> void:
	if not smoke_enabled:
		return
	_smoke_pm = _make_smoke_pm()
	_smoke = GPUParticles2D.new()
	_smoke.amount = maxi(1, smoke_amount)
	_smoke.lifetime = smoke_lifetime
	_smoke.fixed_fps = maxi(4, smoke_sim_fps)   # low → stepped/slowed dissipation (vs the fire on "ones")
	_smoke.one_shot = true
	_smoke.explosiveness = 0.55                # spread spawn times → billows across the area, not one pop
	_smoke.local_coords = false
	_smoke.visibility_rect = Rect2(-1500, -1500, 3000, 3000)
	_smoke.texture = _make_soft_puff(PUFF_TEX_SIZE)
	_smoke.material = _smoke_mat
	_smoke.process_material = _smoke_pm
	_smoke.speed_scale = maxf(0.05, time_scale)   # slow-mo
	_smoke.z_index = 1
	add_child(_smoke)

func _build_streaks() -> void:
	if not streaks_enabled:
		return
	var p := CPUParticles2D.new()
	p.amount = maxi(1, streak_amount)
	p.lifetime = streak_lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = true
	p.gravity = Vector2.ZERO
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.particle_flag_align_y = true
	p.texture = _make_streak_tex()
	var c_fade := streak_color
	c_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([streak_color, streak_color, c_fade])
	p.color_ramp = grad
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.25))
	taper.add_point(Vector2(0.12, 1.0))
	taper.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = taper
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	p.speed_scale = maxf(0.05, time_scale)        # slow-mo
	p.z_index = 0
	add_child(p)
	_streaks = p
	if streak_use_4cell:
		p.hue_variation_min = -1.0
		p.hue_variation_max = 1.0
		var sm := ShaderMaterial.new()
		sm.shader = load(STREAK_SHADER_PATH)
		p.material = sm

func _build_shockwave() -> void:
	if not shockwave_enabled:
		return
	_shock_mat = ShaderMaterial.new()
	_shock_mat.shader = load(SHOCK_SHADER_PATH)
	_shock_mat.set_shader_parameter("radii", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	_shock_mat.set_shader_parameter("amps", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	_shock_mat.set_shader_parameter("thickness", shockwave_thickness)
	_shock_mat.set_shader_parameter("aberration", shockwave_aberration)
	_shock_mat.set_shader_parameter("center", Vector2(0.5, 0.5))
	_shock_rect = ColorRect.new()
	_shock_rect.material = _shock_mat
	_shock_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shock_layer = CanvasLayer.new()
	_shock_layer.layer = shockwave_layer
	_shock_layer.add_child(_shock_rect)
	add_child(_shock_layer)

func _apply_scale_params() -> void:
	_scale_f = size_px / BASE_SIZE
	var tex_w := float(PUFF_TEX_SIZE)
	if _puffs_pm != null:
		_puffs_pm.emission_sphere_radius = fireball_spawn_radius * size_px
		_puffs_pm.initial_velocity_min = fireball_vel_min * _scale_f
		_puffs_pm.initial_velocity_max = fireball_vel_max * _scale_f
		_puffs_pm.scale_min = (fireball_size_min * size_px) / tex_w
		_puffs_pm.scale_max = (fireball_size_max * size_px) / tex_w
	if _smoke_pm != null:
		_smoke_pm.emission_sphere_radius = smoke_spawn_radius * size_px
		_smoke_pm.initial_velocity_min = smoke_vel_min * _scale_f
		_smoke_pm.initial_velocity_max = smoke_vel_max * _scale_f
		_smoke_pm.scale_min = (smoke_size_min * size_px) / tex_w
		_smoke_pm.scale_max = (smoke_size_max * size_px) / tex_w
	if _streaks != null:
		_streaks.initial_velocity_min = streak_vel_min * _scale_f
		_streaks.initial_velocity_max = streak_vel_max * _scale_f
		_streaks.scale_amount_min = (streak_len * size_px) / float(STREAK_TEX_H) * 0.55
		_streaks.scale_amount_max = (streak_len * size_px) / float(STREAK_TEX_H)

func _restart() -> void:
	_t = 0.0
	_puffs_started = false
	if _puffs != null:
		_puffs.emitting = false        # held until fireball_delay → the bare core expands first
	if _smoke != null:
		_smoke.restart()
		_smoke.emitting = true
	if _streaks != null:
		_streaks.restart()
		_streaks.emitting = true
	if _core != null:
		_core.visible = true
	if _shock_rect != null:
		_shock_rect.visible = true

func _process(delta: float) -> void:
	_t += delta * maxf(0.05, time_scale)           # slow-mo: advance the code timeline in scaled time too
	if not _puffs_started and _puffs != null and _t >= fireball_delay:
		_puffs_started = true
		_puffs.restart()               # burst the fire now (core already started expanding)
		_puffs.emitting = true
	_drive_core(_t)
	_drive_shockwave(_t)
	if _t >= _max_life:
		queue_free()

## Core: a hot-white point that grows (ease-out, so the expansion is VISIBLE) to core_size, shifting
## white→orange→red, then fades. This is the readable "starts at a point, explodes outward" element.
func _drive_core(t: float) -> void:
	if _core == null:
		return
	if t >= core_life:
		_core.visible = false
		return
	var k := clampf(t / maxf(0.01, core_grow), 0.0, 1.0)
	var ek := smoothstep(0.0, 1.0, k)                       # ease-in-out → the growth is spread out + VISIBLE
	var grow_r := lerpf(0.02, core_size, ek)               # starts as a near-zero point, grows to full
	# Tutorial lesson: the hot spot SHRINKS toward the inner section as it cools into smoke. After it's grown,
	# condense the radius back inward over the rest of its life (energy collapsing into the smoke cloud).
	var shrink := smoothstep(core_grow, core_life, t)
	var radius := lerpf(grow_r, core_size * 0.32, shrink) * size_px
	_core.scale = Vector2.ONE * (radius * 2.0 / float(PUFF_TEX_SIZE))
	var col := _core_grad.sample(clampf(t / maxf(0.01, core_grow * 1.3), 0.0, 1.0))
	col.a = 1.0 - smoothstep(core_life * 0.5, core_life, t)  # hold then fade as it condenses
	_core.modulate = col

## Shockwave: several concentric ripples travel out to the screen edge. Wave i is born at i*stagger, expands
## (ease-out) to shockwave_max_radius and fades; LATER waves have a shorter life (die faster). Each frame we feed
## the shader the current radius + amplitude of every wave, plus the explosion's screen-UV centre.
func _drive_shockwave(t: float) -> void:
	if _shock_rect == null:
		return
	var total := _shockwave_total_time()
	if t >= total:
		_shock_rect.visible = false
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	_shock_rect.size = vp_size
	_shock_rect.position = Vector2.ZERO
	var screen_pos := vp.get_canvas_transform() * global_position
	_shock_mat.set_shader_parameter("center", screen_pos / vp_size)
	var n := clampi(shockwave_waves, 1, 4)
	var radii := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var amps := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in n:
		var local := t - float(i) * shockwave_stagger
		if local < 0.0 or local >= shockwave_travel:
			continue                                              # not born yet / already crossed the edge
		var p := local / shockwave_travel
		var ek := 1.0 - pow(1.0 - p, 1.4)                         # mild ease-out → visibly crosses the screen
		radii[i] = ek * shockwave_max_radius                      # travels out to the screen edge
		# Fade: later waves (higher i) use a steeper exponent → they DISAPPEAR FASTER, and start weaker.
		amps[i] = shockwave_force * (1.0 - float(i) * 0.12) * pow(1.0 - p, 1.0 + float(i) * 0.6)
	_shock_mat.set_shader_parameter("radii", radii)
	_shock_mat.set_shader_parameter("amps", amps)

## Fireball puff motion + colour/alpha. Orange→red→burn ramp (RED explosion); alpha 0.9→1→0; erupts from the
## point (tiny sphere + 180° spread). The mottle shader fills each puff (no stipple holes).
func _make_puffs_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.particle_flag_disable_z = true
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = fireball_spawn_radius * size_px
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = fireball_vel_min * _scale_f
	pm.initial_velocity_max = fireball_vel_max * _scale_f
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var tex_w := float(PUFF_TEX_SIZE)
	pm.scale_min = (fireball_size_min * size_px) / tex_w
	pm.scale_max = (fireball_size_max * size_px) / tex_w
	pm.scale_curve = _curve_tex([Vector2(0.0, 0.25), Vector2(0.35, 1.0), Vector2(1.0, 0.95)])
	pm.damping_min = 120.0
	pm.damping_max = 220.0
	var g := Gradient.new()
	g.set_color(0, puff_hot)
	g.set_color(1, puff_burn)
	g.add_point(0.4, puff_red)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.alpha_curve = _curve_tex([Vector2(0.0, 0.9), Vector2(0.3, 1.0), Vector2(1.0, 0.0)])
	return pm

## Smoke motion + colour/alpha. Large spawn sphere → smoke rises from the whole blast area. Gray ramp + opacity
## curve (0→peak→0, peak ~45% so it billows in after the fire and lingers).
func _make_smoke_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.particle_flag_disable_z = true
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = smoke_spawn_radius * size_px
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = smoke_vel_min * _scale_f
	pm.initial_velocity_max = smoke_vel_max * _scale_f
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var tex_w := float(PUFF_TEX_SIZE)
	pm.scale_min = (smoke_size_min * size_px) / tex_w
	pm.scale_max = (smoke_size_max * size_px) / tex_w
	pm.scale_curve = _curve_tex([Vector2(0.0, 0.4), Vector2(0.5, 0.85), Vector2(1.0, 1.0)])
	pm.damping_min = 30.0
	pm.damping_max = 70.0
	var g := Gradient.new()
	g.set_color(0, smoke_color_lit)
	g.set_color(1, smoke_color_dim)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.alpha_curve = _curve_tex([Vector2(0.0, 0.0), Vector2(0.45, smoke_opacity), \
			Vector2(0.7, smoke_opacity * 0.85), Vector2(1.0, 0.0)])
	return pm

func _curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

## Soft white puff: solid pale core → transparent rim. Tinted by the ramp; the fireball shader mottles it.
func _make_soft_puff(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.4)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## Streak: bright vertical bar tapering to both ends + soft sides (long axis = Y so align_y stretches it).
func _make_streak_tex() -> ImageTexture:
	var img := Image.create(STREAK_TEX_W, STREAK_TEX_H, false, Image.FORMAT_RGBA8)
	var cx := float(STREAK_TEX_W) * 0.5
	var cy := float(STREAK_TEX_H) * 0.5
	for y in STREAK_TEX_H:
		for x in STREAK_TEX_W:
			var fx := absf(float(x) - cx) / cx
			var fy := absf(float(y) - cy) / cy
			var a := pow(clampf(1.0 - fx, 0.0, 1.0), 2.0) * pow(clampf(1.0 - fy, 0.0, 1.0), 1.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## Seamless erosion noise — same pattern as dynamic_fire._make_noise_tex.
func _make_noise_tex() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = noise_frequency
	var tex := NoiseTexture2D.new()
	tex.width = NOISE_TEX_SIZE
	tex.height = NOISE_TEX_SIZE
	tex.seamless = true
	tex.noise = n
	return tex
