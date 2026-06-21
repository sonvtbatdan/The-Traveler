extends CanvasLayer
## Bottom-right HUD buttons: Pause, Codex, Setting, Devon (toggle dev mode + pause + edit buttons), Quit.
## When Devon is active: game is paused and Boss_edit / Creep_edit buttons are revealed.

const BTN_SIZE        := 60.0
const BTN_SEP         :=  6.0
const MARGIN          :=  8.0
const SIMPLIFIED_X    := -2.0    # MARGIN(8) − 10px left
const SIMPLIFIED_Y    := 83.0   # HP bar bottom(74) + gap(4) + 5

const ArenaEnemy := preload("res://scripts/gameplay/arena_enemy.gd")

var _dev_mode:    bool  = false
var _game_paused: bool  = false   # tracks the pause state managed by this HUD

# Button references
var _devon_btn:      TextureButton = null
var _pause_btn:      TextureButton = null
var _boss_edit_btn:  TextureButton = null
var _creep_edit_btn: TextureButton = null
var _simplified_btn: TextureButton = null
var _vb:             VBoxContainer = null

# Textures
var _tex_devon:         Texture2D = null
var _tex_devoff:        Texture2D = null
var _tex_pause:         Texture2D = null
var _tex_boss_edit:     Texture2D = null
var _tex_creep_edit:    Texture2D = null
var _tex_simplified:    Texture2D = null
var _tex_simplifiedon:  Texture2D = null

# Total height without dev-edit buttons (for VBox repositioning)
var _base_total_h: float = 0.0

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tex_devon         = _load_img("res://assets/hud/Devon.png")
	_tex_devoff        = _load_img("res://assets/hud/devoff.png")
	_tex_pause         = _load_img("res://assets/hud/Pause.png")
	_tex_boss_edit     = _load_img("res://assets/hud/Boss_edit.png")
	_tex_creep_edit    = _load_img("res://assets/hud/Creep_edit.png")
	_tex_simplified    = _load_img("res://assets/hud/Simplified.png")
	_tex_simplifiedon  = _load_img("res://assets/hud/Simplifiedon.png")
	_build_ui()

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

	# VBox: Pause + Codex + Setting + Devon + Quit (5 buttons, 4 gaps) — no dev buttons here
	_base_total_h = pause_h + codex_h + BTN_SIZE * 3.0 + BTN_SEP * 4.0

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

	# Dev buttons at top-left (below HP bar): Simplified → Boss_edit → Creep_edit
	# Only visible when dev mode is on; spacing = BTN_SEP (same as right column)
	var s_h := _btn_h(_tex_simplified)
	_simplified_btn = _make_btn(_tex_simplified, s_h)
	_simplified_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y)
	_simplified_btn.visible = false
	_simplified_btn.pressed.connect(_on_simplified)
	root.add_child(_simplified_btn)

	_boss_edit_btn = _make_btn(_tex_boss_edit, boss_edit_h)
	_boss_edit_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y + s_h + BTN_SEP)
	_boss_edit_btn.visible = false
	_boss_edit_btn.pressed.connect(_on_boss_edit)
	root.add_child(_boss_edit_btn)

	_creep_edit_btn = _make_btn(_tex_creep_edit, creep_edit_h)
	_creep_edit_btn.position = Vector2(SIMPLIFIED_X, SIMPLIFIED_Y + s_h + BTN_SEP + boss_edit_h + BTN_SEP)
	_creep_edit_btn.visible = false
	_creep_edit_btn.pressed.connect(_on_creep_edit)
	root.add_child(_creep_edit_btn)

func _make_btn(tex: Texture2D, h: float) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(BTN_SIZE, h)
	return btn

# ── Button handlers ────────────────────────────────────────────────────────────

func _on_pause() -> void:
	_game_paused = !_game_paused
	get_tree().paused = _game_paused

func _on_codex() -> void:
	pass   # placeholder

func _on_setting() -> void:
	pass   # placeholder

func _on_devon() -> void:
	_dev_mode = !_dev_mode

	# Toggle dev debug UI (arena_debug_spawn)
	var ds := get_tree().get_first_node_in_group("arena_debug_spawn")
	if ds != null and ds.has_method("set_dev_ui_visible"):
		ds.set_dev_ui_visible(_dev_mode)

	# Devon activates: pause game + show edit buttons
	if _dev_mode:
		_game_paused = true
		get_tree().paused = true
	else:
		_game_paused = false
		get_tree().paused = false

	# Show / hide dev buttons at top-left
	_simplified_btn.visible = _dev_mode
	_boss_edit_btn.visible  = _dev_mode
	_creep_edit_btn.visible = _dev_mode

	# Update Devon button texture
	_devon_btn.texture_normal = _tex_devon if _dev_mode else _tex_devoff

func _on_boss_edit() -> void:
	var bem := get_tree().get_first_node_in_group("boss_edit")
	if bem != null and bem.has_method("toggle"):
		bem.toggle()

func _on_creep_edit() -> void:
	var cem := get_tree().get_first_node_in_group("creep_edit")
	if cem != null and cem.has_method("toggle"):
		cem.toggle()

func _on_simplified() -> void:
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
	get_tree().quit()
