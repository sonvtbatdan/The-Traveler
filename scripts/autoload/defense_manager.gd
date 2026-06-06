extends Node

signal level_changed(level: int)
signal items_reset

const SAVE_PATH := "user://save.cfg"

var current_level: int = 0

func _ready() -> void:
	_load_save()

func can_purchase(level: int) -> bool:
	return level == current_level + 1 and level <= 8

func try_purchase(level: int) -> bool:
	if not can_purchase(level):
		return false
	current_level = level
	save_game()
	level_changed.emit(current_level)
	return true

func reset_all() -> void:
	current_level = 0
	save_game()
	level_changed.emit(0)
	items_reset.emit()

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("defense", "level", current_level)
	cfg.save(SAVE_PATH)

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	current_level = cfg.get_value("defense", "level", 0)
