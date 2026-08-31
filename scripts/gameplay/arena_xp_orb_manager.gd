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
##  1. `self` — an additive glow aura, tinted per-instance by the orb's tier glow color (set_instance_color).
##     A baked radial-gradient texture (_bake_glow_gradient()) + CanvasItemMaterial.BLEND_MODE_ADD, no custom
##     shader at all as of 2026-08-29 — see _ready()'s own doc comment for why (was a procedural shader with
##     a TIME-based pulse; before that also drew 5 rotating rim "glint" spikes, removed earlier the same day).
##  2. `_sprite_mm` (child, drawn on top) — the real orb artwork, selected per-instance via INSTANCE_CUSTOM
##     (tier index in .x, spin-desync phase in .y), same atlas-cell-select trick as arena_plume_manager.gd's
##     flipbook-frame selection — see SPRITE_SHADER_CODE. This layer still uses a shader (there's no
##     alternative for animated per-instance atlas-frame selection); layer 1 above doesn't need one anymore.
## Both layers share the same slot index per orb (kept in lockstep by _write_instance/_swap_remove) so a
## single position write updates glow + sprite together.
##
## 2026-08-29, on request ("tôi đã đặt các glb xp vào assets/screen/xp. Tiến hành thay thế cho ảnh png. cùng
## kích thước, xoay xoay"): the sprite atlas is now a FRAME_COUNT-wide × tier-tall grid instead of a single
## 1×5 strip — each tier's row holds FRAME_COUNT snapshots of that tier's .glb (green/yellow/orange/red/
## purple.glb) baked at load time by spinning it in a throwaway SubViewport, one snapshot per rotation step.
## SPRITE_SHADER_CODE then picks (and, since 2026-08-29, crossfade-BLENDS between) two columns from TIME (+ a
## per-orb phase, the same desync trick this file uses elsewhere for per-orb variety) to fake a continuously-spinning 3D model at
## effectively zero added runtime cost (2 texture samples instead of 1) — orbs can number in the thousands, so
## an actual live SubViewport per orb (arena_loot.gd's recipe for the rare, few-at-a-time ruin pickups) is not
## an option here; this is the flipbook equivalent of that same "xoay xoay" look. See SPRITE_SHADER_CODE's own
## doc comment for why the blend (and FRAME_COUNT 24→48) were needed — a non-spherical model's silhouette
## genuinely isn't the same size from every angle, so a hard cut between snapshots read as the orb popping
## bigger, and the coarse angle step on top of that read as judder. Baking is
## async (_start_spin_bake, kicked off via call_deferred from _ready) so it never blocks arena startup —
## _bake_static_atlas() fills every row with its flat PNG first (replicated across all FRAME_COUNT columns,
## so the shader's addressing math needs no fallback branch), and any orb spawned before the glb bake finishes
## just shows that static frame until the atlas texture is swapped in-place via _atlas_tex.update(). A tier
## with no matching .glb (there currently isn't one) simply never gets its row overwritten and stays on the
## static PNG forever, same as today.
##
## 2026-08-29, on request ("đặt luôn các orb xp vào bảng ruin để tôi điều chỉnh kích thước"): all 5 tiers are
## now real Ruin Edit entries too (assets/screen/xp/ added to that editor's scanned folders) — WIRED_3D_CREEPS
## in creep_edit_mode.gd lists them alongside heart/magnetic/divinity/coin/shield.
##
## Size semantics (2026-08-29, follow-up: "tôi điều chỉnh giá trị minimum của từng orb, sau đó sẽ áp hệ số
## size to thêm theo code cũ") — XP orbs already grow with the killed enemy's XP value (small kill → small
## orb, up to a per-tier cap; see _apply_tier()'s old v*MULT/CAP curve, completely unchanged below). The W/H
## box does NOT override that curve or its cap — it sets a MINIMUM floor underneath it (_load_ruin_min →
## _tier_min_sz), so a weak kill's orb never renders smaller than the box value, but the old growth curve and
## cap still govern everything above that floor exactly as before. Deliberately guarded against
## creep_edit_mode.gd's own _save_layout() (it writes every currently-PLACED creep's size on every save, not
## just ones the user actually resized) silently baking the editor's seeded preview size in as a real floor —
## see _load_ruin_min()'s own doc comment.
## The Rotate X/Y/Z + PgUp/PgDn fields are read back once per tier inside _start_spin_bake() itself (baked
## straight into frame 0's starting orientation, same _ruin_rot()/_ruin_z() shape as arena_loot.gd's ruin
## drops) rather than per-orb like arena_loot.gd — there's one shared baked spin sequence per tier here, not
## a live model per pickup, so there's nothing to re-read per spawn.

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
# On-screen sprite diameter of a FULL-cap orb of each tier (sz=CAP → sprite diam = CAP*2; the glow-layer quad
# is that × GLOW_OUTER_MULT on top). Seeds ruin_edit_mode.gd's W/H box ONLY as a reasonably-sized preview to
# calibrate rotation against (_arena_display_px()) — it is NOT the runtime meaning of a saved size anymore
# (see _load_ruin_min()'s doc comment: that's a MINIMUM floor, unrelated to this cap). Kept as its own const
# purely so _load_ruin_min() can tell "user actually typed a number" apart from "box still shows the untouched
# preview seed" — same TIER_NAMES index order as everywhere else in this file (2026-08-29, on request: "đặt
# luôn các orb xp vào bảng ruin để tôi điều chỉnh kích thước").
const TIER_DEFAULT_PX := [TIER_GREEN_CAP * 2.0, TIER_YELLOW_CAP * 2.0, TIER_ORANGE_CAP * 2.0,
	TIER_RED_CAP * 2.0, TIER_PURPLE_CAP * 2.0]

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
# TIER_* index ↔ ruin_layout.cfg entry name — same order as everything else above, used by ruin_edit_mode.gd
# and the ruin-calibration read-back below (2026-08-29, on request: "đặt luôn các orb xp vào bảng ruin để tôi
# điều chỉnh kích thước").
const TIER_NAMES := ["green", "yellow", "orange", "red", "purple"]

const GLOW_OUTER_MULT := 1.8   # outer glow-ring radius = sprite radius × this
const ATLAS_CELL := 128        # px per tier cell in the baked sprite atlas (real art downsampled once at load)
const ORB_TEX_PATHS := [
	"res://assets/screen/xp/green.png",
	"res://assets/screen/xp/yellow.png",
	"res://assets/screen/xp/orange.png",
	"res://assets/screen/xp/red.png",
	"res://assets/screen/xp/purple.png",
]
# 2026-08-29: live 3D counterpart of ORB_TEX_PATHS above, same tier order — baked into a spin-frame atlas by
# _start_spin_bake() (see this file's header). A tier missing its .glb here just never gets its atlas row
# overwritten and stays on the flat PNG from ORB_TEX_PATHS, so this list is free to be a strict subset.
const ORB_GLB_PATHS := [
	"res://assets/screen/xp/green.glb",
	"res://assets/screen/xp/yellow.glb",
	"res://assets/screen/xp/orange.glb",
	"res://assets/screen/xp/red.glb",
	"res://assets/screen/xp/purple.glb",
]
const FRAME_COUNT := 48        # baked rotation snapshots per tier (one full 360° turn) — flipbook column count.
	# 24→48 (2026-08-29, "animation xoay hơi giật") — halves the angular gap between any two snapshots
	# SPRITE_SHADER_CODE crossfades between, on top of that shader now blending instead of hard-cutting.
	# Bake cost scales with this (one `await get_tree().process_frame` per step, shared across every tier's
	# viewport at once — see _start_spin_bake()) — 48 steps ≈ 0.8s one-time async load hit on a real GPU,
	# still never blocks arena startup. Atlas texture also scales linearly (now ~2× the old memory/width).
const ORB_ROT_RPM := 12.0      # matches arena_loot.gd/arena_chest.gd's ROT_RPM elsewhere in the project
const ORB_SPIN_HZ  := ORB_ROT_RPM / 60.0   # revolutions/sec — SPRITE_SHADER_CODE steps columns at this rate
const BAKE_ISO_DEG := 30.0     # camera tilt while baking — matches arena_loot.gd's ISO_DEG

# 2026-08-29 history: this used to be a fully procedural shader (haze falloff + a TIME-based pulse). Before
# that, it ALSO drew 5 rotating, needle-sharp "glint" spikes (pow(cos(spin*5),26)) sitting almost exactly on
# the sprite's own edge — on request ("bỏ cái vfx dạng tia bao quanh orb đi") those were removed, keeping just
# haze+pulse. Then a further bug report ("bug có 1 frame bị phóng to bất thường... vuông", happening
# continuously, even to orbs that never merge or move) pointed at this layer specifically: it's the only
# literally SQUARE-shaped element in the whole render (a plain unit quad) — everything else either sits well
# inside its own quad's bounds (the sprite art) or has a texture doing the shaping. A per-pixel procedural
# shader is the one thing that could plausibly fail to apply for a single draw and let that raw square show
# through. Replaced entirely by _bake_glow_gradient() (a plain alpha-blended texture whose pixels already ARE
# the falloff shape) + CanvasItemMaterial.BLEND_MODE_ADD (a built-in blend flag, not a shader) in _ready() —
# see that function's own doc comment. No shader code left for this layer at all.

# Selects TWO adjacent cells of the FRAME_COUNT × tier grid per-instance — row from INSTANCE_CUSTOM.x (tier
# index, unchanged), column stepped over TIME (+ INSTANCE_CUSTOM.y, a per-orb phase reused from the glow
# layer's own desync trick) — and crossfades between them by how far into the current step TIME has gotten,
# instead of hard-cutting from one baked frame straight to the next.
#
# 2026-08-29, on request ("animation xoay tôi thấy hơi giật" + a bug report of the orb "phóng to rõ ràng" that
# survived removing the glow VFX — i.e. a REAL geometry-level pop, not the glow spikes): a non-spherical
# model's SILHOUETTE genuinely isn't the same size from every angle (broadside vs edge-on), so consecutive
# baked snapshots legitimately differ in apparent size a little — with a hard cel-to-cel cut (the old
# `floor()`-only version) that shows up as an abrupt "pop," and the coarse angular step between snapshots
# (15° at the old FRAME_COUNT=24) on top of that abrupt cut is what read as judder. mix()-blending the two
# neighboring frames turns both into a smooth, gradual crossfade — same fix as a traditional 2D sprite
# flipbook adding motion-blur/tweening, just done with 2 texture samples instead of re-baking. Paired with
# FRAME_COUNT going 24→48 below (half the angular gap between any two blended frames) so the crossfade window
# is narrower and closer in pose to begin with. Same atlas-cell-select shape as arena_plume_manager.gd's
# flipbook-frame shader, just 2D-addressed and now blended. Normal alpha blend — this is opaque model
# artwork, not glow.
#
# 2026-08-29 hardening (same bug report as the glow-layer rewrite): `f0`/`f1` were computed straight from
# `floor()`/`mod()` with no bound — floating-point rounding of TIME (which only ever grows) COULD in principle
# round `fract(...)` up to something numerically indistinguishable from 1.0, making `f0 = frame_count` (one
# past the LAST valid column), sampling past the whole atlas's right edge into undefined territory. `f0` is
# now explicitly clamped into the valid range regardless. Separately, `UV.x`/`UV.y` used to reach exactly 0.0/
# 1.0 at a cell's own edge — with `filter_linear`, sampling exactly on a seam blends in the NEIGHBORING cell's
# edge pixels (a different rotation frame, or across the row boundary a different TIER entirely) — standard
# texture-atlas bleeding, avoided the standard way: `half_texel_uv` insets the sample point half a texel in
# from every cell edge so linear filtering only ever mixes texels that belong to the SAME cell.
const SPRITE_SHADER_CODE := "shader_type canvas_item;\n" \
	+ "uniform sampler2D atlas : source_color, filter_linear;\n" \
	+ "uniform float frame_count;\n" \
	+ "uniform float tier_count;\n" \
	+ "uniform float spin_hz;\n" \
	+ "uniform float half_texel_uv;\n" \
	+ "varying flat float v_tier;\n" \
	+ "varying flat float v_phase;\n" \
	+ "void vertex() { v_tier = INSTANCE_CUSTOM.x; v_phase = INSTANCE_CUSTOM.y; }\n" \
	+ "void fragment() {\n" \
	+ "	float raw = fract(TIME * spin_hz + v_phase) * frame_count;\n" \
	+ "	float f0 = clamp(floor(raw), 0.0, frame_count - 1.0);\n" \
	+ "	float f1 = mod(f0 + 1.0, frame_count);\n" \
	+ "	float blend = clamp(raw - f0, 0.0, 1.0);\n" \
	+ "	float row = floor(v_tier);\n" \
	+ "	vec2 uv_local = clamp(UV, vec2(half_texel_uv), vec2(1.0 - half_texel_uv));\n" \
	+ "	vec2 cw = vec2(1.0 / frame_count, 1.0 / tier_count);\n" \
	+ "	vec2 uv0 = vec2((f0 + uv_local.x) * cw.x, (row + uv_local.y) * cw.y);\n" \
	+ "	vec2 uv1 = vec2((f1 + uv_local.x) * cw.x, (row + uv_local.y) * cw.y);\n" \
	+ "	vec4 t = mix(texture(atlas, uv0), texture(atlas, uv1), blend);\n" \
	+ "	COLOR = vec4(t.rgb, t.a) * COLOR;\n" \
	+ "}\n"

# Parallel arrays — index i is one live orb (count = _n). Swap-remove keeps them packed.
var _pos:   PackedVector2Array = PackedVector2Array()
var _vel:   PackedVector2Array = PackedVector2Array()
var _col:   PackedColorArray   = PackedColorArray()   # glow tint (see TIER_GLOW)
var _value: PackedFloat32Array = PackedFloat32Array()
var _diam:  PackedFloat32Array = PackedFloat32Array()   # glow-layer quad world size (sprite = this / GLOW_OUTER_MULT)
var _tier:  PackedInt32Array   = PackedInt32Array()     # atlas cell / TIER_GLOW index
var _phase: PackedFloat32Array = PackedFloat32Array()   # random shimmer phase, set once at spawn (desync)
var _state: PackedInt32Array   = PackedInt32Array()
var _age:   PackedFloat32Array = PackedFloat32Array()
var _n: int = 0

var _sprite_mm: MultiMeshInstance2D = null
var _atlas_img: Image = null          # the live FRAME_COUNT × tier grid — mutated in place by _start_spin_bake()
var _atlas_tex: ImageTexture = null   # shader's "atlas" param; .update(_atlas_img) pushes bake progress without a texture swap
# Ruin Edit's saved per-tier MINIMUM sprite half-size (sz units, i.e. px/2 — see _apply_tier()), read ONCE in
# _ready() (unlike arena_loot.gd's per-spawn cfg read — that file has no long-lived owner to cache on, this
# manager IS one, and _apply_tier() can run thousands of times a run, so a ConfigFile hit per call would be
# real, avoidable cost). 0.0 = unedited — the old v*MULT/CAP curve alone decides size, exactly like before
# this feature. See _load_ruin_min()'s own doc comment for why this is a floor, not a scale multiplier.
var _tier_min_sz: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _player: Node2D = null
var _sfx: AudioStreamPlayer = null
var _streak: int = 0            # consecutive pickup "beats" (one per frame that collects ≥1 orb)
var _streak_gap: float = 0.0    # seconds since the last pickup beat — streak resets once this exceeds STREAK_RESET_TIME

func _ready() -> void:
	add_to_group("arena_xp_orb_mgr")
	_load_ruin_min()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = false   # 2026-08-29: glow layer no longer needs per-instance data — see below
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # unit quad, scaled per-instance to the orb's glow diameter
	mm.mesh = quad
	mm.instance_count = MAX_ORBS
	mm.visible_instance_count = 0
	multimesh = mm
	# 2026-08-29, bug report ("bug có 1 frame bị phóng to bất thường... vuông", happening continuously to
	# EVERY orb, not just merges, including orbs already sitting idle on screen): idle orbs' MultiMesh data is
	# never rewritten after their initial spawn (see _process()'s "idle+far+young → no transform write,
	# basically free" skip) — so the ONLY thing that could still change frame to frame for an unchanged,
	# stationary orb is whatever a SHADER computes purely from TIME. This layer's old GLOW_SHADER_CODE
	# procedurally shaped a plain square quad into a soft circle every single pixel, every single frame — if
	# that shader's pipeline ever failed to bind for one draw (a known class of hitch for shaders built at
	# runtime via Shader.new()+code, vs. one Godot can precompile ahead of time from a .gdshader resource),
	# the unclipped, un-shaped RAW quad would flash through for that one frame: exactly "big and square." No
	# custom shader for this layer anymore, period — GLOW_SHADER_CODE is gone, replaced by a texture whose
	# alpha already IS the falloff shape (baked once in _bake_glow_gradient(), plain alpha-blended pixels, no
	# per-pixel shader math to ever fail to apply) plus Godot's own built-in additive blend mode (a material
	# FLAG, not a shader) for the "glow" look. Trades away the old per-instance TIME-based breathing pulse —
	# a much smaller loss than an orb randomly flashing to a bright square.
	texture = _bake_glow_gradient()
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow_mat

	_atlas_img = _bake_static_atlas()
	_atlas_tex = ImageTexture.create_from_image(_atlas_img)
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
	sprite_mat.set_shader_parameter("atlas", _atlas_tex)
	sprite_mat.set_shader_parameter("frame_count", float(FRAME_COUNT))
	sprite_mat.set_shader_parameter("tier_count", float(ORB_TEX_PATHS.size()))
	sprite_mat.set_shader_parameter("spin_hz", ORB_SPIN_HZ)
	sprite_mat.set_shader_parameter("half_texel_uv", 0.5 / float(ATLAS_CELL))
	_sprite_mm.material = sprite_mat
	add_child(_sprite_mm)   # child → drawn after `self`, i.e. sprite renders on top of the glow
	call_deferred("_start_spin_bake")   # async — see header note; never blocks arena startup

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
	multimesh.set_instance_color(i, _col[i])   # glow layer no longer reads custom_data (see _ready()'s note) — nothing to set here anymore
	var sd := d / GLOW_OUTER_MULT   # sprite = the orb's actual size; glow ring extends further out around it
	var sxf := Transform2D(Vector2(sd, 0.0), Vector2(0.0, sd), _pos[i])
	_sprite_mm.multimesh.set_instance_transform_2d(i, sxf)
	# .y = this orb's shimmer phase (same value the glow layer already uses), reused here to desync which
	# baked spin-frame each orb shows so a field of same-tier orbs doesn't all rotate in visible lockstep.
	_sprite_mm.multimesh.set_instance_custom_data(i, Color(float(_tier[i]), _phase[i], 0.0, 0.0))

## Compute tier size + glow color from the orb's current value (ported from arena_xp_orb._tier_params).
##
## 2026-08-29 fix (bug report: orb "phóng to rõ ràng" — a real, deterministic, reproducible jump, not the
## rotation-bake artifact the "hơi giật" report was; that one was fixed separately by blending + FRAME_COUNT
## above). Each tier used to size independently off its OWN v*MULT starting from 0 — a merge that pushed
## `v` across a tier boundary jumped straight from the old tier's cap to the new tier's OWN formula, which is
## already capped again almost immediately (e.g. at v=TIER_GREEN_MAX, green sz=TIER_GREEN_CAP=8; one XP point
## later, now yellow, sz=minf(v*TIER_YELLOW_MULT, TIER_YELLOW_CAP)=14 already, since yellow's cap is reached
## at v≈140, well under TIER_GREEN_MAX=250) — an instant, discontinuous, PERMANENT ~75% size jump on that one
## merge, not a rendering blip. Each tier now continues from the PREVIOUS tier's cap instead of restarting at
## 0, so size grows smoothly straight through every boundary. Safe by construction: every tier's own cap is
## reached well before its MAX threshold (green caps at v≈40 of 250; yellow at v≈310 of 500; orange at v≈567
## of 1100; red at v≈1200 of 2500) — so "the previous tier's cap" is always exactly what v reached right
## before crossing, not an approximation.
func _apply_tier(i: int) -> void:
	var v := float(_value[i])
	var sz: float
	var tier: int
	if v <= TIER_GREEN_MAX:
		sz = minf(v * TIER_GREEN_MULT, TIER_GREEN_CAP)
		tier = TIER_GREEN
	elif v <= TIER_YELLOW_MAX:
		sz = minf(TIER_GREEN_CAP + (v - TIER_GREEN_MAX) * TIER_YELLOW_MULT, TIER_YELLOW_CAP)
		tier = TIER_YELLOW
	elif v <= TIER_ORANGE_MAX:
		sz = minf(TIER_YELLOW_CAP + (v - TIER_YELLOW_MAX) * TIER_ORANGE_MULT, TIER_ORANGE_CAP)
		tier = TIER_ORANGE
	elif v <= TIER_RED_MAX:
		sz = minf(TIER_ORANGE_CAP + (v - TIER_ORANGE_MAX) * TIER_RED_MULT, TIER_RED_CAP)
		tier = TIER_RED
	else:
		sz = minf(TIER_RED_CAP + (v - TIER_RED_MAX) * TIER_PURPLE_MULT, TIER_PURPLE_CAP)
		tier = TIER_PURPLE
	# _tier_min_sz (Ruin Edit's saved MINIMUM, 2026-08-29 follow-up: "tôi điều chỉnh giá trị minimum của từng
	# orb, sau đó sẽ áp hệ số size to thêm theo code cũ") clamps the OLD v*MULT/CAP curve up from below —
	# everything above the floor still follows that curve completely unchanged, only a weak kill that would've
	# rendered smaller than the floor gets pulled up to it. maxf here, not a multiply, so the cap above is
	# never touched by this at all.
	sz = maxf(sz, _tier_min_sz[tier])
	_diam[i] = sz * GLOW_OUTER_MULT * 2.0   # quad spans the full outer glow diameter
	_tier[i] = tier
	_col[i] = TIER_GLOW[tier]

## Ruin Edit's saved W/H box, read once at startup and cached as a per-tier MINIMUM (half of the saved px,
## since sprite diam = sz*2 — see _apply_tier()). Skips a tier whose saved size still EXACTLY matches
## TIER_DEFAULT_PX (the box's own untouched preview seed) and treats it as unedited (floor stays 0) —
## necessary because creep_edit_mode.gd's _save_layout() writes every currently-PLACED creep's size on every
## save, not just ones actually resized, so merely opening this tab and saving an unrelated change would
## otherwise silently bake the seed in as a real floor and flatten that tier to always-max-size. The one
## edge case this can't tell apart: deliberately typing the EXACT same number as the seed reads as "untouched"
## too — negligible in practice (nudge the box by any visible amount and it's unambiguous).
func _load_ruin_min() -> void:
	for i in TIER_NAMES.size():
		var entry := _ruin_layout_entry(TIER_NAMES[i])
		var sz = entry.get("size", null)
		if sz == null:
			continue
		var saved_px := float((sz as Vector2).x)
		if absf(saved_px - float(TIER_DEFAULT_PX[i])) < 0.01:
			continue   # matches the untouched seed exactly — treat as never-edited, floor stays 0
		_tier_min_sz[i] = saved_px * 0.5

## The saved calibration entry for a tier name from ruin_edit_mode.gd's cfg ("creeps" section) — mirrors
## arena_loot.gd's own _ruin_layout_entry() exactly (same file, same section shape), just keyed by tier name
## ("green"/"yellow"/"orange"/"red"/"purple") instead of a loot `_type`.
func _ruin_layout_entry(name: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("res://ruin_layout.cfg") != OK:
		return {}
	return cfg.get_value("creeps", name, {})

## EDITOR-space (Z-up) mount angle → a Y-up Euler ready for `Node3D.rotation` — see arena_loot.gd's own
## _ruin_rot() doc comment (identical recipe, reused here for the tier models baked in _start_spin_bake()).
func _ruin_rot(entry: Dictionary) -> Vector3:
	if entry.is_empty():
		return Vector3.ZERO
	var rig := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var composed: Vector3 = rig.compose_rot(entry.get("rot_base", Vector3.ZERO), entry.get("rot", Vector3.ZERO))
	return rig.view_rotation(composed)

## PgUp/PgDn vertical lift — same "z" field every other Ruin Edit entry saves.
func _ruin_z(entry: Dictionary) -> float:
	return float(entry.get("z", 0.0))

## Bake the glow layer's soft radial falloff into a small texture once at startup — replaces what used to be
## a per-pixel shader computation (pow(clamp(1-t,0,1),1.8), t = distance from center) with the exact same
## curve pre-rendered into the alpha channel. See _ready()'s 2026-08-29 doc comment for why: a texture's
## pixels can't "fail to apply" the way a custom fragment shader's math theoretically could for one draw call.
## Small (64×64) since it's just a soft gradient — GPU upsamples it smoothly via linear filtering same as any
## other UI/glow texture.
func _bake_glow_gradient() -> ImageTexture:
	const SIZE := 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := float(SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			var dx := (float(x) + 0.5 - c) / c
			var dy := (float(y) + 0.5 - c) / c
			var t := sqrt(dx * dx + dy * dy)
			var haze := pow(clampf(1.0 - t, 0.0, 1.0), 1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(haze * 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Build the immediate-use FRAME_COUNT × tier atlas from the flat PNGs alone (assets/screen/xp/*.png), each
## downsampled to ATLAS_CELL and replicated across every column of its tier's row — this is what's on screen
## from frame one (identical look to the pre-2026-08-29 single-image-per-tier version) until/unless
## _start_spin_bake() overwrites a row with real rotated .glb snapshots. get_image() decodes the imported PNG
## to a plain Image regardless of its import compression, so resize() always works here (unlike casting a
## loaded texture straight to ImageTexture, which only succeeds for textures already in that format).
func _bake_static_atlas() -> Image:
	var atlas := Image.create(ATLAS_CELL * FRAME_COUNT, ATLAS_CELL * ORB_TEX_PATHS.size(), false, Image.FORMAT_RGBA8)
	for tier in ORB_TEX_PATHS.size():
		var tex: Texture2D = load(ORB_TEX_PATHS[tier])
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(ATLAS_CELL, ATLAS_CELL, Image.INTERPOLATE_BILINEAR)
		var y := tier * ATLAS_CELL
		for f in FRAME_COUNT:
			atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(f * ATLAS_CELL, y))
	return atlas

## Async load-time bake: for every tier with a matching .glb (ORB_GLB_PATHS), spin it in a throwaway
## SubViewport and capture FRAME_COUNT snapshots (one per rotation step) straight into that tier's row of
## _atlas_img, replacing the flat PNG _bake_static_atlas() put there. Runs all tiers' viewports in lockstep
## (one shared `await get_tree().process_frame` per step) so the whole bake costs FRAME_COUNT frames total,
## not FRAME_COUNT × tier_count — a one-time, sub-second load hit regardless of how many tiers have art.
## Never blocks spawn(): any orb created before this finishes just shows the static frame (see header note),
## and _atlas_tex.update() below swaps in the real spin in place, mid-game, with no pop for orbs already live
## (same atlas texture object, just refreshed pixels).
func _start_spin_bake() -> void:
	var rigs: Array = []   # [{tier:int, vp:SubViewport, pivot:Node3D, cam:Camera3D}]
	for tier in ORB_GLB_PATHS.size():
		var glb_path: String = ORB_GLB_PATHS[tier]
		if not ResourceLoader.exists(glb_path):
			continue
		var packed := load(glb_path) as PackedScene
		var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
		if model == null:
			push_warning("arena_xp_orb_manager: could not load " + glb_path)
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(ATLAS_CELL, ATLAS_CELL)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var key := DirectionalLight3D.new()
		key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
		key.light_energy = 1.3
		vp.add_child(key)
		var fill := DirectionalLight3D.new()
		fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
		fill.light_energy = 0.5
		vp.add_child(fill)
		var cam := Camera3D.new()
		vp.add_child(cam)
		var pivot := Node3D.new()
		vp.add_child(pivot)
		pivot.add_child(model)
		_frame_bake_cam(model, cam)
		# Ruin Edit's saved mount-angle/lift (2026-08-29) — applied AFTER _frame_bake_cam()'s AABB-centering
		# (which only ever touches model.position, never model.rotation), same non-conflicting split
		# arena_loot.gd's _build_model_viewport() already uses. This sets frame 0's starting orientation; the
		# rotation-step loop below still turns `pivot` (the model's parent) from there to bake the spin.
		var entry := _ruin_layout_entry(TIER_NAMES[tier])
		if not entry.is_empty():
			model.rotation = _ruin_rot(entry)
			model.position.y += _ruin_z(entry)
		rigs.append({"tier": tier, "vp": vp, "pivot": pivot})
	if rigs.is_empty():
		return   # no xp orb .glb found (yet) — stay on the static PNG atlas, exactly like before this pass
	# 2026-08-29, bug report ("lỗi do quá trình bake" — confirmed NOT the glow layer, NOT the size formula:
	# arena_loot.gd's live pickups (heart/divinity/shield/...) never show this, and the one thing THIS system
	# does that they don't is bake once and replay forever): a freshly-created SubViewport's rendering can lag
	# its own property setup (transparent_bg, lights, camera, the rotation just set) by more than the single
	# frame this bake used to wait before capturing — arena_loot.gd's live pickups re-render EVERY frame, so
	# one stale/incomplete frame there is invisible (next frame just overwrites it); here, whatever gets
	# captured is baked into the atlas PERMANENTLY and replayed on a loop for the rest of the match — an
	# opaque/undefined background captured too early (before transparent_bg has actually taken effect) reads
	# exactly as "a big solid block," and it comes back every single revolution, matching "xảy ra liên tục
	# suốt trận" precisely. Two changes: let every rig sit for a few frames before the FIRST capture (lets a
	# brand-new viewport's background/lighting truly settle once, up front), and wait 2 frames per rotation
	# step instead of 1 (one for the transform to land, one more for the render to actually reflect it) rather
	# than assuming a single process_frame is always enough.
	for _settle in 3:
		await get_tree().process_frame
	for f in FRAME_COUNT:
		var ang := f * TAU / float(FRAME_COUNT)
		for rig in rigs:
			(rig.pivot as Node3D).rotation.y = ang
		await get_tree().process_frame
		await get_tree().process_frame   # 2nd settle frame per step — see this function's doc note above
		var x := f * ATLAS_CELL
		for rig in rigs:
			var tex := (rig.vp as SubViewport).get_texture()
			var img: Image = tex.get_image() if tex != null else null
			if img == null:
				continue   # a viewport that hasn't produced a frame yet (or a headless/no-GPU run with no
				           # real rendering backend) just leaves this cell on its static PNG fallback instead
				           # of crashing the whole bake — the next frame's capture tries again regardless.
			img.convert(Image.FORMAT_RGBA8)
			var y: int = int(rig.tier) * ATLAS_CELL
			_atlas_img.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(ATLAS_CELL, ATLAS_CELL)), Vector2i(x, y))
	_atlas_tex.update(_atlas_img)
	for rig in rigs:
		(rig.vp as SubViewport).queue_free()

## Center `model` on its own AABB and place `cam` at a fixed BAKE_ISO_DEG tilt, backed off just far enough to
## fit the whole model — same recipe as arena_loot.gd/arena_chest.gd's own _frame_cam(), duplicated here since
## this bake is a load-time, run-once affair with no shared rig node to call into.
func _frame_bake_cam(model: Node3D, cam: Camera3D) -> void:
	var aabb := _model_aabb_bake(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	var iso := deg_to_rad(BAKE_ISO_DEG)
	cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	cam.near = maxf(0.05, dist - radius * 2.0)
	cam.far  = dist + radius * 2.0

func _model_aabb_bake(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in _model_meshes_bake(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _model_meshes_bake(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_model_meshes_bake(c))
	return out
