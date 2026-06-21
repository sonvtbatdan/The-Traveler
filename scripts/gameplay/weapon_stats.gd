class_name WeaponStats
extends RefCounted
## Shared, stateless weapon-stat resolver — the single source of truth for turning an equipped item
## (its base def + rolled affixes + hidden ±20% base_mult) into final numbers. Both the main-scene
## firing engine (weapon_system.gd) and the arena firing engine (arena_weapons.gd) call these, so a
## weapon does identical damage/cadence/crit no matter which mode you're in. Pure functions only —
## no node, scene, or coordinate state. weapon_system.gd's get_weapon_stat / _equipped_def / _roll_crit
## now delegate here; keep the logic below in lock-step with that file's intent.

# Base crit values when a weapon has no crit affixes. KEEP IN SYNC with weapon_system.gd.
const BASE_CRIT_CHANCE := 0       # % base crit when a weapon has no crit affix (crit comes from affixes/cards).
const BASE_CRIT_DAMAGE := 100.0   # % extra damage on a crit (100 = double)

# Stat keys each affix maps onto (an affix only changes the matching keys).
const _AFFIX_DAMAGE_KEYS   := ["damage", "damage_min", "damage_max", "damage_per_tick", "dps"]
const _AFFIX_COOLDOWN_KEYS := ["cooldown_sec", "tick_interval_sec"]   # lower = faster
const _AFFIX_ENERGY_KEYS   := ["energy", "activation_energy"]

## Raw stat off the def (no affixes / rolls). Mirrors weapon_system._stat.
static func raw_stat(def: Dictionary, key: String, fallback: float) -> float:
	var stats: Dictionary = def.get("stats", {})
	return float(stats.get(key, fallback))

## Final stat with the instance's ±20% base-damage roll + rolled affixes + attribute multipliers
## applied. Mirrors weapon_system.get_weapon_stat verbatim so both engines agree.
static func get_stat(def: Dictionary, key: String, fallback: float) -> float:
	var v := raw_stat(def, key, fallback)
	# Hidden ±20% base-damage roll (damage keys only) — applied before any affixes.
	var is_dmg: bool = key in _AFFIX_DAMAGE_KEYS
	if is_dmg:
		v *= float(def.get("base_mult", 1.0))
	# Attribute category damage multiplier (Marksmanship / weapon-class bonuses) + the equipped hull's
	# damage-kind bonus (Glass → Light/Energy, Cursed → Fire/Explosive). Both apply to every damage-like
	# key, including shot_damage/tick_damage which sit outside the affix damage keys.
	var cat := 1.0
	if is_dmg or key == "shot_damage" or key == "tick_damage":
		cat = GameManager.weapon_damage_mult(def) * GameManager.hull_kind_mult(def.get("damage_kind", []))
	var affixes: Array = def.get("affixes", [])
	if affixes.is_empty():
		return v * cat
	var dmg_pct := 0.0
	for a: Dictionary in affixes:
		var id := String(a.get("id", ""))
		var val := float(a.get("value", 0.0))
		match id:
			"damage_flat":
				if is_dmg:
					v += val
			"damage_percentage":
				if is_dmg:
					dmg_pct += val
			"fire_rate":
				if key in _AFFIX_COOLDOWN_KEYS:
					v = v / (1.0 + val / 100.0)        # % faster → lower cooldown
			"energy_consumption_percentage":
				if key in _AFFIX_ENERGY_KEYS:
					v = v * (1.0 + val / 100.0)        # val is negative → cheaper
			"crit_chance":
				if key == "crit_chance":
					v += val
			"crit_damage":
				if key == "crit_damage":
					v += val
	return v * (1.0 + dmg_pct / 100.0) * cat

## Resolve the def equipped in `slot`, with the instance's affixes + base_mult attached (without
## mutating the shared ITEM_DEFS entry). Returns {} when the slot is empty. Mirrors _equipped_def.
static func resolve_def(slot: String) -> Dictionary:
	var uid: int = InventoryManager.equipped_uid(slot)
	if uid == -1:
		return {}
	var item: Dictionary = InventoryManager.get_item(uid)
	var def: Dictionary = InventoryManager.get_def(String(item.get("def", "")))
	if def.is_empty():
		return {}
	var affixes: Array = item.get("affixes", [])
	var base_mult := float(item.get("base_mult", 1.0))
	if affixes.is_empty() and base_mult == 1.0:
		return def
	var d := def.duplicate()
	d["affixes"] = affixes
	d["base_mult"] = base_mult
	return d

## Roll a crit against `base` damage using the weapon's crit_chance/crit_damage (affix-aware).
## Returns {dmg, crit}. Mirrors weapon_system._roll_crit.
static func roll_crit(def: Dictionary, base: float) -> Dictionary:
	var chance := get_stat(def, "crit_chance", float(BASE_CRIT_CHANCE))
	var crit := randf() * 100.0 < chance
	var dmg := base
	if crit:
		dmg = base * (1.0 + get_stat(def, "crit_damage", BASE_CRIT_DAMAGE) / 100.0)
	return {"dmg": dmg, "crit": crit}
