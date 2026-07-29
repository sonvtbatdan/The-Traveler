extends Node
## MetaManager — persistent between-run progression (Phase 2). Tracks: known weapon BLUEPRINTS (buyable in
## the hub shop), owned unique FRAGMENTS, already-CRAFTED uniques, permanent PASSIVES, and the player's
## LOADOUT (which unlocked arena weapon kinds they bring into the next run). Persists across runs in
## user://save.cfg [meta]. Drives the hub's Shop / Craft / Fragments / Passives / Loadout tabs. Calls only
## PUBLIC InventoryManager + GameManager APIs so the locked inventory data layer stays untouched.

signal meta_changed

const SAVE_PATH := "user://save.cfg"
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")   # WEAPON_INFO/CHEST_POOL — canonical kind registry
const ArenaAux := preload("res://scripts/gameplay/arena_aux.gd")          # AUX_DEFS — field-drop candidate pool

const FIELD_DROP_CHANCE        := 0.02   # per creep kill
const FIELD_DROP_WEAPON_CHANCE := 0.6    # vs. aux, when a drop actually happens

# Coin price to craft/buy one copy of a known-blueprint weapon, keyed by the weapon's rarity.
const BLUEPRINT_PRICE := {
	"common": 60, "uncommon": 150, "rare": 400, "very_rare": 1200, "unique": 3000, "legendary": 8000,
}

# Ordinal rank per rarity — used to cap boss drops by boss level (lower bosses can't yield top tiers).
const RARITY_RANK := {
	"common": 0, "uncommon": 1, "rare": 2, "very_rare": 3, "unique": 4, "legendary": 5,
}

# Permanent passives — magnitude applied per owned level at the start of every run.
const PASSIVE_DEFS := {
	"max_hp":      {"name": "Reinforced Hull", "max": 10, "base_cost": 200,  "growth": 1.55, "mag": 25.0,  "desc": "+25 max HP / level"},
	"fire_rate":   {"name": "Overclock",       "max": 8,  "base_cost": 250,  "growth": 1.6,  "mag": 0.05,  "desc": "+5% fire rate / level"},
	"damage":      {"name": "Munitions",       "max": 8,  "base_cost": 300,  "growth": 1.6,  "mag": 0.05,  "desc": "+5% weapon damage / level"},
	"start_shield":{"name": "Aegis Battery",   "max": 4,  "base_cost": 400,  "growth": 1.8,  "mag": 2.0,   "desc": "Start each run with +2s of shielding / level"},
	"coin_drop":   {"name": "Scavenger",       "max": 5,  "base_cost": 350,  "growth": 1.6,  "mag": 0.2,   "desc": "+20% coins per pickup / level"},
	"rebirth":     {"name": "Phoenix Core",    "max": 1,  "base_cost": 5000, "growth": 1.0,  "mag": 1.0,   "desc": "Revive once per run at 50% HP"},
}

var blueprints: Array = []           # known def_ids (buyable in the shop)
var fragments_owned: Dictionary = {} # unique_id -> Array[int] of owned fragment indices
var crafted_uniques: Array = []      # unique_ids already assembled (one-time)
var passives: Dictionary = {}        # passive_id -> level (int)
var run_temp_uids: Array = []        # item uids dropped mid-run (lost = sold off at the next run start)
var loadout: Array = []              # arena_weapons kind strings picked for the next run (max MAX_WEAPONS)

# Map Pack registry — hub's "Launch" flow opens a map-select panel over this list (see hub_screen.gd
# _build_mapselect). Every map is the SAME scene/arena.gd (same ship, weapons, HUD, dev-mode editors,
# enemy/wave systems) — only the terrain/background visuals and the creep spawn timeline differ per map_id
# (see arena.gd's map_id branch in _ready(), and arena_wave_director_v2.gd's _last_wave_cfg_path()). Add a
# new theme by dropping one more entry here + a matching background-builder branch in arena.gd.
const MAP_DEFS := {
	"default": {"name": "Default", "desc": "The original space arena — asteroids, waves, weapons, bosses.", "scene": "res://scenes/arena.tscn"},
	"rubicon": {"name": "Rubicon", "desc": "Procedural blue-grass / dark-sand terrain under drifting parallax clouds, scattered trees — same ship/weapons/HUD/waves as Default, different spawn timeline.", "scene": "res://scenes/arena.tscn"},
}
var selected_map_id: String = "default"   # last map picked in the Launch panel (not persisted — resets each session)

func _ready() -> void:
	load_meta()
	_seed_starter_blueprints()

# ── Blueprints / shop ────────────────────────────────────────────────────────────
## Grant every common + uncommon standard weapon as a starting blueprint so the shop is usable from
## the first run. Rarer blueprints are unlocked by disassembling boss drops (Phase 3).
func _seed_starter_blueprints() -> void:
	var changed := false
	for id: String in InventoryManager.ITEM_DEFS:
		var d: Dictionary = InventoryManager.ITEM_DEFS[id]
		var tags: Array = d.get("tags", [])
		if not tags.has("weapon") or tags.has("shield"):
			continue
		if bool(d.get("unique", false)):
			continue
		var r := String(d.get("rarity", "common"))
		if (r == "common" or r == "uncommon") and not blueprints.has(id):
			blueprints.append(id)
			changed = true
	if changed:
		save_meta()

func has_blueprint(def_id: String) -> bool:
	return blueprints.has(def_id)

func unlock_blueprint(def_id: String) -> bool:
	if blueprints.has(def_id) or not InventoryManager.ITEM_DEFS.has(def_id):
		return false
	blueprints.append(def_id)
	save_meta()
	meta_changed.emit()
	return true

func blueprint_price(def_id: String) -> int:
	var r := String(InventoryManager.get_def(def_id).get("rarity", "common"))
	return int(BLUEPRINT_PRICE.get(r, 100))

## Buy one clean copy of a known-blueprint weapon for coins → into the backpack. Returns true on success.
func buy_weapon(def_id: String) -> bool:
	if not has_blueprint(def_id):
		return false
	if not InventoryManager.has_room_for(def_id):
		return false
	var price := blueprint_price(def_id)
	if not GameManager.spend_money(price):
		return false
	var uid := InventoryManager.add_to_backpack(def_id)
	if uid == -1:
		GameManager.add_money(price)   # refund if it somehow failed to place
		return false
	meta_changed.emit()
	return true

# ── Loadout (which unlocked arena_weapons kinds to bring into the next run) ──────────────────────
## Every kind the player can currently pick from: the always-available starters (arena_weapons.CHEST_POOL)
## plus any kind whose WEAPON_INFO.def_id has a known blueprint or a crafted unique.
func unlocked_weapon_kinds() -> Array:
	var out: Array = (ArenaWeapons.CHEST_POOL as Array).duplicate()
	for kind: String in ArenaWeapons.WEAPON_INFO:
		if kind in out:
			continue
		var def_id := String((ArenaWeapons.WEAPON_INFO[kind] as Dictionary).get("def_id", ""))
		if def_id != "" and (blueprints.has(def_id) or crafted_uniques.has(def_id)):
			out.append(kind)
	return out

func is_in_loadout(kind: String) -> bool:
	return loadout.has(kind)

func loadout_full() -> bool:
	return loadout.size() >= ArenaWeapons.MAX_WEAPONS

## Add/remove `kind` from the loadout. Adding requires the kind to be unlocked and the loadout not full.
## Returns true if the loadout changed.
func toggle_loadout(kind: String) -> bool:
	if loadout.has(kind):
		loadout.erase(kind)
	else:
		if not unlocked_weapon_kinds().has(kind) or loadout_full():
			return false
		loadout.append(kind)
	save_meta()
	meta_changed.emit()
	return true

# ── Gear (hull / thruster / shield) — always-purchasable, no blueprint unlock needed ─────────────
## Every hull/thruster/shield def_id, in catalog order. Unlike weapons these never drop or craft (no
## live in-arena source exists for them — see the DOCK design note) — they're just Shop stock.
func gear_ids() -> Array:
	var out: Array = []
	for id: String in InventoryManager.ITEM_DEFS:
		var tags: Array = InventoryManager.ITEM_DEFS[id].get("tags", [])
		if tags.has("hull") or tags.has("thruster") or tags.has("shield"):
			out.append(id)
	return out

## Buy one copy of a gear item for coins → into the backpack. Same rarity-tiered pricing as weapon
## blueprints (blueprint_price is generic over any ITEM_DEFS id, not weapon-specific). No unlock gate.
func buy_gear(def_id: String) -> bool:
	if not InventoryManager.has_room_for(def_id):
		return false
	var price := blueprint_price(def_id)
	if not GameManager.spend_money(price):
		return false
	var uid := InventoryManager.add_to_backpack(def_id)
	if uid == -1:
		GameManager.add_money(price)   # refund if it somehow failed to place
		return false
	meta_changed.emit()
	return true

# ── Field drops (creep kills) — small chance to find a weapon/aux "token" straight in Cargo, so ────
# players keep discovering upgrades after their 5 WEAPONS/AUX run-slots fill up (swap one in via the
# Inventory screen's Cargo → slot drag). Run-temp: purged next run start if never swapped in, same as
# the boss-salvage "equip for this run" choice.
func roll_field_drop() -> void:
	if randf() >= FIELD_DROP_CHANCE:
		return
	if randf() < FIELD_DROP_WEAPON_CHANCE:
		_drop_field_weapon()
	else:
		_drop_field_aux()

func _drop_field_weapon() -> void:
	var def_id := roll_boss_weapon(int(RARITY_RANK.get("rare", 2)))   # standards cap at rare anyway
	if def_id == "" or not InventoryManager.has_room_for(def_id):
		return
	var uid := InventoryManager.add_to_backpack(def_id)
	if uid != -1:
		mark_run_temp(uid)

func _drop_field_aux() -> void:
	var ax := get_tree().get_first_node_in_group("arena_aux")
	var owned: Array = ax.call("owned_aux") if ax != null and ax.has_method("owned_aux") else []
	var candidates: Array = []
	for d: Dictionary in ArenaAux.AUX_DEFS:
		var id := String(d["id"])
		if not (id in owned):
			candidates.append(id)
	if candidates.is_empty():
		return
	var def_id := "aux_" + String(candidates[randi() % candidates.size()])
	if not InventoryManager.has_room_for(def_id):
		return
	var uid := InventoryManager.add_to_backpack(def_id)
	if uid != -1:
		mark_run_temp(uid)

# ── Debug: simulate a full run's worth of rewards without playing it out ─────────────────────────────
# Used by the Dev Mode "skip run" hotkey (arena_debug_spawn.gd, F4): rolls `kills` creep-kill rewards
# (coin + field drop, same formulas/gates as a real kill in arena_enemy.gd's _die()) plus `bosses` boss
# fragment drops, so a tester lands in Dock with roughly what a real run would have paid out.
const SIM_ENEMY_HP_MIN := 20.0
const SIM_ENEMY_HP_MAX := 3000.0

func simulate_run_rewards(kills: int, bosses: int) -> void:
	for _i in kills:
		var hp := randf_range(SIM_ENEMY_HP_MIN, SIM_ENEMY_HP_MAX)
		if GameManager.upg_coin_drop > 0.0:
			var expected := hp / 900.0 * GameManager.upg_coin_drop
			var coins := int(expected) + (1 if randf() < (expected - float(int(expected))) else 0)
			var skew: float = GameManager.mech_bonus("coin_skew")
			for _c in mini(coins, 20):
				GameManager.add_money(GameManager.roll_coin_value(hp, skew))
		roll_field_drop()
	for _b in bosses:
		roll_fragment_drop()

# ── Unique fragments / crafting ──────────────────────────────────────────────────
## All unique weapon ids (fragment-crafted), in catalog order. Skips uniques with no icon art yet
## ("icon": "") — temporarily disconnected from Craft/Fragments/boss fragment drops until they have a
## sprite (2026-07-27); still fully defined in code and spawnable via the F12 debug weapon palette.
func unique_ids() -> Array:
	var out: Array = []
	for id: String in InventoryManager.ITEM_DEFS:
		var d: Dictionary = InventoryManager.ITEM_DEFS[id]
		if bool(d.get("unique", false)) and String(d.get("icon", "")) != "":
			out.append(id)
	return out

func fragment_names(unique_id: String) -> Array:
	return InventoryManager.get_def(unique_id).get("fragments", [])

func fragment_count(unique_id: String) -> int:
	return fragment_names(unique_id).size()

func owned_indices(unique_id: String) -> Array:
	return fragments_owned.get(unique_id, [])

func owned_fragment_count(unique_id: String) -> int:
	return owned_indices(unique_id).size()

func is_fragment_owned(unique_id: String, idx: int) -> bool:
	return owned_indices(unique_id).has(idx)

## True when every fragment of `unique_id` is owned (ready to craft).
func is_unique_complete(unique_id: String) -> bool:
	return fragment_count(unique_id) > 0 and owned_fragment_count(unique_id) >= fragment_count(unique_id)

func is_unique_crafted(unique_id: String) -> bool:
	return crafted_uniques.has(unique_id)

## Record ownership of one fragment. Returns false if already owned / invalid.
func own_fragment(unique_id: String, idx: int) -> bool:
	if idx < 0 or idx >= fragment_count(unique_id) or is_fragment_owned(unique_id, idx):
		return false
	var arr: Array = fragments_owned.get(unique_id, [])
	arr.append(idx)
	fragments_owned[unique_id] = arr
	save_meta()
	meta_changed.emit()
	return true

## The pool of every not-yet-owned fragment across all not-yet-complete uniques, as {unique_id, index}.
func unowned_fragment_pool() -> Array:
	var pool: Array = []
	for uid: String in unique_ids():
		var n := fragment_count(uid)
		for i in n:
			if not is_fragment_owned(uid, i):
				pool.append({"unique_id": uid, "index": i})
	return pool

## Roll one random unowned fragment, mark it owned, and return {unique_id, index, name} (or {} if none
## are left). `allowed_ranks` (rarity ranks of the parent unique) gates which uniques can drop — empty =
## any. This is the boss-drop fragment path; low bosses pass only the low ranks so legendaries hold back.
func roll_fragment_drop(allowed_ranks: Array = []) -> Dictionary:
	var pool: Array = []
	for uid: String in unique_ids():
		var rank := int(RARITY_RANK.get(String(InventoryManager.get_def(uid).get("rarity", "unique")), 4))
		if not allowed_ranks.is_empty() and not (rank in allowed_ranks):
			continue
		for i in fragment_count(uid):
			if not is_fragment_owned(uid, i):
				pool.append({"unique_id": uid, "index": i})
	if pool.is_empty():
		return {}
	var pick: Dictionary = pool[randi() % pool.size()]
	var uid := String(pick["unique_id"])
	var idx := int(pick["index"])
	own_fragment(uid, idx)
	return {"unique_id": uid, "index": idx, "name": String(fragment_names(uid)[idx])}

## Roll a random STANDARD weapon def_id (non-unique) whose rarity rank ≤ max_rank, weighted by loot
## weight. Returns "" if nothing qualifies. Boss weapon drops use this (rarity capped by boss level).
func roll_boss_weapon(max_rank: int) -> String:
	var ids: Array = []
	var weights: Array = []
	var total := 0.0
	for id: String in InventoryManager.ITEM_DEFS:
		var d: Dictionary = InventoryManager.ITEM_DEFS[id]
		var tags: Array = d.get("tags", [])
		if not tags.has("weapon") or tags.has("shield") or bool(d.get("unique", false)):
			continue
		var r := String(d.get("rarity", "common"))
		if int(RARITY_RANK.get(r, 0)) > max_rank:
			continue
		var w := float(InventoryManager.RARITY_LOOT_WEIGHTS.get(r, 0))
		if w <= 0.0:
			continue
		ids.append(id)
		weights.append(w)
		total += w
	if total <= 0.0:
		return ""
	var pick := randf() * total
	var cum := 0.0
	for i in ids.size():
		cum += float(weights[i])
		if pick < cum:
			return String(ids[i])
	return String(ids[ids.size() - 1])

# ── Run-temporary drops (lost at the end of the run) ─────────────────────────────
## Flag an item uid as a mid-run drop — it is sold off (removed) at the next run start.
func mark_run_temp(uid: int) -> void:
	if uid != -1 and not run_temp_uids.has(uid):
		run_temp_uids.append(uid)
		save_meta()

## Remove every still-present run-temp item (mid-run boss drops the player chose to use). Call at the
## start of each run so last run's temporary loot doesn't carry over. Uses the public sell path.
func purge_run_temp() -> void:
	for uid in run_temp_uids:
		if not InventoryManager.get_item(int(uid)).is_empty():
			InventoryManager.sell_item(int(uid))
	run_temp_uids.clear()
	save_meta()

func can_craft_unique(unique_id: String) -> bool:
	return is_unique_complete(unique_id) and not is_unique_crafted(unique_id) and InventoryManager.has_room_for(unique_id)

## Assemble a completed unique into the backpack (one-time, free — the fragment hunt was the cost).
func craft_unique(unique_id: String) -> bool:
	if not can_craft_unique(unique_id):
		return false
	var uid := InventoryManager.add_to_backpack(unique_id)
	if uid == -1:
		return false
	crafted_uniques.append(unique_id)
	save_meta()
	meta_changed.emit()
	return true

# ── Passives ─────────────────────────────────────────────────────────────────────
func passive_level(id: String) -> int:
	return int(passives.get(id, 0))

func passive_max(id: String) -> int:
	return int(PASSIVE_DEFS.get(id, {}).get("max", 0))

## Coin cost of the NEXT level of a passive (base × growth^level). -1 when maxed / unknown.
func passive_cost(id: String) -> int:
	if not PASSIVE_DEFS.has(id):
		return -1
	var lvl := passive_level(id)
	if lvl >= passive_max(id):
		return -1
	var d: Dictionary = PASSIVE_DEFS[id]
	return int(ceil(float(d["base_cost"]) * pow(float(d["growth"]), float(lvl))))

func buy_passive(id: String) -> bool:
	var cost := passive_cost(id)
	if cost < 0 or not GameManager.spend_money(cost):
		return false
	passives[id] = passive_level(id) + 1
	save_meta()
	meta_changed.emit()
	return true

## Fold all owned passives into the fresh run state. Call AFTER GameManager.reset_run() each run start.
func apply_run_start() -> void:
	var hp := passive_level("max_hp")
	if hp > 0 and GameManager.has_method("add_max_hp"):
		GameManager.add_max_hp(int(hp * PASSIVE_DEFS["max_hp"]["mag"]))
	var fr := passive_level("fire_rate")
	if fr > 0 and GameManager.has_method("add_fire_rate"):
		GameManager.add_fire_rate(fr * float(PASSIVE_DEFS["fire_rate"]["mag"]))
	var dm := passive_level("damage")
	if dm > 0 and GameManager.has_method("add_damage"):
		GameManager.add_damage(dm * float(PASSIVE_DEFS["damage"]["mag"]))
	var cd := passive_level("coin_drop")
	if cd > 0:
		GameManager.run_coin_mult = 1.0 + cd * float(PASSIVE_DEFS["coin_drop"]["mag"])
	var rb := passive_level("rebirth")
	if rb > 0 and GameManager.has_method("grant_rebirth"):
		GameManager.grant_rebirth(rb)
	var sh := passive_level("start_shield")
	if sh > 0 and GameManager.has_method("activate_shield"):
		GameManager.activate_shield(sh * float(PASSIVE_DEFS["start_shield"]["mag"]))

# ── Persistence ──────────────────────────────────────────────────────────────────
func save_meta() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # preserve other sections
	cfg.set_value("meta", "blueprints", blueprints)
	cfg.set_value("meta", "fragments", fragments_owned)
	cfg.set_value("meta", "crafted", crafted_uniques)
	cfg.set_value("meta", "passives", passives)
	cfg.set_value("meta", "run_temp", run_temp_uids)
	cfg.set_value("meta", "loadout", loadout)
	cfg.save(SAVE_PATH)

func load_meta() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	blueprints = cfg.get_value("meta", "blueprints", [])
	fragments_owned = cfg.get_value("meta", "fragments", {})
	crafted_uniques = cfg.get_value("meta", "crafted", [])
	passives = cfg.get_value("meta", "passives", {})
	run_temp_uids = cfg.get_value("meta", "run_temp", [])
	loadout = cfg.get_value("meta", "loadout", [])
