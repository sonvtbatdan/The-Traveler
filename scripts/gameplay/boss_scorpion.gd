extends Node2D
## Boss: the animated 3D scorpion, as a world-space actor for boss_fight_test.
##
## Renders Scorpion.glb in a SubViewport shown on a Sprite2D (same 3D→2D bridge as the player ship),
## is shootable by the player's weapons (group "arena_enemy" + take_damage), and runs attack "moves".
##
## MOVE 1 ("track & drill"):
##   TRACK phase (TRACK_TIME s) — play "Head bobbing", tilt left/right, and slide horizontally to stay
##     aligned with the player's X (mirrors the player so they can't just walk out from under it).
##   CHARGE phase — accelerate hard toward the player while spinning about the model's long axis (X),
##     like a drill. On reaching the player (or timing out) it loops back to TRACK.
##
## Model axes (from the user's reference): X = long axis (head↔tail) · Z = up↔down · Y = depth.

const MODEL_PATH := "res://assets/3D models/Boss_Scorpion_1.glb"
const MUZZLE_CFG := "res://scorpion_muzzles.cfg"
const VIEWS_CFG  := "res://scorpion_views.cfg"   # named orientations (front/side/top) from test_boss_scorpion
const ArenaEnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")   # real fly/bug/bee enemies
const ArenaExplosion   := preload("res://scripts/gameplay/arena_explosion.gd")   # death pop (same as the Elephant)
const VP_SIZE    := 320
const DISPLAY_PX := 364.0     # on-screen size of the boss (30% smaller than the original 520)

# ── Entrance cinematic (plays ONCE at spawn, before Move 1; NO HP bar until it lands) ──
# Beat 1: THREE huge near-silhouette "shadows" streak across the screen, each a different angle, 2s apart.
# Beat 2: it enters from behind (7 o'clock) up high, then carves one long curve DOWN to the 3 o'clock home.
const INTRO_PASSES     := 3                       # shadow fly-bys before the real entrance
const INTRO_PASS_TIME  := 0.5                     # seconds per pass (fast streak)
const INTRO_PASS_GAP   := 2.0                     # seconds off-screen between passes
const INTRO_PASS_SCALE := 4.0                     # HUGE near-silhouette during the passes
const INTRO_PASS_SPAN  := 1500.0                  # half-length of each straight pass line (px)
const INTRO_PASS_ANGLES := [30.0, 150.0, 90.0]    # heading (deg) of each pass — all different
const INTRO_DIVE_TIME  := 2.0                     # seconds for the long banking descent
# The dive curve is defined RELATIVE to the player and re-evaluated every frame, so the whole descent
# tracks the ship and lands at INTRO_HOME_DIST out toward 3 o'clock (an arbitrary tethered point).
const INTRO_DIVE_START_OFF := Vector2(-720.0, 560.0)   # 7 o'clock — behind & left, off-screen
const INTRO_DIVE_C1_OFF    := Vector2(-520.0, -780.0)  # shoots UP HIGH on the left/back
const INTRO_DIVE_C2_OFF    := Vector2(520.0, -700.0)   # over the top toward the right, still high
const INTRO_HOME_DIST      := 500.0                    # lands + tethers this far out at 3 o'clock
const INTRO_DARK       := Color(0.05, 0.05, 0.09, 0.80)   # near-black, slightly see-through shadow
const INTRO_TRAIL_GHOSTS := 3                     # motion-smear afterimages during the fast pass (0 = off)

# ── Look (matches test_boss_scorpion) ──
const METALLIC_MULT := 0.55
const HUE_SHIFT   := 0.0
const SATURATION  := 0.85
const VALUE       := 1.35
const WHITEN_GRAYS := 0.95          # how far the gray/white parts mix toward pure white (was 0.9 — a touch whiter)
const GRAY_BRIGHT  := 1.4           # extra brightness multiplier on the gray/white parts only (+40%)
const PULSE_SPEED  := 3.0           # red-part "living" pulse speed
const PULSE_AMOUNT := 1.4           # red-part emission strength (the pulse glow)
const GRAY_SAT_MAX := 0.22
const DARKEN_REDS  := 0.70
const RED_TARGET   := Color("880000")
const RED_HUE_BAND := 0.07
const RED_SAT_MIN  := 0.35

# ── Orientation (tune so the FACE points at the camera / player) ──
# Fallback base facing, only used if scorpion_views.cfg has no saved "side" view yet.
const BASE_YAW_DEG   := 0.0
const BASE_PITCH_DEG := 0.0
const BASE_ROLL_DEG  := 0.0
# ── Move 1 behaviour ──
const HOME_OFFSET := 360.0     # distance to the side of the player it zooms to (3/9 o'clock)
const TRACK_TIME  := 5.0       # aiming phase length
const HOME_LERP   := 6.0       # how fast it zooms to the side position
const TILT_DEG    := 70.0      # rock amplitude each way (leans in the screen plane, stays upright)
const ROCK_SEG    := 0.9       # seconds per left/right rock beat
const LEAN_EASE   := 200.0     # deg/s the rock eases between beats (higher = snappier)
const BURST_COUNT    := 3      # laser bolts per burst
const BURST_INTERVAL := 0.1    # seconds between bolts within a burst
const BURST_PAUSE    := 1.0    # pause after each 3-shot burst
const BOLT_SPEED  := 950.0     # laser bolt speed (px/s)
const CHARGE_ACCEL := 1400.0   # px/s^2 (accel + decel)
const CHARGE_MAX   := 1700.0   # px/s (bullet-fast charge)
const CHARGE_MIN   := 320.0    # px/s while turning around (slow → tight arc)
const TURN_RATE    := 4.0      # rad/s heading turn rate (snake-like); slow speed makes the arc tighter
const AIM_DOT      := 0.6      # re-accelerate once heading is within ~53° of the player (front Z on target)
const CHARGE_PASSES := 3       # charge/turn passes before returning to the aiming phase
const M1_OFFSCREEN   := 950.0   # distance from the player that counts as off-screen
const M1_REAIM_DELAY := 1.0     # only start turning back after this long off-screen
const SPIN_DPS     := 2250.0   # drill-spin at full charge speed; scales down with speed while turning
const WINDUP_TIME  := 1.0      # spin in place this long before launching the charge
const REACH_DIST   := 60.0     # distance that counts as a "pass" through the player

# ── Move 2 ──
const M2_HOME_OFFSET := 340.0   # vertical standoff (12/6 o'clock)
const M2_CHASE_LERP  := 3.0     # how fast it follows the player while flaming
const M2_FLAME_FWD   := 800.0   # chasing flame reach (px)
const M2_RING_RADIUS := 400.0   # ring radius around the player (800px diameter)
const M2_RING_HOLD   := 10.0    # ring of fire lingers this long after the attack ends
const M2_SPIN_HZ     := 3.0     # Z rotations per second during the window
const M2_CIRCLE_FORM := 2.0     # seconds for the full ring to close
const M2_CIRCLE_WAIT := 1.0     # wait after the ring forms before charging
const M2_CHARGE_SPEED := 1500.0 # px/s charge speed (fire + spin stay on)
const M2_OFFSCREEN_DIST := 1150.0  # distance from the player that counts as off-screen → attack ends
const M2_RADIAL_REACH := 260.0  # reach of the all-muzzle fire (short → pools & envelops the boss body)
const MUZZLE_JET_AMOUNT := 900  # particles per muzzle jet (high → dense fiery shroud around the boss)
# Fire look — the chase jet and the ring are tuned separately so they READ as the same intensity
# (the ring packs particles denser along the circle, so it needs slightly lower values to match).
const JET_AMOUNT    := 900
const JET_INTENSITY := 0.875   # chase flame brightness (was 1.25 → dialed down ~30%)
const JET_GLOW      := 0.245
const JET_SPREAD    := 9.0      # ± degrees — modest fan so the stream flares into a cone
const JET_SIZE_MIN  := 22.0     # small at the muzzle (near the boss)
const JET_SIZE_MAX  := 40.0
const JET_GROW      := 3.0      # particles balloon 3× over their flight → megaphone (small→boss, big→player)
const M2_AIM_LAG    := 3.0      # chase-flame aim tracks the ship this fast (lower = laggier/less accurate)
const RING_AMOUNT    := 1600   # big circumference → needs many particles to look dense/full
const RING_INTENSITY := 0.95
const RING_GLOW      := 0.30
const RING_SIZE_MIN  := 60.0
const RING_SIZE_MAX  := 120.0

# ── Move 3 ──
const M3_RADIUS      := 500.0   # orbit radius around the player
const M3_ROT_TIME    := 6.0     # seconds per full rotation
const M3_ROTATIONS   := 3       # flies (rot 1) → bugs (rot 2) → bees (rot 3)
const M3_SPAWN_RATE  := 10.0    # spawns per second
const M3_SPAWN_MUZZLE := 4
const SPAWNING_CLIP  := "Spawning stuff"
const M3_ENEMY_IDS := ["fly", "bug", "bee"]   # rotation 1 / 2 / 3
const M3_ENEMY_DEFS := {
	"fly": {"behavior": "chase", "hp": 20.0,   "speed": 120.0, "size": 7.2,  "contact": 2, "explodes": true, "xp": 10.0,  "icon": "res://assets/enemiesHD/flie1.png"},
	"bug": {"behavior": "chase", "hp": 200.0,  "speed": 100.0, "size": 15.4, "contact": 3, "explodes": true, "xp": 50.0,  "icon": "res://assets/enemiesHD/animalbug.png"},
	"bee": {"behavior": "chase", "hp": 1000.0, "speed": 110.0, "size": 12.0, "contact": 3, "explodes": true, "xp": 100.0, "icon": "res://assets/enemiesHD/animalbee.png"},
}

# ── Move 4 ──
const M4_HOME_OFFSET := 340.0   # 6 o'clock standoff (below the player)
const M4_HOLD_FRAME  := 12.0    # hold Tail_open at this frame
const M4_CHARGE_TIME := 1.0     # energy-converge charge
const M4_BEAM_TIME   := 1.0     # fire straight up (at the player) this long
const M4_SWEEP_TIME  := 4.33    # each full CW / CCW sweep (turn rate +20%)
const M4_SPINFIRE_TIME := 5.0   # final fast spin
const M4_SPIN_HZ     := 3.0     # final spin speed (rotations/sec)
const M4_BIG_LEN     := 3000.0  # big beam length (px)
const M4_SMALL_LEN   := 1200.0  # short-beam length (px)
const M4_SMALL_INTERVAL := 0.04  # seconds between particle bursts (5× more particles)
const M4_BURST_COUNT := 4       # bullets per burst (a fixed fan → clean spiral arms)
const M4_FAN_STEP    := 0.16    # radians between bullets in the fan (fixed = structured/dodgeable)
const M4_PARTICLE_SPEED := 480.0
const M4_PARTICLE_RANGE := 1300.0  # bullets travel this far (further + longer-lived)
const M4_BEAM_MUZZLE := 5
const TAIL_CLIP      := "Tail_open"
const M4_ANIM_FPS    := 30.0
const M2_FRAME_LO    := 120.0   # Prolonged_Flapping frame window for spin + ring
const M2_FRAME_HI    := 240.0
const M2_ANIM_FPS    := 30.0
const M2_END_FRAME   := 301.0

const RECOLOR_SHADER := """
shader_type spatial;
render_mode cull_disabled;   // render both sides so single-sided faces (opened tail) don't vanish
uniform sampler2D albedo_tex : source_color;
uniform sampler2D orm_tex : hint_default_white;
uniform bool has_orm;
uniform float metallic_val;
uniform float roughness_val;
uniform float metallic_mult;
uniform sampler2D normal_tex : hint_normal;
uniform bool has_normal;
uniform float hue_shift;
uniform float sat_mul;
uniform float val_mul;
uniform float white_amt;
uniform float gray_bright;
uniform float gray_sat_max;
uniform vec3 red_target : source_color;
uniform float red_amt;
uniform float red_hue_band;
uniform float red_sat_min;
uniform float pulse_speed;
uniform float pulse_amount;
varying vec3 vloc;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void vertex() { vloc = VERTEX; }
void fragment() {
	vec3 orig = texture(albedo_tex, UV).rgb;
	vec3 h = rgb2hsv(orig);
	float gray_mask = (1.0 - smoothstep(gray_sat_max * 0.5, gray_sat_max, h.y)) * smoothstep(0.15, 0.5, h.z);
	float hue_dist = min(h.x, 1.0 - h.x);
	float red_mask = (1.0 - smoothstep(0.0, red_hue_band, hue_dist)) * smoothstep(red_sat_min * 0.5, red_sat_min, h.y);
	h.x = fract(h.x + hue_shift);
	h.y = clamp(h.y * sat_mul, 0.0, 1.0);
	h.z = h.z * val_mul;
	vec3 col = clamp(hsv2rgb(h), 0.0, 1.0);
	col = mix(col, vec3(1.0), clamp(gray_mask * white_amt, 0.0, 1.0));
	col = clamp(col * mix(1.0, gray_bright, gray_mask), 0.0, 1.0);   // brighten the gray/white parts only
	col = mix(col, red_target, clamp(red_mask * red_amt, 0.0, 1.0));
	ALBEDO = col;
	// living pulse: the red parts glow, pulsing over time with spatial variation
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed + vloc.x * 6.0 + vloc.y * 9.0 + vloc.z * 4.0);
	EMISSION = red_target * red_mask * pulse * pulse_amount;
	float m = metallic_val;
	float r = roughness_val;
	if (has_orm) {
		vec4 orm = texture(orm_tex, UV);
		r = orm.g;
		m = orm.b;
	}
	METALLIC = clamp(m * metallic_mult, 0.0, 1.0);
	ROUGHNESS = r;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
}
"""

# targetable interface (so the player's gatling can lock + hit it)
var hit_radius: float = DISPLAY_PX * 0.35
var _hp: float = 4000.0
var _hp_max: float = 4000.0
# ── Arena boss stats (set by configure() when the wave director spawns it) ──
var _armor: float = 0.0
var _xp: float = 30.0
var _mgr: Node = null
var _dead: bool = false

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _spr: Sprite2D
var _muzzle_anchors: Dictionary = {}
var _flash: float = 0.0

# move state
enum { TRACK, WINDUP, CHARGE, M2_ZOOM, M2_CHASE, M2_CIRCLE, M2_CHARGE, M3_ORBIT,
	M4_ZOOM, M4_CHARGE, M4_BEAM, M4_SWEEP_CW, M4_SWEEP_CCW, M4_SPINFIRE,
	INTRO_PASS, INTRO_DIVE }
var _state: int = INTRO_PASS   # the entrance cinematic runs first, then hands off to the moveset
# ── Move selection (driven by the panel in boss_fight_test) ──
const MOVE_META := [
	{ "id": "m1", "name": "Move 1 — Drill Charge", "desc": "Zoom to 3/9 o'clock; rock + 3-shot laser bursts; spin up; then homing bullet-charges (3 passes)." },
	{ "id": "m2", "name": "Move 2 — Flame Chase", "desc": "Zoom to 12/6; chase while flapping + spitting flame; mid-animation it spins (Z) and the flame coils into a ring." },
	{ "id": "m3", "name": "Move 3 — Swarm Spawner", "desc": "Circles the player at 500px for 3 rotations (6s each), spawning chasers at 10/s from a muzzle: flies, then bugs, then bees." },
	{ "id": "m4", "name": "Move 4 — Laser Sweep", "desc": "Zoom to 6 o'clock; charge; fire a 3000px laser up, sweep it CW then CCW (4s each) about Y, then fast-spin (3/s, 3s) firing short beams every 0.2s." },
]
const PROLONGED_CLIP := "Prolonged_Flapping"
var _enabled: Dictionary = { "m1": true, "m2": true }
var _move: String = ""
var _move_idx: int = -1
# Move 2 state
var _m2_cx: float = 1.0        # nearest corner: X side (±1)
var _m2_cy: float = -1.0       # nearest corner: Y side (±1)
var _m3_ang: float = 0.0       # current orbit angle
var _m3_total: float = 0.0     # total angle swept (3 * TAU = done)
var _spawn_acc: float = 0.0
var _beam_ang: float = 0.0     # Move 4 laser direction (screen angle)
var _beam_ang0: float = 0.0    # base direction; the sweep = a roll about X from here (gimbal-free)
var _beam_on: bool = false     # draw the big beam
var _charge_t: float = 0.0     # 0..1 energy-converge
var _small_beams: Array = []   # short beams from the final spin: { org, ang, life }
var _small_acc: float = 0.0
var _flame_on: bool = false
var _flame_circle: bool = false
var _flame_org: Vector2 = Vector2.ZERO
var _flame_center: Vector2 = Vector2.ZERO   # the ring encircles this (the player), frozen at phase start
var _flame_aim: Vector2 = Vector2.RIGHT
var _circle_t: float = 0.0
var _circle_locked: bool = false
var _held_active: bool = false    # (legacy placeholder — the ring is now a real DynamicFire node)
var _held_t: float = 0.0
var _held_center: Vector2 = Vector2.ZERO
var _ring: DynamicFire = null     # the real elephant flame VFX for the circle of fire
var _jet: DynamicFire = null      # continuous flamethrower streaming out of muzzle 4
var _all_jets: Dictionary = {}    # one flamethrower per muzzle (spin/charge phase — fire from all points)
var _t: float = 0.0
var _spin: float = 0.0
var _lean: float = 0.0
var _side: float = 1.0          # +1 = right (3 o'clock), -1 = left (9 o'clock) — chosen per attack
var _side_chosen: bool = false
var _speed: float = 0.0
var _charge_dir: Vector2 = Vector2.DOWN   # heading — his front Z points along this while charging
var _was_near: bool = false
var _pass_count: int = 0
var _offscreen_t: float = 0.0   # time spent off-screen this charge pass
var _views: Dictionary = {}   # "aligned" -> Quaternion, loaded from scorpion_views.cfg
# ── Entrance cinematic state ──
var _intro_init: bool = false
var _intro_t: float = 0.0
var _intro_pass_i: int = 0         # which shadow pass (0..INTRO_PASSES-1)
var _intro_waiting: bool = false   # true during the 2s off-screen gap between passes
var _base_scale: float = 1.0        # normal (combat) sprite scale = DISPLAY_PX / VP_SIZE
var _intro_p0: Vector2              # current pass line start / end (off-screen → off-screen)
var _intro_p1: Vector2
var _intro_roll: float = 0.0
var _intro_trail: Array = []       # ghost Sprite2D afterimages
var _bolts: Array = []        # laser bolts fired during aiming: { pos, vel, life }
var _fire_acc: float = 0.0
var _burst_shot: int = 0      # bolts fired in the current burst (0..BURST_COUNT)


## Wave-director boss contract (mirrors arena_elephant.configure): read stats from the ENEMY_DEFS entry.
## Called BEFORE _ready(). In the arena the full moveset runs (the panel only exists in boss_fight_test).
func configure(_type_id: String, mgr: Node, def: Dictionary = {}) -> void:
	_mgr = mgr
	_hp_max = float(def.get("hp", _hp_max))
	_hp = _hp_max
	_armor = float(def.get("armor", 0.0))
	_xp = float(def.get("xp", 30.0))
	_enabled = { "m1": true, "m2": true, "m3": true, "m4": true }   # exact spec = the full 4-move set

func _ready() -> void:
	z_index = 40
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("enemy_manager")
	# During the entrance the boss is a STRICTLY cosmetic "shadow": it is NOT in the "arena_enemy"/"boss"
	# groups (so weapons can't target it and nothing collides), and boss HP is force-cleared to 0 (so no
	# HP bar anywhere). Both the groups and the HP are registered in _end_intro() the moment it lands.
	GameManager.boss_hp = 0
	GameManager.boss_max_hp = 0
	if GameManager.has_signal("boss_hp_changed"):
		GameManager.boss_hp_changed.emit(0)
	_load_views()
	_build_viewport()
	_spr = Sprite2D.new()
	_spr.texture = _vp.get_texture()
	_base_scale = DISPLAY_PX / float(VP_SIZE)
	_spr.scale = Vector2(_base_scale, _base_scale)
	add_child(_spr)
	_jet = DynamicFire.new()
	_jet.free_form = true   # driven by set_stream()/set_points() — a muzzle flamethrower
	_jet.z_index = 30
	_jet.size_grow = JET_GROW   # megaphone: particles balloon as they travel toward the player
	_style_fire(_jet, JET_AMOUNT, JET_INTENSITY, JET_GLOW, JET_SIZE_MIN, JET_SIZE_MAX)
	add_child(_jet)
	_move = "intro"   # hold off the moveset until the entrance cinematic finishes (see _process)
	_play(PROLONGED_CLIP)
	_apply_model(_view("aligned"), 0.0, Vector2(-_side, 0.0), true)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var ppos := player.global_position if player != null else global_position - Vector2(HOME_OFFSET * _side, 0.0)

	if _move == "":
		_start_next_move(ppos)

	match _state:
		INTRO_PASS:
			if not _intro_init:
				_intro_begin(ppos)
			_intro_t += delta
			if _intro_waiting:
				# off-screen gap between passes — invisible, no shadow shown
				_spr.visible = false
				_clear_trail()
				if _intro_t >= INTRO_PASS_GAP:
					_intro_pass_i += 1
					_intro_t = 0.0
					_spr.visible = true
					if _intro_pass_i >= INTRO_PASSES:
						_intro_dive_begin(ppos)          # all passes done → the real entrance
					else:
						_intro_setup_pass(ppos, _intro_pass_i)
						_intro_waiting = false
			else:
				var pu: float = clampf(_intro_t / INTRO_PASS_TIME, 0.0, 1.0)
				var newpos := _intro_p0.lerp(_intro_p1, pu)
				var vel := newpos - global_position
				global_position = newpos
				var pdir := vel if vel.length() > 1.0 else (_intro_p1 - _intro_p0)
				_spr.scale = Vector2(_base_scale * INTRO_PASS_SCALE, _base_scale * INTRO_PASS_SCALE)
				_spr.modulate = INTRO_DARK               # HUGE near-silhouette, right in your face
				_intro_roll = clampf(pdir.angle() * 0.15, -0.5, 0.5)
				_apply_model(_view("aligned"), _intro_roll, pdir, false, Vector3(0.0, 0.0, 1.0))
				_update_trail(pdir)
				if pu >= 1.0:
					_clear_trail()
					_intro_waiting = true                # streak done → wait the gap, then next pass
					_intro_t = 0.0
		INTRO_DIVE:
			_intro_t += delta
			var du: float = clampf(_intro_t / INTRO_DIVE_TIME, 0.0, 1.0)
			var due := _ease_out_cubic(du)
			# rebuild the curve from the CURRENT player pos each frame → the whole dive tracks the ship,
			# landing at INTRO_HOME_DIST toward 3 o'clock (tethered to wherever the player is).
			var bp := _bezier3(ppos + INTRO_DIVE_START_OFF, ppos + INTRO_DIVE_C1_OFF,
				ppos + INTRO_DIVE_C2_OFF, ppos + Vector2(INTRO_HOME_DIST, 0.0), due)
			var dvel := bp - global_position
			global_position = bp
			var f: float = lerpf(INTRO_PASS_SCALE, 1.0, due)          # shrink onto the player's plane
			_spr.scale = Vector2(_base_scale * f, _base_scale * f)
			_spr.modulate = INTRO_DARK.lerp(Color(1.0, 1.0, 1.0, 1.0), due)   # brighten out of shadow
			# Ease the model from the top-down flight pose into Move 1's EXACT combat pose over the last
			# ~45% of the dive, so touchdown == the attack's first frame: Z→player, Y up (world-up), no roll.
			var flight_dir := dvel if dvel.length() > 1.0 else (ppos + Vector2(INTRO_HOME_DIST, 0.0) - bp)
			var to_player := ppos - bp
			var w: float = smoothstep(0.55, 1.0, due)
			var aim := flight_dir.normalized().lerp(to_player.normalized(), w)
			if aim.length() < 0.01:
				aim = to_player
			var up_ref := Vector3(0.0, 0.0, 1.0).lerp(Vector3(0.0, 1.0, 0.0), w).normalized()   # top-down → world-up
			var roll := lerpf(clampf(flight_dir.angle() * 0.10, -0.4, 0.4), 0.0, w)               # bank → level
			_apply_model(_view("aligned"), roll, aim, false, up_ref)
			if du >= 1.0:
				_end_intro()
		TRACK:
			_t += delta
			if not _side_chosen:
				_side = 1.0 if global_position.x >= ppos.x else -1.0   # zoom to the CLOSER of 3/9 o'clock
				_side_chosen = true
			var home := ppos + Vector2(HOME_OFFSET * _side, 0.0)
			global_position = global_position.lerp(home, clampf(HOME_LERP * delta, 0.0, 1.0))
			# rock about his Z axis (the ship-pointing axis), like the charge — alternating each ROCK_SEG
			var beat := int(_t / ROCK_SEG)
			var target := -1.0 if (beat % 2 == 0) else 1.0
			_lean = move_toward(_lean, target * deg_to_rad(TILT_DEG), deg_to_rad(LEAN_EASE) * delta)
			_apply_model(_view("aligned"), _lean, ppos - global_position, false)
			# fire in 3-shot bursts from muzzle 1, then pause 1s, throughout the aiming phase
			_fire_acc += delta
			if _burst_shot < BURST_COUNT:
				if _fire_acc >= BURST_INTERVAL:
					_fire_acc -= BURST_INTERVAL
					_fire_bolt(ppos)
					_burst_shot += 1
					if _burst_shot >= BURST_COUNT:
						_fire_acc = 0.0   # begin the pause
			elif _fire_acc >= BURST_PAUSE:
				_fire_acc = 0.0
				_burst_shot = 0
			if _t >= TRACK_TIME:
				_state = WINDUP
				_t = 0.0
				_spin = 0.0
				_speed = 0.0
		WINDUP:
			_t += delta
			_spin += deg_to_rad(SPIN_DPS) * delta   # spin up in place, still facing the ship
			_apply_model(_view("aligned"), _spin, ppos - global_position, false)
			if _t >= WINDUP_TIME:
				_state = CHARGE
				_t = 0.0
				_speed = 0.0
				_pass_count = 0
				_was_near = false
				_offscreen_t = 0.0
				_charge_dir = (ppos - global_position).normalized()
		CHARGE:
			_t += delta
			# straight-line charge — NO homing/tracking; drill spins as it flies
			_speed = move_toward(_speed, CHARGE_MAX, CHARGE_ACCEL * delta)
			global_position += _charge_dir * _speed * delta
			_spin += deg_to_rad(SPIN_DPS) * (_speed / CHARGE_MAX) * delta
			_apply_model(_view("aligned"), _spin, _charge_dir, false)
			# once he's been off-screen for M1_REAIM_DELAY, charge back in at a
			# random angle within ±30° of the reverse of the direction he exited
			var dist := global_position.distance_to(ppos)
			if dist > M1_OFFSCREEN:
				_offscreen_t += delta
				if _offscreen_t >= M1_REAIM_DELAY:
					_offscreen_t = 0.0
					_pass_count += 1
					if _pass_count >= CHARGE_PASSES:
						_end_move(ppos)
					else:
						_charge_dir = (-_charge_dir).rotated(randf_range(-deg_to_rad(30.0), deg_to_rad(30.0)))
			else:
				_offscreen_t = 0.0
		M2_ZOOM:
			_t += delta
			if not _side_chosen:
				_m2_cx = 1.0 if global_position.x >= ppos.x else -1.0   # approach from the nearest corner
				_m2_cy = 1.0 if global_position.y >= ppos.y else -1.0
				_side_chosen = true
			var m2home := ppos + Vector2(M2_HOME_OFFSET * _m2_cx, M2_HOME_OFFSET * _m2_cy)
			global_position = global_position.lerp(m2home, clampf(HOME_LERP * delta, 0.0, 1.0))
			_apply_model(_view("aligned"), 0.0, ppos - global_position, false, Vector3(0.0, 0.0, 1.0))
			if global_position.distance_to(m2home) < 30.0 or _t > 1.5:
				_state = M2_CHASE
				_t = 0.0
				_spin = 0.0
				_circle_t = 0.0
		M2_CHASE:
			_t += delta
			var chome := ppos + Vector2(M2_HOME_OFFSET * _m2_cx, M2_HOME_OFFSET * _m2_cy)
			global_position = global_position.lerp(chome, clampf(M2_CHASE_LERP * delta, 0.0, 1.0))
			_apply_model(_view("aligned"), 0.0, ppos - global_position, false, Vector3(0.0, 0.0, 1.0))
			# chasing flamethrower from muzzle 4
			_flame_on = true
			var mzc := muzzle_world(4)
			_flame_org = mzc
			var fac := ppos - mzc
			if fac.length() > 1.0:
				# lag the aim so the cone trails the ship instead of locking on (less accurate)
				_flame_aim = _flame_aim.lerp(fac.normalized(), clampf(M2_AIM_LAG * delta, 0.0, 1.0))
				if _flame_aim.length() > 0.001:
					_flame_aim = _flame_aim.normalized()
			_drive_jet(mzc, _flame_aim.angle(), M2_FLAME_FWD)
			if _t * M2_ANIM_FPS >= M2_FRAME_LO:
				_state = M2_CIRCLE            # enter the circle phase: freeze, spin, spawn the ring
				_t = 0.0
				_spin = 0.0
				_flame_center = ppos
				_flame_org = muzzle_world(4)
				_spawn_fire_ring(_flame_center, _flame_org)
		M2_CIRCLE:
			_t += delta
			_spin += TAU * M2_SPIN_HZ * delta               # spin in place while the ring forms
			_apply_model(_view("aligned"), _spin, ppos - global_position, false, Vector3(0.0, 0.0, 1.0))
			_flame_on = true
			var reachc := maxf(60.0, (_flame_center - _flame_org).length() - M2_RING_RADIUS)
			_drive_jet(_flame_org, (_flame_center - _flame_org).angle(), reachc)
			if _t >= M2_CIRCLE_FORM + M2_CIRCLE_WAIT:       # ring formed + 1s wait → charge
				_state = M2_CHARGE
				_t = 0.0
				_charge_dir = (ppos - global_position).normalized()
				if _charge_dir.length() < 0.01:
					_charge_dir = Vector2.DOWN
		M2_CHARGE:
			_t += delta
			_spin += TAU * M2_SPIN_HZ * delta               # fire + spin stay on during the charge
			global_position += _charge_dir * M2_CHARGE_SPEED * delta
			_apply_model(_view("aligned"), _spin, _charge_dir, false, Vector3(0.0, 0.0, 1.0))
			_flame_on = false
			_stop_jet()
			_stop_muzzle_jets()
			if global_position.distance_to(ppos) > M2_OFFSCREEN_DIST:
				_end_move(ppos)                             # off screen → attack ends
		M3_ORBIT:
			_t += delta
			if not _side_chosen:
				_m3_ang = (global_position - ppos).angle()   # start orbiting from where it is
				_side_chosen = true
			var dang := (TAU / M3_ROT_TIME) * delta
			_m3_ang += dang
			_m3_total += dang
			global_position = ppos + Vector2.from_angle(_m3_ang) * M3_RADIUS
			_apply_model(_view("aligned"), 0.0, ppos - global_position, false, Vector3(0.0, 0.0, 1.0))   # top-down (Y at camera)
			var rot_idx := int(_m3_total / TAU)              # 0 = flies, 1 = bugs, 2 = bees
			_spawn_acc += delta
			while _spawn_acc >= 1.0 / M3_SPAWN_RATE:
				_spawn_acc -= 1.0 / M3_SPAWN_RATE
				_spawn_enemy(rot_idx, muzzle_world(M3_SPAWN_MUZZLE))
			if _m3_total >= TAU * float(M3_ROTATIONS):
				_end_move(ppos)
		M4_ZOOM:
			_t += delta
			if not _side_chosen:
				_side = 1.0 if global_position.x >= ppos.x else -1.0   # nearest of 3/9 o'clock
				_side_chosen = true
			var h4 := ppos + Vector2(M4_HOME_OFFSET * _side, 0.0)   # 3 or 9 o'clock (beside the player)
			global_position = global_position.lerp(h4, clampf(HOME_LERP * delta, 0.0, 1.0))
			_beam_ang = (ppos - global_position).angle()
			_beam_ang0 = _beam_ang   # track only during the zoom; frozen once the beams start
			_apply_model(_view("aligned"), 0.0, Vector2.from_angle(_beam_ang), false, Vector3(0.0, 0.0, 1.0))
			if global_position.distance_to(h4) < 30.0 or _t > 2.0:
				_state = M4_CHARGE
				_t = 0.0
				_hold_anim(TAIL_CLIP, M4_HOLD_FRAME)
		M4_CHARGE:
			_t += delta
			# no player tracking after the zoom — the beam direction is locked
			_apply_model(_view("aligned"), 0.0, Vector2.from_angle(_beam_ang), false, Vector3(0.0, 0.0, 1.0))
			_charge_t = clampf(_t / M4_CHARGE_TIME, 0.0, 1.0)
			if _t >= M4_CHARGE_TIME:
				_state = M4_BEAM
				_t = 0.0
				_charge_t = 0.0
		M4_BEAM:
			_t += delta   # fire straight up along the locked direction (no tracking)
			_apply_model(_view("aligned"), 0.0, Vector2.from_angle(_beam_ang), false, Vector3(0.0, 0.0, 1.0))
			_beam_on = true
			if _t >= M4_BEAM_TIME:
				_state = M4_SWEEP_CW
				_t = 0.0
		M4_SWEEP_CW:
			_t += delta
			_beam_ang += (TAU / M4_SWEEP_TIME) * delta      # clockwise, one rotation
			_apply_model(_view("aligned"), 0.0, Vector2.from_angle(_beam_ang), false, Vector3(0.0, 0.0, 1.0))
			_beam_on = true
			if _t >= M4_SWEEP_TIME:
				_state = M4_SWEEP_CCW
				_t = 0.0
		M4_SWEEP_CCW:
			_t += delta
			_beam_ang -= (TAU / M4_SWEEP_TIME) * delta      # counter-clockwise, one rotation
			_apply_model(_view("aligned"), 0.0, Vector2.from_angle(_beam_ang), false, Vector3(0.0, 0.0, 1.0))
			_beam_on = true
			if _t >= M4_SWEEP_TIME:
				_state = M4_SPINFIRE
				_t = 0.0
				_beam_on = false
				_small_acc = 0.0
		M4_SPINFIRE:
			_t += delta
			_beam_ang += TAU * M4_SPIN_HZ * delta           # fast clockwise, 3 rot/s
			_apply_model(_view("aligned"), 0.0, Vector2.from_angle(_beam_ang), false, Vector3(0.0, 0.0, 1.0))
			_small_acc += delta
			while _small_acc >= M4_SMALL_INTERVAL:
				_small_acc -= M4_SMALL_INTERVAL
				var borg := muzzle_world(M4_BEAM_MUZZLE)
				for bi in M4_BURST_COUNT:              # fixed fan → clean spiral arms you can weave through
					var boff := (float(bi) - float(M4_BURST_COUNT - 1) * 0.5) * M4_FAN_STEP
					var dir := Vector2.from_angle(_beam_ang + boff)
					_small_beams.append({ "pos": borg, "vel": dir * M4_PARTICLE_SPEED, "life": M4_PARTICLE_RANGE / M4_PARTICLE_SPEED })
			if _t >= M4_SPINFIRE_TIME:
				_end_move(ppos)

	# advance laser bolts
	if not _bolts.is_empty():
		var alive: Array = []
		for b: Dictionary in _bolts:
			b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
			b["life"] = (b["life"] as float) - delta
			if (b["life"] as float) > 0.0:
				alive.append(b)
		_bolts = alive

	# held ring-of-fire lifetime (counts down only after the attack ends)
	if _held_active and _held_t > 0.0:
		_held_t -= delta
		if _held_t <= 0.0:
			_held_active = false

	# advance Move 4 spin particles (travel + fade)
	if not _small_beams.is_empty():
		var sb_alive: Array = []
		for sb: Dictionary in _small_beams:
			sb["pos"] = (sb["pos"] as Vector2) + (sb["vel"] as Vector2) * delta
			sb["life"] = (sb["life"] as float) - delta
			if (sb["life"] as float) > 0.0:
				sb_alive.append(sb)
		_small_beams = sb_alive

	queue_redraw()


## Aim the model: Z → toward the ship, Y → world up (stays upright, never upside down), X → screen depth.
## Roll by `roll` about the depth axis (aiming rock, upright) or the ship axis (charge drill) per `about_depth`.
## `aim_dir` = 2D direction to the ship (game space, +Y down).
func _apply_model(base_q: Quaternion, roll: float, aim_dir: Vector2, about_depth: bool, up_ref := Vector3(0.0, 1.0, 0.0)) -> void:
	if _pivot == null:
		return
	# Z → toward the ship; the third axis follows `up_ref` (world-up for M1, toward-camera/top-down for M2)
	var dz := Vector3(aim_dir.x, -aim_dir.y, 0.0)   # render +Y up vs 2D +Y down → flip Y
	if dz.length() < 0.0001:
		dz = Vector3(-1.0, 0.0, 0.0)
	dz = dz.normalized()
	var dx := up_ref.cross(dz)
	if dx.length() < 0.0001:
		dx = Vector3(0.0, 0.0, 1.0)
	dx = dx.normalized()
	var dy := dz.cross(dx).normalized()
	var target := Basis(dx, dy, dz)
	var axis := dx if about_depth else dz           # M1 aiming rocks about depth; charge/M2 spin drills about Z
	var b := Basis(axis, roll) * target * Basis(base_q)
	_pivot.transform = Transform3D(b, Vector3.ZERO)

# ── Entrance cinematic helpers ──────────────────────────────────────────────────
## First intro frame: start the shadow passes (needs the player position).
func _intro_begin(ppos: Vector2) -> void:
	_intro_init = true
	_intro_pass_i = 0
	_intro_waiting = false
	_intro_setup_pass(ppos, 0)
	_play(PROLONGED_CLIP)

## Build one straight pass line at INTRO_PASS_ANGLES[i], passing through the player. Boss starts off one edge.
func _intro_setup_pass(ppos: Vector2, i: int) -> void:
	var deg: float = float(INTRO_PASS_ANGLES[i % INTRO_PASS_ANGLES.size()])
	var dir := Vector2.from_angle(deg_to_rad(deg))
	_intro_p0 = ppos - dir * INTRO_PASS_SPAN          # start off one edge...
	_intro_p1 = ppos + dir * INTRO_PASS_SPAN          # ...streak through, off the far edge
	global_position = _intro_p0

## After the passes: enter from behind (7 o'clock) up high, then one long curve DOWN to the 3 o'clock home.
## The curve is player-relative (see INTRO_DIVE) so it tracks the ship all the way down.
func _intro_dive_begin(ppos: Vector2) -> void:
	global_position = ppos + INTRO_DIVE_START_OFF
	_state = INTRO_DIVE
	_intro_t = 0.0

## Restore normal scale/tint, REGISTER the boss HP (bar drops in now), hand control to the moveset.
func _end_intro() -> void:
	_clear_trail()
	_spr.visible = true
	_spr.scale = Vector2(_base_scale, _base_scale)
	_spr.modulate = Color(1.0, 1.0, 1.0, 1.0)
	add_to_group("arena_enemy")   # NOW it becomes a real, targetable/collidable enemy
	add_to_group("boss")
	GameManager.boss_max_hp = int(_hp_max)
	GameManager.boss_hp = int(_hp)
	if GameManager.has_signal("boss_spawned"):
		GameManager.boss_spawned.emit()
	if GameManager.has_signal("boss_hp_changed"):
		GameManager.boss_hp_changed.emit(int(_hp))
	_side_chosen = false
	_state = TRACK
	_move = ""   # _process → _start_next_move picks the first enabled move

func _update_trail(dir: Vector2) -> void:
	if INTRO_TRAIL_GHOSTS <= 0:
		return
	if _intro_trail.is_empty():
		for i in INTRO_TRAIL_GHOSTS:
			var g := Sprite2D.new()
			g.texture = _vp.get_texture()
			g.z_index = _spr.z_index - 1
			add_child(g)
			_intro_trail.append(g)
	var nd := dir.normalized()
	for i in _intro_trail.size():
		var g: Sprite2D = _intro_trail[i]
		g.position = -nd * float(i + 1) * 46.0        # lag behind the boss along travel (local space)
		g.scale = _spr.scale
		var a := 0.32 * (1.0 - float(i) / float(_intro_trail.size()))
		g.modulate = Color(INTRO_DARK.r, INTRO_DARK.g, INTRO_DARK.b, a)

func _clear_trail() -> void:
	for g in _intro_trail:
		if is_instance_valid(g):
			g.queue_free()
	_intro_trail.clear()

func _bezier3(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, u: float) -> Vector2:
	var iu := 1.0 - u
	return p0 * (iu * iu * iu) + c1 * (3.0 * iu * iu * u) + c2 * (3.0 * iu * u * u) + p1 * (u * u * u)

func _ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

## A saved orientation (front/side/top) from scorpion_views.cfg; falls back to the BASE_*_DEG euler.
func _view(vname: String) -> Quaternion:
	if _views.has(vname):
		return _views[vname]
	return Basis.from_euler(Vector3(deg_to_rad(BASE_PITCH_DEG), deg_to_rad(BASE_YAW_DEG), deg_to_rad(BASE_ROLL_DEG))).get_rotation_quaternion()

func _load_views() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(VIEWS_CFG) != OK or not cfg.has_section("views"):
		return
	for k: String in cfg.get_section_keys("views"):
		_views[k] = cfg.get_value("views", k)

# ── Move selection (panel API + dispatch) ──
func get_move_meta() -> Array:
	return MOVE_META

func is_move_enabled(id: String) -> bool:
	return _enabled.get(id, false)

func set_move_enabled(id: String, on: bool) -> void:
	_enabled[id] = on

## Pick the next enabled move (cycling through MOVE_META); idle on Head bobbing if none are enabled.
func _start_next_move(ppos: Vector2) -> void:
	var any := false
	for m: Dictionary in MOVE_META:
		if _enabled.get(m["id"], false):
			any = true
	if not any:
		_move = ""
		_flame_on = false
		_play("Head bobbing")
		return
	var start := (_move_idx + 1) % MOVE_META.size()
	for i in MOVE_META.size():
		var idx := (start + i) % MOVE_META.size()
		var id: String = MOVE_META[idx]["id"]
		if _enabled.get(id, false):
			_move_idx = idx
			_start_move(id)
			return

func _end_move(_ppos: Vector2) -> void:
	_flame_on = false
	_stop_jet()
	_stop_muzzle_jets()
	_beam_on = false
	_move = ""   # next _process picks the following enabled move

func _hold_anim(clip: String, frame: float) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_anim.play(clip)
	_anim.seek(frame / M4_ANIM_FPS, true)
	_anim.pause()

func _drive_jet(origin: Vector2, angle: float, reach: float) -> void:
	if _jet == null or not is_instance_valid(_jet):
		return
	var life := 0.5
	_jet.global_position = origin
	_jet.set_stream(angle, JET_SPREAD, reach / life, life)   # tight spread → one thin stream
	_jet.set_points([Vector2.ZERO])                    # emit continuously from the muzzle

func _stop_jet() -> void:
	if _jet != null and is_instance_valid(_jet):
		_jet.set_points([])

## Lazily build one flamethrower per placed muzzle (for the "fire from all points" spin/charge phase).
func _ensure_muzzle_jets() -> void:
	if not _all_jets.is_empty():
		return
	for slot: int in _muzzle_anchors.keys():
		var j := DynamicFire.new()
		j.free_form = true
		j.z_index = 30
		_style_fire(j, MUZZLE_JET_AMOUNT, JET_INTENSITY, JET_GLOW, JET_SIZE_MIN, JET_SIZE_MAX)
		add_child(j)
		_all_jets[slot] = j

## Fire every muzzle's flamethrower radially outward from the boss centre (optionally skipping one slot).
func _drive_muzzle_jets(reach: float, exclude: int = -1) -> void:
	_ensure_muzzle_jets()
	var life := 0.5
	for slot: int in _all_jets.keys():
		var j: DynamicFire = _all_jets[slot]
		if slot == exclude:
			j.set_points([])
			continue
		var org := muzzle_world(slot)
		var dir := org - global_position
		var ang := dir.angle() if dir.length() > 1.0 else 0.0
		j.global_position = org
		j.set_stream(ang, JET_SPREAD, reach / life, life)
		j.set_points([Vector2.ZERO])

func _stop_muzzle_jets() -> void:
	for j: DynamicFire in _all_jets.values():
		if is_instance_valid(j):
			j.set_points([])

## Fire look (density/brightness). Jet and ring pass different values so they read as the same flame.
func _style_fire(df: DynamicFire, amount: int, intensity: float, glow: float, size_min: float, size_max: float) -> void:
	df.particle_amount = amount
	df.particle_size_min = size_min
	df.particle_size_max = size_max
	df.intensity = intensity
	df.glow = glow

## Spawn the elephant-style ring of fire (DynamicFire) around `center`, opening from the boss side.
## It forms over M2_CIRCLE_FORM, holds through the rest of the attack + M2_RING_HOLD, then burns out & frees.
func _spawn_fire_ring(center: Vector2, from_boss: Vector2) -> void:
	var ring := DynamicFire.new()
	_style_fire(ring, RING_AMOUNT, RING_INTENSITY, RING_GLOW, RING_SIZE_MIN, RING_SIZE_MAX)
	ring.ring_radius = M2_RING_RADIUS
	ring.ring_bidirectional = true                          # the "split in half" — two heads close the ring
	ring.ring_start_angle = (from_boss - center).angle()    # opens from the side facing the boss
	ring.jet_length = 0.0
	ring.shape = "ring"
	ring.draw_duration = M2_CIRCLE_FORM
	ring.hold_duration = M2_RING_HOLD + 3.0   # ~form + charge-to-offscreen, so it lingers ~10s past the attack
	ring.burnout_duration = 1.5
	ring.jet_holds = false
	ring.loop = false
	ring.free_on_done = true                                # self-frees after it burns out
	ring.z_index = 30
	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(ring)
	ring.global_position = center
	_ring = ring

func _start_move(id: String) -> void:
	_move = id
	_t = 0.0
	_spin = 0.0
	_lean = 0.0
	_speed = 0.0
	_side_chosen = false
	_circle_t = 0.0
	_circle_locked = false
	_flame_on = false
	_stop_jet()
	_stop_muzzle_jets()
	_beam_on = false
	if id == "m1":
		_burst_shot = 0
		_fire_acc = 0.0
		_pass_count = 0
		_was_near = false
		_state = TRACK
		_play("Head bobbing", 0.3)   # cross-fade from the dive's flapping so the landing→attack is seamless
	elif id == "m2":
		_state = M2_ZOOM
		_play(PROLONGED_CLIP)
	elif id == "m3":
		_m3_total = 0.0
		_spawn_acc = 0.0
		_state = M3_ORBIT
		_play(SPAWNING_CLIP)
	elif id == "m4":
		_charge_t = 0.0
		_small_beams = []
		_small_acc = 0.0
		_state = M4_ZOOM
		_play(TAIL_CLIP)


# ── Targetable / arena-enemy interface (every arena weapon hits it through take_damage) ──
func is_dead() -> bool:
	return _dead

func take_damage(amount: float, _stagger: float = 0.0, _knock: float = 0.0, ignore_armor: bool = false, _bleeds: bool = false, _was_crit: bool = false, _kind: String = "") -> void:
	if _dead or _move == "intro":
		return   # intangible "shadow" during the entrance cinematic (no HP bar, can't be hit)
	var dr := 0.0
	if not ignore_armor and GameManager.has_method("armor_damage_reduction"):
		dr = GameManager.armor_damage_reduction(_armor)   # 100 armor ≈ 33% reduction
	_hp = maxf(0.0, _hp - amount * (1.0 - dr))
	_flash = 0.08
	GameManager.boss_hp = int(_hp)
	if GameManager.has_signal("boss_hp_changed"):
		GameManager.boss_hp_changed.emit(GameManager.boss_hp)
	if _hp <= 0.0:
		_die()

func hp_fraction() -> float:
	return _hp / _hp_max

## Death: drop XP, pop an explosion, tell the arena a boss died (resumes the paused waves), free.
func _die() -> void:
	if _dead:
		return
	_dead = true
	_stop_jet()
	_stop_muzzle_jets()
	if _xp > 0.0 and _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("spawn_xp_orb"):
		_mgr.spawn_xp_orb(global_position, _xp)
	if get_parent() != null:
		var ex: Node2D = ArenaExplosion.new()
		get_parent().add_child(ex)
		ex.global_position = global_position
		ex.call("setup", global_position, DISPLAY_PX * 1.2)
	if GameManager.has_signal("boss_defeated"):
		GameManager.boss_defeated.emit()
	# Beating the boss also grants a new arena item (the other item source now that level-ups only upgrade).
	var ui := get_tree().get_first_node_in_group("levelup_ui")
	if ui != null and is_instance_valid(ui) and ui.has_method("grant_reward"):
		ui.call("grant_reward")
	queue_free()

## Spawn a laser bolt from muzzle 1 toward the ship (called repeatedly during the aiming phase).
func _fire_bolt(ppos: Vector2) -> void:
	var origin := muzzle_world(1)
	var dir := ppos - origin
	if dir.length() < 1.0:
		return
	_bolts.append({ "pos": origin, "vel": dir.normalized() * BOLT_SPEED, "life": 1.4 })

func _draw() -> void:
	# laser bolts (stored in world space → convert to local)
	for b: Dictionary in _bolts:
		var p := to_local(b["pos"])
		var tail := p - (b["vel"] as Vector2).normalized() * 28.0
		draw_line(tail, p, Color(1.0, 0.25, 0.2, 0.85), 3.0)
		draw_circle(p, 3.5, Color(1.0, 0.85, 0.6))
	# (Move 2 flame is now real DynamicFire — the muzzle jet + the ring of fire — not drawn here.)
	# Move 4 lasers (placeholder red beams — real laser VFX to be wired in)
	if _beam_on:
		var bo := to_local(muzzle_world(M4_BEAM_MUZZLE))
		var bdir := Vector2.from_angle(_beam_ang)
		var btip := bo + bdir * M4_BIG_LEN
		draw_line(bo, btip, Color(1.0, 0.08, 0.08, 0.85), 18.0)
		draw_line(bo, btip, Color(1.0, 0.6, 0.6, 0.95), 6.0)
	for sb: Dictionary in _small_beams:
		var sp := to_local(sb["pos"])
		var sv := sb["vel"] as Vector2
		var slife := M4_PARTICLE_RANGE / maxf(1.0, sv.length())
		var sa := clampf((sb["life"] as float) / slife, 0.0, 1.0)
		draw_line(sp - sv.normalized() * 12.0, sp, Color(1.0, 0.35, 0.1, 0.6 * sa), 3.0)
		draw_circle(sp, 4.0, Color(1.0, 0.5, 0.15, 0.9 * sa))
		draw_circle(sp, 2.0, Color(1.0, 0.9, 0.6, sa))
	if _charge_t > 0.0:
		var co := to_local(muzzle_world(M4_BEAM_MUZZLE))
		draw_circle(co, 8.0 + 34.0 * _charge_t, Color(1.0, 0.2, 0.2, 0.25 + 0.45 * _charge_t))
	# thin hit-flash ring + a small HP bar above the boss (debug feedback).
	# Hidden during the entrance cinematic — it's a cosmetic "shadow" then, no HP shown.
	if _move != "intro":
		if _flash > 0.0:
			draw_arc(Vector2.ZERO, hit_radius, 0.0, TAU, 32, Color(1.0, 0.9, 0.5, 0.8), 3.0, true)
		var bw := DISPLAY_PX * 0.8
		var by := -DISPLAY_PX * 0.55
		draw_rect(Rect2(-bw * 0.5, by, bw, 6.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, by, bw * hp_fraction(), 6.0), Color(0.9, 0.2, 0.2))


# ── 3D render (SubViewport → this node's Sprite2D) ──
func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-40.0), 0.0)
	key.light_energy = 2.2
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 1.1
	_vp.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.88, 0.98)
	e.ambient_light_energy = 2.0
	env.environment = e
	_vp.add_child(env)

	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	var packed := load(MODEL_PATH) as PackedScene
	_model = (packed.instantiate() as Node3D) if packed != null else null
	if _model != null:
		_pivot.add_child(_model)
		_frame_camera(_model)
		_style_materials(_model)
		_load_muzzle_anchors()
		_anim = _find_anim_player(_model)
	else:
		push_warning("boss_scorpion: could not load model at " + MODEL_PATH)
		_cam.position = Vector3(0.0, 0.0, 5.0)
		_cam.look_at(Vector3.ZERO, Vector3.UP)

func _play(clip: String, blend: float = -1.0) -> void:
	if _anim == null:
		return
	var a := _anim.get_animation(clip)
	if a != null:
		a.loop_mode = Animation.LOOP_LINEAR
		_anim.play(clip, blend)   # blend > 0 → cross-fade from the current clip (e.g. flapping → head-bob)

func _load_muzzle_anchors() -> void:
	_muzzle_anchors.clear()
	var cfg := ConfigFile.new()
	if _model == null or cfg.load(MUZZLE_CFG) != OK or not cfg.has_section("muzzles"):
		return
	for key: String in cfg.get_section_keys("muzzles"):
		var a := Node3D.new()
		a.position = cfg.get_value("muzzles", key)
		_model.add_child(a)
		_muzzle_anchors[int(key)] = a

## World-space 2D position of muzzle `slot` (for future moves that fire projectiles).
func muzzle_world(slot: int) -> Vector2:
	var a: Node3D = _muzzle_anchors.get(slot, null)
	if a == null or _cam == null or _spr == null:
		return global_position
	var pix := _cam.unproject_position(a.global_position)
	return global_position + (pix - Vector2(VP_SIZE, VP_SIZE) * 0.5) * _spr.scale.x

func _frame_camera(model: Node3D) -> void:
	var aabb := _combined_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	_cam.position = Vector3(0.0, 0.0, dist)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.near = maxf(0.05, dist - radius * 2.0)
	_cam.far  = dist + radius * 2.0

func _style_materials(root: Node) -> void:
	for mi: MeshInstance3D in _all_mesh_instances(root):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null:
				continue
			var mat := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = RECOLOR_SHADER
			mat.shader = sh
			var orm := src.metallic_texture
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mat.set_shader_parameter("orm_tex", orm)
			mat.set_shader_parameter("has_orm", orm != null)
			mat.set_shader_parameter("metallic_val", src.metallic)
			mat.set_shader_parameter("roughness_val", src.roughness)
			mat.set_shader_parameter("metallic_mult", METALLIC_MULT)
			mat.set_shader_parameter("normal_tex", src.normal_texture)
			mat.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
			mat.set_shader_parameter("hue_shift", HUE_SHIFT)
			mat.set_shader_parameter("sat_mul", SATURATION)
			mat.set_shader_parameter("val_mul", VALUE)
			mat.set_shader_parameter("white_amt", WHITEN_GRAYS)
			mat.set_shader_parameter("gray_bright", GRAY_BRIGHT)
			mat.set_shader_parameter("gray_sat_max", GRAY_SAT_MAX)
			mat.set_shader_parameter("red_target", RED_TARGET)
			mat.set_shader_parameter("red_amt", DARKEN_REDS)
			mat.set_shader_parameter("red_hue_band", RED_HUE_BAND)
			mat.set_shader_parameter("red_sat_min", RED_SAT_MIN)
			mat.set_shader_parameter("pulse_speed", PULSE_SPEED)
			mat.set_shader_parameter("pulse_amount", PULSE_AMOUNT)
			mi.set_surface_override_material(si, mat)

func _combined_aabb(root: Node) -> AABB:
	var acc := AABB()
	var has := false
	var inv := _pivot.global_transform.affine_inverse()
	for mi: MeshInstance3D in _all_mesh_instances(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c: Node in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

## Spawn one real arena_enemy (fly/bug/bee by rotation index) at `pos`. It homes on the player (chase
## behavior), uses the real sprite/stats, and is shootable by the player's weapons.
func _spawn_enemy(rot_idx: int, pos: Vector2) -> void:
	var id: String = M3_ENEMY_IDS[clampi(rot_idx, 0, M3_ENEMY_IDS.size() - 1)]
	var e := ArenaEnemyScript.new()
	e.configure(id, null, M3_ENEMY_DEFS[id])   # configure BEFORE add_child so _ready() sees the stats
	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(e)
	e.global_position = pos
