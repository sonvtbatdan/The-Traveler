extends CanvasLayer
## Debug spawner + dev-mode HUD for the arena.
## Quick Spawn panel (Dev:on only) — bottom-left, 4-column enemy grid, bosses last with red bg.
##
## Hotkeys (F-keys always active regardless of DEV_MODE):
##   F3        Boss Edit (toggle)
##   F5        Asteroid field near player       Shift+F5  = clear
##   F6        Planet menu
##   F7        Wave editor
##   F9        Comet near player                Shift+F9  = clear
##   F10       Planet + moons near player       Shift+F10 = clear
##   F11       Space structure (cycles types)   Shift+F11 = clear
##   F12       (removed — use Dev:on → Weapon panel)
##   [−]/[+]   Fire rate mult
##   [+Level]  Force level-up

const GifLoader := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const WaveDir   := preload("res://scripts/gameplay/arena_wave_director.gd")
const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
# Weapon roster for the Dev → Weapon panel, classified per the Corp design doc into 4 tabs:
#   drop     = obtained from drops               (Spawn = "Drop")
#   evolve   = upgraded from ONE parent weapon   (Spawn names 1 weapon)  — evolve mechanic not coded yet
#   fusion   = combined from TWO weapons         (Spawn names 2 weapons)
#   obsolete = the 3 reworked/replaced code kinds (vampire_host / toxic_ballistic / singularities)
# `kind` = arena_weapons code kind (spawnable on click). Entries with "ph": true are PLACEHOLDERS — the weapon
# isn't implemented yet, so the cell renders dimmed + non-spawnable (a gray placeholder icon) until it lands.
# `from` (optional) = the source recipe, shown in the tooltip. NOTE: a few PDF→code kind mappings are
# best-guess (Jeager→zsword, Rosastro HE Mortar→nuke, Viper→snake) — relabel if wrong.
const WEAPON_TABS := {
	"drop": [
		{"kind": "gatling",   "def_id": "gatling_gun",  "label": "Kinetic Auto Cannon"},
		{"kind": "lasgun",    "def_id": "lasgun",        "label": "Solid-State Laser"},
		{"kind": "orbital",   "def_id": "orbitals",      "label": "Orbital Impact Defense"},
		{"kind": "swarm",     "def_id": "swarm_host",    "label": "Orbital Impact Offense"},
		{"kind": "chemtrail", "def_id": "chemtrail",     "label": "Biocide Vaporizer"},
		{"kind": "void",      "def_id": "rift_maker",    "label": "Vacuum Decoupler"},
		{"kind": "arc",       "def_id": "arc",           "label": "Arc Lightning Chain"},
		{"kind": "moroboshi", "def_id": "moroboshi",     "label": "Yari"},
		{"kind": "zsword",    "def_id": "z_sword",       "label": "Jeager"},
		{"kind": "nuke",      "def_id": "nuke",          "label": "Rosastro HE Mortar"},
		{"kind": "red_x",     "def_id": "red_x",         "label": "Thermitic Discharger"},
		{"kind": "boomerang", "def_id": "boomerang",     "label": "Aliwa"},
		{"kind": "gauss",     "def_id": "gauss_cannon",  "label": "Gauss Pulser"},
		{"kind": "snake",     "def_id": "space_snake",   "label": "Viper"},
		{"kind": "",          "def_id": "",              "label": "Swarm", "ph": true},
		{"kind": "sonic",     "def_id": "sonic_wave",    "label": "Sonic"},
	],
	"evolve": [
		{"kind": "",       "def_id": "",               "label": "Kinetic Induction Cannon", "from": "Kinetic Auto Cannon", "ph": true},
		{"kind": "",       "def_id": "",               "label": "Isotope Laser",            "from": "Solid-State Laser",   "ph": true},
		{"kind": "ionize", "def_id": "ionizing_field", "label": "Tachyon Displacer",        "from": "Vacuum Decoupler"},
		{"kind": "",       "def_id": "",               "label": "Mobile Vacuum",            "from": "Vacuum Decoupler",    "ph": true},
		{"kind": "",       "def_id": "",               "label": "Thunder Strike",           "from": "Arc Lightning Chain", "ph": true},
		{"kind": "",       "def_id": "",               "label": "Rosastro Nuclear",         "from": "Rosastro HE Mortar",  "ph": true},
	],
	"fusion": [
		{"kind": "",            "def_id": "",              "label": "KM Quantum Beam Rifle",        "from": "Kinetic Auto Cannon × Solid-State Laser", "ph": true},
		{"kind": "",            "def_id": "",              "label": "Drone Cannon",                 "from": "Kinetic Auto Cannon × Orbital Impact Defense", "ph": true},
		{"kind": "",            "def_id": "",              "label": "Vampire Host",                 "from": "Sonic × Orbital Impact Offense", "ph": true},
		{"kind": "parasite",    "def_id": "parasite_cloud","label": "Bio-Corrosive Spore Launcher", "from": "Biocide Vaporizer × Swarm"},
		{"kind": "overcharger", "def_id": "gauss_cannon",  "label": "Overcharger",                  "from": "Arc Lightning Chain × Gauss Pulser"},
		{"kind": "yari_jaeger", "def_id": "yari_jaeger",   "label": "Yari Jeager",                  "from": "Yari × Jeager"},
		{"kind": "carnage",     "def_id": "gatling_gun",   "label": "Thermitic Auto Cannon",        "from": "Thermitic Discharger × Kinetic Auto Cannon"},
		{"kind": "",            "def_id": "",              "label": "Singularities",                "from": "Vacuum Decoupler × Gauss Pulser", "ph": true},
		{"kind": "predator",    "def_id": "lasgun",        "label": "Predator",                     "from": "Viper × Solid-State Laser"},
	],
	"obsolete": [
		{"kind": "vampire_host",    "def_id": "swarm_host",     "label": "Vampire Host (old)",  "from": "Swarm + Sonic — reworked"},
		{"kind": "toxic_ballistic", "def_id": "homing_missile", "label": "Toxic Ballistic",     "from": "homing + chemtrail → Venomancer"},
		{"kind": "singularities",   "def_id": "orbitals",       "label": "Singularities (old)", "from": "orbital + void — reworked"},
	],
}
const WEAPON_TAB_ORDER: Array[String] = ["drop", "evolve", "fusion", "obsolete"]
const WEAPON_TAB_LABELS := {"drop": "Drop", "evolve": "Evolve", "fusion": "Fusion", "obsolete": "Obsolete"}
const SFX_UICLICK := preload("res://assets/audio/sfx/uiclick.wav")

# Enemy order in the quick-spawn grid — normals first, bosses last.
const QUICK_SPAWN_ORDER: Array[String] = [
	"fly", "bee", "bug", "swarm",
	"diver", "dragonfly", "octopus", "spider",
	"centipede", "shooter", "sentinel", "beamer",
	"bomber", "missile", "dummy", "squid",
	"elephant", "chromeleon", "metalfly",
]
const QUICK_BOSS_IDS: Array[String] = ["elephant", "chromeleon", "metalfly"]


# Set true to show the hotkey panel + fire-rate controls at startup.
const DEV_MODE := false

const FR_STEP        := 0.5    # fire-rate mult change per +/- press (tune for faster/slower testing)
const GAT_INTERVAL   := 0.09   # mirrors arena_weapons.gd GAT_FIRE_INTERVAL (keep in sync if changed)
const FR_MULT_MIN    := 0.5    # clamp floor so fire rate can't go negative or too slow

var _rng := RandomNumberGenerator.new()
var _struct_cycle: int = 0   # F11 steps through the four structure types
var _fr_label: Label = null
var _dev_ui_root: Control = null
var _creep_panel:  Panel = null   # Quick Spawn (creep) — button-toggled, default hidden
var _weapon_panel: Panel = null   # Spawn Weapon — button-toggled, default hidden
var _weapon_grid: GridContainer = null         # current-tab cell grid (rebuilt on tab switch)
var _weapon_tab: String = "drop"               # active weapon tab
var _weapon_tab_btns: Dictionary = {}          # tab id → Button (for highlight)
var _hotkey_panel: Panel = null   # Hotkey help (right side) — button-toggled, default hidden
var _click_player: AudioStreamPlayer = null   # uiclick — local + ALWAYS so it sounds while paused

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("arena_debug_spawn")
	_rng.randomize()
	_build_fire_rate_ui()
	_build_hotkey_panel()
	_build_quick_spawn_panel()
	_build_weapon_spawn_panel()
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

func toggle_creep_panel() -> void:
	if _creep_panel != null:
		_creep_panel.visible = not _creep_panel.visible

func toggle_weapon_panel() -> void:
	if _weapon_panel != null:
		_weapon_panel.visible = not _weapon_panel.visible

func toggle_hotkey_panel() -> void:
	if _hotkey_panel != null:
		_hotkey_panel.visible = not _hotkey_panel.visible

func _build_fire_rate_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.anchor_left   = 0.5
	hb.anchor_right  = 0.5
	hb.anchor_top    = 1.0
	hb.anchor_bottom = 1.0
	hb.offset_left   = -160
	hb.offset_right  =  160
	hb.offset_top    =  -38
	hb.offset_bottom =  -8
	root.add_child(hb)
	_dev_ui_root = root

	var btn_minus := Button.new()
	btn_minus.text = "−"
	btn_minus.custom_minimum_size = Vector2(32, 28)
	btn_minus.pressed.connect(_fr_decrease)
	hb.add_child(btn_minus)

	_fr_label = Label.new()
	_fr_label.custom_minimum_size = Vector2(260, 28)
	_fr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fr_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_fr_label)

	var btn_plus := Button.new()
	btn_plus.text = "+"
	btn_plus.custom_minimum_size = Vector2(32, 28)
	btn_plus.pressed.connect(_fr_increase)
	hb.add_child(btn_plus)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(16, 0)
	hb.add_child(sep)

	var btn_lvl := Button.new()
	btn_lvl.text = "+ Level"
	btn_lvl.custom_minimum_size = Vector2(72, 28)
	btn_lvl.pressed.connect(_add_level)
	hb.add_child(btn_lvl)

func _add_level() -> void:
	if GameManager.has_method("add_xp"):
		var level: int = GameManager.player_level if "player_level" in GameManager else 1
		var xp_needed: int = GameManager.xp_to_next(level) if GameManager.has_method("xp_to_next") else 100
		GameManager.add_xp(xp_needed)

func _fr_increase() -> void:
	if GameManager.has_method("add_fire_rate"):
		GameManager.add_fire_rate(FR_STEP)

func _fr_decrease() -> void:
	if GameManager.has_method("add_fire_rate") and GameManager.upg_fire_rate_mult - FR_STEP >= FR_MULT_MIN:
		GameManager.add_fire_rate(-FR_STEP)

func _process(_delta: float) -> void:
	if _fr_label == null or not GameManager.has_method("get_fire_rate_mult"):
		return
	var mult: float = GameManager.get_fire_rate_mult()
	var shots_per_sec: float = mult / GAT_INTERVAL
	var barrels: int = maxi(1, floori(shots_per_sec / 10.0))
	_fr_label.text = "Fire: %.1f/s  |  %d barrel%s  |  ×%.2f" % [
		shots_per_sec, barrels, "s" if barrels > 1 else " ", mult
	]

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	match key.keycode:
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
	const HDR_H := 50
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
	panel.offset_top    = -(HDR_H + GRID_H + 8)
	panel.offset_bottom = -8.0
	panel.visible = false               # button-toggled (default hidden even when dev:on)
	_creep_panel = panel
	_dev_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# Header row
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size = Vector2(0.0, float(HDR_H))
	hdr.add_theme_constant_override("separation", 0)
	vbox.add_child(hdr)

	var lbl_title := Label.new()
	lbl_title.text = "Quick Spawn"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_title.add_theme_font_size_override("font_size", 11)
	lbl_title.add_theme_color_override("font_color", Color(0.75, 0.87, 1.00))
	hdr.add_child(lbl_title)

	var btn_clear := Button.new()
	btn_clear.text = "CLEAR ALL"
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.add_theme_font_size_override("font_size", 10)
	btn_clear.pressed.connect(_clear_quick_spawn)
	hdr.add_child(btn_clear)

	vbox.add_child(HSeparator.new())

	# Scrollable grid (4 visible rows, scrolls for row 5+)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(float(W), float(GRID_H))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	scroll.add_child(grid)

	for type_id: String in QUICK_SPAWN_ORDER:
		grid.add_child(_make_quick_cell(type_id, CELL))

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
	if icon.ends_with(".gif"):
		var g := GifLoader.load_gif(icon)
		if g != null and g.has_meta("gif_frames"):
			var frames: Array = g.get_meta("gif_frames")
			if not frames.is_empty():
				return frames[0] as Texture2D
		return null
	return load(icon) as Texture2D

func _spawn_quick_enemy(type_id: String) -> void:
	var src: Dictionary = WaveDir.ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return
	var def := src.duplicate()
	var mgr := get_tree().get_first_node_in_group("enemy_manager")

	# Random position within roughly the visible viewport
	var cam := get_viewport().get_camera_2d()
	var base := cam.global_position if cam != null else Vector2.ZERO
	var pos := base + Vector2(_rng.randf_range(-500.0, 500.0), _rng.randf_range(-270.0, 270.0))

	var e: Node
	if def.has("boss_script"):
		var bs := load(String(def["boss_script"])) as GDScript
		e = bs.new() if bs != null else EnemyScript.new()
	else:
		e = EnemyScript.new()
	e.call("configure", type_id, mgr, def)
	e.set("position", pos)
	e.add_to_group("quick_spawn_enemy")

	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null:
		wd.get_parent().add_child(e)
	else:
		get_tree().current_scene.add_child(e)

func _clear_quick_spawn() -> void:
	for e: Node in get_tree().get_nodes_in_group("quick_spawn_enemy"):
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
	const ROWS  := 4                # fixed grid area (Drop tab is the tallest at 16 = 4 rows)
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
	for tab_id: String in WEAPON_TAB_ORDER:
		var tb := Button.new()
		tb.text = String(WEAPON_TAB_LABELS[tab_id])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 10)
		tb.pressed.connect(_select_weapon_tab.bind(tab_id))
		tabs.add_child(tb)
		_weapon_tab_btns[tab_id] = tb

	vbox.add_child(HSeparator.new())

	# ── Cell grid (rebuilt per active tab) ──
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.custom_minimum_size = Vector2(float(W), float(grid_h))
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	vbox.add_child(grid)
	_weapon_grid = grid
	_select_weapon_tab(_weapon_tab)

## Switch the Weapon panel to `tab_id`, highlight its button, and rebuild the cell grid.
func _select_weapon_tab(tab_id: String) -> void:
	if not WEAPON_TABS.has(tab_id):
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
	for w: Dictionary in (WEAPON_TABS[_weapon_tab] as Array):
		_weapon_grid.add_child(_make_weapon_cell(w, 48))

func _make_weapon_cell(w: Dictionary, cell_size: int) -> Control:
	var is_ph: bool = bool(w.get("ph", false))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(cell_size, cell_size)
	btn.focus_mode    = Control.FOCUS_NONE
	var tip := String(w["label"])
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

	var tex: Texture2D = InventoryManager.get_icon(String(w["def_id"]))
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
		"F5         Asteroids          Shift+F5  clear",
		"F6         Planet menu",
		"F7         Wave editor",
		"F9         Comet              Shift+F9  clear",
		"F10        Planet + moons     Shift+F10 clear",
		"F11        Structure          Shift+F11 clear",
		"F12        Lasgun pickup      Shift+F12 clear",
		"[ − ] [ + ]  Fire rate",
		"[ +Level ]   Level up",
	]
	for row: String in rows:
		var lbl := Label.new()
		lbl.text = row
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.90))
		vbox.add_child(lbl)
