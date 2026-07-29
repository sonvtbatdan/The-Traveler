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
const GAT_DAMAGE        := 5.0      # per hit (base -1)
const GAT_LIFETIME      := 1.2      # s before despawn
const GAT_MAX_DIST      := 1300.0   # px travelled before despawn
const GAT_HIT_RADIUS    := 24.0     # bullet↔enemy hit distance (px) — fallback when an enemy has no hit_radius
const GAT_BULLET_HIT_R  := 10.0     # the bullet's OWN collision radius (added to the enemy radius); slightly bigger than the sprite (glow half-width ≈ 7px) so it hits on visual contact
const GAT_SPREAD_DEG    := 0.0      # ± random spray on each shot (0 = laser-straight; base Gatling now stable)
const GAT_STAGGER       := 0.1      # s the enemy is staggered (movement/attacks frozen) per Gatling hit
const GAT_LIGHT         := 1.0      # dust-light "value" per Gatling bullet (low → lights up nearby dust only)
const GAT_WING_SPACING  := 26.0     # px between the two wing muzzles (twin parallel streams)
const GAT_FIRE_STAGGER  := 0.2      # s the RIGHT-wing bullet(s) fire AFTER their left-wing partner (twin-barrel stagger)
const GAT_WING_FWD      := 22.0     # forward offset of the wing muzzles from ship centre (px)
const GAT_MUZZLE_DECAY  := 0.08     # s the muzzle-fire flash decays over (refreshed each shot → ~continuous while firing)

# ── Gatling skill-point upgrade pool (each invested point picks 1 of 3 → +1 rank). Level rewards are derived
# from the weapon's LEVEL (see _gat_* effective-stat helpers). The level-up UI's 2nd tier rolls 3 of these. ──
## All gatling perks are UNCAPPED (max 0) — pick rate is limited by the level-gate roll, not a rank ceiling
## (bouncing: at most once per 3 weapon levels; every other perk: once per 2 levels — see _perk_offer_allowed).
const GATLING_POOL := {
	"hardened":  {"name": "Hardened Round",  "max": 0, "per": "+2 flat damage",        "desc": "Bullets hit harder."},
	"piercing":  {"name": "Piercing Round",  "max": 0, "per": "+20% pierce chance, +10% damage", "desc": "Bullets pass through enemies and hit harder."},
	"quick":     {"name": "Quick Round",     "max": 0, "per": "+16% fire rate",        "desc": "Shoot faster."},
	"bouncing":  {"name": "Bouncing Round",  "max": 0, "per": "+1 bounce",             "desc": "Bullets ricochet to nearby foes (1 extra ricochet per rank)."},
	"multishot": {"name": "Multishot",       "max": 0, "per": "+25% multishot",        "desc": "Extra bullets — every 100% is one guaranteed extra (triple shot and beyond)."},
	"advance_ballistic": {"name": "Advance Ballistic", "max": 0, "per": "+10% multishot (all shots weapons)", "desc": "Global: every weapon with the 'shots' tag gains multishot chance."},
}
const GAT_BOUNCE_RANGE := 280.0    # search radius for a bounce target
const GAT_HEAL_ODDS    := 200      # Healing Round capstone: 1-in-N directly-fired bullets heals
const GAT_HEAL_AMOUNT  := 5        # HP healed (player + target) by a healing bullet
const GAT_FOCUS_STEP   := 0.005    # Focus Fire capstone: +0.5% gatling dmg per consecutive hit on the same target
const GAT_FOCUS_MAX    := 1.0      # … capped at +100%
# Bismuth anti-magnetic: a gatling bullet hitting an anti-magnetic enemy may bounce back at the player.
const GAT_REFLECT_FRAC := 0.5      # fraction of gatling bullets reflected (50%)
const GAT_REFLECT_DMG  := 5        # damage a reflected bullet does to the player
const GAT_REFLECT_PAD  := 12.0     # extra hit padding when a reflected bullet meets the player

# ── TUNABLES: Gauss cannon (auto-charge → heavy piercing orb) ─────────────────
const GAUSS_ENABLED     := false    # disabled for now
const GAUSS_STAGGER     := 0.35     # s the enemy is staggered per Gauss hit (heavier weapon = more)
const GAUSS_LIGHT       := 5.0      # dust-light "value" per Gauss orb (heavy → big bright light)
const GAUSS_USE_SPRITE_VFX := false  # true → fall back to the original hand-drawn flipbook orb/explosion art
									 # instead of the procedural gauss_orb_fx shader. Kept side-by-side, same
									 # convention as the Lasgun's lasgun_ani_1.gd sprite backup.
const GAUSS_CHARGE_TIME := 1.4      # s to fully charge between shots (drives the charge-meter fraction)
const GAUSS_SPEED       := 520.0    # px/s (heavy + slow so you watch it plough through)
const GAUSS_DAMAGE      := 55.0     # per-shot DAMAGE BUDGET the orb carries (× damage-mult at fire)
const GAUSS_RADIUS      := 30.0     # FULL hit radius (at full budget); shrinks ∝ sqrt(damage)
const GAUSS_ORB_HIT_PAD := 16.0     # orb's own collision pad added to the enemy/ruin radius (200% of the
									 # original 8px — invisible, purely a hit-test radius, no visual change —
									 # makes the projectile noticeably easier to land against moving enemies)
const GAUSS_MIN_DMG     := 1.0      # cull the orb once its remaining budget falls below this
const GAUSS_CULL_DIST   := 1800.0   # cull the orb once it gets this far from the player ("too far to notice")
const GAUSS_LIFETIME    := 8.0      # s before despawn (generous backstop; damage/distance are the real culls)
# ── Gauss skill-point pool. Burn/stun are SEPARATE per-weapon stats (own names) but share the enemy status. ──
const GAUSS_POOL := {
	"aoe_mastery": {"name": "AoE Mastery",  "max": 5,  "per": "+5% area (global)",  "desc": "Bigger blasts for ALL area weapons."},
	"damage":      {"name": "Amplify",      "max": 10, "per": "+10% damage",        "desc": "Heavier orbs + DoT."},
	"cooldown":    {"name": "Rapid Charge", "max": 10, "per": "+8% fire rate",      "desc": "Charge faster."},
	"meltdown":    {"name": "Meltdown",     "max": 5,  "per": "+5% burn chance",    "desc": "Orbs ignite enemies (Gauss burn)."},
	"emp":         {"name": "EMP Burst",    "max": 5,  "per": "+5% stun chance",    "desc": "Orbs stun enemies (Gauss electrocute)."},
	"fission":     {"name": "Fission",      "max": 10, "per": "+10% extra orb",     "desc": "Chance for an extra orb, spread to max angle (2→180°, 3→120°)."},
}
# ── Orbital skill-point pool. Contact Mastery is a GLOBAL contact-damage bonus (all contact weapons + the ship). ──
const ORBITAL_POOL := {
	"contact": {"name": "Contact Mastery", "max": 5,  "per": "+5% contact damage (global)", "desc": "Boosts ALL contact damage — orbitals, swarm, snake, boomerang, yari, and the ship hull."},
	"size":    {"name": "Bigger Orbs",     "max": 5,  "per": "+10% ball size",              "desc": "Larger balls (also scaled by AoE)."},
	"damage":  {"name": "Heavy Orbs",      "max": 10, "per": "+10% damage",                 "desc": "Each ball hits harder."},
	"tighten": {"name": "Tight Orbit",     "max": 5,  "per": "-10% orbit distance",         "desc": "Balls hug the ship — faster sweeps, closer guard."},
	"spin":    {"name": "Overspin",        "max": 5,  "per": "+15% spin speed",             "desc": "Orbit faster."},
	"spin2":   {"name": "Flywheel",        "max": 10, "per": "+7% spin speed",              "desc": "Orbit a little faster."},
	"widen":   {"name": "Widen",           "max": 5,  "per": "+5% orbit distance, +7.5% damage", "desc": "Wider swings hit harder."},
}

const MUZZLE_OFFSET     := 22.0     # how far ahead of the ship centre shots spawn (px)

# ── Weapon acquisition (chest + pickups → up to 5 unique weapons; backs the 5-slot HUD) ──
const MAX_WEAPONS := 4                                  # HUD slot count / acquisition cap
const MAX_WEAPON_LEVEL := 18                            # weapon levels 1→18; each point spent = +1 level, then EVOLVE
const FUSION_MIN_LEVEL := 15                            # both components must be ≥ this (and un-evolved) to fuse
const WEAPON_DMG_PER_LEVEL := 0.30                      # FUSIONS ONLY: +30%/bonus-level (base weapons get no per-level damage)
const CHEST_POOL  := ["gatling_gun", "death_beam", "arc", "gauss"]   # the 4 "F12" weapons the start-of-run chest rolls from
# Canonical weapon registry shared by the chest + slot HUD + F12 palette. Per kind:
#   def_id = inventory icon source · name = full official name (matches ITEM_DEFS.name) ·
#   label = short in-game / spawn display name · mfr = manufacturer (lore "group").
# kind keys are wired across the fire engine — DO NOT rename them; only this metadata is editable.
# NOTE: ionize / parasite / homing / toxic_ballistic are NOT in the canonical design sheet yet (orphans) —
# kept with placeholder names until the sheet assigns them. See trace log 2026-06-27.
const WEAPON_INFO := {
	"gatling_gun":     {"def_id": "gatling_gun",     "name": "Gatling Gun",             "label": "Gatling Gun",      "mfr": "Vanguard Ballistics"},
	"death_beam":      {"def_id": "death_beam",          "name": "Death Beam",              "label": "Death Beam",   "mfr": "Kwang Ming"},
	"arc":         {"def_id": "arc",             "name": "Arc Lightning Chain",     "label": "Lightning",    "mfr": "Kwang Ming"},
	"gauss":       {"def_id": "gauss_cannon",    "name": "Gauss Pulser",            "label": "Gauss",        "mfr": "Horizon Logistics x Vanguard Ballistics"},
	"defensive_orbitals":     {"def_id": "orbitals",        "name": "Defensive Orbitals",      "label": "Defensive Orbitals",     "mfr": "Nebula Dynamics"},
	"striker":     {"def_id": "",  "icon": "res://assets/weaponry/ND-OIF-F.png", "name": "Striker",  "label": "Striker",  "mfr": "Nebula Dynamics"},
	"shooter":     {"def_id": "swarm_host",      "icon": "res://assets/weaponry/shooter.png", "name": "Shooter",      "label": "Shooter",      "mfr": "Nebula Dynamics"},
	"rift_maker":        {"def_id": "rift_maker",      "name": "Rift Maker",              "label": "Rift Maker",   "mfr": "Horizon Logistics"},
	"dragons_breath":       {"def_id": "red_x",           "name": "Dragon's Breath",         "label": "Dragon's Breath",        "mfr": "Volney Elements"},
	"chemtrail":   {"def_id": "chemtrail",       "name": "Chemtrail",               "label": "Chemtrail", "mfr": "Volney Elements"},
	"mortar":        {"def_id": "mortar",            "name": "Mortar",                  "label": "Mortar",       "mfr": "Rosastro"},
	"fat_boy":     {"def_id": "rosastro_nuclear","name": "Fat Boy",                 "label": "Fat Boy",      "mfr": "Rosastro"},
	"ultrasonicator":       {"def_id": "sonic_wave",      "name": "Ultrasonicator",          "label": "Ultrasonicator",        "mfr": "Yongsan"},
	"z_sword":      {"def_id": "z_sword",         "name": "Z-Sword",                 "label": "Z-Sword",       "mfr": "Eisenkraft Kinematik"},
	"ionizing_field":      {"def_id": "ionizing_field",  "name": "Ionizing Field",               "label": "Ionizing Field", "mfr": "Horizon Logistics"},
	"aliwa":   {"def_id": "boomerang",       "name": "Boomerang",                    "label": "Boomerang",    "mfr": "Nebula Dynamics"},
	"venomancer":    {"def_id": "parasite_cloud",  "name": "Venomancer",                   "label": "Venomancer",   "mfr": "Volney Elements x Chakra Bio-Synthetics"},
	"yari":   {"def_id": "moroboshi",       "name": "Yari",                    "label": "Yari",         "mfr": "Miyamoto"},
	"yari_jaeger": {"def_id": "yari_jaeger",     "name": "Yari Jeager",             "label": "Yari Jeager",  "mfr": "Miyamoto x Eisenkraft Kinematik"},
	"swarm":       {"def_id": "",                "icon": "res://assets/inventory/Swarm.png", "name": "Swarm", "label": "Swarm", "mfr": "Chakra Bio-Synthetics"},
	"viper":       {"def_id": "viper",     "name": "Viper",                   "label": "VIPER",        "mfr": ""},
	"homing_missile":      {"def_id": "homing_missile",  "name": "Homing Missile",          "label": "Homing",       "mfr": ""},
	"player_2":    {"def_id": "player_2",        "icon": "res://assets/screen/Spaceship.png", "name": "Player 2", "label": "Player 2", "mfr": "You (negative)"},
}
# ── Player 2 companion skill-point pool + evolves ──
const PLAYER2_POOL := {
	"damage":      {"name": "Overclock",              "max": 10, "per": "+5% damage",          "desc": "Player 2 hits harder (on top of its 25% copy)."},
	"kinetic":     {"name": "Kinetic Coat",           "max": 5,  "per": "+10% kinetic damage",  "desc": "Player 2 does +10%/rank when the copied weapon is kinetic."},
	"energy":      {"name": "Energy Coat",            "max": 5,  "per": "+10% energy damage",   "desc": "Player 2 does +10%/rank when the copied weapon is energy."},
	"biochemical": {"name": "Biochemical Coat",       "max": 5,  "per": "+10% bio damage",      "desc": "Player 2 does +10%/rank when the copied weapon is biochemical."},
	"proactive":   {"name": "Proactive Intelligence", "max": 3,  "per": "copy 1 more weapon",   "desc": "Player 2 also copies your next-highest weapon. Unlocks at weapon level 6 / 11 / 16.", "gate": [6, 11, 16]},
	"diversify":   {"name": "Diversification Mastery","max": 10, "per": "+1.25% dmg / weapon owned", "desc": "Player 2 gains +1.25%/rank overall damage for EACH different weapon you own."},
}
const PLAYER2_PHOENIX_CD := 600.0   # Project Phoenix: Player 2 stays shut down this long (s) after a revive
const P2_MIN_WEAPON_LEVEL := 10     # Player 2 is only offerable/acquirable once some OTHER weapon reaches this level

# ── Weapon FUSION recipes ─────────────────────────────────────────────────────────
# Keyed by the FUSED kind (matches _activate_kind / activate_<fused>). `a`+`b` = the two component kinds, each
# must be owned at MAX_WEAPON_LEVEL to fuse (see available_fusions). `def_id` = inventory icon shown in the F12
# palette + fusion cutscene reveal (reuses a component's icon as placeholder until dedicated fusion art lands).
# NOTE: values reconstructed from the fusion code (the const table was missing from the merged commit).
# name = full official name · label = spawn display · mfr = manufacturer · a+b = component kinds (recipe).
# def_id still reuses a component's icon as placeholder; dedicated fusion art (Overcharger/Singularities/
# Vampire Host PNGs exist) is wired in a later phase once their ITEM_DEFS entries are added.
const FUSION_DEFS := {
	"carnage":         {"a": "dragons_breath",   "b": "gatling_gun",   "def_id": "gatling_gun",   "name": "Thermitic Auto Cannon", "label": "Carnage",       "mfr": "Volney Elements x Vanguard Ballistics"},
	"vampire_host":    {"a": "ultrasonicator",   "b": "swarm",     "def_id": "offensive_orbitals",    "icon": "res://assets/inventory/Vampire Host.png", "name": "Vampire Host",          "label": "Vampire Host",  "mfr": "Nebula Dynamics x Yongsan"},
	"overcharger":     {"a": "arc",     "b": "gauss",     "def_id": "gauss",  "icon": "res://assets/inventory/Overcharger.png",  "name": "Overcharger",           "label": "Overcharger",   "mfr": "Kwang Ming x Horizon Logistics"},
	"predator":        {"a": "viper",   "b": "death_beam",    "def_id": "death_beam",        "name": "Predator",              "label": "Predator",      "mfr": ""},
	"toxic_ballistic": {"a": "homing_missile",  "b": "chemtrail", "def_id": "homing_missile","name": "Toxic Ballistic",       "label": "Toxic Ballistic","mfr": ""},
	"singularities":   {"a": "rift_maker",    "b": "gauss",     "def_id": "defensive_orbitals",      "icon": "res://assets/inventory/Singularities.png", "name": "Singularities",         "label": "Singularities", "mfr": "Horizon Logistics x Vanguard Ballistics"},
}

# ── Weapon LORE (English) ─────────────────────────────────────────────────────────────
# Flavour text shown on the Level-Up board's WeaponDisplay (Item Lore). Keyed by weapon/fusion KIND.
# Source: the weaponinfo sheet's English "Lore" column (NOT the Vietnamese tech description). Kinds not
# present here have no lore yet (the Item Lore text simply hides).
const WEAPON_LORE := {
	"gatling_gun":     "High-speed kinetic auto cannon, a standard military issue popular across the universe.",
	"death_beam":  "High-energy laser beam.",
	"arc":         "Chain lightning that strikes multiple targets sequentially.",
	"gauss":       "By locally expanding and contracting space, the G-Pulser generates molecular-level shear stress.",
	"defensive_orbitals":     "Automated UAV that rotates and rams into targets approaching the ship.",
	"striker":     "Automated UAV that tracks and rams into targets approaching the ship.",
	"shooter":     "Rear-guard turret pods that lock onto the nearest threat and fire concentrated bolt bursts.",
	"rift_maker":        "Weapon that triggers a localized Vacuum Decay state.",
	"dragons_breath":       "Turret equipped with 4 symmetrical 90-degree nozzles, simultaneously firing high-velocity liquid Thermite particle chains.",
	"chemtrail":   "Converts liquid biocidal toxic compounds into dense molecular biocide vapor streams, sprayed behind the ship.",
	"mortar":      "Heavy mortar specialized in destroying thick armor and fortified structures.",
	"fat_boy":     "Ultimate nuclear weapon with infinite destructive power.",
	"ultrasonicator":       "Emits sonic waves.",
	"z_sword":      "Melee weapon utilizing a complex sawtooth drive mechanism, sweeping and emitting a shockwave.",
	"aliwa":   "Throws a boomerang.",
	"venomancer":    "Genetically modified bio-spore launcher that corrodes the ultra-durable metal alloy layers of enemy ships.",
	"yari":   "Chase enemy and use melee weapon utilizing a pin-shot mechanism to fire a sharp spear at enemies.",
	"yari_jaeger": "Chase enemy and use melee weapon utilizing a complex sawtooth drive mechanism, sweeping and emitting a shockwave.",
	"swarm":       "A launcher shaped like a hollow bone-and-steel exo-skeleton sphere with 8 upward-facing holes. Capable of launching space bugs folded into spherical shapes.",
	"viper":       "V.I.P.E.R (Viral Infiltration & Penetration Exo-Rover): A peripheral autonomous rover for viral infiltration and penetration.",
	# Fusions
	"carnage":       "Continuously fires high-velocity liquid Thermite particle chains and bullets in 4 directions.",
	"vampire_host":  "Fires minor sonic waves; grants player lifesteal upon hitting targets.",
	"overcharger":   "Arc chain, triggers a Gauss explosion for each chained target.",
	"predator":      "A snake capable of firing lasers.",
	"singularities": "Creates an absolute vacuum combined with negative gravity.",
}
const FUSION_BONUS_LEVELS := 4   # fused weapons can climb this many levels past MAX_WEAPON_LEVEL (6 → 10)
# (Carnage / Vampire Host tunables are declared later in the file — the canonical OURS copies.)

# ── TUNABLES: Batch-1 weapons (Nuke / Sonic Wave / Z-Sword / Ionizing Field) ──────
# Mortar (Little Man, code "Mortar") + Fat Boy (Fat Boy): a mouse-aimed mortarbullet that flies
# straight and detonates an AoE explosion on the FIRST enemy it touches. Fat Boy = the full-size blast; Mortar
# fires the same bullet but its explosion is a 5% mini version.
const MORTAR_RADIUS         := 540.0    # full explosion footprint (Fat Boy) + the full-VFX size_px base
const MORTAR_BLAST_STAGGER  := 0.6      # stagger applied to enemies caught in the blast
const MORTAR_FIRE_INTERVAL := 1.0     # auto-fire cadence (1 bullet/sec, before fire-rate mult)
const MORTAR_BULLET_SPEED  := 700.0   # px/s, straight toward the mouse
const MORTAR_BULLET_LIFE   := 3.0     # s before an un-hit bullet is culled (no explosion on timeout)
const MORTAR_BULLET_LEN    := 28.0    # drawn bullet length (px); width derived from mortarbullet.png ratio
const MORTAR_DAMAGE        := 20.0    # Mortar AoE damage
const MORTAR_AOE           := 90.0    # Mortar blast radius (small)
const MORTAR_VFX_SCALE     := 0.01    # Mortar explosion = 1% of the full (Fat Boy) explosion (lite mode, 1.5× faster)
# ── Mortar skill-point pool ──
const MORTAR_POOL := {
	"damage":       {"name": "Bigger Payload",   "max": 10, "per": "+10% damage",                "desc": "Each shell hits harder."},
	"firerate":     {"name": "Rapid Reload",      "max": 10, "per": "+8% fire rate",              "desc": "Lob shells more often."},
	"aoe":          {"name": "Wider Blast",       "max": 10, "per": "+10% blast radius",          "desc": "A bigger explosion footprint."},
	"concentrated": {"name": "Concentrated Fire", "max": 5,  "per": "-10% AoE, +15% damage",      "desc": "Focus the blast: smaller radius, harder hit."},
	"kinetic":      {"name": "Kinetic Mastery",   "max": 5,  "per": "+5% kinetic damage (global)","desc": "Boosts all kinetic weapons."},
	"wasteland":    {"name": "Waste Land",        "max": 10, "per": "damaging + slowing crater",  "desc": "Each blast leaves a 3s crater: 20%/rank of the shot's damage over 3s + 25% slow. Craters stack."},
}
# Evolve capstones = multipliers on the base Mortar shot (Fusion Reactor instead deactivates it → passive core).
const FATBOY_DMG_MULT   := 6.0    # Fat Boy: +500% damage
const FATBOY_AOE_MULT   := 2.5    # Fat Boy: +150% AoE
const FATBOY_RATE_MULT  := 0.15   # Fat Boy: -85% fire rate
const LILMAN_DMG_MULT   := 0.5    # Little Man: -50% damage
const LILMAN_AOE_MULT   := 0.25   # Little Man: -75% AoE
const LILMAN_RATE_MULT  := 4.0    # Little Man: +300% fire rate
# Waste Land crater tuning.
const WASTELAND_DUR       := 3.0    # s each crater lasts
const WASTELAND_TICK      := 0.25   # s between crater damage ticks
const WASTELAND_SLOW      := 0.25   # fixed move-speed reduction inside a crater (does not scale with rank)
const WASTELAND_DMG_FRAC  := 0.20   # per rank: total crater damage over its life = frac × rank × the shot's damage
const WASTELAND_MAX_ZONES := 30     # leak guard (oldest crater is dropped past this)
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
const SONIC_POOL := {
	"damage": {"name": "Resonance",  "max": 10, "per": "+10% damage",      "desc": "Louder, harder-hitting waves."},
	"range":  {"name": "Far Cry",    "max": 5,  "per": "+15% range",       "desc": "Waves travel further."},
	"cd":     {"name": "Rapid Pulse", "max": 10, "per": "+8% fire rate",   "desc": "Pulse more often."},
	"cold":   {"name": "Cold Wave",  "max": 5,  "per": "+5% freeze chance", "desc": "Waves chill what they hit."},
	"cone":   {"name": "Wide Arc",   "max": 6,  "per": "+15° cone (×AoE)", "desc": "Fan the wave across a wider arc."},
}
# Z-Sword (Energy) — energy blade extends from the ship and sweeps a full circle.
const ZSWORD_COOLDOWN    := 4.0
const ZSWORD_SWEEP_TIME  := 0.6
const ZSWORD_LENGTH      := 220.0
const ZSWORD_ARC_HALF    := 0.314159 # ~18° half-arc hit tolerance
const ZSWORD_DAMAGE      := 45.0
const ZSWORD_STAGGER     := 0.1
const ZSWORD_POOL := {
	"damage":   {"name": "Honed Edge",     "max": 10, "per": "+10% damage",        "desc": "Sharper swings."},
	"size":     {"name": "Long Blade",     "max": 5,  "per": "+15% blade length",   "desc": "Reach further around the ship."},
	"cd":       {"name": "Quick Draw",     "max": 10, "per": "+8% swing rate",      "desc": "Swing more often."},
	"crit":     {"name": "Keen Point",     "max": 5,  "per": "+5% crit chance",     "desc": "Z-Sword crits more (this weapon only)."},
	"martial":  {"name": "Martial Mastery", "max": 10, "per": "+10% crit damage (global)", "desc": "Every weapon's crits hit harder."},
	"divergence": {"name": "Divergence Sword", "max": 6, "per": "+5% extra-swipe chance", "desc": "Each swing may trigger another (and those can chain too)."},
}
# (slash visuals live in scripts/gameplay/fx/z_slash.gd; colours are ZSlash.LEAD_COL/LEAD_HOT there)
# Ionizing Field — always-on aura DoT around the ship; visual = 2 EnergyVortex swirls
# (creep-edit VFX) over a Vacuum-style gravitational-lens that distorts the space background.
const IONIZE_TICK   := 0.3
const IONIZE_RADIUS := 170.0
const IONIZE_DAMAGE := 10.0
const IONIZE_COL    := Color(0.6, 0.9, 1.0)
const IONIZE_LENS_DIAM := 85.0    # gravitational-lens disc diameter around the ship (px) — 50% of the old 170
const IONIZE_VORTEX_SCALE := 3.825   # zoom the 2 swirls (2.125 +50% +20%)
const IONIZE_VORTEX_WIDTH := 0.4167  # line-width mult (0.5 ÷ 1.2 → absolute thickness unchanged after the +20% zoom)
const IONIZE_LENS_BRIGHTNESS := 0.3  # <1 → the lens DARKENS the warped interior (no glare), like a real black hole
const IONIZE_GROUP_OPACITY := 0.75   # overall opacity of the whole Black Hole group (vortex + lens)
# Infalling accretion rings: solid filled discs (not outlines) that spawn at the field's outer edge, ease
# inward toward the ship, fading in then out along the way. Interval = life/3 → ~3 concentric discs are
# always alive at once, each at a flat 10% opacity; their overlap (denser toward the centre) is what reads
# as the "black hole pulling matter in" glow — no single hard ring/outline.
const IONIZE_RING_COL      := Color(0.0, 0.0, 0.0)   # accretion-disk orange (matches vortex1's core)
const IONIZE_RING_LIFE     := 2.4    # seconds for a disc to fall from the edge to the centre (50% of prior speed)
const IONIZE_RING_INTERVAL := IONIZE_RING_LIFE / 3.0   # ~3 concurrent discs
const IONIZE_RING_EASE     := 1.4    # >1 → accelerates inward (gravitational pull), not a linear fall
const IONIZE_RING_OPACITY  := 0.20   # flat opacity per disc
const IONIZE_STUN_DUR := 0.5         # Shocking Field electrocute duration (s)
# ── Ionizing Field (Black Hole) skill-point pool + evolves ──
const IONIZE_POOL := {
	"damage":    {"name": "Field Density",     "max": 10, "per": "+10% damage",            "desc": "A more punishing field."},
	"aoe":       {"name": "Event Horizon",     "max": 10, "per": "+10% radius",            "desc": "A wider field."},
	"proximity": {"name": "Proximity Mastery", "max": 5,  "per": "+10% close-range damage (global)", "desc": "GLOBAL: ALL weapons deal up to +10%/rank more damage to targets near you (max at 50px, none past 400px)."},
	"freezing":  {"name": "Freezing Field",    "max": 5,  "per": "+1%/tick freeze chance",  "desc": "The field chills enemies inside it."},
	"burning":   {"name": "Burning Field",     "max": 5,  "per": "+1%/tick burn chance",    "desc": "The field ignites enemies inside it."},
	"shocking":  {"name": "Shocking Field",     "max": 5,  "per": "+1%/tick stun chance",    "desc": "The field electrocutes enemies inside it (~3.3 ticks/s)."},
}
const IONIZE_ABSOLUTION_DMG := 4.0    # Zone of Absolution: +300% damage
const IONIZE_ABSOLUTION_AOE := 0.30   # Zone of Absolution: -70% AoE
const IONIZE_WAR_MAXHP := 100         # Zone of War: flat +Max HP
const IONIZE_WAR_DMG_PER_HP := 0.001  # Zone of War: +1% field damage per 10 Max HP

# ── TUNABLES: Batch-2 weapons (Boomerang / Parasite Cloud / Moroboshi-M1 / Swarm Host / Space Snake) ──
# Boomerang (Kinetic) — a single PERPETUAL blade flying a 3-petal "trinity"/rose path around the ship: it loops
# out into a petal, sweeps back through the centre, out the next petal — forever (rose r = SIZE·cos(3θ)). The
# pattern centre LAGS the ship, so flying drags the whole flower along behind you. Never thrown, never despawns.
const BOOM_COUNT      := 1          # blades in flight
const BOOM_SIZE       := 330.0      # petal reach (flight-pattern radius) — 150% of the previous 220
const BOOM_ROSE_SPEED := 1.2        # how fast the blade travels the petals (θ rad/s) — 60% of the previous 2.0
const BOOM_CENTER_LAG := 6.0        # how fast the flower centre catches up to the ship (lower = more trailing drag)
const BOOM_BLADE      := 58.5       # blade visual half-length (+150% of the old 18px)
const BOOM_DAMAGE     := 28.0
const BOOM_HIT_RADIUS := 62.4       # enlarged to match the bigger blade
const BOOM_HIT_CD     := 0.25       # per-enemy re-hit interval (a blade sweeps the same enemy repeatedly)
const BOOM_SPIN       := 50.265     # visual self-spin rad/s (120 RPM = 4π)
const BOOM_COL        := Color(0.95, 0.85, 0.5)
const BOOM_DRAW       := 25.35       # on-screen boomerang sprite width (px); height aspect-locked per texture
const BOOM_TEX: Texture2D = preload("res://assets/weaponry/ND-Aliwa-Bmr.png")
# ── Boomerang (kinetic + contact) skill-point pool + evolves ──
const BOOM_POOL := {
	"damage":     {"name": "Sharpened Edge",     "max": 10, "per": "+10% damage",         "desc": "A keener blade."},
	"speed":      {"name": "Aerofoil",           "max": 10, "per": "+10% throw speed",     "desc": "The blade travels its arc faster."},
	"size":       {"name": "Heavy Blade",        "max": 10, "per": "+10% blade size",      "desc": "A bigger blade with a wider hit."},
	"count":      {"name": "Split Blade",        "max": 3,  "per": "+1 boomerang",         "desc": "Another blade joins the flock. Unlocks at weapon level 6 / 11 / 16.", "gate": [6, 11, 16]},
	"bleed":      {"name": "Laceration",         "max": 10, "per": "+2 bleed stacks/hit",  "desc": "Every hit rends: 2 guaranteed bleed stacks per rank."},
	"hemorrhage": {"name": "Hemorrhage Mastery", "max": 10, "per": "+20% bleed dmg (global)", "desc": "All bleed effects bleed harder."},
}
const DEATHROLL_PULL := 32.0   # px an enemy is dragged toward the blade per hit (Death Roll evolve)
# Parasite Cloud (Biochemical) — fast blob that decelerates into a lingering damage cloud.
const PARA_COOLDOWN   := 2.6
const PARA_SPEED      := 520.0
const PARA_DRAG       := 2.2        # exponential deceleration toward a hover
const PARA_LIFETIME   := 3.2
const PARA_RADIUS     := 90.0
const PARA_TICK       := 0.25
const PARA_DAMAGE     := 10.0       # per tick to everything inside
const PARA_COL        := Color(0.6, 0.95, 0.45)
const PARA_GAS_LIFETIME := 4.0   # seconds gas cloud lingers after spore expires
const PARA_GAS_PUFF_N   := 7     # puffs per expired spore (1 centre + 6 ring)
# ── Parasite Cloud (Venomancer, biochemical) skill-point pool + evolves ──
const PARA_POOL := {
	"aoe":              {"name": "Contagion Radius",         "max": 10, "per": "+10% cloud radius",         "desc": "The infection spreads wider."},
	"damage":           {"name": "Virulence",                "max": 10, "per": "+10% damage",               "desc": "A deadlier strain."},
	"duration":         {"name": "Persistence",              "max": 5,  "per": "+20% cloud lifetime",       "desc": "Clouds linger longer."},
	"metal_eater":      {"name": "Metal Eater",              "max": 5,  "per": "-1 armor/s in cloud",       "desc": "Affected enemies corrode: -1/s per rank for 5s (cap -5×rank)."},
	"armor_mastery":    {"name": "Armor Stripping Mastery",  "max": 5,  "per": "-10 min armor (global)",    "desc": "Unlocks the armor floor so stripping drives armor NEGATIVE — all armor-strip sources."},
	"stolen_fortitude": {"name": "Stolen Fortitude",         "max": 5,  "per": "+4% stripped armor → you",  "desc": "Gain armor from a share of the most-corroded enemy's stripped armor."},
}
const PARA_METAL_EATER_PER_RANK := 1.0    # armor/sec corroded per Metal Eater rank
const PARA_METAL_EATER_DUR      := 5.0    # s the corrosion lingers after leaving the cloud
const PARA_STOLEN_PER_RANK      := 0.04   # fraction of the top enemy's stripped armor gained per rank
const PARA_STOLEN_LINGER        := 5.0    # s your stolen armor holds after the source reduction is gone
const PARA_RECON_BONUS          := 0.75   # Perfect Reconstruction evolve: +75% conversion
const PARA_AUTO_SPEED           := 150.0  # Full Automation evolve: cloud drift speed (px/s)
# Moroboshi-M1 (Biochemical) — winged-golem familiar that chases enemies and punches (AoE + stagger).
const MORO_FOLLOW_DIST := 90.0      # rests this far behind the ship when idle
const MORO_MOVE_SPEED  := 240.0
const MORO_AGGRO       := 520.0     # seeks enemies within this of itself
const MORO_ATTACK_CD   := 0.9
const MORO_ATTACK_RANGE:= 80.0
const MORO_AOE         := 90.0
const MORO_DAMAGE      := 40.0
const MORO_STAGGER     := 0.3
const MORO_COL         := Color(0.8, 0.7, 1.0)
# Yari Jaeger (Energy) — blade familiar: seeks nearest enemy like Moroboshi, then arc-sweeps like Z-Sword mini.
const YARI_ORBIT_R     := 200.0     # idle orbit radius around player (no targets)
const YARI_ORBIT_SPEED := 1.0       # rad/s — tangential speed = 200 px/s < YARI_MOVE_SPEED
const YARI_MOVE_SPEED  := 260.0     # flight speed toward enemy
const YARI_AGGRO       := 520.0     # engage enemies within this range of Yari
const YARI_ATTACK_RANGE:= 80.0      # trigger slash when this close to target
const YARI_ATTACK_CD   := 1.5       # seconds between slashes
const YARI_SWEEP_TIME  := 0.4       # full arc completes in this many seconds (5 frames × 0.08 s)
const YARI_LENGTH      := 110.0     # slash arc radius centred on Yari
const YARI_ARC_HALF    := 0.314159  # hit half-arc (~18°) — same tolerance as Z-Sword
const YARI_DAMAGE      := 55.0
const YARI_STAGGER     := 0.25
const YARI_FRAME_DELAY := 0.08      # seconds per GIF frame during the slash animation
const YARI_TURN_RATE   := 120.0 / 60.0 * TAU      # 120 RPM → rad/s (≈ 12.57 rad/s)
const YARI_COL         := Color(0.9, 0.65, 1.0)   # light violet glow
# Swarm Host (Biochemical) — familiars that dart to enemies, deal damage, return and heal the player.
const SWARM_COUNT      := 2         # familiar count (body)
const SWARM_SPEED      := 420.0
const SWARM_AGGRO      := 560.0
const SWARM_DAMAGE     := 22.0
const SWARM_HIT_RADIUS := 26.0
const SWARM_HEAL_FRAC  := 0.25      # heal the player for this fraction of damage dealt, on return
const SWARM_IDLE_R     := 70.0      # orbit radius near the ship when idle
const SWARM_COL        := Color(0.95, 0.6, 0.85)
# Space Snake (Biochemical) — fire-snake familiar; head chases enemies, body trails, contact DoT.
const SNAKE_SEGMENTS   := 5        # 1 head + 3 body + 1 tail (short at first; grows via the Length pool + Primordial God)
const SNAKE_SPACING    := 25.2     # px between centres = body segment size (zero gap)
const SNAKE_SPEED      := 300.0
const SNAKE_TURN       := 3.0       # max turn rad/s (head minimises turn angle)
const PREDATOR_TURN    := 2.0       # The Predator's head turns slower → its beam must be aimed by turning the head
const SNAKE_TICK       := 0.2
const SNAKE_DAMAGE     := 8.0       # per tick per enemy in contact with any segment
const SNAKE_HIT_RADIUS := 22.0
const SNAKE_COL        := Color(1.0, 0.6, 0.3)
# ── Space Snake (VIPER, kinetic + contact + automation) skill-point pool + evolves ──
const SNAKE_POOL := {
	"damage":         {"name": "Venom Glands",       "max": 10, "per": "+10% damage",              "desc": "A more toxic bite."},
	"length":         {"name": "Elongate",           "max": 8,  "per": "+1 segment",               "desc": "A longer serpent covers more ground."},
	"speed":          {"name": "Slither",            "max": 10, "per": "+10% move speed",          "desc": "The snake hunts faster."},
	"serrated_fang":  {"name": "Serrated Fang",       "max": 10, "per": "+10 bleed stacks (head)",  "desc": "Head bites rend: 10 bleed stacks/rank when the HEAD hits (guaranteed)."},
	"serrated_scale": {"name": "Serrated Scale",      "max": 10, "per": "+2 bleed stacks/body seg", "desc": "The scaled body rends: 2 bleed stacks/rank per body/tail segment touching (each counts separately)."},
	"hemophilia":     {"name": "Hemophilia Mastery",  "max": 5,  "per": "+20% bleed duration (global)", "desc": "Bleeds last longer everywhere."},
}
const SNAKE_KILLS_PER_SEG := 1000   # Primordial God: enemies the snake must kill per +1 body segment
const SNAKE_PRIMORDIAL_CAP := 50    # Primordial God: max body segments gained from kills (reached at 50k kills)

# ── TUNABLES: Swarm (Chakra Bio-Synthetics) — 8 swarmballs launch out, loiter to acquire a target, then ram it
# as swarmbots and explode. (The old dart+heal familiar mechanic now belongs to Vampire Host.) ──
const DeathFX := preload("res://scripts/gameplay/arena_death_fx.gd")   # enemy-kill burst, reused (scaled) on swarmbot impact
const SBALL_COUNT          := 8        # balls per volley
const SBALL_SPRITE         := "res://assets/weaponry/Swarmball.png"
const SBALL_BOT_SPRITE     := "res://assets/weaponry/Swarmbot.png"
const SBALL_DRAW           := 20.0     # ball width (px); height keeps the texture ratio
const SBALL_BOT_DRAW       := 24.0     # bot width (px) once it arms near the target
const SBALL_LAUNCH_RADIUS  := 100.0    # spread-out / orbit radius around the player
const SBALL_LAUNCH_SPEED   := 500.0    # px/s while flying out
const SBALL_LOITER_SPEED   := 150.0    # px/s tangential speed while orbiting to pick a target
const SBALL_LOITER_HIT_CD  := 0.3      # s between contact hits while orbiting (chip, ball NOT consumed)
const SBALL_SPIN_RAD       := 40.0 / 60.0 * TAU   # ball self-spin: 40 RPM (rad/s), used for the Swarmball sprite
const SBALL_LOITER_TIME    := 1.5      # s of loiter before locking a target
const SBALL_CHARGE_SPEED   := 500.0    # px/s charging the target
const SBALL_ARM_DIST       := 300.0    # within this of the target → swap to Swarmbot
const SBALL_HIT_R          := 10.0     # ball collision radius (≈ half the draw width)
const SBALL_DAMAGE         := 5.0      # per swarmbot on impact
const SBALL_EXPLODE_SIZE   := 18.0     # DeathFX size_px (~50% of a normal enemy-kill burst)
const SBALL_COOLDOWN       := 3.0      # s between volleys (after the previous one is spent)
const SBALL_MAX_LIFE       := 9.0      # s backstop: a ball that never connects self-destructs
const SBALL_COL            := Color(0.70, 0.95, 0.55)

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
const MISSILE_DRAW_LEN     := 46.0    # drawn missile length (px); width derived from missile.png's native ratio
const PROJ_PLUME_MAX       := 16      # plume-anchor pool size for the (variable-count) missile + mortarbullet trails

# ── TUNABLES: Orbitals (spiky energy orbs circling the ship, contact damage — ported from weapon_system.gd) ──
const ORBITAL_BALLS        := 3       # number of orbiting balls (evenly spaced)
const ORBITAL_RADIUS       := 175.0   # orbit radius around the ship (px)
const ORBITAL_SPIN         := 108.0   # deg/sec orbit around the ship (+20%)
const ORBITAL_SELF_RPM     := 40.0    # sprite self-rotation (RPM); 40 RPM = 240 deg/sec
const ORBITAL_BALL_RADIUS  := 4.5     # procedural-fallback ball radius (px) — 50% of original 9
const ORBITAL_HIT_PAD      := 16.0    # (fallback) added to the ball radius for the contact test
const ORBITAL_DAMAGE       := 25.0    # damage per ball collision (× damage-mult, crit-rollable); also fallback if the item def is missing
const ORBITAL_HIT_COOLDOWN := 0.12    # per-ball seconds before it can hit again (~1 hit per pass)
const ORBITAL_STAGGER      := 0.1     # s stagger per orbital hit
const ORBITAL_LIGHT        := 2.5     # dust-light value per ball
const ORBITAL_COL          := Color(0.6, 0.85, 1.0)   # electric arc tint (fallback draw + dust light)
const ORBITAL_SPRITE       := "res://assets/weaponry/ND-OID-F.png"
const SWARM_DRAW           := 24.0
const PARA_SPRITE          := "res://assets/weaponry/BC-SL-Spore.png"
const PARA_DRAW            := 18.0
const ORBITAL_DRAW         := 22.5    # on-screen orb reference size (px) — 50% of original 45
const ORBITAL_KEY_THR      := 240     # white-key threshold (0-255): border-connected pixels ≥ this → transparent
const ORBITAL_HIT_FRAC     := 0.45    # collision radius = ORBITAL_DRAW * 0.5 * this (matches the sprite body)
# Motion blur (afterimage ghosts + tangent streak glow). Orbit speed is fixed → blur is a constant knob.
const ORBITAL_BLUR_AMT     := 0.9     # overall blur strength (0 = crisp, 1 = full)
const trail_ghosts         := 5       # afterimage copies behind the body
const trail_arc_step       := 0.06    # rad between ghosts, stepping BACK along the orbit (curved trail; tighter spacing)
const trail_alpha_falloff  := 0.55    # each older ghost = prev * this
const trail_scale_falloff  := 0.97    # each older ghost slightly smaller
const trail_tint           := Color(1.0, 0.52, 0.10)   # orange trail tint
const streak_enabled       := true
const streak_len_min       := 8.0     # tangent streak length at low blur (px)
const streak_len_max       := 60.0    # streak length at full blur (px)
const streak_width         := 18.0    # streak thickness (px)
const streak_alpha         := 0.5

# ── TUNABLES: Striker (Orbital Impact OFFENSE) — balls orbit the ship; dash out to ram an enemy in range, then return ──
const STRIKER_BALLS        := 2        # number of orbiting balls
const STRIKER_RADIUS       := 150.0    # orbit radius around the ship (px)
const STRIKER_SPIN         := 108.0    # deg/sec orbit speed while idling in formation
const STRIKER_SELF_RPM     := 40.0     # sprite self-rotation while orbiting (RPM)
const STRIKER_RANGE        := 300.0    # detect-and-attack range from the ship
const STRIKER_DAMAGE       := ORBITAL_DAMAGE   # same damage as Defensive Orbitals, × damage-mult, crit-rollable
const STRIKER_RAM_SPEED    := 900.0    # px/s dash speed while ramming out to a target
const STRIKER_RETURN_SPEED := 900.0    # px/s dash speed while returning to its orbit slot
const STRIKER_HIT_RADIUS   := 16.0     # contact hit padding (added to the enemy's hit_radius)
const STRIKER_STAGGER      := 0.1      # s stagger applied on a ram hit
const STRIKER_LIGHT        := 2.5      # dust-light value per ball
const STRIKER_COL          := Color(1.0, 0.45, 0.15)   # orange-red offense tint (fallback draw + dust light)
const STRIKER_SPRITE       := "res://assets/weaponry/ND-OIF-F.png"   # Striker orb sprite
const STRIKER_DRAW         := 22.5     # on-screen size, matches ORBITAL_DRAW

# ── TUNABLES: Shooter (Orbital Impact OFFENSE) — rear-guard turrets that fire 3-bolt laser bursts at the nearest enemy ──
const SHOOTER_BASE_ORBS   := 2        # base turrets (anchor at 8 & 4 o'clock behind the ship)
const SHOOTER_BACK_DIST   := 54.0     # px the turrets hover from the ship centre (~1cm back)
const SHOOTER_MOVE_LERP   := 12.0     # how fast a turret eases to its slot as the ship turns / count changes
const SHOOTER_TURN_RATE   := 120.0 / 60.0 * TAU   # 120 RPM → rad/s, how fast the sprite turns to face a target
const SHOOTER_BURST       := 3        # bolts per burst
const SHOOTER_BURST_GAP   := 0.09     # s between bolts within one burst
const SHOOTER_COOLDOWN    := 1.0      # s between bursts per turret (before fire-rate)
const SHOOTER_ORB_STAGGER := 0.14     # dramatic cadence offset between turrets
const SHOOTER_RANGE       := 620.0    # target-acquisition range from a turret
const SHOOTER_DAMAGE      := 24.0     # damage per bolt (× mult, crit-rollable)
const SHOOTER_BOLT_SPEED  := 920.0    # bolt fly speed (px/s)
const SHOOTER_BOLT_LIFE   := 1.2      # s before a bolt is culled
const SHOOTER_BOLT_LEN    := 40.0     # bolt length (px) — ref 2.5mm : 0.5mm ⇒ 5:1
const SHOOTER_BOLT_W      := 8.0      # bolt width (px)
const SHOOTER_BOLT_HIT    := 12.0     # bolt hit-radius padding
const SHOOTER_STAGGER     := 0.12     # stagger applied to struck enemies
const SHOOTER_COL         := Color(1.0, 0.18, 0.14)   # laser red (outline)
const SHOOTER_LIGHT       := 2.0      # dust-light value per turret
const SHOOTER_AVATAR_CHANCE := 0.05   # Avatar 2 element proc PER BOLT (low — bolts come in bursts × many turrets)
const SHOOTER_SPRITE      := "res://assets/weaponry/shooter.png"   # UAV drone sprite (matches "rams into targets" desc)
const SHOOTER_DRAW        := 30.0     # turret sprite width on screen (px; height aspect-locked)
# ── Shooter skill-point pool + evolves ──
const SHOOTER_POOL := {
	"morebital":  {"name": "More-bital",         "max": 10, "per": "+1 orbital",              "desc": "Another turret. Extra turrets fan up over the top between the 8 & 4 o'clock anchors."},
	"damage":     {"name": "Focused Lens",        "max": 10, "per": "+10% damage",             "desc": "Hotter bolts."},
	"firerate":   {"name": "Rapid Cycling",       "max": 10, "per": "+8% fire rate",           "desc": "Burst more often."},
	"multishot":  {"name": "Scatter Volley",      "max": 10, "per": "+8% extra-burst chance",  "desc": "Chance to fire a bonus burst."},
	"automation": {"name": "Automation Mastery",  "max": 5,  "per": "+5% automation damage",   "desc": "Boosts ALL automation weapons (Defender, Yari, Snake, Shooter, Parasite)."},
	"crit":       {"name": "Critical Shot",       "max": 10, "per": "+5% crit (this weapon)",  "desc": "Shooter bolts crit more often."},
}

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
	// Godot has no MODULATE builtin in canvas_item fragment shaders (that line failed to compile, which is
	// why the rift rendered as a flat gray square — a ColorRect with a broken ShaderMaterial falls back to a
	// plain fill). COLOR already equals the ColorRect's own color × the node's modulate at this point (Godot
	// pre-fills it before fragment() runs), so capture that here instead — it's a no-op tint for the Vacuum
	// rift (opaque white) and still lets the Black Hole variant dim the lens via its node modulate.
	vec4 node_modulate = COLOR;
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
	COLOR *= node_modulate;
}
"

# ── TUNABLES: Lasgun (continuous tick-based beam — gained from a pickup, off until then) ──────────────────
const DEATHBEAM_RANGE   := 3000.0   # beam length px — runs far off-screen so it reads as "infinite"
const DEATHBEAM_BEAM_Z  := 90       # beam draws ON TOP of enemies (z≤4); still under the ship (z 100)
const DEATHBEAM_DAMAGE  := 22.0     # damage PER TICK
const DEATHBEAM_TICK    := 0.10     # s between damage ticks (≈ damage/sec = DEATHBEAM_DAMAGE / this)
const DEATHBEAM_STAGGER := 0.15     # s stagger per tick
const DEATHBEAM_WIDTH   := 14.0     # beam hit width (px) — matches the beam visual
const DEATHBEAM_HIT_PAD := 16.0     # enemy-radius padding for the distance-to-line hit test
const DEATHBEAM_LIGHT        := 5.5 # dust-light value per sample point along the beam (casts light on the dust)
const DEATHBEAM_LIGHT_SAMPLES := 16 # number of light points sampled evenly along the beam (denser = brighter line)
const DEATHBEAM_CYCLE    := 5.0     # full period (s): the beam fires once every CYCLE
const DEATHBEAM_DURATION := 1.5     # beam-on time within each cycle (s) → fires 1.5s out of every 5s
const DEATHBEAM_CHARGE   := 1.5     # charge telegraph (s) before each burst — the orb light-gather plays over this

# ── Lasgun skill-point upgrade pool (incinerate/freeze need the status system — Stage 2, not wired yet) ──
const DEATHBEAM_POOL := {
	"energy":     {"name": "Energy Mastery", "max": 0,  "per": "+10% energy damage",  "desc": "Boosts all energy weapons (global)."},
	"damage":     {"name": "Overcharge",     "max": 10, "per": "+10% damage",         "desc": "The beam hits harder."},
	"duration":   {"name": "Capacitor",      "max": 10, "per": "+10% duration",       "desc": "Longer Lasgun beam, Red X fire, Sonic, Gauss, Chemtrail + burn/freeze/stun."},
	"cooldown":   {"name": "Heat Sink",      "max": 10, "per": "-5% cooldown",        "desc": "Fire more often."},
	"incinerate": {"name": "Incinerate",     "max": 0,  "per": "+5%/s burn chance",   "desc": "Burn: 0.1% current HP/s per stack for 5s."},
	"freeze":     {"name": "Freeze",         "max": 0,  "per": "+5%/s freeze chance", "desc": "Chill: -15% speed per stack (max -90%, boss -30%)."},
}

# ── Level-6 EVOLVE capstones (choose 1 of 3 when a weapon hits max level) ──
const CAPSTONES := {
	"gatling_gun": [
		{"id": "spray",   "name": "Spray and Pray", "desc": "+2 multishot and a much wider spread."},
		{"id": "focus",   "name": "Focus Fire",     "desc": "+0.5% damage per consecutive hit on the same target (max +100%)."},
		{"id": "healing", "name": "Healing Round",  "desc": "1 in 200 bullets heals you + the target for 5 HP."},
	],
	"death_beam": [
		{"id": "all_in",       "name": "All-In",          "desc": "+200% damage, but you lose a weapon slot."},
		{"id": "lights_out",   "name": "Lights-Out",      "desc": "While the beam fires, -30% cooldown for all your OTHER weapons."},
		{"id": "ice_and_fire", "name": "Of Ice and Fire", "desc": "Applying freeze also burns, and applying burn also freezes."},
	],
	"arc": [
		{"id": "dazzle", "name": "Dazzling Display", "desc": "Halve every enemy's stun-immunity duration."},
		{"id": "pacify", "name": "Pacifying Jolt",   "desc": "Electrocute also cuts the target's damage output 50% for 3s."},
		{"id": "holy",   "name": "Holy Bolt",        "desc": "Bounce → 1; +150% damage per bounce lost (a zap from above)."},
	],
	"gauss": [
		{"id": "spirit_bomb",  "name": "Spirit Bomb",         "desc": "CD→5s; per orb it'd fire: +125% damage + 10% area."},
		{"id": "pew",          "name": "Pew Pew Pew",         "desc": "-75% orb size, +100% fire rate."},
		{"id": "annihilation", "name": "Orb of Annihilation", "desc": "Enemies inside an orb take +20% damage from all sources."},
	],
	"defensive_orbitals": [
		{"id": "avatar", "name": "Avatar", "desc": "Infuse the orbs with fire/ice/lightning (one element each, spread evenly). 25% on contact to burn/freeze/stun — boosted by luck + element masteries."},
		{"id": "center", "name": "Center of the Universe", "desc": "Add 100% of your armor and 5% of your Max HP to orbital damage."},
		{"id": "impenetrable", "name": "Impenetrable", "desc": "Orbiting balls block (destroy) enemy projectiles they touch."},
	],
	"dragons_breath": [
		{"id": "the_sun",      "name": "The Sun",      "desc": "Spray fire in all directions (360°), not just a cone."},
		{"id": "heat_syphon",  "name": "Heat Syphon",  "desc": "+0.01 HP regen per currently-burning enemy (max 200 → +2/s)."},
		{"id": "armor_melter", "name": "Armor Melter", "desc": "Enemies with heavy burn stacks take extra damage (melts their armor)."},
	],
	"chemtrail": [
		{"id": "the_moon",   "name": "The Moon",   "desc": "Spew toxic fume in all directions (360°) around the ship."},
		{"id": "healing_cloud", "name": "Healing Cloud", "desc": "Standing in your own chemtrail heals 5 HP/s (scales with Regeneration Mastery)."},
		{"id": "saturation", "name": "Systematic Saturation", "desc": "Every 2s an enemy stays in the cloud, the chemtrail's damage to it ramps up."},
	],
	"z_sword": [
		{"id": "dual",      "name": "Dual Wielding", "desc": "Two blades swing back-to-back; each rolls Divergence, and each trigger swings BOTH."},
		{"id": "cauterize", "name": "Cauterize the Wound", "desc": "On hit, convert 20% of the target's bleed stacks into burn stacks."},
		{"id": "wiper",     "name": "Windshield Wiper", "desc": "Swings knock non-boss enemies back and slow them 99%, decaying to 0 over 0.2s."},
	],
	"ultrasonicator": [
		{"id": "overload", "name": "Sensory Overload", "desc": "+20% damage for each status effect on the target."},
		{"id": "silence",  "name": "Deafening Silence", "desc": "Waves shove enemies back and destroy all enemy projectiles."},
		{"id": "siren",    "name": "Siren", "desc": "25% chance to charm a non-boss enemy for 5s — it fights for you."},
	],
	"mortar": [
		{"id": "fat_boy",        "name": "Fat Boy",        "desc": "-85% fire rate, +500% damage, +150% AoE. One devastating shell."},
		{"id": "little_man",     "name": "Little Man",     "desc": "+300% fire rate, -75% AoE, -50% damage. A rapid patter of tiny shells."},
		{"id": "fusion_reactor", "name": "Fusion Reactor", "desc": "Deactivate the Mortar → passive core: +5 HP regen, +5 shield regen, +10% move speed, +10% fire rate & damage to ALL weapons."},
	],
	"venomancer": [
		{"id": "full_automation",        "name": "Full Automation",        "desc": "The cloud detaches and roams free (150 px/s), parking over the densest enemy cluster. Gains automation tags."},
		{"id": "perfect_reconstruction", "name": "Perfect Reconstruction", "desc": "+75% Stolen Fortitude conversion."},
		{"id": "strip_naked",            "name": "Strip Naked",            "desc": "+50 to the maximum armor reduction — strip enemies deep into negative armor."},
	],
	"aliwa": [
		{"id": "bleed_more", "name": "Bleed!",     "desc": "Each hit applies an ADDITIONAL 10% of the target's max bleed stacks."},
		{"id": "chaos",      "name": "Chaos",      "desc": "+3 boomerangs."},
		{"id": "death_roll", "name": "Death Roll", "desc": "-70% throw speed (snaps back if it strays too far), +100% damage, and the blade now DRAGS enemies into itself."},
	],
	"viper": [
		{"id": "primordial_god", "name": "Primordial God", "desc": "The snake grows: +1 body segment per 1000 enemies it kills (up to +50 at 50,000 kills)."},
		{"id": "more_snakes",    "name": "More Snakes",     "desc": "+1 snake — a second serpent with identical stats."},
		{"id": "anemia",         "name": "Anemia",          "desc": "Enemies take +1% damage from ALL sources per 10 bleed stacks on them."},
	],
	"swarm": [
		{"id": "dart", "name": "Dart", "desc": "Steal Heal: after a swarmbot detonates, the spent shell flies back to the ship and heals you for 25% of the damage it just dealt."},
	],
	"shooter": [
		{"id": "avatar2",           "name": "Avatar 2",          "desc": "Infuse the turrets with fire/ice/lightning (one each, spread evenly). Bolts have 25% to burn/freeze/stun."},
		{"id": "the_fleet",         "name": "The Fleet",         "desc": "+5 more offensive orbitals."},
		{"id": "piercing_vanguard", "name": "Piercing Vanguard", "desc": "Bolts pierce — they pass through every enemy in line (100% pierce)."},
	],
	"ionizing_field": [
		{"id": "zone_of_war",        "name": "Zone of War",        "desc": "+100 Max HP, and the field gains +1% damage per 10 of your Max HP."},
		{"id": "zone_of_absolution", "name": "Zone of Absolution", "desc": "-70% radius, +300% damage — a tiny, brutal core."},
		{"id": "zone_of_peace",      "name": "Zone of Peace",      "desc": "ALL enemies deal -20% damage & move -20% slower (their projectiles too)."},
	],
	"player_2": [
		{"id": "ready_player_3",  "name": "Ready Player 3",  "desc": "Add a second companion ship — same copies, same bonuses."},
		{"id": "full_sync",       "name": "Full Sync",       "desc": "The companion ships can now PROC status effects + crit (normally they deal only their % damage)."},
		{"id": "project_phoenix", "name": "Project Phoenix", "desc": "When you would die, revive to full HP instead — but Player 2 shuts down for 10 minutes."},
	],
}

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
const RED_X_ARM_HALF_DEG := 14.0   # half-width of each X arm in degrees (Carnage fusion's X-fire)
# ── Dragon's Breath (reworked standalone Red X): a continuous forward cone of fire (DPS, not on-contact). ──
const DRAGON_TICK        := 0.2    # s between damage ticks
const DRAGON_DPS         := 90.0   # base damage/sec sprayed into the cone (× damage-mult + crit)
const DRAGON_RANGE       := 300.0  # base cone reach (px)
const DRAGON_CONE_DEG    := 30.0   # base full cone angle (degrees)
const DRAGON_BURN_CHANCE := 0.30   # base per-tick burn chance (+ Fire Mastery + Stroke of Luck)
const DRAGON_POOL := {
	"damage":  {"name": "Hotter Flame",   "max": 10, "per": "+10% damage",            "desc": "More DPS in the cone."},
	"fire":    {"name": "Fire Mastery",    "max": 5,  "per": "+5% burn chance (global)", "desc": "All fire effects ignite more often."},
	"prolong": {"name": "Prolonged Flame", "max": 5,  "per": "+0.2s burn duration (global)", "desc": "Burns linger longer."},
	"range":   {"name": "Long Reach",      "max": 5,  "per": "+10% range",             "desc": "Reach further."},
	"cone":    {"name": "Wide Spray",      "max": 5,  "per": "+15% cone angle (×AoE)",  "desc": "Wider fan of fire."},
	# NOTE: data + icon only — no gameplay effect wired yet (needs an enemy-armor-reduction hook keyed off
	# _burn_stacks; not implemented). Picking/ranking this currently does nothing mechanically.
	"armor_reduction": {"name": "Melting Steel Beam", "max": 10, "per": "Reduce armor equal to 0.02 stack of burn per rank", "desc": "The heat softens their plating."},
}

# ── Chemtrail (Biochemical): breadcrumb DoT puff-pool dropped behind the moving ship ──
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
const CHEMTRAIL_POOL := {
	"intensity": {"name": "Intensity Mastery", "max": 5,  "per": "-5% tick cooldown (global)", "desc": "All DoT/tick weapons tick faster (shared skill)."},
	"damage":    {"name": "Concentrate",       "max": 10, "per": "+10% damage",                "desc": "Stronger toxin."},
	"duration":  {"name": "Lingering Haze",    "max": 5,  "per": "+20% trail duration",        "desc": "The cloud lasts longer."},
	"burn":      {"name": "Chemical Burn",     "max": 5,  "per": "+5%/s burn chance",          "desc": "Toxin ignites enemies."},
	"ms":        {"name": "Aerosol Boosters",  "max": 5,  "per": "+4% Move Speed",             "desc": "Lay trail while zipping around."},
	"sedative":  {"name": "Sedative Scent",    "max": 5,  "per": "-2.5% enemy dmg & speed",     "desc": "Affected enemies hit softer and move slower."},
}
const ARC_JUMPS    := 4        # extra targets the bolt chains to after the first
const ARC_BASE_BOUNCE := 3     # Arc pool: base chain count (Chain Reaction ranks + Lv1 add to this)
# ── Arc skill-point pool. Stroke of Luck adds to a GLOBAL proc bonus that EVERY chance roll reads (see _proc). ──
const ARC_POOL := {
	"luck":        {"name": "Stroke of Luck",  "max": 5,  "per": "+1% to ALL proc chances", "desc": "Crit, burn, freeze, stun… every chance, retroactively."},
	"damage":      {"name": "Overvolt",        "max": 10, "per": "+10% damage",             "desc": "Stronger bolts."},
	"firerate":    {"name": "Rapid Discharge", "max": 10, "per": "+8% fire rate",           "desc": "Arc more often."},
	"bounce":      {"name": "Chain Reaction",  "max": 5,  "per": "+1 bounce",               "desc": "Chains to more enemies (base 3 → 8)."},
	"lightning":   {"name": "Lightning Mastery", "max": 10, "per": "+2% stun & +5% stun duration", "desc": "GLOBAL: boosts stun chance + duration — Arc electrocute, Gauss EMP, Avatar lightning."},
	"electrocute": {"name": "Electrocute",     "max": 5,  "per": "+5% stun chance",         "desc": "Stun 0.5s (boss 0.2s); stunned foes take +50% damage."},
}
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

const BeamScript   := preload("res://scripts/gameplay/lasgun_ani_5.gd")   # lasgun_ani_5: same Isaac-model body/muzzle/impact art as ani_1, but the body's tile+fade is GPU shader-driven instead of a per-frame CPU tile/sub-quad loop; ani_1/ani_2/ani_3 kept as backups
const SFX_BOLT_HIT: Array[AudioStream] = [
	preload("res://assets/audio/sfx/railgun.wav"),
	preload("res://assets/audio/sfx/railgun2.wav"),
]
const SFX_ENGINE_HUM: AudioStream = preload("res://assets/audio/sfx/Scifi/scifi-background-noise.wav")
const SFX_GAUSS_FIRE: AudioStream = preload("res://assets/audio/sfx/hitimpact.wav")
const SFX_GAUSS_IMPACT: AudioStream = preload("res://assets/audio/sfx/AstroMenace-SFX/weaponfire6.wav")
const SFX_ORBITAL_IMPACT: AudioStream = preload("res://assets/audio/sfx/AstroMenace-SFX/weaponfire6.wav")
const SFX_DEATHBEAM_CHARGE: AudioStream = preload("res://assets/audio/sfx/Scifi/blg_beam_01.wav")
const SFX_DEATHBEAM_BEAM: AudioStream = preload("res://assets/audio/sfx/AstroMenace-SFX/weaponfire14.wav")
const PickupScript := preload("res://scripts/gameplay/arena_weapon_pickup.gd")
const OrbChargeScript := preload("res://scripts/gameplay/arena_orb_charge_fx.gd")
const GatMuzzleScript := preload("res://scripts/gameplay/arena_gatling_muzzle.gd")
const GaussOrbFX   := preload("res://scripts/gameplay/gauss_orb_fx.gd")   # used for both the orb AND (bigger) the impact burst
const GaussExplFX  := preload("res://scripts/gameplay/gauss_explosion_fx.gd")   # fallback sprite explosion node (see GAUSS_USE_SPRITE_VFX)
const ExplosionFX  := preload("res://scripts/gameplay/fx/explosion.gd")   # composite blast used by the Nuke
const ZSlashScript := preload("res://scripts/gameplay/fx/z_slash.gd")     # sweeping energy-slash crescent VFX
const EnergyVortex := preload("res://scripts/gameplay/fx/energy_vortex.gd")   # creep-edit swirl reused by Black Hole

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

# ── Gauss orb look (procedural gauss_orb_fx.gdshader by default — replaces the gauss24_XX.png flipbook) ──
const GAUSS_ORB_DRAW    := 38.0    # on-screen orb diameter incl. transparent margin (px); full uncropped frame

# ── Gauss orb FLIPBOOK (fallback art — see GAUSS_USE_SPRITE_VFX) ──
const GAUSS_ORB_DIR     := "res://assets/beam references/Gauss_orb_files_2/"   # gauss24_00..23.png (already transparent)
const GAUSS_FRAME_COUNT := 24
const GAUSS_ORB_FPS     := 24.0    # plasma-loop playback speed (fps)

# ── Gauss explosion on impact (AoE plasma burst — same gauss_orb_fx.gd/.gdshader, just bigger, by default) ──
# Non-uniform animation: quick pop-in → held bright plasma sphere → fade-out. Damage radius is FIXED at
# the peak size for the whole DURATION (see _tick_explosions / _update_explosion_node).
const GAUSS_EXPL_DURATION     := 2.0
const GAUSS_EXPL_INTRO_TIME   := 0.30          # pop-in time (0 -> full size)
const GAUSS_EXPL_OUTRO_TIME   := 0.30          # fade-out time (full alpha -> 0) at the end of DURATION
const GAUSS_TICK_INTERVAL     := 0.1           # s between DoT ticks (Stage 2)
const GAUSS_TICK_DAMAGE       := 5.0           # base dmg/tick; scaled by _dmg_mult + crit (Stage 2)
const GAUSS_EXPL_RADIUS       := 72.0          # FIXED damage radius (~2.4× orb hit radius 30) — tune in Stage 3
const GAUSS_EXPL_DRAW         := 190.0         # on-screen burst diameter (px) — the "big sphere", same shader as the orb
const GAUSS_EXPL_HIT_PAD      := 14.0          # enemy half-size pad added to the radius test (Stage 2)
const GAUSS_EXPL_DEBUG_DRAW   := false         # true → draw the damage radius (+ enemy-center cutoff) to tune it

# ── Gauss explosion FLIPBOOK (fallback art, 3 cosmetic variants × 12 frames — see GAUSS_USE_SPRITE_VFX) ──
const GAUSS_EXPL_DIR          := "res://assets/fx/gauss_explosion/"   # vN/00..11.png (transparent, glow-baked)
const GAUSS_EXPL_VARIANTS     := 3
const GAUSS_EXPL_FRAME_COUNT  := 12
const GAUSS_EXPL_FRAME_W      := 336.0
const GAUSS_EXPL_FRAME_H      := 336.0
const GAUSS_EXPL_ANCHOR       := Vector2(168.0, 168.0)   # burst-core pixel (frame center) in each frame
const GAUSS_EXPL_SCALE        := 0.45          # sprite scale: 336px frame → ~150px on-screen burst
# Non-uniform flipbook schedule: fast intro → long 6-7-8 peak loop → fast outro.
const GAUSS_EXPL_PEAK_FRAMES  := [5, 6, 7]     # 0-indexed frames 6,7,8 (the dwell)
const GAUSS_EXPL_INTRO_FRAMES := [0, 1, 2, 3, 4]
const GAUSS_EXPL_OUTRO_FRAMES := [8, 9, 10, 11]
const GAUSS_EXPL_PEAK_FPS     := 12.0          # loop speed of the 6-7-8 peak

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
# ── Companion mode (Player 2): a 2nd ArenaWeapons instance bound to the P2 ship, firing ONE copied weapon at a
# reduced damage scale. Set these BEFORE add_child() so _ready() picks them up. _companion skips the singleton
# group registration + player-only signal hooks; _player_ref overrides the "player"-group lookup. ──
var _companion: bool = false
var _player_ref: Node2D = null
var _dmg_scale: float = 1.0
var _p2_fam_bonus: Dictionary = {}   # companion: family ("kinetic"/"energy"/"biochemical") → bonus frac (P2 colour coats)
var _procs_enabled: bool = true      # companion: false suppresses ALL chance procs + crit (Player-2 default; on via Full Sync)
var _p2_nodes: Array = []        # (main instance only) live ArenaPlayer2 companions (1, or 2 with Ready Player 3)
var _player2_upg: Dictionary = {"damage": 0, "kinetic": 0, "energy": 0, "biochemical": 0, "proactive": 0, "diversify": 0}
var _player2_capstone: String = ""     # "" | "ready_player_3" | "full_sync" | "project_phoenix"
var _player2_phoenix_cd: float = 0.0   # >0 → Player 2 is shut down (Project Phoenix cooldown)
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
var _glow_tex: ImageTexture = null  # soft radial-gradient sprite for smooth glows (lazily built)
var _gauss_frames: Array = []       # fallback: 24-frame plasma-orb flipbook (see GAUSS_USE_SPRITE_VFX)
var _gauss_fb_t: float = 0.0
var _gauss_fb_idx: int = 0
var _expl_frames: Array = []        # fallback: [variant][frame] → ImageTexture; 3 variants × 12 frames
var _explosions: Array = []        # live Gauss explosions: {pos, age, node, tick_acc}
# Runtime weapon-enable flags. The ship now starts UNARMED — every weapon is acquired via the start-of-run
# chest or a world/F12 pickup (acquire_weapon → activate_<kind>), so all flags start false.
var _gat_active: bool = false
# Staggered right-wing gatling shots waiting to fire (twin-barrel stagger): each entry {"delay": float, "n": int}.
var _gat_pending: Array = []
# Gatling upgrade ranks (from the skill-point pool) + the level-7 capstone choice + Focus-Fire tracking.
var _gat_upg: Dictionary = {"hardened": 0, "piercing": 0, "quick": 0, "bouncing": 0, "multishot": 0, "advance_ballistic": 0}
var _gat_capstone: String = ""   # "" | "spray" | "focus" | "healing"
# Lasgun upgrade ranks (from its skill-point pool) + the level-6 evolve capstone.
var _db_upg: Dictionary = {"energy": 0, "damage": 0, "duration": 0, "cooldown": 0, "incinerate": 0, "freeze": 0}
var _db_capstone: String = ""   # "" | "all_in" | "lights_out" | "ice_and_fire"
var _db_is_firing: bool = false # true during the beam-on window (Lights-Out reads this)
var _slot_penalty: int = 0       # weapon-slot capacity lost (All-In capstone)
# Arc upgrade ranks + the level-6 evolve capstone.
var _arc_upg: Dictionary = {"luck": 0, "damage": 0, "firerate": 0, "bounce": 0, "lightning": 0, "electrocute": 0}
var _arc_capstone: String = ""   # "" | "dazzle" | "pacify" | "holy"
# Gauss upgrade ranks + the level-6 evolve capstone.
var _gauss_upg: Dictionary = {"aoe_mastery": 0, "damage": 0, "cooldown": 0, "meltdown": 0, "emp": 0, "fission": 0}
var _gauss_capstone: String = ""   # "" | "spirit_bomb" | "pew" | "annihilation"
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
var _orbital_impact_player: AudioStreamPlayer = null
var _db_charge_player: AudioStreamPlayer = null
var _db_beam_player: AudioStreamPlayer = null
var _db_beam_playing: bool = false
var _arc_active: bool = ARC_ENABLED_DEFAULT   # turned on by the Arc pickup
var _red_x_active: bool = false    # turned on by the Red X / Dragon's Breath pickup
var _red_x_cd: float = 0.0         # (legacy detonation cd — Carnage X-fire still uses _spawn_red_x_fire)
var _red_x_fx: DynamicFire = null  # pooled fire visual
var _red_x_upg: Dictionary = {"damage": 0, "fire": 0, "prolong": 0, "range": 0, "cone": 0, "armor_reduction": 0}
var _red_x_capstone: String = ""
var _red_x_tick_acc: float = 0.0   # Dragon's Breath damage-tick accumulator
var _sun_spin: float = 0.0         # The Sun: rotation accumulator for the swirling fire ring
var _chemtrail_active: bool = false   # turned on by the Chemtrail pickup
var _chemtrail_puffs: Array = []      # breadcrumb DoT puffs: {pos, age, max_age, radius}
var _chemtrail_tick_acc: float = 0.0  # weapon-level DoT tick (single damage per enemy per tick = no-stack)
var _chemtrail_emit_acc: float = 0.0  # emit-rate accumulator (puffs shot out the back at a steady cadence)
var _chemtrail_fx: DynamicFire = null # ONE recolored toxic-fire emitter spanning all puff centres
var _chem_upg: Dictionary = {"intensity": 0, "damage": 0, "duration": 0, "burn": 0, "ms": 0, "sedative": 0}
var _chem_capstone: String = ""
var _chem_sat: Dictionary = {}        # Systematic Saturation: enemy instance_id → damage-ramp fraction
var _chem_sat_t: float = 0.0          # 2s saturation re-check timer
var _chem_moon_ang: float = 0.0       # The Moon: emit-direction sweep so the 360° cloud fills evenly
var _arc_cd: float = 0.0           # Arc burst cooldown
var _arcs: Array = []              # live lightning links: {ln, mat, tip, age, max_age, fx, fx_ttl, fx_freed}
var _arc_thunder_tex: ImageTexture = null   # procedural tileable thunder texture (cached)
var _arc_spark_tex: ImageTexture = null     # small stretched spark streak (cached)
var _orbital_active: bool = false  # turned on by the Orbital pickup
var _orbital_angle: float = 0.0    # current orbit angle (deg)
var _orbital_self_angle: float = 0.0  # sprite self-rotation angle (deg), driven by ORBITAL_SELF_RPM
var _orbital_t: float = 0.0        # time accumulator for the electric-arc crackle
var _orbital_cd: Array = []        # per-ball hit cooldown timers
var _orbital_upg: Dictionary = {"contact": 0, "size": 0, "damage": 0, "tighten": 0, "spin": 0, "spin2": 0, "widen": 0}
var _orbital_capstone: String = ""
var _orbital_elements: Array = []  # Avatar: per-ball element ("fire"/"ice"/"lightning"); rebuilt on count change
var _truth_family: String = ""     # Art of War "X Truth" evo: the surviving weapon family ("" = none)
var _truth_count: int = 0          # weapons disabled by the Truth evo → +50% family damage each
var _orbital_tex: Texture2D = null # orb sprite; null → procedural fallback
var _orbital_tex_size: Vector2 = Vector2.ZERO  # native pixel size of the orb sprite (for ratio-correct draw)
var _orbital_damage: float = ORBITAL_DAMAGE
# Striker: balls orbit; peel off to ram a target in range, then return to formation.
var _striker_active: bool = false
var _striker_init: bool = false
var _striker_angle: float = 0.0        # shared orbit angle (deg), like _orbital_angle
var _striker_self_angle: float = 0.0   # sprite self-rotation angle (deg)
var _striker_balls: Array = []         # [{state: "orbit"|"ram"|"return", pos: Vector2, target: Node}]
var _striker_tex: Texture2D = null     # ND-OIF-F.png Orbital Impact OFFENSE sprite
# Shooter (offensive orbital): orbs orbit, then strike out at enemies.
var _shooter_active: bool = false
var _shooter_init: bool = false
var _shooter_orbs: Array = []      # turrets: [{pos, cd, burst_left, gap}]
var _shooter_bolts: Array = []     # laser bolts: [{pos, vel, life, hits:{}}]
var _shooter_upg: Dictionary = {"morebital": 0, "damage": 0, "firerate": 0, "multishot": 0, "automation": 0, "crit": 0}
var _shooter_capstone: String = ""     # "" | "avatar2" | "the_fleet" | "piercing_vanguard"
var _shooter_elements: Array = []      # Avatar 2: per-turret element ("fire"/"ice"/"lightning")
var _shooter_tex: Texture2D = null     # shooter.png UAV drone sprite
var _plume_registry: Array = []    # [{cfg_key, count, ds, provider, anchors}] — generic plume system
var _void_active: bool = false     # turned on by the Void pickup
var _void_cd: float = 0.0          # cast cooldown (ready when <= 0)
var _void_on: bool = false         # a void is currently open
var _void_pos: Vector2 = Vector2.ZERO
var _void_age: float = 0.0         # 0 → VOID_DURATION
var _void_tick: float = 0.0        # damage-tick accumulator
var _void_node: ColorRect = null   # the swirling-vortex visual
var _void_distort: ColorRect = null   # gravitational-lens disc (screen-warp), drawn under the vortex
# ── Batch-1 weapons (Nuke / Sonic Wave / Z-Sword / Ionizing Field) ──
var _mortar_active: bool = false          # Mortar — mortarbullet auto-fire toward the cursor
var _mortar_cd: float = 0.0               # Mortar fire timer
var _mortar_upg: Dictionary = {"damage": 0, "firerate": 0, "aoe": 0, "concentrated": 0, "kinetic": 0, "wasteland": 0}
var _mortar_capstone: String = ""         # "" | "fat_boy" | "little_man" | "fusion_reactor"
var _mortar_bullets: Array = []         # shared pool: {pos, vel, life}
var _wasteland_zones: Array = []        # Waste Land craters: {pos, radius, dmg, age, tick}
var _mortarbullet_tex: Texture2D = null
var _sonic_active: bool = false
var _sonic_cd: float = 0.0
var _sonic_queue: float = 0.0          # stagger timer for the remaining rings of a volley
var _sonic_left: int = 0               # rings still to spawn in the current volley
var _sonic_rings: Array = []           # live rings: {center, age, hit:Array, maxr}
var _sonic_upg: Dictionary = {"damage": 0, "range": 0, "cd": 0, "cold": 0, "cone": 0}
var _sonic_capstone: String = ""
var _zsword_active: bool = false
var _zsword_cd: float = 0.0
var _zsword_sweeping: bool = false
var _zslash: Node2D = null         # sweeping energy-slash crescent VFX node (ZSlash; additive HDR → blooms)
var _zslash_reverse: Node2D = null # Divergence/Dual Wielding's extra swings: same VFX, orange palette, opposite sweep
var _zsword_t: float = 0.0
var _zsword_start: float = 0.0
var _zsword_is_reverse: bool = false   # true while the CURRENT sweep is a queued extra swing (orange, reversed)
var _zsword_hit: Array = []
var _zsword_upg: Dictionary = {"damage": 0, "size": 0, "cd": 0, "crit": 0, "martial": 0, "divergence": 0}
var _zsword_capstone: String = ""
var _zsword_queue: int = 0   # pending immediate swipes (Divergence / Dual Wielding)
var _ionize_active: bool = false
var _ionize_tick: float = 0.0
var _ionize_ring_spawn_t: float = 0.0
var _ionize_rings: Array = []          # {age: float} — infalling accretion rings, edge → centre
var _ionize_upg: Dictionary = {"damage": 0, "aoe": 0, "proximity": 0, "freezing": 0, "burning": 0, "shocking": 0}
var _ionize_capstone: String = ""      # "" | "zone_of_war" | "zone_of_absolution" | "zone_of_peace"
var _ionize_vortex1: Node2D = null     # Black Hole: outer orange EnergyVortex swirl
var _ionize_vortex2: Node2D = null     # Black Hole: inner violet EnergyVortex swirl (on top of vortex1)
var _ionize_lens: ColorRect = null     # Black Hole: gravitational-lens distortion (reuses the Vacuum rift shader)
var _ionize_ring_layer: Node2D = null  # Black Hole: dedicated draw layer for the infalling rings, ABOVE the lens
										# (z 8 > lens's 7) so its darken/warp shader doesn't swallow them
# ── Batch-2 weapons (Boomerang / Parasite Cloud / Moroboshi-M1 / Swarm Host / Space Snake) ──
var _boom_active: bool = false
var _boom_init: bool = false
var _boom_center: Vector2 = Vector2.ZERO   # trailing centre of the rose pattern (lags the ship)
var _booms: Array = []                 # perpetual blades: {theta, spin, age, pos, hits:{}}
var _boom_upg: Dictionary = {"damage": 0, "speed": 0, "size": 0, "count": 0, "bleed": 0, "hemorrhage": 0}
var _boom_capstone: String = ""        # "" | "bleed_more" | "chaos" | "death_roll"
var _para_active: bool = false
var _para_cd: float = 0.0
var _para_clouds: Array = []           # {pos, vel, age, tick, plume, auto}
var _para_upg: Dictionary = {"aoe": 0, "damage": 0, "duration": 0, "metal_eater": 0, "armor_mastery": 0, "stolen_fortitude": 0}
var _para_capstone: String = ""        # "" | "full_automation" | "perfect_reconstruction" | "strip_naked"
var _stolen_armor: float = 0.0         # current Stolen Fortitude bonus armor (fed to GameManager per-frame)
var _stolen_armor_t: float = 0.0       # linger timer for the stolen armor
var _para_gas_puffs: Array = []        # [{pos, age, max_age}] — DynamicFire puffs from expired spores
var _para_gas_fx: DynamicFire = null   # recolored toxic-fire emitter for gas clouds
var _para_tex: Texture2D = null
var _para_plume_data: Dictionary = {}  # cached fracs+styles for fast per-cloud plume creation
var _moro_active: bool = false
var _moro_init: bool = false
var _moro_pos: Vector2 = Vector2.ZERO
var _moro_facing: float = -PI * 0.5
var _moro_frames: Array[Texture2D] = []
var _moro_cd: float = 0.0
var _moro_punch_t: float = 0.0
var _moro_punch_pos: Vector2 = Vector2.ZERO
# ── Yari Jaeger ──
var _yari_active: bool = false
var _yari_init: bool = false
var _yari_pos: Vector2 = Vector2.ZERO
var _yari_cd: float = 0.0
var _yari_sweeping: bool = false
var _yari_sweep_t: float = 0.0
var _yari_sweep_start: float = 0.0
var _yari_hit: Array = []
var _yari_slash: Node2D = null
var _yari_frames: Array[Texture2D] = []
var _yari_frame_acc: float = 0.0
var _yari_frame_idx: int = 0
var _yari_facing: float = -PI * 0.5   # world angle the sprite faces; default = up (sprite's natural axis)
var _yari_orbit_ang: float = 0.0      # current orbit angle when idling (no targets)
var _swarm_active: bool = false
var _swarm_capstone: String = ""       # "" | "dart"
var _swarm_units: Array = []           # {pos, off, dir, state, t, life, target, bot, ang, chip_cd, dmg}
var _swarm_tex: Texture2D = null       # = _swarmball_tex (kept for the plume-sizing reference)
var _swarmball_tex: Texture2D = null
var _swarmbot_tex: Texture2D = null
var _swarm_cd: float = 0.0             # seconds until the next volley (fixed cadence — fires regardless of the current pool)
var _snake_active: bool = false
var _snake_init: bool = false
var _snake_pts: Array = []             # head-first list of segment positions (Vector2)
var _snake_dir: float = 0.0
var _snake_tick: float = 0.0
var _snake_upg: Dictionary = {"damage": 0, "length": 0, "speed": 0, "serrated_fang": 0, "serrated_scale": 0, "hemophilia": 0}
var _snake_capstone: String = ""       # "" | "primordial_god" | "more_snakes" | "anemia"
var _snake_kills: int = 0              # enemies killed by a direct snake bite (Primordial God growth)
var _snake2_init: bool = false         # second snake (More Snakes evolve) — own chain, no plume VFX
var _snake2_pts: Array = []
var _snake2_dir: float = 0.0
var _snake2_tick: float = 0.0
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
var _predator_prev_head: Vector2 = Vector2.ZERO   # head position at the last damage tick (swept hit-test)
var _predator_prev_dir: Vector2 = Vector2.RIGHT   # beam direction at the last damage tick (swept hit-test)
var _predator_prev_valid: bool = false            # false right after the beam (re)starts — no fake sweep
var _snake_head_top_tex: Texture2D = null
var _snake_body_tex:     Texture2D = null
var _snake_tail_tex:      Texture2D = null
var _snake_head_plume_anchor:  Node2D = null
var _snake_tail_plume_anchor:  Node2D = null
var _snake_body_plume_anchors: Array  = []   # one Node2D per body segment (k=1..n-2)
var _death_beam_active: bool = false   # turned on by the Lasgun pickup (auto-equip, accumulates with the Gatling)
var _beam_cd: float = 0.0          # Lasgun damage-tick cooldown
var _db_prev_from: Vector2 = Vector2.ZERO   # muzzle position at the last damage tick (swept hit-test)
var _db_prev_dir: Vector2 = Vector2.RIGHT   # beam direction at the last damage tick (swept hit-test)
var _db_prev_valid: bool = false            # false right after the beam (re)starts — no fake sweep
var _beam: Node2D = null           # additive beam VFX child (gameplay plane → sharp)
var _gat_muzzle_t: float = 0.0     # Gatling muzzle-fire intensity (1 on each shot, decays)
var _gat_muzzle_fx: Node2D = null  # additive Gatling muzzle-flash FX child
var _db_t: float = 0.0            # Lasgun cycle clock (advances while active)
var _charge_fx: Node2D = null      # Chromeleon-orb light-gather charge telegraph (ported _ChannelFX)
var _db_charge_started: bool = false   # one-shot guard so the charge FX triggers once per cycle
var _beam_light_on: bool = false   # beam currently casting dust light
var _beam_light_from := Vector2.ZERO
var _beam_light_to := Vector2.ZERO
var _beam_light_col := Color(1, 1, 1)
var _bolt_hit_player: AudioStreamPlayer = null   # bolt-hit sfx (assign in _ready when wired; null = no-op)
var _crit_layer: CanvasLayer = null
var _crit_host: Control = null

func _ready() -> void:
	if not _companion:
		add_to_group("arena_weapons")   # arena_dust queries get_lights() each frame — only the MAIN instance
	_player = _player_ref if (_companion and _player_ref != null) else get_tree().get_first_node_in_group("player")
	if not _companion and GameManager.has_signal("mitigation_burst"):
		GameManager.mitigation_burst.connect(_fire_mitigation_shockwave)   # Exoskeleton Reactive Plating evo (player only)
	if not _companion and GameManager.has_signal("leveled_up"):
		GameManager.leveled_up.connect(_on_harvest_levelup)   # Data Harvester: heal + AoE blast on level-up
	_beam = BeamScript.new()
	add_child(_beam)
	_beam.z_index = DEATHBEAM_BEAM_Z   # beam renders over enemy sprites
	_charge_fx = OrbChargeScript.new()
	add_child(_charge_fx)
	_gat_muzzle_fx = GatMuzzleScript.new()
	add_child(_gat_muzzle_fx)
	_zslash = ZSlashScript.new()
	add_child(_zslash)
	_zslash_reverse = ZSlashScript.new()
	add_child(_zslash_reverse)
	_zslash_reverse.use_orange_palette()   # Divergence/Dual-Wielding's extra swings: same crescent VFX, warm palette
	_yari_slash = ZSlashScript.new()
	add_child(_yari_slash)
	_load_yari_frames()
	_load_moro_frames()
	_load_snake_tex()
	if GAUSS_USE_SPRITE_VFX:
		_load_gauss_frames()
		_load_gauss_explosion_frames()
	_load_orbital_tex()
	_striker_tex = load(STRIKER_SPRITE) as Texture2D
	_shooter_tex = load(SHOOTER_SPRITE) as Texture2D
	_load_swarm_tex()
	_load_para_tex()
	_load_para_plume_data()
	# ── Generic plume registry ────────────────────────────────────────────────────
	_register_plume("Yari-Jeager", 1,
		Vector2(32.0, 32.0 * 500.0 / 282.0),
		func():
			if not _yari_active or not _yari_init: return []
			return [{"pos": _yari_pos, "rot": _yari_facing + PI * 0.5}])
	var _mo_dw := 32.0
	var _mo_dh := _mo_dw
	if not _moro_frames.is_empty():
		_mo_dh = _mo_dw * float(_moro_frames[0].get_height()) / maxf(float(_moro_frames[0].get_width()), 1.0)
	_register_plume("Yari", 1, Vector2(_mo_dw, _mo_dh),
		func():
			if not _moro_active: return []
			return [{"pos": _moro_pos, "rot": _moro_facing + PI * 0.5}])
	_register_plume("ND-Aliwa-Bmr", 1,
		Vector2(BOOM_DRAW, BOOM_DRAW * float(BOOM_TEX.get_height()) / maxf(float(BOOM_TEX.get_width()), 1.0)),
		func():
			if not _boom_active or _booms.is_empty(): return []
			return [{"pos": _booms[0]["pos"], "rot": _booms[0]["spin"]}])
	_register_plume("ND-OID-F", ORBITAL_BALLS, _orbital_draw_size(),
		func():
			if not _orbital_active or _player == null or not is_instance_valid(_player): return []
			var _rad := deg_to_rad(_orbital_self_angle)
			return _orbital_positions().map(func(p): return {"pos": p, "rot": _rad}))
	var _shooter_sz := Vector2(SHOOTER_DRAW, SHOOTER_DRAW)
	if _shooter_tex != null and _shooter_tex.get_size().x > 0.0:
		_shooter_sz.y = SHOOTER_DRAW * _shooter_tex.get_size().y / _shooter_tex.get_size().x
	_register_plume("shooter", SHOOTER_BASE_ORBS, _shooter_sz,
		func():
			if not _shooter_active: return []
			return _shooter_orbs.map(func(o): return {"pos": o["pos"], "rot": float(o.get("rot", 0.0)) + PI * 0.5}))
	# (Swarm uses no plume here — ND-OIF-F is legacy art, unrelated to the swarmball weapon. The
	# swarmball/swarmbot trails will come from TPs placed on Swarmball.png / Swarmbot.png in Weapon Edit.)
	# Projectile trails: variable count → register a pool of PROJ_PLUME_MAX anchors; the provider returns only the
	# live projectiles each frame (extras auto-hide). Plume offset/style come from the TPs placed on the sprites.
	_register_plume("missile", PROJ_PLUME_MAX, Vector2(MISSILE_DRAW_LEN * 473.0 / 2007.0, MISSILE_DRAW_LEN),
		func():
			return _missiles.map(func(m): return {"pos": m["pos"], "rot": float(m["facing"]) + PI * 0.5}))
	_register_plume("mortarbullet", PROJ_PLUME_MAX, Vector2(MORTAR_BULLET_LEN * 100.0 / 329.0, MORTAR_BULLET_LEN),
		func():
			return _mortar_bullets.map(func(b): return {"pos": b["pos"], "rot": (b["vel"] as Vector2).angle() + PI * 0.5}))
	# Swarm trails — one plume pool per form; the provider returns only the balls currently in that form, so a
	# ball's trail switches Swarmball -> Swarmbot when it arms. TP offset/style come from Weapon Edit (per sprite).
	var _sball_sz := Vector2(SBALL_DRAW, SBALL_DRAW)
	if _swarmball_tex != null and _swarmball_tex.get_size().x > 0.0:
		_sball_sz.y = SBALL_DRAW * _swarmball_tex.get_size().y / _swarmball_tex.get_size().x
	var _sbot_sz := Vector2(SBALL_BOT_DRAW, SBALL_BOT_DRAW)
	if _swarmbot_tex != null and _swarmbot_tex.get_size().x > 0.0:
		_sbot_sz.y = SBALL_BOT_DRAW * _swarmbot_tex.get_size().y / _swarmbot_tex.get_size().x
	_register_plume("Swarmball", SBALL_COUNT, _sball_sz,
		func():
			if not _swarm_active: return []
			var out: Array = []
			for b: Dictionary in _swarm_units:
				if not bool(b.get("bot", false)): out.append({"pos": b["pos"], "rot": float(b["ang"])})
			return out)
	_register_plume("Swarmbot", SBALL_COUNT, _sbot_sz,
		func():
			if not _swarm_active: return []
			var out: Array = []
			for b: Dictionary in _swarm_units:
				if bool(b.get("bot", false)): out.append({"pos": b["pos"], "rot": float(b["ang"])})
			return out)
	_load_all_plumes()
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
	_orbital_impact_player = AudioStreamPlayer.new()
	_orbital_impact_player.stream = SFX_ORBITAL_IMPACT
	_orbital_impact_player.bus = "SFX"
	add_child(_orbital_impact_player)
	_db_charge_player = AudioStreamPlayer.new()
	_db_charge_player.stream = SFX_DEATHBEAM_CHARGE
	_db_charge_player.bus = "SFX"
	add_child(_db_charge_player)
	_db_beam_player = AudioStreamPlayer.new()
	_db_beam_player.stream = SFX_DEATHBEAM_BEAM
	_db_beam_player.bus = "SFX"
	add_child(_db_beam_player)
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
	_crit_font = load("res://assets/fonts/Gameplay.ttf") as FontFile   # load ONCE, not per crit number

## Fallback (see GAUSS_USE_SPRITE_VFX): load the 24-frame Gauss plasma-orb flipbook (individual transparent
## PNGs). CPU Image.load (no import dependency). The FULL frame is kept (NOT cropped to get_used_rect): the
## glow pulses, so per-frame content bounds vary — cropping + fixed-size draw would make the orb appear to
## grow/shrink. All frames share one centered canvas, so the full-frame draw keeps a constant size; only the
## plasma animates.
func _load_gauss_frames() -> void:
	for i in GAUSS_FRAME_COUNT:
		var path := "%sgauss24_%02d.png" % [GAUSS_ORB_DIR, i]
		var img := Image.new()
		if img.load(path) != OK:
			push_warning("arena_weapons: could not load Gauss orb frame %s" % path)
			continue
		_gauss_frames.append(ImageTexture.create_from_image(img))

## Fallback (see GAUSS_USE_SPRITE_VFX): load the 3 explosion variants (12 transparent frames each) into
## _expl_frames[variant][frame]. CPU Image.load (no import dependency), same approach as the orb flipbook.
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

## Load the orbital sprite from ORBITAL_SPRITE. If the image has a white background (ORBITAL_KEY_THR),
## key it out so only the orb silhouette remains.
func _load_orbital_tex() -> void:
	var abs_path := ProjectSettings.globalize_path(ORBITAL_SPRITE)
	var img := Image.load_from_file(abs_path)
	if img == null:
		push_warning("arena_weapons: orbital sprite not found at " + ORBITAL_SPRITE)
		return
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.r8 >= ORBITAL_KEY_THR and px.g8 >= ORBITAL_KEY_THR and px.b8 >= ORBITAL_KEY_THR:
				img.set_pixel(x, y, Color(px.r, px.g, px.b, 0.0))
	_orbital_tex = ImageTexture.create_from_image(img)
	_orbital_tex_size = Vector2(img.get_width(), img.get_height())

## Light sources this weapon currently emits, for the dust field: one per live projectile/beam.
## Each: {pos: world Vector2, value: float (light strength), color: Color}.
func get_lights() -> Array:
	# Built once per frame and cached: both arena_dust and arena_asteroids call this every frame, and it
	# rebuilds a dict per live bullet/orb/arc — no need to do that twice (or allocate it fresh per consumer).
	var lf := Engine.get_process_frames()
	if lf == _lights_frame:
		return _lights_cache
	_lights_frame = lf
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
	if _death_beam_active and _beam_light_on:
		# Light points sampled along the beam → the dust glows the whole length of the laser.
		for i in DEATHBEAM_LIGHT_SAMPLES:
			var f := float(i) / float(maxi(1, DEATHBEAM_LIGHT_SAMPLES - 1))
			lights.append({"pos": _beam_light_from.lerp(_beam_light_to, f), "value": DEATHBEAM_LIGHT, "color": _beam_light_col})
	if (_orbital_active or _singularity_active) and _player != null and is_instance_valid(_player):
		for c: Vector2 in _orbital_positions():
			lights.append({"pos": c, "value": ORBITAL_LIGHT, "color": ORBITAL_COL})
	if _striker_active:
		for ball: Dictionary in _striker_balls:
			lights.append({"pos": ball["pos"], "value": STRIKER_LIGHT, "color": STRIKER_COL})
	if _shooter_active:
		for orb: Dictionary in _shooter_orbs:
			lights.append({"pos": orb["pos"], "value": SHOOTER_LIGHT, "color": SHOOTER_COL})
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
	if _yari_active and _yari_init:
		lights.append({"pos": _yari_pos, "value": 3.5, "color": YARI_COL})
	if _swarm_active:
		for u: Dictionary in _swarm_units:
			lights.append({"pos": u["pos"], "value": 2.0, "color": SWARM_COL})
	if (_snake_active or _predator_active) and not _snake_pts.is_empty():
		lights.append({"pos": _snake_pts[0], "value": 3.0, "color": SNAKE_COL})
	_lights_cache = lights
	return lights

## True when the equipment-driven loadout engine has a primary weapon equipped (so this default
## auto-gun should stand down and let the loadout engine fire instead).
func _loadout_has_primary() -> bool:
	var lo := get_tree().get_first_node_in_group("arena_loadout")
	return lo != null and lo.has_method("has_primary_weapon") and lo.has_primary_weapon()

## True when there's a valid target (enemy, boss, or ruin/lootbox) on screen — the master fire-gate every
## tick-based weapon (Shooter, Gatling, Gauss, Arc, Dragon, Sonic, Z-Sword, …) waits on before shooting.
## Must include ruins: they're a valid damage target too, so a ruin-only screen (no live enemy) should still
## let those weapons fire instead of standing idle.
func _has_enemy_on_screen() -> bool:
	if GameManager.has_method("is_boss_alive") and GameManager.is_boss_alive():
		return true
	var targets := _enemies() + _ruins()
	if targets.is_empty():
		return false
	var canvas_xform := get_viewport().get_canvas_transform()
	var vp_size := get_viewport().get_visible_rect().size
	var screen_rect := Rect2(Vector2.ZERO, vp_size).grow_individual(
		vp_size.x * 0.5, vp_size.y * 0.5, vp_size.x * 0.5, vp_size.y * 0.5)
	for en in targets:
		if not is_instance_valid(en):
			continue
		if screen_rect.has_point(canvas_xform * (en as Node2D).global_position):
			return true
	return false

var _enemy_cache: Array[Node] = []
var _enemy_cache_frame: int = -1

## Enemy list cached for the current frame. The weapon ticks below query the "arena_enemy" group dozens of
## times per frame; each call is O(total nodes), so with a big XP-orb / enemy population it became a real
## drain. This re-queries at most once per process frame. Every caller already guards is_instance_valid and
## arena_enemy.take_damage early-outs on dead enemies, so a within-frame-stale entry is harmless.
## The player's targetable enemies — CHARMED enemies are excluded (your weapons can't hit your own charmed allies).
func _enemies() -> Array[Node]:
	var f := Engine.get_process_frames()
	if f != _enemy_cache_frame:
		_enemy_cache_frame = f
		var out: Array[Node] = []
		for e in get_tree().get_nodes_in_group("arena_enemy"):
			if is_instance_valid(e) and not (e.has_method("is_charmed") and e.call("is_charmed")):
				out.append(e)
		_enemy_cache = out
	return _enemy_cache

var _ruin_cache: Array[Node] = []
var _ruin_cache_frame: int = -1

var _lights_cache: Array = []
var _lights_frame: int = -1

## Ruins (group "arena_ruin"), cached once per frame — same rationale as _enemies(). Small group, but several
## weapon ticks iterated it per-bullet/per-tick, so the per-call group lookup + array alloc added up.
func _ruins() -> Array[Node]:
	var f := Engine.get_process_frames()
	if f != _ruin_cache_frame:
		_ruin_cache_frame = f
		_ruin_cache = get_tree().get_nodes_in_group("arena_ruin")
	return _ruin_cache

# ── Spatial hash grid over the enemies (rebuilt once per frame from _enemies()) ──────────────────────────
# Point-collision weapons with MANY projectiles (gatling/gauss/orbital/mortar) used to test EVERY projectile
# against EVERY enemy — O(projectiles × enemies), which is what collapsed the frame rate at 500 enemies. The
# grid buckets enemies by cell so each projectile only checks the handful of enemies in nearby cells.
const GRID_CELL := 128.0
const ENEMY_MAX_HIT_R := 120.0   # query pad ≥ the largest enemy hit radius (+ test slack) so none is missed
var _grid: Dictionary = {}       # Vector2i cell → Array[Node]
var _grid_frame: int = -1

func _grid_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / GRID_CELL)), int(floor(p.y / GRID_CELL)))

## Rebuild the enemy grid once per frame (cheap: one O(enemies) pass, shared by every projectile query).
func _rebuild_grid() -> void:
	var f := Engine.get_process_frames()
	if f == _grid_frame:
		return
	_grid_frame = f
	_grid.clear()
	for e in _enemies():
		if not is_instance_valid(e):
			continue
		var cell := _grid_cell((e as Node2D).global_position)
		if _grid.has(cell):
			(_grid[cell] as Array).append(e)
		else:
			_grid[cell] = [e]

## Enemies in cells overlapping [pos ± radius] — a SUPERSET; the caller still does the precise distance + valid
## test. Returns a fresh array each call (safe to iterate even if another query runs afterward).
func _enemies_near(pos: Vector2, radius: float) -> Array:
	_rebuild_grid()
	var out: Array = []
	var minc := _grid_cell(pos - Vector2(radius, radius))
	var maxc := _grid_cell(pos + Vector2(radius, radius))
	for cy in range(minc.y, maxc.y + 1):
		for cx in range(minc.x, maxc.x + 1):
			var cell := Vector2i(cx, cy)
			if _grid.has(cell):
				out.append_array(_grid[cell] as Array)
	return out

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		if _companion and _player_ref != null and is_instance_valid(_player_ref):
			_player = _player_ref
		else:
			_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# Project Phoenix: count down the 10-minute Player-2 shutdown, then bring the companions back.
	if not _companion and _player2_phoenix_cd > 0.0:
		_player2_phoenix_cd = maxf(0.0, _player2_phoenix_cd - delta)
		if _player2_phoenix_cd <= 0.0:
			_respawn_player2()
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
		var gat_interval := GAT_FIRE_INTERVAL * _cd_scale("gatling_gun") / (_rate_mult * (1.0 + _gat_fire_bonus()))   # Quick Round + Lv5 + Lights-Out
		_gat_acc += delta
		if enemy_on_screen:
			while _gat_acc >= gat_interval:
				_gat_acc -= gat_interval
				_fire_gatling()
		else:
			# No target: stay primed for exactly ONE immediate shot — do NOT bank a backlog, or the moment a
			# target appears the while-loop above dumps every banked interval at once (the "wall of bullets" + lag).
			_gat_acc = minf(_gat_acc, gat_interval)
	# Fire any staggered right-wing gatling bullets whose 0.2s delay has now elapsed (drains even mid-swap).
	_drain_gat_pending(delta)
	if _gauss_active:
		# Keep charging while waiting; fire only when an enemy is visible.
		_gauss_charge += delta
		if _gauss_charge >= _gauss_charge_time() * _cd_scale("gauss") / _rate_mult and enemy_on_screen:
			_gauss_charge = 0.0
			_fire_gauss()
	if _arc_active and enemy_on_screen:
		_fire_arc(delta)
	if _red_x_active:
		_tick_dragon(delta, enemy_on_screen)   # Dragon's Breath: continuous cone-fire DPS
	if _chemtrail_active:
		_tick_chemtrail(delta)
	if _orbital_active:
		_tick_orbital(delta)
	if _striker_active:
		_tick_striker(delta)
	if _shooter_active:
		_tick_shooter(delta, enemy_on_screen)
	if _void_active:
		_tick_void(delta)
	if _mortar_active:
		_tick_mortar(delta)
	if not _mortar_bullets.is_empty():
		_tick_mortar_bullets(delta)
	if not _wasteland_zones.is_empty():
		_tick_wasteland(delta)
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
	if _para_active or not _para_gas_puffs.is_empty():
		_update_para_gas_fx(delta)
	if _moro_active:
		_tick_moro(delta)
	if _yari_active:
		_tick_yari(delta)
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
	if _death_beam_active:
		if enemy_on_screen:
			_fire_death_beam(delta)
		else:
			_db_is_firing = false   # not firing → Lights-Out off
			# Pause the lasgun cycle — stop beam visuals/audio but don't reset _db_t.
			if _db_beam_playing:
				_db_beam_player.stop()
				_db_beam_playing = false
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
	_update_all_plumes()
	queue_redraw()

## Decay the Gatling muzzle-fire flash and feed the FX child the two wing-muzzle positions + aim each frame.
func _update_gat_muzzle(delta: float) -> void:
	_gat_muzzle_t = maxf(0.0, _gat_muzzle_t - delta / GAT_MUZZLE_DECAY)
	if _gat_muzzle_fx == null:
		return
	if _gat_active and _gat_muzzle_t > 0.0 and _player != null and is_instance_valid(_player):
		var fwd := _forward()
		var muzzles: Array
		if _has_anchors():
			muzzles = [_mz(2), _mz(3)]   # twin barrels = points 2 & 3
		else:
			var perp := Vector2(-fwd.y, fwd.x)
			var base := _player.global_position + fwd * GAT_WING_FWD
			muzzles = [base - perp * (GAT_WING_SPACING * 0.5), base + perp * (GAT_WING_SPACING * 0.5)]
		_gat_muzzle_fx.set_state(muzzles, fwd, _gat_muzzle_t, GAT_CORE_COL, GAT_BODY_COL, GAT_EDGE_COL)
	else:
		_gat_muzzle_fx.set_state([], Vector2.UP, 0.0, GAT_CORE_COL, GAT_BODY_COL, GAT_EDGE_COL)

# ── Aim helpers ───────────────────────────────────────────────────────────────
func _forward() -> Vector2:
	return Vector2.UP.rotated(_player.rotation)

func _muzzle() -> Vector2:
	# Point 1 is the shared forward muzzle (gauss / death beam / arc / dragon's breath / venomancer).
	if _has_anchors():
		return _mz(1)
	return _player.global_position + _forward() * MUZZLE_OFFSET

# ── Anchored muzzle points (placed in ship_rotation_test, projected by the arena) ──
var _arena_ref: Node = null

func _arena() -> Node:
	if _arena_ref == null or not is_instance_valid(_arena_ref):
		_arena_ref = get_tree().get_first_node_in_group("arena")
	return _arena_ref

## True when the ship model has muzzle anchors loaded — weapons use them; otherwise keep legacy offsets.
func _has_anchors() -> bool:
	var a := _arena()
	return a != null and a.has_method("has_muzzle_anchors") and a.has_muzzle_anchors()

## World muzzle position for anchor `slot` (follows heading + bank). Falls back to the legacy forward point.
func _mz(slot: int) -> Vector2:
	var a := _arena()
	if a != null and a.has_method("muzzle_world"):
		return a.muzzle_world(slot)
	return _player.global_position + _forward() * MUZZLE_OFFSET   # legacy (no recursion into _muzzle)

## Base damage × the Damage-card multiplier, then a crit roll. Returns {dmg, is_crit}.
# ── Nanobots aux integration: "automation" weapons + the "+Bodies" mech ───────────────────────────────────
# Automation weapons benefit from Nanobots' Automation Speed perk (mech "automation_speed" → attack/move speed)
# and the Nanobots-Attack! evolution (mech "automation_dmg" → damage). "+2 Bodies" (mech "body_count") adds
# count to orbitals/boomerang, length to the snake, and damage to the yari spears.
const AUTOMATION_KINDS := ["defensive_orbitals", "striker", "venomancer", "viper", "yari", "yari_jaeger", "swarm", "shooter"]
# Weapons that deal CONTACT damage (touch the enemy) → boosted by Contact Mastery (mech "contact_dmg_mult").
const CONTACT_KINDS := ["defensive_orbitals", "striker", "singularities", "swarm", "viper", "aliwa", "yari", "yari_jaeger", "z_sword"]
# Weapon damage FAMILY (the 3-family taxonomy) → Art of War per-family masteries + the X-Truth evolutions.
const WEAPON_FAMILY := {
	"gatling_gun": "kinetic", "defensive_orbitals": "kinetic", "striker": "kinetic", "shooter": "kinetic", "aliwa": "kinetic", "yari": "kinetic",
	"yari_jaeger": "kinetic", "swarm": "kinetic", "homing_missile": "kinetic", "mortar": "kinetic",
	"carnage": "kinetic",
	"death_beam": "energy", "arc": "energy", "gauss": "energy", "ultrasonicator": "energy", "rift_maker": "energy",
	"z_sword": "energy", "ionizing_field": "energy", "singularities": "energy",
	"overcharger": "energy", "predator": "energy",
	"chemtrail": "biochemical", "venomancer": "biochemical", "vampire_host": "biochemical", "toxic_ballistic": "biochemical",
	"viper": "biochemical", "dragons_breath": "biochemical",
	"chain": "kinetic",   # Explosivo Chain Reaction blast (kinetic family so kinetic/all/crit buffs apply)
}
# Weapons that deal AREA/splash damage → get the Explosivo "Bombardment Mastery" bonus (mech "bombardment_dmg").
const AOE_KINDS := ["mortar", "gauss", "ionizing_field", "ultrasonicator", "dragons_breath", "chemtrail", "venomancer", "rift_maker", "homing_missile"]
const BODY_SNAKE_LEN := 0.25   # +25% snake length per body (≈ +50% at +2 Bodies)
const BODY_YARI_DMG  := 0.50   # +50% yari damage per body (+100% at +2 Bodies)

func _is_automation(kind: String) -> bool:
	return kind in AUTOMATION_KINDS

func _is_contact(kind: String) -> bool:
	return kind in CONTACT_KINDS

## Serrated Heads applies bleed only from KINETIC or CONTACT weapons.
func _bleeds(kind: String) -> bool:
	return _is_contact(kind) or String((WEAPON_FAMILY as Dictionary).get(kind, "")) == "kinetic"

func _body_count() -> int:
	return int(round(GameManager.mech_bonus("body_count"))) if GameManager.has_method("mech_bonus") else 0

## Orbital ball count: base + Bodies. The Singularities fusion stays pinned at ORBITAL_BALLS (its O-V-O-V-O-V
## interleaving assumes exactly 3); base orbital and the fusion are mutually exclusive, so the active flag picks.
func _orbital_count() -> int:
	return ORBITAL_BALLS + _body_count()
func _orbital_n() -> int:
	return ORBITAL_BALLS if _singularity_active else _orbital_count()

## Snake segment count: base + Elongate pool + Primordial God kill-growth + 25% length per Nanobots Body.
func _snake_len() -> int:
	var n := SNAKE_SEGMENTS + int(_snake_upg["length"]) + _snake_primordial_segs()
	n += int(round(float(SNAKE_SEGMENTS) * BODY_SNAKE_LEN * float(_body_count())))
	return n

## Primordial God: +1 body segment per SNAKE_KILLS_PER_SEG snake-kills, capped at SNAKE_PRIMORDIAL_CAP.
func _snake_primordial_segs() -> int:
	if _snake_capstone != "primordial_god":
		return 0
	return mini(SNAKE_PRIMORDIAL_CAP, _snake_kills / SNAKE_KILLS_PER_SEG)

# ── Snake upgrade API (pool ranks + evolve capstone) ──
func snake_upgrade_rank(id: String) -> int:
	return int(_snake_upg.get(id, 0))

func snake_grant_upgrade(id: String) -> bool:
	if not SNAKE_POOL.has(id):
		return false
	var maxr := int(SNAKE_POOL[id]["max"])
	if maxr > 0 and int(_snake_upg.get(id, 0)) >= maxr:
		return false
	_snake_upg[id] = int(_snake_upg.get(id, 0)) + 1
	if id == "hemophilia" and GameManager.has_method("add_mech"):
		GameManager.add_mech("bleed_dur_pct", 0.20)   # GLOBAL: +20% bleed duration per rank
	return true

func snake_set_capstone(id: String) -> void:
	_snake_capstone = id
	if id == "anemia" and GameManager.has_method("add_mech"):
		GameManager.add_mech("anemia_vuln", 1.0)   # flag: enemies take +1% dmg per 10 bleed stacks (enemy-side)

func _snake_dmg() -> float:
	return SNAKE_DAMAGE * (1.0 + 0.10 * float(_snake_upg["damage"]))
func _snake_speed_mult() -> float:
	return 1.0 + 0.10 * float(_snake_upg["speed"])

## Speed multiplier (≥1) for an automation weapon's attack/move/spin rate; 1.0 for non-automation weapons.
func _automation_rate(kind: String) -> float:
	if not _is_automation(kind):
		return 1.0
	return 1.0 + (GameManager.mech_bonus("automation_speed") if GameManager.has_method("mech_bonus") else 0.0)

## Fins Speed Mastery: travel-speed multiplier (≥1) for projectiles + orbiting minions.
func _weapon_speed_mult() -> float:
	return 1.0 + (GameManager.weapon_speed_bonus() if GameManager.has_method("weapon_speed_bonus") else 0.0)

func _roll_damage(base: float, kind := "") -> Dictionary:
	var dmg := base * _dmg_mult * _lvl_mult(kind) * _dmg_scale   # _dmg_scale = 0.25× (× P2 Overclock) on the companion
	if not _p2_fam_bonus.is_empty():                              # Player-2 colour coats: +% for the copied weapon's family
		dmg *= 1.0 + float(_p2_fam_bonus.get(String(WEAPON_FAMILY.get(kind, "")), 0.0))
	if kind in AOE_KINDS:                                         # Explosivo Bombardment Mastery
		dmg *= 1.0 + (GameManager.mech_bonus("bombardment_dmg") if GameManager.has_method("mech_bonus") else 0.0)
	if _is_automation(kind):
		dmg *= 1.0 + (GameManager.mech_bonus("automation_dmg") if GameManager.has_method("mech_bonus") else 0.0)
	if _is_contact(kind):
		dmg *= 1.0 + (GameManager.mech_bonus("contact_dmg_mult") if GameManager.has_method("mech_bonus") else 0.0)   # Contact Mastery
	if kind == "yari" or kind == "yari_jaeger":
		dmg *= 1.0 + BODY_YARI_DMG * float(_body_count())   # +Bodies → yari spears gain damage
	# Art of War masteries (GLOBAL, shared by name across items): General (all) + per-family damage.
	if GameManager.has_method("mech_bonus"):
		dmg *= 1.0 + GameManager.mech_bonus("all_dmg")
		var fam := String((WEAPON_FAMILY as Dictionary).get(kind, ""))
		match fam:
			"kinetic":    dmg *= 1.0 + GameManager.mech_bonus("kinetic_dmg")
			"energy":     dmg *= 1.0 + GameManager.mech_bonus("energy_dmg")
			"biochemical": dmg *= 1.0 + GameManager.mech_bonus("bio_dmg")
		# "X Truth" evo: surviving family gains +50% damage per weapon disabled.
		if fam != "" and fam == _truth_family:
			dmg *= 1.0 + 0.50 * float(_truth_count)
		# Auto-Loader Charged Up evo: weapons WITH a cooldown gain +20% damage per 0.5s of base cd.
		if GameManager.mech_bonus("charged_up") > 0.0:
			var cd := _base_cd(kind)
			if cd > 0.0:
				dmg *= 1.0 + 0.20 * floorf(cd / 0.5)
		# Auto-Loader Speed is Force evo: contact weapons add their TOTAL fire-rate bonus as damage —
		# global fire rate + the weapon's OWN family cadence (_fam_rate already keys off this kind's family).
		if GameManager.mech_bonus("speed_force") > 0.0 and _is_contact(kind):
			var fr_bonus := maxf(0.0, GameManager.get_fire_rate_mult() - 1.0) + maxf(0.0, _fam_rate(kind) - 1.0)
			dmg *= 1.0 + fr_bonus
	var is_crit := false
	var local_crit := (_zsword_crit() if kind == "z_sword" else 0.0) + (_shooter_crit() if kind == "shooter" else 0.0)
	var crit_ch := _crit_chance + local_crit   # local (non-shared) crit
	var crit_dmg := _crit_damage
	# Deadly (Aim Assistor evo): use the UNCLAMPED crit chance — anything over 100% becomes bonus crit damage.
	if GameManager.has_method("mech_bonus") and GameManager.mech_bonus("crit_overflow") > 0.0:
		var raw := BASE_CRIT_CHANCE + GameManager.upg_crit_chance + local_crit
		if raw > 1.0:
			crit_dmg += raw - 1.0
		crit_ch = raw
	if _proc(crit_ch):   # crit chance + Stroke of Luck
		dmg *= crit_dmg
		is_crit = true
		if not _companion and GameManager.has_method("add_fervor"):
			GameManager.add_fervor()   # Challenge Accepted: a crit builds a Fervor stack (no-op unless evolved)
	return {"dmg": dmg, "is_crit": is_crit}

# Crit-number popups are POOLED and capped. Previously each crit allocated a fresh Label + font load() + Tween,
# fired from ~35 damage sites inside AoE-per-enemy loops → hundreds of node allocations/frame on a dense wave.
# Now labels are recycled and concurrent count is bounded (illegible past a few dozen on screen anyway).
const CRIT_NUM_MAX_ACTIVE := 40
var _crit_font: FontFile = null
var _crit_pool: Array = []       # recycled hidden Label nodes ready for reuse
var _crit_active: int = 0        # currently-animating crit labels (bounded by CRIT_NUM_MAX_ACTIVE)

func _make_crit_label() -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _crit_font != null:
		lbl.add_theme_font_override("font", _crit_font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.15, 0.10))
	lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 7)
	_crit_host.add_child(lbl)
	return lbl

func _recycle_crit_label(lbl: Label) -> void:
	_crit_active = maxi(0, _crit_active - 1)
	if not is_instance_valid(lbl):
		return
	lbl.visible = false
	_crit_pool.append(lbl)

func _spawn_crit_number(world_pos: Vector2, amount: float) -> void:
	if _crit_host == null or _crit_active >= CRIT_NUM_MAX_ACTIVE:
		return   # over the on-screen cap → skip (spawning more would just be an unreadable smear)
	_crit_active += 1
	var lbl: Label = _crit_pool.pop_back() if not _crit_pool.is_empty() else _make_crit_label()
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	lbl.text = str(roundi(amount))
	lbl.modulate.a = 1.0
	lbl.reset_size()
	lbl.position = screen_pos + Vector2(randf_range(-10.0, 10.0), -16.0) - lbl.size * 0.5
	lbl.scale = Vector2.ONE * 1.6
	lbl.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 48.0, 0.80)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.80).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _recycle_crit_label(lbl))

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
	if GameManager.has_method("add_mech"):
		if id == "advance_ballistic":
			GameManager.add_mech("multishot_pct", 0.10)   # GLOBAL: shots-tagged weapons read mech_bonus("multishot_pct")
	return true

func gat_set_capstone(id: String) -> void:
	_gat_capstone = id

func _gat_lvl() -> int:
	return weapon_level("gatling_gun")   # 0 if unowned, 1..7

func _gat_pierce_chance() -> float:
	return clampf(float(_gat_upg["piercing"]) * 0.20, 0.0, 1.0)

## How many times a freshly-fired bullet may ricochet: +1 per Bouncing Round rank (pool caps rank at 5).
func _gat_bounces() -> int:
	return int(_gat_upg["bouncing"])

func _gat_fire_bonus() -> float:
	return float(_gat_upg["quick"]) * 0.16

func _gat_multishot_chance() -> float:
	var glob: float = GameManager.mech_bonus("multishot_pct") if GameManager.has_method("mech_bonus") else 0.0
	return float(_gat_upg["multishot"]) * 0.25 + glob   # local ranks + global (Advance Ballistic etc.)

func _gat_multishot_flat() -> int:
	return 2 if _gat_capstone == "spray" else 0   # Spray and Pray capstone

func _gat_spread_deg() -> float:
	return 15.0 if _gat_capstone == "spray" else GAT_SPREAD_DEG   # Spray and Pray → much wider fan

## Per-bullet base damage before crit/global mult. Kinetic mastery is GLOBAL (applied in _roll_damage).
func _gat_bullet_base() -> float:
	return (GAT_DAMAGE + 2.0 * float(_gat_upg["hardened"])) * (1.0 + 0.10 * float(_gat_upg["piercing"]))   # Piercing Round: +10% dmg/rank

func _fire_gatling() -> void:
	# Twin-barrel volley: LEFT-wing bullets (even slot n) fire immediately; RIGHT-wing bullets (odd n)
	# fire GAT_FIRE_STAGGER (0.2s) later — so the left barrel visibly leads the right. Any Multishot extra
	# bullets fan out to wider slots but keep the same even=now / odd=+delay rule.
	var ms := _gat_multishot_chance()    # total multishot value (0.25/rank + globals); 1.0 = one guaranteed extra
	var extra := _gat_multishot_flat()   # Spray and Pray capstone flat bonus
	extra += int(ms)                     # every full 100% = a guaranteed extra bullet (triple, quad, …)
	if _proc(ms - float(int(ms))):       # leftover fraction = chance for one more (+ Stroke of Luck)
		extra += 1
	var total := 2 + extra
	for n in total:
		if n % 2 == 0:
			_spawn_gat_bullet(n)                                  # left wing: fire now
		else:
			_gat_pending.append({"delay": GAT_FIRE_STAGGER, "n": n})   # right wing: fire 0.2s later

## Build + fire one gatling bullet for slot index `n`, computed from the ship's CURRENT position/facing
## (so delayed right-wing shots still leave the moving ship's real muzzle, not a stale point).
func _spawn_gat_bullet(n: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var fwd := _forward()
	var spread := _gat_spread_deg()
	var dir := fwd
	if spread > 0.0:
		dir = fwd.rotated(deg_to_rad(randf_range(-spread, spread)))
	var start: Vector2
	if _has_anchors():
		# Twin barrels = points 2 & 3; multishot extras spray from points 1 / 7 / 8 at random.
		if n == 0:
			start = _mz(2)
		elif n == 1:
			start = _mz(3)
		else:
			start = _mz([1, 7, 8][randi() % 3])
	else:
		var perp := Vector2(-fwd.y, fwd.x)   # right-perpendicular (rotates with the ship)
		var base := _player.global_position + fwd * GAT_WING_FWD
		var slot := float(n / 2)                  # 0,0,1,1,2,2…  (pair index → distance out)
		var sgn := -1.0 if (n % 2 == 0) else 1.0   # alternate left / right
		start = base + perp * (sgn * GAT_WING_SPACING * (0.5 + slot * 0.6))
	var bullet := {"pos": start, "vel": dir * GAT_SPEED * _weapon_speed_mult(), "life": 0.0, "start": start, "kind": "gatling_gun", "hits": [], "bounces": _gat_bounces()}
	# Healing Round capstone: a directly-fired bullet has a 1-in-GAT_HEAL_ODDS chance to be a healing bullet.
	if _gat_capstone == "healing" and randi() % GAT_HEAL_ODDS == 0:
		bullet["healing"] = true
	_bullets.append(bullet)
	_gat_muzzle_t = 1.0   # refresh the muzzle-fire flash on every shot

## Advance the staggered right-wing gatling shots; fire each when its delay elapses. Called every tick.
func _drain_gat_pending(delta: float) -> void:
	if _gat_pending.is_empty():
		return
	var still: Array = []
	for e: Dictionary in _gat_pending:
		e["delay"] = float(e["delay"]) - delta
		if float(e["delay"]) <= 0.0:
			_spawn_gat_bullet(int(e["n"]))
		else:
			still.append(e)
	_gat_pending = still

# ── Lasgun (tick-based hitscan beam — fires along the ship facing = toward the cursor) ───────────────────
# ── Generic skill-point pool dispatch (the level-up UI calls these for any weapon that has a pool) ──
func pool_rank(kind: String, id: String) -> int:
	match kind:
		"gatling_gun": return gat_upgrade_rank(id)
		"death_beam":  return db_upgrade_rank(id)
		"arc":     return arc_upgrade_rank(id)
		"gauss":   return gauss_upgrade_rank(id)
		"defensive_orbitals": return orbital_upgrade_rank(id)
		"dragons_breath":   return int(_red_x_upg.get(id, 0))
		"chemtrail": return int(_chem_upg.get(id, 0))
		"z_sword":  return int(_zsword_upg.get(id, 0))
		"ultrasonicator":   return int(_sonic_upg.get(id, 0))
		"mortar":  return mortar_upgrade_rank(id)
		"venomancer": return para_upgrade_rank(id)
		"aliwa": return boom_upgrade_rank(id)
		"viper":    return snake_upgrade_rank(id)
		"shooter":  return shooter_upgrade_rank(id)
		"ionizing_field":   return ionize_upgrade_rank(id)
		"player_2": return player2_upgrade_rank(id)
	return 0

func pool_grant(kind: String, id: String) -> bool:
	match kind:
		"gatling_gun": return gat_grant_upgrade(id)
		"death_beam":  return db_grant_upgrade(id)
		"arc":     return arc_grant_upgrade(id)
		"gauss":   return gauss_grant_upgrade(id)
		"defensive_orbitals": return orbital_grant_upgrade(id)
		"dragons_breath":   return red_x_grant_upgrade(id)
		"chemtrail": return chem_grant_upgrade(id)
		"z_sword":  return zsword_grant_upgrade(id)
		"ultrasonicator":   return sonic_grant_upgrade(id)
		"mortar":  return mortar_grant_upgrade(id)
		"venomancer": return para_grant_upgrade(id)
		"aliwa": return boom_grant_upgrade(id)
		"viper":    return snake_grant_upgrade(id)
		"shooter":  return shooter_grant_upgrade(id)
		"ionizing_field":   return ionize_grant_upgrade(id)
		"player_2": return player2_grant_upgrade(id)
	return false

func pool_set_capstone(kind: String, id: String) -> void:
	match kind:
		"gatling_gun": gat_set_capstone(id)
		"death_beam":  db_set_capstone(id)
		"arc":     arc_set_capstone(id)
		"gauss":   gauss_set_capstone(id)
		"defensive_orbitals": orbital_set_capstone(id)
		"dragons_breath":   red_x_set_capstone(id)
		"chemtrail": _chem_capstone = id
		"z_sword":  _zsword_capstone = id
		"ultrasonicator":   _sonic_capstone = id
		"mortar":  mortar_set_capstone(id)
		"venomancer": para_set_capstone(id)
		"aliwa": boom_set_capstone(id)
		"viper":    snake_set_capstone(id)
		"shooter":  shooter_set_capstone(id)
		"ionizing_field":   ionize_set_capstone(id)
		"swarm":    _swarm_capstone = id
		"player_2": player2_set_capstone(id)
	# All-In: lose a weapon slot. If you're at/over the new cap, the UI must destroy one first (it checks
	# weapons_full() before applying); here we just lower the capacity.
	if kind == "death_beam" and id == "all_in":
		_slot_penalty += 1

## The level-6 evolve options for a weapon (empty if it has none).
func weapon_capstones(kind: String) -> Array:
	return (CAPSTONES as Dictionary).get(kind, [])

## The capstone already chosen for a weapon ("" if none).
func weapon_capstone(kind: String) -> String:
	match kind:
		"gatling_gun": return _gat_capstone
		"death_beam":  return _db_capstone
		"arc":     return _arc_capstone
		"gauss":   return _gauss_capstone
		"defensive_orbitals": return _orbital_capstone
		"dragons_breath":   return _red_x_capstone
		"chemtrail": return _chem_capstone
		"z_sword":  return _zsword_capstone
		"ultrasonicator":   return _sonic_capstone
		"mortar":  return _mortar_capstone
		"venomancer": return _para_capstone
		"aliwa": return _boom_capstone
		"viper":    return _snake_capstone
		"shooter":  return _shooter_capstone
		"ionizing_field":   return _ionize_capstone
		"swarm":    return _swarm_capstone
		"player_2": return _player2_capstone
	return ""

## True when a weapon just earned its evolve pick: at max level, has capstones, none chosen yet.
func weapon_needs_capstone(kind: String) -> bool:
	return weapon_level(kind) >= MAX_WEAPON_LEVEL and not weapon_capstones(kind).is_empty() and weapon_capstone(kind) == ""

## Destroy an owned weapon (used by the All-In slot-loss choice).
func destroy_weapon(kind: String) -> void:
	if kind in _acquired:
		_acquired.erase(kind)
		_levels.erase(kind)
		_wpoints.erase(kind)
		_deactivate_kind(kind)

# ── Lasgun upgrades: API + effective stats (ranks + level rewards). Status (incinerate/freeze) = Stage 2. ──
func db_upgrade_rank(id: String) -> int:
	return int(_db_upg.get(id, 0))

func db_grant_upgrade(id: String) -> bool:
	if not DEATHBEAM_POOL.has(id):
		return false
	var maxr := int(DEATHBEAM_POOL[id]["max"])
	if maxr > 0 and int(_db_upg.get(id, 0)) >= maxr:
		return false
	_db_upg[id] = int(_db_upg.get(id, 0)) + 1
	if GameManager.has_method("add_mech"):
		if id == "energy":
			GameManager.add_mech("energy_dmg", 0.10)      # GLOBAL: energy weapons read mech_bonus("energy_dmg")
		elif id == "duration":
			GameManager.add_mech("duration_pct", 0.10)    # GLOBAL: duration weapons read mech_bonus("duration_pct")
	return true

func db_set_capstone(id: String) -> void:
	_db_capstone = id

func _db_lvl() -> int:
	return weapon_level("death_beam")

## Beam damage per tick: base × Overcharge ranks. Energy/all masteries applied centrally in _roll_damage.
func _db_dmg() -> float:
	var local := 1.0 + float(_db_upg["damage"]) * 0.10
	var allin := 3.0 if _db_capstone == "all_in" else 1.0   # All-In: +200% damage
	return DEATHBEAM_DAMAGE * local * allin

## Firing-cycle length: Heat Sink ranks (floored so it never collapses).
func _db_cycle() -> float:
	var reduction := float(_db_upg["cooldown"]) * 0.05
	return DEATHBEAM_CYCLE * maxf(0.25, 1.0 - reduction)

## Beam-on time: Capacitor (global duration), clamped to keep a little off-time.
func _db_duration() -> float:
	var dur_global: float = GameManager.mech_bonus("duration_pct") if GameManager.has_method("mech_bonus") else 0.0
	var mult := 1.0 + dur_global
	return minf(DEATHBEAM_DURATION * mult, _db_cycle() - 0.3)

## Beam half-width multiplier (no level scaling).
func _db_width_mult() -> float:
	return 1.0

## Burn-apply chance PER SECOND (Incinerate ranks). Rolled per damage tick, scaled by the tick interval.
func _db_incinerate_rate() -> float:
	return float(_db_upg["incinerate"]) * 0.05

## Freeze-apply chance PER SECOND (Freeze ranks).
func _db_freeze_rate() -> float:
	return float(_db_upg["freeze"]) * 0.05

## Lights-Out capstone: while the Lasgun beam fires, every OTHER weapon's cooldown is scaled ×0.7 (-30%).
func _cd_scale(kind: String) -> float:
	var base := 0.7 if (kind != "death_beam" and _death_beam_active and _db_capstone == "lights_out" and _db_is_firing) else 1.0
	return base / _fam_rate(kind)   # Auto-Loader per-family fire rate (faster cadence → smaller cd multiplier)

## Per-family fire-rate multiplier (≥1) from Auto-Loader's kinetic/energy/bio rate masteries; 1.0 if no family.
func _fam_rate(kind: String) -> float:
	if not GameManager.has_method("mech_bonus"):
		return 1.0
	match String((WEAPON_FAMILY as Dictionary).get(kind, "")):
		"kinetic":    return 1.0 + GameManager.mech_bonus("rate_kinetic")
		"energy":     return 1.0 + GameManager.mech_bonus("rate_energy")
		"biochemical": return 1.0 + GameManager.mech_bonus("rate_bio")
	return 1.0

## Tick-frequency multiplier (≥1) — Auto-Loader Intensity Mastery speeds up DoT/tick weapons. Divide tick intervals by this.
func _tick_rate() -> float:
	return 1.0 + (GameManager.mech_bonus("tick_rate") if GameManager.has_method("mech_bonus") else 0.0)

## Base cooldown (s) per weapon kind — for the Charged Up evo. 0 = continuous (beam/cone/orbit) → no bonus.
func _base_cd(kind: String) -> float:
	match kind:
		"gatling_gun":     return GAT_FIRE_INTERVAL
		"gauss":       return GAUSS_CHARGE_TIME
		"arc":         return ARC_COOLDOWN
		"mortar":        return MORTAR_FIRE_INTERVAL
		"ultrasonicator":       return SONIC_COOLDOWN
		"z_sword":      return ZSWORD_COOLDOWN
		"venomancer":    return PARA_COOLDOWN
		"yari":   return MORO_ATTACK_CD
		"yari_jaeger": return YARI_ATTACK_CD
		"homing_missile":      return HOMING_INTERVAL
	return 0.0

# ── Stroke of Luck (Arc): a GLOBAL additive bonus to EVERY proc chance. `_proc()` is the canonical roller. ──
# RULE: any new chance/proc MUST roll via _proc(chance) so Stroke of Luck applies retroactively (see CLAUDE.md).
func _proc_luck() -> float:
	return GameManager.mech_bonus("proc_luck") if GameManager.has_method("mech_bonus") else 0.0

## Effect-duration multiplier from the Lasgun's Capacitor perk (global mech "duration_pct"). Applies to the
## weapons the user designated: Red X fire, Sonic rings, Gauss explosion, Chemtrail puffs (+ enemy statuses).
func _duration_mult() -> float:
	return 1.0 + (GameManager.mech_bonus("duration_pct") if GameManager.has_method("mech_bonus") else 0.0)

func _proc(chance: float) -> bool:
	if _companion and not _procs_enabled:
		return false   # Player 2 deals only its % copy — no crit, no status procs (until the Full Sync evolve)
	return randf() < (chance + _proc_luck())

# ── Arc upgrades: API + effective stats (ranks + level rewards). Stun/overflow/capstone mechanics = Stage 2/3. ──
func arc_upgrade_rank(id: String) -> int:
	return int(_arc_upg.get(id, 0))

func arc_grant_upgrade(id: String) -> bool:
	if not ARC_POOL.has(id):
		return false
	var maxr := int(ARC_POOL[id]["max"])
	if maxr > 0 and int(_arc_upg.get(id, 0)) >= maxr:
		return false
	_arc_upg[id] = int(_arc_upg.get(id, 0)) + 1
	if GameManager.has_method("add_mech"):
		if id == "luck":
			GameManager.add_mech("proc_luck", 0.01)            # GLOBAL: every _proc() chance reads this
		elif id == "lightning":
			GameManager.add_mech("lightning_stun_chance", 0.02)  # GLOBAL stun chance (Lightning Mastery)
			GameManager.add_mech("lightning_stun_dur", 0.05)     # GLOBAL stun duration
	return true

func arc_set_capstone(id: String) -> void:
	_arc_capstone = id
	if id == "dazzle" and GameManager.has_method("add_mech"):
		GameManager.add_mech("stun_immune_reduce", 0.5)   # Dazzling Display: halve all enemies' stun immunity

func _arc_lvl() -> int:
	return weapon_level("arc")

## Arc per-link damage: base × Overvolt ranks. Energy/all masteries applied centrally in _roll_damage.
func _arc_dmg() -> float:
	var local := 1.0 + float(_arc_upg["damage"]) * 0.10
	var holy := 1.0
	if _arc_capstone == "holy":
		holy = 1.0 + 1.5 * float(maxi(0, _arc_jumps_normal()))   # all would-be bounces converted to damage
	return ARC_DAMAGE * local * holy

## Chain count WITHOUT the Holy Bolt override (used to compute Holy's damage bonus).
func _arc_jumps_normal() -> int:
	return ARC_BASE_BOUNCE + int(_arc_upg["bounce"])

## Chain count: normal, or 0 (single target) under Holy Bolt.
func _arc_jumps() -> int:
	if _arc_capstone == "holy":
		return 0
	return _arc_jumps_normal()

## Fire-rate multiplier on the Arc cooldown (Rapid Discharge ranks).
func _arc_cd_mult() -> float:
	return 1.0 / (1.0 + float(_arc_upg["firerate"]) * 0.08)

## Per-hit chance to stun (Electrocute ranks + Lightning Mastery). Rolled via _proc (so Stroke of Luck applies).
func _arc_electrocute_chance() -> float:
	var lm: float = GameManager.mech_bonus("lightning_stun_chance") if GameManager.has_method("mech_bonus") else 0.0
	return float(_arc_upg["electrocute"]) * 0.05 + lm

## Stun duration: 0.5s normal / 0.2s boss, × Lightning Mastery duration bonus.
func _arc_stun_dur(is_boss: bool) -> float:
	var ld: float = GameManager.mech_bonus("lightning_stun_dur") if GameManager.has_method("mech_bonus") else 0.0
	return (0.2 if is_boss else 0.5) * (1.0 + ld)

# ── Gauss upgrades: API + effective stats (Orb of Annihilation vulnerability = Stage 2). ──
func gauss_upgrade_rank(id: String) -> int:
	return int(_gauss_upg.get(id, 0))

func gauss_grant_upgrade(id: String) -> bool:
	if not GAUSS_POOL.has(id):
		return false
	var maxr := int(GAUSS_POOL[id]["max"])
	if maxr > 0 and int(_gauss_upg.get(id, 0)) >= maxr:
		return false
	_gauss_upg[id] = int(_gauss_upg.get(id, 0)) + 1
	if id == "aoe_mastery" and GameManager.has_method("add_mech"):
		GameManager.add_mech("aoe_pct", 0.05)   # GLOBAL: _aoe_radius reads mech_bonus("aoe_pct")
	return true

func gauss_set_capstone(id: String) -> void:
	_gauss_capstone = id

func _gauss_lvl() -> int:
	return weapon_level("gauss")

## Common Gauss damage multiplier (Amplify ranks). Energy/all masteries applied centrally in _roll_damage.
func _gauss_dmg_factor() -> float:
	return 1.0 + float(_gauss_upg["damage"]) * 0.10

## Orb damage budget. Spirit Bomb's extra scaling is applied in _fire_gauss.
func _gauss_budget() -> float:
	return GAUSS_DAMAGE * _gauss_dmg_factor()

## Explosion DoT damage per tick.
func _gauss_tick_dmg() -> float:
	return GAUSS_TICK_DAMAGE * _gauss_dmg_factor()

## Charge time: 5s under Spirit Bomb, else base × fire-rate (Rapid Charge + Pew Pew +100%).
func _gauss_charge_time() -> float:
	if _gauss_capstone == "spirit_bomb":
		return 5.0
	var rate := 1.0 + float(_gauss_upg["cooldown"]) * 0.08 + (1.0 if _gauss_capstone == "pew" else 0.0)
	return GAUSS_CHARGE_TIME / rate

func _gauss_burn_chance() -> float:
	return float(_gauss_upg["meltdown"]) * 0.05

func _gauss_stun_chance() -> float:
	var lm: float = GameManager.mech_bonus("lightning_stun_chance") if GameManager.has_method("mech_bonus") else 0.0
	return float(_gauss_upg["emp"]) * 0.05 + lm

## Orb-size multiplier (Pew Pew: -75%).
func _gauss_size_mult() -> float:
	return 0.25 if _gauss_capstone == "pew" else 1.0

## How many orbs Fission would fire (each extra is a _proc roll, so Stroke of Luck applies). Capped at +5.
func _gauss_fission_count() -> int:
	var count := 1
	var ch := float(_gauss_upg["fission"]) * 0.10 + (GameManager.mech_bonus("multishot_pct") if GameManager.has_method("mech_bonus") else 0.0)
	for _i in 5:
		if _proc(ch):
			count += 1
		else:
			break
	return count

## Orbs fired this shot: Spirit Bomb collapses to a single (scaled) orb.
func _gauss_orb_count() -> int:
	return 1 if _gauss_capstone == "spirit_bomb" else _gauss_fission_count()

func _fire_death_beam(delta: float) -> void:
	# Duty cycle: fire for _db_duration() out of every _db_cycle() seconds, with a charge telegraph in the
	# last DEATHBEAM_CHARGE seconds before each burst.
	_db_t += delta
	var cyc := _db_cycle()
	var dur := _db_duration()
	var phase := fmod(_db_t, cyc)
	var firing := phase < dur
	_db_is_firing = firing   # Lights-Out reads this
	if not firing:
		# Charge telegraph (Chromeleon orb light-gather) in the last DEATHBEAM_CHARGE seconds before the burst.
		var charge_start := maxf(0.0, cyc - DEATHBEAM_CHARGE)
		if phase >= charge_start and _charge_fx != null:
			_charge_fx.position = _muzzle()   # follow the moving nose
			if not _db_charge_started:
				_charge_fx.start(DEATHBEAM_CHARGE)
				_db_charge_player.play()
				_db_charge_started = true
		if _beam != null:
			_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
		_beam_light_on = false
		_beam_cd = 0.0   # so the first damage tick lands the instant the burst starts
		_db_prev_valid = false   # beam is off — don't sweep-test across whatever the ship did while idle
		if _db_beam_playing:
			_db_beam_player.stop()
			_db_beam_playing = false
		return
	# Firing: kill the charge FX and arm the next cycle's telegraph.
	_db_charge_started = false
	if not _db_beam_playing:
		_db_beam_player.play()
		_db_beam_playing = true
	elif not _db_beam_player.playing:
		_db_beam_player.play()
	if _charge_fx != null:
		_charge_fx.stop()
	var from := _muzzle()
	var dir := _forward()
	# ONLY bosses block the beam. Find the nearest boss along the line; otherwise the beam runs to max range.
	var block_along := DEATHBEAM_RANGE
	var half_w := DEATHBEAM_WIDTH * 0.5 * _db_width_mult()   # AOE → wider beam
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		var tb: Vector2 = (b as Node2D).global_position - from
		var balong := tb.dot(dir)
		if balong < 0.0 or balong > DEATHBEAM_RANGE:
			continue
		var _br = b.get("hit_radius")
		var bw: float = half_w + (float(_br) if _br != null else DEATHBEAM_HIT_PAD)
		if (tb - dir * balong).length() <= bw and balong < block_along:
			block_along = balong
	var blocked := block_along < DEATHBEAM_RANGE
	# Beam ends at the blocking boss, else far off-screen (looks infinite). Non-degenerate at point-blank.
	var to_pt := from + dir * maxf(2.0, block_along)
	if _beam != null:
		_beam.set_beam(from, to_pt, true, blocked)
	# Cast light along the beam onto the dust/rocks (rainbow hue tracks the beam).
	_beam_light_on = true
	_beam_light_from = from
	_beam_light_to = to_pt
	_beam_light_col = Color.from_hsv(fposmod(_db_t * 0.5, 1.0), 0.7, 1.0)
	# Tick damage to EVERY enemy the beam SWEPT THROUGH since the last tick (pierce-all; a boss stops it).
	# Testing only the beam's line at the exact tick instant let a fast-rotating beam tunnel past enemies
	# it swept over between ticks; _beam_swept_hit samples the arc from the last tick's aim to this one.
	_beam_cd -= delta
	if _beam_cd <= 0.0:
		_beam_cd = DEATHBEAM_TICK / _rate_mult / _fam_rate("death_beam")
		var prev_from := from if not _db_prev_valid else _db_prev_from
		var prev_dir := dir if not _db_prev_valid else _db_prev_dir
		for en in _enemies() + _ruins():
			if not is_instance_valid(en):
				continue
			var _en_r3 = en.get("hit_radius")
			var hit_w: float = half_w + (float(_en_r3) if _en_r3 != null else DEATHBEAM_HIT_PAD)
			if not _beam_swept_hit(prev_from, prev_dir, from, dir, block_along, hit_w, (en as Node2D).global_position):
				continue
			if en.has_method("take_damage"):
				var _db_r := _roll_damage(_db_dmg(), "death_beam")   # "death_beam" → energy family mastery applies
				if en.is_in_group("arena_ruin"):
					en.take_damage(float(_db_r["dmg"]), DEATHBEAM_STAGGER)   # ruins only implement the 3-arg form
				else:
					en.take_damage(float(_db_r["dmg"]), DEATHBEAM_STAGGER, 0.0, false, _bleeds("death_beam"), bool(_db_r["is_crit"]))
				if bool(_db_r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(_db_r["dmg"]))
				# Incinerate / Freeze: chance/sec, rolled per tick (scaled by the tick interval).
				var tick_dt := DEATHBEAM_TICK / _rate_mult
				var ice_fire := _db_capstone == "ice_and_fire"   # each status also applies the OTHER (no self-loop)
				if _db_incinerate_rate() > 0.0 and en.has_method("apply_burn") and _proc(_db_incinerate_rate() * tick_dt):
					en.call("apply_burn", 1)
					if ice_fire and en.has_method("apply_freeze"):
						en.call("apply_freeze", 1)
				if _db_freeze_rate() > 0.0 and en.has_method("apply_freeze") and _proc(_db_freeze_rate() * tick_dt):
					en.call("apply_freeze", 1)
					if ice_fire and en.has_method("apply_burn"):
						en.call("apply_burn", 1)
		_db_prev_from = from
		_db_prev_dir = dir
		_db_prev_valid = true

## Returns true if `pos` was within `hit_w` of the beam's line at any point while it swept from
## (prev_from, prev_dir) to (cur_from, cur_dir) since the last damage tick. A single straight-line test
## only catches enemies exactly on the beam's CURRENT angle at the tick instant, so a beam that rotates
## fast (or a tick rate that's slow relative to turn speed) can tunnel past enemies it swept over between
## ticks; this samples the swept arc instead. Substep count scales with the angle turned so the sampling
## stays fine at high turn rates, capped to bound worst-case cost (e.g. a near-instant 180° flip).
func _beam_swept_hit(prev_from: Vector2, prev_dir: Vector2, cur_from: Vector2, cur_dir: Vector2, block_along: float, hit_w: float, pos: Vector2) -> bool:
	var ang_delta := absf(prev_dir.angle_to(cur_dir))
	# Step count so consecutive samples are within ~hit_w of each other at the FAR end of the beam (arc
	# length ≈ block_along * ang_delta) — a fixed angular step would under-sample at long range, letting
	# far-away enemies still tunnel through a fast sweep even though near ones were caught.
	var steps := clampi(int(ceil(block_along * ang_delta / maxf(1.0, hit_w))), 1, 512)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var dir_i := prev_dir.slerp(cur_dir, t)
		var from_i := prev_from.lerp(cur_from, t)
		var to_p: Vector2 = pos - from_i
		var along := to_p.dot(dir_i)
		if along < 0.0 or along > block_along:
			continue
		if (to_p - dir_i * along).length() <= hit_w:
			return true
	return false

## Called by the Lasgun pickup on collection — adds the beam to the active loadout (accumulates with Gatling).
func activate_death_beam() -> void:
	_death_beam_active = true
	_db_t = maxf(0.0, _db_cycle() - DEATHBEAM_CHARGE)   # begin in the charge window → telegraph, then the first burst

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
	var is_arc := kind == "arc"   # the real Arc weapon uses its pool stats; Overcharger keeps the base values
	_arc_cd = ARC_COOLDOWN * _cd_scale("arc") * (_arc_cd_mult() if is_arc else 1.0) / _rate_mult
	_ensure_arc_textures()
	var muzzle := _muzzle()
	var hit_set: Array = []                 # enemies already struck this burst (no double-hits)
	var cur := _nearest_enemy(_player.global_position, ARC_ACQUIRE_RANGE, hit_set)
	if cur == null:
		return
	# Pass 1: walk the chain, apply damage, collect the strike points (muzzle → t1 → t2 …).
	var jumps := _arc_jumps() if is_arc else ARC_JUMPS
	var chain := PackedVector2Array([muzzle])
	for _j in range(1 + maxi(0, jumps)):
		if cur == null:
			break
		var c: Vector2 = (cur as Node2D).global_position
		if cur.has_method("take_damage"):
			var _arc_r := _roll_damage(_arc_dmg(), "arc") if is_arc else _roll_damage(ARC_DAMAGE, kind)
			if cur.is_in_group("arena_ruin"):
				cur.take_damage(float(_arc_r["dmg"]), ARC_STAGGER)   # ruins only implement the 3-arg form
			else:
				cur.take_damage(float(_arc_r["dmg"]), ARC_STAGGER, 0.0, false, _bleeds(kind), bool(_arc_r["is_crit"]))
			if bool(_arc_r["is_crit"]):
				_spawn_crit_number(c, float(_arc_r["dmg"]))
			if is_arc:
				if _arc_electrocute_chance() > 0.0 and cur.has_method("apply_stun") and _proc(_arc_electrocute_chance()):
					cur.call("apply_stun", _arc_stun_dur(cur.is_in_group("boss")))
					if _arc_capstone == "pacify" and cur.has_method("apply_weaken"):
						cur.call("apply_weaken", 3.0)   # Pacifying Jolt: -50% damage output for 3s
				pass  # Power Overflow removed → replaced by Lightning Mastery (global stun)
		if gauss_on_hit:
			_spawn_gauss_explosion(c, kind)   # Overcharger: a Gauss blast at every chained target
		chain.append(c)
		hit_set.append(cur)
		cur = _nearest_enemy(c, ARC_RANGE, hit_set)
	if chain.size() < 2:
		return
	# Holy Bolt: a single zap that drops from the top of the screen straight onto the target's head.
	if is_arc and _arc_capstone == "holy":
		chain[0] = Vector2(chain[1].x, chain[1].y - 700.0)
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

## Nearest live arena_enemy OR ruin/lootbox to `from` within `max_dist`, skipping any in `exclude`.
## Self-aiming weapons (Arc, Void, Shooter, Parasite, Moroboshi, Yari, Swarm, Snake, Homing, Vampire)
## all acquire their target through here, so widening this one helper lets all of them lock onto ruins
## too. Callers that pass the result straight to take_damage() must branch on is_in_group("arena_ruin")
## first — ruins only implement the 3-arg take_damage(dmg, stagger, knock), not the enemy's 7-arg one.
func _nearest_enemy(from: Vector2, max_dist: float, exclude: Array) -> Node:
	var best: Node = null
	var best_d := max_dist
	for en in _enemies() + _ruins():
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
	_red_x_cd = 0.0

# ── Dragon's Breath: pool API + effective stats ──
func red_x_grant_upgrade(id: String) -> bool:
	if not DRAGON_POOL.has(id):
		return false
	var maxr := int(DRAGON_POOL[id]["max"])
	if maxr > 0 and int(_red_x_upg.get(id, 0)) >= maxr:
		return false
	_red_x_upg[id] = int(_red_x_upg.get(id, 0)) + 1
	if GameManager.has_method("add_mech"):
		if id == "fire":
			GameManager.add_mech("burn_chance", 0.05)     # GLOBAL Fire Mastery
		elif id == "prolong":
			GameManager.add_mech("burn_dur_add", 0.2)     # GLOBAL burn duration
	return true

func red_x_set_capstone(id: String) -> void:
	_red_x_capstone = id
	if id == "armor_melter" and GameManager.has_method("add_mech"):
		GameManager.add_mech("armor_melt", 1.0)           # flag: heavy burn → extra damage (armor melt proxy)

func _red_x_lvl() -> int:
	return weapon_level("dragons_breath")

func _dragon_dps() -> float:
	return DRAGON_DPS * (1.0 + 0.10 * float(_red_x_upg["damage"]))

func _dragon_range() -> float:
	return DRAGON_RANGE * (1.0 + 0.10 * float(_red_x_upg["range"]))

## Full cone angle (deg). Wide Spray ranks + AoE. The Sun evo → full 360°.
func _dragon_cone_deg() -> float:
	if _red_x_capstone == "the_sun":
		return 360.0
	var aoe: float = GameManager.mech_bonus("aoe_pct") if GameManager.has_method("mech_bonus") else 0.0
	return DRAGON_CONE_DEG * (1.0 + 0.15 * float(_red_x_upg["cone"])) * (1.0 + aoe)

## Per-tick burn chance: base + Fire Mastery (Stroke of Luck added by _proc at roll time).
func _dragon_burn_chance() -> float:
	var fm: float = GameManager.mech_bonus("burn_chance") if GameManager.has_method("mech_bonus") else 0.0
	return DRAGON_BURN_CHANCE + fm

## Continuous cone-fire DPS. Heat Syphon regen is recomputed here each frame too.
func _tick_dragon(delta: float, enemy_on_screen: bool) -> void:
	if _red_x_capstone == "heat_syphon" and GameManager.has_method("set_heat_syphon"):
		var burning := 0
		for en in _enemies():
			if is_instance_valid(en) and en.has_method("is_burning") and en.call("is_burning"):
				burning += 1
		GameManager.set_heat_syphon(0.01 * float(mini(burning, 200)))
	_update_dragon_fire(enemy_on_screen, delta)
	if not enemy_on_screen:
		return
	_red_x_tick_acc += delta
	while _red_x_tick_acc >= DRAGON_TICK:
		_red_x_tick_acc -= DRAGON_TICK
		_dragon_damage_tick()

func _dragon_damage_tick() -> void:
	var origin := _muzzle()
	var fwd := _forward()
	var reach := _dragon_range()
	var full := _dragon_cone_deg()
	var half := deg_to_rad(full) * 0.5
	var per_tick := _dragon_dps() * DRAGON_TICK
	var burn_ch := _dragon_burn_chance()
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var off := (en as Node2D).global_position - origin
		var dist := off.length()
		var _en_r = en.get("hit_radius")
		if dist > reach + (float(_en_r) if _en_r != null else 0.0):
			continue
		if full < 360.0 and absf(angle_difference(off.angle(), fwd.angle())) > half:
			continue
		if en.has_method("take_damage"):
			var r := _roll_damage(per_tick, "dragons_breath")
			en.take_damage(float(r["dmg"]), 0.0)
			if bool(r["is_crit"]):
				_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
		if en.has_method("apply_burn") and _proc(burn_ch):
			en.call("apply_burn", 1)
	for ruin in _ruins():
		if not is_instance_valid(ruin):
			continue
		var roff := (ruin as Node2D).global_position - origin
		if roff.length() > reach:
			continue
		if full < 360.0 and absf(angle_difference(roff.angle(), fwd.angle())) > half:
			continue
		if ruin.has_method("take_damage"):
			ruin.take_damage(per_tick * _dmg_mult * _lvl_mult("dragons_breath"))

## Maintain the forward flamethrower STREAM: particles shoot out the muzzle along the aim, fan into the cone,
## and die at max range. A single emit point at the node + set_stream() (rotated, velocity-tuned) does it.
const DRAGON_FIRE_LIFE := 0.5   # particle life; speed = range/life so flames vanish ~at max range
const SUN_INNER        := 75.0  # The Sun: empty circle radius around the ship (no fire inside)
const SUN_SPIN_RATE    := 1.4   # The Sun: ring rotation speed (rad/s)
func _update_dragon_fire(on: bool, delta: float) -> void:
	if _red_x_fx == null or not is_instance_valid(_red_x_fx):
		_red_x_fx = DynamicFire.new()
		_red_x_fx.free_form         = true   # emit points fed by set_points()
		_red_x_fx.z_index           = 6
		_red_x_fx.particle_lifetime = DRAGON_FIRE_LIFE
		_red_x_fx.particle_amount   = 600    # dense stream
		_red_x_fx.particle_size_min = 16.0
		_red_x_fx.particle_size_max = 40.0
		_red_x_fx.intensity         = 0.6
		_red_x_fx.glow              = 0.3    # low → flames, not a white light-blob
		add_child(_red_x_fx)
	if not on:
		_red_x_fx.set_points([])   # stop emitting when there's nothing to burn
		return
	if _red_x_capstone == "the_sun":
		_update_sun_fire(delta)
	else:
		# Forward cone STREAM from the muzzle.
		_red_x_fx.global_position = _muzzle()
		var reach := _dragon_range()
		var speed := reach / DRAGON_FIRE_LIFE             # travel ~to max range over the particle life
		_red_x_fx.set_stream(_forward().angle(), _dragon_cone_deg() * 0.5, speed, DRAGON_FIRE_LIFE)
		_red_x_fx.set_points([Vector2.ZERO])             # emit from the muzzle (node position)

## The Sun: a swirling ANNULUS of fire around the ship — empty inner circle, rotating ring of emit points.
func _update_sun_fire(delta: float) -> void:
	_sun_spin += SUN_SPIN_RATE * delta
	_red_x_fx.global_position = _player.global_position   # centred on the SHIP, not the muzzle
	_red_x_fx.set_swirl(60.0, DRAGON_FIRE_LIFE)          # low velocity → puffs linger in the ring + trail (swirl)
	var outer := maxf(SUN_INNER + 30.0, _dragon_range())
	var pts: Array = []
	const RINGS := 4
	const ARC := 22
	for ri in range(RINGS):
		var d := lerpf(SUN_INNER, outer, float(ri) / float(maxi(1, RINGS - 1)))
		var phase := _sun_spin + float(ri) * 0.5         # offset each ring → spiral look
		for ai in range(ARC):
			var a := phase + TAU * float(ai) / float(ARC)
			pts.append(Vector2.from_angle(a) * d)
	_red_x_fx.set_points(pts)

## One Red X detonation along the 4 diagonal arms (KEPT for the Carnage fusion's X-fire).
func _fire_red_x(kind := "dragons_breath") -> void:
	_red_x_damage(kind, 1.0)
	_spawn_red_x_fire(_player.global_position, RED_X_REACH, 0.0)   # normal Red X = fixed X diagonals (no ship-facing offset)

## Apply Red X arm damage once (ported from arena_loadout._fire_cross). `scale` multiplies RED_X_DAMAGE so the
## same geometry can be used for a single full detonation (scale 1.0) or smaller periodic DPS ticks (Carnage).
## `base_angle` = the direction of arm 0; the 4 arms sit at base_angle + k·90°. Default PI/4 = the fixed X
## diagonals (normal Red X). Carnage passes the ship facing so the arms align with its 4 Gatling directions.
func _red_x_damage(kind: String, scale: float, base_angle := PI / 4.0) -> void:
	var center := _player.global_position
	var arm_half := deg_to_rad(RED_X_ARM_HALF_DEG)
	var base := RED_X_DAMAGE * scale
	for en in _enemies():
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
	for ruin in _ruins():
		if not is_instance_valid(ruin):
			continue
		if center.distance_to((ruin as Node2D).global_position) <= RED_X_REACH:
			if ruin.has_method("take_damage"):
				ruin.take_damage(base * _dmg_mult * _lvl_mult(kind))

## Pooled DynamicFire X-flash (recycled per shot to avoid rebuilding the GPU particle system each time).
func _spawn_red_x_fire(center: Vector2, reach: float, ship_rot: float) -> void:
	if _red_x_fx == null or not is_instance_valid(_red_x_fx):
		_red_x_fx = DynamicFire.new()
		_red_x_fx.shape             = "cross"
		_red_x_fx.arm_count         = 4
		_red_x_fx.ring_start_angle  = PI / 4.0 + ship_rot   # X diagonals aligned to ship facing
		_red_x_fx.z_index           = 6
		_red_x_fx.particle_lifetime = 0.35 * _duration_mult()
		_red_x_fx.draw_duration     = 0.50
		_red_x_fx.draw_ease         = 1.0
		_red_x_fx.hold_duration     = 2.0 * _duration_mult()    # Capacitor extends the fire (visual)
		_red_x_fx.burnout_duration  = 1.0 * _duration_mult()
		_red_x_fx.recede_burnout    = true
		_red_x_fx.particle_amount   = 495          # +50% particles for +50% arm length
		_red_x_fx.particle_size_min = 20.0
		_red_x_fx.particle_size_max = 46.0
		_red_x_fx.intensity         = 0.5
		_red_x_fx.glow              = 0.25
		_red_x_fx.loop              = false
		_red_x_fx.free_on_done      = false
		_red_x_fx.arm_inner         = RED_X_INNER * 0.5
		_red_x_fx.arm_length        = reach * 0.75
		add_child(_red_x_fx)
		_red_x_fx.global_position = center
	else:
		_red_x_fx.ring_start_angle = PI / 4.0 + ship_rot   # update rotation each shot
		_red_x_fx.arm_length = reach * 0.75
		_red_x_fx.hold_duration     = 2.0 * _duration_mult()   # Capacitor extends the fire (visual)
		_red_x_fx.burnout_duration  = 1.0 * _duration_mult()
		_red_x_fx.particle_lifetime = 0.35 * _duration_mult()
		_red_x_fx.retrigger(center)

## Called by the Chemtrail pickup — turn on the toxic breadcrumb trail.
func activate_chemtrail() -> void:
	_chemtrail_active = true

# ── Chemtrail pool: API + effective stats ──
func chem_grant_upgrade(id: String) -> bool:
	if not CHEMTRAIL_POOL.has(id):
		return false
	var maxr := int(CHEMTRAIL_POOL[id]["max"])
	if maxr > 0 and int(_chem_upg.get(id, 0)) >= maxr:
		return false
	_chem_upg[id] = int(_chem_upg.get(id, 0)) + 1
	if id == "intensity" and GameManager.has_method("add_mech"):
		GameManager.add_mech("tick_rate", 0.05)   # GLOBAL (shared Intensity Mastery)
	elif id == "ms":
		GameManager.add_move_speed(0.04)
	return true

func _chem_dmg_value() -> float:
	return CHEMTRAIL_TICK_DAMAGE * (1.0 + 0.10 * float(_chem_upg["damage"]))
func _chem_dur_mult() -> float:
	return 1.0 + 0.20 * float(_chem_upg["duration"])
func _chem_burn_chance() -> float:   # per second (scaled by tick interval at roll time)
	return 0.05 * float(_chem_upg["burn"])
func _chem_sedative() -> float:      # reduction fraction applied to enemy damage AND move speed
	return 0.025 * float(_chem_upg["sedative"])

## Per-frame: drop a puff 300px behind the ship (no-stack via spacing), then age + expire the pool.
## Stage 1: emit + lifetime only (debug circles in _draw). DoT = Stage 2, recolored fire visual = Stage 3.
func _tick_chemtrail(delta: float) -> void:
	# Emit: the ship continuously shoots puffs out the back at a steady cadence. Each puff spawns just BEHIND
	# the ship and travels outward (opposite facing) at CHEMTRAIL_SHOOT_SPEED, vanishing after its lifetime.
	var back := -_forward()
	var moon := _chem_capstone == "the_moon"
	if moon:
		_chem_moon_ang += delta * 7.0   # sweep the emit direction → fills a 360° toxic cloud around the ship
	var puff_life := CHEMTRAIL_PUFF_LIFETIME * _duration_mult() * _chem_dur_mult()
	_chemtrail_emit_acc += delta
	while _chemtrail_emit_acc >= CHEMTRAIL_EMIT_INTERVAL:
		_chemtrail_emit_acc -= CHEMTRAIL_EMIT_INTERVAL
		var dir := Vector2.from_angle(_chem_moon_ang) if moon else back   # The Moon → all directions
		# Double trail from points 4 & 5 when anchored; single legacy puff behind the ship otherwise.
		var spawns: Array = [_mz(4), _mz(5)] if _has_anchors() else [_player.global_position + dir * CHEMTRAIL_SPAWN_OFFSET]
		for sp: Vector2 in spawns:
			_chemtrail_puffs.append({
				"pos": sp,
				"vel": dir * CHEMTRAIL_SHOOT_SPEED,   # captured at spawn → keeps its world-space heading
				"age": 0.0, "max_age": puff_life,
				"radius": CHEMTRAIL_PUFF_RADIUS + _mech_radius(),
			})
	_process_chemtrail_puffs(delta, "chemtrail")
	# Healing Cloud: regen while standing in your own chemtrail (scales with Regeneration Mastery in hp_regen_rate).
	if GameManager.has_method("set_chem_heal"):
		var heal := 5.0 if (_chem_capstone == "healing_cloud" and _chemtrail_covers(_player.global_position)) else 0.0
		GameManager.set_chem_heal(heal)

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
	var ct_int := CHEMTRAIL_TICK_INTERVAL / _tick_rate()   # Intensity Mastery → faster ticks
	while _chemtrail_tick_acc >= ct_int:
		_chemtrail_tick_acc -= ct_int
		_chemtrail_dot_tick(kind)
	# Systematic Saturation: every 2s, ramp the damage on enemies STILL in the cloud (others reset).
	if _chem_capstone == "saturation":
		_chem_sat_t += delta
		if _chem_sat_t >= 2.0:
			_chem_sat_t -= 2.0
			var next := {}
			for en in _enemies():
				if is_instance_valid(en) and _chemtrail_covers((en as Node2D).global_position):
					var eid := (en as Node2D).get_instance_id()
					next[eid] = float(_chem_sat.get(eid, 0.0)) + 0.25   # +25% ramp per 2s sustained
			_chem_sat = next
	# Visual: feed all live puff centres to the single recolored toxic-fire emitter.
	_update_chemtrail_fx()

## One DoT tick: every enemy inside ANY puff takes CHEMTRAIL_TICK_DAMAGE once (single coverage check → no
## stacking on overlap). Scales via _roll_damage (damage-mult + crit) like the other System-2 weapons.
func _chemtrail_dot_tick(kind := "chemtrail") -> void:
	if _chemtrail_puffs.is_empty():
		return
	var base := _chem_dmg_value()
	var burn_ch := _chem_burn_chance()
	var sed := _chem_sedative()
	var tick_int := CHEMTRAIL_TICK_INTERVAL / _tick_rate()
	var saturating := _chem_capstone == "saturation"
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		if _chemtrail_covers(ep) and en.has_method("take_damage"):
			var dmg_base := base
			if saturating:
				dmg_base *= 1.0 + float(_chem_sat.get((en as Node2D).get_instance_id(), 0.0))
			var r := _roll_damage(dmg_base, kind)
			en.take_damage(float(r["dmg"]), 0.0)
			if bool(r["is_crit"]):
				_spawn_crit_number(ep, float(r["dmg"]))
			if burn_ch > 0.0 and en.has_method("apply_burn") and _proc(burn_ch * tick_int):
				en.call("apply_burn", 1)
			if sed > 0.0 and en.has_method("apply_sedative"):
				en.call("apply_sedative", sed, sed)
	for ruin in _ruins():
		if not is_instance_valid(ruin):
			continue
		if _chemtrail_covers((ruin as Node2D).global_position) and ruin.has_method("take_damage"):
			ruin.take_damage(base * _dmg_mult * _lvl_mult(kind))

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
	var enemies := _enemies()
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
						en.take_damage(per_tick, 0.0, 0.0, "rift_maker")
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
		for men in _enemies():
			if not is_instance_valid(men) or men.is_in_group("boss"):
				continue
			var mep: Vector2 = (men as Node2D).global_position
			var mdd := _void_pos.distance_to(mep)
			if mdd > 1.0 and mdd <= VOID_PULL_RADIUS:
				(men as Node2D).global_position = mep.move_toward(_void_pos, mpull)
		_void_tick += delta
		while _void_tick >= VOID_TICK:
			_void_tick -= VOID_TICK
			var mdmg := VOID_DAMAGE_MAX * VOID_TICK * _dmg_mult * _lvl_mult("rift_maker")
			for men2 in _enemies():
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
				_void_cd = VOID_COOLDOWN * _cd_scale("rift_maker")
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
	for en in _enemies():
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
		var per_tick := lerpf(VOID_DAMAGE_MIN, VOID_DAMAGE_MAX, f) * VOID_TICK * _dmg_mult * _lvl_mult("rift_maker")
		for en in _enemies():
			if not is_instance_valid(en):
				continue
			if _void_pos.distance_to((en as Node2D).global_position) <= radius + VOID_HIT_PAD:
				if en.has_method("take_damage"):
					en.take_damage(per_tick, 0.0, 0.0, "rift_maker")
		for ruin in _ruins():
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
# ── Orbital skill-point pool: API + effective stats ──
func orbital_upgrade_rank(id: String) -> int:
	return int(_orbital_upg.get(id, 0))

func orbital_grant_upgrade(id: String) -> bool:
	if not ORBITAL_POOL.has(id):
		return false
	var maxr := int(ORBITAL_POOL[id]["max"])
	if maxr > 0 and int(_orbital_upg.get(id, 0)) >= maxr:
		return false
	_orbital_upg[id] = int(_orbital_upg.get(id, 0)) + 1
	if id == "contact" and GameManager.has_method("add_mech"):
		GameManager.add_mech("contact_dmg_mult", 0.05)   # GLOBAL: every contact weapon + the ship reads this
	return true

func orbital_set_capstone(id: String) -> void:
	_orbital_capstone = id
	if id == "avatar":
		_rebuild_orbital_elements()

## Impenetrable evo: ball world-positions (+ block radius) that destroy enemy projectiles. [] when inactive.
## Queried by arena_enemy_manager._tick_bullets.
func orbital_block_positions() -> Array:
	if _orbital_capstone != "impenetrable" or not (_orbital_active or _singularity_active):
		return []
	if _player == null or not is_instance_valid(_player):
		return []
	var r := (ORBITAL_DRAW * 0.5 if _orbital_tex != null else ORBITAL_BALL_RADIUS) * _orbital_size_mult() + ORBITAL_HIT_PAD
	var out: Array = []
	for p: Vector2 in _orbital_positions():
		out.append({"pos": p, "r": r})
	return out

## Art of War "X Truth" evolution: disable every acquired weapon NOT of `family`; the surviving family then
## gains +50% damage per disabled weapon (read in _roll_damage via _truth_family / _truth_count).
func apply_truth(family: String) -> void:
	_truth_family = family
	_truth_count = 0
	for k: String in _acquired:
		if String((WEAPON_FAMILY as Dictionary).get(k, "")) != family:
			_deactivate_kind(k)
			_truth_count += 1

func _orbital_lvl() -> int:
	return weapon_level("defensive_orbitals")

## Per-ball contact damage (Heavy Orbs ranks + Widen's damage half). Contact Mastery is applied globally in
## _roll_damage. Center of the Universe evo adds 100% armor + 5% Max HP on top (flat).
func _orbital_dmg_value() -> float:
	var dmg := ORBITAL_DAMAGE * (1.0 + 0.10 * float(_orbital_upg["damage"]) + 0.075 * float(_orbital_upg["widen"]))
	if _orbital_capstone == "center":
		dmg += float(GameManager.upg_base_defense) + 0.05 * float(GameManager.ship_max_hp)
	return dmg

## Spin multiplier (Overspin +15% + Flywheel +7%).
func _orbital_spin_mult() -> float:
	return 1.0 + 0.15 * float(_orbital_upg["spin"]) + 0.07 * float(_orbital_upg["spin2"])

## Orbit radius (Tight Orbit -10%/rank vs Widen +5%/rank — opposing dials — floored so it never collapses).
## Pinned to base under Singularities.
func _orbital_radius() -> float:
	if _singularity_active:
		return ORBITAL_RADIUS
	var mult := pow(0.90, float(_orbital_upg["tighten"])) * (1.0 + 0.05 * float(_orbital_upg["widen"]))
	return ORBITAL_RADIUS * maxf(0.3, mult)

## Ball-size multiplier (Bigger Orbs +10%) × AoE bonus.
func _orbital_size_mult() -> float:
	var aoe: float = GameManager.mech_bonus("aoe_pct") if GameManager.has_method("mech_bonus") else 0.0
	return (1.0 + 0.10 * float(_orbital_upg["size"])) * (1.0 + aoe)

## Avatar: assign each ball an element, spread as evenly as possible and avoiding two of the same in a row.
func _rebuild_orbital_elements() -> void:
	const ELS := ["fire", "ice", "lightning"]
	var n := _orbital_n()
	_orbital_elements.clear()
	for k in n:
		_orbital_elements.append(ELS[k % ELS.size()])   # round-robin → even spread, no two adjacent the same

func _orbital_positions() -> Array:
	var out: Array = []
	var ship := _mz(6) if _has_anchors() else _player.global_position   # orbit centre = point 6
	var n := _orbital_n()
	var radius := _orbital_radius()
	var step := 360.0 / float(n)
	for k in n:
		var ang := deg_to_rad(_orbital_angle + step * float(k))
		out.append(ship + Vector2(cos(ang), sin(ang)) * radius)
	return out

func _tick_orbital(delta: float) -> void:
	_run_orbital(delta, "defensive_orbitals")

## Shared orbital movement + per-ball contact damage. `kind` selects the damage scaling (the Singularities
## fusion reuses this with kind "singularities" so the orbit's contact damage scales with the fused level).
func _run_orbital(delta: float, kind: String) -> void:
	_orbital_t += delta
	_orbital_angle      = fmod(_orbital_angle      + ORBITAL_SPIN * _automation_rate(kind) * _weapon_speed_mult() * _orbital_spin_mult() * delta, 360.0)
	_orbital_self_angle = fmod(_orbital_self_angle + ORBITAL_SELF_RPM * 6.0    * delta, 360.0)
	var n := _orbital_n()
	while _orbital_cd.size() < n:
		_orbital_cd.append(0.0)   # append (not resize) so new per-ball cd slots are 0.0, never null
	if _orbital_capstone == "avatar" and _orbital_elements.size() != n:
		_rebuild_orbital_elements()   # keep element list sized to the current ball count
	var dmg_val := _orbital_dmg_value()
	var ruins   := get_tree().get_nodes_in_group("arena_ruin")
	var balls := _orbital_positions()
	# hit radius = half the visual size (× Bigger Orbs / AoE) + enemy-catchment pad
	var orb_r := (ORBITAL_DRAW * 0.5 if _orbital_tex != null else ORBITAL_BALL_RADIUS) * _orbital_size_mult()
	var hit_r := orb_r + ORBITAL_HIT_PAD
	for k in n:
		_orbital_cd[k] = maxf(0.0, float(_orbital_cd[k]) - delta)
		if float(_orbital_cd[k]) > 0.0:
			continue
		var bpos: Vector2 = balls[k]
		var struck := false
		for en in _enemies_near(bpos, hit_r):
			if not is_instance_valid(en):
				continue
			if bpos.distance_to((en as Node2D).global_position) <= hit_r:
				if en.has_method("take_damage"):
					var _orb_r := _roll_damage(dmg_val, kind)
					en.take_damage(float(_orb_r["dmg"]), ORBITAL_STAGGER, 0.0, false, _bleeds(kind), bool(_orb_r["is_crit"]))
					if bool(_orb_r["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(_orb_r["dmg"]))
				if _orbital_capstone == "avatar":
					_avatar_strike(en, k)   # fire/ice/lightning proc per the ball's element
				if _orbital_impact_player != null and not _orbital_impact_player.playing:
					_orbital_impact_player.play()
				struck = true
				break
		if not struck:
			for ruin in ruins:
				if not is_instance_valid(ruin):
					continue
				var rr: float = (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0) + ORBITAL_BALL_RADIUS
				if bpos.distance_to((ruin as Node2D).global_position) <= rr:
					if ruin.has_method("take_damage"):
						ruin.take_damage(dmg_val * _dmg_mult * _lvl_mult(kind))
					struck = true
					break
		if struck:
			_orbital_cd[k] = ORBITAL_HIT_COOLDOWN

# Avatar: ball k has an element; 25% on contact (+ Stroke of Luck via _proc, + Lightning Mastery for lightning)
# to apply burn / freeze / stun. (Fire/Ice global masteries are not built yet — they'd add here when they are.)
const AVATAR_BASE_CHANCE := 0.25
const AVATAR_STUN_DUR    := 0.6
func _avatar_strike(en, k: int) -> void:
	if k < 0 or k >= _orbital_elements.size():
		return
	var el := String(_orbital_elements[k])
	var extra := 0.0
	if GameManager.has_method("mech_bonus"):
		if el == "lightning":
			extra = GameManager.mech_bonus("lightning_stun_chance")
		elif el == "fire":
			extra = GameManager.mech_bonus("burn_chance")   # Fire Mastery boosts the burn proc
	if not _proc(AVATAR_BASE_CHANCE + extra):
		return
	match el:
		"fire":
			if en.has_method("apply_burn"):
				en.apply_burn(1)
		"ice":
			if en.has_method("apply_freeze"):
				en.apply_freeze(1)
		"lightning":
			if en.has_method("apply_stun"):
				var dur_b: float = GameManager.mech_bonus("lightning_stun_dur") if GameManager.has_method("mech_bonus") else 0.0
				en.apply_stun(AVATAR_STUN_DUR * (1.0 + dur_b))

## Load thrust-point fracs + plume styles from weapon_layout.cfg / weapon_plume_styles.cfg,
## then spawn CPUParticles2D children — ORBITAL_BALLS × num_TPs nodes total.
func _register_plume(cfg_key: String, count: int, ds: Vector2, provider: Callable) -> void:
	_plume_registry.append({"cfg_key": cfg_key, "count": count, "ds": ds, "provider": provider, "anchors": []})

func _load_all_plumes() -> void:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := ConfigFile.new()
	if cfg.load("res://weapon_layout.cfg") != OK:
		return
	var scfg := ConfigFile.new()
	scfg.load("res://weapon_plume_styles.cfg")
	for entry: Dictionary in _plume_registry:
		var key: String = entry["cfg_key"]
		var tps: Array = cfg.get_value("thrustpoints", key, [])
		if tps.is_empty():
			continue
		var eo: Dictionary = cfg.get_value("creeps", key, {})
		if eo.is_empty():
			continue
		var eo_pos:  Vector2 = eo.get("pos",  Vector2(480.0, 380.0))
		var eo_size: Vector2 = eo.get("size", Vector2(60.0,  60.0))
		if eo_size.x <= 0.0 or eo_size.y <= 0.0:
			continue
		var all_styles: Dictionary = scfg.get_value("styles", key, {})
		var ds: Vector2 = entry["ds"]
		var anchors: Array = []
		for _k in int(entry["count"]):
			var anchor := Node2D.new()
			anchor.visible = false
			add_child(anchor)
			anchors.append(anchor)
			for tp: Dictionary in tps:
				var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
				var frac := (tp_oc - eo_pos) / eo_size
				var tp_id: int = int(tp.get("id", 1))
				var style: Dictionary = all_styles.get("tp_%d" % tp_id, {})
				var p := _make_orbital_plume(frac, float(tp.get("dir_angle", PI * 0.5)), style, ds)
				p.z_index = -1
				anchor.add_child(p)
		entry["anchors"] = anchors

func _update_all_plumes() -> void:
	for entry: Dictionary in _plume_registry:
		var anchors: Array = entry.get("anchors", [])
		if anchors.is_empty():
			continue
		var states: Array = (entry["provider"] as Callable).call()
		for i in anchors.size():
			var anchor: Node2D = anchors[i]
			if not is_instance_valid(anchor):
				continue
			if i >= states.size():
				_set_plume_anchor_visible(anchor, false)
				continue
			var st: Dictionary = states[i]
			anchor.global_position = st.get("pos", Vector2.ZERO)
			anchor.rotation = st.get("rot", 0.0)
			_set_plume_anchor_visible(anchor, st.get("visible", true))

## Toggle an anchor's visibility AND its child particles' emission (so idle pool slots don't keep emitting → save CPU).
func _set_plume_anchor_visible(anchor: Node2D, vis: bool) -> void:
	if anchor.visible == vis:
		return
	anchor.visible = vis
	for ch in anchor.get_children():
		if ch is CPUParticles2D:
			(ch as CPUParticles2D).emitting = vis

func _make_orbital_plume(frac: Vector2, dir_angle: float, style: Dictionary, ds: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position    = (frac - Vector2(0.5, 0.5)) * ds
	p.amount      = maxi(1, int(ds.x / 5.0))
	p.lifetime             = float(style.get("lifetime", 0.30))
	p.emitting    = true
	p.local_coords = false
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = true
	p.z_index     = 1
	p.gravity     = Vector2.ZERO
	p.direction   = Vector2.RIGHT.rotated(dir_angle)
	p.spread               = float(style.get("spread",   12.0))
	p.initial_velocity_min = float(style.get("vel_min",  60.0))
	p.initial_velocity_max = float(style.get("vel_max",  100.0))
	p.scale_amount_min     = float(style.get("sc_min",   0.6))
	p.scale_amount_max     = float(style.get("sc_max",   1.5))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.05))
	p.scale_amount_curve = taper
	p.set_meta("base_pos", p.position)
	p.set_meta("base_dir", p.direction)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var dist: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	p.texture = ImageTexture.create_from_image(img)
	var col_core:  Color = style.get("col_core",  Color(0.7, 0.9, 1.0, 1.0))
	var col_flame: Color = style.get("col_flame", Color(0.4, 0.7, 1.0, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.2, 0.5, 1.0, 0.8))
	var col_fade := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	return p

# ── Striker — orbits like Defensive Orbitals; dashes out to ram a target in range, then returns ──
func activate_striker() -> void:
	_striker_active = true
	_striker_init = false

## World position of orbit slot k (of STRIKER_BALLS), evenly spaced around the current shared orbit angle.
func _striker_slot_pos(k: int) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.ZERO
	var step := 360.0 / float(STRIKER_BALLS)
	var ang := deg_to_rad(_striker_angle + step * float(k))
	return _player.global_position + Vector2(cos(ang), sin(ang)) * STRIKER_RADIUS

func _init_striker() -> void:
	_striker_balls.clear()
	for k in STRIKER_BALLS:
		_striker_balls.append({"state": "orbit", "pos": _striker_slot_pos(k), "target": null})
	_striker_init = true

## Per-ball state machine: orbit in formation → dash ("ram") at the nearest enemy within STRIKER_RANGE →
## hit once → return to the (still-advancing) orbit slot → resume orbiting (re-attacks immediately if a
## target is still in range).
func _tick_striker(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _striker_init:
		_init_striker()
	_striker_angle      = fmod(_striker_angle      + STRIKER_SPIN * _automation_rate("striker") * _weapon_speed_mult() * delta, 360.0)
	_striker_self_angle = fmod(_striker_self_angle + STRIKER_SELF_RPM * 6.0 * delta, 360.0)
	for k in _striker_balls.size():
		var ball: Dictionary = _striker_balls[k]
		match String(ball["state"]):
			"orbit":
				ball["pos"] = _striker_slot_pos(k)
				var tgt := _nearest_enemy(ball["pos"] as Vector2, STRIKER_RANGE, [])
				if tgt != null and is_instance_valid(tgt):
					ball["target"] = tgt
					ball["state"] = "ram"
			"ram":
				if not is_instance_valid(ball.get("target")):   # check the raw Variant BEFORE any typed assignment —
					ball["target"] = null                        # a freed ref assigned straight into `Node` trips
					ball["state"] = "return"                     # Godot's "previously freed instance" warning
				else:
					var tgt2: Node = ball["target"]
					var pos: Vector2 = ball["pos"]
					var goal: Vector2 = (tgt2 as Node2D).global_position
					var d := goal - pos
					var enr: float = float(tgt2.get("hit_radius")) if tgt2.get("hit_radius") != null else 12.0
					if d.length() <= STRIKER_HIT_RADIUS + enr:
						_striker_hit(tgt2, goal)
						ball["target"] = null
						ball["state"] = "return"
					else:
						ball["pos"] = pos + d.normalized() * (STRIKER_RAM_SPEED * delta)
			"return":
				var slot := _striker_slot_pos(k)
				var pos2: Vector2 = ball["pos"]
				var d2 := slot - pos2
				if d2.length() <= 6.0:
					ball["state"] = "orbit"
					ball["pos"] = slot
				else:
					ball["pos"] = pos2 + d2.normalized() * (STRIKER_RETURN_SPEED * delta)

## One ram hit: same damage as Defensive Orbitals (STRIKER_DAMAGE = ORBITAL_DAMAGE), × damage-mult, crit-rollable.
func _striker_hit(en: Node, pos: Vector2) -> void:
	if en.is_in_group("arena_ruin"):
		if en.has_method("take_damage"):
			var r := _roll_damage(STRIKER_DAMAGE, "striker")
			en.take_damage(float(r["dmg"]), STRIKER_STAGGER)
	elif en.has_method("take_damage"):
		var r := _roll_damage(STRIKER_DAMAGE, "striker")
		en.take_damage(float(r["dmg"]), STRIKER_STAGGER, 0.0, false, _bleeds("striker"), bool(r["is_crit"]))
		if bool(r["is_crit"]):
			_spawn_crit_number(pos, float(r["dmg"]))

func _draw_striker() -> void:
	var sz := Vector2(STRIKER_DRAW, STRIKER_DRAW)
	if _striker_tex != null:
		var ts := _striker_tex.get_size()
		if ts.x > 0.0:
			sz = Vector2(STRIKER_DRAW, STRIKER_DRAW * ts.y / ts.x)
	for ball: Dictionary in _striker_balls:
		var c: Vector2 = ball["pos"]
		if _striker_tex != null:
			draw_set_transform(c, deg_to_rad(_striker_self_angle))
			draw_texture_rect(_striker_tex, Rect2(-sz * 0.5, sz), false)
			draw_set_transform(Vector2.ZERO, 0.0)
		else:
			draw_circle(c, STRIKER_DRAW * 0.5, Color(STRIKER_COL.r, STRIKER_COL.g, STRIKER_COL.b, 0.5))

# ── Shooter (rear-guard bolt turrets) ───────────────────────────────────────────
func activate_shooter() -> void:
	_shooter_active = true
	_shooter_init = false

# ── Shooter upgrade API (pool ranks + evolve capstone) ──
func shooter_upgrade_rank(id: String) -> int:
	return int(_shooter_upg.get(id, 0))

func shooter_grant_upgrade(id: String) -> bool:
	if not SHOOTER_POOL.has(id):
		return false
	var maxr := int(SHOOTER_POOL[id]["max"])
	if maxr > 0 and int(_shooter_upg.get(id, 0)) >= maxr:
		return false
	_shooter_upg[id] = int(_shooter_upg.get(id, 0)) + 1
	if id == "automation" and GameManager.has_method("add_mech"):
		GameManager.add_mech("automation_dmg", 0.05)   # GLOBAL: +5% to all automation weapons
	return true

func shooter_set_capstone(id: String) -> void:
	_shooter_capstone = id
	if id == "avatar2":
		_shooter_rebuild_elements()

func _shooter_dmg() -> float:
	return SHOOTER_DAMAGE * (1.0 + 0.10 * float(_shooter_upg["damage"]))
func _shooter_crit() -> float:
	return 0.05 * float(_shooter_upg["crit"])   # local crit (folded into _roll_damage for kind "shooter")
func _shooter_count() -> int:
	var n := SHOOTER_BASE_ORBS + int(_shooter_upg["morebital"])
	if _shooter_capstone == "the_fleet":
		n += 5
	return maxi(1, n)

## Round-robin fire/ice/lightning per turret (Avatar 2), rebuilt whenever the count changes.
func _shooter_rebuild_elements() -> void:
	const ELS := ["fire", "ice", "lightning"]
	_shooter_elements.clear()
	for k in _shooter_count():
		_shooter_elements.append(ELS[k % ELS.size()])

## Slot for turret i of n: base 2 anchor at 8 & 4 o'clock; extra turrets fan UP over the top (through 12)
## between those anchors. Angles are SCREEN-fixed (clockwise from screen-up), NOT the ship's facing — the
## turrets keep the same on-screen positions regardless of which way the ship points.
func _shooter_slot_pos(i: int, n: int) -> Vector2:
	var deg := 240.0   # 8 o'clock (single-turret fallback)
	if n >= 2:
		deg = 240.0 + float(i) * (240.0 / float(n - 1))   # 8 o'clock → up → 4 o'clock
	return _player.global_position + Vector2.UP.rotated(deg_to_rad(deg)) * SHOOTER_BACK_DIST

func _init_shooter() -> void:
	_shooter_orbs.clear()
	var n := _shooter_count()
	for k in n:
		var slot := _shooter_slot_pos(k, n)
		var rot := (slot - _player.global_position).angle()   # idle facing: outward, away from the ship
		_shooter_orbs.append({"pos": slot, "cd": SHOOTER_ORB_STAGGER * float(k), "burst_left": 0, "gap": 0.0, "rot": rot})
	if _shooter_capstone == "avatar2":
		_shooter_rebuild_elements()
	_shooter_init = true

func _tick_shooter(delta: float, enemy_on_screen: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _shooter_init:
		_init_shooter()
	var n := _shooter_count()
	while _shooter_orbs.size() < n:   # More-bital / The Fleet grew the fleet
		var k := _shooter_orbs.size()
		var slot := _shooter_slot_pos(k, n)
		var rot := (slot - _player.global_position).angle()
		_shooter_orbs.append({"pos": slot, "cd": SHOOTER_ORB_STAGGER * float(k), "burst_left": 0, "gap": 0.0, "rot": rot})
	while _shooter_orbs.size() > n:
		_shooter_orbs.pop_back()
	if _shooter_capstone == "avatar2" and _shooter_elements.size() != n:
		_shooter_rebuild_elements()
	var rate := maxf(0.01, _rate_mult * (1.0 + 0.08 * float(_shooter_upg["firerate"])))
	for i in _shooter_orbs.size():
		var orb: Dictionary = _shooter_orbs[i]
		orb["pos"] = _shooter_slot_pos(i, n)   # locked to the ship — no trailing/lag
		var facing_tgt := _nearest_enemy(orb["pos"] as Vector2, SHOOTER_RANGE, [])
		if facing_tgt != null and is_instance_valid(facing_tgt):   # turn toward the target at SHOOTER_TURN_RATE (120 RPM) — no instant snap
			var desired := ((facing_tgt as Node2D).global_position - (orb["pos"] as Vector2)).angle()
			var diff := angle_difference(float(orb["rot"]), desired)
			orb["rot"] = float(orb["rot"]) + clampf(diff, -SHOOTER_TURN_RATE * delta, SHOOTER_TURN_RATE * delta)
		if int(orb["burst_left"]) > 0:                       # continue an in-progress burst
			orb["gap"] = float(orb["gap"]) - delta
			if float(orb["gap"]) <= 0.0:
				_shooter_fire_bolt(orb["pos"] as Vector2, i)
				orb["burst_left"] = int(orb["burst_left"]) - 1
				orb["gap"] = SHOOTER_BURST_GAP
			continue
		orb["cd"] = float(orb["cd"]) - delta
		if float(orb["cd"]) <= 0.0 and enemy_on_screen:      # start a burst if a target is in range
			var tgt := _nearest_enemy(orb["pos"] as Vector2, SHOOTER_RANGE, [])
			if tgt != null and is_instance_valid(tgt):
				var bursts := 1
				if _proc(0.08 * float(_shooter_upg["multishot"])):
					bursts += 1                              # Scatter Volley: a bonus burst
				orb["burst_left"] = SHOOTER_BURST * bursts
				orb["gap"] = 0.0
				orb["cd"] = SHOOTER_COOLDOWN / rate
	_tick_shooter_bolts(delta)

## Spawn one laser bolt from a turret toward the current nearest enemy.
func _shooter_fire_bolt(from: Vector2, orb_idx: int) -> void:
	var tgt := _nearest_enemy(from, SHOOTER_RANGE, [])
	var dir := _forward()
	if tgt != null and is_instance_valid(tgt):
		var d := (tgt as Node2D).global_position - from
		dir = d.normalized() if d.length() > 0.01 else _forward()
	_shooter_bolts.append({"pos": from, "vel": dir * SHOOTER_BOLT_SPEED, "life": 0.0, "orb": orb_idx, "hits": {}})

## Move bolts; damage the first enemy each touches (or ALL, under Piercing Vanguard). Cull on lifetime.
func _tick_shooter_bolts(delta: float) -> void:
	var pierce := _shooter_capstone == "piercing_vanguard"
	var i := _shooter_bolts.size() - 1
	while i >= 0:
		var b: Dictionary = _shooter_bolts[i]
		b["life"] = float(b["life"]) + delta
		var pos: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["pos"] = pos
		var dead := float(b["life"]) >= SHOOTER_BOLT_LIFE
		if not dead:
			var hits: Dictionary = b["hits"]
			for en in _enemies() + _ruins():
				if not is_instance_valid(en):
					continue
				var eid := en.get_instance_id()
				if hits.has(eid):
					continue
				var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 12.0
				if pos.distance_to((en as Node2D).global_position) <= SHOOTER_BOLT_HIT + enr:
					if en.has_method("take_damage"):
						var r := _roll_damage(_shooter_dmg(), "shooter")
						if en.is_in_group("arena_ruin"):
							en.take_damage(float(r["dmg"]), SHOOTER_STAGGER)   # ruins only implement the 3-arg form
						else:
							en.take_damage(float(r["dmg"]), SHOOTER_STAGGER, 0.0, false, false, bool(r["is_crit"]))
						if bool(r["is_crit"]):
							_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
					if _shooter_capstone == "avatar2":
						_shooter_avatar_strike(en, int(b["orb"]))
					hits[eid] = true
					if not pierce:
						dead = true
						break
		if dead:
			_shooter_bolts.remove_at(i)
		i -= 1

## Avatar 2: per-turret element proc on a bolt hit (mirrors the Defender's Avatar).
func _shooter_avatar_strike(en, orb_idx: int) -> void:
	if orb_idx < 0 or orb_idx >= _shooter_elements.size():
		return
	var el := String(_shooter_elements[orb_idx])
	var extra := 0.0
	if GameManager.has_method("mech_bonus"):
		if el == "lightning":
			extra = GameManager.mech_bonus("lightning_stun_chance")
		elif el == "fire":
			extra = GameManager.mech_bonus("burn_chance")
	if not _proc(SHOOTER_AVATAR_CHANCE + extra):
		return
	match el:
		"fire":
			if en.has_method("apply_burn"): en.apply_burn(1)
		"ice":
			if en.has_method("apply_freeze"): en.apply_freeze(1)
		"lightning":
			if en.has_method("apply_stun"):
				var dur_b: float = GameManager.mech_bonus("lightning_stun_dur") if GameManager.has_method("mech_bonus") else 0.0
				en.apply_stun(AVATAR_STUN_DUR * (1.0 + dur_b))

func _draw_shooter() -> void:
	# Turrets: the shooter.png UAV sprite (aspect-locked), turning toward its target at SHOOTER_TURN_RATE.
	var sz := Vector2(SHOOTER_DRAW, SHOOTER_DRAW)
	if _shooter_tex != null:
		var ts := _shooter_tex.get_size()
		if ts.x > 0.0:
			sz = Vector2(SHOOTER_DRAW, SHOOTER_DRAW * ts.y / ts.x)
	for orb: Dictionary in _shooter_orbs:
		var p: Vector2 = orb["pos"]
		if _shooter_tex != null:
			draw_set_transform(p, float(orb.get("rot", 0.0)) + PI * 0.5, Vector2.ONE)
			draw_texture_rect(_shooter_tex, Rect2(-sz * 0.5, sz), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(p, 5.5, Color(SHOOTER_COL.r, SHOOTER_COL.g, SHOOTER_COL.b, 0.5))
			draw_circle(p, 2.6, Color(1.0, 0.92, 0.9, 0.95))
	# Bolts: elongated red laser with a hot white core (rounded head, tapered tail).
	for b: Dictionary in _shooter_bolts:
		_draw_shooter_bolt(b["pos"] as Vector2, (b["vel"] as Vector2).angle())

## One bolt at `pos` along `ang`: soft glow → red shell → white core, all teardrop-shaped.
func _draw_shooter_bolt(pos: Vector2, ang: float) -> void:
	draw_set_transform(pos, ang, Vector2.ONE)
	draw_colored_polygon(_shooter_bolt_shape(SHOOTER_BOLT_LEN, SHOOTER_BOLT_W), Color(SHOOTER_COL.r, SHOOTER_COL.g, SHOOTER_COL.b, 0.28))
	draw_colored_polygon(_shooter_bolt_shape(SHOOTER_BOLT_LEN * 0.92, SHOOTER_BOLT_W * 0.72), Color(1.0, 0.20, 0.15, 0.95))
	draw_colored_polygon(_shooter_bolt_shape(SHOOTER_BOLT_LEN * 0.80, SHOOTER_BOLT_W * 0.40), Color(1.0, 0.97, 0.95, 0.98))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Teardrop polygon (local, +X = travel dir): rounded nose at +X, tapered point at -X.
func _shooter_bolt_shape(length: float, width: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hw := width * 0.5
	var nose := length * 0.5
	var arc_c := nose - hw          # centre of the rounded head
	pts.push_back(Vector2(-length * 0.5, 0.0))   # tail point
	var steps := 8
	for s in range(steps + 1):      # rounded nose, top → tip → bottom
		var a := -PI * 0.5 + PI * float(s) / float(steps)
		pts.push_back(Vector2(arc_c + cos(a) * hw, sin(a) * hw))
	return pts

## Per ball, drawn BACK→FRONT: tangent streak glow → afterimage ghosts → crisp body. The orbit is
## deterministic, so past ghost positions are just θ stepped back along the arc (no history buffer).
func _draw_orbital() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var ship := _player.global_position
	var n := _orbital_n()
	var step := 360.0 / float(n)
	var blur := ORBITAL_BLUR_AMT
	for k in n:
		var th := deg_to_rad(_orbital_angle + step * float(k))
		var c := ship + Vector2(cos(th), sin(th)) * _orbital_radius()
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
	var ds0 := _orbital_draw_size()
	for j in range(1, n + 1):
		var gth := th - trail_arc_step * float(j)
		var gc := ship + Vector2(cos(gth), sin(gth)) * _orbital_radius()
		var sf := pow(trail_scale_falloff, float(j))
		var ds := ds0 * sf
		var a := pow(trail_alpha_falloff, float(j)) * blur
		var ghost_ang := _orbital_self_angle - ORBITAL_SELF_RPM * 6.0 * trail_arc_step * float(j) / maxf(0.001, ORBITAL_SPIN * deg_to_rad(1.0))
		draw_set_transform(gc, deg_to_rad(ghost_ang))
		draw_texture_rect(_orbital_tex, Rect2(-ds.x * 0.5, -ds.y * 0.5, ds.x, ds.y), false,
			Color(trail_tint.r, trail_tint.g, trail_tint.b, a))
		draw_set_transform(Vector2.ZERO, 0.0)

## Soft tangent streak glow: stacked low-alpha circles sampled along the arc behind the orbital → a smooth
## speed smear, brightest at the body and fading backward (soft mix-blend glow, no hard shape).
func _draw_orbital_streak(ship: Vector2, th: float, blur: float) -> void:
	var length := lerpf(streak_len_min, streak_len_max, blur)
	var back_ang := length / maxf(1.0, _orbital_radius())   # arc (rad) the streak spans
	var m := 8
	for s in range(1, m + 1):
		var f := float(s) / float(m)                     # 0 at body → 1 at tail
		var sth := th - back_ang * f
		var sc := ship + Vector2(cos(sth), sin(sth)) * _orbital_radius()
		var a := streak_alpha * blur * (1.0 - f)
		var rad := streak_width * 0.5 * (1.0 - f * 0.4)
		draw_circle(sc, rad, Color(trail_tint.r, trail_tint.g, trail_tint.b, a))

func _orbital_draw_size() -> Vector2:
	var sm := _orbital_size_mult()   # Bigger Orbs + AoE
	if _orbital_tex != null and _orbital_tex_size.x > 0.0 and _orbital_tex_size.y > 0.0:
		var max_dim := maxf(_orbital_tex_size.x, _orbital_tex_size.y)
		return _orbital_tex_size * (ORBITAL_DRAW / max_dim) * sm
	return Vector2(ORBITAL_DRAW, ORBITAL_DRAW) * sm

func _draw_orbital_ball(c: Vector2) -> void:
	if _orbital_tex != null:
		var ds := _orbital_draw_size()
		draw_set_transform(c, deg_to_rad(_orbital_self_angle))
		draw_texture_rect(_orbital_tex, Rect2(-ds.x * 0.5, -ds.y * 0.5, ds.x, ds.y), false)
		draw_set_transform(Vector2.ZERO, 0.0)
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
	# Player 2 can't be picked up unless you already own a weapon for it to copy (dev/test bypasses via force_spawn_player2).
	if kind == "player_2" and not _companion and not _p2_eligible():
		return false
	var newly := false
	if not (kind in _acquired):
		if _acquired.size() >= MAX_WEAPONS:
			return false   # all slots full — ignore (unique-only; level-up system comes later)
		_acquired.append(kind)
		_levels[kind] = 1
		newly = true
	_activate_kind(kind)   # idempotent: also re-arms a kind already owned
	# A new weapon changes Player 2's copy-list (Proactive) + Diversification count → refresh the companion(s).
	if newly and not _companion and kind != "player_2" and ("player_2" in _acquired) and _player2_phoenix_cd <= 0.0:
		_respawn_player2()
	return newly

## Player 2 needs an OTHER weapon at level >= P2_MIN_WEAPON_LEVEL to copy (an established, high-level weapon).
func _p2_eligible() -> bool:
	for k: String in _acquired:
		if k != "player_2" and weapon_level(k) >= P2_MIN_WEAPON_LEVEL:
			return true
	return false

## Public wrapper so the level-up UI doesn't OFFER Player 2 until it's actually acquirable.
func player2_eligible() -> bool:
	return _p2_eligible()

# ── Player 2 upgrade API (pool ranks + evolve capstone) ──
func player2_upgrade_rank(id: String) -> int:
	return int(_player2_upg.get(id, 0))

func player2_grant_upgrade(id: String) -> bool:
	if not PLAYER2_POOL.has(id):
		return false
	var maxr := int(PLAYER2_POOL[id]["max"])
	var rk := int(_player2_upg.get(id, 0))
	if maxr > 0 and rk >= maxr:
		return false
	if PLAYER2_POOL[id].has("gate"):   # Proactive Intelligence: rank r needs weapon level ≥ gate[r]
		var gates: Array = PLAYER2_POOL[id]["gate"]
		if rk < gates.size() and weapon_level("player_2") < int(gates[rk]):
			return false
	_player2_upg[id] = rk + 1
	_respawn_player2()   # push the new config to the companion(s)
	return true

func player2_set_capstone(id: String) -> void:
	_player2_capstone = id
	_respawn_player2()

# ── Player 2 config (read by _respawn_player2 → pushed to the companions) ──
## Number of DIFFERENT weapons you own (excluding Player 2 itself) — drives Diversification Mastery.
func _player2_weapon_count() -> int:
	var c := 0
	for k: String in _acquired:
		if k != "player_2":
			c += 1
	return c
func _player2_dmg_scale() -> float:
	var m := 1.0 + 0.05 * float(_player2_upg["damage"])                                    # Overclock
	m *= 1.0 + 0.0125 * float(_player2_upg["diversify"]) * float(_player2_weapon_count())  # Diversification Mastery
	return 0.25 * m
func _player2_fam_bonus() -> Dictionary:
	return {
		"kinetic":    0.10 * float(_player2_upg["kinetic"]),
		"energy":     0.10 * float(_player2_upg["energy"]),
		"biochemical": 0.10 * float(_player2_upg["biochemical"]),
	}
## The weapons Player 2 copies = the top (1 + Proactive rank) by level, highest first (excluding P2 itself).
func _player2_copy_list() -> Array:
	var kinds: Array = []
	for k: String in _acquired:
		if k != "player_2":
			kinds.append(k)
	kinds.sort_custom(func(a, b): return int(_levels.get(a, 1)) > int(_levels.get(b, 1)))
	var n := 1 + int(_player2_upg["proactive"])
	return kinds.slice(0, mini(n, kinds.size()))
func _player2_ship_count() -> int:
	return 2 if _player2_capstone == "ready_player_3" else 1

## (Re)spawn the Player-2 companion ship(s) with the current config. Called on pickup + on every P2 upgrade.
func force_spawn_player2() -> void:
	_respawn_player2()

func _respawn_player2() -> void:
	if _companion:
		return   # a companion never spawns its own companions (no recursion)
	despawn_player2()
	if _player2_phoenix_cd > 0.0:
		return   # shut down during the Project Phoenix cooldown
	var kinds := _player2_copy_list()
	if kinds.is_empty():
		return   # no weapon to copy → no ship
	var P2 := load("res://scripts/gameplay/arena_player2.gd")
	if P2 == null:
		return
	var scale := _player2_dmg_scale()
	var fam := _player2_fam_bonus()
	var procs := _player2_capstone == "full_sync"
	for i in _player2_ship_count():
		var node: Node = P2.new()
		node.set("copied_kinds", kinds.duplicate())
		node.set("dmg_scale", scale)
		node.set("fam_bonus", fam)
		node.set("procs_enabled", procs)
		node.set("ship_index", i)
		get_parent().add_child(node)
		_p2_nodes.append(node)

## Remove all live Player-2 companion ships (re-spawn to apply new config / a different copied weapon).
func despawn_player2() -> void:
	for n in _p2_nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_p2_nodes.clear()

## Project Phoenix (called from the arena death flow): if evolved + off cooldown, revive to full HP and shut
## Player 2 down for 10 minutes. Returns true if it consumed the death.
func player2_phoenix_try() -> bool:
	if _player2_capstone != "project_phoenix" or _player2_phoenix_cd > 0.0:
		return false
	GameManager.ship_hp = GameManager.ship_max_hp
	if GameManager.has_signal("ship_hp_changed"):
		GameManager.ship_hp_changed.emit(GameManager.ship_hp)
	_player2_phoenix_cd = PLAYER2_PHOENIX_CD
	despawn_player2()
	return true

## Ordered copy of the acquired weapon kinds — read by the slot HUD.
func acquired_weapons() -> Array:
	return _acquired.duplicate()

## Debug: instantly disarm every weapon and reset all active state.
func clear_all_weapons() -> void:
	_acquired.clear()
	_levels.clear()
	_gat_active     = false
	_gat_pending.clear()
	_death_beam_active  = false
	_arc_active     = false
	_gauss_active   = false
	_orbital_active = false
	_striker_active = false;  _striker_init = false;  _striker_balls.clear()
	_shooter_active = false;  _shooter_init = false;  _shooter_orbs.clear();  _shooter_bolts.clear()
	_void_active     = false
	_red_x_active    = false
	_chemtrail_active = false
	_mortar_active     = false;  _mortar_bullets.clear();  _wasteland_zones.clear()
	_sonic_active    = false
	_zsword_active   = false
	_ionize_active   = false;  _ionize_set_visible(false);  _ionize_rings.clear()
	_boom_active     = false;  _boom_init = false;  _booms.clear()
	for c: Dictionary in _para_clouds:
		var _pa: Node2D = c.get("plume")
		if _pa != null and is_instance_valid(_pa):
			_pa.queue_free()
	_para_active = false;  _para_clouds.clear();  _para_gas_puffs.clear()
	_stolen_armor = 0.0;  _stolen_armor_t = 0.0
	if GameManager.has_method("set_stolen_armor"):
		GameManager.set_stolen_armor(0.0)
	if _para_gas_fx != null and is_instance_valid(_para_gas_fx):
		_para_gas_fx.visible = false
	_moro_active     = false;  _moro_init = false
	_yari_active     = false;  _yari_init = false
	_swarm_active    = false;  _swarm_cd = 0.0;  _swarm_units.clear()
	for entry: Dictionary in _plume_registry:
		for anchor: Node2D in (entry.get("anchors", []) as Array):
			if is_instance_valid(anchor):
				anchor.visible = false
	_snake_active    = false;  _snake_init = false;  _snake_pts.clear()
	_snake2_init = false;  _snake2_pts.clear();  _snake_kills = 0

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

## Offerable in the level-up roll while it can still gain a level OR is maxed-but-not-yet-evolved (→ EVOLVE option).
func weapon_can_upgrade(kind: String) -> bool:
	if not (kind in _acquired):
		return false
	return int(_levels.get(kind, 1)) < _level_cap(kind) or weapon_needs_capstone(kind)

# ── Skill-point progression (level N→N+1 costs N+1 points; the first point on an unowned kind acquires it) ──
## Points already invested toward this kind's NEXT level (0-owned items start collecting toward level 2).
func weapon_points(kind: String) -> int:
	return int(_wpoints.get(kind, 0))

## Points needed to reach the next level: current_level + 1 (0→1 = 1, 1→2 = 2, … 5→6 = 6). 0 when maxed.
func weapon_next_cost(kind: String) -> int:
	return 0 if weapon_level(kind) >= _level_cap(kind) else 1   # 1 point = 1 level now

## Invest ONE skill point in `kind`: ALWAYS +1 level (acquire at 0→1). Returns true if a level was gained.
## No milestone level rewards anymore — the perk picked alongside this is the reward; level just counts to EVOLVE.
func spend_weapon_point(kind: String) -> bool:
	var lvl := weapon_level(kind)
	if lvl >= _level_cap(kind):
		return false   # already maxed (→ evolve)
	if lvl <= 0:
		acquire_weapon(kind)     # 0→1
	else:
		level_up_weapon(kind)    # L→L+1
	return true

## (Retired) milestone level rewards — kept as a no-op so any stray caller is harmless.
func _apply_global_level_reward(_kind: String, _new_level: int) -> void:
	pass

func weapons_full() -> bool:
	return _acquired.size() >= MAX_WEAPONS - _slot_penalty

## Per-level damage multiplier. Base weapons get NONE now (levels just count toward EVOLVE; power comes from the
## pool perks you pick each level). FUSIONS keep +30%/COMPOUNDING per level ABOVE MAX_WEAPON_LEVEL (their bonus levels).
func _lvl_mult(kind: String) -> float:
	if kind == "" or not (kind in _acquired):
		return 1.0
	if not is_fusion_kind(kind):
		return 1.0
	return pow(1.0 + WEAPON_DMG_PER_LEVEL, float(maxi(0, int(_levels.get(kind, 1)) - MAX_WEAPON_LEVEL)))

## Route a kind to its existing activate_<kind>() entry point.
func _activate_kind(kind: String) -> void:
	match kind:
		"gatling_gun": activate_gatling()
		"death_beam":  activate_death_beam()
		"arc":     activate_arc()
		"gauss":   activate_gauss()
		"defensive_orbitals": activate_orbital()
		"striker": activate_striker()
		"shooter": activate_shooter()
		"rift_maker":    activate_void()
		"dragons_breath":   activate_red_x()
		"chemtrail": activate_chemtrail()
		"mortar":    activate_mortar()
		"fat_boy": activate_fat_boy()
		"ultrasonicator":   activate_sonic()
		"z_sword":  activate_zsword()
		"ionizing_field":  activate_ionize()
		"aliwa": activate_boomerang()
		"venomancer":  activate_parasite()
		"yari":   activate_moroboshi()
		"yari_jaeger": activate_yari()
		"swarm":       activate_swarm()
		"viper":     activate_snake()
		"homing_missile":    activate_homing()
		"carnage":      activate_carnage()
		"vampire_host": activate_vampire()
		"overcharger":  activate_overcharger()
		"predator":     activate_predator()
		"toxic_ballistic": activate_toxic()
		"singularities": activate_singularity()
		"player_2":      force_spawn_player2()

# ── Weapon FUSION API ─────────────────────────────────────────────────────────────
func is_fusion_kind(kind: String) -> bool:
	return FUSION_DEFS.has(kind)

## Recipe ids ready to fuse: both components owned at MAX_WEAPON_LEVEL and the fusion not already owned.
## Fusions become available once both components reach FUSION_MIN_LEVEL (15) — UNLESS a component has already
## evolved (chosen a capstone), which permanently locks it out of fusion.
func available_fusions() -> Array:
	var out: Array = []
	for fid: String in FUSION_DEFS.keys():
		if fid in _acquired:
			continue
		var rec: Dictionary = FUSION_DEFS[fid]
		var a := String(rec["a"])
		var b := String(rec["b"])
		if (a in _acquired) and (b in _acquired) \
			and int(_levels.get(a, 1)) >= FUSION_MIN_LEVEL \
			and int(_levels.get(b, 1)) >= FUSION_MIN_LEVEL \
			and weapon_capstone(a) == "" and weapon_capstone(b) == "":   # not yet evolved
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
		"gatling_gun": _gat_active = false; _gat_pending.clear()
		"death_beam":  _death_beam_active = false
		"arc":     _arc_active = false
		"gauss":   _gauss_active = false
		"defensive_orbitals": _orbital_active = false
		"striker": _striker_active = false; _striker_init = false; _striker_balls.clear()
		"shooter": _shooter_active = false; _shooter_init = false; _shooter_orbs.clear(); _shooter_bolts.clear()
		"rift_maker":    _void_active = false; _void_on = false
		"dragons_breath":   _red_x_active = false; _red_x_cd = 0.0
		"chemtrail": _chemtrail_active = false
		"mortar", "fat_boy":  _mortar_active = false
		"ultrasonicator":   _sonic_active = false; _sonic_left = 0; _sonic_rings.clear()
		"z_sword":  _zsword_active = false
		"ionizing_field":  _ionize_active = false; _ionize_set_visible(false); _ionize_rings.clear()
		"aliwa": _boom_active = false
		"venomancer":
			_para_active = false
			_stolen_armor = 0.0
			if GameManager.has_method("set_stolen_armor"):
				GameManager.set_stolen_armor(0.0)
		"yari": _moro_active = false
		"swarm":     _swarm_active = false; _swarm_cd = 0.0; _swarm_units.clear()
		"viper":     _snake_active = false
		"homing":    _homing_active = false

## Cooldown/charge readiness for the slot HUD: 1.0 = ready (no mask), 0..1 = recovering (mask covers 1-frac).
func weapon_cooldown_frac(kind: String) -> float:
	var rate := maxf(0.01, _rate_mult)
	match kind:
		"gatling", "defensive_orbitals", "striker", "shooter", "chemtrail", "ionizing_field", "yari", "yari_jaeger", "swarm", "viper", "aliwa":
			return 1.0   # continuous stream / always-on passive or familiar → never masked
		"gauss":
			return clampf(_gauss_charge / maxf(0.01, _gauss_charge_time() / rate), 0.0, 1.0)
		"arc", "overcharger":
			if _arc_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _arc_cd / maxf(0.01, ARC_COOLDOWN / rate), 0.0, 1.0)
		"dragons_breath":
			if _red_x_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _red_x_cd / maxf(0.01, RED_X_INTERVAL / rate), 0.0, 1.0)
		"rift_maker":
			if _void_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _void_cd / maxf(0.01, VOID_COOLDOWN / rate), 0.0, 1.0)
		"death_beam":
			var lcyc := _db_cycle()
			var ldur := _db_duration()
			var phase := fmod(_db_t, lcyc)
			if phase < ldur:
				return 1.0   # firing window → ready
			return clampf((phase - ldur) / maxf(0.01, lcyc - ldur), 0.0, 1.0)
		"mortar", "fat_boy":
			if _mortar_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _mortar_cd / maxf(0.01, MORTAR_FIRE_INTERVAL / rate), 0.0, 1.0)
		"ultrasonicator":
			if _sonic_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _sonic_cd / maxf(0.01, SONIC_COOLDOWN / rate), 0.0, 1.0)
		"z_sword":
			if _zsword_cd <= 0.0:
				return 1.0
			return clampf(1.0 - _zsword_cd / maxf(0.01, ZSWORD_COOLDOWN / rate), 0.0, 1.0)
		"venomancer":
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
		"gatling_gun": return _gat_active
		"gauss":   return _gauss_active
		"arc":     return _arc_active
		"dragons_breath":   return _red_x_active
		"chemtrail": return _chemtrail_active
		"rift_maker":    return _void_active
		"defensive_orbitals": return _orbital_active
		"striker": return _striker_active
		"shooter": return _shooter_active
		"death_beam":  return _death_beam_active and fmod(_db_t, _db_cycle()) < _db_duration()
		"mortar", "fat_boy":  return _mortar_active
		"ultrasonicator":   return _sonic_active
		"z_sword":  return _zsword_active and _zsword_sweeping
		"ionizing_field":  return _ionize_active
		"aliwa": return _boom_active
		"venomancer":  return _para_active
		"yari":   return _moro_active
		"yari_jaeger": return _yari_active and _yari_sweeping
		"swarm":       return _swarm_active
		"viper":     return _snake_active
	return false

## Generic pickup drop used by the F12 weapon palette: spawn a `kind` pickup at a world position.
func spawn_weapon_pickup(kind: String, world_pos: Vector2) -> void:
	var p := PickupScript.new()
	p.add_to_group("debug_weapon_pickup")
	get_parent().add_child(p)
	p.setup(world_pos, kind)

## Debug (legacy F12): drop a Lasgun pickup at a world position on the gameplay plane.
func spawn_death_beam_pickup_near(world_pos: Vector2) -> void:
	spawn_weapon_pickup("death_beam", world_pos)

func _tick_bullets(delta: float) -> void:
	var ruins   := get_tree().get_nodes_in_group("arena_ruin")
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		b["pos"] = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) + delta
		var p: Vector2 = b["pos"]
		var dead := float(b["life"]) >= GAT_LIFETIME or p.distance_to(b["start"]) >= GAT_MAX_DIST
		if not dead and b.get("reflected", false):
			# Bismuth-reflected gatling bullet → now flies back and hits the PLAYER (ignores enemies/ruins).
			if _player != null and is_instance_valid(_player) and p.distance_to(_player.global_position) <= GAT_HIT_RADIUS + GAT_REFLECT_PAD:
				if GameManager.has_method("ship_take_damage"):
					GameManager.ship_take_damage(GAT_REFLECT_DMG)
				dead = true
		elif not dead:
			var bk: String = b.get("kind", "gatling_gun")   # Carnage/Red O fusion bullets tag their kind for level scaling
			var is_gat := bk == "gatling_gun"
			var hits: Array = b.get("hits", [])
			for en in _enemies_near(p, ENEMY_MAX_HIT_R):
				if not is_instance_valid(en):
					continue
				if is_gat and en in hits:
					continue   # pierce/bounce: never hit the same enemy twice
				var _en_r = en.get("hit_radius")
				var _hit_r: float = (float(_en_r) if _en_r != null else GAT_HIT_RADIUS) + GAT_BULLET_HIT_R
				if p.distance_to((en as Node2D).global_position) <= _hit_r:
					# Bismuth anti-magnetic: 50% of gatling bullets bounce back at the player instead of landing.
					if is_gat and en.has_method("is_anti_magnetic") and en.is_anti_magnetic() and randf() < GAT_REFLECT_FRAC:
						_reflect_bullet(b, (en as Node2D).global_position)
						break   # bullet survives, now reflected
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
					var ruin_r: float = (ruin.get("hit_radius") if ruin.get("hit_radius") != null else GAT_HIT_RADIUS) + GAT_BULLET_HIT_R
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
	var r := _roll_damage(base, "gatling_gun")   # "gatling_gun" → kinetic family mastery + Serrated bleed
	en.take_damage(float(r["dmg"]), GAT_STAGGER, 1.0, false, _bleeds("gatling_gun"), bool(r["is_crit"]))
	if bool(r["is_crit"]):
		_spawn_crit_number(p, float(r["dmg"]))
	if b.get("healing", false):
		if GameManager.has_method("heal"):
			GameManager.heal(GAT_HEAL_AMOUNT)             # heal the player
		if en.has_method("take_damage"):
			en.take_damage(-float(GAT_HEAL_AMOUNT), 0.0)  # …and the target (negative damage = heal)

## Bounce a gatling bullet back off an anti-magnetic (bismuth) enemy: reverse it into a 45° cone from the
## impact and flag it so _tick_bullets sends it at the PLAYER instead of enemies.
func _reflect_bullet(b: Dictionary, hit_pos: Vector2) -> void:
	var vel: Vector2 = b["vel"]
	var spd := vel.length()
	var back := (-vel).normalized() if spd > 0.01 else Vector2.UP
	var ang := back.angle() + randf_range(-deg_to_rad(22.5), deg_to_rad(22.5))   # ±22.5° → 45° cone
	b["vel"] = Vector2(cos(ang), sin(ang)) * spd
	b["reflected"] = true
	b["start"] = hit_pos   # reset travel origin so it isn't instantly range-culled
	b["life"] = 0.0        # reset lifetime so it can fly back across the screen

## On a Gatling bullet hit: maybe BOUNCE (redirect to a perpendicular nearby foe) or PIERCE (continue straight).
## Returns true if the bullet survives, false if it should die.
func _gat_bounce_or_pierce(b: Dictionary) -> bool:
	var vel: Vector2 = b["vel"]
	var pierced := _proc(_gat_pierce_chance())   # + Stroke of Luck
	# Bouncing Round: a GUARANTEED ricochet per remaining bounce in this bullet's budget (+1 per rank at fire
	# time). Spend one only when a fresh target actually exists, so a wasted look doesn't burn the budget.
	var tgt: Node = null
	if int(b.get("bounces", 0)) > 0:
		tgt = _gat_bounce_target(b["pos"], vel, b["hits"])
	if tgt == null:
		return pierced   # nothing to ricochet into → pierce alone decides whether the bullet lives
	var left := int(b["bounces"]) - 1
	var newdir := ((tgt as Node2D).global_position - (b["pos"] as Vector2)).normalized()
	b["bounces"] = left
	if pierced:
		# BOTH procced → split: the original ploughs straight on, a clone peels off to take the ricochet.
		_gat_spawn_bounce_clone(b, newdir, left)
		return true
	# Bounce only → the bullet itself takes the ricochet.
	b["vel"] = newdir * GAT_SPEED * _weapon_speed_mult()
	b["start"] = b["pos"]   # refresh the travel-distance budget so it doesn't instantly despawn
	return true

## The ricochet half of a pierce+bounce hit: a fresh bullet at the impact point flying at `dir`, inheriting the
## parent's hit list (so it can't re-hit what the parent already hit) and its remaining bounce budget. Shares the
## parent's `life` clock so a splitting chain still dies at GAT_LIFETIME rather than renewing itself forever.
## Appended to the end of _bullets — _tick_bullets walks the index DOWNWARD, so it isn't re-processed this frame.
func _gat_spawn_bounce_clone(parent: Dictionary, dir: Vector2, bounces_left: int) -> void:
	var pos: Vector2 = parent["pos"]
	var clone := {
		"pos": pos, "vel": dir * GAT_SPEED * _weapon_speed_mult(),
		"life": float(parent.get("life", 0.0)), "start": pos,   # fresh distance budget, inherited age
		"kind": "gatling_gun", "hits": (parent["hits"] as Array).duplicate(), "bounces": bounces_left,
	}
	if bool(parent.get("healing", false)):
		clone["healing"] = true
	_bullets.append(clone)

## Bounce target: the not-yet-hit enemy within range whose direction is most PERPENDICULAR to the bullet's path.
func _gat_bounce_target(pos: Vector2, vel: Vector2, hits: Array) -> Node:
	var perp := vel.orthogonal().normalized() if vel.length() > 0.01 else Vector2.RIGHT
	var best: Node = null
	var best_score := -1.0
	for en in _enemies():
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
	var annih := _gauss_capstone == "annihilation"
	if _gauss_capstone == "spirit_bomb":
		var would := _gauss_fission_count()
		var budget := _gauss_budget() * (1.0 + 1.25 * float(would)) * _dmg_mult   # +125% per would-be orb
		_spawn_gauss_orb(_forward(), budget, 1.0 + 0.10 * float(would), annih)     # +10% area per would-be orb
	else:
		var count := _gauss_fission_count()
		var budget := _gauss_budget() * _dmg_mult
		var size := _gauss_size_mult()   # Pew Pew → 0.25
		var basea := _forward().angle()
		for k in count:
			# Fission spreads orbs to maximum angular distance: 2→180°, 3→120°, n→360/n apart.
			var ang := basea + TAU * float(k) / float(count)
			_spawn_gauss_orb(Vector2.from_angle(ang), budget, size, annih)
	_flashes.append({"pos": _muzzle(), "age": 0.0, "max_age": 0.30, "radius": GAUSS_LAUNCH_FLASH})
	# Pop the release flash (the shot's muzzle flash).
	if GC_RELEASE_FLASH > 0.0:
		_flashes.append({"pos": _muzzle(), "age": 0.0, "max_age": 0.30, "radius": GC_RELEASE_FLASH})

func _spawn_gauss_orb(dir: Vector2, budget: float, size_mult: float, annih: bool) -> void:
	var start := _muzzle()
	var orb := _make_orb()
	if annih and orb != null:
		orb.modulate = Color(1.6, 0.4, 0.4)   # Orb of Annihilation → RED
	var o := {
		"pos": start, "vel": dir * GAUSS_SPEED * _weapon_speed_mult(), "life": 0.0, "start": start,
		"orb_node": orb, "trail": [], "spark_acc": 0.0, "dmg": budget, "dmg_ref": budget, "hit": [],
		"size_mult": size_mult, "annih": annih,
	}
	_orbs.append(o)
	_update_orb_node(o)

func _tick_orbs(delta: float) -> void:
	# Fallback (see GAUSS_USE_SPRITE_VFX): advance the shared plasma-orb flipbook loop (all live orbs show
	# the same frame).
	if GAUSS_USE_SPRITE_VFX and not _gauss_frames.is_empty() and GAUSS_ORB_FPS > 0.0:
		_gauss_fb_t += delta
		var gspf := 1.0 / GAUSS_ORB_FPS
		while _gauss_fb_t >= gspf:
			_gauss_fb_t -= gspf
			_gauss_fb_idx = (_gauss_fb_idx + 1) % _gauss_frames.size()
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
			for en in _enemies_near(p, ENEMY_MAX_HIT_R):
				if not is_instance_valid(en):
					continue
				var _en_r = en.get("hit_radius")
				var _hit_r: float = (float(_en_r) if _en_r != null else GAUSS_RADIUS) + GAUSS_ORB_HIT_PAD
				if p.distance_to((en as Node2D).global_position) <= _hit_r:
					_spawn_gauss_explosion(p, "gauss", float(o.get("size_mult", 1.0)), bool(o.get("annih", false)))
					dead = true
					break
			if not dead:
				for ruin in ruins:
					if not is_instance_valid(ruin):
						continue
					var ruin_r: float = (ruin.get("hit_radius") if ruin.get("hit_radius") != null else GAUSS_RADIUS) + GAUSS_ORB_HIT_PAD
					if p.distance_to((ruin as Node2D).global_position) <= ruin_r:
						_spawn_gauss_explosion(p, "gauss", float(o.get("size_mult", 1.0)), bool(o.get("annih", false)))
						dead = true
						break
		if dead:
			_free_orb(o)
			_orbs.remove_at(i)
		i -= 1

## The Gauss projectile: by default a procedural plasma-ball (gauss_orb_fx.gd/.gdshader) — a dumb draw node
## that arena_weapons.gd drives with a world position + diameter each tick, same pattern as the Gauss
## explosion and Lasgun beam VFX. Normal alpha blend (baked into the shader) — additive would blow out the
## white-hot core once several orbs/explosions overlap (Fission spawns multiple orbs at once).
## GAUSS_USE_SPRITE_VFX falls back to the original 24-frame plasma flipbook sprite (TextureRect) instead.
func _make_orb() -> CanvasItem:
	if GAUSS_USE_SPRITE_VFX:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if not _gauss_frames.is_empty():
			tr.texture = _gauss_frames[_gauss_fb_idx]
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		return tr
	var orb := GaussOrbFX.new()
	add_child(orb)
	return orb

func _update_orb_node(o: Dictionary) -> void:
	var trail: Array = o.get("trail", [])
	trail.push_front(o["pos"])
	if trail.size() > GAUSS_TRAIL_LEN:
		trail.resize(GAUSS_TRAIL_LEN)
	o["trail"] = trail
	# Round orb → square footprint, no stretch/rotation. Diameter shrinks ∝ sqrt(remaining damage) so the
	# orb's AREA is proportional to its damage budget.
	var frac := clampf(float(o["dmg"]) / maxf(1.0, float(o["dmg_ref"])), 0.0, 1.0)
	var d := GAUSS_ORB_DRAW * sqrt(frac) * float(o.get("size_mult", 1.0))   # Pew Pew shrinks, Spirit Bomb grows
	if GAUSS_USE_SPRITE_VFX:
		var tr := o.get("orb_node") as TextureRect
		if tr == null or not is_instance_valid(tr):
			return
		if not _gauss_frames.is_empty():
			tr.texture = _gauss_frames[_gauss_fb_idx]   # advance the shared plasma loop
		tr.size = Vector2(d, d)
		tr.position = (o["pos"] as Vector2) - Vector2(d, d) * 0.5
		return
	var orb := o.get("orb_node") as Node2D
	if orb == null or not is_instance_valid(orb):
		return
	orb.diameter = d
	orb.global_position = o["pos"]
	orb.queue_redraw()

func _free_orb(o: Dictionary) -> void:
	var orb := o.get("orb_node") as CanvasItem
	if orb != null and is_instance_valid(orb):
		orb.queue_free()
	o["orb_node"] = null

# ── Gauss explosion (AoE plasma burst spawned on orb impact) ──────────────────
## Spawn a self-expiring explosion at world `pos`. Each explosion owns its own draw node + timers → fully
## independent. By default the "big sphere" is the same procedural plasma-ball node as the orb
## (gauss_orb_fx.gd), just driven bigger and faster; GAUSS_USE_SPRITE_VFX falls back to the original
## 3-variant, 12-frame flipbook burst (gauss_explosion_fx.gd) instead.
func _spawn_gauss_explosion(pos: Vector2, kind := "gauss", size_mult := 1.0, annih := false) -> void:
	var fx: Node2D
	var variant := 0
	if GAUSS_USE_SPRITE_VFX:
		if not _expl_frames.is_empty():
			variant = randi() % _expl_frames.size()
		# Dedicated additive draw node: draw_texture_rect scales the full frame into draw_rect (no
		# EXPAND_IGNORE_SIZE clip → no square). Core pixel (173,183) lands on the impact point.
		var sfx := GaussExplFX.new()
		sfx.draw_rect = Rect2(-GAUSS_EXPL_ANCHOR * GAUSS_EXPL_SCALE * size_mult,
			Vector2(GAUSS_EXPL_FRAME_W, GAUSS_EXPL_FRAME_H) * GAUSS_EXPL_SCALE * size_mult)
		fx = sfx
	else:
		# Runs its internal crackle 10x faster (frantic burst) and skips the small orb's idle size-breathing
		# pulse (the explosion already animates its own size via the intro pop-in / outro fade below).
		var pfx := GaussOrbFX.new()
		pfx.time_scale = 10.0
		pfx.size_pulse_enabled = false
		fx = pfx
	fx.global_position = pos
	if annih:
		fx.modulate = Color(1.6, 0.4, 0.4)   # Orb of Annihilation → RED
	add_child(fx)
	# tick_acc seeded to ≥ one full interval so the first DoT tick lands on the spawn frame (the field is active
	# "the instant it spawns"). The random extra phase DESYNCS overlapping fields so two explosions on the same
	# enemy tick at interleaved times (visibly stacking) instead of in lockstep (which read as a single hit).
	var e := {"pos": pos, "age": 0.0, "variant": variant, "node": fx, "tick_acc": GAUSS_TICK_INTERVAL + randf() * GAUSS_TICK_INTERVAL, "kind": kind, "dur": GAUSS_EXPL_DURATION * _duration_mult(), "size_mult": size_mult, "annih": annih}
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
		if float(e["age"]) >= float(e.get("dur", GAUSS_EXPL_DURATION)):
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
		var g_int := GAUSS_TICK_INTERVAL / _tick_rate()   # Intensity Mastery → faster ticks
		while float(e["tick_acc"]) >= g_int:
			e["tick_acc"] = float(e["tick_acc"]) - g_int
			_gauss_explosion_tick(e["pos"], String(e.get("kind", "gauss")), float(e.get("size_mult", 1.0)), bool(e.get("annih", false)))
		i -= 1

## One DoT tick: GAUSS_TICK_DAMAGE scaled by the damage stat (+ crit) to every enemy in radius, plus ruins.
## Same enumeration + damage call + crit-number path as the orbital/void AoE weapons.
func _gauss_explosion_tick(center: Vector2, kind := "gauss", size_mult := 1.0, annih := false) -> void:
	var is_gauss := kind == "gauss"
	var radius := GAUSS_EXPL_RADIUS * size_mult * (1.0 + (GameManager.mech_bonus("aoe_pct") if (is_gauss and GameManager.has_method("mech_bonus")) else 0.0))   # AoE Mastery + Pew/Spirit size
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= radius + GAUSS_EXPL_HIT_PAD:
			if annih and en.has_method("apply_vulnerable"):
				en.call("apply_vulnerable", 0.3)   # Orb of Annihilation: +20% damage while in the orb (refreshed)
			if en.has_method("take_damage"):
				var r := _roll_damage(_gauss_tick_dmg(), "gauss") if is_gauss else _roll_damage(GAUSS_TICK_DAMAGE, kind)
				en.take_damage(float(r["dmg"]), 0.0, 0.0, false, _bleeds("gauss"), bool(r["is_crit"]))
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
				if is_gauss:   # Meltdown (burn) / EMP (stun) — separate per-tick rolls (via _proc → Stroke of Luck)
					if _gauss_burn_chance() > 0.0 and en.has_method("apply_burn") and _proc(_gauss_burn_chance() * GAUSS_TICK_INTERVAL):
						en.call("apply_burn", 1)
					if _gauss_stun_chance() > 0.0 and en.has_method("apply_stun") and _proc(_gauss_stun_chance() * GAUSS_TICK_INTERVAL):
						en.call("apply_stun", 0.5 * (1.0 + (GameManager.mech_bonus("lightning_stun_dur") if GameManager.has_method("mech_bonus") else 0.0)))
	for ruin in _ruins():
		if not is_instance_valid(ruin):
			continue
		var ruin_r: float = radius + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
		if center.distance_to((ruin as Node2D).global_position) <= ruin_r:
			if ruin.has_method("take_damage"):
				ruin.take_damage((_gauss_tick_dmg() * _dmg_mult) if is_gauss else (GAUSS_TICK_DAMAGE * _dmg_mult * _lvl_mult(kind)))

## Feed the visual node its current state. Procedural (default): pop open over GAUSS_EXPL_INTRO_TIME, hold
## at full size (crackling continuously — same shader as the small orb), then fade out over the last
## GAUSS_EXPL_OUTRO_TIME of DURATION — position/scale are NOT fixed at spawn since diameter animates.
## GAUSS_USE_SPRITE_VFX: feed the flipbook its scheduled frame instead (position/scale WERE fixed at spawn).
func _update_explosion_node(e: Dictionary) -> void:
	var fx := e.get("node") as Node2D
	if fx == null or not is_instance_valid(fx):
		return
	if GAUSS_USE_SPRITE_VFX:
		var variant: int = e.get("variant", 0)
		if variant < 0 or variant >= _expl_frames.size():
			return
		var frames: Array = _expl_frames[variant]
		if frames.is_empty():
			return
		var fi := clampi(_explosion_frame_index(float(e["age"])), 0, frames.size() - 1)
		fx.set_frame(frames[fi])
		return
	var age := float(e["age"])
	var dur := float(e.get("dur", GAUSS_EXPL_DURATION))
	var pop := smoothstep(0.0, GAUSS_EXPL_INTRO_TIME, age)
	var fade := 1.0 - smoothstep(maxf(0.0, dur - GAUSS_EXPL_OUTRO_TIME), dur, age)
	fx.diameter = GAUSS_EXPL_DRAW * float(e.get("size_mult", 1.0)) * pop
	fx.modulate.a = fade
	fx.global_position = e["pos"]
	fx.queue_redraw()

## Fallback (see GAUSS_USE_SPRITE_VFX) non-uniform schedule → 0-indexed flipbook frame:
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
	if not GameManager.has_method("mech_bonus"):
		return base
	return (base + GameManager.mech_bonus("radius")) * (1.0 + GameManager.mech_bonus("aoe_pct"))   # flat (Explosivo) + % (Gauss AoE Mastery, global)

# ── Mortar (Little Man) + Fat Boy (Fat Boy) ──────────────────────────
func activate_mortar() -> void:
	_mortar_active = true
	_mortar_cd = 0.0
	_ensure_mortar_tex()

func activate_fat_boy() -> void:
	# Fat Boy is now the Mortar's evolve — the F12 debug entry activates the Mortar already evolved.
	activate_mortar()
	_mortar_capstone = "fat_boy"

func _ensure_mortar_tex() -> void:
	if _mortarbullet_tex == null:
		_mortarbullet_tex = load("res://assets/weaponry/mortarbullet.png") as Texture2D

# ── Mortar upgrade API (pool ranks + evolve capstone) ──
func mortar_upgrade_rank(id: String) -> int:
	return int(_mortar_upg.get(id, 0))

func mortar_grant_upgrade(id: String) -> bool:
	if not MORTAR_POOL.has(id):
		return false
	var maxr := int(MORTAR_POOL[id]["max"])
	if maxr > 0 and int(_mortar_upg.get(id, 0)) >= maxr:
		return false
	_mortar_upg[id] = int(_mortar_upg.get(id, 0)) + 1
	if id == "kinetic" and GameManager.has_method("add_mech"):
		GameManager.add_mech("kinetic_dmg", 0.05)   # GLOBAL: shared Kinetic Mastery (same key as Gatling's)
	return true

func mortar_set_capstone(id: String) -> void:
	_mortar_capstone = id
	if id == "fusion_reactor":
		# Deactivate the Mortar → passive reactor: permanent global buffs (applied once, like All-In).
		if GameManager.has_method("add_hp_regen"):     GameManager.add_hp_regen(5.0)
		if GameManager.has_method("add_shield_regen"): GameManager.add_shield_regen(5.0)
		if GameManager.has_method("add_move_speed"):   GameManager.add_move_speed(0.10)
		if GameManager.has_method("add_fire_rate"):    GameManager.add_fire_rate(0.10)
		if GameManager.has_method("add_mech"):         GameManager.add_mech("all_dmg", 0.10)

# ── Mortar effective stats (pool + capstone) ──
func _mortar_cap_dmg_mult() -> float:
	if _mortar_capstone == "fat_boy":    return FATBOY_DMG_MULT
	if _mortar_capstone == "little_man": return LILMAN_DMG_MULT
	return 1.0

func _mortar_cap_aoe_mult() -> float:
	if _mortar_capstone == "fat_boy":    return FATBOY_AOE_MULT
	if _mortar_capstone == "little_man": return LILMAN_AOE_MULT
	return 1.0

func _mortar_cap_rate_mult() -> float:
	if _mortar_capstone == "fat_boy":    return FATBOY_RATE_MULT
	if _mortar_capstone == "little_man": return LILMAN_RATE_MULT
	return 1.0

## Per-shot damage (Bigger Payload + Concentrated Fire + capstone; global/family/crit added by _roll_damage).
func _mortar_shot_damage() -> float:
	var m := 1.0 + 0.10 * float(_mortar_upg["damage"]) + 0.15 * float(_mortar_upg["concentrated"])
	return MORTAR_DAMAGE * m * _mortar_cap_dmg_mult()

## Blast radius (Wider Blast + Concentrated Fire trade-off + capstone + global AoE mods).
func _mortar_blast_radius() -> float:
	var m := maxf(0.05, 1.0 + 0.10 * float(_mortar_upg["aoe"]) - 0.10 * float(_mortar_upg["concentrated"]))
	return _aoe_radius(MORTAR_AOE * m * _mortar_cap_aoe_mult())

## Fire interval (Rapid Reload + capstone + global fire-rate).
func _mortar_interval() -> float:
	var fr := _rate_mult * (1.0 + 0.08 * float(_mortar_upg["firerate"])) * _mortar_cap_rate_mult()
	return MORTAR_FIRE_INTERVAL / maxf(0.01, fr)

## Mortar: auto-fire one mortarbullet toward the mouse. The Fusion Reactor evolve turns it off (passive core).
func _tick_mortar(delta: float) -> void:
	if _mortar_capstone == "fusion_reactor":
		return
	_mortar_cd -= delta
	if _mortar_cd <= 0.0:
		_mortar_cd = _mortar_interval()
		_fire_mortar()

## Launch one mortarbullet from the ship straight toward the current mouse position.
func _fire_mortar() -> void:
	if _player == null:
		return
	var origin := _player.global_position
	var dir := get_global_mouse_position() - origin
	dir = dir.normalized() if dir.length() > 0.01 else _forward()
	var muzzle := _mz(6) if _has_anchors() else origin + dir * MUZZLE_OFFSET   # point 6
	_mortar_bullets.append({
		"pos": muzzle, "vel": dir * MORTAR_BULLET_SPEED, "life": 0.0,
	})

## Move bullets; the FIRST enemy a bullet touches → detonate (AoE damage + scaled explosion VFX). Cull on timeout.
func _tick_mortar_bullets(delta: float) -> void:
	var i := _mortar_bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _mortar_bullets[i]
		b["life"] = float(b["life"]) + delta
		var pos: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["pos"] = pos
		var hit := false
		for en in _enemies_near(pos, ENEMY_MAX_HIT_R):
			if not is_instance_valid(en):
				continue
			var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 12.0
			if pos.distance_to((en as Node2D).global_position) <= enr:
				hit = true
				break
		if not hit:
			for ruin in _ruins():
				if not is_instance_valid(ruin):
					continue
				var rr: float = float(ruin.get("hit_radius")) if ruin.get("hit_radius") != null else 12.0
				if pos.distance_to((ruin as Node2D).global_position) <= rr:
					hit = true
					break
		if hit:
			_explode_mortar(pos)
			_mortar_bullets.remove_at(i)
		elif float(b["life"]) >= MORTAR_BULLET_LIFE:
			_mortar_bullets.remove_at(i)
		i -= 1

## AoE detonation at `pos`: damage every enemy/ruin in radius once + spawn the explosion VFX (+ a Waste Land crater).
func _explode_mortar(pos: Vector2) -> void:
	var is_big := _mortar_capstone == "fat_boy"
	var dmg := _mortar_shot_damage()
	var aoe := _mortar_blast_radius()
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var en2 := en as Node2D
		var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
		if pos.distance_to(en2.global_position) <= aoe + enr:
			if en.has_method("take_damage"):
				var r := _roll_damage(dmg, "mortar")
				en.take_damage(float(r["dmg"]), MORTAR_BLAST_STAGGER, 1.0, false, true, bool(r["is_crit"]))   # Mortar keeps pushback
				if bool(r["is_crit"]):
					_spawn_crit_number(en2.global_position, float(r["dmg"]))
	for ruin in _ruins():
		if not is_instance_valid(ruin):
			continue
		var rr: float = aoe + (float(ruin.get("hit_radius")) if ruin.get("hit_radius") != null else 0.0)
		if pos.distance_to((ruin as Node2D).global_position) <= rr:
			if ruin.has_method("take_damage"):
				ruin.take_damage(dmg * _dmg_mult * _lvl_mult("mortar"))
	# Waste Land: leave a lingering damaging + slowing crater (radius = this shot's blast).
	if int(_mortar_upg["wasteland"]) > 0:
		_spawn_wasteland(pos, aoe, dmg)
	# Fat Boy = blast VFX matches its actual AoE damage radius; otherwise a tiny (1%) LITE puff, 1.5× faster, no fullscreen shockwave.
	if is_big:
		_spawn_mortar_explosion(pos, aoe, 1.0, false)
	else:
		var full_px := _aoe_radius(MORTAR_RADIUS) * _mortar_cap_aoe_mult()
		_spawn_mortar_explosion(pos, full_px * MORTAR_VFX_SCALE, 1.5, true)

## Barbed Wire: the ship's contact damage vs an enemy — rolled as KINETIC (so crit/kinetic/global apply), plus
## the contact-bleed perk and the Blood Thirsty lifesteal. Called from arena_enemy._check_contact (throttled 0.5s).
func apply_ship_contact(en) -> void:
	if not is_instance_valid(en) or not en.has_method("take_damage"):
		return
	var base := GameManager.ship_contact_damage() if GameManager.has_method("ship_contact_damage") else 0.0
	if base <= 0.0:
		return
	var r := _roll_damage(base, "chain")   # "chain" = kinetic family → kinetic/all/crit buffs apply
	en.take_damage(float(r["dmg"]), 0.0, 0.0, false, false, bool(r["is_crit"]))
	var cb := int(GameManager.mech_bonus("contact_bleed")) if GameManager.has_method("mech_bonus") else 0
	if cb > 0 and en.has_method("apply_bleed"):
		en.apply_bleed(cb)
	if GameManager.upg_blood_thirsty and GameManager.has_method("heal"):
		GameManager.heal(int(round(float(r["dmg"]) * 0.05)))
	if bool(r["is_crit"]):
		_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))

## Number of contact-damage weapons owned (Barbed Wire "Fortify" reads this).
func contact_source_count() -> int:
	var n := 0
	for k: String in _acquired:
		if k in CONTACT_KINDS:
			n += 1
	return n

## Data Harvester: on level-up, heal a % of Max HP + detonate a kinetic AoE blast (200px × AoE) around the ship.
func _on_harvest_levelup(_lvl: int) -> void:
	if _companion or GameManager.upg_harvester_off:
		return
	var hp_pct := GameManager.mech_bonus("levelup_heal")
	if hp_pct > 0.0 and GameManager.has_method("heal"):
		GameManager.heal(int(round(hp_pct * float(GameManager.ship_max_hp))))
	var dmg := GameManager.mech_bonus("levelup_dmg")
	if dmg > 0.0 and _player != null and is_instance_valid(_player):
		var pos := _player.global_position
		var aoe := _aoe_radius(200.0)
		for en in _enemies() + _ruins():
			if not is_instance_valid(en):
				continue
			var en2 := en as Node2D
			var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
			if pos.distance_to(en2.global_position) <= aoe + enr:
				if en.has_method("take_damage"):
					var r := _roll_damage(dmg, "chain")
					if en.is_in_group("arena_ruin"):
						en.take_damage(float(r["dmg"]))   # ruins only implement the 3-arg form
					else:
						en.take_damage(float(r["dmg"]), 0.0, 0.0, false, false, bool(r["is_crit"]))
					if bool(r["is_crit"]):
						_spawn_crit_number(en2.global_position, float(r["dmg"]))
		_spawn_mortar_explosion(pos, aoe * 1.3, 1.3, true)

## Explosivo "Chain Reaction" evolve: a slain enemy detonates for 50 kinetic damage in a small (AoE-scaled) blast.
## Called from arena_enemy._die() (which already rolled the 25% chance). Routes through _roll_damage so global /
## crit / kinetic bonuses apply.
func chain_reaction_explode(pos: Vector2) -> void:
	var aoe := _aoe_radius(50.0)
	for en in _enemies() + _ruins():
		if not is_instance_valid(en):
			continue
		var en2 := en as Node2D
		var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
		if pos.distance_to(en2.global_position) <= aoe + enr:
			if en.has_method("take_damage"):
				var r := _roll_damage(50.0, "chain")
				if en.is_in_group("arena_ruin"):
					en.take_damage(float(r["dmg"]))   # ruins only implement the 3-arg form
				else:
					en.take_damage(float(r["dmg"]), 0.0, 0.0, false, false, bool(r["is_crit"]))
				if bool(r["is_crit"]):
					_spawn_crit_number(en2.global_position, float(r["dmg"]))
	_spawn_mortar_explosion(pos, aoe * 1.6, 1.6, true)   # small lite blast VFX

## Waste Land crater: total damage over its life = frac × rank × the shot's damage, split evenly across ticks. Stacks.
func _spawn_wasteland(pos: Vector2, radius: float, shot_dmg: float) -> void:
	var rank := int(_mortar_upg["wasteland"])
	var total := WASTELAND_DMG_FRAC * float(rank) * shot_dmg
	var per_tick := total * (WASTELAND_TICK / WASTELAND_DUR)
	_wasteland_zones.append({"pos": pos, "radius": radius, "dmg": per_tick, "age": 0.0, "tick": 0.0})
	if _wasteland_zones.size() > WASTELAND_MAX_ZONES:
		_wasteland_zones.remove_at(0)

## Tick every crater: damage + 25% slow to enemies inside; expire after WASTELAND_DUR. Craters damage independently.
func _tick_wasteland(delta: float) -> void:
	var i := _wasteland_zones.size() - 1
	while i >= 0:
		var z: Dictionary = _wasteland_zones[i]
		z["age"] = float(z["age"]) + delta
		if float(z["age"]) >= WASTELAND_DUR:
			_wasteland_zones.remove_at(i)
			i -= 1
			continue
		z["tick"] = float(z["tick"]) + delta
		var zr: float = z["radius"]
		var zp: Vector2 = z["pos"]
		while float(z["tick"]) >= WASTELAND_TICK:
			z["tick"] = float(z["tick"]) - WASTELAND_TICK
			for en in _enemies() + _ruins():
				if not is_instance_valid(en):
					continue
				var en2 := en as Node2D
				var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
				if zp.distance_to(en2.global_position) <= zr + enr:
					if en.has_method("take_damage"):
						var r := _roll_damage(float(z["dmg"]), "mortar")
						if en.is_in_group("arena_ruin"):
							en.take_damage(float(r["dmg"]))   # ruins only implement the 3-arg form
						else:
							en.take_damage(float(r["dmg"]), 0.0, 0.0, false, true, bool(r["is_crit"]))
					if en.has_method("apply_sedative"):
						en.apply_sedative(0.0, WASTELAND_SLOW, WASTELAND_TICK * 1.6)
		i -= 1

## Composite explosion VFX (extracted from the old Nuke detonation), sized by size_px.
## speed_mult > 1 plays it faster; `lite` = a cheap small puff (no fullscreen shockwave, fewer particles, no shake)
## for the tiny Mortar so it isn't GPU-heavy at 1 shot/sec.
func _spawn_mortar_explosion(pos: Vector2, size_px: float, speed_mult: float = 1.0, lite: bool = false) -> void:
	var ex := ExplosionFX.new()
	ex.time_scale = (ex.time_scale / 3.0) * speed_mult
	ex.shockwave_layer = 8   # above the world (0), below ALL HUD layers (UI 10, buttons 11, crit 12…) → ripple arena only, never the HUD
	ex.glow = 1.4
	ex.core_size = 0.5
	ex.core_hot = Color(3.0, 2.3, 1.6)
	if lite:
		# Small fast Mortar puff — KEEP the shockwave but cap its ring radius to ~250px (was fullscreen) + trim particles.
		ex.fireball_amount = 28
		ex.smoke_amount = 45
		ex.streak_amount = 24
		var vp_h := get_viewport_rect().size.y   # shockwave_max_radius is in screen-height units → px / height
		if vp_h > 1.0:
			ex.shockwave_max_radius = 250.0 / vp_h
	else:
		# Giant Fat Boy blast — exaggerate the shockwave to sweep the whole screen.
		ex.shockwave_max_radius = ex.shockwave_max_radius * 3.0
		ex.shockwave_travel = ex.shockwave_travel * 2.0
	get_parent().add_child(ex)
	ex.call("setup", pos, size_px)
	if not lite:
		var cam := get_tree().get_first_node_in_group("camera_shake")
		if cam != null and cam.has_method("mortar_impact"):
			cam.call("mortar_impact")

## Draw in-flight mortarbullets at native aspect ratio, nose pointing along velocity.
func _draw_mortar_bullets() -> void:
	if _mortarbullet_tex == null:
		return
	var bl := MORTAR_BULLET_LEN
	var tw := float(_mortarbullet_tex.get_width())
	var th := float(_mortarbullet_tex.get_height())
	var bw := bl
	if th > 0.0:
		bw = bl * (tw / th)
	for b: Dictionary in _mortar_bullets:
		var ang := (b["vel"] as Vector2).angle() + PI / 2.0
		draw_set_transform(b["pos"], ang, Vector2.ONE)
		draw_texture_rect(_mortarbullet_tex, Rect2(-bw * 0.5, -bl * 0.5, bw, bl), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Waste Land craters: a smouldering toxic-orange disc that fades as it expires (fill + hot rim + inner glow).
func _draw_wasteland() -> void:
	for z: Dictionary in _wasteland_zones:
		var p: Vector2 = z["pos"]
		var r: float = z["radius"]
		var life := clampf(1.0 - float(z["age"]) / WASTELAND_DUR, 0.0, 1.0)   # 1 → 0 over its life
		draw_circle(p, r, Color(0.85, 0.35, 0.10, 0.16 * life))          # smouldering fill
		draw_circle(p, r * 0.55, Color(1.0, 0.55, 0.15, 0.12 * life))     # hotter core glow
		draw_arc(p, r, 0.0, TAU, 40, Color(1.0, 0.45, 0.15, 0.5 * life), 2.5, true)   # ember rim

# ── Reactive Plating (Exoskeleton evo): every 500 mitigated damage erupts a shockwave ──────────────────────
const REACTIVE_RADIUS := 400.0
const REACTIVE_DAMAGE  := 100.0
func _fire_mitigation_shockwave() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center := _player.global_position
	for en in _enemies() + _ruins():
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= REACTIVE_RADIUS:
			if en.has_method("take_damage"):
				var r := _roll_damage(REACTIVE_DAMAGE, "")   # kinetic (global dmg mult + crit; no per-weapon scaling)
				en.take_damage(float(r["dmg"]), 0.3)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
	var ex := ExplosionFX.new()
	get_parent().add_child(ex)
	ex.call("setup", center, REACTIVE_RADIUS)

# ── Sonic Wave ──────────────────────────────────────────────────────────────────────
func activate_sonic() -> void:
	_sonic_active = true
	_sonic_cd = 0.0

# ── Sonic pool: API + effective stats ──
func sonic_grant_upgrade(id: String) -> bool:
	if not SONIC_POOL.has(id):
		return false
	var maxr := int(SONIC_POOL[id]["max"])
	if maxr > 0 and int(_sonic_upg.get(id, 0)) >= maxr:
		return false
	_sonic_upg[id] = int(_sonic_upg.get(id, 0)) + 1
	return true

func _sonic_dmg() -> float:
	return SONIC_DAMAGE * (1.0 + 0.10 * float(_sonic_upg["damage"]))
func _sonic_range() -> float:
	return SONIC_MAX_RADIUS * (1.0 + 0.15 * float(_sonic_upg["range"]))
func _sonic_cd_mult() -> float:
	return 1.0 + 0.08 * float(_sonic_upg["cd"])
func _sonic_freeze() -> float:
	return 0.05 * float(_sonic_upg["cold"])
## Cone half-angle: base + 7.5°/rank (15° per rank full), × AoE bonus.
func _sonic_cone_half() -> float:
	var aoe: float = GameManager.mech_bonus("aoe_pct") if GameManager.has_method("mech_bonus") else 0.0
	return (SONIC_CONE_HALF + deg_to_rad(7.5) * float(_sonic_upg["cone"])) * (1.0 + aoe)

func _tick_sonic(delta: float, enemy_on_screen: bool) -> void:
	# Fire a fresh volley on cooldown; spawn the rest of the volley on a stagger.
	if _sonic_left <= 0:
		_sonic_cd -= delta
		if _sonic_cd <= 0.0 and enemy_on_screen:
			_sonic_cd = SONIC_COOLDOWN * _cd_scale("ultrasonicator") / _rate_mult / _sonic_cd_mult()
			_sonic_left = SONIC_RINGS
			_sonic_queue = 0.0
			if _sonic_capstone == "silence":
				_sonic_clear_bullets()   # Deafening Silence: destroy enemy projectiles each volley
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
		var expand: float = ring.get("expand", SONIC_EXPAND_TIME)
		if age >= expand:
			_sonic_rings.remove_at(i)
			i -= 1
			continue
		var maxr: float = ring["maxr"]
		var r := maxr * (age / expand)
		var center: Vector2 = ring["center"]
		var hit: Array = ring["hit"]
		var aim: float = ring["aim"]
		var cone := _sonic_cone_half()
		var freeze_ch := _sonic_freeze()
		var overload := _sonic_capstone == "overload"
		var silence := _sonic_capstone == "silence"
		var siren := _sonic_capstone == "siren"
		for en in _enemies() + _ruins():
			if not is_instance_valid(en) or en in hit:
				continue
			var off := (en as Node2D).global_position - center
			# Hit only enemies the arc front sweeps AND that lie within the forward cone.
			if absf(off.length() - r) <= SONIC_BAND and absf(wrapf(off.angle() - aim, -PI, PI)) <= cone:
				if en.has_method("take_damage"):
					var sdmg := _sonic_dmg()
					if overload and en.has_method("status_count"):
						sdmg *= 1.0 + 0.20 * float(en.call("status_count"))   # +20% per status
					var rr := _roll_damage(sdmg, "ultrasonicator")
					if en.is_in_group("arena_ruin"):
						en.take_damage(float(rr["dmg"]))   # ruins only implement the 3-arg form
					else:
						en.take_damage(float(rr["dmg"]), 0.0, 1.0 if silence else 0.0, false, false, bool(rr["is_crit"]))
					if bool(rr["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(rr["dmg"]))
					if freeze_ch > 0.0 and en.has_method("apply_freeze") and _proc(freeze_ch):
						en.call("apply_freeze", 1)
					if siren and en.has_method("apply_charm") and not en.is_in_group("boss") and _proc(0.25):
						en.call("apply_charm", 5.0)
				hit.append(en)
		i -= 1

func _spawn_sonic_ring() -> void:
	# Capture the aim direction at spawn so the cone fires where the ship was pointing (a forward fan).
	_sonic_rings.append({"center": (_mz(6) if _has_anchors() else _player.global_position), "aim": _forward().angle(), "age": 0.0, "hit": [], "maxr": _aoe_radius(_sonic_range()), "expand": SONIC_EXPAND_TIME * _duration_mult()})

## Deafening Silence: ask the enemy manager to wipe its projectile pool.
func _sonic_clear_bullets() -> void:
	var mgr := get_tree().get_first_node_in_group("enemy_manager")
	if mgr != null and mgr.has_method("clear_bullets"):
		mgr.call("clear_bullets")

# ── Z-Sword ──────────────────────────────────────────────────────────────────────
func activate_zsword() -> void:
	_zsword_active = true
	_zsword_cd = 0.0

# ── Z-Sword pool: API + effective stats ──
func zsword_grant_upgrade(id: String) -> bool:
	if not ZSWORD_POOL.has(id):
		return false
	var maxr := int(ZSWORD_POOL[id]["max"])
	if maxr > 0 and int(_zsword_upg.get(id, 0)) >= maxr:
		return false
	_zsword_upg[id] = int(_zsword_upg.get(id, 0)) + 1
	if id == "martial" and GameManager.has_method("add_crit_damage"):
		GameManager.add_crit_damage(0.10)   # GLOBAL crit damage (Martial Mastery)
	return true

func _zsword_dmg() -> float:
	return ZSWORD_DAMAGE * (1.0 + 0.10 * float(_zsword_upg["damage"]))
func _zsword_length() -> float:
	return ZSWORD_LENGTH * (1.0 + 0.15 * float(_zsword_upg["size"]))
func _zsword_cd_mult() -> float:
	return 1.0 + 0.08 * float(_zsword_upg["cd"])
func _zsword_crit() -> float:
	return 0.05 * float(_zsword_upg["crit"])
func _zsword_divergence() -> float:
	return 0.05 * float(_zsword_upg["divergence"])
func _zsword_swords() -> int:
	return 2 if _zsword_capstone == "dual" else 1

## True if at least one enemy/ruin sits within the Z-Sword's current reach. `enemy_on_screen` alone only
## means SOME enemy is visible anywhere on screen — far wider than the blade's short melee reach — so
## gating fresh sweeps on it alone let the sword swing uselessly at enemies it could never actually hit.
func _zsword_enemy_in_range() -> bool:
	var reach := _aoe_radius(_zsword_length())
	var center := _player.global_position
	for en in _enemies() + _ruins():
		if not is_instance_valid(en):
			continue
		if ((en as Node2D).global_position - center).length() <= reach:
			return true
	return false

## `reverse` = this is a queued extra swing (Divergence proc, or Dual Wielding's 2nd blade), NOT the first
## swing of a fresh burst: it starts from BEHIND the ship (opposite the normal starting facing) and sweeps
## the opposite rotational way, drawn with the orange ZSlash so it reads as a distinct second sword.
func _start_zsword_sweep(reverse: bool) -> void:
	_zsword_sweeping = true
	_zsword_t = 0.0
	_zsword_is_reverse = reverse
	_zsword_start = _forward().angle() + (PI if reverse else 0.0)
	_zsword_hit = []

## The ZSlash node driving the CURRENT sweep's visuals (blue for the first swing of a burst, orange for
## any queued extra swing).
func _active_zslash() -> Node2D:
	return _zslash_reverse if _zsword_is_reverse else _zslash

func _tick_zsword(delta: float, enemy_on_screen: bool) -> void:
	if not _zsword_sweeping:
		if _zsword_queue > 0:
			_zsword_queue -= 1
			_start_zsword_sweep(true)   # Divergence proc / Dual Wielding's 2nd blade → orange, reversed
		else:
			_zsword_cd -= delta
			if _zsword_cd <= 0.0 and enemy_on_screen and _zsword_enemy_in_range():
				_zsword_cd = ZSWORD_COOLDOWN * _cd_scale("z_sword") / _rate_mult / _zsword_cd_mult()
				_zsword_queue = _zsword_swords()   # Dual Wielding starts 2 swings
				_zsword_queue -= 1
				_start_zsword_sweep(false)   # fresh burst's first swing → normal blue blade
		return
	_zsword_t += delta
	if _zsword_t >= ZSWORD_SWEEP_TIME:
		_zsword_sweeping = false
		_active_zslash().fade_out()
		# Divergence rolls at the end of each swing: each sword may trigger another (full) swing.
		var swords := _zsword_swords()
		for _i in swords:
			if _proc(_zsword_divergence()):
				_zsword_queue += swords
		return
	var dir := -1.0 if _zsword_is_reverse else 1.0
	var blade_ang := _zsword_start + dir * TAU * (_zsword_t / ZSWORD_SWEEP_TIME)
	var reach := _aoe_radius(_zsword_length())
	var center := _player.global_position
	var slash := _active_zslash()
	slash.set_sweep(center, reach, _zsword_start, blade_ang)   # crescent trails the leading edge
	var wiper := _zsword_capstone == "wiper"
	var cauter := _zsword_capstone == "cauterize"
	for en in _enemies() + _ruins():
		if not is_instance_valid(en) or en in _zsword_hit:
			continue
		var off := (en as Node2D).global_position - center
		if off.length() > reach:
			continue
		if absf(wrapf(off.angle() - blade_ang, -PI, PI)) <= ZSWORD_ARC_HALF:
			if en.has_method("take_damage"):
				var r := _roll_damage(_zsword_dmg(), "z_sword")
				var knock := 1.0 if (wiper and not en.is_in_group("boss")) else 0.0
				if en.is_in_group("arena_ruin"):
					en.take_damage(float(r["dmg"]), ZSWORD_STAGGER, knock)   # ruins only implement the 3-arg form
				else:
					en.take_damage(float(r["dmg"]), ZSWORD_STAGGER, knock, false, true, bool(r["is_crit"]))
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
				if cauter and en.has_method("cauterize"):
					en.call("cauterize", 0.20)
				if wiper and not en.is_in_group("boss") and en.has_method("apply_wiper"):
					en.call("apply_wiper")
			slash.add_spark((en as Node2D).global_position)   # impact sparks (tutorial: sparks come last)
			_zsword_hit.append(en)

# ── Ionizing Field ────────────────────────────────────────────────────────────────
func activate_ionize() -> void:
	_ionize_active = true
	_ionize_tick = 0.0
	_ensure_ionize_vfx()

# ── Ionizing Field upgrade API (pool ranks + evolve capstone) ──
func ionize_upgrade_rank(id: String) -> int:
	return int(_ionize_upg.get(id, 0))

func ionize_grant_upgrade(id: String) -> bool:
	if not IONIZE_POOL.has(id):
		return false
	var maxr := int(IONIZE_POOL[id]["max"])
	if maxr > 0 and int(_ionize_upg.get(id, 0)) >= maxr:
		return false
	_ionize_upg[id] = int(_ionize_upg.get(id, 0)) + 1
	if id == "proximity" and GameManager.has_method("add_mech"):
		GameManager.add_mech("proximity_dmg", 0.10)   # GLOBAL: closer targets take more damage (enemy-side)
	return true

func ionize_set_capstone(id: String) -> void:
	_ionize_capstone = id
	if id == "zone_of_war":
		GameManager.upg_max_hp_bonus += IONIZE_WAR_MAXHP
		if GameManager.has_method("recompute_max_hp"):
			GameManager.recompute_max_hp()
	elif id == "zone_of_peace" and GameManager.has_method("add_mech"):
		GameManager.add_mech("zone_of_peace", 1.0)   # GLOBAL enemy debuff: -20% dmg-out, -20% speed, -20% bullet speed

## Field damage per tick (Field Density + Zone evolves).
func _ionize_dmg() -> float:
	var d := IONIZE_DAMAGE * (1.0 + 0.10 * float(_ionize_upg["damage"]))
	if _ionize_capstone == "zone_of_absolution":
		d *= IONIZE_ABSOLUTION_DMG
	elif _ionize_capstone == "zone_of_war":
		d *= 1.0 + IONIZE_WAR_DMG_PER_HP * float(GameManager.ship_max_hp)   # +1% per 10 Max HP
	return d

## Field radius (Event Horizon + Zone of Absolution + global AoE mods).
func _ionize_field_radius() -> float:
	var m := 1.0 + 0.10 * float(_ionize_upg["aoe"])
	if _ionize_capstone == "zone_of_absolution":
		m *= IONIZE_ABSOLUTION_AOE
	return _aoe_radius(IONIZE_RADIUS * m)

## Build the Black Hole visual (2 EnergyVortex swirls + the gravitational lens) once. This used to be
## dead code stranded after _ionize_field_radius()'s return — it never ran, so the vortex/lens never
## existed and _tick_ionize's per-frame follow/resize silently no-op'd on null. Called from activate_ionize().
func _ensure_ionize_vfx() -> void:
	if _ionize_vortex1 == null:
		# Two stacked EnergyVortex swirls (the creep-edit VFX) — outer orange + inner violet.
		# NOTE: EnergyVortex._ready() sets its own z_index, so override z AFTER add_child.
		_ionize_vortex1 = EnergyVortex.new()
		add_child(_ionize_vortex1)
		_ionize_vortex1.z_index = 5
		_ionize_vortex1.modulate.a = IONIZE_GROUP_OPACITY
		_ionize_vortex1.set("draw_halo", false)   # the breathing bloom circles — replaced by the accretion rings
		_ionize_vortex1.call("setup", {
			"radius": 40.0, "spin": 2.2, "arms": 6, "width_mult": IONIZE_VORTEX_WIDTH, "sparkle_mult": 0.5,
			"col_core": Color.html("#f17500"), "col_mid": Color.html("#fde0a1e6"), "col_outer": Color.html("#ff930000")})
		_ionize_vortex2 = EnergyVortex.new()
		add_child(_ionize_vortex2)
		_ionize_vortex2.z_index = 6
		_ionize_vortex2.modulate.a = IONIZE_GROUP_OPACITY
		_ionize_vortex2.set("draw_halo", false)
		_ionize_vortex2.call("setup", {
			"radius": 30.0, "spin": 3.8, "arms": 6, "width_mult": IONIZE_VORTEX_WIDTH, "sparkle_mult": 0.5,
			"col_core": Color.html("#5900fc"), "col_mid": Color.html("#774dffe6"), "col_outer": Color.html("#8c33f200")})
		# Gravitational lens (same screen-warp shader as the Vacuum rift) — distorts the space background.
		var dsh := Shader.new()
		dsh.code = RIFT_DISTORTION_SHADER
		var dmat := ShaderMaterial.new()
		dmat.shader = dsh
		dmat.set_shader_parameter("twist_strength", RIFT_DISTORT_TWIST)
		dmat.set_shader_parameter("twist_falloff", RIFT_DISTORT_FALLOFF)
		dmat.set_shader_parameter("suck_in", RIFT_DISTORT_SUCK)
		dmat.set_shader_parameter("rotation_speed", RIFT_DISTORT_ROT_SPEED)
		dmat.set_shader_parameter("edge_softness", RIFT_DISTORT_EDGE)
		dmat.set_shader_parameter("brightness", IONIZE_LENS_BRIGHTNESS)   # darken (no glare) instead of brighten
		dmat.set_shader_parameter("growth", 1.0)
		_ionize_lens = ColorRect.new()
		_ionize_lens.material = dmat
		_ionize_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ionize_lens.modulate.a = IONIZE_GROUP_OPACITY   # 75% group opacity (RIFT_DISTORTION_SHADER multiplies its output by the node's modulate)
		add_child(_ionize_lens)
		_ionize_lens.z_index = 7   # ABOVE the swirls (5/6) — lenses/distorts the vortex glow too
		# Accretion rings draw on their OWN CanvasItem, above the lens, so the lens's screen-sample
		# darken/warp shader (which would otherwise capture + nearly erase them) never touches them.
		_ionize_ring_layer = Node2D.new()
		add_child(_ionize_ring_layer)
		_ionize_ring_layer.z_index = 8
		_ionize_ring_layer.draw.connect(_draw_ionize_rings)
	_ionize_set_visible(true)

## Show/hide all Black Hole visual nodes together.
func _ionize_set_visible(v: bool) -> void:
	if _ionize_vortex1 != null:    _ionize_vortex1.visible = v
	if _ionize_vortex2 != null:    _ionize_vortex2.visible = v
	if _ionize_lens != null:       _ionize_lens.visible = v
	if _ionize_ring_layer != null: _ionize_ring_layer.visible = v

func _tick_ionize(delta: float) -> void:
	# Glue the swirls + lens onto the ship every frame, scaled to the field's CURRENT AoE radius (Event
	# Horizon rank / Zone of Absolution / global AoE mods) so the visual tracks the actual damage area
	# instead of a fixed size (ratio preserved: lens diameter = half the base field radius).
	if _player != null and is_instance_valid(_player):
		var c := _player.global_position
		var vfx_scale := _ionize_field_radius() / _aoe_radius(IONIZE_RADIUS)   # 1.0 at the un-upgraded radius
		if _ionize_vortex1 != null:
			_ionize_vortex1.position = c
			_ionize_vortex1.scale = Vector2.ONE * IONIZE_VORTEX_SCALE * vfx_scale
		if _ionize_vortex2 != null:
			_ionize_vortex2.position = c
			_ionize_vortex2.scale = Vector2.ONE * IONIZE_VORTEX_SCALE * vfx_scale
		if _ionize_lens != null:
			var diam := IONIZE_LENS_DIAM * vfx_scale
			_ionize_lens.size = Vector2(diam, diam)
			_ionize_lens.position = c - Vector2(diam * 0.5, diam * 0.5)
			var lmat := _ionize_lens.material as ShaderMaterial
			if lmat != null:
				lmat.set_shader_parameter("rect_size", Vector2(diam, diam))
		if _ionize_ring_layer != null:
			_ionize_ring_layer.queue_redraw()   # its own CanvasItem — not covered by this node's queue_redraw()
	# Infalling accretion rings: spawn on a cadence, age them, cull once they've reached the centre.
	_ionize_ring_spawn_t += delta
	while _ionize_ring_spawn_t >= IONIZE_RING_INTERVAL:
		_ionize_ring_spawn_t -= IONIZE_RING_INTERVAL
		_ionize_rings.append({"age": 0.0})
	var ri := _ionize_rings.size() - 1
	while ri >= 0:
		var ring: Dictionary = _ionize_rings[ri]
		ring["age"] = float(ring["age"]) + delta
		if float(ring["age"]) >= IONIZE_RING_LIFE:
			_ionize_rings.remove_at(ri)
		ri -= 1
	_ionize_tick += delta
	var ion_int := IONIZE_TICK / _tick_rate()   # Intensity Mastery → faster ticks
	if _ionize_tick < ion_int:
		return
	_ionize_tick -= ion_int
	if not _enemy_visible:
		return
	var center := _mz(6) if _has_anchors() else _player.global_position   # aura centre = point 6
	var reach := _ionize_field_radius()
	var base_dmg := _ionize_dmg()
	var frz := int(_ionize_upg["freezing"])
	var brn := int(_ionize_upg["burning"])
	var shk := int(_ionize_upg["shocking"])
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		if center.distance_to((en as Node2D).global_position) <= reach:
			if en.has_method("take_damage"):
				var r := _roll_damage(base_dmg, "ionizing_field")
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
			# Field status procs (per tick, ~3.3/s): 1%/rank each, + Stroke of Luck via _proc.
			if frz > 0 and en.has_method("apply_freeze") and _proc(0.01 * float(frz)):
				en.apply_freeze(1)
			if brn > 0 and en.has_method("apply_burn") and _proc(0.01 * float(brn)):
				en.apply_burn(1)
			if shk > 0 and en.has_method("apply_stun") and _proc(0.01 * float(shk)):
				en.apply_stun(IONIZE_STUN_DUR)
	for ruin in _ruins():
		if not is_instance_valid(ruin):
			continue
		var rr: float = reach + (ruin.get("hit_radius") if ruin.get("hit_radius") != null else 0.0)
		if center.distance_to((ruin as Node2D).global_position) <= rr:
			if ruin.has_method("take_damage"):
				ruin.take_damage(base_dmg * _dmg_mult * _lvl_mult("ionizing"))

## Infalling accretion discs: each starts as a filled circle at the field's current AoE radius, eases
## inward toward the ship (accelerating, like gravity), and fades in then out along the way. ~3 discs are
## alive at once (see IONIZE_RING_INTERVAL); their overlap naturally builds up brightness toward the
## centre — that layered overlap IS the glow, so each disc itself is just a flat-alpha filled circle.
func _draw_ionize_rings() -> void:
	if _player == null or not is_instance_valid(_player) or _ionize_ring_layer == null:
		return
	var center := _player.global_position
	var reach := _ionize_field_radius()
	for ring: Dictionary in _ionize_rings:
		var t := clampf(float(ring["age"]) / IONIZE_RING_LIFE, 0.0, 1.0)
		var r := reach * pow(1.0 - t, IONIZE_RING_EASE)
		var a := sin(t * PI) * IONIZE_RING_OPACITY
		if a <= 0.001 or r <= 1.0:
			continue
		_ionize_ring_layer.draw_circle(center, r, Color(IONIZE_RING_COL.r, IONIZE_RING_COL.g, IONIZE_RING_COL.b, a))

# ── Batch-1 draw helpers (this Node2D draws in world space) ─────────────────────────
## Energy-wave VFX: a rippling crest + a trailing wave train fanning into the forward cone. Each crest is a
## soft translucent GLOW (layered widths) whose alpha fades to 0 toward the two cone edges.
const SONIC_GLOW_PASSES := [Vector2(12.0, 0.16), Vector2(6.0, 0.34), Vector2(2.5, 0.95)]
func _draw_sonic_ring(ring: Dictionary) -> void:
	var age := float(ring["age"])
	var expand: float = ring.get("expand", SONIC_EXPAND_TIME)
	var maxr: float = ring["maxr"]
	var r := maxr * (age / expand)
	var a := 1.0 - (age / expand)
	var c: Vector2 = ring["center"]
	var aim: float = ring["aim"]
	var seg := maxi(12, int(SONIC_CONE_HALF / PI * 96.0))
	# Leading crest (bright) + trailing wave train (fainter, smaller radius, phase-shifted ripple).
	_draw_sonic_wave_arc(c, r,        aim, seg, 0.90 * a, age, 0.0)
	_draw_sonic_wave_arc(c, r * 0.86, aim, seg, 0.50 * a, age, 1.3)
	_draw_sonic_wave_arc(c, r * 0.72, aim, seg, 0.30 * a, age, 2.6)

## A single wavy crest across the cone. Radius is sine-rippled (energy wavefront); the alpha tapers to 0 at the
## two cone edges (sin envelope) and is drawn in layered glow passes (wide soft → narrow bright).
func _draw_sonic_wave_arc(c: Vector2, base_r: float, aim: float, seg: int, intensity: float, age: float, phase: float) -> void:
	var col := SONIC_COL
	var pts := PackedVector2Array()
	for i in seg + 1:
		var t := float(i) / float(seg)
		var ang := aim - SONIC_CONE_HALF + t * (2.0 * SONIC_CONE_HALF)
		var ripple := sin(t * TAU * 3.0 + age * 16.0 + phase) * (base_r * 0.05)
		pts.append(c + Vector2(cos(ang), sin(ang)) * (base_r + ripple))
	for pass_def: Vector2 in SONIC_GLOW_PASSES:
		var cols := PackedColorArray()
		for i in seg + 1:
			var t := float(i) / float(seg)
			var edge := sin(clampf(t, 0.0, 1.0) * PI)   # 0 at both cone edges → fade out
			cols.append(Color(col.r, col.g, col.b, intensity * pass_def.y * edge))
		draw_polyline_colors(pts, cols, pass_def.x, true)

# ══ Batch-2 weapons: Boomerang / Parasite Cloud / Moroboshi-M1 / Swarm Host / Space Snake ══════════
## Max turn toward a target angle, capped per call (used by the snake head to minimise turn angle).
func _approach_angle(cur: float, target: float, max_step: float) -> float:
	var diff := wrapf(target - cur, -PI, PI)
	return cur + clampf(diff, -max_step, max_step)

# ── Boomerang ──────────────────────────────────────────────────────────────────────
func activate_boomerang() -> void:
	_boom_active = true

# ── Boomerang upgrade API (pool ranks + evolve capstone) ──
func boom_upgrade_rank(id: String) -> int:
	return int(_boom_upg.get(id, 0))

func boom_grant_upgrade(id: String) -> bool:
	if not BOOM_POOL.has(id):
		return false
	var maxr := int(BOOM_POOL[id]["max"])
	var rk := int(_boom_upg.get(id, 0))
	if maxr > 0 and rk >= maxr:
		return false
	if BOOM_POOL[id].has("gate"):   # Split Blade: rank r requires weapon level ≥ gate[r]
		var gates: Array = BOOM_POOL[id]["gate"]
		if rk < gates.size() and weapon_level("aliwa") < int(gates[rk]):
			return false
	_boom_upg[id] = rk + 1
	if id == "hemorrhage" and GameManager.has_method("add_mech"):
		GameManager.add_mech("bleed_dmg", 0.20)   # GLOBAL: +20% bleed damage per rank
	return true

func boom_set_capstone(id: String) -> void:
	_boom_capstone = id

# ── Boomerang effective stats (pool + capstone) ──
func _boom_dmg() -> float:
	var m := 1.0 + 0.10 * float(_boom_upg["damage"])
	if _boom_capstone == "death_roll":
		m *= 2.0   # Death Roll: +100% damage
	return BOOM_DAMAGE * m
func _boom_speed_mult() -> float:
	var m := 1.0 + 0.10 * float(_boom_upg["speed"])
	if _boom_capstone == "death_roll":
		m *= 0.30   # Death Roll: -70% throw speed
	return m
func _boom_size_mult() -> float:
	return 1.0 + 0.10 * float(_boom_upg["size"])
## Target blade count: base + Nanobots Bodies + Split Blade picks + Chaos evolve.
func _boom_target_count() -> int:
	var n := BOOM_COUNT + _body_count() + int(_boom_upg["count"])
	if _boom_capstone == "chaos":
		n += 3
	return maxi(1, n)

## Spawn the perpetual blade(s) once, phase-offset so multiple blades spread across the rose.
func _spawn_boomerangs() -> void:
	_boom_center = _mz(6) if _has_anchors() else _player.global_position   # pattern centre = point 6
	var n := _boom_target_count()
	for k in n:
		_booms.append({"theta": TAU * float(k) / float(n), "spin": 0.0, "age": 0.0, "pos": _boom_center, "hits": {}})

## Add/remove blades live when the target count changes (Split Blade pick, Chaos evolve, +Bodies aux).
func _boom_resync(target: int) -> void:
	while _booms.size() < target:
		_booms.append({"theta": TAU * float(_booms.size()) / float(maxi(1, target)), "spin": 0.0, "age": 0.0, "pos": _boom_center, "hits": {}})
	while _booms.size() > target:
		_booms.pop_back()

func _tick_boom(delta: float, _enemy_on_screen: bool) -> void:
	if not _boom_init:
		_spawn_boomerangs()
		_boom_init = true
	var target := _boom_target_count()
	if _booms.size() != target:
		_boom_resync(target)
	# The pattern centre trails the ship → flying drags the flower behind you.
	_boom_center = _boom_center.lerp(_mz(6) if _has_anchors() else _player.global_position, clampf(BOOM_CENTER_LAG * delta, 0.0, 1.0))
	var death_roll := _boom_capstone == "death_roll"
	var hit_r := BOOM_HIT_RADIUS * _boom_size_mult()
	var bleed_rank := int(_boom_upg["bleed"])
	for b: Dictionary in _booms:
		b["spin"] = float(b["spin"]) + BOOM_SPIN * delta
		var prev_age := float(b["age"])
		b["age"] = prev_age + delta
		b["theta"] = float(b["theta"]) + BOOM_ROSE_SPEED * _weapon_speed_mult() * _boom_speed_mult() * delta
		var th := float(b["theta"])
		# 3-petal rose: r = SIZE·cos(3θ). Negative r flips to the opposite side → the blade loops out into a
		# petal, back through the centre, out the next petal, tracing the trinity/triquetra flower forever.
		var rr := BOOM_SIZE * cos(3.0 * th)
		var pos := _boom_center + Vector2(cos(th), sin(th)) * rr
		# Death Roll: the slow blade can lag behind a fleeing ship — snap the whole pattern back if it strays.
		if death_roll and pos.distance_to(_player.global_position) > BOOM_SIZE * 1.6:
			_boom_center = _player.global_position
			pos = _boom_center + Vector2(cos(th), sin(th)) * rr
		b["pos"] = pos
		var hits: Dictionary = b["hits"]
		for en in _enemies() + _ruins():
			if not is_instance_valid(en):
				continue
			var en2 := en as Node2D
			var enr: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
			if pos.distance_to(en2.global_position) <= hit_r + enr:
				var eid := en.get_instance_id()
				if float(b["age"]) - float(hits.get(eid, -999.0)) >= BOOM_HIT_CD:
					hits[eid] = float(b["age"])
					if en.has_method("take_damage"):
						var r := _roll_damage(_boom_dmg(), "aliwa")
						if en.is_in_group("arena_ruin"):
							en.take_damage(float(r["dmg"]))   # ruins only implement the 3-arg form
						else:
							en.take_damage(float(r["dmg"]), 0.0, 0.0, false, true, bool(r["is_crit"]))
						if bool(r["is_crit"]):
							_spawn_crit_number(en2.global_position, float(r["dmg"]))
					# Laceration: 2 guaranteed bleed stacks per rank.
					if bleed_rank > 0 and en.has_method("apply_bleed"):
						en.apply_bleed(2 * bleed_rank)
					# Bleed! evolve: an extra 10% of the target's max bleed stacks per hit.
					if _boom_capstone == "bleed_more" and en.has_method("apply_bleed") and en.has_method("bleed_max"):
						en.apply_bleed(maxi(1, int(ceil(0.10 * float(en.bleed_max())))))
					# Death Roll: drag the enemy toward the blade (non-boss only).
					if death_roll and not en2.is_in_group("boss"):
						en2.global_position = en2.global_position.move_toward(pos, DEATHROLL_PULL)
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

# ── Parasite upgrade API (pool ranks + evolve capstone) ──
func para_upgrade_rank(id: String) -> int:
	return int(_para_upg.get(id, 0))

func para_grant_upgrade(id: String) -> bool:
	if not PARA_POOL.has(id):
		return false
	var maxr := int(PARA_POOL[id]["max"])
	if maxr > 0 and int(_para_upg.get(id, 0)) >= maxr:
		return false
	_para_upg[id] = int(_para_upg.get(id, 0)) + 1
	if id == "armor_mastery" and GameManager.has_method("add_mech"):
		GameManager.add_mech("armor_floor", 10.0)   # GLOBAL: lets stripped armor go 10 further negative per rank
	return true

func para_set_capstone(id: String) -> void:
	_para_capstone = id
	if id == "strip_naked" and GameManager.has_method("add_mech"):
		GameManager.add_mech("armor_floor", 50.0)   # +50 to the max armor reduction (floor further negative)

# ── Parasite effective stats (pool ranks) ──
func _para_dmg() -> float:
	return PARA_DAMAGE * (1.0 + 0.10 * float(_para_upg["damage"]))
func _para_radius() -> float:
	return _aoe_radius(PARA_RADIUS * (1.0 + 0.10 * float(_para_upg["aoe"])))
func _para_lifetime() -> float:
	return PARA_LIFETIME * (1.0 + 0.20 * float(_para_upg["duration"]))

func _tick_para(delta: float, enemy_on_screen: bool) -> void:
	var auto := _para_capstone == "full_automation"
	var reach := _para_radius()
	var life := _para_lifetime()
	if auto:
		# Full Automation: one persistent free-floating cloud that hunts the densest enemy cluster (150 px/s).
		if _para_clouds.is_empty():
			_para_clouds.append({"pos": _muzzle(), "vel": Vector2.ZERO, "age": 0.0, "tick": 0.0,
					"ang": 0.0, "plume": _make_para_cloud_plume(), "auto": true})
	else:
		_para_cd -= delta
		if _para_cd <= 0.0 and enemy_on_screen:
			_para_cd = PARA_COOLDOWN * _cd_scale("venomancer") / _rate_mult / _automation_rate("venomancer")
			var dir := _forward()
			var tgt := _nearest_enemy(_player.global_position, INF, [])
			if tgt != null:
				dir = ((tgt as Node2D).global_position - _muzzle()).normalized()
			_para_clouds.append({"pos": _muzzle(), "vel": dir * PARA_SPEED * _weapon_speed_mult(), "age": 0.0, "tick": 0.0,
					"ang": dir.angle(), "plume": _make_para_cloud_plume(), "auto": false})
	var me_rank := int(_para_upg["metal_eater"])
	var i := _para_clouds.size() - 1
	while i >= 0:
		var c: Dictionary = _para_clouds[i]
		var is_auto: bool = bool(c.get("auto", false))
		c["age"] = float(c["age"]) + delta
		if not is_auto and float(c["age"]) >= life:
			var _pa0: Node2D = c.get("plume")
			if _pa0 != null and is_instance_valid(_pa0):
				_pa0.queue_free()
			var _gp: Vector2 = c["pos"]
			_para_gas_puffs.append({"pos": _gp, "age": 0.0, "max_age": PARA_GAS_LIFETIME})
			for _gi in 6:
				var _ga := TAU * float(_gi) / 6.0
				_para_gas_puffs.append({"pos": _gp + Vector2(cos(_ga), sin(_ga)) * reach * 0.55,
						"age": 0.0, "max_age": PARA_GAS_LIFETIME})
			_para_clouds.remove_at(i)
			i -= 1
			continue
		if is_auto:
			var target := _para_best_target((c["pos"] as Vector2), reach)
			var to := target - (c["pos"] as Vector2)
			var desired := (to.normalized() * PARA_AUTO_SPEED) if to.length() > 4.0 else Vector2.ZERO
			c["vel"] = (c["vel"] as Vector2).lerp(desired, clampf(3.0 * delta, 0.0, 1.0))
		else:
			c["vel"] = (c["vel"] as Vector2).lerp(Vector2.ZERO, clampf(PARA_DRAG * delta, 0.0, 1.0))
		c["pos"] = (c["pos"] as Vector2) + (c["vel"] as Vector2) * delta
		var _vel: Vector2 = c["vel"]
		if _vel.length_squared() > 1.0:
			c["ang"] = _vel.angle()
		var _pa: Node2D = c.get("plume")
		if _pa != null and is_instance_valid(_pa):
			_pa.global_position = c["pos"]
			_pa.rotation = float(c["ang"])
		c["tick"] = float(c["tick"]) + delta
		var para_int := PARA_TICK / _tick_rate()   # Intensity Mastery → faster ticks
		while float(c["tick"]) >= para_int:
			c["tick"] = float(c["tick"]) - para_int
			var cp: Vector2 = c["pos"]
			for en in _enemies() + _ruins():
				if not is_instance_valid(en):
					continue
				if cp.distance_to((en as Node2D).global_position) <= reach:
					if en.has_method("take_damage"):
						var r := _roll_damage(_para_dmg(), "venomancer")
						en.take_damage(float(r["dmg"]), 0.0)
					if me_rank > 0 and en.has_method("apply_corrode"):
						# Ramp -1×rank armor/sec (add = rate × tick dt), capped at -5×rank, lingering 5s.
						en.apply_corrode(PARA_METAL_EATER_PER_RANK * float(me_rank) * para_int,
								PARA_METAL_EATER_PER_RANK * 5.0 * float(me_rank), PARA_METAL_EATER_DUR)
		i -= 1
	_update_stolen_fortitude(delta)

## Steer target for Full Automation: the enemy whose neighbourhood (within `reach`) holds the most enemies —
## i.e. park the cloud over the densest cluster to maximise the number affected. Falls back to hovering in place.
func _para_best_target(from: Vector2, reach: float) -> Vector2:
	var list := _enemies()
	var best := from
	var best_n := -1
	for en in list:
		if not is_instance_valid(en):
			continue
		var ep: Vector2 = (en as Node2D).global_position
		var n := 0
		for other in list:
			if is_instance_valid(other) and ep.distance_to((other as Node2D).global_position) <= reach:
				n += 1
		if n > best_n:
			best_n = n
			best = ep
	return best

## Stolen Fortitude: gain armor from a share of the SINGLE most-corroded enemy; the bonus lingers 5s after that
## enemy's reduction is gone, then falls to the current value. Fed to GameManager.total_armor() per frame.
func _update_stolen_fortitude(delta: float) -> void:
	var rank := int(_para_upg["stolen_fortitude"])
	if rank <= 0:
		if _stolen_armor != 0.0:
			_stolen_armor = 0.0
			if GameManager.has_method("set_stolen_armor"):
				GameManager.set_stolen_armor(0.0)
		return
	var pct := PARA_STOLEN_PER_RANK * float(rank)
	if _para_capstone == "perfect_reconstruction":
		pct *= (1.0 + PARA_RECON_BONUS)
	var top := 0.0
	for en in _enemies():
		if is_instance_valid(en) and en.has_method("armor_reduction_total"):
			top = maxf(top, float(en.armor_reduction_total()))
	var desired := top * pct
	if desired >= _stolen_armor:
		_stolen_armor = desired
		_stolen_armor_t = PARA_STOLEN_LINGER
	else:
		_stolen_armor_t -= delta
		if _stolen_armor_t <= 0.0:
			_stolen_armor = desired
	if GameManager.has_method("set_stolen_armor"):
		GameManager.set_stolen_armor(_stolen_armor)

func _update_para_gas_fx(delta: float) -> void:
	var idx := _para_gas_puffs.size() - 1
	while idx >= 0:
		var puff: Dictionary = _para_gas_puffs[idx]
		puff["age"] = float(puff["age"]) + delta
		if float(puff["age"]) >= float(puff["max_age"]):
			_para_gas_puffs.remove_at(idx)
		idx -= 1
	if _para_gas_puffs.is_empty():
		if _para_gas_fx != null and is_instance_valid(_para_gas_fx):
			_para_gas_fx.visible = false
		return
	if _para_gas_fx == null or not is_instance_valid(_para_gas_fx):
		_para_gas_fx = DynamicFire.new()
		_para_gas_fx.free_form         = true
		_para_gas_fx.z_index           = 6
		_para_gas_fx.color_start       = Color(0.45, 0.88, 0.28)
		_para_gas_fx.color_mid         = Color(0.32, 0.52, 0.18)
		_para_gas_fx.color_end         = Color(0.28, 0.12, 0.38)
		_para_gas_fx.intensity         = 0.15
		_para_gas_fx.particle_amount   = 200
		_para_gas_fx.particle_size_min = 60.0
		_para_gas_fx.particle_size_max = 130.0
		_para_gas_fx.velocity_min      = 8.0
		_para_gas_fx.velocity_max      = 28.0
		_para_gas_fx.particle_lifetime = 1.0
		add_child(_para_gas_fx)
	_para_gas_fx.visible = true
	var center := _player.global_position
	_para_gas_fx.global_position = center
	var pts: Array = []
	for puff: Dictionary in _para_gas_puffs:
		pts.append((puff["pos"] as Vector2) - center)
	_para_gas_fx.set_points(pts)

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
	var prev_pos := _moro_pos
	_moro_pos = _moro_pos.move_toward(dest, MORO_MOVE_SPEED * _weapon_speed_mult() * delta)
	var _moro_dp := _moro_pos - center
	if _moro_dp.length() > 1000.0:
		_moro_pos = center + _moro_dp.normalized() * 1000.0
	if _moro_pos.distance_squared_to(prev_pos) > 0.01:
		var _moro_desired := (dest - prev_pos).angle()
		var _moro_diff := angle_difference(_moro_facing, _moro_desired)
		_moro_facing += clampf(_moro_diff, -YARI_TURN_RATE * delta, YARI_TURN_RATE * delta)
	_moro_cd -= delta
	_moro_punch_t = maxf(0.0, _moro_punch_t - delta)
	if tgt != null and _moro_cd <= 0.0:
		var tp := (tgt as Node2D).global_position
		if _moro_pos.distance_to(tp) <= MORO_ATTACK_RANGE:
			_moro_cd = MORO_ATTACK_CD * _cd_scale("yari") / _rate_mult / _automation_rate("yari")
			_moro_punch_t = 0.18
			_moro_punch_pos = tp
			var reach := _aoe_radius(MORO_AOE)
			for en in _enemies() + _ruins():
				if not is_instance_valid(en):
					continue
				if tp.distance_to((en as Node2D).global_position) <= reach:
					if en.has_method("take_damage"):
						var r := _roll_damage(MORO_DAMAGE, "yari")
						if en.is_in_group("arena_ruin"):
							en.take_damage(float(r["dmg"]), MORO_STAGGER)   # ruins only implement the 3-arg form
						else:
							en.take_damage(float(r["dmg"]), MORO_STAGGER, 0.0, false, true, bool(r["is_crit"]))
						if bool(r["is_crit"]):
							_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))

# ── Yari Jaeger (homing blade familiar — arc slash on contact) ─────────────────────
func activate_yari() -> void:
	_yari_active = true
	_yari_cd = 0.0

func _load_yari_frames() -> void:
	# GifLoader: tries sheet.png+sheet.json first (fast), falls back to LZW decode + auto-converts for next run.
	var tex := GifLoader.load_gif("res://assets/weaponry/Yari-Jeager.gif")
	if tex == null:
		return
	_yari_frames.clear()
	if tex.has_meta("gif_frames"):
		for f: Texture2D in (tex.get_meta("gif_frames") as Array):
			_yari_frames.append(f)
	else:
		_yari_frames.append(tex)   # single-frame GIF

func _load_moro_frames() -> void:
	var tex := GifLoader.load_gif("res://assets/weaponry/Yari.gif")
	if tex == null:
		return
	_moro_frames.clear()
	if tex.has_meta("gif_frames"):
		for f: Texture2D in (tex.get_meta("gif_frames") as Array):
			_moro_frames.append(f)
	else:
		_moro_frames.append(tex)

func _load_swarm_tex() -> void:
	_swarmball_tex = _load_sball_tex(SBALL_SPRITE)
	_swarmbot_tex  = _load_sball_tex(SBALL_BOT_SPRITE)
	_swarm_tex = _swarmball_tex   # plume-sizing reference

func _load_sball_tex(res_path: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)

func _load_para_tex() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(PARA_SPRITE))
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	_para_tex = ImageTexture.create_from_image(img)

func _load_para_plume_data() -> void:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	var cfg := ConfigFile.new()
	if cfg.load("res://weapon_layout.cfg") != OK:
		return
	var eo: Dictionary = cfg.get_value("creeps", "BC-SL-Spore", {})
	if eo.is_empty():
		return
	var eo_pos:  Vector2 = eo.get("pos",  Vector2(480.0, 380.0))
	var eo_size: Vector2 = eo.get("size", Vector2(60.0, 68.7))
	var tps: Array = cfg.get_value("thrustpoints", "BC-SL-Spore", [])
	if tps.is_empty():
		return
	var scfg := ConfigFile.new()
	var all_styles: Dictionary = {}
	if scfg.load("res://weapon_plume_styles.cfg") == OK:
		all_styles = scfg.get_value("styles", "BC-SL-Spore", {})
	var pw := PARA_DRAW
	var ph := pw
	if _para_tex != null:
		ph = pw * float(_para_tex.get_height()) / maxf(float(_para_tex.get_width()), 1.0)
	var fracs: Array = []
	for tp: Dictionary in tps:
		var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (tp_oc - eo_pos) / eo_size
		var tp_id: int = int(tp.get("id", 1))
		fracs.append({"frac": frac, "dir_angle": float(tp.get("dir_angle", PI * 0.5)),
				"style": all_styles.get("tp_%d" % tp_id, {})})
	_para_plume_data = {"fracs": fracs, "ds": Vector2(pw, ph)}

func _make_para_cloud_plume() -> Node2D:
	var anchor := Node2D.new()
	add_child(anchor)
	if _para_plume_data.is_empty():
		return anchor
	var ds: Vector2 = _para_plume_data.get("ds", Vector2(PARA_DRAW, PARA_DRAW))
	for fd: Dictionary in (_para_plume_data.get("fracs", []) as Array):
		var p := _make_orbital_plume(fd["frac"] as Vector2, float(fd["dir_angle"]),
				fd["style"] as Dictionary, ds)
		p.z_index = -1
		anchor.add_child(p)
	return anchor

func _tick_yari(delta: float) -> void:
	if not _yari_init:
		_yari_pos = _player.global_position
		_yari_init = true
	_yari_cd -= delta
	if not _yari_sweeping:
		_yari_frame_idx = 0
		_yari_frame_acc = 0.0
		var center := _player.global_position
		var tgt := _nearest_enemy(_yari_pos, YARI_AGGRO, [])
		var dest: Vector2
		if tgt != null:
			dest = (tgt as Node2D).global_position
		else:
			# Advance orbit point and chase it — Yari spirals naturally into the orbit circle.
			_yari_orbit_ang += YARI_ORBIT_SPEED * _weapon_speed_mult() * delta
			dest = center + Vector2(cos(_yari_orbit_ang), sin(_yari_orbit_ang)) * YARI_ORBIT_R
		# Only fly toward enemy; stop when within attack range
		var old_pos := _yari_pos
		if tgt == null or _yari_pos.distance_to((tgt as Node2D).global_position) > YARI_ATTACK_RANGE:
			_yari_pos = _yari_pos.move_toward(dest, YARI_MOVE_SPEED * _weapon_speed_mult() * delta)
		var _yari_dp := _yari_pos - center
		if _yari_dp.length() > 1000.0:
			_yari_pos = center + _yari_dp.normalized() * 1000.0
		# Facing: rotate toward desired direction at YARI_TURN_RATE (120 RPM) — no instant snap.
		var desired_facing: float
		if _yari_pos.distance_to(old_pos) > 0.5:
			desired_facing = (_yari_pos - old_pos).angle()
		elif tgt != null:
			desired_facing = ((tgt as Node2D).global_position - _yari_pos).angle()
		else:
			desired_facing = _yari_facing
		var diff := wrapf(desired_facing - _yari_facing, -PI, PI)
		_yari_facing += clampf(diff, -YARI_TURN_RATE * delta, YARI_TURN_RATE * delta)
		if tgt != null and _yari_cd <= 0.0 and _yari_pos.distance_to((tgt as Node2D).global_position) <= YARI_ATTACK_RANGE:
			_yari_cd = YARI_ATTACK_CD / _rate_mult / _automation_rate("yari_jaeger") / _fam_rate("yari_jaeger")
			_yari_sweeping = true
			_yari_sweep_t = 0.0
			# CCW sweep: start +90° ahead of target direction, blade_ang decreases each frame
			_yari_facing = ((tgt as Node2D).global_position - _yari_pos).angle()
			_yari_sweep_start = _yari_facing + PI * 0.5
			_yari_hit = []
	else:
		_yari_sweep_t += delta
		# Advance GIF frame
		_yari_frame_acc += delta
		if _yari_frame_acc >= YARI_FRAME_DELAY and not _yari_frames.is_empty():
			_yari_frame_acc -= YARI_FRAME_DELAY
			_yari_frame_idx = mini(_yari_frame_idx + 1, _yari_frames.size() - 1)
		if _yari_sweep_t >= YARI_SWEEP_TIME:
			_yari_sweeping = false
			if _yari_slash != null:
				_yari_slash.fade_out()
			# Sync orbit angle to current bearing so idle orbit continues smoothly.
			_yari_orbit_ang = (_yari_pos - _player.global_position).angle()
			queue_redraw()
			return
		# CCW: blade_ang decreases. ZSlash requires lead > start (swept>0), so pass:
		#   lead = blade_ang, start = blade_ang - swept_so_far
		# → swept = TAU*t_frac > 0; ZSlash clamps to its internal SPAN.
		var t_frac  := _yari_sweep_t / YARI_SWEEP_TIME
		var blade_ang := _yari_sweep_start - TAU * t_frac
		var reach := _aoe_radius(YARI_LENGTH)
		if _yari_slash != null:
			_yari_slash.set_sweep(_yari_pos, reach, blade_ang - TAU * t_frac, blade_ang)
		for en in _enemies() + _ruins():
			if not is_instance_valid(en) or en in _yari_hit:
				continue
			var off := (en as Node2D).global_position - _yari_pos
			if off.length() <= reach and absf(wrapf(off.angle() - blade_ang, -PI, PI)) <= YARI_ARC_HALF:
				if en.has_method("take_damage"):
					var r := _roll_damage(YARI_DAMAGE, "yari_jaeger")
					if en.is_in_group("arena_ruin"):
						en.take_damage(float(r["dmg"]), YARI_STAGGER)   # ruins only implement the 3-arg form
					else:
						en.take_damage(float(r["dmg"]), YARI_STAGGER, 0.0, false, true, bool(r["is_crit"]))
					if bool(r["is_crit"]):
						_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
				if _yari_slash != null:
					_yari_slash.add_spark((en as Node2D).global_position)
				_yari_hit.append(en)
	queue_redraw()

# ── Swarm (Chakra) — volley of swarmballs: launch out → loiter (chip dmg) → lock + ram as a swarmbot → explode.
# A fresh volley of SBALL_COUNT balls fires every SBALL_COOLDOWN on a fixed cadence, regardless of whether the
# previous volley's balls are still in flight. Dart evolve adds a return-to-ship leg that heals on arrival
# (the old dart+heal familiar mechanic lives on unchanged in the Vampire Host fusion, which has its own
# separate _vampire_units loop — untouched by this). ──
func activate_swarm() -> void:
	_swarm_active = true
	_swarm_cd = 0.0          # fire the first volley as soon as the player exists
	_swarm_units.clear()

## Fire one ring of SBALL_COUNT balls outward in evenly-spaced directions from the player.
func _launch_swarm_volley() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var origin := _player.global_position
	for k in SBALL_COUNT:
		var dir := Vector2.RIGHT.rotated(TAU * float(k) / float(SBALL_COUNT))
		# off = offset from the player; while loitering the ball is ANCHORED to the player (pos = player + off),
		# so the whole ring drifts with the ship exactly like the old idle-orbit familiars did.
		_swarm_units.append({
			"pos": origin, "off": Vector2.ZERO, "dir": dir, "state": "loiter",
			"t": 0.0, "life": 0.0, "target": null, "bot": false, "ang": dir.angle(), "chip_cd": 0.0, "dmg": 0.0,
			"anchor_dynamic": true, "anchor_pos": Vector2.ZERO, "last_target_pos": Vector2.ZERO,
		})

func _tick_swarm(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center := _player.global_position
	# Fixed-cadence volley launcher (NOT a replenish-on-consume pool): every SBALL_COOLDOWN a fresh batch of
	# SBALL_COUNT balls launches, independent of whatever earlier balls are still doing.
	_swarm_cd -= delta
	if _swarm_cd <= 0.0:
		_swarm_cd += SBALL_COOLDOWN * _cd_scale("swarm") / _rate_mult
		_launch_swarm_volley()
	var chg_sp := SBALL_CHARGE_SPEED * _automation_rate("swarm") * _weapon_speed_mult()
	var ret_sp := SWARM_SPEED * _automation_rate("swarm") * _weapon_speed_mult()
	var i := _swarm_units.size() - 1
	while i >= 0:
		var u: Dictionary = _swarm_units[i]
		u["life"] = float(u["life"]) + delta
		u["t"] = float(u["t"]) + delta
		u["chip_cd"] = maxf(0.0, float(u["chip_cd"]) - delta)
		var pos: Vector2 = u["pos"]
		var remove := false
		match String(u["state"]):
			"loiter":
				# Anchor is the player WHILE this ball has never lost a target; once a target dies on it
				# (see "seek_last" below), the anchor becomes fixed at the point it arrived at, and stays
				# fixed for the rest of this ball's life — it no longer drifts along with the ship.
				var anchor: Vector2 = center if bool(u.get("anchor_dynamic", true)) else Vector2(u["anchor_pos"])
				# Radius eases toward SBALL_LAUNCH_RADIUS (0 → ring on the initial launch-out; already 0 when
				# starting a fixed-anchor loiter after "seek_last") while spinning tangentially to hunt.
				var off: Vector2 = u["off"]
				var radius := off.length()
				var orbit_ang := (off.angle() if radius > 1.0 else (u["dir"] as Vector2).angle())
				var new_radius := move_toward(radius, SBALL_LAUNCH_RADIUS, SBALL_LAUNCH_SPEED * delta)
				orbit_ang += (SBALL_LOITER_SPEED / maxf(new_radius, 1.0)) * delta
				off = Vector2.RIGHT.rotated(orbit_ang) * new_radius
				u["off"] = off
				pos = anchor + off
				u["ang"] = float(u["ang"]) + SBALL_SPIN_RAD * delta   # visual self-spin (Swarmball form)
				# Chip damage on contact while loitering — the ball is NOT consumed.
				if float(u["chip_cd"]) <= 0.0:
					for en in _enemies() + _ruins():
						if not is_instance_valid(en):
							continue
						var er: float = float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0
						if pos.distance_to((en as Node2D).global_position) <= SBALL_HIT_R + er:
							if en.has_method("take_damage"):
								var r := _roll_damage(SBALL_DAMAGE, "swarm")
								if en.is_in_group("arena_ruin"):
									en.take_damage(float(r["dmg"]))   # ruins only implement the 3-arg form
								else:
									en.take_damage(float(r["dmg"]), 0.0, 0.0, false, true, bool(r["is_crit"]))
								if bool(r["is_crit"]):
									_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
							u["chip_cd"] = SBALL_LOITER_HIT_CD
							break
				# Lock the nearest target once the minimum loiter time has passed.
				if float(u["t"]) >= SBALL_LOITER_TIME:
					var tgt := _nearest_enemy(pos, SWARM_AGGRO, [])
					if tgt != null:
						u["target"] = tgt
						u["state"] = "charge"
						u["t"] = 0.0
			"charge":
				var t = u["target"]
				if t == null or not is_instance_valid(t):
					# Target died before impact — keep flying to where it last was, THEN loiter there (fixed
					# anchor, no snap back to the ship/launch ring). last_target_pos is cached fresh every
					# frame below while the target was still alive, so it's the target's death spot.
					u["state"] = "seek_last"
					u["bot"] = false
				else:
					var tp := (t as Node2D).global_position
					u["last_target_pos"] = tp
					pos = pos.move_toward(tp, chg_sp * delta)
					var dist := pos.distance_to(tp)
					if dist > 0.5:
						u["ang"] = (tp - pos).angle()
					if not bool(u["bot"]) and dist <= SBALL_ARM_DIST:
						u["bot"] = true   # arm: swap to the Swarmbot sprite for the final approach
					var tr: float = float(t.get("hit_radius")) if t.get("hit_radius") != null else 0.0
					if dist <= SBALL_HIT_R + tr:
						var dmg_dealt := 0.0
						if t.has_method("take_damage"):
							var r := _roll_damage(SBALL_DAMAGE, "swarm")
							dmg_dealt = float(r["dmg"])
							if t.is_in_group("arena_ruin"):
								t.take_damage(dmg_dealt)   # ruins only implement the 3-arg form
							else:
								t.take_damage(dmg_dealt, 0.0, 0.0, false, true, bool(r["is_crit"]))
							if bool(r["is_crit"]):
								_spawn_crit_number(tp, dmg_dealt)
						var fx := DeathFX.new()
						add_child(fx)
						fx.setup(tp, SBALL_EXPLODE_SIZE)
						if _swarm_capstone == "dart":
							u["state"] = "return"
							u["target"] = null
							u["dmg"] = dmg_dealt
							u["t"] = 0.0
							u["bot"] = false
						else:
							remove = true
			"seek_last":
				# Coasting to the dead target's last known position — no retargeting mid-flight.
				var dest: Vector2 = u["last_target_pos"]
				pos = pos.move_toward(dest, chg_sp * delta)
				var dleft := pos.distance_to(dest)
				if dleft > 0.5:
					u["ang"] = (dest - pos).angle()
				if dleft <= 4.0:
					u["anchor_dynamic"] = false
					u["anchor_pos"] = pos
					u["off"] = Vector2.ZERO
					u["state"] = "loiter"
					u["t"] = 0.0
			"return":
				pos = pos.move_toward(center, ret_sp * delta)
				var dist_home := pos.distance_to(center)
				if dist_home > 0.5:
					u["ang"] = (center - pos).angle()
				if dist_home <= SWARM_IDLE_R + 8.0:
					if float(u["dmg"]) > 0.0 and GameManager.has_method("heal"):
						GameManager.heal(int(round(float(u["dmg"]) * SWARM_HEAL_FRAC)))
					remove = true
		if not remove and float(u["life"]) >= SBALL_MAX_LIFE:
			remove = true   # backstop: a ball that never connects self-destructs
		if remove:
			_swarm_units.remove_at(i)
		else:
			u["pos"] = pos
			_swarm_units[i] = u
		i -= 1

# ── Space Snake (segmented fire familiar) ───────────────────────────────────────────
func activate_snake() -> void:
	_snake_active = true

func _load_snake_tex() -> void:
	var load_img := func(res_path: String) -> Texture2D:
		var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
		return ImageTexture.create_from_image(img) if img != null else null
	_snake_head_top_tex = load_img.call("res://assets/weaponry/VIPER head top.png")
	_snake_body_tex     = load_img.call("res://assets/weaponry/VIPER body.png")
	_snake_tail_tex      = load_img.call("res://assets/weaponry/VIPER Tail.png")
	_load_snake_plume()

func _load_snake_plume() -> void:
	const SCREEN_ORIGIN := Vector2(15.0, 8.0)
	const SEG_PX        := 44.0
	var cfg := ConfigFile.new()
	if cfg.load("res://weapon_layout.cfg") != OK:
		return
	var scfg := ConfigFile.new()
	scfg.load("res://weapon_plume_styles.cfg")

	# --- Head ---
	if _snake_head_top_tex != null:
		var eh: Dictionary  = cfg.get_value("creeps",       "VIPER head top", {})
		var head_tps: Array = cfg.get_value("thrustpoints", "VIPER head top", [])
		if not eh.is_empty() and not head_tps.is_empty():
			var eh_pos:  Vector2 = eh.get("pos",  Vector2(480.0, 380.0))
			var eh_size: Vector2 = eh.get("size", Vector2(60.0,  101.5))
			var styles: Dictionary = scfg.get_value("styles", "VIPER head top", {})
			var htw := float(_snake_head_top_tex.get_width())
			var hth := float(_snake_head_top_tex.get_height())
			var ds := Vector2(SEG_PX * htw / maxf(hth, 1.0), SEG_PX)
			_snake_head_plume_anchor = Node2D.new()
			_snake_head_plume_anchor.visible = false
			add_child(_snake_head_plume_anchor)
			for tp: Dictionary in head_tps:
				var tp_oc := (tp["pos"] as Vector2) + SCREEN_ORIGIN
				var frac  := (tp_oc - eh_pos) / eh_size
				var style: Dictionary = styles.get("tp_%d" % int(tp.get("id", 1)), {})
				var p := _make_orbital_plume(frac, float(tp.get("dir_angle", -PI * 0.5)), style, ds)
				p.z_index = -1   # below the sprite drawn by the parent node's _draw()
				_snake_head_plume_anchor.add_child(p)

	# --- Tail ---
	if _snake_tail_tex != null:
		var et: Dictionary  = cfg.get_value("creeps",       "VIPER Tail", {})
		var tail_tps: Array = cfg.get_value("thrustpoints", "VIPER Tail", [])
		if not et.is_empty() and not tail_tps.is_empty():
			var et_pos:  Vector2 = et.get("pos",  Vector2(480.0, 380.0))
			var et_size: Vector2 = et.get("size", Vector2(60.0,  59.5))
			var styles: Dictionary = scfg.get_value("styles", "VIPER Tail", {})
			var ttw := float(_snake_tail_tex.get_width())
			var tth := float(_snake_tail_tex.get_height())
			var ds := Vector2(SEG_PX * ttw / maxf(tth, 1.0), SEG_PX)
			_snake_tail_plume_anchor = Node2D.new()
			_snake_tail_plume_anchor.visible = false
			add_child(_snake_tail_plume_anchor)
			for tp: Dictionary in tail_tps:
				var tp_oc := (tp["pos"] as Vector2) + SCREEN_ORIGIN
				var frac  := (tp_oc - et_pos) / et_size
				var style: Dictionary = styles.get("tp_%d" % int(tp.get("id", 1)), {})
				var p := _make_orbital_plume(frac, float(tp.get("dir_angle", PI * 0.5)), style, ds)
				p.z_index = -1   # below the sprite drawn by the parent node's _draw()
				_snake_tail_plume_anchor.add_child(p)

	# --- Body (one anchor per segment, k = 1..SNAKE_SEGMENTS-2) ---
	if _snake_body_tex != null:
		var eb: Dictionary  = cfg.get_value("creeps",       "VIPER body", {})
		var body_tps: Array = cfg.get_value("thrustpoints", "VIPER body", [])
		if not eb.is_empty() and not body_tps.is_empty():
			var eb_pos:  Vector2 = eb.get("pos",  Vector2(480.0, 380.0))
			var eb_size: Vector2 = eb.get("size", Vector2(60.0,  50.0))
			var styles: Dictionary = scfg.get_value("styles", "VIPER body", {})
			const BODY_SEG_PX := 25.2
			var btw := float(_snake_body_tex.get_width())
			var bth := float(_snake_body_tex.get_height())
			# Body is landscape: travel = dw (local +x), cross-section = dh (local +y).
			# Anchor rotation = ang with no +PI/2, matching draw_set_transform in _draw_snake_seg.
			var ds := Vector2(BODY_SEG_PX, BODY_SEG_PX * bth / maxf(btw, 1.0))
			for _k in range(SNAKE_SEGMENTS - 2):
				var anchor := Node2D.new()
				anchor.visible = false
				add_child(anchor)
				_snake_body_plume_anchors.append(anchor)
				for tp: Dictionary in body_tps:
					var tp_oc := (tp["pos"] as Vector2) + SCREEN_ORIGIN
					var frac  := (tp_oc - eb_pos) / eb_size
					var style: Dictionary = styles.get("tp_%d" % int(tp.get("id", 1)), {})
					var p := _make_orbital_plume(frac, float(tp.get("dir_angle", PI * 0.5)), style, ds)
					p.z_index = -1
					anchor.add_child(p)

func _tick_snake(delta: float) -> void:
	_run_snake(delta, "viper")

## The primary Space Snake (chain 0). `kind` selects the damage scaling (the Predator fusion reuses this with
## kind "predator"). Movement + bite are shared with the 2nd snake (More Snakes evolve) via helpers.
func _run_snake(delta: float, kind: String, turn_rate := SNAKE_TURN, aim_angle := INF) -> void:
	if not _snake_init:
		_snake_pts.clear()
		var base := _mz(6) if _has_anchors() else _player.global_position   # spawn from point 6
		for k in _snake_len():
			_snake_pts.append(base - Vector2(SNAKE_SPACING * float(k), 0.0))
		_snake_dir = 0.0
		_snake_init = true
	# Grow the tail if the snake got longer after spawning (Elongate pick, Primordial God, +Bodies).
	while _snake_pts.size() < _snake_len():
		_snake_pts.append(_snake_pts[_snake_pts.size() - 1])
	if _snake_pts.is_empty():
		return
	_snake_dir = _snake_move(_snake_pts, _snake_dir, turn_rate, aim_angle, delta)
	_snake_tick += delta
	while _snake_tick >= SNAKE_TICK:
		_snake_tick -= SNAKE_TICK
		_snake_bite(_snake_pts, kind)
	_update_snake_plumes()
	# More Snakes evolve: a 2nd identical serpent (own chain; no plume VFX).
	if _snake_capstone == "more_snakes":
		_run_snake2(delta)

## Second snake for the More Snakes evolve — same stats/behaviour, separate chain, no plume anchors.
func _run_snake2(delta: float) -> void:
	if not _snake2_init:
		_snake2_pts.clear()
		var base := _player.global_position + Vector2(0.0, 48.0)
		for k in _snake_len():
			_snake2_pts.append(base - Vector2(SNAKE_SPACING * float(k), 0.0))
		_snake2_dir = PI
		_snake2_init = true
	while _snake2_pts.size() < _snake_len():
		_snake2_pts.append(_snake2_pts[_snake2_pts.size() - 1])
	if _snake2_pts.is_empty():
		return
	_snake2_dir = _snake_move(_snake2_pts, _snake2_dir, SNAKE_TURN, INF, delta)
	_snake2_tick += delta
	while _snake2_tick >= SNAKE_TICK:
		_snake2_tick -= SNAKE_TICK
		_snake_bite(_snake2_pts, "viper")

## Move a snake chain one frame: head steers toward the nearest enemy (or a given aim), body follows. Returns dir.
func _snake_move(pts: Array, dir_in: float, turn_rate: float, aim_angle: float, delta: float) -> float:
	var head: Vector2 = pts[0]
	var desired := dir_in
	if is_finite(aim_angle):
		desired = aim_angle
	else:
		var tgt := _nearest_enemy(head, INF, [])
		if tgt != null:
			desired = ((tgt as Node2D).global_position - head).angle()
		else:
			desired = (head - _player.global_position).angle() + PI * 0.5   # idle: circle the ship
	var new_dir := _approach_angle(dir_in, desired, turn_rate * delta)
	head += Vector2(cos(new_dir), sin(new_dir)) * SNAKE_SPEED * _snake_speed_mult() * _automation_rate("viper") * _weapon_speed_mult() * delta
	var dp := head - _player.global_position
	if dp.length() > 1000.0:
		head = _player.global_position + dp.normalized() * 1000.0
	pts[0] = head
	for k in range(1, pts.size()):
		var prev: Vector2 = pts[k - 1]
		var cur: Vector2 = pts[k]
		var d := prev - cur
		if d.length() > SNAKE_SPACING:
			cur = prev - d.normalized() * SNAKE_SPACING
		pts[k] = cur
	return new_dir

## One bite tick for a chain: base contact damage once per enemy + Serrated Fang (head) / Serrated Scale (per
## body segment) bleed + Primordial God kill-count.
func _snake_bite(pts: Array, kind: String) -> void:
	var fang := int(_snake_upg["serrated_fang"])
	var scale := int(_snake_upg["serrated_scale"])
	for en in _enemies() + _ruins():
		if not is_instance_valid(en):
			continue
		var ep := (en as Node2D).global_position
		var er: float = SNAKE_HIT_RADIUS + (float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0)
		var head_hit := false
		var body_contacts := 0
		for k in pts.size():
			if (pts[k] as Vector2).distance_to(ep) <= er:
				if k == 0:
					head_hit = true
				else:
					body_contacts += 1
		if not head_hit and body_contacts == 0:
			continue
		var was_alive: bool = not (en.has_method("is_dead") and en.is_dead())
		if en.has_method("take_damage"):
			var r := _roll_damage(_snake_dmg(), kind)
			if en.is_in_group("arena_ruin"):
				en.take_damage(float(r["dmg"]))   # ruins only implement the 3-arg form
			else:
				en.take_damage(float(r["dmg"]), 0.0, 0.0, false, _bleeds(kind), bool(r["is_crit"]))
		if head_hit and fang > 0 and en.has_method("apply_bleed"):
			en.apply_bleed(10 * fang)                       # Serrated Fang: head bite
		if body_contacts > 0 and scale > 0 and en.has_method("apply_bleed"):
			en.apply_bleed(2 * scale * body_contacts)       # Serrated Scale: each body segment counts separately
		if was_alive and en.has_method("is_dead") and en.is_dead():
			_snake_kills += 1                                # Primordial God growth

func _update_snake_plumes() -> void:
	if _snake_pts.is_empty():
		return
	if _snake_head_plume_anchor != null:
		var head_pos: Vector2 = _snake_pts[0]
		var fwd := Vector2(cos(_snake_dir), sin(_snake_dir))
		_snake_head_plume_anchor.global_position = head_pos + fwd * ((44.0 + 36.0) * 0.5 - SNAKE_SPACING)
		_snake_head_plume_anchor.rotation = _snake_dir + PI * 0.5
		var near := _nearest_enemy(head_pos, INF, [])
		var touching := false
		if near != null:
			var er: float = SNAKE_HIT_RADIUS + (float(near.get("hit_radius")) if near.get("hit_radius") != null else 0.0)
			touching = head_pos.distance_to((near as Node2D).global_position) <= er
		_snake_head_plume_anchor.visible = _snake_init and touching
	var n := _snake_pts.size()
	if _snake_tail_plume_anchor != null:
		var tail_pos: Vector2 = _snake_pts[n - 1]
		var tail_ang := ((_snake_pts[n - 2] as Vector2) - tail_pos).angle() if n >= 2 else _snake_dir
		_snake_tail_plume_anchor.global_position = tail_pos
		_snake_tail_plume_anchor.rotation = tail_ang + PI * 0.5
		_snake_tail_plume_anchor.visible  = _snake_init
	for bi in _snake_body_plume_anchors.size():
		var anchor: Node2D = _snake_body_plume_anchors[bi]
		var k := bi + 1   # body segments are _snake_pts[1..n-2]
		if k >= n - 1:
			anchor.visible = false
			continue
		var seg_pos: Vector2 = _snake_pts[k]
		var ang := ((_snake_pts[k - 1] as Vector2) - (_snake_pts[k + 1] as Vector2)).angle()
		anchor.global_position = seg_pos
		anchor.rotation = ang   # body uses ang directly, no +PI/2
		anchor.visible  = _snake_init

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
	_predator_beam.z_index = DEATHBEAM_BEAM_Z

func _tick_predator(delta: float, enemy_on_screen: bool) -> void:
	# Steer the head toward the densest beam line (only when there are enemies); otherwise default snake
	# steering (chase/idle). The head turns at the slower PREDATOR_TURN rate — it must rotate to aim.
	var has_enemies := not _enemies().is_empty()
	var aim_angle := _predator_aim.angle() if (enemy_on_screen and has_enemies) else INF
	_run_snake(delta, "predator", PREDATOR_TURN, aim_angle)   # snake still chases + bites (fused-level scaled)
	_ensure_predator_beam()
	if _snake_pts.is_empty():
		return
	var head: Vector2 = _snake_pts[0]
	if not enemy_on_screen:
		_predator_beam.set_beam(Vector2.ZERO, Vector2.ZERO, false, false)
		_predator_prev_valid = false   # beam is off — don't sweep-test across whatever the head did while idle
		return
	# Recompute the IDEAL aim (steering target for the head); the beam itself fires STRAIGHT from the head.
	_predator_beam_cd -= delta
	var fire := false
	if _predator_beam_cd <= 0.0:
		_predator_beam_cd = DEATHBEAM_TICK / _rate_mult / _fam_rate("predator")
		_predator_aim = _best_beam_dir(head)
		fire = true
	var dir := Vector2.from_angle(_snake_dir)   # beam = the head's current facing (turning aims it)
	# Bosses block the beam (same rule as the main Lasgun).
	var block_along := DEATHBEAM_RANGE
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		var tb: Vector2 = (b as Node2D).global_position - head
		var balong := tb.dot(dir)
		if balong < 0.0 or balong > DEATHBEAM_RANGE:
			continue
		var _br = b.get("hit_radius")
		var bw: float = DEATHBEAM_WIDTH * 0.5 + (float(_br) if _br != null else DEATHBEAM_HIT_PAD)
		if (tb - dir * balong).length() <= bw and balong < block_along:
			block_along = balong
	var blocked := block_along < DEATHBEAM_RANGE
	_predator_beam.set_beam(head, head + dir * maxf(2.0, block_along), true, blocked)
	if fire:
		# Same swept hit-test as the main Lasgun (see _beam_swept_hit) — the head can turn fast enough
		# between ticks that a single straight-line test at the tick instant would miss swept-over enemies.
		var prev_head := head if not _predator_prev_valid else _predator_prev_head
		var prev_dir := dir if not _predator_prev_valid else _predator_prev_dir
		for en in _enemies() + _ruins():
			if not is_instance_valid(en):
				continue
			var _en_r = en.get("hit_radius")
			var hit_w: float = DEATHBEAM_WIDTH * 0.5 + (float(_en_r) if _en_r != null else DEATHBEAM_HIT_PAD)
			if not _beam_swept_hit(prev_head, prev_dir, head, dir, block_along, hit_w, (en as Node2D).global_position):
				continue
			if en.has_method("take_damage"):
				var r := _roll_damage(DEATHBEAM_DAMAGE, "predator")
				if en.is_in_group("arena_ruin"):
					en.take_damage(float(r["dmg"]), DEATHBEAM_STAGGER)   # ruins only implement the 3-arg form
				else:
					en.take_damage(float(r["dmg"]), DEATHBEAM_STAGGER, 0.0, "death_beam")
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
		_predator_prev_head = head
		_predator_prev_dir = dir
		_predator_prev_valid = true

## The beam direction from `head` that crosses the MOST enemies (candidate directions = toward each enemy).
func _best_beam_dir(head: Vector2) -> Vector2:
	var enemies := _enemies()
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
			if along < 0.0 or along > DEATHBEAM_RANGE:
				continue
			var _en_r = en.get("hit_radius")
			var hit_w: float = DEATHBEAM_WIDTH * 0.5 + (float(_en_r) if _en_r != null else DEATHBEAM_HIT_PAD)
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
		var interval := HOMING_INTERVAL * _cd_scale("homing_missile") / _rate_mult
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
		var interval := HOMING_INTERVAL * _cd_scale("homing_missile") / _rate_mult
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
	for en in _enemies() + _ruins():
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
	# Missiles launch from points 7 & 8 (one per peel side) when anchored.
	var p0 := (_mz(7) if side >= 0.0 else _mz(8)) if _has_anchors() else ship_c + down * MUZZLE_OFFSET * 0.5
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
		var step := float(m["speed"]) * _weapon_speed_mult() * delta
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
						"age": 0.0, "max_age": CHEMTRAIL_PUFF_LIFETIME * _duration_mult(),
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
func _missile_explode(pos: Vector2, dmg: float, kind := "homing_missile") -> void:
	var reach := _aoe_radius(MISSILE_AOE_RADIUS)   # "AOE" stat (mech_bonus "radius") widens the blast
	for en in _enemies():
		if not is_instance_valid(en):
			continue
		var er: float = reach + (float(en.get("hit_radius")) if en.get("hit_radius") != null else 0.0)
		if pos.distance_to((en as Node2D).global_position) <= er:
			if en.has_method("take_damage"):
				var r := _roll_damage(dmg, kind)
				en.take_damage(float(r["dmg"]), 0.0)
				if bool(r["is_crit"]):
					_spawn_crit_number((en as Node2D).global_position, float(r["dmg"]))
	for ruin in _ruins():
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
		# Exhaust plume removed — drive it via thrust points (weapon_layout.cfg) + the plume registry instead.
		if _missile_tex != null:
			# Keep missile.png's native aspect ratio: anchor the length, derive the width from the texture.
			var mh := MISSILE_DRAW_LEN
			var tw := float(_missile_tex.get_width())
			var th := float(_missile_tex.get_height())
			var mw := mh
			if th > 0.0:
				mw = mh * (tw / th)
			draw_set_transform(mp, f + PI / 2.0, Vector2.ONE)
			draw_texture_rect(_missile_tex, Rect2(-mw * 0.5, -mh * 0.5, mw, mh), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var a := mp + fwd * 14.0
			var bl := mp + fwd.rotated(2.5) * 9.0
			var br := mp + fwd.rotated(-2.5) * 9.0
			draw_colored_polygon(PackedVector2Array([a, bl, br]), Color(0.9, 0.85, 0.8))

func _draw_boomerang(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var s := float(b["spin"])
	var vs := _boom_size_mult()   # Heavy Blade → the blade renders bigger, matching its wider hit
	var tex: Texture2D = BOOM_TEX
	if tex != null:
		# Spin the boomerang sprite about its centre at the projectile position (aspect-locked, never stretched).
		var ts := tex.get_size()
		var sz := Vector2(BOOM_DRAW, BOOM_DRAW * ts.y / ts.x if ts.x > 0.0 else BOOM_DRAW)
		draw_set_transform(p, s, Vector2.ONE * vs)
		draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# Procedural fallback (if the sprite is missing).
	for off: float in [0.0, PI * 0.5]:
		var a := s + off
		var d := Vector2(cos(a), sin(a)) * BOOM_BLADE * vs
		draw_line(p - d, p + d, Color(BOOM_COL.r, BOOM_COL.g, BOOM_COL.b, 0.9), 5.0, true)
	draw_circle(p, BOOM_BLADE * 0.18 * vs, Color(1, 1, 1, 0.85))

func _draw_para_cloud(c: Dictionary) -> void:
	var p: Vector2 = c["pos"]
	var a := clampf(1.0 - float(c["age"]) / PARA_LIFETIME, 0.0, 1.0)
	var reach := _aoe_radius(PARA_RADIUS)
	draw_circle(p, reach, Color(PARA_COL.r, PARA_COL.g, PARA_COL.b, 0.0))
	draw_arc(p, reach, 0.0, TAU, 48, Color(PARA_COL.r, PARA_COL.g, PARA_COL.b, 0.0), 2.0, true)
	if _para_tex != null:
		var ts := _para_tex.get_size()
		var pw := PARA_DRAW
		var ph := pw * ts.y / ts.x if ts.x > 0.0 else pw
		draw_set_transform(p, float(c.get("ang", 0.0)), Vector2.ONE)
		draw_texture_rect(_para_tex, Rect2(Vector2(-pw * 0.5, -ph * 0.5), Vector2(pw, ph)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_moro() -> void:
	const DISPLAY_W := 32.0
	var frame_idx := 1 if (_moro_punch_t > 0.0 and _moro_frames.size() > 1) else 0
	if not _moro_frames.is_empty():
		var tex := _moro_frames[mini(frame_idx, _moro_frames.size() - 1)]
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var dh := DISPLAY_W * (th / maxf(tw, 1.0))
		draw_set_transform(_moro_pos, _moro_facing + PI * 0.5, Vector2.ONE)
		draw_texture_rect(tex, Rect2(Vector2(-DISPLAY_W * 0.5, -dh * 0.5), Vector2(DISPLAY_W, dh)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(_moro_pos, 18.0, Color(MORO_COL.r, MORO_COL.g, MORO_COL.b, 0.25))
		draw_circle(_moro_pos, 13.0, Color(MORO_COL.r, MORO_COL.g, MORO_COL.b, 0.95))
	if _moro_punch_t > 0.0:
		var pf := _moro_punch_t / 0.18
		draw_arc(_moro_punch_pos, _aoe_radius(MORO_AOE) * (1.0 - pf), 0.0, TAU, 32, Color(1, 1, 1, 0.6 * pf), 3.0, true)

func _draw_yari() -> void:
	const DISPLAY_W := 32.0
	# Sprite's natural axis is UP (-PI/2). Add PI/2 to align "up" → "facing direction".
	draw_set_transform(_yari_pos, _yari_facing + PI * 0.5, Vector2.ONE)
	if not _yari_frames.is_empty():
		var tex := _yari_frames[_yari_frame_idx]
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		# Height derived from actual texture ratio — never independent X/Y scaling.
		var dh := DISPLAY_W * (th / maxf(tw, 1.0))
		draw_texture_rect(tex, Rect2(Vector2(-DISPLAY_W * 0.5, -dh * 0.5), Vector2(DISPLAY_W, dh)), false)
	else:
		draw_circle(Vector2.ZERO, 18.0, Color(YARI_COL.r, YARI_COL.g, YARI_COL.b, 0.25))
		draw_circle(Vector2.ZERO, 13.0, Color(YARI_COL.r, YARI_COL.g, YARI_COL.b, 0.95))
	if _yari_sweeping:
		var t := _yari_sweep_t / YARI_SWEEP_TIME
		draw_arc(Vector2.ZERO, 22.0 * (1.0 + 0.4 * t), 0.0, TAU, 24,
				Color(YARI_COL.r, YARI_COL.g, YARI_COL.b, 0.45 * (1.0 - t)), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # restore transform for subsequent draws

func _draw_swarm() -> void:
	for b: Dictionary in _swarm_units:
		var p: Vector2 = b["pos"]
		var is_bot: bool = bool(b.get("bot", false))
		var tex: Texture2D = _swarmbot_tex if is_bot else _swarmball_tex
		var w: float = SBALL_BOT_DRAW if is_bot else SBALL_DRAW
		if tex != null:
			var ts := tex.get_size()
			var h := w * ts.y / ts.x if ts.x > 0.0 else w
			draw_set_transform(p, float(b["ang"]), Vector2.ONE)
			draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h)), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(p, w * 0.5, Color(SBALL_COL.r, SBALL_COL.g, SBALL_COL.b, 0.9))

func _draw_snake() -> void:
	_draw_snake_chain(_snake_pts, _snake_dir)
	if _snake_capstone == "more_snakes" and not _snake2_pts.is_empty():
		_draw_snake_chain(_snake2_pts, _snake2_dir)

func _draw_snake_chain(pts: Array, dir: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	# Draw tail → head so head renders on top.
	for k in range(n - 1, -1, -1):
		var pos: Vector2 = pts[k]
		# Angle = direction from this segment toward the one closer to head (travel direction).
		var ang: float
		if k == 0:
			ang = dir
		elif k == n - 1:
			ang = ((pts[k - 1] as Vector2) - pos).angle()
		else:
			ang = ((pts[k - 1] as Vector2) - (pts[k + 1] as Vector2)).angle()  # smoothed bisector
		if k == 0:
			_draw_snake_head(pos, ang)
		elif k == n - 1:
			_draw_snake_seg(pos, ang, _snake_tail_tex, 44.0, true)
		else:
			_draw_snake_seg(pos, ang, _snake_body_tex, 25.2, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_snake_head(pos: Vector2, ang: float) -> void:
	const HEAD_PX     := 44.0
	const BODY_SEG_PX := 25.2  # must match body seg_px in _draw_snake
	var tex := _snake_head_top_tex
	if tex == null:
		draw_circle(pos, 9.0, Color(1.0, 0.85, 0.5, 0.95))
		return
	# Shift centre forward so neck is flush with body-segment front (eliminates 4 px overlap).
	var fwd      := Vector2(cos(ang), sin(ang))
	var draw_pos := pos + fwd * ((HEAD_PX + BODY_SEG_PX) * 0.5 - SNAKE_SPACING)
	var tw := float(tex.get_width())   # 390
	var th := float(tex.get_height())  # 660 = travel axis (portrait, front at top)
	var dh := HEAD_PX
	var dw := dh * tw / maxf(th, 1.0)
	draw_set_transform(draw_pos, ang + PI * 0.5, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-dw * 0.5, -dh * 0.5), Vector2(dw, dh)), false)

# Draws one body OR tail segment.  is_tail = true → portrait-UP sprite (rotation + PI/2).
func _draw_snake_seg(pos: Vector2, ang: float, tex: Texture2D, seg_px: float, is_tail: bool) -> void:
	if tex == null:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var dw: float
	var dh: float
	if is_tail:
		# Tail (498×494, nearly square, connection at TOP = travel axis = HEIGHT).
		dh = seg_px
		dw = dh * tw / maxf(th, 1.0)
		draw_set_transform(pos, ang + PI * 0.5, Vector2.ONE)
	else:
		# Body (449×376, landscape, travel axis = WIDTH).
		dw = seg_px
		dh = dw * th / maxf(tw, 1.0)
		draw_set_transform(pos, ang, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-dw * 0.5, -dh * 0.5), Vector2(dw, dh)), false)

# ── Carnage fusion (gatling + red_x): constant Red X fire + Gatling firing in 4 directions ─────────
# NOTE: const values reconstructed (missing from the merged commit).
const CARNAGE_REDX_TICK    := 0.25   # s between Carnage Red-X damage ticks; per-tick dmg = RED_X_DAMAGE × (tick/RED_X_INTERVAL) so sustained DPS == one base Red X
const CARNAGE_FIRE_DRAW    := 0.5    # DynamicFire draw-in time for the persistent X stream (matches the one-shot Red X)
const CARNAGE_FIRE_LIFETIME := 0.35  # DynamicFire particle lifetime (matches the one-shot Red X)
func activate_carnage() -> void:
	_carnage_active = true
	_carnage_gat_acc = 0.0
	_carnage_redx_tick = 0.0

func _tick_carnage(delta: float, enemy_on_screen: bool) -> void:
	# Gatling at its normal cadence, but each volley fires in 4 directions: the main facing (toward the mouse)
	# plus the 3 directions 90° apart. Bullets tagged "carnage" → scale with this fusion's level.
	var interval := GAT_FIRE_INTERVAL / _rate_mult / _fam_rate("carnage")
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
				_bullets.append({"pos": origin, "vel": dir * GAT_SPEED * _weapon_speed_mult(), "life": 0.0, "start": origin, "kind": "carnage"})
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
		_carnage_redx_tick = CARNAGE_REDX_TICK / _rate_mult / _fam_rate("carnage")
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
# NOTE: const values reconstructed (missing from the merged commit).
const VAMPIRE_RING_MAXR := 160.0      # max radius of the familiars' mini sonic wave (smaller than the Sonic weapon's 320)
const VAMPIRE_DMG_FRAC  := 1.0 / 3.0  # the mini sonic wave deals 1/3 of SONIC_DAMAGE (per the design comment)
const VAMPIRE_HEAL_FRAC := 0.25       # player heals this fraction of damage dealt (matches SWARM_HEAL_FRAC)
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
		for en in _enemies() + _ruins():
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
	if _striker_active:
		_draw_striker()
	if _shooter_active:
		_draw_shooter()
	for sring: Dictionary in _sonic_rings:
		_draw_sonic_ring(sring)
	# Z-Sword slash is rendered by the additive ZSlash crescent node (driven in _tick_zsword) — no draw here.
	# Ionize's accretion rings are drawn by _ionize_ring_layer's own "draw" signal (see _ensure_ionize_vfx) —
	# it needs to sit ABOVE the lens (z 8 > 7), which this node's own _draw() (z 0) can't do.
	for boom: Dictionary in _booms:
		_draw_boomerang(boom)
	for pc: Dictionary in _para_clouds:
		_draw_para_cloud(pc)
	if _moro_active and _moro_init:
		_draw_moro()
	if _yari_active and _yari_init:
		_draw_yari()
	if _swarm_active:
		_draw_swarm()
	if _snake_active or _predator_active:
		_draw_snake()
	if not _missiles.is_empty():
		_draw_missiles()
	if not _wasteland_zones.is_empty():
		_draw_wasteland()
	if not _mortar_bullets.is_empty():
		_draw_mortar_bullets()
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
