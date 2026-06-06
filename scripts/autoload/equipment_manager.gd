extends Node

signal item_purchased(id: String)
signal items_reset

const SAVE_PATH := "user://save.cfg"

# Static data — price in Cash ($), targets = upgrade IDs, multiplier applied to their VpS/CpS.
# global_vps:true items multiply the entire Total VpS instead of specific tools.
const ITEMS: Dictionary = {
	"monitor": {
		"name": "Navigation Screen",
		"icon": "monitor.png",
		"price_type": "metal",
		"price": 150.0,
		"targets": ["solar_panel"],
		"multiplier": 2.0,
		"desc": "×2 passive Liquid production for Solar Panel"
	},
	"monitor2": {
		"name": "Sensor Display",
		"icon": "monitor2.png",
		"price_type": "nonmetal",
		"price": 400.0,
		"targets": ["mining_drone"],
		"multiplier": 2.0,
		"desc": "×2 passive Metal production for Mining Drone"
	},
	"micro": {
		"name": "Signal Booster",
		"icon": "Micro.png",
		"price_type": "liquid",
		"price": 900.0,
		"targets": ["solar_panel", "mining_drone"],
		"multiplier": 1.5,
		"desc": "×1.5 production for Solar Panel & Mining Drone"
	},
	"monitor3": {
		"name": "Targeting Array",
		"icon": "monitor3.png",
		"price_type": "metal",
		"price": 3000.0,
		"targets": ["asteroid_harvester"],
		"multiplier": 2.0,
		"desc": "×2 passive Nonmetal production for Asteroid Harvester"
	},
	"headphone": {
		"name": "Comm Amplifier",
		"icon": "Headphone.png",
		"price_type": "organic",
		"price": 12000.0,
		"targets": ["asteroid_harvester", "dark_matter_extractor"],
		"multiplier": 1.5,
		"desc": "×1.5 production for Asteroid Harvester & Dark Matter Extractor"
	},
	"monitor4": {
		"name": "Deep Scanner",
		"icon": "monitor4.png",
		"price_type": "nonmetal",
		"price": 25000.0,
		"targets": ["dark_matter_extractor"],
		"multiplier": 2.5,
		"desc": "×2.5 passive Organic production for Dark Matter Extractor"
	},
	"led": {
		"name": "Plasma Grid",
		"icon": "led.png",
		"price_type": "organic",
		"price": 85000.0,
		"targets": [],
		"multiplier": 1.1,
		"global_vps": true,
		"desc": "×1.10 to Total passive production (global)"
	},
	"2ndpc": {
		"name": "Co-Processor",
		"icon": "2ndpc.png",
		"price_type": "liquid",
		"price": 250000.0,
		"targets": ["nebula_harvester"],
		"multiplier": 3.0,
		"desc": "×3 passive Liquid production for Nebula Harvester"
	},
	"goku": {
		"name": "Warp Coil",
		"icon": "Goku.png",
		"price_type": "metal",
		"price": 1500000.0,
		"targets": ["nebula_harvester", "stellar_forge"],
		"multiplier": 2.0,
		"desc": "×2 production for Nebula Harvester & Stellar Forge"
	},
	"3rdpc": {
		"name": "Fusion Core",
		"icon": "3rdpc.png",
		"price_type": "nonmetal",
		"price": 6000000.0,
		"targets": ["stellar_forge", "quantum_synthesizer"],
		"multiplier": 3.0,
		"desc": "×3 passive production for Stellar Forge & Quantum Synthesizer"
	},
	"vegeta": {
		"name": "Void Resonator",
		"icon": "Vegeta.png",
		"price_type": "organic",
		"price": 45000000.0,
		"targets": ["quantum_synthesizer", "galactic_fuel_web"],
		"multiplier": 2.0,
		"desc": "×2 production for Quantum Synthesizer & Galactic Fuel Web"
	},
	"moon": {
		"name": "Dyson Module",
		"icon": "moon.png",
		"price_type": "liquid",
		"price": 250000000.0,
		"targets": ["galactic_fuel_web"],
		"multiplier": 4.0,
		"desc": "×4 passive Liquid production for Galactic Fuel Web"
	},
}

var _owned: Dictionary = {}

func _ready() -> void:
	_load_save()

func try_purchase(id: String) -> bool:
	if not ITEMS.has(id):
		return false
	if _owned.get(id, 0) >= 1:
		return false
	var price := int(ITEMS[id]["price"])
	var price_type: String = ITEMS[id].get("price_type", "metal")
	if not MaterialManager.spend(price_type, price):
		return false
	_owned[id] = 1
	MaterialManager.save_game()
	save_game()
	item_purchased.emit(id)
	UpgradeManager.recalculate_all_rates()
	return true

func get_owned(id: String) -> int:
	return _owned.get(id, 0)

# Returns the combined multiplier that owned equipment applies to a specific upgrade_id.
func get_multiplier_for_upgrade(upgrade_id: String) -> float:
	var mult := 1.0
	for id in ITEMS:
		if _owned.get(id, 0) < 1:
			continue
		var data: Dictionary = ITEMS[id]
		if data.get("global_vps", false):
			continue
		var targets: Array = data.get("targets", [])
		if upgrade_id in targets:
			mult *= float(data["multiplier"])
	return mult

# Led-style global multiplier applied to the final Total VpS after per-tool multipliers.
func get_global_vps_multiplier() -> float:
	if _owned.get("led", 0) >= 1:
		return float(ITEMS["led"]["multiplier"])
	return 1.0

func reset_all() -> void:
	_owned.clear()
	save_game()
	items_reset.emit()
	UpgradeManager.recalculate_all_rates()

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.erase_section("equipment")
	for id in _owned:
		cfg.set_value("equipment", id, _owned[id])
	cfg.save(SAVE_PATH)

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section("equipment"):
		return
	for id in cfg.get_section_keys("equipment"):
		if ITEMS.has(id):
			_owned[id] = cfg.get_value("equipment", id, 0)
