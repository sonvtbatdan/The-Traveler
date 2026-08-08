extends SceneTree
## One-off audit (2026-08-06, on request): list every weapon (InventoryManager.ITEM_DEFS, tag "weapon") and
## every perk (weapon skill-point pool perks + aux/passive items + aux pool perks) whose icon file is
## missing/empty, cross-referencing the exact path conventions arena_levelup_ui.gd itself uses
## (WEAPON_PERK_ICON_DIR/WEAPON_PERK_FOLDER/WEAPON_PERK_ID_ALIAS, AUX_ICON_DIR) so this audit can't drift out
## of sync with what the game actually tries to load.
##
## Run headless (pure Dictionary/file-existence checks, no GPU needed):
##   godot --headless --path . --script tools/audit_missing_icons.gd

const InventoryManager := preload("res://scripts/autoload/inventory_manager.gd")
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaAux := preload("res://scripts/gameplay/arena_aux.gd")

const AUX_ICON_DIR := "res://assets/hud/aux perk/"
const WEAPON_PERK_ICON_DIR := "res://assets/hud/weapon perks/"

# Mirrors arena_levelup_ui.gd's own WEAPON_PERK_FOLDER/WEAPON_PERK_ID_ALIAS/​_weapon_pool exactly — keep in
# sync with that file if it's ever edited.
const WEAPON_PERK_FOLDER := {
	"gatling_gun": "Gatling", "death_beam": "Death Beam", "arc": "Arc Lightning", "gauss": "Gauss Pulser",
	"defensive_orbitals": "Orbital Defender", "dragons_breath": "red X", "chemtrail": "Chemtrail", "z_sword": "Z-Sword", "ultrasonicator": "ultrasonicator",
	"shooter": "shooter", "viper": "viper", "ionizing_field": "blackhole", "player_2": "player 2",
	"aliwa": "aliwa", "mortar": "mortar",
	"venomancer": "swarm",
	"graviton_well": "gravitation well",
}
const WEAPON_PERK_ID_ALIAS := {
	"aoe_mastery": "aoe", "cd": "cooldown", "ms": "movespeed", "armor_reduction": "armor reduction",
	"player_2/damage": "overclock",
}

func _weapon_pool(kind: String) -> Dictionary:
	if kind == "gatling_gun": return ArenaWeapons.GATLING_POOL
	if kind == "death_beam": return ArenaWeapons.DEATHBEAM_POOL
	if kind == "arc": return ArenaWeapons.ARC_POOL
	if kind == "gauss": return ArenaWeapons.GAUSS_POOL
	if kind == "defensive_orbitals": return ArenaWeapons.ORBITAL_POOL
	if kind == "dragons_breath": return ArenaWeapons.DRAGON_POOL
	if kind == "chemtrail": return ArenaWeapons.CHEMTRAIL_POOL
	if kind == "z_sword": return ArenaWeapons.ZSWORD_POOL
	if kind == "ultrasonicator": return ArenaWeapons.SONIC_POOL
	if kind == "mortar": return ArenaWeapons.MORTAR_POOL
	if kind == "venomancer": return ArenaWeapons.PARA_POOL
	if kind == "aliwa": return ArenaWeapons.BOOM_POOL
	if kind == "viper": return ArenaWeapons.SNAKE_POOL
	if kind == "shooter": return ArenaWeapons.SHOOTER_POOL
	if kind == "ionizing_field": return ArenaWeapons.IONIZE_POOL
	if kind == "player_2": return ArenaWeapons.PLAYER2_POOL
	if kind == "thunderhead": return ArenaWeapons.THUNDER_POOL
	if kind == "graviton_well": return ArenaWeapons.GRAVWELL_POOL
	if kind == "omega_swarm": return ArenaWeapons.OMEGA_POOL
	if kind == "singularity_lance": return ArenaWeapons.SLANCE_POOL
	if kind == "prism_array": return ArenaWeapons.PRISM_POOL
	if kind == "hailstorm": return ArenaWeapons.HAIL_POOL
	if kind == "wraithfire": return ArenaWeapons.WRAITH_POOL
	if kind == "hivemind": return ArenaWeapons.HIVE_POOL
	if kind == "annihilator": return ArenaWeapons.ANNI_POOL
	if kind == "event_horizon": return ArenaWeapons.EVENTH_POOL
	return {}

func _exists(path: String) -> bool:
	return path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path))

func _initialize() -> void:
	print("=== WEAPONS (InventoryManager.ITEM_DEFS, tag \"weapon\") — missing/empty icon ===")
	var weapon_ids: Array = []
	for id: String in InventoryManager.ITEM_DEFS:
		var d: Dictionary = InventoryManager.ITEM_DEFS[id]
		if not (d.get("tags", []) as Array).has("weapon"):
			continue
		weapon_ids.append(id)
		var icon := String(d.get("icon", ""))
		if not _exists(icon):
			print("  %-22s icon=\"%s\"" % [id, icon])
	print("(%d total weapon defs)" % weapon_ids.size())

	print("\n=== WEAPON KINDS WITH NO PERK-ICON FOLDER AT ALL (every pool perk falls back to the parent icon) ===")
	for kind: String in ArenaWeapons.WEAPON_INFO:
		var pool := _weapon_pool(kind)
		if pool.is_empty():
			continue   # no skill-point pool at all — nothing to audit
		if not WEAPON_PERK_FOLDER.has(kind):
			print("  %s  (%d perks, all unillustrated)" % [kind, pool.size()])

	print("\n=== WEAPON POOL PERKS — folder exists but THIS perk's file is missing ===")
	for kind: String in WEAPON_PERK_FOLDER:
		var pool := _weapon_pool(kind)
		if pool.is_empty():
			continue
		var dir := WEAPON_PERK_ICON_DIR + String(WEAPON_PERK_FOLDER[kind]) + "/"
		for perk_id: String in pool.keys():
			var fname := String(WEAPON_PERK_ID_ALIAS.get(kind + "/" + perk_id, WEAPON_PERK_ID_ALIAS.get(perk_id, perk_id)))
			var path := dir + fname + ".png"
			if not _exists(path):
				print("  %-22s / %-20s -> %s" % [kind, perk_id, path])

	print("\n=== AUX / PASSIVE ITEMS (ArenaAux.AUX_DEFS) — missing/empty base icon ===")
	for d: Dictionary in ArenaAux.AUX_DEFS:
		var id := String(d["id"])
		var path := (AUX_ICON_DIR + id + "/" + id + ".png") if ArenaAux.AUX_POOL.has(id) else (AUX_ICON_DIR + id + ".png")
		if not _exists(path):
			print("  %-22s -> %s" % [id, path])
	print("(%d total aux defs)" % ArenaAux.AUX_DEFS.size())

	print("\n=== AUX POOL PERKS (ArenaAux.AUX_POOL) — own-icon file missing (falls back to parent aux icon) ===")
	for aux_id: String in ArenaAux.AUX_POOL:
		var pool: Dictionary = ArenaAux.AUX_POOL[aux_id]
		for perk_id: String in pool.keys():
			var path := AUX_ICON_DIR + aux_id + "/" + perk_id + ".png"
			if not _exists(path):
				print("  %-22s / %-20s -> %s" % [aux_id, perk_id, path])

	quit(0)
