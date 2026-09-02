extends Node2D
class_name VolcanicClouds
## TWO kinds of plume erupting from the Volcanic map — "smoke" (ash) and "flame" (fire), user feedback: "thêm
## 1 loại plume nữa là flame plume... chia bảng plume thành 2 tab, smoke và flame". Every plume-related public
## method takes a `kind: String` ("smoke" or "flame", see KINDS) and drives that kind's own independent
## settings/pools — the two kinds never share particles, only the world-anchored/hover-free architecture below.
##
## THREE independent vent sources PER KIND, all spawning via the same _make_plume(pos, kind):
##   1. RANDOM AMBIENT vents — a coarse world-space hash grid (VolcanicNoise.hash21, same technique as
##      VolcanicTrees' scatter), tunable via the Plume Edit panel's per-tab "Density" slider. `_placed[kind]`.
##   2. MARKED CRATER vents — user-placed via volcanic_crater_mark.gd (clicking the maptile photo). A mark is
##      a normalized (u, v) on one specific ground photo — replicated at EVERY world-space repetition of that
##      photo (mirrors volcanic_ground.gdshader's uv_a/uv_b/uv_c tiling, VolcanicNoise.GROUND_UV_MULT/OFFSET),
##      spawning only where VolcanicNoise.ground_region() agrees that photo is the one showing there. Each
##      replica also rolls a STABLE (position-hashed) chance against that kind's "Marked Crater Reveal %".
##      `_marked_placed[kind]`.
##   3. LANDMARK-ATTACHED vents — set_landmark_plumes(), called by volcanic_temple_layer.gd once per spawned
##      temple instance with already-world-transformed positions (from volcanic_landmark_mark.gd's local-space
##      marks). PERMANENT for that landmark instance's lifetime — no view-culling, there are only ever a
##      handful of landmarks on the whole map. `_landmark_placed[landmark_id][kind]`.
##
## Every vent is ONE ENTRY = {"body": CPUParticles2D, "spark": CPUParticles2D or null, "color": Color}. Smoke
## has no spark companion (spark stays null); FLAME does — see _make_plume()'s header note below for why a
## single particle layer read as flat/unconvincing fire and what the second layer fixes. _free_entry()/
## _style_entry()/_gravity_entry() operate on the whole entry uniformly so every pool (ambient/marked/
## landmark) manages body+spark together without duplicating null-checks at each call site.
##
## NOTE: an earlier revision of this file rebuilt the flame BODY on top of DynamicFire (this project's
## GPUParticles2D noise-erosion fire VFX, scripts/gameplay/fx/dynamic_fire.gd) for a richer look — reverted
## per user feedback ("hệ thống dynamicfire này lag quá, khi di chuyển bị lag rất nhiều") — one GPUParticles2D
## + ShaderMaterial + NoiseTexture2D per flame vent was too costly with many plumes on screen while moving.
## Flame's body is a plain CPUParticles2D again, same as smoke, just with its own texture/curve/motion consts.
##
## WIND is the one thing SHARED across both kinds — a single direction+strength, rolled randomly once per map
## load (user feedback: "hướng gió, cường độ gió random"), applied as a constant lateral accel added to every
## particle's `gravity` regardless of kind, so smoke and flame both lean the same way at any given moment
## (real weather, not each vent independently misbehaving). Re-rollable live via Plume Edit's REROLL WIND.
##
## Each plume instance independently rolls ONE random color from that kind's own 6-slot palette at creation
## and keeps it — live palette edits re-color future plumes, not existing ones (same scoping as speed/height).
##
## This node stays at the world origin and never moves — every plume's CPUParticles2D column is a plain child
## at its own FIXED world coordinate (local_coords = true) because a plume represents a real terrain/landmark
## feature, not sky-anchored weather. update_view() only decides which vents currently exist within
## view+margin (ambient/marked pools only — landmark pools are always alive).

const VolcanicNoise := preload("res://scripts/gameplay/volcanic/volcanic_noise.gd")
const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")
const SmokeTrail := preload("res://scripts/gameplay/fx/smoke_trail.gd")

## 2026-09-01 (user: "áp dụng code phun khói lửa cho ash enemy để thay vào các plume của map volcanic"): the
## plume BODIES + flame SPARKS now render through the ash-creep SmokeTrail shaders (smoke_trail /
## smoke_flame / smoke_ember .gdshader) + its shared baked FBM texture — domain-warped "boil", relief
## lighting, licking-tongue erosion — WITHOUT adding node/particle count: still one CPUParticles2D per vent,
## CPU-simulated, and ONE ShaderMaterial per kind shared by every vent. This is NOT the reverted DynamicFire
## route (a GPUParticles2D + its own NoiseTexture2D per vent — THAT is what lagged when moving). Flip
## USE_SMOKETRAIL_FX to false for the plain GradientTexture2D + CanvasItemMaterial bodies.
const USE_SMOKETRAIL_FX := true
const FX_SMOKE_CHEAP_ABOVE := 9   # this many visible smoke vents → smoke shader drops to its `cheap` path

const KINDS := ["smoke", "flame"]

const CELL_SIZE := 900.0        # world-px grid spacing between ambient vent CANDIDATES (not every cell gets one)
const MARGIN := 300.0           # extra world-px beyond the viewport a vent may exist in before it's culled
const REGEN_MOVE_THRESHOLD := 220.0
const VENT_CHANCE_MAX := 0.5    # density (0..1) maps to 0..this fraction of candidate cells actually spawning
const WIND_STRENGTH_MIN := 20.0 # wind never rolls below this — see _roll_wind()

const PLUME_TEX_PX := 64.0      # _make_puff_tex's native size (smoke body + flame sparks)
const FLAME_TEX_W := 56         # _make_flame_tex's native size — TALLER than wide (see that function) so a
const FLAME_TEX_H := 104        # single flat GradientTexture2D reads as an upright flame LICK, not a round blob

# Per-kind physical/visual constants — NOT user-tunable (the Speed/Height sliders already cover the main
# feel); these are what make "flame" read as fire rather than a faster/shorter smoke.
const KIND_RISE_ACCEL := {"smoke": 10.0, "flame": 30.0}    # px/s^2 upward accel (buoyancy) — fire rises harder
const KIND_SPREAD_DEG := {"smoke": 16.0, "flame": 8.0}     # emission cone half-angle — fire is a tight column
const KIND_AMOUNT := {"smoke": 20, "flame": 12}

# Flame body: low angular_velocity (a spinning elongated lick reads as broken, not flickering) but real
# tangential_accel instead — a per-particle random-signed sideways accel that makes each lick curl left or
# right independently as it rises, which is what actually reads as "flicker" for an upright flame shape.
const FLAME_ANGULAR_VEL := 10.0
const FLAME_TANGENTIAL_ACCEL := 22.0
const FLAME_RADIAL_ACCEL := 8.0     # small inward/outward pull — keeps licks from drifting apart into a blob

# Flame SPARKS — a second, independent CPUParticles2D per flame plume (user feedback: "nghiên cứu cách viết
# lửa đẹp, có spark"). Real fire reads as convincing largely BECAUSE of the small fast embers popping off the
# main body, not from the body alone however well-shaped — a single soft particle layer, no matter how tuned,
# caps out looking like a static blob. Sparks are small, few, fast, short-lived, spinning freely, additive.
const FLAME_SPARK_AMOUNT := 8
const FLAME_SPARK_SPREAD_DEG := 80.0      # MUCH wider than the body's 8° column — sparks need to visibly
                                           # scatter clear of the additive core, not trace straight up through
                                           # it (where, sharing the body's own bright glow, they're invisible)
const FLAME_SPARK_LIFETIME_FRAC := 0.7    # spark lifetime = flame Height slider * this — sparks burn out much
                                           # faster than the body they came from
const FLAME_SPARK_SPEED_MULT := 3.2       # sparks fly noticeably faster than the body's own rise velocity —
                                           # this is what actually clears them of the body's glow in time
const FLAME_SPARK_TANGENTIAL_ACCEL := 70.0

var _placed: Dictionary = {"smoke": {}, "flame": {}}          # kind -> cell Vector2 -> entry
var _marked_placed: Dictionary = {"smoke": {}, "flame": {}}   # kind -> "mi_i_j" String -> entry (+ "pos")
var _landmark_placed: Dictionary = {}                          # landmark_id -> {"smoke":[entry,...], "flame":[...]}
var _crater_marks: Dictionary = {"smoke": [], "flame": []}
var _canopy_size: float = VolcanicTerrainSettings.DEFAULT_CANOPY_SIZE
var _last_center: Vector2 = Vector2.ZERO
var _last_regen_center: Vector2 = Vector2.ZERO
var _has_last_center: bool = false
var _view_size: Vector2 = Vector2(1440.0, 780.0)
var _puff_tex: GradientTexture2D
var _flame_tex: GradientTexture2D
var _additive_mat: CanvasItemMaterial
var _fx_smoke_mat: ShaderMaterial = null    # SmokeTrail shaders, shared across every vent of that kind
var _fx_flame_mat: ShaderMaterial = null
var _fx_ember_mat: ShaderMaterial = null
var _fx_cheap: bool = false

var _opacity: Dictionary = {}     # kind -> float
var _brightness: Dictionary = {}  # kind -> float
var _colors: Dictionary = {}      # kind -> Array[Color] (6-slot palette)
var _vent_chance: Dictionary = {} # kind -> float (0..VENT_CHANCE_MAX)
var _speed: Dictionary = {}       # kind -> float
var _height: Dictionary = {}      # kind -> float (lifetime seconds)
var _mark_reveal: Dictionary = {} # kind -> float (0..1)

var _wind_strength_max: float = VolcanicTerrainSettings.DEFAULT_WIND_STRENGTH_MAX
var _wind_dir_deg: float = 0.0     # rolled fresh in _ready()/reroll_wind()
var _wind_strength: float = 0.0
var _river_width: float = 0.0      # half-width of the lava band — see apply_river_width()

func _ready() -> void:
	add_to_group("volcanic_clouds")   # so the Plume Edit panel can find this instance
	_puff_tex = _make_puff_tex()
	_flame_tex = _make_flame_tex()
	_additive_mat = CanvasItemMaterial.new()
	_additive_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if USE_SMOKETRAIL_FX:
		var fbm := SmokeTrail.shared_fbm_tex()
		_fx_smoke_mat = ShaderMaterial.new()
		_fx_smoke_mat.shader = SmokeTrail.shared_smoke_shader()
		_fx_smoke_mat.set_shader_parameter("fbm_tex", fbm)
		_fx_smoke_mat.set_shader_parameter("evolve", 0.28)   # gentler boil than the fast-moving ash creep
		_fx_flame_mat = ShaderMaterial.new()
		_fx_flame_mat.shader = SmokeTrail.shared_flame_shader()
		_fx_flame_mat.set_shader_parameter("fbm_tex", fbm)
		_fx_ember_mat = ShaderMaterial.new()
		_fx_ember_mat.shader = SmokeTrail.shared_ember_shader()

	var s := VolcanicTerrainSettings.load_settings()
	_canopy_size = float(s["canopy_size"])
	_river_width = float(s["river_width"])
	_crater_marks["smoke"] = (s["smoke_crater_marks"] as Array).duplicate(true)
	_crater_marks["flame"] = (s["flame_crater_marks"] as Array).duplicate(true)
	apply_kind_settings("smoke", s["smoke_opacity"], s["smoke_brightness"],
		[s["smoke_color_0"], s["smoke_color_1"], s["smoke_color_2"], s["smoke_color_3"], s["smoke_color_4"], s["smoke_color_5"]],
		s["smoke_density"], s["smoke_speed"], s["smoke_height"], s["smoke_mark_reveal_percent"])
	apply_kind_settings("flame", s["flame_opacity"], s["flame_brightness"],
		[s["flame_color_0"], s["flame_color_1"], s["flame_color_2"], s["flame_color_3"], s["flame_color_4"], s["flame_color_5"]],
		s["flame_density"], s["flame_speed"], s["flame_height"], s["flame_mark_reveal_percent"])
	_wind_strength_max = float(s["wind_strength_max"])
	_roll_wind()

## Public: called every frame with the camera's world-space focus and viewport size (mirrors
## VolcanicTrees.update_view) — decides which ambient/marked vents currently exist within view+margin
## (landmark-attached plumes are permanent, unaffected by this).
func update_view(center: Vector2, view_size: Vector2) -> void:
	_last_center = center
	_view_size = view_size
	if _has_last_center and center.distance_to(_last_regen_center) < REGEN_MOVE_THRESHOLD:
		return
	_has_last_center = true
	_last_regen_center = center
	_regenerate()

func _regenerate() -> void:
	var half: Vector2 = _view_size * 0.5 + Vector2(MARGIN, MARGIN)
	var min_p: Vector2 = _last_center - half
	var max_p: Vector2 = _last_center + half
	for kind: String in KINDS:
		_regen_grid(kind, min_p, max_p)
		_regen_marked(kind, min_p, max_p)
	# Crowd LOD: once enough smoke vents are on screen at once, drop the smoke shader to its `cheap` path
	# (skips the relief-lighting texture reads). One shared uniform → flips every vent together.
	if USE_SMOKETRAIL_FX and _fx_smoke_mat != null:
		var n := (_placed["smoke"] as Dictionary).size() + (_marked_placed["smoke"] as Dictionary).size()
		var want_cheap := n > FX_SMOKE_CHEAP_ABOVE
		if want_cheap != _fx_cheap:
			_fx_cheap = want_cheap
			_fx_smoke_mat.set_shader_parameter("cheap", want_cheap)

func _regen_grid(kind: String, min_p: Vector2, max_p: Vector2) -> void:
	var pool: Dictionary = _placed[kind]
	for key: Vector2 in pool.keys().duplicate():
		if key.x < min_p.x or key.x > max_p.x or key.y < min_p.y or key.y > max_p.y:
			_free_entry(pool[key])
			pool.erase(key)

	var start_x: float = floor(min_p.x / CELL_SIZE) * CELL_SIZE
	var start_y: float = floor(min_p.y / CELL_SIZE) * CELL_SIZE
	var x := start_x
	while x < max_p.x:
		var y := start_y
		while y < max_p.y:
			_maybe_place_grid(kind, Vector2(x, y))
			y += CELL_SIZE
		x += CELL_SIZE

func _maybe_place_grid(kind: String, cell: Vector2) -> void:
	var pool: Dictionary = _placed[kind]
	if pool.has(cell):
		return
	# Salt the hash differently per kind so smoke/flame ambient rolls at the same cell are independent.
	var salt: Vector2 = Vector2(511.0, -233.0) if kind == "smoke" else Vector2(-611.0, 833.0)
	var roll: float = VolcanicNoise.hash21(cell + salt)
	if roll >= float(_vent_chance.get(kind, 0.0)):
		return
	var jitter := Vector2(
		(VolcanicNoise.hash21(cell + salt + Vector2(71.0, 5.0)) - 0.5) * CELL_SIZE * 0.6,
		(VolcanicNoise.hash21(cell + salt + Vector2(5.0, 71.0)) - 0.5) * CELL_SIZE * 0.6
	)
	var pos: Vector2 = cell + jitter
	if _river_width > 0.0 and VolcanicNoise.is_river(pos, _river_width):
		return   # user feedback: "Plume và Flame không spawn trên river" — no smoke/flame vent inside the lava band
	pool[cell] = _make_plume(pos, kind)

## Replicates every entry in _crater_marks[kind] at EVERY world-space repetition of its source photo within
## [min_p, max_p] — see this file's header. `base_pos + Vector2(i, j) * period` inverts
## volcanic_ground.gdshader's `world_pos * scale + offset` UV formula (scale/offset per mark["tex"], from
## VolcanicNoise.GROUND_UV_MULT/OFFSET). Each valid replica then rolls a STABLE (hashed off its own world
## position — never flickers between regens) chance against that kind's mark-reveal fraction.
func _regen_marked(kind: String, min_p: Vector2, max_p: Vector2) -> void:
	var pool: Dictionary = _marked_placed[kind]
	for key: String in pool.keys().duplicate():
		var entry: Dictionary = pool[key]
		var pos: Vector2 = entry["pos"]
		if pos.x < min_p.x or pos.x > max_p.x or pos.y < min_p.y or pos.y > max_p.y:
			_free_entry(entry)
			pool.erase(key)

	var ground_uv_scale: float = 1.0 / maxf(_canopy_size, 1.0)
	var marks: Array = _crater_marks[kind]
	var reveal: float = float(_mark_reveal.get(kind, 1.0))
	var reveal_salt: Vector2 = Vector2(777.0, 333.0) if kind == "smoke" else Vector2(-919.0, 271.0)
	for mi in marks.size():
		var mark: Dictionary = marks[mi]
		var tex_idx: int = clampi(int(mark.get("tex", 0)), 0, 2)
		var uv := Vector2(float(mark.get("u", 0.5)), float(mark.get("v", 0.5)))
		var mult: float = VolcanicNoise.GROUND_UV_MULT[tex_idx]
		var offset: Vector2 = VolcanicNoise.GROUND_UV_OFFSET[tex_idx]
		var scale: float = ground_uv_scale * mult
		if scale <= 0.0:
			continue
		var period: float = 1.0 / scale
		var base_pos: Vector2 = (uv - offset) / scale

		var i_min := int(floor((min_p.x - base_pos.x) / period))
		var i_max := int(ceil((max_p.x - base_pos.x) / period))
		var j_min := int(floor((min_p.y - base_pos.y) / period))
		var j_max := int(ceil((max_p.y - base_pos.y) / period))
		for i in range(i_min, i_max + 1):
			for j in range(j_min, j_max + 1):
				var key := "%d_%d_%d" % [mi, i, j]
				if pool.has(key):
					continue
				var pos: Vector2 = base_pos + Vector2(float(i), float(j)) * period
				if pos.x < min_p.x or pos.x > max_p.x or pos.y < min_p.y or pos.y > max_p.y:
					continue
				if VolcanicNoise.ground_region(pos) != tex_idx:
					continue   # a DIFFERENT photo actually shows at this particular repetition — no crater here
				if _river_width > 0.0 and VolcanicNoise.is_river(pos, _river_width):
					continue   # this replica happens to land inside the lava band — see _maybe_place_grid
				var reveal_roll: float = VolcanicNoise.hash21(pos + reveal_salt)
				if reveal_roll >= reveal:
					continue   # this specific replica lost its Marked Crater Reveal % roll — stably, not per-frame
				var entry: Dictionary = _make_plume(pos, kind)
				entry["pos"] = pos
				pool[key] = entry

## Builds one vent's full entry — a "body" CPUParticles2D always, plus (flame only) a companion "spark"
## CPUParticles2D. Smoke keeps its original single-layer soft-puff treatment (that already reads fine for
## ash/smoke, which SHOULD look uniform/soft — real smoke doesn't throw off bright embers). Flame does not:
## a single particle layer, no matter how tuned, reads as a flat glowing blob, not fire — the second (spark)
## layer is what actually sells it, see this file's header.
func _make_plume(pos: Vector2, kind: String) -> Dictionary:
	var palette: Array = _colors.get(kind, [])
	var color: Color = palette[randi() % palette.size()] if not palette.is_empty() else Color(0.5, 0.5, 0.5)
	var body := _make_body(pos, kind)
	var spark: CPUParticles2D = _make_flame_spark(pos) if kind == "flame" else null
	var entry := {"body": body, "spark": spark, "color": color}
	_style_entry(entry, kind)
	return entry

func _make_body(pos: Vector2, kind: String) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = -1   # stays under the ship/enemies (z_index 1+) but above the ground CanvasLayer
	p.local_coords = true   # particles inherit this node's own fixed world position, not the camera's
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(14.0, 4.0) if kind == "smoke" else Vector2(9.0, 3.0)
	p.lifetime = float(_height.get(kind, 3.0))
	p.lifetime_randomness = 0.35
	p.amount = int(KIND_AMOUNT.get(kind, 20))
	p.direction = Vector2(0.0, -1.0)   # straight up (screen space, Y+ down)
	p.spread = float(KIND_SPREAD_DEG.get(kind, 16.0))
	var spd: float = float(_speed.get(kind, 24.0))
	p.initial_velocity_min = spd * 0.7
	p.initial_velocity_max = spd * 1.3
	p.gravity = _wind_gravity(kind)
	if kind == "flame":
		p.texture = _flame_tex
		p.scale_amount_min = 0.45
		p.scale_amount_max = 0.75
		p.scale_amount_curve = _make_flame_curve()
		p.angular_velocity_min = -FLAME_ANGULAR_VEL
		p.angular_velocity_max = FLAME_ANGULAR_VEL
		p.tangential_accel_min = -FLAME_TANGENTIAL_ACCEL
		p.tangential_accel_max = FLAME_TANGENTIAL_ACCEL
		p.radial_accel_min = -FLAME_RADIAL_ACCEL
		p.radial_accel_max = FLAME_RADIAL_ACCEL
		# smoke_flame.gdshader carries its own blend_add render_mode; else the plain additive material.
		p.material = _fx_flame_mat if USE_SMOKETRAIL_FX else _additive_mat
	else:
		p.scale_amount_min = 0.65
		p.scale_amount_max = 1.0
		p.scale_amount_curve = _make_growth_curve()   # billows outward as it rises
		p.angular_velocity_min = -12.0
		p.angular_velocity_max = 12.0
		if USE_SMOKETRAIL_FX:
			p.texture = SmokeTrail.shared_puff_tex()          # FBM "cauliflower" puff, not the soft blob
			p.color_initial_ramp = SmokeTrail.seed_initial_ramp()   # per-particle seed for the shader
			p.material = _fx_smoke_mat
		else:
			p.texture = _puff_tex
	add_child(p)
	return p

## The ember layer — small, fast, short-lived, additive, spinning freely (unlike the body, a tumbling round
## spark still reads correctly). Its own lifetime/speed derive from the flame kind's Speed/Height sliders
## (scaled up) rather than being separately tunable — sparks are a property OF the flame, not an independent
## knob, matching how a real fire's embers scale with how vigorously it's burning.
func _make_flame_spark(pos: Vector2) -> CPUParticles2D:
	var sp := CPUParticles2D.new()
	# Spawn origin sits ABOVE the body's base (near the flame's mid-height, not buried at its brightest,
	# widest point) and spreads along a tall thin strip — sparks read as breaking off the licks partway up,
	# not as emerging from directly inside the hottest part of the core where they'd be invisible at birth.
	sp.position = pos + Vector2(0.0, -14.0)
	sp.z_index = -1
	sp.local_coords = true
	sp.texture = _puff_tex
	sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sp.emission_rect_extents = Vector2(6.0, 14.0)
	sp.lifetime = maxf(0.25, float(_height.get("flame", 1.0)) * FLAME_SPARK_LIFETIME_FRAC)
	sp.lifetime_randomness = 0.5
	sp.amount = FLAME_SPARK_AMOUNT
	sp.direction = Vector2(0.0, -1.0)
	sp.spread = FLAME_SPARK_SPREAD_DEG
	var spd: float = float(_speed.get("flame", 45.0)) * FLAME_SPARK_SPEED_MULT
	sp.initial_velocity_min = spd * 0.6
	sp.initial_velocity_max = spd * 1.4
	sp.gravity = _wind_gravity("flame")
	sp.angular_velocity_min = -180.0
	sp.angular_velocity_max = 180.0   # sparks tumble freely, unlike the body's constrained lick-shape
	sp.tangential_accel_min = -FLAME_SPARK_TANGENTIAL_ACCEL
	sp.tangential_accel_max = FLAME_SPARK_TANGENTIAL_ACCEL
	sp.scale_amount_min = 0.16
	sp.scale_amount_max = 0.34
	sp.scale_amount_curve = _make_spark_curve()
	sp.material = _fx_ember_mat if USE_SMOKETRAIL_FX else _additive_mat
	add_child(sp)
	return sp

## Rebuilds `entry`'s body (+ spark, if any) color ramp/alpha from ITS OWN stored color (see this file's
## header) and the current opacity/brightness settings for `kind` — called at creation AND whenever
## opacity/brightness live-change, WITHOUT re-rolling the stored color.
func _style_entry(entry: Dictionary, kind: String) -> void:
	var color: Color = entry["color"]
	var opacity: float = float(_opacity.get(kind, 1.0))
	var brightness: float = float(_brightness.get(kind, 1.0))
	var base: Color = color * brightness
	var body: CPUParticles2D = entry["body"]
	if is_instance_valid(body):
		if USE_SMOKETRAIL_FX and kind == "smoke":
			body.color_ramp = _fx_smoke_ramp(opacity, brightness)   # value+alpha → smoke_trail.gdshader owns hue
		else:
			body.color_ramp = _make_ramp(base, opacity, kind)
	var spark: CPUParticles2D = entry.get("spark")
	if is_instance_valid(spark):
		# Sparks read as the HOTTEST point of the fire — push toward white regardless of the body's own
		# palette pick, same idea as a real ember glowing whiter/hotter than the flame around it.
		var hot: Color = base.lerp(Color(1.0, 1.0, 0.92), 0.5)
		spark.color_ramp = _make_ramp(hot, opacity, "flame")

## Ramp for a SmokeTrail-shaded smoke body: the shader does all the colouring itself (grey volumetric relief,
## warm-lit rim) and derives the puff's age from `1 - COLOR.a/peak_alpha`. So RGB just carries the Brightness
## slider (shader reads COLOR.g as an overall value multiplier) and A carries a brief fade-in + long fade-out
## scaled by Opacity. `peak_alpha` is kept in lockstep on the shared material so age reads right at any opacity.
func _fx_smoke_ramp(opacity: float, brightness: float) -> Gradient:
	var pk := minf(0.95, 0.9 * opacity)
	var val := clampf(brightness, 0.2, 2.0)
	if _fx_smoke_mat != null:
		_fx_smoke_mat.set_shader_parameter("peak_alpha", pk)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.5, 0.8, 1.0])
	g.colors = PackedColorArray([
		Color(val, val, val, 0.0),
		Color(val, val, val, pk),
		Color(val, val, val, pk * 0.78),
		Color(val, val, val, pk * 0.38),
		Color(val, val, val, 0.0),
	])
	return g

func _make_ramp(base: Color, opacity: float, kind: String) -> Gradient:
	var ramp := Gradient.new()
	if kind == "flame":
		# White-hot core -> the picked flame color -> a duller ember red -> gone. No "cooling toward ash"
		# mid-life plateau the way smoke has; fire just burns out.
		var hot := Color(1.0, 0.95, 0.85)
		var near_col := Color(lerp(hot.r, base.r, 0.45), lerp(hot.g, base.g, 0.45), lerp(hot.b, base.b, 0.45), 1.0 * opacity)
		var mid_col := Color(base.r, base.g * 0.6, base.b * 0.35, 0.7 * opacity)
		var far_col := Color(base.r * 0.8, base.g * 0.2, base.b * 0.08, 0.0)
		ramp.colors = PackedColorArray([near_col, mid_col, far_col])
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	else:
		# Smoke: dark, warm ember-lit near the vent mouth -> cooling toward the base tint -> fades to nothing.
		var near_col := Color(base.r * 0.5 + 0.15, base.g * 0.35, base.b * 0.30, 0.95 * opacity)
		var mid_col := Color(base.r, base.g, base.b, 0.7 * opacity)
		var far_col := Color(base.r * 1.1, base.g * 1.1, base.b * 1.1, 0.0)
		ramp.colors = PackedColorArray([near_col, mid_col, far_col])
		ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	return ramp

## Sets `entry`'s body (+ spark) gravity to the current wind vector for `kind` — see reroll_wind().
func _gravity_entry(entry: Dictionary, kind: String) -> void:
	var g := _wind_gravity(kind)
	var body: CPUParticles2D = entry["body"]
	if is_instance_valid(body):
		body.gravity = g
	var spark: CPUParticles2D = entry.get("spark")
	if is_instance_valid(spark):
		spark.gravity = g   # sparks share the flame's own gravity vector — same wind, same buoyancy source

## Frees `entry`'s body + spark (if any). Safe to call on an already-freed entry.
func _free_entry(entry: Dictionary) -> void:
	var body: CPUParticles2D = entry.get("body")
	if is_instance_valid(body):
		body.queue_free()
	var spark: CPUParticles2D = entry.get("spark")
	if is_instance_valid(spark):
		spark.queue_free()

func _make_growth_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	return c

## Fire flares up fast then tapers to a point as it burns out — the inverse shape of smoke's billow-outward
## curve (which keeps growing the whole time it's visible).
func _make_flame_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.85))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 0.08))
	return c

## Sparks shrink steadily as they cool — simpler than the body's flare-then-taper since a spark doesn't
## "billow," it just burns down to nothing.
func _make_spark_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.15))
	return c

## The combined accel every particle of `kind` rises under: that kind's own buoyancy (KIND_RISE_ACCEL)
## straight up, plus the current shared wind vector (see this file's header).
func _wind_gravity(kind: String) -> Vector2:
	var rad := deg_to_rad(_wind_dir_deg)
	var accel: float = float(KIND_RISE_ACCEL.get(kind, 10.0))
	return Vector2(0.0, -accel) + Vector2(cos(rad), sin(rad)) * _wind_strength

## Rolls a brand-new random wind direction (0..360°) and strength (0.._wind_strength_max), then re-applies the
## resulting gravity to every plume of EVERY kind already on screen (new plumes pick it up automatically).
## Public: called by the Plume Edit panel's REROLL WIND button, by apply_wind_strength_max() when the ceiling
## changes, and by this node's own _ready().
func reroll_wind() -> void:
	_roll_wind()
	for kind: String in KINDS:
		for key: Vector2 in _placed[kind].keys():
			_gravity_entry(_placed[kind][key], kind)
		for key: String in _marked_placed[kind].keys():
			_gravity_entry(_marked_placed[kind][key], kind)
	for lid in _landmark_placed.keys():
		var pools: Dictionary = _landmark_placed[lid]
		for kind: String in KINDS:
			for entry: Dictionary in pools.get(kind, []):
				_gravity_entry(entry, kind)

func _roll_wind() -> void:
	_wind_dir_deg = randf() * 360.0
	# User feedback: "Wind Strength min = 20, để khói luôn được thổi đi" — wind must never roll near-zero, or
	# smoke/flame just rise straight up with no visible drift. Clamped against the ceiling in case the Plume
	# Edit "Wind Strength" slider is set below WIND_STRENGTH_MIN (its range allows down to 0).
	var floor_val: float = minf(WIND_STRENGTH_MIN, _wind_strength_max)
	_wind_strength = randf_range(floor_val, _wind_strength_max)

## Forces every currently-placed AMBIENT/MARKED plume of `kind` (landmark plumes are untouched — they don't
## depend on view position) to be freed and immediately re-evaluated — used whenever a setting that changes
## WHICH cells/repetitions qualify (density, canopy_size, mark reveal %) is live-edited, so the panel's
## sliders feel responsive instead of waiting for REGEN_MOVE_THRESHOLD of camera movement.
func _force_regenerate(kind: String) -> void:
	for key: Vector2 in _placed[kind].keys():
		_free_entry(_placed[kind][key])
	_placed[kind].clear()
	for key: String in _marked_placed[kind].keys():
		_free_entry(_marked_placed[kind][key])
	_marked_placed[kind].clear()
	if _has_last_center:
		_regenerate()

## Public: called by the Plume Edit panel (live, on that kind's tab, on slider/ColorPickerButton change) and
## by this node's own _ready() (persisted settings). `colors` is that kind's 6-slot palette — each plume of
## this kind rolls its own random pick from it. `density` (0..1) is the AMBIENT vent chance for this kind
## (0..VENT_CHANCE_MAX per candidate grid cell) — marked/landmark plumes are unaffected by it. `speed` is
## px/s initial rise velocity; `height` is seconds of lifetime before a plume fully fades (also scales flame's
## spark lifetime — see _make_flame_spark). `mark_reveal_percent` (0..100) is the fraction of this kind's
## marked-crater replicas that actually show a plume — see this file's header.
func apply_kind_settings(kind: String, opacity_mult: float, brightness_mult: float, colors: Array, density: float, speed: float, height: float, mark_reveal_percent: float) -> void:
	if not _placed.has(kind):
		return
	_opacity[kind] = opacity_mult
	_brightness[kind] = brightness_mult
	_colors[kind] = colors.duplicate()
	var new_chance: float = clampf(density, 0.0, 1.0) * VENT_CHANCE_MAX
	var new_reveal: float = clampf(mark_reveal_percent, 0.0, 100.0) / 100.0
	var needs_regen := not is_equal_approx(new_chance, float(_vent_chance.get(kind, -1.0))) or not is_equal_approx(new_reveal, float(_mark_reveal.get(kind, -1.0)))
	_vent_chance[kind] = new_chance
	_mark_reveal[kind] = new_reveal
	_speed[kind] = speed
	_height[kind] = height
	for key: Vector2 in _placed[kind].keys():
		_style_entry(_placed[kind][key], kind)
	for key: String in _marked_placed[kind].keys():
		_style_entry(_marked_placed[kind][key], kind)
	for lid in _landmark_placed.keys():
		for entry: Dictionary in (_landmark_placed[lid] as Dictionary).get(kind, []):
			_style_entry(entry, kind)
	if needs_regen:
		_force_regenerate(kind)

## Public: called by the Plume Edit panel (live, on the "Wind Strength" slider — shared across both tabs) and
## by this node's own _ready() (persisted settings).
func apply_wind_strength_max(max_val: float) -> void:
	if is_equal_approx(max_val, _wind_strength_max):
		return
	_wind_strength_max = max_val
	reroll_wind()

## Public: called by the Terrain Edit panel (live, on "Ground Tile Size" slider change) and by this node's
## own _ready() (persisted settings) — marked-crater replication period is derived from canopy_size (see
## _regen_marked), so a size change must force a full re-placement of BOTH kinds' marked pools.
func apply_canopy_size(size_px: float) -> void:
	if is_equal_approx(size_px, _canopy_size):
		return
	_canopy_size = size_px
	for kind: String in KINDS:
		_force_regenerate(kind)

## Public: called by the Terrain Edit panel (live, on "River Width" slider change) and by this node's own
## _ready() (persisted settings). User feedback: "Plume và Flame không spawn trên river" — ambient/marked vents
## inside the lava band are skipped (see _maybe_place_grid/_regen_marked); a width change can newly include or
## exclude cells/replicas, so both kinds' ambient+marked pools are force-regenerated.
func apply_river_width(width: float) -> void:
	if is_equal_approx(width, _river_width):
		return
	_river_width = width
	for kind: String in KINDS:
		_force_regenerate(kind)

## Public: called by the Crater Mark panel (live, whenever a mark is added/removed on that kind's tab) and by
## this node's own _ready() (persisted settings).
func apply_crater_marks(kind: String, marks: Array) -> void:
	if not _crater_marks.has(kind):
		return
	_crater_marks[kind] = marks.duplicate(true)
	_force_regenerate(kind)

## Public: called by volcanic_temple_layer.gd once per spawned landmark instance. `entries` = Array of
## {"kind": "smoke"/"flame", "pos": Vector2} — already-transformed WORLD positions (that instance's own
## local-space marks, rotated/translated by its yaw/position — see volcanic_temple_layer.gd's header).
## Landmark plumes are PERMANENT for that instance's lifetime — no view-culling, replaces any previous set for
## the same `landmark_id` (used when the Landmark Mark panel edits marks live and volcanic_temple_layer.gd
## re-syncs every currently-spawned instance).
func set_landmark_plumes(landmark_id, entries: Array) -> void:
	clear_landmark_plumes(landmark_id)
	var pools := {"smoke": [], "flame": []}
	for e: Dictionary in entries:
		var kind: String = String(e.get("kind", "smoke"))
		if not pools.has(kind):
			continue
		(pools[kind] as Array).append(_make_plume(e["pos"], kind))
	_landmark_placed[landmark_id] = pools

## Public: frees every plume attached to `landmark_id`. Currently landmarks are permanent for the run, but
## set_landmark_plumes() calls this itself (to replace a stale set) and it's kept public/safe to call
## defensively (e.g. if landmarks ever gain a despawn path later).
func clear_landmark_plumes(landmark_id) -> void:
	if not _landmark_placed.has(landmark_id):
		return
	var pools: Dictionary = _landmark_placed[landmark_id]
	for kind: String in pools.keys():
		for entry: Dictionary in (pools[kind] as Array):
			_free_entry(entry)
	_landmark_placed.erase(landmark_id)

## Soft round puff — smoke's body AND flame's sparks (small = reads as an ember regardless of the round
## shape; it's the flame BODY that needed an elongated texture, not the sparks).
func _make_puff_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = int(PLUME_TEX_PX)
	tex.height = int(PLUME_TEX_PX)
	return tex

## Flame body texture — a soft radial gradient baked into a TALLER-than-wide canvas (FLAME_TEX_W x
## FLAME_TEX_H), so the same "distance from center" gradient math that makes _make_puff_tex() round instead
## renders as a vertically-elongated glow: an upright flame LICK shape, not a round blob, with zero extra
## draw cost (CPUParticles2D just stretches this one flat texture per particle, same as the smoke puff).
func _make_flame_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = FLAME_TEX_W
	tex.height = FLAME_TEX_H
	return tex
