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

# Backpack grid size (columns × rows), Diablo-2 style.
const BACKPACK_COLS := 10
const BACKPACK_ROWS := 6

# The 10 physical equip slots.
const EQUIP_SLOTS: Array[String] = [
	"primary_weapon", "secondary_weapon", "thruster", "command_bridge", "hull",
	"energy_core", "radar", "drone_1", "drone_2", "wings",
]

# What each physical slot accepts, by item tag (see ITEM_DEFS "tags").
#   "any"     = item fits if it has AT LEAST ONE of these tags
#   "exclude" = item is rejected if it has ANY of these tags (takes priority)
# So Primary takes weapons but never shields; Secondary takes weapons OR shields;
# a shield (incl. the weapon+shield Ionizing Field) is therefore secondary-only.
# drone_1 / drone_2 both take the generic "drone" tag, so any drone fits either.
const SLOT_RULES: Dictionary = {
	"primary_weapon":   {"any": ["weapon"],           "exclude": ["shield"]},
	"secondary_weapon": {"any": ["weapon", "shield"], "exclude": []},
	"thruster":         {"any": ["thruster"],         "exclude": []},
	"command_bridge":   {"any": ["command_bridge"],   "exclude": []},
	"hull":             {"any": ["hull"],             "exclude": []},
	"energy_core":      {"any": ["energy_core"],      "exclude": []},
	"radar":            {"any": ["radar"],            "exclude": []},
	"drone_1":          {"any": ["drone"],            "exclude": []},
	"drone_2":          {"any": ["drone"],            "exclude": []},
	"wings":            {"any": ["wings"],            "exclude": []},
}

# Placeholder icon colour per rarity (used until real art is added).
const RARITY_COLORS: Dictionary = {
	"common":    Color(0.62, 0.66, 0.72),
	"rare":      Color(0.30, 0.55, 0.95),
	"epic":      Color(0.65, 0.35, 0.90),
	"legendary": Color(0.95, 0.60, 0.20),
}

# Asteroid loot drop weights per rarity. Pool total / LOOT_DENOM ≈ base drop chance.
# With the 4 current items the base chance is roughly 5.7 % per destroyed asteroid.
# Rare items are ~3× less likely than common; epic ~10× less likely than common.
const RARITY_LOOT_WEIGHTS: Dictionary = {
	"common":    40,
	"rare":      12,
	"epic":       4,
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
	"gauss_cannon": {
		"name": "Gauss Cannon",
		"icon": "",  # TODO final art → "res://assets/inventory/gauss_cannon.png"
		"size": Vector2i(3, 2),
		"tags": ["weapon"],
		"fire_mode": "charge",   # hold to charge (up to cooldown_sec); damage scales with charge
		"rarity": "rare",
		"desc": "Charge up, then fire a big chunk of metal at a target. Heavy single-target burst — slow cadence, big hit.",
		"stats": {
			"damage": 110,
			"cooldown_sec": 1.5,   # full charge time; damage scales linearly up to this
			"weight": 8,
			"energy_per_shot": 10,
		},
	},
	"ionizing_field": {
		"name": "Ionizing Field",
		"icon": "",  # TODO final art → "res://assets/inventory/ionizing_field.png"
		"size": Vector2i(2, 2),
		"tags": ["weapon", "shield"],
		"fire_mode": "aura",   # always-on while equipped; damages everything within radius_px each tick
		"rarity": "epic",
		"desc": "An electric area-effect aura around the ship. Always-on while equipped; damages every enemy within a radius each tick.",
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
		"icon": "",  # TODO final art → "res://assets/inventory/gatling_gun.png"
		"size": Vector2i(3, 1),
		"tags": ["weapon"],
		"fire_mode": "repeat",   # hold to keep firing every cooldown_sec
		"rarity": "common",
		"desc": "Fires fast; hold to keep firing. The baseline rapid-fire weapon — light, cheap, reliable sustained fire.",
		"stats": {
			"damage": 8,
			"cooldown_sec": 0.12,
			"weight": 4,
			"energy_per_sec": 6,
		},
	},
	"shield_generator": {
		"name": "Shield Generator",
		"icon": "",  # TODO final art → "res://assets/inventory/shield_generator.png"
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
}

# Items granted automatically the FIRST time a save is created (new game only).
# Keeping this separate from ITEM_DEFS means future items (e.g. asteroid drops in
# Phase 4) can be defined without being auto-placed in the backpack.
const STARTER_ITEMS: Array[String] = ["gauss_cannon", "shield_generator", "gatling_gun"]

# ── Runtime state ─────────────────────────────────────────────────────────────
# _items: uid(int) -> {"def": String, "where": String, "cell": Vector2i}
#   where = "backpack" or one of EQUIP_SLOTS; cell = backpack origin (col, row).
var _items: Dictionary = {}
var _next_uid: int = 1
var _icon_cache: Dictionary = {}

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

## Roll for an item drop when an asteroid is destroyed.
## Adds the item to the backpack and returns its def_id, or "" if nothing dropped.
## Callers can use the returned id to show a visual notification.
func roll_asteroid_drop() -> String:
	# Build the weighted pool from the current ITEM_DEFS.
	var pool_weight: int = 0
	for id: String in ITEM_DEFS:
		var r := String(ITEM_DEFS[id].get("rarity", "common"))
		pool_weight += int(RARITY_LOOT_WEIGHTS.get(r, 0))
	# pool_weight / LOOT_DENOM = base drop probability per asteroid.
	if randf_range(0.0, float(LOOT_DENOM)) > float(pool_weight):
		return ""
	# Pick an item proportionally by rarity weight.
	var pick: float = randf() * float(pool_weight)
	var cum: float = 0.0
	for id: String in ITEM_DEFS:
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

# ── Persistence (shared user://save.cfg, section [inventory]) ───────────────────

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # preserve [weapons] / [defense] written by other managers
	if cfg.has_section("inventory"):
		cfg.erase_section("inventory")
	cfg.set_value("inventory", "next_uid", _next_uid)
	var arr: Array = []
	for uid: int in _items:
		var it: Dictionary = _items[uid]
		arr.append({"uid": uid, "def": it["def"], "where": it["where"], "cell": it["cell"]})
	cfg.set_value("inventory", "items", arr)
	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SAVE_PATH)
	if loaded != OK or not cfg.has_section("inventory"):
		_seed_starter_items()
		return
	_items.clear()
	_next_uid = int(cfg.get_value("inventory", "next_uid", 1))
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
		}
	inventory_changed.emit()

## First run only (no [inventory] in the save): grant the STARTER_ITEMS. Once a
## save exists this never runs again — so it won't re-add items every load, and
## won't restore items a player deliberately got rid of.
func _seed_starter_items() -> void:
	_items.clear()
	_next_uid = 1
	for def_id: String in STARTER_ITEMS:
		add_to_backpack(def_id)
	save_game()
