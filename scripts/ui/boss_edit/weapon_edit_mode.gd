extends "res://scripts/ui/boss_edit/creep_edit_mode.gd"
## Weapon Edit Mode — the SAME Fire-Point / Thrust-Point / plume editor as creep_edit_mode.gd,
## but pointed at the in-arena weapon sprites (assets/weaponry) instead of enemies.
## Excludes ship-part sprites (Spaceship, Wing, missile…). Saves to res://weapon_layout.cfg + res://weapon_plume_styles.cfg.
##
## Opened via the "Edit Weapon" button in the dev weapon-spawn panel (arena_debug_spawn.gd).
## Pick a weapon from the list, drop FP/TP on it, set plume styles — e.g. add a Thrust Point to
## the Orbital so it can emit a plume.
##
## NOTE: this writes the layout/plume config; consuming it in-game (e.g. drawing the orbital's
## TP plume during play) is separate weapon-render wiring.

func _edit_group() -> String: return "weapon_edit"
func _folder() -> String:     return "res://assets/weaponry/"
func _layout_path() -> String: return "res://weapon_layout.cfg"
func _plume_path() -> String:  return "res://weapon_plume_styles.cfg"
func _title() -> String:      return "WEAPON EDIT"

## Exclude ship parts that are not weapons.
static var _SKIP := ["spaceship", "spaceshiphitbox", "wing", "missile"]
func _accept_file(fname: String) -> bool:
	var low := fname.to_lower().get_basename()
	for s in _SKIP:
		if low == s:
			return false
	return true
