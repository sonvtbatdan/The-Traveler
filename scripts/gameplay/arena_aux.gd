extends Node
## Arena auxiliary (passive) items — the second item class alongside weapons (arena_weapons.gd). Each aux
## item grants a flat run-stat bonus routed into GameManager's upg_* store, and can be leveled up (1..MAX_AUX_LEVEL)
## from the level-up screen; each level re-applies its per-level effect once. No firing logic and no art yet —
## the level-up UI + the aux slot HUD draw a placeholder COLOR per item.
##
## Pure data layer: owns no visuals. Added to group "arena_aux" so the level-up UI and the slot HUD can find it.
## Per-run state lives only here (a fresh node each run) + GameManager.upg_* (zeroed by reset_run), so each run
## starts clean.

const MAX_AUX       := 5    # aux slot count (second HUD row) / acquisition cap
const MAX_AUX_LEVEL := 5    # per-item level cap

# ── AUX CATALOG ──────────────────────────────────────────────────────────────────
# id        — unique key (also the effect dispatcher key in _apply_effect)
# name      — display name
# color     — placeholder swatch (no art yet) for cards + slots
# weight    — spawn weight in the level-up roll (rarer effects → lower weight)
# effect    — short per-level description for the card
const AUX_DEFS := [
	{"id": "hp",          "name": "Reinforcement Plate", "color": Color(0.40, 0.85, 0.45), "weight": 100, "effect": "+20 Max HP"},
	{"id": "regen",       "name": "Nanobots",            "color": Color(0.45, 0.90, 0.70), "weight": 80,  "effect": "+0.5 HP/s"},
	{"id": "armor",       "name": "Exoskeleton",         "color": Color(0.55, 0.62, 0.70), "weight": 80,  "effect": "+2 Armor"},
	{"id": "speed",       "name": "Fins",                "color": Color(0.45, 0.75, 1.00), "weight": 90,  "effect": "+6% Speed"},
	{"id": "damage",      "name": "Accelerated Muzzle",  "color": Color(1.00, 0.45, 0.35), "weight": 70,  "effect": "+10% Damage"},
	{"id": "fire_rate",   "name": "Auto-Loader",         "color": Color(1.00, 0.65, 0.30), "weight": 70,  "effect": "+8% Fire Rate"},
	{"id": "pierce",      "name": "Penetrator Rounds",   "color": Color(0.90, 0.80, 0.40), "weight": 40,  "effect": "+1 Pierce"},
	{"id": "aoe",         "name": "Explosivo",           "color": Color(1.00, 0.55, 0.20), "weight": 40,  "effect": "+25 AoE"},
	{"id": "pickup",      "name": "Magnet",              "color": Color(0.55, 0.85, 0.95), "weight": 90,  "effect": "+15% Pickup"},
	{"id": "xp",          "name": "Data Harvester",      "color": Color(0.65, 0.55, 1.00), "weight": 60,  "effect": "+10% EXP"},
	{"id": "spawn",       "name": "Beacon",              "color": Color(0.85, 0.40, 0.55), "weight": 30,  "effect": "+15% Spawns"},
	{"id": "retaliation", "name": "Barbed Wire",         "color": Color(0.80, 0.35, 0.30), "weight": 40,  "effect": "+5 Retaliation"},
	{"id": "revival",     "name": "Backup Image",        "color": Color(1.00, 0.85, 0.35), "weight": 10,  "effect": "+1 Revive"},
	{"id": "coin",        "name": "Credit Extractor",    "color": Color(1.00, 0.90, 0.45), "weight": 60,  "effect": "+25% Coin"},
]

var _owned: Dictionary = {}   # id → level (1..MAX_AUX_LEVEL)
var _order: Array = []        # acquisition order (stable slot order for the HUD)
var _by_id: Dictionary = {}   # id → def dict (built in _ready)

func _ready() -> void:
	add_to_group("arena_aux")
	for d: Dictionary in AUX_DEFS:
		_by_id[String(d["id"])] = d

# ── Acquisition / leveling ────────────────────────────────────────────────────────
## Acquire a NEW aux item (level 1) and apply its effect once. No-op if already owned or slots are full.
func acquire_aux(id: String) -> bool:
	if id in _owned or not _by_id.has(id):
		return false
	if aux_slots_full():
		return false
	_owned[id] = 1
	_order.append(id)
	_apply_effect(id)
	return true

## Raise an owned aux item's level by one (capped) and re-apply its per-level effect. No-op otherwise.
func level_up_aux(id: String) -> void:
	if not (id in _owned):
		return
	if int(_owned[id]) >= MAX_AUX_LEVEL:
		return
	_owned[id] = int(_owned[id]) + 1
	_apply_effect(id)

# ── Queries (level-up UI + slot HUD) ───────────────────────────────────────────────
func aux_level(id: String) -> int:
	return int(_owned.get(id, 0))

func aux_can_upgrade(id: String) -> bool:
	return id in _owned and int(_owned[id]) < MAX_AUX_LEVEL

func aux_slots_full() -> bool:
	return _owned.size() >= MAX_AUX

## Ordered owned ids (acquisition order) — read by the slot HUD.
func owned_aux() -> Array:
	return _order.duplicate()

func def_for(id: String) -> Dictionary:
	return _by_id.get(id, {})

# ── Effect dispatch ────────────────────────────────────────────────────────────────
## Apply ONE level's worth of `id`'s effect to GameManager. Called once per acquire + once per level-up,
## so the run-stat store accumulates naturally across levels.
func _apply_effect(id: String) -> void:
	match id:
		"hp":          GameManager.add_max_hp(20)
		"regen":       GameManager.add_hp_regen(0.5)
		"armor":       GameManager.add_base_defense(2)
		"speed":       GameManager.add_move_speed(0.06)
		"damage":      GameManager.add_damage(0.10)
		"fire_rate":   GameManager.add_fire_rate(0.08)
		"pierce":      GameManager.add_mech("pierce", 1)
		"aoe":         GameManager.add_mech("radius", 25)
		"pickup":      GameManager.add_pickup_radius(0.15)
		"xp":          GameManager.add_xp_gain(0.10)
		"spawn":       GameManager.add_spawn_rate(0.15)
		"retaliation": GameManager.add_retaliation(5.0)
		"revival":     GameManager.add_rebirth(1)
		"coin":        GameManager.add_coin_mult(0.25)
