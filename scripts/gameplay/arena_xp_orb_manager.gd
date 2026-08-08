extends MultiMeshInstance2D
## Single-node manager that renders and updates EVERY arena XP orb via two batched MultiMesh draw calls.
##
## Replaces the old per-orb Node2D model (arena_xp_orb.gd), where each orb ran _process + queue_redraw
## + a 4-draw_circle _draw() every frame with no cap — hundreds of those were the dominant share of the
## node count that tanked arena FPS. Here all orb state lives in parallel Packed arrays (no node per orb)
## and is drawn with two shared MultiMeshInstance2D layers — idle orbs cost only a distance check per frame
## and are never re-transformed. Lives on the sharp gameplay plane (arena root), world space (node at origin
## → instance transforms ARE world positions). Found by callers via group "arena_xp_orb_mgr".
##
## Two layers, back to front:
##  1. `self` — a fully procedural additive glow/sparkle aura (GLOW_SHADER_CODE), tinted per-instance by the
##     orb's tier glow color, animated on the GPU (TIME-based pulse + rotating rim sparkles, desynced per
##     orb via INSTANCE_CUSTOM's phase) — costs zero extra CPU per frame regardless of orb count.
##  2. `_sprite_mm` (child, drawn on top) — the real orb artwork (assets/screen/xp/*.png, one baked atlas,
##     SPRITE_SHADER_CODE) selected per-instance via INSTANCE_CUSTOM's tier index, same trick as
##     arena_plume_manager.gd's flipbook-frame selection.
## Both layers share the same slot index per orb (kept in lockstep by _write_instance/_swap_remove) so a
## single position write updates glow + sprite together.

# ── Magnet / collect tunables (ported verbatim from arena_xp_orb.gd) ───────────
const COLLECT_RADIUS      := 16.0
const MAGNET_SPEED        := 120.0    # starting fly speed once magnetized naturally (px/s)
const MAGNET_ACCEL        := 900.0    # acceleration when magnetized naturally (px/s²)
const MAGNET_MAX          := 1400.0   # speed cap for natural magnetization
const FORCE_MAGNET_ACCEL  := 600.0    # acceleration when pulled by the magnetic loot item (0→1200 in 2s)
const FORCE_MAGNET_MAX    := 1200.0   # speed cap for forced magnetization

# ── Pickup-streak SFX pitch ramp ────────────────────────────────────────────────
# Rapid consecutive pickups (walking through a field of orbs, or a mass suck-in) nudge the pickup sound's
# pitch up a little each beat instead of replaying the exact same note — reads as a rising "combo" instead of
# a machine-gun of identical clicks. One frame that collects ≥1 orb = one "beat" (matches the existing one-
# sound-per-frame batching above, not one sound per orb). The streak resets once STREAK_RESET_TIME passes
# with no pickup at all.
const STREAK_RESET_TIME  := 0.35    # seconds of no pickup before the streak resets to 0
const STREAK_PITCH_STEP  := 0.035   # pitch_scale added per consecutive beat
const STREAK_PITCH_MAX   := 1.8     # cap so a huge mass-pickup doesn't chipmunk the sound

# ── Population control ────────────────────────────────────────────────────────
const MAX_ORBS      := 16000    # MultiMesh buffer size (raised so orbs pile up instead of silently auto-collecting the oldest)
const MERGE_RADIUS  := 24.0     # an orb spawning within this of an idle orb folds its value into it
const MERGE_SCAN_MAX := 48      # spawn() only scans the most-recent N orbs for a merge target (O(1)-ish instead of
                                # O(all orbs)) — a whole cluster dying drops orbs at the same spot consecutively, so
                                # the merge target is always among the latest few. Avoids the mass-death spawn spike.
const ORB_LIFETIME  := INF      # disabled — idle orbs never auto-magnetize; XP piles up until you walk over it

# ── State machine ─────────────────────────────────────────────────────────────
const ST_IDLE   := 0
const ST_MAGNET := 1   # naturally magnetized (player walked into pickup radius)
const ST_FORCE  := 2   # pulled by the magnetic loot item (ramps from 0 speed)

# ── XP orb tiers (threshold = max xp for that tier, inclusive) ────────────────
# 2026-08-05: creep XP DROP scaled ×10 AGAIN (real pacing buff this time, not just a units rescale — see
# game_manager.gd's changelog) → thresholds rescaled ×10 to match (a fly's kill should still land in the same
# GREEN tier it always did), MULTs rescaled ÷10 to keep on-screen orb SIZE unchanged — same "rescale
# thresholds with value, rescale mult inversely, leave caps alone" pattern as the two PRIOR xp rescales below
# (÷20/×20, then ×10/÷10; this one compounds another ×10/÷10 on top of both).
# 2026-07-28: every ENEMY_DEFS "xp" value scaled ×10 (units-only rescale, see core.md's changelog) →
# thresholds rescaled ×10 to match, MULTs rescaled ÷10 to keep on-screen orb SIZE unchanged (size = value ×
# mult; value is 10× bigger, so mult must be 10× smaller to land on the same pixel size).
# 2026-08-02: added ORANGE as a 5th tier between YELLOW and RED (real orb artwork dropped in
# assets/screen/xp/ came in 5 colors) — threshold picked as the geometric midpoint of the yellow→red span
# (sqrt(50×250)≈112, rounded) so the two new sub-ranges are proportionally similar instead of a raw average
# skewing toward red; mult/cap interpolated between their yellow/red neighbors. (Both since-rescaled ×10 by
# the 2026-08-05 pass above, same as every other tier threshold/mult.)
const TIER_GREEN_MAX  := 250.0
const TIER_YELLOW_MAX := 500.0
const TIER_ORANGE_MAX := 1100.0
const TIER_RED_MAX    := 2500.0
const TIER_GREEN_MULT  := 0.2
const TIER_YELLOW_MULT := 0.1
const TIER_ORANGE_MULT := 0.06
const TIER_RED_MULT    := 0.04
const TIER_PURPLE_MULT := 0.02
const TIER_GREEN_CAP  :=  8.0
const TIER_YELLOW_CAP := 14.0
const TIER_ORANGE_CAP := 18.0
const TIER_RED_CAP    := 22.0
const TIER_PURPLE_CAP := 32.0

# Tier index (0..4) ↔ atlas cell ↔ glow tint — order must match ORB_TEX_PATHS below.
const TIER_GREEN  := 0
const TIER_YELLOW := 1
const TIER_ORANGE := 2
const TIER_RED    := 3
const TIER_PURPLE := 4
const TIER_GLOW := [
	Color(0.35, 1.0,  0.55),   # green  — matches green.png's neon trim
	Color(1.0,  0.85, 0.15),   # yellow — matches yellow.png's gold plating
	Color(1.0,  0.5,  0.05),   # orange — matches orange.png's copper plating
	Color(1.0,  0.15, 0.1),    # red    — matches red.png's crimson trim
	Color(0.75, 0.35, 1.0),    # purple — matches purple.png's violet trim
]

const GLOW_OUTER_MULT := 1.8   # outer glow/sparkle-ring radius = sprite radius × this
const ATLAS_CELL := 128        # px per tier cell in the baked sprite atlas (real art downsampled once at load)
const ORB_TEX_PATHS := [
	"res://assets/screen/xp/green.png",
	"res://assets/screen/xp/yellow.png",
	"res://assets/screen/xp/orange.png",
	"res://assets/screen/xp/red.png",
	"res://assets/screen/xp/purple.png",
]

# Additive, fully procedural (no texture sample) — pulsing haze + rotating sparkle glints right at the
# sprite's rim (t≈0.56 = 1/GLOW_OUTER_MULT, where the smaller sprite layer's edge sits inside this quad's
# UV space), both desynced per orb via INSTANCE_CUSTOM.x (a random phase set once at spawn).
const GLOW_SHADER_CODE := "shader_type canvas_item;\n" \
	+ "render_mode blend_add, unshaded;\n" \
	+ "varying flat float v_phase;\n" \
	+ "void vertex() { v_phase = INSTANCE_CUSTOM.x; }\n" \
	+ "void fragment() {\n" \
	+ "	vec2 p = UV - 0.5;\n" \
	+ "	float t = length(p) * 2.0;\n" \
	+ "	float ang = atan(p.y, p.x);\n" \
	+ "	float haze = pow(clamp(1.0 - t, 0.0, 1.0), 1.8);\n" \
	+ "	float pulse = 0.7 + 0.3 * sin(TIME * 2.1 + v_phase);\n" \
	+ "	float rim = 1.0 - smoothstep(0.10, 0.24, abs(t - 0.56));\n" \
	+ "	float spin = ang - TIME * 1.3 - v_phase;\n" \
	+ "	float glint = pow(max(0.0, cos(spin * 5.0)), 26.0);\n" \
	+ "	float a = clamp(haze * pulse * 0.5 + rim * glint * 1.4, 0.0, 1.0);\n" \
	+ "	COLOR = vec4(COLOR.rgb, COLOR.a * a);\n" \
	+ "}\n"

# Selects one of the 5 atlas cells per-instance (INSTANCE_CUSTOM.x = tier index), same pattern as
# arena_plume_manager.gd's flipbook-frame shader. Normal alpha blend — this is opaque metal artwork, not glow.
const SPRITE_SHADER_CODE := "shader_type canvas_item;\n" \
	+ "uniform sampler2D atlas : source_color, filter_linear;\n" \
	+ "uniform float cells;\n" \
	+ "varying flat float v_cell;\n" \
	+ "void vertex() { v_cell = INSTANCE_CUSTOM.x; }\n" \
	+ "void fragment() {\n" \
	+ "	float w = 1.0 / cells;\n" \
	+ "	vec2 uv = vec2((floor(v_cell) + UV.x) * w, UV.y);\n" \
	+ "	vec4 t = texture(atlas, uv);\n" \
	+ "	COLOR = vec4(t.rgb, t.a) * COLOR;\n" \
	+ "}\n"

# Parallel arrays — index i is one live orb (count = _n). Swap-remove keeps them packed.
var _pos:   PackedVector2Array = PackedVector2Array()
var _vel:   PackedVector2Array = PackedVector2Array()
var _col:   PackedColorArray   = PackedColorArray()   # glow/sparkle tint (see TIER_GLOW)
var _value: PackedFloat32Array = PackedFloat32Array()
var _diam:  PackedFloat32Array = PackedFloat32Array()   # glow-layer quad world size (sprite = this / GLOW_OUTER_MULT)
var _tier:  PackedInt32Array   = PackedInt32Array()     # atlas cell / TIER_GLOW index
var _phase: PackedFloat32Array = PackedFloat32Array()   # random shimmer phase, set once at spawn (desync)
var _state: PackedInt32Array   = PackedInt32Array()
var _age:   PackedFloat32Array = PackedFloat32Array()
var _n: int = 0

var _sprite_mm: MultiMeshInstance2D = null
var _player: Node2D = null
var _sfx: AudioStreamPlayer = null
var _streak: int = 0            # consecutive pickup "beats" (one per frame that collects ≥1 orb)
var _streak_gap: float = 0.0    # seconds since the last pickup beat — streak resets once this exceeds STREAK_RESET_TIME

func _ready() -> void:
	add_to_group("arena_xp_orb_mgr")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # unit quad, scaled per-instance to the orb's glow diameter
	mm.mesh = quad
	mm.instance_count = MAX_ORBS
	mm.visible_instance_count = 0
	multimesh = mm
	var glow_sh := Shader.new()
	glow_sh.code = GLOW_SHADER_CODE
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = glow_sh
	material = glow_mat

	var atlas := _bake_sprite_atlas()
	_sprite_mm = MultiMeshInstance2D.new()
	_sprite_mm.name = "OrbSpriteLayer"
	_sprite_mm.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_2D
	smm.use_colors = true
	smm.use_custom_data = true
	var squad := QuadMesh.new()
	squad.size = Vector2.ONE
	smm.mesh = squad
	smm.instance_count = MAX_ORBS
	smm.visible_instance_count = 0
	_sprite_mm.multimesh = smm
	var sprite_sh := Shader.new()
	sprite_sh.code = SPRITE_SHADER_CODE
	var sprite_mat := ShaderMaterial.new()
	sprite_mat.shader = sprite_sh
	sprite_mat.set_shader_parameter("atlas", atlas)
	sprite_mat.set_shader_parameter("cells", float(ORB_TEX_PATHS.size()))
	_sprite_mm.material = sprite_mat
	add_child(_sprite_mm)   # child → drawn after `self`, i.e. sprite renders on top of the glow

	_player = get_tree().get_first_node_in_group("player")
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = load("res://assets/audio/sfx/equip.wav") as AudioStream
	_sfx.volume_db = linear_to_db(0.6)
	_sfx.bus = "SFX"
	add_child(_sfx)

func _process(delta: float) -> void:
	_streak_gap += delta   # ticked unconditionally so an idle stretch (no orbs at all) still decays the streak
	if _streak_gap >= STREAK_RESET_TIME:
		_streak = 0
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
	# Vampire-Survivors / Halls-of-Torment style: collecting is a running total, not per-orb work. All orbs that
	# reach the player this frame are summed and handed to GameManager.add_xp ONCE, with ONE pickup sound — no
	# per-orb add_xp (and thus no per-orb save/HUD churn), which is what made a mass suck-in stutter.
	var got_xp := 0.0
	var got_any := false
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
			got_xp += _value[i]
			got_any = true
			_swap_remove(i)   # remove the orb; XP is applied in one batch after the loop
		else:
			_write_instance(i)
		i -= 1
	# One batched XP grant + one sound (pitched by the current streak) for everything collected this frame.
	if got_any:
		if GameManager.has_method("add_xp"):
			GameManager.add_xp(got_xp)
		_play_pickup_sfx()

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
	_tier.append(0)
	_phase.append(randf() * TAU)   # desync this orb's shimmer from every other orb
	_state.append(ST_IDLE)
	_age.append(0.0)
	_n += 1
	_sprite_mm.multimesh.set_instance_color(idx, Color.WHITE)   # sprite layer shows true art colors, never tinted
	_apply_tier(idx)
	_write_instance(idx)
	multimesh.visible_instance_count = _n
	_sprite_mm.multimesh.visible_instance_count = _n

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
	_play_pickup_sfx()
	_swap_remove(i)

## One pickup "beat": bumps the streak (or starts a fresh one if the gap since the last beat exceeded
## STREAK_RESET_TIME — see _process's unconditional gap tick), raises the sfx pitch a notch per streak step
## up to STREAK_PITCH_MAX, and plays it.
func _play_pickup_sfx() -> void:
	if _sfx == null:
		return
	_streak = 1 if _streak_gap >= STREAK_RESET_TIME else _streak + 1
	_streak_gap = 0.0
	_sfx.pitch_scale = clampf(1.0 + float(_streak - 1) * STREAK_PITCH_STEP, 1.0, STREAK_PITCH_MAX)
	_sfx.stop()
	_sfx.play()

## Remove orb i by moving the last live orb into its slot (O(1)); the rest of the buffer is untouched.
func _swap_remove(i: int) -> void:
	var last := _n - 1
	if i != last:
		_pos[i]   = _pos[last]
		_vel[i]   = _vel[last]
		_col[i]   = _col[last]
		_value[i] = _value[last]
		_diam[i]  = _diam[last]
		_tier[i]  = _tier[last]
		_phase[i] = _phase[last]
		_state[i] = _state[last]
		_age[i]   = _age[last]
		_write_instance(i)   # the moved orb now lives in slot i
	_pos.remove_at(last)
	_vel.remove_at(last)
	_col.remove_at(last)
	_value.remove_at(last)
	_diam.remove_at(last)
	_tier.remove_at(last)
	_phase.remove_at(last)
	_state.remove_at(last)
	_age.remove_at(last)
	_n -= 1
	multimesh.visible_instance_count = _n
	_sprite_mm.multimesh.visible_instance_count = _n

## Push slot i's position/scale/color/phase into both the glow and sprite MultiMeshes. Quads are unit +
## centered → scale = diameter.
func _write_instance(i: int) -> void:
	var d := _diam[i]
	var xf := Transform2D(Vector2(d, 0.0), Vector2(0.0, d), _pos[i])
	multimesh.set_instance_transform_2d(i, xf)
	multimesh.set_instance_color(i, _col[i])
	multimesh.set_instance_custom_data(i, Color(_phase[i], 0.0, 0.0, 0.0))
	var sd := d / GLOW_OUTER_MULT   # sprite = the orb's actual size; glow/sparkle ring extends further out around it
	var sxf := Transform2D(Vector2(sd, 0.0), Vector2(0.0, sd), _pos[i])
	_sprite_mm.multimesh.set_instance_transform_2d(i, sxf)
	_sprite_mm.multimesh.set_instance_custom_data(i, Color(float(_tier[i]), 0.0, 0.0, 0.0))

## Compute tier size + glow color from the orb's current value (ported from arena_xp_orb._tier_params).
func _apply_tier(i: int) -> void:
	var v := float(_value[i])
	var sz: float
	var tier: int
	if v <= TIER_GREEN_MAX:
		sz = minf(v * TIER_GREEN_MULT,  TIER_GREEN_CAP);  tier = TIER_GREEN
	elif v <= TIER_YELLOW_MAX:
		sz = minf(v * TIER_YELLOW_MULT, TIER_YELLOW_CAP); tier = TIER_YELLOW
	elif v <= TIER_ORANGE_MAX:
		sz = minf(v * TIER_ORANGE_MULT, TIER_ORANGE_CAP); tier = TIER_ORANGE
	elif v <= TIER_RED_MAX:
		sz = minf(v * TIER_RED_MULT,    TIER_RED_CAP);    tier = TIER_RED
	else:
		sz = minf(v * TIER_PURPLE_MULT, TIER_PURPLE_CAP); tier = TIER_PURPLE
	_diam[i] = sz * GLOW_OUTER_MULT * 2.0   # quad spans the full outer glow/sparkle diameter
	_tier[i] = tier
	_col[i] = TIER_GLOW[tier]

## Bake the shared sprite atlas once: the 5 real orb images (assets/screen/xp/*.png), each downsampled to a
## fixed ATLAS_CELL square and laid out in a horizontal strip, in TIER_* index order. get_image() decodes the
## imported PNG to a plain Image regardless of its import compression, so resize() always works here (unlike
## casting a loaded texture straight to ImageTexture, which only succeeds for textures already in that format).
func _bake_sprite_atlas() -> ImageTexture:
	var atlas := Image.create(ATLAS_CELL * ORB_TEX_PATHS.size(), ATLAS_CELL, false, Image.FORMAT_RGBA8)
	for i in ORB_TEX_PATHS.size():
		var tex: Texture2D = load(ORB_TEX_PATHS[i])
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(ATLAS_CELL, ATLAS_CELL, Image.INTERPOLATE_BILINEAR)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * ATLAS_CELL, 0))
	return ImageTexture.create_from_image(atlas)
