extends Node2D
class_name ArcticPlumes
## ENERGY BEAM vents for the Arctic map — port of mechanic_plumes.gd (see that file's header for the full
## rationale: straight vertical pulses of light shooting up and fading, two spawn tiers — ambient grid +
## user-marked positions — density gates the wait->rise ROLL each cycle, not placement itself).
##
## 2026-08-19, on request ("hệ thống blend dynamic..."): the marked-vent tier replicates a mark at every
## world-space repetition of its source photo (mirrors arctic_ground.gdshader's per-slot UV tiling) and checks
## ArcticNoise.ground_region() to confirm that photo is actually the one showing there — both now take the
## LIVE `canopy_count` (auto-detected, see arctic_ground.gd's header) instead of Mechanic's fixed 7.

const ArcticNoise := preload("res://scripts/gameplay/arctic/arctic_noise.gd")
const ArcticAssetScan := preload("res://scripts/gameplay/arctic/arctic_asset_scan.gd")
const ArcticTerrainSettings := preload("res://scripts/gameplay/arctic/arctic_terrain_settings.gd")

const CELL_SIZE := 900.0        # world-px grid spacing between ambient vent candidates — EVERY candidate cell
                                 # gets a vent placed; density gates FIRING, not placement
const MARGIN := 300.0           # extra world-px beyond the viewport a vent may exist in before it's culled
const REGEN_MOVE_THRESHOLD := 220.0

const BEAM_MAX_HEIGHT := 2200.0    # world-px a fully-risen column reaches
const BEAM_TEX_W := 32.0           # _make_beam_tex's native size (world-px at scale 1,1)
const BEAM_TEX_H := 256.0
const BEAM_BASE_SCALE_Y := BEAM_MAX_HEIGHT / BEAM_TEX_H   # sprite.scale.y at full "risen" height
const BEAM_FADE_TIME := 0.25       # fixed fadeout length after `hold` ends — not slider-controlled
const GAP_FLOOR := 0.05            # never roll a shorter wait than this, however tiny the math below yields

var _placed: Dictionary = {}          # cell Vector2 -> entry
var _marked_placed: Dictionary = {}   # "mi_i_j" String -> entry (+ "pos")
var _vent_marks: Array = []
var _canopy_size: float = ArcticTerrainSettings.DEFAULT_CANOPY_SIZE
var _mottle_uv_scale: float = 1.0 / ArcticTerrainSettings.DEFAULT_CANOPY_MOTTLE_SCALE
var _river_width: float = 0.0
var _river_count: int = int(ArcticTerrainSettings.DEFAULT_RIVER_COUNT)
var _canopy_count: int = 4   # refreshed via apply_maptile_set() — see arctic_ground.gd's header on auto-detection
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
	add_to_group("arctic_plumes")   # so the Plume Edit panel can find this instance
	_beam_tex = _make_beam_tex()

	var s := ArcticTerrainSettings.load_settings()
	_river_width = float(s["river_width"])
	_river_count = int(s["river_count"])
	_canopy_size = float(s["canopy_size"])
	_mottle_uv_scale = 1.0 / maxf(float(s["canopy_mottle_scale"]), 1.0)
	_canopy_count = ArcticAssetScan.canopy_count(String(s["maptile_set"]))
	_vent_marks = (s["beam_marks"] as Array).duplicate(true)
	apply_beam_settings(s["beam_strength"],
		[s["beam_color_0"], s["beam_color_1"], s["beam_color_2"], s["beam_color_3"], s["beam_color_4"], s["beam_color_5"]],
		s["beam_density"], s["beam_speed"], s["beam_duration"])

func _process(delta: float) -> void:
	for key: Vector2 in _placed.keys():
		_advance_entry(_placed[key], delta)
	for key: String in _marked_placed.keys():
		_advance_entry(_marked_placed[key], delta)

## Public: called every frame with the camera's world-space focus and viewport size (mirrors ArcticTrees).
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
		(ArcticNoise.hash21(cell + Vector2(71.0, 5.0)) - 0.5) * CELL_SIZE * 0.6,
		(ArcticNoise.hash21(cell + Vector2(5.0, 71.0)) - 0.5) * CELL_SIZE * 0.6
	)
	var pos: Vector2 = cell + jitter
	if _river_width > 0.0 and ArcticNoise.is_river(pos, _river_width, _mottle_uv_scale, _river_count, _canopy_count):
		return   # no vents on the river band
	_placed[cell] = _make_plume(pos)

## Replicates every entry in _vent_marks at EVERY world-space repetition of its source photo within
## [min_p, max_p] — see this file's header. Every valid replica (region-match + not-in-river) is placed.
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
		var tex_idx: int = clampi(int(mark.get("tex", 0)), 0, ArcticNoise.GROUND_UV_MULT.size() - 1)
		if tex_idx >= _canopy_count:
			continue   # mark's source photo isn't part of the CURRENT canopy set at all — nothing to replicate
		var uv := Vector2(float(mark.get("u", 0.5)), float(mark.get("v", 0.5)))
		var mult: float = ArcticNoise.GROUND_UV_MULT[tex_idx]
		var offset: Vector2 = ArcticNoise.GROUND_UV_OFFSET[tex_idx]
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
				if ArcticNoise.ground_region(pos, _mottle_uv_scale, _canopy_count) != tex_idx:
					continue   # a DIFFERENT photo actually shows at this particular repetition — no vent here
				if _river_width > 0.0 and ArcticNoise.is_river(pos, _river_width, _mottle_uv_scale, _river_count, _canopy_count):
					continue   # this replica happens to land inside the river band
				var entry: Dictionary = _make_plume(pos)
				entry["pos"] = pos
				_marked_placed[key] = entry

func _make_plume(pos: Vector2) -> Dictionary:
	var color: Color = _colors[randi() % _colors.size()] if not _colors.is_empty() else Color(0.7, 0.9, 1.0)
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

## The wait BETWEEN one roll-attempt and the next — see mechanic_plumes.gd's own doc comment for the full
## duty-cycle derivation (identical here).
func _roll_gap() -> float:
	var base: float = _avg_on_time() * (1.0 - _density_frac)
	return maxf(randf_range(base * 0.6, base * 1.4), GAP_FLOOR)

## Advances one vent's wait -> rise -> hold -> fade -> wait state machine by `delta` — see this file's header.
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

## Refreshes the CURRENT strength/color TARGETS an already-placed vent blends toward — see mechanic_plumes.
## gd's own doc comment (identical rationale here).
func _style_entry(entry: Dictionary) -> void:
	var color: Color = entry["color"]
	entry["base_width"] = clampf(_strength, 0.05, 4.0)
	var glow: float = 0.6 + 0.5 * _strength   # brighter as strength rises; ADD blend reads >1.0 as extra glow
	entry["base_color"] = Color(minf(color.r * glow, 3.0), minf(color.g * glow, 3.0), minf(color.b * glow, 3.0))

func _free_entry(entry: Dictionary) -> void:
	var root: Node2D = entry.get("root")
	if is_instance_valid(root):
		root.queue_free()

## Public: called by the Plume Edit panel (live) and by this node's own _ready() (persisted settings).
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

## Forces every currently-placed AMBIENT/MARKED vent to be freed and immediately re-evaluated.
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
## _ready() (persisted settings).
func apply_river_count(count: int) -> void:
	if count == _river_count:
		return
	_river_count = count
	_force_regenerate()

## Public: called by the Terrain Edit panel (live, on "Canopy Size" slider change) and by this node's own
## _ready() (persisted settings) — marked-vent replication period is derived from canopy_size.
func apply_canopy_size(size_px: float) -> void:
	if is_equal_approx(size_px, _canopy_size):
		return
	_canopy_size = size_px
	_force_regenerate()

## Public: called by the Terrain Edit panel (live, on "Canopy Blend Sparseness" slider change) and by this
## node's own _ready() (persisted settings) — ArcticNoise.ground_region()'s region split depends on it.
func apply_canopy_mottle_scale(size_px: float) -> void:
	var new_scale: float = 1.0 / maxf(size_px, 1.0)
	if is_equal_approx(new_scale, _mottle_uv_scale):
		return
	_mottle_uv_scale = new_scale
	_force_regenerate()

## Public: called by the Terrain Edit panel (live, on Tile Set dropdown change) and by this node's own
## _ready() (persisted settings) — refreshes _canopy_count (ArcticAssetScan.canopy_count()), since both the
## region-split check AND the marked-vent tex_idx validity depend on how many photos are currently active.
func apply_maptile_set(set_name: String) -> void:
	var new_count := ArcticAssetScan.canopy_count(set_name)
	if new_count == _canopy_count:
		return
	_canopy_count = new_count
	_force_regenerate()

## Public: called by the Vent Mark panel (live, whenever a mark is added/removed) and by this node's own
## _ready() (persisted settings).
func apply_vent_marks(marks: Array) -> void:
	_vent_marks = marks.duplicate(true)
	_force_regenerate()

## Soft vertical energy column — see mechanic_plumes.gd's own doc comment (identical rationale here).
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
