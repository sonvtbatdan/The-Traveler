extends Node

signal upgrade_purchased(upgrade_id: String)
signal upgrades_reset

var owned: Dictionary = {}

const UPGRADES := {
	"solar_panel": {
		"name": "Solar Panel",
		"icon": "fan.png",
		"cost": 100.0,
		"tab": "weaponry",
		"vps": 2.0,
		"desc": "Harness the nearest star's light for free energy."
	},
	"mining_drone": {
		"name": "Mining Drone",
		"icon": "collab.png",
		"cost": 1500.0,
		"tab": "weaponry",
		"vps": 35.0,
		"desc": "Send drones to harvest asteroid field resources."
	},
	"asteroid_harvester": {
		"name": "Asteroid Harvester",
		"icon": "publisher.png",
		"cost": 25000.0,
		"tab": "weaponry",
		"vps": 650.0,
		"desc": "A dedicated asteroid processing station."
	},
	"dark_matter_extractor": {
		"name": "Dark Matter Extractor",
		"icon": "troy.png",
		"cost": 400000.0,
		"tab": "weaponry",
		"vps": 12000.0,
		"desc": "Tap into the invisible mass of the universe."
	},
	"nebula_harvester": {
		"name": "Nebula Harvester",
		"icon": "sattelite.png",
		"cost": 8000000.0,
		"tab": "weaponry",
		"vps": 275000.0,
		"desc": "A colossal net that scoops fuel from nebula gas clouds."
	},
	"stellar_forge": {
		"name": "Stellar Forge",
		"icon": "camp.png",
		"cost": 200000000.0,
		"tab": "weaponry",
		"vps": 8000000.0,
		"desc": "A ring around a star that converts stellar plasma into fuel."
	},
	"quantum_synthesizer": {
		"name": "Quantum Synthesizer",
		"icon": "animal.png",
		"cost": 5000000000.0,
		"tab": "weaponry",
		"vps": 230000000.0,
		"desc": "Synthesizes exotic matter by bending quantum probability."
	},
	"galactic_fuel_web": {
		"name": "Galactic Fuel Web",
		"icon": "vats.png",
		"cost": 150000000000.0,
		"tab": "weaponry",
		"vps": 8500000000.0,
		"desc": "A network spanning the galaxy, converting starlight into fuel."
	},
}

const PRICE_SCALE := 1.15   # each new unit costs 15% more than the previous

# Reaction Factory state: virtual machines produced over time.
var _views_produced: Dictionary = {}   # id -> float, reset on reset_all

func _process(delta: float) -> void:
	for id in owned:
		if not UPGRADES.has(id):
			continue
		var data: Dictionary = UPGRADES[id]
		var n: int = owned.get(id, 0)
		if n <= 0:
			continue
		var mult: float = EquipmentManager.get_multiplier_for_upgrade(id)
		if data.has("vps"):
			_views_produced[id] = _views_produced.get(id, 0.0) + float(n) * float(data["vps"]) * mult * delta

func get_views_produced(id: String) -> float:
	return _views_produced.get(id, 0.0)

func get_virtual_machines() -> int:
	return 0

func recalculate_all_rates() -> void:
	GameManager.vps = 0.0
	for id in owned:
		if not UPGRADES.has(id):
			continue
		var data: Dictionary = UPGRADES[id]
		var n: int = owned.get(id, 0)
		if n <= 0:
			continue
		var mult: float = EquipmentManager.get_multiplier_for_upgrade(id)
		if data.has("vps"):
			GameManager.vps += float(n) * float(data["vps"]) * mult

func try_purchase(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	if not GameManager.spend_views(get_current_price(upgrade_id)):
		return false
	owned[upgrade_id] = owned.get(upgrade_id, 0) + 1
	recalculate_all_rates()
	save_game()
	emit_signal("upgrade_purchased", upgrade_id)
	return true

# Cost of the next purchase: baseprice * 1.15^(units_already_owned).
# Owning 0 units → first unit at baseprice; owning 1 → next at baseprice*1.15.
func get_current_price(upgrade_id: String) -> int:
	if not UPGRADES.has(upgrade_id):
		return 0
	var base: float = float(UPGRADES[upgrade_id]["cost"])
	var n: int = get_owned_count(upgrade_id)
	return int(ceil(base * pow(PRICE_SCALE, n)))

func _apply_upgrade(data: Dictionary) -> void:
	if data.has("vps"):
		GameManager.vps += float(data["vps"])

func get_owned_count(upgrade_id: String) -> int:
	return owned.get(upgrade_id, 0)

func can_afford(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	return GameManager.stable_views >= get_current_price(upgrade_id)

func reset_all() -> void:
	owned.clear()
	_views_produced.clear()
	recalculate_all_rates()
	save_game()
	upgrades_reset.emit()

func get_price(upgrade_id: String) -> float:
	if not UPGRADES.has(upgrade_id):
		return 0.0
	return UPGRADES[upgrade_id]["cost"]

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

const SAVE_PATH := "user://save.cfg"

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.erase_section("upgrades")
	for id in owned:
		cfg.set_value("upgrades", id, owned[id])
	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	GameManager.vps = 0.0
	owned.clear()
	if cfg.has_section("upgrades"):
		for key in cfg.get_section_keys("upgrades"):
			var count: int = cfg.get_value("upgrades", key, 0)
			if count > 0 and UPGRADES.has(key):
				owned[key] = count
	recalculate_all_rates()
