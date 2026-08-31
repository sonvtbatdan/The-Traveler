extends "res://scripts/ui/boss_edit/creep_edit_mode.gd"
const ArenaLootScript := preload("res://scripts/gameplay/arena_loot.gd")
const ArenaXpMgrScript := preload("res://scripts/gameplay/arena_xp_orb_manager.gd")
## Ruin-Drop Edit Mode — the SAME Rotate X/Y/Z mount-angle + W/H size editor weapon_edit_mode.gd already
## gives weapons, pointed at the "ruin drop" pickups instead (2026-08-28, on request: "trong mục weapon edit,
## thêm 1 tab bên cạnh tab weapon hiện tại. Đặt tên là tab Ruin. Trong đó hiện các ruin drop (coin, divinity,
## magnet...)"). Saves to res://ruin_layout.cfg — a SEPARATE file from weapon_layout.cfg, even though both
## reuse the same "creeps" section shape (rot/rot_base/z/size/...), so a ruin item and a weapon that happened
## to share a name could never collide.
##
## 5 of arena_loot.gd's pickup TYPES get a real editable entry here — heart/magnetic/divinity/coin/shield, the
## ones with an actual 3D model (see arena_loot.gd's own header: "coin/heart/magnetic/divinity/shield" render
## via a live SubViewport when a matching .glb exists). "diamond" is a palette-only alias for "coin" with no
## model of its own, and "orb_of_light" is fully procedural (drawn with draw_circle, never a texture or
## model) — neither has anything for Rotate X/Y/Z or a W/H box to calibrate, so neither is listed.
##
## "shield" joined the other four here 2026-08-28 (bug report: "assets\screen đã có shield.glb... nhưng không
## được hiển thị") as PREVIEW/CALIBRATION only at first — nothing spawned a "shield" pickup yet, so it wasn't
## added to WIRED_3D_CREEPS below. That changed 2026-08-29 (on request: "shield cũng là dạng drop như heal,
## hồi 20 shield. bắn ruin rơi ra"): arena_loot.gd's _collect() now has a real "shield" case
## (GameManager.add_shield(20)) and arena_small_ruin.gd's LOOT_POOL can roll it, so shield is now in
## WIRED_3D_CREEPS alongside the rest and its Rotate X/Y/Z sliders are live, same as heart/magnetic/divinity/
## coin's.
##
## Added to creep_edit_mode.gd's WIRED_3D_CREEPS allowlist for all 5 (see that const's own doc comment on why
## that step is mandatory, not optional) — arena_loot.gd's _ruin_rot()/_ruin_z()/_ruin_size() read this file's
## saved values back on every spawn, so the sliders and the size box drive the real pickup, not just this
## editor's own preview.
##
## 2026-08-29, on request ("đặt luôn các orb xp vào bảng ruin để tôi điều chỉnh kích thước"): the 5 XP orb
## tiers (green/yellow/orange/red/purple, assets/screen/xp/*.glb — see arena_xp_orb_manager.gd's own header)
## joined as a 3rd scanned folder (XP_FOLDER) and are wired from the start, same as coin/shield's own launch.
## Their runtime is a shared baked spin-atlas per tier (not a live model per pickup like every other entry
## here), so arena_xp_orb_manager.gd's own _load_ruin_min()/_start_spin_bake() do the read-back instead of
## arena_loot.gd — see that file's matching 2026-08-29 header note for the split.
##
## IMPORTANT, XP tiers only: the W/H box here does NOT mean "always exactly this size" the way it does for
## every other entry above (heart/coin/... really do render at the literal saved px, unconditionally). XP
## orbs already grow with the killed enemy's XP value — the box instead sets a MINIMUM floor under that
## existing curve (follow-up request: "tôi điều chỉnh giá trị minimum của từng orb, sau đó sẽ áp hệ số size
## to thêm theo code cũ"). A weak kill's orb won't render smaller than the box value; a strong kill still
## grows past it up to that tier's own cap, unchanged. See arena_xp_orb_manager.gd's _load_ruin_min() for the
## full reasoning, including why it deliberately ignores an untouched/still-default box value.

## coin.glb lives outside assets/screen/ (see arena_loot.gd's own COIN_GLB doc comment for why) — the other
## four sit in assets/screen/ alongside every other pickup/HUD art asset in that folder, most of which are
## NOT ruin drops (Spaceship.png, dash.png, the ship's own baked textures...), hence the strict per-folder
## name whitelist in _accept_file() below rather than a blanket folder scan.
##
## 2026-08-28 bug fix (user report: "coin đang hiện là file png trong ruin edit... không được hiển thị")
## — _accept_file() used to accept "coin" from EITHER folder, no folder check at all. assets/screen/ ALSO
## happens to hold a coin.png (the old flat-icon fallback, still used by every OTHER type here), and
## creep_edit_mode.gd's own _scan_creeps() dedupes by "first folder in _folders() wins" — since RUIN_FOLDER
## (assets/screen/) is listed BEFORE COIN_FOLDER (assets/hud/), the scan claimed "coin" from screen/coin.png
## before it ever reached hud/coin.glb, and the real glb was silently skipped as a duplicate name. Fixed by
## making _accept_file() folder-aware: "coin" is now only ever accepted from COIN_FOLDER, so screen/coin.png
## is rejected outright and can no longer win the race.
const RUIN_FOLDER     := "res://assets/screen/"
const COIN_FOLDER     := "res://assets/hud/"
const XP_FOLDER       := "res://assets/screen/xp/"
const RUIN_FOLDER_NAMES: Array[String] = ["heart", "magnetic", "divinity", "shield"]   # live in RUIN_FOLDER
const COIN_FOLDER_NAMES: Array[String] = ["coin"]                                       # live in COIN_FOLDER
const XP_FOLDER_NAMES: Array[String] = ["green", "yellow", "orange", "red", "purple"]   # live in XP_FOLDER —
	# same order as arena_xp_orb_manager.gd's own TIER_NAMES; each name has both a .glb and a same-named .png
	# sitting right next to it in that folder (the old flat-icon art), but creep_edit_mode.gd's own scan/
	# load/icon functions already try .glb before .png within a single folder (see _load_or_create_creep()'s
	# "glb tried FIRST" doc comment) — so unlike coin, no _asset_path_for()/_creep_icon_tex() override is
	# needed here; the glb just wins on its own.

func _folder() -> String: return RUIN_FOLDER
func _folders() -> Array[String]: return [RUIN_FOLDER, COIN_FOLDER, XP_FOLDER]
func _edit_group() -> String: return "ruin_edit"
func _show_map_selector() -> bool: return false
func _layout_path() -> String: return "res://ruin_layout.cfg"
func _plume_path() -> String:  return "res://ruin_plume_styles.cfg"   # unused in practice — ruin drops carry no plumes/TPs, kept separate just so a save never touches weapon_plume_styles.cfg
func _title() -> String:       return "RUIN EDIT"
func _palette_title() -> String: return "RUIN"

## Whitelist AND folder-locked — a name is only accepted from the ONE folder it actually lives in, so a
## same-named file sitting in the OTHER scanned folder (screen/coin.png, see this file's 2026-08-28 doc note
## above) can never win the base editor's cross-folder "first one found" dedup.
func _accept_file(fname: String, folder_path: String) -> bool:
	var low := fname.to_lower().get_basename()
	if folder_path == COIN_FOLDER:
		return low in COIN_FOLDER_NAMES
	if folder_path == XP_FOLDER:
		return low in XP_FOLDER_NAMES
	if folder_path == RUIN_FOLDER:
		return low in RUIN_FOLDER_NAMES
	return false

## The real on-screen diameter arena_loot.gd draws `creep_name` at right now (its own hardcoded LOOT_WIDTH/
## COIN_WIDTH/DIVINITY_WIDTH consts) — seeds the editor's initial W/H box with a sensible starting point that
## matches the live game, exactly like weapon_edit_mode.gd's own override does via arena_weapons.display_px_
## for(). Purely a one-time default; the box is freely user-editable afterward (see creep_edit_mode.gd's own
## 2026-08-23 note on why nothing re-forces it after that).
func _arena_display_px(creep_name: String) -> float:
	if creep_name in XP_FOLDER_NAMES:
		# ArenaXpMgrScript.TIER_DEFAULT_PX — for XP tiers this is ONLY a reasonable-looking untouched preview
		# size, not a runtime meaning (see this file's header + arena_xp_orb_manager.gd's _load_ruin_min()):
		# that same const also doubles as the "still exactly the untouched seed" sentinel _load_ruin_min()
		# checks for, so it MUST stay in lockstep with this — if this ever returns something else, an
		# untouched tier would misread as an intentional (and wrong) minimum the moment anything saves.
		var idx := ArenaXpMgrScript.TIER_NAMES.find(creep_name)
		if idx >= 0:
			return float(ArenaXpMgrScript.TIER_DEFAULT_PX[idx])
	match creep_name:
		"coin":     return ArenaLootScript.COIN_WIDTH
		"divinity": return ArenaLootScript.DIVINITY_WIDTH
		_:          return ArenaLootScript.LOOT_WIDTH   # heart, magnetic, shield (no dedicated const of its own)

## 2026-08-28 bug fix, part 2 of the "coin shows as PNG" report — _accept_file()'s folder lock (above) only
## fixes the SCAN/DISCOVERY half (making sure the palette even registers "coin" as pointing somewhere real).
## The actual FILE PICK for placing/previewing "coin" on the canvas is a completely SEPARATE, independent
## search in creep_edit_mode.gd's own _load_or_create_creep(): it tries every extension of the FIRST folder
## in _folders() before ever moving to the second (folder is the OUTER loop, extension the inner one) — for
## "coin" that means screen/coin.glb (doesn't exist) → screen/coin.png (DOES exist, and gets used) → the
## search stops there, never reaching hud/coin.glb at all. Same root shape of bug as the scan-dedup one, just
## in a different function. `_asset_path_for()` is the base class's own escape hatch for exactly this —
## weapon_edit_mode.gd already uses it to force Jeager's ten layer names onto one merged glb — so it's the
## same fix, just for "coin".
func _asset_path_for(creep_name: String) -> String:
	return (COIN_FOLDER + "coin.glb") if creep_name == "coin" else ""

## Part 3: the palette's own thumbnail BUTTON (creep_edit_mode.gd's _creep_icon_tex()) has YET ANOTHER
## independent folder×extension search, and it does NOT consult _asset_path_for() at all — so even with the
## two fixes above, the palette list's little icon for "coin" would still show screen/coin.png. Short-
## circuited here rather than touching the base class (shared by Creep Edit and Weapon Edit too, and whether
## the same gap matters for Jeager's own _asset_path_for-driven layers is out of scope for this report).
func _creep_icon_tex(creep_name: String) -> Texture2D:
	if creep_name == "coin":
		return _load_full_tex(COIN_FOLDER + "coin.glb")
	return super(creep_name)
