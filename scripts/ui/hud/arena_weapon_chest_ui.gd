extends CanvasLayer
## Start-of-run weapon chest (arena). At run start the player picks ONE weapon from three random choices
## drawn from arena_weapons.CHEST_POOL (the four "F12" weapons). Pause-safe (layer 109 + PROCESS_MODE_ALWAYS),
## styled to echo the level-up cards. Picking a card calls arena_weapons.acquire_weapon(kind), unpauses, closes.
## Self-contained: arena.gd adds it and calls show_chest() once, deferred, after the run resets.

const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")

const FONT_TITLE := "res://assets/fonts/Good Old DOS.ttf"
const FONT_BODY  := "res://assets/fonts/Gameplay.ttf"
const CARD_SIZE  := Vector2(180, 220)

const SFX_SHOW   := preload("res://assets/audio/sfx/uialert.wav")
const SFX_HOVER  := preload("res://assets/audio/sfx/uiclick.wav")
const SFX_PICK   := preload("res://assets/audio/sfx/selectconfirm3.wav")

var _root: Control = null
var _cards_row: HBoxContainer = null
var _sfx: AudioStreamPlayer = null

func _ready() -> void:
	layer = 109                                   # above HUD, below settings (100 is the settings overlay's; 109 sits over gameplay HUD)
	process_mode = Node.PROCESS_MODE_ALWAYS       # work while the tree is paused
	add_to_group("arena_weapon_chest")
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_build_ui()
	_root.hide()

# ── Public ────────────────────────────────────────────────────────────────────────
## Roll three distinct weapons and present the chest (pauses the game).
func show_chest() -> void:
	var pool: Array = (ArenaWeapons.CHEST_POOL as Array).duplicate()
	pool.shuffle()
	var picks: Array = pool.slice(0, mini(3, pool.size()))
	for c in _cards_row.get_children():
		c.free()
	for kind: String in picks:
		_cards_row.add_child(_make_card(kind))
	_root.show()
	get_tree().paused = true
	_play(SFX_SHOW)

# ── Cards ─────────────────────────────────────────────────────────────────────────
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
	hint.text = "Click to equip"
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
	get_tree().paused = false

# ── Scaffold ────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to the scene below
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

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
