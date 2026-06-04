extends Node

signal upgrade_purchased(upgrade_id: String)
signal upgrades_reset

var owned: Dictionary = {}

const UPGRADES := {
	"solar_panel": {
		"name": "Solar Panel",
		"icon": "fan.png",
		"cost_type": "nonmetal",
		"cost": 100.0,
		"produces_type": "liquid",
		"mps": 2.0,
		"desc": "Harness the nearest star's light to refine liquid fuel."
	},
	"mining_drone": {
		"name": "Mining Drone",
		"icon": "collab.png",
		"cost_type": "liquid",
		"cost": 1500.0,
		"produces_type": "metal",
		"mps": 35.0,
		"desc": "Send drones to harvest asteroid field metal resources."
	},
	"asteroid_harvester": {
		"name": "Asteroid Harvester",
		"icon": "publisher.png",
		"cost_type": "metal",
		"cost": 25000.0,
		"produces_type": "nonmetal",
		"mps": 650.0,
		"desc": "A dedicated asteroid processing station to filter nonmetals."
	},
	"dark_matter_extractor": {
		"name": "Dark Matter Extractor",
		"icon": "troy.png",
		"cost_type": "nonmetal",
		"cost": 400000.0,
		"produces_type": "organic",
		"mps": 12000.0,
		"desc": "Tap into the invisible mass of the universe for biochemical organic matter."
	},
	"nebula_harvester": {
		"name": "Nebula Harvester",
		"icon": "sattelite.png",
		"cost_type": "liquid",
		"cost": 8000000.0,
		"produces_type": "liquid",
		"mps": 275000.0,
		"desc": "A colossal net that scoops liquid energy from nebula gas clouds."
	},
	"stellar_forge": {
		"name": "Stellar Forge",
		"icon": "camp.png",
		"cost_type": "metal",
		"cost": 200000000.0,
		"produces_type": "metal",
		"mps": 8000000.0,
		"desc": "A ring around a star that forge-crafts metal materials."
	},
	"quantum_synthesizer": {
		"name": "Quantum Synthesizer",
		"icon": "animal.png",
		"cost_type": "organic",
		"cost": 5000000000.0,
		"produces_type": "organic",
		"mps": 230000000.0,
		"desc": "Synthesizes organic compound matter by bending quantum probability."
	},
	"galactic_fuel_web": {
		"name": "Galactic Fuel Web",
		"icon": "vats.png",
		"cost_type": "nonmetal",
		"cost": 150000000000.0,
		"produces_type": "liquid",
		"mps": 8500000000.0,
		"desc": "A network spanning the galaxy, converting cosmic radiation into liquid fuel."
	},
}

const PRICE_SCALE := 1.15

# Passive production accumulators
var _metal_acc: float = 0.0
var _nonmetal_acc: float = 0.0
var _organic_acc: float = 0.0
var _liquid_acc: float = 0.0

# Stats for tooltip
var _views_produced: Dictionary = {}

func _process(delta: float) -> void:
	var total_metal_rate: float = 0.0
	var total_nonmetal_rate: float = 0.0
	var total_organic_rate: float = 0.0
	var total_liquid_rate: float = 0.0

	for id in owned:
		if not UPGRADES.has(id):
			continue
		var data: Dictionary = UPGRADES[id]
		var n: int = owned.get(id, 0)
		if n <= 0:
			continue
		var mult: float = EquipmentManager.get_multiplier_for_upgrade(id) * EquipmentManager.get_global_vps_multiplier()
		var rate: float = float(n) * float(data.get("mps", 0.0)) * mult
		
		_views_produced[id] = _views_produced.get(id, 0.0) + rate * delta
		
		match data.get("produces_type", ""):
			"metal":    total_metal_rate    += rate
			"nonmetal": total_nonmetal_rate += rate
			"organic":  total_organic_rate  += rate
			"liquid":   total_liquid_rate   += rate

	# Update float accumulators
	_metal_acc    += total_metal_rate    * delta
	_nonmetal_acc += total_nonmetal_rate * delta
	_organic_acc  += total_organic_rate  * delta
	_liquid_acc   += total_liquid_rate   * delta

	# Add to MaterialManager on integer overflow
	if _metal_acc >= 1.0:
		var add_val := int(_metal_acc)
		_metal_acc = fmod(_metal_acc, 1.0)
		MaterialManager.add("metal", add_val)
	if _nonmetal_acc >= 1.0:
		var add_val := int(_nonmetal_acc)
		_nonmetal_acc = fmod(_nonmetal_acc, 1.0)
		MaterialManager.add("nonmetal", add_val)
	if _organic_acc >= 1.0:
		var add_val := int(_organic_acc)
		_organic_acc = fmod(_organic_acc, 1.0)
		MaterialManager.add("organic", add_val)
	if _liquid_acc >= 1.0:
		var add_val := int(_liquid_acc)
		_liquid_acc = fmod(_liquid_acc, 1.0)
		MaterialManager.add("liquid", add_val)

func get_views_produced(id: String) -> float:
	return _views_produced.get(id, 0.0)

func get_virtual_machines() -> int:
	return 0

func recalculate_all_rates() -> void:
	pass

func try_purchase(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	var price := get_current_price(upgrade_id)
	var cost_type: String = UPGRADES[upgrade_id].get("cost_type", "metal")
	if not MaterialManager.spend(cost_type, price):
		return false
	owned[upgrade_id] = owned.get(upgrade_id, 0) + 1
	MaterialManager.save_game()
	save_game()
	emit_signal("upgrade_purchased", upgrade_id)
	return true

func get_current_price(upgrade_id: String) -> int:
	if not UPGRADES.has(upgrade_id):
		return 0
	var base: float = float(UPGRADES[upgrade_id]["cost"])
	var n: int = get_owned_count(upgrade_id)
	return int(ceil(base * pow(PRICE_SCALE, n)))

func _apply_upgrade(_data: Dictionary) -> void:
	pass

func get_owned_count(upgrade_id: String) -> int:
	return owned.get(upgrade_id, 0)

func can_afford(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	var price := get_current_price(upgrade_id)
	var cost_type: String = UPGRADES[upgrade_id].get("cost_type", "metal")
	return MaterialManager.get_amount(cost_type) >= price

func reset_all() -> void:
	owned.clear()
	_views_produced.clear()
	_metal_acc = 0.0
	_nonmetal_acc = 0.0
	_organic_acc = 0.0
	_liquid_acc = 0.0
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
	owned.clear()
	if cfg.has_section("upgrades"):
		for key in cfg.get_section_keys("upgrades"):
			var count: int = cfg.get_value("upgrades", key, 0)
			if count > 0 and UPGRADES.has(key):
				owned[key] = count
	recalculate_all_rates()

