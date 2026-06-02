extends Node

signal weapon_purchased(weapon_id: String, side: String)
signal weapons_reset
signal catalog_updated

const SAVE_PATH := "user://save.cfg"

const WEAPON_CATALOG: Dictionary = {
	"gun": {
		"desc": "Standard kinetic blaster. Balanced fire rate and damage. Your reliable starter weapon.",
		"base_cost": {"metal": 10, "nonmetal": 7, "organic": 3, "liquid": 2},
		"mult": [1.0, 2.5, 4.5],
	},
	"turret": {
		"desc": "Auto-tracking defense turret. Locks onto targets and intercepts incoming bogeys within a limited firing arc.",
		"base_cost": {"metal": 50, "nonmetal": 35, "organic": 15, "liquid": 10},
		"mult": [1.0, 2.5, 4.5],
	},
	"lightning_emitter": {
		"center": true,
		"desc": "Emits chain lightning that arcs between nearby foes. No aiming required. Excellent for crowd control and clearing swarms.",
		"base_cost": {"metal": 200, "nonmetal": 140, "organic": 60, "liquid": 40},
		"mult": [1.0, 2.5, 4.5],
	},
	"wing": {
		"desc": "Core chassis module. Deals no damage, but provides auxiliary energy and structural support. Required to mount heavy weaponry.",
		"base_cost": {"metal": 1000, "nonmetal": 700, "organic": 300, "liquid": 200},
		"mult": [1.0, 2.5, 4.5],
	},
	"railgun": {
		"requires": "wing",
		"desc": "Hyper-velocity armor-piercing cannon. Slow fire rate, but delivers devastating critical damage in a straight line. (Requires: Wing)",
		"base_cost": {"metal": 5000, "nonmetal": 3500, "organic": 1500, "liquid": 1000},
		"mult": [1.0, 2.5, 4.5],
	},
	"left_canon_heavy_bolt": {
		"name": "Heavy Canon",
		"desc": "Lobs heavy, compressed energy bolts. High recoil and slow projectile speed, but triggers massive AoE explosions upon impact.",
		"base_cost": {"metal": 25000, "nonmetal": 17500, "organic": 7500, "liquid": 5000},
		"mult": [1.0, 2.5, 4.5],
	},
	"plasma_gun": {
		"requires": "wing",
		"desc": "Spews superheated matter. Continuously melts enemy armor, dealing heavy Damage over Time (DoT). (Requires: Wing)",
		"base_cost": {"metal": 100000, "nonmetal": 70000, "organic": 30000, "liquid": 20000},
		"mult": [1.0, 2.5, 4.5],
	},
	"homing_missile": {
		"name": "Homing Missile",
		"requires": "wing",
		"desc": "Smart missile pods. Automatically locks on and relentlessly pursues agile targets with pinpoint accuracy. (Requires: Wing)",
		"base_cost": {"metal": 500000, "nonmetal": 350000, "organic": 150000, "liquid": 100000},
		"mult": [1.0, 2.5, 4.5],
	},
	"anti_matter_canon": {
		"center": true,
		"desc": "Annihilates molecular structures on contact. Overwhelming firepower. The ultimate conventional weapon for elite pilots.",
		"base_cost": {"metal": 2500000, "nonmetal": 1750000, "organic": 750000, "liquid": 500000},
		"mult": [1.0, 2.5, 4.5],
	},
	"omega_system": {
		"center": true,
		"desc": "Colossal energy core. Unleashes a devastating screen-clearing wave, wiping out all enemies and obstacles. The ultimate endgame weapon.",
		"base_cost": {"metal": 10000000, "nonmetal": 7000000, "organic": 3000000, "liquid": 2000000},
		"mult": [1.0, 2.5, 4.5],
	},
}

const KEY_ALIASES: Dictionary = {
	"homing_missle": "homing_missile",
}

func get_tier_cost(id: String, tier: int) -> Dictionary:
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	if entry.is_empty():
		return {}
	var base: Dictionary = entry.get("base_cost", {})
	var mults: Array = entry.get("mult", [1.0])
	var m: float = mults[mini(tier, mults.size() - 1)] if not mults.is_empty() else 1.0
	var result: Dictionary = {}
	for k: String in base:
		result[k] = ceili(float(base[k]) * m)
	return result

# Populated at runtime by sync_from_canvas() — not a const.
var WEAPONS: Dictionary = {}  # id -> {name, desc, tiers:[file...], side_only?}
var owned:        Dictionary = {}  # id -> {L:int, R:int}  (-1 = not purchased)
var damage_dealt: Dictionary = {}  # id -> float (tổng damage đã deal trong session)

# Canvas object refs: id -> {tier_int -> {side -> [EditableObjectNode, ...]}}
var _canvas_objs: Dictionary = {}

var ship_cx: float = 620.0  # horizontal center of spaceship in ObjectsContainer space

func _ready() -> void:
	pass  # Catalog built after layout loads via sync_from_canvas()

# ── Canvas scan ───────────────────────────────────────────────────────────────

## Called by edit_mode.gd after _load_layout() completes.
func sync_from_canvas(placed: Array) -> void:
	# Find spaceship horizontal center (fallback to viewport half)
	ship_cx = 720.0
	for o in placed:
		var eo := o as EditableObjectNode
		if eo == null or not is_instance_valid(eo):
			continue
		if _eo_basename(eo) == "spaceship":
			ship_cx = eo.global_position.x + eo.size.x * 0.5
			break

	# Collect raw data: group_key -> {display, tiers: {tier: {side: [objs]}}}
	var raw: Dictionary = {}
	for o in placed:
		var eo := o as EditableObjectNode
		if eo == null or not is_instance_valid(eo):
			continue
		var bn := _eo_basename(eo)
		if bn == "spaceship" or bn.is_empty():
			continue
		if eo.source_path.begins_with("res://__"):
			continue  # shelf markers

		var parsed := _parse_filename(bn)
		var resolved: String = KEY_ALIASES.get(parsed.key, parsed.key)
		var key: String = _find_or_add_group(resolved, parsed.display, raw)

		var t: int = parsed.tier
		var is_center: bool = WEAPON_CATALOG.get(key, {}).get("center", false)
		if not raw[key]["tiers"].has(t):
			raw[key]["tiers"][t] = {"C": []} if is_center else {"L": [], "R": []}
		var side: String
		if is_center:
			side = "C"
		else:
			var obj_cx: float = eo.global_position.x + eo.size.x * 0.5
			side = "L" if obj_cx <= ship_cx else "R"
		raw[key]["tiers"][t][side].append(eo)

	# Build final catalog from raw data
	var prev_owned := owned.duplicate(true)
	WEAPONS.clear()
	owned.clear()
	_canvas_objs.clear()

	for key in raw:
		var g: Dictionary    = raw[key]
		var td: Dictionary   = g["tiers"]
		if td.is_empty():
			continue

		var t_sorted: Array = td.keys()
		t_sorted.sort()

		var has_L := false
		var has_R := false
		var tier_files: Array[String] = []

		var is_center_w: bool = WEAPON_CATALOG.get(key, {}).get("center", false)
		var has_C := false
		for t in t_sorted:
			var slot: Dictionary = td[t]
			var l_objs: Array = slot.get("L", [])
			var r_objs: Array = slot.get("R", [])
			var c_objs: Array = slot.get("C", [])
			has_L = has_L or not l_objs.is_empty()
			has_R = has_R or not r_objs.is_empty()
			has_C = has_C or not c_objs.is_empty()
			var rep: Array = l_objs if not l_objs.is_empty() else (r_objs if not r_objs.is_empty() else c_objs)
			if not rep.is_empty():
				var rep_eo := rep[0] as EditableObjectNode
				if rep_eo:
					tier_files.append(rep_eo.source_path.get_file())

		if tier_files.is_empty():
			continue

		var cat_entry: Dictionary = WEAPON_CATALOG.get(key, {})
		var display_name: String = cat_entry.get("name", g["display"])
		WEAPONS[key] = {"name": display_name, "desc": cat_entry.get("desc", ""), "tiers": tier_files}
		var side_only := ""
		if is_center_w or has_C:
			side_only = "C"
		elif has_L and not has_R:
			side_only = "L"
		elif has_R and not has_L:
			side_only = "R"
		if side_only != "":
			WEAPONS[key]["side_only"] = side_only

		_canvas_objs[key] = td
		owned[key] = prev_owned.get(key, {"C": -1} if side_only == "C" else {"L": -1, "R": -1})

	load_game()
	_refresh_all_visibility()
	catalog_updated.emit()

# ── Queries ───────────────────────────────────────────────────────────────────

func get_all_objects(id: String) -> Array:
	var result: Array = []
	var td: Dictionary = _canvas_objs.get(id, {})
	for t in td:
		for side in td[t]:
			for o in td[t][side]:
				var eo := o as EditableObjectNode
				if eo != null and is_instance_valid(eo):
					result.append(eo)
	return result

func get_active_objects(id: String) -> Array:
	var result: Array = []
	var td: Dictionary = _canvas_objs.get(id, {})
	for t in td:
		for side in td[t]:
			for o in td[t][side]:
				var eo := o as EditableObjectNode
				if eo != null and is_instance_valid(eo) and eo.visible:
					result.append(eo)
	return result

func get_active_positions(id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var td: Dictionary = _canvas_objs.get(id, {})
	for t in td:
		for side in td[t]:
			for o in td[t][side]:
				var eo := o as EditableObjectNode
				if eo != null and is_instance_valid(eo) and eo.visible:
					result.append(eo.global_position + eo.size / 2.0)
	return result

func get_tier(id: String, side: String) -> int:
	return owned.get(id, {}).get(side, -1)

func is_tier_available(id: String, tier: int) -> bool:
	if tier == 0:
		return true
	var data: Dictionary = WEAPONS.get(id, {})
	var side_only: String = data.get("side_only", "")
	if side_only != "":
		return get_tier(id, side_only) >= tier - 1
	return get_tier(id, "L") >= tier - 1 and get_tier(id, "R") >= tier - 1

func _is_required_purchased(requires: String) -> bool:
	if requires.is_empty():
		return true
	if WEAPON_CATALOG.get(requires, {}).get("center", false):
		return get_tier(requires, "C") >= 0
	return maxi(get_tier(requires, "L"), get_tier(requires, "R")) >= 0

func can_purchase(id: String, side: String) -> bool:
	var data: Dictionary = WEAPONS.get(id, {})
	if data.is_empty():
		return false
	var side_only: String = data.get("side_only", "")
	if side_only != "" and side != side_only:
		return false
	var next: int = get_tier(id, side) + 1
	if next >= (data["tiers"] as Array).size():
		return false
	if not is_tier_available(id, next):
		return false
	if not _is_required_purchased(WEAPON_CATALOG.get(id, {}).get("requires", "")):
		return false
	var cost := get_tier_cost(id, next)
	if not cost.is_empty():
		if MaterialManager.metal    < cost.get("metal",    0) or \
		   MaterialManager.nonmetal < cost.get("nonmetal", 0) or \
		   MaterialManager.organic  < cost.get("organic",  0) or \
		   MaterialManager.liquid   < cost.get("liquid",   0):
			return false
	return true

func purchase(id: String, side: String) -> bool:
	if not can_purchase(id, side):
		return false
	var next: int = get_tier(id, side) + 1
	var cost := get_tier_cost(id, next)
	if not cost.is_empty():
		MaterialManager.spend("metal",    cost.get("metal",    0))
		MaterialManager.spend("nonmetal", cost.get("nonmetal", 0))
		MaterialManager.spend("organic",  cost.get("organic",  0))
		MaterialManager.spend("liquid",   cost.get("liquid",   0))
	owned[id][side] += 1
	_refresh_visibility(id)
	save_game()
	weapon_purchased.emit(id, side)
	return true

# ── Visibility ────────────────────────────────────────────────────────────────

func _refresh_all_visibility() -> void:
	for id in _canvas_objs:
		_refresh_visibility(id)

func _refresh_visibility(id: String) -> void:
	var td: Dictionary = _canvas_objs.get(id, {})
	for t in td:
		for side in td[t]:
			var active: bool = get_tier(id, side) == int(t)
			for o in td[t][side]:
				var eo := o as EditableObjectNode
				if eo != null and is_instance_valid(eo):
					eo.layer_visible = active
					eo.visible       = active

# ── Filename parsing helpers ──────────────────────────────────────────────────

func _eo_basename(eo: EditableObjectNode) -> String:
	return eo.source_path.get_file().get_basename().to_lower()

func _parse_filename(lower_name: String) -> Dictionary:
	var tier := 0
	var base := lower_name
	var mk_pos: int = lower_name.rfind(" mk")
	if mk_pos >= 0:
		var suffix: String = lower_name.substr(mk_pos + 3)
		if suffix in ["2", "ii"]:
			tier = 1; base = lower_name.substr(0, mk_pos).strip_edges()
		elif suffix in ["3", "iii"]:
			tier = 2; base = lower_name.substr(0, mk_pos).strip_edges()
	var key     := base.replace(" ", "_").replace("-", "_")
	var display := base.capitalize()
	return {"key": key, "display": display, "tier": tier}

## Return an existing group key if it fuzzy-matches `key`, else return `key` and
## register a new group in `raw`.
func _find_or_add_group(key: String, display: String, raw: Dictionary) -> String:
	if raw.has(key):
		return key
	# Fuzzy: share first 7 chars (handles "missle" vs "missile", etc.)
	for k in raw:
		var ml := mini(key.length(), k.length())
		if ml >= 7 and key.substr(0, ml) == k.substr(0, ml):
			return k
	raw[key] = {"display": display, "tiers": {}}
	return key

# ── Persistence ───────────────────────────────────────────────────────────────

func record_damage(id: String, amount: float) -> void:
	damage_dealt[id] = damage_dealt.get(id, 0.0) + amount

func reset_all() -> void:
	for id in owned:
		var is_center: bool = WEAPON_CATALOG.get(id, {}).get("center", false)
		owned[id] = {"C": -1} if is_center else {"L": -1, "R": -1}
	damage_dealt.clear()
	_refresh_all_visibility()
	save_game()
	weapons_reset.emit()

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.erase_section("weapons")
	for id: String in owned:
		for side: String in owned[id]:
			cfg.set_value("weapons", id + "_" + side, owned[id][side])
	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id: String in owned:
		for side: String in owned[id]:
			owned[id][side] = cfg.get_value("weapons", id + "_" + side, -1)
