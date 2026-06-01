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
		"price": 150.0,
		"targets": ["solar_panel"],
		"multiplier": 2.0,
		"desc": "×2 FPS for Solar Panel"
	},
	"monitor2": {
		"name": "Sensor Display",
		"icon": "monitor2.png",
		"price": 400.0,
		"targets": ["mining_drone"],
		"multiplier": 2.0,
		"desc": "×2 FPS for Mining Drone"
	},
	"micro": {
		"name": "Signal Booster",
		"icon": "Micro.png",
		"price": 900.0,
		"targets": ["comm_relay", "signal_filter"],
		"multiplier": 3.0,
		"desc": "×3 Scan/s for Comm Relay & Signal Filter"
	},
	"monitor3": {
		"name": "Targeting Array",
		"icon": "monitor3.png",
		"price": 3000.0,
		"targets": ["asteroid_harvester"],
		"multiplier": 2.0,
		"desc": "×2 FPS for Asteroid Harvester"
	},
	"headphone": {
		"name": "Comm Amplifier",
		"icon": "Headphone.png",
		"price": 12000.0,
		"targets": ["scanner_array", "sensor_grid"],
		"multiplier": 2.5,
		"desc": "×2.5 Scan/s for Scanner Array & Sensor Grid"
	},
	"monitor4": {
		"name": "Deep Scanner",
		"icon": "monitor4.png",
		"price": 25000.0,
		"targets": ["dark_matter_extractor"],
		"multiplier": 2.5,
		"desc": "×2.5 FPS for Dark Matter Extractor"
	},
	"led": {
		"name": "Plasma Grid",
		"icon": "led.png",
		"price": 85000.0,
		"targets": [],
		"multiplier": 1.1,
		"global_vps": true,
		"desc": "×1.10 to Total FPS (global)"
	},
	"2ndpc": {
		"name": "Co-Processor",
		"icon": "2ndpc.png",
		"price": 250000.0,
		"targets": ["nebula_harvester"],
		"multiplier": 3.0,
		"desc": "×3 FPS for Nebula Harvester"
	},
	"goku": {
		"name": "Warp Coil",
		"icon": "Goku.png",
		"price": 1500000.0,
		"targets": ["deep_space_array"],
		"multiplier": 2.0,
		"desc": "×2 Scan/s for Deep Space Array"
	},
	"3rdpc": {
		"name": "Fusion Core",
		"icon": "3rdpc.png",
		"price": 6000000.0,
		"targets": ["stellar_forge", "quantum_synthesizer"],
		"multiplier": 3.0,
		"desc": "×3 FPS for Stellar Forge & Quantum Synthesizer"
	},
	"vegeta": {
		"name": "Void Resonator",
		"icon": "Vegeta.png",
		"price": 45000000.0,
		"targets": ["galactic_sensor_web"],
		"multiplier": 2.0,
		"desc": "×2 Scan/s for Galactic Sensor Web"
	},
	"moon": {
		"name": "Dyson Module",
		"icon": "moon.png",
		"price": 250000000.0,
		"targets": ["galactic_fuel_web"],
		"multiplier": 4.0,
		"desc": "×4 FPS for Galactic Fuel Web"
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
	var price := float(ITEMS[id]["price"])
	if not GameManager.spend_cash(price):
		return false
	_owned[id] = 1
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
