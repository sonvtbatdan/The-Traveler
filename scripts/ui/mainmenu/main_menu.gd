extends Control
## Main Menu — the game's entry screen and the return target when the player presses
## Quit inside the Arena.
##
## The menu's visuals (background, space, Logo) and the four buttons (Resume / Setting /
## Codex / Quit) ARE the EditableObjectNodes owned by the F4 object edit mode: static
## images in gameplay, draggable/resizable once F4 is pressed (the editor just lays a
## dim overlay over them — the objects stay in place so you can resize/move them live).
## Positions/sizes/Z persist to res://mainmenu_layout.cfg.
##
##   Resume  → load the Hub/Dock screen (2026-08-02: was a direct load straight into the Arena — now stops
##             at the Hub first, same "RETURN TO DOCK" screen the Arena's own RUN OVER button uses, see
##             hub_screen.gd; its own "Launch" room is what actually starts a run from there)
##   Setting → "Coming soon" toast (panel not built yet)
##   Codex   → "Coming soon" toast (panel not built yet)
##   Quit    → persist all managers, then exit the application
##
## Press F4 to open the object edit mode.

const HUB_SCENE       := "res://scenes/hub.tscn"
const EditScript      := preload("res://scripts/ui/mainmenu/main_menu_edit_mode.gd")
const SpawnerScript   := preload("res://scripts/ui/mainmenu/menu_enemy_spawner.gd")
const SettingsScript  := preload("res://scripts/ui/settings/settings_panel.gd")

# UI sounds (played via AudioManager so they survive the scene change on Resume).
const SFX_HOVER   := preload("res://assets/audio/sfx/uiclick.wav")
const SFX_RESUME  := preload("res://assets/audio/sfx/start.mp3")
const SFX_SETTING := preload("res://assets/audio/sfx/selectconfirm2.wav")
const SFX_CODEX   := preload("res://assets/audio/sfx/uialert.wav")
const SFX_QUIT    := preload("res://assets/audio/sfx/gameover.wav")

var _edit: Node   = null
var _toast: Label = null
var _settings: Node = null
var _hovered: String = ""   # basename of the button currently hovered ("" = none)

func _ready() -> void:
	# TEMP DIAGNOSTIC — timing breakdown for the "menu sometimes freezes on startup" report.
	# Safe to delete once the cause is confirmed/fixed.
	var _t0 := Time.get_ticks_usec()
	process_mode = Node.PROCESS_MODE_ALWAYS   # so F4 still toggles while the editor pauses the tree
	set_anchors_preset(Control.PRESET_FULL_RECT)
	SettingsScript.apply_saved()              # apply saved SFX volume + window mode at startup
	print("[menu-startup] apply_saved: %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0)); _t0 = Time.get_ticks_usec()
	_settings = SettingsScript.new()
	add_child(_settings)
	print("[menu-startup] settings panel build: %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0)); _t0 = Time.get_ticks_usec()
	_build_toast()
	_setup_edit_mode()
	print("[menu-startup] TOTAL _ready: %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0))

func _setup_edit_mode() -> void:
	var _t0 := Time.get_ticks_usec()
	# Full-screen Control as the ObjectsContainer the editor places sprites into
	# (same role as edit_mode's ObjectsContainer in main.gd / arena.gd). These placed
	# objects are also the live menu visuals.
	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(oc)
	_edit = EditScript.new()
	add_child(_edit)
	print("[menu-startup]   edit_mode _ready (UI build): %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0)); _t0 = Time.get_ticks_usec()
	_edit.setup(oc)
	print("[menu-startup]   edit_mode.setup (layer texture loads): %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0)); _t0 = Time.get_ticks_usec()

	# Decorative flying-enemy backdrop (real arena AI; shooters fire; no bosses). Added into the
	# same object container so it sits over the starfield but under the Logo / buttons.
	var spawner := SpawnerScript.new()
	spawner.setup(oc)
	add_child(spawner)
	print("[menu-startup]   spawner add_child (prespawn): %.1fms" % ((Time.get_ticks_usec() - _t0) / 1000.0))

# ── Button input (manual hit-test — see main_menu_edit_mode.gd) ────────────────────

func _input(event: InputEvent) -> void:
	if _edit == null or _edit.is_open() or (_settings != null and _settings.is_open()):
		return
	if event is InputEventMouseMotion:
		var hb: String = _edit.live_button_at((event as InputEventMouseMotion).position)
		_set_hover(hb)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var base: String = _edit.live_button_at(mb.position)
			if base != "":
				get_viewport().set_input_as_handled()
				_on_menu_button(base)

func _set_hover(base: String) -> void:
	if base == _hovered:
		return
	if _hovered != "":
		_edit.set_button_hover(_hovered, false)
	_hovered = base
	if base != "":
		_edit.set_button_hover(base, true)
		AudioManager.play_sfx(SFX_HOVER)

# ── Button actions ───────────────────────────────────────────────────────────────

func _on_menu_button(base: String) -> void:
	match base:
		"resume":
			AudioManager.play_sfx(SFX_RESUME)   # persists into the hub scene
			get_tree().change_scene_to_file(HUB_SCENE)
		"setting":
			AudioManager.play_sfx(SFX_SETTING)
			if _settings != null:
				_settings.open()
		"codex":
			AudioManager.play_sfx(SFX_CODEX)
			_show_toast("Coming soon")
		"quit":
			_save_and_quit()

func _save_and_quit() -> void:
	# Play the game-over sting, let it ring out, persist all managers, then exit.
	AudioManager.play_sfx(SFX_QUIT)
	await get_tree().create_timer(minf(SFX_QUIT.get_length(), 4.0)).timeout
	for mgr in [GameManager, InventoryManager, MetaManager]:
		if mgr != null and mgr.has_method("save_game"):
			mgr.save_game()
	get_tree().quit()

# ── F4 edit mode ─────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_edit_mode"):
		if _settings != null and _settings.is_open():
			return
		if _edit != null:
			_edit.toggle()
		get_viewport().set_input_as_handled()

# ── Toast ────────────────────────────────────────────────────────────────────────

func _build_toast() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	_toast = Label.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never intercept clicks (even at alpha 0)
	_toast.modulate.a = 0.0
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left   = -200.0
	_toast.offset_right  = 200.0
	_toast.offset_top    = -120.0
	_toast.offset_bottom = -80.0
	cl.add_child(_toast)

func _show_toast(message: String) -> void:
	if _toast == null:
		return
	_toast.text = message
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
