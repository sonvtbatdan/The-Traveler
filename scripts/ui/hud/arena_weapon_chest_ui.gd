extends CanvasLayer
## Start-of-run weapon chest (arena). At run start the player picks ONE weapon from three random choices
## drawn from arena_weapons.CHEST_POOL (the four "F12" weapons). Pause-safe (layer 109 + PROCESS_MODE_ALWAYS),
## styled to echo the level-up cards. Picking a card calls arena_weapons.acquire_weapon(kind), unpauses, closes.
## Self-contained: arena.gd adds it and calls show_chest() once, deferred, after the run resets.
##
## Authored "choose_weapon" board (optional visual chrome, see ChooseWeaponBinder): once 3 "screen" sprites
## are authored in the board editor, each choice's weapon icon is centred on a screen sprite (name below it),
## replacing the built-in centred row of cards — same "falls back until authored" pattern as the Level Up
## board. Every screen carries a green CRT scan-line VFX (same shader pair as the Level Up board); hovering
## turns it red. The VFX draws just under the authored "background" bezel layer (not relative to each screen's
## own z, which used to let it inconsistently poke above the bezel on whichever screen out-ranked it) — see
## ChooseWeaponBinder.background_z(). The board's own art (bezel/background, the "CHOOSE YOUR WEAPON" text)
## renders itself once the board is live; no role lookup needed for those.

const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")
const BoardEditScript := preload("res://scripts/ui/boss_edit/hud_edit_mode.gd")

const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/mandalore/mandalore.ttf"
const CARD_SIZE  := Vector2(180, 220)

const SFX_SHOW   := preload("res://assets/audio/sfx/uialert.wav")
const SFX_HOVER  := preload("res://assets/audio/sfx/uiclick.wav")
const SFX_PICK   := preload("res://assets/audio/sfx/selectconfirm3.wav")

# Board-mode slot rendering (icon centred on a "screen" sprite, name below it; green idle scan-line VFX, red on hover).
const SCAN_SHADER := "res://assets/shaders/selection_scan.gdshader"
const SWEEP_SHADER := "res://assets/shaders/selection_sweep.gdshader"
const SCAN_COLOR_IDLE := Color(0.35, 1.0, 0.45, 0.5)    # green — same idle colour as the Level Up board
const SCAN_COLOR_HOVER := Color(1.0, 0.30, 0.30, 1.0)   # red — same "selected" colour as the Level Up board
const SLOT_ICON_FIT := 0.7    # weapon icon contain-fits within this fraction of the screen sprite's box
const SLOT_NAME_GAP := -24.0  # px between the screen sprite's bottom edge and the name label (negative = up)
const SLOT_NAME_HEIGHT := 26.0
var _scan_mats: Dictionary = {}   # Color -> shared ShaderMaterial (idle/hover, same colour every slot)

var _root: Control = null
var _dim: ColorRect = null
var _center: CenterContainer = null
var _cards_row: HBoxContainer = null
var _sfx: AudioStreamPlayer = null
var _prev_paused: bool = false   # tree's paused state from just before we showed — restored on pick instead of a blind unpause

# Authored board host (runtime-only board_edit_mode), layered above _root's dim so its chrome is visible.
var _board_layer: CanvasLayer = null
var _board_host = null
var _rt_board: Array = []   # runtime nodes rendered onto the board container (cleared each show_chest())

func _ready() -> void:
	layer = 109                                   # above HUD, below settings (100 is the settings overlay's; 109 sits over gameplay HUD)
	process_mode = Node.PROCESS_MODE_ALWAYS       # work while the tree is paused
	add_to_group("arena_weapon_chest")
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_build_ui()
	_build_board_host()
	_root.hide()

# ── Public ────────────────────────────────────────────────────────────────────────
## Roll three distinct weapons and present the chest (pauses the game). Excludes kinds already acquired
## (e.g. seeded from the Hub Loadout by arena.gd._open_start_chest before this is called) so a partial
## loadout only rolls for the slots still empty, and a pool with nothing left to offer shows nothing.
func show_chest() -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	var acquired: Array = weapons.call("acquired_weapons") if weapons != null and weapons.has_method("acquired_weapons") else []
	var pool: Array = (ArenaWeapons.CHEST_POOL as Array).filter(func(k: String) -> bool: return not (k in acquired))
	if pool.is_empty():
		return
	pool.shuffle()
	var picks: Array = pool.slice(0, mini(3, pool.size()))
	for c in _cards_row.get_children():
		c.free()
	_board_clear()
	var authored := _board_authored()
	_board_layer.visible = authored
	_center.visible = not authored
	_dim.color.a = 0.0 if authored else 0.72
	if authored:
		_board_render(picks)
	else:
		for kind: String in picks:
			_cards_row.add_child(_make_card(kind))
	_root.show()
	# Capture/restore instead of a blind force (2026-08-02: forcing false on pick could clobber an outer
	# pause some other panel/HUD button set — see arena_hud_buttons.gd's _on_pause() for the "needs 2 clicks"
	# class of bug this caused).
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_play(SFX_SHOW)

# ── Authored board (optional visual layout) ─────────────────────────────────────────────────
## Spawn a runtime-only board surface (CanvasLayer 110, above _root's dim/cards at 109) that renders the
## authored "choose_weapon" board chrome. Hidden until the chest shows. ChooseWeaponBinder supplies the screens.
func _build_board_host() -> void:
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 110
	_board_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_board_layer.visible = false
	add_child(_board_layer)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.add_child(oc)
	_board_host = BoardEditScript.new()
	add_child(_board_host)
	_board_host.setup(oc, "choose_weapon", false)   # runtime-only host (no authoring UI)

## The host's ChooseWeaponBinder (exposes has_layout/screen_nodes), or null.
func _board_binder():
	if _board_host != null and is_instance_valid(_board_host):
		return _board_host.get_binder()
	return null

func _board_authored() -> bool:
	var b = _board_binder()
	return b != null and b.has_method("has_layout") and bool(b.call("has_layout"))

func _board_add(n: Control) -> void:
	var b = _board_binder()
	if b == null:
		return
	var c = b.call("container")
	if c != null and is_instance_valid(c):
		c.add_child(n)
		_rt_board.append(n)

func _board_clear() -> void:
	for n in _rt_board:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_rt_board.clear()

## Each picked weapon's icon centred on its "screen" sprite (name label below it). The board's own bezel/
## background art and "CHOOSE YOUR WEAPON" text already render themselves (ordinary authored layers) — this
## only adds the dynamic per-run content.
func _board_render(picks: Array) -> void:
	var b = _board_binder()
	if b == null:
		return
	var screens: Array = b.call("screen_nodes")
	var bg_z := int(b.call("background_z"))
	for i in mini(picks.size(), screens.size()):
		var scr := screens[i] as Control
		if scr == null:
			continue
		_board_make_slot(scr, String(picks[i]), bg_z)

## Icon (contain-fit, centred on the screen sprite) + name below + hover/click, all anchored to `scr`'s
## current rect (so it tracks whatever the artist authored). Green idle scan-line VFX on the screen sprite,
## swapping red while hovered. `bg_z` = the authored "background" bezel's z_index (-1 if not authored) — the
## VFX draws just under it (a fixed reference, not each screen's own z, which varies per slot and used to let
## the VFX inconsistently poke above the bezel on whichever screen happened to out-rank it).
func _board_make_slot(scr: Control, kind: String, bg_z: int) -> void:
	var rect := Rect2(scr.position, scr.size)
	var center := rect.position + rect.size * 0.5
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
	var icon_path := String(info.get("icon", ""))
	var tex: Texture2D = (load(icon_path) as Texture2D) if icon_path != "" else InventoryManager.get_icon(String(info.get("def_id", "")))

	# Scan-line VFX, sized to the screen sprite, drawn just under the background bezel (or just above the
	# screen's own z if no bezel is authored). Green idle, swaps to red on hover (see below).
	var vfx_z := (bg_z - 1) if bg_z > -1 else (scr.z_index + 1)
	var vfx := _board_make_scan_vfx(rect, vfx_z)
	var scan: ColorRect = vfx["scan"]
	var sweep: ColorRect = vfx["sweep"]
	_board_add(vfx["root"])

	# Hover/click root: sized to the screen sprite so clicking the "monitor" picks that weapon.
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.pivot_offset = rect.size * 0.5
	root.z_index = scr.z_index + 2
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon: Control
	if tex != null:
		var box := _contain_box(tex.get_size(), rect.size.x * SLOT_ICON_FIT, rect.size.y * SLOT_ICON_FIT)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = box
		tr.position = (rect.size - box) * 0.5
		icon = tr
	else:
		var sw := ColorRect.new()
		sw.color = Color.GRAY
		sw.size = rect.size * SLOT_ICON_FIT
		sw.position = (rect.size - sw.size) * 0.5
		icon = sw
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	_board_add(root)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.mouse_entered.connect(func() -> void:
		root.scale = Vector2(1.05, 1.05)
		icon.modulate = Color(1.35, 1.35, 1.35)
		scan.material = _scan_material(SCAN_COLOR_HOVER)
		(sweep.material as ShaderMaterial).set_shader_parameter("sweep_color", SCAN_COLOR_HOVER)
		_play(SFX_HOVER))
	btn.mouse_exited.connect(func() -> void:
		root.scale = Vector2.ONE
		icon.modulate = Color.WHITE
		scan.material = _scan_material(SCAN_COLOR_IDLE)
		(sweep.material as ShaderMaterial).set_shader_parameter("sweep_color", SCAN_COLOR_IDLE))
	btn.pressed.connect(_pick.bind(kind))
	root.add_child(btn)

	# Name label below the screen sprite, centred on it.
	var name_lbl := Label.new()
	name_lbl.text = String(info.get("label", kind.capitalize()))
	name_lbl.position = Vector2(center.x - rect.size.x * 0.5, rect.position.y + rect.size.y + SLOT_NAME_GAP)
	name_lbl.size = Vector2(rect.size.x, SLOT_NAME_HEIGHT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.z_index = scr.z_index + 2
	_font(name_lbl, FONT_TITLE, 18, Color("#E5792A"))
	_board_add(name_lbl)

func _contain_box(native: Vector2, max_w: float, max_h: float) -> Vector2:
	var s := minf(max_w / native.x, max_h / native.y)
	return native * s

## Shared/cached scan+noise+border material per colour (idle green / hover red) — same look across slots,
## no need to desync (unlike the sweep, which is per-instance for its randomised speed/phase).
func _scan_material(color: Color) -> ShaderMaterial:
	if not _scan_mats.has(color):
		var m := ShaderMaterial.new()
		m.shader = load(SCAN_SHADER) as Shader
		m.set_shader_parameter("scan_color", color)
		_scan_mats[color] = m
	return _scan_mats[color]

## Per-instance sweep material — randomised speed/phase so slots never sweep in lockstep (matches Level Up).
## Its colour is mutated in place on hover/exit (see _board_make_slot) so the random speed/phase persist.
func _sweep_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SWEEP_SHADER) as Shader
	m.set_shader_parameter("sweep_color", SCAN_COLOR_IDLE)
	m.set_shader_parameter("sweep_speed", 0.35 * randf_range(0.75, 1.25))
	m.set_shader_parameter("time_offset", randf() * 20.0)
	return m

func _board_make_scan_vfx(rect: Rect2, z: int) -> Dictionary:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = z
	var scan := ColorRect.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.color = Color.WHITE
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.material = _scan_material(SCAN_COLOR_IDLE)
	root.add_child(scan)
	var sweep := ColorRect.new()
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.color = Color.WHITE
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.z_index = 1   # relative to root — draws just above the scan layer
	sweep.material = _sweep_material()
	root.add_child(sweep)
	return {"root": root, "scan": scan, "sweep": sweep}

# ── Cards (built-in fallback row, used until the 3 "screen" sprites are authored) ──────────────────
func _make_card(kind: String) -> Button:
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var shade := 0.12 if state == "normal" else (0.20 if state == "hover" else 0.08)
		sb.bg_color = Color(shade, shade + 0.02, shade + 0.07, 0.97)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.45, 0.6, 0.9, 0.95) if state == "hover" else Color(0.3, 0.42, 0.7, 0.9)
		sb.set_corner_radius_all(10)
		card.add_theme_stylebox_override(state, sb)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 10; vb.offset_top = 14; vb.offset_right = -10; vb.offset_bottom = -14
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path := String(info.get("icon", ""))   # dedicated art (fusions / swarm) wins over the def_id icon
	var tex: Texture2D = (load(icon_path) as Texture2D) if icon_path != "" else InventoryManager.get_icon(String(info.get("def_id", "")))
	if tex != null:
		icon.texture = tex
	vb.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = String(info.get("label", kind.capitalize()))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(name_lbl, FONT_TITLE, 20, Color("#E5792A"))
	vb.add_child(name_lbl)

	var hint := Label.new()
	hint.text = MandaloreText.a("Click to equip")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(hint, FONT_BODY, 12, Color(0.7, 0.75, 0.85))
	vb.add_child(hint)

	card.mouse_entered.connect(func() -> void: _play(SFX_HOVER))
	card.pressed.connect(_pick.bind(kind))
	return card

func _pick(kind: String) -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons != null and weapons.has_method("acquire_weapon"):
		weapons.call("acquire_weapon", kind)
	_play(SFX_PICK)
	_root.hide()
	_board_layer.hide()
	get_tree().paused = _prev_paused

# ── Scaffold ────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to the scene below (kept even in board mode)
	_root.add_child(_dim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	_center.add_child(col)

	var title := Label.new()
	title.text = "CHOOSE YOUR WEAPON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(title, FONT_TITLE, 34, Color("#E5792A"))
	col.add_child(title)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 22)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_cards_row)

func _play(stream: AudioStream) -> void:
	if _sfx != null and stream != null:
		_sfx.stream = stream
		_sfx.play()

func _font(lbl: Label, path: String, size: int, col: Color) -> void:
	var f := load(path) as Font
	if f != null:
		lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
