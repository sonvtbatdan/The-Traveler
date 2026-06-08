extends Control

const SS_OFFSET := Vector2(270.0, 8.0)
const OC_BOUNDS := Rect2(270.0, 8.0, 700.0, 764.0)
const GifLoader  := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const LasgunBeamScript := preload("res://scripts/gameplay/lasgun_beam.gd")  # player-Lasgun procedural beam

# Viewport-space limits (screen-local + SS_OFFSET)
const Y_LIMIT       := 458.0   # 450 screen-local + 8
const BALL_SPIN_POS := Vector2(620.0, 158.0)   # (350,150) screen-local

# Final patrol waypoints (viewport space)
const TEAL_WP_A := Vector2(920.0, 158.0)   # (650,150)
const TEAL_WP_B := Vector2(320.0, 158.0)   # (50,150)
const BLUE_WP_A := Vector2(320.0, 108.0)   # (50,100)
const BLUE_WP_B := Vector2(920.0, 108.0)   # (650,100)

# Bullet wave spawn (viewport space)
const WAVE_Y     := 58.0
const WAVE_X_MIN := 280.0
const WAVE_X_MAX := 920.0

const BOSS_MAX_HP := 1500
const ORB_MAX_HP  := 1000

const M1_SPEED     := 120.0
const M1_SHOOT_INT := 0.7   # seconds between spreads (30% faster than 1.0)
const M1_FP2_DELAY := 0.25
const M1_MIN_DUR   := 6.0
const M1_MAX_DUR   := 10.0
const M1_PANIC_RANGE := 100.0   # if the player gets this close in Move 1, bail into the Ball Charge (Move 4)

const M2_MOVE_SPD  := 150.0
const M2_MOVE_RPM  := 40.0
const M2_SPIN_RPM  := 80.0
const M2_SPINUP_T  := 3.0     # time to ramp up to full spin speed (controls spin FEEL — unchanged)
const M2_SPIN_DUR  := 5.0     # how long the spin phase lasts
const M2_SHOOT_INT := 0.111   # 3x faster fire than before (0.334) → 3x more projectiles in the spin phase

const M3_BODY_RPM  := 20.0     # ball's slow idle spin
const M3_ORB_SHOOT := 0.25     # orb fire interval during the spiral
# Move 3: curl → eject to the sides → spiral back, firing
const M3_CURL_T       := 1.0     # stage 1: curl + fast spin + orbs glow in
const M3_CURL_RPM     := 240.0   # fast spin during curl
const M3_EJECT_T      := 0.45    # fly-out-to-the-sides duration
const M3_ORB_GLOW_MAX := 2.0     # orb brightness peak for the shine-in
const M3_SIDE_CM      := 5.0     # orbs eject this far to each side of the body
const M3_SPIRAL_T     := 4.0     # spiral-back duration
const M3_SPIRAL_TURNS := 3.0     # full rotations during the spiral
# Bullet hit radius as a fraction of its half-size — keeps the hitbox tight to the
# diamond/hex VISUAL instead of the full square texture (transparent corners don't hit).
const BULLET_HIT_FACTOR := 0.7
# Bullet render sizes (px) — kept in code so they don't depend on decorative layout
# objects. Tune here. Index i of _bullet_frames maps to "chromebullet(i+1)".
const BULLET_SIZES := {
	"chromebullet1": Vector2(10, 41), "chromebullet2": Vector2(8, 42),
	"chromebullet3": Vector2(9, 40),  "chromebullet4": Vector2(14, 42),
	"chromebullet5": Vector2(12, 43), "chromebullet6": Vector2(12, 43),
	"chromebullet7": Vector2(12, 42), "chromebullet8": Vector2(11, 42),
	"chromebullet9": Vector2(11, 43), "chromebullet10": Vector2(16, 38),
	"chromebullet11": Vector2(12, 40), "chromebullet12": Vector2(28, 41),
	"bluebullet": Vector2(30, 30), "tealbullet": Vector2(30, 30),
}
# Safety net: if any single main-phase move runs longer than this (well above the
# longest legit move, the ~15s spin), force-recover so the boss can never get stuck
# "spinning in place doing nothing" again, whatever sub-phase breaks.
const MOVE_HARD_CAP := 30.0

const M4_SPIN_DUR         := 1.0     # spin-in-place telegraph before the first charge
const M4_CHARGE_MAX       := 600.0   # max charge speed (px/s)
const M4_CHARGE_ACCEL     := 3000.0  # pass-1 ramp 0 → max (px/s^2)
const M4_OFFSCREEN_T      := 1.0     # time spent out of the map between passes
const M4_PASSES           := 5       # total charge passes
const M4_CHARGE_RPM       := 80.0    # spin speed while telegraphing / charging
const M4_OVERSHOOT_MARGIN := 90.0    # how far past the edge counts as "fully out"
const M4_FINAL_T          := 1.0     # 5th charge: decelerating glide that stops at the ending spot
const M4_HIT_DMG    := 40
# TEST TOGGLE: 0 = full random moveset (M1-M4); 1-4 = force only that move.
const DEBUG_FORCE_MOVE := 0

# ── Phase 2 (orb fight) ───────────────────────────────────────────────────────
# TEST TOGGLE: true = skip Phase 1 and start the fight directly in Phase 2 (orbs as target).
# Flip to false for the normal flow (Phase 1 moves → HP 0 → transition cutscene → Phase 2).
const DEBUG_START_IN_PHASE2 := true
# TEST TOGGLE: which Phase-2 attack the picker forces. 1 = Move 1 (bull charge + slide lasers),
# 2 = Move 2 (docked rotating laser cross). Switch this value to test each in isolation.
const DEBUG_FORCE_ATTACK := 3
# Attack-1 orbs: deterministic SLIDE (2s) → CHANNEL (1s) → FIRE (3s) cycle, run independently
# per orb. Channel locks the aim + shows the Elephant warning sign + an inward light-gather FX;
# FIRE shoots a recolored copy of the Elephant lasgun (300px wide) in the locked direction.
const P2_ORB_SLIDE_T     := 2.0     # slide phase duration
const P2_ORB_CHANNEL_T   := 1.0     # channel (stationary, aim-lock + telegraph) duration
const P2_ORB_FIRE_T      := 3.0     # fire (stationary beam) duration
const P2_ORB_SLIDE_SPD   := 160.0   # edge-slide speed (px/s)
const P2_ORB_EDGE_MARGIN := 26.0    # orb centre sits this far from its edge (perpendicular lock)
const P2_ORB_RANGE_LO    := 0.33    # orbs slide only within 33%–66% of their edge length
const P2_ORB_RANGE_HI    := 0.66    # (bounce at these limits, normal reverse)
const P2_LASER_WIDTH     := 50.0    # fired beam width (px) — procedural beam scales off this
const P2_LASER_DMG       := 20      # damage per tick while the beam overlaps the ship
const P2_LASER_DMG_INT   := 0.5     # seconds between damage ticks (fair, not per-frame)
const P2_BLUE_LASER_COL  := Color(0.4, 0.7, 1.0, 1.0)    # blue glow (white core stays automatic)
const P2_TEAL_LASER_COL  := Color(0.4, 1.0, 0.85, 1.0)   # teal glow
# ── Move 2 — orbs dock on the head, head centres, then fires a rotating laser cross ──
# Docking slots as offsets from the head CENTRE (TUNE to the crystal-head sprite). The two
# slots sit symmetric on the lower-mid face; the docked orb orbits at head_center + offset.rotated(spin).
const M2_SLOT_BLUE_OFFSET := Vector2(-28.0, 10.0)   # left slot  → blue orb (fires the VERTICAL line)
const M2_SLOT_TEAL_OFFSET := Vector2( 28.0, 10.0)   # right slot → teal orb (fires the HORIZONTAL line)
const M2_APPROACH_T    := 0.7     # first rush blue→right-edge mid, teal→left-edge mid (eased)
const M2_DOCK_T        := 5.0     # orbs + head rush into place over this long (eased)
const M2_DOCK_SHOOT_INT:= 0.45    # 4-diagonal fire interval while rushing in (fire rate −40% from 0.27)
const M2_FIRE_STATIC_T := 1.0     # fire the cross stationary before spinning
const M2_SPIN_T        := 5.0     # seconds per full rotation (40% slower than the old 3s)
const M2_SPIN_SPEED    := TAU / M2_SPIN_T   # rad/s
const M2_SPIN_ROTATIONS:= 2.0     # full turns each spin direction (CCW then CW)
const M2_STOP_T        := 1.0     # pause between the CCW and CW spins (beams stay on)
# ── Move 3 — two orbs on a rigid 400px rainbow-lightning rope; they swing alternately ──
const M3_ROPE_LEN          := 200.0   # FIXED rope length — orbs are always this far apart
const M3_SETUP_OFFSET      := 100.0   # setup formation: blue this far LEFT of centre, teal RIGHT (→ 200 apart)
const M3_SETUP_MOVE_SPD    := 700.0   # speed the orbs fly to the centre formation (px/s)
const M3_ROPE_GROW_T       := 0.5     # rope grows 0 → 400px over this once both orbs are in place
const M3_SWING_DUR         := 1.2     # seconds for one orb to whirl around the pivot (swing speed −50%)
const M3_SWING_MIN_SWEEP   := 1.4     # rad (~80°); if the natural arc is smaller, go the LONG way so it whips
const M3_SWING_EASE        := 1.0     # 0 = linear, 1 = full accelerate-out / decelerate-in (smoothstep)
const M3_CHARGE_T          := 0.5     # charge time before detonation (fast)
const M3_TOTAL_BOMBS       := 10      # total explosions before the attack ends (orbs alternate)
# Rainbow-lightning rope visual (tunable look):
const M3_ROPE_SEGMENTS  := 16     # jagged segments along the rope
const M3_ROPE_JITTER    := 18.0   # perpendicular lightning jitter (px), re-randomised each frame
const M3_ROPE_HALO_W    := 14.0   # wide soft glow pass width
const M3_ROPE_MID_W     := 6.0    # brighter mid pass width
const M3_ROPE_CORE_W    := 2.5    # near-white hot core width
const M3_ROPE_HUE_SCROLL := 0.6   # how fast the rainbow hues flow along the rope (cycles/sec)
const M3_ROPE_SAT       := 0.9    # rope colour saturation (0 = white, 1 = full rainbow)
const M3_ROPE_DMG       := 5      # tether contact damage per tick
const M3_ROPE_DMG_INT   := 0.5    # seconds between tether damage ticks while the ship touches it
const M3_ROPE_DMG_W     := 22.0   # tether hit corridor half-width (px), added to the ship radius
const M3_BLAST_RADIUS      := 117.0   # AoE radius (dodge outside this) — 60% of the old 195
const M3_BLAST_DMG         := 45      # one-shot AoE damage if inside at detonation
const M3_CHANNEL_SCALE     := 3.0     # channel light-gather FX scaled up vs Move 1
const M3_CHANNEL_MOTE_MULT := 2.0     # twice as many motes
const M3_CHARGE_SPIN       := 18.0    # orb spin while charging (rad/s ≈ 2.9 rev/s — quite fast)
const M3_EXPLOSION_DUR     := 1.0     # move ends this long after the last blast (light portion)
const M3_AFTERMATH_DUR     := 2.0     # explosion NODE lifetime (light fades fast; smoke/debris linger)
# ── Detonation impact feel (visual/feel only — no damage/radius change) ──
const SHAKE_MAX_OFFSET := 16.0    # peak random shake offset (px) — scales with trauma²
const SHAKE_KICK       := 14.0    # one-time directional kick away from the blast (px)
const TRAUMA_DECAY     := 0.4     # seconds for trauma to fall 1 → 0
const ABERRATION_MAX   := 0.012   # peak RGB-split (screen-UV units)
const ABERRATION_T     := 0.2     # aberration fade time
const ABERRATION_LAYER := 149     # CanvasLayer for the RGB split (above the scene)
# How rainbow the explosion is: HSV saturation for the prismatic hues. 0 = white, 1 = full rainbow.
const M3_RAINBOW_SAT   := 0.9
# Rainbow recolour for every procedural attack FX (beams, channel motes, orb shine).
const RAINBOW_SPEED    := 0.5     # hue cycles per second
const M3_GLOW_RADIUS   := 26.0    # orb rainbow-shine glow radius (px)
const M3_GLOW_ALPHA    := 0.6     # orb rainbow-shine peak alpha
const ABERRATION_SHADER := "shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5, 0.5);
uniform float strength = 0.0;
void fragment() {
	vec2 d = SCREEN_UV - center;
	vec2 off = d * strength;          // split R out / B in, radially from the blast
	float r = texture(screen_tex, SCREEN_UV + off).r;
	float g = texture(screen_tex, SCREEN_UV).g;
	float b = texture(screen_tex, SCREEN_UV - off).b;
	COLOR = vec4(r, g, b, 1.0);
}
"

# Head bull-charge: the invincible head rushes the player, overshoots, stomps, re-aims, repeats.
const P2_BULL_SPD         := 520.0   # top charge speed (px/s)
const P2_BULL_ACCEL       := 2600.0  # ramp 0 → top speed (px/s^2)
const P2_BULL_DECEL_T     := 0.4     # slow-down "stomp" beat after a pass overshoots/exits
const P2_BULL_REAIM_PAUSE := 0.35    # telegraph pause before the next charge
const P2_BULL_DMG         := 30      # contact damage if the head reaches the ship mid-charge

const FINAL_HEAD_SPD  := 25.0
const FINAL_HEAD_RPM  := 20.0
const FINAL_ORB_RPM   := 40.0
const FINAL_ORB_SHOOT := 0.25
const PATROL_SPD      := 120.0

const SUB1_DUR     := 8.0
const SUB2_DUR     := 3.0
const SUB2_WAVE_INT := 0.5
const SUB2_BLT_HP  := 10
const SUB2_BLT_CNT := 10
const SUB3_DUR     := 5.0
const SUB3_RAND_INT := 0.25
const SUB3_ORB_INT  := 0.5

const BULLET_SPD     := 280.0
const ORB_BULLET_SPD := 250.0
const WAVE_SPD_MIN   := 100.0
const WAVE_SPD_MAX   := 150.0

enum Phase {
	IDLE,
	M1_CRAWL,
	M2_TRANSFORM, M2_MOVE, M2_SPIN, M2_RETURN,
	M3_CURL, M3_EJECT, M3_SPIRAL,
	M4_TRANSFORM, M4_MOVE, M4_SPIN, M4_CHARGE, M4_OFFSCREEN, M4_FINAL, M4_RETURN_CURVE, M4_RETURN,
	# Phase 2 — the new orb fight (replaces the old FINAL_SUB orb patrol). Only Attack 1 is
	# implemented; ATTACK2..5 are reserved for the upcoming attacks.
	P2_ENTRY, P2_ATTACK1, P2_ATTACK2, P2_ATTACK3, P2_ATTACK4, P2_ATTACK5,
	DONE
}

# Head bull-charge sub-state (Phase-2 Attack 1): charge → overshoot → slow → re-aim → repeat.
enum Bull { CHARGING, SLOWING, REAIM }

var _phase        := Phase.IDLE
var _phase_timer  := 0.0
var _move_watchdog := 0.0   # time spent in the current main-phase move (stall safety net)

var _objects_container: Control          = null
var _ship_eo:           EditableObjectNode = null
var _chromeleon_eo:     EditableObjectNode = null
var _chromeleonbody_eo: EditableObjectNode = null
var _chromehead_eo:     EditableObjectNode = null
var _chromeball_eo:     EditableObjectNode = null
var _blueorb_eo:        EditableObjectNode = null
var _tealorb_eo:        EditableObjectNode = null
var _ball_orig_local_pos: Vector2 = Vector2.ZERO

var _blueorb_hp:    int  = ORB_MAX_HP
var _tealorb_hp:    int  = ORB_MAX_HP
var _orbs_detached: bool = false
var _ball_detached: bool = false

var _main_fp_nodes: Array[Node2D] = []
var _ball_fp_nodes: Array[Node2D] = []
var _blue_fp_nodes: Array[Node2D] = []
var _teal_fp_nodes: Array[Node2D] = []
var _ball_fp_offset: Vector2 = Vector2.ZERO
var _blue_fp_offset: Vector2 = Vector2.ZERO
var _teal_fp_offset: Vector2 = Vector2.ZERO

var _clip_node: Control = null

var _assets_loaded:   bool  = false
var _bullet_frames:   Array = []
var _bullet_sizes:    Array = []   # Vector2 per chromebullet, matching _bullet_frames
var _bullet_native_sizes: Array = []  # native texture sizes for fallback
var _bullet_resized_frames: Array = []  # resized textures, cached per chromebullet
var _last_cb_idx:     int   = 0    # last random chromebullet index
var _ball_frames:     Array = []
var _ball_delays:     Array = []
var _body_frames:     Array = []
var _body_delays:     Array = []
var _blue_bullet_tex:  Texture2D = null
var _teal_bullet_tex:  Texture2D = null
var _blue_bullet_resized: Texture2D = null
var _teal_bullet_resized: Texture2D = null
var _blue_bullet_native_size: Vector2 = Vector2.ZERO
var _teal_bullet_native_size: Vector2 = Vector2.ZERO
var _blue_bullet_size: Vector2   = Vector2.ZERO
var _teal_bullet_size: Vector2   = Vector2.ZERO

var _projectiles:      Array = []
var _shielded_bullets: Array = []

# Body animation (chromeball gif forward/backward)
var _anim_tr:       TextureRect = null
var _anim_frames:   Array = []
var _anim_delays:   Array = []
var _anim_idx:      int   = 0
var _anim_acc:      float = 0.0
var _anim_backward: bool  = false
var _anim_hold:     bool  = false
var _anim_done:     bool  = false
var _anim_phase_timer: float = 0.0   # timeout guard for anim-waiting phases
signal anim_finished

# M1 state
var _m1_wp:           Vector2 = Vector2.ZERO
var _m1_shoot_acc:    float   = 0.0
var _m1_fp2_acc:      float   = 0.0
var _m1_fp2_pending:  bool    = false
var _m1_next_fp:      int     = 0    # which hand fires next (alternates 0/1 each interval)
var _m1_duration:     float   = 8.0

# Ball (M2/M4) state
var _ball_angle:   float = 0.0
var _spin_acc:     float = 0.0
var _m2_shoot_acc: float = 0.0

# M3 state
var _blue_shoot_acc:   float = 0.0
var _teal_shoot_acc:   float = 0.0
var _blue_eject_from:  Vector2 = Vector2.ZERO
var _blue_eject_to:    Vector2 = Vector2.ZERO
var _teal_eject_from:  Vector2 = Vector2.ZERO
var _teal_eject_to:    Vector2 = Vector2.ZERO
var _m3_spiral_center: Vector2 = Vector2.ZERO
var _m3_spiral_R:      float   = 0.0
var _m3_unfurling:     bool  = false

# M4 state
var _m4_charge_dir: Vector2 = Vector2.ZERO
var _m4_pass:           int = 0
var _m4_charge_spd:   float = 0.0
var _m4_offscreen_timer: float = 0.0
var _m4_exit_pos:    Vector2 = Vector2.ZERO
var _m4_exit_dir:    Vector2 = Vector2.ZERO
var _m4_was_inside:     bool = false
var _m4_hit_done:       bool = false

# Final state
var _head_wp:           Vector2 = Vector2.ZERO
var _head_rot:          float   = 0.0
var _teal_fin_angle:    float   = 0.0
var _blue_fin_angle:    float   = 0.0
var _teal_patrol_tgt:   int     = 0   # 0=WP_A, 1=WP_B
var _blue_patrol_tgt:   int     = 0
var _teal_fin_shoot:    float   = 0.0
var _blue_fin_shoot:    float   = 0.0
var _sub2_wave_acc:     float   = 0.0
var _sub3_rand_b:       float   = 0.0
var _sub3_rand_t:       float   = 0.0
var _sub3_orb_b:        float   = 0.0
var _sub3_orb_t:        float   = 0.0

# Phase 2 state
var _p2_attack:    int     = 1            # which Phase-2 attack the picker chose (only 1 exists)
# Attack-1 per-orb cycle: SLIDE → CHANNEL → FIRE (blue = right edge slides vertically,
# teal = top edge slides horizontally). Blue/teal run independently (own state + timers).
enum OrbState { SLIDE, CHANNEL, FIRE }
var _beam_fx:        Node = null          # LasgunBeam node (additive glow) owning both orb beams
var _blue_beam:      Dictionary = {}      # beam ctx (geometry/state) handed to _beam_fx
var _teal_beam:      Dictionary = {}
var _orb_glow_blue:  Node = null          # additive rainbow "shine" that follows each orb
var _orb_glow_teal:  Node = null
var _blue_orb_state: OrbState = OrbState.SLIDE
var _teal_orb_state: OrbState = OrbState.SLIDE
var _blue_orb_timer: float = 0.0
var _teal_orb_timer: float = 0.0
var _blue_slide_dir: float = 1.0           # +1 down / -1 up   (blue slides vertically)
var _teal_slide_dir: float = 1.0           # +1 right / -1 left (teal slides horizontally)
var _blue_fire_dir:  Vector2 = Vector2.DOWN  # aim locked at channel start (not tracked after)
var _teal_fire_dir:  Vector2 = Vector2.DOWN
var _blue_laser_dmg_acc: float = 0.0       # damage-tick accumulator during FIRE
var _teal_laser_dmg_acc: float = 0.0
var _blue_channel_fx: Node = null          # inward light-gather FX node (freed at fire start)
var _teal_channel_fx: Node = null
var _bull_state:   Bull    = Bull.CHARGING
var _bull_dir:     Vector2 = Vector2.ZERO
var _bull_spd:     float   = 0.0
var _bull_timer:   float   = 0.0
var _bull_hit_done: bool   = false
# Attack-2 (docked rotating laser cross): sub-phase machine + the 4 beam arms anchored at the head.
enum M2 { APPROACH, DOCK, CHANNEL, FIRE_STATIC, SPIN_CCW, STOP, SPIN_CW }
var _m2_state: M2    = M2.APPROACH
var _m2_timer: float = 0.0
var _m2_spin_from: float = 0.0   # _head_rot captured at a spin's start (to count full turns)
var _m2_appr_blue_from: Vector2 = Vector2.ZERO   # orb positions captured for the edge approach
var _m2_appr_teal_from: Vector2 = Vector2.ZERO
var _m2_beam_tl: Dictionary = {}   # teal LEFT arm
var _m2_beam_tr: Dictionary = {}   # teal RIGHT arm  (TL+TR = full horizontal line)
var _m2_beam_bu: Dictionary = {}   # blue UP arm
var _m2_beam_bd: Dictionary = {}   # blue DOWN arm   (BU+BD = full vertical line)
var _m2_dock_head_from: Vector2 = Vector2.ZERO   # rush start positions (lerp targets are computed)
var _m2_dock_blue_from: Vector2 = Vector2.ZERO
var _m2_dock_teal_from: Vector2 = Vector2.ZERO
var _m2_dock_shoot: float = 0.0    # fire accumulator while rushing in
# Attack-3 (staggered orb bombs). Two-element arrays indexed [first, second] = firing order.
enum Bomb { IDLE, ZOOM, CHARGE, DONE }
var _m3_eo:    Array = []                       # [first orb, second orb] EOs
var _m3_which: Array = []                       # ["blue"/"teal", ...] for hp lookup
var _m3_col:   Array = []                       # [Color, Color]
var _m3_state: Array = [Bomb.IDLE, Bomb.IDLE]
var _m3_timer: Array = [0.0, 0.0]
var _m3_lock:  Array = [Vector2.ZERO, Vector2.ZERO]   # locked blast points
# Rope-swing state (per orb): whirl around a captured pivot toward a captured target.
var _m3_pivot:   Array = [Vector2.ZERO, Vector2.ZERO]  # pivot point (the planted partner)
var _m3_swing_t: Array = [0.0, 0.0]                    # 0..1 swing progress
var _m3_th0:     Array = [0.0, 0.0]                    # start angle around the pivot
var _m3_dtheta:  Array = [0.0, 0.0]                    # signed total angle to sweep
var _m3_fx:    Array = [null, null]                    # channel FX nodes
var _m3_in_setup: bool  = false                        # Stage 1: orbs flying to centre + rope growing
var _m3_setup_t:  float = 0.0                          # rope-grow timer (after both orbs in place)
var _m3_rope:     Node  = null                          # rainbow-lightning rope FX node
var _m3_rope_dmg_acc: float = 0.0                       # tether contact-damage tick accumulator
var _m3_launched: int = 0                       # bombs that have begun zooming (cap = M3_TOTAL_BOMBS)
var _m3_exploded: int = 0                       # detonations done (attack ends at M3_TOTAL_BOMBS)
var _m3_fx_t:     float = 0.0                   # explosion-FX countdown after the last detonation
# Detonation impact: trauma-based shake + directional kick on the shared _objects_container.
var _shaking:      bool    = false
var _trauma:       float   = 0.0       # 0..1; set to 1 on a blast, decays over TRAUMA_DECAY
var _kick:         Vector2 = Vector2.ZERO   # one-time directional shove (decays with trauma)
var _shake_origin: Vector2 = Vector2.ZERO
var _aberration_shader: Shader = null  # lazily built from ABERRATION_SHADER

# =============================================================================
# Setup
# =============================================================================

func setup(oc: Control) -> void:
	_objects_container = oc
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	process_mode = Node.PROCESS_MODE_PAUSABLE

	var clip := Control.new()
	clip.position      = OC_BOUNDS.position
	clip.size          = OC_BOUNDS.size
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	clip.z_index       = 0
	clip.z_as_relative = false
	add_child(clip)
	_clip_node = clip

	_find_eos()
	_load_fp_offsets()
	_cache_fp_offsets()
	# _load_assets() is deferred to first spawn_boss() to avoid startup lag
	# Boss-killed routing is handled by the Boss Manager (boss_fight.gd), the single listener.

# Called by the Boss Manager when GameManager.boss_killed fires (was a direct signal connection).
func notify_boss_killed() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	# Already in Phase 2 — the HP bar is the orb pool (and head-block hits also call
	# take_boss_damage), so ignore the global signal; the real win is _check_orb_win().
	match _phase:
		Phase.P2_ENTRY, Phase.P2_ATTACK1, Phase.P2_ATTACK2, Phase.P2_ATTACK3, Phase.P2_ATTACK4, Phase.P2_ATTACK5:
			return
	# M1-M4: player depleted the body HP → transition to Phase 2 (the boss does NOT die yet).
	_begin_phase2_transition()

func _force_reset() -> void:
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	_cleanup_orb_beams()
	_reattach_orbs()
	_reattach_head()
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_orbs_detached = false
	_ball_detached = false
	var ws := _get_ws()
	if ws != null:
		ws.clear_extra_targets()
		ws.clear_multi_hit_provider()

# =============================================================================
# Public API
# =============================================================================

func spawn_boss() -> void:
	if _chromeleon_eo == null or not is_instance_valid(_chromeleon_eo):
		return
	if _phase != Phase.IDLE and _phase != Phase.DONE:
		return
	if not _assets_loaded:
		_load_assets()
		_assets_loaded = true
	_reload_bullet_sizes()
	GameManager.boss_max_hp = BOSS_MAX_HP
	GameManager.boss_hp     = BOSS_MAX_HP
	GameManager.boss_hp_changed.emit(BOSS_MAX_HP)
	GameManager.boss_spawned.emit()
	if not GameManager.manual_boost:
		GameManager.set_boost(true)
	_start_fight()

func kill_boss() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	_cleanup_orb_beams()
	_reattach_orbs()
	_reattach_head()
	_reattach_ball()
	_show_only(null)
	_phase = Phase.IDLE
	_phase_timer = 0.0
	var ws := _get_ws()
	if ws != null:
		ws.clear_extra_targets()
		ws.clear_multi_hit_provider()
	GameManager.boss_hp     = 0
	GameManager.boss_max_hp = 0
	GameManager.boss_killed.emit()

func get_intro_eo() -> EditableObjectNode:
	return _chromeleon_eo

func get_boss_hit_rect() -> Rect2:
	# Main phase: body takes damage. Final phase: chromehead takes damage (via direct hits).
	var eo: EditableObjectNode
	match _phase:
		Phase.P2_ENTRY, Phase.P2_ATTACK1, Phase.P2_ATTACK2, Phase.P2_ATTACK3, Phase.P2_ATTACK4, Phase.P2_ATTACK5:
			# Phase 2: the head is the (invincible) blocker — return its hitbox so bullets stop on it.
			eo = _chromehead_eo
		_:
			# M1-M4: return main body hitbox
			eo = _active_body()

	if eo == null or not is_instance_valid(eo) or not eo.visible:
		return Rect2()
	var tr: TextureRect = eo.texture_rect
	if tr == null:
		return Rect2(eo.global_position, eo.size)
	var sz := tr.size
	var xf := tr.get_global_transform()
	var p0 := xf * Vector2(0.0, 0.0); var p1 := xf * Vector2(sz.x, 0.0)
	var p2 := xf * Vector2(0.0, sz.y); var p3 := xf * Vector2(sz.x, sz.y)
	var mn := Vector2(minf(minf(p0.x,p1.x),minf(p2.x,p3.x)), minf(minf(p0.y,p1.y),minf(p2.y,p3.y)))
	var mx := Vector2(maxf(maxf(p0.x,p1.x),maxf(p2.x,p3.x)), maxf(maxf(p0.y,p1.y),maxf(p2.y,p3.y)))
	return Rect2(mn, mx - mn)

## Let an external defender (Swarm Host bats) destroy the nearest in-flight boss
## projectile within `radius` of `center`. Projectiles live in _clip_node-local space,
## which shares the StreamScreen origin (270,8) with weapon_system-local — so the bat's
## own local position can be passed straight in. Returns {"hit":bool, "pos":Vector2}.
func consume_projectile_near(center: Vector2, radius: float) -> Dictionary:
	var best: int = -1
	var best_d: float = INF
	var best_pos := Vector2.ZERO
	for i in range(_projectiles.size()):
		var p: Dictionary = _projectiles[i]
		var tr: TextureRect = p.get("tr")
		if tr == null or not is_instance_valid(tr):
			continue
		var pc: Vector2 = tr.position + tr.size * 0.5
		var pr: float = maxf(tr.size.x, tr.size.y) * 0.5
		var d: float = pc.distance_to(center)
		if d <= radius + pr and d < best_d:
			best_d = d; best = i; best_pos = pc
	if best < 0:
		return {"hit": false, "pos": Vector2.ZERO}
	var bp: Dictionary = _projectiles[best]
	var btr: TextureRect = bp.get("tr")
	if btr != null and is_instance_valid(btr):
		btr.queue_free()
	_projectiles.remove_at(best)
	return {"hit": true, "pos": best_pos}

func flash_boss_hit() -> void:
	var eo := _active_body()
	if eo == null or not is_instance_valid(eo):
		return
	var tw := create_tween()
	tw.tween_property(eo, "modulate", Color(2.0, 0.5, 0.5, 1.0), 0.04)
	tw.tween_property(eo, "modulate", Color.WHITE, 0.15)

func _start_fight() -> void:
	_reattach_orbs()
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_blueorb_hp   = ORB_MAX_HP
	_tealorb_hp   = ORB_MAX_HP
	_head_rot     = 0.0
	_setup_pivots()
	if DEBUG_START_IN_PHASE2:
		_enter_phase2()      # TEST: skip Phase 1, go straight to the orb fight
	else:
		_begin_random_move()

func _setup_pivots() -> void:
	for eo: EditableObjectNode in [_chromeleonbody_eo, _chromehead_eo, _chromeball_eo, _blueorb_eo, _tealorb_eo]:
		if is_instance_valid(eo) and eo.texture_rect != null:
			eo.texture_rect.pivot_offset = eo.texture_rect.size / 2.0

# =============================================================================
# Move dispatch
# =============================================================================

func _begin_random_move() -> void:
	_move_watchdog = 0.0   # fresh move → reset the stall safety net
	match DEBUG_FORCE_MOVE:
		1: _begin_m1()
		2: _begin_m2()
		3: _begin_m3()
		4: _begin_m4()
		_:
			match randi() % 4:
				0: _begin_m1()
				1: _begin_m2()
				2: _begin_m3()
				_: _begin_m4()

func _check_hp_or_next() -> void:
	if GameManager.boss_hp <= 0:
		_begin_phase2_transition()
	else:
		_begin_random_move()

# Watchdog recovery: a main-phase move hung past MOVE_HARD_CAP. Reset every transient
# form/orb/clone state back to the idle cluster and start a fresh move so the boss can
# never stay stuck "spinning in place doing nothing".
func _recover_stuck_move() -> void:
	_reattach_orbs()
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_move_watchdog = 0.0
	_check_hp_or_next()

# =============================================================================
# Move 1 — Crawl + Shoot
# =============================================================================

func _begin_m1() -> void:
	_phase = Phase.M1_CRAWL
	_phase_timer  = 0.0
	_m1_shoot_acc = 0.0
	_m1_next_fp   = 0   # start with the left hand
	_m1_duration  = randf_range(M1_MIN_DUR, M1_MAX_DUR)
	_show_only(_chromeleon_eo)

func _tick_m1(delta: float) -> void:
	_phase_timer  += delta
	_m1_shoot_acc += delta

	# Player too close to the boss BODY → bail out of Move 1 and charge them (Move 4).
	# Measure distance to the body rect's nearest edge (not its centre — the boss is tall,
	# so a centre-based check never fired when the ship was right under it).
	if is_instance_valid(_chromeleon_eo):
		var br := get_boss_hit_rect()
		var sc := _ship_center()
		if br.has_area():
			var near := Vector2(clampf(sc.x, br.position.x, br.end.x), clampf(sc.y, br.position.y, br.end.y))
			if sc.distance_to(near) <= M1_PANIC_RANGE:
				_move_watchdog = 0.0
				_begin_m4()
				return

	# Position directly in front of (above) the player — track their X, keep current Y.
	if is_instance_valid(_chromeleon_eo):
		var target_x := _ship_center().x - _chromeleon_eo.size.x * 0.5
		var diff_x := target_x - _chromeleon_eo.position.x
		var step := M1_SPEED * delta
		if absf(diff_x) <= step:
			_chromeleon_eo.position.x = target_x
		else:
			_chromeleon_eo.position.x += signf(diff_x) * step
		_clamp_eo(_chromeleon_eo, Y_LIMIT)

	# Alternate hands: left fire, interval, right fire, interval, ...
	if _m1_shoot_acc >= M1_SHOOT_INT:
		_m1_shoot_acc = 0.0
		_fire_m1_spread(_m1_next_fp)
		_m1_next_fp = 1 - _m1_next_fp

	if _phase_timer >= _m1_duration:
		_check_hp_or_next()

func _fire_m1_spread(fp_idx: int) -> void:
	if _main_fp_nodes.size() <= fp_idx:
		return
	var fp := _main_fp_nodes[fp_idx]
	if not is_instance_valid(fp):
		return
	var origin := fp.global_position
	var tex := _random_bullet()
	var bsz  := _random_bullet_sz()
	for a: float in [-30.0, -15.0, 0.0, 15.0, 30.0]:   # 5-shot fan (was 3)
		var dir := Vector2.DOWN.rotated(deg_to_rad(a))
		_spawn_bullet(tex, origin, dir * BULLET_SPD, bsz)

# =============================================================================
# Move 2 — Ball spin + shoot 4 dirs
# =============================================================================

func _begin_m2() -> void:
	_phase = Phase.M2_TRANSFORM
	_phase_timer  = 0.0
	_ball_angle   = 0.0
	_spin_acc     = 0.0
	_m2_shoot_acc = 0.0
	_anim_phase_timer = 0.0
	_detach_ball()
	_show_only(null)
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.gif_paused = true   # pause before visible so no rogue GIF frame shows
		_chromeball_eo.reset_gif()
		_chromeball_eo.texture_rect.pivot_offset = _chromeball_eo.texture_rect.size / 2.0
		_chromeball_eo.visible = true
		if not _ball_frames.is_empty():
			_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, false, true)
			anim_finished.connect(_on_m2_transform_done, CONNECT_ONE_SHOT)
		else:
			_on_m2_transform_done()

func _on_m2_transform_done() -> void:
	if _phase != Phase.M2_TRANSFORM:
		return
	_phase = Phase.M2_MOVE

# Rotate the ball and fly it toward `target`; return true once it arrives. Single
# source of truth for both ball moves so the "rotate but never translate" stall
# (which spun the boss in place forever) cannot exist in two divergent copies.
func _ball_travel(target: Vector2, spd: float, rpm: float, delta: float) -> bool:
	_ball_angle += rpm * TAU / 60.0 * delta
	if not is_instance_valid(_chromeball_eo):
		return false
	_chromeball_eo.texture_rect.rotation = _ball_angle
	var diff := target - _chromeball_eo.position
	if diff.length() < spd * delta + 3.0:
		_chromeball_eo.position = target
		return true
	_chromeball_eo.position += diff.normalized() * spd * delta
	return false

func _tick_m2_move(delta: float) -> void:
	_phase_timer += delta
	if is_instance_valid(_chromeball_eo) \
			and _ball_travel(BALL_SPIN_POS - _chromeball_eo.size / 2.0, M2_MOVE_SPD, M2_MOVE_RPM, delta):
		_phase    = Phase.M2_SPIN
		_spin_acc = 0.0

func _tick_m2_spin(delta: float) -> void:
	_phase_timer  += delta
	_spin_acc     += delta
	_m2_shoot_acc += delta
	var t: float   = minf(_spin_acc / M2_SPINUP_T, 1.0)
	var rpm: float = lerpf(M2_MOVE_RPM, M2_SPIN_RPM, t)
	_ball_angle += rpm * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	if _m2_shoot_acc >= M2_SHOOT_INT:
		_m2_shoot_acc = 0.0
		_fire_ball_4dirs()
	if _spin_acc >= M2_SPIN_DUR:
		_begin_m2_return()

func _begin_m2_return() -> void:
	_phase = Phase.M2_RETURN
	_anim_phase_timer = 0.0
	if is_instance_valid(_chromeball_eo) and not _ball_frames.is_empty():
		_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, true, true)
		anim_finished.connect(_on_m2_return_done, CONNECT_ONE_SHOT)
	else:
		_on_m2_return_done()

func _on_m2_return_done() -> void:
	if _phase != Phase.M2_RETURN:
		return
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_check_hp_or_next()

# =============================================================================
# Move 3 — Orb detach
# =============================================================================

# Physical cm → px via monitor DPI (best-effort; 96 fallback). Mirrors weapon_system._cm_to_px.
func _cm_px(cm: float) -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)

# Helper: world centre of the curled ball (objects-container-local space).
func _ball_center_local() -> Vector2:
	if not is_instance_valid(_chromeball_eo):
		return Vector2.ZERO
	return _chromeball_eo.position + _chromeball_eo.size * 0.5

func _pin_orb_to_ball(orb: EditableObjectNode) -> void:
	if is_instance_valid(orb):
		orb.position = _ball_center_local() - orb.size * 0.5

# ── Stage 1: curl into the ball in place + orbs shine in ──────────────────────
func _begin_m3() -> void:
	_phase = Phase.M3_CURL
	_phase_timer = 0.0
	_ball_angle = 0.0
	_m3_unfurling = false
	_detach_ball()      # ball becomes the (in-place) body
	_detach_orbs()      # orbs become independent nodes
	_show_only(null)
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.gif_paused = true
		_chromeball_eo.reset_gif()
		_chromeball_eo.texture_rect.pivot_offset = _chromeball_eo.texture_rect.size / 2.0
		_chromeball_eo.visible = true
		if not _ball_frames.is_empty():
			_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, false, true)  # curl
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.visible  = true
			orb.modulate = Color.WHITE
			_pin_orb_to_ball(orb)

func _tick_m3_curl(delta: float) -> void:
	_phase_timer += delta
	_ball_angle += M3_CURL_RPM * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	var t: float = minf(_phase_timer / M3_CURL_T, 1.0)
	var g: float = lerpf(1.0, M3_ORB_GLOW_MAX, t)
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.modulate = Color(g, g, g, 1.0)
			_pin_orb_to_ball(orb)
	if _phase_timer >= M3_CURL_T:
		_begin_m3_eject()

# ── Stage 2: orbs fly out along the spin tangent, decelerating ────────────────
# ── Stage 2: orbs fly out to the two sides of the body (±M3_SIDE_CM) ──────────
func _begin_m3_eject() -> void:
	_phase = Phase.M3_EJECT
	_phase_timer = 0.0
	var c := _ball_center_local()
	var r := _cm_px(M3_SIDE_CM)
	if is_instance_valid(_blueorb_eo):
		_blue_eject_from = _blueorb_eo.position
		_blue_eject_to   = c + Vector2(r, 0.0) - _blueorb_eo.size * 0.5    # right
	if is_instance_valid(_tealorb_eo):
		_teal_eject_from = _tealorb_eo.position
		_teal_eject_to   = c + Vector2(-r, 0.0) - _tealorb_eo.size * 0.5   # left
	_blue_shoot_acc = 0.0
	_teal_shoot_acc = 0.0

func _tick_m3_eject(delta: float) -> void:
	_phase_timer += delta
	_ball_angle += M3_BODY_RPM * TAU / 60.0 * delta   # settle to slow idle spin
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	var t: float = minf(_phase_timer / M3_EJECT_T, 1.0)
	var e: float = 1.0 - (1.0 - t) * (1.0 - t)   # ease-out
	var g: float = lerpf(M3_ORB_GLOW_MAX, 1.0, t)
	if is_instance_valid(_blueorb_eo):
		_blueorb_eo.position = _blue_eject_from.lerp(_blue_eject_to, e)
		_blueorb_eo.modulate = Color(g, g, g, 1.0)
	if is_instance_valid(_tealorb_eo):
		_tealorb_eo.position = _teal_eject_from.lerp(_teal_eject_to, e)
		_tealorb_eo.modulate = Color(g, g, g, 1.0)
	if _phase_timer >= M3_EJECT_T:
		for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
			if is_instance_valid(orb):
				orb.modulate = Color.WHITE
		_begin_m3_spiral()

# ── Stage 3: orbs spiral back into the body (3 turns / M3_SPIRAL_T), firing ───
func _begin_m3_spiral() -> void:
	_phase = Phase.M3_SPIRAL
	_phase_timer = 0.0
	_m3_spiral_center = _ball_center_local()
	_m3_spiral_R = _cm_px(M3_SIDE_CM)
	_blue_shoot_acc = 0.0
	_teal_shoot_acc = 0.0

func _tick_m3_spiral(delta: float) -> void:
	if _m3_unfurling:
		return
	_phase_timer += delta
	_ball_angle += M3_BODY_RPM * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	var t: float = minf(_phase_timer / M3_SPIRAL_T, 1.0)
	var theta: float = t * M3_SPIRAL_TURNS * TAU
	var radius: float = _m3_spiral_R * (1.0 - t)
	var off := Vector2(cos(theta), sin(theta)) * radius
	if is_instance_valid(_blueorb_eo):
		_blueorb_eo.position = _m3_spiral_center + off - _blueorb_eo.size * 0.5
	if is_instance_valid(_tealorb_eo):
		_tealorb_eo.position = _m3_spiral_center - off - _tealorb_eo.size * 0.5
	# Fire while spiralling: blue = cardinal, teal = diagonal.
	_blue_shoot_acc += delta
	if _blue_shoot_acc >= M3_ORB_SHOOT:
		_blue_shoot_acc = 0.0
		_fire_orb_nsew(_blueorb_eo, _blue_fp_offset, 0.0,
			_blue_bullet_resized if _blue_bullet_resized != null else _blue_bullet_tex,
			[Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT], _blue_bullet_size)
	_teal_shoot_acc += delta
	if _teal_shoot_acc >= M3_ORB_SHOOT:
		_teal_shoot_acc = 0.0
		_fire_orb_nsew(_tealorb_eo, _teal_fp_offset, 0.0,
			_teal_bullet_resized if _teal_bullet_resized != null else _teal_bullet_tex,
			[Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
			 Vector2(-1, 1).normalized(), Vector2(1, 1).normalized()], _teal_bullet_size)
	if _phase_timer >= M3_SPIRAL_T:
		_finish_m3_recall()

func _finish_m3_recall() -> void:
	_reattach_orbs()
	_m3_unfurling = true
	if is_instance_valid(_chromeball_eo) and not _ball_frames.is_empty():
		_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, true, true)  # unfurl
		anim_finished.connect(_on_m3_unfurl_done, CONNECT_ONE_SHOT)
	else:
		_on_m3_unfurl_done()

func _on_m3_unfurl_done() -> void:
	_reattach_ball()
	_show_only(_chromeleon_eo)
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.modulate = Color.WHITE
	_check_hp_or_next()

# =============================================================================
# Move 4 — Ball charge at player
# =============================================================================

func _begin_m4() -> void:
	_phase = Phase.M4_TRANSFORM
	_phase_timer = 0.0
	_ball_angle  = 0.0
	_spin_acc    = 0.0
	_anim_phase_timer = 0.0
	_detach_ball()
	_show_only(null)
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.gif_paused = true   # pause before visible so no rogue GIF frame shows
		_chromeball_eo.reset_gif()
		_chromeball_eo.texture_rect.pivot_offset = _chromeball_eo.texture_rect.size / 2.0
		_chromeball_eo.visible = true
		if not _ball_frames.is_empty():
			_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, false, true)
			anim_finished.connect(_on_m4_transform_done, CONNECT_ONE_SHOT)
		else:
			_on_m4_transform_done()

func _on_m4_transform_done() -> void:
	if _phase != Phase.M4_TRANSFORM:
		return
	_phase    = Phase.M4_SPIN   # spin in place where it transformed (no fly-to-park)
	_spin_acc = 0.0
	_m4_pass  = 0

# Spin in place for M4_SPIN_DUR as a telegraph, then launch the first charge.
func _tick_m4_spin(delta: float) -> void:
	_phase_timer += delta
	_spin_acc    += delta
	_ball_angle  += M4_CHARGE_RPM * TAU / 60.0 * delta
	if is_instance_valid(_chromeball_eo):
		_chromeball_eo.texture_rect.rotation = _ball_angle
	if _spin_acc >= M4_SPIN_DUR:
		_start_m4_dash()

# Begin one charge pass. Pass 0 aims at the player and accelerates from rest;
# later passes re-enter from the exit point and charge back across at max speed.
func _start_m4_dash() -> void:
	if not is_instance_valid(_chromeball_eo):
		_begin_m4_return_anim()
		return
	if _m4_pass == 0:
		# First charge: accelerate from where it transformed.
		_m4_charge_spd = 0.0
	else:
		# Re-enter from a point on the edge within ±90° of the exit direction. This
		# random angle ONLY varies WHERE it comes in — the charge itself still aims at
		# the player (set below).
		var entry_dir := _m4_exit_dir.rotated(randf_range(-PI / 2.0, PI / 2.0))
		_chromeball_eo.position = _offscreen_entry_point(entry_dir, M4_OVERSHOOT_MARGIN) - _chromeball_eo.size / 2.0
		_m4_charge_spd = M4_CHARGE_MAX
		_chromeball_eo.visible = true
	# The charge ALWAYS aims at the player.
	var ship_c := _ship_center()
	var ball_c := _chromeball_eo.global_position + _chromeball_eo.size / 2.0
	var d := ship_c - ball_c
	_m4_charge_dir = d.normalized() if d.length() > 0.01 else Vector2.DOWN
	_m4_was_inside = false
	_m4_hit_done   = false
	_phase = Phase.M4_CHARGE

# A point just outside the play-area edge in direction `dir` from the centre — used to
# vary where the ball re-enters before charging at the player.
func _offscreen_entry_point(dir: Vector2, margin: float) -> Vector2:
	var dn := dir.normalized()
	if dn == Vector2.ZERO:
		dn = Vector2.DOWN
	var c := OC_BOUNDS.get_center()
	var hw := OC_BOUNDS.size.x * 0.5
	var hh := OC_BOUNDS.size.y * 0.5
	var tx: float = hw / absf(dn.x) if absf(dn.x) > 0.0001 else INF
	var ty: float = hh / absf(dn.y) if absf(dn.y) > 0.0001 else INF
	return c + dn * (minf(tx, ty) + margin)

func _tick_m4_charge(delta: float) -> void:
	_phase_timer += delta
	if not is_instance_valid(_chromeball_eo):
		_begin_m4_return_anim()
		return
	_m4_charge_spd = minf(_m4_charge_spd + M4_CHARGE_ACCEL * delta, M4_CHARGE_MAX)
	_chromeball_eo.position += _m4_charge_dir * _m4_charge_spd * delta
	_ball_angle += M4_CHARGE_RPM * TAU / 60.0 * delta
	_chromeball_eo.texture_rect.rotation = _ball_angle

	var ball_c := _chromeball_eo.global_position + _chromeball_eo.size / 2.0

	# Collision vs the VISIBLE (scaled) ship — one hit per pass; the dash overshoots regardless.
	if not _m4_hit_done and _ship_eo != null and is_instance_valid(_ship_eo):
		var sc := _ship_eo.get_global_transform() * (_ship_eo.size * 0.5)
		var sr := _ship_eo.size.x * 0.5 * _ship_eo.scale.x
		var br := minf(_chromeball_eo.size.x, _chromeball_eo.size.y) * 0.5
		if ball_c.distance_to(sc) <= sr + br:
			GameManager.ship_take_damage(M4_HIT_DMG)
			_flash_ship_red()
			_m4_hit_done = true

	if OC_BOUNDS.has_point(ball_c):
		_m4_was_inside = true

	# Once it has crossed the map and fully overshot the edge, end this pass.
	if _m4_was_inside and not OC_BOUNDS.grow(M4_OVERSHOOT_MARGIN).has_point(ball_c):
		_m4_exit_pos = _chromeball_eo.position
		_m4_exit_dir = _m4_charge_dir
		_m4_pass += 1
		_chromeball_eo.visible = false   # hide off-screen so it never overlaps the side panels
		if _m4_pass >= M4_PASSES:
			_chromeball_eo.position = BALL_SPIN_POS - _chromeball_eo.size / 2.0
			_chromeball_eo.visible = true
			_begin_m4_return_anim()
		else:
			_m4_offscreen_timer = 0.0
			_phase = Phase.M4_OFFSCREEN

# Wait off-screen, then re-enter from the exit point and charge back across.
func _tick_m4_offscreen(delta: float) -> void:
	_phase_timer += delta
	_m4_offscreen_timer += delta
	if _m4_offscreen_timer >= M4_OFFSCREEN_T:
		# After 4 normal overshooting charges, the 5th is the finisher.
		if _m4_pass >= M4_PASSES - 1:
			_begin_m4_final()
		else:
			_start_m4_dash()

# 5th charge: enter from the player's side and glide UP to the ending position
# (middle-up), decelerating to a full stop within M4_FINAL_T, then play the unfolding
# (transform-back) animation there. Aims at both the player (it sweeps through the
# player on the way) and the ending spot (where it comes to rest).
func _begin_m4_final() -> void:
	_phase = Phase.M4_FINAL
	_m4_hit_done = false
	if not is_instance_valid(_chromeball_eo):
		_begin_m4_return_anim()
		return
	var ship_c := _ship_center()
	var entry_dir := ship_c - BALL_SPIN_POS   # from the ending spot toward the player
	if entry_dir.length() < 0.01:
		entry_dir = Vector2.DOWN
	_chromeball_eo.position = _offscreen_entry_point(entry_dir, M4_OVERSHOOT_MARGIN) - _chromeball_eo.size / 2.0
	_chromeball_eo.visible = true
	var target := BALL_SPIN_POS - _chromeball_eo.size / 2.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_chromeball_eo, "position", target, M4_FINAL_T)
	tw.tween_callback(func() -> void: _begin_m4_return_anim())

func _tick_m4_final(delta: float) -> void:
	_phase_timer += delta
	if not is_instance_valid(_chromeball_eo):
		return
	_ball_angle += M4_CHARGE_RPM * TAU / 60.0 * delta
	_chromeball_eo.texture_rect.rotation = _ball_angle
	# Still dangerous as it sweeps in — one hit vs the visible ship.
	if not _m4_hit_done and _ship_eo != null and is_instance_valid(_ship_eo):
		var ball_c := _chromeball_eo.global_position + _chromeball_eo.size / 2.0
		var sc := _ship_eo.get_global_transform() * (_ship_eo.size * 0.5)
		var sr := _ship_eo.size.x * 0.5 * _ship_eo.scale.x
		var br := minf(_chromeball_eo.size.x, _chromeball_eo.size.y) * 0.5
		if ball_c.distance_to(sc) <= sr + br:
			GameManager.ship_take_damage(M4_HIT_DMG)
			_flash_ship_red()
			_m4_hit_done = true

func _begin_m4_return_anim() -> void:
	_phase = Phase.M4_RETURN
	_anim_phase_timer = 0.0
	if is_instance_valid(_chromeball_eo) and not _ball_frames.is_empty():
		_play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, true, true)
		anim_finished.connect(_on_m4_return_done, CONNECT_ONE_SHOT)
	else:
		_on_m4_return_done()

func _on_m4_return_done() -> void:
	if _phase != Phase.M4_RETURN:
		return
	_reattach_ball()
	_show_only(_chromeleon_eo)
	_check_hp_or_next()

# =============================================================================
# Phase 2 — orb fight (triggered when Phase-1 HP = 0)
# =============================================================================

# Phase-1 end (body HP hit 0): play the death cutscene in TRANSITION mode (boss does NOT die),
# then enter Phase 2. Input stays locked through the FX and unlocks when Phase 2 begins.
func _begin_phase2_transition() -> void:
	_phase = Phase.P2_ENTRY   # block move ticks / re-entry while the cutscene plays
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	GameManager.input_locked = true
	var body := _active_body()
	var mgr := get_tree().get_first_node_in_group("boss_fight")
	if mgr != null and mgr.has_method("play_death_cutscene") and body != null:
		await mgr.play_death_cutscene([body], false)   # is_final = false → TRANSITION
	_enter_phase2()
	GameManager.input_locked = false

# Phase-2 setup. Head = invincible blocker (reuses get_boss_hit_rect → head). Orbs = the
# 1000-HP damage targets. HP bar = combined orb pool. Reused by the debug start + transition.
func _enter_phase2() -> void:
	_phase = Phase.P2_ENTRY
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	_blueorb_hp = ORB_MAX_HP
	_tealorb_hp = ORB_MAX_HP
	GameManager.boss_max_hp = ORB_MAX_HP * 2
	GameManager.boss_hp     = ORB_MAX_HP * 2
	GameManager.boss_hp_changed.emit(GameManager.boss_hp)

	# Head: detached so it stays visible + can move while the cluster is hidden.
	_show_only(null)
	_detach_head()
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.visible = true
		_chromehead_eo.position = BALL_SPIN_POS - _chromehead_eo.size * 0.5
	# Orbs: detached, visible, registered as the player's damage targets.
	_detach_orbs()
	if is_instance_valid(_blueorb_eo):
		_blueorb_eo.visible = true
		_blueorb_eo.position = BLUE_WP_A - _blueorb_eo.size * 0.5
	if is_instance_valid(_tealorb_eo):
		_tealorb_eo.visible = true
		_tealorb_eo.position = TEAL_WP_A - _tealorb_eo.size * 0.5
	_register_orb_targets()
	_head_rot = 0.0

	# HP hitting 0 in Phase 1 fired the GLOBAL boss_killed/boss_defeated signals, whose other
	# listeners think the boss died — re-assert "boss active" so asteroids stay stopped, the HP
	# bar (now the orb pool) stays up, and boost stays on.
	GameManager.boss_spawned.emit()
	if not GameManager.manual_boost:
		GameManager.set_boost(true)

	_begin_p2_attack()

# Phase-2 attack picker. Only Attack 1 exists for now; it always returns Attack 1.
# TODO(phase2): when Attacks 2-5 are implemented, choose randomly / in a cycle here.
func _begin_p2_attack() -> void:
	# Moves 1-3 exist; DEBUG_FORCE_ATTACK forces one for testing.
	match DEBUG_FORCE_ATTACK:
		3: _p2_attack = 3; _begin_p2_attack3()
		2: _p2_attack = 2; _begin_p2_attack2()
		_: _p2_attack = 1; _begin_p2_attack1()

# ── Attack 1 — "Bull charge + edge-sliding alignment lasers" ─────────────────
func _begin_p2_attack1() -> void:
	_phase = Phase.P2_ATTACK1
	_phase_timer = 0.0
	_blue_slide_dir = 1.0
	_teal_slide_dir = 1.0
	_blue_orb_state = OrbState.SLIDE;  _teal_orb_state = OrbState.SLIDE
	_blue_orb_timer = 0.0;             _teal_orb_timer = 0.0
	_blue_laser_dmg_acc = 0.0;         _teal_laser_dmg_acc = 0.0
	# Snap the orbs onto their edges (perpendicular lock) and into the middle of their slide
	# band (avoids a first-frame jump); clear any spin so the laser reads as a fixed emitter.
	var mid := (P2_ORB_RANGE_LO + P2_ORB_RANGE_HI) * 0.5
	if is_instance_valid(_blueorb_eo):
		_blueorb_eo.texture_rect.rotation = 0.0
		_blueorb_eo.position.x = (OC_BOUNDS.end.x - P2_ORB_EDGE_MARGIN) - _blueorb_eo.size.x * 0.5
		_blueorb_eo.position.y = (OC_BOUNDS.position.y + OC_BOUNDS.size.y * mid) - _blueorb_eo.size.y * 0.5
	if is_instance_valid(_tealorb_eo):
		_tealorb_eo.texture_rect.rotation = 0.0
		_tealorb_eo.position.y = (OC_BOUNDS.position.y + P2_ORB_EDGE_MARGIN) - _tealorb_eo.size.y * 0.5
		_tealorb_eo.position.x = (OC_BOUNDS.position.x + OC_BOUNDS.size.x * mid) - _tealorb_eo.size.x * 0.5
	_ensure_orb_beams()
	_begin_bull_charge()

func _tick_p2_attack1(delta: float) -> void:
	_phase_timer += delta
	if not _blue_beam.is_empty(): _blue_beam["beam_color"] = _rainbow(0.0)   # rainbow lasers
	if not _teal_beam.is_empty(): _teal_beam["beam_color"] = _rainbow(0.5)
	_tick_orb_blue(delta)   # right edge, vertical slide → channel → fire straight LEFT (perpendicular)
	_tick_orb_teal(delta)   # top edge, horizontal slide → channel → fire straight DOWN (perpendicular)
	_tick_bull(delta)       # invincible head bull-rushes the player (unchanged)
	_check_orb_win()        # both orbs dead → FINAL death cutscene + victory
	queue_redraw()          # keep the channel warning sign(s) drawn/cleared each frame

# ── Blue orb (right edge) — SLIDE 2s → CHANNEL 1s → FIRE 3s → repeat ──────────
func _tick_orb_blue(delta: float) -> void:
	if not is_instance_valid(_blueorb_eo) or _blueorb_hp <= 0:
		_deactivate_beam(_blue_beam)
		return
	# Lock to the right edge at all times.
	_blueorb_eo.position.x = (OC_BOUNDS.end.x - P2_ORB_EDGE_MARGIN) - _blueorb_eo.size.x * 0.5
	_blue_orb_timer += delta
	match _blue_orb_state:
		OrbState.SLIDE:
			var cy := _blueorb_eo.position.y + _blueorb_eo.size.y * 0.5 + _blue_slide_dir * P2_ORB_SLIDE_SPD * delta
			var y_lo := OC_BOUNDS.position.y + OC_BOUNDS.size.y * P2_ORB_RANGE_LO
			var y_hi := OC_BOUNDS.position.y + OC_BOUNDS.size.y * P2_ORB_RANGE_HI
			if cy <= y_lo:   cy = y_lo; _blue_slide_dir = 1.0
			elif cy >= y_hi: cy = y_hi; _blue_slide_dir = -1.0
			_blueorb_eo.position.y = cy - _blueorb_eo.size.y * 0.5
			if _blue_orb_timer >= P2_ORB_SLIDE_T:
				_blue_fire_dir = Vector2.LEFT   # straight into the arena, perpendicular to the right edge
				_blue_channel_fx = _spawn_orb_channel_fx(_orb_center_vp(_blueorb_eo), P2_BLUE_LASER_COL)
				_blue_orb_state = OrbState.CHANNEL;  _blue_orb_timer = 0.0
		OrbState.CHANNEL:
			if _blue_orb_timer >= P2_ORB_CHANNEL_T:
				_free_node(_blue_channel_fx);  _blue_channel_fx = null
				_blue_laser_dmg_acc = 0.0
				_blue_orb_state = OrbState.FIRE;  _blue_orb_timer = 0.0
		OrbState.FIRE:
			var hit := _beam_hits_ship(_orb_center_vp(_blueorb_eo), _blue_fire_dir, OC_BOUNDS.size.length(), P2_LASER_WIDTH)
			_set_orb_beam(_blue_beam, _orb_center_vp(_blueorb_eo), _blue_fire_dir, true, hit)
			_blue_laser_dmg_acc = _accrue_beam_dmg(_blue_laser_dmg_acc, hit, delta)
			if _blue_orb_timer >= P2_ORB_FIRE_T:
				_deactivate_beam(_blue_beam)   # let lingering particles/debris finish on their own
				_blue_orb_state = OrbState.SLIDE;  _blue_orb_timer = 0.0

# ── Teal orb (top edge) — same cycle, slides horizontally ────────────────────
func _tick_orb_teal(delta: float) -> void:
	if not is_instance_valid(_tealorb_eo) or _tealorb_hp <= 0:
		_deactivate_beam(_teal_beam)
		return
	_tealorb_eo.position.y = (OC_BOUNDS.position.y + P2_ORB_EDGE_MARGIN) - _tealorb_eo.size.y * 0.5
	_teal_orb_timer += delta
	match _teal_orb_state:
		OrbState.SLIDE:
			var cx := _tealorb_eo.position.x + _tealorb_eo.size.x * 0.5 + _teal_slide_dir * P2_ORB_SLIDE_SPD * delta
			var x_lo := OC_BOUNDS.position.x + OC_BOUNDS.size.x * P2_ORB_RANGE_LO
			var x_hi := OC_BOUNDS.position.x + OC_BOUNDS.size.x * P2_ORB_RANGE_HI
			if cx <= x_lo:   cx = x_lo; _teal_slide_dir = 1.0
			elif cx >= x_hi: cx = x_hi; _teal_slide_dir = -1.0
			_tealorb_eo.position.x = cx - _tealorb_eo.size.x * 0.5
			if _teal_orb_timer >= P2_ORB_SLIDE_T:
				_teal_fire_dir = Vector2.DOWN   # straight into the arena, perpendicular to the top edge
				_teal_channel_fx = _spawn_orb_channel_fx(_orb_center_vp(_tealorb_eo), P2_TEAL_LASER_COL)
				_teal_orb_state = OrbState.CHANNEL;  _teal_orb_timer = 0.0
		OrbState.CHANNEL:
			if _teal_orb_timer >= P2_ORB_CHANNEL_T:
				_free_node(_teal_channel_fx);  _teal_channel_fx = null
				_teal_laser_dmg_acc = 0.0
				_teal_orb_state = OrbState.FIRE;  _teal_orb_timer = 0.0
		OrbState.FIRE:
			var hit := _beam_hits_ship(_orb_center_vp(_tealorb_eo), _teal_fire_dir, OC_BOUNDS.size.length(), P2_LASER_WIDTH)
			_set_orb_beam(_teal_beam, _orb_center_vp(_tealorb_eo), _teal_fire_dir, true, hit)
			_teal_laser_dmg_acc = _accrue_beam_dmg(_teal_laser_dmg_acc, hit, delta)
			if _teal_orb_timer >= P2_ORB_FIRE_T:
				_deactivate_beam(_teal_beam)
				_teal_orb_state = OrbState.SLIDE;  _teal_orb_timer = 0.0

# ── Shared orb-laser helpers ─────────────────────────────────────────────────
func _orb_center_vp(orb: EditableObjectNode) -> Vector2:
	return orb.global_position + orb.size * 0.5

# A full-saturation hue that cycles over time; `offset` shifts the phase per element so several
# elements show different rainbow colours at once. Used to recolour every procedural attack FX.
func _rainbow(offset: float) -> Color:
	return Color.from_hsv(fposmod(_phase_timer * RAINBOW_SPEED + offset, 1.0), M3_RAINBOW_SAT, 1.0)

# Point the procedural Lasgun beam from `origin_vp` straight along `dir` to the arena edge.
# Works for any direction (Move-1 axis beams AND Move-2's rotating cross arms).
func _set_orb_beam(beam: Dictionary, origin_vp: Vector2, dir: Vector2, active: bool, hit: bool) -> void:
	if _beam_fx == null or not is_instance_valid(_beam_fx) or beam.is_empty():
		return
	var length := _arena_edge_len(origin_vp, dir)
	_beam_fx.set_beam(beam, origin_vp, origin_vp + dir * length, active, hit)

# Distance from `o` to the arena boundary along (unit) `dir` — keeps a beam inside the arena.
func _arena_edge_len(o: Vector2, dir: Vector2) -> float:
	var t := OC_BOUNDS.size.length()
	if dir.x > 0.0001:    t = minf(t, (OC_BOUNDS.end.x - o.x) / dir.x)
	elif dir.x < -0.0001: t = minf(t, (OC_BOUNDS.position.x - o.x) / dir.x)
	if dir.y > 0.0001:    t = minf(t, (OC_BOUNDS.end.y - o.y) / dir.y)
	elif dir.y < -0.0001: t = minf(t, (OC_BOUNDS.position.y - o.y) / dir.y)
	return t if t > 0.0 else OC_BOUNDS.size.length()

# Stop firing but keep the ctx (its lingering particles/debris finish on their own).
func _deactivate_beam(beam: Dictionary) -> void:
	if not beam.is_empty():
		beam["beam_active"] = false

# Damage on a fair interval while the beam overlaps the ship (hit precomputed). Returns the acc.
func _accrue_beam_dmg(dmg_acc: float, hit: bool, delta: float) -> float:
	if hit:
		dmg_acc += delta
		if dmg_acc >= P2_LASER_DMG_INT:
			dmg_acc -= P2_LASER_DMG_INT
			GameManager.ship_take_damage(P2_LASER_DMG)
			_flash_ship_red()
	else:
		dmg_acc = 0.0
	return dmg_acc

# Wide-beam hit test: ship within half-width (+ its radius) of the beam ray, along its length.
func _beam_hits_ship(origin_vp: Vector2, dir: Vector2, length: float, width: float) -> bool:
	var sr := _ship_rect_vp()
	if sr == Rect2():
		return false
	var ship_c := sr.position + sr.size * 0.5
	var to := ship_c - origin_vp
	var t := clampf(to.dot(dir), 0.0, length)        # dir is unit-length
	var closest := origin_vp + dir * t
	var ship_r := maxf(sr.size.x, sr.size.y) * 0.5
	return ship_c.distance_to(closest) <= width * 0.5 + ship_r

func _free_node(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

# Light-gather FX: glowing motes appear around the orb and spiral inward to the focus over the
# channel, shrinking + fading as they converge. Procedural (the _ChannelFX inner node draws it).
func _spawn_orb_channel_fx(center_vp: Vector2, color: Color, dur: float = P2_ORB_CHANNEL_T,
		scale: float = 1.0, mote_mult: float = 1.0) -> Node:
	var fx := _ChannelFX.new()
	fx.position     = center_vp - OC_BOUNDS.position   # clip-local
	fx.z_index      = 161
	fx.z_as_relative = false
	fx.setup(color, dur, scale, mote_mult)
	_clip_node.add_child(fx)
	return fx

# Lazily create the shared LasgunBeam node (additive glow, viewport space) + the two orb beams.
func _ensure_orb_beams() -> void:
	if _beam_fx == null or not is_instance_valid(_beam_fx):
		_beam_fx = LasgunBeamScript.new()
		add_child(_beam_fx)   # child of the chromeleon root → draws in viewport space (no clip)
		_blue_beam = _beam_fx.make_beam(P2_BLUE_LASER_COL, P2_LASER_WIDTH)
		_teal_beam = _beam_fx.make_beam(P2_TEAL_LASER_COL, P2_LASER_WIDTH)
		# Move-2 cross arms (4): teal horizontal pair + blue vertical pair.
		_m2_beam_tl = _beam_fx.make_beam(P2_TEAL_LASER_COL, P2_LASER_WIDTH)
		_m2_beam_tr = _beam_fx.make_beam(P2_TEAL_LASER_COL, P2_LASER_WIDTH)
		_m2_beam_bu = _beam_fx.make_beam(P2_BLUE_LASER_COL, P2_LASER_WIDTH)
		_m2_beam_bd = _beam_fx.make_beam(P2_BLUE_LASER_COL, P2_LASER_WIDTH)

func _cleanup_orb_beams() -> void:
	_free_node(_beam_fx);  _beam_fx = null
	_blue_beam = {};  _teal_beam = {}
	_m2_beam_tl = {};  _m2_beam_tr = {};  _m2_beam_bu = {};  _m2_beam_bd = {}
	_free_node(_blue_channel_fx);  _free_node(_teal_channel_fx)
	_blue_channel_fx = null;  _teal_channel_fx = null
	_free_node(_orb_glow_blue);  _free_node(_orb_glow_teal)
	_orb_glow_blue = null;  _orb_glow_teal = null

# ── Orb rainbow shine — an additive glow that follows each visible orb, cycling hue ──
func _update_orb_glow() -> void:
	if _clip_node == null or not is_instance_valid(_clip_node):
		return
	if _orb_glow_blue == null or not is_instance_valid(_orb_glow_blue):
		_orb_glow_blue = _make_orb_glow()
	if _orb_glow_teal == null or not is_instance_valid(_orb_glow_teal):
		_orb_glow_teal = _make_orb_glow()
	_set_one_orb_glow(_orb_glow_blue, _blueorb_eo, 0.0)
	_set_one_orb_glow(_orb_glow_teal, _tealorb_eo, 0.5)

func _make_orb_glow() -> Node:
	var g := _OrbGlow.new()
	g.z_index = 158               # just behind the orbs/beams; additive so it reads as light
	g.z_as_relative = false
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = m
	g.visible = false
	_clip_node.add_child(g)
	return g

func _set_one_orb_glow(glow: Node, orb: EditableObjectNode, hue_off: float) -> void:
	if glow == null or not is_instance_valid(glow):
		return
	if is_instance_valid(orb) and orb.visible:
		glow.position = _orb_center_vp(orb) - OC_BOUNDS.position   # clip-local
		glow.set_glow(_rainbow(hue_off), M3_GLOW_RADIUS, M3_GLOW_ALPHA)
		glow.visible = true
	else:
		glow.visible = false

# Soft additive halo (concentric circles) in a single colour — the chromeleon recolours it each
# frame via set_glow() so it shines rainbow.
class _OrbGlow extends Node2D:
	var _col := Color.WHITE
	var _rad := 26.0
	var _a := 0.6
	func set_glow(col: Color, rad: float, a: float) -> void:
		_col = col;  _rad = rad;  _a = a
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, _rad * 1.9, Color(_col.r, _col.g, _col.b, _a * 0.16))
		draw_circle(Vector2.ZERO, _rad * 1.1, Color(_col.r, _col.g, _col.b, _a * 0.4))
		draw_circle(Vector2.ZERO, _rad * 0.6, Color(_col.r, _col.g, _col.b, _a * 0.7))

# Elephant-style ⚠ warning sign during each orb's CHANNEL, placed along its locked fire dir.
func _draw() -> void:
	if _phase == Phase.P2_ATTACK1:
		if is_instance_valid(_blueorb_eo) and _blueorb_hp > 0 and _blue_orb_state == OrbState.CHANNEL:
			_draw_warn_sign(_orb_center_vp(_blueorb_eo) + _blue_fire_dir * 46.0 - global_position)
		if is_instance_valid(_tealorb_eo) and _tealorb_hp > 0 and _teal_orb_state == OrbState.CHANNEL:
			_draw_warn_sign(_orb_center_vp(_tealorb_eo) + _teal_fire_dir * 46.0 - global_position)
	elif _phase == Phase.P2_ATTACK2 and _m2_state == M2.CHANNEL:
		if _orb_alive(_blueorb_eo, _blueorb_hp):
			_draw_warn_sign(_orb_center_vp(_blueorb_eo) - global_position)
		if _orb_alive(_tealorb_eo, _tealorb_hp):
			_draw_warn_sign(_orb_center_vp(_tealorb_eo) - global_position)

# Copied from boss_elephant._draw_warning_sign (amber triangle + exclamation), slightly larger.
func _draw_warn_sign(c: Vector2, s: float = 20.0) -> void:
	var amber := Color(1.0, 0.78, 0.1)
	var dark  := Color(0.12, 0.09, 0.0)
	var p0 := c + Vector2(0.0, -s)            # top
	var p1 := c + Vector2(s * 0.9, s * 0.7)   # bottom-right
	var p2 := c + Vector2(-s * 0.9, s * 0.7)  # bottom-left
	draw_colored_polygon(PackedVector2Array([p0, p1, p2]), amber)
	draw_polyline(PackedVector2Array([p0, p1, p2, p0]), dark, 2.0)
	draw_line(c + Vector2(0.0, -s * 0.35), c + Vector2(0.0, s * 0.18), dark, 3.0)
	draw_circle(c + Vector2(0.0, s * 0.42), 2.0, dark)

# Inward light-gather FX node — glowing motes spiralling toward the orb's focus over `dur`.
class _ChannelFX extends Node2D:
	var _t := 0.0
	var _dur := 1.0
	var _col := Color.WHITE
	var _motes: Array = []   # [{ang, rad, spin, size, hue}]
	func setup(color: Color, dur: float, scale: float = 1.0, mote_mult: float = 1.0) -> void:
		_col = color
		_dur = maxf(dur, 0.01)
		var n: int = int(round(12.0 * mote_mult))
		for i in n:
			_motes.append({
				"ang":  randf() * TAU,
				"rad":  randf_range(80.0, 150.0) * scale,
				"spin": randf_range(2.5, 5.0) * (1.0 if randf() < 0.5 else -1.0),
				"size": randf_range(3.0, 6.0) * scale,
				"hue":  randf(),   # each mote its own rainbow hue (scrolls over time)
			})
	func _process(delta: float) -> void:
		_t += delta
		if _t >= _dur:
			queue_free()   # safety net (also freed explicitly at fire start)
			return
		queue_redraw()
	func _draw() -> void:
		var p: float = clampf(_t / _dur, 0.0, 1.0)
		for m in _motes:
			var ang: float = float(m["ang"]) + float(m["spin"]) * _t
			var rad: float = float(m["rad"]) * (1.0 - p)            # converge inward
			var pos := Vector2(cos(ang), sin(ang)) * rad
			var a: float = 1.0 - p                                  # fade as they reach the focus
			var sz: float = float(m["size"]) * (1.0 - 0.5 * p)
			var col := Color.from_hsv(fposmod(float(m["hue"]) + _t * 0.5, 1.0), 0.9, 1.0)  # rainbow
			draw_circle(pos, sz * 2.2, Color(col.r, col.g, col.b, a * 0.25))   # soft glow
			draw_circle(pos, sz, Color(col.r, col.g, col.b, a))               # core

# ── Head bull charge: CHARGING → (passed player / out of bounds) → SLOWING → REAIM → repeat ──
func _begin_bull_charge() -> void:
	var head_c := _head_center()
	var d := _ship_center() - head_c
	_bull_dir = d.normalized() if d.length() > 0.01 else Vector2.DOWN
	_bull_spd = 0.0
	_bull_hit_done = false
	_bull_state = Bull.CHARGING

func _tick_bull(delta: float) -> void:
	if not is_instance_valid(_chromehead_eo):
		return
	_head_rot += FINAL_HEAD_RPM * TAU / 60.0 * delta
	_chromehead_eo.texture_rect.rotation = _head_rot
	match _bull_state:
		Bull.CHARGING:
			_bull_spd = minf(_bull_spd + P2_BULL_ACCEL * delta, P2_BULL_SPD)
			_chromehead_eo.position += _bull_dir * _bull_spd * delta
			_bull_contact_check()
			var head_c := _head_center()
			# "Passed the player": the head→ship vector now points opposite the travel dir.
			var passed: bool = (_ship_center() - head_c).dot(_bull_dir) <= 0.0
			var out: bool = not OC_BOUNDS.has_point(head_c)
			_clamp_eo(_chromehead_eo, OC_BOUNDS.end.y)
			if passed or out:
				_bull_state = Bull.SLOWING
				_bull_timer = 0.0
		Bull.SLOWING:
			_bull_timer += delta
			var f: float = 1.0 - clampf(_bull_timer / P2_BULL_DECEL_T, 0.0, 1.0)
			_chromehead_eo.position += _bull_dir * (P2_BULL_SPD * f) * delta
			_clamp_eo(_chromehead_eo, OC_BOUNDS.end.y)
			if _bull_timer >= P2_BULL_DECEL_T:
				_bull_state = Bull.REAIM
				_bull_timer = 0.0
		Bull.REAIM:
			_bull_timer += delta   # brief telegraph, then charge the player's CURRENT position
			if _bull_timer >= P2_BULL_REAIM_PAUSE:
				_begin_bull_charge()

# Contact damage if the charging head reaches the visible (scaled) ship — one hit per charge.
func _bull_contact_check() -> void:
	if _bull_hit_done or _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var sc := _ship_eo.get_global_transform() * (_ship_eo.size * 0.5)
	var sr := _ship_eo.size.x * 0.5 * _ship_eo.scale.x
	var hc := _head_center()
	var hr := minf(_chromehead_eo.size.x, _chromehead_eo.size.y) * 0.5
	if hc.distance_to(sc) <= sr + hr:
		GameManager.ship_take_damage(P2_BULL_DMG)
		_flash_ship_red()
		_bull_hit_done = true

# ── Attack 2 — "Docked rotating laser cross" ─────────────────────────────────
# DOCK → CHANNEL(1s) → FIRE_STATIC(1s) → SPIN_CCW(2s) → SPIN_CW(2s) → picker.
func _begin_p2_attack2() -> void:
	_phase = Phase.P2_ATTACK2
	_phase_timer = 0.0
	_m2_state = M2.APPROACH
	_m2_timer = 0.0
	_head_rot = 0.0
	_blue_laser_dmg_acc = 0.0
	_teal_laser_dmg_acc = 0.0
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.texture_rect.rotation = 0.0
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.texture_rect.rotation = 0.0
	# Capture each orb's start so the approach eases it to its side-edge midpoint.
	if is_instance_valid(_blueorb_eo): _m2_appr_blue_from = _blueorb_eo.position
	if is_instance_valid(_tealorb_eo): _m2_appr_teal_from = _tealorb_eo.position
	_ensure_orb_beams()   # also makes the 4 cross-arm beams

func _tick_p2_attack2(delta: float) -> void:
	_phase_timer += delta
	_m2_timer += delta
	# Rainbow laser cross — 4 arms each a different live hue.
	if not _m2_beam_tl.is_empty(): _m2_beam_tl["beam_color"] = _rainbow(0.0)
	if not _m2_beam_tr.is_empty(): _m2_beam_tr["beam_color"] = _rainbow(0.25)
	if not _m2_beam_bu.is_empty(): _m2_beam_bu["beam_color"] = _rainbow(0.5)
	if not _m2_beam_bd.is_empty(): _m2_beam_bd["beam_color"] = _rainbow(0.75)
	match _m2_state:
		M2.APPROACH:
			_tick_m2_approach(delta)
		M2.DOCK:
			_tick_m2_dock(delta)
		M2.CHANNEL:
			_tick_m2_channel(delta)
		M2.FIRE_STATIC:
			_tick_m2_cross(delta, 0.0)
			if _m2_timer >= M2_FIRE_STATIC_T:
				_m2_state = M2.SPIN_CCW;  _m2_timer = 0.0;  _m2_spin_from = _head_rot
		M2.SPIN_CCW:
			_tick_m2_cross(delta, -1.0)
			if absf(_head_rot - _m2_spin_from) >= M2_SPIN_ROTATIONS * TAU:
				_m2_state = M2.STOP;  _m2_timer = 0.0
		M2.STOP:
			_tick_m2_cross(delta, 0.0)   # beams stay on, no rotation
			if _m2_timer >= M2_STOP_T:
				_m2_state = M2.SPIN_CW;  _m2_timer = 0.0;  _m2_spin_from = _head_rot
		M2.SPIN_CW:
			_tick_m2_cross(delta, 1.0)
			if absf(_head_rot - _m2_spin_from) >= M2_SPIN_ROTATIONS * TAU:
				_end_m2()
	_check_orb_win()
	queue_redraw()        # channel warning sign(s)

# APPROACH: blue eases to the RIGHT-edge midpoint, teal to the LEFT-edge midpoint, then docking.
func _tick_m2_approach(delta: float) -> void:
	var t := clampf(_m2_timer / M2_APPROACH_T, 0.0, 1.0)
	var e := 1.0 - (1.0 - t) * (1.0 - t)   # ease-out rush
	var cy := OC_BOUNDS.get_center().y
	if _orb_alive(_blueorb_eo, _blueorb_hp):
		var bt := Vector2(OC_BOUNDS.end.x - P2_ORB_EDGE_MARGIN, cy) - _eo_half(_blueorb_eo)
		_blueorb_eo.position = _m2_appr_blue_from.lerp(bt, e)
	if _orb_alive(_tealorb_eo, _tealorb_hp):
		var tt := Vector2(OC_BOUNDS.position.x + P2_ORB_EDGE_MARGIN, cy) - _eo_half(_tealorb_eo)
		_tealorb_eo.position = _m2_appr_teal_from.lerp(tt, e)
	if t >= 1.0:
		_enter_m2_dock()

# Begin docking: capture the orbs' (and head's) current positions as the dock-rush start.
func _enter_m2_dock() -> void:
	_m2_state = M2.DOCK
	_m2_timer = 0.0
	_m2_dock_shoot = 0.0
	if is_instance_valid(_chromehead_eo): _m2_dock_head_from = _chromehead_eo.position
	if is_instance_valid(_blueorb_eo):    _m2_dock_blue_from = _blueorb_eo.position
	if is_instance_valid(_tealorb_eo):    _m2_dock_teal_from = _tealorb_eo.position

# DOCK: over M2_DOCK_T the orbs + head ease into place; meanwhile the orbs spin and fire a
# 4-direction spread (like Phase-1 Move 2). Final slots are the arena centre + slot offset.
func _tick_m2_dock(delta: float) -> void:
	var t := clampf(_m2_timer / M2_DOCK_T, 0.0, 1.0)
	var e := 1.0 - (1.0 - t) * (1.0 - t)   # ease-out: rushes in, settles
	var center := OC_BOUNDS.get_center()
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.position = _m2_dock_head_from.lerp(center - _eo_half(_chromehead_eo), e)
	if _orb_alive(_blueorb_eo, _blueorb_hp):
		_blueorb_eo.position = _m2_dock_blue_from.lerp(center + M2_SLOT_BLUE_OFFSET - _eo_half(_blueorb_eo), e)
	if _orb_alive(_tealorb_eo, _tealorb_hp):
		_tealorb_eo.position = _m2_dock_teal_from.lerp(center + M2_SLOT_TEAL_OFFSET - _eo_half(_tealorb_eo), e)
	# Constantly fire the 4 diagonals while rushing in (orbs do NOT spin).
	_m2_dock_shoot += delta
	if _m2_dock_shoot >= M2_DOCK_SHOOT_INT:
		_m2_dock_shoot = 0.0
		_m2_dock_fire()
	if t >= 1.0:
		_enter_m2_channel()

# Each live orb fires a fixed 4-diagonal spread (no spin).
func _m2_dock_fire() -> void:
	var diag: Array = [Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized()]
	if _orb_alive(_blueorb_eo, _blueorb_hp):
		_fire_orb_nsew(_blueorb_eo, _blue_fp_offset, 0.0,
			_blue_bullet_resized if _blue_bullet_resized != null else _blue_bullet_tex, diag, _blue_bullet_size)
	if _orb_alive(_tealorb_eo, _tealorb_hp):
		_fire_orb_nsew(_tealorb_eo, _teal_fp_offset, 0.0,
			_teal_bullet_resized if _teal_bullet_resized != null else _teal_bullet_tex, diag, _teal_bullet_size)

func _enter_m2_channel() -> void:
	_move_eo_to(_chromehead_eo, OC_BOUNDS.get_center() - _eo_half(_chromehead_eo), 1e9)  # snap
	_dock_orbs()
	_m2_state = M2.CHANNEL
	_m2_timer = 0.0
	# Identical channel to Move 1: light-gather FX at each (live) docked orb.
	if _orb_alive(_blueorb_eo, _blueorb_hp):
		_blue_channel_fx = _spawn_orb_channel_fx(_orb_center_vp(_blueorb_eo), P2_BLUE_LASER_COL)
	if _orb_alive(_tealorb_eo, _tealorb_hp):
		_teal_channel_fx = _spawn_orb_channel_fx(_orb_center_vp(_tealorb_eo), P2_TEAL_LASER_COL)

func _tick_m2_channel(delta: float) -> void:
	_dock_orbs()   # stationary: head at centre, _head_rot = 0
	if _m2_timer >= P2_ORB_CHANNEL_T:
		_free_node(_blue_channel_fx);  _blue_channel_fx = null
		_free_node(_teal_channel_fx);  _teal_channel_fx = null
		_blue_laser_dmg_acc = 0.0
		_teal_laser_dmg_acc = 0.0
		_m2_state = M2.FIRE_STATIC
		_m2_timer = 0.0

# Fire the cross. `spin_sign`: 0 = static, -1 = CCW, +1 = CW. The 4 arms emit from the head
# centre along the head's current spin angle, so the cross sweeps as the head rotates.
func _tick_m2_cross(delta: float, spin_sign: float) -> void:
	_head_rot += spin_sign * M2_SPIN_SPEED * delta
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.texture_rect.rotation = _head_rot
	_dock_orbs()
	var hc := _head_center()
	var diag := OC_BOUNDS.size.length()
	# Teal horizontal line (LEFT + RIGHT arms).
	var teal_hit := false
	if _orb_alive(_tealorb_eo, _tealorb_hp):
		var dl := Vector2.LEFT.rotated(_head_rot)
		var dr := Vector2.RIGHT.rotated(_head_rot)
		var hl := _beam_hits_ship(hc, dl, diag, P2_LASER_WIDTH)
		var hr := _beam_hits_ship(hc, dr, diag, P2_LASER_WIDTH)
		teal_hit = hl or hr
		_set_orb_beam(_m2_beam_tl, hc, dl, true, hl)
		_set_orb_beam(_m2_beam_tr, hc, dr, true, hr)
	else:
		_deactivate_beam(_m2_beam_tl);  _deactivate_beam(_m2_beam_tr)
	# Blue vertical line (UP + DOWN arms).
	var blue_hit := false
	if _orb_alive(_blueorb_eo, _blueorb_hp):
		var du := Vector2.UP.rotated(_head_rot)
		var dd := Vector2.DOWN.rotated(_head_rot)
		var hu := _beam_hits_ship(hc, du, diag, P2_LASER_WIDTH)
		var hd := _beam_hits_ship(hc, dd, diag, P2_LASER_WIDTH)
		blue_hit = hu or hd
		_set_orb_beam(_m2_beam_bu, hc, du, true, hu)
		_set_orb_beam(_m2_beam_bd, hc, dd, true, hd)
	else:
		_deactivate_beam(_m2_beam_bu);  _deactivate_beam(_m2_beam_bd)
	# Damage once per colour per interval (so the cross hub can't quadruple-dip).
	_teal_laser_dmg_acc = _accrue_beam_dmg(_teal_laser_dmg_acc, teal_hit, delta)
	_blue_laser_dmg_acc = _accrue_beam_dmg(_blue_laser_dmg_acc, blue_hit, delta)

func _end_m2() -> void:
	for beam in [_m2_beam_tl, _m2_beam_tr, _m2_beam_bu, _m2_beam_bd]:
		_deactivate_beam(beam)   # let lingering particles/debris finish on their own
	_head_rot = 0.0
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.texture_rect.rotation = 0.0
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.texture_rect.rotation = 0.0
	_begin_p2_attack()   # back to the picker

# Slave the docked orbs to head_center + rotated slot offset (so they orbit as the head spins).
func _dock_orbs() -> void:
	var hc := _head_center()
	if is_instance_valid(_blueorb_eo):
		_blueorb_eo.position = hc + M2_SLOT_BLUE_OFFSET.rotated(_head_rot) - _eo_half(_blueorb_eo)
		_blueorb_eo.texture_rect.rotation = _head_rot
	if is_instance_valid(_tealorb_eo):
		_tealorb_eo.position = hc + M2_SLOT_TEAL_OFFSET.rotated(_head_rot) - _eo_half(_tealorb_eo)
		_tealorb_eo.texture_rect.rotation = _head_rot

func _eo_half(eo: EditableObjectNode) -> Vector2:
	return eo.size * 0.5 if is_instance_valid(eo) else Vector2.ZERO

func _orb_alive(eo: EditableObjectNode, hp: int) -> bool:
	return is_instance_valid(eo) and hp > 0

# Move `eo.position` toward `target` by at most `step`; returns true once it has arrived.
func _move_eo_to(eo: EditableObjectNode, target: Vector2, step: float) -> bool:
	if not is_instance_valid(eo):
		return true
	var d := target - eo.position
	if d.length() <= step:
		eo.position = target
		return true
	eo.position += d.normalized() * step
	return false

# ── Attack 3 — "Two orbs on a rigid rope" ───────────────────────────────────
# Stage 1: both orbs fly to centre (blue 200 above, teal 200 below → 400 apart) and a rainbow-
# lightning rope grows between them. Stage 2+: the rope is rigid (400px); the planted orb is the
# pivot, the other rotates around it at exactly 400px to the point nearest a once-captured player
# spot, then charges/detonates; roles swap. Ends after M3_TOTAL_BOMBS (10) explosions.
func _begin_p2_attack3() -> void:
	_phase = Phase.P2_ATTACK3
	_phase_timer = 0.0
	# Firing order: blue first, then teal (swap these two lists to reverse).
	_m3_eo    = [_blueorb_eo, _tealorb_eo]
	_m3_which = ["blue", "teal"]
	_m3_col   = [P2_BLUE_LASER_COL, P2_TEAL_LASER_COL]
	_m3_state   = [Bomb.IDLE, Bomb.IDLE]
	_m3_timer   = [0.0, 0.0]
	_m3_lock    = [Vector2.ZERO, Vector2.ZERO]
	_m3_pivot   = [Vector2.ZERO, Vector2.ZERO]
	_m3_swing_t = [0.0, 0.0]
	_m3_th0     = [0.0, 0.0]
	_m3_dtheta  = [0.0, 0.0]
	_m3_fx      = [null, null]
	_m3_launched = 0
	_m3_exploded = 0
	_m3_fx_t = 0.0
	_m3_in_setup = true
	_m3_setup_t = 0.0
	_m3_rope_dmg_acc = 0.0
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.texture_rect.rotation = 0.0
	_ensure_rope()

func _tick_p2_attack3(delta: float) -> void:
	_phase_timer += delta
	if _m3_in_setup:
		_tick_m3_setup(delta)
	else:
		_tick_m3_orb(0, delta)
		_tick_m3_orb(1, delta)
	_tick_shake(delta)
	_update_rope()
	_tick_rope_damage(delta)
	if _m3_fx_t > 0.0:
		_m3_fx_t -= delta
	_check_orb_win()
	queue_redraw()
	# End once all explosions are done, or nothing is left in flight (e.g. orbs died).
	if not _m3_in_setup:
		var active: bool = _m3_busy(0) or _m3_busy(1)
		if (_m3_exploded >= M3_TOTAL_BOMBS or not active) and _m3_fx_t <= 0.0:
			_end_m3()

# Stage 1 — fly to the centre formation, then grow the rope, then start the first swing.
func _tick_m3_setup(delta: float) -> void:
	var center := OC_BOUNDS.get_center()
	var step := M3_SETUP_MOVE_SPD * delta
	var b_done := _move_orb_center(_blueorb_eo, center + Vector2(-M3_SETUP_OFFSET, 0.0), step)  # blue left
	var t_done := _move_orb_center(_tealorb_eo, center + Vector2( M3_SETUP_OFFSET, 0.0), step)  # teal right
	if b_done and t_done:
		_m3_setup_t += delta
		if _m3_setup_t >= M3_ROPE_GROW_T:
			_m3_in_setup = false
			_m3_start_first_swing()

# Move an orb so its CENTRE reaches `target_c` by at most `step`; true once arrived.
func _move_orb_center(eo: EditableObjectNode, target_c: Vector2, step: float) -> bool:
	if not is_instance_valid(eo):
		return true
	return _move_eo_to(eo, target_c - _eo_half(eo), step)

# Stage 3 — the orb CLOSEST to the player swings first; the farther one is the pivot.
func _m3_start_first_swing() -> void:
	var ship := _ship_center()
	var d0: float = _orb_center_vp(_m3_eo[0]).distance_to(ship) if _m3_orb_alive(0) else INF
	var d1: float = _orb_center_vp(_m3_eo[1]).distance_to(ship) if _m3_orb_alive(1) else INF
	var first: int = 0 if d0 <= d1 else 1
	_m3_try_launch(first)

func _m3_busy(i: int) -> bool:
	return _m3_state[i] == Bomb.ZOOM or _m3_state[i] == Bomb.CHARGE

# Start orb `i` zooming for a new bomb — only if it's free (IDLE/DONE), alive, and bombs remain.
func _m3_try_launch(i: int) -> void:
	if _m3_launched >= M3_TOTAL_BOMBS or not _m3_orb_alive(i):
		return
	if _m3_state[i] == Bomb.IDLE or _m3_state[i] == Bomb.DONE:
		_m3_start_swing(i)
		_m3_launched += 1

# Begin orb i's rope swing: whirl around the PLANTED partner (the pivot) toward a player point
# captured ONCE here. Pivot = the partner orb's current position; if the partner is dead, fall
# back to the head so the survivor can still bomb. Target + pivot are fixed for the whole swing.
func _m3_start_swing(i: int) -> void:
	_m3_state[i] = Bomb.ZOOM
	_m3_timer[i] = 0.0
	_m3_swing_t[i] = 0.0
	var eo := _m3_eo[i] as EditableObjectNode
	if not is_instance_valid(eo):
		return
	# Pivot = the planted partner's position. If its node is gone, fall back to the head; killed
	# orbs are only hidden (not freed), so a dead partner still gives a sensible last position.
	var other := _m3_eo[1 - i] as EditableObjectNode
	var pivot: Vector2 = _orb_center_vp(other) if is_instance_valid(other) else _head_center()
	var rel0 := _orb_center_vp(eo) - pivot
	_m3_pivot[i] = pivot
	_m3_th0[i]   = rel0.angle() if rel0.length() > 0.01 else 0.0
	# (No target capture — the swing homes onto the player's LIVE position each frame; see the tick.)

func _m3_orb_alive(i: int) -> bool:
	var hp: int = _blueorb_hp if _m3_which[i] == "blue" else _tealorb_hp
	return _orb_alive(_m3_eo[i], hp)

func _tick_m3_orb(i: int, delta: float) -> void:
	var eo := _m3_eo[i] as EditableObjectNode
	if not _m3_orb_alive(i):
		# Dead orb → no detonation; park it DONE (it just won't launch again).
		if _m3_state[i] != Bomb.DONE:
			_free_node(_m3_fx[i]);  _m3_fx[i] = null
			_m3_state[i] = Bomb.DONE
		return
	_m3_timer[i] = float(_m3_timer[i]) + delta
	match _m3_state[i]:
		Bomb.ZOOM:
				# Rigid-rope swing: rotate around the pivot at the FIXED rope length, easing the
				# angle, and HOMING onto the player's LIVE position (re-aimed every frame).
				_m3_swing_t[i] = minf(float(_m3_swing_t[i]) + delta / M3_SWING_DUR, 1.0)
				var t := float(_m3_swing_t[i])
				var e := lerpf(t, smoothstep(0.0, 1.0, t), M3_SWING_EASE)
				var pivot := _m3_pivot[i] as Vector2
				var to_player := _ship_center() - pivot                   # LIVE player each frame
				var th1: float = to_player.angle() if to_player.length() > 0.01 else float(_m3_th0[i])
				var angle := lerp_angle(float(_m3_th0[i]), th1, e)         # ease toward the live target
				var c := pivot + Vector2(M3_ROPE_LEN, 0.0).rotated(angle)
				eo.position = c - _eo_half(eo)   # no clamp: the rigid rope length wins over bounds
				if t >= 1.0:
					_m3_lock[i] = c   # plant here and charge (unchanged downstream)
					_enter_m3_charge(i)
		Bomb.CHARGE:
			# Hold at the locked spot, charging. Keep the orb pinned (no chasing) + spin it fast.
			eo.position = (_m3_lock[i] as Vector2) - _eo_half(eo)
			if eo.texture_rect != null:
				eo.texture_rect.rotation = float(_m3_timer[i]) * M3_CHARGE_SPIN
			if float(_m3_timer[i]) >= M3_CHARGE_T:
				_detonate(i)
		Bomb.DONE:
			pass

func _enter_m3_charge(i: int) -> void:
	_m3_state[i] = Bomb.CHARGE
	_m3_timer[i] = 0.0
	_m3_fx[i] = _spawn_orb_channel_fx(_m3_lock[i], _m3_col[i], M3_CHARGE_T,
		M3_CHANNEL_SCALE, M3_CHANNEL_MOTE_MULT)
	_m3_try_launch(1 - i)   # the OTHER orb starts zooming the instant this one stops

func _detonate(i: int) -> void:
	_free_node(_m3_fx[i]);  _m3_fx[i] = null
	var pos: Vector2 = _m3_lock[i]
	_spawn_explosion(pos, M3_BLAST_RADIUS, _m3_col[i])
	_impact_fx(pos)   # hit-stop + white-out + trauma shake/kick + chromatic aberration
	# Single dodgeable AoE tick — only if the ship is still inside the blast radius.
	if _ship_center().distance_to(pos) <= M3_BLAST_RADIUS:
		GameManager.ship_take_damage(M3_BLAST_DMG)
		_flash_ship_red()
	_m3_exploded += 1
	_m3_fx_t = M3_EXPLOSION_DUR
	_m3_state[i] = Bomb.DONE
	# Re-launch THIS orb only if its partner is gone (solo). Normally the partner's own plant
	# (in _enter_m3_charge) launches the next swing, so exactly ONE orb ever swings at a time and
	# the pivot stays put → the 200px rope length can never shrink.
	if not _m3_orb_alive(1 - i):
		_m3_try_launch(i)

func _end_m3() -> void:
	for i in 2:
		_free_node(_m3_fx[i]);  _m3_fx[i] = null
	_free_node(_m3_rope);  _m3_rope = null
	if _shaking and is_instance_valid(_objects_container):
		_objects_container.position = _shake_origin
	_shaking = false;  _trauma = 0.0;  _kick = Vector2.ZERO
	for orb: EditableObjectNode in [_blueorb_eo, _tealorb_eo]:
		if is_instance_valid(orb):
			orb.texture_rect.rotation = 0.0
	_begin_p2_attack()   # back to the picker

# ── Rainbow-lightning rope (rigid 400px link between the two orbs) ────────────
func _ensure_rope() -> void:
	if _m3_rope == null or not is_instance_valid(_m3_rope):
		_m3_rope = _RopeFX.new()
		_m3_rope.setup(M3_ROPE_SEGMENTS, M3_ROPE_JITTER, M3_ROPE_HALO_W, M3_ROPE_MID_W,
			M3_ROPE_CORE_W, M3_ROPE_HUE_SCROLL, M3_ROPE_SAT)
		_m3_rope.z_index = 168           # under the orbs/explosions, above the arena
		_m3_rope.z_as_relative = false
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # glows like light
		_m3_rope.material = m
		_clip_node.add_child(_m3_rope)

# Feed the rope the two orbs' current positions (clip-local) + the setup grow factor; it
# fizzles (stops drawing) if either orb is dead/gone.
func _update_rope() -> void:
	if _m3_rope == null or not is_instance_valid(_m3_rope):
		return
	var e0 := _m3_eo[0] as EditableObjectNode
	var e1 := _m3_eo[1] as EditableObjectNode
	if not is_instance_valid(e0) or not is_instance_valid(e1):
		_m3_rope.set_ends(Vector2.ZERO, Vector2.ZERO, 0.0, false)   # fizzle if an orb is gone
		return
	var both := _m3_orb_alive(0) and _m3_orb_alive(1)
	var a := _orb_center_vp(e0) - OC_BOUNDS.position
	var b := _orb_center_vp(e1) - OC_BOUNDS.position
	var grow: float = clampf(_m3_setup_t / M3_ROPE_GROW_T, 0.0, 1.0) if _m3_in_setup else 1.0
	_m3_rope.set_ends(a, b, grow, both)

# The live rainbow tether hurts the ship while it touches the line between the two orbs:
# M3_ROPE_DMG every M3_ROPE_DMG_INT. Only once the rope is fully formed and both orbs are alive.
func _tick_rope_damage(delta: float) -> void:
	if _m3_in_setup or not (_m3_orb_alive(0) and _m3_orb_alive(1)):
		_m3_rope_dmg_acc = 0.0
		return
	var a := _orb_center_vp(_m3_eo[0])
	var b := _orb_center_vp(_m3_eo[1])
	var ship := _ship_center()
	var closest := Geometry2D.get_closest_point_to_segment(ship, a, b)
	var sr := _ship_rect_vp()
	var ship_r: float = maxf(sr.size.x, sr.size.y) * 0.5 if sr != Rect2() else 16.0
	if ship.distance_to(closest) <= M3_ROPE_DMG_W + ship_r:
		_m3_rope_dmg_acc += delta
		if _m3_rope_dmg_acc >= M3_ROPE_DMG_INT:
			_m3_rope_dmg_acc -= M3_ROPE_DMG_INT
			GameManager.ship_take_damage(M3_ROPE_DMG)
			_flash_ship_red()
	else:
		_m3_rope_dmg_acc = 0.0

# A jagged, hue-scrolling, additively-glowing "lightning rope" between two points.
class _RopeFX extends Node2D:
	var _a := Vector2.ZERO
	var _b := Vector2.ZERO
	var _grow := 0.0
	var _alive := true
	var _t := 0.0
	var _segs := 16
	var _jit := 18.0
	var _halo := 14.0
	var _mid := 6.0
	var _core := 2.5
	var _hue_scroll := 0.6
	var _sat := 0.9

	func setup(segs: int, jit: float, halo: float, mid: float, core: float, hue_scroll: float, sat: float) -> void:
		_segs = maxi(segs, 2);  _jit = jit;  _halo = halo;  _mid = mid;  _core = core
		_hue_scroll = hue_scroll;  _sat = sat

	func set_ends(a: Vector2, b: Vector2, grow: float, alive: bool) -> void:
		_a = a;  _b = b;  _grow = clampf(grow, 0.0, 1.0);  _alive = alive

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	# Build the jagged polyline (interior points jittered perpendicular, re-randomised each frame).
	func _points(span_end: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var dir := span_end - _a
		var L := dir.length()
		if L < 1.0:
			return pts
		dir /= L
		var perp := Vector2(-dir.y, dir.x)
		for k in _segs + 1:
			var f := float(k) / float(_segs)
			var base := _a + (span_end - _a) * f
			var jit := 0.0
			if k > 0 and k < _segs:
				jit = randf_range(-1.0, 1.0) * _jit * sin(f * PI)   # taper jitter to the ends
			pts.append(base + perp * jit)
		return pts

	func _pass(pts: PackedVector2Array, width: float, alpha: float, white_amt: float) -> void:
		for k in pts.size() - 1:
			var f := float(k) / float(maxi(pts.size() - 1, 1))
			var col := Color.from_hsv(fposmod(f + _t * _hue_scroll, 1.0), _sat, 1.0).lerp(Color(1, 1, 1), white_amt)
			col.a = alpha
			draw_line(pts[k], pts[k + 1], col, width)

	func _draw() -> void:
		if not _alive or _grow <= 0.0:
			return                       # fizzle: no rope when an orb is gone / before it grows
		var span_end := _a + (_b - _a) * _grow
		var pts := _points(span_end)
		if pts.size() < 2:
			return
		_pass(pts, _halo, 0.16, 0.0)     # wide soft halo
		_pass(pts, _mid,  0.5,  0.4)     # brighter mid
		_pass(pts, _core, 0.95, 0.8)     # near-white hot core
		# A couple of faint branch-forks for electric feel.
		for _b2 in 2:
			var k := randi_range(2, maxi(2, _segs - 2))
			if k < pts.size():
				var p: Vector2 = pts[k]
				var fork := p + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _jit * 2.2
				var fc := Color.from_hsv(fposmod(float(k) / float(_segs) + _t * _hue_scroll, 1.0), _sat, 1.0)
				draw_line(p, fork, Color(fc.r, fc.g, fc.b, 0.4), 1.5)

# ── Detonation impact bundle (visual/feel only; reusable for any blast) ──────
# Trauma shake/kick + chromatic aberration (no hit-stop, no full-screen white-out).
func _impact_fx(blast_pos_vp: Vector2) -> void:
	_trigger_shake(blast_pos_vp)
	_spawn_aberration(blast_pos_vp)

# Full-screen radial RGB-split pulse centred on the blast; fades over ABERRATION_T. Self-frees.
func _spawn_aberration(center_vp: Vector2) -> void:
	if _aberration_shader == null:
		_aberration_shader = Shader.new()
		_aberration_shader.code = ABERRATION_SHADER
	var cl := CanvasLayer.new()
	cl.layer = ABERRATION_LAYER
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _aberration_shader
	var vp := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("center", (center_vp / vp) if vp.x > 0.0 else Vector2(0.5, 0.5))
	mat.set_shader_parameter("strength", ABERRATION_MAX)
	cr.material = mat
	cl.add_child(cr)
	get_tree().root.add_child(cl)
	var tw := cr.create_tween()
	tw.tween_method(func(s: float) -> void: mat.set_shader_parameter("strength", s),
		ABERRATION_MAX, 0.0, ABERRATION_T)
	tw.tween_callback(cl.queue_free)

# Trauma-based shake: spike to full on a blast, decay over TRAUMA_DECAY; offset = max·trauma²
# (squared → a hard punchy spike). Plus a one-time directional kick away from the blast.
func _trigger_shake(blast_pos_vp: Vector2) -> void:
	if not _shaking and is_instance_valid(_objects_container):
		_shake_origin = _objects_container.position
		_shaking = true
	_trauma = 1.0
	var dir := OC_BOUNDS.get_center() - blast_pos_vp   # shove the view away from the blast
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.from_angle(randf() * TAU)
	_kick = dir * SHAKE_KICK

func _tick_shake(delta: float) -> void:
	if not _shaking:
		return
	_trauma = maxf(0.0, _trauma - delta / TRAUMA_DECAY)
	if _trauma <= 0.0 or not is_instance_valid(_objects_container):
		if is_instance_valid(_objects_container):
			_objects_container.position = _shake_origin
		_shaking = false
		_kick = Vector2.ZERO
		return
	var s := _trauma * _trauma   # squared = hard spike that decays fast
	var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAX_OFFSET * s
	_objects_container.position = _shake_origin + off + _kick * s

# ── Layered procedural explosion (additive, self-freeing) ────────────────────
func _spawn_explosion(pos_vp: Vector2, radius: float, color: Color) -> Node:
	var ex := _Explosion.new()
	ex.position      = pos_vp - OC_BOUNDS.position   # clip-local
	ex.z_index       = 170
	ex.z_as_relative = false
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # light stacks
	ex.material = m
	ex.setup(radius, color, M3_AFTERMATH_DUR, M3_RAINBOW_SAT)   # light fades fast; smoke/debris linger
	_clip_node.add_child(ex)
	return ex

# A supernova-style burst: flash → fireball → shockwave ring → radial rays → smoke → embers.
# Each layer on its own growth/fade curve; modelled on the Lasgun impact flare. Self-frees.
class _Explosion extends Node2D:
	var _t := 0.0
	var _dur := 1.0
	var _radius := 120.0
	var _col := Color(1.0, 0.6, 0.2)
	var _sat := 0.9           # HSV saturation for the prismatic hues (0 = white, 1 = full rainbow)
	var _base_hue := 0.0      # fireball/ring base hue (shifts over time)
	var _rays: Array = []     # {ang, len, w, hue}
	var _embers: Array = []   # {pos, vel, life, max_life, hue}
	var _smoke: Array = []    # {pos, vel, rad, life, max_life, hue} — decelerating, lingering
	var _chunks: Array = []   # {pos, vel, rot, rot_spd, size, life, max_life, hue} — tumbling debris

	func setup(radius: float, color: Color, dur: float, sat: float = 0.9) -> void:
		_radius = maxf(radius, 4.0)
		_col = color
		_dur = maxf(dur, 0.2)
		_sat = clampf(sat, 0.0, 1.0)
		_base_hue = randf()
		var nray := 18
		for i in nray:
			_rays.append({
				"ang": (float(i) / float(nray)) * TAU + randf_range(-0.12, 0.12),
				"len": _radius * randf_range(0.95, 1.55),
				"w":   randf_range(3.0, 7.0),
				"hue": randf(),   # full-spectrum random hue per streak (prism scatter)
			})
		for _i in 26:
			var a := randf() * TAU
			var spd := _radius * randf_range(2.0, 4.5)
			_embers.append({"pos": Vector2.ZERO, "vel": Vector2(cos(a), sin(a)) * spd,
				"life": 0.0, "max_life": randf_range(0.35, 0.75), "hue": randf()})
		# Aftermath — slow decelerating smoke puffs that linger well past the light.
		for _j in 7:
			var sa := randf() * TAU
			var sd := Vector2(cos(sa), sin(sa))
			_smoke.append({
				"pos": sd * _radius * randf_range(0.0, 0.35),
				"vel": sd * _radius * randf_range(0.6, 1.4),   # slow outward drift, decelerates
				"rad": _radius * randf_range(0.35, 0.6),
				"life": 0.0, "max_life": randf_range(1.2, 2.0), "hue": randf()})
		# Aftermath — a few tumbling debris chunks that arc out, slow down, and fade.
		for _k in 7:
			var ca := randf() * TAU
			_chunks.append({
				"pos": Vector2.ZERO,
				"vel": Vector2(cos(ca), sin(ca)) * _radius * randf_range(2.0, 4.0),
				"rot": randf() * TAU, "rot_spd": randf_range(-8.0, 8.0),
				"size": randf_range(4.0, 9.0),
				"life": 0.0, "max_life": randf_range(0.9, 1.8), "hue": randf()})

	func _process(delta: float) -> void:
		_t += delta
		for e in _embers:
			e["life"] = float(e["life"]) + delta
			var v: Vector2 = e["vel"]
			v.y += 680.0 * delta            # gravity arc
			v *= (1.0 - 1.5 * delta)        # drag
			e["vel"] = v
			e["pos"] = (e["pos"] as Vector2) + v * delta
		for s in _smoke:
			s["life"] = float(s["life"]) + delta
			var sv: Vector2 = s["vel"]
			sv *= (1.0 - 1.8 * delta)       # decelerate (not constant speed)
			s["vel"] = sv
			s["pos"] = (s["pos"] as Vector2) + sv * delta
		for c in _chunks:
			c["life"] = float(c["life"]) + delta
			var cv: Vector2 = c["vel"]
			cv.y += 520.0 * delta           # gravity
			cv *= (1.0 - 1.6 * delta)       # drag (decelerate)
			c["vel"] = cv
			c["pos"] = (c["pos"] as Vector2) + cv * delta
			c["rot"] = float(c["rot"]) + float(c["rot_spd"]) * delta
		if _t >= _dur:
			queue_free()
			return
		queue_redraw()

	# Prismatic colour helper: a vivid hue at the current saturation, full value (additive →
	# overlapping hues stack toward white). `a` is the alpha.
	func _hue(h: float, a: float) -> Color:
		var c := Color.from_hsv(fposmod(h, 1.0), _sat, 1.0)
		return Color(c.r, c.g, c.b, a)

	func _draw() -> void:
		# 1) Flash — LOCAL white-hot core disc only (the full-screen white-out was removed).
		var ft: float = clampf(_t / 0.12, 0.0, 1.0)
		if ft < 1.0:
			draw_circle(Vector2.ZERO, _radius * 0.45, Color(1, 1, 1, 1.0 - ft))
		# 2) Core fireball — expands; shell cycles through hues; centre stays blinding white.
		var ct: float = clampf(_t / 0.5, 0.0, 1.0)
		if ct < 1.0:
			var fr := _radius * (0.18 + 0.95 * ct)
			var fa2 := 1.0 - ct
			draw_circle(Vector2.ZERO, fr, _hue(_base_hue + ct, fa2 * 0.85))   # hue-shifting shell
			draw_circle(Vector2.ZERO, fr * 0.5, Color(1, 1, 1, fa2 * 0.9))    # white-hot core
		# 3) Shockwave ring — iridescent: hue varies around the circumference + shifts as it grows.
		var rt: float = clampf(_t / 0.55, 0.0, 1.0)
		if rt < 1.0:
			var rr := _radius * (0.35 + 1.15 * rt)
			var rw := lerpf(9.0, 1.0, rt)
			var segs := 16
			for k in segs:
				var a0 := TAU * float(k) / float(segs)
				var a1 := TAU * float(k + 1) / float(segs)
				draw_arc(Vector2.ZERO, rr, a0, a1, 6,
					_hue(_base_hue + rt * 0.5 + float(k) / float(segs), (1.0 - rt) * 0.8), rw)
		# 4) Radial rays — each streak its own random hue (prism scatter), fading.
		var yt: float = clampf(_t / 0.4, 0.0, 1.0)
		if yt < 1.0:
			var ya := 1.0 - yt
			for ray in _rays:
				var d := Vector2(cos(float(ray["ang"])), sin(float(ray["ang"])))
				var perp := Vector2(-d.y, d.x)
				var inner := d * (_radius * 0.12)
				var outer := d * (float(ray["len"]) * (0.45 + 0.55 * yt))
				var w := float(ray["w"]) * ya
				var rc := _hue(float(ray["hue"]), ya)
				draw_polygon(
					PackedVector2Array([inner + perp * w, inner - perp * w, outer]),
					PackedColorArray([rc, rc, _hue(float(ray["hue"]), 0.0)]))
		# 5) Smoke halo — slow decelerating puffs, faintly tinted, lingering past the light.
		for s in _smoke:
			var sp: float = clampf(float(s["life"]) / float(s["max_life"]), 0.0, 1.0)
			if sp < 1.0:
				var srad := float(s["rad"]) * (0.6 + 1.0 * sp)
				var smc := Color.from_hsv(fposmod(float(s["hue"]), 1.0), _sat * 0.5, 0.7)
				draw_circle(s["pos"], srad, Color(smc.r, smc.g, smc.b, (1.0 - sp) * 0.18))
		# 6) Tumbling debris chunks — glowing hued bits that arc out, slow + fade (linger).
		for c in _chunks:
			var cp: float = clampf(1.0 - float(c["life"]) / float(c["max_life"]), 0.0, 1.0)
			if cp > 0.0:
				var cpos: Vector2 = c["pos"]
				var sz := float(c["size"])
				var crot := float(c["rot"])
				var pts := PackedVector2Array()
				for k in 4:
					var a := crot + TAU * float(k) / 4.0 + PI / 4.0
					pts.append(cpos + Vector2(cos(a), sin(a)) * sz)
				draw_colored_polygon(pts, _hue(float(c["hue"]), 0.5 * cp))    # hued chunk body
				draw_circle(cpos, sz * 0.32, Color(1, 1, 1, 0.45 * cp))       # hot white core
		# 7) Embers — fast streaks, each a random saturated hue.
		for e in _embers:
			var ep: float = clampf(1.0 - float(e["life"]) / float(e["max_life"]), 0.0, 1.0)
			if ep > 0.0:
				var pos: Vector2 = e["pos"]
				var v: Vector2 = e["vel"]
				var tail := pos - v.normalized() * 7.0
				draw_line(tail, pos, _hue(float(e["hue"]), 0.8 * ep), 2.0)
				draw_circle(pos, 2.2 * ep, _hue(float(e["hue"]), ep))

# TODO(phase2): Attacks 4-5. Stubbed to Attack 1 until designed.
func _begin_p2_attack4() -> void: _begin_p2_attack1()
func _begin_p2_attack5() -> void: _begin_p2_attack1()

# =============================================================================
# Orb HP + win condition
# =============================================================================

func _register_orb_targets() -> void:
	var ws := _get_ws()
	if ws == null:
		return
	ws.add_hit_target(
		func() -> Rect2: return _orb_rect_stream(_blueorb_eo, ws),
		func(dmg: float) -> void: _on_blueorb_hit(dmg)
	)
	ws.add_hit_target(
		func() -> Rect2: return _orb_rect_stream(_tealorb_eo, ws),
		func(dmg: float) -> void: _on_tealorb_hit(dmg)
	)

func _orb_rect_stream(eo: EditableObjectNode, ws: Node) -> Rect2:
	if eo == null or not is_instance_valid(eo) or not eo.visible:
		return Rect2()
	return Rect2(eo.global_position - (ws as Control).global_position, eo.size)

func _on_blueorb_hit(dmg: float) -> void:
	if _blueorb_hp <= 0:
		return
	_blueorb_hp = maxi(0, _blueorb_hp - int(dmg))
	var total := _blueorb_hp + _tealorb_hp
	GameManager.boss_hp = total
	GameManager.boss_hp_changed.emit(total)
	if _blueorb_hp <= 0 and is_instance_valid(_blueorb_eo):
		_blueorb_eo.visible = false

func _on_tealorb_hit(dmg: float) -> void:
	if _tealorb_hp <= 0:
		return
	_tealorb_hp = maxi(0, _tealorb_hp - int(dmg))
	var total := _blueorb_hp + _tealorb_hp
	GameManager.boss_hp = total
	GameManager.boss_hp_changed.emit(total)
	if _tealorb_hp <= 0 and is_instance_valid(_tealorb_eo):
		_tealorb_eo.visible = false

func _check_orb_win() -> void:
	if _blueorb_hp <= 0 and _tealorb_hp <= 0:
		_end_fight_win()

func get_move_name() -> String:
	match _phase:
		Phase.M1_CRAWL:
			return "Move 1: Crawl"
		Phase.M2_TRANSFORM, Phase.M2_MOVE, Phase.M2_SPIN, Phase.M2_RETURN:
			return "Move 2: Ball Spin"
		Phase.M3_CURL, Phase.M3_EJECT, Phase.M3_SPIRAL:
			return "Move 3: Orb Detach"
		Phase.M4_TRANSFORM, Phase.M4_SPIN, Phase.M4_CHARGE, Phase.M4_OFFSCREEN, Phase.M4_FINAL, Phase.M4_RETURN:
			return "Move 4: Ball Charge"
		Phase.P2_ENTRY:
			return "Phase 2 — Entry"
		Phase.P2_ATTACK1:
			return "Phase 2 — Bull Charge"
		Phase.P2_ATTACK2, Phase.P2_ATTACK3, Phase.P2_ATTACK4, Phase.P2_ATTACK5:
			return "Phase 2"
	return ""

func _end_fight_win() -> void:
	if _phase == Phase.DONE:
		return
	# Play the shared death cutscene (boss frozen via input_locked) before victory.
	GameManager.input_locked = true
	_cleanup_orb_beams()   # kill the alignment lasers before the cutscene freezes everything
	var mgr := get_tree().get_first_node_in_group("boss_fight")
	if mgr != null and mgr.has_method("play_death_cutscene"):
		await mgr.play_death_cutscene([_chromehead_eo])
	_cleanup_projectiles()
	_cleanup_shielded_bullets()
	var ws := _get_ws()
	if ws != null:
		ws.clear_extra_targets()
		ws.clear_multi_hit_provider()
	if is_instance_valid(_chromehead_eo):
		_chromehead_eo.visible = false
	_phase = Phase.DONE
	_phase_timer = 0.0
	GameManager.boss_hp     = 0
	GameManager.boss_max_hp = 0
	# Delay boss_killed so HUD stays visible and asteroids don't spawn yet
	await get_tree().create_timer(0.1).timeout
	GameManager.boss_killed.emit()
	_show_victory_screen()
	GameManager.input_locked = false

# =============================================================================
# Shielded bullets (Final Sub 2)
# =============================================================================

func _spawn_bullet_wave() -> void:
	if _bullet_frames.is_empty():
		return
	print(">>> WAVE SPAWN at Y=%f, spawning %d bullets" % [WAVE_Y, SUB2_BLT_CNT])
	for i in SUB2_BLT_CNT:
		var x_vp := WAVE_X_MIN + i * (WAVE_X_MAX - WAVE_X_MIN) / float(SUB2_BLT_CNT - 1)
		var tex  := _random_bullet()
		var sz   := _random_bullet_sz()
		var tr   := TextureRect.new()
		tr.texture        = tex
		tr.size           = sz
		tr.stretch_mode   = TextureRect.STRETCH_SCALE
		tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.z_as_relative  = false
		tr.z_index        = 150
		var lpos := Vector2(x_vp - OC_BOUNDS.position.x, WAVE_Y - OC_BOUNDS.position.y) - sz / 2.0
		tr.position = lpos
		_clip_node.add_child(tr)
		_shielded_bullets.append({
			"tr":  tr,
			"pos": Vector2(x_vp, WAVE_Y),
			"vel": Vector2(0.0, randf_range(WAVE_SPD_MIN, WAVE_SPD_MAX)),
			"hp":  SUB2_BLT_HP,
			"sz":  sz
		})

func _tick_shielded_bullets(delta: float) -> void:
	var i := _shielded_bullets.size() - 1
	while i >= 0:
		var sb: Dictionary = _shielded_bullets[i]
		sb["pos"] = (sb["pos"] as Vector2) + (sb["vel"] as Vector2) * delta
		var tr: TextureRect = sb["tr"]
		if is_instance_valid(tr):
			var p: Vector2 = sb["pos"]
			tr.position = Vector2(p.x - OC_BOUNDS.position.x, p.y - OC_BOUNDS.position.y) - tr.size / 2.0
		var py: float = float((sb["pos"] as Vector2).y)
		if py > OC_BOUNDS.end.y + 20.0:
			if is_instance_valid(tr):
				tr.queue_free()
			_shielded_bullets.remove_at(i)
		i -= 1

func _get_shielded_targets() -> Array:
	var ws := _get_ws()
	if ws == null:
		return []
	var ws_gp: Vector2 = (ws as Control).global_position
	var result: Array = []
	for sb: Dictionary in _shielded_bullets:
		var pos: Vector2 = sb["pos"]
		var sz: Vector2  = sb.get("sz", Vector2.ZERO) as Vector2
		var sbref := sb
		result.append({
			"rect":   Rect2(pos - ws_gp - sz / 2.0, sz),
			"on_hit": func(dmg: float) -> void: _on_shielded_hit(sbref, dmg)
		})
	return result

func _on_shielded_hit(sb: Dictionary, dmg: float) -> void:
	if not _shielded_bullets.has(sb):
		return
	sb["hp"] = int(sb["hp"]) - int(dmg)
	if int(sb["hp"]) <= 0:
		var tr: TextureRect = sb["tr"]
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
		_shielded_bullets.erase(sb)

func _cleanup_shielded_bullets() -> void:
	var ws := _get_ws()
	if ws != null:
		ws.clear_multi_hit_provider()
	for sb: Dictionary in _shielded_bullets:
		var tr: TextureRect = sb["tr"]
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_shielded_bullets.clear()

# =============================================================================
# Victory screen
# =============================================================================

func _show_victory_screen() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 500
	get_tree().root.add_child(cl)

	var vp_sz := get_viewport().get_visible_rect().size
	var bg    := ColorRect.new()
	bg.color  = Color(0.0, 0.0, 0.0, 0.75)
	bg.size   = vp_sz
	cl.add_child(bg)

	var cx := vp_sz.x / 2.0
	var cy := vp_sz.y / 2.0

	var font_path := "res://assets/fonts/Gameplay.ttf"
	var font: FontFile = null
	if ResourceLoader.exists(font_path):
		font = load(font_path) as FontFile

	var title := Label.new()
	title.text = "CHROMELEON DEFEATED"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.9))
	title.size = Vector2(640.0, 60.0)
	title.position = Vector2(cx - 320.0, cy - 90.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		title.add_theme_font_override("font", font)
	bg.add_child(title)

	var btn := Button.new()
	btn.text = "Continue to Universe"
	btn.size = Vector2(240.0, 44.0)
	btn.position = Vector2(cx - 120.0, cy + 10.0)
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 12)
	var cl_ref := cl
	btn.pressed.connect(func() -> void: cl_ref.queue_free())
	bg.add_child(btn)

# =============================================================================
# Process
# =============================================================================

func _process(delta: float) -> void:
	if GameManager.boss_intro_active or GameManager.input_locked:
		return   # frozen during the fly-in / death cutscene (boss stays visible)
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		# Safety net: never leave a boss part visible while idle, or the cluster just
		# sits there spinning its idle GIF and looks "stuck". (Tree is paused in edit
		# mode, so this never fights F4 placement.)
		if _active_body() != null:
			_show_only(null)
		return
	_tick_body_anim(delta)
	_tick_projectiles(delta)
	_update_orb_glow()   # rainbow shine that follows the orbs whenever they're visible

	# Stall safety net — only the main-phase moves (M1-M4), never Phase 2.
	# If a move runs past MOVE_HARD_CAP a sub-phase failed to advance, so recover.
	if _phase != Phase.P2_ENTRY and _phase != Phase.P2_ATTACK1 \
			and _phase != Phase.P2_ATTACK2 and _phase != Phase.P2_ATTACK3 \
			and _phase != Phase.P2_ATTACK4 and _phase != Phase.P2_ATTACK5:
		_move_watchdog += delta
		if _move_watchdog >= MOVE_HARD_CAP:
			_recover_stuck_move()
			return

	match _phase:
		Phase.M1_CRAWL:        _tick_m1(delta)
		Phase.M2_TRANSFORM:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m2_transform_done()
		Phase.M2_MOVE:         _tick_m2_move(delta)
		Phase.M2_SPIN:         _tick_m2_spin(delta)
		Phase.M2_RETURN:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m2_return_done()
		Phase.M3_CURL:         _tick_m3_curl(delta)
		Phase.M3_EJECT:        _tick_m3_eject(delta)
		Phase.M3_SPIRAL:       _tick_m3_spiral(delta)
		Phase.M4_TRANSFORM:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m4_transform_done()
		Phase.M4_SPIN:         _tick_m4_spin(delta)
		Phase.M4_CHARGE:       _tick_m4_charge(delta)
		Phase.M4_OFFSCREEN:    _tick_m4_offscreen(delta)
		Phase.M4_FINAL:        _tick_m4_final(delta)
		Phase.M4_RETURN:
			_anim_phase_timer += delta
			if _anim_phase_timer >= 15.0:
				_on_m4_return_done()
		Phase.P2_ATTACK1:      _tick_p2_attack1(delta)
		Phase.P2_ATTACK2:      _tick_p2_attack2(delta)
		Phase.P2_ATTACK3:      _tick_p2_attack3(delta)

# =============================================================================
# Body animation system
# =============================================================================

func _play_anim(tr: TextureRect, frames: Array, delays: Array, backward: bool, hold: bool) -> void:
	_anim_tr       = tr
	_anim_frames   = frames
	_anim_delays   = delays
	_anim_backward = backward
	_anim_hold     = hold
	_anim_idx      = frames.size() - 1 if backward else 0
	_anim_acc      = 0.0
	_anim_done     = false
	if not frames.is_empty():
		tr.texture = frames[_anim_idx] as Texture2D

func _tick_body_anim(delta: float) -> void:
	if _anim_tr == null or _anim_done or _anim_frames.is_empty():
		return
	_anim_acc += delta
	var d: float = float(_anim_delays[_anim_idx]) if _anim_idx < _anim_delays.size() else 0.05
	if _anim_acc < d:
		return
	_anim_acc -= d
	if _anim_backward:
		_anim_idx -= 1
	else:
		_anim_idx += 1
	if _anim_idx < 0 or _anim_idx >= _anim_frames.size():
		if _anim_hold:
			_anim_idx = clamp(_anim_idx, 0, _anim_frames.size() - 1)
			_anim_done = true
			anim_finished.emit()
		else:
			_anim_idx = (_anim_idx + _anim_frames.size()) % _anim_frames.size()
	if not _anim_done and is_instance_valid(_anim_tr):
		_anim_tr.texture = _anim_frames[_anim_idx] as Texture2D

# =============================================================================
# Shoot helpers
# =============================================================================

func _fire_ball_4dirs() -> void:
	if not is_instance_valid(_chromeball_eo):
		return
	var center := _chromeball_eo.global_position + _chromeball_eo.size / 2.0
	var base_dir: Vector2
	var origin: Vector2
	if _ball_fp_offset.length() > 1.5:
		origin   = center + _ball_fp_offset.rotated(_ball_angle)
		base_dir = _ball_fp_offset.normalized().rotated(_ball_angle)
	else:
		origin   = center
		base_dir = Vector2.UP.rotated(_ball_angle)
	var tex := _random_bullet()
	var bsz := _random_bullet_sz()
	for i in 4:
		var dir := base_dir.rotated(float(i) * PI / 2.0)
		_spawn_bullet(tex, origin, dir * BULLET_SPD, bsz)

func _fire_orb_nsew(eo: EditableObjectNode, fp_off: Vector2, rot: float, tex: Texture2D, dirs: Array, sz: Vector2) -> void:
	if tex == null or eo == null or not is_instance_valid(eo):
		return
	var center := eo.global_position + eo.size / 2.0
	var origin: Vector2
	if fp_off.length() > 1.5:
		origin = center + fp_off.rotated(rot)
	else:
		origin = center
	for d in dirs:
		_spawn_bullet(tex, origin, (d as Vector2) * ORB_BULLET_SPD, sz)

func _fire_orb_rotated(eo: EditableObjectNode, fp_off: Vector2, angle: float, tex: Texture2D, sz: Vector2) -> void:
	if tex == null or eo == null or not is_instance_valid(eo):
		return
	var center := eo.global_position + eo.size / 2.0
	var base_dir: Vector2
	var origin: Vector2
	if fp_off.length() > 1.5:
		origin   = center + fp_off.rotated(angle)
		base_dir = fp_off.normalized().rotated(angle)
	else:
		origin   = center
		base_dir = Vector2.UP.rotated(angle)
	for i in 4:
		var dir := base_dir.rotated(float(i) * PI / 2.0)
		_spawn_bullet(tex, origin, dir * ORB_BULLET_SPD, sz)

func _random_bullet() -> Texture2D:
	if _bullet_frames.is_empty():
		return null
	_last_cb_idx = randi() % _bullet_frames.size()
	# Return resized frame if available, fallback to raw frame
	if _last_cb_idx < _bullet_resized_frames.size():
		return _bullet_resized_frames[_last_cb_idx] as Texture2D
	return _bullet_frames[_last_cb_idx] as Texture2D

func _random_bullet_sz() -> Vector2:
	if _bullet_sizes.size() <= _last_cb_idx:
		return Vector2.ZERO
	var sz := _bullet_sizes[_last_cb_idx] as Vector2
	return sz if sz != Vector2.ZERO else Vector2(1.0, 1.0)

# =============================================================================
# Projectile system
# =============================================================================

func _spawn_bullet(tex: Texture2D, origin_vp: Vector2, vel: Vector2, sz: Vector2) -> void:
	if tex == null:
		return
	var lpos := origin_vp - OC_BOUNDS.position - sz / 2.0
	var tr      := TextureRect.new()
	tr.texture        = tex
	tr.size           = sz
	tr.stretch_mode   = TextureRect.STRETCH_KEEP  # texture is pre-resized CPU-side
	tr.pivot_offset   = sz / 2.0
	tr.position       = lpos
	tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.z_as_relative  = false
	tr.z_index        = 150
	_clip_node.add_child(tr)
	_projectiles.append({"tr": tr, "vel": vel, "dmg": 12})

func _tick_projectiles(delta: float) -> void:
	# Ship hitbox = the VISIBLE (scaled) ship as a circle, matching the green debug circle
	# the player dodges with — not the full unscaled EO rect (which is far bigger than the
	# shrunk ship during a boss fight and caused hits after a clean dodge).
	var ship_c := Vector2.INF
	var ship_r := 0.0
	if _ship_eo != null and is_instance_valid(_ship_eo):
		ship_c = _ship_eo.get_global_transform() * (_ship_eo.size * 0.5) - OC_BOUNDS.position
		ship_r = _ship_eo.size.x * 0.5 * _ship_eo.scale.x
	var clip_rect := Rect2(Vector2.ZERO, OC_BOUNDS.size)
	var i := _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var tr: TextureRect = p["tr"]
		if not is_instance_valid(tr):
			_projectiles.remove_at(i); i -= 1; continue
		tr.position += (p["vel"] as Vector2) * delta
		# Bullet hitbox = a circle tight to the diamond/hex visual (BULLET_HIT_FACTOR),
		# so the transparent corners of the square texture no longer register hits.
		if ship_r > 0.0:
			var bc := tr.position + tr.size * 0.5
			var br := minf(tr.size.x, tr.size.y) * 0.5 * BULLET_HIT_FACTOR
			if bc.distance_to(ship_c) <= ship_r + br:
				GameManager.ship_take_damage(int(p["dmg"]))
				_flash_ship_red()
				tr.queue_free()
				_projectiles.remove_at(i); i -= 1; continue
		var ctr := tr.position + tr.size / 2.0
		if not clip_rect.grow(60.0).has_point(ctr):
			tr.queue_free()
			_projectiles.remove_at(i)
		i -= 1

func _cleanup_projectiles() -> void:
	for p in _projectiles:
		var tr = p.get("tr")
		if tr != null and is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()

func _resize_tex(tex: Texture2D, target_sz: Vector2) -> Texture2D:
	# CPU-side resize (bilinear) → ImageTexture. Pattern: fixed-size bullets pre-cached.
	# Called by _resize_all_bullets() at load time; cached results reused on spawn.
	if tex == null or target_sz == Vector2.ZERO:
		return tex
	var img := tex.get_image()
	if img == null:
		return tex
	var copy := img.duplicate() as Image
	copy.resize(int(target_sz.x), int(target_sz.y), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(copy)

# =============================================================================
# EO helpers
# =============================================================================

func _detach_orbs() -> void:
	if _orbs_detached:
		return
	if _blueorb_eo == null or _tealorb_eo == null:
		return
	_orbs_detached = true
	var oc_gp := _objects_container.global_position
	if is_instance_valid(_blueorb_eo) and _blueorb_eo.get_parent() != _objects_container:
		var gp := _blueorb_eo.global_position
		_blueorb_eo.get_parent().remove_child(_blueorb_eo)
		_objects_container.add_child(_blueorb_eo)
		_blueorb_eo.position = gp - oc_gp
	if is_instance_valid(_tealorb_eo) and _tealorb_eo.get_parent() != _objects_container:
		var gp := _tealorb_eo.global_position
		_tealorb_eo.get_parent().remove_child(_tealorb_eo)
		_objects_container.add_child(_tealorb_eo)
		_tealorb_eo.position = gp - oc_gp
		_clamp_eo(_tealorb_eo, OC_BOUNDS.end.y)

func _reattach_orbs() -> void:
	if not _orbs_detached:
		return
	_orbs_detached = false
	var base := _chromeleon_eo if is_instance_valid(_chromeleon_eo) else _chromeleonbody_eo
	if base == null:
		return
	if is_instance_valid(_blueorb_eo) and _blueorb_eo.get_parent() == _objects_container:
		_objects_container.remove_child(_blueorb_eo)
		base.add_child(_blueorb_eo)
		_blueorb_eo.position = Vector2(-20.0, 0.0)
		_blueorb_eo.visible  = true
	if is_instance_valid(_tealorb_eo) and _tealorb_eo.get_parent() == _objects_container:
		_objects_container.remove_child(_tealorb_eo)
		base.add_child(_tealorb_eo)
		_tealorb_eo.position = Vector2(20.0, 0.0)
		_tealorb_eo.visible  = true

# The chromehead is a child of the cluster, so it must be detached (like the orbs) to be
# visible while the cluster is hidden AND so _tick_head's wander runs in objects-container space.
func _detach_head() -> void:
	if not is_instance_valid(_chromehead_eo) or _chromehead_eo.get_parent() == _objects_container:
		return
	var oc_gp := _objects_container.global_position
	var gp := _chromehead_eo.global_position
	_chromehead_eo.get_parent().remove_child(_chromehead_eo)
	_objects_container.add_child(_chromehead_eo)
	_chromehead_eo.position = gp - oc_gp

func _reattach_head() -> void:
	if not is_instance_valid(_chromehead_eo) or _chromehead_eo.get_parent() != _objects_container:
		return
	var base := _chromeleon_eo if is_instance_valid(_chromeleon_eo) else _chromeleonbody_eo
	if base == null:
		return
	_objects_container.remove_child(_chromehead_eo)
	base.add_child(_chromehead_eo)
	_chromehead_eo.position = Vector2.ZERO
	_chromehead_eo.visible  = false

func _detach_ball() -> void:
	if _ball_detached or not is_instance_valid(_chromeball_eo):
		return
	_ball_detached = true
	if _chromeball_eo.get_parent() == _objects_container:
		return
	var oc_gp := _objects_container.global_position
	var gp    := _chromeleon_eo.global_position + _chromeleon_eo.size / 2.0 - _chromeball_eo.size / 2.0
	var parent := _chromeball_eo.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(_chromeball_eo)
	_objects_container.add_child(_chromeball_eo)
	_chromeball_eo.position = gp - oc_gp

func _reattach_ball() -> void:
	if not _ball_detached or not is_instance_valid(_chromeball_eo):
		return
	_ball_detached = false
	if _chromeball_eo.get_parent() != _objects_container:
		return
	var ball_center_vp := _chromeball_eo.position + _objects_container.global_position + _chromeball_eo.size / 2.0
	_objects_container.remove_child(_chromeball_eo)
	if is_instance_valid(_chromeleon_eo):
		_chromeleon_eo.add_child(_chromeball_eo)
		_chromeball_eo.position = _ball_orig_local_pos
		# Position chromeleon so its center is at ball's last center
		_chromeleon_eo.position = ball_center_vp - _chromeleon_eo.size / 2.0
		_clamp_eo(_chromeleon_eo, OC_BOUNDS.end.y)
	_chromeball_eo.texture_rect.rotation = 0.0
	_chromeball_eo.visible = true
	_chromeball_eo.gif_paused = false   # restore EO's own GIF loop
	_chromeball_eo.reset_gif()

func _show_only(target: EditableObjectNode) -> void:
	for eo in [_chromeleon_eo, _chromeleonbody_eo, _chromehead_eo, _chromeball_eo, _blueorb_eo, _tealorb_eo]:
		if is_instance_valid(eo):
			eo.visible = (eo == target)

func _active_body() -> EditableObjectNode:
	if is_instance_valid(_chromehead_eo) and _chromehead_eo.visible:
		return _chromehead_eo
	if is_instance_valid(_chromeleonbody_eo) and _chromeleonbody_eo.visible:
		return _chromeleonbody_eo
	if is_instance_valid(_chromeball_eo) and _chromeball_eo.visible:
		return _chromeball_eo
	if is_instance_valid(_chromeleon_eo) and _chromeleon_eo.visible:
		return _chromeleon_eo
	return null

func _tick_wander(eo: EditableObjectNode, wp: Vector2, delta: float, spd: float, y_max: float) -> Vector2:
	if not is_instance_valid(eo):
		return wp
	var diff := wp - eo.position
	if diff.length() < spd * delta + 5.0:
		eo.position = wp
		return _pick_wander_wp(y_max)
	eo.position += diff.normalized() * spd * delta
	_clamp_eo(eo, y_max)
	return wp

func _clamp_eo(eo: EditableObjectNode, y_max: float) -> void:
	if not is_instance_valid(eo):
		return
	eo.position.x = clampf(eo.position.x, OC_BOUNDS.position.x, OC_BOUNDS.end.x - eo.size.x)
	eo.position.y = clampf(eo.position.y, OC_BOUNDS.position.y, y_max - eo.size.y)

func _pick_wander_wp(y_max: float) -> Vector2:
	return Vector2(
		randf_range(OC_BOUNDS.position.x + 40.0, OC_BOUNDS.end.x - 80.0),
		randf_range(OC_BOUNDS.position.y + 30.0, y_max - 40.0)
	)

func _pick_crawl_wp() -> Vector2:
	return _pick_wander_wp(Y_LIMIT)

func _ship_center() -> Vector2:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return OC_BOUNDS.get_center()
	# Use the transform (not global_position + size/2): the ship is scaled ~0.35 during
	# the fight and scaling around the centre pivot shifts global_position, which would
	# put this point well below the visible ship.
	return _ship_eo.get_global_transform() * (_ship_eo.size * 0.5)

func _head_center() -> Vector2:
	if not is_instance_valid(_chromehead_eo):
		return OC_BOUNDS.get_center()
	return _chromehead_eo.global_position + _chromehead_eo.size / 2.0

# Ship hitbox in viewport/OC space (scaled sprite AABB) — for the orb-laser damage corridor.
# Matches the M4 charge collision sizing (centre via real transform, half-size × scale).
func _ship_rect_vp() -> Rect2:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return Rect2()
	var sc := _ship_eo.get_global_transform() * (_ship_eo.size * 0.5)
	var half := _ship_eo.size * 0.5 * _ship_eo.scale.x
	return Rect2(sc - half, half * 2.0)

func _flash_ship_red() -> void:
	if _ship_eo == null or not is_instance_valid(_ship_eo):
		return
	var tw := create_tween()
	tw.tween_property(_ship_eo, "modulate", Color(2.0, 0.2, 0.2, 1.0), 0.05)
	tw.tween_property(_ship_eo, "modulate", Color.WHITE, 0.3)

func _get_ws() -> Node:
	return get_tree().get_first_node_in_group("weapon_system")

# =============================================================================
# EO discovery
# =============================================================================

func _find_eos() -> void:
	if _objects_container == null:
		return
	for child in _objects_container.get_children():
		var eo := child as EditableObjectNode
		if eo == null:
			continue
		var base := eo.source_path.get_file().get_basename().to_lower()
		if base == "spaceship":
			_ship_eo = eo
		elif base == "chromeleon":
			_chromeleon_eo = eo
			_find_chromeleon_children(eo)
		elif base == "spaceshiphitbox":
			eo.visible = false

func _find_chromeleon_children(base_eo: EditableObjectNode) -> void:
	for child in base_eo.get_children():
		var seo := child as EditableObjectNode
		if seo == null:
			continue
		var bname := seo.source_path.get_file().get_basename().to_lower()
		match bname:
			"blueorb":
				_blueorb_eo = seo
			"tealorb":
				_tealorb_eo = seo
			"chromeball":
				_chromeball_eo = seo
				_ball_orig_local_pos = seo.position
			"chromeleonbody":
				_chromeleonbody_eo = seo
			"chromehead":
				_chromehead_eo = seo

# =============================================================================
# Firepoint loading
# =============================================================================

func _load_fp_offsets() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://boss_layout.cfg") != OK:
		return
	if is_instance_valid(_chromeleon_eo):
		_main_fp_nodes = _build_fp_nodes(_chromeleon_eo, cfg.get_value("firepoints", "chromeleon", []))
	if is_instance_valid(_chromeball_eo):
		_ball_fp_nodes = _build_fp_nodes(_chromeball_eo, cfg.get_value("firepoints", "chromeleon_chromeball", []))
	if is_instance_valid(_blueorb_eo):
		_blue_fp_nodes = _build_fp_nodes(_blueorb_eo, cfg.get_value("firepoints", "chromeleon_blueorb", []))
	if is_instance_valid(_tealorb_eo):
		_teal_fp_nodes = _build_fp_nodes(_tealorb_eo, cfg.get_value("firepoints", "chromeleon_tealorb", []))

func _build_fp_nodes(parent_eo: EditableObjectNode, fp_data: Array) -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	if fp_data.is_empty():
		return nodes
	var boss_center := parent_eo.global_position + parent_eo.size / 2.0
	for fp: Dictionary in fp_data:
		var fp_oc: Vector2 = (fp.get("pos", Vector2.ZERO) as Vector2) + SS_OFFSET
		var offset := fp_oc - boss_center
		var n := Node2D.new()
		n.position = parent_eo.size / 2.0 + offset
		parent_eo.add_child(n)
		nodes.append(n)
	return nodes

func _cache_fp_offsets() -> void:
	if is_instance_valid(_chromeball_eo) and not _ball_fp_nodes.is_empty():
		var fp := _ball_fp_nodes[0]
		if is_instance_valid(fp):
			_ball_fp_offset = fp.position - _chromeball_eo.size / 2.0
	if is_instance_valid(_blueorb_eo) and not _blue_fp_nodes.is_empty():
		var fp := _blue_fp_nodes[0]
		if is_instance_valid(fp):
			_blue_fp_offset = fp.position - _blueorb_eo.size / 2.0
	if is_instance_valid(_tealorb_eo) and not _teal_fp_nodes.is_empty():
		var fp := _teal_fp_nodes[0]
		if is_instance_valid(fp):
			_teal_fp_offset = fp.position - _tealorb_eo.size / 2.0

# =============================================================================
# Asset loading
# =============================================================================

func _load_assets() -> void:
	# chromebullet1-12
	for i in range(1, 13):
		var bn   := "chromebullet%d" % i
		var path := "res://assets/bosses/chromeleon/%s.gif" % bn
		var tex := GifLoader.load_gif(path)
		if tex == null:
			tex = load(path) as Texture2D
		if tex == null:
			continue
		var frame: Texture2D = tex
		if tex.has_meta("gif_frames"):
			var frames: Array = tex.get_meta("gif_frames")
			if not frames.is_empty():
				frame = frames[0] as Texture2D
		_bullet_frames.append(frame)
		var native_sz := frame.get_size() if frame != null else Vector2.ZERO
		_bullet_native_sizes.append(native_sz)
		_bullet_sizes.append(native_sz)  # will be overwritten by _reload_bullet_sizes() if F5 defines size

	# chromeball animation
	var ball_tex := GifLoader.load_gif("res://assets/bosses/chromeleon/chromeball.gif")
	if ball_tex != null:
		if ball_tex.has_meta("gif_frames"):
			_ball_frames = ball_tex.get_meta("gif_frames")
		if ball_tex.has_meta("gif_delays"):
			_ball_delays = ball_tex.get_meta("gif_delays")

	# chromeleonbody animation (for M3 projectiles)
	var body_tex := GifLoader.load_gif("res://assets/bosses/chromeleon/chromeleonbody.gif")
	if body_tex != null:
		if body_tex.has_meta("gif_frames"):
			_body_frames = body_tex.get_meta("gif_frames")
		if body_tex.has_meta("gif_delays"):
			_body_delays = body_tex.get_meta("gif_delays")

	# bluebullet
	var bt := GifLoader.load_gif("res://assets/bosses/chromeleon/bluebullet.gif")
	if bt == null:
		bt = load("res://assets/bosses/chromeleon/bluebullet.gif") as Texture2D
	if bt != null:
		var bframes: Array = bt.get_meta("gif_frames") if bt.has_meta("gif_frames") else []
		if not bframes.is_empty():
			_blue_bullet_tex = bframes[0] as Texture2D
		else:
			_blue_bullet_tex = bt
		_blue_bullet_native_size = _blue_bullet_tex.get_size() if _blue_bullet_tex != null else Vector2.ZERO
		_blue_bullet_size = _blue_bullet_native_size

	# tealbullet
	var tt := GifLoader.load_gif("res://assets/bosses/chromeleon/tealbullet.gif")
	if tt == null:
		tt = load("res://assets/bosses/chromeleon/tealbullet.gif") as Texture2D
	if tt != null:
		var tframes: Array = tt.get_meta("gif_frames") if tt.has_meta("gif_frames") else []
		if not tframes.is_empty():
			_teal_bullet_tex = tframes[0] as Texture2D
		else:
			_teal_bullet_tex = tt
		_teal_bullet_native_size = _teal_bullet_tex.get_size() if _teal_bullet_tex != null else Vector2.ZERO
		_teal_bullet_size = _teal_bullet_native_size

func _reload_bullet_sizes() -> void:
	# Sizes come from the BULLET_SIZES const (native texture size only as a last resort),
	# so bullet rendering no longer depends on decorative layout objects in boss_layout.cfg.
	for i in _bullet_frames.size():
		var bn := "chromebullet%d" % (i + 1)
		var native_fallback: Vector2 = _bullet_native_sizes[i] if i < _bullet_native_sizes.size() else Vector2.ZERO
		if i < _bullet_sizes.size():
			_bullet_sizes[i] = BULLET_SIZES.get(bn, native_fallback) as Vector2

	_blue_bullet_size = BULLET_SIZES.get("bluebullet", _blue_bullet_native_size) as Vector2
	_teal_bullet_size = BULLET_SIZES.get("tealbullet", _teal_bullet_native_size) as Vector2

	# Pre-cache resized bullet frames
	_resize_all_bullets()

func _resize_all_bullets() -> void:
	# Resize chromebullets
	_bullet_resized_frames.clear()
	for i in _bullet_frames.size():
		var frame: Texture2D = _bullet_frames[i]
		var sz: Vector2 = _bullet_sizes[i] if i < _bullet_sizes.size() else Vector2.ZERO
		var resized := _resize_tex(frame, sz) if sz != Vector2.ZERO else frame
		_bullet_resized_frames.append(resized)

	# Resize blue/teal bullets
	_blue_bullet_resized = _resize_tex(_blue_bullet_tex, _blue_bullet_size) if _blue_bullet_size != Vector2.ZERO else _blue_bullet_tex
	_teal_bullet_resized = _resize_tex(_teal_bullet_tex, _teal_bullet_size) if _teal_bullet_size != Vector2.ZERO else _teal_bullet_tex
