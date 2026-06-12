extends Node

## AffixManager — Diablo-2-style affix catalog + tier-band roller (minh_scope Phase 1).
##
## DATA ONLY here: the affix table (from Item_fixes_completed.xlsx), the list of
## affixes allowed on WEAPONS, and one roll function. Nothing is wired into weapons
## yet — that is Phase 2 (rolling a weapon instance + feeding get_weapon_stat).
##
## Tier-band rolling (from the spreadsheet's "Tier rules" sheet):
##   span    = Max - Min
##   low_cap = Min + span * 0.33
##   mid_cap = Min + span * 0.66
##   tier 1 (Low):  roll in [Min,     low_cap]
##   tier 2 (Mid):  roll in [low_cap, mid_cap]
##   tier 3 (High): roll in [mid_cap, Max]
## Negative affixes (energy_consumption_percentage, model_size_reduce) use the SAME
## math — Min/Max are negative so a higher tier rolls toward the more-negative (better) end.

const TIER_LOW  := 1
const TIER_MID  := 2
const TIER_HIGH := 3

## Every affix: id -> {prefix, after_fix, unit, min, max}. Mirrors the spreadsheet
## (the 33%/66% caps are derived in roll_affix, not stored). Tweak min/max freely.
const AFFIX_DEFS: Dictionary = {
	"damage_flat":                    {"prefix": "Devastating", "after_fix": "of Ruin",            "unit": "flat",   "min": 1,   "max": 5},
	"damage_percentage":              {"prefix": "Brutal",      "after_fix": "of Destruction",     "unit": "%",      "min": 10,  "max": 150},
	"fire_rate":                      {"prefix": "Rapidfire",   "after_fix": "of Barrage",         "unit": "%",      "min": 10,  "max": 150},
	"faster_run_flat":                {"prefix": "Fleet",       "after_fix": "of Footing",         "unit": "flat",   "min": 10,  "max": 70},
	"faster_run_percentage":          {"prefix": "Swift",       "after_fix": "of Speed",           "unit": "%",      "min": 5,   "max": 30},
	"energy_regen_flat":              {"prefix": "Energizing",  "after_fix": "of Replenishment",   "unit": "flat",   "min": 1,   "max": 5},
	"energy_regen_percentage":        {"prefix": "Conductive",  "after_fix": "of Flow",            "unit": "%",      "min": 20,  "max": 300},
	"shield_flat":                    {"prefix": "Bulwark",     "after_fix": "of Fortification",   "unit": "flat",   "min": 10,  "max": 200},
	"hp_flat":                        {"prefix": "Stalwart",    "after_fix": "of Vitality",        "unit": "flat",   "min": 20,  "max": 300},
	"hp_percentage":                  {"prefix": "Vigorous",    "after_fix": "of Endurance",       "unit": "%",      "min": 10,  "max": 300},
	"energy_consumption_percentage":  {"prefix": "Efficient",   "after_fix": "of Conservation",    "unit": "%",      "min": -10, "max": -50},
	"hp_regen":                       {"prefix": "Regenerative","after_fix": "of Repair",          "unit": "flat/s", "min": 1,   "max": 25},
	"shield_regen":                   {"prefix": "Recharging",  "after_fix": "of Recovery",        "unit": "flat/s", "min": 2,   "max": 40},
	"crit_chance":                    {"prefix": "Accurate",    "after_fix": "of Luck",            "unit": "%",      "min": 2,   "max": 25},
	"crit_damage":                    {"prefix": "Savage",      "after_fix": "of Devastation",     "unit": "%",      "min": 15,  "max": 150},
	"armor":                          {"prefix": "Armored",     "after_fix": "of Plating",         "unit": "flat",   "min": 10,  "max": 250},
	"damage_reduction":               {"prefix": "Reinforced",  "after_fix": "of Mitigation",      "unit": "%",      "min": 2,   "max": 20},
	"model_size_increase":            {"prefix": "Titanic",     "after_fix": "of Expansion",       "unit": "%",      "min": 5,   "max": 30},
	"model_size_reduce":              {"prefix": "Compact",     "after_fix": "of Miniaturization", "unit": "%",      "min": -5,  "max": -30},
	"weight_requirement_reduction":   {"prefix": "Lightweight", "after_fix": "of Loadlifting",     "unit": "%",      "min": 5,   "max": 40},
	"projectile_speed":               {"prefix": "Accelerating","after_fix": "of Ballistics",      "unit": "%",      "min": 10,  "max": 100},
	"armor_penetration":              {"prefix": "Piercing",    "after_fix": "of Breach",          "unit": "%",      "min": 5,   "max": 50},
	"poison":                         {"prefix": "Toxic",       "after_fix": "of Venom",           "unit": "flat/s", "min": 2,   "max": 60},
	"slow":                           {"prefix": "Crippling",   "after_fix": "of Drag",            "unit": "%",      "min": 5,   "max": 40},
	"freeze":                         {"prefix": "Frozen",      "after_fix": "of Frost",           "unit": "%",      "min": 3,   "max": 20},
	"burn":                           {"prefix": "Incendiary",  "after_fix": "of Scorching",       "unit": "flat/s", "min": 3,   "max": 75},
	"multishot":                      {"prefix": "Duplicative", "after_fix": "of Multiplicity",    "unit": "flat",   "min": 1,   "max": 3},
	"pierce":                         {"prefix": "Piercing",    "after_fix": "of Perforation",     "unit": "flat",   "min": 1,   "max": 4},
	"ricochet":                       {"prefix": "Rebounding",  "after_fix": "of Ricochet",        "unit": "flat",   "min": 1,   "max": 3},
	"splash_radius":                  {"prefix": "Explosive",   "after_fix": "of Detonation",      "unit": "%",      "min": 10,  "max": 120},
	"knockback":                      {"prefix": "Repulsing",   "after_fix": "of Impact",          "unit": "%",      "min": 5,   "max": 50},
	"shield_delay_reduction":         {"prefix": "Reactive",    "after_fix": "of Quick Recovery",  "unit": "%",      "min": 5,   "max": 50},
	"evasion_chance":                 {"prefix": "Elusive",     "after_fix": "of Evasion",         "unit": "%",      "min": 2,   "max": 20},
	"damage_immunity_duration":       {"prefix": "Invulnerable","after_fix": "of Phaseguard",      "unit": "%",      "min": 5,   "max": 40},
	"rebirth":                        {"prefix": "Phoenix",     "after_fix": "of Rebirth",         "unit": "flat",   "min": 1,   "max": 1},
	"dash_cooldown_reduction":        {"prefix": "Blinking",    "after_fix": "of Swift Reset",     "unit": "%",      "min": 5,   "max": 40},
	"dash_distance":                  {"prefix": "Lunging",     "after_fix": "of Long Dash",       "unit": "%",      "min": 10,  "max": 60},
	"energy_leech":                   {"prefix": "Siphoning",   "after_fix": "of Energy Drain",    "unit": "%",      "min": 1,   "max": 8},
	"hp_leech":                       {"prefix": "Vampiric",    "after_fix": "of Life Drain",      "unit": "%",      "min": 1,   "max": 6},
	"shield_leech":                   {"prefix": "Absorbing",   "after_fix": "of Shield Drain",    "unit": "%",      "min": 1,   "max": 7},
	"drone_damage":                   {"prefix": "Commanding",  "after_fix": "of Drone Assault",   "unit": "%",      "min": 10,  "max": 120},
	"damage_on_contact":              {"prefix": "Thorned",     "after_fix": "of Retribution",     "unit": "flat",   "min": 2,   "max": 50},
	"damage_when_damaged":            {"prefix": "Vengeful",    "after_fix": "of Reprisal",        "unit": "flat",   "min": 5,   "max": 100},
}

## Affixes allowed to roll on WEAPONS. Everything else (HP/shield/dash/drone/etc.)
## is ship/equipment-only and excluded. Edit this one list to add/remove later.
const WEAPON_AFFIX_POOL: Array[String] = [
	"damage_flat", "damage_percentage", "fire_rate", "crit_chance", "crit_damage",
	"armor_penetration", "poison", "slow", "freeze", "burn", "multishot", "pierce",
	"ricochet", "splash_radius", "knockback", "projectile_speed",
	"energy_consumption_percentage", "energy_leech", "hp_leech", "shield_leech",
	"energy_regen_flat", "energy_regen_percentage",
]

## Affixes allowed to roll on HULLS (defensive / ship affixes). These are the ones EXCLUDED from
## weapons, PLUS the energy affixes (shared with weapons), MINUS "rebirth" (excluded by design).
## Its own list so affixes can be moved between the weapon and hull pools later.
const HULL_AFFIX_POOL: Array[String] = [
	"hp_flat", "hp_percentage", "hp_regen",
	"shield_flat", "shield_regen", "shield_delay_reduction",
	"armor", "damage_reduction", "evasion_chance", "damage_immunity_duration",
	"faster_run_flat", "faster_run_percentage",
	"dash_cooldown_reduction", "dash_distance",
	"model_size_increase", "model_size_reduce", "weight_requirement_reduction",
	"drone_damage", "damage_on_contact", "damage_when_damaged",
	"energy_regen_flat", "energy_regen_percentage", "energy_consumption_percentage",
]

# ── Queries ───────────────────────────────────────────────────────────────────

func get_affix(affix_id: String) -> Dictionary:
	return AFFIX_DEFS.get(affix_id, {})

func is_weapon_eligible(affix_id: String) -> bool:
	return WEAPON_AFFIX_POOL.has(affix_id)

func is_hull_eligible(affix_id: String) -> bool:
	return HULL_AFFIX_POOL.has(affix_id)

## The weapon-eligible affix ids (a copy, so callers can shuffle/edit freely).
func weapon_affix_ids() -> Array:
	return WEAPON_AFFIX_POOL.duplicate()

## The hull-eligible (defensive) affix ids (a copy, so callers can shuffle/edit freely).
func hull_affix_ids() -> Array:
	return HULL_AFFIX_POOL.duplicate()

# ── Roller ────────────────────────────────────────────────────────────────────

## Roll one affix's value for a given item tier (1=Low, 2=Mid, 3=High), inside that
## tier's band of the affix's Min→Max range (see the tier-band notes at the top).
## Returns 0.0 for an unknown affix id. Integer-count affixes (multishot/pierce/…)
## are returned raw here; rounding happens where the value is applied (Phase 2).
func roll_affix(affix_id: String, tier: int) -> float:
	var a: Dictionary = AFFIX_DEFS.get(affix_id, {})
	if a.is_empty():
		return 0.0
	var mn := float(a["min"])
	var mx := float(a["max"])
	var span := mx - mn
	var low_cap := mn + span * 0.33
	var mid_cap := mn + span * 0.66
	var roll_lo := mn
	var roll_hi := low_cap
	match clampi(tier, TIER_LOW, TIER_HIGH):
		TIER_MID:
			roll_lo = low_cap
			roll_hi = mid_cap
		TIER_HIGH:
			roll_lo = mid_cap
			roll_hi = mx
	# minf/maxf so randf_range always gets from <= to (handles negative affixes,
	# where the band runs from a less-negative to a more-negative number).
	return randf_range(minf(roll_lo, roll_hi), maxf(roll_lo, roll_hi))
