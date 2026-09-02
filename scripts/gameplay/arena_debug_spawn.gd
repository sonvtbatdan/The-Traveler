extends CanvasLayer
## Debug spawner + dev-mode HUD for the arena.
## Quick Spawn panel (Dev:on only) — bottom-left, 4-column enemy grid, bosses last with red bg.
##
## Hotkeys (F-keys always active regardless of DEV_MODE):
##   F3        Boss Edit (toggle)
##   F4        Skip run — simulate a full run's rewards (coin/field-drop/fragments/level-ups) then jump to RUN OVER
##   F5        Asteroid field near player       Shift+F5  = clear
##   F6        Planet menu
##   F7        Wave editor
##   F9        Comet near player                Shift+F9  = clear
##   F10       Planet + moons near player       Shift+F10 = clear
##   F11       Space structure (cycles types)   Shift+F11 = clear
##   F12       (removed — use Dev:on → Weapon panel)
## (Bottom-center Level Up / Fire-rate +/- row removed — force level-up now lives in
## arena_hud_buttons.gd's dev column as the +LEVEL button.)

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const WaveDir   := preload("res://scripts/gameplay/arena_wave_director.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const CreepInfoPanelScript := preload("res://scripts/ui/hud/creep_info_panel.gd")   # see _ready()'s apply_overrides() call
const CreepEditModeScript  := preload("res://scripts/ui/boss_edit/creep_edit_mode.gd")   # see _ready()'s apply_chain_overrides() call
const ArenaToastScript := preload("res://scripts/ui/hud/arena_toast.gd")   # BOSS FIGHT button no-op feedback
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")   # for WEAPON_INFO/FUSION_DEFS code names
const Item3DIcon   := preload("res://scripts/ui/hud/item_3d_icon.gd")      # Boss tab cells for defs with a "boss_glb"
# Weapon roster for the Dev → Weapon panel. Four tabs (WEAPON_TAB_ORDER, below):
#   drop     = obtained from drops, incl. the 2 "narratively fusion" kinds that aren't real FUSION_DEFS
#              recipes (Venomancer, Yari Jaeger — see "fusion"'s own comment)
#   evolve   = NOT a WEAPON_TABS key — built live from the real EVOLVE capstones (3/weapon), see
#              _evolved_entries(). Replaced a static hand-picked list here 2026-08-07, on request (it was
#              incomplete — 6 entries, not each weapon's real 3 choices, 2 not even coded in CAPSTONES).
#   fusion   = the game's actual FUSION_DEFS recipes (combine 2 owned max-level weapons), audited 2026-08-07
#              against arena_weapons.gd's real implementation — see that key's own comment for what changed.
#   unique   = the 10 fragment-crafted uniques (split out of "drop" 2026-08-07, on request, to match
#              weapon_info_panel.gd's own Drop/Evolve/Fusion/Unique split — same weapons, just their own tab
#              instead of buried at the tail of Drop)
# The old dynamic "Evolved"/"Combined" tabs and the static "obsolete" tab are gone (removed from
# WEAPON_TAB_ORDER/_all_weapon_tabs(), same 2026-08-07 request) — Evolved's content is now just "evolve"
# above; Combined's content is superseded by the audited "fusion" above; obsolete (vampire_host/
# toxic_ballistic/singularities old reworks + a retired Shield Generator placeholder) only ever duplicated
# concepts spawnable elsewhere — its dict entry is left in place, unreferenced, in case it's wanted back.
## Weapon-cell edge, in px. 2026-08-23 ("Bảng spawn weapon tôi không tìm thấy Jeager"): cells used to be
## icon-ONLY, so finding a weapon meant recognising its inventory art — and several of those don't look like
## what the arena draws (Yari Jeager's icon is a ship with a blue blade; the arena draws a humanoid mech).
## Every cell carries its name now, which needs a slightly bigger cell to stay legible: 48 -> 62. Nothing was
## actually missing from the table. Named here because the panel's width and `_rebuild_weapon_grid()`'s
## per-cell size both need it, and they had already drifted apart (the grid was hardcoding 48).
const WEAPON_CELL := 62

# `kind` = arena_weapons code kind (spawnable on click). Entries with "ph": true are PLACEHOLDERS — the weapon
# isn't implemented yet, so the cell renders dimmed + non-spawnable (a gray placeholder icon) until it lands.
# `from` (optional) = the source recipe, shown in the tooltip. NOTE: a few PDF→code kind mappings are
# best-guess (Jeager→zsword, Little Man→mortar, Viper→snake) — relabel if wrong.
const WEAPON_TABS := {
	"drop": [
		{"kind": "gatling_gun",   "def_id": "gatling_gun",  "label": "Gatling Gun"},
		{"kind": "death_beam",    "def_id": "death_beam",        "label": "Death Beam"},
		# 2026-08-23: def_id was "orbitals", which is not an ITEM_DEFS key — InventoryManager.get_icon() fell
		# through to _make_placeholder() and this cell rendered as a blank grey square. The real def (and what
		# WEAPON_INFO has always used for this kind) is "defensive_orbitals".
		{"kind": "defensive_orbitals",   "def_id": "defensive_orbitals",      "label": "Defensive Orbitals"},
		{"kind": "striker",   "def_id": "",              "label": "Striker", "icon": "res://assets/weaponry/ND-OIF-F.png"},
		{"kind": "shooter",   "def_id": "swarm_host",    "label": "Shooter", "icon": "res://assets/weaponry/shooter.png"},
		{"kind": "chemtrail", "def_id": "chemtrail",     "label": "Chemtrail"},
		{"kind": "rift_maker",      "def_id": "rift_maker",    "label": "Rift Maker"},
		{"kind": "arc",       "def_id": "arc",           "label": "Arc Lightning Chain"},
		{"kind": "yari", "def_id": "yari",     "label": "Yari"},
		{"kind": "z_sword",    "def_id": "z_sword",       "label": "Z-Sword"},
		{"kind": "mortar",      "def_id": "mortar",          "label": "Little Man"},
		{"kind": "dragons_breath",     "def_id": "dragons_breath",         "label": "Dragon's Breath"},
		{"kind": "aliwa", "def_id": "boomerang",     "label": "Boomerang"},
		{"kind": "gauss",     "def_id": "gauss",  "label": "Gauss Pulser"},
		{"kind": "viper",     "def_id": "viper",   "label": "Viper"},
		{"kind": "swarm",     "def_id": "",              "label": "Swarm", "icon": "res://assets/inventory/Swarm.png"},
		{"kind": "ultrasonicator",     "def_id": "ultrasonicator",    "label": "Ultrasonicator"},
		{"kind": "homing_missile",    "def_id": "homing_missile","label": "Homing Missile"},   # temp impl (copied from enemy missile launcher) — not in the Corp doc
		# Moved in from "fusion" 2026-08-07 — neither is an actual FUSION_DEFS recipe (not obtained by
		# combining 2 owned max-level weapons); both are ordinary standalone droppable kinds, their mfr
		# just narratively hints at a dual-origin. See the "fusion" key's own audit comment below.
		{"kind": "venomancer",  "def_id": "venomancer",  "label": "Venomancer"},
		{"kind": "yari_jaeger", "def_id": "yari_jaeger", "label": "Yari Jeager"},
	],
	"unique": [
		{"kind": "thunderhead",      "def_id": "thunderhead",      "label": "Thunderhead"},        # fragment-crafted unique
		{"kind": "graviton_well",    "def_id": "graviton_well",    "label": "Graviton Well"},       # fragment-crafted unique
		{"kind": "omega_swarm",      "def_id": "omega_swarm",      "label": "Omega Swarm"},         # fragment-crafted unique
		{"kind": "singularity_lance","def_id": "singularity_lance","label": "Singularity Lance"},   # fragment-crafted unique
		{"kind": "prism_array",      "def_id": "prism_array",      "label": "Prism Array"},         # fragment-crafted unique
		{"kind": "hailstorm",        "def_id": "hailstorm",        "label": "Hailstorm"},           # fragment-crafted unique
		{"kind": "wraithfire",       "def_id": "wraithfire",       "label": "Wraithfire"},          # fragment-crafted unique
		{"kind": "hivemind",         "def_id": "hivemind",         "label": "Hivemind"},            # fragment-crafted unique
		{"kind": "annihilator",      "def_id": "annihilator",      "label": "Annihilator"},         # fragment-crafted unique
		{"kind": "event_horizon",    "def_id": "event_horizon",    "label": "Event Horizon"},       # fragment-crafted unique — all 9 restored 2026-08-06, back to full parity with graviton_well
	],
	# "evolve" is intentionally NOT a key here anymore — the old static list was a hand-picked, incomplete
	# design-doc excerpt (6 entries — not each weapon's real 3 evolve choices, 2 didn't correspond to
	# anything CAPSTONES implements). The Evolve tab is built live from CAPSTONES instead (accurate, all
	# 3/weapon) — see _evolved_entries() / _weapon_tab_entries()'s special case for "evolve".
	#
	# fusion — audited 2026-08-07 against the game's actual FUSION_DEFS (arena_weapons.gd): all 6 real
	# recipes are FULLY IMPLEMENTED (each has a working activate_<kind>() + fire/tick logic — verified by
	# reading the code, not assumed), so none of them should be "ph": true. Two bugs fixed from the prior
	# hand-curated list: "Vampire Host" was wrongly marked ph:true with no kind (it's real — kind
	# "vampire_host", recipe is Ultrasonicator × Swarm, not "× Offensive Orbitals" as it said); "Singularities"
	# was the same — real kind "singularities", recipe Rift Maker × Gauss Pulser. "Toxic Ballistic" was
	# missing entirely (it had been filed under the now-removed "obsolete" tab instead, despite being a
	# real, working FUSION_DEFS recipe — Homing Missile × Chemtrail — just narratively superseded by
	# Venomancer; included here since it's still genuinely fusable in-game). Venomancer and Yari Jaeger
	# moved OUT to "drop" above — neither is an actual FUSION_DEFS recipe. "KM Quantum Beam Rifle" and
	# "Drone Cannon" remain genuine placeholders (ph: true) — truly not in FUSION_DEFS, never implemented.
	"fusion": [
		{"kind": "",            "def_id": "",              "label": "KM Quantum Beam Rifle",        "code": "Jedi Laser",  "from": "Gatling Gun × Death Beam", "icon": "res://assets/inventory/KM-QBM-200.png", "ph": true},
		{"kind": "",            "def_id": "",              "label": "Drone Cannon",                 "code": "Candy Crush", "from": "Gatling Gun × Defensive Orbitals", "icon": "res://assets/inventory/NC-DC-F.png", "ph": true},
		{"kind": "vampire_host", "def_id": "offensive_orbitals", "label": "Vampire Host",           "from": "Ultrasonicator × Swarm", "icon": "res://assets/inventory/Vampire Host.png"},
		{"kind": "overcharger", "def_id": "gauss",  "label": "Overcharger",                  "from": "Arc Lightning Chain × Gauss Pulser", "icon": "res://assets/inventory/Overcharger.png"},
		{"kind": "carnage",     "def_id": "gatling_gun",   "label": "Thermitic Auto Cannon",        "from": "Dragon's Breath × Gatling Gun"},
		{"kind": "predator",    "def_id": "death_beam",        "label": "Predator",                     "from": "Viper × Death Beam"},
		{"kind": "toxic_ballistic", "def_id": "homing_missile", "label": "Toxic Ballistic",         "from": "Homing Missile × Chemtrail"},
		{"kind": "singularities", "def_id": "defensive_orbitals", "label": "Singularities",         "from": "Rift Maker × Gauss Pulser", "icon": "res://assets/inventory/Singularities.png"},
	],
	"obsolete": [
		{"kind": "vampire_host",    "def_id": "offensive_orbitals",     "label": "Vampire Host (old)",  "from": "Swarm + Sonic — reworked"},
		{"kind": "toxic_ballistic", "def_id": "homing_missile", "label": "Toxic Ballistic",     "from": "homing + chemtrail → Venomancer"},
		{"kind": "singularities",   "def_id": "defensive_orbitals",       "label": "Singularities (old)", "from": "orbital + void — reworked"},
		{"kind": "", "def_id": "shield_generator", "label": "Shield Generator", "from": "retired item", "ph": true},
	],
}
const WEAPON_TAB_ORDER: Array[String] = ["drop", "evolve", "fusion", "unique"]
const WEAPON_TAB_LABELS := {"drop": "Drop", "evolve": "Evolve", "fusion": "Fusion", "unique": "Unique"}
# "evolve" is NOT a WEAPON_TABS key — it's built live from the real EVOLVE capstones (3/weapon, e.g.
# "Dragon's Breath: The Sun") by _evolved_entries(); see _weapon_tab_entries()'s special case for it.
# In-fiction base name where WEAPON_INFO's label differs from the design name (red_x is the Dragon's Breath weapon).
const BASE_NAME_OVERRIDE := {"dragons_breath": "Dragon's Breath"}
const SFX_UICLICK := preload("res://assets/audio/sfx/uiclick.wav")

# Enemy order in the quick-spawn grid — normals first, bosses last.
const QUICK_SPAWN_ORDER: Array[String] = [
	"fly", "bee", "bug", "swarm",
	"diver", "dragonfly", "spider", "centipede",
	"shooter", "beamer", "missile", "animalhornet", "squid",
	"sentinel", "dummy",
	"sentinel1", "sentinel2", "sentinel3", "sentinel4", "sentinelleader",
	"alien1", "alien2", "alien3", "alien4", "alien5", "alien6", "alien7", "alien8",
	"bismuth1", "bismuth2", "bismuth3", "bismuth4", "bismuth5", "bismuth6",
	"fleet1", "fleet2", "fleet3", "fleet4", "fleetleader",
	"ghost1", "ghost2", "ghost3", "ghost4", "ghost5",
	"pirate1", "pirate2", "piratespear", "piratespearshield",
	"magma1", "magma2", "magma3", "magma4", "magma5", "magma6", "magma7",
	"stone1", "stone2", "stone3", "stone4", "stone5", "stone6", "stone7",
	"ash1", "ash2", "ash3", "ash4", "ashleader",
	"pros1", "pros2", "pros3", "pros4", "pros5", "pros6", "pros7", "pros8", "prosmotherblank",
	# Atlantic sea creatures (2026-08-13) — data-only wire-up, no wave timeline yet; this is the easiest way
	# to test-spawn them in the meantime (see docs/enemy.md's matching changelog entry).
	"shark", "killer_whale", "whale", "spermwhale", "atlantic_squid", "stingray", "stingray_elite",
	"atlantic_centipede", "hammerhead", "killerwhale", "shark_elite", "spermwhale2",
	"elephant", "chromeleon", "metalfly",
]
const QUICK_BOSS_IDS: Array[String] = ["elephant", "chromeleon", "metalfly", "boss", "Nautilus"]   # "boss" = "The Skull" (Volcanic 3D boss, 2026-09-01); "Nautilus" = Atlantic 3D boss (2026-09-02)
# Boss-tab cell size. Bigger than the Enemies grid's 48 because a "boss_glb" cell is a live 3D render, and a
# spinning model in a 48px box reads as a smudge (see _make_quick_cell).
const BOSS_CELL := 92
const ENEMY_CELL := 48

# Enemies tab "Map:" filter (2026-08-31). Each QUICK_SPAWN_ORDER id is bucketed by the `assets/map/<id>/`
# folder in its def's icon path (so a new sprite dropped into a map folder + a def entry needs no wiring
# here — e.g. ash1 → Volcanic). "all" shows the whole roster; ids with no map folder fall under "Space".
# CREEP_MAP_ORDER is the dropdown order for the buckets that turn out non-empty.
const CREEP_MAP_ORDER: Array[String] = ["electric", "volcanic", "atlantic", "mechanic", "arctic", "cosmic", "mystic", "space"]
const CREEP_MAP_NAMES := {
	"all": "All", "electric": "Electric", "volcanic": "Volcanic", "atlantic": "Atlantic",
	"mechanic": "Mechanic", "arctic": "Arctic", "cosmic": "Cosmic", "mystic": "Mystic", "space": "Space",
}


# Set true to show the hotkey panel + fire-rate controls at startup.
const DEV_MODE := false

const SIM_KILLS        := 150  # F4 skip-run: creep kills to simulate (drives coin + field-drop rolls)
const SIM_BOSSES       := 2    # F4 skip-run: boss kills to simulate (drives fragment rolls)
const SIM_TARGET_LEVEL := 15   # F4 skip-run: in-run level to simulate reaching (drives attribute points)

var _rng := RandomNumberGenerator.new()
var _struct_cycle: int = 0   # F11 steps through the four structure types
var _dev_ui_root: Control = null
var _creep_panel:  Panel = null   # Quick Spawn (creep) — button-toggled, default hidden
var _weapon_panel: Panel = null   # Spawn Weapon — button-toggled, default hidden
var _weapon_grid: GridContainer = null         # current-tab cell grid (rebuilt on tab switch)
var _weapon_tab: String = "drop"               # active weapon tab
var _weapon_tab_btns: Dictionary = {}          # tab id → Button (for highlight)
# Creep panel tabs: Enemies (quick-spawn grid) + Fleet (saved-fleet list + preview) + Boss (QUICK_BOSS_IDS)
var _creep_tab: String = "enemies"
var _creep_tab_btns: Dictionary = {}
var _creep_enemies_content: Control = null
var _creep_fleet_content: Control = null
var _creep_boss_content: Control = null
var _creep_map_option: OptionButton = null    # Enemies tab "Map:" dropdown
var _creep_enemy_grid: GridContainer = null   # rebuilt when the Map filter changes
var _creep_map_ids: Array[String] = []        # parallel to _creep_map_option items
var _creep_map_filter: String = "all"
var _creep_stop_btn: Button = null            # header "Stop" ⇄ "Resume"
var _spawn_stopped: bool = false              # true = every wave director's _process is halted
var _fleet_list_vbox: VBoxContainer = null
var _fleet_preview: Control = null             # floating 500×500 formation preview (hover)
var _fleet_icon_cache: Dictionary = {}
var _hotkey_panel: Panel = null   # Hotkey help (right side) — button-toggled, default hidden
var _click_player: AudioStreamPlayer = null   # uiclick — local + ALWAYS so it sounds while paused

func _ready() -> void:
	# TEMP DIAGNOSTIC — see the note on arena.gd's _ready() timers. Safe to delete once the cause is found.
	var _t0 := Time.get_ticks_usec()
	# 2026-08-14 bug fix ("tôi chỉnh segment thành 8, tắt game mở lại vẫn bị reset về 3" — the SAVED override
	# was correct on disk, but never got READ back). Root cause: arena.gd skips creating BOTH wave-director
	# nodes entirely on the Atlantic map (`if _map_id != "atlantic":`, a deliberate 2026-08-08 debug guard,
	# unrelated to this feature) — and `apply_overrides()`/`apply_chain_overrides()` were ONLY ever called from
	# a wave director's own `_ready()`. No wave director on Atlantic → nothing ever applies the saved
	# HP/Move/Shoot or CHAIN overrides to `WaveDir.ENEMY_DEFS` (a static var, reset to its literal hardcoded
	# values on every fresh process launch) → Quick Spawn (this file reads `WaveDir.ENEMY_DEFS` directly, line
	# ~549/604/687) silently used the un-overridden defaults all game. Within the SAME session it looked fixed
	# because Creep Edit's own live-apply mutates that same static dict directly, in memory — the override file
	# itself was always correct, it just never got loaded back in on a real restart. This debug-spawn panel is
	# instantiated unconditionally on every map (unlike either wave director), so applying both override kinds
	# here too guarantees they're loaded regardless of which map/wave-director setup is active — redundant
	# (and harmless) wherever a wave director already does it, load-bearing where none exists.
	CreepInfoPanelScript.apply_overrides(WaveDir.ENEMY_DEFS)
	CreepEditModeScript.apply_chain_overrides(WaveDir.ENEMY_DEFS)
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 60   # all Dev:on panels above the mortar/fatboy blast distortion (shockwave layer 8) + the HUD; below modals (settings 100)
	add_to_group("arena_debug_spawn")
	_rng.randomize()
	_build_fire_rate_ui()
	_build_hotkey_panel()
	print("[arena-startup]   debug_spawn fire_rate+hotkey UI: %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0)); _t0 = Time.get_ticks_usec()
	# _build_quick_spawn_panel()/_build_weapon_spawn_panel() moved to lazy first-open (see toggle_creep_panel()/
	# toggle_weapon_panel()) — they were loading a thumbnail per enemy/weapon (~430ms combined) on every single
	# arena boot even though both panels start hidden and most players never open them.
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = SFX_UICLICK
	_click_player.bus = "SFX"
	add_child(_click_player)
	if _dev_ui_root != null:
		_dev_ui_root.visible = DEV_MODE

func _click() -> void:
	if _click_player != null:
		_click_player.play()

## Open/close the Weapon Edit mode (FP/TP editor for weapon sprites).
func _on_clear_weapons() -> void:
	_click()
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons != null and weapons.has_method("clear_all_weapons"):
		weapons.clear_all_weapons()

## Dev-only: acquire every base weapon so their animations can be previewed. `acquire_weapon` honours the
## MAX_WEAPONS equip cap (fills the first N slots) and its own guards (e.g. Player 2 companion) — extras are
## simply ignored. To preview a specific weapon, CLEAR then use the per-weapon cells below.
func _on_grant_all_weapons() -> void:
	_click()
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons == null or not weapons.has_method("acquire_weapon"):
		return
	for kind: String in (ArenaWeapons.WEAPON_INFO as Dictionary).keys():
		if kind == "player_2":
			continue   # companion — needs an existing weapon to copy; skip in a blind grant
		weapons.acquire_weapon(kind)

func _on_edit_weapon() -> void:
	_click()
	var we := get_tree().get_first_node_in_group("weapon_edit")
	if we != null and we.has_method("toggle"):
		we.toggle()

func set_dev_ui_visible(v: bool) -> void:
	if _dev_ui_root != null:
		_dev_ui_root.visible = v
	if not v:
		# The creep/weapon/hotkey panels are button-toggled — reset them hidden when dev turns off.
		if _creep_panel != null:  _creep_panel.visible = false
		if _weapon_panel != null: _weapon_panel.visible = false
		if _hotkey_panel != null: _hotkey_panel.visible = false
		_hide_fleet_preview()

func toggle_creep_panel() -> void:
	if _creep_panel == null:
		_build_quick_spawn_panel()   # first open: pay the ~80-enemy thumbnail-load cost now instead of at boot
	if _creep_panel != null:
		_creep_panel.visible = not _creep_panel.visible
		if not _creep_panel.visible:
			_hide_fleet_preview()

func toggle_weapon_panel() -> void:
	if _weapon_panel == null:
		_build_weapon_spawn_panel()   # first open: pay the weapon thumbnail-load cost now instead of at boot
	if _weapon_panel != null:
		_weapon_panel.visible = not _weapon_panel.visible

func toggle_hotkey_panel() -> void:
	if _hotkey_panel != null:
		_hotkey_panel.visible = not _hotkey_panel.visible

## Shared invisible root for the dev popups built elsewhere in this file (Quick Spawn / Weapon / Hotkey
## panels). Was also the host for the bottom-center Level Up / Fire-rate row (removed — +LEVEL moved to
## arena_hud_buttons.gd) and the bottom-left Jeager sweep-delay tuning slider (removed 2026-09-01 once the
## value was dialled in; `YARI_SWEEP_DELAY` in arena_weapons.gd + get/set_yari_sweep_delay() are kept).
func _build_fire_rate_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_dev_ui_root = root

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_F4:
			_skip_run()
			get_viewport().set_input_as_handled()
		KEY_F5:
			if key.shift_pressed: _clear("arena_asteroids")
			else: _spawn_asteroids()
			get_viewport().set_input_as_handled()
		KEY_F9:
			if key.shift_pressed: _clear("arena_comets")
			else: _spawn_comet()
			get_viewport().set_input_as_handled()
		KEY_F10:
			if key.shift_pressed: _clear_planets()
			else: _spawn_planet_with_moons()
			get_viewport().set_input_as_handled()
		KEY_F11:
			if key.shift_pressed: _clear("arena_structures")
			else: _spawn_structure_cycle()
			get_viewport().set_input_as_handled()

## Debug: skip the rest of the current run — grants roughly what a real run of SIM_KILLS kills / SIM_BOSSES
## bosses / SIM_TARGET_LEVEL levels would have paid out (coins, field-drop weapon/aux tokens, boss fragments,
## attribute points from leveling), then jumps straight to the RUN OVER / BOSS ELIMINATED screen. Persistent
## rewards only — in-run-only state (equipped weapons/aux, HP) is simply discarded, same as any other run
## ending. `victory` (2026-08-07: the END RUN dev button now asks WIN/LOSE first via a popup — see
## arena_hud_buttons.gd's _on_end_run) just picks which end-screen framing force_end_run() shows; F4's
## keybind still calls this with no arg, defaulting to the original LOSE/RUN OVER behavior.
func _skip_run(victory: bool = false) -> void:
	if MetaManager.has_method("simulate_run_rewards"):
		MetaManager.simulate_run_rewards(SIM_KILLS, SIM_BOSSES)
	if GameManager.has_method("add_xp") and GameManager.has_method("xp_to_next"):
		var total_xp := 0.0
		for lvl in range(1, SIM_TARGET_LEVEL):
			total_xp += float(GameManager.xp_to_next(lvl))
		GameManager.add_xp(total_xp)
	var arena := get_parent()
	if arena != null and arena.has_method("force_end_run"):
		arena.call("force_end_run", victory)
	print("[debug] skip run (%s) — simulated %d kills / %d bosses / level %d" % ["WIN" if victory else "LOSE", SIM_KILLS, SIM_BOSSES, SIM_TARGET_LEVEL])

## Debug: jump straight to the loaded timeline's final-boss finale (arena_hud_buttons.gd's BOSS FIGHT
## button, next to END RUN) — clears the field and fast-forwards past every remaining regular wave, so the
## boss spawns almost immediately for testing the fight + the BOSS ELIMINATED / RUN OVER screens. No-op if
## the currently loaded map's timeline doesn't end in a solo is_boss entry (2026-09-01: Volcanic
## (`vocalnic.json` → `boss`/The Skull) and Electric (`elecforest.json` → `metalfly`) both end in a solo
## is_boss entry at t=1200; "default"/Space and Atlantic have none, so the button is a no-op there).
## Used to only `print()` this (console-only — invisible in a built/played game, which is
## exactly why a no-op here read as "the button is broken"); now also surfaces via ArenaToast so the result
## is visible on screen either way.
func _jump_to_boss_fight() -> void:
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd == null or not wd.has_method("debug_jump_to_final_boss"):
		print("[debug] BOSS FIGHT — no wave director found")
		ArenaToastScript.show(self, "BOSS FIGHT — no wave director found")
		return
	var ok := bool(wd.call("debug_jump_to_final_boss"))
	print("[debug] BOSS FIGHT jump -> %s" % ("spawning shortly" if ok else "loaded timeline has no final-boss entry"))
	ArenaToastScript.show(self, "BOSS FIGHT — boss incoming" if ok else "BOSS FIGHT — this map's timeline has no boss entry")

func _near_player() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	var base := cam.global_position if cam != null else Vector2.ZERO
	return base + Vector2(_rng.randf_range(-180.0, 180.0), _rng.randf_range(-120.0, 120.0))

func _spawn_asteroids() -> void:
	var layer := get_tree().get_first_node_in_group("arena_asteroids")
	if layer == null:
		return
	var n: int = layer.spawn_field_near(_near_player())
	print("[debug] F5 asteroid field spawned (%d rocks)" % n)

func _spawn_comet() -> void:
	var layer := get_tree().get_first_node_in_group("arena_comets")
	if layer == null:
		return
	layer.spawn_comet_near(_near_player())
	print("[debug] F9 comet spawned")

func _spawn_planet_with_moons() -> void:
	var layer := get_tree().get_first_node_in_group("arena_planets")
	if layer == null:
		return
	var pl: Node2D = layer.spawn_planet_with_moons(_near_player(), _rng)
	print("[debug] F10 planet+moons spawned: %d moon(s)" % pl._moons.size())

func _spawn_structure_cycle() -> void:
	var layer := get_tree().get_first_node_in_group("arena_structures")
	if layer == null:
		return
	var t: int = _struct_cycle % 3   # pillars (type 3) disabled for now → set 4 to re-enable
	_struct_cycle += 1
	layer.spawn_structure_near(_near_player(), t, _rng)
	print("[debug] F11 structure spawned: %s" % ArenaStructure.TYPE_NAMES[t])

func _clear(group: String) -> void:
	var layer := get_tree().get_first_node_in_group(group)
	if layer != null and layer.has_method("clear_debug"):
		layer.clear_debug()
	print("[debug] cleared ", group)

func _clear_planets() -> void:
	for n in get_tree().get_nodes_in_group("debug_planet"):
		if is_instance_valid(n):
			n.queue_free()
	print("[debug] cleared debug planets")

# ── Quick Spawn panel ──────────────────────────────────────────────────────────

func _build_quick_spawn_panel() -> void:
	if _dev_ui_root == null:
		return
	const CELL  := ENEMY_CELL
	const COLS  := 4
	const HDR_H := 28
	const TAB_H := 26
	const MAP_H := 24           # Enemies tab "Map:" dropdown row
	const W     := COLS * CELL   # 192 px
	const GRID_H := CELL * 4    # 4 visible rows = 192 px

	var panel := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = UiPalette.SURFACE
	ps.set_corner_radius_all(0)
	ps.border_width_left = 1; ps.border_width_right  = 1
	ps.border_width_top  = 1; ps.border_width_bottom = 1
	ps.border_color = UiPalette.WIRE_2
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left   = 0.0; panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left   = 8.0
	panel.offset_right  = 8.0 + W
	panel.offset_top    = -(HDR_H + TAB_H + MAP_H + GRID_H + 16)
	panel.offset_bottom = -8.0
	panel.visible = false               # button-toggled (default hidden even when dev:on)
	_creep_panel = panel
	_dev_ui_root.add_child(panel)
	UiPalette.scanlines(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Header row — Clear (wipe every live creep) + Stop/Resume (pause the wave director's spawning). Split out
	# of the old single "CLEAR ALL" button (2026-08-31) so a dev can freeze incoming waves without also
	# clearing the field, and vice-versa.
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size = Vector2(0.0, float(HDR_H))
	hdr.add_theme_constant_override("separation", 2)
	vbox.add_child(hdr)
	var btn_clear := Button.new()
	btn_clear.text = "Clear"
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.add_theme_font_size_override("font_size", 10)
	btn_clear.tooltip_text = "Remove every creep currently on the arena"
	btn_clear.pressed.connect(_clear_quick_spawn)
	hdr.add_child(btn_clear)
	_creep_stop_btn = Button.new()
	_creep_stop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creep_stop_btn.add_theme_font_size_override("font_size", 10)
	_creep_stop_btn.tooltip_text = "Pause / resume the wave director's spawning"
	_creep_stop_btn.pressed.connect(_toggle_spawn_stopped)
	hdr.add_child(_creep_stop_btn)
	_update_spawn_stop_btn()

	# Tab row — Enemies / Fleet / Boss
	var tabs := HBoxContainer.new()
	tabs.custom_minimum_size = Vector2(0.0, float(TAB_H))
	tabs.add_theme_constant_override("separation", 2)
	vbox.add_child(tabs)
	_creep_tab_btns.clear()
	for tab_def: Array in [["enemies", "Enemies"], ["fleet", "Fleet"], ["boss", "Boss"]]:
		var tb := Button.new()
		tb.text = String(tab_def[1])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 10)
		tb.pressed.connect(_select_creep_tab.bind(String(tab_def[0])))
		tabs.add_child(tb)
		_creep_tab_btns[String(tab_def[0])] = tb

	vbox.add_child(HSeparator.new())

	# Content holder — both tab panels overlap full-rect; visibility is toggled.
	var content := Control.new()
	content.custom_minimum_size = Vector2(float(W), float(GRID_H))
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	# Enemies tab — a "Map:" filter dropdown above the quick-spawn grid (4 visible rows, scrolls for row 5+).
	# The dropdown defaults to the map the player is currently in; they can switch to any other set after.
	var evbox := VBoxContainer.new()
	evbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	evbox.add_theme_constant_override("separation", 1)
	content.add_child(evbox)
	_creep_enemies_content = evbox

	var map_row := HBoxContainer.new()
	map_row.custom_minimum_size = Vector2(0.0, float(MAP_H))
	map_row.add_theme_constant_override("separation", 3)
	evbox.add_child(map_row)
	var map_lbl := Label.new()
	map_lbl.text = "Map:"
	map_lbl.add_theme_font_size_override("font_size", 10)
	map_row.add_child(map_lbl)
	_creep_map_option = OptionButton.new()
	_creep_map_option.add_theme_font_size_override("font_size", 10)
	_creep_map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creep_map_option.focus_mode = Control.FOCUS_NONE
	_creep_map_option.item_selected.connect(_on_creep_map_selected)
	map_row.add_child(_creep_map_option)

	var escroll := ScrollContainer.new()
	escroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	escroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	escroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	evbox.add_child(escroll)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	escroll.add_child(grid)
	_creep_enemy_grid = grid
	_populate_creep_map_option()   # fills the dropdown + picks the current-map default
	_rebuild_enemy_grid()

	# Fleet tab — list of saved fleets (formation preview on hover, click to spawn).
	var fscroll := ScrollContainer.new()
	fscroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	fscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(fscroll)
	_creep_fleet_content = fscroll
	_fleet_list_vbox = VBoxContainer.new()
	_fleet_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_list_vbox.add_theme_constant_override("separation", 2)
	fscroll.add_child(_fleet_list_vbox)

	# Boss tab (2026-08-24) — the QUICK_BOSS_IDS roster, split out of the Enemies grid. Cells are bigger
	# (BOSS_CELL) because a boss whose def carries a "boss_glb" renders as a LIVE spinning 3D model rather
	# than a flat thumbnail, and that needs the room to read.
	var bscroll := ScrollContainer.new()
	bscroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bscroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(bscroll)
	_creep_boss_content = bscroll
	var bgrid := GridContainer.new()
	bgrid.columns = 2
	bgrid.add_theme_constant_override("h_separation", 0)
	bgrid.add_theme_constant_override("v_separation", 0)
	bscroll.add_child(bgrid)
	for type_id: String in QUICK_BOSS_IDS:
		bgrid.add_child(_make_quick_cell(type_id, BOSS_CELL))

	# Floating 500×500 formation preview (shown while hovering a fleet row) — to the right of both panels.
	_fleet_preview = _FleetPreview.new()
	_fleet_preview.editor = self
	_fleet_preview.anchor_left = 0.0; _fleet_preview.anchor_right = 0.0
	_fleet_preview.anchor_top  = 1.0; _fleet_preview.anchor_bottom = 1.0
	_fleet_preview.offset_left   = 8.0 + W + 8.0 + W + 8.0
	_fleet_preview.offset_right  = 8.0 + W + 8.0 + W + 8.0 + 500.0
	_fleet_preview.offset_top    = -8.0 - 500.0
	_fleet_preview.offset_bottom = -8.0
	_fleet_preview.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_fleet_preview.visible = false
	_dev_ui_root.add_child(_fleet_preview)

	_select_creep_tab("enemies")

## Switch the creep panel between the Enemies grid and the Fleet list.
func _select_creep_tab(tab_id: String) -> void:
	_creep_tab = tab_id
	for id: String in _creep_tab_btns.keys():
		var active: bool = id == tab_id
		(_creep_tab_btns[id] as Button).modulate = UiPalette.INK if active else UiPalette.MUTED
	if _creep_enemies_content != null:
		_creep_enemies_content.visible = (tab_id == "enemies")
	if _creep_fleet_content != null:
		_creep_fleet_content.visible = (tab_id == "fleet")
	if _creep_boss_content != null:
		_creep_boss_content.visible = (tab_id == "boss")
	if tab_id == "fleet":
		_rebuild_fleet_list()   # refresh in case fleets were edited since last open
	else:
		_hide_fleet_preview()

# ── Enemies tab: Map filter ────────────────────────────────────────────────────

## map_id → Array[String] of QUICK_SPAWN_ORDER ids (bosses excluded — own tab) whose def icon lives under
## res://assets/map/<id>/…  . An id whose icon has no map folder is bucketed as "space".
func _enemy_ids_by_map() -> Dictionary:
	const MARK := "/assets/map/"
	var out: Dictionary = {}
	for type_id: String in QUICK_SPAWN_ORDER:
		if QUICK_BOSS_IDS.has(type_id):
			continue
		var icon := String((WaveDir.ENEMY_DEFS.get(type_id, {}) as Dictionary).get("icon", ""))
		var mid := "space"
		var k := icon.find(MARK)
		if k != -1:
			mid = icon.substr(k + MARK.length()).get_slice("/", 0)
		if not out.has(mid):
			out[mid] = [] as Array
		(out[mid] as Array).append(type_id)
	return out

## The map the player is currently in — arena's snapshotted `_map_id`, else MetaManager. The classic
## "default"/Space arena has no themed roster of its own, so it defaults to the full list ("all").
func _current_map_bucket() -> String:
	var mid := ""
	var a := get_tree().get_first_node_in_group("arena")
	if a != null and is_instance_valid(a):
		mid = String(a.get("_map_id"))
	if mid == "" and typeof(MetaManager) != TYPE_NIL:
		mid = String(MetaManager.selected_map_id)
	return "all" if (mid == "" or mid == "default") else mid

## Fill the "Map:" dropdown: "All" first, then every non-empty bucket in CREEP_MAP_ORDER. Selects the
## current map's set by default (falls back to "All" if that map has no enemies in QUICK_SPAWN_ORDER).
func _populate_creep_map_option() -> void:
	if _creep_map_option == null:
		return
	_creep_map_ids.clear()
	_creep_map_option.clear()
	_creep_map_option.add_item(String(CREEP_MAP_NAMES["all"]))
	_creep_map_ids.append("all")
	var by_map := _enemy_ids_by_map()
	for mid: String in CREEP_MAP_ORDER:
		if by_map.has(mid) and not (by_map[mid] as Array).is_empty():
			_creep_map_option.add_item(String(CREEP_MAP_NAMES.get(mid, mid.capitalize())))
			_creep_map_ids.append(mid)
	var sel := _creep_map_ids.find(_current_map_bucket())
	if sel < 0:
		sel = 0
	_creep_map_option.selected = sel
	_creep_map_filter = _creep_map_ids[sel]

func _on_creep_map_selected(idx: int) -> void:
	if idx < 0 or idx >= _creep_map_ids.size():
		return
	_creep_map_filter = _creep_map_ids[idx]
	_rebuild_enemy_grid()

## Repopulate the Enemies grid for the active Map filter. "all" = the whole QUICK_SPAWN_ORDER (minus bosses).
func _rebuild_enemy_grid() -> void:
	if _creep_enemy_grid == null:
		return
	for c in _creep_enemy_grid.get_children():
		_creep_enemy_grid.remove_child(c)   # remove NOW (queue_free alone leaves them a frame → transient dupes)
		c.queue_free()
	var ids: Array = []
	if _creep_map_filter == "all":
		for type_id: String in QUICK_SPAWN_ORDER:
			if not QUICK_BOSS_IDS.has(type_id):
				ids.append(type_id)
	else:
		ids = (_enemy_ids_by_map().get(_creep_map_filter, [] as Array) as Array)
	for type_id: String in ids:
		_creep_enemy_grid.add_child(_make_quick_cell(type_id, ENEMY_CELL))

## Rebuild the Fleet tab's list from res://fleet_layout.cfg.
func _rebuild_fleet_list() -> void:
	if _fleet_list_vbox == null:
		return
	for c in _fleet_list_vbox.get_children():
		c.queue_free()
	var fleets := _load_fleets()
	if fleets.is_empty():
		var lbl := Label.new()
		lbl.text = "(no fleets saved)"
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", UiPalette.MUTED)
		_fleet_list_vbox.add_child(lbl)
		return
	for fl: Dictionary in fleets:
		var nm := String(fl.get("name", "Fleet"))
		var b := Button.new()
		b.text = nm
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0.0, 24.0)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.tooltip_text = "Click to spawn this fleet"
		var cap_fl := fl
		b.mouse_entered.connect(func() -> void: _show_fleet_preview(cap_fl))
		b.mouse_exited.connect(func() -> void: _hide_fleet_preview())
		b.pressed.connect(func() -> void: _spawn_fleet(cap_fl))
		_fleet_list_vbox.add_child(b)

func _load_fleets() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load("res://fleet_layout.cfg") != OK:
		return []
	var data = cfg.get_value("fleets", "data", [])
	return data if data is Array else []

func _show_fleet_preview(fl: Dictionary) -> void:
	if _fleet_preview == null:
		return
	_fleet_preview.set_fleet(fl)
	_fleet_preview.visible = true
	_fleet_preview.move_to_front()   # above the weapon/hotkey panels

func _hide_fleet_preview() -> void:
	if _fleet_preview != null:
		_fleet_preview.visible = false

## Icon for a fleet preview cell (by enemy id), cached.
func _fleet_icon(id: String) -> Texture2D:
	if _fleet_icon_cache.has(id):
		return _fleet_icon_cache[id]
	var d: Dictionary = WaveDir.ENEMY_DEFS.get(id, {})
	var path := String(d.get("icon", ""))
	var tex: Texture2D = _load_thumb(path) if path != "" else null
	_fleet_icon_cache[id] = tex
	return tex

## Spawn a fleet EXACTLY like Wave Edit does — route through the wave director's _deploy_fleet so the
## carrier logic (mothership docking/flee/respawn), per-slot sizes and off-screen entry all match the real
## wave deploy. Only falls back to independent-unit spawning if no wave director is present.
func _spawn_fleet(fl: Dictionary) -> void:
	if _deploy_fleet_via_director(String(fl.get("name", ""))):
		return
	var slots: Array = fl.get("slots", [])
	var sum := Vector2.ZERO
	var cnt := 0
	for s: Dictionary in slots:
		if not (s.get("enemies", []) as Array).is_empty():
			sum += (s.get("pos", Vector2.ZERO) as Vector2)
			cnt += 1
	if cnt == 0:
		return
	var centroid := sum / float(cnt)
	var cam := get_viewport().get_camera_2d()
	var base := cam.global_position if cam != null else Vector2.ZERO
	for s: Dictionary in slots:
		var enemies: Array = s.get("enemies", [])
		if enemies.is_empty():
			continue
		var id := String(enemies[_rng.randi() % enemies.size()])
		var pos := base + ((s.get("pos", Vector2.ZERO) as Vector2) - centroid)
		_spawn_enemy_at(id, pos)

## Deploy a fleet by name through the wave director — the SAME code path Wave Edit uses. Returns false if
## the director is unavailable (so the caller can fall back).
func _deploy_fleet_via_director(fleet_name: String) -> bool:
	if fleet_name == "":
		return false
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd == null or not wd.has_method("_deploy_fleet"):
		return false
	wd.call("_deploy_fleet", fleet_name)
	return true

## First saved fleet whose any slot contains `unit_id` — used to deploy a carrier fleet from a lone
## Enemies-tab click on a mothership unit.
func _fleet_name_containing(unit_id: String) -> String:
	for fl: Dictionary in _load_fleets():
		for s: Dictionary in (fl.get("slots", []) as Array):
			for en in (s.get("enemies", []) as Array):
				if String(en) == unit_id:
					return String(fl.get("name", ""))
	return ""

func _make_quick_cell(type_id: String, cell_size: int) -> Control:
	var is_boss: bool = QUICK_BOSS_IDS.has(type_id)
	var def: Dictionary = WaveDir.ENEMY_DEFS.get(type_id, {})

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(cell_size, cell_size)
	btn.focus_mode    = Control.FOCUS_NONE
	btn.tooltip_text  = String(def.get("name", type_id))   # e.g. "The Skull" for the Volcanic boss
	btn.clip_contents = true

	var _make_style := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(0)
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = border
		return s

	var has_glb: bool = String(def.get("boss_glb", "")) != ""
	if has_glb:
		# A live 3D cell keeps the red BORDER that marks it as a boss but drops the red fill (2026-08-24, on
		# request: "nền icon màu đỏ"). These models are dark and unlit against a background — red-on-dark
		# buried metalfly's silhouette, where a flat sprite sat on top of the red perfectly well.
		btn.add_theme_stylebox_override("normal",  _make_style.call(Color(0.05, 0.05, 0.07, 0.88), Color(0.65, 0.15, 0.10, 0.80)))
		btn.add_theme_stylebox_override("hover",   _make_style.call(Color(0.12, 0.09, 0.10, 0.94), Color(1.00, 0.35, 0.25, 1.00)))
		btn.add_theme_stylebox_override("pressed", _make_style.call(Color(0.02, 0.02, 0.03, 0.96), Color(0.65, 0.15, 0.10, 0.80)))
	elif is_boss:
		btn.add_theme_stylebox_override("normal",  _make_style.call(Color(0.42, 0.05, 0.05, 0.80), Color(0.65, 0.15, 0.10, 0.80)))
		btn.add_theme_stylebox_override("hover",   _make_style.call(Color(0.65, 0.10, 0.08, 0.92), Color(1.00, 0.35, 0.25, 1.00)))
		btn.add_theme_stylebox_override("pressed", _make_style.call(Color(0.25, 0.03, 0.03, 0.95), Color(0.65, 0.15, 0.10, 0.80)))
	else:
		btn.add_theme_stylebox_override("normal",  _make_style.call(UiPalette.SURFACE_2, UiPalette.WIRE_2))
		btn.add_theme_stylebox_override("hover",   _make_style.call(UiPalette.SURFACE_3, UiPalette.ACCENT_DIM))
		btn.add_theme_stylebox_override("pressed", _make_style.call(UiPalette.ACCENT_DIM, UiPalette.WIRE_2))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# A boss whose def carries "boss_glb" shows the LIVE 3D model, slowly spinning, instead of a flat
	# thumbnail (2026-08-24, "Đặt metalfly (dạng 3D) vào tab này"). Item3DIcon keeps mouse_filter IGNORE, so
	# it sits harmlessly under this Button and the click still lands. Falls through to the PNG path below if
	# the glb can't be built, and every boss without the key (elephant, chromeleon) is unchanged.
	var glb_path: String = String(def.get("boss_glb", ""))
	if glb_path != "":
		const PAD := 3
		var icon3d: Control = Item3DIcon.new()
		# setup() OWNS the control's size (it assigns `size` itself). Anchors must NOT be used with it: an
		# earlier version anchored FULL_RECT with -3 offsets first, and setup()'s later `size =` write
		# recomputed those offsets against the button's size AT THAT MOMENT — zero, since nothing had been
		# laid out yet — so once the grid sized the button the icon resolved to roughly DOUBLE the cell and
		# spilled out of the panel. Fixed size + fixed position, no anchors, can't be reflowed.
		if not icon3d.call("setup", glb_path, float(cell_size - PAD * 2), float(cell_size - PAD * 2)):
			icon3d.free()   # never entered the tree
		else:
			btn.add_child(icon3d)
			icon3d.position = Vector2(PAD, PAD)
			btn.pressed.connect(_spawn_quick_enemy.bind(type_id, btn))
			return btn

	var icon_path: String = String(def.get("icon", ""))
	if icon_path != "":
		var thumb := _load_thumb(icon_path)
		if thumb != null:
			var tr := TextureRect.new()
			tr.texture = thumb
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.offset_left = 3; tr.offset_right  = -3
			tr.offset_top  = 3; tr.offset_bottom = -3
			btn.add_child(tr)

	btn.pressed.connect(_spawn_quick_enemy.bind(type_id, btn))
	return btn

func _load_thumb(icon: String) -> Texture2D:
	var src: String = EnemyScript._resolve_sprite(icon)   # prefer assets/enemiesHD/, fall back to assets/enemies/
	if src.ends_with(".sheet.png"):
		return _sheet_first_frame(src)
	if src.ends_with(".gif"):
		var g := GifLoader.load_gif(src)
		if g != null and g.has_meta("gif_frames"):
			var frames: Array = g.get_meta("gif_frames")
			if not frames.is_empty():
				return frames[0] as Texture2D
		return null
	var t := load(src) as Texture2D
	if t == null and src != icon:
		t = load(icon) as Texture2D   # HD failed to load (e.g. not imported) → standard sprite
	return t

## First frame of a `<name>.sheet.png` as an AtlasTexture, sliced by its sibling `<name>.sheet.json` (same
## {cols, w, h} format arena_enemy.gd's _load_sheet_frames reads). Without this a sheet-icon cell showed the
## WHOLE strip squeezed into the button — every frame side by side, unreadable. It only became obvious once
## the Boss tab's cells went up to BOSS_CELL, but the three sheet-icon bosses looked like that in the
## Enemies grid too. Falls back to the raw sheet if the JSON is missing or unparseable.
func _sheet_first_frame(path: String) -> Texture2D:
	var atlas := load(path) as Texture2D
	if atlas == null:
		return null
	var json_path := path.replace(".sheet.png", ".sheet.json")
	if not FileAccess.file_exists(json_path):
		return atlas
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return atlas
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		return atlas
	var fw := int((data as Dictionary).get("w", atlas.get_width()))
	var fh := int((data as Dictionary).get("h", atlas.get_height()))
	if fw <= 0 or fh <= 0:
		return atlas
	var at := AtlasTexture.new()
	at.atlas = atlas
	at.region = Rect2(0, 0, fw, fh)
	return at

## Shift+Click a quick-spawn cell to mass-spawn BULK_SPAWN_COUNT at once instead of 1 — a fast way
## to reach a stress-test population (e.g. reproduce the arena's creep-count FPS cliff) without
## waiting for the wave timeline to build up naturally over real playtime.
const BULK_SPAWN_COUNT := 300

func _spawn_quick_enemy(type_id: String, btn: Button) -> void:
	var cam := get_viewport().get_camera_2d()
	var base := cam.global_position if cam != null else Vector2.ZERO
	# Bulk-spawn is for building a stress-test horde, never for bosses — and since bosses now correctly
	# bypass the alive cap (see _spawn_enemy_at), a Shift+click on a boss cell would otherwise drop 300
	# uncapped bosses on the field. The cap used to absorb that mistake; it no longer does.
	var n := BULK_SPAWN_COUNT if (Input.is_key_pressed(KEY_SHIFT) and not QUICK_BOSS_IDS.has(type_id)) else 1
	var spawned := 0
	for _i in n:
		var pos := base + Vector2(_rng.randf_range(-500.0, 500.0), _rng.randf_range(-270.0, 270.0))
		if _spawn_enemy_at(type_id, pos):
			spawned += 1
	if spawned == 0:
		_flash_cap_blocked(btn, type_id)

## Instantiate one enemy of `type_id` at `pos` (shared by quick-spawn + fleet-spawn). Routes through
## the wave director's own _spawn() when available so debug-spawned enemies go through the SAME
## path as real gameplay spawns — including the MAX_ALIVE cap. Falls back to the old direct-instantiate
## path only if no wave director is present at all. Returns false when nothing was actually spawned
## (unknown type_id, or the director rejected it — most commonly the MAX_ALIVE/MAX_ALIVE_V2 population
## cap, see arena_wave_director_v2.gd's _spawn_def) so _spawn_quick_enemy can surface that to the user
## instead of the click looking like a no-op.
func _spawn_enemy_at(type_id: String, pos: Vector2) -> bool:
	var src: Dictionary = WaveDir.ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return false
	# A carrier (mothership) spawned alone makes no sense — deploy its full fleet, exactly like Wave Edit.
	if String(src.get("behavior", "")) == "mothership":
		if _deploy_fleet_via_director(_fleet_name_containing(type_id)):
			return true
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null:
		# `is_boss` MUST be true for a boss (2026-08-24 bug: clicking a boss cell did nothing). The director's
		# one authoritative cap gate — v1's _spawn, v2's _spawn_def — bypasses MAX_ALIVE only for
		# `is_boss`/`elite` defs, and this call passed a hardcoded `false`. So a boss quick-spawn was
		# rejected outright whenever the field was at cap, which during real play it essentially always is:
		# the boss is exactly the thing a dev wants to force in on top of a busy field, not the one thing
		# that can't be. Pre-existing for all three bosses; only noticed once metalfly got its own tab.
		return wd.call("_spawn", type_id, pos, QUICK_BOSS_IDS.has(type_id)) != null
	var def := src.duplicate()
	var mgr := get_tree().get_first_node_in_group("enemy_manager")
	var e: Node
	if def.has("boss_script"):
		var bs := load(String(def["boss_script"])) as GDScript
		e = bs.new() if bs != null else EnemyScript.new()
	else:
		e = EnemyScript.new()
	e.call("configure", type_id, mgr, def)
	e.set("position", pos)
	get_tree().current_scene.add_child(e)
	return true

const CAP_FLASH_COLOR := Color(1.0, 0.25, 0.2)
const CAP_FLASH_TIME  := 0.4

## Every Quick Spawn attempt for `type_id` was rejected — the one real way _spawn_enemy_at can silently do
## nothing is the wave director's population cap (MAX_ALIVE / MAX_ALIVE_V2). Flash the cell red so the click
## doesn't read as a no-op, plus a console line with the concrete reason for anyone watching the log.
func _flash_cap_blocked(btn: Button, type_id: String) -> void:
	print("[debug] quick-spawn '%s' blocked — enemy population is at cap" % type_id)
	if not is_instance_valid(btn):
		return
	btn.modulate = CAP_FLASH_COLOR
	var tw := create_tween()
	tw.tween_property(btn, "modulate", Color.WHITE, CAP_FLASH_TIME)

## "CLEAR ALL" — wipes every live creep on the arena (real wave-director spawns included, not just ones
## quick-spawned through this panel), matching what a dev testing the arena actually wants: a clean field.
func _clear_quick_spawn() -> void:
	for e: Node in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e):
			e.queue_free()

## "Stop" freezes every wave director (V1 / V2 / test spawner — all sit in group "wave_director") by
## halting its _process/_physics_process, so no new creeps arrive; "Resume" restarts them. A director's
## local clock only advances while it processes (see arena_wave_director_v2.gd `_run_t`), so the timeline
## picks up exactly where it left off. Debug-only — nothing else touches the directors' processing.
func _toggle_spawn_stopped() -> void:
	_spawn_stopped = not _spawn_stopped
	for wd: Node in get_tree().get_nodes_in_group("wave_director"):
		if is_instance_valid(wd):
			wd.set_process(not _spawn_stopped)
			wd.set_physics_process(not _spawn_stopped)
	_update_spawn_stop_btn()
	print("[debug] wave spawning ", "STOPPED" if _spawn_stopped else "RESUMED")

func _update_spawn_stop_btn() -> void:
	if _creep_stop_btn == null:
		return
	_creep_stop_btn.text = "Resume" if _spawn_stopped else "Stop"
	_creep_stop_btn.add_theme_color_override("font_color",
		UiPalette.GOOD if _spawn_stopped else UiPalette.AMBER)

# ── Weapon Spawn panel ──────────────────────────────────────────────────────────

func _build_weapon_spawn_panel() -> void:
	if _dev_ui_root == null:
		return
	const CELL  := WEAPON_CELL
	const COLS  := 4
	const HDR_H := 40
	const TAB_H := 26
	const ROWS  := 5                # fixed VISIBLE grid height (Evolve is the tallest tab overall — scrolls; this just sets the window)
	const W     := COLS * CELL
	var grid_h: int = CELL * ROWS

	var panel := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = UiPalette.SURFACE
	ps.set_corner_radius_all(0)
	ps.border_width_left = 1; ps.border_width_right  = 1
	ps.border_width_top  = 1; ps.border_width_bottom = 1
	ps.border_color = UiPalette.WIRE_2
	panel.add_theme_stylebox_override("panel", ps)
	# Bottom-left, just to the RIGHT of the creep panel so both can be open together.
	panel.anchor_left   = 0.0; panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left   = 8.0 + W + 8.0
	panel.offset_right  = 8.0 + W + 8.0 + W
	panel.offset_top    = -(HDR_H + TAB_H + grid_h + 18)
	panel.offset_bottom = -8.0
	panel.visible = false
	_weapon_panel = panel
	_dev_ui_root.add_child(panel)
	UiPalette.scanlines(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# ── Header: title + CLEAR + EDIT ──
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size = Vector2(0.0, float(HDR_H))
	hdr.add_theme_constant_override("separation", 0)
	vbox.add_child(hdr)

	var lbl_title := Label.new()
	lbl_title.text = "Spawn Weapon"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_title.add_theme_font_size_override("font_size", 11)
	lbl_title.add_theme_color_override("font_color", UiPalette.INK)
	hdr.add_child(lbl_title)

	var btn_all := Button.new()
	btn_all.text = "ALL"
	btn_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_all.add_theme_font_size_override("font_size", 10)
	btn_all.tooltip_text = "Grant every weapon (fills up to the %d equip slots)" % ArenaWeapons.MAX_WEAPONS
	btn_all.pressed.connect(_on_grant_all_weapons)
	hdr.add_child(btn_all)

	var btn_clear := Button.new()
	btn_clear.text = "CLEAR"
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.add_theme_font_size_override("font_size", 10)
	btn_clear.tooltip_text = "Remove all equipped weapons"
	btn_clear.pressed.connect(_on_clear_weapons)
	hdr.add_child(btn_clear)

	var btn_edit := Button.new()
	btn_edit.text = "EDIT"
	btn_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_edit.add_theme_font_size_override("font_size", 10)
	btn_edit.tooltip_text = "Open the Weapon Edit mode (place FP / TP on weapon sprites)"
	btn_edit.pressed.connect(_on_edit_weapon)
	hdr.add_child(btn_edit)

	# ── Tab row: Drop / Evolve / Fusion / Unique ──
	var tabs := HBoxContainer.new()
	tabs.custom_minimum_size = Vector2(0.0, float(TAB_H))
	tabs.add_theme_constant_override("separation", 2)
	vbox.add_child(tabs)
	_weapon_tab_btns.clear()
	for tab_id: String in _all_weapon_tabs():
		var tb := Button.new()
		tb.text = _weapon_tab_label(tab_id)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 10)
		tb.pressed.connect(_select_weapon_tab.bind(tab_id))
		tabs.add_child(tb)
		_weapon_tab_btns[tab_id] = tb

	vbox.add_child(HSeparator.new())

	# ── Cell grid (rebuilt per active tab) — scrollable so the Evolve tab's ~50 cells fit the fixed panel ──
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(float(W), float(grid_h))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	scroll.add_child(grid)
	_weapon_grid = grid
	_select_weapon_tab(_weapon_tab)

## Switch the Weapon panel to `tab_id`, highlight its button, and rebuild the cell grid.
func _select_weapon_tab(tab_id: String) -> void:
	if tab_id not in _all_weapon_tabs():
		return
	_weapon_tab = tab_id
	for id: String in _weapon_tab_btns.keys():
		var active: bool = id == tab_id
		(_weapon_tab_btns[id] as Button).modulate = UiPalette.INK if active else UiPalette.MUTED
	_rebuild_weapon_grid()

func _rebuild_weapon_grid() -> void:
	if _weapon_grid == null:
		return
	for c in _weapon_grid.get_children():
		c.queue_free()
	for w: Dictionary in _weapon_tab_entries(_weapon_tab):
		_weapon_grid.add_child(_make_weapon_cell(w, WEAPON_CELL))

## The weapon's Code Name (short nickname, e.g. "Gatling"). Implemented weapons resolve it from the live
## registry via their kind; placeholders carry an explicit "code"; everything else falls back to the full name.
func _weapon_code_name(w: Dictionary) -> String:
	var kind := String(w.get("kind", ""))
	if kind != "":
		var info: Dictionary = ArenaWeapons.WEAPON_INFO.get(kind, ArenaWeapons.FUSION_DEFS.get(kind, {}))
		var lbl := String(info.get("label", ""))
		if lbl != "":
			return lbl
	return String(w.get("code", w.get("label", "")))

func _make_weapon_cell(w: Dictionary, cell_size: int) -> Control:
	var is_ph: bool = bool(w.get("ph", false))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(cell_size, cell_size)
	btn.focus_mode    = Control.FOCUS_NONE
	var code := _weapon_code_name(w)
	var full := String(w["label"])
	var tip := code                          # Code Name first (e.g. "Gatling")
	if full != code:
		tip += "  —  " + full                # then the full name (e.g. "Gatling Gun")
	if w.has("from"):
		tip += "\n(" + String(w["from"]) + ")"
	if is_ph:
		tip += "\n[placeholder — chưa implement]"
	btn.tooltip_text  = tip
	btn.clip_contents = true
	btn.disabled      = is_ph

	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(0)
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = border
		return s
	btn.add_theme_stylebox_override("normal",   mk.call(UiPalette.SURFACE_2, UiPalette.WIRE_2))
	btn.add_theme_stylebox_override("hover",    mk.call(UiPalette.SURFACE_3, UiPalette.ACCENT_DIM))
	btn.add_theme_stylebox_override("pressed",  mk.call(UiPalette.ACCENT_DIM, UiPalette.WIRE_2))
	btn.add_theme_stylebox_override("disabled", mk.call(UiPalette.SURFACE, UiPalette.WIRE))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# Prefer an explicit `icon` path (used for placeholder weapons whose art exists but aren't in ITEM_DEFS yet);
	# otherwise fall back to the inventory icon by def_id.
	var tex: Texture2D = null
	var icon_path := String(w.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	else:
		tex = InventoryManager.get_icon(String(w["def_id"]))
	const NAME_H := 15.0   # bottom strip reserved for the name label below
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 3; tr.offset_right  = -3
		tr.offset_top  = 3; tr.offset_bottom = -NAME_H
		tr.modulate = Color(1, 1, 1, 0.35) if is_ph else Color(1, 1, 1, 1)   # dim placeholder icons
		btn.add_child(tr)

	# Name strip (2026-08-23) — the cell's own label, so the grid can be scanned by NAME instead of by
	# recognising art. Same text as the tooltip's first line; the full name stays in the tooltip.
	var name_lbl := Label.new()
	name_lbl.text = code
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.add_theme_color_override("font_color",
		UiPalette.MUTED if is_ph else UiPalette.INK)
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	name_lbl.add_theme_constant_override("shadow_outline_size", 2)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_left = 1; name_lbl.offset_right = -1
	name_lbl.offset_top = -NAME_H; name_lbl.offset_bottom = -1
	btn.add_child(name_lbl)

	if not is_ph:
		var cap := String(w.get("capstone", ""))
		if cap != "":
			btn.pressed.connect(_spawn_evolved.bind(String(w["kind"]), cap))   # Evolved tab: grant base + evolution
		else:
			btn.pressed.connect(_spawn_weapon_pickup.bind(String(w["kind"])))
	return btn

## Drop a weapon pickup right next to the player (walk over it to collect + activate).
func _spawn_weapon_pickup(kind: String) -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons == null or not weapons.has_method("spawn_weapon_pickup"):
		return
	var player := get_tree().get_first_node_in_group("player")
	var base: Vector2 = (player as Node2D).global_position if player != null else Vector2.ZERO
	var pos := base + Vector2(_rng.randf_range(-80.0, 80.0), _rng.randf_range(-80.0, 80.0))
	weapons.spawn_weapon_pickup(kind, pos)

# ── Weapon tabs ──────────────────────────────────────────────────────────────────────────────────────
# 2026-08-07, on request (the static "evolve" list only ever had 6 hand-picked entries — not each weapon's
# real 3 evolve choices, and 2 of those didn't even correspond to anything CAPSTONES actually implements —
# while the dynamic capstone-derived list was already complete/accurate): "evolve" now points at
# _evolved_entries() (real EVOLVE capstones, 3/weapon) instead of a WEAPON_TABS static list — that key was
# deleted from WEAPON_TABS entirely. The old dynamic "Combined" tab (auto-generated FUSION_DEFS recipe
# list) is removed outright, per request — WEAPON_TABS["fusion"] (hand-curated, audited to include the
# game's actual 6 FUSION_DEFS recipes: carnage/vampire_host/overcharger/predator/toxic_ballistic/
# singularities — see that key's own comment) is the one true Fusion tab now.
func _all_weapon_tabs() -> Array:
	return WEAPON_TAB_ORDER

func _weapon_tab_label(tab_id: String) -> String:
	return String(WEAPON_TAB_LABELS.get(tab_id, tab_id))

func _weapon_tab_entries(tab_id: String) -> Array:
	if tab_id == "evolve":
		return _evolved_entries()
	return WEAPON_TABS.get(tab_id, [])

## Base weapon's display name for the Evolve tab's "<Base>: <Evolution>" labels (override → WEAPON_INFO
## label → kind). Static (no instance state) so weapon_info_panel.gd can call it too, via the preloaded
## script directly, without needing a live arena_debug_spawn instance.
static func _base_name(kind: String) -> String:
	if BASE_NAME_OVERRIDE.has(kind):
		return String(BASE_NAME_OVERRIDE[kind])
	return String((ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {}).get("label", kind))

## Every EVOLVE capstone (3/weapon) as a spawnable cell: "<Base>: <Evolved>", drawn with the BASE weapon's
## icon, carrying the capstone id so a click grants the base weapon then forces its evolution. Static for
## the same reason as _base_name() — weapon_info_panel.gd's Weapon tab reuses this exact function for its
## own "Evolve" sub-tab (single source of truth, not a duplicated copy).
static func _evolved_entries() -> Array:
	var out: Array = []
	for kind: String in (ArenaWeapons.CAPSTONES as Dictionary).keys():
		var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
		for cap: Dictionary in (ArenaWeapons.CAPSTONES[kind] as Array):
			out.append({
				"kind": kind,
				"def_id": String(info.get("def_id", "")),
				"icon": String(info.get("icon", "")),
				"label": "%s: %s" % [_base_name(kind), String(cap.get("name", cap.get("id", "")))],
				"from": String(cap.get("desc", "")),
				"capstone": String(cap.get("id", "")),
			})
	return out

## Grant an evolved weapon: acquire the base weapon, then force its evolution capstone.
func _spawn_evolved(kind: String, capstone: String) -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons == null:
		return
	if weapons.has_method("acquire_weapon"):
		weapons.acquire_weapon(kind)
	if weapons.has_method("pool_set_capstone"):
		weapons.pool_set_capstone(kind, capstone)

func _build_hotkey_panel() -> void:
	if _dev_ui_root == null:
		return
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the RIGHT edge (was top-left); button-toggled, default hidden.
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.anchor_top  = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left   = -312.0
	panel.offset_right  = -8.0
	panel.offset_top    = 8.0
	panel.offset_bottom = 8.0 + 232.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.086, 0.059, 0.85)
	sb.set_corner_radius_all(0)
	sb.content_margin_left   = 10.0
	sb.content_margin_right  = 10.0
	sb.content_margin_top    = 7.0
	sb.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	_hotkey_panel = panel
	_dev_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10.0; vbox.offset_top = 7.0
	vbox.offset_right = -10.0; vbox.offset_bottom = -7.0
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var rows: Array[String] = [
		"F3         Boss Edit (toggle)",
		"F4         Skip run (sim rewards → RUN OVER)",
		"F5         Asteroids          Shift+F5  clear",
		"F6         Planet menu",
		"F7         Wave editor",
		"F9         Comet              Shift+F9  clear",
		"F10        Planet + moons     Shift+F10 clear",
		"F11        Structure          Shift+F11 clear",
		"F12        DeathBeam pickup      Shift+F12 clear",
	]
	for row: String in rows:
		var lbl := Label.new()
		lbl.text = row
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UiPalette.INK)
		vbox.add_child(lbl)

# ── Fleet formation preview ──────────────────────────────────────────────────────

## Hovered-fleet formation preview: draws each non-empty slot's representative sprite at its placed
## position/size, scaled to fit the 500px box. Mirrors arena_wave_editor.gd's _FleetPreview.
class _FleetPreview extends Control:
	var editor = null
	var fleet: Dictionary = {}
	func set_fleet(f: Dictionary) -> void:
		fleet = f
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.SURFACE)
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.WIRE_2, false, 1.0)
		if fleet.is_empty() or editor == null:
			return
		var slots: Array = fleet.get("slots", [])
		var rects: Array = []
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for s: Dictionary in slots:
			var enemies: Array = s.get("enemies", [])
			if enemies.is_empty():
				continue
			var tex: Texture2D = editor._fleet_icon(String(enemies[0]))
			var w: float = float(s.get("size", 50.0))
			var h := w
			if tex != null and tex.get_width() > 0:
				h = w * float(tex.get_height()) / float(tex.get_width())
			var p: Vector2 = s.get("pos", Vector2.ZERO)
			rects.append({"tex": tex, "p": p, "w": w, "h": h})
			mn.x = minf(mn.x, p.x - w * 0.5); mn.y = minf(mn.y, p.y - h * 0.5)
			mx.x = maxf(mx.x, p.x + w * 0.5); mx.y = maxf(mx.y, p.y + h * 0.5)
		if rects.is_empty():
			return
		var span := mx - mn
		var avail := size - Vector2(40.0, 40.0)
		var sc := minf(avail.x / maxf(span.x, 1.0), avail.y / maxf(span.y, 1.0))
		sc = minf(sc, 1.0)
		var center := (mn + mx) * 0.5
		for r: Dictionary in rects:
			var rw: float = float(r["w"]) * sc
			var rh: float = float(r["h"]) * sc
			var rp: Vector2 = (r["p"] as Vector2 - center) * sc + size * 0.5
			var rect := Rect2(rp - Vector2(rw, rh) * 0.5, Vector2(rw, rh))
			if r["tex"] != null:
				draw_texture_rect(r["tex"] as Texture2D, rect, false)
			else:
				draw_rect(rect, Color(UiPalette.ACCENT.r, UiPalette.ACCENT.g, UiPalette.ACCENT.b, 0.6))
