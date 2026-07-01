extends MultiMeshInstance2D
## Single-node manager that renders and updates EVERY arena XP orb via one MultiMesh draw call.
##
## Replaces the old per-orb Node2D model (arena_xp_orb.gd), where each orb ran _process + queue_redraw
## + a 4-draw_circle _draw() every frame with no cap — hundreds of those were the dominant share of the
## node count that tanked arena FPS. Here all orb state lives in parallel Packed arrays (no node per orb)
## and is drawn with one shared baked glow texture; idle orbs cost only a distance check per frame and are
## never re-transformed. Lives on the sharp gameplay plane (arena root), world space (node at origin →
## instance transforms ARE world positions). Found by callers via group "arena_xp_orb_mgr".

# ── Magnet / collect tunables (ported verbatim from arena_xp_orb.gd) ───────────
const COLLECT_RADIUS      := 16.0
const MAGNET_SPEED        := 120.0    # starting fly speed once magnetized naturally (px/s)
const MAGNET_ACCEL        := 900.0    # acceleration when magnetized naturally (px/s²)
const MAGNET_MAX          := 1400.0   # speed cap for natural magnetization
const FORCE_MAGNET_ACCEL  := 600.0    # acceleration when pulled by the magnetic loot item (0→1200 in 2s)
const FORCE_MAGNET_MAX    := 1200.0   # speed cap for forced magnetization

# ── Population control ────────────────────────────────────────────────────────
const MAX_ORBS      := 4000     # MultiMesh buffer size (visible_instance_count tracks the live subset)
const MERGE_RADIUS  := 24.0     # an orb spawning within this of an idle orb folds its value into it
const MERGE_SCAN_MAX := 48      # spawn() only scans the most-recent N orbs for a merge target (O(1)-ish instead of
                                # O(all orbs)) — a whole cluster dying drops orbs at the same spot consecutively, so
                                # the merge target is always among the latest few. Avoids the mass-death spawn spike.
const ORB_LIFETIME  := 30.0     # idle orbs auto-magnetize after this so XP is never lost / never piles up

# ── State machine ─────────────────────────────────────────────────────────────
const ST_IDLE   := 0
const ST_MAGNET := 1   # naturally magnetized (player walked into pickup radius)
const ST_FORCE  := 2   # pulled by the magnetic loot item (ramps from 0 speed)

# ── XP orb tiers (threshold = max xp for that tier, inclusive) ────────────────
const TIER_GREEN_MAX  :=  2.5   # XP is face-value now (1/20 of the old scale) → tiers rescaled ÷20, mults ×20,
const TIER_YELLOW_MAX :=  5.0   # caps unchanged, so orbs keep the same on-screen size/color as before.
const TIER_RED_MAX    := 25.0
const TIER_GREEN_MULT  := 20.0
const TIER_YELLOW_MULT := 10.0
const TIER_RED_MULT    := 4.0
const TIER_PURPLE_MULT := 2.0
const TIER_GREEN_CAP  :=  8.0
const TIER_YELLOW_CAP := 14.0
const TIER_RED_CAP    := 22.0
const TIER_PURPLE_CAP := 32.0
const GREEN_CORE  := Color(0.45, 1.0,  0.7)
const YELLOW_CORE := Color(1.0,  0.95, 0.2)
const RED_CORE    := Color(1.0,  0.18, 0.08)
const PURPLE_CORE := Color(0.75, 0.2,  1.0)

const GLOW_OUTER_MULT := 1.8   # outer faint glow radius = size × 1.8 (matches old _draw)
const TEX_SIZE := 64

# Parallel arrays — index i is one live orb (count = _n). Swap-remove keeps them packed.
var _pos:   PackedVector2Array = PackedVector2Array()
var _vel:   PackedVector2Array = PackedVector2Array()
var _col:   PackedColorArray   = PackedColorArray()
var _value: PackedFloat32Array = PackedFloat32Array()
var _diam:  PackedFloat32Array = PackedFloat32Array()   # quad world size (= glow diameter)
var _state: PackedInt32Array   = PackedInt32Array()
var _age:   PackedFloat32Array = PackedFloat32Array()
var _n: int = 0

var _player: Node2D = null
var _sfx: AudioStreamPlayer = null

func _ready() -> void:
	add_to_group("arena_xp_orb_mgr")
	texture = _make_glow_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # unit quad, scaled per-instance to the orb's diameter
	mm.mesh = quad
	mm.instance_count = MAX_ORBS
	mm.visible_instance_count = 0
	multimesh = mm
	_player = get_tree().get_first_node_in_group("player")
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = load("res://assets/audio/sfx/equip.wav") as AudioStream
	_sfx.volume_db = linear_to_db(0.6)
	_sfx.bus = "SFX"
	add_child(_sfx)

func _process(delta: float) -> void:
	if _n == 0:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var pp: Vector2 = _player.global_position
	var radius: float = GameManager.get_pickup_radius() if GameManager.has_method("get_pickup_radius") else 90.0
	var pick_sq := radius * radius
	var collect_sq := COLLECT_RADIUS * COLLECT_RADIUS
	var i := _n - 1
	while i >= 0:
		var st := _state[i]
		if st == ST_IDLE:
			_age[i] += delta
			var to_idle := pp - _pos[i]
			if to_idle.length_squared() <= pick_sq:
				_state[i] = ST_MAGNET
				_vel[i] = Vector2.ZERO
			elif _age[i] >= ORB_LIFETIME:
				_state[i] = ST_FORCE   # never lost, never piles up
				_vel[i] = Vector2.ZERO
			else:
				i -= 1
				continue   # idle + far + young → no transform write, basically free
		# magnetized (natural or forced): accelerate toward the player
		var to := pp - _pos[i]
		var d := to.length()
		var dir := to / maxf(d, 0.001)
		if _state[i] == ST_FORCE:
			var spdf := _vel[i].length() + FORCE_MAGNET_ACCEL * delta
			_vel[i] = dir * minf(spdf, FORCE_MAGNET_MAX)
		else:
			var spdn := maxf(_vel[i].length(), MAGNET_SPEED) + MAGNET_ACCEL * delta
			_vel[i] = dir * minf(spdn, MAGNET_MAX)
		_pos[i] += _vel[i] * delta
		if to.length_squared() <= collect_sq:
			_collect(i)
		else:
			_write_instance(i)
		i -= 1

# ── Spawn / merge ─────────────────────────────────────────────────────────────
## Add a collectible XP orb at a world position. Merges into a nearby idle orb when possible to keep the
## live array (and thus the per-frame loop) short.
func spawn(world_pos: Vector2, value: float) -> void:
	var merge_sq := MERGE_RADIUS * MERGE_RADIUS
	var scan_start := maxi(0, _n - MERGE_SCAN_MAX)   # scan only the most-recent orbs (see MERGE_SCAN_MAX)
	for i in range(_n - 1, scan_start - 1, -1):
		if _state[i] == ST_IDLE and (_pos[i] - world_pos).length_squared() <= merge_sq:
			_value[i] += value
			_apply_tier(i)
			_write_instance(i)
			return
	if _n >= MAX_ORBS:
		# Buffer full — collect the oldest live orb to free a slot (XP not lost).
		_collect(0)
	var idx := _n
	_pos.append(world_pos)
	_vel.append(Vector2.ZERO)
	_col.append(Color.WHITE)
	_value.append(value)
	_diam.append(1.0)
	_state.append(ST_IDLE)
	_age.append(0.0)
	_n += 1
	_apply_tier(idx)
	_write_instance(idx)
	multimesh.visible_instance_count = _n

# ── Magnetic loot item hooks (replace the old per-node group iteration) ────────
## Pull every orb toward the player with the smooth 0→1200 px/s ramp (magnetic loot item, full-map sweep).
func magnetize_all() -> void:
	for i in _n:
		if _state[i] != ST_FORCE:
			_state[i] = ST_FORCE
			_vel[i] = Vector2.ZERO

## Pull every orb within `rng` of `center` toward the player (radius-limited magnetic pull).
func magnetize_all_within(center: Vector2, rng: float) -> void:
	var rng_sq := rng * rng
	for i in _n:
		if _state[i] != ST_FORCE and (_pos[i] - center).length_squared() <= rng_sq:
			_state[i] = ST_FORCE
			_vel[i] = Vector2.ZERO

# ── Internals ─────────────────────────────────────────────────────────────────
func _collect(i: int) -> void:
	if GameManager.has_method("add_xp"):
		GameManager.add_xp(_value[i])
	if _sfx != null:
		_sfx.stop()
		_sfx.play()
	_swap_remove(i)

## Remove orb i by moving the last live orb into its slot (O(1)); the rest of the buffer is untouched.
func _swap_remove(i: int) -> void:
	var last := _n - 1
	if i != last:
		_pos[i]   = _pos[last]
		_vel[i]   = _vel[last]
		_col[i]   = _col[last]
		_value[i] = _value[last]
		_diam[i]  = _diam[last]
		_state[i] = _state[last]
		_age[i]   = _age[last]
		_write_instance(i)   # the moved orb now lives in slot i
	_pos.remove_at(last)
	_vel.remove_at(last)
	_col.remove_at(last)
	_value.remove_at(last)
	_diam.remove_at(last)
	_state.remove_at(last)
	_age.remove_at(last)
	_n -= 1
	multimesh.visible_instance_count = _n

## Push slot i's position/scale/color into the MultiMesh. Quad is unit + centered → scale = diameter.
func _write_instance(i: int) -> void:
	var d := _diam[i]
	var xf := Transform2D(Vector2(d, 0.0), Vector2(0.0, d), _pos[i])
	multimesh.set_instance_transform_2d(i, xf)
	multimesh.set_instance_color(i, _col[i])

## Compute tier size + color from the orb's current value (ported from arena_xp_orb._tier_params).
func _apply_tier(i: int) -> void:
	var v := float(_value[i])
	var sz: float
	var cc: Color
	if _value[i] <= TIER_GREEN_MAX:
		sz = minf(v * TIER_GREEN_MULT,  TIER_GREEN_CAP);  cc = GREEN_CORE
	elif _value[i] <= TIER_YELLOW_MAX:
		sz = minf(v * TIER_YELLOW_MULT, TIER_YELLOW_CAP); cc = YELLOW_CORE
	elif _value[i] <= TIER_RED_MAX:
		sz = minf(v * TIER_RED_MULT,    TIER_RED_CAP);    cc = RED_CORE
	else:
		sz = minf(v * TIER_PURPLE_MULT, TIER_PURPLE_CAP); cc = PURPLE_CORE
	_diam[i] = sz * GLOW_OUTER_MULT * 2.0   # quad spans the full outer-glow diameter
	_col[i] = cc

## Bake the shared soft-glow sprite once: white RGB (so per-instance color tints it) with a layered radial
## alpha profile reproducing the old 4-circle look (faint outer glow → solid core → hot centre).
func _make_glow_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := float(TEX_SIZE) * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var dx := (float(x) + 0.5 - c) / c
			var dy := (float(y) + 0.5 - c) / c
			var t := sqrt(dx * dx + dy * dy)   # 0 at centre, 1 at edge
			# Painter's-algorithm composite of the old layers (bottom → top), all white:
			var a := 0.0
			if t <= 1.0:               a = 0.15 + a * 0.85           # outer glow  (radius 1.0)
			if t <= 1.0 / GLOW_OUTER_MULT * 1.1:  a = 0.30 + a * 0.70   # mid glow (radius 1.1/1.8)
			if t <= 1.0 / GLOW_OUTER_MULT * 0.7:  a = 1.0               # solid core (radius 0.7/1.8)
			if t <= 1.0 / GLOW_OUTER_MULT * 0.30: a = 0.88 + a * 0.12   # hot centre (radius 0.30/1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
