extends Node

## InventoryManager — Diablo-2-style item / equipment data layer (Phase 2).
##
## Data only — NO UI here (that is Phase 3). Holds the item catalog, a grid
## backpack, and the 10 equip slots; provides add / move / equip / unequip plus
## fit-checking. Persists to the shared user://save.cfg under [inventory], the
## same pattern WeaponManager and DefenseManager already use.

signal inventory_changed
signal item_added(uid: int)
signal item_equipped(slot: String, uid: int)
signal item_unequipped(slot: String, uid: int)

const SAVE_PATH := "user://save.cfg"

# DEBUG ("for now"): wipe the inventory and grant exactly ONE of every item on every
# load, so testing always starts with the full arsenal in the backpack. Set to false
# to restore normal persistence (saved inventory + one-time starter grant).
const RESET_INVENTORY_ON_LOAD := false

# Affix-roll tuning. Each dropped/granted weapon also rolls a HIDDEN base-damage
# multiplier within ±BASE_DAMAGE_VARIANCE (so every copy's base damage varies a bit).
const BASE_DAMAGE_VARIANCE := 0.20          # ±20% base-damage roll per weapon instance
const WEAPON_ROLL_TIER := 1                 # tier for load-granted + ROLL WEAPON drops (1=Low 2=Mid 3=High)

# Affix-count rolling: each item independently rolls 0-or-1 prefix and 0-or-1 after-fix, so it can
# end up with 0, 1, or 2 affixes. Tune these chances (applies to both weapons and hulls).
const PREFIX_CHANCE   := 0.3                # chance an item gets a prefix affix
const AFTERFIX_CHANCE := 0.3                # chance an item gets an after-fix affix

# Backpack grid size (columns × rows), Diablo-2 style.
const BACKPACK_COLS := 10
const BACKPACK_ROWS := 13   # was 6 — enlarged so the debug "one of every item" grant (weapons + 10 hulls, ~108 cells) fits

# The physical equip slots.
## Combat weapon kinds are picked via the Hub LOADOUT tab (MetaManager.loadout) and shown live in the
## Inventory screen's 5-slot WEAPONS row (from arena_weapons) — not equipped from the backpack, so
## "primary_weapon" was dropped entirely. "secondary_weapon" survives as the shield-only slot (its real
## gameplay effect). drone_1/drone_2 and the single-placeholder gear slots (radar/energy_core/wings/
## relic/command_bridge) were removed earlier — drone combat is now the arena_weapons.gd orbital/swarm
## roster, and the other five never had more than one placeholder ITEM_DEFS entry each.
const EQUIP_SLOTS: Array[String] = [
	"secondary_weapon", "thruster", "hull",
]

# What each physical slot accepts, by item tag (see ITEM_DEFS "tags").
#   "any"     = item fits if it has AT LEAST ONE of these tags
#   "exclude" = item is rejected if it has ANY of these tags (takes priority)
const SLOT_RULES: Dictionary = {
	"secondary_weapon": {"any": ["shield"], "exclude": []},
	"thruster":         {"any": ["thruster"], "exclude": []},
	"hull":             {"any": ["hull"], "exclude": []},
}

# Placeholder icon colour per rarity (used until real art is added).
# Six-tier scheme: the 20 standard weapons roll common/uncommon/rare; the 10 fragment-crafted
# uniques are very_rare/unique/legendary. (epic was remapped → rare in the 4→6 migration.)
const RARITY_COLORS: Dictionary = {
	"common":    Color(0.62, 0.66, 0.72),   # grey
	"uncommon":  Color(0.40, 0.80, 0.45),   # green
	"rare":      Color(0.30, 0.55, 0.95),   # blue
	"very_rare": Color(0.65, 0.35, 0.90),   # purple
	"unique":    Color(0.95, 0.60, 0.20),   # orange/gold
	"legendary": Color(0.95, 0.30, 0.25),   # red
}

# Display colour by AFFIX COUNT (not loot rarity): 0 affixes = white (common), 1-2 = blue (uncommon).
const COLOR_NO_AFFIX := Color(0.95, 0.95, 0.95)   # white  — no affixes (common)
const COLOR_AFFIXED  := Color(0.35, 0.60, 1.0)    # blue   — 1-2 affixes (uncommon)

# Asteroid loot drop weights per rarity. Pool total / LOOT_DENOM ≈ base drop chance.
# Six-tier scheme. unique = 0 (fragment-crafted only; also hard-excluded in roll_asteroid_drop);
# legendary kept at 1 so the rare legendary hulls can still trickle out of asteroids.
const RARITY_LOOT_WEIGHTS: Dictionary = {
	"common":    40,
	"uncommon":  18,
	"rare":       8,
	"very_rare":  3,
	"unique":     0,
	"legendary":  1,
}
const LOOT_DENOM: int = 1000

# All possible items. "size" = grid cells (cols, rows). "tags" describe what the
# item IS (e.g. "weapon", "shield"); which slots accept it is decided by
# SLOT_RULES above. "stats" hold raw, easy-to-tweak numbers; none are wired to
# gameplay yet — that happens in Phase 5.
#
# ICONS: when "icon" is "" a coloured placeholder sized to the item's grid
# footprint is generated at runtime (see get_icon / _make_placeholder). To use
# final art later, drop a PNG (e.g. into res://assets/inventory/) and set the
# item's "icon" to its res:// path — no other code change needed.
const ITEM_DEFS: Dictionary = {
	"gauss": {
		"name": "Gauss Pulser",
		"icon": "res://assets/inventory/Gauss.png",
		"size": Vector2i(3, 2),
		"tags": ["weapon"],
		"fire_mode": "charge",   # hold to charge (up to cooldown_sec); damage scales with charge
		"fire_type": "projectile",
		"rarity": "rare",
		"group": "hybrid",
		"damage_kind": ["kinetic", "energy"],
		"desc": "Bằng cách làm co giãn cục bộ không gian, G-Pulser tạo ra nội lực xé (Shear stress) ở cấp độ phân tử",
		"stats": {
			"damage": 110,
			"cooldown_sec": 1.5,   # full charge time; damage scales linearly up to this
			"weight": 8,
			"energy_per_shot": 10,
		},
	},
	"dragons_breath": {
		"name": "Dragon's Breath",
		"icon": "res://assets/inventory/VE-TD-P.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",   # pulses every cooldown_sec (~once/sec)
		"fire_type": "cross",    # X-shaped AoE detonation centered on the ship
		"rarity": "uncommon",
		"req": 0,                # no equip gate (so the F12 grant always equips) — set a real req when balancing
		"group": "explosive",
		"damage_kind": ["kinetic", "fire"],   # a fiery X detonation
		"desc": "Turret sở hữu 4 họng phun đối xứng 90 độ, đồng loạt bắn ra các chuỗi hạt Thermite lỏng gia tốc cao.",
		"stats": {
			"cooldown_sec": 1.0,    # ~once per second; scales via _cooldown (fire-rate passives/affixes)
			"ammo_cost": 8,
			"damage": 30,           # per detonation hit; scales via _shot_damage
			"radius_px": 160,       # arm LENGTH (reach of each X arm); scales via _mech("radius")
			"arm_half_deg": 14,     # half-width of each arm in degrees (X-arm thickness)
			"weight": 5,
		},
	},
	"chemtrail": {
		"name": "Chemtrail",
		"icon": "res://assets/inventory/VE-BV-4.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "trail",    # continuous breadcrumb emit (handled in arena_weapons System 2; doc-only here)
		"fire_type": "trail",
		"rarity": "uncommon",
		"group": "area_dot",
		"damage_kind": ["bio"],
		"desc": "Chuyển hóa hợp chất độc sinh học dạng lỏng thành các luồng khí hóa hơi (Biocide Vapor) có mật độ phân tử dày đặc, phun ra phía sau tàu",
		"stats": {              # reference values — the live numbers are CHEMTRAIL_* consts in arena_weapons.gd
			"tick_damage": 6,
			"tick_interval_sec": 0.25,
			"puff_radius": 70,
			"puff_lifetime_sec": 3.0,
			"trail_offset_px": 300,
			"puff_spacing_px": 60,
			"weight": 5,
		},
	},
	"ionizing_field": {
		"name": "Ionizing Field",
		"icon": "res://assets/inventory/HO-TD-W.png",   # Black Hole (evolve of Vacuum) per Corp.pdf
		"size": Vector2i(2, 2),
		"tags": ["weapon", "shield"],
		"fire_mode": "aura",   # always-on while equipped; damages everything within radius_px each tick
		"fire_type": "aura",
		"rarity": "rare",
		"group": "energy",
		"damage_kind": ["energy"],
		"desc": "Vũ khí thử nghiệm bẻ cong không gian tại các trạm trung chuyển, gây sát thương diện rộng.",
		"stats": {
			"damage_per_tick": 14,
			"tick_interval_sec": 0.25,
			"radius_px": 140,
			"weight": 6,
			"energy_per_sec": 14,
		},
	},
	"gatling_gun": {
		"name": "Gatling Gun",
		"icon": "res://assets/inventory/VB-KA6.png",
		"size": Vector2i(3, 1),
		"tags": ["weapon"],
		"fire_mode": "repeat",   # hold to keep firing every cooldown_sec
		"fire_type": "projectile",
		"rarity": "common",
		"group": "ballistic",
		"damage_kind": ["kinetic"],
		"desc": "Pháo tự động bắn đạn động năng tốc độ cao, tiêu chuẩn quân sự phổ biến toàn vũ trụ.",
		"uses_ammo": true,
		"stats": {
			"damage": 8,
			"cooldown_sec": 0.12,
			"weight": 4,
			"ammo": 1,          # 1 ammo/s drain while firing
		},
	},
	"homing_missile": {
		"name": "Homing Missile",
		"icon": "res://assets/inventory/homingmissile.png",
		"size": Vector2i(2, 1),
		"tags": ["weapon"],
		"fire_mode": "repeat",   # auto-fires every cooldown_sec while held
		"fire_type": "homing",   # picks the nearest target; missile curves toward it
		"rarity": "uncommon",
		"damage_kind": ["explosive", "fire"],
		"desc": "Launches out the back, loops around the ship, then streaks to the cursor and bursts in an explosion.",
		"stats": {
			"damage": 19,
			"cooldown_sec": 0.53,
			"weight": 5,
			"energy": 7,   # energy per shot
		},
	},
	"death_beam": {
		"name": "Death Beam",
		"icon": "res://assets/inventory/KM-SSL-A-Alt.png",
		"size": Vector2i(3, 1),
		"tags": ["weapon"],
		"fire_mode": "beam",          # continuous while held
		"fire_type": "hitscan_beam",  # instant beam, stops at the first target
		"uses_ammo": true,            # drains the ammo bar at stats.ammo per second
		"rarity": "rare",
		"group": "energy",
		"damage_kind": ["energy", "light"],
		"desc": "Tia laser năng lượng cao",
		"stats": {
			"damage": 20,             # per tick (−70% from 66)
			"tick_interval_sec": 0.15,
			"range_px": 760,
			"beam_width": 40,         # 5× wider (drives both the drawn beam and hit width)
			"weight": 5,
			"ammo": 20,               # 20/s sustained ammo drain while firing
			"activation_ammo": 10,    # one-time ammo cost the moment you start firing
		},
	},
	"arc": {
		"name": "Arc Lightning Chain",
		"icon": "res://assets/inventory/KM-FC-A-Alt.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"fire_type": "chain",   # hits a target, then jumps to nearby ones
		"rarity": "uncommon",
		"group": "ballistic",
		"damage_kind": ["energy"],
		"desc": "Tia sét đánh nối tiếp vào đa mục tiêu",
		"stats": {
			"damage": 30,
			"cooldown_sec": 0.5,
			"chain_jumps": 4,
			"chain_range_px": 200,
			"weight": 6,
			"energy": 12,
		},
	},
	"rift_maker": {
		"name": "Rift Maker",
		"icon": "res://assets/inventory/HZ-VD-S.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "channel",        # hold to sustain
		"fire_type": "growing_zone",   # places a void at a spot that grows in size + damage while held
		"uses_ammo": true,             # drains the ammo bar (10 to start + 20/s held; can't fire at 0)
		"rarity": "rare",
		"group": "area_dot",
		"damage_kind": ["energy"],
		"desc": "Vũ khí kích hoạt trạng thái Phân rã Chân không (Vacuum Decay) cục bộ.",
		"stats": {
			"damage_min": 20,          # damage/tick at placement (-50%)
			"damage_max": 195,         # damage/tick at full ramp (-50%)
			"ramp_sec": 2.5,           # time to grow from min → max
			"tick_interval_sec": 0.3,
			"radius_min": 40,
			"radius_max": 90,    # 40% smaller than the old 150
			"weight": 9,
			"ammo": 20,                # per-second ammo drain while held
			"activation_ammo": 10,     # one-time ammo cost the moment you start holding
		},
	},
	"defensive_orbitals": {
		"name": "Defensive Orbitals",
		"icon": "res://assets/inventory/ND-OID-F.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "orbital",     # always-on passive + hold to power up (new behaviour)
		"fire_type": "orbital",     # 3 metal balls orbit the ship; collide for damage
		"uses_energy": true,        # powering up costs energy (10 to start + 20/s); the passive is free
		"rarity": "rare",
		"group": "summon",
		"damage_kind": ["kinetic", "energy"],
		"desc": "UAV tự động xoay và đâm vào các mục tiêu tiếp cận tàu",
		"stats": {
			"damage": 25,            # per collision (routed through get_weapon_stat)
			"weight": 5,
			"energy": 20,            # per-second drain while overcharged
			"activation_energy": 10, # one-time cost to start the overcharge
		},
	},
	# ── Unique weapons (Phase 1) — never random-rolled (see _is_craft_only). Each is assembled at the
	# crafting bench once you own all its fragments. "fragments" lists the distinct piece names; the
	# [fragments] save section (Phase 2) tracks which indices you own. very_rare=3 / unique=4 /
	# legendary=5 pieces. They reuse existing fire_types so the shared engine fires them unchanged.
	"singularity_lance": {
		"name": "Singularity Lance", "icon": "res://assets/inventory/Singularity Lance.png", "size": Vector2i(3, 1), "tags": ["weapon"],
		"fire_mode": "beam", "fire_type": "hitscan_beam",
		"rarity": "very_rare", "unique": true, "craftable_from_fragments": true,
		"group": "hybrid", "damage_kind": ["energy", "light"], "uses_ammo": true,
		"fragments": ["Lens Core", "Focusing Coil", "Containment Ring"],
		"desc": "A continuous lance of collapsed light that burns its target and detonates a small singularity at the impact point.",
		"stats": { "damage": 45, "tick_interval_sec": 0.12, "range_px": 900, "beam_width": 56, "splash_radius": 60, "weight": 6, "ammo": 24, "activation_ammo": 12 },
	},
	"hailstorm": {
		"name": "Hailstorm", "icon": "res://assets/inventory/Hailstorm.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "repeat", "fire_type": "cone",
		"rarity": "very_rare", "unique": true, "craftable_from_fragments": true,
		"group": "ballistic", "damage_kind": ["kinetic"], "uses_ammo": true,
		"fragments": ["Frost Chamber", "Shard Feeder", "Cryo Valve"],
		"desc": "A blizzard of razor ice shards in a wide cone that chills and shreds anything in front of you.",
		"stats": { "damage": 22, "pellets": 10, "spread_deg": 46, "range_px": 320, "cooldown_sec": 0.45, "slow": 30, "weight": 6, "ammo": 3 },
	},
	"wraithfire": {
		"name": "Wraithfire", "icon": "res://assets/inventory/Wraithfire.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "repeat", "fire_type": "projectile",
		"rarity": "very_rare", "unique": true, "craftable_from_fragments": true,
		"group": "explosive", "damage_kind": ["fire", "explosive"],
		"fragments": ["Ember Core", "Soul Wick", "Pyre Shell"],
		"desc": "Hurls ghostly fireballs that burst into a clinging blaze, burning everything caught in the splash.",
		"stats": { "damage": 40, "cooldown_sec": 0.7, "splash_radius": 120, "burn": 18, "weight": 6 },
	},
	"hivemind": {
		"name": "Hivemind", "icon": "res://assets/inventory/hivemind.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "channel", "fire_type": "minion",
		"rarity": "unique", "unique": true, "craftable_from_fragments": true,
		"group": "summon", "damage_kind": ["bio"], "uses_energy": true,
		"fragments": ["Brood Node", "Neural Mesh", "Hatch Cluster", "Queen Cell"],
		"desc": "Hold to unleash a living swarm that hunts, body-blocks, and arcs neural lightning between victims.",
		"stats": { "damage": 12, "attack_interval_sec": 0.3, "bats": 8, "respawn_sec": 2.0, "bat_range_px": 320, "chain_jumps": 2, "weight": 7, "energy": 12 },
	},
	"prism_array": {
		"name": "Prism Array", "icon": "res://assets/inventory/Prism Array.png", "size": Vector2i(3, 1), "tags": ["weapon"],
		"fire_mode": "beam", "fire_type": "hitscan_beam",
		"rarity": "unique", "unique": true, "craftable_from_fragments": true,
		"group": "energy", "damage_kind": ["light", "energy"], "uses_ammo": true,
		"fragments": ["Prism Facet", "Refractor", "Light Well", "Spectrum Gate"],
		"desc": "Splits a coherent beam into a fan of three searing lances that sweep with the cursor.",
		"stats": { "damage": 35, "tick_interval_sec": 0.12, "range_px": 820, "beam_width": 36, "beams": 3, "beam_spread_deg": 16, "weight": 6, "ammo": 26, "activation_ammo": 12 },
	},
	"graviton_well": {
		"name": "Graviton Well", "icon": "res://assets/inventory/graviton_well.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "channel", "fire_type": "growing_zone",
		"rarity": "unique", "unique": true, "craftable_from_fragments": true,
		"group": "area_dot", "damage_kind": ["energy"], "uses_ammo": true,
		"fragments": ["Mass Core", "Warp Coil", "Tidal Lens", "Singularity Seed"],
		"desc": "Hold to open a gravity well that drags enemies inward and crushes them harder the longer it grows.",
		"stats": { "damage_min": 30, "damage_max": 260, "ramp_sec": 2.5, "tick_interval_sec": 0.25, "radius_min": 50, "radius_max": 120, "pull": 180, "weight": 8, "ammo": 22, "activation_ammo": 10 },
	},
	"thunderhead": {
		"name": "Thunderhead", "icon": "res://assets/inventory/Thunderhead.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "repeat", "fire_type": "chain",
		"rarity": "unique", "unique": true, "craftable_from_fragments": true,
		"group": "energy", "damage_kind": ["energy"], "uses_energy": true,
		"fragments": ["Storm Cell", "Charge Bank", "Arc Node", "Static Crown"],
		"desc": "A rolling storm that forks lightning to a dozen targets at once and discharges a shock pulse around the ship.",
		"stats": { "damage": 30, "cooldown_sec": 0.3, "chain_jumps": 10, "chain_range_px": 240, "radius_px": 150, "weight": 7, "energy": 18 },
	},
	"annihilator": {
		"name": "Annihilator", "icon": "res://assets/inventory/Annihilator.png", "size": Vector2i(3, 2), "tags": ["weapon"],
		"fire_mode": "charge", "fire_type": "projectile",
		"rarity": "legendary", "unique": true, "craftable_from_fragments": true,
		"group": "hybrid", "damage_kind": ["kinetic", "energy"], "uses_energy": true,
		"fragments": ["Core Breach", "Rail Spine", "Capacitor Bank", "Aiming Reticle", "Doom Trigger"],
		"desc": "Charge to vent the whole reactor into one hypersonic lance that pierces an entire column and detonates.",
		"stats": { "damage": 320, "cooldown_sec": 1.6, "pierce": 12, "splash_radius": 100, "weight": 9, "energy_per_shot": 22 },
	},
	"omega_swarm": {
		"name": "Omega Swarm", "icon": "res://assets/inventory/omegaswarm.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "orbital", "fire_type": "orbital",
		"rarity": "legendary", "unique": true, "craftable_from_fragments": true,
		"group": "summon", "damage_kind": ["kinetic", "energy"], "uses_energy": true,
		"fragments": ["Orbit Hub", "Drone Bay", "Gyro Ring", "Power Spindle", "Command Halo"],
		"desc": "Six heavy orbs storm around the ship, grinding everything they touch — overcharge to whip them to a blur.",
		"stats": { "damage": 70, "orbs": 6, "weight": 8, "energy": 22, "activation_energy": 12 },
	},
	"event_horizon": {
		"name": "Event Horizon", "icon": "res://assets/inventory/Event Horizon.png", "size": Vector2i(2, 2), "tags": ["weapon"],
		"fire_mode": "channel", "fire_type": "growing_zone",
		"rarity": "legendary", "unique": true, "craftable_from_fragments": true,
		"group": "area_dot", "damage_kind": ["energy"], "uses_ammo": true,
		"fragments": ["Void Heart", "Collapse Matrix", "Dark Lattice", "Horizon Edge", "Null Anchor"],
		"desc": "Tear a true black hole into the field: a vast, devouring void that grows to swallow the screen.",
		"stats": { "damage_min": 40, "damage_max": 400, "ramp_sec": 3.0, "tick_interval_sec": 0.25, "radius_min": 60, "radius_max": 170, "pull": 240, "weight": 9, "ammo": 26, "activation_ammo": 12 },
	},

	"shield_generator": {
		"name": "Shield Generator",
		"icon": "res://assets/inventory/shield.png",
		"size": Vector2i(2, 2),
		"tags": ["shield"],   # shield-only → fits the Secondary slot only (see SLOT_RULES)
		"rarity": "rare",
		"desc": "Projects a 20-pt energy shield that absorbs damage before your hull and recharges 3s after the last hit.",
		# GameManager reads stats.shield_points (>0) on the equipped Secondary to enable the shield.
		"stats": {
			"shield_points": 20,
			"regen_delay_sec": 3.0,
			"regen_time_sec": 1.5,
			"weight": 6,
		},
	},

	# ── Hulls (Hull_balance sheet). All 2×3, tag "hull" → routed to the hull slot by SLOT_RULES.
	# stats.innate names the special effect. SIMPLE innates (already meaningful data, trivial to
	# apply later): none / move_speed_up / move_speed_down / hp_regen / glass. COMPLEX innates left
	# as TODO(innate) for a later pass: shield_on_cd, dodge_chance, energy_convert, resurrect_once,
	# reflect_damage. bonus_hp + armor are the simple shared stats (armor → DR curve in GameManager).
	"titanium_hull": {
		"name": "Titanium Hull", "icon": "res://assets/inventory/Hull/titanium.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "common",
		"desc": "Sturdy plating — flat bonus HP and flat damage reduction. No special effect.",
		"stats": { "bonus_hp": 50, "armor": 50, "innate": "none", "weight": 8 },
	},
	"adamantine_hull": {
		"name": "Adamantine Hull", "icon": "res://assets/inventory/Hull/adamantine.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "rare",
		"desc": "Every 10s gains a shield that blocks the first instance of damage, then breaks.",
		# TODO(innate): shield_on_cd — recharging 1-hit shield on a 10s cooldown.
		"stats": { "bonus_hp": 30, "armor": 20, "innate": "shield_on_cd", "innate_cd_sec": 10.0, "weight": 9 },
	},
	"aerographene_hull": {
		"name": "Aerographene Hull", "icon": "res://assets/inventory/Hull/aerographene.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "common",
		"desc": "Ultralight — small bonus HP/DR and +10% flying speed.",
		# SIMPLE: move_speed_up — apply +move_speed_pct% to ship speed.
		"stats": { "bonus_hp": 30, "armor": 20, "innate": "move_speed_up", "move_speed_pct": 10, "weight": 4 },
	},
	"glass_hull": {
		"name": "Glass Hull", "icon": "res://assets/inventory/Hull/glass.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "rare",
		"desc": "Lensed plating — amplifies beam/laser (Light & Energy) firepower, but fragile: -15% max HP.",
		# SIMPLE: glass — scale damage taken/dealt by the pcts below. Cross-interaction (Phase 5):
		# kind_bonus lifts Light/Energy damage; max_hp_pct shrinks the HP pool (read in recompute_max_hp).
		"stats": { "bonus_hp": 30, "armor": 0, "innate": "glass", "extra_damage_taken_pct": 10, "extra_damage_dealt_pct": 10,
			"kind_bonus": {"light": 25, "energy": 15}, "max_hp_pct": -15, "weight": 5 },
	},
	"neutronium_hull": {
		"name": "Neutronium Hull", "icon": "res://assets/inventory/Hull/neutronium.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "very_rare",
		"desc": "Immensely dense — big bonus HP and damage reduction, but -10% flying speed.",
		# SIMPLE: move_speed_down — apply move_speed_pct% (negative) to ship speed.
		"stats": { "bonus_hp": 80, "armor": 80, "innate": "move_speed_down", "move_speed_pct": -10, "weight": 12 },
	},
	"nanobot_hull": {
		"name": "Nanobot Hull", "icon": "res://assets/inventory/Hull/nano.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "rare",
		"desc": "Low max HP but self-repairing — decent armor and heals over time.",
		# SIMPLE: hp_regen — +hp_regen HP per second.
		"stats": { "bonus_hp": 10, "armor": 50, "innate": "hp_regen", "hp_regen": 1, "weight": 6 },
	},
	"voidmetal_hull": {
		"name": "Voidmetal Hull", "icon": "res://assets/inventory/Hull/voidmetal.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "rare",
		"desc": "Phases out of harm's way — a chance to completely dodge an instance of damage.",
		# TODO(innate): dodge_chance — dodge_pct% chance to ignore a hit entirely.
		"stats": { "bonus_hp": 30, "armor": 30, "innate": "dodge_chance", "dodge_pct": 10, "weight": 6 },
	},
	"pzt_hull": {
		"name": "PZT Hull", "icon": "res://assets/inventory/Hull/pzt.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "very_rare",
		"desc": "Piezoelectric — converts a portion of incoming damage into energy.",
		# TODO(innate): energy_convert — convert energy_convert_pct% of damage taken into energy.
		"stats": { "bonus_hp": 25, "armor": 50, "innate": "energy_convert", "energy_convert_pct": 20, "weight": 7 },
	},
	"memory_foam_hull": {
		"name": "Memory Foam Hull", "icon": "res://assets/inventory/Hull/thorned.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "legendary",
		"desc": "Bounces back from death — once per combat, revive at 50% HP and energy.",
		# TODO(innate): resurrect_once — on death, revive once per combat at 50% HP/energy.
		"stats": { "bonus_hp": 0, "armor": 0, "innate": "resurrect_once", "weight": 5 },
	},
	"cursed_hull": {
		"name": "Cursed Hull", "icon": "res://assets/inventory/Hull/cursed.png", "size": Vector2i(2, 3), "tags": ["hull"],
		"rarity": "legendary",
		"desc": "Vengeful pact — supercharges Fire & Explosive firepower, but curses your luck (-30% crit & drop).",
		# Cross-interaction (Phase 5): kind_bonus lifts Fire/Explosive damage; luck_mult scales crit chance +
		# drop/fragment chance down (read in the crit roll + the salvage screen). reflect_damage VFX still TODO.
		"stats": { "bonus_hp": 50, "armor": 0, "innate": "reflect_damage", "reflect_pct": 100,
			"kind_bonus": {"fire": 30, "explosive": 30}, "luck_mult": 0.7, "weight": 8 },
	},

	# ── New gear types (Phase 3) — one placeholder each so the slots + attribute equip-gating are
	# usable. Their stats are NOT wired to gameplay yet (descs say "coming soon"); the point for now
	# is the equip requirement (set by rarity via REQ_BY_RARITY, gated on the attribute in _gating_attr).
	# Drop a PNG path into "icon" and flesh out "stats" later — no other code change needed.
	# ── Thrusters (Phase 5) — one per behaviour; the arena player controller reads stats.thruster_type.
	"strong_thruster": {
		"name": "Strong Thruster", "icon": "", "size": Vector2i(2, 1), "tags": ["thruster"],
		"rarity": "uncommon",
		"desc": "Brute-force drive — raw top speed. Requires Maneuverability to equip.",
		"stats": { "thruster_type": "strong", "speed_mult": 1.25, "weight": 5 },
	},
	"reverse_thruster": {
		"name": "Reverse Thruster", "icon": "", "size": Vector2i(2, 1), "tags": ["thruster"],
		"rarity": "common",
		"desc": "Tuned for the backpedal — kite fast, retreat faster. Requires Maneuverability to equip.",
		"stats": { "thruster_type": "reverse", "reverse_mult": 1.6, "weight": 4 },
	},
	"smart_thruster": {
		"name": "Smart Thruster", "icon": "", "size": Vector2i(2, 1), "tags": ["thruster"],
		"rarity": "rare",
		"desc": "AI-assisted micro-bursts auto-nudge the ship off incoming fire. Requires Maneuverability to equip.",
		"stats": { "thruster_type": "smart", "dodge_radius": 130, "dodge_force": 680, "weight": 6 },
	},
	"defend_thruster": {
		"name": "Bulwark Thruster", "icon": "", "size": Vector2i(2, 1), "tags": ["thruster"],
		"rarity": "very_rare",
		"desc": "Vents a pressure wash that shoves enemy fire away from the hull. Requires Maneuverability to equip.",
		"stats": { "thruster_type": "defend", "push_radius": 170, "push_force": 560, "weight": 6 },
	},

	# ── Aux "field find" tokens — one per arena_aux.gd AUX_DEFS entry (def_id = "aux_" + aux id). Backpack-
	# representable so an aux can sit in Cargo and be dragged onto an empty AUX slot (live_slot.gd accepts any
	# "aux_"-prefixed def_id). Rarity is bucketed from the aux's level-up roll weight (no gameplay stats live
	# here — the real effect applies through arena_aux.gd once swapped in).
	# NOTE 2026-08-28: their only producer, MetaManager's creep-kill field drop, is now disabled (see
	# roll_field_drop's header) — so nothing currently puts one of these in Cargo. Kept because the defs cost
	# nothing and the drag path still works if a future source (shop tab, salvage choice) wants them.
	"aux_hp":          {"name": "Reinforcement Plate", "icon": "res://assets/hud/aux perk/hp/hp.png",                 "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "common",    "desc": "+20 Max HP."},
	"aux_regen":       {"name": "Nanobots",             "icon": "res://assets/hud/aux perk/regen/regen.png",           "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "common",    "desc": "+0.5 HP/s regen."},
	"aux_armor":       {"name": "Exoskeleton",          "icon": "res://assets/hud/aux perk/armor/armor.png",           "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "common",    "desc": "+2 Armor."},
	"aux_force_field": {"name": "Force Field",          "icon": "res://assets/hud/aux perk/force_field/force_field.png", "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "uncommon",  "desc": "+20 Max Shield (1/s regen)."},
	"aux_speed":       {"name": "Fins",                 "icon": "res://assets/hud/aux perk/speed/speed.png",           "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "common",    "desc": "+6% Speed."},
	"aux_damage":      {"name": "Art of War",           "icon": "res://assets/hud/aux perk/damage/damage.png",         "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "uncommon",  "desc": "Damage masteries."},
	"aux_fire_rate":   {"name": "Auto-Loader",          "icon": "res://assets/hud/aux perk/fire_rate/fire_rate.png",   "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "uncommon",  "desc": "+8% Fire Rate."},
	"aux_armor_pen":   {"name": "Drill Bits",           "icon": "res://assets/hud/aux perk/armor_pen/armor_pen.png",   "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "rare",      "desc": "Armor penetration + bleed."},
	"aux_crit":        {"name": "Aim Assistor",         "icon": "res://assets/hud/aux perk/crit/crit.png",             "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "uncommon",  "desc": "+5% Crit Chance."},
	"aux_harmonizer":  {"name": "Harmonizer",           "icon": "res://assets/hud/aux perk/harmonizer.png",            "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "rare",      "desc": "+Type Damage."},
	"aux_aoe":         {"name": "Explosivo",            "icon": "res://assets/hud/aux perk/aoe/aoe.png",               "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "rare",      "desc": "+25 AoE."},
	"aux_pickup":      {"name": "Magnet",               "icon": "res://assets/hud/aux perk/pickup/pickup.png",         "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "common",    "desc": "+15% Pickup radius."},
	"aux_xp":          {"name": "Data Harvester",       "icon": "res://assets/hud/aux perk/xp/xp.png",                 "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "uncommon",  "desc": "+10% EXP."},
	"aux_spawn":       {"name": "Beacon",               "icon": "res://assets/hud/aux perk/spawn/spawn.png",           "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "rare",      "desc": "+15% Spawns."},
	"aux_retaliation": {"name": "Barbed Wire",          "icon": "res://assets/hud/aux perk/retaliation/retaliation.png", "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "rare",      "desc": "+5 Retaliation."},
	"aux_revival":     {"name": "Backup Image",         "icon": "res://assets/hud/aux perk/revival.png",               "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "very_rare", "desc": "+1 Revive."},
	"aux_coin":        {"name": "Credit Extractor",     "icon": "res://assets/hud/aux perk/coin/coin.png",             "size": Vector2i(1, 1), "tags": ["aux"], "rarity": "uncommon",  "desc": "+25% Coin."},

	"yari_jaeger": {
		"name": "Yari Jeager",
		"icon": "res://assets/inventory/Yari-Jeager-idle.png",
		# The level-up board renders this instead of the flat icon (2026-08-23, on request). It is the same
		# merged model the arena draws, and Item3DIcon never touches its AnimationPlayer — so it shows the
		# rest pose, i.e. exactly `stand`.
		"glb": "res://assets/weaponry/Jeager/Jeager.glb",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "familiar",
		"fire_type": "slash",
		"rarity": "rare",
		"group": "summon",
		"damage_kind": ["energy"],
		"desc": "A blade familiar that hunts down enemies and unleashes a spinning arc slash on contact.",
		"stats": {
			"damage": 55,
			"attack_interval_sec": 1.5,
			"weight": 4,
		},
	},
	"mortar": {
		"name": "Mortar",
		"icon": "res://assets/inventory/R-HPM-IV.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"rarity": "rare",
		"group": "explosive",
		"damage_kind": ["kinetic", "explosive"],
		"desc": "Súng cối hạng nặng chuyên phá hủy lớp giáp dày và các công trình kiên cố.",
		"stats": { "weight": 8 },
	},
	"fat_boy": {
		"name": "Fat Boy",
		"icon": "res://assets/inventory/FatBoy.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"rarity": "epic",
		"group": "explosive",
		"damage_kind": ["kinetic", "explosive"],
		"desc": "Vũ khí hạt nhân tối thượng, sức hủy diệt vô hạn",
		"stats": { "weight": 10 },
	},
	"z_sword": {
		"name": "Z-Sword",
		"icon": "res://assets/inventory/EK-SW88.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"rarity": "rare",
		"group": "energy",
		"damage_kind": ["energy"],
		"desc": "Vũ khí cận chiến, sử dụng cơ cấu truyền động răng cưa phức tạp, quét và đẩy ra sóng xung kích",
		"stats": { "weight": 6 },
	},
	"ultrasonicator": {
		"name": "Ultrasonicator",
		"icon": "res://assets/inventory/YongSan Sonic.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"rarity": "uncommon",
		"group": "energy",
		"damage_kind": ["energy"],
		"desc": "Phóng ra sóng sonic",
		"stats": { "weight": 5 },
	},
	"boomerang": {
		"name": "Boomerang",
		"icon": "res://assets/inventory/ND-Aliwa.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"rarity": "uncommon",
		"group": "ballistic",
		"damage_kind": ["kinetic"],
		"desc": "Ném boomerang",
		"stats": { "weight": 5 },
	},
	"viper": {
		"name": "Viper",
		"icon": "res://assets/inventory/VIPER.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "familiar",
		"rarity": "rare",
		"group": "summon",
		"damage_kind": ["fire"],
		"desc": "V.I.P.E.R (Viral Infiltration & Penetration Exo-Rover): Thiết bị tự hành ngoại vi xâm nhập và thẩm thấu virus.",
		"stats": { "weight": 5 },
	},
	"yari": {
		"name": "Yari",
		"icon": "res://assets/inventory/Yari.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "familiar",
		"fire_type": "slash",
		"rarity": "rare",
		"group": "summon",
		"damage_kind": ["energy"],
		"desc": "Vũ khí cận chiến, sử dụng cơ cấu pin shot bắn cây thương nhọn vào địch",
		"stats": { "weight": 5 },
	},
	"venomancer": {
		"name": "Venomancer",
		"icon": "res://assets/inventory/BC-SL.png",
		"size": Vector2i(2, 2),
		"tags": ["weapon"],
		"fire_mode": "repeat",
		"rarity": "rare",
		"group": "summon",
		"damage_kind": ["bio"],
		"desc": "Súng phóng bào tử sinh học biến đổi gen, ăn mòn các lớp hợp kim kim loại siêu bền của tàu địch.",
		"stats": { "weight": 5 },
	},
}

# Items granted automatically the FIRST time a save is created (new game only).
# Keeping this separate from ITEM_DEFS means future items (e.g. asteroid drops in
# Phase 4) can be defined without being auto-placed in the backpack.
#
# 2026-08-25, on request: **EMPTY** — a new game (or Settings' Reset Profile) now starts with a completely
# bare inventory. "Khi mới bắt đầu game thì inventory phải trống mới đúng. Người chơi sẽ có cơ chế craft đồ
# từ mechanic, khi đó mới đem đi và xuất hiện trong inventory được." Previously this granted gatling_gun.
#
# Safe to empty: arena combat does NOT read equipped inventory weapons at all — arena.gd deliberately never
# instantiates arena_loadout.gd, and the run is armed entirely by the bespoke 5-slot system (the start-of-run
# weapon chest + F12 pickups, see arena_weapons.gd). The ship also keeps BASE_SHIP_HP/BASE_SHIELD_MAX
# (game_manager.gd) with zero hull/shield equipped, which was already the shipped baseline.
#
# NOTE this only governs what a FRESH profile is seeded with. The mid-run "field drop" loot that used to keep
# refilling the backpack anyway (meta_manager.gd's roll_field_drop(), 2% per creep kill, completely silent) is
# now DISABLED — 2026-08-28, after it made a freshly-reset profile sprout ~6-9 unexplained items, Vipers
# included, in its first minute on Electric. See roll_field_drop's header for the full write-up.
const STARTER_ITEMS: Array[String] = []

# The starter BLUEPRINT — a separate concept from STARTER_ITEMS above, and deliberately still gatling_gun.
# meta_manager.gd seeds this into the craftable blueprint list (_seed_starter_blueprints) and exempts it from
# the "already known?" check, so a fresh profile can immediately CRAFT a Gatling Gun at the mechanic rather
# than being handed one. That is exactly the flow the empty-inventory request describes ("người chơi sẽ có cơ
# chế craft đồ từ mechanic, khi đó mới đem đi và xuất hiện trong inventory được"), so it stays.
const STARTER_WEAPON_ID := "gatling_gun"

# ── Runtime state ─────────────────────────────────────────────────────────────
# _items: uid(int) -> {"def": String, "where": String, "cell": Vector2i}
#   where = "backpack" or one of EQUIP_SLOTS; cell = backpack origin (col, row).
var _items: Dictionary = {}
var _next_uid: int = 1
# Def ids ever granted as starters — so a newly-added starter item is granted to an
# existing save exactly once, and trashed items aren't restored on the next load.
var _granted: Array = []
var _icon_cache: Dictionary = {}
var _glb_cache: Dictionary = {}   # def_id -> res:// glb path, or "" if none — see get_glb()

func _ready() -> void:
	load_game()

# ── Definition / item queries ─────────────────────────────────────────────────

func get_def(def_id: String) -> Dictionary:
	var d: Dictionary = ITEM_DEFS.get(def_id, {})
	return d

func get_item(uid: int) -> Dictionary:
	var d: Dictionary = _items.get(uid, {})
	return d

func def_size(def_id: String) -> Vector2i:
	var d: Dictionary = ITEM_DEFS.get(def_id, {})
	var s: Vector2i = d.get("size", Vector2i(1, 1))
	return s

func backpack_uids() -> Array:
	var result: Array = []
	for uid: int in _items:
		if String(_items[uid]["where"]) == "backpack":
			result.append(uid)
	return result

func equipped_uid(slot: String) -> int:
	for uid: int in _items:
		if String(_items[uid]["where"]) == slot:
			return uid
	return -1

func fits_slot(def_id: String, slot: String) -> bool:
	var d: Dictionary = ITEM_DEFS.get(def_id, {})
	if d.is_empty():
		return false
	var rule: Dictionary = SLOT_RULES.get(slot, {})
	if rule.is_empty():
		return false
	var tags: Array = d.get("tags", [])
	# Any excluded tag disqualifies the item outright (e.g. shield → not Primary).
	for t in rule.get("exclude", []):
		if tags.has(t):
			return false
	# Otherwise it fits if it has at least one accepted tag.
	for t in rule.get("any", []):
		if tags.has(t):
			return true
	return false

# ── Weapon classes + attribute equip requirements (Phase 3) ──────────────────────

## A weapon's damage class drives which attribute boosts it (and which attribute gates it).
## TODO (user): set "weapon_class" on each weapon in ITEM_DEFS to one of
## "kinetic" / "energy" / "biochemical". Left unset for now, so only Marksmanship's universal
## damage bonus is active and weapons gate on Marksmanship by default.
func weapon_class(def: Dictionary) -> String:
	return String(def.get("weapon_class", ""))

## Which attribute gates equipping an item, from its tags / weapon class.
## hull & relic → biotech, radar → marksmanship, energy_core → engineering,
## wings/thruster/drone → maneuverability, weapons → by class (else marksmanship). "" = ungated.
func _gating_attr(def: Dictionary) -> String:
	var tags: Array = def.get("tags", [])
	if tags.has("hull") or tags.has("relic"):
		return "biotech"
	if tags.has("radar"):
		return "marksmanship"
	if tags.has("energy_core"):
		return "engineering"
	if tags.has("wings") or tags.has("thruster") or tags.has("drone"):
		return "maneuverability"
	if tags.has("weapon"):
		match weapon_class(def):
			"energy":     return "engineering"
			"biochemical": return "biotech"
			_:            return "marksmanship"
	return ""   # command_bridge, shield, etc. — ungated

## The attribute + minimum value needed to equip a def. `value` comes from an optional per-def
## "req" override, else the rarity default (GameManager.REQ_BY_RARITY). attr "" = no requirement.
func item_requirement(def_id: String) -> Dictionary:
	var d: Dictionary = ITEM_DEFS.get(def_id, {})
	if d.is_empty():
		return {"attr": "", "value": 0}
	var a := _gating_attr(d)
	if a == "":
		return {"attr": "", "value": 0}
	var val: int = int(d.get("req", GameManager.REQ_BY_RARITY.get(String(d.get("rarity", "common")), 0)))
	return {"attr": a, "value": val}

## True if the player's attributes meet the def's equip requirement.
func meets_requirement(def_id: String) -> bool:
	var r := item_requirement(def_id)
	if String(r["attr"]) == "":
		return true
	return GameManager.attr(String(r["attr"])) >= int(r["value"])

# ── Backpack geometry ──────────────────────────────────────────────────────────

func can_place(size: Vector2i, cell: Vector2i, ignore_uid: int = -1) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	if cell.x + size.x > BACKPACK_COLS or cell.y + size.y > BACKPACK_ROWS:
		return false
	var rect := Rect2i(cell, size)
	for uid: int in _items:
		if uid == ignore_uid:
			continue
		if String(_items[uid]["where"]) != "backpack":
			continue
		var other_cell: Vector2i = _items[uid]["cell"]
		var other_size := def_size(String(_items[uid]["def"]))
		if rect.intersects(Rect2i(other_cell, other_size)):
			return false
	return true

func _find_free_cell(size: Vector2i, ignore_uid: int = -1) -> Vector2i:
	for r: int in range(BACKPACK_ROWS):
		for c: int in range(BACKPACK_COLS):
			var cell := Vector2i(c, r)
			if can_place(size, cell, ignore_uid):
				return cell
	return Vector2i(-1, -1)

func has_room_for(def_id: String) -> bool:
	return _find_free_cell(def_size(def_id)) != Vector2i(-1, -1)

func is_backpack_full() -> bool:
	# "Full" relative to the smallest possible item (1×1).
	return _find_free_cell(Vector2i(1, 1)) == Vector2i(-1, -1)

# ── Mutations ──────────────────────────────────────────────────────────────────

## Add a new instance of def_id into the first free backpack slot.
## Returns the new uid, or -1 if the item is unknown / there is no room.
func add_to_backpack(def_id: String) -> int:
	if not ITEM_DEFS.has(def_id):
		return -1
	var cell := _find_free_cell(def_size(def_id))
	if cell == Vector2i(-1, -1):
		return -1
	var uid := _next_uid
	_next_uid += 1
	_items[uid] = {"def": def_id, "where": "backpack", "cell": cell}
	save_game()
	item_added.emit(uid)
	inventory_changed.emit()
	return uid

## Move an item to a backpack cell. Works both for re-arranging within the
## backpack and for dragging an equipped item back out to a specific cell.
func move_item(uid: int, cell: Vector2i) -> bool:
	if not _items.has(uid):
		return false
	var size := def_size(String(_items[uid]["def"]))
	if not can_place(size, cell, uid):
		return false
	var prev_slot := String(_items[uid]["where"])
	_items[uid]["where"] = "backpack"
	_items[uid]["cell"] = cell
	if prev_slot != "backpack":
		item_unequipped.emit(prev_slot, uid)
	save_game()
	inventory_changed.emit()
	return true

## Equip uid into slot. Fails if the item type does not match the slot, or if
## the slot is occupied and the current occupant cannot be returned to the
## backpack (no room).
func equip(uid: int, slot: String) -> bool:
	if not _items.has(uid):
		return false
	var def_id := String(_items[uid]["def"])
	if not fits_slot(def_id, slot):
		return false
	if not meets_requirement(def_id):
		return false   # attribute requirement not met (caller surfaces the reason — see equip_slot.gd)
	var occupant := equipped_uid(slot)
	if occupant == uid:
		return true
	if occupant != -1:
		if not _send_to_backpack(occupant):
			return false  # no room to swap the old item out
		item_unequipped.emit(slot, occupant)
	_items[uid]["where"] = slot
	save_game()
	item_equipped.emit(slot, uid)
	inventory_changed.emit()
	return true

## Move whatever is in slot back to the backpack. Fails if the backpack is full.
func unequip(slot: String) -> bool:
	var uid := equipped_uid(slot)
	if uid == -1:
		return false
	if not _send_to_backpack(uid):
		return false
	save_game()
	item_unequipped.emit(slot, uid)
	inventory_changed.emit()
	return true

## "Bring Home" (2026-08-29, on request) — a single-item staging slot for the inventory UI's Bring Home drop
## target. Same "where" mechanism and single-occupant swap shape as equip()/unequip() above (reuses
## _send_to_backpack, fires the same item_equipped/item_unequipped signals with slot name "bring_home" so
## existing listeners need no special-casing) — but this is NOT a real EQUIP_SLOTS gear slot: no stat effect,
## and deliberately no fits_slot()/meets_requirement() gate (the caller, MetaManager.stage_bring_home(),
## already restricts this to weapon items before ever calling here). can_place()/_find_free_cell() already
## treat any where != "backpack" as not occupying a cell, so nothing else needed changes for this to coexist
## cleanly with the real backpack grid.
func stage_bring_home(uid: int) -> bool:
	if not _items.has(uid):
		return false
	var occupant := equipped_uid("bring_home")
	if occupant == uid:
		return true
	if occupant != -1:
		if not _send_to_backpack(occupant):
			return false   # no room to swap the previous pick back to Cargo
		item_unequipped.emit("bring_home", occupant)
	_items[uid]["where"] = "bring_home"
	save_game()
	item_equipped.emit("bring_home", uid)
	inventory_changed.emit()
	return true

## Send the Bring Home slot's current occupant (if any) back to Cargo — used both for the player dragging it
## back out by hand (via the generic move_item() path backpack_grid.gd already calls, which needs no changes
## since it treats every non-"backpack" where identically) and by MetaManager.resolve_bring_home()'s victory
## path (the item survives a completed run and becomes an ordinary owned item again). A no-op returning true
## when nothing is staged.
func release_bring_home() -> bool:
	var uid := equipped_uid("bring_home")
	if uid == -1:
		return true
	if not _send_to_backpack(uid):
		return false
	save_game()
	item_unequipped.emit("bring_home", uid)
	inventory_changed.emit()
	return true

## Payout for scrapping one item instance ("Extract & Dispose"). 2026-08-29, on request ("lượng coin thu
## được bằng 1/10 giá mua"): 1/10th of MetaManager.blueprint_price(def_id) — the exact same rarity-tiered
## price the Merchant charges to buy that item, so extracting something never looks arbitrary next to what
## it would cost to buy back. Was a flat $5 (2026-08-25, itself a bump from $1) before this; EXTRACT_PAYOUT
## stays as the floor for anything with no meaningful price (an unrecognized def_id → blueprint_price's own
## 100-default ÷ 10 = 10, well above this floor in practice — kept mainly as a defensive minimum, not the
## normal case). Keep this the single source of sell pricing — the right-click confirm dialog and the
## inventory's Extract & Dispose drop slot both read it, so the two routes can never disagree.
const EXTRACT_PAYOUT := 5

func get_sell_price(uid: int) -> int:
	var def_id := String(_items.get(uid, {}).get("def", ""))
	if def_id == "":
		return EXTRACT_PAYOUT
	return maxi(EXTRACT_PAYOUT, int(round(float(MetaManager.blueprint_price(def_id)) / 10.0)))

## Sell (delete) an item and pay the player. Works whether the item is in the
## backpack or equipped — selling an equipped item just removes it from its slot
## (unequip-then-sell). Returns false if the uid is unknown.
func sell_item(uid: int) -> bool:
	if not _items.has(uid):
		return false
	var price := get_sell_price(uid)
	var where := String(_items[uid]["where"])   # "backpack" or an equip slot name
	_items.erase(uid)
	GameManager.add_money(price)
	save_game()
	if where != "backpack":
		item_unequipped.emit(where, uid)   # let shield/weapon systems react
	inventory_changed.emit()
	return true

## True if at least one instance of def_id exists anywhere in the inventory (backpack or equipped) —
## used by the Hub Shop grid to show an "Owned" state instead of a price once a copy has been bought.
func owns_def(def_id: String) -> bool:
	for uid: int in _items:
		if String(_items[uid]["def"]) == def_id:
			return true
	return false

## Remove `uid` outright — no coin payment, no confirmation. Used when a Cargo item is CONSUMED by
## swapping it into a live in-run WEAPONS/AUX slot (as opposed to sell_item(), which pays out and is
## driven by the player's explicit right-click "Sell" confirm).
func remove_item(uid: int) -> bool:
	if not _items.has(uid):
		return false
	var where := String(_items[uid]["where"])
	_items.erase(uid)
	save_game()
	if where != "backpack":
		item_unequipped.emit(where, uid)
	inventory_changed.emit()
	return true

func _send_to_backpack(uid: int) -> bool:
	var cell := _find_free_cell(def_size(String(_items[uid]["def"])), uid)
	if cell == Vector2i(-1, -1):
		return false
	_items[uid]["where"] = "backpack"
	_items[uid]["cell"] = cell
	return true

# ── Icons (real art if present, else a coloured placeholder) ────────────────────

func get_icon(def_id: String) -> Texture2D:
	if _icon_cache.has(def_id):
		return _icon_cache[def_id]
	var d: Dictionary = ITEM_DEFS.get(def_id, {})
	var tex: Texture2D = null
	var icon_path := String(d.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	if tex == null:
		tex = _make_placeholder(d)
	_icon_cache[def_id] = tex
	return tex

## Path to a live 3D model for `def_id`'s art, or "" if it only has flat PNG art. Derived from ITEM_DEFS'
## "icon" path by swapping the extension (e.g. "assets/inventory/Annihilator.png" → "…Annihilator.glb") —
## 2026-08-19, on request: a batch of test weapon glbs was dropped in alongside their existing PNGs under
## the same basename, no separate data field needed. Callers (arena_levelup_ui.gd) use this to swap a
## TextureRect for a live-rendered Item3DIcon when one exists, falling back to get_icon()'s PNG otherwise.
## Explicit .glb art for icons whose MODEL file isn't named after the PNG — the sibling-of-the-icon guess
## below (and in arena_levelup_ui) can't find those on its own. Keyed by ICON PATH rather than def_id so it
## also covers weapon kinds that have no ITEM_DEFS entry at all and are identified purely by an icon
## override (Striker, whose art is the Orbital Impact OFFENSE model — see arena_weapons.WEAPON_INFO).
const GLB_BY_ICON := {
	"res://assets/inventory/ND-OID-F.png": "res://assets/inventory/defense orbital.glb",
	"res://assets/inventory/ND-OIF-F.png": "res://assets/inventory/offense orbital.glb",
	"res://assets/weaponry/ND-OIF-F.png": "res://assets/inventory/offense orbital.glb",
}

## The .glb for a weapon identified by an ITEM_DEFS def_id and/or a direct icon-path override — the SINGLE
## resolution shared by the level-up board (arena_levelup_ui._weapon_icon_glb), the arena weapon pickup
## (arena_weapon_pickup.gd) and the background preloader (arena_glb_preloader.gd), so a weapon can never
## show a 3D model in one of those and a flat PNG in another. "" = no model, caller falls back to the PNG.
func glb_for(def_id: String, icon_path: String) -> String:
	if def_id != "":
		var g := get_glb(def_id)
		if g != "":
			return g
	if icon_path != "":
		var ov := String(GLB_BY_ICON.get(icon_path, ""))
		if ov != "" and ResourceLoader.exists(ov):
			return ov
		if icon_path.get_extension().to_lower() == "png":
			var candidate := icon_path.get_basename() + ".glb"
			if ResourceLoader.exists(candidate):
				return candidate
	return ""

func get_glb(def_id: String) -> String:
	if _glb_cache.has(def_id):
		return String(_glb_cache[def_id])
	var d: Dictionary = ITEM_DEFS.get(def_id, {})
	var glb_path := ""
	# An explicit "glb" on the def wins over the sibling-of-the-icon guess below (2026-08-23). The guess only
	# works when the model happens to sit next to the PNG under the same basename; Yari Jeager's lives in
	# assets/weaponry/Jeager/ and is shared with the arena, so it has to be named outright.
	var explicit := String(d.get("glb", ""))
	if explicit != "" and ResourceLoader.exists(explicit):
		_glb_cache[def_id] = explicit
		return explicit
	var icon_path := String(d.get("icon", ""))
	if icon_path != "":
		# A GLB_BY_ICON entry outranks the sibling guess (Defensive Orbitals' icon is ND-OID-F.png but its
		# model is "defense orbital.glb" — nothing about the filename connects the two).
		var mapped := String(GLB_BY_ICON.get(icon_path, ""))
		if mapped != "" and ResourceLoader.exists(mapped):
			glb_path = mapped
		elif icon_path.get_extension().to_lower() == "png":
			var candidate := icon_path.get_basename() + ".glb"
			if ResourceLoader.exists(candidate):
				glb_path = candidate
	_glb_cache[def_id] = glb_path
	return glb_path

func _make_placeholder(d: Dictionary) -> Texture2D:
	# Sized to the item's grid footprint so multi-cell items (3×2, 2×2, …) fill
	# their space at the right aspect ratio rather than appearing as a tiny square.
	var rarity := String(d.get("rarity", "common"))
	var col: Color = RARITY_COLORS.get(rarity, Color(0.6, 0.6, 0.6))
	var size_cells: Vector2i = d.get("size", Vector2i(1, 1))
	var w: int = maxi(size_cells.x * 48, 16)
	var h: int = maxi(size_cells.y * 48, 16)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(col)
	var border := col.darkened(0.45)
	for x: int in range(w):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, h - 1, border)
	for y: int in range(h):
		img.set_pixel(0, y, border)
		img.set_pixel(w - 1, y, border)
	return ImageTexture.create_from_image(img)

# ── Asteroid loot (Phase 4) ─────────────────────────────────────────────────────

## True for items that must NOT appear in random rolls: fragment-crafted uniques and the
## fragments themselves. They enter the game only through boss drops + the crafting bench.
func _is_craft_only(d: Dictionary) -> bool:
	if bool(d.get("unique", false)):
		return true
	var tags: Array = d.get("tags", [])
	return tags.has("fragment")

## Roll for an item drop when an asteroid is destroyed.
## Adds the item to the backpack and returns its def_id, or "" if nothing dropped.
## Callers can use the returned id to show a visual notification.
func roll_asteroid_drop() -> String:
	# Build the weighted pool from the current ITEM_DEFS.
	var pool_weight: int = 0
	for id: String in ITEM_DEFS:
		if _is_craft_only(ITEM_DEFS[id]):
			continue
		var r := String(ITEM_DEFS[id].get("rarity", "common"))
		pool_weight += int(RARITY_LOOT_WEIGHTS.get(r, 0))
	# pool_weight / LOOT_DENOM = base drop probability per asteroid.
	if randf_range(0.0, float(LOOT_DENOM)) > float(pool_weight):
		return ""
	# Pick an item proportionally by rarity weight.
	var pick: float = randf() * float(pool_weight)
	var cum: float = 0.0
	for id: String in ITEM_DEFS:
		if _is_craft_only(ITEM_DEFS[id]):
			continue
		var r := String(ITEM_DEFS[id].get("rarity", "common"))
		cum += float(int(RARITY_LOOT_WEIGHTS.get(r, 0)))
		if pick < cum:
			if not has_room_for(id):
				return ""  # backpack full
			var uid := add_to_backpack(id)
			if uid == -1:
				return ""
			return id
	return ""

# ── Affix-rolled weapons (Phase 2) ─────────────────────────────────────────────

## Base weapon ids eligible to be rolled into a unique drop (real weapons only —
## excludes the passive Shield Generator).
func _weapon_base_ids() -> Array:
	var out: Array = []
	for id: String in ITEM_DEFS:
		var tags: Array = ITEM_DEFS[id].get("tags", [])
		if _is_craft_only(ITEM_DEFS[id]):
			continue   # fragment-crafted uniques are never randomly rolled
		if tags.has("weapon") and not tags.has("shield"):
			out.append(id)
	return out

## Generate a unique weapon instance: a random base (or `base_def_id` if given) with
## ONE prefix affix + ONE after-fix affix, both drawn from the weapon-eligible pool
## (distinct ids) and rolled at `tier` (1=Low, 2=Mid, 3=High). The rolls are stored on
## the item instance, so every drop is unique. Returns the new uid, or -1 if there's
## no room. (Phase 3 will vary the affix COUNT by rarity; this always rolls 2.)
## Roll the unique part of a weapon: 0-or-1 prefix + 0-or-1 after-fix affix (each rolled
## independently at PREFIX_CHANCE / AFTERFIX_CHANCE), drawn from the weapon-eligible pool at
## `tier` — distinct ids when both roll, and any affix can fill either slot. Plus a hidden
## ±BASE_DAMAGE_VARIANCE base-damage multiplier. Returns {affixes, base_mult} (0, 1, or 2 affixes).
func _roll_weapon(tier: int) -> Dictionary:
	return _roll_affixes(AffixManager.weapon_affix_ids(), tier)

## Shared affix roller for weapons AND hulls: shuffle `pool`, then independently add a prefix
## (PREFIX_CHANCE) and an after-fix (AFTERFIX_CHANCE). Consuming the shuffled pool by index keeps
## the two ids distinct when both roll; either id can be either role. base_mult is the hidden roll.
func _roll_affixes(pool: Array, tier: int) -> Dictionary:
	pool.shuffle()
	var affixes: Array = []
	var idx := 0
	if pool.size() > idx and randf() < PREFIX_CHANCE:
		var pid := String(pool[idx]); idx += 1
		affixes.append({"id": pid, "role": "prefix", "value": AffixManager.roll_affix(pid, tier)})
	if pool.size() > idx and randf() < AFTERFIX_CHANCE:
		var sid := String(pool[idx]); idx += 1
		affixes.append({"id": sid, "role": "suffix", "value": AffixManager.roll_affix(sid, tier)})
	var v := BASE_DAMAGE_VARIANCE
	return {"affixes": affixes, "base_mult": randf_range(1.0 - v, 1.0 + v)}

## Generate a unique weapon instance: a random base (or `base_def_id`) rolled at
## `tier`. Returns the new uid, or -1 if there's no room.
func generate_weapon(tier: int, base_def_id: String = "") -> int:
	var bases := _weapon_base_ids()
	if bases.is_empty():
		return -1
	var base_id := base_def_id if ITEM_DEFS.has(base_def_id) else String(bases[randi() % bases.size()])
	var uid := add_to_backpack(base_id)
	if uid == -1:
		return -1
	var roll := _roll_weapon(tier)
	_items[uid]["affixes"] = roll["affixes"]
	_items[uid]["base_mult"] = roll["base_mult"]
	save_game()
	inventory_changed.emit()
	return uid

# ── Affix-rolled hulls (mirror the weapon path; defensive affix pool) ───────────

## Base hull ids eligible to be rolled (anything tagged "hull").
func _hull_base_ids() -> Array:
	var out: Array = []
	for id: String in ITEM_DEFS:
		if Array(ITEM_DEFS[id].get("tags", [])).has("hull"):
			out.append(id)
	return out

## Roll the unique part of a hull: 0-or-1 prefix + 0-or-1 after-fix from the HULL (defensive) affix
## pool, plus the hidden ±BASE_DAMAGE_VARIANCE roll — stored as base_mult exactly like weapons, but
## applied to the hull's bonus_hp (not damage) wherever it's read. Returns {affixes, base_mult}.
func _roll_hull(tier: int) -> Dictionary:
	var roll := _roll_affixes(AffixManager.hull_affix_ids(), tier)
	# bonus_hp and armor each get their OWN independent ±BASE_DAMAGE_VARIANCE roll.
	var v := BASE_DAMAGE_VARIANCE
	roll["hull_mult"] = {
		"bonus_hp": randf_range(1.0 - v, 1.0 + v),
		"armor": randf_range(1.0 - v, 1.0 + v),
	}
	return roll

## Generate a unique hull instance: a random hull base (or `base_def_id` if it's a hull) rolled at
## `tier`. Returns the new uid, or -1 if there's no room.
func generate_hull(tier: int, base_def_id: String = "") -> int:
	var bases := _hull_base_ids()
	if bases.is_empty():
		return -1
	var valid_base: bool = ITEM_DEFS.has(base_def_id) and Array(ITEM_DEFS[base_def_id].get("tags", [])).has("hull")
	var base_id := base_def_id if valid_base else String(bases[randi() % bases.size()])
	var uid := add_to_backpack(base_id)
	if uid == -1:
		return -1
	var roll := _roll_hull(tier)
	_items[uid]["affixes"] = roll["affixes"]
	_items[uid]["base_mult"] = roll["base_mult"]
	_items[uid]["hull_mult"] = roll["hull_mult"]
	save_game()
	inventory_changed.emit()
	return uid

## Affixes rolled on an item instance: Array of {id, role:"prefix"/"suffix", value}.
func item_affixes(uid: int) -> Array:
	return _items.get(uid, {}).get("affixes", [])

## Hidden base-damage multiplier rolled on this instance (1.0 if none).
func item_base_mult(uid: int) -> float:
	return float(_items.get(uid, {}).get("base_mult", 1.0))

## Name/border colour by affix count: white if no affixes (common), blue if it has 1-2 affixes
## (uncommon). Independent of the def's loot rarity.
func item_display_color(uid: int) -> Color:
	return COLOR_AFFIXED if not item_affixes(uid).is_empty() else COLOR_NO_AFFIX

## A hull instance's rolled bonus HP / armor = the def's base × that stat's OWN independent ±20% roll
## (stored in the item's `hull_mult`), rounded. 0 if absent. Each stat varies separately, so a hull
## can roll high HP but low armor (and vice-versa). Armor feeds the damage-reduction curve in GameManager.
func hull_bonus_hp(uid: int) -> int:
	return _hull_rolled_stat(uid, "bonus_hp")
func hull_armor(uid: int) -> int:
	return _hull_rolled_stat(uid, "armor")
func _hull_rolled_stat(uid: int, key: String) -> int:
	var it: Dictionary = _items.get(uid, {})
	var s: Dictionary = get_def(String(it.get("def", ""))).get("stats", {})
	if not s.has(key):
		return 0
	var mult: float = float(Dictionary(it.get("hull_mult", {})).get(key, 1.0))
	return roundi(float(s[key]) * mult)

## Combined display name: "[Prefix] [Base] [After-fix]" (empty slots omitted).
func item_display_name(uid: int) -> String:
	var it: Dictionary = _items.get(uid, {})
	if it.is_empty():
		return ""
	var base := String(get_def(String(it.get("def", ""))).get("name", ""))
	var affixes: Array = it.get("affixes", [])
	if affixes.is_empty():
		return base
	var prefix := ""
	var suffix := ""
	for a: Dictionary in affixes:
		var ad: Dictionary = AffixManager.get_affix(String(a.get("id", "")))
		if ad.is_empty():
			continue
		if String(a.get("role", "")) == "prefix":
			prefix = String(ad.get("prefix", ""))
		elif String(a.get("role", "")) == "suffix":
			suffix = String(ad.get("after_fix", ""))
	var parts: Array[String] = []
	if prefix != "":
		parts.append(prefix)
	parts.append(base)
	if suffix != "":
		parts.append(suffix)
	return " ".join(parts)

# ── Persistence (shared user://save.cfg, section [inventory]) ───────────────────

## Public: wipes this manager's own [inventory] slice of the profile back to a fresh-start state — every
## owned item (weapons/gear/whatever's in the backpack or equipped) is cleared and replaced with just
## STARTER_ITEMS (gatling_gun). Part of Settings' "Reset Profile" action (see settings_panel.gd);
## GameManager.reset_profile()/MetaManager.reset_profile() handle their own slices.
func reset_profile() -> void:
	_seed_starter_items()   # clears _items, re-grants STARTER_ITEMS, saves

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # preserve [weapons] / [defense] written by other managers
	if cfg.has_section("inventory"):
		cfg.erase_section("inventory")
	cfg.set_value("inventory", "next_uid", _next_uid)
	cfg.set_value("inventory", "granted", _granted)
	var arr: Array = []
	for uid: int in _items:
		var it: Dictionary = _items[uid]
		arr.append({"uid": uid, "def": it["def"], "where": it["where"], "cell": it["cell"], "affixes": it.get("affixes", []), "base_mult": it.get("base_mult", 1.0), "hull_mult": it.get("hull_mult", {})})
	cfg.set_value("inventory", "items", arr)
	cfg.save(SAVE_PATH)

func load_game() -> void:
	if RESET_INVENTORY_ON_LOAD:
		_grant_one_of_each()
		return
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SAVE_PATH)
	if loaded != OK or not cfg.has_section("inventory"):
		_seed_starter_items()
		return
	_items.clear()
	_next_uid = int(cfg.get_value("inventory", "next_uid", 1))
	_granted = cfg.get_value("inventory", "granted", [])
	var arr: Array = cfg.get_value("inventory", "items", [])
	for entry: Dictionary in arr:
		var def_id := String(entry.get("def", ""))
		if not ITEM_DEFS.has(def_id):
			continue  # drop items whose definition no longer exists
		var uid := int(entry.get("uid", _next_uid))
		_items[uid] = {
			"def": def_id,
			"where": String(entry.get("where", "backpack")),
			"cell": entry.get("cell", Vector2i.ZERO),
			"affixes": entry.get("affixes", []),
			"base_mult": float(entry.get("base_mult", 1.0)),
			"hull_mult": entry.get("hull_mult", {}),
		}
	_backfill_starters()
	inventory_changed.emit()

## Grant any STARTER_ITEMS this save has never been granted before (e.g. weapons
## added in a later update), once each. Existing items / trashed items are untouched.
func _backfill_starters() -> void:
	var changed := false
	for def_id: String in STARTER_ITEMS:
		if not _granted.has(def_id):
			if add_to_backpack(def_id) != -1:
				changed = true
			_granted.append(def_id)
			changed = true
	if changed:
		save_game()

## DEBUG (RESET_INVENTORY_ON_LOAD): clear everything and drop one of EVERY item into
## the backpack. Runs on every load while the flag is on. Nothing is auto-equipped.
func _grant_one_of_each() -> void:
	_items.clear()
	_next_uid = 1
	var weapons := _weapon_base_ids()
	var hulls := _hull_base_ids()
	for def_id: String in ITEM_DEFS:
		var uid := add_to_backpack(def_id)
		if uid == -1:
			continue
		# Weapons + hulls roll affixes + a hidden base roll, like real drops (each from its own pool).
		if weapons.has(def_id):
			var roll := _roll_weapon(WEAPON_ROLL_TIER)
			_items[uid]["affixes"] = roll["affixes"]
			_items[uid]["base_mult"] = roll["base_mult"]
		elif hulls.has(def_id):
			var hroll := _roll_hull(WEAPON_ROLL_TIER)
			_items[uid]["affixes"] = hroll["affixes"]
			_items[uid]["base_mult"] = hroll["base_mult"]
			_items[uid]["hull_mult"] = hroll["hull_mult"]
	_granted = ITEM_DEFS.keys()   # so backfill won't double-add if the flag is later turned off
	inventory_changed.emit()

## First run only (no [inventory] in the save): grant the STARTER_ITEMS. Once a
## save exists this never runs again — so it won't re-add items every load, and
## won't restore items a player deliberately got rid of.
func _seed_starter_items() -> void:
	_items.clear()
	_next_uid = 1
	for def_id: String in STARTER_ITEMS:
		add_to_backpack(def_id)
	_granted = STARTER_ITEMS.duplicate()
	save_game()
