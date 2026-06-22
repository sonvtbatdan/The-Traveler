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

# ── TUNABLES: Gauss cannon (auto-charge → heavy piercing orb) ─────────────────
const GAUSS_ENABLED     := false    # disabled for now
const GAUSS_STAGGER     := 0.35     # s the enemy is staggered per Gauss hit (heavier weapon = more)
const GAUSS_LIGHT       := 5.0      # dust-light "value" per Gauss orb (heavy → big bright light)
const GAUSS_CHARGE_TIME := 1.4      # s to fully charge between shots (charge rings ramp up over this)
const GAUSS_SPEED       := 520.0    # px/s (heavy + slow so you watch it plough through)
const GAUSS_DAMAGE      := 55.0     # per-shot DAMAGE BUDGET the orb carries (× damage-mult at fire)
const GAUSS_RADIUS      := 30.0     # FULL hit radius (at full budget); shrinks ∝ sqrt(damage)
const GAUSS_MIN_DMG     := 1.0      # cull the orb once its remaining budget falls below this
const GAUSS_CULL_DIST   := 1800.0   # cull the orb once it gets this far from the player ("too far to notice")
const GAUSS_LIFETIME    := 8.0      # s before despawn (generous backstop; damage/distance are the real culls)

const MUZZLE_OFFSET     := 22.0     # how far ahead of the ship centre shots spawn (px)

# ── Weapon acquisition (chest + pickups → up to 5 unique weapons; backs the 5-slot HUD) ──
const MAX_WEAPONS := 5                                  # HUD slot count / acquisition cap
const MAX_WEAPON_LEVEL := 5                             # per-weapon level cap (level-up upgrades)
const WEAPON_DMG_PER_LEVEL := 0.30                      # +30% damage per level, COMPOUNDING (×1.30^(level-1))
const CHEST_POOL  := ["gatling", "lasgun", "arc", "gauss"]   # the 4 "F12" weapons the start-of-run chest rolls from
# kind → inventory def_id (icon) + display label. Canonical map shared by the chest + slot HUD.
const WEAPON_INFO := {
	"gatling": {"def_id": "gatling_gun",  "label": "Gatling"},
	"lasgun":  {"def_id": "lasgun",       "label": "Lasgun"},
	"arc":     {"def_id": "arc",          "label": "Arc"},
	"gauss":   {"def_id": "gauss_cannon", "label": "Gauss"},
	"orbital": {"def_id": "orbitals",     "label": "Orbital"},
	"void":    {"def_id": "rift_maker",   "label": "Void"},
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
}

# ── TUNABLES: Batch-1 weapons (Nuke / Sonic Wave / Z-Sword / Ionizing Field) ──────
# Nuke (Kinetic) — long-cooldown player-centred blast + auto knockback + lingering radiation slow zone.
const NUKE_COOLDOWN      := 7.0
const NUKE_DAMAGE        := 200.0
const NUKE_RADIUS        := 360.0
const NUKE_BLAST_STAGGER := 0.6      # blast freeze on hit
# Sonic Wave (Energy) — 3 expanding rings; each ring damages every enemy its front passes, once.
const SONIC_COOLDOWN     := 3.0
const SONIC_RINGS        := 3
const SONIC_RING_STAGGER := 0.18     # delay between successive rings of one volley
const SONIC_MAX_RADIUS   := 320.0
const SONIC_EXPAND_TIME  := 0.7
const SONIC_DAMAGE       := 30.0
const SONIC_BAND         := 24.0     # ring-front thickness for the hit test
const SONIC_COL          := Color(0.55, 0.85, 1.0)
# Z-Sword (Energy) — energy blade extends from the ship and sweeps a full circle.
const ZSWORD_COOLDOWN    := 4.0
const ZSWORD_SWEEP_TIME  := 0.6
const ZSWORD_LENGTH      := 220.0
const ZSWORD_ARC_HALF    := 0.314159 # ~18° half-arc hit tolerance
const ZSWORD_DAMAGE      := 45.0
const ZSWORD_STAGGER     := 0.1
const ZSWORD_COL         := Color(0.7, 1.0, 0.85)
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
const BOOM_SPIN       := 7.0        # visual self-spin rad/s (slowed from 18)
const BOOM_COL        := Color(0.95, 0.85, 0.5)
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
const SNAKE_TICK       := 0.2
const SNAKE_DAMAGE     := 8.0       # per tick per enemy in contact with any segment
const SNAKE_HIT_RADIUS := 22.0
const SNAKE_COL        := Color(1.0, 0.6, 0.3)

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
const VOID_RADIUS_MIN   := 40.0    # damage radius at placement (px)
const VOID_RADIUS_MAX   := 90.0    # damage radius at full growth (px)
const VOID_DAMAGE_MIN   := 20.0    # damage/SEC at placement (ramps)
const VOID_DAMAGE_MAX   := 195.0   # damage/SEC at full growth
const VOID_TICK         := 0.3     # s between damage ticks
const VOID_HIT_PAD      := 14.0    # enemy half-size pad added to the radius test
const VOID_VISUAL_SCALE := 1.1     # vortex draw diameter = (radius*2) * this (cover the damage zone)
const VOID_COL          := Color(0.7, 0.4, 1.0)   # void purple (pickup tint / dust light)

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

# ── TUNABLES: Lasgun (continuous tick-based beam — gained from a pickup, off until then) ──────────────────
const LASGUN_RANGE   := 1400.0   # beam length px
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
const ARC_LIFE     := 0.60     # s each lightning segment stays visible (dissolves start→end over this)
const ARC_FADE_SOFT := 0.35    # softness of the dissolve front sweeping from the muzzle to the strike point
const ARC_STAGGER  := 0.12     # s stagger per link
const ARC_COL      := Color(0.75, 0.9, 1.0)   # cold electric blue-white (soft outer glow)
const ARC_EDGE_COL := Color(0.45, 0.75, 1.0)  # light-blue rim drawn just outside the white-hot core
const ARC_LIGHT    := 4.0      # dust-light value per lit segment endpoint

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

# ── Gauss charge-up rings converging onto the ship (copied — visuals only) ────
const GC_START_RADIUS   := 150.0
const GC_RING_SIZE      := 13.0
const GC_COL_OUT        := Color(1.0, 0.30, 0.45)
const GC_COL_IN         := Color(1.0, 1.0, 0.95)
const GC_SPEED_EMPTY    := 130.0
const GC_SPEED_FULL     := 340.0
const GC_INTERVAL_EMPTY := 0.5
const GC_INTERVAL_FULL  := 0.05
const GC_RAMP_CURVE     := 1.6
const GC_SPAWN_COUNT    := 1
const GC_BRIGHT         := 0.9
const GC_FLASH_R        := 7.0
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
var _charge_rings: Array = []    # {ang, r}
var _charge_spawn_acc: float = 0.0
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
var _acquired: Array = []   # ordered list of acquired weapon kinds (max MAX_WEAPONS, unique) — backs the slot HUD
var _levels: Dictionary = {}   # kind → level (1..MAX_WEAPON_LEVEL); set on acquire, raised by level_up_weapon
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
var _arcs: Array = []              # live lightning segments: {a, b, age, max_age}
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
# ── Batch-1 weapons (Nuke / Sonic Wave / Z-Sword / Ionizing Field) ──
var _nuke_active: bool = false
var _nuke_cd: float = 0.0
var _sonic_active: bool = false
var _sonic_cd: float = 0.0
var _sonic_queue: float = 0.0          # stagger timer for the remaining rings of a volley
var _sonic_left: int = 0               # rings still to spawn in the current volley
var _sonic_rings: Array = []           # live rings: {center, age, hit:Array, maxr}
var _zsword_active: bool = false
var _zsword_cd: float = 0.0
var _zsword_sweeping: bool = false
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
	_charge_fx = OrbChargeScript.new()
	add_child(_charge_fx)
	_gat_muzzle_fx = GatMuzzleScript.new()
	add_child(_gat_muzzle_fx)
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
	if _orbital_active and _player != null and is_instance_valid(_player):
		for c: Vector2 in _orbital_positions():
			lights.append({"pos": c, "value": ORBITAL_LIGHT, "color": ORBITAL_COL})
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
	if _snake_active and not _snake_pts.is_empty():
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
		_gat_acc += delta
		if enemy_on_screen:
			var gat_interval := GAT_FIRE_INTERVAL / _rate_mult
			while _gat_acc >= gat_interval:
				_gat_acc -= gat_interval
				_fire_gatling()
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
	_update_charge_rings(delta)
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
func _fire_gatling() -> void:
	# Two parallel streams from the left/right wing muzzles. Offsets are in the ship's local frame (fwd/perp),
	# so they rotate with the aim. Both fire in the facing direction (not converging) → twin wing guns.
	var fwd := _forward()
	var perp := Vector2(-fwd.y, fwd.x)   # right-perpendicular (rotates with the ship)
	var base := _player.global_position + fwd * GAT_WING_FWD
	for side: float in [-1.0, 1.0]:
		var dir := fwd
		if GAT_SPREAD_DEG > 0.0:
			dir = fwd.rotated(deg_to_rad(randf_range(-GAT_SPREAD_DEG, GAT_SPREAD_DEG)))   # independent per-stream spray
		var start: Vector2 = base + perp * (side * GAT_WING_SPACING * 0.5)
		_bullets.append({"pos": start, "vel": dir * GAT_SPEED, "life": 0.0, "start": start})
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
	# Nearest enemy along the beam line (distance-to-line within range), like the legacy first-hit beam.
	var best_along := LASGUN_RANGE
	var best: Node = null
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var to_e: Vector2 = (en as Node2D).global_position - from
		var along := to_e.dot(dir)
		if along < 0.0 or along > LASGUN_RANGE:
			continue
		var perp_d := (to_e - dir * along).length()
		var _en_r3 = en.get("hit_radius")
		var _las_hit_w: float = LASGUN_WIDTH * 0.5 + (float(_en_r3) if _en_r3 != null else LASGUN_HIT_PAD)
		if perp_d <= _las_hit_w and along < best_along:
			best_along = along
			best = en
	var hit := best != null
	var end_along: float = (best_along - LASGUN_HIT_PAD) if hit else LASGUN_RANGE   # terminate at the surface
	# Keep a non-degenerate end point even at point-blank so the beam VFX retains a valid direction and can
	# apply its own min-length floor (damage still uses the actual target, not this visual end).
	var to_pt := from + dir * maxf(2.0, end_along)
	if _beam != null:
		_beam.set_beam(from, to_pt, true, hit)
	# Cast light along the beam onto the dust (rainbow hue tracks the beam).
	_beam_light_on = true
	_beam_light_from = from
	_beam_light_to = to_pt
	_beam_light_col = Color.from_hsv(fposmod(_las_t * 0.5, 1.0), 0.7, 1.0)
	# Tick damage (one apply per interval → no per-frame double-hit; damage_mult + fire_rate_mult both apply).
	_beam_cd -= delta
	if _beam_cd <= 0.0:
		if hit and best.has_method("take_damage"):
			var _las_r := _roll_damage(LASGUN_DAMAGE, "lasgun")
			best.take_damage(float(_las_r["dmg"]), LASGUN_STAGGER)
			if bool(_las_r["is_crit"]):
				_spawn_crit_number((best as Node2D).global_position, float(_las_r["dmg"]))
		_beam_cd = LASGUN_TICK / _rate_mult

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
func _fire_arc(delta: float) -> void:
	_arc_cd -= delta
	if _arc_cd > 0.0:
		return
	_arc_cd = ARC_COOLDOWN / _rate_mult
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
			var _arc_r := _roll_damage(ARC_DAMAGE, "arc")
			cur.take_damage(float(_arc_r["dmg"]), ARC_STAGGER)
			if bool(_arc_r["is_crit"]):
				_spawn_crit_number(c, float(_arc_r["dmg"]))
		chain.append(c)
		hit_set.append(cur)
		cur = _nearest_enemy(c, ARC_RANGE, hit_set)
	if chain.size() < 2:
		return
	# Pass 2: each link stores its span [u0,u1] of the TOTAL chain length, so a single dissolve front sweeps
	# the whole bolt from the ORIGINAL muzzle outward — it does not restart the fade at each bounce point.
	var seglen := PackedFloat32Array()
	var total := 0.0
	for i in range(chain.size() - 1):
		var l := chain[i].distance_to(chain[i + 1])
		seglen.append(l)
		total += l
	total = maxf(0.001, total)
	var acc := 0.0
	for i in range(chain.size() - 1):
		var u0 := acc / total
		acc += seglen[i]
		var u1 := acc / total
		var paths := _build_arc_paths(chain[i], chain[i + 1])   # shapes fixed once → no per-frame fluctuation
		_arcs.append({"pts": paths[0], "pts2": paths[1], "pts3": paths[2], "tip": chain[i + 1],
			"u0": u0, "u1": u1, "age": 0.0, "max_age": ARC_LIFE})

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

## Age out lightning segments; alpha is computed at draw time from age/max_age.
func _tick_arcs(delta: float) -> void:
	var i := _arcs.size() - 1
	while i >= 0:
		var a: Dictionary = _arcs[i]
		a["age"] = float(a["age"]) + delta
		if float(a["age"]) >= float(a["max_age"]):
			_arcs.remove_at(i)
		else:
			_arcs[i] = a
		i -= 1

## Build the (fixed) bolt geometry for a→b: a single gentle bow toward the target plus a small FIXED ripple,
## so the bolt "arcs slightly" but never fluctuates frame-to-frame. Returns [main_path, companion_path].
func _build_arc_paths(a: Vector2, b: Vector2) -> Array:
	var segs := 12
	var seg := b - a
	var dist := seg.length()
	var perp := seg.normalized().rotated(PI * 0.5) if dist > 0.01 else Vector2.UP
	var bow := perp * randf_range(-1.0, 1.0) * clampf(dist * 0.07, 6.0, 28.0)   # gentle shared arc, chosen once
	var zig := clampf(dist * 0.02, 1.5, 5.0) * 1.4     # main zigzag amplitude (40% rougher than before)
	var zig_c := zig * 0.6                              # secondary-strand zigzag — smaller (not too much)
	var off := perp * 4.0                               # companion sits a little to one side of the main line
	var off3 := perp * -4.0                             # third strand to the other side
	var pts := PackedVector2Array()
	var pts2 := PackedVector2Array()
	var pts3 := PackedVector2Array()
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var arc := a.lerp(b, u) + bow * sin(u * PI)     # shared bow → all strands track the same direction
		# Main: rough zigzag = a tighter sine ripple + a random kink (both FIXED at spawn → no fluctuation).
		var pm := arc + perp * sin(u * PI * 4.0) * zig + perp * randf_range(-1.0, 1.0) * zig * 0.6
		pts.append(pm)
		# Companion: same general direction, kept near the main line, but with its OWN modest random noise.
		var pc := arc + off + perp * sin(u * PI * 5.0) * zig_c * 0.5 + perp * randf_range(-1.0, 1.0) * zig_c
		pts2.append(pc)
		# Third strand: same idea (similar math), other side, its own noise.
		var pc3 := arc + off3 + perp * sin(u * PI * 6.0) * zig_c * 0.4 + perp * randf_range(-1.0, 1.0) * zig_c * 0.9
		pts3.append(pc3)
	# Anchor every strand's endpoints exactly to muzzle/target for a clean attach (no floating ends).
	pts[0] = a; pts[pts.size() - 1] = b
	pts2[0] = a; pts2[pts2.size() - 1] = b
	pts3[0] = a; pts3[pts3.size() - 1] = b
	return [pts, pts2, pts3]

## Draw one stored chain link. All three strands dissolve along the SAME global front that sweeps the whole
## bolt from the original muzzle (each link maps its vertices into its [u0,u1] span of the chain).
func _draw_arc(d: Dictionary) -> void:
	var life: float = clampf(float(d["age"]) / float(d["max_age"]), 0.0, 1.0)
	var u0: float = d["u0"]
	var u1: float = d["u1"]
	_draw_bolt(d["pts"], 1.0, life, u0, u1)            # main line
	_draw_bolt(d["pts2"], 0.3, life, u0, u1)           # companion (0.3× width)
	_draw_bolt(d["pts3"], 1.0 / 6.0, life, u0, u1)     # third strand (1/6× width)
	# Strike-point burst — fades when the global dissolve front reaches this link's end (u1).
	var front := life * (1.0 + ARC_FADE_SOFT) - ARC_FADE_SOFT
	var tipv := clampf((u1 - front) / ARC_FADE_SOFT, 0.0, 1.0)
	var tip: Vector2 = d["tip"]
	draw_circle(tip, 9.0, Color(ARC_COL.r, ARC_COL.g, ARC_COL.b, 0.30 * tipv))
	draw_circle(tip, 4.0, Color(1, 1, 1, 0.85 * tipv))

## A thick, glowing bolt along `pts`, widths × `wscale`: soft outer glow → light-blue edge → white-hot core.
## Per-vertex alpha dissolves along the GLOBAL chain parameter (vertex u mapped into [u0,u1]) so the muzzle
## end fades first and the front sweeps toward the far tip — "first spawned, first faded".
func _draw_bolt(pts: PackedVector2Array, wscale: float, life: float, u0: float, u1: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var front := life * (1.0 + ARC_FADE_SOFT) - ARC_FADE_SOFT
	var vis := PackedFloat32Array()
	for i in n:
		var gu := lerpf(u0, u1, float(i) / float(n - 1))   # this vertex's position along the WHOLE chain
		vis.append(clampf((gu - front) / ARC_FADE_SOFT, 0.0, 1.0))
	# Soft outer glow (ARC_COL).
	var widths := [20.0, 11.0]
	var alphas := [0.16, 0.35]
	for li in widths.size():
		var cols := PackedColorArray()
		for i in n:
			cols.append(Color(ARC_COL.r, ARC_COL.g, ARC_COL.b, float(alphas[li]) * vis[i]))
		draw_polyline_colors(pts, cols, float(widths[li]) * wscale)
	# Light-blue edge, then white-hot core on top → white centre with a light-blue rim.
	var edge := PackedColorArray()
	var core := PackedColorArray()
	for i in n:
		edge.append(Color(ARC_EDGE_COL.r, ARC_EDGE_COL.g, ARC_EDGE_COL.b, 0.9 * vis[i]))
		core.append(Color(1, 1, 1, 0.95 * vis[i]))
	draw_polyline_colors(pts, edge, 5.5 * wscale)
	draw_polyline_colors(pts, core, 2.8 * wscale)

## Called by the Arc pickup on collection — adds chain lightning to the active loadout (accumulates).
func activate_arc() -> void:
	_arc_active = true
	_arc_cd = 0.0   # fire on the next frame

## Called by the Red X pickup — turn on the X-shaped fire detonation.
func activate_red_x() -> void:
	_red_x_active = true
	_red_x_cd = 0.0   # fire as soon as an enemy is visible

## One Red X detonation: damage everything along the 4 diagonal arms (ported from arena_loadout._fire_cross,
## using System-2 _roll_damage), then play the pooled X fire-flash.
func _fire_red_x() -> void:
	var center := _player.global_position
	var arm_half := deg_to_rad(RED_X_ARM_HALF_DEG)
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
		var a := fposmod(off.angle(), PI / 2.0)        # fold into 4-fold symmetry
		var d_to_diag := absf(a - PI / 4.0)            # 0 on a diagonal, PI/4 on an axis
		if d_to_diag <= arm_half:
			if en.has_method("take_damage"):
				var r := _roll_damage(RED_X_DAMAGE, "red_x")
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number(ep, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		if center.distance_to((ruin as Node2D).global_position) <= RED_X_REACH:
			if ruin.has_method("take_damage"):
				ruin.take_damage(RED_X_DAMAGE * _dmg_mult * _lvl_mult("red_x"))
	_spawn_red_x_fire(center, RED_X_REACH)

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
	# Move + age + expire.
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
		_chemtrail_dot_tick()
	# Visual: feed all live puff centres to the single recolored toxic-fire emitter.
	_update_chemtrail_fx()

## One DoT tick: every enemy inside ANY puff takes CHEMTRAIL_TICK_DAMAGE once (single coverage check → no
## stacking on overlap). Scales via _roll_damage (damage-mult + crit) like the other System-2 weapons.
func _chemtrail_dot_tick() -> void:
	if _chemtrail_puffs.is_empty():
		return
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		if _chemtrail_covers(ep) and en.has_method("take_damage"):
			var r := _roll_damage(CHEMTRAIL_TICK_DAMAGE, "chemtrail")
			en.take_damage(float(r["dmg"]), 0.0)
			if bool(r["is_crit"]):
				_spawn_crit_number(ep, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		if _chemtrail_covers((ruin as Node2D).global_position) and ruin.has_method("take_damage"):
			ruin.take_damage(CHEMTRAIL_TICK_DAMAGE * _dmg_mult * _lvl_mult("chemtrail"))

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

## Called by the Void pickup — adds the auto-casting void gun to the loadout (accumulates).
func activate_void() -> void:
	_void_active = true
	_void_cd = 0.0   # cast on the next available enemy

# ── Void gun (Rift Maker): every VOID_COOLDOWN s, tear a growing void on the nearest enemy for VOID_DURATION s ──
func _tick_void(delta: float) -> void:
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
					_void_node.visible = true
		return
	_void_age += delta
	if _void_age >= VOID_DURATION:
		_void_on = false
		if _void_node != null:
			_void_node.visible = false
		return
	var f := clampf(_void_age / VOID_RAMP, 0.0, 1.0)
	var radius := lerpf(VOID_RADIUS_MIN, VOID_RADIUS_MAX, f)
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
					var _orb_r := _roll_damage(_orbital_damage, "orbital")
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
						ruin.take_damage(_orbital_damage * _dmg_mult * _lvl_mult("orbital"))
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
## Raise an owned weapon's level by one (capped). No-op for un-owned weapons.
func level_up_weapon(kind: String) -> void:
	if kind in _acquired:
		_levels[kind] = mini(MAX_WEAPON_LEVEL, int(_levels.get(kind, 1)) + 1)

func weapon_level(kind: String) -> int:
	return int(_levels.get(kind, 1)) if kind in _acquired else 0

func weapon_can_upgrade(kind: String) -> bool:
	return kind in _acquired and int(_levels.get(kind, 1)) < MAX_WEAPON_LEVEL

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

## Cooldown/charge readiness for the slot HUD: 1.0 = ready (no mask), 0..1 = recovering (mask covers 1-frac).
func weapon_cooldown_frac(kind: String) -> float:
	var rate := maxf(0.01, _rate_mult)
	match kind:
		"gatling", "orbital", "chemtrail", "ionize", "moroboshi", "swarm", "snake", "boomerang":
			return 1.0   # continuous stream / always-on passive or familiar → never masked
		"gauss":
			return clampf(_gauss_charge / maxf(0.01, GAUSS_CHARGE_TIME / rate), 0.0, 1.0)
		"arc":
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
			for en in enemies:
				if not is_instance_valid(en):
					continue
				var _en_r = en.get("hit_radius")
				var _hit_r: float = float(_en_r) if _en_r != null else GAT_HIT_RADIUS
				if p.distance_to((en as Node2D).global_position) <= _hit_r:
					if en.has_method("take_damage"):
						var _gat_r := _roll_damage(GAT_DAMAGE, "gatling")
						en.take_damage(float(_gat_r["dmg"]), GAT_STAGGER)
						if bool(_gat_r["is_crit"]):
							_spawn_crit_number(p, float(_gat_r["dmg"]))
					dead = true
					if _bolt_hit_player != null:
						_bolt_hit_player.stream = SFX_BOLT_HIT[randi() % SFX_BOLT_HIT.size()]
						_bolt_hit_player.play()
					break
			if not dead:
				for ruin in ruins:
					if not is_instance_valid(ruin): continue
					var ruin_r: float = ruin.get("hit_radius") if ruin.get("hit_radius") != null else GAT_HIT_RADIUS
					if p.distance_to((ruin as Node2D).global_position) <= ruin_r:
						if ruin.has_method("take_damage"):
							ruin.take_damage(GAT_DAMAGE * _dmg_mult * _lvl_mult("gatling"))
						dead = true
						if _bolt_hit_player != null:
							_bolt_hit_player.stream = SFX_BOLT_HIT[randi() % SFX_BOLT_HIT.size()]
							_bolt_hit_player.play()
						break
		if dead:
			_bullets.remove_at(i)
		i -= 1

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
	# Clear the converging rings and pop the release flash (charge cycle restarts).
	_charge_rings.clear()
	_charge_spawn_acc = 0.0
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
func _spawn_gauss_explosion(pos: Vector2) -> void:
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
	# tick_acc seeded to one full interval so the first DoT tick lands on the spawn frame (damage field
	# is active "the instant the explosion spawns" per spec).
	var e := {"pos": pos, "age": 0.0, "variant": variant, "node": fx, "tick_acc": GAUSS_TICK_INTERVAL}
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
			_gauss_explosion_tick(e["pos"])
		i -= 1

## One DoT tick: GAUSS_TICK_DAMAGE scaled by the damage stat (+ crit) to every enemy in radius, plus ruins.
## Same enumeration + damage call + crit-number path as the orbital/void AoE weapons.
func _gauss_explosion_tick(center: Vector2) -> void:
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= GAUSS_EXPL_RADIUS + GAUSS_EXPL_HIT_PAD:
			if en.has_method("take_damage"):
				var r := _roll_damage(GAUSS_TICK_DAMAGE, "gauss")
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		var ruin_r: float = GAUSS_EXPL_RADIUS + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
		if center.distance_to((ruin as Node2D).global_position) <= ruin_r:
			if ruin.has_method("take_damage"):
				ruin.take_damage(GAUSS_TICK_DAMAGE * _dmg_mult * _lvl_mult("gauss"))

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

# ── Gauss charge rings (auto-charge: charging is always true between shots) ────
func _update_charge_rings(delta: float) -> void:
	if not _gauss_active:
		return
	var frac := clampf(_gauss_charge / maxf(0.01, GAUSS_CHARGE_TIME), 0.0, 1.0)
	var focal := _muzzle()
	var interval := lerpf(GC_INTERVAL_EMPTY, GC_INTERVAL_FULL, pow(frac, GC_RAMP_CURVE))
	_charge_spawn_acc += delta
	while _charge_spawn_acc >= interval:
		_charge_spawn_acc -= interval
		for _k in GC_SPAWN_COUNT:
			_charge_rings.append({"ang": randf() * TAU, "r": GC_START_RADIUS * randf_range(0.85, 1.12)})
	var spd := lerpf(GC_SPEED_EMPTY, GC_SPEED_FULL, frac)
	var i := _charge_rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _charge_rings[i]
		ring["r"] = float(ring["r"]) - spd * delta
		if float(ring["r"]) <= GC_FLASH_R:
			_flashes.append({"pos": focal, "age": 0.0, "max_age": 0.16, "radius": GC_FLASH_R * 2.2})
			_charge_rings.remove_at(i)
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

func _fire_nuke() -> void:
	var center := _player.global_position
	var reach := _aoe_radius(NUKE_RADIUS)
	# Single big blast — knockback is automatic in take_damage (pushed away from the player). No lingering zone.
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		if center.distance_to(ep) <= reach:
			if en.has_method("take_damage"):
				var r := _roll_damage(NUKE_DAMAGE, "nuke")
				en.take_damage(float(r["dmg"]), NUKE_BLAST_STAGGER)
				if bool(r["is_crit"]):
					_spawn_crit_number(ep, float(r["dmg"]))
	for ruin in get_tree().get_nodes_in_group("arena_ruin"):
		if not is_instance_valid(ruin):
			continue
		if center.distance_to((ruin as Node2D).global_position) <= reach:
			if ruin.has_method("take_damage"):
				ruin.take_damage(NUKE_DAMAGE * _dmg_mult * _lvl_mult("nuke"))
	# Composite blast VFX, sized to the blast radius. Overrides (set before add_child so _ready picks them up):
	#  • time_scale ÷3        → the whole explosion lasts 3× longer (every frame + every stagger gap ×3)
	#  • shockwave radius ×3  → the ripple travels 3× further
	#  • shockwave travel ×2  → net HALF the expansion speed (×3 distance ÷ ×6 time, given the 3× global slow-mo)
	var ex := ExplosionFX.new()
	ex.time_scale = ex.time_scale / 3.0
	ex.shockwave_max_radius = ex.shockwave_max_radius * 3.0
	ex.shockwave_travel = ex.shockwave_travel * 2.0
	get_parent().add_child(ex)
	ex.call("setup", center, reach)

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
		for en in get_tree().get_nodes_in_group("arena_enemy"):
			if not is_instance_valid(en) or en in hit:
				continue
			var d := center.distance_to((en as Node2D).global_position)
			if absf(d - r) <= SONIC_BAND:
				if en.has_method("take_damage"):
					var rr := _roll_damage(SONIC_DAMAGE, "sonic")
					en.take_damage(float(rr["dmg"]), 0.0)
					if bool(rr["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(rr["dmg"]))
				hit.append(en)
		i -= 1

func _spawn_sonic_ring() -> void:
	_sonic_rings.append({"center": _player.global_position, "age": 0.0, "hit": [], "maxr": _aoe_radius(SONIC_MAX_RADIUS)})

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
		return
	var blade_ang := _zsword_start + TAU * (_zsword_t / ZSWORD_SWEEP_TIME)
	var reach := _aoe_radius(ZSWORD_LENGTH)
	var center := _player.global_position
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
	draw_arc(c, r, 0.0, TAU, 72, Color(SONIC_COL.r, SONIC_COL.g, SONIC_COL.b, 0.85 * a), 5.0, true)
	draw_arc(c, r, 0.0, TAU, 72, Color(SONIC_COL.r, SONIC_COL.g, SONIC_COL.b, 0.30 * a), 12.0, true)

func _draw_zsword() -> void:
	var blade_ang := _zsword_start + TAU * (_zsword_t / ZSWORD_SWEEP_TIME)
	var reach := _aoe_radius(ZSWORD_LENGTH)
	var center := _player.global_position
	var tip := center + Vector2(cos(blade_ang), sin(blade_ang)) * reach
	draw_line(center, tip, Color(ZSWORD_COL.r, ZSWORD_COL.g, ZSWORD_COL.b, 0.25), 14.0, true)
	draw_line(center, tip, Color(ZSWORD_COL.r, ZSWORD_COL.g, ZSWORD_COL.b, 0.6), 6.0, true)
	draw_line(center, tip, Color(1, 1, 1, 0.9), 2.0, true)
	draw_arc(center, reach, blade_ang - 0.5, blade_ang, 16, Color(ZSWORD_COL.r, ZSWORD_COL.g, ZSWORD_COL.b, 0.18), 4.0, true)

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
	var tgt := _nearest_enemy(head, INF, [])
	var desired := _snake_dir
	if tgt != null:
		desired = ((tgt as Node2D).global_position - head).angle()
	else:
		desired = (head - _player.global_position).angle() + PI * 0.5   # idle: circle the ship
	_snake_dir = _approach_angle(_snake_dir, desired, SNAKE_TURN * delta)
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
						var r := _roll_damage(SNAKE_DAMAGE, "snake")
						en.take_damage(float(r["dmg"]), 0.0)
					break

# ── Batch-2 draw helpers ────────────────────────────────────────────────────────────
func _draw_boomerang(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var s := float(b["spin"])
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

func _draw() -> void:
	# Charge rings + comet trails + sparks draw UNDER the orb ColorRect children.
	_draw_charge_rings()
	for o: Dictionary in _orbs:
		_draw_gauss_trail(o)
	_draw_sparks()
	for b: Dictionary in _bullets:
		_draw_tracer(b["pos"], b["vel"])
	# Arc chain lightning — each stored bolt fades from the outside in over its lifetime.
	for a: Dictionary in _arcs:
		_draw_arc(a)
	if _orbital_active:
		_draw_orbital()
	for sring: Dictionary in _sonic_rings:
		_draw_sonic_ring(sring)
	if _zsword_sweeping:
		_draw_zsword()
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
	if _snake_active:
		_draw_snake()
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

func _draw_charge_rings() -> void:
	if _charge_rings.is_empty():
		return
	var focal := _muzzle()
	for ring: Dictionary in _charge_rings:
		var r: float = ring["r"]
		var t := clampf(1.0 - r / GC_START_RADIUS, 0.0, 1.0)
		var pos := focal + Vector2(cos(float(ring["ang"])), sin(float(ring["ang"]))) * r
		var col := GC_COL_OUT.lerp(GC_COL_IN, t)
		var a := GC_BRIGHT * (0.12 + 0.88 * t)
		var rs := GC_RING_SIZE * (0.3 + 0.7 * (1.0 - t))
		draw_arc(pos, rs * 2.4, 0.0, TAU, 16, Color(col.r, col.g, col.b, a * 0.05), 3.0, true)
		draw_arc(pos, rs * 1.7, 0.0, TAU, 16, Color(col.r, col.g, col.b, a * 0.14), 2.5, true)
		draw_arc(pos, rs * 1.2, 0.0, TAU, 16, Color(col.r, col.g, col.b, a * 0.28), 2.0, true)
		draw_arc(pos, rs, 0.0, TAU, 16, Color(col.r, col.g, col.b, a), 2.0, true)
		draw_circle(pos, rs * 0.35, Color(col.r, col.g, col.b, a * 0.5))

func _draw_flashes() -> void:
	for f: Dictionary in _flashes:
		var t := clampf(1.0 - float(f["age"]) / maxf(0.01, float(f["max_age"])), 0.0, 1.0)
		var pos: Vector2 = f["pos"]
		var r := float(f["radius"]) * (0.4 + 0.6 * (1.0 - t))   # expands as it fades
		draw_circle(pos, r, Color(0.7, 0.85, 1.0, 0.25 * t))
		draw_circle(pos, r * 0.5, Color(1.0, 1.0, 1.0, 0.5 * t))
