extends CanvasLayer
## Bottom-right HUD buttons: Pause, Codex, Setting, Devon (toggle dev mode + pause + edit buttons), Quit.
## When Devon is active: game is paused and Boss_edit / Creep_edit buttons are revealed.
##
## The 6-button column is hidden outside dev mode (`_vb.visible` follows `_dev_mode`, toggled in
## set_dev_mode() — Setting/Inv stay reachable via the Player-HUD's own MENU/INV board buttons, see
## hud_binder.gd, and via Esc for Setting). Dev mode now toggles from a switch in the Settings panel
## instead of the (hidden) Devon button — see set_dev_mode()/is_dev_mode() and settings_panel.gd's "Dev
## Mode" row. Group "arena_hud_buttons" is how Settings finds this instance.

const BTN_SIZE        := 60.0
const BTN_SEP         :=  6.0
const MARGIN          :=  8.0
const SIMPLIFIED_X    := -2.0    # MARGIN(8) − 10px left
const SIMPLIFIED_Y    := 183.0  # moved down 100px (was 83) to clear room below the HP bar
# 2026-08-18 request: every dev-mode-cluster button (Map Edit/Creep Edit triggers + both flyouts +
# the standalone column below) is now a uniform-size TEXT button — no more icon art, sized to match
# End Run (was the reference "small button" size already used by End Run/Boss Fight/Auto-Fire/God
# Mode/+Level). Promoted from a local const inside _build_ui() since the whole cluster needs it now,
# not just the bottom small-button row.
const SMALL_BTN_W := BTN_SIZE * 0.9    # 54px
const SMALL_BTN_H := BTN_SIZE * 0.5    # 30px

const ArenaEnemy := preload("res://scripts/gameplay/arena_enemy.gd")
const SettingsScript := preload("res://scripts/ui/settings/settings_panel.gd")
const SFX_UICLICK := preload("res://assets/audio/sfx/uiclick.wav")

var _settings: Node = null
var _click_player: AudioStreamPlayer = null   # uiclick — local + ALWAYS so it sounds while dev:on pauses the tree

var _dev_mode:    bool  = false
var _game_paused: bool  = false   # tracks the pause state managed by this HUD
var _auto_fire:   bool  = false   # "Auto-Aim": ship auto-faces the nearest enemy instead of the mouse (read by arena.gd._aim(); movement is unaffected — WASD is absolute, not facing-relative). Flipped by either the dev-cluster AUTO button (_on_auto_fire, dev-mode only) or the Settings panel's Auto-Aim switch (set_auto_aim, persisted — see _ready())
var _god_mode:    bool  = false   # dev-mode cheat toggle: forces Auto-Fire ON + GameManager.set_god_mode (10000x damage mult, full HP/shield immunity — see game_manager.gd)

# Button references
var _devon_btn:      TextureButton = null
var _dev_toggle_btn: TextureButton = null   # 2026-08-06, on request: always-visible bottom-right Dev Mode
                                              # toggle (separate from _devon_btn, which lives inside _vb — the
                                              # 6-button column that only SHOWS once dev mode is already on, so
                                              # it can't turn dev mode ON by itself; see set_dev_mode()'s doc).
var _pause_btn:      TextureButton = null
# 2026-08-18 grouping (request: "gom nhóm lại"): the individual buttons below are unchanged in behavior/
# handler — they're now parented into one of the two flyouts below instead of sitting directly in the
# always-visible column. See _map_edit_btn/_map_edit_flyout and _creep_edit_group_btn/_creep_edit_flyout.
var _terrain_edit_btn: Button = null
var _light_edit_btn: Button = null
var _plume_edit_btn: Button = null
var _crater_mark_btn: Button = null
var _landmark_mark_btn: Button = null
var _boss_edit_btn:  Button = null
var _creep_info_btn: Button = null
var _weapon_info_btn: Button = null
var _creep_edit_btn: Button = null   # the individual "Creep Edit" tool (creep_edit_mode.gd) — lives INSIDE the Creep Edit flyout, distinct from _creep_edit_group_btn (the flyout's own trigger)
var _simplified_btn: Button = null
# Group triggers + flyouts (2026-08-18) — MAP EDIT groups Landmark Mark/Crater Mark/Plume Edit/Light
# Edit/Terrain Edit/Simplified; CREEP EDIT groups Boss Edit/Creep Info/Creep Edit/Fleet Edit/Wave Edit.
# Each flyout opens to the RIGHT of its trigger so it never collides with the standalone column below.
var _map_edit_btn:      Button = null
var _map_edit_flyout:   VBoxContainer = null
var _creep_edit_group_btn: Button = null
var _creep_edit_flyout: VBoxContainer = null
var _creep_btn:      Button = null
var _weapon_btn:     Button = null
var _hotkey_btn:     Button = null
var _fleet_edit_btn: Button = null
var _wave_edit_btn:  Button = null
var _hud_edit_btn:   Button = null
var _end_run_btn:    Button = null
var _end_run_popup:  CanvasLayer = null   # WIN/LOSE choice popup — built lazily on first END RUN click
var _boss_fight_btn: Button = null
var _auto_fire_btn:  Button = null
var _god_mode_btn:   Button = null
var _level_btn:      Button = null
var _inv_btn:        Button = null
var _vb:             VBoxContainer = null

# Textures (Devon/dev-toggle + Pause only — every other dev-cluster button lost its icon 2026-08-18,
# see _make_label_btn()'s dev-cluster callers below; those texture vars are gone)
var _tex_devon:         Texture2D = null
var _tex_devoff:        Texture2D = null
var _tex_pause:         Texture2D = null

# Total height without dev-edit buttons (for VBox repositioning)
var _base_total_h: float = 0.0

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("arena_hud_buttons")   # so the Settings panel's Dev Mode switch can find this instance
	_tex_devon         = _load_img("res://assets/hud/Devon.png")
	_tex_devoff        = _load_img("res://assets/hud/devoff.png")
	_tex_pause         = _load_img("res://assets/hud/Pause.png")
	_build_ui()
	SettingsScript.apply_saved()       # apply saved SFX volume + window mode (covers arena-direct launch)
	if bool(SettingsScript.load_cfg().get("dev_mode", false)):
		set_dev_mode(true)   # re-arm a saved "Dev Mode: on" at the start of every arena load
	if bool(SettingsScript.load_cfg().get("auto_aim", false)):
		set_auto_aim(true)   # re-arm a saved "Auto-Aim: on" at the start of every arena load
	_settings = SettingsScript.new()
	_settings.add_to_group("settings_panel")   # so the HUD Menu button can open it (hud_edit_mode._open_menu)
	add_child(_settings)
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = SFX_UICLICK
	_click_player.bus = "SFX"
	add_child(_click_player)

func _load_img(res_path: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

func _btn_h(tex: Texture2D) -> float:
	if tex != null and tex.get_width() > 0:
		return BTN_SIZE * float(tex.get_height()) / float(tex.get_width())
	return BTN_SIZE

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var tex_codex   := _load_img("res://assets/hud/codex.png")
	var tex_setting := _load_img("res://assets/hud/Setting.png")
	var tex_quit    := _load_img("res://assets/hud/Quit.png")

	var pause_h      := _btn_h(_tex_pause)
	var codex_h      := _btn_h(tex_codex)

	# VBox: Pause + Codex + Inventory + Setting + Devon + Quit (6 buttons, 5 gaps) — no dev buttons here
	_base_total_h = pause_h + codex_h + BTN_SIZE * 4.0 + BTN_SEP * 5.0

	_vb = VBoxContainer.new()
	_vb.add_theme_constant_override("separation", int(BTN_SEP))
	_vb.anchor_left   = 1.0
	_vb.anchor_right  = 1.0
	_vb.anchor_top    = 1.0
	_vb.anchor_bottom = 1.0
	_vb.offset_left   = -(BTN_SIZE + MARGIN)
	_vb.offset_right  = -MARGIN
	_vb.offset_top    = -(_base_total_h + MARGIN)
	_vb.offset_bottom = -MARGIN
	root.add_child(_vb)

	# Pause button (top)
	_pause_btn = _make_btn(_tex_pause, pause_h)
	_pause_btn.pressed.connect(_on_pause)
	_vb.add_child(_pause_btn)

	# Codex
	var btn_codex := _make_btn(tex_codex, codex_h)
	btn_codex.pressed.connect(_on_codex)
	_vb.add_child(btn_codex)

	# Inventory
	_inv_btn = _make_label_btn("INV")
	_inv_btn.pressed.connect(_on_inventory)
	_vb.add_child(_inv_btn)

	# Setting
	var btn_setting := _make_btn(tex_setting, BTN_SIZE)
	btn_setting.pressed.connect(_on_setting)
	_vb.add_child(btn_setting)

	# Devon / devoff toggle — starts as dev:off
	_devon_btn = _make_btn(_tex_devoff, BTN_SIZE)
	_devon_btn.pressed.connect(_on_devon)
	_vb.add_child(_devon_btn)

	# Quit
	var btn_quit := _make_btn(tex_quit, BTN_SIZE)
	btn_quit.pressed.connect(_on_quit)
	_vb.add_child(btn_quit)

	# Hidden on the main gameplay screen — Setting/Inv stay reachable via the Player-HUD's own
	# MENU/INV board buttons (hud_binder.gd); Dev mode moved to a switch in the Settings panel.
	_vb.visible = false

	# Always-visible bottom-right Dev Mode toggle (2026-08-06, on request) — independent of _vb (which is
	# hidden until dev mode is ALREADY on, so it can't be the thing that turns it on). Sits one button-width
	# to the LEFT of _vb's own column so the two never overlap once _vb shows.
	_dev_toggle_btn = _make_btn(_tex_devoff, BTN_SIZE)
	_dev_toggle_btn.anchor_left   = 1.0
	_dev_toggle_btn.anchor_right  = 1.0
	_dev_toggle_btn.anchor_top    = 1.0
	_dev_toggle_btn.anchor_bottom = 1.0
	_dev_toggle_btn.offset_right  = -(BTN_SIZE + MARGIN * 2.0)
	_dev_toggle_btn.offset_left   = -(BTN_SIZE * 2.0 + MARGIN * 2.0)
	_dev_toggle_btn.offset_bottom = -MARGIN
	_dev_toggle_btn.offset_top    = -(BTN_SIZE + MARGIN)
	_dev_toggle_btn.pressed.connect(_on_devon)
	root.add_child(_dev_toggle_btn)

	# Dev buttons at top-left (below HP bar). Only visible when dev mode is on; spacing = BTN_SEP (same
	# as right column). 2026-08-18 regroup (request: "các nút dev mode giờ gom nhóm lại"): the 6
	# map-terrain-family buttons and the 5 creep/boss/fleet/wave-family buttons each collapsed into ONE
	# trigger button ("MAP EDIT" / "CREEP EDIT") that expands a flyout to the right when clicked. Every
	# sub-button below keeps its EXACT original texture/handler/behavior — only where it's shown changed.

	# ── MAP EDIT — Landmark Mark / Crater Mark / Plume Edit / Light Edit / Terrain Edit / Simplified ──
	# 2026-08-18: every button in this cluster is now a uniform SMALL_BTN_W × SMALL_BTN_H TEXT button
	# (no icon art, default font) — see _make_label_btn()'s own header comment.
	_map_edit_btn = _make_label_btn("MAP EDIT", SMALL_BTN_W, SMALL_BTN_H, 8)
	_map_edit_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y)
	_map_edit_btn.visible = false
	_map_edit_btn.pressed.connect(_on_map_edit_trigger)
	root.add_child(_map_edit_btn)

	_map_edit_flyout = VBoxContainer.new()
	_map_edit_flyout.add_theme_constant_override("separation", BTN_SEP)
	_map_edit_flyout.position = Vector2(SIMPLIFIED_X + SMALL_BTN_W + BTN_SEP, SIMPLIFIED_Y)
	_map_edit_flyout.visible = false
	root.add_child(_map_edit_flyout)

	# Landmark Mark — Volcanic/Atlantic-only (click the temple's top-down reference render to mark plume
	# points, see volcanic_landmark_mark.gd / atlantic_landmark_mark.gd).
	_landmark_mark_btn = _make_label_btn("LANDMARK", SMALL_BTN_W, SMALL_BTN_H, 7)
	_landmark_mark_btn.visible = false
	_landmark_mark_btn.pressed.connect(_on_landmark_mark)
	_map_edit_flyout.add_child(_landmark_mark_btn)

	# Crater Mark — Volcanic/Atlantic-only (click the maptile reference photo to mark craters/vents, see
	# volcanic_crater_mark.gd / atlantic_crater_mark.gd).
	_crater_mark_btn = _make_label_btn("CRATER", SMALL_BTN_W, SMALL_BTN_H, 7)
	_crater_mark_btn.visible = false
	_crater_mark_btn.pressed.connect(_on_crater_mark)
	_map_edit_flyout.add_child(_crater_mark_btn)

	# Plume Edit — Volcanic/Atlantic-only (ash/bubble-plume speed/height/density/color, see
	# volcanic_plume_edit.gd / atlantic_plume_edit.gd).
	_plume_edit_btn = _make_label_btn("PLUME", SMALL_BTN_W, SMALL_BTN_H, 7)
	_plume_edit_btn.visible = false
	_plume_edit_btn.pressed.connect(_on_plume_edit)
	_map_edit_flyout.add_child(_plume_edit_btn)

	# Light Edit — canopy normal-map lighting knobs (angle/height/ambient/specular, see
	# electric_light_edit.gd / volcanic_light_edit.gd / atlantic_light_edit.gd).
	_light_edit_btn = _make_label_btn("LIGHT", SMALL_BTN_W, SMALL_BTN_H, 7)
	_light_edit_btn.visible = false
	_light_edit_btn.pressed.connect(_on_light_edit)
	_map_edit_flyout.add_child(_light_edit_btn)

	# Terrain Edit — terrain-map-only (Electric/Volcanic/Atlantic; density/scale/blur/cloud
	# opacity+brightness/2 terrain colors — see electric_terrain_edit.gd / volcanic_terrain_edit.gd /
	# atlantic_terrain_edit.gd). ALSO gated on the current map (set_dev_mode() below only reveals it when
	# MetaManager.selected_map_id is "electric"/"volcanic"/"atlantic" — Default has no terrain/cloud/asset
	# system to edit).
	_terrain_edit_btn = _make_label_btn("TERRAIN", SMALL_BTN_W, SMALL_BTN_H, 7)
	_terrain_edit_btn.visible = false
	_terrain_edit_btn.pressed.connect(_on_terrain_edit)
	_map_edit_flyout.add_child(_terrain_edit_btn)

	# Simplified — was an icon that swapped Simplified.png/Simplifiedon.png to show ON/OFF; now a text
	# toggle (_on_simplified() sets .text/.color instead), same convention as Auto-Fire/God Mode below.
	_simplified_btn = _make_label_btn("SIMPLE:OFF", SMALL_BTN_W, SMALL_BTN_H, 7)
	_simplified_btn.visible = false
	_simplified_btn.pressed.connect(_on_simplified)
	_map_edit_flyout.add_child(_simplified_btn)

	# Picking any sub-tool collapses the flyout back (submenu convention) — a 2nd listener per button,
	# added after its own real handler above, so it doesn't disturb that handler's own signature/binding.
	for c: Node in _map_edit_flyout.get_children():
		(c as BaseButton).pressed.connect(func() -> void: _map_edit_flyout.visible = false)

	# ── CREEP EDIT — Boss Edit / Creep Info / Creep Edit / Fleet Edit / Wave Edit ──────────────────────
	# None of these 5 are map-gated (always shown once the flyout is open, dev:on).
	_creep_edit_group_btn = _make_label_btn("CREEP EDIT", SMALL_BTN_W, SMALL_BTN_H, 8)
	_creep_edit_group_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y + SMALL_BTN_H + BTN_SEP)
	_creep_edit_group_btn.visible = false
	_creep_edit_group_btn.pressed.connect(_on_creep_edit_trigger)
	root.add_child(_creep_edit_group_btn)

	_creep_edit_flyout = VBoxContainer.new()
	_creep_edit_flyout.add_theme_constant_override("separation", BTN_SEP)
	_creep_edit_flyout.position = Vector2(SIMPLIFIED_X + SMALL_BTN_W + BTN_SEP, SIMPLIFIED_Y + SMALL_BTN_H + BTN_SEP)
	_creep_edit_flyout.visible = false
	root.add_child(_creep_edit_flyout)

	_boss_edit_btn = _make_label_btn("BOSS EDIT", SMALL_BTN_W, SMALL_BTN_H, 7)
	_boss_edit_btn.visible = false
	_boss_edit_btn.pressed.connect(_on_boss_edit)
	_creep_edit_flyout.add_child(_boss_edit_btn)

	# Creep Info — opens a table (icon/name/HP/Move/Shoot) for every enemy type — see creep_info_panel.gd.
	_creep_info_btn = _make_label_btn("CREEP INFO", SMALL_BTN_W, SMALL_BTN_H, 7)
	_creep_info_btn.visible = false
	_creep_info_btn.pressed.connect(_on_creep_info)
	_creep_edit_flyout.add_child(_creep_info_btn)

	# Creep Edit — the individual sprite/layout tool (creep_edit_mode.gd), distinct from the "CREEP EDIT"
	# group trigger above even though they share a name.
	_creep_edit_btn = _make_label_btn("CREEP EDIT", SMALL_BTN_W, SMALL_BTN_H, 7)
	_creep_edit_btn.visible = false
	_creep_edit_btn.pressed.connect(_on_creep_edit)
	_creep_edit_flyout.add_child(_creep_edit_btn)

	_fleet_edit_btn = _make_label_btn("FLEET EDIT", SMALL_BTN_W, SMALL_BTN_H, 7)
	_fleet_edit_btn.visible = false
	_fleet_edit_btn.pressed.connect(_on_fleet_edit)
	_creep_edit_flyout.add_child(_fleet_edit_btn)

	_wave_edit_btn = _make_label_btn("WAVE EDIT", SMALL_BTN_W, SMALL_BTN_H, 7)
	_wave_edit_btn.visible = false
	_wave_edit_btn.pressed.connect(_on_wave_edit)
	_creep_edit_flyout.add_child(_wave_edit_btn)

	for c: Node in _creep_edit_flyout.get_children():
		(c as BaseButton).pressed.connect(func() -> void: _creep_edit_flyout.visible = false)

	# ── Standalone buttons below the 2 group triggers — unchanged behavior, "giữ nguyên" ───────────────
	var y_next := SIMPLIFIED_Y + SMALL_BTN_H + BTN_SEP + SMALL_BTN_H + BTN_SEP

	# Weapon Info — opens the item catalog table (icon/name/code/category/mfr/damage/speed/lore +
	# expandable perk pools, Drop/Evolve/Fusion/Unique sub-tabs on the Weapon tab) across
	# Weapon/Aux/Shield/Hull/Thruster — see weapon_info_panel.gd. NOT the same as the "Weapon" button
	# below (_weapon_btn) — that one opens the older Spawn Weapon debug grid (arena_debug_spawn.gd).
	_weapon_info_btn = _make_label_btn("WEAPON INFO", SMALL_BTN_W, SMALL_BTN_H, 7)
	_weapon_info_btn.position = Vector2(SIMPLIFIED_X, y_next)
	_weapon_info_btn.visible = false
	_weapon_info_btn.pressed.connect(_on_weapon_info)
	root.add_child(_weapon_info_btn)
	y_next += SMALL_BTN_H + BTN_SEP

	# Creep (Quick Spawn debug grid) — unchanged.
	_creep_btn = _make_label_btn("CREEP", SMALL_BTN_W, SMALL_BTN_H, 8)
	_creep_btn.position = Vector2(SIMPLIFIED_X, y_next)
	_creep_btn.visible = false
	_creep_btn.pressed.connect(_on_creep_panel)
	root.add_child(_creep_btn)
	y_next += SMALL_BTN_H + BTN_SEP

	# Weapon (Quick Spawn debug grid) — unchanged.
	_weapon_btn = _make_label_btn("WEAPON", SMALL_BTN_W, SMALL_BTN_H, 8)
	_weapon_btn.position = Vector2(SIMPLIFIED_X, y_next)
	_weapon_btn.visible = false
	_weapon_btn.pressed.connect(_on_weapon_panel)
	root.add_child(_weapon_btn)
	y_next += SMALL_BTN_H + BTN_SEP

	_hotkey_btn = _make_label_btn("HOTKEY", SMALL_BTN_W, SMALL_BTN_H, 8)
	_hotkey_btn.position = Vector2(SIMPLIFIED_X, y_next)
	_hotkey_btn.visible = false
	_hotkey_btn.pressed.connect(_on_hotkey_panel)
	root.add_child(_hotkey_btn)
	y_next += SMALL_BTN_H + BTN_SEP

	# HUD Edit — unchanged.
	_hud_edit_btn = _make_label_btn("HUD EDIT", SMALL_BTN_W, SMALL_BTN_H, 8)
	_hud_edit_btn.position = Vector2(SIMPLIFIED_X, y_next)
	_hud_edit_btn.visible = false
	_hud_edit_btn.pressed.connect(_on_hud_edit)
	root.add_child(_hud_edit_btn)
	y_next += SMALL_BTN_H + BTN_SEP

	# Small dev-cluster buttons (End Run / Auto-Fire / +Level) — SMALL_BTN_W/H (top of file), the same
	# uniform size now shared by the whole cluster above.
	var y_small := y_next

	# End Run — below HUD Edit, top of the small-button stack (dev:on only). Same effect as F4 (_skip_run
	# in arena_debug_spawn.gd): simulated rewards + jump straight to the RUN OVER screen.
	_end_run_btn = _make_label_btn("END RUN", SMALL_BTN_W, SMALL_BTN_H, 8)
	_end_run_btn.position = Vector2(SIMPLIFIED_X, y_small)
	_end_run_btn.visible = false
	_end_run_btn.pressed.connect(_on_end_run)
	root.add_child(_end_run_btn)

	# Boss Fight — to the RIGHT of End Run (same row, dev:on only). Skips straight to the loaded timeline's
	# final-boss finale (arena_wave_director_v2.gd's debug_jump_to_final_boss(), via arena_debug_spawn.gd)
	# for testing the fight + the BOSS ELIMINATED / RUN OVER screens without clearing every wave by hand.
	_boss_fight_btn = _make_label_btn("BOSS FIGHT", SMALL_BTN_W, SMALL_BTN_H, 8)
	_boss_fight_btn.position = Vector2(SIMPLIFIED_X + SMALL_BTN_W + BTN_SEP, y_small)
	_boss_fight_btn.visible = false
	_boss_fight_btn.pressed.connect(_on_boss_fight_debug)
	root.add_child(_boss_fight_btn)
	y_small += SMALL_BTN_H + BTN_SEP

	# Auto-Fire — below End Run. ON: ship auto-faces the nearest enemy (read by arena.gd._aim() via
	# is_auto_fire_on()) instead of the mouse; movement (WASD) is absolute-direction and untouched either way.
	_auto_fire_btn = _make_label_btn("AUTO:OFF", SMALL_BTN_W, SMALL_BTN_H, 8)
	_auto_fire_btn.position = Vector2(SIMPLIFIED_X, y_small)
	_auto_fire_btn.visible = false
	_auto_fire_btn.pressed.connect(_on_auto_fire)
	root.add_child(_auto_fire_btn)
	y_small += SMALL_BTN_H + BTN_SEP

	# God Mode — below Auto-Fire. ON: forces Auto-Fire on (ship auto-aims/fires at the nearest enemy) +
	# GameManager.set_god_mode (weapon damage ×10000, full HP/shield immunity — see game_manager.gd's
	# ship_take_damage god_mode guard). A single combined dev cheat toggle, not 3 separate switches.
	_god_mode_btn = _make_label_btn("GOD:OFF", SMALL_BTN_W, SMALL_BTN_H, 8)
	_god_mode_btn.position = Vector2(SIMPLIFIED_X, y_small)
	_god_mode_btn.visible = false
	_god_mode_btn.pressed.connect(_on_god_mode)
	root.add_child(_god_mode_btn)
	y_small += SMALL_BTN_H + BTN_SEP

	# +Level — below God Mode. Same effect as arena_debug_spawn's "+ Level" button: grants exactly enough
	# XP to force one player level-up.
	_level_btn = _make_label_btn("+LEVEL", SMALL_BTN_W, SMALL_BTN_H, 8)
	_level_btn.position = Vector2(SIMPLIFIED_X, y_small)
	_level_btn.visible = false
	_level_btn.pressed.connect(_on_add_level)
	root.add_child(_level_btn)

## 2026-08-18 request: dev-mode buttons use the engine's DEFAULT font now, not Mandalore — Mandalore's
## uppercase-A glyph is broken (see mandalore_text.gd) and MandaloreText.a() is only correct for text
## actually rendered in that font; this file's buttons never should have loaded it unconditionally like
## this (same class of bug already fixed in arena_wave_editor.gd — see that file's _txt() and the
## traveler_mandaloretext_rule memory note). No font override + no MandaloreText.a() wrapping here.
func _make_label_btn(label: String, width: float = BTN_SIZE, height: float = BTN_SIZE, font_size: int = 11) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(width, height)
	var s := StyleBoxFlat.new()
	s.bg_color = UiPalette.SURFACE_2
	s.border_color = UiPalette.WIRE_2
	s.set_border_width_all(1)
	s.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = UiPalette.SURFACE_3
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = UiPalette.ACCENT_DIM
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", UiPalette.INK)
	btn.clip_text = true   # uniform SMALL_BTN_W (54px) is narrower than some labels (e.g. "WEAPON INFO") — clip instead of overflow
	return btn

func _make_btn(tex: Texture2D, h: float) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(BTN_SIZE, h)
	return btn

# ── Button handlers ────────────────────────────────────────────────────────────

## Esc: open the Settings panel (pause menu), same panel/behavior as the Setting button. Pressing Esc
## again while it's open closes it without saving (same as the Cancel button). While dev mode is on, Esc
## instead closes whichever dev-mode panel is currently open (2026-08-18 request — see
## _close_open_dev_panel(); none of those editors had their own Escape handling before this). Likewise if
## Inventory is open, its own Escape handler closes it first instead of also popping Settings on top.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).keycode != KEY_ESCAPE:
		return
	if _settings == null:
		return
	if _settings.is_open():
		_settings._on_cancel()
		get_viewport().set_input_as_handled()
		return
	if _dev_mode:
		if _close_open_dev_panel():
			get_viewport().set_input_as_handled()
		return
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("is_open") and inv.is_open():
		return
	_settings.open()
	get_viewport().set_input_as_handled()

## 2026-08-18 request: "bấm phím Esc tự động tắt các bảng khi đang mở" — closes EVERY currently-open
## dev-mode panel (checked via each one's own is_open(), same convention creep_edit_mode.gd /
## boss_edit_mode.gd / fleet_edit_mode.gd / creep_info_panel.gd / weapon_info_panel.gd / hud_edit_mode.gd /
## arena_wave_editor.gd / the 11 map-terrain-family editors all already expose). Falls back to just
## collapsing an expanded-but-empty Map Edit / Creep Edit flyout if nothing underneath is actually open.
## Returns true if it did anything (so the caller knows to consume the keypress), false otherwise —
## letting Esc fall through to Settings when dev mode is on but nothing dev-specific is open would be
## surprising (dev mode already blocks that path unconditionally, unchanged from before this request).
## Picks the TERRAIN EDIT / LIGHT EDIT node-group name for whichever themed map is currently selected —
## atlantic/volcanic/mechanic each get their own explicit branch, Electric is the (only) implicit fallback for
## every id NOT in that list (matches _has_terrain_editor's own explicit id check below, so an id outside all
## 4 — e.g. "default" — never reaches these groups in the first place). Explicit per-id branches (rather than
## a single chained ternary) so adding a 5th themed map later is a one-line addition here, not a 5-way ternary
## rewrite, and so an unhandled id can never silently fall through to Electric's panels the way it used to
## before Mechanic was added (that implicit-fallback shape is exactly how a 4th themed map would have gone
## unnoticed).
func _terrain_edit_group(map_id: String) -> String:
	match map_id:
		"atlantic": return "atlantic_terrain_edit"
		"volcanic": return "volcanic_terrain_edit"
		"mechanic": return "mechanic_terrain_edit"
		"arctic": return "arctic_terrain_edit"
		_: return "electric_terrain_edit"

func _light_edit_group(map_id: String) -> String:
	match map_id:
		"atlantic": return "atlantic_light_edit"
		"volcanic": return "volcanic_light_edit"
		"mechanic": return "mechanic_light_edit"
		"arctic": return "arctic_light_edit"
		_: return "electric_light_edit"

## Picks the PLUME EDIT node-group name — unlike terrain/light edit, this only covers the 3 maps that
## actually HAVE a plume/wind system (atlantic/volcanic/mechanic); Electric has none, so there's no meaningful
## fallback group here the way "electric_terrain_edit" works above — callers gate on _has_plume_system first
## (see set_dev_mode) and never call this for an id outside those 3.
func _plume_edit_group(map_id: String) -> String:
	match map_id:
		"atlantic": return "atlantic_plume_edit"
		"mechanic": return "mechanic_plume_edit"
		"arctic": return "arctic_plume_edit"
		_: return "volcanic_plume_edit"

## Picks the CRATER MARK node-group name — covers the same 3 maps as _plume_edit_group (mechanic_vent_mark.gd,
## 2026-08-19: the marking tool a plume system needs to place vents at deliberate spots, not just random
## ambient scatter — see mechanic_plumes.gd's header). Callers gate on _has_vent_marking first (see
## set_dev_mode) and never call this for an id outside those 3. Mechanic has no LANDMARK marking though (no
## landmark .glb yet) — that stays volcanic/atlantic-only, see _has_landmark_marking.
func _crater_mark_group(map_id: String) -> String:
	match map_id:
		"atlantic": return "atlantic_crater_mark"
		"mechanic": return "mechanic_vent_mark"
		"arctic": return "arctic_vent_mark"
		_: return "volcanic_crater_mark"

func _close_open_dev_panel() -> bool:
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var groups: Array[String] = [
		"boss_edit", "creep_edit", "creep_info", "fleet_edit", "wave_editor", "hud_edit", "weapon_info",
		_terrain_edit_group(map_id),
		_light_edit_group(map_id),
		_plume_edit_group(map_id),
		_crater_mark_group(map_id),
		("atlantic_landmark_mark" if map_id == "atlantic" else "volcanic_landmark_mark"),
	]
	var closed_any := false
	for g: String in groups:
		var n := get_tree().get_first_node_in_group(g)
		if n != null and n.has_method("is_open") and n.has_method("toggle") and bool(n.call("is_open")):
			n.call("toggle")
			closed_any = true
	if closed_any:
		return true
	if _map_edit_flyout != null and _map_edit_flyout.visible:
		_map_edit_flyout.visible = false
		return true
	if _creep_edit_flyout != null and _creep_edit_flyout.visible:
		_creep_edit_flyout.visible = false
		return true
	return false

## Derives the new state from the tree's ACTUAL live paused flag, not _game_paused's own remembered value —
## several other panels (weapon palette F12, planet menu F6, drop UI, weapon chest UI, level-up UI) force
## get_tree().paused on/off directly for their own modal purposes without touching _game_paused, so a blind
## `_game_paused = !_game_paused` could drift out of sync with reality (2026-08-02 bug report: "Pause needs
## 2 clicks" — one click was silently just catching _game_paused up to whatever the tree already was, with
## no visible effect, before the next click did what the user actually asked for).
func _on_pause() -> void:
	_game_paused = not get_tree().paused
	get_tree().paused = _game_paused

func _on_codex() -> void:
	pass   # placeholder

func _on_inventory() -> void:
	_click_sfx()
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("toggle"):
		inv.call("toggle")

func _on_setting() -> void:
	if _settings != null:
		_settings.open()

func _on_devon() -> void:
	set_dev_mode(!_dev_mode)

## Current dev-mode state — read by the Settings panel's Dev Mode switch to sync itself on open.
func is_dev_mode() -> bool:
	return _dev_mode

## Public: toggles dev mode from the Settings panel's Dev Mode switch (the Devon button itself is hidden on
## the main gameplay screen — see _build_ui()). Turning ON pauses the game, since the dev tools need it held
## still; turning OFF does NOT force-unpause — Settings is already the one managing pause (it paused the tree
## on open() and restores whatever it was on close), so unpausing here would resume gameplay behind an open
## panel.
func set_dev_mode(v: bool) -> void:
	if v == _dev_mode:
		return
	_dev_mode = v

	# Toggle dev debug UI (arena_debug_spawn)
	var ds := get_tree().get_first_node_in_group("arena_debug_spawn")
	if ds != null and ds.has_method("set_dev_ui_visible"):
		ds.set_dev_ui_visible(_dev_mode)

	if _dev_mode:
		_game_paused = true
		get_tree().paused = true

	# Show / hide the bottom-right column (Pause/Codex/Inv/Setting/Devon/Quit) + dev buttons at top-left
	_vb.visible = _dev_mode
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var _has_terrain_editor := map_id == "electric" or map_id == "volcanic" or map_id == "atlantic" or map_id == "mechanic" or map_id == "arctic"
	var _has_plume_system := map_id == "volcanic" or map_id == "atlantic" or map_id == "mechanic" or map_id == "arctic"
	# Vent/crater MARKING is now on all 4 (mechanic_vent_mark.gd/arctic_vent_mark.gd, 2026-08-19 — the
	# ambient-only first pass was missing this). LANDMARK marking stays narrower — Mechanic/Arctic have no
	# landmark .glb SCATTERED on the ground yet, unlike Volcanic/Atlantic, so there's nothing to attach a
	# landmark-scoped plume mark to.
	var _has_vent_marking := map_id == "volcanic" or map_id == "atlantic" or map_id == "mechanic" or map_id == "arctic"
	var _has_landmark_marking := map_id == "volcanic" or map_id == "atlantic"
	_map_edit_btn.visible = _dev_mode
	_creep_edit_group_btn.visible = _dev_mode
	# Every toggle collapses both flyouts back to closed — a clean, deterministic starting state instead
	# of "remembering" whichever was expanded across a dev-mode off/on cycle.
	_map_edit_flyout.visible = false
	_creep_edit_flyout.visible = false
	_terrain_edit_btn.visible = _dev_mode and _has_terrain_editor   # Default has no terrain/cloud/asset system to edit
	_light_edit_btn.visible = _dev_mode and _has_terrain_editor     # same gating — ground lighting is terrain-map-only too
	_plume_edit_btn.visible = _dev_mode and _has_plume_system    # ash/bubble/steam plumes — no clouds system on Electric
	_crater_mark_btn.visible = _dev_mode and _has_vent_marking     # crater/vent marking — see _has_vent_marking
	_landmark_mark_btn.visible = _dev_mode and _has_landmark_marking # landmark marking — Volcanic/Atlantic only
	_simplified_btn.visible = _dev_mode
	_boss_edit_btn.visible  = _dev_mode
	_creep_info_btn.visible = _dev_mode
	_creep_edit_btn.visible = _dev_mode
	_creep_btn.visible      = _dev_mode
	_weapon_btn.visible     = _dev_mode
	_hotkey_btn.visible     = _dev_mode
	_fleet_edit_btn.visible = _dev_mode
	_wave_edit_btn.visible  = _dev_mode
	_hud_edit_btn.visible   = _dev_mode
	_end_run_btn.visible    = _dev_mode
	_boss_fight_btn.visible = _dev_mode
	_auto_fire_btn.visible  = _dev_mode
	_god_mode_btn.visible   = _dev_mode
	_level_btn.visible      = _dev_mode
	_weapon_info_btn.visible = _dev_mode

	# Update Devon button texture (both the legacy in-column one and the always-visible corner toggle)
	_devon_btn.texture_normal = _tex_devon if _dev_mode else _tex_devoff
	_dev_toggle_btn.texture_normal = _tex_devon if _dev_mode else _tex_devoff

func _click_sfx() -> void:
	if _click_player != null:
		_click_player.play()

func _toggle_ds_panel(method: String) -> void:
	var ds := get_tree().get_first_node_in_group("arena_debug_spawn")
	if ds != null and ds.has_method(method):
		ds.call(method)

func _on_creep_panel() -> void:
	_click_sfx()
	_toggle_ds_panel("toggle_creep_panel")

func _on_weapon_panel() -> void:
	_click_sfx()
	_toggle_ds_panel("toggle_weapon_panel")

func _on_hotkey_panel() -> void:
	_click_sfx()
	_toggle_ds_panel("toggle_hotkey_panel")

## MAP EDIT trigger — expands/collapses the flyout listing Landmark Mark/Crater Mark/Plume Edit/Light
## Edit/Terrain Edit/Simplified. Also collapses the OTHER flyout (Creep Edit) if it happened to be open,
## so at most one flyout is ever expanded at a time.
func _on_map_edit_trigger() -> void:
	_click_sfx()
	_map_edit_flyout.visible = not _map_edit_flyout.visible
	if _map_edit_flyout.visible:
		_creep_edit_flyout.visible = false

## CREEP EDIT trigger — expands/collapses the flyout listing Boss Edit/Creep Info/Creep Edit/Fleet
## Edit/Wave Edit. Mirrors _on_map_edit_trigger()'s single-flyout-open-at-a-time behavior.
func _on_creep_edit_trigger() -> void:
	_click_sfx()
	_creep_edit_flyout.visible = not _creep_edit_flyout.visible
	if _creep_edit_flyout.visible:
		_map_edit_flyout.visible = false

func _on_terrain_edit() -> void:
	_click_sfx()
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var tem := get_tree().get_first_node_in_group(_terrain_edit_group(map_id))
	if tem != null and tem.has_method("toggle"):
		tem.toggle()

func _on_light_edit() -> void:
	_click_sfx()
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var lem := get_tree().get_first_node_in_group(_light_edit_group(map_id))
	if lem != null and lem.has_method("toggle"):
		lem.toggle()

func _on_plume_edit() -> void:
	_click_sfx()
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var pem := get_tree().get_first_node_in_group(_plume_edit_group(map_id))
	if pem != null and pem.has_method("toggle"):
		pem.toggle()

func _on_crater_mark() -> void:
	_click_sfx()
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var cmm := get_tree().get_first_node_in_group(_crater_mark_group(map_id))
	if cmm != null and cmm.has_method("toggle"):
		cmm.toggle()

func _on_landmark_mark() -> void:
	_click_sfx()
	var map_id := String(MetaManager.selected_map_id) if typeof(MetaManager) != TYPE_NIL else "default"
	var group := "atlantic_landmark_mark" if map_id == "atlantic" else "volcanic_landmark_mark"
	var lmm := get_tree().get_first_node_in_group(group)
	if lmm != null and lmm.has_method("toggle"):
		lmm.toggle()

func _on_boss_edit() -> void:
	_click_sfx()
	var bem := get_tree().get_first_node_in_group("boss_edit")
	if bem != null and bem.has_method("toggle"):
		bem.toggle()

func _on_creep_info() -> void:
	_click_sfx()
	var cip := get_tree().get_first_node_in_group("creep_info")
	if cip != null and cip.has_method("toggle"):
		cip.toggle()

func _on_creep_edit() -> void:
	_click_sfx()
	var cem := get_tree().get_first_node_in_group("creep_edit")
	if cem != null and cem.has_method("toggle"):
		cem.toggle()

func _on_weapon_info() -> void:
	_click_sfx()
	var wip := get_tree().get_first_node_in_group("weapon_info")
	if wip != null and wip.has_method("toggle"):
		wip.toggle()

## Read every frame by arena.gd._aim() (group "arena_hud_buttons") to decide mouse-aim vs. nearest-enemy-aim.
func is_auto_fire_on() -> bool:
	return _auto_fire

func _on_auto_fire() -> void:
	_click_sfx()
	set_auto_aim(not _auto_fire)

## Public: Settings panel's "Auto-Aim" switch (settings_panel.gd, persisted to user://settings.cfg's
## [game] auto_aim, re-armed at _ready() below) — same underlying flag as the dev-cluster AUTO button
## above, just reachable by regular players instead of dev-mode only. Keeps the dev button's own
## label/color in sync so flipping either one doesn't desync from the other.
func set_auto_aim(v: bool) -> void:
	_auto_fire = v
	if _auto_fire_btn != null:
		_auto_fire_btn.text = "AUTO:ON" if _auto_fire else "AUTO:OFF"
		_auto_fire_btn.add_theme_color_override("font_color", UiPalette.GOOD if _auto_fire else UiPalette.INK)

## Combined dev cheat: forces Auto-Fire on (and keeps that button's own label/color in sync) + GameManager's
## damage-mult/invulnerability god_mode flag. Turning God Mode back off also turns Auto-Fire back off — one
## bundled toggle, not 3 independent switches the user has to remember to undo separately.
func _on_god_mode() -> void:
	_click_sfx()
	_god_mode = not _god_mode
	_god_mode_btn.text = "GOD:ON" if _god_mode else "GOD:OFF"
	_god_mode_btn.add_theme_color_override("font_color", UiPalette.AMBER if _god_mode else UiPalette.INK)
	_auto_fire = _god_mode
	_auto_fire_btn.text = "AUTO:ON" if _auto_fire else "AUTO:OFF"
	_auto_fire_btn.add_theme_color_override("font_color", UiPalette.GOOD if _auto_fire else UiPalette.INK)
	if GameManager.has_method("set_god_mode"):
		GameManager.set_god_mode(_god_mode)

## Same effect as arena_debug_spawn.gd's "+ Level" button: grants exactly enough XP for one level-up.
func _on_add_level() -> void:
	_click_sfx()
	if GameManager.has_method("add_xp"):
		var level: int = GameManager.player_level if "player_level" in GameManager else 1
		var xp_needed: int = GameManager.xp_to_next(level) if GameManager.has_method("xp_to_next") else 100
		GameManager.add_xp(xp_needed)

## 2026-08-07, on request: END RUN now asks WIN or LOSE first (small popup) instead of always ending in
## defeat like F4 does — WIN shows the BOSS ELIMINATED / victory framing (arena.gd's force_end_run(true),
## same screen a real final-boss kill shows), LOSE is the original RUN OVER behavior. Same simulated rewards
## either way (arena_debug_spawn.gd's _skip_run) — only the end-screen outcome differs.
func _on_end_run() -> void:
	_click_sfx()
	if _end_run_popup == null:
		_build_end_run_popup()
	_end_run_popup.visible = true

func _build_end_run_popup() -> void:
	_end_run_popup = CanvasLayer.new()
	_end_run_popup.layer = 90   # above the dev HUD buttons (this CanvasLayer has no explicit layer = 0), below Settings (100)
	_end_run_popup.process_mode = Node.PROCESS_MODE_ALWAYS   # dev mode pauses the tree; popup must still take input
	add_child(_end_run_popup)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_run_popup.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_run_popup.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = UiPalette.ACCENT_DIM
	sb.set_content_margin_all(18.0)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "End Run — pick an outcome"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(btn_row)

	var win_btn := _make_label_btn("WIN", 90.0, 34.0, 13)
	win_btn.add_theme_color_override("font_color", UiPalette.GOOD)
	win_btn.pressed.connect(_on_end_run_choice.bind(true))
	btn_row.add_child(win_btn)

	var lose_btn := _make_label_btn("LOSE", 90.0, 34.0, 13)
	lose_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	lose_btn.pressed.connect(_on_end_run_choice.bind(false))
	btn_row.add_child(lose_btn)

	var cancel_btn := _make_label_btn("Cancel", 190.0, 26.0, 11)
	cancel_btn.pressed.connect(func() -> void: _end_run_popup.visible = false)
	vb.add_child(cancel_btn)

func _on_end_run_choice(victory: bool) -> void:
	_click_sfx()
	_end_run_popup.visible = false
	var ds := get_tree().get_first_node_in_group("arena_debug_spawn")
	if ds != null and ds.has_method("_skip_run"):
		ds.call("_skip_run", victory)

## Skip straight to the loaded timeline's final-boss finale (arena_debug_spawn.gd's _jump_to_boss_fight →
## arena_wave_director_v2.gd's debug_jump_to_final_boss) — clears the field and fast-forwards past every
## remaining regular wave so the boss shows up almost immediately, for testing the fight + end screens.
func _on_boss_fight_debug() -> void:
	_click_sfx()
	_toggle_ds_panel("_jump_to_boss_fight")

func _on_fleet_edit() -> void:
	_click_sfx()
	var fem := get_tree().get_first_node_in_group("fleet_edit")
	if fem != null and fem.has_method("toggle"):
		fem.toggle()

func _on_wave_edit() -> void:
	_click_sfx()
	var wem := get_tree().get_first_node_in_group("wave_editor")
	if wem != null and wem.has_method("toggle"):
		wem.toggle()

func _on_hud_edit() -> void:
	_click_sfx()
	var hem := get_tree().get_first_node_in_group("hud_edit")
	if hem != null and hem.has_method("toggle"):
		hem.toggle()

func _on_simplified() -> void:
	_click_sfx()
	ArenaEnemy.simplified_mode = !ArenaEnemy.simplified_mode
	# 2026-08-18: was an icon swap (Simplified.png/Simplifiedon.png); now a text/color toggle, same
	# convention as Auto-Fire/God Mode.
	_simplified_btn.text = "SIMPLE:ON" if ArenaEnemy.simplified_mode else "SIMPLE:OFF"
	_simplified_btn.add_theme_color_override("font_color", UiPalette.GOOD if ArenaEnemy.simplified_mode else UiPalette.INK)

	# Scan simplified folder → build filename→path dict
	var simplified_files: Dictionary = {}
	var dir := DirAccess.open("res://assets/enemies/simplified")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and not fname.ends_with(".import"):
				simplified_files[fname] = "res://assets/enemies/simplified/" + fname
			fname = dir.get_next()
		dir.list_dir_end()

	# Apply to all active arena enemies
	for enemy in get_tree().get_nodes_in_group("arena_enemy"):
		if enemy.has_method("apply_simplified"):
			enemy.apply_simplified(ArenaEnemy.simplified_mode, simplified_files)

func _on_quit() -> void:
	# Return to the Main Menu (the menu also persists state via its own Quit button).
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
