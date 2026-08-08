extends CanvasLayer
## Dev-mode-only item catalog — group "weapon_info", toggled from arena_hud_buttons.gd's WEAPON INFO
## button (small dev-cluster button, next to +LEVEL). Tabs: Weapon / Aux / Shield / Hull / Thruster —
## every equippable item category that exists in InventoryManager.ITEM_DEFS's "tags".
##
## Each row shows Icon / Name / Code (the internal dictionary key) / Category (rarity, "(Craft)" suffix
## for craftable_from_fragments items) / a stat field or two / an editable Lore field. Weapon and Aux
## items that have a REAL rank-up perk pool (arena_weapons.gd's *_POOL consts / arena_aux.gd's AUX_POOL —
## the "pick one of N perks each level" system) get a Perk button that expands an inline sub-table
## (real per-perk icon + name + editable value column(s), see _make_perk_table) for just that item; a
## global per-tab "Perk: Expand/Collapse All" button does the same for every row in the current tab at
## once. Rows with no pool (7 of 33 weapons — striker, rift_maker, fat_boy, yari, yari_jaeger, swarm,
## homing_missile — and 2 of 17 aux — harmonizer, revival — still level up, just not through the
## pool-pick flow) show "—" instead of a button, keeping columns aligned. Shield/Hull/Thruster items are
## single fixed-stat gear with no pool system at all, so those 3 tabs have no Perk column/button
## whatsoever, per explicit request.
##
## Perk icons: real art from res://assets/hud/weapon perks/<folder>/ and res://assets/hud/aux perk/<id>/
## (WEAPON_PERK_FOLDER/WEAPON_PERK_ICON_OVERRIDES + _weapon_perk_icon()/_aux_perk_icon()), falling back to
## the parent weapon/aux's own icon wherever no per-perk file exists — as of 2026-08-07 that's nobody among
## the 10 fragment-crafted uniques anymore; all 10 now have both an item icon and a full perk-art folder.
##
## Damage/Speed (Weapon tab) and Effect (Aux tab) are now EDITABLE fields, not plain labels — seeded from
## the live-computed base values (_weapon_stats(), read off arena_weapons.gd's own *_DAMAGE/*_TICK/
## *_COOLDOWN consts — "damage creep nhận trong 1 tick khi tiếp xúc với đạn/vật thể") or AUX_DEFS's
## "effect" string, editable/overridable, and saved like Lore. A few weapons don't reduce to one clean
## damage number (dual-stage Gauss, growing-radius Graviton Well/Event Horizon, volley-based Swarm,
## ram-and-return Striker, Player 2's companion) — those seed as a range or "—" plus a small note
## underneath; ask if any specific one still reads wrong.
##
## Perk value columns: each pool perk's "per" mechanical string (e.g. "+10% damage", "-10% AoE, +15%
## damage") is parsed into one editable SpinBox per numeric component (_parse_per) — the old flavor "desc"
## paragraph is gone entirely, per request. Perks with multiple stat types get multiple value columns;
## the sub-table's column count = the widest perk in that specific pool.
##
## Lore: arena_weapons.gd's WEAPON_LORE supplies English flavor text for ~19 base weapons; the 10
## fragment-crafted uniques + a few others have none yet, and Aux/Shield/Hull/Thruster never had a lore
## field at all (only a short mechanical "desc"/"effect"). All editable fields (Lore + Damage/Speed/Effect
## + every perk value) are saved together by the top "Save" button into res://weapon_info_lore.cfg (one
## ConfigFile section per field kind) — saved values override the live-computed defaults on the next open.
## This is a dev reference/tuning notepad: none of these saved overrides feed back into the actual
## gameplay formulas, which stay as separate hardcoded literals throughout arena_weapons.gd/arena_aux.gd.
##
## All data-entry fields (Lore + Damage/Speed/Effect + perk-value SpinBoxes) are sized compact with font
## size 11 — matching the row's own item-name label — per request; everything else uses the default theme
## font throughout, no custom font override (matches creep_info_panel.gd's convention).

const ArenaWeapons    := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaAux        := preload("res://scripts/gameplay/arena_aux.gd")
const ArenaDebugSpawn := preload("res://scripts/gameplay/arena_debug_spawn.gd")   # WEAPON_TABS — single source of truth for Drop/Evolve/Fusion categorization, shared with the F12 debug spawn panel
const CFG_PATH := "res://weapon_info_lore.cfg"

const TAB_ORDER := ["weapon", "aux", "shield", "hull", "thruster"]
const TAB_LABELS := {"weapon": "WEAPON", "aux": "AUX", "shield": "SHIELD", "hull": "HULL", "thruster": "THRUSTER"}

# Weapon tab's own sub-tabs, built from arena_debug_spawn.gd's WEAPON_TABS const (NOT duplicated by hand —
# read live so this stays in sync with that file). WEAPON_TABS itself has "drop"/"evolve"/"fusion"/"unique"
# as top-level keys (that file's own Drop/Unique split, 2026-08-07, done to match this same scheme — the 10
# fragment-crafted uniques live in its "unique" key, not buried in "drop"). Its "obsolete" tab (3
# reworked/retired kinds + a retired Shield Generator entry — vampire_host/toxic_ballistic/singularities,
# each already re-represented as a placeholder or live entry elsewhere: Fusion's "Vampire Host"/
# "Singularities" placeholders, Shield tab's real shield_generator) is dropped entirely, per request — it
# only ever duplicated concepts shown elsewhere. player_2 (a real, fully-implemented weapon-like companion
# with its own POOL/CAPSTONES) isn't in WEAPON_TABS at all — that debug panel doesn't spawn it — so it's
# folded into "drop" here to avoid it silently vanishing from this catalog.
const WEAPON_SUBTAB_ORDER := ["drop", "evolve", "fusion", "unique"]
const WEAPON_SUBTAB_LABELS := {"drop": "Drop", "evolve": "Evolve", "fusion": "Fusion", "unique": "Unique"}

# kind → its "res://assets/hud/weapon perks/<folder>/" subfolder. 2026-08-07: user added real perk art for
# all 10 fragment-crafted uniques now (last 2 — annihilator, event_horizon — same day, filenames match their
# NEW post-redesign pool keys damage/cd/chain/burn and damage/radius/pull/uptime 1:1, no overrides needed).
# annihilator's own folder has a stray duplicate "burn (1).png" alongside "burn.png" — harmless, unused,
# left as-is (not referenced by ANNI_POOL's actual "burn" key).
const WEAPON_PERK_FOLDER := {
	"gatling_gun": "Gatling", "arc": "Arc Lightning", "death_beam": "Death Beam", "gauss": "Gauss Pulser",
	"defensive_orbitals": "Orbital Defender", "dragons_breath": "red X", "chemtrail": "Chemtrail",
	"z_sword": "Z-Sword", "ultrasonicator": "sonic", "mortar": "mortar", "venomancer": "swarm",
	"aliwa": "boomerang", "viper": "snake", "shooter": "shooter", "ionizing_field": "blackhole",
	"player_2": "player 2", "graviton_well": "gravitation well",
	"thunderhead": "Thunderhead", "prism_array": "Prism Array", "singularity_lance": "Singularity Lance",
	"wraithfire": "Wraithfire", "hailstorm": "hailstorm", "hivemind": "hivemind", "omega_swarm": "omega swarm",
	"annihilator": "Annihilator", "event_horizon": "Event Horizon",
}
# Perk-id → filename stem, for the handful of files whose art was named differently than the pool's own dict
# key (verified by hand against the actual folder listing — everything NOT listed here matches its key 1:1).
const WEAPON_PERK_ICON_OVERRIDES := {
	"gauss": {"aoe_mastery": "aoe"},
	"dragons_breath": {"armor_reduction": "armor reduction"},
	"chemtrail": {"ms": "movespeed"},
	"ultrasonicator": {"cd": "cooldown"},
	"z_sword": {"cd": "cooldown"},
	"player_2": {"damage": "overclock"},
}

var _is_open: bool = false
var _root: Control = null
var _status: Label = null
var _global_perk_btn: Button = null
var _active_tab: String = "weapon"

var _lore_overrides: Dictionary = {}     # tab → {id → text}, loaded from CFG_PATH once at build time
var _perk_val_overrides: Dictionary = {} # "tab:owner_id:perk_id:index" → float, loaded from CFG_PATH
var _weapon_rows: Array = []           # {id, tab, lore_edit, dmg_edit, spd_edit, perk_box, perk_btn}
var _aux_rows: Array = []              # {id, tab, lore_edit, eff_edit, perk_box, perk_btn}
var _simple_rows: Dictionary = {"shield": [], "hull": [], "thruster": []}   # {id, tab, lore_edit}
var _perk_val_rows: Array = []         # {key, spin} — every editable perk-value SpinBox across all pools
var _expand_state: Dictionary = {"weapon": false, "aux": false}

var _tab_scroll: Dictionary = {}    # tab → ScrollContainer
var _tab_rows_box: Dictionary = {}  # tab (excl. "weapon", which has 4 sub-boxes instead) → VBoxContainer
var _tab_btns: Dictionary = {}      # tab → Button

var _weapon_subtab: String = "drop"       # active Drop/Evolve/Fusion/Unique sub-tab
var _weapon_subtab_box: Dictionary = {}   # subtab id → VBoxContainer (all 4 persistent, visibility toggled)
var _weapon_subtab_btns: Dictionary = {}  # subtab id → Button

func _ready() -> void:
	layer = 61   # same tier as creep_info_panel.gd (above the HUD dev-column buttons)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("weapon_info")
	visible = false

func is_open() -> bool:
	return _is_open

## Public: called by arena_hud_buttons.gd's WEAPON INFO button. Built once and kept alive afterward (unlike
## creep_info_panel.gd's per-open rebuild) so in-progress Lore edits + expanded-perk state survive close/reopen.
func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	if _is_open and _root == null:
		_build_ui()

# ── Data resolvers ───────────────────────────────────────────────────────────────────────────────────

## kind → its rank-up perk pool (mirrors arena_levelup_ui.gd's _weapon_pool() dispatch — keep in sync by
## hand if that function's kind list ever changes; NOTE there matches WEAPON_INFO *kind* keys, not def_id).
func _weapon_pool_for(kind: String) -> Dictionary:
	match kind:
		"gatling_gun": return ArenaWeapons.GATLING_POOL
		"death_beam": return ArenaWeapons.DEATHBEAM_POOL
		"arc": return ArenaWeapons.ARC_POOL
		"gauss": return ArenaWeapons.GAUSS_POOL
		"defensive_orbitals": return ArenaWeapons.ORBITAL_POOL
		"dragons_breath": return ArenaWeapons.DRAGON_POOL
		"chemtrail": return ArenaWeapons.CHEMTRAIL_POOL
		"z_sword": return ArenaWeapons.ZSWORD_POOL
		"ultrasonicator": return ArenaWeapons.SONIC_POOL
		"mortar": return ArenaWeapons.MORTAR_POOL
		"venomancer": return ArenaWeapons.PARA_POOL
		"aliwa": return ArenaWeapons.BOOM_POOL
		"viper": return ArenaWeapons.SNAKE_POOL
		"shooter": return ArenaWeapons.SHOOTER_POOL
		"ionizing_field": return ArenaWeapons.IONIZE_POOL
		"player_2": return ArenaWeapons.PLAYER2_POOL
		"thunderhead": return ArenaWeapons.THUNDER_POOL
		"graviton_well": return ArenaWeapons.GRAVWELL_POOL
		"omega_swarm": return ArenaWeapons.OMEGA_POOL
		"singularity_lance": return ArenaWeapons.SLANCE_POOL
		"prism_array": return ArenaWeapons.PRISM_POOL
		"hailstorm": return ArenaWeapons.HAIL_POOL
		"wraithfire": return ArenaWeapons.WRAITH_POOL
		"hivemind": return ArenaWeapons.HIVE_POOL
		"annihilator": return ArenaWeapons.ANNI_POOL
		"event_horizon": return ArenaWeapons.EVENTH_POOL
		_: return {}

## Best-effort base (rank 0) "damage per contact tick" + "ticks/shots per second", read live off
## arena_weapons.gd's own consts. {"dmg": float | [min,max], "cd": float (seconds between hits), "note": String}
func _weapon_stats(kind: String) -> Dictionary:
	var AW := ArenaWeapons
	match kind:
		"gatling_gun": return {"dmg": AW.GAT_DAMAGE, "cd": AW.GAT_FIRE_INTERVAL, "note": ""}
		"death_beam": return {"dmg": AW.DEATHBEAM_DAMAGE, "cd": AW.DEATHBEAM_TICK, "note": "beam fires %.1fs out of every %.1fs cycle" % [AW.DEATHBEAM_DURATION, AW.DEATHBEAM_CYCLE]}
		"arc": return {"dmg": AW.ARC_DAMAGE, "cd": AW.ARC_COOLDOWN, "note": "per chain link"}
		"gauss": return {"dmg": AW.GAUSS_DAMAGE, "cd": AW.GAUSS_CHARGE_TIME, "note": "impact budget; +%.0f/tick DoT every %.2fs while embedded" % [AW.GAUSS_TICK_DAMAGE, AW.GAUSS_TICK_INTERVAL]}
		"defensive_orbitals": return {"dmg": AW.ORBITAL_DAMAGE, "cd": AW.ORBITAL_HIT_COOLDOWN, "note": "per ball collision"}
		"striker": return {"dmg": AW.STRIKER_DAMAGE, "cd": 0.0, "note": "ram-and-return — no fixed cadence"}
		"shooter": return {"dmg": AW.SHOOTER_DAMAGE, "cd": AW.SHOOTER_COOLDOWN, "note": "per bolt, per turret"}
		"rift_maker": return {"dmg": [AW.VOID_DAMAGE_MIN * AW.VOID_TICK, AW.VOID_DAMAGE_MAX * AW.VOID_TICK], "cd": AW.VOID_TICK, "note": "ramps over %.1fs, recasts every %.1fs" % [AW.VOID_RAMP, AW.VOID_COOLDOWN]}
		"dragons_breath": return {"dmg": AW.RED_X_DAMAGE, "cd": AW.RED_X_INTERVAL, "note": ""}
		"chemtrail": return {"dmg": AW.CHEMTRAIL_TICK_DAMAGE, "cd": AW.CHEMTRAIL_TICK_INTERVAL, "note": "DoT tick"}
		"mortar": return {"dmg": AW.MORTAR_DAMAGE, "cd": AW.MORTAR_FIRE_INTERVAL, "note": ""}
		"fat_boy": return {"dmg": AW.MORTAR_DAMAGE * AW.FATBOY_DMG_MULT, "cd": AW.MORTAR_FIRE_INTERVAL / AW.FATBOY_RATE_MULT, "note": "Mortar's Fat Boy capstone"}
		"ultrasonicator": return {"dmg": AW.SONIC_DAMAGE, "cd": AW.SONIC_COOLDOWN, "note": ""}
		"z_sword": return {"dmg": AW.ZSWORD_DAMAGE, "cd": AW.ZSWORD_COOLDOWN, "note": ""}
		"ionizing_field": return {"dmg": AW.IONIZE_DAMAGE, "cd": AW.IONIZE_RING_INTERVAL, "note": "per ring tick (black-hole field)"}
		"aliwa": return {"dmg": AW.BOOM_DAMAGE, "cd": AW.BOOM_HIT_CD, "note": ""}
		"venomancer": return {"dmg": AW.PARA_DAMAGE, "cd": AW.PARA_TICK, "note": "new spore cast every %.1fs" % AW.PARA_COOLDOWN}
		"yari": return {"dmg": AW.MORO_DAMAGE, "cd": AW.MORO_ATTACK_CD, "note": ""}
		"yari_jaeger": return {"dmg": AW.YARI_DAMAGE, "cd": AW.YARI_ATTACK_CD, "note": ""}
		"swarm": return {"dmg": AW.SWARM_DAMAGE, "cd": AW.SBALL_LOITER_HIT_CD, "note": "volley of %d balls every %.1fs" % [AW.SBALL_COUNT, AW.SBALL_COOLDOWN]}
		"viper": return {"dmg": AW.SNAKE_DAMAGE, "cd": AW.SNAKE_TICK, "note": "per segment in contact"}
		"homing_missile": return {"dmg": AW.HOMING_DAMAGE, "cd": AW.HOMING_INTERVAL, "note": "AoE blast on impact"}
		"player_2": return {"dmg": -1.0, "cd": 0.0, "note": "companion — reuses the player's own equipped weapons"}
		"thunderhead": return {"dmg": AW.THUNDER_DAMAGE, "cd": AW.THUNDER_COOLDOWN, "note": ""}
		"graviton_well": return {"dmg": [AW.GRAVWELL_DAMAGE_MIN, AW.GRAVWELL_DAMAGE_MAX], "cd": AW.GRAVWELL_TICK, "note": "grows over ~%.1fs while open" % (AW.GRAVWELL_RAMP * 2.0)}
		"omega_swarm": return {"dmg": AW.OMEGA_DAMAGE, "cd": AW.OMEGA_HIT_COOLDOWN, "note": "per orb"}
		"singularity_lance": return {"dmg": AW.SLANCE_DAMAGE, "cd": AW.SLANCE_TICK, "note": ""}
		"prism_array": return {"dmg": AW.PRISM_DAMAGE, "cd": AW.PRISM_TICK, "note": "× %d beams" % AW.PRISM_BEAMS}
		"hailstorm": return {"dmg": AW.HAIL_DAMAGE, "cd": AW.HAIL_COOLDOWN, "note": ""}
		"wraithfire": return {"dmg": AW.WRAITH_DAMAGE, "cd": AW.WRAITH_COOLDOWN, "note": ""}
		"hivemind": return {"dmg": AW.HIVE_DAMAGE, "cd": AW.HIVE_ATTACK_INT, "note": "× %d bats" % AW.HIVE_BATS}
		"annihilator": return {"dmg": AW.ANNI_DAMAGE, "cd": AW.ANNI_COOLDOWN, "note": "total pool per strike, split evenly across up to %d nearest enemies hit (1 target = full amount)" % AW.ANNI_MAX_TARGETS}
		"event_horizon": return {"dmg": [AW.EVENTH_DAMAGE_MIN, AW.EVENTH_DAMAGE_MAX], "cd": AW.EVENTH_TICK, "note": "grows over ~%.1fs while open" % (AW.EVENTH_RAMP * 2.0)}
		_: return {"dmg": -1.0, "cd": 0.0, "note": ""}

func _fmt_num(f: float) -> String:
	return str(int(round(f))) if is_equal_approx(f, round(f)) else ("%.1f" % f)

func _fmt_dmg(d) -> String:
	if d is Array:
		return "%s–%s" % [_fmt_num(float(d[0])), _fmt_num(float(d[1]))]
	var f := float(d)
	return "—" if f < 0.0 else _fmt_num(f)

func _fmt_speed(cd: float) -> String:
	return "—" if cd <= 0.0 else ("%.2f/s" % (1.0 / cd))

func _fmt_category(rarity: String, craftable: bool = false) -> String:
	if rarity == "":
		return "—"
	var label: String = String(rarity).replace("_", " ").capitalize()
	return (label + " (Craft)") if craftable else label

## Weapon sub-tab → its list of WEAPON_TABS-shaped entries ({kind, def_id, label, icon?, code?, from?, ph?}).
## See WEAPON_SUBTAB_ORDER's doc comment above for the player_2/obsolete notes.
func _weapon_subtab_entries(subtab: String) -> Array:
	# "evolve" isn't a WEAPON_TABS key (arena_debug_spawn.gd removed its old static list 2026-08-07,
	# incomplete/inaccurate — see that file's own comments) — it's built live from the real EVOLVE
	# capstones via that same file's static _evolved_entries(), the single source of truth also used by
	# the Spawn Weapon panel's own Evolve tab. "drop"/"fusion"/"unique" are straight WEAPON_TABS
	# passthroughs, except "drop" also gets player_2 folded in (see WEAPON_SUBTAB_ORDER's doc comment above:
	# it isn't in WEAPON_TABS at all, that debug panel doesn't spawn it).
	if subtab == "evolve":
		return ArenaDebugSpawn._evolved_entries()
	var out := (ArenaDebugSpawn.WEAPON_TABS.get(subtab, []) as Array).duplicate()
	if subtab == "drop":
		out.append({"kind": "player_2", "def_id": "", "label": "Player 2"})
	return out

## A WEAPON_TABS entry's canonical metadata: WEAPON_INFO (has "kind") wins, then FUSION_DEFS, then the raw
## entry itself for not-yet-implemented placeholders (label/def_id/icon only, no name/mfr).
func _weapon_entry_info(entry: Dictionary) -> Dictionary:
	var kind := String(entry.get("kind", ""))
	if kind != "" and ArenaWeapons.WEAPON_INFO.has(kind):
		return ArenaWeapons.WEAPON_INFO[kind]
	if kind != "" and ArenaWeapons.FUSION_DEFS.has(kind):
		return ArenaWeapons.FUSION_DEFS[kind]
	return entry

func _weapon_icon(kind: String, info: Dictionary) -> Texture2D:
	var def_id := String(info.get("def_id", ""))
	if def_id != "" and InventoryManager.ITEM_DEFS.has(def_id):
		return InventoryManager.get_icon(def_id)
	var icon_path := String(info.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex := load(icon_path) as Texture2D
		if tex != null:
			return tex
	return InventoryManager.get_icon(def_id)   # placeholder swatch (gray if def_id unknown)

## Real per-perk art from res://assets/hud/weapon perks/<folder>/<perk_id>.png, falling back to the parent
## weapon's own icon wherever no art exists (unmapped kind, or a perk id with no matching file).
func _weapon_perk_icon(kind: String, perk_id: String, fallback: Texture2D) -> Texture2D:
	var folder := String(WEAPON_PERK_FOLDER.get(kind, ""))
	if folder == "":
		return fallback
	var overrides: Dictionary = WEAPON_PERK_ICON_OVERRIDES.get(kind, {})
	var stem := String(overrides.get(perk_id, perk_id))
	var path := "res://assets/hud/weapon perks/%s/%s.png" % [folder, stem]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	return fallback

## Real per-perk art from res://assets/hud/aux perk/<aux_id>/<perk_id>.png — every AUX_POOL key matches its
## own filename exactly (verified against the full folder listing), so no override table is needed here.
func _aux_perk_icon(aux_id: String, perk_id: String, fallback: Texture2D) -> Texture2D:
	var path := "res://assets/hud/aux perk/%s/%s.png" % [aux_id, perk_id]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	return fallback

## Best-effort split of a pool perk's "per" mechanical string into editable (value, unit, tag) components —
## e.g. "+10% damage" → one [10, "%", "damage"]; "-5% cooldown" → one [-5, "%", "cooldown"]; "+10 HP, +2%
## Speed" → two components. Heuristic (regex over comma-separated segments): a handful of perks with no
## leading number in their text at all (e.g. Mortar's "damaging + slowing crater") yield zero components and
## just show blank value cells — accepted, there's no clean number to pull out of those.
var _perk_num_re: RegEx = null
func _parse_per(per: String) -> Array:
	if _perk_num_re == null:
		_perk_num_re = RegEx.new()
		_perk_num_re.compile("([+-]?\\d+(?:\\.\\d+)?)\\s*(%|°|px)?")
	var out: Array = []
	for seg in per.split(","):
		var s := String(seg).strip_edges()
		var m := _perk_num_re.search(s)
		if m == null:
			continue
		var label := (s.substr(0, m.get_start()) + s.substr(m.get_end())).strip_edges()
		label = label.replace("(global)", "").replace("(this weapon)", "").strip_edges()
		if label.length() > 16:
			label = label.substr(0, 16)
		out.append({"value": float(m.get_string(1)), "unit": m.get_string(2), "label": label})
	return out

func _aux_icon(def: Dictionary) -> Texture2D:
	var path := String(def.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	var col: Color = def.get("color", Color(0.6, 0.6, 0.6))
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)

func _lore_for(tab: String, id: String, default_text: String) -> String:
	var sec: Dictionary = _lore_overrides.get(tab, {})
	return String(sec.get(id, default_text))

# ── UI build ─────────────────────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_load_lore_overrides()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.12, 0.98)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.75)
	sb.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", sb)
	var psize := Vector2(1180.0, 700.0)
	var vpz := get_viewport().get_visible_rect().size
	panel.position = ((vpz - psize) * 0.5).clamp(Vector2(8, 8), vpz)
	panel.size = psize
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(8.0, 8.0)
	vb.size = psize - Vector2(16.0, 16.0)
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := _mk_label("WEAPON INFO", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vb.add_child(title)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vb.add_child(top_row)
	for t: String in TAB_ORDER:
		var b := _mk_button(String(TAB_LABELS[t]), func(tk: String = t) -> void: _select_tab(tk))
		_tab_btns[t] = b
		top_row.add_child(b)
	var save_btn := _mk_button("Save", _on_save_lore)
	save_btn.add_theme_color_override("font_color", Color(0.35, 0.9, 0.35))
	top_row.add_child(save_btn)
	var close_btn := _mk_button("Close", toggle)
	close_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	top_row.add_child(close_btn)
	_status = _mk_label("", 11)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	top_row.add_child(_status)

	_global_perk_btn = _mk_button("Perk: Expand All", _on_toggle_all_perks)
	vb.add_child(_global_perk_btn)

	for t: String in TAB_ORDER:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(psize.x - 16.0, psize.y - 190.0)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.visible = false
		vb.add_child(scroll)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(body)
		if t == "weapon":
			# Drop/Evolve/Fusion/Unique sub-tabs — own button row above the (shared) header, then 4
			# persistent row-boxes stacked in the same scroll body, visibility toggled between them.
			var subtab_row := HBoxContainer.new()
			subtab_row.add_theme_constant_override("separation", 4)
			body.add_child(subtab_row)
			for st: String in WEAPON_SUBTAB_ORDER:
				var stb := _mk_button(String(WEAPON_SUBTAB_LABELS[st]), func(stk: String = st) -> void: _select_weapon_subtab(stk))
				_weapon_subtab_btns[st] = stb
				subtab_row.add_child(stb)
			body.add_child(_make_header(t))
			for st2: String in WEAPON_SUBTAB_ORDER:
				var sbox := VBoxContainer.new()
				sbox.add_theme_constant_override("separation", 6)
				sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sbox.visible = false
				body.add_child(sbox)
				_weapon_subtab_box[st2] = sbox
		else:
			body.add_child(_make_header(t))
			var rows_box := VBoxContainer.new()
			rows_box.add_theme_constant_override("separation", 6)
			rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(rows_box)
			_tab_rows_box[t] = rows_box
		_tab_scroll[t] = scroll

	_populate_all()
	_select_tab("weapon")
	_select_weapon_subtab("drop")

func _make_header(tab: String) -> Control:
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	var icon_l := _mk_label("", 11)
	icon_l.custom_minimum_size = Vector2(32.0, 0.0)
	hdr.add_child(icon_l)
	var name_l := _mk_label("Name", 11)
	var code_l := _mk_label("Code", 11)
	var cat_l := _mk_label("Category", 11)
	cat_l.custom_minimum_size = Vector2(100.0, 0.0)
	match tab:
		"weapon":
			name_l.custom_minimum_size = Vector2(130.0, 0.0)
			code_l.custom_minimum_size = Vector2(120.0, 0.0)
			hdr.add_child(name_l); hdr.add_child(code_l); hdr.add_child(cat_l)
			var mfr_l := _mk_label("Manufacturer", 11)
			mfr_l.custom_minimum_size = Vector2(150.0, 0.0)
			hdr.add_child(mfr_l)
			var dmg_l := _mk_label("Damage", 11)
			dmg_l.custom_minimum_size = Vector2(58.0, 0.0)
			hdr.add_child(dmg_l)
			var spd_l := _mk_label("Speed", 11)
			spd_l.custom_minimum_size = Vector2(58.0, 0.0)
			hdr.add_child(spd_l)
			var lore_l := _mk_label("Lore", 11)
			lore_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hdr.add_child(lore_l)
			var perk_l := _mk_label("Perk", 11)
			perk_l.custom_minimum_size = Vector2(60.0, 0.0)
			hdr.add_child(perk_l)
		"aux":
			name_l.custom_minimum_size = Vector2(130.0, 0.0)
			code_l.custom_minimum_size = Vector2(90.0, 0.0)
			hdr.add_child(name_l); hdr.add_child(code_l); hdr.add_child(cat_l)
			var eff_l := _mk_label("Effect", 11)
			eff_l.custom_minimum_size = Vector2(150.0, 0.0)
			hdr.add_child(eff_l)
			var lore_l2 := _mk_label("Lore", 11)
			lore_l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hdr.add_child(lore_l2)
			var perk_l2 := _mk_label("Perk", 11)
			perk_l2.custom_minimum_size = Vector2(60.0, 0.0)
			hdr.add_child(perk_l2)
		_:
			name_l.custom_minimum_size = Vector2(150.0, 0.0)
			code_l.custom_minimum_size = Vector2(130.0, 0.0)
			hdr.add_child(name_l); hdr.add_child(code_l); hdr.add_child(cat_l)
			var eff_l3 := _mk_label("Effect", 11)
			eff_l3.custom_minimum_size = Vector2(230.0, 0.0)
			hdr.add_child(eff_l3)
			var lore_l3 := _mk_label("Lore", 11)
			lore_l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hdr.add_child(lore_l3)
	return hdr

func _select_tab(tab: String) -> void:
	_active_tab = tab
	for t: String in TAB_ORDER:
		(_tab_scroll[t] as ScrollContainer).visible = (t == tab)
		(_tab_btns[t] as Button).add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if t == tab else Color(0.82, 0.9, 1.0))
	var has_perks := tab == "weapon" or tab == "aux"
	_global_perk_btn.visible = has_perks
	if has_perks:
		var key := _weapon_subtab if tab == "weapon" else tab
		_global_perk_btn.text = "Perk: Collapse All" if bool(_expand_state.get(key, false)) else "Perk: Expand All"

## Switch the Weapon tab's own Drop/Evolve/Fusion/Unique sub-tab (independent of the top-level tab row).
func _select_weapon_subtab(st: String) -> void:
	_weapon_subtab = st
	for k: String in WEAPON_SUBTAB_ORDER:
		(_weapon_subtab_box[k] as VBoxContainer).visible = (k == st)
		(_weapon_subtab_btns[k] as Button).add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if k == st else Color(0.82, 0.9, 1.0))
	if _global_perk_btn != null and _active_tab == "weapon":
		_global_perk_btn.text = "Perk: Collapse All" if bool(_expand_state.get(st, false)) else "Perk: Expand All"

# ── Row population ───────────────────────────────────────────────────────────────────────────────────

func _populate_all() -> void:
	_weapon_rows.clear()
	_aux_rows.clear()
	_perk_val_rows.clear()
	_simple_rows = {"shield": [], "hull": [], "thruster": []}

	for subtab: String in WEAPON_SUBTAB_ORDER:
		var box := _weapon_subtab_box[subtab] as VBoxContainer
		for entry: Dictionary in _weapon_subtab_entries(subtab):
			box.add_child(_make_weapon_entry_row(entry, subtab))

	for def: Dictionary in ArenaAux.AUX_DEFS:
		(_tab_rows_box["aux"] as VBoxContainer).add_child(_make_aux_row(def))

	for def_id in InventoryManager.ITEM_DEFS.keys():
		var d: Dictionary = InventoryManager.ITEM_DEFS[def_id]
		var tags: Array = d.get("tags", [])
		if "weapon" in tags or "aux" in tags:
			continue   # weapons/aux already handled above from their own canonical tables
		if "shield" in tags:
			(_tab_rows_box["shield"] as VBoxContainer).add_child(_make_simple_row("shield", String(def_id), d))
		elif "hull" in tags:
			(_tab_rows_box["hull"] as VBoxContainer).add_child(_make_simple_row("hull", String(def_id), d))
		elif "thruster" in tags:
			(_tab_rows_box["thruster"] as VBoxContainer).add_child(_make_simple_row("thruster", String(def_id), d))

## Row for one WEAPON_TABS-shaped entry (Drop/Evolve/Fusion/Unique — see _weapon_subtab_entries). `kind`
## may be "" for a not-yet-implemented placeholder (WEAPON_TABS's own "ph": true convention) — those get a
## dimmed row, a synthesized save-key (kind has none to key by), "Not implemented" in place of Category,
## and Damage/Speed/Perk all read as "—"/empty since none of that data exists for them yet.
func _make_weapon_entry_row(entry: Dictionary, subtab: String) -> Control:
	var kind := String(entry.get("kind", ""))
	var is_ph := bool(entry.get("ph", false)) or kind == ""
	var info := _weapon_entry_info(entry)
	var def_id := String(info.get("def_id", ""))
	var item_def: Dictionary = InventoryManager.ITEM_DEFS.get(def_id, {})
	var icon := _weapon_icon(kind, info)
	var stats := _weapon_stats(kind)
	var pool := _weapon_pool_for(kind)
	# Unique, stable key for Lore/Damage/Speed persistence — real kind when there is one, else a
	# slug of the label (placeholders have no kind to key by, but must not all collide on "").
	var row_id := kind if kind != "" else ("ph_" + String(entry.get("label", "?")).to_lower().replace(" ", "_").replace("-", "_").replace("'", ""))

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	if is_ph:
		outer.modulate = Color(1.0, 1.0, 1.0, 0.55)   # dimmed — matches arena_debug_spawn.gd's own placeholder convention
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(32.0, 32.0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = icon
	hb.add_child(tr)

	var label_txt := String(info.get("label", info.get("name", kind)))
	var code_hint := String(entry.get("code", ""))
	if code_hint != "" and code_hint != label_txt:
		label_txt += " (%s)" % code_hint
	var nm := _mk_label(label_txt, 11)
	nm.custom_minimum_size = Vector2(130.0, 0.0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	hb.add_child(nm)

	var code := _mk_label(kind if kind != "" else "—", 10)
	code.custom_minimum_size = Vector2(120.0, 0.0)
	code.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8))
	hb.add_child(code)

	var cat_txt := "Not implemented" if is_ph else _fmt_category(String(item_def.get("rarity", "")), bool(item_def.get("craftable_from_fragments", false)))
	var cat := _mk_label(cat_txt, 10)
	cat.custom_minimum_size = Vector2(100.0, 0.0)
	hb.add_child(cat)

	var mfr_txt := String(info.get("mfr", ""))
	var mfr := _mk_label(mfr_txt if mfr_txt != "" else "—", 10)
	mfr.custom_minimum_size = Vector2(150.0, 0.0)
	mfr.autowrap_mode = TextServer.AUTOWRAP_WORD
	hb.add_child(mfr)

	var dmg_edit := _mk_input(_lore_for("weapon_dmg", row_id, _fmt_dmg(stats.get("dmg", -1.0))))
	dmg_edit.custom_minimum_size = Vector2(58.0, 0.0)
	hb.add_child(dmg_edit)

	var spd_edit := _mk_input(_lore_for("weapon_spd", row_id, _fmt_speed(float(stats.get("cd", 0.0)))))
	spd_edit.custom_minimum_size = Vector2(58.0, 0.0)
	hb.add_child(spd_edit)

	var lore_edit := TextEdit.new()
	lore_edit.custom_minimum_size = Vector2(180.0, 34.0)
	lore_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	lore_edit.add_theme_font_size_override("font_size", 11)
	lore_edit.text = _lore_for("weapon", row_id, String(ArenaWeapons.WEAPON_LORE.get(kind, "")))
	hb.add_child(lore_edit)

	var perk_btn: Button = null
	var perk_box: Control = null
	if not pool.is_empty():
		perk_box = _make_perk_table("weapon", kind, pool, func(pid: String) -> Texture2D: return _weapon_perk_icon(kind, pid, icon))
		perk_box.visible = false
		perk_btn = Button.new()
		perk_btn.text = "Perk ▸"
		perk_btn.custom_minimum_size = Vector2(60.0, 0.0)
		perk_btn.pressed.connect(func() -> void:
			perk_box.visible = not perk_box.visible
			perk_btn.text = "Perk ▾" if perk_box.visible else "Perk ▸")
		hb.add_child(perk_btn)
	else:
		var ph := _mk_label("—", 10)
		ph.custom_minimum_size = Vector2(60.0, 0.0)
		hb.add_child(ph)

	outer.add_child(hb)
	if perk_box != null:
		outer.add_child(perk_box)
	var from_txt := String(entry.get("from", ""))
	if from_txt != "":
		# "evolve" entries' "from" is the capstone's own EFFECT description (from _evolved_entries()), not
		# a source weapon — "fusion"/"drop"/"unique" entries' "from" (when set) is the "A × B" recipe.
		var prefix := "Effect: " if subtab == "evolve" else ("Fuses: " if subtab == "fusion" else "Source: ")
		var fl := _mk_label(prefix + from_txt, 9)
		fl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD
		outer.add_child(fl)
	var note := String(stats.get("note", ""))
	if note != "":
		var nl := _mk_label(note, 9)
		nl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD
		outer.add_child(nl)

	_weapon_rows.append({"id": row_id, "tab": "weapon", "subtab": subtab, "lore_edit": lore_edit, "dmg_edit": dmg_edit, "spd_edit": spd_edit, "perk_box": perk_box, "perk_btn": perk_btn})
	return outer

func _make_aux_row(def: Dictionary) -> Control:
	var id := String(def.get("id", ""))
	var def_id := "aux_" + id
	var item_def: Dictionary = InventoryManager.ITEM_DEFS.get(def_id, {})
	var icon := _aux_icon(def)
	var pool: Dictionary = ArenaAux.AUX_POOL.get(id, {})

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(32.0, 32.0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = icon
	hb.add_child(tr)

	var nm := _mk_label(String(def.get("name", id)), 11)
	nm.custom_minimum_size = Vector2(130.0, 0.0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	hb.add_child(nm)

	var code := _mk_label(id, 10)
	code.custom_minimum_size = Vector2(90.0, 0.0)
	code.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8))
	hb.add_child(code)

	var cat := _mk_label(_fmt_category(String(item_def.get("rarity", ""))), 10)
	cat.custom_minimum_size = Vector2(100.0, 0.0)
	hb.add_child(cat)

	var eff_edit := _mk_input(_lore_for("aux_effect", id, String(def.get("effect", ""))))
	eff_edit.custom_minimum_size = Vector2(150.0, 0.0)
	hb.add_child(eff_edit)

	var lore_edit := TextEdit.new()
	lore_edit.custom_minimum_size = Vector2(180.0, 34.0)
	lore_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	lore_edit.add_theme_font_size_override("font_size", 11)
	lore_edit.text = _lore_for("aux", id, "")
	hb.add_child(lore_edit)

	var perk_btn: Button = null
	var perk_box: Control = null
	if not pool.is_empty():
		perk_box = _make_perk_table("aux", id, pool, func(pid: String) -> Texture2D: return _aux_perk_icon(id, pid, icon))
		perk_box.visible = false
		perk_btn = Button.new()
		perk_btn.text = "Perk ▸"
		perk_btn.custom_minimum_size = Vector2(60.0, 0.0)
		perk_btn.pressed.connect(func() -> void:
			perk_box.visible = not perk_box.visible
			perk_btn.text = "Perk ▾" if perk_box.visible else "Perk ▸")
		hb.add_child(perk_btn)
	else:
		var ph := _mk_label("—", 10)
		ph.custom_minimum_size = Vector2(60.0, 0.0)
		hb.add_child(ph)

	outer.add_child(hb)
	if perk_box != null:
		outer.add_child(perk_box)

	_aux_rows.append({"id": id, "tab": "aux", "lore_edit": lore_edit, "eff_edit": eff_edit, "perk_box": perk_box, "perk_btn": perk_btn})
	return outer

func _make_simple_row(tab: String, id: String, def: Dictionary) -> Control:
	var icon := InventoryManager.get_icon(id)

	var outer := VBoxContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(32.0, 32.0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = icon
	hb.add_child(tr)

	var nm := _mk_label(String(def.get("name", id)), 11)
	nm.custom_minimum_size = Vector2(150.0, 0.0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	hb.add_child(nm)

	var code := _mk_label(id, 10)
	code.custom_minimum_size = Vector2(130.0, 0.0)
	code.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8))
	hb.add_child(code)

	var cat := _mk_label(_fmt_category(String(def.get("rarity", ""))), 10)
	cat.custom_minimum_size = Vector2(100.0, 0.0)
	hb.add_child(cat)

	var eff := _mk_label(String(def.get("desc", "")), 10)
	eff.custom_minimum_size = Vector2(230.0, 0.0)
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD
	hb.add_child(eff)

	var lore_edit := TextEdit.new()
	lore_edit.custom_minimum_size = Vector2(180.0, 34.0)
	lore_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	lore_edit.add_theme_font_size_override("font_size", 11)
	lore_edit.text = _lore_for(tab, id, "")
	hb.add_child(lore_edit)

	outer.add_child(hb)
	(_simple_rows[tab] as Array).append({"id": id, "tab": tab, "lore_edit": lore_edit})
	return outer

## The Perk expand sub-table: Icon | Perk name | Max rank | editable value column(s) — one SpinBox per
## numeric component parsed out of the perk's "per" string (_parse_per), each tagged with a short unit
## label instead of the old flavor "desc" paragraph (removed entirely, per request). Perks with more than
## one stat type (e.g. "-10% AoE, +15% damage") get one column per value; column count = the WIDEST perk
## in this specific pool, so every row in the sub-table lines up. Edits here are a tuning/reference
## notepad — saved via the top "Save" button into weapon_info_lore.cfg, NOT wired into the actual
## gameplay formulas (those live as separate hardcoded literals throughout arena_weapons.gd/arena_aux.gd).
func _make_perk_table(tab: String, owner_id: String, pool: Dictionary, icon_resolver: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.16, 0.9)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.25, 0.35, 0.55)
	sb.set_content_margin_all(6.0)
	sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
	var pnl := PanelContainer.new()
	pnl.add_theme_stylebox_override("panel", sb)
	pnl.add_child(box)

	var parsed: Dictionary = {}   # perk_id → Array of {value, unit, label}
	var max_cols := 0
	for pid in pool.keys():
		var segs := _parse_per(String((pool[pid] as Dictionary).get("per", "")))
		parsed[pid] = segs
		max_cols = maxi(max_cols, segs.size())

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	var i_hdr := _mk_label("", 10)
	i_hdr.custom_minimum_size = Vector2(28.0, 0.0)
	hdr.add_child(i_hdr)
	var n_hdr := _mk_label("Perk", 10)
	n_hdr.custom_minimum_size = Vector2(140.0, 0.0)
	hdr.add_child(n_hdr)
	var m_hdr := _mk_label("Max", 10)
	m_hdr.custom_minimum_size = Vector2(40.0, 0.0)
	hdr.add_child(m_hdr)
	if max_cols > 0:
		var v_hdr := _mk_label("Value(s) — editable", 10)
		v_hdr.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
		hdr.add_child(v_hdr)
	box.add_child(hdr)

	for pid in pool.keys():
		var pd: Dictionary = pool[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(28.0, 28.0)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = icon_resolver.call(pid)
		row.add_child(tr)

		var nm := _mk_label(String(pd.get("name", "")), 10)
		nm.custom_minimum_size = Vector2(140.0, 0.0)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(nm)

		var maxr := int(pd.get("max", 0))
		var mx := _mk_label(str(maxr) if maxr > 0 else "∞", 10)
		mx.custom_minimum_size = Vector2(40.0, 0.0)
		row.add_child(mx)

		var segs: Array = parsed[pid]
		for i in max_cols:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 3)
			cell.custom_minimum_size = Vector2(108.0, 0.0)
			if i < segs.size():
				var seg: Dictionary = segs[i]
				var tag := _mk_label(String(seg.get("label", "")), 9)
				tag.custom_minimum_size = Vector2(44.0, 0.0)
				tag.clip_text = true
				tag.tooltip_text = String(seg.get("label", ""))
				cell.add_child(tag)
				var spin := SpinBox.new()
				spin.min_value = -99999.0
				spin.max_value = 99999.0
				spin.step = 0.01
				spin.value = float(seg.get("value", 0.0))
				spin.suffix = String(seg.get("unit", ""))
				spin.custom_minimum_size = Vector2(58.0, 0.0)
				spin.add_theme_font_size_override("font_size", 11)
				cell.add_child(spin)
				var pkey := "%s:%s:%s:%d" % [tab, owner_id, pid, i]
				if _perk_val_overrides.has(pkey):
					spin.value = float(_perk_val_overrides[pkey])
				_perk_val_rows.append({"key": pkey, "spin": spin})
			row.add_child(cell)

		box.add_child(row)

	return pnl

func _on_toggle_all_perks() -> void:
	var is_weapon := _active_tab == "weapon"
	var key := _weapon_subtab if is_weapon else _active_tab
	var new_state := not bool(_expand_state.get(key, false))
	_expand_state[key] = new_state
	var rows: Array = _weapon_rows if is_weapon else _aux_rows
	for r: Dictionary in rows:
		if is_weapon and String(r.get("subtab", "")) != _weapon_subtab:
			continue   # only affect the currently-visible Drop/Evolve/Fusion/Unique sub-tab's rows
		var pb: Control = r.get("perk_box")
		var btn: Button = r.get("perk_btn")
		if pb != null:
			pb.visible = new_state
			btn.text = "Perk ▾" if new_state else "Perk ▸"
	_global_perk_btn.text = "Perk: Collapse All" if new_state else "Perk: Expand All"

# ── Lore persistence ─────────────────────────────────────────────────────────────────────────────────

func _load_lore_overrides() -> void:
	_lore_overrides.clear()
	_perk_val_overrides.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	for section in cfg.get_sections():
		if section == "perk_vals":
			for key in cfg.get_section_keys(section):
				_perk_val_overrides[key] = float(cfg.get_value(section, key, 0.0))
			continue
		var d: Dictionary = {}
		for key in cfg.get_section_keys(section):
			d[key] = String(cfg.get_value(section, key, ""))
		_lore_overrides[section] = d

## Saves everything editable in the panel: Lore (all 5 tabs), Weapon Damage/Speed, Aux Effect, and every
## perk-table value SpinBox — all into one file, one section per field kind. Reference/tuning data only —
## see _make_perk_table's doc comment on why perk values aren't wired into actual gameplay formulas.
func _on_save_lore() -> void:
	var cfg := ConfigFile.new()
	var all_rows: Array = _weapon_rows + _aux_rows + _simple_rows["shield"] + _simple_rows["hull"] + _simple_rows["thruster"]
	var count := 0
	for r: Dictionary in all_rows:
		var txt := String((r["lore_edit"] as TextEdit).text).strip_edges()
		if txt != "":
			cfg.set_value(String(r["tab"]), String(r["id"]), txt)
			count += 1
	for r: Dictionary in _weapon_rows:
		var dmg_txt := String((r["dmg_edit"] as LineEdit).text).strip_edges()
		if dmg_txt != "":
			cfg.set_value("weapon_dmg", String(r["id"]), dmg_txt)
			count += 1
		var spd_txt := String((r["spd_edit"] as LineEdit).text).strip_edges()
		if spd_txt != "":
			cfg.set_value("weapon_spd", String(r["id"]), spd_txt)
			count += 1
	for r: Dictionary in _aux_rows:
		var eff_txt := String((r["eff_edit"] as LineEdit).text).strip_edges()
		if eff_txt != "":
			cfg.set_value("aux_effect", String(r["id"]), eff_txt)
			count += 1
	for r: Dictionary in _perk_val_rows:
		cfg.set_value("perk_vals", String(r["key"]), (r["spin"] as SpinBox).value)
		count += 1
	cfg.save(CFG_PATH)
	_status.text = "Saved %d entrie(s)" % count

# ── Widget helpers (default theme font throughout — no custom font override) ───────────────────────────
func _mk_label(text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

## Compact editable text field — font size matches _mk_label's item-name size (11), per request, so every
## data-entry field (Weapon Damage/Speed, Aux Effect, and — via TextEdit's own override at each call site —
## Lore) reads at the same size instead of the theme's larger default LineEdit font.
func _mk_input(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.add_theme_font_size_override("font_size", 11)
	return e
