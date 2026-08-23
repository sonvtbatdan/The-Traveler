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
	"interest_boost": {"name": "Cunning Engineer", "max": 5, "base_cost": 300, "growth": 1.6, "mag": 0.02, "desc": "+2% dock interest / level (see DOCK_INTEREST_BASE_RATE)"},
}

# ── Dock interest (2026-08-05, on request) ─────────────────────────────────────────
# Saved coins earn interest on every "RETURN TO DOCK" (arena.gd's two dock_btn/_show_dock_corner_button
# handlers both call apply_dock_interest() right before the scene change), but ONLY if the run lasted at
# least DOCK_INTEREST_MIN_RUN_TIME — a sub-10-minute run earns nothing, specifically to close off an
# exploit where the player could farm interest by instantly quitting back to dock over and over. Rate =
# base 5% + 2%/level of the "interest_boost" passive above (max +10% at level 5, so 5–15% total).
const DOCK_INTEREST_BASE_RATE := 0.05
const DOCK_INTEREST_MIN_RUN_TIME := 600.0   # 10 minutes, in seconds — GameManager.run_time (frozen while paused)

## Apply one dock-interest payout to the persistent wallet (GameManager.money) and return the amount paid
## (0 if the run didn't qualify, or the wallet was already empty). Idempotent to call at most once per
## dock arrival — arena.gd is the only caller, right before each of its two hub.tscn scene changes.
func apply_dock_interest() -> int:
	if GameManager.run_time < DOCK_INTEREST_MIN_RUN_TIME:
		return 0
	var rate := DOCK_INTEREST_BASE_RATE + float(passive_level("interest_boost")) * float(PASSIVE_DEFS["interest_boost"]["mag"])
	var interest := int(round(float(GameManager.money) * rate))
	if interest <= 0:
		return 0
	GameManager.add_money(interest)
	return interest

# ── Dock room unlocks (2026-08-06, on request) ────────────────────────────────────
# Rooms on the Dock board that start LOCKED — an overlay "<room> lock.png" hides the room (see
# dock_binder.gd) until unlock_room() is called for it. Rooms with no lock asset (Bridge, Launch) aren't
# listed here and are always open. "name" is the player-facing label shown in the unlock notification
# (hub_screen.gd) — mirrors dock_binder.ROOM_NAME_OVERRIDE's "mechanic"→"Merchant" precedent for the
# internal-id-vs-display-label split. Pilot/Pilot2 share the "Pilot" label since they're the same room
# conceptually, just two plaques unlocked by two separate Constructor-room upgrades.
#
# Unlock conditions (per 2026-08-06 design, some "set up in a later level/system" — TODO markers below):
#   beacon      → rescue the Psyker                         (TODO: no rescue system yet)
#   codex       → defeat your first boss                    (wired: _on_boss_defeated below)
#   constructor → rescue the Constructor                     (TODO: no rescue system yet)
#   engineer    → rescue the Engineer                        (TODO: no rescue system yet)
#   equipment   → buy any weapon other than the starter gatling_gun (wired: buy_weapon below)
#   instructor  → rescue the Scholar                         (TODO: no rescue system yet)
#   mechanic    → rescue the Mechanic                        (TODO: no rescue system yet)
#   pilot       → Constructor-room upgrade #1                (TODO: Constructor upgrades not built yet)
#   pilot2      → Constructor-room upgrade #2                (TODO: Constructor upgrades not built yet)
#   trophy      → complete your first achievement            (TODO: achievement list not defined yet)
const ROOM_UNLOCK_DEFS := {
	"beacon":      {"name": "Beacon"},
	"codex":       {"name": "Codex"},
	"constructor": {"name": "Constructor"},
	"engineer":    {"name": "Engineer"},
	"equipment":   {"name": "Equipment"},
	"instructor":  {"name": "Instructor"},
	"mechanic":    {"name": "Merchant"},
	"pilot":       {"name": "Pilot"},
	"pilot2":      {"name": "Pilot"},
	"trophy":      {"name": "Trophy"},
}
var room_unlocks: Dictionary = {}   # room_id (key of ROOM_UNLOCK_DEFS) -> bool; missing/false = still locked

## True if `room_id` is playable — either it has no lock def at all (Bridge/Launch) or it's been unlocked.
func is_room_unlocked(room_id: String) -> bool:
	if not ROOM_UNLOCK_DEFS.has(room_id):
		return true
	return bool(room_unlocks.get(room_id, false))

## Unlock a Dock room (idempotent — false if already unlocked or `room_id` isn't a known lockable room).
## Every future rescue/boss/upgrade/achievement hook is meant to call this one function — dock_binder.gd
## reacts to meta_changed and shows/hides the room's lock overlay accordingly. Also queues a
## GameManager.pending_room_unlock_notices entry so hub_screen.gd can show the "<room> is now accessible"
## card next time it's on-screen, whether the unlock happened while already on the Dock or elsewhere
## (mid-run boss kill, etc. — same "queue it, drain it on arrival" idiom as pending_interest_notice).
func unlock_room(room_id: String) -> bool:
	if not ROOM_UNLOCK_DEFS.has(room_id) or is_room_unlocked(room_id):
		return false
	room_unlocks[room_id] = true
	save_meta()
	meta_changed.emit()
	if "pending_room_unlock_notices" in GameManager:
		GameManager.pending_room_unlock_notices.append(String(ROOM_UNLOCK_DEFS[room_id]["name"]))
	return true

# ── Rescue landmarks (2026-08-06, on request; redistributed 2026-08-19) ────────────
# The 5 rescue-character ruin landmarks, one per map. Each maps to the Dock room it unlocks
# (ROOM_UNLOCK_DEFS key above) and the display name used in the "has been taken on your ship" pickup
# toast + the run-end rescue result line. NOTE (2026-08-19): icon PNGs below don't exist yet — the glb
# models were swapped to new art and the old baked icons were deleted with them; the "icon" paths here
# are the intended location for the NEXT bake (tools/bake_*_landmark.gd) but will fail to load until
# then. Only electric_ruin_layer.gd / volcanic_ruin_layer.gd actually spawn a landmark today — arctic
# and cosmic have no ruin_layer script yet, so their entries below are wired but inert until one is
# built (same TODO status atlantic was already in before this pass).
const RESCUE_CHARACTER_DEFS := {
	"constructor": {"room": "constructor", "name": "Constructor", "glb": "res://assets/map/electric/landmark/constructor.glb", "icon": "res://assets/map/electric/landmark/constructor.png"},
	"mechanic":    {"room": "mechanic",    "name": "Mechanic",    "glb": "res://assets/map/volcanic/landmark/mechanic.glb",    "icon": "res://assets/map/volcanic/landmark/mechanic.png"},
	"engineer":    {"room": "engineer",    "name": "Engineer",    "glb": "res://assets/map/arctic/landmark/engineer.glb",      "icon": "res://assets/map/arctic/landmark/engineer.png"},
	"psyker":      {"room": "beacon",      "name": "Psyker",      "glb": "res://assets/map/cosmic/landmark/psyker.glb",        "icon": "res://assets/map/cosmic/landmark/psyker.png"},
	"scholar":     {"room": "instructor",  "name": "Scholar",     "glb": "res://assets/map/atlantic/landmark/Scholar.glb",     "icon": "res://assets/map/atlantic/landmark/Scholar.png"},
}
# One character per map (2026-08-19: was a 2-per-map queue + a shared "Scholar fallback" before the
# redistribution; now every character — Scholar included — belongs to exactly one map, so the fallback
# tier is gone). Default/space never gets a rescue landmark (no 3D landmark rendering pipeline for it).
const RESCUE_MAP_QUEUE := {
	"electric": ["constructor"],
	"volcanic": ["mechanic"],
	"arctic":   ["engineer"],
	"cosmic":   ["psyker"],
	"atlantic": ["scholar"],
}

## Which rescue character (if any) should spawn as this run's landmark for `map_id`. "" means this map
## has no rescue landmark at all (e.g. "default"/"space") or its character is already rescued. Called
## once per run at spawn time; each map's *_ruin_layer.gd owns the actual spawning mechanics.
func rescue_candidate_for_map(map_id: String) -> String:
	var queue: Array = RESCUE_MAP_QUEUE.get(map_id, [])
	for char_id: String in queue:
		if not is_room_unlocked(String(RESCUE_CHARACTER_DEFS[char_id]["room"])):
			return char_id
	return ""

var blueprints: Array = []           # known def_ids (buyable in the shop)
var fragments_owned: Dictionary = {} # unique_id -> Array[int] of owned fragment indices
var crafted_uniques: Array = []      # unique_ids already assembled (one-time)
var passives: Dictionary = {}        # passive_id -> level (int)
var run_temp_uids: Array = []        # item uids dropped mid-run (lost = sold off at the next run start)
var loadout: Array = []              # arena_weapons kind strings picked for the next run (max MAX_WEAPONS)

# ── Run-scoped (2026-08-06, on request) — boss-salvage DISASSEMBLE picks this run, NOT YET permanent ──
# (Not saved: cleared by arena.gd's _ready() at every run start, same as run_temp_uids.) A DISASSEMBLE choice
# in arena_drop_ui.gd's salvage screen used to call unlock_blueprint() immediately — now it only stages the
# def_id here (stage_blueprint()); arena.gd's RUN OVER screen commits the whole list to `blueprints` via
# commit_pending_blueprints() IF the run ends in victory (boss defeated), or simply lets it lapse (never
# committed) if the ship is destroyed first — "picked up a blueprint but died before bringing it home", the
# same risk-of-loss framing as a rescue-landmark character (see RESCUE_CHARACTER_DEFS / run_rescue_collected).
var run_pending_blueprints: Array = []   # def_ids, in disassemble order (may repeat; de-duped on display)
var run_weapon_drop_seen: bool = false   # true once ANY boss-salvage weapon card was shown this run — lets
                                          # arena.gd tell "no boss fought" (suppress the line) apart from
                                          # "fought a boss, disassembled nothing" (show "no blueprint" line)

# Map Pack registry — hub's "Launch" flow opens a map-select panel over this list (see hub_screen.gd
# _build_mapselect). Every map is the SAME scene/arena.gd (same ship, weapons, HUD, dev-mode editors,
# enemy/wave systems) — only the terrain/background visuals and the creep spawn timeline differ per map_id
# (see arena.gd's map_id branch in _ready(), and arena_wave_director_v2.gd's _last_wave_cfg_path()). Add a
# new theme by dropping one more entry here + a matching background-builder branch in arena.gd.
## `name` is the player-facing display name (shown on the Hub Launch thumbnails, hub_screen.gd
## _build_mapselect) — NOT necessarily the map_id key. "default" keeps "Space" as its internal id (the
## original map, no rename history). The map once internally called "rubicon" was fully renamed to
## "electric" (folder, class names, group names, cfg filenames, map_id — everything) on request; no
## "rubicon" should remain anywhere in this codebase.
const MAP_DEFS := {
	"default": {"name": "Space", "desc": "The original space arena — asteroids, waves, weapons, bosses.", "scene": "res://scenes/arena.tscn"},
	"electric": {"name": "Electric", "desc": "Procedural blue-grass / dark-sand terrain under drifting parallax clouds, scattered trees — same ship/weapons/HUD/waves as Default, different spawn timeline.", "scene": "res://scenes/arena.tscn"},
	"volcanic": {"name": "Volcanic", "desc": "Procedural basalt-rock / ash terrain scarred by jagged cracks of flowing lava, under drifting ash clouds and rising embers — same ship/weapons/HUD/waves as Default, different spawn timeline.", "scene": "res://scenes/arena.tscn"},
	"atlantic": {"name": "Atlantic", "desc": "Deep-sea sunken-ruin seabed terrain scarred by a winding current channel, under rising bubble columns and spiraling whirlpools — same ship/weapons/HUD/waves as Default, different spawn timeline.", "scene": "res://scenes/arena.tscn"},
	"mechanic": {"name": "Mechanic", "desc": "Procedural blue-grass / dark-sand terrain woven from 7 canopy photos under drifting parallax clouds — same ship/weapons/HUD/waves as Default, different spawn timeline.", "scene": "res://scenes/arena.tscn"},
	"arctic": {"name": "Arctic", "desc": "Icy blue-white / frost terrain woven from canopy photos (auto-blended, however many are on hand) under drifting parallax clouds and rising energy-beam vents — same ship/weapons/HUD/waves as Default, different spawn timeline.", "scene": "res://scenes/arena.tscn"},
}
var selected_map_id: String = "default"   # last map picked in the Launch panel (not persisted — resets each session)

func _ready() -> void:
	load_meta()
	_seed_starter_blueprints()
	if GameManager.has_signal("boss_defeated") and not GameManager.boss_defeated.is_connected(_on_boss_defeated):
		GameManager.boss_defeated.connect(_on_boss_defeated)

## Codex Lock unlock condition: "defeat your first boss" — boss_defeated fires on EVERY boss kill, but
## unlock_room() is idempotent, so this only actually does anything (save + notify) the first time.
func _on_boss_defeated() -> void:
	unlock_room("codex")

# ── Blueprints / shop ────────────────────────────────────────────────────────────
## Grant ONLY gatling_gun as a starting blueprint (user feedback: "trong kho (equipment) chỉ có vũ khí cơ bản
## là gatling gun... Mechanic cũng reset, chưa có vũ khí gì để mua" — a fresh profile's shop should be
## effectively empty, not pre-stocked with every common/uncommon weapon). Every other blueprint is earned by
## disassembling boss drops (Phase 3) — see arena_drop_ui.gd, now including Electric's temple landmark boss.
func _seed_starter_blueprints() -> void:
	if not blueprints.has(InventoryManager.STARTER_WEAPON_ID):
		blueprints.append(InventoryManager.STARTER_WEAPON_ID)
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

## Boss-salvage DISASSEMBLE choice (arena_drop_ui.gd) — stage `def_id` instead of unlocking it outright; see
## run_pending_blueprints' own doc comment above. Duplicates allowed (disassembling the same weapon twice in
## one run just shows twice on the RUN OVER report — harmless, commit_pending_blueprints() below is
## idempotent per entry either way).
func stage_blueprint(def_id: String) -> void:
	run_pending_blueprints.append(def_id)

## Called by arena.gd's _show_run_over ONLY when the run ends in victory — turns every staged DISASSEMBLE
## pick this run into a real, permanent blueprint. Left uncalled (the list just lapses, cleared at the next
## run's start) on a real death — that's the "picked up a blueprint but died before bringing it home" loss.
func commit_pending_blueprints() -> void:
	for def_id: String in run_pending_blueprints:
		unlock_blueprint(def_id)

func blueprint_price(def_id: String) -> int:
	var r := String(InventoryManager.get_def(def_id).get("rarity", "common"))
	return int(BLUEPRINT_PRICE.get(r, 100))

## Buy one clean copy of a weapon for coins → into the backpack. Returns true on success. Normally requires
## an already-known blueprint — EXCEPT the CHEST_POOL "starter tier" (gatling_gun/death_beam/arc/gauss),
## which is always buyable for coin alone (2026-08-05, on request): buying one of those with no blueprint yet
## also silently teaches it (unlock_blueprint), so it becomes pickable in the Loadout tab from then on.
func buy_weapon(def_id: String) -> bool:
	if not has_blueprint(def_id):
		if def_id in ArenaWeapons.CHEST_POOL:
			unlock_blueprint(def_id)
		else:
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
	# Equipment Lock unlock condition: buy any weapon other than the starter gatling_gun.
	if def_id != InventoryManager.STARTER_WEAPON_ID:
		unlock_room("equipment")
	return true

# ── Loadout (which unlocked arena_weapons kinds to bring into the next run) ──────────────────────
## Every kind the player can currently pick from: any kind whose WEAPON_INFO.def_id has a known blueprint or
## a crafted unique. (2026-08-05, on request: used to ALSO blanket-include arena_weapons.CHEST_POOL —
## gatling_gun/death_beam/arc/gauss — regardless of ownership, which is why "RESET PROFILE" appeared to leave
## 3 extra weapons equipped: they were never actually owned, just always shown as pickable. Fixed by requiring
## real ownership for ALL kinds, including CHEST_POOL ones — buy_weapon() lets those 4 be bought for coin
## alone with no blueprint prerequisite, so they're still trivially available, just not pre-unlocked for
## free. gatling_gun itself is unaffected in practice since it's a STARTER_ITEM, always in `blueprints`. The
## in-run start-of-run chest (arena_weapon_chest_ui.gd) reads CHEST_POOL directly and is untouched by this.
func unlocked_weapon_kinds() -> Array:
	var out: Array = []
	for kind: String in ArenaWeapons.WEAPON_INFO:
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

## Every ITEM_DEFS id carrying `tag`, for the Merchant's per-category tabs (Weapon/Hull/Thruster/Shield/Aux —
## 2026-08-05, on request). Craft-only uniques (fragments-assembled, see unique_ids()) are deliberately
## excluded from every category — they never appear in a coin-shop tab, only in Craft. An item can appear in
## more than one tab if it carries more than one tag (e.g. Ionizing Field is tagged both "weapon" and
## "shield").
func shop_ids_by_tag(tag: String) -> Array:
	var out: Array = []
	for id: String in InventoryManager.ITEM_DEFS:
		var d: Dictionary = InventoryManager.ITEM_DEFS[id]
		if bool(d.get("unique", false)):
			continue
		if (d.get("tags", []) as Array).has(tag):
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
## All unique weapon ids (fragment-crafted), in catalog order. Used to skip uniques with no icon art yet
## ("icon": "") — temporarily disconnected from Craft/Fragments/boss fragment drops until they had a sprite
## (2026-07-27). 2026-08-06, on request: that gate is OFF again — InventoryManager.get_icon() already falls
## back to a rarity-colored placeholder swatch for an empty "icon" (see its own _make_placeholder()), so an
## icon-less unique now shows fine (just with a swatch instead of real art) instead of being hidden outright.
## Swap the placeholder for real art later by just filling in ITEM_DEFS' "icon" field — no code change needed.
func unique_ids() -> Array:
	var out: Array = []
	for id: String in InventoryManager.ITEM_DEFS:
		var d: Dictionary = InventoryManager.ITEM_DEFS[id]
		if bool(d.get("unique", false)):
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

# ── Constructor room: Pilot Room upgrades (2026-08-06, on request) ──────────────────
# 2 one-time purchases that unlock the "pilot"/"pilot2" Dock rooms (both display as "Pilot" — see
# ROOM_UNLOCK_DEFS' own doc comment). Shown on the Constructor room panel (hub_screen.gd's
# _build_construction) as "Pilot Room (N/2)".
const PILOT_UPGRADE_ROOMS  := ["pilot", "pilot2"]
const PILOT_UPGRADE_PRICES := [3000, 5000]

## How many of the 2 Pilot Room upgrades are already bought (0/1/2).
func pilot_upgrade_level() -> int:
	var n := 0
	for room_id: String in PILOT_UPGRADE_ROOMS:
		if not is_room_unlocked(room_id):
			break
		n += 1
	return n

## Coin cost of the NEXT Pilot Room upgrade, or -1 once both are bought.
func pilot_upgrade_price() -> int:
	var lvl := pilot_upgrade_level()
	return PILOT_UPGRADE_PRICES[lvl] if lvl < PILOT_UPGRADE_PRICES.size() else -1

func buy_pilot_upgrade() -> bool:
	var lvl := pilot_upgrade_level()
	if lvl >= PILOT_UPGRADE_PRICES.size():
		return false
	if not GameManager.spend_money(PILOT_UPGRADE_PRICES[lvl]):
		return false
	unlock_room(PILOT_UPGRADE_ROOMS[lvl])   # already saves + emits meta_changed
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

## Public: wipes this manager's own [meta] slice of the profile back to a fresh-start state — blueprints,
## fragments, crafted uniques, passive levels, and loadout — then reseeds the single starter blueprint
## (gatling_gun). Part of Settings' "Reset Profile" action (see settings_panel.gd); GameManager.reset_profile()/
## InventoryManager.reset_profile() handle their own slices.
func reset_profile() -> void:
	blueprints = []
	fragments_owned = {}
	crafted_uniques = []
	passives = {}
	run_temp_uids = []
	loadout = []
	room_unlocks = {}
	_seed_starter_blueprints()   # re-adds just gatling_gun + saves
	save_meta()
	meta_changed.emit()

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
	cfg.set_value("meta", "room_unlocks", room_unlocks)
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
	room_unlocks = cfg.get_value("meta", "room_unlocks", {})
