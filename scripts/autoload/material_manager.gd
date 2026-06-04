extends Node
# (Keep static typing)

signal materials_changed
signal material_added(type: String)

var liquid: int = 0
var metal: int = 0
var nonmetal: int = 0
var organic: int = 0

func get_amount(type: String) -> int:
	match type:
		"liquid":   return liquid
		"metal":    return metal
		"nonmetal": return nonmetal
		"organic":  return organic
	return 0

func add(type: String, amount: int) -> void:
	match type:
		"liquid":  liquid  += amount
		"metal":   metal   += amount
		"nonmetal": nonmetal += amount
		"organic": organic += amount
	material_added.emit(type)
	materials_changed.emit()

func spend(type: String, amount: int) -> bool:
	match type:
		"liquid":
			if liquid < amount: return false
			liquid -= amount
		"metal":
			if metal < amount: return false
			metal -= amount
		"nonmetal":
			if nonmetal < amount: return false
			nonmetal -= amount
		"organic":
			if organic < amount: return false
			organic -= amount
		_:
			return false
	materials_changed.emit()
	return true

func reset_all() -> void:
	liquid = 0
	metal = 0
	nonmetal = 0
	organic = 0
	materials_changed.emit()
	save_game()

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("materials", "liquid",   liquid)
	cfg.set_value("materials", "metal",    metal)
	cfg.set_value("materials", "nonmetal", nonmetal)
	cfg.set_value("materials", "organic",  organic)
	cfg.save("user://materials.cfg")

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://materials.cfg") != OK:
		return
	liquid   = cfg.get_value("materials", "liquid",   0)
	metal    = cfg.get_value("materials", "metal",    0)
	nonmetal = cfg.get_value("materials", "nonmetal", 0)
	organic  = cfg.get_value("materials", "organic",  0)
	materials_changed.emit()

