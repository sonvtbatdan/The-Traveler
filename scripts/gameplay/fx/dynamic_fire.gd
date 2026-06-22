extends Node2D
class_name DynamicFire
## Dynamic fire = GPUParticles2D whose per-particle alpha erodes a soft flame texture via noise
## (technique from the tutorial; see CLAUDE.md "Dynamic Fire"). The flame texture is generated procedurally
## (soft, transparent) since the repo's only flame art is a hard cel sheet.
##
## Stage 3 (v2): a STATIC emitter whose emission POINTS are distributed along the path (straight jet → around
## a circle). The path "draws" by GROWING the revealed point set (DRAW), then keeps the whole point set
## emitting so the ring HOLDS as a lit, shimmering band, then stops emitting (BURNOUT). This holds the ring —
## a single moving emitter can't, because each particle only lives `particle_lifetime`. All tunables @export.

const SHADER_PATH := "res://scripts/gameplay/fx/dynamic_fire.gdshader"
const FLAME_TEX_SIZE := 256   # the flame texture is resized to this at load → predictable size + light VRAM

# ── TUNABLES: particle look ──────────────────────────────────────────────────────
@export var particle_amount: int = 900        # high density → no gaps in the ring
@export var particle_lifetime: float = 0.9
@export var sim_fps: int = 24                 # particle simulation framerate (lower = more stepped/animated)
@export var particle_size_min: float = 40.0   # on-screen particle size in PIXELS (resolution-independent)
@export var particle_size_max: float = 90.0   # → scale = size_px / flame texture width (smaller = finer fire)
@export var velocity_min: float = 30.0        # low → flames lick near the ring instead of flying off
@export var velocity_max: float = 90.0
@export var inherit_velocity: float = 0.2
@export var spawn_angle_range: float = 90.0   # random initial sprite angle ±deg
@export var spread_deg: float = 180.0         # emission cone half-spread (180 = all directions)
@export var color_start := Color(1.0, 0.72, 0.44)   # hot core (ramp 0) — 20% redder (G/B cut)
@export var color_mid   := Color(1.0, 0.36, 0.064)  # orange (ramp ~0.4) — 20% redder
@export var color_end   := Color(0.50, 0.024, 0.0)  # dark-red embers (ramp 1)
@export var noise_scale: float = 0.7          # erosion noise tiling (smaller = larger, smoother features)
@export var erosion_softness: float = 0.28    # dissolve-edge softness (larger = softer, wispier)
@export var intensity: float = 1.1            # overall brightness (additive glow)
@export var glow: float = 0.0                 # HDR boost: >0 pushes output >1 so the WorldEnvironment bloom catches it
@export var fade_start: float = 0.62          # life fraction where embers start fading out (kills hard specks)
@export var noise_frequency: float = 0.05     # FastNoiseLite frequency for the erosion field
@export var flame_texture: Texture2D = null   # optional direct Texture2D override (takes priority)
@export var flame_texture_path: String = "res://assets/Soft_flame_3.png"   # CPU-loaded; works for
                                              # grayscale-on-black OR transparent flames (shader keys it).
                                              # "" + null → flat procedural fallback.

# ── TUNABLES: motion (jet → ring path; draw/hold/burnout) ────────────────────────
@export var path_enabled: bool = true         # false → single static emitter at origin (plain fire)
@export var free_form: bool = false           # true → no phase machine; emission points fed each frame via set_points()
@export var draw_duration: float = 5.0        # time to reveal the jet + full ring
@export var draw_ease: float = 1.6            # >1 = ease-in/out on the draw progress
@export var hold_duration: float = 10.0       # ring stays fully lit this long
@export var burnout_duration: float = 1.5     # after hold: stop emitting, particles die out
@export var ring_center_offset := Vector2.ZERO
@export var ring_radius: float = 240.0
@export var ring_start_angle: float = 0.0     # radians; the jet aims here and the ring opens from here
@export var ring_clockwise: bool = true
@export var ring_bidirectional: bool = false  # ring: form from BOTH directions (two heads meet at the far side)
@export var jet_length: float = 0.0           # straight jet reach (px); 0 → auto = ring_radius (seamless spoke)
@export var point_spacing: float = 12.0       # px between emission points along the path
@export var loop: bool = true                 # test-scene convenience: restart the cycle when done
@export var shape: String = "ring"            # "ring" (jet→circle) or "cross" (arms from centre — Red X flash)
@export var arm_count: int = 4                # cross: number of arms (4 = X)
@export var arm_length: float = 160.0         # cross: arm reach (px)
@export var arm_inner: float = 0.0            # cross: arms START at this radius (gap around the centre/ship)
@export var free_on_done: bool = false        # one-shot: queue_free() after BURNOUT (fire flashes)
@export var jet_holds: bool = false           # ring: keep the jet lit during HOLD; false = jet drops once the ring forms
@export var recede_burnout: bool = false      # BURNOUT un-reveals inner→outer over burnout_duration (fire recedes outward)

enum Phase { DRAW, HOLD, BURNOUT, DONE }

var _particles: GPUParticles2D = null
var _pm: ParticleProcessMaterial = null
var _shader_mat: ShaderMaterial = null
var _noise_tex: NoiseTexture2D = null
var _path_pts: Array[Vector2] = []
var _phase: int = Phase.DRAW
var _t: float = 0.0
var _jet_len: float = 0.0
var _revealed: int = 0
var _ring_start_idx: int = 0   # index in _path_pts where the ring begins (jet points are [0, _ring_start_idx))

func _ready() -> void:
	_noise_tex = _make_noise_tex()
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load(SHADER_PATH)
	_shader_mat.set_shader_parameter("noise_tex", _noise_tex)
	_shader_mat.set_shader_parameter("noise_scale", noise_scale)
	_shader_mat.set_shader_parameter("erosion_softness", erosion_softness)
	_shader_mat.set_shader_parameter("intensity", intensity)
	_shader_mat.set_shader_parameter("glow", glow)
	_shader_mat.set_shader_parameter("fade_start", fade_start)
	var ftex := _load_flame()
	_pm = _make_process_material(float(ftex.get_width()))
	_particles = GPUParticles2D.new()
	_particles.amount = maxi(1, particle_amount)
	_particles.lifetime = particle_lifetime
	_particles.fixed_fps = maxi(1, sim_fps)
	_particles.local_coords = false
	_particles.visibility_rect = Rect2(-2000, -2000, 4000, 4000)   # generous → spread-out trails aren't culled
	_particles.texture = ftex
	_particles.material = _shader_mat
	_particles.process_material = _pm
	add_child(_particles)
	if free_form:
		_particles.emitting = false   # driven externally by set_points()
	else:
		_restart_path()

## Free-form trail mode: set the emission points to `pts` (world space; keep this node at the origin) each
## frame. Empty → stop emitting. Used by Chemtrail to render the whole puff trail with ONE emitter.
func set_points(pts: Array) -> void:
	if _particles == null:
		return
	if pts.is_empty():
		_particles.emitting = false
		return
	_path_pts.clear()
	for p: Vector2 in pts:
		_path_pts.append(p)
	_apply_emission(_path_pts.size())
	_particles.emitting = true

func _process(delta: float) -> void:
	if free_form:
		return   # emission is driven by set_points()
	if not path_enabled:
		if _revealed != 1:
			_path_pts = [Vector2.ZERO]
			_apply_emission(1)
		_particles.emitting = true
		return
	match _phase:
		Phase.DRAW:
			_t += delta
			var p := _ease(clampf(_t / maxf(0.01, draw_duration), 0.0, 1.0))
			var want := maxi(1, int(ceil(p * float(_path_pts.size()))))
			if want != _revealed:
				_apply_emission(want)
			_particles.emitting = true
			if _t >= draw_duration:
				_phase = Phase.HOLD
				_t = 0.0
				# Ring formed: drop the jet (emit ring points only) so the initiating "line" stops + burns out,
				# leaving only the ring lingering. jet_holds=true keeps the old behaviour.
				if shape == "ring" and not jet_holds:
					_apply_emission(_path_pts.size(), _ring_start_idx)
				else:
					_apply_emission(_path_pts.size())
		Phase.HOLD:
			_t += delta
			_particles.emitting = true
			if _t >= hold_duration:
				_phase = Phase.BURNOUT
				_t = 0.0
				if not recede_burnout:
					_particles.emitting = false     # stop seeding → existing particles burn out
		Phase.BURNOUT:
			_t += delta
			if recede_burnout:
				# Directional disappearance: drop emission points inner→outer over burnout_duration, so the
				# fire recedes from the centre/ship out to the endpoint (inner particles die first).
				var q := clampf(_t / maxf(0.01, burnout_duration), 0.0, 1.0)
				var fidx := int(q * float(_path_pts.size()))
				if fidx >= _path_pts.size():
					_particles.emitting = false
				else:
					_apply_emission(_path_pts.size(), fidx)
					_particles.emitting = true
			else:
				_particles.emitting = false
			if _t >= burnout_duration + particle_lifetime:
				_phase = Phase.DONE
				_t = 0.0
		Phase.DONE:
			if loop:
				_restart_path()
			elif free_on_done:
				queue_free()

## Restart the full draw → hold → burnout cycle from the top.
func _restart_path() -> void:
	_jet_len = jet_length if jet_length > 0.0 else ring_radius
	_build_path_points()
	_phase = Phase.DRAW
	_t = 0.0
	if _particles != null:
		_particles.restart()
		_apply_emission(1)
		_particles.emitting = true

## Ordered emission points along the path, dispatched by shape.
func _build_path_points() -> void:
	_path_pts.clear()
	_ring_start_idx = 0
	if shape == "cross":
		_build_cross_points()
	else:
		_build_ring_points()
	if _path_pts.is_empty():
		_path_pts.append(Vector2.ZERO)

## Ring: straight jet (origin → ring start), then once around the ring (revealed in order = pen-tip draw).
func _build_ring_points() -> void:
	var spacing := maxf(4.0, point_spacing)
	var jdir := Vector2.from_angle(ring_start_angle)
	var d := 0.0
	while d < _jet_len:
		_path_pts.append(jdir * d)
		d += spacing
	_ring_start_idx = _path_pts.size()   # ring points begin here (jet = [0, _ring_start_idx))
	if ring_bidirectional:
		# Two heads grow from the start point in OPPOSITE directions, meeting at the far side. Points are
		# interleaved by distance-from-start so the reveal advances both arcs together.
		var half := PI * ring_radius
		d = 0.0
		while d <= half:
			var da := d / maxf(1.0, ring_radius)
			_path_pts.append(ring_center_offset + Vector2.from_angle(ring_start_angle + da) * ring_radius)
			if d > 0.0:
				_path_pts.append(ring_center_offset + Vector2.from_angle(ring_start_angle - da) * ring_radius)
			d += spacing
	else:
		var sgn := -1.0 if ring_clockwise else 1.0
		var ring_len := TAU * ring_radius
		d = 0.0
		while d < ring_len:
			var ang := ring_start_angle + sgn * (d / maxf(1.0, ring_radius))
			_path_pts.append(ring_center_offset + Vector2.from_angle(ang) * ring_radius)
			d += spacing

## Cross/X: arms radiating from the centre, points ordered by DISTANCE so all arms shoot out together.
func _build_cross_points() -> void:
	var spacing := maxf(4.0, point_spacing)
	var n := maxi(1, arm_count)
	var d := maxf(spacing, arm_inner)   # start outside the inner gap so the centre (ship) stays empty
	while d <= arm_length:
		for a in n:
			var ang := ring_start_angle + TAU * float(a) / float(n)
			_path_pts.append(ring_center_offset + Vector2.from_angle(ang) * d)
		d += spacing

## Emit path points [from_idx, count). DRAW reveals [0, want) (pen-tip draw); dropping the jet emits
## [_ring_start_idx, end) so the jet stops while the ring holds.
func _apply_emission(count: int, from_idx: int = 0) -> void:
	count = clampi(count, 1, _path_pts.size())
	from_idx = clampi(from_idx, 0, count - 1)
	_revealed = count
	var n := count - from_idx
	var img := Image.create(maxi(1, n), 1, false, Image.FORMAT_RGBF)
	for i in n:
		var p: Vector2 = _path_pts[from_idx + i]
		img.set_pixel(i, 0, Color(p.x, p.y, 0.0))
	_pm.emission_point_texture = ImageTexture.create_from_image(img)
	_pm.emission_point_count = maxi(1, n)
	# Keep per-point density uniform as the reveal grows: scale total particles by the emitted-point fraction
	# so the early draw / jet (few points) doesn't concentrate the fixed budget into a bright clump.
	# amount_ratio scales emission WITHOUT restarting the system (Godot 4.2+).
	if _particles != null:
		_particles.amount_ratio = clampf(float(n) / float(maxi(1, _path_pts.size())), 0.02, 1.0)

func _ease(p: float) -> float:
	var s := smoothstep(0.0, 1.0, p)
	return pow(s, 1.0 / maxf(0.25, draw_ease)) if draw_ease < 1.0 else pow(s, draw_ease)

## Resolve the flame sprite: explicit Texture2D > CPU-loaded path > procedural fallback. CPU Image.load
## avoids any import dependency and works for the supplied grayscale-on-black PNG (the shader keys it by lum).
func _load_flame() -> Texture2D:
	if flame_texture != null:
		return flame_texture
	if flame_texture_path != "":
		var img := Image.new()
		if img.load(flame_texture_path) == OK:
			# Resize down so particle size is predictable + VRAM-light, regardless of source resolution.
			img.resize(FLAME_TEX_SIZE, FLAME_TEX_SIZE, Image.INTERPOLATE_BILINEAR)
			return ImageTexture.create_from_image(img)
		push_warning("dynamic_fire: could not load flame texture %s" % flame_texture_path)
	return _make_soft_flame(FLAME_TEX_SIZE)

## Bright pale core fading to transparent — a soft radial flame blob. The noise erosion carves it into
## licking tongues, and the particle colour ramp tints it, so a simple soft falloff is enough here.
func _make_soft_flame(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)   # soft falloff to transparent at the rim
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## Seamless erosion noise — same pattern as arena_nebula._make_noise_tex (FastNoiseLite + NoiseTexture2D).
func _make_noise_tex() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = noise_frequency
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	return tex

## Motion + colour/alpha over lifetime. Colour ramp (orange→red) and the alpha curve (0→1, drives the
## erosion edge) live HERE, not in the shader. Emission is point-based (set per frame via _apply_emission).
func _make_process_material(tex_w: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.particle_flag_disable_z = true
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = spread_deg
	pm.initial_velocity_min = velocity_min
	pm.initial_velocity_max = velocity_max
	pm.inherit_velocity_ratio = inherit_velocity
	# Particle size in PIXELS → scale is size / texture width (resolution-independent).
	pm.scale_min = particle_size_min / maxf(1.0, tex_w)
	pm.scale_max = particle_size_max / maxf(1.0, tex_w)
	pm.angle_min = -spawn_angle_range
	pm.angle_max = spawn_angle_range
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	var g := Gradient.new()
	g.set_color(0, color_start)
	g.set_color(1, color_end)
	g.add_point(0.4, color_mid)   # hot white core → orange → red embers
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var crv := Curve.new()
	crv.add_point(Vector2(0.0, 0.0))
	crv.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = crv
	pm.alpha_curve = ct
	return pm

## Replay key (test scene): restart the whole draw → hold → burnout cycle.
func _unhandled_input(event: InputEvent) -> void:
	if loop and event.is_action_pressed("ui_accept"):   # test-scene replay only (one-shots don't replay)
		_restart_path()

## Re-trigger this fire at a new world position (pooled one-shot use, e.g. the Red X flash).
func retrigger(at: Vector2) -> void:
	global_position = at
	_restart_path()
