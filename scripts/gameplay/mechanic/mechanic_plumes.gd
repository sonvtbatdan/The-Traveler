extends Node2D
class_name MechanicPlumes
## ENERGY BEAM vents for the Mechanic map. Originally a Volcanic-style rising steam-puff particle system
## (2026-08-19 first pass); REDESIGNED same day on request ("thay đổi cách hiển thị, thay vì là plume...
## tại các điểm mark sẽ bắn thẳng cột năng lượng sáng xanh blue lên trời") into straight vertical pulses of
## light that shoot up from each vent and fade — no more billowing/drifting puffs, no more wind (a "cột
## thẳng" straight column has nothing to drift sideways with, so the whole wind system was removed along with
## it — see the git history / earlier revision of this file for the old CPUParticles2D + wind implementation).
##
## Still keeps the same TWO spawn tiers as the first pass (only the per-vent VISUAL changed, not WHERE vents
## exist):
##  1. AMBIENT GRID vents — a coarse world-space hash grid (MechanicNoise.hash21). `_placed`.
##  2. MARKED VENT positions — user-placed via mechanic_vent_mark.gd (clicking the maptile photo). A mark is a
##     normalized (u, v) on ONE specific ground photo (0=a..6=g), replicated at EVERY world-space repetition of
##     that photo (mirrors mechanic_ground.gdshader's uv_a..uv_g tiling, MechanicNoise.GROUND_UV_MULT/OFFSET),
##     spawning only where MechanicNoise.ground_region() agrees that photo is the one showing there.
##     `_marked_placed`.
## EVERY eligible candidate/replica is ALWAYS placed (subject only to the river-avoidance/region-match rules
## below) — "Vent Density" (0..100, apply_beam_settings' `density` param) does NOT decide which vents exist
## any more (2026-08-19, 2nd fix same day: the original density gated PLACEMENT via a position-hashed roll,
## so it was always the exact same fixed subset of vents lit — "hiện tại đang bắn ở vent nào thì chỉ bắn ở
## vent đó, các vent khác không được random chọn"). Instead density gates each vent's wait -> rise ROLL every
## cycle (see _advance_entry): every vent keeps re-attempting to fire, so which ones are actually lit rotates
## over time, and at any instant roughly `density%` of the whole pool is lit — not a frozen subset.
##  No "landmark-attached" tier — Mechanic has no landmark .glb yet (see MechanicAssetScan/MechanicTrees); can
##  be ported from volcanic_clouds.gd if Mechanic later gets landmarks worth marking.
##
## PER-VENT VISUAL: a single Sprite2D (additive-blended, "_make_beam_tex()"'s soft-edged/top-fading gradient)
## anchored bottom-at-vent, non-centered, that a tiny _process()-driven state machine animates through
## wait -> rise -> hold -> fade -> wait, forever, independently phased per vent (random initial offset) so a
## field of vents doesn't pulse in lockstep:
##   wait : invisible. Counts down a random gap, then ROLLS against Vent Density (`_density_frac`) — success
##          moves to `rise`; failure re-arms another gap and rolls again next time. The gap is NOT a small
##          fixed constant — see _roll_gap()'s doc comment for why that was a bug: a short fixed gap made the
##          on-screen count balloon past what Density implied at low settings, because each successful fire
##          then stays lit for several seconds (rise+hold+fade) regardless of how rarely it wins a roll — with
##          hundreds of vents all retrying fast, "few are winning" and "many are visibly lit at once" turned
##          out not to be the same thing. The gap is scaled to the CURRENT rise+hold+fade duration precisely so
##          that, on average, exactly `density%` of the whole pool is lit at any instant, at any density.
##   rise : scale.y (height) grows 0 -> full (BEAM_MAX_HEIGHT world-px) linearly over BEAM_MAX_HEIGHT/beam_speed
##          seconds — this is what "Tốc độ bắn" (beam_speed, px/s) controls: how fast the column shoots
##          skyward. scale.x (width) and alpha (opacity) ride the SAME progress but smoothstep-eased, both
##          going 0 -> full together — the column starts as a thin, dim sliver and thickens/brightens as it
##          extends, instead of snapping in as an already-full-width, already-opaque growing rectangle.
##   hold : full height/width/opacity, for beam_duration seconds ("Duration luồng bắn").
##   fade : quick fixed-time alpha fadeout (width/height stay full), then back to wait.
## "Beam Strength" (beam_strength) controls both the column's full thickness and its brightness (color
## multiplier, alpha unclamped past 1.0 — ADD blend mode reads that as extra glow, not a hard clip). Each vent
## still rolls one random color from the 6-slot palette.
##
## Each vent is ONE ENTRY = {"root": Node2D, "sprite": Sprite2D, "color": Color, "phase": String, "t": float,
## "base_width": float, "base_color": Color} (+ "pos" for marked entries, used by _regen_marked's culling).
## `base_width`/`base_color` are the CURRENT strength/color-derived targets (refreshed by _style_entry on every
## settings change); _advance_entry blends them against the phase progress every frame, so a live slider drag
## is reflected immediately even on a vent that's mid-hold or mid-fade. This node stays at the world origin;
## every vent's root is a plain child at its own fixed world position (local_coords via plain Node2D.position)
## since it represents a terrain feature, not sky-anchored weather — update_view() only decides which vents
## currently EXIST within view+margin (placement, not firing — see above).

const MechanicNoise := preload("res://scripts/gameplay/mechanic/mechanic_noise.gd")
const MechanicTerrainSettings := preload("res://scripts/gameplay/mechanic/mechanic_terrain_settings.gd")

const CELL_SIZE := 900.0        # world-px grid spacing between ambient vent candidates — EVERY candidate cell
                                 # gets a vent placed (see this file's header); density gates FIRING, not placement
const MARGIN := 300.0           # extra world-px beyond the viewport a vent may exist in before it's culled
const REGEN_MOVE_THRESHOLD := 220.0

const BEAM_MAX_HEIGHT := 2200.0    # world-px a fully-risen column reaches — tall enough to clear the base
                                    # 1440x780 viewport (+ MARGIN) from any vent position on-screen
const BEAM_TEX_W := 32.0           # _make_beam_tex's native size (world-px at scale 1,1)
const BEAM_TEX_H := 256.0
const BEAM_BASE_SCALE_Y := BEAM_MAX_HEIGHT / BEAM_TEX_H   # sprite.scale.y at full "risen" height
const BEAM_FADE_TIME := 0.25       # fixed fadeout length after `hold` ends — not slider-controlled
const GAP_FLOOR := 0.05            # never roll a shorter wait than this, however tiny the math below yields

var _placed: Dictionary = {}          # cell Vector2 -> entry
var _marked_placed: Dictionary = {}   # "mi_i_j" String -> entry (+ "pos")
var _vent_marks: Array = []
var _canopy_size: float = MechanicTerrainSettings.DEFAULT_CANOPY_SIZE
var _mottle_uv_scale: float = 1.0 / MechanicTerrainSettings.DEFAULT_CANOPY_MOTTLE_SCALE
var _river_width: float = 0.0
var _river_count: int = int(MechanicTerrainSettings.DEFAULT_RIVER_COUNT)
var _beam_tex: Texture2D

var _colors: Array = []
var _density_frac: float = 0.5   # 0..1 — per-cycle chance a "wait"-ing vent actually fires next, see header
var _strength: float = 1.0      # thickness + brightness multiplier ("Beam Strength")
var _speed: float = 1500.0      # px/s the column shoots upward ("Tốc độ bắn")
var _duration: float = 1.5      # seconds fully visible before fading ("Duration luồng bắn")

var _last_center: Vector2 = Vector2.ZERO
var _last_regen_center: Vector2 = Vector2.ZERO
var _has_last_center: bool = false
var _view_size: Vector2 = Vector2(1440.0, 780.0)

func _ready() -> void:
	add_to_group("mechanic_plumes")   # so the Plume Edit panel can find this instance
	_beam_tex = _make_beam_tex()

	var s := MechanicTerrainSettings.load_settings()
	_river_width = float(s["river_width"])
	_river_count = int(s["river_count"])
	_canopy_size = float(s["canopy_size"])
	_mottle_uv_scale = 1.0 / maxf(float(s["canopy_mottle_scale"]), 1.0)
	_vent_marks = (s["beam_marks"] as Array).duplicate(true)
	apply_beam_settings(s["beam_strength"],
		[s["beam_color_0"], s["beam_color_1"], s["beam_color_2"], s["beam_color_3"], s["beam_color_4"], s["beam_color_5"]],
		s["beam_density"], s["beam_speed"], s["beam_duration"])

func _process(delta: float) -> void:
	for key: Vector2 in _placed.keys():
		_advance_entry(_placed[key], delta)
	for key: String in _marked_placed.keys():
		_advance_entry(_marked_placed[key], delta)

## Public: called every frame with the camera's world-space focus and viewport size (mirrors MechanicTrees).
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
	_regen_grid(min_p, max_p)
	_regen_marked(min_p, max_p)

func _regen_grid(min_p: Vector2, max_p: Vector2) -> void:
	for key: Vector2 in _placed.keys().duplicate():
		if key.x < min_p.x or key.x > max_p.x or key.y < min_p.y or key.y > max_p.y:
			_free_entry(_placed[key])
			_placed.erase(key)

	var start_x: float = floor(min_p.x / CELL_SIZE) * CELL_SIZE
	var start_y: float = floor(min_p.y / CELL_SIZE) * CELL_SIZE
	var x := start_x
	while x < max_p.x:
		var y := start_y
		while y < max_p.y:
			_maybe_place(Vector2(x, y))
			y += CELL_SIZE
		x += CELL_SIZE

func _maybe_place(cell: Vector2) -> void:
	if _placed.has(cell):
		return
	var jitter := Vector2(
		(MechanicNoise.hash21(cell + Vector2(71.0, 5.0)) - 0.5) * CELL_SIZE * 0.6,
		(MechanicNoise.hash21(cell + Vector2(5.0, 71.0)) - 0.5) * CELL_SIZE * 0.6
	)
	var pos: Vector2 = cell + jitter
	if _river_width > 0.0 and MechanicNoise.is_river(pos, _river_width, _mottle_uv_scale, _river_count):
		return   # no vents on the river band
	_placed[cell] = _make_plume(pos)

## Replicates every entry in _vent_marks at EVERY world-space repetition of its source photo within
## [min_p, max_p] — see this file's header. `base_pos + Vector2(i, j) * period` inverts
## mechanic_ground.gdshader's `world_pos * scale + offset` UV formula (scale/offset per mark["tex"], from
## MechanicNoise.GROUND_UV_MULT/OFFSET). Every valid replica (region-match + not-in-river) is placed — Density
## no longer prunes placement, see this file's header.
func _regen_marked(min_p: Vector2, max_p: Vector2) -> void:
	for key: String in _marked_placed.keys().duplicate():
		var entry: Dictionary = _marked_placed[key]
		var pos: Vector2 = entry["pos"]
		if pos.x < min_p.x or pos.x > max_p.x or pos.y < min_p.y or pos.y > max_p.y:
			_free_entry(entry)
			_marked_placed.erase(key)

	var ground_uv_scale: float = 1.0 / maxf(_canopy_size, 1.0)
	for mi in _vent_marks.size():
		var mark: Dictionary = _vent_marks[mi]
		var tex_idx: int = clampi(int(mark.get("tex", 0)), 0, MechanicNoise.GROUND_UV_MULT.size() - 1)
		var uv := Vector2(float(mark.get("u", 0.5)), float(mark.get("v", 0.5)))
		var mult: float = MechanicNoise.GROUND_UV_MULT[tex_idx]
		var offset: Vector2 = MechanicNoise.GROUND_UV_OFFSET[tex_idx]
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
				if _marked_placed.has(key):
					continue
				var pos: Vector2 = base_pos + Vector2(float(i), float(j)) * period
				if pos.x < min_p.x or pos.x > max_p.x or pos.y < min_p.y or pos.y > max_p.y:
					continue
				if MechanicNoise.ground_region(pos, _mottle_uv_scale) != tex_idx:
					continue   # a DIFFERENT photo actually shows at this particular repetition — no vent here
				if _river_width > 0.0 and MechanicNoise.is_river(pos, _river_width, _mottle_uv_scale, _river_count):
					continue   # this replica happens to land inside the river band
				var entry: Dictionary = _make_plume(pos)
				entry["pos"] = pos
				_marked_placed[key] = entry

func _make_plume(pos: Vector2) -> Dictionary:
	var color: Color = _colors[randi() % _colors.size()] if not _colors.is_empty() else Color(0.35, 0.65, 1.0)
	var root := Node2D.new()
	root.position = pos
	root.z_index = -1   # stays under the ship/enemies (z_index 1+) but above the ground CanvasLayer
	var sprite := Sprite2D.new()
	sprite.texture = _beam_tex
	sprite.centered = false
	sprite.offset = Vector2(-BEAM_TEX_W * 0.5, -BEAM_TEX_H)   # pivot at the vent (texture bottom = local origin)
	sprite.scale = Vector2.ZERO   # starts as nothing — width/height/opacity all ramp up together, see header
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # overlapping/bright columns glow instead of clipping
	sprite.material = mat
	root.add_child(sprite)
	add_child(root)
	# Random initial wait (spread across one full average cycle) so a field of vents doesn't all roll their
	# first fire-attempt in lockstep.
	var entry := {"root": root, "sprite": sprite, "color": color, "phase": "wait", "t": randf() * _avg_on_time(),
		"base_width": 1.0, "base_color": Color.WHITE}
	_style_entry(entry)
	return entry

## Average seconds a fired beam actually stays visible (rise + hold + fade) at the CURRENT speed/duration —
## see _roll_gap() for why this matters.
func _avg_on_time() -> float:
	return BEAM_MAX_HEIGHT / maxf(_speed, 1.0) + _duration + BEAM_FADE_TIME

## The wait BETWEEN one roll-attempt and the next. Derived so the long-run fraction of TIME any one vent
## spends lit exactly matches `_density_frac`, however long a fire actually stays visible:
## duty_cycle = on_time / (on_time + wait), and each vent needs ~1/_density_frac attempts (each costing one
## gap) before a roll succeeds, so solving duty_cycle = _density_frac for the average gap gives
## `gap = on_time * (1 - _density_frac)` — shorter gaps at high density (it should barely wait between
## bursts), gaps approaching on_time at low density (so a rare successful burst doesn't get "topped up" by
## a flood of other vents each retrying many times over that same burst's lifetime). ±40% jitter keeps a
## field of vents from pulsing in a visible rhythm.
func _roll_gap() -> float:
	var base: float = _avg_on_time() * (1.0 - _density_frac)
	return maxf(randf_range(base * 0.6, base * 1.4), GAP_FLOOR)

## Advances one vent's wait -> rise -> hold -> fade -> wait state machine by `delta` — see this file's header.
## Reads entry["base_width"]/["base_color"] (kept current by _style_entry) every frame, so a live slider drag
## is reflected instantly even mid-hold/mid-fade without needing to touch the state machine itself.
func _advance_entry(entry: Dictionary, delta: float) -> void:
	var sprite: Sprite2D = entry["sprite"]
	if not is_instance_valid(sprite):
		return
	var base_w: float = entry["base_width"]
	var base_c: Color = entry["base_color"]
	match String(entry["phase"]):
		"wait":
			entry["t"] = float(entry["t"]) - delta
			if float(entry["t"]) <= 0.0:
				if randf() < _density_frac:
					entry["phase"] = "rise"
					entry["t"] = 0.0
				else:
					entry["t"] = _roll_gap()   # missed this roll — try again after a density-scaled wait
			sprite.scale = Vector2.ZERO
		"rise":
			entry["t"] = float(entry["t"]) + delta
			var rise_time: float = BEAM_MAX_HEIGHT / maxf(_speed, 1.0)
			var frac: float = clampf(float(entry["t"]) / rise_time, 0.0, 1.0)
			var eased: float = frac * frac * (3.0 - 2.0 * frac)   # smoothstep — width/opacity ease in together
			sprite.scale = Vector2(base_w * eased, BEAM_BASE_SCALE_Y * frac)
			sprite.modulate = Color(base_c.r, base_c.g, base_c.b, eased)
			if frac >= 1.0:
				entry["phase"] = "hold"
				entry["t"] = 0.0
		"hold":
			entry["t"] = float(entry["t"]) + delta
			sprite.scale = Vector2(base_w, BEAM_BASE_SCALE_Y)
			sprite.modulate = Color(base_c.r, base_c.g, base_c.b, 1.0)
			if float(entry["t"]) >= _duration:
				entry["phase"] = "fade"
				entry["t"] = 0.0
		"fade":
			entry["t"] = float(entry["t"]) + delta
			var f: float = clampf(float(entry["t"]) / BEAM_FADE_TIME, 0.0, 1.0)
			sprite.scale = Vector2(base_w, BEAM_BASE_SCALE_Y)
			sprite.modulate = Color(base_c.r, base_c.g, base_c.b, 1.0 - f)
			if f >= 1.0:
				entry["phase"] = "wait"
				entry["t"] = _roll_gap()
				sprite.scale = Vector2.ZERO

## Refreshes the CURRENT strength/color TARGETS an already-placed vent blends toward, WITHOUT touching its
## wait/rise/hold/fade timing — called on every slider change and once when a vent is first created. The
## actual sprite write happens every frame in _advance_entry (see its doc comment for why).
func _style_entry(entry: Dictionary) -> void:
	var color: Color = entry["color"]
	entry["base_width"] = clampf(_strength, 0.05, 4.0)
	var glow: float = 0.6 + 0.5 * _strength   # brighter as strength rises; ADD blend reads >1.0 as extra glow
	entry["base_color"] = Color(minf(color.r * glow, 3.0), minf(color.g * glow, 3.0), minf(color.b * glow, 3.0))

func _free_entry(entry: Dictionary) -> void:
	var root: Node2D = entry.get("root")
	if is_instance_valid(root):
		root.queue_free()

## Public: called by the Plume Edit panel (live, on slider/ColorPickerButton change) and by this node's own
## _ready() (persisted settings). `colors` is the 6-slot palette — each vent rolls its own random pick from
## it. `density` is 0..100 — 0 = nothing ever fires, 100 = every eligible vent fires essentially continuously:
## it's the per-cycle wait->rise roll chance every ALREADY-PLACED vent uses (see this file's header) — a live
## change here takes effect on each vent's NEXT roll, no placement regen needed. `speed` is px/s the column
## shoots upward; `duration` is seconds it stays fully visible before fading.
func apply_beam_settings(strength: float, colors: Array, density: float, speed: float, duration: float) -> void:
	_strength = strength
	_colors = colors.duplicate()
	_density_frac = clampf(density, 0.0, 100.0) / 100.0
	_speed = maxf(speed, 1.0)
	_duration = maxf(duration, 0.05)
	for key: Vector2 in _placed.keys():
		_style_entry(_placed[key])
	for key: String in _marked_placed.keys():
		_style_entry(_marked_placed[key])

## Forces every currently-placed AMBIENT/MARKED vent to be freed and immediately re-evaluated — used whenever
## a setting that changes WHICH cells/repetitions qualify (density, canopy_size, mottle scale, river width,
## marks) is live-edited, so the panel's sliders feel responsive instead of waiting for REGEN_MOVE_THRESHOLD
## of camera movement.
func _force_regenerate() -> void:
	for key: Vector2 in _placed.keys():
		_free_entry(_placed[key])
	_placed.clear()
	for key: String in _marked_placed.keys():
		_free_entry(_marked_placed[key])
	_marked_placed.clear()
	if _has_last_center:
		_regenerate()

## Public: called by the Terrain Edit panel (live, on "River Width" slider change) and by this node's own
## _ready() (persisted settings). Keeps vents off the river band.
func apply_river_width(width: float) -> void:
	if is_equal_approx(width, _river_width):
		return
	_river_width = width
	_force_regenerate()

## Public: called by the Terrain Edit panel (live, on "River Count" slider change) and by this node's own
## _ready() (persisted settings) — MechanicNoise.is_river()'s seam-based check depends on how many seams
## currently carry a river.
func apply_river_count(count: int) -> void:
	if count == _river_count:
		return
	_river_count = count
	_force_regenerate()

## Public: called by the Terrain Edit panel (live, on "Canopy Size" slider change) and by this node's own
## _ready() (persisted settings) — marked-vent replication period is derived from canopy_size (see
## _regen_marked), so a size change must force a full re-placement of the marked pool.
func apply_canopy_size(size_px: float) -> void:
	if is_equal_approx(size_px, _canopy_size):
		return
	_canopy_size = size_px
	_force_regenerate()

## Public: called by the Terrain Edit panel (live, on "Canopy Blend Sparseness" slider change) and by this
## node's own _ready() (persisted settings) — MechanicNoise.ground_region()'s CPU-side approximation of the
## GPU region split depends on the CURRENT mottle scale (see mechanic_noise.gd's header, unlike Volcanic's
## fixed baked frequency), so a change must force a full re-placement of the marked pool (a replica's photo
## may now win/lose the region-split lottery differently at the same world position).
func apply_canopy_mottle_scale(size_px: float) -> void:
	var new_scale: float = 1.0 / maxf(size_px, 1.0)
	if is_equal_approx(new_scale, _mottle_uv_scale):
		return
	_mottle_uv_scale = new_scale
	_force_regenerate()

## Public: called by the Vent Mark panel (live, whenever a mark is added/removed) and by this node's own
## _ready() (persisted settings).
func apply_vent_marks(marks: Array) -> void:
	_vent_marks = marks.duplicate(true)
	_force_regenerate()

## Soft vertical energy column: bright, sharp-cored horizontal falloff (a glowing rod, not a blob) crossed
## with a vertical fade so the currently-growing TIP always trails off softly into the sky regardless of how
## tall the column has grown so far (scaling the whole sprite vertically keeps that gradient proportional).
func _make_beam_tex() -> ImageTexture:
	var w := int(BEAM_TEX_W)
	var h := int(BEAM_TEX_H)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v: float = float(y) / float(h - 1)   # 0 at top (tip), 1 at bottom (vent mouth)
		var vert_fade: float = clampf(v * 1.35, 0.0, 1.0)
		for x in w:
			var u: float = float(x) / float(w - 1) * 2.0 - 1.0   # -1..1
			var horiz: float = clampf(1.0 - absf(u), 0.0, 1.0)
			horiz = horiz * horiz   # sharper bright core, softer edge falloff
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, horiz * vert_fade))
	return ImageTexture.create_from_image(img)
