extends Panel

## ENEMIES debug panel — sits where the old POWER CORE panel was. Lists every normal-enemy type as a
## clickable row; clicking a row spawns that enemy immediately via the EnemyManager (group
## "enemy_manager"). A CLEAR ALL row removes everything on screen. Built entirely in code, so it
## carries no scene dependencies.
##
## Adding a new enemy = add one line to ENEMIES (and a matching spawn_*() on enemy_manager.gd).

const FONT_PATH := "res://assets/fonts/Gameplay.ttf"

# [display label, EnemyManager method to call]. One row per enemy, top → bottom.
const ENEMIES := [
	["Dummy", "spawn_dummy"],
	["Diver", "spawn_diver"],
	["Shooter", "spawn_shooter"],
	["Sentinels", "spawn_sentinels"],
	["Bombing_wanderer", "spawn_bombing_wanderer"],
	["Bomb (test)", "spawn_bomb_test"],
	["Swarm", "spawn_swarm"],
	["Beamer", "spawn_beamer"],
	["Missile_launcher", "spawn_missile_launcher"],
]

var _font: FontFile

## Position/size the panel, then style + build. Called from main.gd AFTER add_child(), so size is
## known here (building in _ready would run before setup() with a zero size).
func setup(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	_font = load(FONT_PATH) as FontFile
	_style()
	_build()

func _style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	s.set_border_width_all(2)
	s.border_color = Color(0.3, 0.4, 0.6, 0.9)
	s.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", s)

func _build() -> void:
	for c in get_children():
		c.queue_free()

	var title := _mk_label("ENEMIES", 14)
	title.position = Vector2(0, 6)
	title.size = Vector2(size.x, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# Rows live inside a ScrollContainer so the list scrolls when it's taller than the panel (the enemy
	# count has outgrown the fixed height). Horizontal scrolling is off → rows stay full-width.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 30)
	scroll.size = Vector2(size.x - 12.0, size.y - 36.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)

	for e: Array in ENEMIES:
		var btn := _mk_row_button(String(e[0]))
		btn.pressed.connect(_spawn.bind(String(e[1])))
		vbox.add_child(btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)
	var clear := _mk_row_button("CLEAR ALL")
	clear.pressed.connect(_clear)
	vbox.add_child(clear)

func _spawn(method: String) -> void:
	var m := get_tree().get_first_node_in_group("enemy_manager")
	if m != null and m.has_method(method):
		m.call(method)

func _clear() -> void:
	var m := get_tree().get_first_node_in_group("enemy_manager")
	if m != null and m.has_method("clear_enemies"):
		m.clear_enemies()

# ── Widgets ─────────────────────────────────────────────────────────────────────
func _mk_label(txt: String, sz: int) -> Label:
	var l := Label.new()
	l.text = txt
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	return l

func _mk_row_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0.0, 34.0)   # height only; width fills the scroll container
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		var shade := 0.10
		if state == "hover": shade = 0.16
		elif state == "pressed": shade = 0.07
		s.bg_color = Color(shade, shade + 0.03, shade + 0.08, 0.95)
		s.set_border_width_all(1)
		s.border_color = Color(0.35, 0.45, 0.65, 0.9)
		s.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, s)
	return b
