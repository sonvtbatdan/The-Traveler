extends Node2D
## Arena weapons — the first two REAL weapons ported into world space: the Gatling gun (rapid golden
## tracer bolts) and the Gauss cannon (auto-charging heavy plasma orb with converging charge rings).
##
## Self-contained: it does NOT pull in the Control/InventoryManager weapon machinery. It only reuses the
## VISUAL code (tracer capsule, plasma-orb shader, comet trail, tail sparks, charge rings) from
## weapon_system.gd, adapted to a Node2D so it can draw in world space. It auto-fires both weapons toward
## the ship's current facing (Vampire-Survivors style) and damages enemies via the take_damage contract.
##
## Drawing: this Node2D sits at the world origin, so its _draw() coordinates ARE world coordinates. The
## Gauss orb is a ColorRect child positioned in world space (renders on top of the _draw() trail/sparks).

# ── TUNABLES: Gatling gun (rapid tracer stream) ───────────────────────────────
const GAT_ENABLED       := true
const GAT_FIRE_INTERVAL := 0.09     # s between shots (hold-to-fire feel)
const GAT_SPEED         := 900.0    # px/s
const GAT_DAMAGE        := 6.0      # per hit
const GAT_LIFETIME      := 1.2      # s before despawn
const GAT_MAX_DIST      := 1300.0   # px travelled before despawn
const GAT_HIT_RADIUS    := 16.0     # bullet↔enemy hit distance (px)
const GAT_SPREAD_DEG    := 3.0      # ± random spray on each shot (0 = laser-straight)
const GAT_STAGGER       := 0.1      # s the enemy is staggered (movement/attacks frozen) per Gatling hit
const GAT_LIGHT         := 1.0      # dust-light "value" per Gatling bullet (low → lights up nearby dust only)
const GAT_WING_SPACING  := 26.0     # px between the two wing muzzles (twin parallel streams)
const GAT_WING_FWD      := 22.0     # forward offset of the wing muzzles from ship centre (px)
const GAT_MUZZLE_DECAY  := 0.08     # s the muzzle-fire flash decays over (refreshed each shot → ~continuous while firing)

# ── Gatling skill-point upgrade pool (each invested point picks 1 of 3 → +1 rank). Level rewards are derived
# from the weapon's LEVEL (see _gat_* effective-stat helpers). The level-up UI's 2nd tier rolls 3 of these. ──
const GATLING_POOL := {
	"hardened":  {"name": "Hardened Round",  "max": 10, "per": "+1 flat damage",        "desc": "Bullets hit harder."},
	"piercing":  {"name": "Piercing Round",  "max": 5,  "per": "+10% pierce chance",    "desc": "Bullets pass through enemies."},
	"quick":     {"name": "Quick Round",     "max": 10, "per": "+8% fire rate",         "desc": "Shoot faster."},
	"bouncing":  {"name": "Bouncing Round",  "max": 5,  "per": "+8% bounce chance",     "desc": "Bullets ricochet to a nearby foe."},
	"multishot": {"name": "Multishot",       "max": 10, "per": "+10% extra-bullet chance", "desc": "Chance for an extra bullet."},
	"kinetic":   {"name": "Kinetic Mastery", "max": 0,  "per": "+10% kinetic damage",   "desc": "Boosts all kinetic weapons (cross-weapon part TBD)."},
}
const GAT_BOUNCE_RANGE := 280.0    # search radius for a bounce target
const GAT_HEAL_ODDS    := 200      # Healing Round capstone: 1-in-N directly-fired bullets heals
const GAT_HEAL_AMOUNT  := 5        # HP healed (player + target) by a healing bullet
const GAT_FOCUS_STEP   := 0.005    # Focus Fire capstone: +0.5% gatling dmg per consecutive hit on the same target
const GAT_FOCUS_MAX    := 1.0      # … capped at +100%

# ── TUNABLES: Gauss cannon (auto-charge → heavy piercing orb) ─────────────────
const GAUSS_ENABLED     := false    # disabled for now
const GAUSS_STAGGER     := 0.35     # s the enemy is staggered per Gauss hit (heavier weapon = more)
const GAUSS_LIGHT       := 5.0      # dust-light "value" per Gauss orb (heavy → big bright light)
const GAUSS_CHARGE_TIME := 1.4      # s to fully charge between shots (drives the charge-meter fraction)
const GAUSS_SPEED       := 520.0    # px/s (heavy + slow so you watch it plough through)
const GAUSS_DAMAGE      := 55.0     # per-shot DAMAGE BUDGET the orb carries (× damage-mult at fire)
const GAUSS_RADIUS      := 30.0     # FULL hit radius (at full budget); shrinks ∝ sqrt(damage)
const GAUSS_MIN_DMG     := 1.0      # cull the orb once its remaining budget falls below this
const GAUSS_CULL_DIST   := 1800.0   # cull the orb once it gets this far from the player ("too far to notice")
const GAUSS_LIFETIME    := 8.0      # s before despawn (generous backstop; damage/distance are the real culls)

const MUZZLE_OFFSET     := 22.0     # how far ahead of the ship centre shots spawn (px)

# ── Weapon acquisition (chest + pickups → up to 5 unique weapons; backs the 5-slot HUD) ──
const MAX_WEAPONS := 5                                  # HUD slot count / acquisition cap
const MAX_WEAPON_LEVEL := 6                             # per-item level cap (skill-point progression; max level 6)
const WEAPON_DMG_PER_LEVEL := 0.30                      # +30% damage per level, COMPOUNDING (×1.30^(level-1))
const CHEST_POOL  := ["gatling", "lasgun", "arc", "gauss"]   # the 4 "F12" weapons the start-of-run chest rolls from
# kind → inventory def_id (icon) + display label. Canonical map shared by the chest + slot HUD.
const WEAPON_INFO := {
	"gatling": {"def_id": "gatling_gun",  "label": "Gatling"},
	"lasgun":  {"def_id": "lasgun",       "label": "Lasgun"},
	"arc":     {"def_id": "arc",          "label": "Arc"},
	"gauss":   {"def_id": "gauss_cannon", "label": "Gauss"},
	"orbital": {"def_id": "orbitals",     "label": "Orbital"},
	"void":    {"def_id": "rift_maker",   "label": "Rift Maker"},
	"red_x":   {"def_id": "red_x",        "label": "Red X"},
	"chemtrail": {"def_id": "chemtrail",  "label": "Chemtrail"},
	"nuke":    {"def_id": "nuke",          "label": "Nuke"},
	"sonic":   {"def_id": "sonic_wave",    "label": "Sonic Wave"},
	"zsword":  {"def_id": "z_sword",       "label": "Z-Sword"},
	"ionize":  {"def_id": "ionizing_field","label": "Ionizing Field"},
	"boomerang": {"def_id": "boomerang",     "label": "Boomerang"},
	"parasite":  {"def_id": "parasite_cloud","label": "Parasite Cloud"},
	"moroboshi": {"def_id": "moroboshi",     "label": "Moroboshi-M1"},
	"swarm":     {"def_id": "swarm_host",    "label": "Swarm Host"},
	"snake":     {"def_id": "space_snake",   "label": "Space Snake"},
	"homing":    {"def_id": "homing_missile","label": "Homing Missile"},
	# ── Fused weapons (created via fuse(); NOT offered in the normal new-weapon roll — see is_fusion_kind) ──
	"carnage":      {"def_id": "carnage",      "label": "Carnage"},
	"vampire_host": {"def_id": "vampire_host", "label": "Vampire Host"},
	"overcharger":  {"def_id": "overcharger",  "label": "Overcharger"},
	"predator":     {"def_id": "predator",     "label": "The Predator"},
	"toxic_ballistic": {"def_id": "toxic_ballistic", "label": "Toxic Ballistic"},
	"singularities": {"def_id": "singularities", "label": "Singularities"},
}

# ── Weapon FUSION (two maxed weapons → one fused weapon with FUSION_BONUS_LEVELS extra levels) ──
# When BOTH components of a recipe are owned at MAX_WEAPON_LEVEL, the level-up UI offers a guaranteed
# fusion card (arena_levelup_ui._fusion_choice). fuse() removes both components and grants the fused kind,
# which carries the maxed state (starts at MAX_WEAPON_LEVEL) and can climb FUSION_BONUS_LEVELS further.
# Each fused-weapon level bumps BOTH component damages together (they share one _lvl_mult via the fusion kind).
const FUSION_BONUS_LEVELS := 5
const FUSION_DEFS := {
	"carnage":      {"a": "gatling", "b": "red_x", "label": "Carnage",      "def_id": "carnage"},
	"vampire_host": {"a": "swarm",   "b": "sonic", "label": "Vampire Host", "def_id": "vampire_host"},
	"overcharger":  {"a": "gauss",   "b": "arc",   "label": "Overcharger",  "def_id": "overcharger"},
	"predator":     {"a": "lasgun",  "b": "snake", "label": "The Predator",  "def_id": "predator"},
	"toxic_ballistic": {"a": "homing", "b": "chemtrail", "label": "Toxic Ballistic", "def_id": "toxic_ballistic"},
	"singularities": {"a": "orbital", "b": "void", "label": "Singularities", "def_id": "singularities"},
	# Added later: moroboshi_m2 (moroboshi+zsword), deadzone (boomerang+ionize).
}

# ── TUNABLES: Carnage fusion (gatling + red_x → constant Red X fire + Gatling in 4 directions) ──
# Gatling fires in 4 directions: the main one (toward the mouse/ship facing) plus the 3 at 90° increments.
# The Red X cross-detonation re-fires on a SHORT cadence with a SHORT-lived flash → a constant fire stream.
const CARNAGE_REDX_TICK      := 0.25   # Red X DAMAGE tick — per-tick damage is scaled so sustained DPS ≈ base Red X
const CARNAGE_FIRE_DRAW      := 0.30   # one-time reach-out of the persistent X-fire arms (then HOLD continuously)
const CARNAGE_FIRE_LIFETIME  := 0.40   # particle life of the continuous X-fire

# ── TUNABLES: Vampire Host fusion (swarm + sonic → familiars fire small sonic waves, heal on hit) ──
const VAMPIRE_DMG_FRAC  := 1.0 / 3.0   # each wave deals 1/3 of SONIC_DAMAGE
const VAMPIRE_HEAL_FRAC := 0.25        # heal the player this fraction of damage dealt
const VAMPIRE_RING_MAXR := 150.0       # smaller than SONIC_MAX_RADIUS (320)

# ── TUNABLES: Batch-1 weapons (Nuke / Sonic Wave / Z-Sword / Ionizing Field) ──────
# Nuke (Kinetic) — long-cooldown player-centred blast + auto knockback + lingering radiation slow zone.
const NUKE_COOLDOWN      := 15.0
const NUKE_DAMAGE        := 200.0
const NUKE_RADIUS        := 540.0    # AoE (was 360, +50%) — also sizes the explosion visual
const NUKE_BLAST_STAGGER := 0.6      # blast freeze on hit
# (the damage window is set per detonation to the explosion's FIRE phase — see _fire_nuke / _nuke_blast_dur)
# Sonic Wave (Energy) — 3 expanding rings; each ring damages every enemy its front passes, once.
const SONIC_COOLDOWN     := 3.0
const SONIC_RINGS        := 3
const SONIC_RING_STAGGER := 0.18     # delay between successive rings of one volley
const SONIC_MAX_RADIUS   := 320.0
const SONIC_EXPAND_TIME  := 0.7
const SONIC_DAMAGE       := 30.0
const SONIC_BAND         := 24.0     # ring-front thickness for the hit test
const SONIC_CONE_HALF    := 1.05     # half-angle of the forward cone the arcs fan into (~120° total)
const SONIC_COL          := Color(0.55, 0.85, 1.0)
# Z-Sword (Energy) — energy blade extends from the ship and sweeps a full circle.
const ZSWORD_COOLDOWN    := 4.0
const ZSWORD_SWEEP_TIME  := 0.6
const ZSWORD_LENGTH      := 220.0
const ZSWORD_ARC_HALF    := 0.314159 # ~18° half-arc hit tolerance
const ZSWORD_DAMAGE      := 45.0
const ZSWORD_STAGGER     := 0.1
# (slash visuals live in scripts/gameplay/fx/z_slash.gd; colours are ZSlash.LEAD_COL/LEAD_HOT there)
# Ionizing Field (Energy) — always-on aura DoT around the ship.
const IONIZE_TICK   := 0.3
const IONIZE_RADIUS := 170.0
const IONIZE_DAMAGE := 10.0
const IONIZE_COL    := Color(0.6, 0.9, 1.0)

# ── TUNABLES: Batch-2 weapons (Boomerang / Parasite Cloud / Moroboshi-M1 / Swarm Host / Space Snake) ──
# Boomerang (Kinetic) — a single PERPETUAL blade flying a 3-petal "trinity"/rose path around the ship: it loops
# out into a petal, sweeps back through the centre, out the next petal — forever (rose r = SIZE·cos(3θ)). The
# pattern centre LAGS the ship, so flying drags the whole flower along behind you. Never thrown, never despawns.
const BOOM_COUNT      := 1          # blades in flight
const BOOM_SIZE       := 330.0      # petal reach (flight-pattern radius) — 150% of the previous 220
const BOOM_ROSE_SPEED := 1.2        # how fast the blade travels the petals (θ rad/s) — 60% of the previous 2.0
const BOOM_CENTER_LAG := 6.0        # how fast the flower centre catches up to the ship (lower = more trailing drag)
const BOOM_BLADE      := 45.0       # blade visual half-length (+150% of the old 18px)
const BOOM_DAMAGE     := 28.0
const BOOM_HIT_RADIUS := 48.0       # enlarged to match the bigger blade
const BOOM_HIT_CD     := 0.25       # per-enemy re-hit interval (a blade sweeps the same enemy repeatedly)
const BOOM_SPIN       := 28.0       # visual self-spin rad/s (+300% of the previous 7.0)
const BOOM_COL        := Color(0.95, 0.85, 0.5)
const BOOM_DRAW       := 130.0      # on-screen boomerang sprite width (px); height aspect-locked per texture
# Fired-projectile sprite variants. Switch with `sprite_version_boomerang` (1, 2, or 3).
const BOOM_TEX_VERSIONS: Array[Texture2D] = [
	preload("res://assets/Boomerang.png"),     # 1 — chrome V
	preload("res://assets/Boomerang 2.png"),   # 2 — saw blade
	preload("res://assets/Boomerang 3.png"),   # 3 — sci-fi tech boomerang
]
## TUNABLE — which boomerang sprite is used when firing: 1, 2, or 3. Change this to swap the look.
var sprite_version_boomerang: int = 2
# Parasite Cloud (Biological) — fast blob that decelerates into a lingering damage cloud.
const PARA_COOLDOWN   := 2.6
const PARA_SPEED      := 520.0
const PARA_DRAG       := 2.2        # exponential deceleration toward a hover
const PARA_LIFETIME   := 3.2
const PARA_RADIUS     := 90.0
const PARA_TICK       := 0.25
const PARA_DAMAGE     := 10.0       # per tick to everything inside
const PARA_COL        := Color(0.6, 0.95, 0.45)
# Moroboshi-M1 (Biological) — winged-golem familiar that chases enemies and punches (AoE + stagger).
const MORO_FOLLOW_DIST := 90.0      # rests this far behind the ship when idle
const MORO_MOVE_SPEED  := 240.0
const MORO_AGGRO       := 520.0     # seeks enemies within this of itself
const MORO_ATTACK_CD   := 0.9
const MORO_ATTACK_RANGE:= 80.0
const MORO_AOE         := 90.0
const MORO_DAMAGE      := 40.0
const MORO_STAGGER     := 0.3
const MORO_COL         := Color(0.8, 0.7, 1.0)
# Swarm Host (Biological) — familiars that dart to enemies, deal damage, return and heal the player.
const SWARM_COUNT      := 2         # familiar count (body)
const SWARM_SPEED      := 420.0
const SWARM_AGGRO      := 560.0
const SWARM_DAMAGE     := 22.0
const SWARM_HIT_RADIUS := 26.0
const SWARM_HEAL_FRAC  := 0.25      # heal the player for this fraction of damage dealt, on return
const SWARM_IDLE_R     := 70.0      # orbit radius near the ship when idle
const SWARM_COL        := Color(0.95, 0.6, 0.85)
# Space Snake (Biological) — fire-snake familiar; head chases enemies, body trails, contact DoT.
const SNAKE_SEGMENTS   := 10
const SNAKE_SPACING    := 18.0
const SNAKE_SPEED      := 300.0
const SNAKE_TURN       := 3.0       # max turn rad/s (head minimises turn angle)
const PREDATOR_TURN    := 2.0       # The Predator's head turns slower → its beam must be aimed by turning the head
const SNAKE_TICK       := 0.2
const SNAKE_DAMAGE     := 8.0       # per tick per enemy in contact with any segment
const SNAKE_HIT_RADIUS := 22.0
const SNAKE_COL        := Color(1.0, 0.6, 0.3)

# ── TUNABLES: Homing Missile (ported from weapon_system.gd) — flies like the Space Snake: it is ALWAYS moving
# and steers toward its target at a fixed turn rate (it can't pivot in place). Pops off the back, arcs around,
# accelerates in, AoE explodes on contact. ──
const HOMING_INTERVAL      := 0.9     # s between launches (repeat fire — scaled by the "cd" / fire-rate stat)
const HOMING_DAMAGE        := 40.0    # AoE blast damage (per enemy in radius — kinetic)
const HOMING_ACQUIRE_RANGE := 1600.0  # max distance to pick a target at launch
const MISSILE_BASE_SHOTS   := 2       # missiles per volley (the "shots"/multishot stat adds more)
const MISSILE_SEEK_TURN    := 9.8     # rad/s steering rate (like SNAKE_TURN; lower = wider, lazier curve)
const MISSILE_SPREAD_WEIGHT := 1.0    # target picker: weight of the (capped) "avoid other missiles' targets" bonus
const MISSILE_SPREAD_CAP    := 250.0  # that bonus saturates here → closeness dominates; a far target can't win just for being far from the others
const MISSILE_LAUNCH_SPEED := 150.0   # speed it peels off the back at (slow → tight initial turn → it lines up)
const MISSILE_ACCEL        := 900.0   # base acceleration toward the target
const MISSILE_ACCEL_RAMP   := 9.0     # acceleration grows ×this per second → slow start, hard whip
const MISSILE_SPEED        := 400.0   # max strike speed (cruise)
const MISSILE_EXPLODE_DIST := 14.0    # "touched the target"
const MISSILE_AOE_RADIUS   := 44.0    # explosion radius
const TOXIC_PUFF_RADIUS    := 80.0    # Toxic Ballistic: width of the chemtrail each missile lays down the path
const MISSILE_MAX_LIFE     := 4.0     # backstop: explode after this long

# ── TUNABLES: Orbitals (spiky energy orbs circling the ship, contact damage — ported from weapon_system.gd) ──
const ORBITAL_BALLS        := 3       # number of orbiting balls (evenly spaced)
const ORBITAL_RADIUS       := 350.0   # orbit radius around the ship (px)
const ORBITAL_SPIN         := 90.0   # deg/sec (one loop every 3s); always-on passive (no overcharge in arena)
const ORBITAL_BALL_RADIUS  := 9.0     # procedural-fallback ball radius (px)
const ORBITAL_HIT_PAD      := 16.0    # (fallback) added to the ball radius for the contact test
const ORBITAL_DAMAGE       := 25.0    # damage per ball collision (× damage-mult, crit-rollable); also fallback if the item def is missing
const ORBITAL_HIT_COOLDOWN := 0.12    # per-ball seconds before it can hit again (~1 hit per pass)
const ORBITAL_STAGGER      := 0.1     # s stagger per orbital hit
const ORBITAL_LIGHT        := 2.5     # dust-light value per ball
const ORBITAL_COL          := Color(0.6, 0.85, 1.0)   # electric arc tint (fallback draw + dust light)
const ORBITAL_SPRITE       := "res://assets/beam references/Sprite_orbital_2.png"   # spiky energy orb art (white bg keyed out)
const ORBITAL_DRAW         := 45.0    # on-screen orb diameter (px)
const ORBITAL_KEY_THR      := 240     # white-key threshold (0-255): border-connected pixels ≥ this → transparent
const ORBITAL_HIT_FRAC     := 0.45    # collision radius = ORBITAL_DRAW * 0.5 * this (matches the sprite body)
# Motion blur (afterimage ghosts + tangent streak glow). Orbit speed is fixed → blur is a constant knob.
const ORBITAL_BLUR_AMT     := 0.9     # overall blur strength (0 = crisp, 1 = full)
const trail_ghosts         := 5       # afterimage copies behind the body
const trail_arc_step       := 0.06    # rad between ghosts, stepping BACK along the orbit (curved trail; tighter spacing)
const trail_alpha_falloff  := 0.55    # each older ghost = prev * this
const trail_scale_falloff  := 0.97    # each older ghost slightly smaller
const trail_tint           := Color(0.6, 0.85, 1.0)   # cool tint pushed into ghosts (energy streak, not clones)
const streak_enabled       := true
const streak_len_min       := 8.0     # tangent streak length at low blur (px)
const streak_len_max       := 60.0    # streak length at full blur (px)
const streak_width         := 18.0    # streak thickness (px)
const streak_alpha         := 0.5

# ── TUNABLES: Void gun (Rift Maker — auto-casts a growing void on the nearest enemy; ported from weapon_system.gd) ──
const VOID_COOLDOWN     := 5.0     # s between casts (measured from cast start)
const VOID_DURATION     := 3.0     # s the void stays open
const VOID_RAMP         := 2.5     # s to grow from min→max size/damage
const VOID_RADIUS_MIN   := 10.0    # damage radius at placement (px) — AOE at 25% (was 40)
const VOID_RADIUS_MAX   := 22.5    # damage radius at full growth (px) — AOE at 25% (was 90)
const VOID_DAMAGE_MIN   := 4.0     # damage/SEC at placement (−80%)
const VOID_DAMAGE_MAX   := 39.0    # damage/SEC at full growth (−80%)
const VOID_TICK         := 0.3     # s between damage ticks
const VOID_HIT_PAD      := 14.0    # enemy half-size pad added to the radius test
const VOID_VISUAL_SCALE := 1.375   # vortex draw diameter = (radius*2) * this — purple circle +25% (was 1.1)
const VOID_PURPLE_MASK  := false   # OFF for now — hide the purple swirling-vortex overlay (the lens distortion stays on)
const VOID_COL          := Color(0.7, 0.4, 1.0)   # void purple (pickup tint / dust light)
const VOID_PULL_RADIUS  := 300.0   # non-boss enemies within this get pulled toward the rift centre
const VOID_PULL_SPEED   := 53.3    # max inward pull (px/s); ramps up as the rift grows — pull strength ÷3 (was 160)
const VOID_FOLLOW_MOUSE := true    # TEST: one constant rift that tracks the mouse cursor (vs periodic cast on nearest)
const VOID_LENS_SCALE   := 2.2     # gravitational-lens disc diameter = (radius*2) × this (warps the scene around the rift)
# Legacy rift-maker lensing (ported from weapon_system.gd) — spiral-warps the REAL scene behind the rift.
const RIFT_DISTORT_TWIST     := 1.5    # spiral swirl — softened so the scene reads THROUGH the lens (was 8.0)
const RIFT_DISTORT_FALLOFF   := 2.0
const RIFT_DISTORT_SUCK      := 0.09   # centre pinch — halved so detail isn't compressed away (was 0.18)
const RIFT_DISTORT_ROT_SPEED := 0.8
const RIFT_DISTORT_EDGE      := 0.22
const RIFT_DISTORT_BRIGHTNESS := 4.0   # brighten the scene pulled into the lens by 300% (1.0 → 4.0)

# Rift-Maker vortex shader (additive swirl) — copied verbatim from weapon_system.gd.
const RIFT_VORTEX_SHADER := "shader_type canvas_item;
render_mode blend_add;

uniform sampler2D portal_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4  arm_color  : source_color = vec4(0.55, 0.20, 0.95, 1.0);
uniform vec4  core_color : source_color = vec4(0.95, 0.75, 1.0, 1.0);
uniform vec4  eye_color  : source_color = vec4(0.04, 0.0, 0.10, 1.0);
uniform float vortex_effect_radius : hint_range(0.05, 0.5, 0.01) = 0.5;
uniform float eye_size : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float twist_strength : hint_range(0.0, 30.0, 0.1) = 9.0;
uniform float arm_count : hint_range(1.0, 12.0, 0.5) = 5.0;
uniform float pulsation_speed : hint_range(0.0, 5.0, 0.01) = 0.7;
uniform float breath_magnitude : hint_range(-0.3, 0.3, 0.005) = 0.05;
uniform float overall_rotation_speed : hint_range(-3.0, 3.0, 0.01) = 0.42;
uniform float texture_scroll_speed : hint_range(-2.0, 2.0, 0.01) = 0.5;
uniform float edge_softness : hint_range(0.01, 0.5, 0.005) = 0.12;
uniform float contrast : hint_range(0.5, 6.0, 0.05) = 2.4;
uniform float glow : hint_range(0.0, 4.0, 0.01) = 1.7;
uniform float growth : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float ang = atan(uv.y, uv.x);
	float t = sin(TIME * pulsation_speed);
	float spatial = smoothstep(0.0, vortex_effect_radius, vortex_effect_radius - dist);
	float twist = spatial * twist_strength * (0.5 + 0.5 * growth) * t;
	float a2 = ang + TIME * overall_rotation_speed + twist;
	vec2 puv  = vec2(a2 * arm_count / 6.2831853, dist - TIME * texture_scroll_speed);
	float n   = texture(portal_texture, fract(puv)).r;
	float n2  = texture(portal_texture, fract(puv * 2.0 + 0.5)).r;
	float raw = clamp(n * 0.7 + n2 * 0.5, 0.0, 1.0);
	float arms = pow(raw, contrast);
	float core = smoothstep(eye_size + 0.18, eye_size, dist);
	float eye  = smoothstep(eye_size, 0.0, dist);
	vec3 col = mix(arm_color.rgb, core_color.rgb, core);
	col = mix(col, eye_color.rgb, eye);
	float breath = 1.0 + breath_magnitude * t;
	float bright = arms * (0.35 + 0.65 * growth) * glow * breath;
	bright += core * (0.5 * growth) * glow;
	float edge  = smoothstep(vortex_effect_radius, vortex_effect_radius - edge_softness, dist);
	float alpha = edge * (1.0 - eye * 0.85);
	COLOR = vec4(col * bright, alpha);
	if (UV.x < 0.0 || UV.x > 1.0 || UV.y < 0.0 || UV.y > 1.0) COLOR.a = 0.0;
}
"

# Rift-maker gravitational-lensing distortion (ported from legacy weapon_system.gd). A screen-reading
# ColorRect drawn UNDER the bright vortex: samples the already-rendered scene and spirals it inward toward the
# rift centre (radius-dependent twist = spiral arms + a centre-weighted suck-in), seamless at the rim.
const RIFT_DISTORTION_SHADER := "shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float twist_strength : hint_range(0.0, 20.0, 0.1) = 8.0;
uniform float twist_falloff  : hint_range(0.3, 6.0, 0.05) = 2.0;
uniform float suck_in        : hint_range(0.0, 0.6, 0.01) = 0.18;
uniform float rotation_speed : hint_range(-3.0, 3.0, 0.01) = 0.8;
uniform float edge_softness  : hint_range(0.01, 0.6, 0.01) = 0.22;
uniform float growth         : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float brightness     : hint_range(0.0, 8.0, 0.05) = 1.0;
uniform vec2  rect_size = vec2(120.0, 120.0);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float dist = clamp(r * 2.0, 0.0, 1.0);
	float edge = 1.0 - smoothstep(1.0 - edge_softness, 1.0, dist);
	float gscale = 0.4 + 0.6 * growth;
	float w = pow(1.0 - dist, twist_falloff);
	float ang = atan(p.y, p.x);
	float new_ang = ang + (twist_strength * w + TIME * rotation_speed) * edge * gscale;
	float new_r   = r * (1.0 - suck_in * w * edge * gscale);
	vec2 sample_p = vec2(cos(new_ang), sin(new_ang)) * new_r;
	vec2 uv_off   = sample_p - p;
	vec2 suv      = SCREEN_UV + uv_off * rect_size * SCREEN_PIXEL_SIZE;
	vec4 scene    = texture(screen_tex, suv);
	// Brighten only the warped interior (fade to unmodified scene at the rim so the disc edge stays seamless).
	COLOR = vec4(scene.rgb * mix(1.0, brightness, edge), scene.a);
}
"

# ── TUNABLES: Lasgun (continuous tick-based beam — gained from a pickup, off until then) ──────────────────
const LASGUN_RANGE   := 3000.0   # beam length px — runs far off-screen so it reads as "infinite"
const LASGUN_BEAM_Z  := 90       # beam draws ON TOP of enemies (z≤4); still under the ship (z 100)
const LASGUN_DAMAGE  := 22.0     # damage PER TICK
const LASGUN_TICK    := 0.10     # s between damage ticks (≈ damage/sec = LASGUN_DAMAGE / this)
const LASGUN_STAGGER := 0.15     # s stagger per tick
const LASGUN_WIDTH   := 14.0     # beam hit width (px) — matches the beam visual
const LASGUN_HIT_PAD := 16.0     # enemy-radius padding for the distance-to-line hit test
const LASGUN_LIGHT        := 5.5 # dust-light value per sample point along the beam (casts light on the dust)
const LASGUN_LIGHT_SAMPLES := 16 # number of light points sampled evenly along the beam (denser = brighter line)
const LASGUN_CYCLE    := 5.0     # full period (s): the beam fires once every CYCLE
const LASGUN_DURATION := 3.0     # beam-on time within each cycle (s) → fires 3s out of every 5s
const LASGUN_CHARGE   := 1.5     # charge telegraph (s) before each burst — the orb light-gather plays over this

# ── TUNABLES: Arc (chain lightning — gained from a pickup, off until then) ────────────────────────────────
# Ported from weapon_system.gd's _fire_chain / _draw_lightning, adapted to arena world space + auto-targeting.
const ARC_ENABLED_DEFAULT := false   # off until the Arc pickup activates it
const ARC_DAMAGE   := 20.0     # damage per link
const ARC_COOLDOWN := 1.0      # s between bursts (before fire-rate mult)

# ── Red X (X-shaped fire detonation centered on the ship; data-driven Red X ported into System 2) ──
const RED_X_DAMAGE       := 60.0   # per-hit damage (× damage-mult + crit)
const RED_X_INTERVAL     := 2.0    # s between detonations — must exceed the full flash (~1.4s) so the recede
								   # completes before the next shot's retrigger clears particles (no sudden tip pop)
const RED_X_REACH        := 320.0  # arm length / hit reach (px) — twice as big
const RED_X_INNER        := 44.0   # ship-exclusion radius: fire starts on the OUTER edge of the ship area
const RED_X_ARM_HALF_DEG := 14.0   # half-width of each X arm in degrees

# ── Chemtrail (Biological): breadcrumb DoT puff-pool dropped behind the moving ship ──
const CHEMTRAIL_TICK_DAMAGE   := 6.0    # DoT per tick (× damage-mult + crit)
const CHEMTRAIL_TICK_INTERVAL := 0.25   # s between DoT ticks per puff
const CHEMTRAIL_PUFF_RADIUS   := 140.0  # DoT + visual radius of each puff (2× wider trail)
const CHEMTRAIL_PUFF_LIFETIME := 3.0    # s before a puff vanishes
const CHEMTRAIL_SHOOT_SPEED   := 100.0  # px/s the exhaust shoots out the back of the ship
const CHEMTRAIL_SPAWN_OFFSET  := 36.0   # spawn just BEHIND the ship (not at the centre / not in front)
const CHEMTRAIL_EMIT_INTERVAL := 0.06   # s between emitted puffs → a continuous stream
const CHEMTRAIL_MAX_PUFFS     := 60     # pool cap — leak guard (covers ~3s × the emit rate)
const CHEMTRAIL_DEBUG_DRAW    := false  # debug: draw a filled disc per puff (off once the fire visual is live)
# Toxic hue — sickly dark green → murky → purple, much darker/lower-value than Red X's bright fire (tunable).
const CHEMTRAIL_COL_HOT   := Color(0.55, 0.85, 0.30)   # sickly green core (additive needs some brightness to read)
const CHEMTRAIL_COL_MID   := Color(0.38, 0.48, 0.26)   # murky green transition
const CHEMTRAIL_COL_END   := Color(0.42, 0.15, 0.50)   # sickly purple
const CHEMTRAIL_INTENSITY := 0.2                        # -80% brightness/intensity → murky, dim
const CHEMTRAIL_PARTICLES := 280                        # -80% density → thin, sparse haze
const ARC_JUMPS    := 4        # extra targets the bolt chains to after the first
const ARC_ACQUIRE_RANGE := 400.0  # max px to acquire the FIRST target (chains then extend further via ARC_RANGE)
const ARC_RANGE    := 200.0    # max px between consecutive chain links
const ARC_LIFE     := 0.60     # s each lightning bolt stays visible (dissolves via the shader vanishing_value)
const ARC_STAGGER  := 0.12     # s stagger per link
const ARC_COL      := Color(0.75, 0.9, 1.0)   # cold electric blue-white (used for the dust light tint)
const ARC_LIGHT    := 1.6      # dust-light value per lit segment endpoint (more lighting effect)
# Textured-lightning visuals (2D-lightning tutorial): each chain link is a Line2D with arc_lightning.gdshader
# (scrolling thunder texture + smoothstep vanish + additive HDR), plus a CPUParticles2D spark burst + flare.
const ARC_BOLT_SHADER := "res://scripts/gameplay/fx/arc_lightning.gdshader"
const ARC_BOLT_WIDTH  := 56.0   # Line2D width (px)
const ARC_BOLT_Z      := 7      # render above enemies
const ARC_THUNDER_UNIT := 260.0 # px of bolt per thunder-texture tile
const ARC_HDR_COL     := Color(0.3, 0.8, 1.8)    # soft blue body/glow
const ARC_CORE_COL    := Color(1.8, 2.0, 2.5)    # HDR white-blue continuous core (blooms)
const ARC_CORE_SHARP  := 6.0   # white-core thinness — pow(t, this), so the core is CONTINUOUS (no threshold dashes)
const ARC_SECONDARY_FRAC := 0.4   # secondary companion strand width = 40% of the main
const ARC_STRAND_GAP  := 10.0     # secondary runs this close to the main
const ARC_SPARK_COL   := Color(1.8, 2.6, 3.6)   # HDR sparks
const ARC_SPARK_COUNT := 12

const BeamScript   := preload("res://scripts/gameplay/lasgun_ani_1.gd")   # lasgun_ani_1: Isaac-model body (no backward extension) + anchored, non-spinning, beam-aligned impact flipbook from the impact spritesheet; ani_2/ani_3 kept as backups
const SFX_BOLT_HIT: Array[AudioStream] = [
	preload("res://assets/audio/sfx/railgun.wav"),
	preload("res://assets/audio/sfx/railgun2.wav"),
]
const SFX_ENGINE_HUM: AudioStream = preload("res://assets/audio/sfx/Scifi/scifi-background-noise.wav")
const SFX_GAUSS_FIRE: AudioStream = preload("res://assets/audio/sfx/hitimpact.wav")
const SFX_GAUSS_IMPACT: AudioStream = preload("res://assets/audio/sfx/AstroMenace-SFX/weaponfire6.wav")
const SFX_LASGUN_CHARGE: AudioStream = preload("res://assets/audio/sfx/Scifi/blg_beam_01.wav")
const SFX_LASGUN_BEAM: AudioStream = preload("res://assets/audio/sfx/AstroMenace-SFX/weaponfire14.wav")
const PickupScript := preload("res://scripts/gameplay/arena_weapon_pickup.gd")
const OrbChargeScript := preload("res://scripts/gameplay/arena_orb_charge_fx.gd")
const GatMuzzleScript := preload("res://scripts/gameplay/arena_gatling_muzzle.gd")
const GaussExplFX  := preload("res://scripts/gameplay/gauss_explosion_fx.gd")
const ExplosionFX  := preload("res://scripts/gameplay/fx/explosion.gd")   # composite blast used by the Nuke
const ZSlashScript := preload("res://scripts/gameplay/fx/z_slash.gd")     # sweeping energy-slash crescent VFX

# ── Gatling tracer bolt look (copied from weapon_system.gd — visuals only) ────
const GAT_TRACER_LEN   := 16.0
const GAT_TRACER_WIDTH := 6.0
const GAT_TRACER_SCALE := 1.0
const GAT_CORE_COL := Color(1.0, 1.0, 0.85)
const GAT_BODY_COL := Color(1.0, 0.82, 0.25)
const GAT_EDGE_COL := Color(1.0, 0.5, 0.12)
const GAT_GLOW_SIZE := 2.4
const GAT_GLOW_INTENSITY := 0.30
const GAT_TAIL_LEN := 12.0

# ── Gauss plasma orb look (copied from weapon_system.gd — visuals only) ───────
const GAUSS_ORB_CORE_COL      := Color(0.85, 0.95, 1.0)
const GAUSS_ORB_LIGHT_COL     := Color(0.25, 0.65, 1.0)
const GAUSS_ORB_HAZE_COL      := Color(0.20, 0.50, 1.0)
const GAUSS_ORB_TEAR_WIDTH    := 0.62
const GAUSS_ORB_CORE_WIDTH    := 0.10
const GAUSS_ORB_CORE_BRIGHT   := 1.3
const GAUSS_ORB_LIGHT_DENSITY := 5.0
const GAUSS_ORB_CRACKLE_SPEED := 6.0
const GAUSS_ORB_HAZE_SIZE     := 0.5
const GAUSS_ORB_GLOW          := 1.4
const GAUSS_ORB_QUAD          := 2.0    # quad half-size = ball radius × this
const GAUSS_ORB_STRETCH       := 1.4    # elongation along travel
const GAUSS_TRAIL_LEN         := 10
const GAUSS_TRAIL_WIDTH       := 0.75
const GAUSS_TRAIL_ALPHA       := 0.5
const GAUSS_TRAIL_COL         := Color(0.4, 0.7, 1.0)
const GAUSS_LAUNCH_FLASH      := 48.0
const GAUSS_SPARK_RATE        := 26.0
const GAUSS_SPARK_SPEED       := 95.0
const GAUSS_SPARK_LIFE        := 0.4
const GAUSS_SPARK_LEN         := 7.0
const GAUSS_SPARK_COL         := Color(0.5, 0.85, 1.0)
const GAUSS_SPARK_ALPHA       := 0.9

# ── Gauss orb FLIPBOOK (24-frame plasma loop sprite — replaces the procedural shader orb) ──
const GAUSS_ORB_DIR     := "res://assets/beam references/Gauss_orb_files_2/"   # gauss24_00..23.png (already transparent)
const GAUSS_FRAME_COUNT := 24
const GAUSS_ORB_FPS     := 24.0    # plasma-loop playback speed (fps)
const GAUSS_ORB_DRAW    := 38.0    # on-screen orb diameter incl. transparent margin (px); full uncropped frame

# ── Gauss explosion on impact (AoE plasma burst — 3 cosmetic variants, 12 frames each) ────────
# Non-uniform animation: fast intro → long 6-7-8 peak loop → fast outro. Damage radius is FIXED at the
# peak size for the whole DURATION (see _tick_explosions / _explosion_frame_index).
const GAUSS_EXPL_DURATION     := 2.0
const GAUSS_EXPL_INTRO_TIME   := 0.30          # time for frames 1->5
const GAUSS_EXPL_OUTRO_TIME   := 0.30          # time for frames 9->12
# peak loop time = DURATION - INTRO - OUTRO (~1.40s looping frames 6,7,8)
const GAUSS_EXPL_PEAK_FRAMES  := [5, 6, 7]     # 0-indexed frames 6,7,8 (the dwell)
const GAUSS_EXPL_INTRO_FRAMES := [0, 1, 2, 3, 4]
const GAUSS_EXPL_OUTRO_FRAMES := [8, 9, 10, 11]
const GAUSS_EXPL_PEAK_FPS     := 12.0          # loop speed of the 6-7-8 peak
const GAUSS_TICK_INTERVAL     := 0.1           # s between DoT ticks (Stage 2)
const GAUSS_TICK_DAMAGE       := 5.0           # base dmg/tick; scaled by _dmg_mult + crit (Stage 2)
const GAUSS_EXPL_RADIUS       := 72.0          # FIXED damage radius (~2.4× orb hit radius 30) — tune in Stage 3
const GAUSS_EXPL_SCALE        := 0.45          # sprite scale: 336px frame → ~150px on-screen burst — tune in Stage 3
const GAUSS_EXPL_HIT_PAD      := 14.0          # enemy half-size pad added to the radius test (Stage 2)
const GAUSS_EXPL_DIR          := "res://assets/fx/gauss_explosion/"   # vN/00..11.png (transparent, glow-baked)
const GAUSS_EXPL_VARIANTS     := 3
const GAUSS_EXPL_FRAME_COUNT  := 12
const GAUSS_EXPL_FRAME_W      := 336.0
const GAUSS_EXPL_FRAME_H      := 336.0
const GAUSS_EXPL_ANCHOR       := Vector2(168.0, 168.0)   # burst-core pixel (frame center) in each frame
const GAUSS_EXPL_DEBUG_DRAW   := false         # true → draw the damage radius (+ enemy-center cutoff) to tune it

# ── Gauss shot release flash (the converging charge-up rings were removed) ────
const GC_RELEASE_FLASH  := 60.0

const GAUSS_ORB_SHADER := """
shader_type canvas_item;
render_mode blend_add;

uniform vec4  core_color   : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform vec4  light_color  : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform vec4  haze_color   : source_color = vec4(0.20, 0.50, 1.0, 1.0);
uniform float tear_width    = 0.62;
uniform float core_width    = 0.10;
uniform float core_bright   = 1.3;
uniform float light_density = 5.0;
uniform float crackle_speed = 6.0;
uniform float haze_size     = 0.5;
uniform float glow          = 1.4;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p){
	float v = 0.0; float amp = 0.5;
	for(int k = 0; k < 5; k++){ v += amp * vnoise(p); p *= 2.0; amp *= 0.5; }
	return v;
}

void fragment(){
	vec2 p = (UV - 0.5) * 2.0;
	float t = clamp((p.x + 1.0) * 0.5, 0.0, 1.0);
	float hw = tear_width * pow(t, 0.6) * (1.0 - smoothstep(0.78, 1.0, t));
	float d = abs(p.y) - hw;
	float inside = step(d, 0.0);

	vec3 col = vec3(0.0);

	float along = smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(0.85, 1.0, t));
	float core = exp(-pow(p.y / max(core_width, 0.001), 2.0)) * along;
	col += core_color.rgb * core * core_bright;

	vec2 np = vec2(p.x * light_density * 0.6 + TIME * crackle_speed * 0.35,
	               p.y * light_density + TIME * crackle_speed);
	float n = fbm(np);
	float arc = smoothstep(0.05, 0.0, abs(fract(n * 3.0) - 0.5) - 0.02);
	float rim = exp(-pow(d / 0.06, 2.0));
	float light = (arc * inside + rim) * (0.5 + 0.5 * fbm(np * 1.7 + 13.0));
	col += light_color.rgb * light * 1.6;

	float haze = exp(-pow(max(d, 0.0) / max(haze_size * 0.5, 0.001), 2.0)) * (1.0 - inside);
	col += haze_color.rgb * haze * 0.6;

	float a = clamp(core + light + haze + inside * 0.12, 0.0, 1.0);
	COLOR = vec4(col * glow, a);
}
"""

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player: Node2D = null
var _gat_acc: float = 0.0
var _gauss_charge: float = 0.0
var _dmg_mult: float = 1.0    # GameManager.get_damage_mult(), refreshed each frame (Damage upgrade cards)
var _rate_mult: float = 1.0   # GameManager.get_fire_rate_mult() (Fire Rate upgrade cards)
const BASE_CRIT_CHANCE := 0.10  # 10% base crit chance before any upgrade cards
var _crit_chance: float = BASE_CRIT_CHANCE
var _crit_damage: float = 1.5 # GameManager.get_crit_damage() (Lethality cards)
var _bullets: Array = []         # Gatling: {pos, vel, life, start}
var _orbs: Array = []            # Gauss: {pos, vel, life, start, orb_node, trail, spark_acc, dmg, dmg_ref, hit}
var _sparks: Array = []          # Gauss tail sparks: {pos, vel, life, ttl}
var _flashes: Array = []         # {pos, age, max_age, radius}
var _orb_shader: Shader = null
var _gauss_frames: Array = []      # 12-frame plasma-orb flipbook (cropped from the reference sheet)
var _gauss_fb_t: float = 0.0
var _gauss_fb_idx: int = 0
var _glow_tex: ImageTexture = null  # soft radial-gradient sprite for smooth glows (lazily built)
var _expl_frames: Array = []       # [variant][frame] → ImageTexture; 3 variants × 12 frames (Gauss explosion)
var _explosions: Array = []        # live Gauss explosions: {pos, age, variant, node, tick_acc}
# Runtime weapon-enable flags. The ship now starts UNARMED — every weapon is acquired via the start-of-run
# chest or a world/F12 pickup (acquire_weapon → activate_<kind>), so all flags start false.
var _gat_active: bool = false
# Gatling upgrade ranks (from the skill-point pool) + the level-7 capstone choice + Focus-Fire tracking.
var _gat_upg: Dictionary = {"hardened": 0, "piercing": 0, "quick": 0, "bouncing": 0, "multishot": 0, "kinetic": 0}
var _gat_capstone: String = ""   # "" | "spray" | "focus" | "healing"
var _gat_focus_target: Object = null   # Focus Fire: the enemy currently being focused
var _gat_focus_stacks: int = 0         # … consecutive hits on it
var _acquired: Array = []   # ordered list of acquired weapon kinds (max MAX_WEAPONS, unique) — backs the slot HUD
var _levels: Dictionary = {}   # kind → level (1..MAX_WEAPON_LEVEL); set on acquire, raised by level_up_weapon
var _wpoints: Dictionary = {}  # kind → skill points invested toward the NEXT level (skill-point progression)
var _enemy_visible: bool = false   # set each _process from _has_enemy_on_screen(); read by weapon_is_firing()
var _gauss_active: bool = GAUSS_ENABLED
var _engine_hum: AudioStreamPlayer = null
var _gauss_fire_player: AudioStreamPlayer = null
var _gauss_impact_player: AudioStreamPlayer = null
var _las_charge_player: AudioStreamPlayer = null
var _las_beam_player: AudioStreamPlayer = null
var _las_beam_playing: bool = false
var _arc_active: bool = ARC_ENABLED_DEFAULT   # turned on by the Arc pickup
var _red_x_active: bool = false    # turned on by the Red X pickup
var _red_x_cd: float = 0.0         # Red X detonation cooldown
var _red_x_fx: DynamicFire = null  # pooled X-flash visual (reused per shot)
var _chemtrail_active: bool = false   # turned on by the Chemtrail pickup
var _chemtrail_puffs: Array = []      # breadcrumb DoT puffs: {pos, age, max_age, radius}
var _chemtrail_tick_acc: float = 0.0  # weapon-level DoT tick (single damage per enemy per tick = no-stack)
var _chemtrail_emit_acc: float = 0.0  # emit-rate accumulator (puffs shot out the back at a steady cadence)
var _chemtrail_fx: DynamicFire = null # ONE recolored toxic-fire emitter spanning all puff centres
var _arc_cd: float = 0.0           # Arc burst cooldown
var _arcs: Array = []              # live lightning links: {ln, mat, tip, age, max_age, fx, fx_ttl, fx_freed}
var _arc_thunder_tex: ImageTexture = null   # procedural tileable thunder texture (cached)
var _arc_spark_tex: ImageTexture = null     # small stretched spark streak (cached)
var _orbital_active: bool = false  # turned on by the Orbital pickup
var _orbital_angle: float = 0.0    # current orbit angle (deg)
var _orbital_t: float = 0.0        # time accumulator for the electric-arc crackle
var _orbital_cd: Array = []        # per-ball hit cooldown timers
var _orbital_tex: Texture2D = null # orb sprite (white background keyed out); null → procedural fallback
var _orbital_damage: float = ORBITAL_DAMAGE   # per-collision damage, ported from the "orbitals" item def at _ready
var _void_active: bool = false     # turned on by the Void pickup
var _void_cd: float = 0.0          # cast cooldown (ready when <= 0)
var _void_on: bool = false         # a void is currently open
var _void_pos: Vector2 = Vector2.ZERO
var _void_age: float = 0.0         # 0 → VOID_DURATION
var _void_tick: float = 0.0        # damage-tick accumulator
var _void_node: ColorRect = null   # the swirling-vortex visual
var _void_distort: ColorRect = null   # gravitational-lens disc (screen-warp), drawn under the vortex
# ── Batch-1 weapons (Nuke / Sonic Wave / Z-Sword / Ionizing Field) ──
var _nuke_active: bool = false
var _nuke_cd: float = 0.0
var _nuke_blast_on: bool = false        # a detonation's damage hitbox is live (for NUKE_DURATION)
var _nuke_blast_t: float = 0.0
var _nuke_blast_pos: Vector2 = Vector2.ZERO   # fixed detonation centre (matches the explosion FX)
var _nuke_blast_reach: float = 0.0
var _nuke_hit: Dictionary = {}          # instance_id → true: each enemy/ruin damaged at most once per detonation
var _nuke_blast_dur: float = 0.0        # damage window = the explosion's FIRE phase only (excludes the smoke tail)
var _sonic_active: bool = false
var _sonic_cd: float = 0.0
var _sonic_queue: float = 0.0          # stagger timer for the remaining rings of a volley
var _sonic_left: int = 0               # rings still to spawn in the current volley
var _sonic_rings: Array = []           # live rings: {center, age, hit:Array, maxr}
var _zsword_active: bool = false
var _zsword_cd: float = 0.0
var _zsword_sweeping: bool = false
var _zslash: Node2D = null         # sweeping energy-slash crescent VFX node (ZSlash; additive HDR → blooms)
var _zsword_t: float = 0.0
var _zsword_start: float = 0.0
var _zsword_hit: Array = []
var _ionize_active: bool = false
var _ionize_tick: float = 0.0
var _ionize_clock: float = 0.0         # always-advancing clock for the aura pulse visual
# ── Batch-2 weapons (Boomerang / Parasite Cloud / Moroboshi-M1 / Swarm Host / Space Snake) ──
var _boom_active: bool = false
var _boom_init: bool = false
var _boom_center: Vector2 = Vector2.ZERO   # trailing centre of the rose pattern (lags the ship)
var _booms: Array = []                 # perpetual blades: {theta, spin, age, pos, hits:{}}
var _para_active: bool = false
var _para_cd: float = 0.0
var _para_clouds: Array = []           # {pos, vel, age, tick}
var _moro_active: bool = false
var _moro_init: bool = false
var _moro_pos: Vector2 = Vector2.ZERO
var _moro_cd: float = 0.0
var _moro_punch_t: float = 0.0
var _moro_punch_pos: Vector2 = Vector2.ZERO
var _swarm_active: bool = false
var _swarm_init: bool = false
var _swarm_units: Array = []           # {pos, state, target, dmg, ang}
var _snake_active: bool = false
var _snake_init: bool = false
var _snake_pts: Array = []             # head-first list of segment positions (Vector2)
var _snake_dir: float = 0.0
var _snake_tick: float = 0.0
var _homing_active: bool = false
var _homing_acc: float = 0.0
var _missiles: Array = []          # {pos, vel, speed, dmg, target_enemy, target, seek_t, life, facing, emit_acc}
var _missile_tex: Texture2D = null
var _toxic_active: bool = false    # fusion: homing missiles that trail a chemtrail (Toxic Ballistic)
var _singularity_active: bool = false   # fusion: 3 void rifts spinning around the mouse cursor (Singularities)
var _singularity_nodes: Array = []      # one rift (lens-distortion ColorRect) per void
var _singularity_tick: float = 0.0      # shared DoT-tick clock
var _singularity_pos: Array = []        # cached void centres this frame (read by get_lights)
# ── Fused weapons (Carnage / Vampire Host) ──
var _carnage_active: bool = false
var _carnage_gat_acc: float = 0.0      # Gatling-cadence accumulator (4-direction volleys)
var _carnage_redx_tick: float = 0.0    # Red X DAMAGE-tick cooldown
var _carnage_fire: DynamicFire = null  # persistent X-fire emitter (HOLD phase = continuous stream, no blink)
var _vampire_active: bool = false
var _vampire_init: bool = false
var _vampire_units: Array = []         # {pos, ang, cd}
var _vampire_rings: Array = []         # {center, aim, age, hit:[], maxr}
var _overcharger_active: bool = false  # fusion: Arc chain that drops a Gauss explosion at each struck target
var _predator_active: bool = false     # fusion: the Space Snake also fires a Lasgun beam from its head
var _predator_beam: Node2D = null      # the snake-head Lasgun beam visual (separate from the main _beam)
var _predator_beam_cd: float = 0.0     # beam damage-tick cooldown
var _predator_aim: Vector2 = Vector2.RIGHT   # current beam direction (recomputed each tick to maximise hits)
var _lasgun_active: bool = false   # turned on by the Lasgun pickup (auto-equip, accumulates with the Gatling)
var _beam_cd: float = 0.0          # Lasgun damage-tick cooldown
var _beam: Node2D = null           # additive beam VFX child (gameplay plane → sharp)
var _gat_muzzle_t: float = 0.0     # Gatling muzzle-fire intensity (1 on each shot, decays)
var _gat_muzzle_fx: Node2D = null  # additive Gatling muzzle-flash FX child
var _las_t: float = 0.0            # Lasgun cycle clock (advances while active)
var _charge_fx: Node2D = null      # Chromeleon-orb light-gather charge telegraph (ported _ChannelFX)
var _las_charge_started: bool = false   # one-shot guard so the charge FX triggers once per cycle
var _beam_light_on: bool = false   # beam currently casting dust light
var _beam_light_from := Vector2.ZERO
var _beam_light_to := Vector2.ZERO
var _beam_light_col := Color(1, 1, 1)
var _bolt_hit_player: AudioStreamPlayer = null   # bolt-hit sfx (assign in _ready when wired; null = no-op)
var _crit_layer: CanvasLayer = null
var _crit_host: Control = null

func _ready() -> void:
	add_to_group("arena_weapons")   # arena_dust queries get_lights() each frame
	_player = get_tree().get_first_node_in_group("player")
	_beam = BeamScript.new()
	add_child(_beam)
	_beam.z_index = LASGUN_BEAM_Z   # beam renders over enemy sprites
	_charge_fx = OrbChargeScript.new()
	add_child(_charge_fx)
	_gat_muzzle_fx = GatMuzzleScript.new()
	add_child(_gat_muzzle_fx)
	_zslash = ZSlashScript.new()
	add_child(_zslash)
	_load_gauss_frames()
	_load_gauss_explosion_frames()
	_bolt_hit_player = AudioStreamPlayer.new()
	_bolt_hit_player.bus = "SFX"
	add_child(_bolt_hit_player)
	_gauss_fire_player = AudioStreamPlayer.new()
	_gauss_fire_player.bus = "SFX"
	add_child(_gauss_fire_player)
	_gauss_impact_player = AudioStreamPlayer.new()
	_gauss_impact_player.stream = SFX_GAUSS_IMPACT
	_gauss_impact_player.bus = "SFX"
	add_child(_gauss_impact_player)
	_las_charge_player = AudioStreamPlayer.new()
	_las_charge_player.stream = SFX_LASGUN_CHARGE
	_las_charge_player.bus = "SFX"
	add_child(_las_charge_player)
	_las_beam_player = AudioStreamPlayer.new()
	_las_beam_player.stream = SFX_LASGUN_BEAM
	_las_beam_player.bus = "SFX"
	add_child(_las_beam_player)
	_engine_hum = AudioStreamPlayer.new()
	_engine_hum.stream = SFX_ENGINE_HUM
	_engine_hum.bus = "SFX"
	_engine_hum.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_engine_hum)
	_engine_hum.finished.connect(func() -> void:
		if GameManager.ship_hp > 0:
			_engine_hum.play()
	)
	GameManager.ship_hp_changed.connect(_on_ship_hp_changed)
	_engine_hum.play()
	_crit_layer = CanvasLayer.new()
	_crit_layer.layer = 12
	add_child(_crit_layer)
	_crit_host = Control.new()
	_crit_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crit_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crit_layer.add_child(_crit_host)

## Load the 24-frame Gauss plasma-orb flipbook (individual transparent PNGs). CPU Image.load (no import
## dependency). The FULL frame is kept (NOT cropped to get_used_rect): the glow pulses, so per-frame
## content bounds vary — cropping + fixed-size draw would make the orb appear to grow/shrink. All frames
## share one centered canvas, so the full-frame draw keeps a constant size; only the plasma animates.
func _load_gauss_frames() -> void:
	for i in GAUSS_FRAME_COUNT:
		var path := "%sgauss24_%02d.png" % [GAUSS_ORB_DIR, i]
		var img := Image.new()
		if img.load(path) != OK:
			push_warning("arena_weapons: could not load Gauss orb frame %s" % path)
			continue
		_gauss_frames.append(ImageTexture.create_from_image(img))

## Load the 3 explosion variants (12 transparent frames each) into _expl_frames[variant][frame].
## CPU Image.load (no import dependency), same approach as the orb flipbook.
func _load_gauss_explosion_frames() -> void:
	_expl_frames.clear()
	for v in range(1, GAUSS_EXPL_VARIANTS + 1):
		var frames: Array = []
		for i in GAUSS_EXPL_FRAME_COUNT:
			var path := "%sv%d/%02d.png" % [GAUSS_EXPL_DIR, v, i]
			var img := Image.new()
			if img.load(path) != OK:
				push_warning("arena_weapons: could not load Gauss explosion frame %s" % path)
				continue
			frames.append(ImageTexture.create_from_image(img))
		if not frames.is_empty():
			_expl_frames.append(frames)

## Light sources this weapon currently emits, for the dust field: one per live projectile/beam.
## Each: {pos: world Vector2, value: float (light strength), color: Color}.
func get_lights() -> Array:
	var lights: Array = []
	if _gat_active:
		for b: Dictionary in _bullets:
			lights.append({"pos": b["pos"], "value": GAT_LIGHT, "color": GAT_BODY_COL})
	if _gauss_active:
		for o: Dictionary in _orbs:
			lights.append({"pos": o["pos"], "value": GAUSS_LIGHT, "color": GAUSS_ORB_LIGHT_COL})
	if _arc_active:
		for a: Dictionary in _arcs:
			lights.append({"pos": a["tip"], "value": ARC_LIGHT, "color": ARC_COL})
	if _lasgun_active and _beam_light_on:
		# Light points sampled along the beam → the dust glows the whole length of the laser.
		for i in LASGUN_LIGHT_SAMPLES:
			var f := float(i) / float(maxi(1, LASGUN_LIGHT_SAMPLES - 1))
			lights.append({"pos": _beam_light_from.lerp(_beam_light_to, f), "value": LASGUN_LIGHT, "color": _beam_light_col})
	if (_orbital_active or _singularity_active) and _player != null and is_instance_valid(_player):
		for c: Vector2 in _orbital_positions():
			lights.append({"pos": c, "value": ORBITAL_LIGHT, "color": ORBITAL_COL})
	if _singularity_active:
		for c: Vector2 in _singularity_pos:
			lights.append({"pos": c, "value": 6.0, "color": VOID_COL})   # void-purple glow at each rift
	if _void_on:
		lights.append({"pos": _void_pos, "value": 6.0, "color": VOID_COL})
	if _ionize_active and _player != null and is_instance_valid(_player):
		lights.append({"pos": _player.global_position, "value": 4.0, "color": IONIZE_COL})
	for boom: Dictionary in _booms:
		lights.append({"pos": boom["pos"], "value": 2.0, "color": BOOM_COL})
	for pc: Dictionary in _para_clouds:
		lights.append({"pos": pc["pos"], "value": 3.0, "color": PARA_COL})
	if _moro_active and _moro_init:
		lights.append({"pos": _moro_pos, "value": 3.0, "color": MORO_COL})
	if _swarm_active:
		for u: Dictionary in _swarm_units:
			lights.append({"pos": u["pos"], "value": 2.0, "color": SWARM_COL})
	if (_snake_active or _predator_active) and not _snake_pts.is_empty():
		lights.append({"pos": _snake_pts[0], "value": 3.0, "color": SNAKE_COL})
	return lights

## True when the equipment-driven loadout engine has a primary weapon equipped (so this default
## auto-gun should stand down and let the loadout engine fire instead).
func _loadout_has_primary() -> bool:
	var lo := get_tree().get_first_node_in_group("arena_loadout")
	return lo != null and lo.has_method("has_primary_weapon") and lo.has_primary_weapon()

func _has_enemy_on_screen() -> bool:
	if GameManager.has_method("is_boss_alive") and GameManager.is_boss_alive():
		return true
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	if enemies.is_empty():
		return false
	var canvas_xform := get_viewport().get_canvas_transform()
	var vp_size := get_viewport().get_visible_rect().size
	var screen_rect := Rect2(Vector2.ZERO, vp_size).grow_individual(
		vp_size.x * 0.5, vp_size.y * 0.5, vp_size.x * 0.5, vp_size.y * 0.5)
	for en in enemies:
		if not is_instance_valid(en):
			continue
		if screen_rect.has_point(canvas_xform * (en as Node2D).global_position):
			return true
	return false

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# Player-stat multipliers (base values 1.0 → identical to before).
	_dmg_mult = GameManager.get_damage_mult() if GameManager.has_method("get_damage_mult") else 1.0
	_rate_mult = maxf(0.01, GameManager.get_fire_rate_mult()) if GameManager.has_method("get_fire_rate_mult") else 1.0
	_crit_chance = BASE_CRIT_CHANCE + (GameManager.get_crit_chance() if GameManager.has_method("get_crit_chance") else 0.0)
	_crit_damage = GameManager.get_crit_damage() if GameManager.has_method("get_crit_damage") else 1.5
	var enemy_on_screen := _has_enemy_on_screen()
	_enemy_visible = enemy_on_screen   # cached for the slot HUD's firing-pulse query
	# Stand down the default Gatling when the player has an inventory weapon equipped — the loadout
	# engine (arena_loadout.gd) drives firing then, so the two don't stack.
	if _gat_active and not _loadout_has_primary():
		var gat_interval := GAT_FIRE_INTERVAL / (_rate_mult * (1.0 + _gat_fire_bonus()))   # Quick Round + Lv5
		_gat_acc += delta
		if enemy_on_screen:
			while _gat_acc >= gat_interval:
				_gat_acc -= gat_interval
				_fire_gatling()
		else:
			# No target: stay primed for exactly ONE immediate shot — do NOT bank a backlog, or the moment a
			# target appears the while-loop above dumps every banked interval at once (the "wall of bullets" + lag).
			_gat_acc = minf(_gat_acc, gat_interval)
	if _gauss_active:
		# Keep charging while waiting; fire only when an enemy is visible.
		_gauss_charge += delta
		if _gauss_charge >= GAUSS_CHARGE_TIME / _rate_mult and enemy_on_screen:
			_gauss_charge = 0.0
			_fire_gauss()
	if _arc_active and enemy_on_screen:
		_fire_arc(delta)
	if _red_x_active:
		_red_x_cd -= delta
		if _red_x_cd <= 0.0 and enemy_on_screen:
			_red_x_cd = RED_X_INTERVAL / _rate_mult
			_fire_red_x()
	if _chemtrail_active:
		_tick_chemtrail(delta)
	if _orbital_active:
		_tick_orbital(delta)
	if _void_active:
		_tick_void(delta)
	if _nuke_active:
		_tick_nuke(delta, enemy_on_screen)
	if _sonic_active:
		_tick_sonic(delta, enemy_on_screen)
	if _zsword_active:
		_tick_zsword(delta, enemy_on_screen)
	if _ionize_active:
		_tick_ionize(delta)
	if _boom_active:
		_tick_boom(delta, enemy_on_screen)
	if _para_active:
		_tick_para(delta, enemy_on_screen)
	if _moro_active:
		_tick_moro(delta)
	if _swarm_active:
		_tick_swarm(delta)
	if _snake_active:
		_tick_snake(delta)
	if _carnage_active:
		_tick_carnage(delta, enemy_on_screen)
	if _vampire_active:
		_tick_vampire(delta)
	if _overcharger_active and enemy_on_screen:
		_fire_arc(delta, "overcharger", true)   # Arc chain + a Gauss explosion at each struck target
	if _predator_active:
		_tick_predator(delta, enemy_on_screen)
	if _homing_active:
		_tick_homing(delta, enemy_on_screen)
	if _toxic_active:
		_tick_toxic(delta, enemy_on_screen)
	if _singularity_active:
		_tick_singularity(delta)
	if _lasgun_active:
		if enemy_on_screen:
			_fire_lasgun(delta)
		else:
			# Pause the lasgun cycle — stop beam visuals/audio but don't reset _las_t.
			if _las_beam_playing:
				_las_beam_player.stop()
				_las_beam_playing = false
			if _beam != null:
				_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
			_beam_light_on = false
	elif _beam != null:
		_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
	_tick_bullets(delta)
	_tick_orbs(delta)
	_tick_explosions(delta)
	_tick_arcs(delta)
	_update_sparks(delta)
	_update_flashes(delta)
	_update_gat_muzzle(delta)
	queue_redraw()

## Decay the Gatling muzzle-fire flash and feed the FX child the two wing-muzzle positions + aim each frame.
func _update_gat_muzzle(delta: float) -> void:
	_gat_muzzle_t = maxf(0.0, _gat_muzzle_t - delta / GAT_MUZZLE_DECAY)
	if _gat_muzzle_fx == null:
		return
	if _gat_active and _gat_muzzle_t > 0.0 and _player != null and is_instance_valid(_player):
		var fwd := _forward()
		var perp := Vector2(-fwd.y, fwd.x)
		var base := _player.global_position + fwd * GAT_WING_FWD
		var muzzles := [base - perp * (GAT_WING_SPACING * 0.5), base + perp * (GAT_WING_SPACING * 0.5)]
		_gat_muzzle_fx.set_state(muzzles, fwd, _gat_muzzle_t, GAT_CORE_COL, GAT_BODY_COL, GAT_EDGE_COL)
	else:
		_gat_muzzle_fx.set_state([], Vector2.UP, 0.0, GAT_CORE_COL, GAT_BODY_COL, GAT_EDGE_COL)

# ── Aim helpers ───────────────────────────────────────────────────────────────
func _forward() -> Vector2:
	return Vector2.UP.rotated(_player.rotation)

func _muzzle() -> Vector2:
	return _player.global_position + _forward() * MUZZLE_OFFSET

## Base damage × the Damage-card multiplier, then a crit roll. Returns {dmg, is_crit}.
func _roll_damage(base: float, kind := "") -> Dictionary:
	var dmg := base * _dmg_mult * _lvl_mult(kind)
	var is_crit := false
	if _crit_chance > 0.0 and randf() < _crit_chance:
		dmg *= _crit_damage
		is_crit = true
	return {"dmg": dmg, "is_crit": is_crit}

func _spawn_crit_number(world_pos: Vector2, amount: float) -> void:
	if _crit_host == null:
		return
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var lbl := Label.new()
	lbl.text = str(roundi(amount))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.10))
	lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 7)
	lbl.reset_size()
	lbl.position = screen_pos + Vector2(randf_range(-10.0, 10.0), -16.0) - lbl.size * 0.5
	lbl.scale = Vector2.ONE * 1.6
	_crit_host.add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 48.0, 0.80)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.80).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: lbl.queue_free())

# ── Gatling — twin wing streams ─────────────────────────────────────────────────
# ── Gatling upgrades: API (the UI grants ranks) + effective stats (ranks + level rewards + capstone) ──
func gat_upgrade_rank(id: String) -> int:
	return int(_gat_upg.get(id, 0))

## Grant +1 rank in a pool upgrade (capped at its max; max 0 = uncapped). Returns true if applied.
func gat_grant_upgrade(id: String) -> bool:
	if not GATLING_POOL.has(id):
		return false
	var maxr := int(GATLING_POOL[id]["max"])
	if maxr > 0 and int(_gat_upg.get(id, 0)) >= maxr:
		return false
	_gat_upg[id] = int(_gat_upg.get(id, 0)) + 1
	return true

func gat_set_capstone(id: String) -> void:
	_gat_capstone = id

func _gat_lvl() -> int:
	return weapon_level("gatling")   # 0 if unowned, 1..7

func _gat_pierce_chance() -> float:
	return clampf(float(_gat_upg["piercing"]) * 0.10 + (0.20 if _gat_lvl() >= 2 else 0.0), 0.0, 1.0)

func _gat_bounce_chance() -> float:
	return clampf(float(_gat_upg["bouncing"]) * 0.08 + (0.20 if _gat_lvl() >= 1 else 0.0), 0.0, 1.0)

func _gat_fire_bonus() -> float:
	return float(_gat_upg["quick"]) * 0.08 + (0.30 if _gat_lvl() >= 4 else 0.0)

func _gat_multishot_chance() -> float:
	return float(_gat_upg["multishot"]) * 0.10

func _gat_multishot_flat() -> int:
	return (1 if _gat_lvl() >= 5 else 0) + (2 if _gat_capstone == "spray" else 0)

func _gat_spread_deg() -> float:
	return 15.0 if _gat_capstone == "spray" else GAT_SPREAD_DEG   # Spray and Pray → much wider fan

## Per-bullet base damage before crit/global mult: (base + flat) × Lv4 dmg reward × kinetic mastery.
func _gat_bullet_base() -> float:
	var lvl := _gat_lvl()
	var dmg_mult := 1.0 + (0.30 if lvl >= 3 else 0.0)                                # Lv3: +30% damage
	var kinetic_mult := 1.0 + float(_gat_upg["kinetic"]) * 0.10 + (0.30 if lvl >= 6 else 0.0)
	return (GAT_DAMAGE + float(_gat_upg["hardened"])) * dmg_mult * kinetic_mult

func _fire_gatling() -> void:
	# Two parallel streams from the left/right wing muzzles, plus any Multishot extra bullets fanned out from
	# wider muzzle points. Offsets are in the ship's local frame (fwd/perp) so they rotate with the aim.
	var fwd := _forward()
	var perp := Vector2(-fwd.y, fwd.x)   # right-perpendicular (rotates with the ship)
	var base := _player.global_position + fwd * GAT_WING_FWD
	var spread := _gat_spread_deg()
	# Total bullets = 2 base + flat multishot + a chance-based extra. Placed symmetric along the perp axis.
	var extra := _gat_multishot_flat()
	if _gat_multishot_chance() > 0.0 and randf() < _gat_multishot_chance():
		extra += 1
	var total := 2 + extra
	for n in total:
		# Symmetric perp offset: n 0/1 are the L/R wings; extras step further out alternating sides.
		var slot := float(n / 2)                  # 0,0,1,1,2,2…  (pair index → distance out)
		var sgn := -1.0 if (n % 2 == 0) else 1.0   # alternate left / right
		var off := perp * (sgn * GAT_WING_SPACING * (0.5 + slot * 0.6))
		var dir := fwd
		if spread > 0.0:
			dir = fwd.rotated(deg_to_rad(randf_range(-spread, spread)))
		var start: Vector2 = base + off
		var bullet := {"pos": start, "vel": dir * GAT_SPEED, "life": 0.0, "start": start, "kind": "gatling", "hits": []}
		# Healing Round capstone: a directly-fired bullet has a 1-in-GAT_HEAL_ODDS chance to be a healing bullet.
		if _gat_capstone == "healing" and randi() % GAT_HEAL_ODDS == 0:
			bullet["healing"] = true
		_bullets.append(bullet)
	_gat_muzzle_t = 1.0   # refresh the muzzle-fire flash on every shot

# ── Lasgun (tick-based hitscan beam — fires along the ship facing = toward the cursor) ───────────────────
func _fire_lasgun(delta: float) -> void:
	# Duty cycle: fire for LASGUN_DURATION out of every LASGUN_CYCLE seconds, with a charge telegraph in the
	# last LASGUN_CHARGE seconds before each burst.
	_las_t += delta
	var phase := fmod(_las_t, LASGUN_CYCLE)
	var firing := phase < LASGUN_DURATION
	if not firing:
		# Charge telegraph (Chromeleon orb light-gather) in the last LASGUN_CHARGE seconds before the burst.
		var charge_start := LASGUN_CYCLE - LASGUN_CHARGE
		if phase >= charge_start and _charge_fx != null:
			_charge_fx.position = _muzzle()   # follow the moving nose
			if not _las_charge_started:
				_charge_fx.start(LASGUN_CHARGE)
				_las_charge_player.play()
				_las_charge_started = true
		if _beam != null:
			_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
		_beam_light_on = false
		_beam_cd = 0.0   # so the first damage tick lands the instant the burst starts
		if _las_beam_playing:
			_las_beam_player.stop()
			_las_beam_playing = false
		return
	# Firing: kill the charge FX and arm the next cycle's telegraph.
	_las_charge_started = false
	if not _las_beam_playing:
		_las_beam_player.play()
		_las_beam_playing = true
	elif not _las_beam_player.playing:
		_las_beam_player.play()
	if _charge_fx != null:
		_charge_fx.stop()
	var from := _muzzle()
	var dir := _forward()
	# ONLY bosses block the beam. Find the nearest boss along the line; otherwise the beam runs to max range.
	var block_along := LASGUN_RANGE
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		var tb: Vector2 = (b as Node2D).global_position - from
		var balong := tb.dot(dir)
		if balong < 0.0 or balong > LASGUN_RANGE:
			continue
		var _br = b.get("hit_radius")
		var bw: float = LASGUN_WIDTH * 0.5 + (float(_br) if _br != null else LASGUN_HIT_PAD)
		if (tb - dir * balong).length() <= bw and balong < block_along:
			block_along = balong
	var blocked := block_along < LASGUN_RANGE
	# Beam ends at the blocking boss, else far off-screen (looks infinite). Non-degenerate at point-blank.
	var to_pt := from + dir * maxf(2.0, block_along)
	if _beam != null:
		_beam.set_beam(from, to_pt, true, blocked)
	# Cast light along the beam onto the dust/rocks (rainbow hue tracks the beam).
	_beam_light_on = true
	_beam_light_from = from
	_beam_light_to = to_pt
	_beam_light_col = Color.from_hsv(fposmod(_las_t * 0.5, 1.0), 0.7, 1.0)
	# Tick damage to EVERY enemy the beam touches up to the block point (pierce-all; a boss stops it).
	_beam_cd -= delta
	if _beam_cd <= 0.0:
		_beam_cd = LASGUN_TICK / _rate_mult
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			var to_e: Vector2 = (en as Node2D).global_position - from
			var along := to_e.dot(dir)
			if along < 0.0 or along > block_along:
				continue
			var _en_r3 = en.get("hit_radius")
			var hit_w: float = LASGUN_WIDTH * 0.5 + (float(_en_r3) if _en_r3 != null else LASGUN_HIT_PAD)
			if (to_e - dir * along).length() > hit_w:
				continue
			if en.has_method("take_damage"):
				var _las_r := _roll_damage(LASGUN_DAMAGE, "lasgun")
				en.take_damage(float(_las_r["dmg"]), LASGUN_STAGGER)
				if bool(_las_r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(_las_r["dmg"]))

## Called by the Lasgun pickup on collection — adds the beam to the active loadout (accumulates with Gatling).
func activate_lasgun() -> void:
	_lasgun_active = true
	_las_t = LASGUN_CYCLE - LASGUN_CHARGE   # begin in the charge window → telegraph, then the first burst

func _on_ship_hp_changed(hp: int) -> void:
	if not is_instance_valid(_engine_hum):
		return
	if hp <= 0:
		_engine_hum.stop()
	elif not _engine_hum.playing:
		_engine_hum.play()

# ── Arc (chain lightning — auto-targets nearest enemy, then chains to nearby foes) ───────────────────────
## Cooldown-gated burst: strike the enemy nearest the ship, then chain to the nearest un-hit enemy within
## ARC_RANGE, up to ARC_JUMPS extra links. Each link applies damage + records a fading lightning segment.
func _fire_arc(delta: float, kind := "arc", gauss_on_hit := false) -> void:
	_arc_cd -= delta
	if _arc_cd > 0.0:
		return
	_arc_cd = ARC_COOLDOWN / _rate_mult
	_ensure_arc_textures()
	var muzzle := _muzzle()
	var hit_set: Array = []                 # enemies already struck this burst (no double-hits)
	var cur := _nearest_enemy(_player.global_position, ARC_ACQUIRE_RANGE, hit_set)
	if cur == null:
		return
	# Pass 1: walk the chain, apply damage, collect the strike points (muzzle → t1 → t2 …).
	var chain := PackedVector2Array([muzzle])
	for _j in range(1 + maxi(0, ARC_JUMPS)):
		if cur == null:
			break
		var c: Vector2 = (cur as Node2D).global_position
		if cur.has_method("take_damage"):
			var _arc_r := _roll_damage(ARC_DAMAGE, kind)
			cur.take_damage(float(_arc_r["dmg"]), ARC_STAGGER)
			if bool(_arc_r["is_crit"]):
				_spawn_crit_number(c, float(_arc_r["dmg"]))
		if gauss_on_hit:
			_spawn_gauss_explosion(c, kind)   # Overcharger: a Gauss blast at every chained target
		chain.append(c)
		hit_set.append(cur)
		cur = _nearest_enemy(c, ARC_RANGE, hit_set)
	if chain.size() < 2:
		return
	# Pass 2 (textured-lightning rewrite): each link is a static Line2D bolt (+ spark burst at its strike point).
	# Free the PREVIOUS burst's bolts first so a new shot REPLACES the old arc instead of stacking additively on a
	# still-fading one (the over-bright "regenerate" stack). Damage/chaining above is unchanged.
	_clear_arcs()
	for i in range(chain.size() - 1):
		var delay := float(i) * ARC_STAGGER * 0.4   # later links dissolve slightly later → outward sweep
		_spawn_arc_bolt(chain[i], chain[i + 1], delay)
		_spawn_arc_sparks(chain[i + 1])

## Free all live arc bolts + their fx (called on a new burst so arcs don't accumulate/stack).
func _clear_arcs() -> void:
	for a: Dictionary in _arcs:
		for bolt: Dictionary in a["bolts"]:
			var n: Node = bolt["ln"]
			if is_instance_valid(n):
				n.queue_free()
		for fx in a["fx"]:
			if is_instance_valid(fx):
				(fx as Node).queue_free()
	_arcs.clear()

## Nearest live arena_enemy to `from` within `max_dist`, skipping any in `exclude`.
func _nearest_enemy(from: Vector2, max_dist: float, exclude: Array) -> Node:
	var best: Node = null
	var best_d := max_dist
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or en in exclude:
			continue
		var d := (en as Node2D).global_position.distance_to(from)
		if d <= best_d:
			best_d = d
			best = en
	return best

## Advance each live bolt: animate its shader `vanishing_value` (dissolve), free the spark/flare FX once they've
## played, and free the Line2D when its life ends. (Bolts are Line2D children, not immediate-mode draws.)
func _tick_arcs(delta: float) -> void:
	var i := _arcs.size() - 1
	while i >= 0:
		var a: Dictionary = _arcs[i]
		var age := float(a["age"]) + delta
		a["age"] = age
		var delay: float = a["delay"]
		var life := clampf((age - delay) / maxf(0.01, float(a["max_age"]) - delay), 0.0, 1.0)
		for bolt: Dictionary in a["bolts"]:
			var mat: ShaderMaterial = bolt["mat"]
			if is_instance_valid(mat):
				mat.set_shader_parameter("vanishing_value", life)   # 0→1 dissolves the thunder texture away
		if not bool(a["fx_freed"]) and age >= float(a["fx_ttl"]):
			a["fx_freed"] = true
			for fx in a["fx"]:
				if is_instance_valid(fx):
					(fx as Node).queue_free()
		if age >= float(a["max_age"]):
			for bolt: Dictionary in a["bolts"]:
				var ln: Line2D = bolt["ln"]
				if is_instance_valid(ln):
					ln.queue_free()
			for fx in a["fx"]:
				if is_instance_valid(fx):
					(fx as Node).queue_free()
			_arcs.remove_at(i)
		else:
			_arcs[i] = a
		i -= 1

## Build/cache the procedural textures the textured-lightning visuals need (thunder bolt + spark streak).
func _ensure_arc_textures() -> void:
	if _arc_thunder_tex == null:
		_arc_thunder_tex = _make_thunder_tex()
	if _arc_spark_tex == null:
		_arc_spark_tex = _make_arc_spark_tex()

## One chain link = a MAIN Line2D bolt + a thinner SECONDARY strand running CLOSE alongside it (same jagged path
## nudged a few px, different texture phase) + FRACTAL branches forking off toward the shot direction. All use the
## thunder shader. `delay` staggers the dissolve so outer links linger. Bolts stored in one `bolts` list.
func _spawn_arc_bolt(a: Vector2, b: Vector2, delay: float) -> void:
	var tiling := maxf(1.0, a.distance_to(b) / ARC_THUNDER_UNIT)
	var pts := _arc_line_points(a, b)
	var bolts: Array = []
	bolts.append(_make_bolt_line(pts, ARC_BOLT_WIDTH, tiling, 0.0))
	# secondary: SAME jagged path nudged a few px → a thin companion strand that crackles out of phase, close by
	bolts.append(_make_bolt_line(_offset_points(pts, randf_range(-ARC_STRAND_GAP, ARC_STRAND_GAP)),
		ARC_BOLT_WIDTH * ARC_SECONDARY_FRAC, tiling, 0.4))
	_arcs.append({"bolts": bolts, "tip": b, "age": 0.0, "max_age": ARC_LIFE, "delay": delay,
		"fx": [], "fx_ttl": 0.3, "fx_freed": false})

## Build one textured Line2D bolt (its own shader material) → {ln, mat}. `phase` shifts the thunder texture so a
## strand crackles out of phase with another.
func _make_bolt_line(points: PackedVector2Array, width: float, tiling: float, phase: float) -> Dictionary:
	var ln := Line2D.new()
	ln.points = points
	ln.width = width
	ln.texture = _arc_thunder_tex
	ln.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	ln.joint_mode = Line2D.LINE_JOINT_ROUND
	ln.begin_cap_mode = Line2D.LINE_CAP_NONE
	ln.end_cap_mode = Line2D.LINE_CAP_NONE
	ln.z_index = ARC_BOLT_Z
	var mat := ShaderMaterial.new()
	mat.shader = load(ARC_BOLT_SHADER)
	mat.set_shader_parameter("basic_texture", _arc_thunder_tex)
	mat.set_shader_parameter("color", ARC_HDR_COL)
	mat.set_shader_parameter("core_color", ARC_CORE_COL)
	mat.set_shader_parameter("core_sharp", ARC_CORE_SHARP)   # pow(t, this) → continuous core (no dashes)
	mat.set_shader_parameter("scroll_speed", 0.0)   # STATIC bolt — generated once at the shot, no crawl/fluctuation
	mat.set_shader_parameter("tiling_x", tiling)
	mat.set_shader_parameter("phase", phase)
	mat.set_shader_parameter("vanishing_value", 0.0)
	ln.material = mat
	add_child(ln)
	return {"ln": ln, "mat": mat}

## A SHARP, jagged centreline a→b — random perpendicular kinks per point (sharp angular bends), tapered to 0 at
## the endpoints. The thunder texture adds finer crackle on top.
func _arc_line_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var dist := a.distance_to(b)
	if dist < 1.0:
		return PackedVector2Array([a, b])
	var perp := (b - a).normalized().rotated(PI * 0.5)
	var segs := 9
	var amp := clampf(dist * 0.1, 8.0, 50.0)                  # bigger random kinks = sharper bends
	var pts := PackedVector2Array()
	pts.append(a)
	for i in range(1, segs):
		var u := float(i) / float(segs)
		pts.append(a.lerp(b, u) + perp * randf_range(-1.0, 1.0) * amp * sin(u * PI))
	pts.append(b)
	return pts

## Shift a path perpendicular to its overall heading by `d` (tapered to 0 at the ends so it still meets a/b).
func _offset_points(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var perp := (pts[pts.size() - 1] - pts[0]).normalized().rotated(PI * 0.5)
	var out := PackedVector2Array()
	for i in pts.size():
		var u := float(i) / float(pts.size() - 1)
		out.append(pts[i] + perp * d * sin(u * PI))
	return out

## Stretched spark burst at a strike point (CPUParticles2D, additive HDR, velocity-aligned). Tracked + freed
## by the owning bolt in _tick_arcs (see fx/fx_ttl).
func _spawn_arc_sparks(pos: Vector2) -> void:
	if _arcs.is_empty():
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = ARC_SPARK_COUNT
	p.lifetime = 0.2
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 320.0
	p.initial_velocity_max = 700.0
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 16.0
	p.texture = _arc_spark_tex
	var c_fade := ARC_SPARK_COL
	c_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([ARC_SPARK_COL, ARC_SPARK_COL, c_fade])
	p.color_ramp = grad
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.6))
	taper.add_point(Vector2(0.15, 1.0))
	taper.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = taper
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	p.z_index = ARC_BOLT_Z
	add_child(p)
	(_arcs[_arcs.size() - 1]["fx"] as Array).append(p)

## Procedural TILEABLE thunder texture: a CONTINUOUS jagged glowing band (red = brightness). The bright centreline
## jitters (integer-harmonic sines so left/right edges wrap seamlessly) and ALWAYS peaks at 1.0 along its length,
## so the bolt's bright core is an unbroken line. h is tall (64) so the bright band is well-resolved (not sub-pixel).
func _make_thunder_tex() -> ImageTexture:
	var w := 256
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var midy := float(h) * 0.5
	for x in w:
		var fx := float(x) / float(w) * TAU
		var cy := midy + sin(fx) * 8.0 + sin(fx * 3.0 + 1.3) * 4.0 + sin(fx * 7.0 + 0.5) * 2.0   # jagged, tileable
		var bright := 0.9 + 0.1 * (sin(fx * 11.0 + 2.0) * 0.5 + 0.5)    # always high → the centre always peaks at 1.0
		for y in h:
			var dy := absf(float(y) - cy)
			var core := pow(clampf(1.0 - dy / 7.0, 0.0, 1.0), 1.3)        # bright RESOLVED centreline (≈22% of half-h)
			var glow := pow(clampf(1.0 - dy / midy, 0.0, 1.0), 1.7) * 0.7  # soft glow halo, fades to 0 at the edge
			var v := clampf((core + glow) * bright, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, v))
	return ImageTexture.create_from_image(img)

## Small vertical streak for sparks (align_y stretches it along the velocity).
func _make_arc_spark_tex() -> ImageTexture:
	var w := 8
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	for y in h:
		for x in w:
			var fxr := absf(float(x) - cx) / cx
			var fyr := absf(float(y) - cy) / cy
			var v := pow(clampf(1.0 - fxr, 0.0, 1.0), 2.0) * pow(clampf(1.0 - fyr, 0.0, 1.0), 1.2)
			img.set_pixel(x, y, Color(v, v, v, v))
	return ImageTexture.create_from_image(img)

## Called by the Arc pickup on collection — adds chain lightning to the active loadout (accumulates).
func activate_arc() -> void:
	_arc_active = true
	_arc_cd = 0.0   # fire on the next frame

## Called by the Red X pickup — turn on the X-shaped fire detonation.
func activate_red_x() -> void:
	_red_x_active = true
	_red_x_cd = 0.0   # fire as soon as an enemy is visible

## One Red X detonation: damage everything along the 4 diagonal arms, then play the pooled X fire-flash.
func _fire_red_x(kind := "red_x") -> void:
	_red_x_damage(kind, 1.0)
	_spawn_red_x_fire(_player.global_position, RED_X_REACH)

## Apply Red X arm damage once (ported from arena_loadout._fire_cross). `scale` multiplies RED_X_DAMAGE so the
## same geometry can be used for a single full detonation (scale 1.0) or smaller periodic DPS ticks (Carnage).
## `base_angle` = the direction of arm 0; the 4 arms sit at base_angle + k·90°. Default PI/4 = the fixed X
## diagonals (normal Red X). Carnage passes the ship facing so the arms align with its 4 Gatling directions.
func _red_x_damage(kind: String, scale: float, base_angle := PI / 4.0) -> void:
	var center := _player.global_position
	var arm_half := deg_to_rad(RED_X_ARM_HALF_DEG)
	var base := RED_X_DAMAGE * scale
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		var off := ep - center
		var dist := off.length()
		var _en_r = en.get("hit_radius")
		if dist > RED_X_REACH + (float(_en_r) if _en_r != null else 0.0):
			continue
		if dist < RED_X_INNER:
			continue                                   # leave the ship area empty (no centre damage)
		var fold := fposmod(off.angle() - base_angle, PI / 2.0)   # fold into 4-fold symmetry around base_angle
		var d_to_arm := minf(fold, PI / 2.0 - fold)               # 0 on an arm, PI/4 between arms
		if d_to_arm <= arm_half:
			if en.has_method("take_damage"):
				var r := _roll_damage(base, kind)
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number(ep, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		if center.distance_to((ruin as Node2D).global_position) <= RED_X_REACH:
			if ruin.has_method("take_damage"):
				ruin.take_damage(base * _dmg_mult * _lvl_mult(kind))

## Pooled DynamicFire X-flash (recycled per shot to avoid rebuilding the GPU particle system each time).
func _spawn_red_x_fire(center: Vector2, reach: float) -> void:
	if _red_x_fx == null or not is_instance_valid(_red_x_fx):
		_red_x_fx = DynamicFire.new()
		_red_x_fx.shape             = "cross"
		_red_x_fx.arm_count         = 4
		_red_x_fx.ring_start_angle  = PI / 4.0      # X diagonals (matches the hit test)
		_red_x_fx.z_index           = 6
		_red_x_fx.particle_lifetime = 0.35
		_red_x_fx.draw_duration     = 0.50          # 0.5s to travel from the ship's edge to the endpoint
		_red_x_fx.draw_ease         = 1.0
		_red_x_fx.hold_duration     = 0.06          # brief full-X moment at peak
		_red_x_fx.burnout_duration  = 0.50          # 0.5s to recede back from ship → endpoint
		_red_x_fx.recede_burnout    = true          # disappear directionally (inner→outer), not a uniform fade
		_red_x_fx.particle_amount   = 330           # +50% density
		_red_x_fx.particle_size_min = 40.0
		_red_x_fx.particle_size_max = 92.0
		_red_x_fx.intensity         = 0.5           # each particle LDR (<1) → only the dense core blooms
		_red_x_fx.glow              = 0.25          # small HDR boost → contained bloom (not a screen-wide halo)
		_red_x_fx.loop              = false
		_red_x_fx.free_on_done      = false         # pooled: kept alive and reused
		_red_x_fx.arm_inner         = RED_X_INNER   # fire starts on the outer edge of the ship area
		_red_x_fx.arm_length        = reach
		add_child(_red_x_fx)
		_red_x_fx.global_position = center
	else:
		_red_x_fx.arm_length = reach
		_red_x_fx.retrigger(center)

## Called by the Chemtrail pickup — turn on the toxic breadcrumb trail.
func activate_chemtrail() -> void:
	_chemtrail_active = true

## Per-frame: drop a puff 300px behind the ship (no-stack via spacing), then age + expire the pool.
## Stage 1: emit + lifetime only (debug circles in _draw). DoT = Stage 2, recolored fire visual = Stage 3.
func _tick_chemtrail(delta: float) -> void:
	# Emit: the ship continuously shoots puffs out the back at a steady cadence. Each puff spawns just BEHIND
	# the ship and travels outward (opposite facing) at CHEMTRAIL_SHOOT_SPEED, vanishing after its lifetime.
	var back := -_forward()
	_chemtrail_emit_acc += delta
	while _chemtrail_emit_acc >= CHEMTRAIL_EMIT_INTERVAL:
		_chemtrail_emit_acc -= CHEMTRAIL_EMIT_INTERVAL
		# No cap for now (the lifetime bounds the pool on its own).
		_chemtrail_puffs.append({
			"pos": _player.global_position + back * CHEMTRAIL_SPAWN_OFFSET,
			"vel": back * CHEMTRAIL_SHOOT_SPEED,   # captured at spawn → keeps its world-space heading
			"age": 0.0, "max_age": CHEMTRAIL_PUFF_LIFETIME,
			"radius": CHEMTRAIL_PUFF_RADIUS + _mech_radius(),
		})
	_process_chemtrail_puffs(delta, "chemtrail")

## Shared: move + age + expire the puff pool, run the DoT tick (scaled by `kind`'s level), drive the toxic-fire
## visual. Used by the Chemtrail weapon (ship-emitted puffs) and Toxic Ballistic (missile-emitted puffs).
func _process_chemtrail_puffs(delta: float, kind: String) -> void:
	var i := _chemtrail_puffs.size() - 1
	while i >= 0:
		var puff: Dictionary = _chemtrail_puffs[i]
		puff["pos"] = (puff["pos"] as Vector2) + (puff["vel"] as Vector2) * delta
		puff["age"] = float(puff["age"]) + delta
		if float(puff["age"]) >= float(puff["max_age"]):
			_chemtrail_puffs.remove_at(i)
		i -= 1
	# DoT: one weapon-level tick → each enemy inside ANY puff takes damage once (no double-dip on overlap).
	_chemtrail_tick_acc += delta
	while _chemtrail_tick_acc >= CHEMTRAIL_TICK_INTERVAL:
		_chemtrail_tick_acc -= CHEMTRAIL_TICK_INTERVAL
		_chemtrail_dot_tick(kind)
	# Visual: feed all live puff centres to the single recolored toxic-fire emitter.
	_update_chemtrail_fx()

## One DoT tick: every enemy inside ANY puff takes CHEMTRAIL_TICK_DAMAGE once (single coverage check → no
## stacking on overlap). Scales via _roll_damage (damage-mult + crit) like the other System-2 weapons.
func _chemtrail_dot_tick(kind := "chemtrail") -> void:
	if _chemtrail_puffs.is_empty():
		return
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		if _chemtrail_covers(ep) and en.has_method("take_damage"):
			var r := _roll_damage(CHEMTRAIL_TICK_DAMAGE, kind)
			en.take_damage(float(r["dmg"]), 0.0)
			if bool(r["is_crit"]):
				_spawn_crit_number(ep, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		if _chemtrail_covers((ruin as Node2D).global_position) and ruin.has_method("take_damage"):
			ruin.take_damage(CHEMTRAIL_TICK_DAMAGE * _dmg_mult * _lvl_mult(kind))

## True if world point `p` is inside ANY live puff (used for single-damage-per-tick coverage).
func _chemtrail_covers(p: Vector2) -> bool:
	for puff: Dictionary in _chemtrail_puffs:
		if p.distance_to(puff["pos"]) <= float(puff["radius"]):
			return true
	return false

## Drive the single toxic-fire emitter: lazily create it (recolored, dim, sparse) and feed the live puff
## centres as its emission points each frame. Expired puffs drop out → their particles die → the tail fades.
func _update_chemtrail_fx() -> void:
	if _chemtrail_fx == null or not is_instance_valid(_chemtrail_fx):
		_chemtrail_fx = DynamicFire.new()
		_chemtrail_fx.free_form         = true
		_chemtrail_fx.z_index           = 6
		_chemtrail_fx.color_start       = CHEMTRAIL_COL_HOT
		_chemtrail_fx.color_mid         = CHEMTRAIL_COL_MID
		_chemtrail_fx.color_end         = CHEMTRAIL_COL_END
		_chemtrail_fx.intensity         = CHEMTRAIL_INTENSITY
		_chemtrail_fx.particle_amount   = CHEMTRAIL_PARTICLES
		_chemtrail_fx.particle_size_min = 72.0
		_chemtrail_fx.particle_size_max = 160.0
		_chemtrail_fx.velocity_min      = 16.0
		_chemtrail_fx.velocity_max      = 50.0
		_chemtrail_fx.particle_lifetime = 0.8
		add_child(_chemtrail_fx)
	# The emitter must sit ON the player (on-screen) or GPUParticles2D culls the whole system. Feed puff
	# positions as OFFSETS from the player; local_coords=false → particles still spawn at the world puff
	# positions and linger there as the player moves. (Same pattern as the Red X fire node.)
	var center := _player.global_position
	_chemtrail_fx.global_position = center
	var centers: Array = []
	for puff: Dictionary in _chemtrail_puffs:
		centers.append((puff["pos"] as Vector2) - center)
	_chemtrail_fx.set_points(centers)

## System 2 has no _mech() — radius cards live in arena_loadout. Returns 0 here (hook for future parity).
func _mech_radius() -> float:
	return 0.0

## Called by the Orbital pickup — adds the orbiting balls to the active loadout (accumulates).
func activate_orbital() -> void:
	_orbital_active = true
	_orbital_cd.resize(ORBITAL_BALLS)
	for k in ORBITAL_BALLS:
		_orbital_cd[k] = 0.0

# ── Singularities fusion (orbital + void): the orbiting balls keep the orbital movement + damage, but are
# re-skinned as void vortices (same swirling-rift shader as the Void weapon). ──
func activate_singularity() -> void:
	_singularity_active = true
	_singularity_tick = 0.0
	_orbital_cd.resize(ORBITAL_BALLS)   # the 3 orbital balls need their per-ball hit cooldowns
	for k in ORBITAL_BALLS:
		_orbital_cd[k] = 0.0
	_ensure_singularity_nodes()

## Build one rift node per orbiting ball — uses the SAME gravitational-lens distortion shader the live Rift
## Maker (Void) weapon renders (RIFT_DISTORTION_SHADER, same params as _void_distort), so the orbs look like
## the actual weapon's rift, not the disabled purple vortex.
func _ensure_singularity_nodes() -> void:
	if not _singularity_nodes.is_empty():
		return
	for k in ORBITAL_BALLS:
		var dsh := Shader.new()
		dsh.code = RIFT_DISTORTION_SHADER
		var dmat := ShaderMaterial.new()
		dmat.shader = dsh
		dmat.set_shader_parameter("twist_strength", RIFT_DISTORT_TWIST)
		dmat.set_shader_parameter("twist_falloff", RIFT_DISTORT_FALLOFF)
		dmat.set_shader_parameter("suck_in", RIFT_DISTORT_SUCK)
		dmat.set_shader_parameter("rotation_speed", RIFT_DISTORT_ROT_SPEED)
		dmat.set_shader_parameter("edge_softness", RIFT_DISTORT_EDGE)
		dmat.set_shader_parameter("brightness", RIFT_DISTORT_BRIGHTNESS)
		var cr := ColorRect.new()
		cr.material = dmat
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.z_index = 4
		cr.visible = false
		add_child(cr)
		_singularity_nodes.append(cr)

## The 3 normal orbitals (around the ship) PLUS 3 void rifts interleaved between them on the same ring
## (O-V-O-V-O-V), all spinning together. The orbitals keep contact damage; each void deals its own void DoT.
func _tick_singularity(delta: float) -> void:
	_run_orbital(delta, "singularities")   # the 3 orbital balls: spin (advances _orbital_angle) + contact damage
	_ensure_singularity_nodes()
	if _player == null or not is_instance_valid(_player):
		return
	var ship := _player.global_position
	# The 3 voids sit 60° BETWEEN the orbital balls (orbitals at _orbital_angle+0/120/240) and share the spin.
	var void_pos: Array = []
	for k in ORBITAL_BALLS:
		var ang := deg_to_rad(_orbital_angle + 60.0 + 120.0 * float(k))
		void_pos.append(ship + Vector2(cos(ang), sin(ang)) * ORBITAL_RADIUS)
	_singularity_pos = void_pos
	# One shared DoT clock; each void applies VOID damage in its own radius SEPARATELY (overlap double-dips).
	_singularity_tick += delta
	var do_dmg := false
	if _singularity_tick >= VOID_TICK:
		_singularity_tick -= VOID_TICK
		do_dmg = true
	var per_tick := VOID_DAMAGE_MAX * VOID_TICK * _dmg_mult * _lvl_mult("singularities")
	var radius := VOID_RADIUS_MAX
	var diam := VOID_RADIUS_MAX * 2.0 * VOID_LENS_SCALE   # same on-screen lens size as the full Rift Maker rift
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var ruins := get_tree().get_nodes_in_group("arena_ruin")
	for k in ORBITAL_BALLS:
		var p: Vector2 = void_pos[k]
		if k < _singularity_nodes.size():
			var cr: ColorRect = _singularity_nodes[k]
			cr.visible = true
			cr.position = p - Vector2(diam * 0.5, diam * 0.5)
			cr.size = Vector2(diam, diam)
			var dmat := cr.material as ShaderMaterial
			if dmat != null:
				dmat.set_shader_parameter("growth", 1.0)
				dmat.set_shader_parameter("rect_size", Vector2(diam, diam))
		if do_dmg:
			for en in enemies:
				if not is_instance_valid(en):
					continue
				if p.distance_to((en as Node2D).global_position) <= radius + VOID_HIT_PAD:
					if en.has_method("take_damage"):
						en.take_damage(per_tick, 0.0)
			for ruin in ruins:
				if not is_instance_valid(ruin):
					continue
				var rr: float = radius + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
				if p.distance_to((ruin as Node2D).global_position) <= rr:
					if ruin.has_method("take_damage"):
						ruin.take_damage(per_tick)

## Called by the Void pickup — adds the auto-casting void gun to the loadout (accumulates).
func activate_void() -> void:
	_void_active = true
	_void_cd = 0.0   # cast on the next available enemy
	if _void_node == null:   # build the swirling-vortex visual once (was missing → the rift fired invisibly)
		var sh := Shader.new()
		sh.code = RIFT_VORTEX_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("portal_texture", _make_void_noise())
		# Gravitational-lens disc (screen-warp) — created FIRST and z 4 so it draws UNDER the bright vortex (z 5).
		var dsh := Shader.new()
		dsh.code = RIFT_DISTORTION_SHADER
		var dmat := ShaderMaterial.new()
		dmat.shader = dsh
		dmat.set_shader_parameter("twist_strength", RIFT_DISTORT_TWIST)
		dmat.set_shader_parameter("twist_falloff", RIFT_DISTORT_FALLOFF)
		dmat.set_shader_parameter("suck_in", RIFT_DISTORT_SUCK)
		dmat.set_shader_parameter("rotation_speed", RIFT_DISTORT_ROT_SPEED)
		dmat.set_shader_parameter("edge_softness", RIFT_DISTORT_EDGE)
		dmat.set_shader_parameter("brightness", RIFT_DISTORT_BRIGHTNESS)
		_void_distort = ColorRect.new()
		_void_distort.material = dmat
		_void_distort.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_void_distort.z_index = 4
		_void_distort.visible = false
		add_child(_void_distort)
		_void_node = ColorRect.new()
		_void_node.material = mat
		_void_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_void_node.z_index = 5   # above the background/enemies + lens, below the ship (100)
		_void_node.visible = false
		add_child(_void_node)

## Seamless noise the rift shader twists into spiral arms (it samples `portal_texture`).
func _make_void_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	return tex

# ── Void gun (Rift Maker): every VOID_COOLDOWN s, tear a growing void on the nearest enemy for VOID_DURATION s ──
func _tick_void(delta: float) -> void:
	if VOID_FOLLOW_MOUSE:
		# TEST MODE: one constant rift glued to the mouse cursor — full size, no cooldown/duration.
		_void_on = true
		_void_pos = get_global_mouse_position()
		var mradius := VOID_RADIUS_MAX
		var mpull := VOID_PULL_SPEED * delta
		for men in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(men) or men.is_in_group("boss"):
				continue
			var mep: Vector2 = (men as Node2D).global_position
			var mdd := _void_pos.distance_to(mep)
			if mdd > 1.0 and mdd <= VOID_PULL_RADIUS:
				(men as Node2D).global_position = mep.move_toward(_void_pos, mpull)
		_void_tick += delta
		while _void_tick >= VOID_TICK:
			_void_tick -= VOID_TICK
			var mdmg := VOID_DAMAGE_MAX * VOID_TICK * _dmg_mult * _lvl_mult("void")
			for men2 in get_tree().get_nodes_in_group("arena_enemy"):
				if not is_instance_valid(men2):
					continue
				if _void_pos.distance_to((men2 as Node2D).global_position) <= mradius + VOID_HIT_PAD:
					if men2.has_method("take_damage"):
						men2.take_damage(mdmg, 0.0)
		if _void_node != null:
			var mdiam := mradius * 2.0 * VOID_VISUAL_SCALE
			_void_node.position = _void_pos - Vector2(mdiam * 0.5, mdiam * 0.5)
			_void_node.size = Vector2(mdiam, mdiam)
			var mmat := _void_node.material as ShaderMaterial
			if mmat != null:
				mmat.set_shader_parameter("growth", 1.0)
			_void_node.visible = VOID_PURPLE_MASK   # purple overlay off for now (lens distortion still shows)
		if _void_distort != null:
			var mld := mradius * 2.0 * VOID_LENS_SCALE
			_void_distort.position = _void_pos - Vector2(mld * 0.5, mld * 0.5)
			_void_distort.size = Vector2(mld, mld)
			var dmat2 := _void_distort.material as ShaderMaterial
			if dmat2 != null:
				dmat2.set_shader_parameter("growth", 1.0)
				dmat2.set_shader_parameter("rect_size", Vector2(mld, mld))
			_void_distort.visible = true
		return
	if not _void_on:
		_void_cd -= delta
		if _void_cd <= 0.0:
			var e := _nearest_enemy(_player.global_position, INF, [])
			if e != null:
				_void_pos = (e as Node2D).global_position
				_void_age = 0.0
				_void_tick = 0.0
				_void_on = true
				_void_cd = VOID_COOLDOWN
				if _void_node != null:
					_void_node.visible = VOID_PURPLE_MASK   # purple overlay off for now
		return
	_void_age += delta
	if _void_age >= VOID_DURATION:
		_void_on = false
		if _void_node != null:
			_void_node.visible = false
		return
	var f := clampf(_void_age / VOID_RAMP, 0.0, 1.0)
	var radius := lerpf(VOID_RADIUS_MIN, VOID_RADIUS_MAX, f)
	# Gravity pull: every frame, suck nearby NON-boss enemies toward the rift centre (stronger as it grows).
	var pull := VOID_PULL_SPEED * (0.35 + 0.65 * f) * delta
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or en.is_in_group("boss"):
			continue
		var ep: Vector2 = (en as Node2D).global_position
		var dd := _void_pos.distance_to(ep)
		if dd > 1.0 and dd <= VOID_PULL_RADIUS:
			(en as Node2D).global_position = ep.move_toward(_void_pos, pull)
	# Damage everything inside the radius, in ticks (DoT ramps with growth).
	_void_tick += delta
	while _void_tick >= VOID_TICK:
		_void_tick -= VOID_TICK
		var per_tick := lerpf(VOID_DAMAGE_MIN, VOID_DAMAGE_MAX, f) * VOID_TICK * _dmg_mult * _lvl_mult("void")
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			if _void_pos.distance_to((en as Node2D).global_position) <= radius + VOID_HIT_PAD:
				if en.has_method("take_damage"):
					en.take_damage(per_tick, 0.0)
		for ruin in get_tree().get_nodes_in_group("arena_ruin"):
			if not is_instance_valid(ruin):
				continue
			var rr: float = radius + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
			if _void_pos.distance_to((ruin as Node2D).global_position) <= rr:
				if ruin.has_method("take_damage"):
					ruin.take_damage(per_tick)
	# Size/position the vortex visual to the void.
	if _void_node != null:
		var diam := radius * 2.0 * VOID_VISUAL_SCALE
		_void_node.position = _void_pos - Vector2(diam * 0.5, diam * 0.5)
		_void_node.size = Vector2(diam, diam)
		var mat := _void_node.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("growth", f)

# ── Orbitals (metal balls circling the ship; contact damage with a per-ball cooldown) ──────────────────
## World positions of the orbiting balls this frame (evenly spaced on the orbit around the ship).
func _orbital_positions() -> Array:
	var out: Array = []
	var ship := _player.global_position
	var step := 360.0 / float(ORBITAL_BALLS)
	for k in ORBITAL_BALLS:
		var ang := deg_to_rad(_orbital_angle + step * float(k))
		out.append(ship + Vector2(cos(ang), sin(ang)) * ORBITAL_RADIUS)
	return out

func _tick_orbital(delta: float) -> void:
	_run_orbital(delta, "orbital")

## Shared orbital movement + per-ball contact damage. `kind` selects the damage scaling (the Singularities
## fusion reuses this with kind "singularities" so the orbit's contact damage scales with the fused level).
func _run_orbital(delta: float, kind: String) -> void:
	_orbital_t += delta
	_orbital_angle = fmod(_orbital_angle + ORBITAL_SPIN * delta, 360.0)
	if _orbital_cd.size() < ORBITAL_BALLS:
		_orbital_cd.resize(ORBITAL_BALLS)
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var ruins   := get_tree().get_nodes_in_group("arena_ruin")
	var balls := _orbital_positions()
	var hit_r := ORBITAL_DRAW * 0.5 * ORBITAL_HIT_FRAC if _orbital_tex != null else ORBITAL_BALL_RADIUS + ORBITAL_HIT_PAD
	for k in ORBITAL_BALLS:
		_orbital_cd[k] = maxf(0.0, float(_orbital_cd[k]) - delta)
		if float(_orbital_cd[k]) > 0.0:
			continue
		var bpos: Vector2 = balls[k]
		var struck := false
		for en in enemies:
			if not is_instance_valid(en):
				continue
			if bpos.distance_to((en as Node2D).global_position) <= hit_r:
				if en.has_method("take_damage"):
					var _orb_r := _roll_damage(_orbital_damage, kind)
					en.take_damage(float(_orb_r["dmg"]), ORBITAL_STAGGER)
					if bool(_orb_r["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(_orb_r["dmg"]))
				struck = true
				break
		if not struck:
			for ruin in ruins:
				if not is_instance_valid(ruin):
					continue
				var rr: float = (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0) + ORBITAL_BALL_RADIUS
				if bpos.distance_to((ruin as Node2D).global_position) <= rr:
					if ruin.has_method("take_damage"):
						ruin.take_damage(_orbital_damage * _dmg_mult * _lvl_mult(kind))
					struck = true
					break
		if struck:
			_orbital_cd[k] = ORBITAL_HIT_COOLDOWN

## Per ball, drawn BACK→FRONT: tangent streak glow → afterimage ghosts → crisp body. The orbit is
## deterministic, so past ghost positions are just θ stepped back along the arc (no history buffer).
func _draw_orbital() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var ship := _player.global_position
	var step := 360.0 / float(ORBITAL_BALLS)
	var blur := ORBITAL_BLUR_AMT
	for k in ORBITAL_BALLS:
		var th := deg_to_rad(_orbital_angle + step * float(k))
		var c := ship + Vector2(cos(th), sin(th)) * ORBITAL_RADIUS
		if blur > 0.001:
			if streak_enabled:
				_draw_orbital_streak(ship, th, blur)
			_draw_orbital_ghosts(ship, th, blur)
		_draw_orbital_ball(c)

## Afterimage ghosts: copies of the orb at θ stepped BACK along the orbit, fading + shrinking + tinted.
func _draw_orbital_ghosts(ship: Vector2, th: float, blur: float) -> void:
	if _orbital_tex == null:
		return
	var n := maxi(1, int(round(float(trail_ghosts) * blur)))
	for j in range(1, n + 1):
		var gth := th - trail_arc_step * float(j)   # back along the arc (spin is +θ)
		var gc := ship + Vector2(cos(gth), sin(gth)) * ORBITAL_RADIUS
		var d := ORBITAL_DRAW * pow(trail_scale_falloff, float(j))
		var a := pow(trail_alpha_falloff, float(j)) * blur
		draw_texture_rect(_orbital_tex, Rect2(gc.x - d * 0.5, gc.y - d * 0.5, d, d), false,
			Color(trail_tint.r, trail_tint.g, trail_tint.b, a))

## Soft tangent streak glow: stacked low-alpha circles sampled along the arc behind the orbital → a smooth
## speed smear, brightest at the body and fading backward (soft mix-blend glow, no hard shape).
func _draw_orbital_streak(ship: Vector2, th: float, blur: float) -> void:
	var length := lerpf(streak_len_min, streak_len_max, blur)
	var back_ang := length / maxf(1.0, ORBITAL_RADIUS)   # arc (rad) the streak spans
	var m := 8
	for s in range(1, m + 1):
		var f := float(s) / float(m)                     # 0 at body → 1 at tail
		var sth := th - back_ang * f
		var sc := ship + Vector2(cos(sth), sin(sth)) * ORBITAL_RADIUS
		var a := streak_alpha * blur * (1.0 - f)
		var rad := streak_width * 0.5 * (1.0 - f * 0.4)
		draw_circle(sc, rad, Color(trail_tint.r, trail_tint.g, trail_tint.b, a))

func _draw_orbital_ball(c: Vector2) -> void:
	# Sprite path: draw the keyed orb art (crisp, NO self-rotation — orbit-only). It carries its own energy.
	if _orbital_tex != null:
		var d := ORBITAL_DRAW
		draw_texture_rect(_orbital_tex, Rect2(c.x - d * 0.5, c.y - d * 0.5, d, d), false)
		return
	# Procedural fallback (no sprite): soft glow + crackling arcs + a 3-layer metal sphere.
	var r := ORBITAL_BALL_RADIUS
	# Soft electric glow.
	draw_circle(c, r * 2.4, Color(ORBITAL_COL.r, ORBITAL_COL.g, ORBITAL_COL.b, 0.12))
	draw_circle(c, r * 1.5, Color(ORBITAL_COL.r, ORBITAL_COL.g, ORBITAL_COL.b, 0.20))
	# Crackling lightning spokes (re-jagged ~18×/s).
	var jag := floorf(_orbital_t * 18.0)
	var arcs := 4
	for a in arcs:
		var base_ang := _orbital_t * 5.0 + TAU * float(a) / float(arcs)
		var dir := Vector2(cos(base_ang), sin(base_ang))
		var perp := Vector2(-dir.y, dir.x)
		var prev := c + dir * r
		for s in range(1, 4):
			var tt := float(s) / 3.0
			var jit := _orb_pseudo(base_ang * 10.0 + float(s), jag) * 6.0
			var pt := c + dir * (r + r * 2.0 * tt) + perp * jit
			draw_line(prev, pt, Color(ORBITAL_COL.r, ORBITAL_COL.g, ORBITAL_COL.b, 0.7 * (1.0 - tt * 0.5)), 1.5)
			prev = pt
	# Metal sphere: dark rim → grey body → bright specular highlight.
	draw_circle(c, r + 1.0, Color(0.04, 0.05, 0.08))
	draw_circle(c, r, Color(0.55, 0.58, 0.66))
	draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.36, Color(0.86, 0.9, 0.96))

## Deterministic pseudo-random in [-0.5, 0.5] from two seeds (for the lightning jitter).
func _orb_pseudo(a: float, b: float) -> float:
	var v := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (v - floorf(v)) - 0.5

## Called by Gatling / Gauss pickups — turn the (otherwise default-state) weapon on so it accumulates too.
func activate_gatling() -> void:
	_gat_active = true

func activate_gauss() -> void:
	_gauss_active = true

# ── Weapon acquisition (chest + pickups → the 5-slot HUD) ────────────────────────────────
## Acquire a weapon `kind`: add it to the ordered slot list (if new and below the cap) and turn it on.
## Returns true when a NEW slot was filled (false if a duplicate or the cap is already reached).
func acquire_weapon(kind: String) -> bool:
	var newly := false
	if not (kind in _acquired):
		if _acquired.size() >= MAX_WEAPONS:
			return false   # all slots full — ignore (unique-only; level-up system comes later)
		_acquired.append(kind)
		_levels[kind] = 1
		newly = true
	_activate_kind(kind)   # idempotent: also re-arms a kind already owned
	return newly

## Ordered copy of the acquired weapon kinds — read by the slot HUD.
func acquired_weapons() -> Array:
	return _acquired.duplicate()

# ── Weapon levels (level-up upgrades) ────────────────────────────────────────────
## Per-kind level cap — fused weapons get FUSION_BONUS_LEVELS extra levels above MAX_WEAPON_LEVEL.
func _level_cap(kind: String) -> int:
	return (MAX_WEAPON_LEVEL + FUSION_BONUS_LEVELS) if is_fusion_kind(kind) else MAX_WEAPON_LEVEL

## Raise an owned weapon's level by one (capped). No-op for un-owned weapons.
func level_up_weapon(kind: String) -> void:
	if kind in _acquired:
		_levels[kind] = mini(_level_cap(kind), int(_levels.get(kind, 1)) + 1)

func weapon_level(kind: String) -> int:
	return int(_levels.get(kind, 1)) if kind in _acquired else 0

func weapon_can_upgrade(kind: String) -> bool:
	return kind in _acquired and int(_levels.get(kind, 1)) < _level_cap(kind)

# ── Skill-point progression (level N→N+1 costs N+1 points; the first point on an unowned kind acquires it) ──
## Points already invested toward this kind's NEXT level (0-owned items start collecting toward level 2).
func weapon_points(kind: String) -> int:
	return int(_wpoints.get(kind, 0))

## Points needed to reach the next level: current_level + 1 (0→1 = 1, 1→2 = 2, … 5→6 = 6). 0 when maxed.
func weapon_next_cost(kind: String) -> int:
	var lvl := weapon_level(kind)   # 0 if not yet owned
	if lvl >= _level_cap(kind):
		return 0
	return lvl + 1

## Invest ONE skill point in `kind`. Acquires it (level 0→1) if unowned, else accumulates toward the next
## level and auto-levels when the threshold is reached. Returns true if a level was gained this point.
func spend_weapon_point(kind: String) -> bool:
	var lvl := weapon_level(kind)
	if lvl >= _level_cap(kind):
		return false   # already maxed
	var pts := int(_wpoints.get(kind, 0)) + 1
	var cost := lvl + 1
	if pts >= cost:
		_wpoints[kind] = 0
		if lvl <= 0:
			acquire_weapon(kind)     # 0→1 (acquisition is the first invested point)
		else:
			level_up_weapon(kind)    # L→L+1
		return true
	_wpoints[kind] = pts
	return false

func weapons_full() -> bool:
	return _acquired.size() >= MAX_WEAPONS

## Per-weapon damage multiplier from its level — COMPOUNDING: (1+WEAPON_DMG_PER_LEVEL)^(level-1).
## L1 ×1.0, L2 ×1.30, L3 ×1.69, L4 ×2.20, L5 ×2.86.
func _lvl_mult(kind: String) -> float:
	if kind == "" or not (kind in _acquired):
		return 1.0
	return pow(1.0 + WEAPON_DMG_PER_LEVEL, float(int(_levels.get(kind, 1)) - 1))

## Route a kind to its existing activate_<kind>() entry point.
func _activate_kind(kind: String) -> void:
	match kind:
		"gatling": activate_gatling()
		"lasgun":  activate_lasgun()
		"arc":     activate_arc()
		"gauss":   activate_gauss()
		"orbital": activate_orbital()
		"void":    activate_void()
		"red_x":   activate_red_x()
		"chemtrail": activate_chemtrail()
		"nuke":    activate_nuke()
		"sonic":   activate_sonic()
		"zsword":  activate_zsword()
		"ionize":  activate_ionize()
		"boomerang": activate_boomerang()
		"parasite":  activate_parasite()
		"moroboshi": activate_moroboshi()
		"swarm":     activate_swarm()
		"snake":     activate_snake()
		"homing":    activate_homing()
		"carnage":      activate_carnage()
		"vampire_host": activate_vampire()
		"overcharger":  activate_overcharger()
		"predator":     activate_predator()
		"toxic_ballistic": activate_toxic()
		"singularities": activate_singularity()

# ── Weapon FUSION API ─────────────────────────────────────────────────────────────
func is_fusion_kind(kind: String) -> bool:
	return FUSION_DEFS.has(kind)

## Recipe ids ready to fuse: both components owned at MAX_WEAPON_LEVEL and the fusion not already owned.
func available_fusions() -> Array:
	var out: Array = []
	for fid: String in FUSION_DEFS.keys():
		if fid in _acquired:
			continue
		var rec: Dictionary = FUSION_DEFS[fid]
		var a := String(rec["a"])
		var b := String(rec["b"])
		if (a in _acquired) and (b in _acquired) \
			and int(_levels.get(a, 1)) >= MAX_WEAPON_LEVEL \
			and int(_levels.get(b, 1)) >= MAX_WEAPON_LEVEL:
			out.append(fid)
	return out

## Perform a fusion: remove both components, grant the fused kind (carrying the maxed state).
func fuse(fusion_id: String) -> bool:
	if not FUSION_DEFS.has(fusion_id):
		return false
	var rec: Dictionary = FUSION_DEFS[fusion_id]
	for comp: String in [String(rec["a"]), String(rec["b"])]:
		_acquired.erase(comp)
		_levels.erase(comp)
		_deactivate_kind(comp)
	if not (fusion_id in _acquired):
		_acquired.append(fusion_id)
	_levels[fusion_id] = MAX_WEAPON_LEVEL   # carry the maxed state; can climb FUSION_BONUS_LEVELS further
	_activate_kind(fusion_id)
	return true

## Turn a weapon OFF and clear its runtime state (used when its slot is consumed by a fusion).
func _deactivate_kind(kind: String) -> void:
	match kind:
		"gatling": _gat_active = false
		"lasgun":  _lasgun_active = false
		"arc":     _arc_active = false
		"gauss":   _gauss_active = false
		"orbital": _orbital_active = false
		"void":    _void_active = false; _void_on = false
		"red_x":   _red_x_active = false; _red_x_cd = 0.0
		"chemtrail": _chemtrail_active = false
		"nuke":    _nuke_active = false
		"sonic":   _sonic_active = false; _sonic_left = 0; _sonic_rings.clear()
		"zsword":  _zsword_active = false
		"ionize":  _ionize_active = false
		"boomerang": _boom_active = false
		"parasite":  _para_active = false
		"moroboshi": _moro_active = false
		"swarm":     _swarm_active = false; _swarm_init = false; _swarm_units.clear()
		"snake":     _snake_active = false
		"homing":    _homing_active = false

## Cooldown/charge readiness for the slot HUD: 1.0 = ready (no mask), 0..1 = recovering (mask covers 1-frac).
func weapon_cooldown_frac(kind: String) -> float:
	var rate := maxf(0.01, _rate_mult)
	match kind:
		"gatling", "orbital", "chemtrail", "ionize", "moroboshi", "swarm", "snake", "boomerang", "carnage", "vampire_host", "predator", "homing", "toxic_ballistic", "singularities":
			return 1.0   # continuous stream / always-on passive or familiar → never masked
		"gauss":
			return clampf(_gauss_charge / maxf(0.01, GAUSS_CHARGE_TIME / rate), 0.0, 1.0)
		"arc", "overcharger":
			if _arc_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _arc_cd / maxf(0.01, ARC_COOLDOWN / rate), 0.0, 1.0)
		"red_x":
			if _red_x_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _red_x_cd / maxf(0.01, RED_X_INTERVAL / rate), 0.0, 1.0)
		"void":
			if _void_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _void_cd / maxf(0.01, VOID_COOLDOWN / rate), 0.0, 1.0)
		"lasgun":
			var phase := fmod(_las_t, LASGUN_CYCLE)
			if phase < LASGUN_DURATION:
				return 1.0   # firing window → ready
			return clampf((phase - LASGUN_DURATION) / maxf(0.01, LASGUN_CYCLE - LASGUN_DURATION), 0.0, 1.0)
		"nuke":
			if _nuke_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _nuke_cd / maxf(0.01, NUKE_COOLDOWN / rate), 0.0, 1.0)
		"sonic":
			if _sonic_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _sonic_cd / maxf(0.01, SONIC_COOLDOWN / rate), 0.0, 1.0)
		"zsword":
			if _zsword_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _zsword_cd / maxf(0.01, ZSWORD_COOLDOWN / rate), 0.0, 1.0)
		"parasite":
			if _para_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _para_cd / maxf(0.01, PARA_COOLDOWN / rate), 0.0, 1.0)
	return 1.0

## True while `kind` is actively engaging this frame (acquired/active + an enemy on screen). The slot HUD
## uses this to give the firing weapon a slight in-place pulse. Lasgun only counts during its burst window.
func weapon_is_firing(kind: String) -> bool:
	if not _enemy_visible:
		return false
	match kind:
		"gatling": return _gat_active
		"gauss":   return _gauss_active
		"arc":     return _arc_active
		"red_x":   return _red_x_active
		"chemtrail": return _chemtrail_active
		"void":    return _void_active
		"orbital": return _orbital_active
		"lasgun":  return _lasgun_active and fmod(_las_t, LASGUN_CYCLE) < LASGUN_DURATION
		"nuke":    return _nuke_active
		"sonic":   return _sonic_active
		"zsword":  return _zsword_active and _zsword_sweeping
		"ionize":  return _ionize_active
		"boomerang": return _boom_active
		"parasite":  return _para_active
		"moroboshi": return _moro_active
		"swarm":     return _swarm_active
		"snake":     return _snake_active
	return false

## Generic pickup drop used by the F12 weapon palette: spawn a `kind` pickup at a world position.
func spawn_weapon_pickup(kind: String, world_pos: Vector2) -> void:
	var p := PickupScript.new()
	p.add_to_group("debug_weapon_pickup")
	get_parent().add_child(p)
	p.setup(world_pos, kind)

## Debug (legacy F12): drop a Lasgun pickup at a world position on the gameplay plane.
func spawn_lasgun_pickup_near(world_pos: Vector2) -> void:
	spawn_weapon_pickup("lasgun", world_pos)

func _tick_bullets(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var ruins   := get_tree().get_nodes_in_group("arena_ruin")
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var p: Vector2 = b["pos"]
		var dead := float(b["life"]) >= GAT_LIFETIME or p.distance_to(b["start"]) >= GAT_MAX_DIST
		if not dead:
			var bk: String = b.get("kind", "gatling")   # Carnage/Red O fusion bullets tag their kind for level scaling
			var is_gat := bk == "gatling"
			var hits: Array = b.get("hits", [])
			for en in enemies:
				if not is_instance_valid(en):
					continue
				if is_gat and en in hits:
					continue   # pierce/bounce: never hit the same enemy twice
				var _en_r = en.get("hit_radius")
				var _hit_r: float = float(_en_r) if _en_r != null else GAT_HIT_RADIUS
				if p.distance_to((en as Node2D).global_position) <= _hit_r:
					if en.has_method("take_damage"):
						if is_gat:
							_gat_hit_enemy(b, en, p)   # flat dmg + kinetic + focus + healing
						else:
							var _gat_r := _roll_damage(GAT_DAMAGE, bk)
							en.take_damage(float(_gat_r["dmg"]), GAT_STAGGER, 1.0)   # Gatling keeps pushback
							if bool(_gat_r["is_crit"]):
								_spawn_crit_number(p, float(_gat_r["dmg"]))
					if _bolt_hit_player != null:
						_bolt_hit_player.stream = SFX_BOLT_HIT[randi() % SFX_BOLT_HIT.size()]
						_bolt_hit_player.play()
					if is_gat:
						hits.append(en)
						b["hits"] = hits
						if not _gat_bounce_or_pierce(b):   # bounce → redirect, pierce → continue, else die
							dead = true
					else:
						dead = true
					break
			if not dead:
				for ruin in ruins:
					if not is_instance_valid(ruin): continue
					var ruin_r: float = ruin.get("hit_radius") if ruin.get("hit_radius") != null else GAT_HIT_RADIUS
					if p.distance_to((ruin as Node2D).global_position) <= ruin_r:
						if ruin.has_method("take_damage"):
							if is_gat:
								ruin.take_damage(_gat_bullet_base() * _dmg_mult)
							else:
								ruin.take_damage(GAT_DAMAGE * _dmg_mult * _lvl_mult(bk))
						dead = true
						if _bolt_hit_player != null:
							_bolt_hit_player.stream = SFX_BOLT_HIT[randi() % SFX_BOLT_HIT.size()]
							_bolt_hit_player.play()
						break
		if dead:
			_bullets.remove_at(i)
		i -= 1

## Apply a Gatling bullet's hit to an enemy: gatling base (flat dmg + Lv4 + kinetic) × Focus-Fire ramp, then
## crit + global mult via _roll_damage("") — kind "" so the OLD per-level mult isn't double-counted (gatling's
## level rewards are explicit). Plus the Healing Round capstone.
func _gat_hit_enemy(b: Dictionary, en: Node, p: Vector2) -> void:
	var base := _gat_bullet_base()
	if _gat_capstone == "focus":
		if en == _gat_focus_target:
			_gat_focus_stacks = mini(_gat_focus_stacks + 1, int(GAT_FOCUS_MAX / GAT_FOCUS_STEP))
		else:
			_gat_focus_target = en
			_gat_focus_stacks = 0
		base *= 1.0 + minf(float(_gat_focus_stacks) * GAT_FOCUS_STEP, GAT_FOCUS_MAX)
	var r := _roll_damage(base, "")
	en.take_damage(float(r["dmg"]), GAT_STAGGER, 1.0)
	if bool(r["is_crit"]):
		_spawn_crit_number(p, float(r["dmg"]))
	if b.get("healing", false) and GameManager.has_method("heal"):
		GameManager.heal(GAT_HEAL_AMOUNT)   # heals the player; "heal the target" (enemy) omitted — confirm intent

## On a Gatling bullet hit: maybe BOUNCE (redirect to a perpendicular nearby foe) or PIERCE (continue straight).
## Returns true if the bullet survives, false if it should die.
func _gat_bounce_or_pierce(b: Dictionary) -> bool:
	var vel: Vector2 = b["vel"]
	if _gat_bounce_chance() > 0.0 and randf() < _gat_bounce_chance():
		var tgt := _gat_bounce_target(b["pos"], vel, b["hits"])
		if tgt != null:
			var newdir := ((tgt as Node2D).global_position - (b["pos"] as Vector2)).normalized()
			b["vel"] = newdir * GAT_SPEED
			b["start"] = b["pos"]   # refresh the travel-distance budget so it doesn't instantly despawn
			return true
	if _gat_pierce_chance() > 0.0 and randf() < _gat_pierce_chance():
		return true
	return false

## Bounce target: the not-yet-hit enemy within range whose direction is most PERPENDICULAR to the bullet's path.
func _gat_bounce_target(pos: Vector2, vel: Vector2, hits: Array) -> Node:
	var perp := vel.orthogonal().normalized() if vel.length() > 0.01 else Vector2.RIGHT
	var best: Node = null
	var best_score := -1.0
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or en in hits:
			continue
		var to: Vector2 = (en as Node2D).global_position - pos
		var d := to.length()
		if d > GAT_BOUNCE_RANGE or d < 1.0:
			continue
		var score := absf(to.normalized().dot(perp))   # 1 = perfectly perpendicular to the trajectory
		if score > best_score:
			best_score = score
			best = en
	return best

# ── Gauss ─────────────────────────────────────────────────────────────────────
func _fire_gauss() -> void:
	_gauss_fire_player.stream = SFX_GAUSS_FIRE
	_gauss_fire_player.play()
	var dir := _forward()
	var start := _muzzle()
	var orb := _make_orb()
	var budget := GAUSS_DAMAGE * _dmg_mult * _lvl_mult("gauss")   # the orb carries this much damage; size ∝ sqrt(dmg/dmg_ref)
	var o := {
		"pos": start, "vel": dir * GAUSS_SPEED, "life": 0.0, "start": start,
		"orb_node": orb, "trail": [], "spark_acc": 0.0, "dmg": budget, "dmg_ref": budget, "hit": [],
	}
	_orbs.append(o)
	_update_orb_node(o)
	_flashes.append({"pos": start, "age": 0.0, "max_age": 0.30, "radius": GAUSS_LAUNCH_FLASH})
	# Pop the release flash (the shot's muzzle flash).
	if GC_RELEASE_FLASH > 0.0:
		_flashes.append({"pos": _muzzle(), "age": 0.0, "max_age": 0.30, "radius": GC_RELEASE_FLASH})

func _tick_orbs(delta: float) -> void:
	# Advance the shared 12-frame Gauss-orb plasma loop (all live orbs show the same frame).
	if not _gauss_frames.is_empty() and GAUSS_ORB_FPS > 0.0:
		_gauss_fb_t += delta
		var gspf := 1.0 / GAUSS_ORB_FPS
		while _gauss_fb_t >= gspf:
			_gauss_fb_t -= gspf
			_gauss_fb_idx = (_gauss_fb_idx + 1) % _gauss_frames.size()
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var ruins   := get_tree().get_nodes_in_group("arena_ruin")
	var i := _orbs.size() - 1
	while i >= 0:
		var o: Dictionary = _orbs[i]
		o["pos"] = (o["pos"] as Vector2) + (o["vel"] as Vector2) * delta
		o["life"] = float(o["life"]) + delta
		_update_orb_node(o)
		_shed_sparks(o, delta)
		var p: Vector2 = o["pos"]
		var dmg := float(o["dmg"])
		# Cull when the budget is spent, the orb drifts too far from the player, or the lifetime backstop.
		var far := _player != null and is_instance_valid(_player) and p.distance_to(_player.global_position) > GAUSS_CULL_DIST
		var dead := dmg <= GAUSS_MIN_DMG or float(o["life"]) >= GAUSS_LIFETIME or far
		# Consume-on-first-hit: the orb dies the instant it touches ANY enemy or ruin and spawns a Gauss
		# explosion at the impact point. All damage now comes from the explosion DoT (_tick_explosions);
		# the orb itself no longer deals direct damage.
		if not dead:
			for en in enemies:
				if not is_instance_valid(en):
					continue
				var _en_r = en.get("hit_radius")
				var _hit_r: float = (float(_en_r) if _en_r != null else GAUSS_RADIUS) + 8.0
				if p.distance_to((en as Node2D).global_position) <= _hit_r:
					_spawn_gauss_explosion(p)
					dead = true
					break
			if not dead:
				for ruin in ruins:
					if not is_instance_valid(ruin):
						continue
					var ruin_r: float = (ruin.get("hit_radius") if ruin.get("hit_radius") != null else GAUSS_RADIUS) + 8.0
					if p.distance_to((ruin as Node2D).global_position) <= ruin_r:
						_spawn_gauss_explosion(p)
						dead = true
						break
		if dead:
			_free_orb(o)
			_orbs.remove_at(i)
		i -= 1

## The Gauss projectile is now a 12-frame plasma flipbook sprite (round orb). Normal alpha blend — the
## frames are finished art with the glow baked in (additive would blow out the white-hot core).
func _make_orb() -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if not _gauss_frames.is_empty():
		tr.texture = _gauss_frames[_gauss_fb_idx]
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr

func _update_orb_node(o: Dictionary) -> void:
	var trail: Array = o.get("trail", [])
	trail.push_front(o["pos"])
	if trail.size() > GAUSS_TRAIL_LEN:
		trail.resize(GAUSS_TRAIL_LEN)
	o["trail"] = trail
	var tr := o.get("orb_node") as TextureRect
	if tr == null or not is_instance_valid(tr):
		return
	if not _gauss_frames.is_empty():
		tr.texture = _gauss_frames[_gauss_fb_idx]   # advance the shared plasma loop
	# Round orb → square footprint, no stretch/rotation. Diameter shrinks ∝ sqrt(remaining damage) so the
	# orb's AREA is proportional to its damage budget.
	var frac := clampf(float(o["dmg"]) / maxf(1.0, float(o["dmg_ref"])), 0.0, 1.0)
	var d := GAUSS_ORB_DRAW * sqrt(frac)
	tr.size = Vector2(d, d)
	tr.position = (o["pos"] as Vector2) - Vector2(d, d) * 0.5

func _free_orb(o: Dictionary) -> void:
	var tr := o.get("orb_node") as TextureRect
	if tr != null and is_instance_valid(tr):
		tr.queue_free()
	o["orb_node"] = null

# ── Gauss explosion (AoE plasma burst spawned on orb impact) ──────────────────
## Spawn a self-expiring explosion at world `pos`. Picks one of the 3 cosmetic variants at random
## (same timing/radius for all). Each explosion owns its own draw node + timers → fully independent.
func _spawn_gauss_explosion(pos: Vector2, kind := "gauss") -> void:
	var variant := 0
	if not _expl_frames.is_empty():
		variant = randi() % _expl_frames.size()
	# Dedicated additive draw node: draw_texture_rect scales the full frame into draw_rect (no
	# EXPAND_IGNORE_SIZE clip → no square). Core pixel (173,183) lands on the impact point.
	var fx := GaussExplFX.new()
	fx.global_position = pos
	fx.draw_rect = Rect2(-GAUSS_EXPL_ANCHOR * GAUSS_EXPL_SCALE,
		Vector2(GAUSS_EXPL_FRAME_W, GAUSS_EXPL_FRAME_H) * GAUSS_EXPL_SCALE)
	add_child(fx)
	# tick_acc seeded to ≥ one full interval so the first DoT tick lands on the spawn frame (the field is active
	# "the instant it spawns"). The random extra phase DESYNCS overlapping fields so two explosions on the same
	# enemy tick at interleaved times (visibly stacking) instead of in lockstep (which read as a single hit).
	var e := {"pos": pos, "age": 0.0, "variant": variant, "node": fx, "tick_acc": GAUSS_TICK_INTERVAL + randf() * GAUSS_TICK_INTERVAL, "kind": kind}
	_explosions.append(e)
	_gauss_impact_player.play()
	_update_explosion_node(e)

## Drive every live explosion: advance its age, update the (non-uniform) animation frame, run the DoT
## field every GAUSS_TICK_INTERVAL at a FIXED radius, despawn at DURATION.
func _tick_explosions(delta: float) -> void:
	var i := _explosions.size() - 1
	while i >= 0:
		var e: Dictionary = _explosions[i]
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) >= GAUSS_EXPL_DURATION:
			var n := e.get("node") as Node2D
			if n != null and is_instance_valid(n):
				n.queue_free()
			_explosions.remove_at(i)
			i -= 1
			continue
		_update_explosion_node(e)
		# DoT: damage everything within GAUSS_EXPL_RADIUS (fixed for the whole 2s — no per-frame scaling),
		# once per enemy per tick. Each explosion has its own tick_acc → independent fields.
		e["tick_acc"] = float(e["tick_acc"]) + delta
		while float(e["tick_acc"]) >= GAUSS_TICK_INTERVAL:
			e["tick_acc"] = float(e["tick_acc"]) - GAUSS_TICK_INTERVAL
			_gauss_explosion_tick(e["pos"], String(e.get("kind", "gauss")))
		i -= 1

## One DoT tick: GAUSS_TICK_DAMAGE scaled by the damage stat (+ crit) to every enemy in radius, plus ruins.
## Same enumeration + damage call + crit-number path as the orbital/void AoE weapons.
func _gauss_explosion_tick(center: Vector2, kind := "gauss") -> void:
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= GAUSS_EXPL_RADIUS + GAUSS_EXPL_HIT_PAD:
			if en.has_method("take_damage"):
				var r := _roll_damage(GAUSS_TICK_DAMAGE, kind)
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		var ruin_r: float = GAUSS_EXPL_RADIUS + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
		if center.distance_to((ruin as Node2D).global_position) <= ruin_r:
			if ruin.has_method("take_damage"):
				ruin.take_damage(GAUSS_TICK_DAMAGE * _dmg_mult * _lvl_mult(kind))

## Feed the visual node its scheduled frame (position/scale were fixed on spawn → only the frame changes).
func _update_explosion_node(e: Dictionary) -> void:
	var fx: Node2D = e.get("node")
	if fx == null or not is_instance_valid(fx):
		return
	var variant: int = e["variant"]
	if variant < 0 or variant >= _expl_frames.size():
		return
	var frames: Array = _expl_frames[variant]
	if frames.is_empty():
		return
	var fi := clampi(_explosion_frame_index(float(e["age"])), 0, frames.size() - 1)
	fx.set_frame(frames[fi])

## Non-uniform schedule → 0-indexed frame:
##   intro frames spread over INTRO_TIME → loop PEAK_FRAMES at PEAK_FPS until (DURATION-OUTRO_TIME)
##   → outro frames spread over OUTRO_TIME.
func _explosion_frame_index(age: float) -> int:
	if age < GAUSS_EXPL_INTRO_TIME:
		var ni := GAUSS_EXPL_INTRO_FRAMES.size()
		var ki := int(age / maxf(0.001, GAUSS_EXPL_INTRO_TIME) * float(ni))
		return GAUSS_EXPL_INTRO_FRAMES[clampi(ki, 0, ni - 1)]
	var peak_end := GAUSS_EXPL_DURATION - GAUSS_EXPL_OUTRO_TIME
	if age < peak_end:
		var np := GAUSS_EXPL_PEAK_FRAMES.size()
		var kp := int((age - GAUSS_EXPL_INTRO_TIME) * GAUSS_EXPL_PEAK_FPS) % np
		return GAUSS_EXPL_PEAK_FRAMES[kp]
	var no := GAUSS_EXPL_OUTRO_FRAMES.size()
	var ko := int((age - peak_end) / maxf(0.001, GAUSS_EXPL_OUTRO_TIME) * float(no))
	return GAUSS_EXPL_OUTRO_FRAMES[clampi(ko, 0, no - 1)]

func _shed_sparks(o: Dictionary, delta: float) -> void:
	var v: Vector2 = o["vel"]
	if v.length() < 0.01:
		return
	var dir := v.normalized()
	var tail: Vector2 = (o["pos"] as Vector2) - dir * (GAUSS_RADIUS * GAUSS_ORB_QUAD * GAUSS_ORB_STRETCH * 0.85)
	o["spark_acc"] = float(o.get("spark_acc", 0.0)) + GAUSS_SPARK_RATE * delta
	while float(o["spark_acc"]) >= 1.0:
		o["spark_acc"] = float(o["spark_acc"]) - 1.0
		var jit := Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
		var sv := (-dir + jit).normalized() * GAUSS_SPARK_SPEED * randf_range(0.6, 1.25)
		_sparks.append({"pos": tail, "vel": sv, "life": 0.0, "ttl": GAUSS_SPARK_LIFE * randf_range(0.7, 1.2)})

func _update_sparks(delta: float) -> void:
	var i := _sparks.size() - 1
	while i >= 0:
		var s: Dictionary = _sparks[i]
		s["life"] = float(s["life"]) + delta
		if float(s["life"]) >= float(s["ttl"]):
			_sparks.remove_at(i)
		else:
			s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		i -= 1

func _update_flashes(delta: float) -> void:
	var i := _flashes.size() - 1
	while i >= 0:
		var f: Dictionary = _flashes[i]
		f["age"] = float(f["age"]) + delta
		if float(f["age"]) >= float(f["max_age"]):
			_flashes.remove_at(i)
		i -= 1

# ── Drawing (world-space; this node sits at the origin) ────────────────────────
# ══ Batch-1 weapons: Nuke / Sonic Wave / Z-Sword / Ionizing Field ══════════════════
## Effective AoE radius for a weapon: base + the Explosivo aux item's "radius" mech bonus.
func _aoe_radius(base: float) -> float:
	var bonus: float = GameManager.mech_bonus("radius") if GameManager.has_method("mech_bonus") else 0.0
	return base + bonus

# ── Nuke ──────────────────────────────────────────────────────────────────────────
func activate_nuke() -> void:
	_nuke_active = true
	_nuke_cd = 0.0   # detonate as soon as an enemy is visible

func _tick_nuke(delta: float, enemy_on_screen: bool) -> void:
	_nuke_cd -= delta
	if _nuke_cd <= 0.0 and enemy_on_screen:
		_nuke_cd = NUKE_COOLDOWN / _rate_mult
		_fire_nuke()
	# While the explosion plays, keep the hitbox live: anything caught in it takes damage ONCE (this also
	# catches enemies that drift into the blast mid-animation).
	if _nuke_blast_on:
		_nuke_blast_t += delta
		_damage_nuke_blast()
		if _nuke_blast_t >= _nuke_blast_dur:
			_nuke_blast_on = false

## Damage every enemy/ruin within the live blast that hasn't been hit yet this detonation (one hit each).
func _damage_nuke_blast() -> void:
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var eid := en.get_instance_id()
		if _nuke_hit.has(eid):
			continue
		var en2 := en as Node2D
		var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
		if _nuke_blast_pos.distance_to(en2.global_position) <= _nuke_blast_reach + enr:
			_nuke_hit[eid] = true
			if en.has_method("take_damage"):
				var r := _roll_damage(NUKE_DAMAGE, "nuke")
				en.take_damage(float(r["dmg"]), NUKE_BLAST_STAGGER, 1.0)   # Nuke keeps pushback
				if bool(r["is_crit"]):
					_spawn_crit_number(en2.global_position, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		var rid := ruin.get_instance_id()
		if _nuke_hit.has(rid):
			continue
		var rr: float = _nuke_blast_reach + (float(ruin.get("hit_radius")) if ruin.get("hit_radius") != null else 0.0)
		if _nuke_blast_pos.distance_to((ruin as Node2D).global_position) <= rr:
			_nuke_hit[rid] = true
			if ruin.has_method("take_damage"):
				ruin.take_damage(NUKE_DAMAGE * _dmg_mult * _lvl_mult("nuke"))

func _fire_nuke() -> void:
	var center := _player.global_position
	var reach := _aoe_radius(NUKE_RADIUS)
	# Open a fixed-point damage hitbox for the explosion's duration (knockback is automatic in take_damage).
	_nuke_blast_pos = center
	_nuke_blast_reach = reach
	_nuke_blast_t = 0.0
	_nuke_hit.clear()
	_nuke_blast_on = true
	_damage_nuke_blast()   # hit everything already inside on the detonation frame
	# Composite blast VFX, sized to the blast radius. Overrides (set before add_child so _ready picks them up):
	#  • time_scale ÷3        → the whole explosion lasts 3× longer (every frame + every stagger gap ×3)
	#  • shockwave radius ×3  → the ripple travels 3× further
	#  • shockwave travel ×2  → net HALF the expansion speed (×3 distance ÷ ×6 time, given the 3× global slow-mo)
	var ex := ExplosionFX.new()
	ex.time_scale = ex.time_scale / 3.0
	ex.shockwave_max_radius = ex.shockwave_max_radius * 3.0
	ex.shockwave_travel = ex.shockwave_travel * 2.0
	# Tame the blinding white CENTRE so the ship (drawn on top, z=100) reads through the blast instead of being
	# washed white by the HDR core + bloom. The orange/red fireball ring stays full-strength.
	ex.glow = 1.4                        # less HDR → smaller bloom halo over the ship
	ex.core_size = 0.5                   # smaller hot-white centre → doesn't blanket the ship
	ex.core_hot = Color(3.0, 2.3, 1.6)   # warm-bright instead of a blinding pure-white point
	# Damage only while the FIRE is burning (core + fireball), NOT during the lingering smoke tail.
	_nuke_blast_dur = maxf(ex.core_life, ex.fireball_delay + ex.fireball_lifetime) / maxf(0.05, ex.time_scale)
	get_parent().add_child(ex)
	ex.call("setup", center, reach)
	# Impact feedback: a heavy screen shake on detonation + a vibration buzz 0.5s later.
	var cam := get_tree().get_first_node_in_group("camera_shake")
	if cam != null and cam.has_method("nuke_impact"):
		cam.call("nuke_impact")

# ── Sonic Wave ──────────────────────────────────────────────────────────────────────
func activate_sonic() -> void:
	_sonic_active = true
	_sonic_cd = 0.0

func _tick_sonic(delta: float, enemy_on_screen: bool) -> void:
	# Fire a fresh volley on cooldown; spawn the rest of the volley on a stagger.
	if _sonic_left <= 0:
		_sonic_cd -= delta
		if _sonic_cd <= 0.0 and enemy_on_screen:
			_sonic_cd = SONIC_COOLDOWN / _rate_mult
			_sonic_left = SONIC_RINGS
			_sonic_queue = 0.0
			_spawn_sonic_ring()
			_sonic_left -= 1
	else:
		_sonic_queue -= delta
		if _sonic_queue <= 0.0:
			_sonic_queue = SONIC_RING_STAGGER
			_spawn_sonic_ring()
			_sonic_left -= 1
	# Age + damage every live ring (each enemy hit once per ring as its front passes).
	var i := _sonic_rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _sonic_rings[i]
		ring["age"] = float(ring["age"]) + delta
		var age := float(ring["age"])
		if age >= SONIC_EXPAND_TIME:
			_sonic_rings.remove_at(i)
			i -= 1
			continue
		var maxr: float = ring["maxr"]
		var r := maxr * (age / SONIC_EXPAND_TIME)
		var center: Vector2 = ring["center"]
		var hit: Array = ring["hit"]
		var aim: float = ring["aim"]
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en) or en in hit:
				continue
			var off := (en as Node2D).global_position - center
			# Hit only enemies the arc front sweeps AND that lie within the forward cone.
			if absf(off.length() - r) <= SONIC_BAND and absf(wrapf(off.angle() - aim, -PI, PI)) <= SONIC_CONE_HALF:
				if en.has_method("take_damage"):
					var rr := _roll_damage(SONIC_DAMAGE, "sonic")
					en.take_damage(float(rr["dmg"]), 0.0)
					if bool(rr["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(rr["dmg"]))
				hit.append(en)
		i -= 1

func _spawn_sonic_ring() -> void:
	# Capture the aim direction at spawn so the cone fires where the ship was pointing (a forward fan).
	_sonic_rings.append({"center": _player.global_position, "aim": _forward().angle(), "age": 0.0, "hit": [], "maxr": _aoe_radius(SONIC_MAX_RADIUS)})

# ── Z-Sword ──────────────────────────────────────────────────────────────────────
func activate_zsword() -> void:
	_zsword_active = true
	_zsword_cd = 0.0

func _tick_zsword(delta: float, enemy_on_screen: bool) -> void:
	if not _zsword_sweeping:
		_zsword_cd -= delta
		if _zsword_cd <= 0.0 and enemy_on_screen:
			_zsword_cd = ZSWORD_COOLDOWN / _rate_mult
			_zsword_sweeping = true
			_zsword_t = 0.0
			_zsword_start = _forward().angle()   # begin the sweep from the current aim
			_zsword_hit = []
		return
	_zsword_t += delta
	if _zsword_t >= ZSWORD_SWEEP_TIME:
		_zsword_sweeping = false
		if _zslash != null:
			_zslash.fade_out()       # quick fade of the crescent when the sweep ends
		return
	var blade_ang := _zsword_start + TAU * (_zsword_t / ZSWORD_SWEEP_TIME)
	var reach := _aoe_radius(ZSWORD_LENGTH)
	var center := _player.global_position
	if _zslash != null:
		_zslash.set_sweep(center, reach, _zsword_start, blade_ang)   # crescent trails the leading edge
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or en in _zsword_hit:
			continue
		var off := (en as Node2D).global_position - center
		if off.length() > reach:
			continue
		if absf(wrapf(off.angle() - blade_ang, -PI, PI)) <= ZSWORD_ARC_HALF:
			if en.has_method("take_damage"):
				var r := _roll_damage(ZSWORD_DAMAGE, "zsword")
				en.take_damage(float(r["dmg"]), ZSWORD_STAGGER)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
			if _zslash != null:
				_zslash.add_spark((en as Node2D).global_position)   # impact sparks (tutorial: sparks come last)
			_zsword_hit.append(en)

# ── Ionizing Field ────────────────────────────────────────────────────────────────
func activate_ionize() -> void:
	_ionize_active = true
	_ionize_tick = 0.0

func _tick_ionize(delta: float) -> void:
	_ionize_clock += delta
	_ionize_tick += delta
	if _ionize_tick < IONIZE_TICK:
		return
	_ionize_tick -= IONIZE_TICK
	if not _enemy_visible:
		return
	var center := _player.global_position
	var reach := _aoe_radius(IONIZE_RADIUS)
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= reach:
			if en.has_method("take_damage"):
				var r := _roll_damage(IONIZE_DAMAGE, "ionize")
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		var rr: float = reach + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
		if center.distance_to((ruin as Node2D).global_position) <= rr:
			if ruin.has_method("take_damage"):
				ruin.take_damage(IONIZE_DAMAGE * _dmg_mult * _lvl_mult("ionize"))

# ── Batch-1 draw helpers (this Node2D draws in world space) ─────────────────────────
func _draw_sonic_ring(ring: Dictionary) -> void:
	var age := float(ring["age"])
	var maxr: float = ring["maxr"]
	var r := maxr * (age / SONIC_EXPAND_TIME)
	var a := 1.0 - (age / SONIC_EXPAND_TIME)
	var c: Vector2 = ring["center"]
	var aim: float = ring["aim"]
	# Forward crescent arc (not a full ring) — the cone the wave fans into.
	var seg := maxi(8, int(SONIC_CONE_HALF / PI * 72.0))
	draw_arc(c, r, aim - SONIC_CONE_HALF, aim + SONIC_CONE_HALF, seg, Color(SONIC_COL.r, SONIC_COL.g, SONIC_COL.b, 0.85 * a), 5.0, true)
	draw_arc(c, r, aim - SONIC_CONE_HALF, aim + SONIC_CONE_HALF, seg, Color(SONIC_COL.r, SONIC_COL.g, SONIC_COL.b, 0.30 * a), 12.0, true)

func _draw_ionize() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center := _player.global_position
	var reach := _aoe_radius(IONIZE_RADIUS)
	var pulse := 0.5 + 0.5 * sin(_ionize_clock * 4.0)
	draw_circle(center, reach, Color(IONIZE_COL.r, IONIZE_COL.g, IONIZE_COL.b, 0.06 + 0.04 * pulse))
	draw_arc(center, reach, 0.0, TAU, 64, Color(IONIZE_COL.r, IONIZE_COL.g, IONIZE_COL.b, 0.3 + 0.2 * pulse), 2.0, true)

# ══ Batch-2 weapons: Boomerang / Parasite Cloud / Moroboshi-M1 / Swarm Host / Space Snake ══════════
## Max turn toward a target angle, capped per call (used by the snake head to minimise turn angle).
func _approach_angle(cur: float, target: float, max_step: float) -> float:
	var diff := wrapf(target - cur, -PI, PI)
	return cur + clampf(diff, -max_step, max_step)

# ── Boomerang ──────────────────────────────────────────────────────────────────────
func activate_boomerang() -> void:
	_boom_active = true

## Spawn the perpetual blade(s) once, phase-offset so multiple blades (if BOOM_COUNT > 1) spread across the rose.
func _spawn_boomerangs() -> void:
	_boom_center = _player.global_position
	for k in BOOM_COUNT:
		_booms.append({"theta": TAU * float(k) / float(maxi(1, BOOM_COUNT)), "spin": 0.0, "age": 0.0, "pos": _boom_center, "hits": {}})

func _tick_boom(delta: float, _enemy_on_screen: bool) -> void:
	if not _boom_init:
		_spawn_boomerangs()
		_boom_init = true
	# The pattern centre trails the ship → flying drags the flower behind you.
	_boom_center = _boom_center.lerp(_player.global_position, clampf(BOOM_CENTER_LAG * delta, 0.0, 1.0))
	for b: Dictionary in _booms:
		b["spin"] = float(b["spin"]) + BOOM_SPIN * delta
		var prev_age := float(b["age"])
		b["age"] = prev_age + delta
		b["theta"] = float(b["theta"]) + BOOM_ROSE_SPEED * delta
		var th := float(b["theta"])
		# 3-petal rose: r = SIZE·cos(3θ). Negative r flips to the opposite side → the blade loops out into a
		# petal, back through the centre, out the next petal, tracing the trinity/triquetra flower forever.
		var rr := BOOM_SIZE * cos(3.0 * th)
		var pos := _boom_center + Vector2(cos(th), sin(th)) * rr
		b["pos"] = pos
		var hits: Dictionary = b["hits"]
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			var en2 := en as Node2D
			var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
			if pos.distance_to(en2.global_position) <= BOOM_HIT_RADIUS + enr:
				var eid := en.get_instance_id()
				if float(b["age"]) - float(hits.get(eid, -999.0)) >= BOOM_HIT_CD:
					hits[eid] = float(b["age"])
					if en.has_method("take_damage"):
						var r := _roll_damage(BOOM_DAMAGE, "boomerang")
						en.take_damage(float(r["dmg"]), 0.0)
						if bool(r["is_crit"]):
							_spawn_crit_number(en2.global_position, float(r["dmg"]))
		# Once per second, drop stale hit-timestamps so the dict doesn't grow over a long run.
		if int(b["age"]) != int(prev_age):
			var cutoff := float(b["age"]) - BOOM_HIT_CD
			for key in hits.keys():
				if float(hits[key]) < cutoff:
					hits.erase(key)

# ── Parasite Cloud ──────────────────────────────────────────────────────────────────
func activate_parasite() -> void:
	_para_active = true
	_para_cd = 0.0

func _tick_para(delta: float, enemy_on_screen: bool) -> void:
	_para_cd -= delta
	if _para_cd <= 0.0 and enemy_on_screen:
		_para_cd = PARA_COOLDOWN / _rate_mult
		var dir := _forward()
		var tgt := _nearest_enemy(_player.global_position, INF, [])
		if tgt != null:
			dir = ((tgt as Node2D).global_position - _muzzle()).normalized()
		_para_clouds.append({"pos": _muzzle(), "vel": dir * PARA_SPEED, "age": 0.0, "tick": 0.0})
	var reach := _aoe_radius(PARA_RADIUS)
	var i := _para_clouds.size() - 1
	while i >= 0:
		var c: Dictionary = _para_clouds[i]
		c["age"] = float(c["age"]) + delta
		if float(c["age"]) >= PARA_LIFETIME:
			_para_clouds.remove_at(i)
			i -= 1
			continue
		c["vel"] = (c["vel"] as Vector2).lerp(Vector2.ZERO, clampf(PARA_DRAG * delta, 0.0, 1.0))
		c["pos"] = (c["pos"] as Vector2) + (c["vel"] as Vector2) * delta
		c["tick"] = float(c["tick"]) + delta
		while float(c["tick"]) >= PARA_TICK:
			c["tick"] = float(c["tick"]) - PARA_TICK
			var cp: Vector2 = c["pos"]
			for en in get_tree().get_nodes_in_group("arena_enemy"):
				if not is_instance_valid(en):
					continue
				if cp.distance_to((en as Node2D).global_position) <= reach:
					if en.has_method("take_damage"):
						var r := _roll_damage(PARA_DAMAGE, "parasite")
						en.take_damage(float(r["dmg"]), 0.0)
		i -= 1

# ── Moroboshi-M1 (golem familiar) ───────────────────────────────────────────────────
func activate_moroboshi() -> void:
	_moro_active = true
	_moro_cd = 0.0

func _tick_moro(delta: float) -> void:
	if not _moro_init:
		_moro_pos = _player.global_position
		_moro_init = true
	var center := _player.global_position
	var tgt := _nearest_enemy(_moro_pos, MORO_AGGRO, [])
	var dest: Vector2
	if tgt != null:
		dest = (tgt as Node2D).global_position
	else:
		dest = center + Vector2(0.0, MORO_FOLLOW_DIST).rotated(_player.rotation)   # rest behind the ship
	_moro_pos = _moro_pos.move_toward(dest, MORO_MOVE_SPEED * delta)
	_moro_cd -= delta
	_moro_punch_t = maxf(0.0, _moro_punch_t - delta)
	if tgt != null and _moro_cd <= 0.0:
		var tp := (tgt as Node2D).global_position
		if _moro_pos.distance_to(tp) <= MORO_ATTACK_RANGE:
			_moro_cd = MORO_ATTACK_CD / _rate_mult
			_moro_punch_t = 0.18
			_moro_punch_pos = tp
			var reach := _aoe_radius(MORO_AOE)
			for en in get_tree().get_nodes_in_group("arena_enemy"):
				if not is_instance_valid(en):
					continue
				if tp.distance_to((en as Node2D).global_position) <= reach:
					if en.has_method("take_damage"):
						var r := _roll_damage(MORO_DAMAGE, "moroboshi")
						en.take_damage(float(r["dmg"]), MORO_STAGGER)
						if bool(r["is_crit"]):
							_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))

# ── Swarm Host (darting familiars that heal on return) ──────────────────────────────
func activate_swarm() -> void:
	_swarm_active = true

func _tick_swarm(delta: float) -> void:
	if not _swarm_init:
		_swarm_units.clear()
		for k in SWARM_COUNT:
			_swarm_units.append({"pos": _player.global_position, "state": "idle", "target": null, "dmg": 0.0, "ang": TAU * float(k) / float(maxi(1, SWARM_COUNT))})
		_swarm_init = true
	var center := _player.global_position
	for u: Dictionary in _swarm_units:
		u["ang"] = float(u["ang"]) + delta * 2.0
		var pos: Vector2 = u["pos"]
		match String(u["state"]):
			"idle":
				var orbit := center + Vector2(SWARM_IDLE_R, 0.0).rotated(float(u["ang"]))
				pos = pos.move_toward(orbit, SWARM_SPEED * delta)
				var tgt := _nearest_enemy(pos, SWARM_AGGRO, [])
				if tgt != null:
					u["target"] = tgt
					u["dmg"] = 0.0
					u["state"] = "attack"
			"attack":
				var t = u["target"]
				if t == null or not is_instance_valid(t):
					u["state"] = "return"
				else:
					var tp := (t as Node2D).global_position
					pos = pos.move_toward(tp, SWARM_SPEED * delta)
					var tr: float = float(t.get("hit_radius")) if t.get("hit_radius") != null else 0.0
					if pos.distance_to(tp) <= SWARM_HIT_RADIUS + tr:
						if t.has_method("take_damage"):
							var r := _roll_damage(SWARM_DAMAGE, "swarm")
							t.take_damage(float(r["dmg"]), 0.0)
							if bool(r["is_crit"]):
								_spawn_crit_number(tp, float(r["dmg"]))
							u["dmg"] = float(u["dmg"]) + float(r["dmg"])
						u["state"] = "return"
			"return":
				pos = pos.move_toward(center, SWARM_SPEED * delta)
				if pos.distance_to(center) <= SWARM_IDLE_R + 8.0:
					if float(u["dmg"]) > 0.0 and GameManager.has_method("heal"):
						GameManager.heal(int(round(float(u["dmg"]) * SWARM_HEAL_FRAC)))
					u["dmg"] = 0.0
					u["state"] = "idle"
		u["pos"] = pos

# ── Space Snake (segmented fire familiar) ───────────────────────────────────────────
func activate_snake() -> void:
	_snake_active = true

func _tick_snake(delta: float) -> void:
	_run_snake(delta, "snake")

## Shared Space Snake movement + per-segment contact damage. `kind` selects the damage scaling (the Predator
## fusion reuses this with kind "predator" so the snake's contact bite scales with the fused level).
func _run_snake(delta: float, kind: String, turn_rate := SNAKE_TURN, aim_angle := INF) -> void:
	if not _snake_init:
		_snake_pts.clear()
		var base := _player.global_position
		for k in SNAKE_SEGMENTS:
			_snake_pts.append(base - Vector2(SNAKE_SPACING * float(k), 0.0))
		_snake_dir = 0.0
		_snake_init = true
	if _snake_pts.is_empty():
		return
	var head: Vector2 = _snake_pts[0]
	var desired := _snake_dir
	if is_finite(aim_angle):
		desired = aim_angle   # caller-provided heading (Predator: steer toward the densest beam line)
	else:
		var tgt := _nearest_enemy(head, INF, [])
		if tgt != null:
			desired = ((tgt as Node2D).global_position - head).angle()
		else:
			desired = (head - _player.global_position).angle() + PI * 0.5   # idle: circle the ship
	_snake_dir = _approach_angle(_snake_dir, desired, turn_rate * delta)
	head += Vector2(cos(_snake_dir), sin(_snake_dir)) * SNAKE_SPEED * delta
	_snake_pts[0] = head
	for k in range(1, _snake_pts.size()):
		var prev: Vector2 = _snake_pts[k - 1]
		var cur: Vector2 = _snake_pts[k]
		var d := prev - cur
		if d.length() > SNAKE_SPACING:
			cur = prev - d.normalized() * SNAKE_SPACING
		_snake_pts[k] = cur
	_snake_tick += delta
	while _snake_tick >= SNAKE_TICK:
		_snake_tick -= SNAKE_TICK
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			var ep := (en as Node2D).global_position
			var er: float = SNAKE_HIT_RADIUS + (float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0)
			for seg: Vector2 in _snake_pts:
				if seg.distance_to(ep) <= er:
					if en.has_method("take_damage"):
						var r := _roll_damage(SNAKE_DAMAGE, kind)
						en.take_damage(float(r["dmg"]), 0.0)
					break

# ── Batch-2 draw helpers ────────────────────────────────────────────────────────────
## The Predator fusion (lasgun + snake): the Space Snake also fires a Lasgun beam from its head, re-aimed each
## tick to the direction crossing the MOST enemies. Continuous beam (no duty cycle).
func activate_predator() -> void:
	_predator_active = true
	_predator_beam_cd = 0.0
	_snake_init = false   # (re)build the snake when the fusion takes over

func _ensure_predator_beam() -> void:
	if _predator_beam != null and is_instance_valid(_predator_beam):
		return
	_predator_beam = BeamScript.new()
	add_child(_predator_beam)
	_predator_beam.z_index = LASGUN_BEAM_Z

func _tick_predator(delta: float, enemy_on_screen: bool) -> void:
	# Steer the head toward the densest beam line (only when there are enemies); otherwise default snake
	# steering (chase/idle). The head turns at the slower PREDATOR_TURN rate — it must rotate to aim.
	var has_enemies := not get_tree().get_nodes_in_group("arena_enemy").is_empty()
	var aim_angle := _predator_aim.angle() if (enemy_on_screen and has_enemies) else INF
	_run_snake(delta, "predator", PREDATOR_TURN, aim_angle)   # snake still chases + bites (fused-level scaled)
	_ensure_predator_beam()
	if _snake_pts.is_empty():
		return
	var head: Vector2 = _snake_pts[0]
	if not enemy_on_screen:
		_predator_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
		return
	# Recompute the IDEAL aim (steering target for the head); the beam itself fires STRAIGHT from the head.
	_predator_beam_cd -= delta
	var fire := false
	if _predator_beam_cd <= 0.0:
		_predator_beam_cd = LASGUN_TICK / _rate_mult
		_predator_aim = _best_beam_dir(head)
		fire = true
	var dir := Vector2.from_angle(_snake_dir)   # beam = the head's current facing (turning aims it)
	# Bosses block the beam (same rule as the main Lasgun).
	var block_along := LASGUN_RANGE
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		var tb: Vector2 = (b as Node2D).global_position - head
		var balong := tb.dot(dir)
		if balong < 0.0 or balong > LASGUN_RANGE:
			continue
		var _br = b.get("hit_radius")
		var bw: float = LASGUN_WIDTH * 0.5 + (float(_br) if _br != null else LASGUN_HIT_PAD)
		if (tb - dir * balong).length() <= bw and balong < block_along:
			block_along = balong
	var blocked := block_along < LASGUN_RANGE
	_predator_beam.set_beam(head, head + dir * maxf(2.0, block_along), true, blocked)
	if fire:
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en):
				continue
			var to_e: Vector2 = (en as Node2D).global_position - head
			var along := to_e.dot(dir)
			if along < 0.0 or along > block_along:
				continue
			var _en_r = en.get("hit_radius")
			var hit_w: float = LASGUN_WIDTH * 0.5 + (float(_en_r) if _en_r != null else LASGUN_HIT_PAD)
			if (to_e - dir * along).length() > hit_w:
				continue
			if en.has_method("take_damage"):
				var r := _roll_damage(LASGUN_DAMAGE, "predator")
				en.take_damage(float(r["dmg"]), LASGUN_STAGGER)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))

## The beam direction from `head` that crosses the MOST enemies (candidate directions = toward each enemy).
func _best_beam_dir(head: Vector2) -> Vector2:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var best_dir := _predator_aim
	var best_count := -1
	for cand in enemies:
		if not is_instance_valid(cand):
			continue
		var cd: Vector2 = (cand as Node2D).global_position - head
		if cd.length() < 1.0:
			continue
		var dir := cd.normalized()
		var count := 0
		for en in enemies:
			if not is_instance_valid(en):
				continue
			var to_e: Vector2 = (en as Node2D).global_position - head
			var along := to_e.dot(dir)
			if along < 0.0 or along > LASGUN_RANGE:
				continue
			var _en_r = en.get("hit_radius")
			var hit_w: float = LASGUN_WIDTH * 0.5 + (float(_en_r) if _en_r != null else LASGUN_HIT_PAD)
			if (to_e - dir * along).length() <= hit_w:
				count += 1
		if count > best_count:
			best_count = count
			best_dir = dir
	return best_dir

# ── Homing Missile (ported from weapon_system.gd) ─────────────────────────────────────────────────
func activate_homing() -> void:
	_homing_active = true
	_homing_acc = 0.0
	if _missile_tex == null:
		_missile_tex = load("res://assets/weaponry/missile.png") as Texture2D

func _tick_homing(delta: float, enemy_on_screen: bool) -> void:
	_homing_acc += delta
	if enemy_on_screen:
		var interval := HOMING_INTERVAL / _rate_mult
		while _homing_acc >= interval:
			_homing_acc -= interval
			_fire_homing_volley()
	_update_missiles(delta)

# ── Toxic Ballistic fusion (homing + chemtrail): same missile volleys, but each missile lays a chemtrail down
# its flight path (the DoT + toxic-fire reuse the Chemtrail pipeline). ──
func activate_toxic() -> void:
	_toxic_active = true
	_homing_acc = 0.0
	if _missile_tex == null:
		_missile_tex = load("res://assets/weaponry/missile.png") as Texture2D

func _tick_toxic(delta: float, enemy_on_screen: bool) -> void:
	_homing_acc += delta
	if enemy_on_screen:
		var interval := HOMING_INTERVAL / _rate_mult
		while _homing_acc >= interval:
			_homing_acc -= interval
			_fire_homing_volley()
	_update_missiles(delta)                              # missiles drop chemtrail puffs (because _toxic_active)
	_process_chemtrail_puffs(delta, "toxic_ballistic")   # age + DoT + toxic-fire visual for those puffs

## Fire a volley of MISSILE_BASE_SHOTS (+ the "shots"/multishot stat) missiles, each at a distinct nearby enemy
## (falling back to the nearest when targets run out), peeling off alternating sides.
func _fire_homing_volley() -> void:
	var extra := 0
	if GameManager.has_method("mech_bonus"):
		extra = int(round(GameManager.mech_bonus("shots") + GameManager.mech_bonus("multishot")))
	var count := maxi(1, MISSILE_BASE_SHOTS + extra)
	var chosen: Array = []
	for s in count:
		var tgt := _pick_spread_target(chosen)
		if tgt == null:
			tgt = _nearest_enemy(_player.global_position, HOMING_ACQUIRE_RANGE, [])   # reuse nearest if none fresh
		if tgt == null:
			return
		chosen.append(tgt)
		_spawn_homing_missile(tgt, 1.0 if (s % 2 == 0) else -1.0)

## Pick a target for the next missile: among enemies NOT already chosen this volley, the one maximising
## (distance from the nearest already-chosen target) − weight·(distance to the ship). So missiles fan out to
## separate targets — close ones preferred, but biased away from where the other missiles are already headed.
func _pick_spread_target(chosen: Array) -> Node:
	var from := _player.global_position
	var best: Node = null
	var best_score := -INF
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en) or en in chosen:
			continue
		var ep: Vector2 = (en as Node2D).global_position
		var prox := ep.distance_to(from)
		if prox > HOMING_ACQUIRE_RANGE:
			continue
		var spread := HOMING_ACQUIRE_RANGE   # no chosen targets yet → neutral; proximity decides
		for c in chosen:
			if is_instance_valid(c):
				spread = minf(spread, ep.distance_to((c as Node2D).global_position))
		# Closeness (−prox) dominates; the spread bonus is CAPPED so it only nudges away from other missiles'
		# targets, never overrides picking a near enemy over a far one.
		var score := -prox + MISSILE_SPREAD_WEIGHT * minf(spread, MISSILE_SPREAD_CAP)
		if score > best_score:
			best_score = score
			best = en
	return best

## Launch one missile at `tgt`, peeling off the back to `side` with an initial velocity. From there it flies
## like the Space Snake: always moving, steering toward the target — never pivoting in place.
func _spawn_homing_missile(tgt: Node, side: float) -> void:
	var ship_c := _player.global_position
	var down := -_forward()                              # toward the back/underside
	var p0 := ship_c + down * MUZZLE_OFFSET * 0.5        # spawn at the back/underside
	var eject_dir := (down * 0.5 + Vector2(side, 0.0)).normalized()   # peel out & back, to one side
	_missiles.append({
		"pos": p0, "vel": eject_dir * MISSILE_LAUNCH_SPEED, "speed": MISSILE_LAUNCH_SPEED, "dmg": HOMING_DAMAGE,
		"target_enemy": tgt, "target": (tgt as Node2D).global_position,
		"seek_t": 0.0, "life": 0.0, "facing": eject_dir.angle(), "emit_acc": 0.0,
	})
	_flashes.append({"pos": p0, "age": 0.0, "max_age": 0.25, "radius": 18.0})

func _update_missiles(delta: float) -> void:
	var i := _missiles.size() - 1
	while i >= 0:
		var m: Dictionary = _missiles[i]
		m["life"] = float(m["life"]) + delta
		# Re-home: track the live enemy's current position (fall back to last known if it died).
		var te = m.get("target_enemy")
		if te != null and is_instance_valid(te):
			m["target"] = (te as Node2D).global_position
		var pos: Vector2 = m["pos"]
		# Snake-like flight: ALWAYS moving. Accelerate (ease-in), steer the heading toward the target at a fixed
		# turn rate (it cannot pivot in place), then step forward along that heading.
		m["seek_t"] = float(m["seek_t"]) + delta
		var accel := MISSILE_ACCEL * (1.0 + MISSILE_ACCEL_RAMP * float(m["seek_t"]))
		m["speed"] = minf(MISSILE_SPEED, float(m["speed"]) + accel * delta)
		var to_t: Vector2 = (m["target"] as Vector2) - pos
		var step := float(m["speed"]) * delta
		var explode := false
		if to_t.length() <= maxf(step, MISSILE_EXPLODE_DIST):
			m["pos"] = m["target"]
			explode = true
		else:
			var heading: Vector2 = m["vel"]
			var cur_a := heading.angle() if heading.length() > 0.01 else float(m["facing"])
			var new_a := _approach_angle(cur_a, to_t.angle(), MISSILE_SEEK_TURN * delta)
			var dir := Vector2.from_angle(new_a)
			m["vel"] = dir * float(m["speed"])
			m["pos"] = pos + dir * step
			m["facing"] = new_a   # nose always points where it travels
			# Toxic Ballistic: lay a chemtrail puff along the path (drops in place — vel zero — so the trail lingers).
			if _toxic_active:
				m["emit_acc"] = float(m["emit_acc"]) + delta
				while float(m["emit_acc"]) >= CHEMTRAIL_EMIT_INTERVAL:
					m["emit_acc"] = float(m["emit_acc"]) - CHEMTRAIL_EMIT_INTERVAL
					_chemtrail_puffs.append({
						"pos": m["pos"], "vel": Vector2.ZERO,
						"age": 0.0, "max_age": CHEMTRAIL_PUFF_LIFETIME,
						"radius": TOXIC_PUFF_RADIUS + _mech_radius(),
					})
		if not explode and float(m["life"]) > MISSILE_MAX_LIFE:
			explode = true
		if explode:
			_missile_explode(m["pos"], float(m["dmg"]))
			_missiles.remove_at(i)
		else:
			_missiles[i] = m
		i -= 1

## AoE blast: damage every enemy/ruin within MISSILE_AOE_RADIUS (scaled by _roll_damage + the weapon level).
func _missile_explode(pos: Vector2, dmg: float, kind := "homing") -> void:
	var reach := _aoe_radius(MISSILE_AOE_RADIUS)   # "AOE" stat (mech_bonus "radius") widens the blast
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var er: float = reach + (float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0)
		if pos.distance_to((en as Node2D).global_position) <= er:
			if en.has_method("take_damage"):
				var r := _roll_damage(dmg, kind)
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		var rr: float = reach + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
		if pos.distance_to((ruin as Node2D).global_position) <= rr:
			if ruin.has_method("take_damage"):
				ruin.take_damage(dmg * _dmg_mult * _lvl_mult(kind))
	_flashes.append({"pos": pos, "age": 0.0, "max_age": 0.35, "radius": reach})

func _draw_missiles() -> void:
	for m: Dictionary in _missiles:
		var mp: Vector2 = m["pos"]
		var f := float(m["facing"])
		var fwd := Vector2(cos(f), sin(f))
		# Exhaust plume (white-hot → orange → blue tip → fade): 7 circles behind the nozzle.
		var nozzle := mp - fwd * 20.0
		var back := -fwd
		for pi_ in range(7):
			var t := float(pi_) / 6.0
			var ppos := nozzle + back * (t * 28.0)
			var psize := lerpf(4.5, 1.0, t)
			var col: Color
			if t < 0.30:
				var rr := t / 0.30
				col = Color(1.0, lerpf(0.95, 0.60, rr), lerpf(0.70, 0.20, rr), 1.0)
			elif t < 0.65:
				var rr := (t - 0.30) / 0.35
				col = Color(lerpf(1.0, 0.45, rr), 0.6, lerpf(0.20, 1.0, rr), lerpf(1.0, 0.85, rr))
			else:
				var rr := (t - 0.65) / 0.35
				col = Color(lerpf(0.45, 0.20, rr), lerpf(0.60, 0.45, rr), 1.0, lerpf(0.85, 0.0, rr))
			draw_circle(ppos, psize, col)
		if _missile_tex != null:
			draw_set_transform(mp, f + PI / 2.0, Vector2.ONE)
			draw_texture_rect(_missile_tex, Rect2(-10.0, -23.0, 20.0, 46.0), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var a := mp + fwd * 14.0
			var bl := mp + fwd.rotated(2.5) * 9.0
			var br := mp + fwd.rotated(-2.5) * 9.0
			draw_colored_polygon(PackedVector2Array([a, bl, br]), Color(0.9, 0.85, 0.8))

func _draw_boomerang(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var s := float(b["spin"])
	var ver := clampi(sprite_version_boomerang, 1, BOOM_TEX_VERSIONS.size()) - 1
	var tex: Texture2D = BOOM_TEX_VERSIONS[ver]
	if tex != null:
		# Spin the boomerang sprite about its centre at the projectile position (aspect-locked, never stretched).
		var ts := tex.get_size()
		var sz := Vector2(BOOM_DRAW, BOOM_DRAW * ts.y / ts.x if ts.x > 0.0 else BOOM_DRAW)
		draw_set_transform(p, s, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# Procedural fallback (if the sprite is missing).
	for off: float in [0.0, PI * 0.5]:
		var a := s + off
		var d := Vector2(cos(a), sin(a)) * BOOM_BLADE
		draw_line(p - d, p + d, Color(BOOM_COL.r, BOOM_COL.g, BOOM_COL.b, 0.9), 5.0, true)
	draw_circle(p, BOOM_BLADE * 0.18, Color(1, 1, 1, 0.85))

func _draw_para_cloud(c: Dictionary) -> void:
	var p: Vector2 = c["pos"]
	var a := clampf(1.0 - float(c["age"]) / PARA_LIFETIME, 0.0, 1.0)
	var reach := _aoe_radius(PARA_RADIUS)
	draw_circle(p, reach, Color(PARA_COL.r, PARA_COL.g, PARA_COL.b, 0.10 + 0.10 * a))
	draw_arc(p, reach, 0.0, TAU, 48, Color(PARA_COL.r, PARA_COL.g, PARA_COL.b, 0.3 * a), 2.0, true)

func _draw_moro() -> void:
	draw_circle(_moro_pos, 18.0, Color(MORO_COL.r, MORO_COL.g, MORO_COL.b, 0.25))
	draw_circle(_moro_pos, 13.0, Color(MORO_COL.r, MORO_COL.g, MORO_COL.b, 0.95))
	if _moro_punch_t > 0.0:
		var pf := _moro_punch_t / 0.18
		draw_arc(_moro_punch_pos, _aoe_radius(MORO_AOE) * (1.0 - pf), 0.0, TAU, 32, Color(1, 1, 1, 0.6 * pf), 3.0, true)

func _draw_swarm() -> void:
	for u: Dictionary in _swarm_units:
		var p: Vector2 = u["pos"]
		draw_circle(p, 12.0, Color(SWARM_COL.r, SWARM_COL.g, SWARM_COL.b, 0.25))
		draw_circle(p, 7.0, Color(SWARM_COL.r, SWARM_COL.g, SWARM_COL.b, 0.95))

func _draw_snake() -> void:
	if _snake_pts.size() < 2:
		return
	var n := _snake_pts.size()
	for k in range(n - 1):
		var a: Vector2 = _snake_pts[k]
		var b2: Vector2 = _snake_pts[k + 1]
		var f := 1.0 - float(k) / float(n)
		draw_line(a, b2, Color(SNAKE_COL.r, SNAKE_COL.g * f, SNAKE_COL.b * 0.5, 0.9), lerpf(4.0, 12.0, f), true)
	draw_circle(_snake_pts[0], 9.0, Color(1.0, 0.85, 0.5, 0.95))

# ── Carnage fusion (gatling + red_x): constant Red X fire + Gatling firing in 4 directions ─────────
func activate_carnage() -> void:
	_carnage_active = true
	_carnage_gat_acc = 0.0
	_carnage_redx_tick = 0.0

func _tick_carnage(delta: float, enemy_on_screen: bool) -> void:
	# Gatling at its normal cadence, but each volley fires in 4 directions: the main facing (toward the mouse)
	# plus the 3 directions 90° apart. Bullets tagged "carnage" → scale with this fusion's level.
	var interval := GAT_FIRE_INTERVAL / _rate_mult
	_carnage_gat_acc += delta
	if not enemy_on_screen:
		_carnage_gat_acc = minf(_carnage_gat_acc, interval)   # prime ONE shot, don't bank a backlog (see _process Gatling)
	if enemy_on_screen:
		while _carnage_gat_acc >= interval:
			_carnage_gat_acc -= interval
			var fwd := _forward()
			var origin := _player.global_position
			for k in 4:
				var dir := fwd.rotated(PI * 0.5 * float(k))
				_bullets.append({"pos": origin, "vel": dir * GAT_SPEED, "life": 0.0, "start": origin, "kind": "carnage"})
			_gat_muzzle_t = 1.0   # reuse the Gatling muzzle flash
	# Red X VISUAL: ONE persistent emitter held in its lit HOLD phase → a true continuous stream (no re-trigger,
	# no blink). It just follows the ship; the damage below is fully decoupled from it.
	_ensure_carnage_fire()
	if _carnage_fire != null:
		_carnage_fire.global_position = _player.global_position
		_carnage_fire.rotation = _forward().angle()   # arms follow the 4 Gatling directions (rotate with the mouse)
	# Red X DAMAGE: applied on CARNAGE_REDX_TICK ticks. Per-tick damage = RED_X_DAMAGE × (tick / RED_X_INTERVAL)
	# so sustained DPS to a stationary target matches a single base Red X weapon (regardless of the tick rate).
	_carnage_redx_tick -= delta
	if _carnage_redx_tick <= 0.0 and enemy_on_screen:
		_carnage_redx_tick = CARNAGE_REDX_TICK / _rate_mult
		_red_x_damage("carnage", CARNAGE_REDX_TICK / RED_X_INTERVAL, _forward().angle())

## Build (once) the persistent Carnage X-fire. Unlike the one-shot Red X flash, this uses a near-infinite HOLD
## so the 4 arms stay continuously lit/shimmering (the DynamicFire HOLD phase) — a real stream, not re-triggers.
func _ensure_carnage_fire() -> void:
	if _carnage_fire != null and is_instance_valid(_carnage_fire):
		return
	_carnage_fire = DynamicFire.new()
	_carnage_fire.shape             = "cross"
	_carnage_fire.arm_count         = 4
	_carnage_fire.ring_start_angle  = 0.0           # arm 0 at local 0° → node rotation aims it at the ship facing
	_carnage_fire.z_index           = 6
	_carnage_fire.arm_inner         = RED_X_INNER
	_carnage_fire.arm_length        = RED_X_REACH
	_carnage_fire.draw_duration     = CARNAGE_FIRE_DRAW
	_carnage_fire.draw_ease         = 1.0
	_carnage_fire.hold_duration     = 1.0e9         # effectively never ends → stays in the lit HOLD phase
	_carnage_fire.burnout_duration  = 0.3
	_carnage_fire.recede_burnout    = true
	_carnage_fire.loop              = false         # do NOT restart (looping would re-draw → blink)
	_carnage_fire.free_on_done      = false
	_carnage_fire.particle_lifetime = CARNAGE_FIRE_LIFETIME
	_carnage_fire.particle_amount   = 330
	_carnage_fire.particle_size_min = 40.0
	_carnage_fire.particle_size_max = 92.0
	_carnage_fire.intensity         = 0.5
	_carnage_fire.glow              = 0.25
	add_child(_carnage_fire)
	_carnage_fire.global_position = _player.global_position

# ── Overcharger fusion (gauss + arc): Arc chain lightning that drops a Gauss explosion at every struck target ──
func activate_overcharger() -> void:
	_overcharger_active = true
	_arc_cd = 0.0   # fire on the next frame (shares the Arc burst cooldown)

# ── Vampire Host fusion (swarm + sonic): familiars fire small sonic waves; player lifesteals on hit ──
func activate_vampire() -> void:
	_vampire_active = true

func _tick_vampire(delta: float) -> void:
	if not _vampire_init:
		_vampire_units.clear()
		for k in SWARM_COUNT:
			_vampire_units.append({"pos": _player.global_position, "state": "idle", "target": null, "dmg": 0.0, "ang": TAU * float(k) / float(maxi(1, SWARM_COUNT))})
		_vampire_init = true
	var center := _player.global_position
	# Full Swarm Host attack (idle orbit → chase → melee hit → return + heal), AND on each melee hit it ALSO
	# fires a sonic wave at the target (1/3 damage, which lifesteals on its own — see the wave loop below).
	for u: Dictionary in _vampire_units:
		u["ang"] = float(u["ang"]) + delta * 2.0
		var pos: Vector2 = u["pos"]
		match String(u["state"]):
			"idle":
				var orbit := center + Vector2(SWARM_IDLE_R, 0.0).rotated(float(u["ang"]))
				pos = pos.move_toward(orbit, SWARM_SPEED * delta)
				var tgt := _nearest_enemy(pos, SWARM_AGGRO, [])
				if tgt != null:
					u["target"] = tgt
					u["dmg"] = 0.0
					u["state"] = "attack"
			"attack":
				var t = u["target"]
				if t == null or not is_instance_valid(t):
					u["state"] = "return"
				else:
					var tp := (t as Node2D).global_position
					pos = pos.move_toward(tp, SWARM_SPEED * delta)
					var tr: float = float(t.get("hit_radius")) if t.get("hit_radius") != null else 0.0
					if pos.distance_to(tp) <= SWARM_HIT_RADIUS + tr:
						# Normal melee hit (scales with this fusion's level).
						if t.has_method("take_damage"):
							var r := _roll_damage(SWARM_DAMAGE, "vampire_host")
							t.take_damage(float(r["dmg"]), 0.0)
							if bool(r["is_crit"]):
								_spawn_crit_number(tp, float(r["dmg"]))
							u["dmg"] = float(u["dmg"]) + float(r["dmg"])
						# ON TOP of the melee: shoot a sonic wave at the target.
						_vampire_rings.append({"center": pos, "aim": (tp - pos).angle(), "age": 0.0, "hit": [], "maxr": _aoe_radius(VAMPIRE_RING_MAXR)})
						u["state"] = "return"
			"return":
				pos = pos.move_toward(center, SWARM_SPEED * delta)
				if pos.distance_to(center) <= SWARM_IDLE_R + 8.0:
					if float(u["dmg"]) > 0.0 and GameManager.has_method("heal"):
						GameManager.heal(int(round(float(u["dmg"]) * VAMPIRE_HEAL_FRAC)))   # heal on the melee damage
					u["dmg"] = 0.0
					u["state"] = "idle"
		u["pos"] = pos
	# Age + damage every live wave (each enemy hit once per wave; heal the player a fraction of damage dealt).
	var i := _vampire_rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _vampire_rings[i]
		ring["age"] = float(ring["age"]) + delta
		var age := float(ring["age"])
		if age >= SONIC_EXPAND_TIME:
			_vampire_rings.remove_at(i)
			i -= 1
			continue
		var maxr: float = ring["maxr"]
		var r := maxr * (age / SONIC_EXPAND_TIME)
		var c: Vector2 = ring["center"]
		var hit: Array = ring["hit"]
		var aim: float = ring["aim"]
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en) or en in hit:
				continue
			var off := (en as Node2D).global_position - c
			if absf(off.length() - r) <= SONIC_BAND and absf(wrapf(off.angle() - aim, -PI, PI)) <= SONIC_CONE_HALF:
				if en.has_method("take_damage"):
					var rr := _roll_damage(SONIC_DAMAGE * VAMPIRE_DMG_FRAC, "vampire_host")
					en.take_damage(float(rr["dmg"]), 0.0)
					if bool(rr["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(rr["dmg"]))
					if GameManager.has_method("heal"):
						GameManager.heal(int(round(float(rr["dmg"]) * VAMPIRE_HEAL_FRAC)))
				hit.append(en)
		i -= 1

func _draw_vampire() -> void:
	# Familiars as small pink dots, plus their expanding sonic-wave arcs (smaller than the Sonic weapon's).
	for u: Dictionary in _vampire_units:
		var p: Vector2 = u["pos"]
		draw_circle(p, 9.0, Color(SWARM_COL.r, SWARM_COL.g, SWARM_COL.b, 0.25))
		draw_circle(p, 5.0, Color(SWARM_COL.r, SWARM_COL.g, SWARM_COL.b, 0.95))
	for ring: Dictionary in _vampire_rings:
		var age := float(ring["age"])
		var maxr: float = ring["maxr"]
		var r := maxr * (age / SONIC_EXPAND_TIME)
		var a := 1.0 - (age / SONIC_EXPAND_TIME)
		var c: Vector2 = ring["center"]
		var aim: float = ring["aim"]
		var seg := maxi(8, int(SONIC_CONE_HALF / PI * 72.0))
		draw_arc(c, r, aim - SONIC_CONE_HALF, aim + SONIC_CONE_HALF, seg, Color(SONIC_COL.r, SONIC_COL.g, SONIC_COL.b, 0.85 * a), 4.0, true)

func _draw() -> void:
	# Comet trails + sparks draw UNDER the orb ColorRect children.
	for o: Dictionary in _orbs:
		_draw_gauss_trail(o)
	_draw_sparks()
	for b: Dictionary in _bullets:
		_draw_tracer(b["pos"], b["vel"])
		if b.get("healing", false):   # Healing Round capstone — soft red glow on the bullet
			var hp_: Vector2 = b["pos"]
			draw_circle(hp_, 7.0, Color(1.0, 0.4, 0.45, 0.35))
			draw_circle(hp_, 3.5, Color(1.0, 0.55, 0.6, 0.9))
	# Arc chain lightning is now rendered by per-link Line2D bolts (arc_lightning.gdshader) + spark/flare
	# particles spawned in _fire_arc — no immediate-mode draw here.
	if _orbital_active or _singularity_active:
		_draw_orbital()   # Singularities draws the 3 orbital balls (the voids are ColorRect nodes, not _draw)
	for sring: Dictionary in _sonic_rings:
		_draw_sonic_ring(sring)
	# Z-Sword slash is rendered by the additive ZSlash crescent node (driven in _tick_zsword) — no draw here.
	if _ionize_active:
		_draw_ionize()
	for boom: Dictionary in _booms:
		_draw_boomerang(boom)
	for pc: Dictionary in _para_clouds:
		_draw_para_cloud(pc)
	if _moro_active and _moro_init:
		_draw_moro()
	if _swarm_active:
		_draw_swarm()
	if _snake_active or _predator_active:
		_draw_snake()
	if not _missiles.is_empty():
		_draw_missiles()
	if _vampire_active:
		_draw_vampire()
	_draw_flashes()
	if GAUSS_EXPL_DEBUG_DRAW:
		for e: Dictionary in _explosions:
			var c: Vector2 = e["pos"]
			# Solid = GAUSS_EXPL_RADIUS (tune to the visible 6-8 plasma edge); faint = the enemy-center
			# cutoff actually used in the hit test (radius + GAUSS_EXPL_HIT_PAD).
			draw_arc(c, GAUSS_EXPL_RADIUS, 0.0, TAU, 56, Color(1.0, 0.3, 0.1, 0.9), 2.0, true)
			draw_arc(c, GAUSS_EXPL_RADIUS + GAUSS_EXPL_HIT_PAD, 0.0, TAU, 56, Color(1.0, 0.8, 0.2, 0.35), 1.0, true)
	if CHEMTRAIL_DEBUG_DRAW:
		for puff: Dictionary in _chemtrail_puffs:
			var pt := clampf(1.0 - float(puff["age"]) / maxf(0.01, float(puff["max_age"])), 0.0, 1.0)
			# Filled low-alpha disc → overlapping puffs blend into one continuous green band.
			draw_circle(puff["pos"], float(puff["radius"]), Color(0.35, 0.85, 0.3, 0.12 + 0.12 * pt))

func _draw_tracer(p: Vector2, vel: Vector2) -> void:
	var dir := (vel as Vector2).normalized() if (vel as Vector2).length() > 0.01 else Vector2.UP
	var ca := dir.x
	var sa := dir.y
	var s := GAT_TRACER_SCALE
	var hl := GAT_TRACER_LEN * 0.5 * s
	var hw := GAT_TRACER_WIDTH * 0.5 * s
	var tail_steps := 5
	for i in range(tail_steps, 0, -1):
		var f := float(i) / float(tail_steps)
		var tp := p - dir * (GAT_TAIL_LEN * s * f)
		var ta := GAT_GLOW_INTENSITY * (1.0 - f) * 0.7
		draw_circle(tp, hw * (1.0 - 0.6 * f), Color(GAT_EDGE_COL.r, GAT_EDGE_COL.g, GAT_EDGE_COL.b, ta))
	draw_colored_polygon(_oblong(p, hl * GAT_GLOW_SIZE, hw * GAT_GLOW_SIZE, ca, sa, 20),
		Color(GAT_EDGE_COL.r, GAT_EDGE_COL.g, GAT_EDGE_COL.b, GAT_GLOW_INTENSITY * 0.5))
	draw_colored_polygon(_oblong(p, hl * GAT_GLOW_SIZE * 0.6, hw * GAT_GLOW_SIZE * 0.6, ca, sa, 20),
		Color(GAT_BODY_COL.r, GAT_BODY_COL.g, GAT_BODY_COL.b, GAT_GLOW_INTENSITY))
	draw_colored_polygon(_oblong(p, hl, hw, ca, sa, 18), GAT_EDGE_COL)
	draw_colored_polygon(_oblong(p, hl * 0.72, hw * 0.72, ca, sa, 18), GAT_BODY_COL)
	var head := p + dir * (hl * 0.28)
	draw_colored_polygon(_oblong(head, hl * 0.42, hw * 0.5, ca, sa, 16), GAT_CORE_COL)

func _oblong(c: Vector2, rx: float, ry: float, ca: float, sa: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segs)
	for i in segs:
		var t := TAU * float(i) / float(segs)
		var x := rx * cos(t)
		var y := ry * sin(t)
		pts[i] = c + Vector2(x * ca - y * sa, x * sa + y * ca)
	return pts

## Soft radial glow: one smooth-falloff gradient sprite, modulated by `col`, centred at `pos`. Replaces
## stacked hard draw_circle layers so glows blend out smoothly. Lazily builds the gradient texture once.
func _draw_glow(pos: Vector2, radius: float, col: Color) -> void:
	if _glow_tex == null:
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var ctr := float(size) * 0.5
		for y in size:
			for x in size:
				var dx := (float(x) - ctr) / ctr
				var dy := (float(y) - ctr) / ctr
				var d := sqrt(dx * dx + dy * dy)
				var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.0)   # smooth radial falloff → no hard edge
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		_glow_tex = ImageTexture.create_from_image(img)
	draw_texture_rect(_glow_tex, Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), false, col)

func _draw_gauss_trail(o: Dictionary) -> void:
	var trail: Array = o.get("trail", [])
	var n := trail.size()
	if n < 2:
		return
	var base_w := GAUSS_RADIUS * GAUSS_TRAIL_WIDTH
	var c := GAUSS_TRAIL_COL
	for i in range(n - 1, 0, -1):
		var f := float(i) / float(n - 1)
		var fade := 1.0 - f
		var w := base_w * (0.3 + 0.7 * fade)
		if w < 0.5:
			continue
		var pa: Vector2 = trail[i]
		# Soft radial-gradient glow (smooth falloff) instead of stacked hard circles → blends out cleanly.
		_draw_glow(pa, w * 2.6, Color(c.r, c.g, c.b, GAUSS_TRAIL_ALPHA * 0.55 * fade))   # wide colored halo
		_draw_glow(pa, w * 0.9, Color(1.0, 0.9, 0.92, GAUSS_TRAIL_ALPHA * 0.6 * fade))    # bright hot core

func _draw_sparks() -> void:
	var c := GAUSS_SPARK_COL
	for s: Dictionary in _sparks:
		var t := clampf(1.0 - float(s["life"]) / maxf(0.01, float(s["ttl"])), 0.0, 1.0)
		var p: Vector2 = s["pos"]
		var v: Vector2 = s["vel"]
		var tail := p - (v.normalized() * GAUSS_SPARK_LEN if v.length() > 0.01 else Vector2.ZERO)
		draw_line(tail, p, Color(c.r, c.g, c.b, GAUSS_SPARK_ALPHA * t), 2.0)
		draw_circle(p, 1.6 * t + 0.5, Color(1.0, 1.0, 1.0, GAUSS_SPARK_ALPHA * t))

func _draw_flashes() -> void:
	for f: Dictionary in _flashes:
		var t := clampf(1.0 - float(f["age"]) / maxf(0.01, float(f["max_age"])), 0.0, 1.0)
		var pos: Vector2 = f["pos"]
		var r := float(f["radius"]) * (0.4 + 0.6 * (1.0 - t))   # expands as it fades
		draw_circle(pos, r, Color(0.7, 0.85, 1.0, 0.25 * t))
		draw_circle(pos, r * 0.5, Color(1.0, 1.0, 1.0, 0.5 * t))
