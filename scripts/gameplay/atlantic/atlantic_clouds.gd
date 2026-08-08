extends Node2D
class_name AtlanticClouds
## TWO kinds of plume for the Atlantic map — "bubble" (rising bubble columns) and "whirlpool" (a rotating
## vortex/water-spout funnel), replacing Volcanic's smoke/flame pair (2026-08-06, on request: "bong bóng nổi
## lên và vòi rồng xoáy" instead of ash/fire). Every plume-related public method takes a `kind: String`
## ("bubble" or "whirlpool", see KINDS) and drives that kind's own independent settings/pools — the two kinds
## never share particles, only the world-anchored/hover-free architecture below (a straight port of
## volcanic/volcanic_clouds.gd's own architecture — see that file's header for the full rationale on why it's
## shaped this way).
##
## WHIRLPOOL has THREE independent vent sources, all spawning via the same _make_plume(pos, kind):
##   1. RANDOM AMBIENT vents — a coarse world-space hash grid (AtlanticNoise.hash21), tunable via the Plume Edit
##      panel's "Density" slider. `_placed["whirlpool"]`.
##   2. MARKED vents — user-placed via atlantic_crater_mark.gd (clicking the maptile photo). A mark is a
##      normalized (u, v) on one specific ground photo — replicated at EVERY world-space repetition of that
##      photo, spawning only where AtlanticNoise.ground_region() agrees that photo is the one showing there.
##      Always-on subject to "Marked Vent Reveal %". `_marked_placed["whirlpool"]`.
##   3. LANDMARK-ATTACHED vents — set_landmark_plumes(), called by atlantic_temple_layer.gd once per spawned
##      temple instance with already-world-transformed positions. PERMANENT for that landmark instance's
##      lifetime. `_landmark_placed[landmark_id][kind]`.
##
## BUBBLE instead uses a SINGLE unified RATE spawner covering what used to be two separate sources (2026-08-08
## fix, then 2026-08-09 unification on request: "Bubble Rate có thêm thanh điều chỉnh cả vent mark, đây mới là
## chỗ tôi muốn điều chỉnh" — the old split meant "Bubble Rate" alone could never promise "0 = 0 bubbles" once
## any Crater Mark existed). `_bubble_rate` (bubbles/sec, = the "Bubble Rate" slider ÷ BUBBLE_RATE_DIVISOR) ticks
## `_bubble_spawn_accum` every _process(delta) and spawns ONE discrete single/few-particle bubble per whole
## accumulated unit, at a spawn point that's EITHER a pure-random point in view OR (50% chance, if any marks
## exist) one of the Crater Mark panel's placed positions (_pick_bubble_spawn_pos()) — current-avoiding either
## way, self-freeing after its own lifetime. `_ambient_bubbles` (a flat Array, not a stable per-cell dict, since
## these are transient one-shots) — bubble's `_placed`/`_marked_placed` dicts stay permanently empty, kept only
## for structural symmetry with whirlpool. Bubble LANDMARK vents (temple-attached) are still a separate,
## always-on third source, same as whirlpool's.
##
## Every vent is ONE ENTRY = {"body": CPUParticles2D, "spark": CPUParticles2D or null, "funnel": MeshInstance3D
## or null, "color": Color, "size_mult": float}. Bubble has no spark/funnel companion; WHIRLPOOL has BOTH — a
## center-jet "spray" layer of droplets flung upward out of the vortex's throat (same "second layer sells the
## effect" idea Volcanic's flame sparks use), plus a REAL 3D cone-frustum "funnel" mesh (atlantic_whirlpool_
## funnel3d.gdshader) spawned into atlantic_trees.gd's shared World3D root — same isometric-tilted camera/
## compositor the ship/temple/scattered coral already render through, so it just shows up, no extra viewport
## needed. Replaced a flat top-down 2D disc on 2026-08-08 (on request: "tôi muốn xoay vfx này để có thể nhìn
## thấy thân Whirlpool" — a flat disc can only ever show its top face, never a wall).
##
## Bubble's body is a straight-up rising column, same technique as Volcanic's smoke (EMISSION_SHAPE_RECTANGLE,
## constant upward accel + shared current push), textured with _make_bubble_tex()'s fresnel-rim-plus-highlight
## bubble (added 2026-08-08 — bright thin edge ring + one offset glint dot, replacing the plain soft radial
## blob every other plume/spark system in this project still uses, which read as too flat/fake for something
## meant to look like a small glass sphere). Whirlpool is a genuinely different shape — no direct Volcanic
## equivalent (see the class-level research note from 2026-08-06's Atlantic build): particles spawn around a
## RING (EMISSION_SHAPE_SPHERE_SURFACE, which in 2D emits from a circle's circumference) with strong
## tangential_accel (spin) and negative radial_accel (pulled inward toward the vortex core), shrinking as they
## approach center — reads as water circling down into a drain/funnel. The companion "spray" jet then throws
## droplets straight up from that same center point, standing in for the spout portion.
##
## CURRENT is the one thing SHARED across both kinds — a single direction+strength, rolled randomly once per
## map load (mirrors Volcanic's shared "wind"), applied as a constant lateral accel added to every particle's
## `gravity` regardless of kind. Re-rollable live via Plume Edit's REROLL CURRENT.
##
## Each plume instance independently rolls ONE random color from that kind's own 6-slot palette at creation
## and keeps it — live palette edits re-color future plumes, not existing ones.
##
## This node stays at the world origin and never moves — every plume's CPUParticles2D column is a plain child
## at its own FIXED world coordinate (local_coords = true). update_view() only decides which vents currently
## exist within view+margin (ambient/marked pools only — landmark pools are always alive).

const AtlanticNoise := preload("res://scripts/gameplay/atlantic/atlantic_noise.gd")
const AtlanticTerrainSettings := preload("res://scripts/gameplay/atlantic/atlantic_terrain_settings.gd")

const KINDS := ["bubble", "whirlpool"]

const CELL_SIZE := 900.0        # world-px grid spacing between ambient vent CANDIDATES (not every cell gets one)
const MARGIN := 300.0           # extra world-px beyond the viewport a vent may exist in before it's culled
const REGEN_MOVE_THRESHOLD := 220.0
const VENT_CHANCE_MAX := 0.5    # density (0..1) maps to 0..this fraction of candidate cells actually spawning
const CURRENT_STRENGTH_MIN := 12.0   # current never rolls below this — see _roll_current()

const PLUME_TEX_PX := 64.0      # _make_puff_tex's native size (whirlpool spray droplets)
const WHIRL_FUNNEL_3D_SHADER := preload("res://scripts/gameplay/atlantic/atlantic_whirlpool_funnel3d.gdshader")
const WHIRL_FUNNEL_RADIAL_SEGMENTS := 24
const WHIRL_FUNNEL_HEIGHT_SEGMENTS := 16   # rings along the profile CURVE (2026-08-09 — a curved wall needs more
                                             # than CylinderMesh's 2-ring straight taper to read smoothly)
const BUBBLE_TEX_PX := 48.0     # _make_bubble_tex's native size — smaller than PLUME_TEX_PX, bubbles read small

# Per-kind physical/visual constants — NOT user-tunable.
const KIND_RISE_ACCEL := {"bubble": 0.0, "whirlpool": 4.0}    # px/s^2 EXTRA upward accel on top of initial_velocity.
                                                                 # Bubble is 0 (2026-08-08 fix) so the "Rise Speed"
                                                                 # slider IS the bubble's actual, stable observed
                                                                 # rise speed — a nonzero accel here kept compounding
                                                                 # speed past the slider value over a bubble's life.
                                                                 # Whirlpool water barely rises at all (it's spiraling
                                                                 # inward, not floating away) — untouched.
const BUBBLE_RATE_SLIDER_MAX := 100.0   # Plume Edit's "Bubble Rate" slider range (0..100)
const BUBBLE_RATE_DIVISOR := 10.0       # slider value -> bubbles/sec: 100 -> 10/sec (2026-08-08 request)
const BUBBLE_AMBIENT_AMOUNT := 3        # particles per discrete ambient bubble spawn — a small handful, not a
                                          # full KIND_AMOUNT["bubble"] column (that stays for marked/landmark bubbles)
const KIND_SPREAD_DEG := {"bubble": 14.0, "whirlpool": 180.0}  # bubble = a tight rising column; whirlpool
                                                                 # spreads its whole ring (see EMISSION_SHAPE)
const KIND_AMOUNT := {"bubble": 22, "whirlpool": 26}

# Whirlpool body: strong tangential spin + inward pull, mild wobble in angular_velocity so individual bubbles-
# of-foam don't all rotate in perfect lockstep.
const WHIRL_ANGULAR_VEL := 40.0
const WHIRL_TANGENTIAL_ACCEL := 90.0    # spin speed around the vortex center
const WHIRL_RADIAL_ACCEL := -55.0       # negative = pulled INWARD toward the core (this is what reads as "sucked in")

# Whirlpool SPRAY — a second, independent CPUParticles2D per whirlpool plume: droplets flung straight up out
# of the vortex's throat, standing in for the spout. Small, few, fast, short-lived, additive (foam highlight).
const WHIRL_SPRAY_AMOUNT := 7
const WHIRL_SPRAY_SPREAD_DEG := 22.0     # a narrow upward jet, unlike the body's full-ring spread
const WHIRL_SPRAY_LIFETIME_FRAC := 0.55
const WHIRL_SPRAY_SPEED_MULT := 2.6
const WHIRL_SPRAY_TANGENTIAL_ACCEL := 30.0

var _placed: Dictionary = {"bubble": {}, "whirlpool": {}}          # kind -> cell Vector2 -> entry (whirlpool only — see _bubble_rate/_ambient_bubbles for bubble's own ambient path)
var _bubble_rate: float = 0.0            # bubbles/sec — see BUBBLE_RATE_DIVISOR
var _bubble_spawn_accum: float = 0.0     # fractional bubbles owed, ticked in _process()
var _ambient_bubbles: Array = []         # flat list of {"body":..., "spark":null, "funnel":null, "color":..., "ttl": float} — one-shot, self-expiring
var _marked_placed: Dictionary = {"bubble": {}, "whirlpool": {}}   # kind -> "mi_i_j" String -> entry (+ "pos")
var _landmark_placed: Dictionary = {}                                # landmark_id -> {"bubble":[entry,...], "whirlpool":[...]}
var _crater_marks: Dictionary = {"bubble": [], "whirlpool": []}
var _canopy_size: float = AtlanticTerrainSettings.DEFAULT_CANOPY_SIZE
var _last_center: Vector2 = Vector2.ZERO
var _last_regen_center: Vector2 = Vector2.ZERO
var _has_last_center: bool = false
var _view_size: Vector2 = Vector2(1440.0, 780.0)
var _puff_tex: GradientTexture2D
var _bubble_tex: ImageTexture
var _additive_mat: CanvasItemMaterial

var _opacity: Dictionary = {}     # kind -> float
var _brightness: Dictionary = {}  # kind -> float
var _colors: Dictionary = {}      # kind -> Array[Color] (6-slot palette)
var _vent_chance: Dictionary = {} # kind -> float (0..VENT_CHANCE_MAX)
var _speed: Dictionary = {}       # kind -> float
var _height: Dictionary = {}      # kind -> float (lifetime seconds)
var _mark_reveal: Dictionary = {} # kind -> float (0..1)

var _current_strength_max: float = AtlanticTerrainSettings.DEFAULT_WIND_STRENGTH_MAX
var _current_dir_deg: float = 0.0     # rolled fresh in _ready()/reroll_current()
var _current_strength: float = 0.0
var _river_width: float = 0.0         # half-width of the current band — see apply_river_width()

var _whirl_size_min: float = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_SIZE_MIN   # each whirlpool independently
var _whirl_size_max: float = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_SIZE_MAX   # rolls a multiplier in this
                                                                                     # range at creation and keeps it
var _whirl_tilt_deg: Vector3 = Vector3.ZERO   # SHARED orientation offset applied to every funnel mesh — see
                                                # apply_whirlpool_tilt() (2026-08-08, on request: a way to angle
                                                # the funnel instead of it always standing perfectly upright)
var _whirl_mouth_radius: float = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_MOUTH_RADIUS   # top (wide) radius —
                                                # also where the particle ring/spray emit — before size_mult
var _whirl_throat_radius: float = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_THROAT_RADIUS # bottom (narrow) radius
var _whirl_height: float = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_HEIGHT               # total funnel depth (world Y)
var _whirl_profile_exp: float = AtlanticTerrainSettings.DEFAULT_WHIRLPOOL_PROFILE_EXP     # radius(t) = throat +
                                                # (mouth-throat)*(1-t)^exp — <1 stays wide/flared near the mouth
                                                # and only pinches sharply right at the throat (2026-08-09 fix:
                                                # a real whirlpool isn't a straight-walled cone — see this file's
                                                # header and atlantic_whirlpool_funnel3d.gdshader's own header)

func _ready() -> void:
	add_to_group("atlantic_clouds")   # so the Plume Edit panel can find this instance
	_puff_tex = _make_puff_tex()
	_bubble_tex = _make_bubble_tex()
	_additive_mat = CanvasItemMaterial.new()
	_additive_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var s := AtlanticTerrainSettings.load_settings()
	_canopy_size = float(s["canopy_size"])
	_river_width = float(s["river_width"])
	_crater_marks["bubble"] = (s["bubble_crater_marks"] as Array).duplicate(true)
	_crater_marks["whirlpool"] = (s["whirlpool_crater_marks"] as Array).duplicate(true)
	apply_kind_settings("bubble", s["bubble_opacity"], s["bubble_brightness"],
		[s["bubble_color_0"], s["bubble_color_1"], s["bubble_color_2"], s["bubble_color_3"], s["bubble_color_4"], s["bubble_color_5"]],
		s["bubble_density"], s["bubble_speed"], s["bubble_height"], s["bubble_mark_reveal_percent"])
	apply_kind_settings("whirlpool", s["whirlpool_opacity"], s["whirlpool_brightness"],
		[s["whirlpool_color_0"], s["whirlpool_color_1"], s["whirlpool_color_2"], s["whirlpool_color_3"], s["whirlpool_color_4"], s["whirlpool_color_5"]],
		s["whirlpool_density"], s["whirlpool_speed"], s["whirlpool_height"], s["whirlpool_mark_reveal_percent"])
	apply_whirlpool_size(s["whirlpool_size_min"], s["whirlpool_size_max"])
	apply_whirlpool_tilt(s["whirlpool_rot_x_deg"], s["whirlpool_rot_y_deg"], s["whirlpool_rot_z_deg"])
	apply_whirlpool_dimensions(s["whirlpool_mouth_radius"], s["whirlpool_throat_radius"], s["whirlpool_height_px"], s["whirlpool_profile_exp"])
	_current_strength_max = float(s["wind_strength_max"])
	_roll_current()

## Ticks the bubble RATE spawner + expires finished ambient bubbles. Grid/marked/landmark vents (both kinds) are
## driven by update_view() instead (only re-evaluated on camera movement, not every frame) — this is the one
## per-frame path in the whole file, needed because a literal "N bubbles/sec" promise has to be TIME-based, not
## spatial-hash-based. See this file's header.
func _process(delta: float) -> void:
	if _bubble_rate > 0.0:
		_bubble_spawn_accum += delta * _bubble_rate
		while _bubble_spawn_accum >= 1.0:
			_bubble_spawn_accum -= 1.0
			_spawn_ambient_bubble()
	elif _bubble_spawn_accum != 0.0:
		_bubble_spawn_accum = 0.0   # rate dropped to 0 (or below) — don't let a stale accumulator fire once it's raised again
	for i in range(_ambient_bubbles.size() - 1, -1, -1):
		var entry: Dictionary = _ambient_bubbles[i]
		entry["ttl"] = float(entry["ttl"]) - delta
		if float(entry["ttl"]) <= 0.0:
			_free_entry(entry)
			_ambient_bubbles.remove_at(i)

## One discrete bubble (or small handful — BUBBLE_AMBIENT_AMOUNT) at a random point within the current view,
## current-avoiding same as the grid/marked placers. Self-expires via _process()'s ttl sweep instead of
## view-culling, since it's a one-shot, not a persistent vent tied to a world cell.
func _spawn_ambient_bubble() -> void:
	var pos: Vector2 = _pick_bubble_spawn_pos()
	if _river_width > 0.0 and AtlanticNoise.is_river(pos, _river_width):
		return   # skip this roll rather than retry — at a real bubbles/sec rate a miss just means slightly fewer
	var entry := _make_plume(pos, "bubble")
	var body: CPUParticles2D = entry["body"]
	body.amount = BUBBLE_AMBIENT_AMOUNT
	body.one_shot = true
	entry["ttl"] = float(_height.get("bubble", 3.0)) * 1.5   # generous buffer past its own lifetime so it fully rises+fades before freeing
	_ambient_bubbles.append(entry)

## 2026-08-09 unification (on request: "Bubble Rate có thêm thanh điều chỉnh cả vent mark, đây mới là chỗ tôi
## muốn điều chỉnh") — Bubble Rate is now the ONE master control for every ambient bubble on screen, whether it
## spawns at a pure-random point OR at one of the user's own Crater-Mark positions. There's no more separate
## "Marked Vent Reveal %"/always-on persistent marked pool for bubble (still exists for whirlpool, unchanged) —
## a mark is just an extra weighted candidate SOURCE for where the next rate-spawned bubble appears, so dragging
## Bubble Rate to 0 now means EXACTLY 0 bubbles, full stop, marks included.
## 50/50 split between "pick one of the marks" and "pick a pure-random point" whenever marks exist at all.
func _pick_bubble_spawn_pos() -> Vector2:
	var half: Vector2 = _view_size * 0.5 + Vector2(MARGIN, MARGIN)
	var marks: Array = _crater_marks["bubble"]
	if not marks.is_empty() and randf() < 0.5:
		var mark: Dictionary = marks[randi() % marks.size()]
		var mark_pos = _random_mark_replica_pos(mark, half)
		if mark_pos != null:
			return mark_pos
	return _last_center + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))

## Picks ONE random currently-in-view world-space replica of `mark` (a mark can repeat at every world-space
## tiling of its reference photo — see this file's header) — same replication math as _regen_marked(), just
## returning a single random pick instead of enumerating/persisting every replica. Returns null if the mark has
## no valid replica in view right now (e.g. a different photo actually shows at every candidate spot).
func _random_mark_replica_pos(mark: Dictionary, half: Vector2):
	var ground_uv_scale: float = 1.0 / maxf(_canopy_size, 1.0)
	var tex_idx: int = clampi(int(mark.get("tex", 0)), 0, 2)
	var uv := Vector2(float(mark.get("u", 0.5)), float(mark.get("v", 0.5)))
	var mult: float = AtlanticNoise.GROUND_UV_MULT[tex_idx]
	var offset: Vector2 = AtlanticNoise.GROUND_UV_OFFSET[tex_idx]
	var scale: float = ground_uv_scale * mult
	if scale <= 0.0:
		return null
	var period: float = 1.0 / scale
	var base_pos: Vector2 = (uv - offset) / scale
	var min_p: Vector2 = _last_center - half
	var max_p: Vector2 = _last_center + half
	var i_min := int(floor((min_p.x - base_pos.x) / period))
	var i_max := int(ceil((max_p.x - base_pos.x) / period))
	var j_min := int(floor((min_p.y - base_pos.y) / period))
	var j_max := int(ceil((max_p.y - base_pos.y) / period))
	var candidates: Array = []
	for i in range(i_min, i_max + 1):
		for j in range(j_min, j_max + 1):
			var pos: Vector2 = base_pos + Vector2(float(i), float(j)) * period
			if pos.x < min_p.x or pos.x > max_p.x or pos.y < min_p.y or pos.y > max_p.y:
				continue
			if AtlanticNoise.ground_region(pos) != tex_idx:
				continue   # a DIFFERENT photo actually shows at this particular replica — no vent here
			candidates.append(pos)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

## Public: called every frame with the camera's world-space focus and viewport size (mirrors
## AtlanticTrees.update_view) — decides which whirlpool ambient / either kind's marked vents currently exist
## within view+margin (landmark-attached plumes are permanent, unaffected by this; bubble's own ambient path is
## _process()'s rate spawner above, not this).
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
		if kind != "bubble":   # bubble's ambient AND marked vents are both the rate spawner above now — see
			_regen_grid(kind, min_p, max_p)   # _pick_bubble_spawn_pos()/2026-08-09's "one master rate" unification
			_regen_marked(kind, min_p, max_p)

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
	# Salt the hash differently per kind so bubble/whirlpool ambient rolls at the same cell are independent.
	var salt: Vector2 = Vector2(511.0, -233.0) if kind == "bubble" else Vector2(-611.0, 833.0)
	var roll: float = AtlanticNoise.hash21(cell + salt)
	if roll >= float(_vent_chance.get(kind, 0.0)):
		return
	var jitter := Vector2(
		(AtlanticNoise.hash21(cell + salt + Vector2(71.0, 5.0)) - 0.5) * CELL_SIZE * 0.6,
		(AtlanticNoise.hash21(cell + salt + Vector2(5.0, 71.0)) - 0.5) * CELL_SIZE * 0.6
	)
	var pos: Vector2 = cell + jitter
	if _river_width > 0.0 and AtlanticNoise.is_river(pos, _river_width):
		return   # no bubble/whirlpool vent inside the current band itself, same rule Volcanic applies to lava
	pool[cell] = _make_plume(pos, kind)

## Replicates every entry in _crater_marks[kind] at EVERY world-space repetition of its source photo within
## [min_p, max_p] — see this file's header, mirrors volcanic_clouds.gd's _regen_marked exactly.
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
	var reveal_salt: Vector2 = Vector2(777.0, 333.0) if kind == "bubble" else Vector2(-919.0, 271.0)
	for mi in marks.size():
		var mark: Dictionary = marks[mi]
		var tex_idx: int = clampi(int(mark.get("tex", 0)), 0, 2)
		var uv := Vector2(float(mark.get("u", 0.5)), float(mark.get("v", 0.5)))
		var mult: float = AtlanticNoise.GROUND_UV_MULT[tex_idx]
		var offset: Vector2 = AtlanticNoise.GROUND_UV_OFFSET[tex_idx]
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
				if AtlanticNoise.ground_region(pos) != tex_idx:
					continue   # a DIFFERENT photo actually shows at this particular repetition — no vent here
				if _river_width > 0.0 and AtlanticNoise.is_river(pos, _river_width):
					continue
				var reveal_roll: float = AtlanticNoise.hash21(pos + reveal_salt)
				if reveal_roll >= reveal:
					continue   # this specific replica lost its Marked Reveal % roll — stably, not per-frame
				var entry: Dictionary = _make_plume(pos, kind)
				entry["pos"] = pos
				pool[key] = entry

## Builds one vent's full entry — a "body" CPUParticles2D always, plus (whirlpool only) a companion "spark"
## (here: spray-droplet) CPUParticles2D. Whirlpool also rolls ONE random size multiplier (independent of its
## color roll) and keeps it for the vent's whole lifetime — shared across body/spray/funnel so all three scale
## together (2026-08-08, on request: "chỉnh size, sẽ random to nhỏ giữa trên size chỉ định").
func _make_plume(pos: Vector2, kind: String) -> Dictionary:
	var palette: Array = _colors.get(kind, [])
	var color: Color = palette[randi() % palette.size()] if not palette.is_empty() else Color(0.5, 0.5, 0.5)
	var size_mult: float = randf_range(_whirl_size_min, _whirl_size_max) if kind == "whirlpool" else 1.0
	var body := _make_body(pos, kind, size_mult)
	var spark: CPUParticles2D = _make_whirl_spray(pos, size_mult) if kind == "whirlpool" else null
	var funnel: MeshInstance3D = _make_whirl_funnel(pos, size_mult) if kind == "whirlpool" else null
	var entry := {"body": body, "spark": spark, "funnel": funnel, "color": color, "size_mult": size_mult}
	_style_entry(entry, kind)
	return entry

func _make_body(pos: Vector2, kind: String, size_mult: float = 1.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = -1   # stays under the ship/enemies (z_index 1+) but above the ground CanvasLayer
	p.local_coords = true   # particles inherit this node's own fixed world position, not the camera's
	p.lifetime = float(_height.get(kind, 3.0))
	p.lifetime_randomness = 0.35
	p.amount = int(KIND_AMOUNT.get(kind, 20))
	p.texture = _puff_tex
	var spd: float = float(_speed.get(kind, 24.0))
	if kind == "whirlpool":
		# A ring of particles spiraling down into the vortex core — EMISSION_SHAPE_SPHERE_SURFACE emits from a
		# circle's circumference in 2D, giving the "mouth of the whirlpool" starting ring for free.
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		p.emission_sphere_radius = _whirl_mouth_radius * size_mult
		p.direction = Vector2(0.0, -1.0)
		p.spread = float(KIND_SPREAD_DEG.get(kind, 180.0))
		p.initial_velocity_min = spd * 0.15
		p.initial_velocity_max = spd * 0.35   # barely any outward/radial launch speed — the spin+pull do the work
		p.gravity = _current_gravity(kind)
		p.scale_amount_min = 0.5 * size_mult
		p.scale_amount_max = 0.85 * size_mult
		p.scale_amount_curve = _make_whirl_curve()   # shrinks toward the center as it's drawn in
		p.angular_velocity_min = -WHIRL_ANGULAR_VEL
		p.angular_velocity_max = WHIRL_ANGULAR_VEL
		# Negative tangential_accel = counter-clockwise on screen in Godot 2D (Y-down flips the usual math-CCW
		# convention) — matches the funnel mesh's own CCW spin fixed in atlantic_whirlpool_funnel3d.gdshader
		# (2026-08-09 bug report: the two layers used to spin opposite ways).
		p.tangential_accel_min = -WHIRL_TANGENTIAL_ACCEL * 1.15
		p.tangential_accel_max = -WHIRL_TANGENTIAL_ACCEL * 0.85
		p.radial_accel_min = WHIRL_RADIAL_ACCEL * 1.15
		p.radial_accel_max = WHIRL_RADIAL_ACCEL * 0.85
		p.material = _additive_mat   # foam/caustic-highlight glow
	else:
		# Bubble: a plain rising column, same shape/technique as Volcanic's smoke — textured with the fresnel-
		# rim bubble (_make_bubble_tex) instead of a flat soft blob.
		p.texture = _bubble_tex
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(10.0, 4.0)
		p.direction = Vector2(0.0, -1.0)   # straight up (screen space, Y+ down)
		p.spread = float(KIND_SPREAD_DEG.get(kind, 14.0))
		p.initial_velocity_min = spd * 0.75
		p.initial_velocity_max = spd * 1.25
		p.gravity = _current_gravity(kind)
		p.scale_amount_min = 0.35
		p.scale_amount_max = 0.65
		p.scale_amount_curve = _make_bubble_curve()   # wobbles/grows slightly as it rises
		p.angular_velocity_min = -20.0
		p.angular_velocity_max = 20.0
	add_child(p)
	return p

## The whirlpool's real vortex-shaped visual — a CUSTOM curved-profile mesh (2026-08-09, replacing a straight-
## walled CylinderMesh cone on request: "Shape của Whirlpool trong thực tế không phải là hình cone đơn giản, mà
## miệng của nó loe ra rộng hơn, thuôn dần về throat" — a real whirlpool stays wide/flared for most of its depth
## and only pinches into a narrow throat right at the very bottom, not a straight taper. See _build_funnel_mesh()
## for the profile curve and atlantic_whirlpool_funnel3d.gdshader for the logarithmic-spiral surface pattern).
## Spawned into atlantic_trees.gd's shared World3D "host" root so it renders through the SAME isometric-tilted
## camera/compositor as the ship/temple/scattered coral — no separate viewport needed (see atlantic_trees.gd's
## get_world3d_root()/get_z_comp() and atlantic_asset_layer.gd's header for the full pipeline). Wide mouth at
## world Y=0 (the water surface), narrow throat extending down into "underwater" — the isometric tilt lets you
## see the funnel's own inner wall, not just its rim. Returns null (no crash) if AtlanticTrees isn't ready yet.
func _make_whirl_funnel(pos: Vector2, size_mult: float = 1.0) -> MeshInstance3D:
	var trees := get_tree().get_first_node_in_group("atlantic_trees")
	if trees == null or not trees.has_method("get_world3d_root") or not trees.has_method("get_z_comp"):
		return null
	var world_root: Node3D = trees.call("get_world3d_root")
	if world_root == null:
		return null
	var z_comp: float = float(trees.call("get_z_comp"))

	var mouth_r: float = _whirl_mouth_radius * size_mult
	var throat_r: float = _whirl_throat_radius * size_mult
	var depth: float = _whirl_height * size_mult

	var mi := MeshInstance3D.new()
	mi.mesh = _build_funnel_mesh(mouth_r, throat_r, depth, _whirl_profile_exp)
	# Mesh is built with its MOUTH ring at local Y=0 and the throat at local Y=-depth (see _build_funnel_mesh) —
	# so the node itself can sit right at the water surface, no extra offset needed.
	mi.position = Vector3(pos.x, 0.0, pos.y * z_comp)
	mi.rotation_degrees = _whirl_tilt_deg   # shared orientation offset — see apply_whirlpool_tilt()
	var mat := ShaderMaterial.new()
	mat.shader = WHIRL_FUNNEL_3D_SHADER
	mat.set_shader_parameter("mouth_radius", mouth_r)
	mat.set_shader_parameter("throat_radius", throat_r)
	mat.set_shader_parameter("profile_exp", _whirl_profile_exp)
	mi.material_override = mat
	world_root.add_child(mi)
	return mi

## Builds the funnel's curved-wall surface of revolution: radius(t) = throat_r + (mouth_r-throat_r)*(1-t)^exp,
## t=0 at the mouth (rim, y=0) down to t=1 at the throat (y=-depth). exp<1 keeps the wall close to mouth_r for
## most of the depth and only pinches toward throat_r sharply near the very end (a real whirlpool's "wide bowl,
## narrow drain" profile); exp=1 would reproduce the old straight cone. WHIRL_FUNNEL_HEIGHT_SEGMENTS rings
## approximate the curve — a plain 2-ring CylinderMesh can only ever do a straight line between two radii.
func _build_funnel_mesh(mouth_r: float, throat_r: float, depth: float, exp_v: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := WHIRL_FUNNEL_HEIGHT_SEGMENTS
	var segs := WHIRL_FUNNEL_RADIAL_SEGMENTS
	for j in rings + 1:
		var t: float = float(j) / float(rings)
		var r: float = throat_r + (mouth_r - throat_r) * pow(1.0 - t, exp_v)
		var y: float = -t * depth
		for i in segs + 1:
			var u: float = float(i) / float(segs)
			var theta: float = u * TAU
			var x: float = sin(theta) * r
			var z: float = cos(theta) * r
			st.set_uv(Vector2(u, t))
			st.set_normal(Vector3(sin(theta), 0.0, cos(theta)))   # outward-radial approximation — material is
			                                                        # unshaded, so the exact normal doesn't matter
			st.add_vertex(Vector3(x, y, z))
	var row_len := segs + 1
	for j in rings:
		for i in segs:
			var a := j * row_len + i
			var b := a + 1
			var c := (j + 1) * row_len + i
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	return st.commit()

## The spray layer — small, fast, short-lived droplets shot straight up from the vortex's throat, additive.
## Standing in for the "spout" half of a whirlpool: the body reads as water circling down INTO the funnel,
## the spray reads as water being flung back UP out of it. Lifetime/speed derive from the whirlpool kind's own
## Speed/Height sliders (scaled up), same "a property OF the effect, not an independent knob" idea Volcanic's
## flame sparks use.
func _make_whirl_spray(pos: Vector2, size_mult: float = 1.0) -> CPUParticles2D:
	var sp := CPUParticles2D.new()
	sp.position = pos
	sp.z_index = -1
	sp.local_coords = true
	sp.texture = _puff_tex
	sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 6.0 * size_mult
	sp.lifetime = maxf(0.2, float(_height.get("whirlpool", 1.0)) * WHIRL_SPRAY_LIFETIME_FRAC)
	sp.lifetime_randomness = 0.5
	sp.amount = WHIRL_SPRAY_AMOUNT
	sp.direction = Vector2(0.0, -1.0)
	sp.spread = WHIRL_SPRAY_SPREAD_DEG
	var spd: float = float(_speed.get("whirlpool", 70.0)) * WHIRL_SPRAY_SPEED_MULT
	sp.initial_velocity_min = spd * 0.6
	sp.initial_velocity_max = spd * 1.4
	sp.gravity = _current_gravity("whirlpool") + Vector2(0.0, 40.0)   # a little extra downward pull so
	                                                                    # droplets arc back down like real spray
	sp.angular_velocity_min = -180.0
	sp.angular_velocity_max = 180.0
	sp.tangential_accel_min = -WHIRL_SPRAY_TANGENTIAL_ACCEL
	sp.tangential_accel_max = WHIRL_SPRAY_TANGENTIAL_ACCEL
	sp.scale_amount_min = 0.14 * size_mult
	sp.scale_amount_max = 0.30 * size_mult
	sp.scale_amount_curve = _make_spray_curve()
	sp.material = _additive_mat
	add_child(sp)
	return sp

## Rebuilds `entry`'s body (+ spark/funnel, if any) color ramp/tint from ITS OWN stored color and the current
## opacity/brightness/speed settings for `kind` — called at creation AND whenever those settings live-change,
## WITHOUT re-rolling the stored color.
func _style_entry(entry: Dictionary, kind: String) -> void:
	var color: Color = entry["color"]
	var opacity: float = float(_opacity.get(kind, 1.0))
	var brightness: float = float(_brightness.get(kind, 1.0))
	var base: Color = color * brightness
	var body: CPUParticles2D = entry["body"]
	if is_instance_valid(body):
		body.color_ramp = _make_ramp(base, opacity, kind)
	var spark: CPUParticles2D = entry.get("spark")
	if is_instance_valid(spark):
		# Spray reads as the BRIGHTEST foam of the whirlpool — push toward white regardless of the body's own
		# palette pick.
		var hot: Color = base.lerp(Color(0.95, 1.0, 1.0), 0.6)
		spark.color_ramp = _make_ramp(hot, opacity, "whirlpool")
	var funnel: MeshInstance3D = entry.get("funnel")
	if is_instance_valid(funnel):
		var fmat: ShaderMaterial = funnel.material_override
		fmat.set_shader_parameter("tint", base)
		fmat.set_shader_parameter("opacity", opacity)
		# Ties the funnel's own rotation speed to the same "Spin Speed (px/s)" slider that drives the particle
		# ring's tangential_accel — one control, both layers agree on how fast the vortex is spinning.
		# px/s at the ring's radius -> rad/s.
		var spd: float = float(_speed.get(kind, 70.0))
		fmat.set_shader_parameter("spin_speed", spd / _whirl_mouth_radius)

func _make_ramp(base: Color, opacity: float, kind: String) -> Gradient:
	var ramp := Gradient.new()
	if kind == "whirlpool":
		# Foam-white at the mouth -> the picked whirlpool color -> a deep abyssal blue -> gone, drawn down
		# into the core. No "cooling" plateau the way fire has; it just gets swallowed.
		var hot := Color(0.9, 0.98, 1.0)
		var near_col := Color(lerp(hot.r, base.r, 0.4), lerp(hot.g, base.g, 0.4), lerp(hot.b, base.b, 0.4), 1.0 * opacity)
		var mid_col := Color(base.r * 0.7, base.g * 0.8, base.b, 0.75 * opacity)
		var far_col := Color(base.r * 0.3, base.g * 0.35, base.b * 0.5, 0.0)
		ramp.colors = PackedColorArray([near_col, mid_col, far_col])
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	else:
		# Bubble: bright rim near the vent mouth -> the picked pale tone -> fades to nothing near the surface.
		var near_col := Color(base.r, base.g, base.b, 0.9 * opacity)
		var mid_col := Color(min(base.r * 1.15, 1.0), min(base.g * 1.15, 1.0), min(base.b * 1.15, 1.0), 0.6 * opacity)
		var far_col := Color(1.0, 1.0, 1.0, 0.0)
		ramp.colors = PackedColorArray([near_col, mid_col, far_col])
		ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	return ramp

## Sets `entry`'s body (+ spark) gravity to the current current vector for `kind` — see reroll_current().
func _gravity_entry(entry: Dictionary, kind: String) -> void:
	var g := _current_gravity(kind)
	var body: CPUParticles2D = entry["body"]
	if is_instance_valid(body):
		body.gravity = g
	var spark: CPUParticles2D = entry.get("spark")
	if is_instance_valid(spark):
		spark.gravity = g + (Vector2(0.0, 40.0) if kind == "whirlpool" else Vector2.ZERO)

## Frees `entry`'s body + spark (if any). Safe to call on an already-freed entry.
func _free_entry(entry: Dictionary) -> void:
	var body: CPUParticles2D = entry.get("body")
	if is_instance_valid(body):
		body.queue_free()
	var spark: CPUParticles2D = entry.get("spark")
	if is_instance_valid(spark):
		spark.queue_free()
	var funnel: MeshInstance3D = entry.get("funnel")
	if is_instance_valid(funnel):
		funnel.queue_free()

## Bubbles wobble/grow slightly as they rise and expand toward the surface (lower pressure).
func _make_bubble_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.55))
	c.add_point(Vector2(1.0, 1.0))
	return c

## Whirlpool particles start full-size at the ring's mouth and shrink to nothing as they're pulled into the
## core — the inverse of a bubble's steady growth.
func _make_whirl_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.7, 0.55))
	c.add_point(Vector2(1.0, 0.05))
	return c

## Spray droplets shrink as they arc up and fall back — simpler than the body's curve.
func _make_spray_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.1))
	return c

## The combined accel every particle of `kind` moves under: that kind's own buoyancy/pull (KIND_RISE_ACCEL)
## straight up, plus the current shared "current" vector (see this file's header).
func _current_gravity(kind: String) -> Vector2:
	var rad := deg_to_rad(_current_dir_deg)
	var accel: float = float(KIND_RISE_ACCEL.get(kind, 10.0))
	return Vector2(0.0, -accel) + Vector2(cos(rad), sin(rad)) * _current_strength

## Rolls a brand-new random current direction (0..360°) and strength (0.._current_strength_max), then
## re-applies the resulting gravity to every plume of EVERY kind already on screen (new plumes pick it up
## automatically). Public: called by the Plume Edit panel's REROLL CURRENT button, by
## apply_wind_strength_max() when the ceiling changes, and by this node's own _ready().
func reroll_current() -> void:
	_roll_current()
	for kind: String in KINDS:
		for key: Vector2 in _placed[kind].keys():
			_gravity_entry(_placed[kind][key], kind)
		for key: String in _marked_placed[kind].keys():
			_gravity_entry(_marked_placed[kind][key], kind)
	for entry: Dictionary in _ambient_bubbles:
		_gravity_entry(entry, "bubble")
	for lid in _landmark_placed.keys():
		var pools: Dictionary = _landmark_placed[lid]
		for kind: String in KINDS:
			for entry: Dictionary in pools.get(kind, []):
				_gravity_entry(entry, kind)

func _roll_current() -> void:
	_current_dir_deg = randf() * 360.0
	# Current must never roll near-zero, or bubbles just rise dead straight with no visible drift. Clamped
	# against the ceiling in case the Plume Edit "Current Strength" slider is set below CURRENT_STRENGTH_MIN.
	var floor_val: float = minf(CURRENT_STRENGTH_MIN, _current_strength_max)
	_current_strength = randf_range(floor_val, _current_strength_max)

## Forces every currently-placed AMBIENT/MARKED plume of `kind` to be freed and immediately re-evaluated, AND
## rebuilds every LANDMARK-attached plume of `kind` in place (same position, fresh settings) — added 2026-08-08
## alongside apply_kind_settings' own Speed/Height needs_regen check, so a landmark whirlpool/bubble picks up a
## live Speed/Height change too instead of only ambient/marked ones.
## For bubble: clears the rate-spawner's own transient pool instead of the (unused, for bubble) grid dict.
func _force_regenerate(kind: String) -> void:
	if kind == "bubble":
		for entry: Dictionary in _ambient_bubbles:
			_free_entry(entry)
		_ambient_bubbles.clear()
		_bubble_spawn_accum = 0.0
	else:
		for key: Vector2 in _placed[kind].keys():
			_free_entry(_placed[kind][key])
		_placed[kind].clear()
	for key: String in _marked_placed[kind].keys():
		_free_entry(_marked_placed[kind][key])
	_marked_placed[kind].clear()
	for lid in _landmark_placed.keys():
		var pools: Dictionary = _landmark_placed[lid]
		var rebuilt: Array = []
		for entry: Dictionary in (pools.get(kind, []) as Array):
			var pos: Vector2 = entry.get("pos", Vector2.ZERO)
			_free_entry(entry)
			rebuilt.append(_make_plume(pos, kind))
		pools[kind] = rebuilt
	if _has_last_center:
		_regenerate()

## Public: called by the Plume Edit panel (live, on that kind's tab, on slider/ColorPickerButton change) and
## by this node's own _ready() (persisted settings). `colors` is that kind's 6-slot palette. `speed`/`height` are
## kind-specific (rise speed / spin speed, lifetime). `mark_reveal_percent` (0..100) is the fraction of this
## kind's marked replicas that actually show a plume.
##
## `density` means something DIFFERENT per kind (2026-08-08 — see this file's header):
##   - whirlpool: the OLD 0..1 AMBIENT VENT CHANCE (0..VENT_CHANCE_MAX per candidate grid cell), unchanged.
##   - bubble: a literal 0..BUBBLE_RATE_SLIDER_MAX "Bubble Rate" slider value -> bubbles/sec = density ÷
##     BUBBLE_RATE_DIVISOR (100 -> 10/sec) — the old per-cell-chance model couldn't promise "0 = truly 0" in a
##     way users could feel, or calibrate to a real bubbles/sec number.
func apply_kind_settings(kind: String, opacity_mult: float, brightness_mult: float, colors: Array, density: float, speed: float, height: float, mark_reveal_percent: float) -> void:
	if not _placed.has(kind):
		return
	_opacity[kind] = opacity_mult
	_brightness[kind] = brightness_mult
	_colors[kind] = colors.duplicate()
	var new_reveal: float = clampf(mark_reveal_percent, 0.0, 100.0) / 100.0
	var needs_regen := not is_equal_approx(new_reveal, float(_mark_reveal.get(kind, -1.0)))
	# 2026-08-08 fix: Speed/Height are baked into a CPUParticles2D at CREATION (initial_velocity/lifetime) and
	# never re-applied to an already-running one — dragging either slider used to visibly do NOTHING to whatever
	# vents were already on screen (bug report: "Life time kéo có lúc không có tác dụng"), only affecting vents
	# spawned AFTER the change. Now an actual change force-regenerates every existing vent of this kind too, same
	# as a density/mark_reveal change already did.
	needs_regen = needs_regen or not is_equal_approx(speed, float(_speed.get(kind, -1.0)))
	needs_regen = needs_regen or not is_equal_approx(height, float(_height.get(kind, -1.0)))
	if kind == "bubble":
		var new_rate: float = clampf(density, 0.0, BUBBLE_RATE_SLIDER_MAX) / BUBBLE_RATE_DIVISOR
		needs_regen = needs_regen or not is_equal_approx(new_rate, _bubble_rate)
		_bubble_rate = new_rate
	else:
		var new_chance: float = clampf(density, 0.0, 1.0) * VENT_CHANCE_MAX
		needs_regen = needs_regen or not is_equal_approx(new_chance, float(_vent_chance.get(kind, -1.0)))
		_vent_chance[kind] = new_chance
	_mark_reveal[kind] = new_reveal
	_speed[kind] = speed
	_height[kind] = height
	for key: Vector2 in _placed[kind].keys():
		_style_entry(_placed[kind][key], kind)
	for key: String in _marked_placed[kind].keys():
		_style_entry(_marked_placed[kind][key], kind)
	if kind == "bubble":
		for entry: Dictionary in _ambient_bubbles:
			_style_entry(entry, kind)
	for lid in _landmark_placed.keys():
		for entry: Dictionary in (_landmark_placed[lid] as Dictionary).get(kind, []):
			_style_entry(entry, kind)
	if needs_regen:
		_force_regenerate(kind)

## Public: called by the Plume Edit panel (live, whirlpool tab's Size Min/Max sliders) and by this node's own
## _ready() (persisted settings). Each whirlpool independently rolls ITS OWN size multiplier once at creation
## (see _make_plume) and keeps it for its whole life — this only changes the range future/regenerated ones roll
## from. Force-regenerates existing ambient/marked whirlpools on an actual range change so the new range is
## visible immediately rather than waiting for them to naturally cycle out (landmark whirlpools are untouched —
## same convention as apply_kind_settings' own needs_regen).
func apply_whirlpool_size(min_v: float, max_v: float) -> void:
	var changed := not is_equal_approx(min_v, _whirl_size_min) or not is_equal_approx(max_v, _whirl_size_max)
	_whirl_size_min = min_v
	_whirl_size_max = max_v
	if changed:
		_force_regenerate("whirlpool")

## Public: called by the Plume Edit panel (live, whirlpool tab's Mouth/Throat Radius + Height + Funnel Curve
## sliders) and by this node's own _ready() (persisted settings) — on request 2026-08-08/09: "tôi muốn chỉnh
## được độ rộng của 2 đáy và chiều cao tổng của whirlpool" + "miệng của nó loe ra rộng hơn, thuôn dần về throat".
## All four are BASE values — each whirlpool's own size_mult (see apply_whirlpool_size) still scales the three
## dimensions per-instance (profile_exp is a pure SHAPE ratio, not a distance, so size_mult doesn't apply to it).
## Force-regenerates on an actual change (same convention as apply_whirlpool_size) so it's visible immediately.
func apply_whirlpool_dimensions(mouth_radius: float, throat_radius: float, height: float, profile_exp: float) -> void:
	var changed := not is_equal_approx(mouth_radius, _whirl_mouth_radius) \
		or not is_equal_approx(throat_radius, _whirl_throat_radius) \
		or not is_equal_approx(height, _whirl_height) \
		or not is_equal_approx(profile_exp, _whirl_profile_exp)
	_whirl_mouth_radius = mouth_radius
	_whirl_throat_radius = throat_radius
	_whirl_height = height
	_whirl_profile_exp = profile_exp
	if changed:
		_force_regenerate("whirlpool")

## Public: called by the Plume Edit panel (live, whirlpool tab's Tilt X/Y/Z sliders) and by this node's own
## _ready() (persisted settings) — on request 2026-08-08: "tôi muốn có cách chỉnh hướng xoay của whirlpool".
## ONE SHARED orientation for every whirlpool funnel (not independently randomized per instance, unlike size —
## this reads as "the artist dialed in an angle", not "each whirlpool looks different"). Rotates the mesh
## around its own center (mid-depth of the cone), so an extreme tilt can visibly lift the throat out of the
## water or sink the mouth below it — an intentional trade-off for the creative control being asked for.
## Applied instantly to every EXISTING funnel (ambient/marked/landmark) — no regenerate needed, this is a pure
## Node3D transform, not baked into any particle system.
func apply_whirlpool_tilt(rot_x_deg: float, rot_y_deg: float, rot_z_deg: float) -> void:
	_whirl_tilt_deg = Vector3(rot_x_deg, rot_y_deg, rot_z_deg)
	for key: Vector2 in _placed["whirlpool"].keys():
		_apply_tilt(_placed["whirlpool"][key])
	for key: String in _marked_placed["whirlpool"].keys():
		_apply_tilt(_marked_placed["whirlpool"][key])
	for lid in _landmark_placed.keys():
		for entry: Dictionary in (_landmark_placed[lid] as Dictionary).get("whirlpool", []):
			_apply_tilt(entry)

func _apply_tilt(entry: Dictionary) -> void:
	var funnel: MeshInstance3D = entry.get("funnel")
	if is_instance_valid(funnel):
		funnel.rotation_degrees = _whirl_tilt_deg

## Public: called by the Plume Edit panel (live, on the "Current Strength" slider — shared across both tabs)
## and by this node's own _ready() (persisted settings).
func apply_wind_strength_max(max_val: float) -> void:
	if is_equal_approx(max_val, _current_strength_max):
		return
	_current_strength_max = max_val
	reroll_current()

## Public: called by the Terrain Edit panel (live, on "Ground Tile Size" slider change) and by this node's
## own _ready() (persisted settings) — marked replication period is derived from canopy_size, so a size
## change must force a full re-placement of BOTH kinds' marked pools.
func apply_canopy_size(size_px: float) -> void:
	if is_equal_approx(size_px, _canopy_size):
		return
	_canopy_size = size_px
	for kind: String in KINDS:
		_force_regenerate(kind)

## Public: called by the Terrain Edit panel (live, on "Current Width" slider change) and by this node's own
## _ready() (persisted settings). Ambient/marked vents inside the current band are skipped; a width change
## can newly include or exclude cells/replicas, so both kinds' ambient+marked pools are force-regenerated.
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

## Public: called by atlantic_temple_layer.gd once per spawned landmark instance. `entries` = Array of
## {"kind": "bubble"/"whirlpool", "pos": Vector2} — already-transformed WORLD positions. Landmark plumes are
## PERMANENT for that instance's lifetime — no view-culling, replaces any previous set for the same
## `landmark_id`.
func set_landmark_plumes(landmark_id, entries: Array) -> void:
	clear_landmark_plumes(landmark_id)
	var pools := {"bubble": [], "whirlpool": []}
	for e: Dictionary in entries:
		var kind: String = String(e.get("kind", "bubble"))
		if not pools.has(kind):
			continue
		var pos: Vector2 = e["pos"]
		var entry := _make_plume(pos, kind)
		entry["pos"] = pos   # kept so _force_regenerate() can rebuild this landmark plume in place on a live Speed/Height change
		(pools[kind] as Array).append(entry)
	_landmark_placed[landmark_id] = pools

## Public: frees every plume attached to `landmark_id`.
func clear_landmark_plumes(landmark_id) -> void:
	if not _landmark_placed.has(landmark_id):
		return
	var pools: Dictionary = _landmark_placed[landmark_id]
	for kind: String in pools.keys():
		for entry: Dictionary in (pools[kind] as Array):
			_free_entry(entry)
	_landmark_placed.erase(landmark_id)

## Soft round puff — whirlpool's spray droplets only (bubble's body uses the fresnel _make_bubble_tex below).
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

## A small glassy sphere instead of a flat soft blob: near-transparent interior, a bright thin FRESNEL rim near
## the silhouette edge (real bubbles are brightest at a grazing angle, i.e. right at their edge, not in the
## middle), and one small offset specular glint (a light-source highlight dot) — the two cues that actually read
## as "bubble" rather than "glowing puff". Baked once as a plain white-RGB/varying-alpha image (same convention
## as _make_puff_tex/atlantic_sparks.gd's _make_spark_tex) so color_ramp tinting still works unmodified.
func _make_bubble_tex() -> ImageTexture:
	var size := int(BUBBLE_TEX_PX)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var highlight_center := center + Vector2(-size * 0.16, -size * 0.18)
	var highlight_radius := size * 0.16
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(center) / (size * 0.5)   # 0 = center, 1 = silhouette edge
			if d > 1.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var rim: float = smoothstep(0.55, 0.85, d) * (1.0 - smoothstep(0.93, 1.0, d))
			var interior: float = (1.0 - smoothstep(0.0, 0.55, d)) * 0.12   # faint glassy fill, mostly see-through
			var hd: float = p.distance_to(highlight_center) / highlight_radius
			var highlight: float = pow(clampf(1.0 - hd, 0.0, 1.0), 2.0)
			var alpha: float = clampf(rim * 0.85 + interior + highlight * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)
