extends RefCounted
class_name BoardDefs
## Registry of editor "boards" — each is an independent authored layout edited by the SAME editor
## (`board_edit_mode.gd`). A board = a saved groups/items/text layout (`layout`), a palette folder of
## sprites to drag from (`assets`), and a runtime `binder` script that drives its placed nodes from game
## state. Add a new board by adding an entry here (+ a binder script + a palette folder) — no editor edits.
##
## Layout files live under res://config/boards/. The HUD keeps a fallback to its original path so an
## existing playerhud_layout.cfg is picked up until it is migrated.

const DIR := "res://config/boards/"

const BOARDS := {
	"hud": {
		"name": "HUD 1.0",
		"layout": "res://config/boards/hud.cfg",
		"legacy_layout": "res://playerhud_layout.cfg",   # fallback: original location (pre-migration)
		"assets": "res://assets/hud/Playerhud/",
		"binder": "res://scripts/ui/boards/hud_binder.gd",
		"hud_version": true,   # selectable as a runtime HUD in the Settings panel — see hud_version_ids()
	},
	"hud_1_1": {
		"name": "HUD 1.1",
		"layout": "res://config/boards/hud_1_1.cfg",
		"assets": "res://assets/hud/Playerhud/",
		"binder": "res://scripts/ui/boards/hud_binder.gd",
		"hud_version": true,
	},
	"levelup": {
		"name": "Level Up",
		"layout": "res://config/boards/levelup.cfg",
		"assets": "res://assets/hud/LevelUp/",
		"binder": "res://scripts/ui/boards/levelup_binder.gd",
	},
	"choose_weapon": {
		"name": "Choose Weapon",
		"layout": "res://config/boards/choose_weapon.cfg",
		"assets": "res://assets/hud/choose weapon/",
		"binder": "res://scripts/ui/boards/choose_weapon_binder.gd",
	},
}

## Dropdown / iteration order (Board: selector in the HUD editor — every board, including Level Up).
const ORDER := ["hud", "hud_1_1", "levelup", "choose_weapon"]

## Alternate HUD layouts a player can pick between in Settings (excludes non-HUD boards like Level Up).
static func hud_version_ids() -> Array:
	var out: Array = []
	for id in ORDER:
		if bool((BOARDS.get(id, {}) as Dictionary).get("hud_version", false)):
			out.append(id)
	return out

static func has(id: String) -> bool:
	return BOARDS.has(id)

static func get_def(id: String) -> Dictionary:
	return BOARDS.get(id, {})

static func display_name(id: String) -> String:
	return String((BOARDS.get(id, {}) as Dictionary).get("name", id))

static func assets_dir(id: String) -> String:
	return String((BOARDS.get(id, {}) as Dictionary).get("assets", "res://assets/hud/Playerhud/"))

## Resolved layout path to LOAD from: the primary path if it exists, else the legacy fallback (if any).
static func layout_load_path(id: String) -> String:
	var d: Dictionary = BOARDS.get(id, {})
	var primary := String(d.get("layout", ""))
	if primary != "" and (ResourceLoader.exists(primary) or FileAccess.file_exists(primary)):
		return primary
	var legacy := String(d.get("legacy_layout", ""))
	if legacy != "" and (ResourceLoader.exists(legacy) or FileAccess.file_exists(legacy)):
		return legacy
	return primary

## Path to SAVE to (always the primary location — migrates a legacy file forward on first save).
static func layout_save_path(id: String) -> String:
	return String((BOARDS.get(id, {}) as Dictionary).get("layout", ""))

## Instantiate the board's binder (or a plain BoardBinder if the script is missing/not yet written).
static func make_binder(id: String) -> BoardBinder:
	var d: Dictionary = BOARDS.get(id, {})
	var path := String(d.get("binder", ""))
	if path != "" and ResourceLoader.exists(path):
		var scr := load(path)
		if scr != null:
			var b = scr.new()
			if b is BoardBinder:
				return b
	return BoardBinder.new()
