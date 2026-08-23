extends "res://scripts/ui/boss_edit/creep_edit_mode.gd"
const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
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

# ── The player ship, as an editable "weapon" (2026-08-23) ────────────────────────────────────────────────
# "Đặt player ship vào bảng weapon edit như 1 loại vũ khí để tôi có thể gắn plume." The ship model does not
# live in assets/weaponry (it is the DEFENCE asset arena.gd renders into the player's own SubViewport), so
# the palette scans its folder as well. That folder also holds the defence-track icons (lv1..lv8, shield) and
# the glTF-extracted textures, which are not weapons — hence the folder-aware `_accept_file` below rather
# than a blanket second folder.
const SHIP_FOLDER := "res://assets/defense/"
const SHIP_NAME   := "Ship_model_1"        # arena.gd::SHIP_MODEL's basename; also the weapon_layout.cfg key

# ── Yari Jeager's animation glbs, as editable LAYERS (2026-08-23) ────────────────────────────────────────
# "Khi tôi chọn jeager trong edit. Hiện các glb dưới dạng các layer cho tôi. Để tôi xoay nó cho đúng chiều /
# Hiện tại jeager đang bị bay ngược."
#
# The arena builds Jeager from ONE model (Walk.glb) with the other seven glbs' clips MERGED onto its skeleton
# (`_merge_jaeger_clip`), and orients the whole thing with a SINGLE mount angle read from the "Yari-Jeager"
# cfg entry. That is why it can fly backwards: the clips were authored facing different ways, and one angle
# cannot be right for all of them. Listing each glb as its own layer gives each clip its own Rotate X/Y/Z,
# which `arena_weapons.gd::_draw_yari()` then applies per playing clip.
#
# They are a plain LAYERS group, not a chain: `_chain_id_for()` doesn't claim them, so no Segments/Spacing
# panel and no auto-arrangement — you place and rotate each one yourself.
const JAEGER_FOLDER := "res://assets/weaponry/Jeager/"
const JAEGER_ROOT   := "Yari-Jeager"
## 2026-08-23: every layer below now previews ONE merged file (tools/merge_jaeger_glb.gd) instead of its own
## 19 MB copy of the same mesh. The layer NAMES are unchanged, so every saved rotation, TP and plume style
## keeps working — only the asset they resolve to moved. `_rig_key()` is what keeps them from collapsing into
## a single shared preview rig now that the path no longer distinguishes them.
const JAEGER_MERGED := "res://assets/weaponry/Jeager/Jeager.glb"
## The master layer: the user's clean, animation-free reference model. Plumes placed HERE apply to every clip
## that has none of its own (arena_weapons.gd::_load_jaeger_plume_3d reads it first). Its preview plays no
## clip, so it sits in the rest pose — which is the pose you want to be aiming a thruster at.
const JAEGER_MASTER := "stand"
## Order here is the order they read in the LAYERS list — master, then idle/locomotion, then the attacks.
const JAEGER_CLIPS: Array[String] = ["Fly", "Walk", "Run", "Dive", "Kick", "Low Kick", "Slash", "Fly punch"]
const JAEGER_LAYERS: Array[String] = ["stand", "Fly", "Walk", "Run", "Dive", "Kick", "Low Kick", "Slash", "Fly punch"]
## Layer name -> the clip its preview plays. The master is absent on purpose (rest pose), and "Fly punch"
## differs from its clip "Fly Punch" by one letter's case — the same trap JAEGER3D_LAYER_CLIP guards.
const JAEGER_LAYER_CLIP := {
	"Fly": "Fly", "Walk": "Walk", "Run": "Run", "Dive": "Dive",
	"Kick": "Kick", "Low Kick": "Low Kick", "Slash": "Slash", "Fly punch": "Fly Punch",
}

## All of Jeager's layers resolve to the one merged glb, and so does the weapon's own entry — 2026-08-23,
## on request: `Yari-Jeager.glb` is a byte-identical copy of `Walk.glb`, so the group row used to display a
## mid-stride walk frame. Pointing it at the merged file with no clip shows the `stand` reference pose
## instead, and drops the last 19 MB duplicate.
func _asset_path_for(creep_name: String) -> String:
	return JAEGER_MERGED if (creep_name in JAEGER_LAYERS or creep_name == JAEGER_ROOT) else ""

func _preview_clip(creep_name: String) -> String:
	return String(JAEGER_LAYER_CLIP.get(creep_name, ""))

## Weapons have one shared folder — undo creep_edit_mode.gd's per-map dropdown-driven scan — plus the ship's
## and Jeager's clip folder.
func _folders() -> Array[String]: return [_folder(), SHIP_FOLDER, JAEGER_FOLDER]

## Hangs Jeager's clip glbs off the weapon itself in the LAYERS list. `super()` first so the VIPER chain (and
## any Head/Body/Tail convention group) is built exactly as before; this only adds parents the regex could
## never have found, since these names share no prefix with their root.
func _auto_group_chain_names() -> void:
	super()
	var members: Array[String] = []
	for c: String in JAEGER_LAYERS:
		if c in _all_creep_names and JAEGER_ROOT in _all_creep_names:
			_creep_parents[c] = JAEGER_ROOT
			members.append(c)
	if not members.is_empty():
		_chain_group_order[JAEGER_ROOT] = members

## First-placement layout for Jeager's clip layers: a 4-wide grid down the left of the canvas, big enough to
## judge a facing at a glance, so the eight of them don't pile up on one spot. Only the FIRST placement —
## `_load_layout()` restores whatever you drag them to afterwards. Everything else keeps the base default.
# Two rows of four along the top and bottom of the canvas: clear of the control panels either side (the
# left one covers up to x~240, the palette starts around x~1190) and clear of the weapon's own 150px rect at
# (480, 380), so the root and its clips never overlap on first open.
const JAEGER_GRID_ORIGIN := Vector2(255.0, 75.0)
const JAEGER_GRID_STEP   := Vector2(178.0, 470.0)
const JAEGER_GRID_COLS   := 4
const JAEGER_LAYER_PX    := 150.0   # same as the weapon's own, so a clip reads at the size it plays at

const JAEGER_MASTER_POS := Vector2(255.0, 290.0)   # its own band between the two clip rows

func _default_creep_rect(creep_name: String, aspect: float) -> Rect2:
	if creep_name == JAEGER_MASTER:
		# Not a grid slot: the master is the one you dwell on placing plumes, so it gets clear space of its
		# own rather than sharing a cell edge with a clip that may already have a saved position there.
		return Rect2(JAEGER_MASTER_POS, Vector2(JAEGER_LAYER_PX, JAEGER_LAYER_PX * aspect))
	var i := JAEGER_LAYERS.find(creep_name)
	if i < 0:
		return super(creep_name, aspect)
	var cell := Vector2(float(i % JAEGER_GRID_COLS), float(i / JAEGER_GRID_COLS))
	return Rect2(JAEGER_GRID_ORIGIN + cell * JAEGER_GRID_STEP,
		Vector2(JAEGER_LAYER_PX, JAEGER_LAYER_PX * aspect))
func _show_map_selector() -> bool: return false
func _layout_path() -> String: return "res://weapon_layout.cfg"
func _plume_path() -> String:  return "res://weapon_plume_styles.cfg"
func _title() -> String:      return "WEAPON EDIT"
func _palette_title() -> String: return "WEAPON"

## Exclude ship parts that are not weapons.
## "viper head side" (2026-08-23, "Bỏ Viper Head side ở bảng Enemies"): an alternate side-on art variant of
## VIPER's head that nothing renders — the live weapon draws "VIPER head top".glb — so it only ever added a
## decoy entry to the palette next to the real head. Skipping it here also keeps `_load_layout()` from
## placing its stale weapon_layout.cfg entry on the canvas, since that walks the scanned name list.
static var _SKIP := ["spaceship", "spaceshiphitbox", "wing", "viper head side"]
func _accept_file(fname: String, folder: String) -> bool:
	if folder == SHIP_FOLDER:
		return fname == SHIP_NAME   # that folder is the defence track's; only the ship model is a "weapon"
	if folder == JAEGER_FOLDER:
		# Named explicitly, so neither the merged glb itself nor a stray file becomes a tenth palette entry.
		return fname in JAEGER_LAYERS
	var low := fname.to_lower().get_basename()
	for s in _SKIP:
		if low == s:
			return false
	return true

# ── CHAIN (multi-node) for VIPER — 2026-08-22 ────────────────────────────────
## VIPER is the weapon-side equivalent of the centipede-style chain enemies: a head, N body segments and a
## tail that trail each other with a fixed spacing and a turn-rate clamp (arena_weapons.gd's `_snake_move()`
## / `_snake_len()`). It therefore wants the SAME authoring panel the chain enemies already have — Segments /
## Spacing× / Bend lock / Taper — instead of its own bespoke controls. The panel, its cfg format
## (`creep_chain_overrides.cfg`) and the whole save/live-apply flow are inherited unchanged from
## creep_edit_mode.gd; only the three hooks below differ, pointing it at the weapon instead of ENEMY_DEFS.
const VIPER_CHAIN_PARTS := ["VIPER head top", "VIPER body", "VIPER Tail"]
const VIPER_CHAIN_ID    := "viper"   # key inside creep_chain_overrides.cfg; arena_weapons.gd reads the same one

func _chain_id_for(creep_name: String) -> String:
	return VIPER_CHAIN_ID if creep_name in VIPER_CHAIN_PARTS else ""

## Hardcoded VIPER values, kept in sync with arena_weapons.gd's own consts — shown when the cfg has no
## override yet, and what Reset falls back to. `centi_spacing_mult` is a MULTIPLIER on SNAKE_SPACING (1.0 =
## the stock 25.2px), matching how the enemy chain treats its own spacing, so the two panels read alike.
func _chain_defaults(id: String) -> Dictionary:
	if id != VIPER_CHAIN_ID:
		return super._chain_defaults(id)
	return {
		"centi_segments":     ArenaWeaponsScript.SNAKE_SEGMENTS,
		"centi_spacing_mult": 1.0,
		"centi_bend_deg":     rad_to_deg(ArenaWeaponsScript.SNAKE_TURN),
		"centi_taper_pct":    0.0,
	}

func _apply_chain_runtime(id: String) -> void:
	if id != VIPER_CHAIN_ID:
		super._apply_chain_runtime(id)
		return
	var ws: Node = get_tree().get_first_node_in_group("arena_weapons")
	if ws != null and ws.has_method("reload_chain_overrides"):
		ws.reload_chain_overrides()

## Nothing in-memory to erase for the weapon — arena_weapons.gd re-reads the cfg wholesale in
## `reload_chain_overrides()` (called right after this by `_on_chain_reset`), so deleting the cfg entry is
## already the complete reset.
func _clear_chain_runtime(id: String) -> void:
	if id != VIPER_CHAIN_ID:
		super._clear_chain_runtime(id)

## Groups VIPER's 3 sprites into ONE chain weapon (2026-08-22, "gom cả đầu, thân, đuôi của viper lại trong
## chung 1 weapon... align center và xếp chúng thành 1 hàng. Nếu tôi tăng số segment thì tạo thêm body").
## Everything needed for that already exists in creep_edit_mode.gd and runs off `_auto_group_chain_names()`:
## parenting the parts under the head, centre-aligning + stacking them in a row (`_position_chain_members` /
## `_auto_arrange_chain_templates`), and spawning extra body duplicates from the Segments field
## (`_rebuild_chain_preview`). The ONLY reason VIPER was left out is that its filenames don't match the
## Head/Body<N>/Tail regex that feeds that grouping — "VIPER head top" ends in "top", not "head". Mapping the
## three names explicitly is all that was missing; no grouping/arrangement logic is duplicated here.
## All three must be answered here, not just the head: the regex would give "VIPER body"/"VIPER Tail" the
## prefix "VIPER " (trailing space) while the head gets "VIPER", and the grouping keys off that prefix — a
## mismatch would split them back into two groups.
func _parse_chain_name(cname: String) -> Dictionary:
	match cname:
		"VIPER head top":
			return {"prefix": "VIPER", "kind": "head", "n": 0}
		"VIPER body":
			return {"prefix": "VIPER", "kind": "body", "n": 1}
		"VIPER Tail":
			return {"prefix": "VIPER", "kind": "tail", "n": 0}
	# "VIPER head side" is deliberately NOT listed — it's an alternate art variant, not a chain member.
	return super._parse_chain_name(cname)

## VIPER is always presented as ONE weapon: head, bodies and tail centre-aligned in a single vertical row
## (2026-08-22 request). Unlike the chain enemies — whose parts are hand-placed on a map and must keep that
## layout — VIPER's three sprites only ever exist as one assembled creature, so there is no authored
## arrangement worth preserving and the row is always the correct presentation.
func _chain_force_arrange(root_name: String) -> bool:
	return root_name == "VIPER head top"

# ── ONE display source, shared with the arena (2026-08-22) ───────────────────────────────────────────────
# "Tôi muốn trên arena và trong weapon edit lấy nguồn dữ liệu hiển thị từ cùng 1 nguồn để đảm bảo đồng nhất."
# arena_weapons.gd owns the numbers because it is what actually draws the weapon in play; these two hooks
# are the whole of the editor's access to them. Nothing here restates a size or a spacing.

## VIPER's chain geometry at the CHAIN panel's current Spacing multiplier. Returning {} for anything else
## leaves every enemy chain on creep_edit_mode.gd's own rect-based layout, which is correct for them (their
## arena positions are hand-placed per map, so the editor rects genuinely are the source).
func _chain_geometry(root_name: String) -> Dictionary:
	if root_name != "VIPER head top":
		return super._chain_geometry(root_name)
	return ArenaWeaponsScript.snake_chain_geometry(_chain_spacing_spin.value)

## Same taper curve the live VIPER body uses, so the editor's shrinking duplicates match the arena's
## shrinking MultiMesh segments step for step.
func _chain_seg_scale(taper_pct: float, steps: int) -> float:
	return ArenaWeaponsScript.chain_seg_scale(taper_pct, steps)

## The on-screen diameter arena_weapons.gd renders each 3D weapon at (0.0 for the 2D ones, which keeps their
## hand-authored W/H). This is what makes the editor canvas 1:1 with the arena — see
## creep_edit_mode.gd's `_sync_arena_part_size()` for why a mismatch here silently misplaces every TP.
func _arena_display_px(creep_name: String) -> float:
	return ArenaWeaponsScript.display_px_for(creep_name)

## Canvas direction "forward" points at, for the FRONT arrow the grid overlay draws (2026-08-23). Derived in
## arena_weapons.gd, which owns the draw paths it is read off — see `front_angle_for()`'s header. Only the
## weapon editor has an arena to ask; the enemy editor keeps the base NAN (no marker).
func _front_marker_angle(creep_name: String) -> float:
	return ArenaWeaponsScript.front_angle_for(creep_name)
