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
var _pause_btn:      TextureButton = null
var _terrain_edit_btn: Button = null
var _light_edit_btn: Button = null
var _boss_edit_btn:  TextureButton = null
var _creep_info_btn: Button = null
var _creep_edit_btn: TextureButton = null
var _simplified_btn: TextureButton = null
var _creep_btn:      TextureButton = null
var _weapon_btn:     TextureButton = null
var _hotkey_btn:     TextureButton = null
var _fleet_edit_btn: TextureButton = null
var _wave_edit_btn:  TextureButton = null
var _hud_edit_btn:   TextureButton = null
var _end_run_btn:    Button = null
var _boss_fight_btn: Button = null
var _auto_fire_btn:  Button = null
var _god_mode_btn:   Button = null
var _level_btn:      Button = null
var _inv_btn:        Button = null
var _vb:             VBoxContainer = null

# Textures
var _tex_devon:         Texture2D = null
var _tex_devoff:        Texture2D = null
var _tex_pause:         Texture2D = null
var _tex_boss_edit:     Texture2D = null
var _tex_creep_edit:    Texture2D = null
var _tex_simplified:    Texture2D = null
var _tex_simplifiedon:  Texture2D = null
var _tex_creep:         Texture2D = null
var _tex_weapon:        Texture2D = null
var _tex_hotkey:        Texture2D = null
var _tex_fleet_edit:    Texture2D = null
var _tex_wave_edit:     Texture2D = null
var _tex_hud_edit:      Texture2D = null

# Total height without dev-edit buttons (for VBox repositioning)
var _base_total_h: float = 0.0

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("arena_hud_buttons")   # so the Settings panel's Dev Mode switch can find this instance
	_tex_devon         = _load_img("res://assets/hud/Devon.png")
	_tex_devoff        = _load_img("res://assets/hud/devoff.png")
	_tex_pause         = _load_img("res://assets/hud/Pause.png")
	_tex_boss_edit     = _load_img("res://assets/hud/Boss_edit.png")
	_tex_creep_edit    = _load_img("res://assets/hud/Creep_edit.png")
	_tex_simplified    = _load_img("res://assets/hud/Simplified.png")
	_tex_simplifiedon  = _load_img("res://assets/hud/Simplifiedon.png")
	_tex_creep         = _load_img("res://assets/hud/creep.png")
	_tex_weapon        = _load_img("res://assets/hud/weapon.png")
	_tex_hotkey        = _load_img("res://assets/hud/hotkey.png")
	_tex_fleet_edit    = _load_img("res://assets/hud/Fleet_edit.png")
	_tex_wave_edit     = _load_img("res://assets/hud/Wave_edit.png")
	_tex_hud_edit      = _load_img("res://assets/hud/Asset 41.png")
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
	var boss_edit_h  := _btn_h(_tex_boss_edit)
	var creep_edit_h := _btn_h(_tex_creep_edit)

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

	# Dev buttons at top-left (below HP bar): Terrain Edit → Simplified → Boss_edit → Creep_edit
	# Only visible when dev mode is on; spacing = BTN_SEP (same as right column)

	# Terrain Edit — Rubicon-map-only (density/scale/blur/cloud opacity+brightness/2 terrain colors — see
	# rubicon_terrain_edit.gd). No dedicated icon art, so a compact label button; ALSO gated on the current
	# map (set_dev_mode() below only reveals it when MetaManager.selected_map_id == "rubicon" — Default has
	# no terrain/cloud/asset system for it to edit).
	var terrain_edit_h := BTN_SIZE * 0.5
	_terrain_edit_btn = _make_label_btn("TERRAIN EDIT", BTN_SIZE * 1.8, terrain_edit_h, 9)
	_terrain_edit_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y)
	_terrain_edit_btn.visible = false
	_terrain_edit_btn.pressed.connect(_on_terrain_edit)
	root.add_child(_terrain_edit_btn)
	var simplified_y := SIMPLIFIED_Y + terrain_edit_h + BTN_SEP

	# Light Edit — canopy normal-map lighting knobs (angle/height/ambient/specular, see rubicon_light_edit.gd),
	# split out of the big Terrain Edit panel into its own small focused one. Sits directly ABOVE Terrain
	# Edit, going upward from SIMPLIFIED_Y so it never disturbs the existing cascade below Terrain Edit.
	var light_edit_h := BTN_SIZE * 0.5
	_light_edit_btn = _make_label_btn("LIGHT EDIT", BTN_SIZE * 1.8, light_edit_h, 9)
	_light_edit_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y - light_edit_h - BTN_SEP)
	_light_edit_btn.visible = false
	_light_edit_btn.pressed.connect(_on_light_edit)
	root.add_child(_light_edit_btn)

	var s_h := _btn_h(_tex_simplified)
	_simplified_btn = _make_btn(_tex_simplified, s_h)
	_simplified_btn.position = Vector2(SIMPLIFIED_X, simplified_y)
	_simplified_btn.visible = false
	_simplified_btn.pressed.connect(_on_simplified)
	root.add_child(_simplified_btn)

	_boss_edit_btn = _make_btn(_tex_boss_edit, boss_edit_h)
	_boss_edit_btn.position = Vector2(SIMPLIFIED_X, simplified_y + s_h + BTN_SEP)
	_boss_edit_btn.visible = false
	_boss_edit_btn.pressed.connect(_on_boss_edit)
	root.add_child(_boss_edit_btn)

	# Creep Info — between Boss Edit and Creep Edit (dev:on only). Opens a table (icon/name/HP/Move/Shoot)
	# for every enemy type — see creep_info_panel.gd. No dedicated icon art yet, so a compact label button
	# (same small-button style as END RUN/AUTO-FIRE/+LEVEL below).
	var creep_info_h := BTN_SIZE * 0.5
	_creep_info_btn = _make_label_btn("CREEP INFO", BTN_SIZE * 1.8, creep_info_h, 9)
	_creep_info_btn.position = Vector2(SIMPLIFIED_X, simplified_y + s_h + BTN_SEP + boss_edit_h + BTN_SEP)
	_creep_info_btn.visible = false
	_creep_info_btn.pressed.connect(_on_creep_info)
	root.add_child(_creep_info_btn)

	_creep_edit_btn = _make_btn(_tex_creep_edit, creep_edit_h)
	_creep_edit_btn.position = Vector2(SIMPLIFIED_X, simplified_y + s_h + BTN_SEP + boss_edit_h + BTN_SEP + creep_info_h + BTN_SEP)
	_creep_edit_btn.visible = false
	_creep_edit_btn.pressed.connect(_on_creep_edit)
	root.add_child(_creep_edit_btn)

	# Panel-toggle buttons below the edit cluster: creep / weapon / hotkey (dev:on only).
	var y_panels := simplified_y + s_h + BTN_SEP + boss_edit_h + BTN_SEP + creep_info_h + BTN_SEP + creep_edit_h + BTN_SEP
	var creep_h := _btn_h(_tex_creep)
	_creep_btn = _make_btn(_tex_creep, creep_h)
	_creep_btn.position = Vector2(SIMPLIFIED_X, y_panels)
	_creep_btn.visible = false
	_creep_btn.pressed.connect(_on_creep_panel)
	root.add_child(_creep_btn)

	var weapon_h := _btn_h(_tex_weapon)
	_weapon_btn = _make_btn(_tex_weapon, weapon_h)
	_weapon_btn.position = Vector2(SIMPLIFIED_X, y_panels + creep_h + BTN_SEP)
	_weapon_btn.visible = false
	_weapon_btn.pressed.connect(_on_weapon_panel)
	root.add_child(_weapon_btn)

	var hotkey_h := _btn_h(_tex_hotkey)
	_hotkey_btn = _make_btn(_tex_hotkey, hotkey_h)
	_hotkey_btn.position = Vector2(SIMPLIFIED_X, y_panels + creep_h + BTN_SEP + weapon_h + BTN_SEP)
	_hotkey_btn.visible = false
	_hotkey_btn.pressed.connect(_on_hotkey_panel)
	root.add_child(_hotkey_btn)

	# Fleet Edit — below the hotkey button (dev:on only)
	var fleet_h := _btn_h(_tex_fleet_edit)
	var y_fleet := y_panels + creep_h + BTN_SEP + weapon_h + BTN_SEP + hotkey_h + BTN_SEP
	_fleet_edit_btn = _make_btn(_tex_fleet_edit, fleet_h)
	_fleet_edit_btn.position = Vector2(SIMPLIFIED_X, y_fleet)
	_fleet_edit_btn.visible = false
	_fleet_edit_btn.pressed.connect(_on_fleet_edit)
	root.add_child(_fleet_edit_btn)

	# Wave Edit (F7) — below the Fleet button (dev:on only)
	var wave_h := _btn_h(_tex_wave_edit)
	_wave_edit_btn = _make_btn(_tex_wave_edit, wave_h)
	_wave_edit_btn.position = Vector2(SIMPLIFIED_X, y_fleet + fleet_h + BTN_SEP)
	_wave_edit_btn.visible = false
	_wave_edit_btn.pressed.connect(_on_wave_edit)
	root.add_child(_wave_edit_btn)

	# HUD Edit — below the Wave button (dev:on only)
	var hud_h := _btn_h(_tex_hud_edit)
	_hud_edit_btn = _make_btn(_tex_hud_edit, hud_h)
	_hud_edit_btn.position = Vector2(SIMPLIFIED_X, y_fleet + fleet_h + BTN_SEP + wave_h + BTN_SEP)
	_hud_edit_btn.visible = false
	_hud_edit_btn.pressed.connect(_on_hud_edit)
	root.add_child(_hud_edit_btn)

	# Small dev-cluster buttons (End Run / Auto-Fire / +Level) — half the size of the icon buttons above,
	# so this stack of 3 fits without pushing the column further off-screen.
	const SMALL_BTN_W := BTN_SIZE * 0.9    # 54px  (was BTN_SIZE * 1.8 = 108px)
	const SMALL_BTN_H := BTN_SIZE * 0.5    # 30px  (was BTN_SIZE = 60px)
	var y_small := y_fleet + fleet_h + BTN_SEP + wave_h + BTN_SEP + hud_h + BTN_SEP

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

	# +Level — below God Mode, bottom of the dev cluster (dev:on only). Same effect as arena_debug_spawn's
	# "+ Level" button: grants exactly enough XP to force one player level-up.
	_level_btn = _make_label_btn("+LEVEL", SMALL_BTN_W, SMALL_BTN_H, 8)
	_level_btn.position = Vector2(SIMPLIFIED_X, y_small)
	_level_btn.visible = false
	_level_btn.pressed.connect(_on_add_level)
	root.add_child(_level_btn)

func _make_label_btn(label: String, width: float = BTN_SIZE, height: float = BTN_SIZE, font_size: int = 11) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(width, height)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.12, 0.16, 0.85)
	s.border_color = Color(0.35, 0.45, 0.60)
	s.set_border_width_all(1)
	s.corner_radius_top_left = 3; s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.25, 0.35, 0.55, 1.0)
	btn.add_theme_stylebox_override("pressed", sp)
	var font := load("res://assets/fonts/Gameplay.ttf") as Font
	if font:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
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
## again while it's open closes it without saving (same as the Cancel button). Dev-mode editors (Boss/
## Creep/Fleet/Wave/HUD Edit) own Escape while dev mode is on, so this backs off in that case; likewise if
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
		return
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and inv.has_method("is_open") and inv.is_open():
		return
	_settings.open()
	get_viewport().set_input_as_handled()

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
	var is_rubicon := typeof(MetaManager) != TYPE_NIL and String(MetaManager.selected_map_id) == "rubicon"
	_terrain_edit_btn.visible = _dev_mode and is_rubicon   # Default has no terrain/cloud/asset system to edit
	_light_edit_btn.visible = _dev_mode and is_rubicon     # same gating — canopy lighting is Rubicon-only too
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

	# Update Devon button texture
	_devon_btn.texture_normal = _tex_devon if _dev_mode else _tex_devoff

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

func _on_terrain_edit() -> void:
	_click_sfx()
	var tem := get_tree().get_first_node_in_group("rubicon_terrain_edit")
	if tem != null and tem.has_method("toggle"):
		tem.toggle()

func _on_light_edit() -> void:
	_click_sfx()
	var lem := get_tree().get_first_node_in_group("rubicon_light_edit")
	if lem != null and lem.has_method("toggle"):
		lem.toggle()

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
		_auto_fire_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if _auto_fire else Color(0.85, 0.90, 1.0))

## Combined dev cheat: forces Auto-Fire on (and keeps that button's own label/color in sync) + GameManager's
## damage-mult/invulnerability god_mode flag. Turning God Mode back off also turns Auto-Fire back off — one
## bundled toggle, not 3 independent switches the user has to remember to undo separately.
func _on_god_mode() -> void:
	_click_sfx()
	_god_mode = not _god_mode
	_god_mode_btn.text = "GOD:ON" if _god_mode else "GOD:OFF"
	_god_mode_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if _god_mode else Color(0.85, 0.90, 1.0))
	_auto_fire = _god_mode
	_auto_fire_btn.text = "AUTO:ON" if _auto_fire else "AUTO:OFF"
	_auto_fire_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if _auto_fire else Color(0.85, 0.90, 1.0))
	if GameManager.has_method("set_god_mode"):
		GameManager.set_god_mode(_god_mode)

## Same effect as arena_debug_spawn.gd's "+ Level" button: grants exactly enough XP for one level-up.
func _on_add_level() -> void:
	_click_sfx()
	if GameManager.has_method("add_xp"):
		var level: int = GameManager.player_level if "player_level" in GameManager else 1
		var xp_needed: int = GameManager.xp_to_next(level) if GameManager.has_method("xp_to_next") else 100
		GameManager.add_xp(xp_needed)

## Same effect as F4: simulated rewards (arena_debug_spawn.gd's _skip_run), then straight to RUN OVER.
func _on_end_run() -> void:
	_click_sfx()
	_toggle_ds_panel("_skip_run")

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
	_simplified_btn.texture_normal = _tex_simplifiedon if ArenaEnemy.simplified_mode else _tex_simplified

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
