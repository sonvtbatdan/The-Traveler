extends Panel

## ENEMIES debug panel — 6-tab layout (Animal / Human / Alien / Asteroid / Boss / Other).
## Clicking a thumbnail spawns that enemy or boss. Hovering shows the enemy-info panel
## that sits permanently above the HP-bar cluster.

const GifLoader      := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const CoordGridScript := preload("res://scripts/ui/hud/coord_grid.gd")

const GRID_COLS  := 7
const THUMB_SIZE := Vector2(30, 30)

# Tab order displayed in the 2×3 button grid
const TAB_ORDER := ["Animal", "Human", "Alien", "Asteroid", "Boss", "Other"]

# Each entry: [display_label, spawn_key, icon_path, spawn_group]
#   spawn_group "enemy_manager" → manager.call(spawn_key)
#   spawn_group "boss"          → boss_fight_manager.call("spawn_boss", spawn_key)
const TAB_ENEMIES := {
	"Animal": [
		["Diver",            "spawn_diver",            "res://assets/enemies/kingfisher.png",      "enemy_manager"],
		["Bombing wanderer", "spawn_bombing_wanderer", "res://assets/enemies/bombing.sheet.png",   "enemy_manager"],
		["Swarm",            "spawn_swarm",            "res://assets/enemies/swarm.png",           "enemy_manager"],
		["Bee",              "spawn_bee",              "res://assets/enemies/animalbee.png",       "enemy_manager"],
		["Bug",              "spawn_bug",              "res://assets/enemies/animalbug.png",       "enemy_manager"],
		["Centipede",        "spawn_centipede",        "res://assets/enemies/animalcentipede.png", "enemy_manager"],
		["Dragonfly",        "spawn_dragonfly",        "res://assets/enemies/animaldragonfly.png", "enemy_manager"],
		["Flies",            "spawn_flies",            "res://assets/enemies/animalflies.png",     "enemy_manager"],
		["Octopus",          "spawn_octopus",          "res://assets/enemies/animaloctopus.png",   "enemy_manager"],
		["Spider",           "spawn_spider",           "res://assets/enemies/animalspider.png",    "enemy_manager"],
	],
	"Human": [
		["Shooter",            "spawn_shooter",            "res://assets/enemies/jetfighter.png",         "enemy_manager"],
		["Beamer",             "spawn_beamer",             "res://assets/enemies/beamer.png",             "enemy_manager"],
		["Missile launcher",   "spawn_missile_launcher",   "res://assets/enemies/missilelauncher.png",    "enemy_manager"],
		["Royal",              "spawn_royal",              "res://assets/enemies/royal.png",              "enemy_manager"],
		["Royal Fighter",      "spawn_royal_fighter",      "res://assets/enemies/royalfighter.png",       "enemy_manager"],
		["Royal Scout",        "spawn_royal_scout",        "res://assets/enemies/royalscout.png",         "enemy_manager"],
		["Royal Tanker",       "spawn_royal_tanker",       "res://assets/enemies/royaltanker.png",        "enemy_manager"],
		["Pirate Leader",      "spawn_pirate_leader",      "res://assets/enemies/pirateleader.png",       "enemy_manager"],
		["Pirate Ork",         "spawn_pirate_ork",         "res://assets/enemies/pirateork.png",          "enemy_manager"],
		["Pirate Spear",       "spawn_pirate_spear",       "res://assets/enemies/piratespear.png",        "enemy_manager"],
		["Pirate SpearShield", "spawn_pirate_spear_shield","res://assets/enemies/piratespearshield.png",  "enemy_manager"],
	],
	"Alien": [
		["Sentinels", "spawn_sentinels",    "res://assets/enemies/sentinel.png",     "enemy_manager"],
		["Cruiser",   "spawn_alien_cruiser","res://assets/enemies/aliencruiser.png", "enemy_manager"],
		["Crystal",   "spawn_alien_crystal","res://assets/enemies/aliencrystal.png", "enemy_manager"],
		["Egg",       "spawn_alien_egg",    "res://assets/enemies/alienegg.png",     "enemy_manager"],
		["Fighter",   "spawn_alien_fighter","res://assets/enemies/alienfighter.png", "enemy_manager"],
		["Plate",     "spawn_alien_plate",  "res://assets/enemies/alienplate.png",   "enemy_manager"],
		["Scout",     "spawn_alien_scout",  "res://assets/enemies/alienscout.png",   "enemy_manager"],
		["Tree",      "spawn_alien_tree",   "res://assets/enemies/alientree.png",    "enemy_manager"],
	],
	"Asteroid": [],
	"Boss": [
		["Elephant",   "elephant",   "res://assets/bosses/elephant/elephant.gif",     "boss"],
		["Chromeleon", "chromeleon", "res://assets/bosses/chromeleon/chromeleon.gif", "boss"],
		["Metalfly",   "metalfly",   "res://assets/bosses/metalfly/cocoon.gif",       "boss"],
		["Nautilus",   "nautilus",   "res://assets/bosses/nautilus/broken.gif",       "boss"],
	],
	"Other": [
		["Dummy", "spawn_dummy",     "res://assets/enemies/dummy.png",  "enemy_manager"],
		["Bomb",  "spawn_bomb_test", "res://assets/enemies/bomb.png",   "enemy_manager"],
	],
}

# Fixed info panel above HP bar
const INFO_POS   := Vector2(976.0, 10.0)
const INFO_SIZE  := Vector2(240.0, 260.0)
const INFO_IMG_W := 220.0
const INFO_IMG_H := 200.0
const INFO_PAD   := 10.0

var _active_tab  := "Animal"
var _tab_btns:  Dictionary = {}   # tab_name → Button
var _tab_pages: Dictionary = {}   # tab_name → Control
var _coord_grid: CanvasLayer = null
var _coord_btn:  Button      = null

var _info_panel: Panel       = null
var _info_img:   TextureRect = null
var _info_lbl:   Label       = null

## Called from main.gd AFTER add_child(), so size and parent are known.
func setup(rect: Rect2) -> void:
	var saved := _load_hud_rect("enemy_panel")
	if saved.size != Vector2.ZERO:
		rect = saved
	add_to_group("hud_editable")
	set_meta("hud_key", "enemy_panel")
	position = rect.position
	size     = rect.size
	_style()
	_build()
	_build_info_panel()
	_coord_grid = CoordGridScript.new()
	add_child(_coord_grid)

func get_hud_rect() -> Rect2:
	return Rect2(position, size)

func apply_hud_rect(rect: Rect2) -> void:
	var was_grid_on := is_instance_valid(_coord_grid) and _coord_grid.visible
	position = rect.position
	size     = rect.size
	_build()
	if was_grid_on and is_instance_valid(_coord_grid) and is_instance_valid(_coord_btn):
		_coord_grid.visible      = true
		_coord_btn.button_pressed = true
		_coord_btn.text          = "Coords ON"

static func _load_hud_rect(key: String) -> Rect2:
	var cfg := ConfigFile.new()
	if cfg.load("user://hud_layout.cfg") != OK:
		return Rect2()
	if not cfg.has_section_key("hud", key + "/pos"):
		return Rect2()
	return Rect2(
		cfg.get_value("hud", key + "/pos",  Vector2.ZERO) as Vector2,
		cfg.get_value("hud", key + "/size", Vector2.ZERO) as Vector2
	)

func _exit_tree() -> void:
	if is_instance_valid(_info_panel):
		_info_panel.queue_free()

func _style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	s.set_border_width_all(2)
	s.border_color = Color(0.3, 0.4, 0.6, 0.9)
	s.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", s)

func _build() -> void:
	_tab_btns.clear()
	_tab_pages.clear()
	for c in get_children():
		if c != _coord_grid:
			c.queue_free()

	# Title
	var title := Label.new()
	title.text = "ENEMIES"
	title.position = Vector2(0, 3)
	title.size = Vector2(size.x, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	add_child(title)

	# Tab buttons: 2 rows × 3 columns
	var btn_w := (size.x - 6.0) / 3.0
	for i in TAB_ORDER.size():
		var tab_name: String = TAB_ORDER[i]
		var col := i % 3
		var row := i / 3
		var btn := _mk_tab_btn(tab_name, tab_name == _active_tab)
		btn.position = Vector2(2.0 + col * btn_w, 23.0 + row * 24.0)
		btn.size     = Vector2(btn_w - 2.0, 22.0)
		btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		_tab_btns[tab_name] = btn
		add_child(btn)

	# Content pages (y=78 → CLEAR ALL at y=size.y-30)
	const CONTENT_Y := 78.0
	var content_h := size.y - CONTENT_Y - 32.0

	for tab_name in TAB_ORDER:
		var page := Control.new()
		page.position = Vector2(4.0, CONTENT_Y)
		page.size     = Vector2(size.x - 8.0, content_h)
		page.visible  = (tab_name == _active_tab)
		_tab_pages[tab_name] = page

		var entries: Array = TAB_ENEMIES.get(tab_name, [])
		if entries.is_empty():
			var lbl := Label.new()
			lbl.text = "—"
			lbl.position = Vector2(0, 10)
			lbl.size     = Vector2(page.size.x, 20)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65))
			page.add_child(lbl)
		else:
			var grid := GridContainer.new()
			grid.columns  = GRID_COLS
			grid.position = Vector2(0, 4)
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			page.add_child(grid)
			for e: Array in entries:
				grid.add_child(_mk_thumb(String(e[0]), String(e[1]), String(e[2]), String(e[3])))

		add_child(page)

	# Bottom row: [CLEAR ALL] [Coords OFF/ON]
	var half_w := (size.x - 10.0) * 0.5
	var clear := _mk_row_button("CLEAR ALL")
	clear.position = Vector2(4.0, size.y - 30.0)
	clear.size     = Vector2(half_w, 26.0)
	clear.pressed.connect(_clear)
	add_child(clear)

	_coord_btn = _mk_row_button("Coords OFF")
	_coord_btn.position      = Vector2(4.0 + half_w + 2.0, size.y - 30.0)
	_coord_btn.size          = Vector2(half_w, 26.0)
	_coord_btn.toggle_mode   = true
	_coord_btn.button_pressed = false
	_coord_btn.toggled.connect(_on_coords_toggled)
	add_child(_coord_btn)

# ── Tab switching ─────────────────────────────────────────────────────────────

func _on_tab_pressed(tab_name: String) -> void:
	_active_tab = tab_name
	for t: String in _tab_btns:
		(_tab_btns[t] as Button).button_pressed = (t == tab_name)
	for t: String in _tab_pages:
		(_tab_pages[t] as Control).visible = (t == tab_name)

func _on_coords_toggled(pressed: bool) -> void:
	if is_instance_valid(_coord_grid):
		_coord_grid.visible = pressed
	if is_instance_valid(_coord_btn):
		_coord_btn.text = "Coords ON" if pressed else "Coords OFF"

# ── Fixed info panel (sibling in the same canvas, above HP bar) ───────────────

func _build_info_panel() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.10, 0.95)
	s.set_border_width_all(2)
	s.border_color = Color(0.3, 0.45, 0.65, 0.9)
	s.set_corner_radius_all(8)

	_info_panel = Panel.new()
	_info_panel.position = INFO_POS
	_info_panel.size     = INFO_SIZE
	_info_panel.z_index  = 20
	_info_panel.visible  = false
	_info_panel.add_theme_stylebox_override("panel", s)

	_info_img = TextureRect.new()
	_info_img.position     = Vector2(INFO_PAD, INFO_PAD)
	_info_img.size         = Vector2(INFO_IMG_W, INFO_IMG_H)
	_info_img.stretch_mode = TextureRect.STRETCH_SCALE
	_info_img.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_info_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_info_img)

	_info_lbl = Label.new()
	_info_lbl.position             = Vector2(INFO_PAD, INFO_PAD + INFO_IMG_H + 6.0)
	_info_lbl.size                 = Vector2(INFO_IMG_W, 30.0)
	_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_info_lbl.add_theme_font_size_override("font_size", 12)
	_info_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_info_panel.add_child(_info_lbl)

	get_parent().add_child(_info_panel)

func _show_info(label_txt: String, icon_path: String) -> void:
	if not is_instance_valid(_info_panel):
		return
	var tex: Texture2D = null
	if icon_path != "":
		if icon_path.ends_with(".gif"):
			var gtex = GifLoader.load_gif(icon_path)
			if gtex != null:
				var frames: Array = gtex.get_meta("gif_frames") if gtex.has_meta("gif_frames") else []
				tex = (frames[0] as Texture2D) if not frames.is_empty() else (gtex as Texture2D)
		else:
			tex = load(icon_path) as Texture2D
	_info_img.texture = tex
	var img_w := INFO_IMG_W
	if tex != null and tex.get_height() > 0:
		img_w = INFO_IMG_H * float(tex.get_width()) / float(tex.get_height())
	img_w = minf(img_w, INFO_IMG_W)
	_info_img.size     = Vector2(img_w, INFO_IMG_H)
	_info_img.position = Vector2((INFO_SIZE.x - img_w) * 0.5, INFO_PAD)
	_info_lbl.text     = label_txt
	_info_panel.visible = true

func _hide_info() -> void:
	if is_instance_valid(_info_panel):
		_info_panel.visible = false

# ── Widgets ───────────────────────────────────────────────────────────────────

func _mk_tab_btn(tab_name: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text           = tab_name
	btn.toggle_mode    = true
	btn.button_pressed = active
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 9)
	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var st := StyleBoxFlat.new()
		st.bg_color = bg; st.set_border_width_all(1); st.border_color = bc
		st.set_corner_radius_all(4)
		return st
	btn.add_theme_stylebox_override("normal",  mk.call(Color(0.09, 0.11, 0.16, 0.9), Color(0.28, 0.36, 0.52, 0.7)))
	btn.add_theme_stylebox_override("hover",   mk.call(Color(0.13, 0.17, 0.24, 0.9), Color(0.45, 0.58, 0.78, 0.9)))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.10, 0.22, 0.13, 0.95), Color(0.28, 0.78, 0.42, 0.9)))
	return btn

func _mk_thumb(label_txt: String, spawn_key: String, icon_path: String, spawn_group: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = THUMB_SIZE
	btn.expand_icon = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon_path.ends_with(".gif"):
		var gtex = GifLoader.load_gif(icon_path)
		if gtex != null:
			var frames: Array = gtex.get_meta("gif_frames") if gtex.has_meta("gif_frames") else []
			btn.icon = (frames[0] as Texture2D) if not frames.is_empty() else (gtex as Texture2D)
	elif icon_path != "":
		var tex := load(icon_path) as Texture2D
		if tex != null:
			btn.icon = tex
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		var shade := 0.10
		if state == "hover":     shade = 0.16
		elif state == "pressed": shade = 0.07
		s.bg_color = Color(shade, shade + 0.03, shade + 0.08, 0.95)
		s.set_border_width_all(1)
		s.border_color = Color(0.35, 0.45, 0.65, 0.9)
		s.set_corner_radius_all(6)
		btn.add_theme_stylebox_override(state, s)
	btn.pressed.connect(_spawn.bind(spawn_key, spawn_group))
	btn.mouse_entered.connect(func(): _show_info(label_txt, icon_path))
	btn.mouse_exited.connect(_hide_info)
	return btn

func _mk_row_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		var shade := 0.10
		if state == "hover":     shade = 0.16
		elif state == "pressed": shade = 0.07
		s.bg_color = Color(shade, shade + 0.03, shade + 0.08, 0.95)
		s.set_border_width_all(1)
		s.border_color = Color(0.35, 0.45, 0.65, 0.9)
		s.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, s)
	return b

func _spawn(spawn_key: String, spawn_group: String) -> void:
	if spawn_group == "boss":
		var m := get_tree().get_first_node_in_group("boss_fight")
		if m != null and m.has_method("spawn_boss"):
			m.call("spawn_boss", spawn_key)
	else:
		var m := get_tree().get_first_node_in_group(spawn_group)
		if m != null and m.has_method(spawn_key):
			m.call(spawn_key)

func _clear() -> void:
	var m := get_tree().get_first_node_in_group("enemy_manager")
	if m != null and m.has_method("clear_enemies"):
		m.call("clear_enemies")
