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
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")   # for WEAPON_INFO/FUSION_DEFS code names
# Weapon roster for the Dev → Weapon panel, classified per the Corp design doc into 4 tabs:
#   drop     = obtained from drops               (Spawn = "Drop")
#   evolve   = upgraded from ONE parent weapon   (Spawn names 1 weapon)  — evolve mechanic not coded yet
#   fusion   = combined from TWO weapons         (Spawn names 2 weapons)
#   obsolete = the 3 reworked/replaced code kinds (vampire_host / toxic_ballistic / singularities)
# `kind` = arena_weapons code kind (spawnable on click). Entries with "ph": true are PLACEHOLDERS — the weapon
# isn't implemented yet, so the cell renders dimmed + non-spawnable (a gray placeholder icon) until it lands.
# `from` (optional) = the source recipe, shown in the tooltip. NOTE: a few PDF→code kind mappings are
# best-guess (Jeager→zsword, Little Man→mortar, Viper→snake) — relabel if wrong.
const WEAPON_TABS := {
	"drop": [
		{"kind": "gatling_gun",   "def_id": "gatling_gun",  "label": "Gatling Gun"},
		{"kind": "death_beam",    "def_id": "death_beam",        "label": "Death Beam"},
		{"kind": "defensive_orbitals",   "def_id": "orbitals",      "label": "Defensive Orbitals"},
		{"kind": "striker",   "def_id": "",              "label": "Striker", "icon": "res://assets/weaponry/ND-OIF-F.png"},
		{"kind": "shooter",   "def_id": "swarm_host",    "label": "Shooter", "icon": "res://assets/weaponry/shooter.png"},
		{"kind": "chemtrail", "def_id": "chemtrail",     "label": "Chemtrail"},
		{"kind": "rift_maker",      "def_id": "rift_maker",    "label": "Rift Maker"},
		{"kind": "arc",       "def_id": "arc",           "label": "Arc Lightning Chain"},
		{"kind": "yari", "def_id": "yari",     "label": "Yari"},
		{"kind": "z_sword",    "def_id": "z_sword",       "label": "Z-Sword"},
		{"kind": "mortar",      "def_id": "mortar",          "label": "Little Man"},
		{"kind": "dragons_breath",     "def_id": "red_x",         "label": "Dragon's Breath"},
		{"kind": "aliwa", "def_id": "boomerang",     "label": "Boomerang"},
		{"kind": "gauss",     "def_id": "gauss_cannon",  "label": "Gauss Pulser"},
		{"kind": "viper",     "def_id": "space_snake",   "label": "Viper"},
		{"kind": "swarm",     "def_id": "",              "label": "Swarm", "icon": "res://assets/inventory/Swarm.png"},
		{"kind": "ultrasonicator",     "def_id": "ultrasonicator",    "label": "Ultrasonicator"},
		{"kind": "homing_missile",    "def_id": "homing_missile","label": "Homing Missile"},   # temp impl (copied from enemy missile launcher) — not in the Corp doc
	],
	"evolve": [
		{"kind": "",       "def_id": "",               "label": "Kinetic Induction Cannon", "code": "Big Gun",    "from": "Gatling Gun", "icon": "res://assets/inventory/VB-KIC-6.png",      "ph": true},
		{"kind": "",       "def_id": "",               "label": "Isotope Laser",            "code": "Super Laser", "from": "Death Beam",   "icon": "res://assets/inventory/KM-IL-200.png", "ph": true},
		{"kind": "ionizing_field", "def_id": "ionizing_field", "label": "Ionizing Field",        "from": "Rift Maker"},
		{"kind": "",       "def_id": "",               "label": "Mobile Vacuum",            "code": "Black Ship", "from": "Rift Maker",    "icon": "res://assets/inventory/M-ST-17.png",     "ph": true},
		{"kind": "",       "def_id": "",               "label": "Thunder Strike",           "code": "Zeus",       "from": "Arc Lightning Chain", "icon": "res://assets/inventory/Zeus.png",          "ph": true},
		{"kind": "fat_boy", "def_id": "fat_boy", "label": "Fat Boy",        "from": "Little Man"},
	],
	"fusion": [
		{"kind": "",            "def_id": "",              "label": "KM Quantum Beam Rifle",        "code": "Jedi Laser",  "from": "Gatling Gun × Death Beam", "icon": "res://assets/inventory/KM-QBM-200.png", "ph": true},
		{"kind": "",            "def_id": "",              "label": "Drone Cannon",                 "code": "Candy Crush", "from": "Gatling Gun × Defensive Orbitals", "icon": "res://assets/inventory/NC-DC-F.png", "ph": true},
		{"kind": "",            "def_id": "",              "label": "Vampire Host",                 "from": "Ultrasonicator × Offensive Orbitals", "icon": "res://assets/inventory/Vampire Host.png", "ph": true},
		{"kind": "venomancer",    "def_id": "venomancer","label": "Venomancer", "from": "Chemtrail × Swarm"},
		{"kind": "overcharger", "def_id": "gauss",  "label": "Overcharger",                  "from": "Arc Lightning Chain × Gauss Pulser", "icon": "res://assets/inventory/Overcharger.png"},
		{"kind": "yari_jaeger", "def_id": "yari_jaeger",   "label": "Yari Jeager",                  "from": "Yari × Z-Sword"},
		{"kind": "carnage",     "def_id": "gatling_gun",   "label": "Thermitic Auto Cannon",        "from": "Dragon's Breath × Gatling Gun"},
		{"kind": "",            "def_id": "",              "label": "Singularities",                "from": "Rift Maker × Gauss Pulser", "icon": "res://assets/inventory/Singularities.png", "ph": true},
		{"kind": "predator",    "def_id": "death_beam",        "label": "Predator",                     "from": "Viper × Death Beam"},
	],
	"obsolete": [
		{"kind": "vampire_host",    "def_id": "offensive_orbitals",     "label": "Vampire Host (old)",  "from": "Swarm + Sonic — reworked"},
		{"kind": "toxic_ballistic", "def_id": "homing_missile", "label": "Toxic Ballistic",     "from": "homing + chemtrail → Venomancer"},
		{"kind": "singularities",   "def_id": "defensive_orbitals",       "label": "Singularities (old)", "from": "orbital + void — reworked"},
		{"kind": "", "def_id": "shield_generator", "label": "Shield Generator", "from": "retired item", "ph": true},
	],
}
const WEAPON_TAB_ORDER: Array[String] = ["drop", "evolve", "fusion", "obsolete"]
const WEAPON_TAB_LABELS := {"drop": "Drop", "evolve": "Evolve", "fusion": "Fusion", "obsolete": "Obsolete"}
# Two extra tabs built dynamically from the live weapon data (not from WEAPON_TABS): "Evolved" = the real EVOLVE
# capstones (3/weapon, e.g. "Dragon's Breath: The Sun"); "Combined" = the FUSION recipes ("Combined (A + B)").
const EXTRA_WEAPON_TABS: Array[String] = ["evolved", "combined"]
const EXTRA_TAB_LABELS := {"evolved": "Evolved", "combined": "Combined"}
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
	"pros1", "pros2", "pros3", "pros4", "pros5", "pros6", "pros7", "pros8", "prosmotherblank",
	"elephant", "chromeleon", "metalfly",
]
const QUICK_BOSS_IDS: Array[String] = ["elephant", "chromeleon", "metalfly"]


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
# Creep panel tabs: Enemies (quick-spawn grid) + Fleet (saved-fleet list + formation preview)
var _creep_tab: String = "enemies"
var _creep_tab_btns: Dictionary = {}
var _creep_enemies_content: Control = null
var _creep_fleet_content: Control = null
var _fleet_list_vbox: VBoxContainer = null
var _fleet_preview: Control = null             # floating 500×500 formation preview (hover)
var _fleet_icon_cache: Dictionary = {}
var _hotkey_panel: Panel = null   # Hotkey help (right side) — button-toggled, default hidden
var _click_player: AudioStreamPlayer = null   # uiclick — local + ALWAYS so it sounds while paused

func _ready() -> void:
	# TEMP DIAGNOSTIC — see the note on arena.gd's _ready() timers. Safe to delete once the cause is found.
	var _t0 := Time.get_ticks_usec()
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
## panels) — used to just host the bottom-center Level Up / Fire-rate row, which has been removed (Level
## Up now lives in arena_hud_buttons.gd's dev column as +LEVEL; the row overflowed screen width alongside it).
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
## attribute points from leveling), then jumps straight to the RUN OVER screen. Persistent rewards only —
## in-run-only state (equipped weapons/aux, HP) is simply discarded, same as any other run ending.
func _skip_run() -> void:
	if MetaManager.has_method("simulate_run_rewards"):
		MetaManager.simulate_run_rewards(SIM_KILLS, SIM_BOSSES)
	if GameManager.has_method("add_xp") and GameManager.has_method("xp_to_next"):
		var total_xp := 0.0
		for lvl in range(1, SIM_TARGET_LEVEL):
			total_xp += float(GameManager.xp_to_next(lvl))
		GameManager.add_xp(total_xp)
	var arena := get_parent()
	if arena != null and arena.has_method("force_end_run"):
		arena.call("force_end_run")
	print("[debug] F4 skip run — simulated %d kills / %d bosses / level %d" % [SIM_KILLS, SIM_BOSSES, SIM_TARGET_LEVEL])

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
	const CELL  := 48
	const COLS  := 4
	const HDR_H := 28
	const TAB_H := 26
	const W     := COLS * CELL   # 192 px
	const GRID_H := CELL * 4    # 4 visible rows = 192 px

	var panel := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.05, 0.08, 0.90)
	ps.set_corner_radius_all(4)
	ps.border_width_left = 1; ps.border_width_right  = 1
	ps.border_width_top  = 1; ps.border_width_bottom = 1
	ps.border_color = Color(0.30, 0.40, 0.60, 0.65)
	panel.add_theme_stylebox_override("panel", ps)
	panel.anchor_left   = 0.0; panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left   = 8.0
	panel.offset_right  = 8.0 + W
	panel.offset_top    = -(HDR_H + TAB_H + GRID_H + 16)
	panel.offset_bottom = -8.0
	panel.visible = false               # button-toggled (default hidden even when dev:on)
	_creep_panel = panel
	_dev_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Header row — CLEAR ALL only (the old "Quick Spawn" title is now the Enemies tab).
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size = Vector2(0.0, float(HDR_H))
	hdr.add_theme_constant_override("separation", 0)
	vbox.add_child(hdr)
	var btn_clear := Button.new()
	btn_clear.text = "CLEAR ALL"
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.add_theme_font_size_override("font_size", 10)
	btn_clear.pressed.connect(_clear_quick_spawn)
	hdr.add_child(btn_clear)

	# Tab row — Enemies / Fleet
	var tabs := HBoxContainer.new()
	tabs.custom_minimum_size = Vector2(0.0, float(TAB_H))
	tabs.add_theme_constant_override("separation", 2)
	vbox.add_child(tabs)
	_creep_tab_btns.clear()
	for tab_def: Array in [["enemies", "Enemies"], ["fleet", "Fleet"]]:
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

	# Enemies tab — the quick-spawn grid (4 visible rows, scrolls for row 5+).
	var escroll := ScrollContainer.new()
	escroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	escroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	escroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(escroll)
	_creep_enemies_content = escroll
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	escroll.add_child(grid)
	for type_id: String in QUICK_SPAWN_ORDER:
		grid.add_child(_make_quick_cell(type_id, CELL))

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
		(_creep_tab_btns[id] as Button).modulate = Color(1, 1, 1, 1) if active else Color(0.62, 0.66, 0.78, 1)
	if _creep_enemies_content != null:
		_creep_enemies_content.visible = (tab_id == "enemies")
	if _creep_fleet_content != null:
		_creep_fleet_content.visible = (tab_id == "fleet")
	if tab_id == "fleet":
		_rebuild_fleet_list()   # refresh in case fleets were edited since last open
	else:
		_hide_fleet_preview()

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
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
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
	wd.call("_deploy_fleet", fleet_name, false)
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
	btn.tooltip_text  = type_id
	btn.clip_contents = true

	var _make_style := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(2)
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = border
		return s

	if is_boss:
		btn.add_theme_stylebox_override("normal",  _make_style.call(Color(0.42, 0.05, 0.05, 0.80), Color(0.65, 0.15, 0.10, 0.80)))
		btn.add_theme_stylebox_override("hover",   _make_style.call(Color(0.65, 0.10, 0.08, 0.92), Color(1.00, 0.35, 0.25, 1.00)))
		btn.add_theme_stylebox_override("pressed", _make_style.call(Color(0.25, 0.03, 0.03, 0.95), Color(0.65, 0.15, 0.10, 0.80)))
	else:
		btn.add_theme_stylebox_override("normal",  _make_style.call(Color(0.08, 0.10, 0.15, 0.82), Color(0.25, 0.30, 0.48, 0.55)))
		btn.add_theme_stylebox_override("hover",   _make_style.call(Color(0.14, 0.18, 0.26, 0.92), Color(0.50, 0.65, 1.00, 0.90)))
		btn.add_theme_stylebox_override("pressed", _make_style.call(Color(0.05, 0.07, 0.10, 0.95), Color(0.25, 0.30, 0.48, 0.55)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

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

	btn.pressed.connect(_spawn_quick_enemy.bind(type_id))
	return btn

func _load_thumb(icon: String) -> Texture2D:
	var src: String = EnemyScript._resolve_sprite(icon)   # prefer assets/enemiesHD/, fall back to assets/enemies/
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

## Shift+Click a quick-spawn cell to mass-spawn BULK_SPAWN_COUNT at once instead of 1 — a fast way
## to reach a stress-test population (e.g. reproduce the arena's creep-count FPS cliff) without
## waiting for the wave timeline to build up naturally over real playtime.
const BULK_SPAWN_COUNT := 300

func _spawn_quick_enemy(type_id: String) -> void:
	var cam := get_viewport().get_camera_2d()
	var base := cam.global_position if cam != null else Vector2.ZERO
	var n := BULK_SPAWN_COUNT if Input.is_key_pressed(KEY_SHIFT) else 1
	for _i in n:
		var pos := base + Vector2(_rng.randf_range(-500.0, 500.0), _rng.randf_range(-270.0, 270.0))
		_spawn_enemy_at(type_id, pos)

## Instantiate one enemy of `type_id` at `pos` (shared by quick-spawn + fleet-spawn). Routes through
## the wave director's own _spawn() when available so debug-spawned enemies go through the SAME
## path as real gameplay spawns — including the MAX_ALIVE cap. Falls back to the old direct-instantiate
## path only if no wave director is present at all.
func _spawn_enemy_at(type_id: String, pos: Vector2) -> void:
	var src: Dictionary = WaveDir.ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return
	# A carrier (mothership) spawned alone makes no sense — deploy its full fleet, exactly like Wave Edit.
	if String(src.get("behavior", "")) == "mothership":
		if _deploy_fleet_via_director(_fleet_name_containing(type_id)):
			return
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null:
		wd.call("_spawn", type_id, pos, false)
		return
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

## "CLEAR ALL" — wipes every live creep on the arena (real wave-director spawns included, not just ones
## quick-spawned through this panel), matching what a dev testing the arena actually wants: a clean field.
func _clear_quick_spawn() -> void:
	for e: Node in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e):
			e.queue_free()

# ── Weapon Spawn panel ──────────────────────────────────────────────────────────

func _build_weapon_spawn_panel() -> void:
	if _dev_ui_root == null:
		return
	const CELL  := 48
	const COLS  := 4
	const HDR_H := 40
	const TAB_H := 26
	const ROWS  := 5                # fixed grid area (Drop tab is the tallest at 17 = 5 rows)
	const W     := COLS * CELL
	var grid_h: int = CELL * ROWS

	var panel := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.05, 0.08, 0.90)
	ps.set_corner_radius_all(4)
	ps.border_width_left = 1; ps.border_width_right  = 1
	ps.border_width_top  = 1; ps.border_width_bottom = 1
	ps.border_color = Color(0.30, 0.40, 0.60, 0.65)
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
	lbl_title.add_theme_color_override("font_color", Color(0.75, 0.87, 1.00))
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

	# ── Tab row: Drop / Evolve / Fusion / Obsolete ──
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

	# ── Cell grid (rebuilt per active tab) — scrollable so the Evolved tab's 27 cells fit the fixed panel ──
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
		(_weapon_tab_btns[id] as Button).modulate = Color(1, 1, 1, 1) if active else Color(0.62, 0.66, 0.78, 1)
	_rebuild_weapon_grid()

func _rebuild_weapon_grid() -> void:
	if _weapon_grid == null:
		return
	for c in _weapon_grid.get_children():
		c.queue_free()
	for w: Dictionary in _weapon_tab_entries(_weapon_tab):
		_weapon_grid.add_child(_make_weapon_cell(w, 48))

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
		s.set_corner_radius_all(2)
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = border
		return s
	btn.add_theme_stylebox_override("normal",   mk.call(Color(0.08, 0.10, 0.15, 0.82), Color(0.25, 0.30, 0.48, 0.55)))
	btn.add_theme_stylebox_override("hover",    mk.call(Color(0.14, 0.18, 0.26, 0.92), Color(0.50, 0.65, 1.00, 0.90)))
	btn.add_theme_stylebox_override("pressed",  mk.call(Color(0.05, 0.07, 0.10, 0.95), Color(0.25, 0.30, 0.48, 0.55)))
	btn.add_theme_stylebox_override("disabled", mk.call(Color(0.07, 0.08, 0.11, 0.70), Color(0.22, 0.25, 0.34, 0.45)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# Prefer an explicit `icon` path (used for placeholder weapons whose art exists but aren't in ITEM_DEFS yet);
	# otherwise fall back to the inventory icon by def_id.
	var tex: Texture2D = null
	var icon_path := String(w.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	else:
		tex = InventoryManager.get_icon(String(w["def_id"]))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 3; tr.offset_right  = -3
		tr.offset_top  = 3; tr.offset_bottom = -3
		tr.modulate = Color(1, 1, 1, 0.35) if is_ph else Color(1, 1, 1, 1)   # dim placeholder icons
		btn.add_child(tr)

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

# ── Dynamic weapon tabs: Evolved (real EVOLVE capstones) + Combined (FUSION recipes) ────────────────────
func _all_weapon_tabs() -> Array:
	var out: Array = []
	out.append_array(WEAPON_TAB_ORDER)
	out.append_array(EXTRA_WEAPON_TABS)
	return out

func _weapon_tab_label(tab_id: String) -> String:
	if WEAPON_TAB_LABELS.has(tab_id):
		return String(WEAPON_TAB_LABELS[tab_id])
	return String(EXTRA_TAB_LABELS.get(tab_id, tab_id))

func _weapon_tab_entries(tab_id: String) -> Array:
	match tab_id:
		"evolved":  return _evolved_entries()
		"combined": return _combined_entries()
	return WEAPON_TABS.get(tab_id, [])

## Base weapon's display name for the Evolved/Combined labels (override → WEAPON_INFO label → kind).
func _base_name(kind: String) -> String:
	if BASE_NAME_OVERRIDE.has(kind):
		return String(BASE_NAME_OVERRIDE[kind])
	return String((ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {}).get("label", kind))

## Every EVOLVE capstone (3/weapon) as a spawnable cell: "<Base>: <Evolved>", drawn with the BASE weapon's
## icon, carrying the capstone id so a click grants the base weapon then forces its evolution.
func _evolved_entries() -> Array:
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

## Every fusion recipe as a spawnable cell: "Combined (<A> + <B>)" with the fusion's icon.
func _combined_entries() -> Array:
	var out: Array = []
	for fid: String in (ArenaWeapons.FUSION_DEFS as Dictionary).keys():
		var rec: Dictionary = ArenaWeapons.FUSION_DEFS[fid]
		out.append({
			"kind": fid,
			"def_id": String(rec.get("def_id", "")),
			"icon": String(rec.get("icon", "")),
			"label": "Combined (%s + %s)" % [_base_name(String(rec.get("a", ""))), _base_name(String(rec.get("b", "")))],
			"from": String(rec.get("name", "")),
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
	sb.bg_color = Color(0.04, 0.04, 0.08, 0.72)
	sb.set_corner_radius_all(4)
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
		lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.90))
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
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.95))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.40, 0.50, 0.6), false, 1.0)
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
				draw_rect(rect, Color(0.4, 0.5, 0.7, 0.6))
