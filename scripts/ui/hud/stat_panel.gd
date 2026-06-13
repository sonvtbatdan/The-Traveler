extends Panel

const SETTINGS_PATH := "user://settings.cfg"
const AudioMonitorScript := preload("res://scripts/ui/hud/audio_monitor.gd")

const RESOLUTIONS: Array = [
	{"label": "720p\n1280×720",   "size": Vector2i(1280,  720)},
	{"label": "1080p\n1920×1080", "size": Vector2i(1920, 1080)},
	{"label": "2K\n2560×1440",    "size": Vector2i(2560, 1440)},
]

var _overlay_layer:    CanvasLayer   = null
var _overlay_rect:     ColorRect     = null
var _settings_panel:   Panel         = null
var _confirm_panel:    Panel         = null
var _confirm_msg_lbl:  Label         = null
var _pending_action:   String        = ""

var _res_btns:     Array[Button] = []
var _music_slider: HSlider       = null
var _sfx_slider:   HSlider       = null
var _mute_btn:     Button        = null

var _init_music_vol: float = 1.0
var _init_sfx_vol:   float = 1.0
var _pre_mute_music: float = -1.0   # -1 = not muted; ≥0 = saved pre-mute volume
var _audio_monitor:  Node  = null
var _mat_spins:      Dictionary = {}  # "metal"|"nonmetal"|"liquid"|"organic" -> SpinBox

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_monitor = AudioMonitorScript.new()
	add_child(_audio_monitor)
	_apply_style()
	_load_settings()
	_build_action_bar()
	call_deferred("_build_settings_panel")
	call_deferred("_anchor_bottom_right")

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

# ── Action bar ────────────────────────────────────────────────────────────────

func _build_action_bar() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6; vbox.offset_right  = -6
	vbox.offset_top  = 4; vbox.offset_bottom = -4
	vbox.add_theme_constant_override("separation", 3)
	add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox)

	_mute_btn = _make_btn("MUTE")
	var setting_btn := _make_btn("SETTING")
	var quit_btn    := _make_btn("QUIT")
	hbox.add_child(_mute_btn)
	hbox.add_child(setting_btn)
	hbox.add_child(quit_btn)
	_mute_btn.pressed.connect(_toggle_mute)
	setting_btn.pressed.connect(_toggle_settings)
	quit_btn.pressed.connect(_on_quit)

	var hbox2 := HBoxContainer.new()
	hbox2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox2.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox2)

	var reset_hp_btn := _make_btn("RESET HP")
	var kill_boss_btn := _make_btn("KILL BOSS")
	var roll_btn := _make_btn("ROLL WEAPON")
	var roll_hull_btn := _make_btn("ROLL HULL")
	var add_xp_btn := _make_btn("ADD XP")
	hbox2.add_child(reset_hp_btn)
	hbox2.add_child(kill_boss_btn)
	hbox2.add_child(roll_btn)
	hbox2.add_child(roll_hull_btn)
	hbox2.add_child(add_xp_btn)
	reset_hp_btn.pressed.connect(_on_reset_hp)
	kill_boss_btn.pressed.connect(_on_kill_boss)
	roll_btn.pressed.connect(_on_roll_weapon)
	roll_hull_btn.pressed.connect(_on_roll_hull)
	add_xp_btn.pressed.connect(_on_add_xp)

## DEBUG (Phase 1 test): grant 100 XP and print the resulting level/xp so the widening curve is visible.
func _on_add_xp() -> void:
	GameManager.add_xp(100)
	print("[ADD XP] +100 → level ", GameManager.player_level, "  xp ", GameManager.player_xp,
		" / ", GameManager.xp_to_next(GameManager.player_level))

## DEBUG (Phase 2 test): roll a random Mid-tier affixed weapon into the backpack.
func _on_roll_weapon() -> void:
	var uid := InventoryManager.generate_weapon(InventoryManager.WEAPON_ROLL_TIER)
	if uid == -1:
		print("[ROLL WEAPON] backpack full — no room")
	else:
		print("[ROLL WEAPON] dropped: ", InventoryManager.item_display_name(uid))

## DEBUG (armor test): roll a random Mid-tier hull into the backpack so armor/HP can be verified.
func _on_roll_hull() -> void:
	var uid := InventoryManager.generate_hull(InventoryManager.WEAPON_ROLL_TIER)
	if uid == -1:
		print("[ROLL HULL] backpack full — no room")
	else:
		print("[ROLL HULL] dropped: ", InventoryManager.item_display_name(uid),
			"  armor=", InventoryManager.hull_armor(uid), " bonus_hp=", InventoryManager.hull_bonus_hp(uid))

func _on_reset_hp() -> void:
	GameManager.ship_hp = GameManager.ship_max_hp
	GameManager.ship_hp_changed.emit(GameManager.ship_max_hp)

func _on_kill_boss() -> void:
	# Set boss HP to 1 for testing phase transitions
	if GameManager.boss_max_hp > 0 and GameManager.boss_hp > 0:
		GameManager.boss_hp = 1
		GameManager.boss_hp_changed.emit(GameManager.boss_hp)
	else:
		for bf in get_tree().get_nodes_in_group("boss_fight"):
			if bf.has_method("kill_boss"):
				bf.call("kill_boss")

func _make_btn(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = bc
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.content_margin_top = 4; s.content_margin_bottom = 4
		return s
	btn.add_theme_stylebox_override("normal",  mk.call(Color(0.09, 0.12, 0.18, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	btn.add_theme_stylebox_override("hover",   mk.call(Color(0.14, 0.18, 0.28, 0.9), Color(0.50, 0.65, 0.90, 0.9)))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.06, 0.08, 0.13, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	btn.add_theme_stylebox_override("focus",   mk.call(Color(0.09, 0.12, 0.18, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	return btn

# ── Settings overlay ──────────────────────────────────────────────────────────

func _build_settings_panel() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer        = 100
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_layer.visible      = false

	_overlay_rect = ColorRect.new()
	_overlay_rect.color        = Color(0.0, 0.0, 0.0, 0.60)
	_overlay_rect.anchor_right  = 1.0
	_overlay_rect.anchor_bottom = 1.0
	_overlay_rect.mouse_filter  = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_overlay_rect)

	# ── Settings panel ─────────────────────────────────────────────────────────
	_settings_panel = Panel.new()
	_settings_panel.z_index = 1
	_settings_panel.size    = Vector2(330, 660)
	_settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var ps := StyleBoxFlat.new()
	ps.bg_color            = Color(0.06, 0.08, 0.14, 0.97)
	ps.border_width_left   = 2; ps.border_width_right  = 2
	ps.border_width_top    = 2; ps.border_width_bottom = 2
	ps.border_color        = Color(0.40, 0.55, 0.80, 0.90)
	ps.corner_radius_top_left     = 8; ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8; ps.corner_radius_bottom_right = 8
	_settings_panel.add_theme_stylebox_override("panel", ps)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12; vbox.offset_right  = -12
	vbox.offset_top  = 12; vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(vbox)

	var title := _make_lbl("SETTINGS", 14, Color(0.82, 0.92, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# ── Resolution ──
	vbox.add_child(_make_lbl("Resolution", 11, Color(0.60, 0.75, 0.90)))
	var res_hbox := HBoxContainer.new()
	res_hbox.add_theme_constant_override("separation", 4)
	_res_btns.clear()
	for r in RESOLUTIONS:
		var btn := Button.new()
		btn.text = r["label"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.pressed.connect(_on_res_selected.bind(r["size"]))
		_res_btns.append(btn)
		res_hbox.add_child(btn)
	vbox.add_child(res_hbox)
	vbox.add_child(HSeparator.new())

	# ── Volume ──
	vbox.add_child(_make_lbl("Volume", 11, Color(0.60, 0.75, 0.90)))
	_music_slider = _add_slider_row(vbox, "Music", _init_music_vol)
	_sfx_slider   = _add_slider_row(vbox, "SFX",   _init_sfx_vol)

	_music_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_music_volume(v)
		_save_settings())
	_sfx_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_sfx_volume(v)
		_save_settings())

	vbox.add_child(HSeparator.new())

	# ── Weapon SFX ──
	vbox.add_child(_make_lbl("Weapon SFX", 11, Color(0.60, 0.75, 0.90)))
	var weapon_sfx_defs := [
		["Gun",       "gun"],
		["Turret",    "turret"],
		["Railgun",   "railgun"],
		["Canon",     "canon"],
		["Lightning", "lightning"],
	]
	for wd in weapon_sfx_defs:
		var key: String = wd[1]
		var init_val: float = float(AudioManager.weapon_sfx_vols.get(key, 1.0))
		var sl := _add_slider_row(vbox, wd[0], init_val)
		sl.value_changed.connect(func(v: float) -> void:
			AudioManager.weapon_sfx_vols[key] = v
			_save_settings())

	vbox.add_child(HSeparator.new())

	# ── Materials ──
	vbox.add_child(_make_lbl("Materials", 11, Color(0.60, 0.75, 0.90)))
	var mat_defs := [
		["Metal",     "metal"],
		["Non-Metal", "nonmetal"],
		["Liquid",    "liquid"],
		["Organic",   "organic"],
	]
	for md in mat_defs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := _make_lbl(md[0], 10, Color(0.75, 0.82, 0.95))
		lbl.custom_minimum_size = Vector2(72, 0)
		lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 999999999
		spin.step      = 1
		spin.value     = MaterialManager.get(md[1])
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.process_mode          = Node.PROCESS_MODE_ALWAYS
		spin.get_line_edit().process_mode = Node.PROCESS_MODE_ALWAYS
		row.add_child(lbl)
		row.add_child(spin)
		vbox.add_child(row)
		_mat_spins[md[1]] = spin
	var apply_btn := _make_btn("APPLY MATERIALS")
	apply_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	apply_btn.pressed.connect(_apply_materials)
	vbox.add_child(apply_btn)

	vbox.add_child(HSeparator.new())

	# ── Resets ──
	vbox.add_child(_make_lbl("Reset", 11, Color(0.90, 0.55, 0.55)))

	var reset_purchases_btn := _make_btn("RESET PURCHASES")
	reset_purchases_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	reset_purchases_btn.pressed.connect(func() -> void: _prompt_confirm("purchases"))
	vbox.add_child(reset_purchases_btn)

	var reset_game_btn := _make_btn("RESET GAME")
	reset_game_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	reset_game_btn.pressed.connect(func() -> void: _prompt_confirm("game"))
	vbox.add_child(reset_game_btn)

	vbox.add_child(HSeparator.new())
	var close_btn := _make_btn("CLOSE")
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.pressed.connect(_close_settings)
	vbox.add_child(close_btn)

	_overlay_layer.add_child(_settings_panel)

	# ── Confirm dialog (hidden by default) ─────────────────────────────────────
	_confirm_panel = Panel.new()
	_confirm_panel.z_index = 2
	_confirm_panel.size    = Vector2(280, 160)
	_confirm_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_panel.visible = false

	var cp_style := StyleBoxFlat.new()
	cp_style.bg_color            = Color(0.08, 0.05, 0.05, 0.98)
	cp_style.border_width_left   = 2; cp_style.border_width_right  = 2
	cp_style.border_width_top    = 2; cp_style.border_width_bottom = 2
	cp_style.border_color        = Color(0.80, 0.30, 0.30, 0.90)
	cp_style.corner_radius_top_left     = 8; cp_style.corner_radius_top_right    = 8
	cp_style.corner_radius_bottom_left  = 8; cp_style.corner_radius_bottom_right = 8
	_confirm_panel.add_theme_stylebox_override("panel", cp_style)

	var cv := VBoxContainer.new()
	cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cv.offset_left = 14; cv.offset_right  = -14
	cv.offset_top  = 14; cv.offset_bottom = -14
	cv.add_theme_constant_override("separation", 10)
	_confirm_panel.add_child(cv)

	var warn_icon := _make_lbl("⚠  ARE YOU SURE?", 13, Color(1.0, 0.65, 0.20))
	warn_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(warn_icon)

	_confirm_msg_lbl = _make_lbl("", 10, Color(0.88, 0.72, 0.72))
	_confirm_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	cv.add_child(_confirm_msg_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	cv.add_child(btn_row)

	var cancel_btn := _make_btn("CANCEL")
	cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	cancel_btn.pressed.connect(_hide_confirm)
	btn_row.add_child(cancel_btn)

	var confirm_btn := _make_btn("CONFIRM")
	confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	# Tint confirm button red
	var ck := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = bc
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.content_margin_top = 4; s.content_margin_bottom = 4
		return s
	confirm_btn.add_theme_stylebox_override("normal",  ck.call(Color(0.30, 0.06, 0.06, 0.9), Color(0.65, 0.20, 0.20, 0.8)))
	confirm_btn.add_theme_stylebox_override("hover",   ck.call(Color(0.45, 0.10, 0.10, 0.9), Color(0.85, 0.30, 0.30, 0.9)))
	confirm_btn.add_theme_stylebox_override("pressed", ck.call(Color(0.20, 0.04, 0.04, 0.9), Color(0.65, 0.20, 0.20, 0.8)))
	confirm_btn.add_theme_stylebox_override("focus",   ck.call(Color(0.30, 0.06, 0.06, 0.9), Color(0.65, 0.20, 0.20, 0.8)))
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	confirm_btn.pressed.connect(_execute_confirm)
	btn_row.add_child(confirm_btn)

	_overlay_layer.add_child(_confirm_panel)

	get_tree().root.add_child(_overlay_layer)
	_center_settings()
	_center_confirm()
	_update_res_btns()

func _anchor_bottom_right() -> void:
	size = Vector2(size.x, get_combined_minimum_size().y + 8.0)
	position = Vector2(1240.0, 278.0)

func _make_lbl(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

func _add_slider_row(parent: VBoxContainer, label_text: String, initial: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := _make_lbl(label_text, 10, Color(0.75, 0.82, 0.95))
	lbl.custom_minimum_size = Vector2(88, 0)
	lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.02
	slider.value     = clampf(initial, 0.0, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.process_mode          = Node.PROCESS_MODE_ALWAYS

	var pct := _make_lbl("%d%%" % int(initial * 100.0), 10, Color(0.60, 0.70, 0.88))
	pct.custom_minimum_size    = Vector2(34, 0)
	pct.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v * 100.0))

	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(pct)
	parent.add_child(row)
	return slider

# ── Confirm dialog ────────────────────────────────────────────────────────────

func _prompt_confirm(action: String) -> void:
	_pending_action = action
	match action:
		"purchases":
			_confirm_msg_lbl.text = "This will reset all WEAPONRY and DEFENSE\nupgrades and POWER CORE items to zero.\nThis cannot be undone."
		"game":
			_confirm_msg_lbl.text = "This will reset all Materials, Upgrades,\nand Equipment to zero.\nThis cannot be undone."
	_confirm_panel.visible = true
	_settings_panel.visible = false

func _hide_confirm() -> void:
	_confirm_panel.visible = false
	_settings_panel.visible = true
	_pending_action = ""

func _execute_confirm() -> void:
	match _pending_action:
		"purchases":
			UpgradeManager.reset_all()
			WeaponManager.reset_all()
			DefenseManager.reset_all()
		"game":
			GameManager.reset_stats()
			UpgradeManager.reset_all()
	_pending_action = ""
	_confirm_panel.visible = false
	_close_settings()

# ── Open / Close ──────────────────────────────────────────────────────────────

func _toggle_mute() -> void:
	if _pre_mute_music < 0.0:
		_pre_mute_music = AudioManager.music_volume
		AudioManager.set_music_volume(0.0)
		_mute_btn.text = "UNMUTE"
	else:
		AudioManager.set_music_volume(_pre_mute_music)
		if is_instance_valid(_music_slider):
			_music_slider.value = _pre_mute_music
		_pre_mute_music = -1.0
		_mute_btn.text = "MUTE"

func _toggle_settings() -> void:
	if not is_instance_valid(_overlay_layer):
		return
	if _overlay_layer.visible:
		_close_settings()
	else:
		_open_settings()

func _apply_materials() -> void:
	for key in _mat_spins:
		MaterialManager.set(key, int((_mat_spins[key] as SpinBox).value))
	MaterialManager.materials_changed.emit()
	MaterialManager.save_game()

func _open_settings() -> void:
	_update_res_btns()
	_center_settings()
	_center_confirm()
	# Sync spinbox values với current materials
	for key in _mat_spins:
		(_mat_spins[key] as SpinBox).value = MaterialManager.get(key)
	_settings_panel.visible = true
	_confirm_panel.visible  = false
	_overlay_layer.visible  = true

func _close_settings() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.visible = false
	_pending_action = ""

func _center_settings() -> void:
	if not is_instance_valid(_settings_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	_settings_panel.position = ((vp - _settings_panel.size) * 0.5).floor()

func _center_confirm() -> void:
	if not is_instance_valid(_confirm_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	_confirm_panel.position = ((vp - _confirm_panel.size) * 0.5).floor()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_instance_valid(_overlay_layer) and _overlay_layer.visible:
			if _confirm_panel.visible:
				_hide_confirm()
			else:
				_close_settings()
			get_viewport().set_input_as_handled()

# ── Resolution ────────────────────────────────────────────────────────────────

func _on_res_selected(res: Vector2i) -> void:
	DisplayServer.window_set_size(res)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - res) / 2)
	_update_res_btns()
	_save_settings()

func _update_res_btns() -> void:
	if _res_btns.is_empty():
		return
	var cur := DisplayServer.window_get_size()
	for i in _res_btns.size():
		var target: Vector2i = RESOLUTIONS[i]["size"]
		_res_btns[i].add_theme_color_override("font_color",
			Color(0.35, 0.88, 1.0) if cur == target else Color(0.72, 0.78, 0.90))

# ── Quit ──────────────────────────────────────────────────────────────────────

func _on_quit() -> void:
	get_tree().paused = false
	GameManager.save_game()
	UpgradeManager.save_game()
	get_tree().quit()

# ── Persistence ───────────────────────────────────────────────────────────────

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	var res := DisplayServer.window_get_size()
	cfg.set_value("display", "width",  res.x)
	cfg.set_value("display", "height", res.y)
	cfg.set_value("audio", "music_vol", AudioManager.music_volume)
	cfg.set_value("audio", "sfx_vol",   AudioManager.sfx_volume)
	for key: String in AudioManager.weapon_sfx_vols:
		cfg.set_value("weapon_sfx", key, float(AudioManager.weapon_sfx_vols[key]))
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var w: int = cfg.get_value("display", "width",  1280)
	var h: int = cfg.get_value("display", "height",  720)
	DisplayServer.window_set_size(Vector2i(w, h))
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - Vector2i(w, h)) / 2)
	_init_music_vol = cfg.get_value("audio", "music_vol", 1.0)
	_init_sfx_vol   = cfg.get_value("audio", "sfx_vol",   1.0)
	AudioManager.set_music_volume(_init_music_vol)
	AudioManager.set_sfx_volume(_init_sfx_vol)
	for key: String in AudioManager.weapon_sfx_vols:
		AudioManager.weapon_sfx_vols[key] = cfg.get_value("weapon_sfx", key, 1.0)
